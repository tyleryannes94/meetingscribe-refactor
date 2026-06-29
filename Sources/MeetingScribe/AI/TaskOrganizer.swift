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
            // PHASE 1 — instant, deterministic, no model. Publish immediately so
            // the user always sees value in well under a second, even if the
            // local model is slow or unavailable.
            self.suggestions = Self.deterministicSuggestions(store: store)

            // PHASE 2 — optional LLM grouping/tagging over ungrouped tasks. One
            // structured call, short timeout. A failure here must NEVER erase the
            // Phase-1 results — it just means no AI groups this round.
            self.refining = true
            do {
                let extra = try await self.refineWithModel(store: store)
                self.suggestions.append(contentsOf: extra)
            } catch {
                // Only surface an error if we have nothing at all to show.
                if self.suggestions.isEmpty { self.error = Self.friendlyError(error) }
                self.log.info("organizer LLM phase skipped: \(error.localizedDescription, privacy: .public)")
            }
            self.refining = false
            self.isRunning = false
            self.didRun = true
        }
    }

    /// PHASE 2: ask the local model — in ONE structured-JSON call — to group
    /// loose (project-less) tasks and propose shared tags. Only the ungrouped
    /// tasks are sent, so prefill stays tiny and the call is fast.
    private func refineWithModel(store: ActionItemStore) async throws -> [TaskSuggestion] {
        let loose = store.items
            .filter { $0.deletedAt == nil && $0.status != .completed && $0.projectID == nil }
            .prefix(30)
        // Nothing loose to group → skip the model entirely (instant).
        guard loose.count >= 2 else { return [] }

        let raw = try await chatClient.oneShotJSON(
            system: Self.groupingSystemPrompt(store: store),
            user: Self.groupingInventory(Array(loose), store: store),
            timeoutSeconds: 45
        )
        let parsed = Self.parseGrouping(raw, store: store)
        reasoning = parsed.summary
        return parsed.suggestions
    }

    // MARK: - Apply / dismiss (user signoff)

    /// Apply one reviewed suggestion to the store and mark it applied.
    func apply(_ suggestion: TaskSuggestion, store: ActionItemStore) {
        guard let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }),
              !suggestions[idx].applied else { return }
        switch suggestion.kind {
        case let .reschedule(taskID, _, newDate):
            store.setDueDate(taskID, dueDate: newDate)
        case let .reprioritize(taskID, _, priority):
            store.setPriority(taskID, priority: priority)
        case let .assignProject(taskIDs, _, projectName, existingID):
            let pid = existingID ?? store.createProject(name: projectName).id
            for tid in taskIDs { store.setProject(tid, projectID: pid) }
        case let .addTag(taskIDs, _, tag):
            let label = store.labels.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }
                ?? store.createLabel(name: tag)
            for tid in taskIDs where !(store.items.first { $0.id == tid }?.labelIDs?.contains(label.id) ?? false) {
                store.toggleLabel(tid, labelID: label.id)
            }
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

    /// Compute the obvious, high-confidence fixes in pure Swift — no LLM, no
    /// network — so they render instantly. Covers the two highest-value cases:
    /// rescheduling overdue tasks and correcting priority from clear title cues.
    static func deterministicSuggestions(store: ActionItemStore) -> [TaskSuggestion] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let open = store.items.filter { $0.deletedAt == nil && $0.status != .completed }
        var out: [TaskSuggestion] = []

        // 1) Overdue → reschedule. Urgent/high land today; everything else is
        //    spread across the next few weekdays so we don't pile it all on one
        //    day. Deterministic and explainable.
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
        //    "someday/eventually" task as low. Never fight an explicit higher
        //    priority the user already set.
        for t in open {
            guard let (p, cue) = inferredPriority(from: t.title) else { continue }
            let isUpgrade = rank(p) > rank(t.priority)
            let isSomeday = p == .low && (t.priority == .medium || t.priority == .high)
            guard isUpgrade || isSomeday, p != t.priority else { continue }
            out.append(.init(kind: .reprioritize(taskID: t.id, taskTitle: t.title, priority: p),
                             reason: "“\(cue)” in the title → \(p.label) priority"))
        }
        return out
    }

    private static func rank(_ p: ActionItem.Priority) -> Int {
        switch p { case .low: return 0; case .medium: return 1; case .high: return 2; case .urgent: return 3 }
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
