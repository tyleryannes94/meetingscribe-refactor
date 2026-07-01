import Foundation
import VaultKit
import OSLog

/// "Organize my Tasks": an AI pass over the user's CURRENT tasks that proposes
/// concrete, one-click fixes — reschedule overdue items, fix priorities, and
/// group/tag loose tasks (optionally into a brand-new project). It NEVER mutates
/// anything itself: every suggestion is reviewed and applied (or dismissed) by
/// the user. Mirrors the Brain Dump planner's tool-loop shape but its tools only
/// record suggestions instead of writing through to the store.
///
/// Local-only: runs against the same Ollama chat client as everything else.
@MainActor
final class TaskOrganizer: ObservableObject {
    /// Shared instance so the review modal AND the Brain Dump recommendations
    /// section show the same (persisted) results — a run isn't tied to one sheet.
    static let shared = TaskOrganizer()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "TaskOrganizer")
    private let chatClient = OllamaChatClient()

    @Published private(set) var suggestions: [TaskSuggestion] = [] { didSet { persist() } }
    /// A run is in flight. With the two-phase design this is true only while the
    /// optional LLM grouping pass is still working — the instant deterministic
    /// suggestions are already published by then.
    @Published private(set) var isRunning = false
    /// The instant pass has published its results; the LLM is still looking for
    /// groups/tags in the background. Drives a slim inline "still looking…" hint
    /// instead of a blocking spinner.
    @Published private(set) var refining = false
    @Published var reasoning: String?
    @Published var error: String?

    /// True once a run has finished (so the UI can distinguish "no suggestions
    /// yet" from "analyzed, nothing to fix").
    @Published private(set) var didRun = false

    init() { loadPersisted() }

    func reset() {
        suggestions = []; reasoning = nil; error = nil; didRun = false; refining = false
    }

    // MARK: - Persistence (results survive modal close + app restart)

    private static var persistURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("task_organizer_suggestions.json")
    }

    private func persist() {
        // Keep pending + applied (so the UI shows what was done); drop dismissed.
        let keep = suggestions.filter { !$0.dismissed }
        guard let data = try? JSONEncoder().encode(keep) else { return }
        try? data.write(to: Self.persistURL, options: .atomic)
    }

    private func loadPersisted() {
        guard let data = try? Data(contentsOf: Self.persistURL),
              let loaded = try? JSONDecoder().decode([TaskSuggestion].self, from: data),
              !loaded.isEmpty else { return }
        suggestions = loaded
        didRun = true   // so opening the modal shows these instead of auto-re-running
    }

    func run(store: ActionItemStore) {
        guard !isRunning else { return }
        isRunning = true
        reset()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The store loads its items asynchronously at launch. If the organizer
            // is opened in that window it would analyze an empty set and report
            // "nothing to fix". Give the load up to ~3s to land first.
            var waited = 0
            while store.items.isEmpty && waited < 20 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                waited += 1
            }

            // PHASE 1 — instant, deterministic, no model. High-confidence fixes
            // (reschedule overdue, priority from cues, split, due-from-title,
            // theme grouping) render in under a second, model or no model.
            var all = Self.deterministicSuggestions(store: store)
            all = self.dropRejected(all)
            self.suggestions = Self.balanceWorkload(all, store: store)

            // PHASE 2 — the SMART pass. Reasons over the tasks that would benefit
            // most from a change (no due date, mis-prioritized, loose) with full
            // context — current priority/due/project/age and project deadlines —
            // and proposes concrete due dates, priorities, project assignments,
            // splits, and project deadlines. Single structured call, background,
            // bounded; a failure never erases the instant results.
            let candidates = Self.candidateTasks(store: store, given: self.suggestions)
            if candidates.count >= 2 {
                self.refining = true
                do {
                    let extra = try await self.smartPass(candidates: candidates, store: store)
                    let merged = self.mergeDeduped(self.suggestions, adding: self.dropRejected(extra))
                    self.suggestions = Self.balanceWorkload(merged, store: store)
                } catch {
                    if self.suggestions.isEmpty { self.error = Self.friendlyError(error) }
                    self.log.info("organizer smart pass skipped: \(error.localizedDescription, privacy: .public)")
                }
                self.refining = false
            }
            self.isRunning = false
            self.didRun = true
        }
    }

    /// Tasks worth spending a model call on: anything the deterministic pass
    /// didn't already fully handle that would benefit from a due date, a priority
    /// fix, or a project. Prioritized so the (capped) list leads with the tasks
    /// where a change matters most: no due date, then loose, then the rest.
    private static func candidateTasks(store: ActionItemStore,
                                       given suggestions: [TaskSuggestion]) -> [ActionItem] {
        // Tasks already given a concrete single-task fix this run — don't ask the
        // model to re-decide them (avoids churn + duplicate proposals).
        var handled = Set<String>()
        for s in suggestions {
            switch s.kind {
            case let .assignProject(ids, _, _, _): handled.formUnion(ids)
            case let .addTag(ids, _, _):           handled.formUnion(ids)
            case let .reschedule(id, _, _):        handled.insert(id)
            case let .split(id, _, _):             handled.insert(id)
            default: break
            }
        }
        let open = store.items.filter {
            $0.deletedAt == nil && $0.status != .completed && !handled.contains($0.id)
        }
        // Rank: no due date first (highest value), then loose, then the rest.
        func score(_ t: ActionItem) -> Int {
            var s = 0
            if t.dueDate == nil { s += 4 }
            if t.projectID == nil { s += 2 }
            if t.priority == .high || t.priority == .urgent { s += 1 }
            return s
        }
        return open.filter { score($0) > 0 }
            .sorted { score($0) > score($1) }
            .prefix(20).map { $0 }
    }

    /// PHASE 2: one structured-JSON call proposing due dates / priorities /
    /// projects / splits / project deadlines.
    private func smartPass(candidates: [ActionItem], store: ActionItemStore) async throws -> [TaskSuggestion] {
        // Generous ceiling: a local 7B model generating dates + reasons for ~15
        // tasks legitimately takes 20–40s. This runs in the background behind the
        // instant deterministic results, so a longer wait is fine — and a too-tight
        // 25s cap was silently timing the whole smart pass out (surfaced as a
        // bogus "Ollama isn't running").
        let raw = try await chatClient.oneShotJSON(
            system: Self.smartSystemPrompt(store: store),
            user: Self.smartInventory(candidates, store: store),
            timeoutSeconds: 90,
            maxTokens: 1600,
            temperature: 0.35
        )
        let parsed = Self.parseSmart(raw, candidates: candidates, store: store)
        reasoning = parsed.summary
        return parsed.suggestions
    }

    /// Merge model suggestions into the existing set, skipping any that duplicate
    /// a task+kind already proposed (deterministic wins).
    private func mergeDeduped(_ base: [TaskSuggestion], adding extra: [TaskSuggestion]) -> [TaskSuggestion] {
        var seen = Set(base.map { $0.rejectionSignature })
        var out = base
        for s in extra where !seen.contains(s.rejectionSignature) {
            seen.insert(s.rejectionSignature)
            out.append(s)
        }
        return out
    }

    // MARK: - Apply / dismiss (user signoff)

    /// Toggle whether one task inside a multi-task suggestion is included. Lets
    /// the user uncheck individual tasks in a "tag N tasks / move N tasks" card
    /// before applying, without losing the rest of the recommendation list.
    func toggleTask(_ taskID: String, in suggestion: TaskSuggestion) {
        guard let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        if suggestions[idx].deselectedTaskIDs.contains(taskID) {
            suggestions[idx].deselectedTaskIDs.remove(taskID)
        } else {
            suggestions[idx].deselectedTaskIDs.insert(taskID)
        }
    }

    /// Apply one reviewed suggestion to the store and mark it applied. Multi-task
    /// kinds act only on the still-checked tasks (`activeTaskIDs`).
    func apply(_ suggestion: TaskSuggestion, store: ActionItemStore) {
        guard let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }),
              !suggestions[idx].applied else { return }
        let active = suggestions[idx].activeTaskIDs
        switch suggestion.kind {
        case let .reschedule(taskID, _, newDate):
            store.setDueDate(taskID, dueDate: newDate)
        case let .reprioritize(taskID, _, priority):
            store.setPriority(taskID, priority: priority)
        case let .setProjectDeadline(projectID, _, date):
            store.setProjectTargetDate(projectID, date)
        case let .assignProject(_, _, projectName, existingID):
            guard !active.isEmpty else { return }
            let pid = existingID ?? store.createProject(name: projectName).id
            for tid in active { store.setProject(tid, projectID: pid) }
        case let .addTag(_, _, tag):
            guard !active.isEmpty else { return }
            let label = store.labels.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }
                ?? store.createLabel(name: tag)
            for tid in active where !(store.items.first { $0.id == tid }?.labelIDs?.contains(label.id) ?? false) {
                store.toggleLabel(tid, labelID: label.id)
            }
        case let .split(taskID, _, parts):
            for p in parts { store.addSubtask(taskID, title: p) }
        }
        suggestions[idx].applied = true
    }

    func applyAll(store: ActionItemStore) {
        for s in suggestions where !s.applied && !s.dismissed { apply(s, store: store) }
    }

    func dismiss(_ suggestion: TaskSuggestion) {
        guard let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        suggestions[idx].dismissed = true
        // Remember it so a future run doesn't re-propose the exact same change —
        // a top annoyance of these features is re-suggesting what you rejected.
        Self.rememberRejection(suggestion.rejectionSignature)
    }

    // MARK: - Rejection memory (don't re-suggest what the user dismissed)

    private static let rejectionsKey = "taskOrganizer.rejectedSignatures"

    private static func rejectedSignatures() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: rejectionsKey) ?? [])
    }

    private static func rememberRejection(_ sig: String) {
        var set = rejectedSignatures()
        set.insert(sig)
        // Cap so it can't grow unbounded across months of use.
        UserDefaults.standard.set(Array(set.suffix(400)), forKey: rejectionsKey)
    }

    private func dropRejected(_ suggestions: [TaskSuggestion]) -> [TaskSuggestion] {
        let rejected = Self.rejectedSignatures()
        return suggestions.filter { !rejected.contains($0.rejectionSignature) }
    }

    // MARK: - Phase 1: instant deterministic suggestions (no model)

    /// Compute every high-confidence fix in pure Swift — no LLM, no network — so
    /// the whole set renders instantly. Covers reschedule, priority, splitting
    /// compound tasks, inferring a due date from the title, and theme-based
    /// tagging/grouping (both per-task and across tasks that share a theme).
    static func deterministicSuggestions(store: ActionItemStore) -> [TaskSuggestion] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let open = store.items.filter { $0.deletedAt == nil && $0.status != .completed }
        var out: [TaskSuggestion] = []

        // 1) Overdue → reschedule. Urgent/high land today; the rest spread across
        //    the next few weekdays so we don't pile it all on one day.
        let overdue = open
            .filter { if let d = $0.dueDate { return cal.startOfDay(for: d) < today } else { return false } }
            .sorted { rank($0.priority) > rank($1.priority) }
        var spread = 0
        for t in overdue {
            let target: Date
            if t.priority == .urgent || t.priority == .high {
                target = nextWeekday(onOrAfter: today)
            } else {
                target = nextWeekday(onOrAfter: cal.date(byAdding: .day, value: 1 + spread / 3, to: today) ?? today)
                spread += 1
            }
            out.append(.init(kind: .reschedule(taskID: t.id, taskTitle: t.title, newDate: target),
                             reason: "Overdue\(dueAgo(t.dueDate, cal: cal))"))
        }

        // 2) Priority from title cues — conservative: only upgrade when the cue
        //    clearly outranks the current priority, or flag an explicit
        //    "someday/eventually" task as low.
        for t in open {
            guard let (p, cue) = inferredPriority(from: t.title) else { continue }
            let isUpgrade = rank(p) > rank(t.priority)
            let isSomeday = p == .low && (t.priority == .medium || t.priority == .high)
            guard isUpgrade || isSomeday, p != t.priority else { continue }
            out.append(.init(kind: .reprioritize(taskID: t.id, taskTitle: t.title, priority: p),
                             reason: "“\(cue)” in the title → \(p.label) priority"))
        }

        // 3) Split compound tasks ("do X and Y, then Z") into subtasks.
        for t in open {
            guard let parts = splitParts(t.title), parts.count >= 2 else { continue }
            out.append(.init(kind: .split(taskID: t.id, taskTitle: t.title, parts: parts),
                             reason: "Subtasks: " + parts.joined(separator: " · ")))
        }

        // 4) Due date from a date word in the title, for tasks with none set.
        for t in open where t.dueDate == nil {
            guard let (date, word) = inferredDueDate(from: t.title, today: today, cal: cal) else { continue }
            out.append(.init(kind: .reschedule(taskID: t.id, taskTitle: t.title, newDate: date),
                             reason: "“\(word)” in the title → give it a due date"))
        }

        // 5) Theme tag/group over loose (project-less) tasks. Tasks sharing a
        //    theme are grouped into a matching project (if one exists) or a
        //    shared tag; a lone themed task gets an individual tag suggestion.
        let loose = open.filter { $0.projectID == nil }
        var byTheme: [String: [ActionItem]] = [:]
        for t in loose { if let th = TaskAutoTagger.theme(for: t.title) { byTheme[th, default: []].append(t) } }
        for (tag, tasks) in byTheme.sorted(by: { $0.value.count > $1.value.count }) {
            let need = tasks.filter { t in
                !(t.labelIDs ?? []).contains { store.label(id: $0)?.name.caseInsensitiveCompare(tag) == .orderedSame }
            }
            guard !need.isEmpty else { continue }
            if need.count >= 2 {
                if let proj = store.projects.first(where: {
                    $0.status != .archived && $0.name.range(of: tag, options: .caseInsensitive) != nil
                }) {
                    out.append(.init(kind: .assignProject(taskIDs: need.map { $0.id }, taskTitles: need.map { $0.title },
                                                          projectName: proj.name, existingProjectID: proj.id),
                                     reason: "\(need.count) loose tasks about \(tag)"))
                } else {
                    out.append(.init(kind: .addTag(taskIDs: need.map { $0.id }, taskTitles: need.map { $0.title }, tag: tag),
                                     reason: "\(need.count) tasks share the “\(tag)” theme"))
                }
            } else if let t = need.first, (t.labelIDs ?? []).isEmpty {
                out.append(.init(kind: .addTag(taskIDs: [t.id], taskTitles: [t.title], tag: tag),
                                 reason: "“\(tag)” theme in the title"))
            }
        }

        // Keep the review list focused.
        return Array(out.prefix(24))
    }

    private static func rank(_ p: ActionItem.Priority) -> Int {
        switch p { case .low: return 0; case .medium: return 1; case .high: return 2; case .urgent: return 3 }
    }

    // MARK: Split detection

    /// Split a compound task title into parts when it clearly describes several
    /// actions. Conservative: strong sequence/list separators trigger on a
    /// 5-word minimum; a plain " and " needs a longer (9+ word) title to avoid
    /// false positives like "research and development".
    static func splitParts(_ title: String) -> [String]? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let wordCount = trimmed.split(separator: " ").count
        guard wordCount >= 5 else { return nil }
        let lower = trimmed.lowercased()
        let strong = [" and then ", " then ", "; ", " & "]
        let weak   = [", and ", ", ", " and "]
        var chosen: String?
        for s in strong where lower.contains(s) { chosen = s; break }
        // A plain " and " / ", and " is the easiest to over-trigger on compound
        // noun phrases ("quality and clarity"), so it needs a clearly long task.
        if chosen == nil, wordCount >= 10 { for s in weak where lower.contains(s) { chosen = s; break } }
        guard let sep = chosen else { return nil }
        let parts = splitCaseInsensitive(trimmed, on: sep)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,;&")) }
            .filter { $0.split(separator: " ").count >= 2 }
        guard (2...5).contains(parts.count) else { return nil }
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    private static func splitCaseInsensitive(_ s: String, on sep: String) -> [String] {
        var result: [String] = []
        var rest = Substring(s)
        while let r = rest.range(of: sep, options: .caseInsensitive) {
            result.append(String(rest[rest.startIndex..<r.lowerBound]))
            rest = rest[r.upperBound...]
        }
        result.append(String(rest))
        return result
    }

    // MARK: Due-date inference

    private static func inferredDueDate(from title: String, today: Date, cal: Calendar) -> (Date, String)? {
        let t = " " + title.lowercased() + " "
        if t.contains(" eod ")      { return (today, "EOD") }
        if t.contains(" today ") || t.contains(" tonight ") { return (today, "today") }
        if t.contains(" tomorrow ") { return (cal.date(byAdding: .day, value: 1, to: today) ?? today, "tomorrow") }
        let weekdays: [(String, Int)] = [("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
                                         ("thursday", 5), ("friday", 6), ("saturday", 7)]
        for (name, wd) in weekdays where t.contains(" \(name) ") {
            return (nextOccurrence(ofWeekday: wd, after: today, cal: cal), name.capitalized)
        }
        if t.contains(" next week ") {
            let wk = cal.date(byAdding: .day, value: 7, to: today) ?? today
            return (nextOccurrence(ofWeekday: 2, after: wk, cal: cal), "next week")
        }
        if t.contains(" this week ") {
            return (nextWeekday(onOrAfter: cal.date(byAdding: .day, value: 2, to: today) ?? today), "this week")
        }
        return nil
    }

    private static func nextOccurrence(ofWeekday wd: Int, after day: Date, cal: Calendar) -> Date {
        var d = cal.date(byAdding: .day, value: 1, to: day) ?? day
        for _ in 0..<8 {
            if cal.component(.weekday, from: d) == wd { return cal.startOfDay(for: d) }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: day)
    }

    // Theme detection is shared with the auto-tagger — see `TaskAutoTagger`.

    /// The given day if it's a weekday, otherwise the following Monday.
    private static func nextWeekday(onOrAfter day: Date) -> Date {
        let cal = Calendar.current
        var d = cal.startOfDay(for: day)
        while cal.isDateInWeekend(d) { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }

    private static func dueAgo(_ due: Date?, cal: Calendar) -> String {
        guard let due else { return "" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: due),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return "" }
        if days == 1 { return " by 1 day" }
        if days < 14 { return " by \(days) days" }
        return " by \(days / 7) weeks"
    }

    /// Map clear urgency words in a title to a priority. Returns the matched cue
    /// word too, for the user-facing reason. Conservative word lists only.
    private static func inferredPriority(from title: String) -> (ActionItem.Priority, String)? {
        let t = " " + title.lowercased() + " "
        let urgent = ["urgent", "asap", "immediately", "critical", "emergency", "blocker", "p0"]
        let high   = ["important", "high priority", "high-priority", "deadline", "must ", "p1"]
        let low    = ["someday", "eventually", "nice to have", "nice-to-have", "low priority", "whenever", "p3"]
        for w in urgent where t.contains(w) { return (.urgent, w.trimmingCharacters(in: .whitespaces)) }
        for w in high   where t.contains(w) { return (.high,   w.trimmingCharacters(in: .whitespaces)) }
        for w in low    where t.contains(w) { return (.low,    w.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    // MARK: - Phase 2: smart prompt + JSON parse

    private static func smartSystemPrompt(store: ActionItemStore) -> String {
        // Kept deliberately COMPACT and numbered. A verbose, multi-section prompt
        // makes the local 7B model emit malformed / looping JSON and skip tasks;
        // this tight shape reliably dates every task with valid JSON.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let dfFull = DateFormatter(); dfFull.dateFormat = "yyyy-MM-dd (EEEE)"
        let dfISO = DateFormatter(); dfISO.dateFormat = "yyyy-MM-dd"

        let projNames = store.projects.filter { $0.status != .archived }.map { $0.name }
        let projList = projNames.isEmpty ? "(none)" : projNames.joined(separator: ", ")
        let dateless = store.projects
            .filter { $0.status != .archived && $0.targetDate == nil && store.openCount(forProject: $0.id) > 0 }
            .map { $0.name }
        let tags = store.labels.map { $0.name }
        let tagList = tags.isEmpty ? "(none)" : tags.joined(separator: ", ")
        return """
        You are a task planner. Today is \(dfFull.string(from: today)). Do all of the below and reply with ONE JSON object only, no prose.
        1) For EVERY task, set "due" as YYYY-MM-DD — a weekday, not before \(dfISO.string(from: tomorrow)). Do not skip any task. urgent/high → next 1–3 days; medium → this week or next; low → 1–2 weeks. Vary the days; don't put them all on one date.
        2) Set "priority" (low/medium/high/urgent) only when the current one is clearly wrong — differentiate, don't make everything high.
        3) Set "project" to an EXISTING project name only if the task clearly fits. Projects: \(projList).
        4) In "splits", give a task id + 2–5 subtask titles only if it's really several steps.
        5) In "projects", set a "target_date" for a project that has open work but no deadline\(dateless.isEmpty ? "" : " (e.g. \(dateless.joined(separator: ", ")))").
        Existing tags: \(tagList). Refer to each task by its handle (t1, t2, …). Shape:
        {"tasks":[{"id":"t1","due":"YYYY-MM-DD","priority":"high","project":"Name","reason":"why"}],"splits":[{"id":"t2","parts":["Step a","Step b"],"reason":"why"}],"projects":[{"name":"Name","target_date":"YYYY-MM-DD","reason":"why"}],"summary":"one sentence"}
        """
    }

    private static func smartInventory(_ tasks: [ActionItem], store: ActionItemStore) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        // Short positional handles (t1, t2, …) instead of 36-char UUIDs: small
        // models copy those reliably, and it keeps the prompt short.
        var lines = ["TASKS (handle · title [priority, due, project, age]):"]
        for (i, t) in tasks.enumerated() {
            let due = t.dueDate.map { df.string(from: $0) } ?? "none"
            let proj = t.projectID.flatMap { store.project(id: $0)?.name } ?? "none"
            let age = cal.dateComponents([.day], from: cal.startOfDay(for: t.createdAt), to: today).day ?? 0
            lines.append("- t\(i + 1) · \(t.title) [pri=\(t.priority.rawValue), due=\(due), project=\(proj), age=\(age)d]")
        }
        return lines.joined(separator: "\n")
    }

    /// Parse the smart reply into suggestions. Tolerant: validates ids/dates,
    /// only emits a change when it actually differs from the task's current
    /// value, and never overrides a good future due date the user already set
    /// (only fills empty or fixes overdue dates).
    private static func parseSmart(_ raw: String, candidates: [ActionItem], store: ActionItemStore)
        -> (suggestions: [TaskSuggestion], summary: String?) {
        guard let data = raw.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return ([], nil) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Resolve a model reference back to a real task: a positional handle
        // (t1, t2, …) or, defensively, a full task id.
        let byHandle = Dictionary(uniqueKeysWithValues:
            candidates.enumerated().map { ("t\($0.offset + 1)", $0.element) })
        func resolve(_ any: Any?) -> ActionItem? {
            guard let ref = (any as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
            if let t = byHandle[ref.lowercased()] { return t }
            return store.items.first { $0.id == ref && $0.deletedAt == nil }
        }
        var out: [TaskSuggestion] = []

        for entry in (root["tasks"] as? [[String: Any]] ?? []).prefix(24) {
            guard let task = resolve(entry["id"]) else { continue }
            let id = task.id
            let reason = (entry["reason"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""

            // Due date — only fill an empty date or fix an overdue one.
            if let raw = entry["due"] as? String, let date = sanitizeDueDate(parseDate(raw), cal: cal) {
                let isOverdue = task.dueDate.map { cal.startOfDay(for: $0) < today } ?? false
                if task.dueDate == nil || isOverdue,
                   task.dueDate.map({ cal.startOfDay(for: $0) }) != date {
                    out.append(.init(kind: .reschedule(taskID: id, taskTitle: task.title, newDate: date),
                                     reason: reason.isEmpty ? "Give it a due date" : reason))
                }
            }
            // Priority — only when it changes.
            if let pRaw = (entry["priority"] as? String)?.lowercased(),
               let p = ActionItem.Priority(rawValue: pRaw), p != task.priority {
                out.append(.init(kind: .reprioritize(taskID: id, taskTitle: task.title, priority: p),
                                 reason: reason.isEmpty ? "\(p.label) priority fits better" : reason))
            }
            // Project — only for loose tasks, into an existing project.
            if task.projectID == nil,
               let pn = (entry["project"] as? String)?.trimmingCharacters(in: .whitespaces), !pn.isEmpty,
               let proj = store.projects.first(where: { $0.name.caseInsensitiveCompare(pn) == .orderedSame }) {
                out.append(.init(kind: .assignProject(taskIDs: [id], taskTitles: [task.title],
                                                      projectName: proj.name, existingProjectID: proj.id),
                                 reason: reason.isEmpty ? "Fits “\(proj.name)”" : reason))
            }
        }

        for s in (root["splits"] as? [[String: Any]] ?? []).prefix(6) {
            guard let task = resolve(s["id"]),
                  (task.subtasks ?? []).isEmpty,
                  let partsAny = s["parts"] as? [Any] else { continue }
            let parts = partsAny.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard (2...5).contains(parts.count) else { continue }
            out.append(.init(kind: .split(taskID: task.id, taskTitle: task.title, parts: parts),
                             reason: (s["reason"] as? String) ?? "Break into steps"))
        }

        for p in (root["projects"] as? [[String: Any]] ?? []).prefix(5) {
            guard let name = (p["name"] as? String)?.trimmingCharacters(in: .whitespaces),
                  let proj = store.projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  proj.targetDate == nil,
                  let date = sanitizeDueDate(parseDate((p["target_date"] as? String) ?? ""), cal: cal) else { continue }
            out.append(.init(kind: .setProjectDeadline(projectID: proj.id, projectName: proj.name, date: date),
                             reason: (p["reason"] as? String) ?? "Give the project a deadline"))
        }

        let summary = (root["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out, (summary?.isEmpty == false) ? summary : nil)
    }

    // MARK: - Workload balancing + date helpers

    /// Spread reschedule suggestions so no single day gets overloaded. Seeds the
    /// per-day tally with existing due tasks (minus the ones being rescheduled),
    /// then bumps any proposed date whose day is already full to the next weekday
    /// with room. This is the deterministic guarantee that the plan is realistic,
    /// independent of what the model proposed.
    private static func balanceWorkload(_ suggestions: [TaskSuggestion], store: ActionItemStore) -> [TaskSuggestion] {
        let cal = Calendar.current
        let cap = 4  // max tasks landing on any one day
        // Seed with existing due dates, excluding tasks we're about to move.
        let moving = Set(suggestions.compactMap { s -> String? in
            if case let .reschedule(id, _, _) = s.kind { return id } else { return nil }
        })
        var perDay: [Date: Int] = [:]
        for t in store.items where t.deletedAt == nil && t.status != .completed && !moving.contains(t.id) {
            if let d = t.dueDate { perDay[cal.startOfDay(for: d), default: 0] += 1 }
        }
        // Apply in date order so earlier dates fill first (keeps urgency).
        let order = suggestions.enumerated().sorted { a, b in
            let da = rescheduleDate(a.element) ?? .distantFuture
            let db = rescheduleDate(b.element) ?? .distantFuture
            return da < db
        }
        var result = suggestions
        for (idx, s) in order {
            guard case let .reschedule(id, title, date) = s.kind else { continue }
            var day = cal.startOfDay(for: date)
            var guardN = 0
            while (perDay[day] ?? 0) >= cap && guardN < 30 {
                day = nextWeekday(onOrAfter: cal.date(byAdding: .day, value: 1, to: day) ?? day)
                guardN += 1
            }
            perDay[day, default: 0] += 1
            if day != cal.startOfDay(for: date) {
                result[idx].kind = .reschedule(taskID: id, taskTitle: title, newDate: day)
            }
        }
        return result
    }

    private static func rescheduleDate(_ s: TaskSuggestion) -> Date? {
        if case let .reschedule(_, _, d) = s.kind { return d }
        return nil
    }

    /// Parse a "YYYY-MM-DD" model date into a local start-of-day Date.
    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s.trimmingCharacters(in: .whitespaces)).map { Calendar.current.startOfDay(for: $0) }
    }

    /// Clamp a proposed date to a sane weekday no earlier than tomorrow.
    private static func sanitizeDueDate(_ date: Date?, cal: Calendar) -> Date? {
        guard let date else { return nil }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? date
        let floored = max(cal.startOfDay(for: date), tomorrow)
        return nextWeekday(onOrAfter: floored)
    }

    private static func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("not reachable") || msg.contains("notReachable") {
            return "The on-device summary engine isn't running. Open Settings → Integrations to start it, then retry."
        }
        return msg
    }
}
