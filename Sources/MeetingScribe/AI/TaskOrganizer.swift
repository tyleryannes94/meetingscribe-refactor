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
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "TaskOrganizer")
    private let chatClient = OllamaChatClient()

    @Published private(set) var suggestions: [TaskSuggestion] = []
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

    func reset() {
        suggestions = []; reasoning = nil; error = nil; didRun = false; refining = false
    }

    func run(store: ActionItemStore) {
        guard !isRunning else { return }
        isRunning = true
        reset()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // PHASE 1 — instant, deterministic, no model. Reschedule, priority,
            // split, due-dates, and theme tag/grouping are all computed in pure
            // Swift, so the full set of suggestions is on screen in well under a
            // second — even if the local model is slow or offline.
            self.suggestions = Self.deterministicSuggestions(store: store)

            // PHASE 2 — only when several loose tasks remain that the
            // deterministic themer COULDN'T cluster is the model worth running.
            // It's a single structured call, hard-capped at 12s, in the
            // background. A failure/timeout NEVER erases the instant results.
            let leftover = Self.unclusteredLooseTasks(store: store, given: self.suggestions)
            if leftover.count >= 4 {
                self.refining = true
                do {
                    let extra = try await self.refineWithModel(tasks: leftover, store: store)
                    self.suggestions.append(contentsOf: extra)
                } catch {
                    if self.suggestions.isEmpty { self.error = Self.friendlyError(error) }
                    self.log.info("organizer LLM phase skipped: \(error.localizedDescription, privacy: .public)")
                }
                self.refining = false
            }
            self.isRunning = false
            self.didRun = true
        }
    }

    /// Loose (project-less) tasks the deterministic pass did NOT already fold
    /// into a group or tag — the only ones worth spending a model call on.
    private static func unclusteredLooseTasks(store: ActionItemStore,
                                              given suggestions: [TaskSuggestion]) -> [ActionItem] {
        var handled = Set<String>()
        for s in suggestions {
            switch s.kind {
            case let .assignProject(ids, _, _, _): handled.formUnion(ids)
            case let .addTag(ids, _, _):           handled.formUnion(ids)
            default: break
            }
        }
        return store.items
            .filter { $0.deletedAt == nil && $0.status != .completed
                && $0.projectID == nil && !handled.contains($0.id) }
            .prefix(18).map { $0 }
    }

    /// PHASE 2: one structured-JSON call to group whatever the deterministic
    /// themer couldn't. Hard 12s ceiling + output-token cap so it can never be
    /// the multi-minute bottleneck it used to be.
    private func refineWithModel(tasks: [ActionItem], store: ActionItemStore) async throws -> [TaskSuggestion] {
        guard tasks.count >= 2 else { return [] }
        let raw = try await chatClient.oneShotJSON(
            system: Self.groupingSystemPrompt(store: store),
            user: Self.groupingInventory(tasks, store: store),
            timeoutSeconds: 12,
            maxTokens: 500
        )
        let parsed = Self.parseGrouping(raw, store: store)
        reasoning = parsed.summary
        return parsed.suggestions
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
        guard !active.isEmpty else { return }
        switch suggestion.kind {
        case let .reschedule(taskID, _, newDate):
            store.setDueDate(taskID, dueDate: newDate)
        case let .reprioritize(taskID, _, priority):
            store.setPriority(taskID, priority: priority)
        case let .assignProject(_, _, projectName, existingID):
            let pid = existingID ?? store.createProject(name: projectName).id
            for tid in active { store.setProject(tid, projectID: pid) }
        case let .addTag(_, _, tag):
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
        for t in loose { if let th = detectTheme(t.title) { byTheme[th, default: []].append(t) } }
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

    // MARK: Theme detection

    private struct Theme { let tag: String; let keywords: [String] }
    private static let themes: [Theme] = [
        .init(tag: "email", keywords: ["email", "reply", "respond to", "follow up", "follow-up", "inbox"]),
        .init(tag: "docs", keywords: ["document", "documentation", "write up", "write-up", "readme", "spec ", "notes for"]),
        .init(tag: "bug", keywords: ["bug", "fix ", "error", "crash", "broken", "regression", "hotfix"]),
        .init(tag: "meeting", keywords: ["meeting", "schedule a", "sync ", "standup", "stand-up", "1:1", "agenda"]),
        .init(tag: "review", keywords: ["review", "pull request", " pr ", "feedback", "sign off", "sign-off", "approve"]),
        .init(tag: "design", keywords: ["design", "mockup", "wireframe", "figma", "prototype"]),
        .init(tag: "analytics", keywords: ["analytics", "metrics", "dashboard", "benchmark", "tracking", "report on"]),
        .init(tag: "research", keywords: ["research", "investigate", "evaluate", "explore", "spike", "compare"]),
        .init(tag: "outreach", keywords: ["reach out", "outreach", "contact ", "intro to", "ping "]),
        .init(tag: "scoping", keywords: ["scope", "scoping", "planning", "estimate", "roadmap"]),
    ]
    private static func detectTheme(_ title: String) -> String? {
        let t = " " + title.lowercased() + " "
        for theme in themes { for k in theme.keywords where t.contains(k) { return theme.tag } }
        return nil
    }

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

    // MARK: - Phase 2: grouping/tagging prompt + JSON parse

    private static func groupingSystemPrompt(store: ActionItemStore) -> String {
        let projects = store.projects.filter { $0.status != .archived }.map { $0.name }
        let projectList = projects.isEmpty ? "(none yet)" : projects.joined(separator: ", ")
        let tags = store.labels.map { $0.name }
        let tagList = tags.isEmpty ? "(none yet)" : tags.joined(separator: ", ")
        return """
        You organize \(AppSettings.shared.userName)'s loose tasks. You are given tasks that have NO project. Group ones that clearly belong together and suggest a shared tag for obvious themes. Prefer existing names.

        Existing projects: \(projectList)
        Existing tags: \(tagList)

        Reply with ONLY this JSON (no prose):
        {
          "groups": [{ "task_ids": ["id1","id2"], "project": "Short Name", "reason": "one clause" }],
          "tags":   [{ "task_ids": ["id1","id2"], "tag": "shorttag", "reason": "one clause" }],
          "summary": "one short sentence"
        }
        Rules: only group 2+ tasks that genuinely belong together; skip tasks that don't fit anywhere; at most 5 groups and 5 tags; use exact ids from the list; "project"/"tag" reuse an existing name when one fits.
        """
    }

    private static func groupingInventory(_ tasks: [ActionItem], store: ActionItemStore) -> String {
        var lines = ["LOOSE TASKS (id · title):"]
        for t in tasks { lines.append("- (\(t.id)) \(t.title)") }
        return lines.joined(separator: "\n")
    }

    /// Parse the structured grouping reply into suggestions. Tolerant: ignores
    /// malformed entries, validates every id against the store, and drops groups
    /// of fewer than two real tasks.
    private static func parseGrouping(_ raw: String, store: ActionItemStore)
        -> (suggestions: [TaskSuggestion], summary: String?) {
        guard let data = raw.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return ([], nil) }
        func realIDs(_ any: Any?) -> ([String], [String]) {
            guard let arr = any as? [Any] else { return ([], []) }
            let ids = arr.compactMap { $0 as? String }
                .filter { id in store.items.contains { $0.id == id && $0.deletedAt == nil } }
            let titles = ids.compactMap { id in store.items.first { $0.id == id }?.title }
            return (ids, titles)
        }
        var out: [TaskSuggestion] = []
        for g in (root["groups"] as? [[String: Any]] ?? []).prefix(5) {
            let (ids, titles) = realIDs(g["task_ids"])
            guard ids.count >= 2,
                  let name = (g["project"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { continue }
            let existing = store.projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            out.append(.init(kind: .assignProject(taskIDs: ids, taskTitles: titles,
                                                  projectName: existing?.name ?? name,
                                                  existingProjectID: existing?.id),
                             reason: (g["reason"] as? String) ?? ""))
        }
        for tg in (root["tags"] as? [[String: Any]] ?? []).prefix(5) {
            let (ids, titles) = realIDs(tg["task_ids"])
            guard ids.count >= 2,
                  let tag = (tg["tag"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !tag.isEmpty else { continue }
            out.append(.init(kind: .addTag(taskIDs: ids, taskTitles: titles, tag: tag),
                             reason: (tg["reason"] as? String) ?? ""))
        }
        let summary = (root["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out, (summary?.isEmpty == false) ? summary : nil)
    }

    private static func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("not reachable") || msg.contains("notReachable") {
            return "The on-device summary engine isn't running. Open Settings → Integrations to start it, then retry."
        }
        return msg
    }
}
