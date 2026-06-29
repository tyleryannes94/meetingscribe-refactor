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
    @Published private(set) var isRunning = false
    @Published var reasoning: String?
    @Published var error: String?

    /// True once a run has finished (so the UI can distinguish "no suggestions
    /// yet" from "analyzed, nothing to fix").
    @Published private(set) var didRun = false

    func reset() {
        suggestions = []; reasoning = nil; error = nil; didRun = false
    }

    func run(store: ActionItemStore) {
        guard !isRunning else { return }
        isRunning = true
        reset()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.analyze(store: store)
            } catch {
                self.error = error.localizedDescription
            }
            self.isRunning = false
            self.didRun = true
        }
    }

    private func analyze(store: ActionItemStore) async throws {
        let handlers = TaskOrganizerTools(store: store) { [weak self] suggestion in
            self?.suggestions.append(suggestion)
        }
        let system = Self.systemPrompt(store: store)
        let seed = AnthropicClient.Message(role: .user, content: [.text(Self.taskInventory(store: store))])
        let final = try await chatClient.send(
            messages: [seed],
            system: system,
            tools: TaskOrganizerTools.catalog,
            maxIterations: 10,
            progress: { _ in }
        ) { name, input in
            if let r = await handlers.run(name: name, input: input) { return r }
            return .failure(TaskOrganizerError.unknownTool(name))
        }
        reasoning = Self.lastText(final)
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

    // MARK: - Prompt building

    private static func systemPrompt(store: ActionItemStore) -> String {
        let pretty = DateFormatter(); pretty.dateFormat = "EEEE, MMMM d, yyyy"
        let iso = DateFormatter(); iso.locale = Locale(identifier: "en_US_POSIX"); iso.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let projects = store.projects.filter { $0.status != .archived }.map { $0.name }
        let projectList = projects.isEmpty ? "(none yet)" : projects.map { "- \($0)" }.joined(separator: "\n")
        let tags = store.labels.map { $0.name }
        let tagList = tags.isEmpty ? "(none yet)" : tags.joined(separator: ", ")
        return """
        You are \(AppSettings.shared.userName)'s task organizer inside MeetingScribe. You review their CURRENT tasks and propose concrete fixes that make the list easier to act on. You ONLY propose — the user reviews and one-click applies each suggestion.

        Today is \(pretty.string(from: now)) (\(iso.string(from: now))).

        Existing projects (assign by exact name, or create a new one):
        \(projectList)
        Existing tags: \(tagList)

        WHAT TO LOOK FOR (propose a fix for each issue you find):
        - OVERDUE tasks: reschedule_task to today, or a sensible near-future weekday, based on the title's urgency. Don't pile everything on today.
        - Wrong/missing priority: change_priority (low/medium/high/urgent) from the title's urgency cues.
        - Loose, ungrouped tasks that clearly belong together: group_into_project — assign them to an existing project, or create a new one with a short name. Prefer existing projects when one fits.
        - Tasks that share an obvious theme: apply_tag with a short reusable tag (prefer existing tags).

        RULES
        - Only propose changes that are clearly improvements; skip tasks that are already fine.
        - Each suggestion needs a one-clause `reason` shown to the user.
        - Reference tasks by the exact id from the inventory.
        - Propose at most 12 suggestions. When done, write one short sentence summarizing what you changed and why.
        """
    }

    /// The user-turn inventory of current tasks the model reasons over.
    static func taskInventory(store: ActionItemStore) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let iso = DateFormatter(); iso.locale = Locale(identifier: "en_US_POSIX"); iso.dateFormat = "yyyy-MM-dd"
        let live = store.items
            .filter { $0.deletedAt == nil && $0.status != .completed }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(60)
        var lines = ["CURRENT TASKS (id · title · priority · due · project · tags):"]
        for t in live {
            let due: String
            if let d = t.dueDate {
                let overdue = cal.startOfDay(for: d) < today
                due = iso.string(from: d) + (overdue ? " (OVERDUE)" : "")
            } else { due = "no due date" }
            let project = t.projectID.flatMap { store.project(id: $0)?.name } ?? "none"
            let tags = (t.labelIDs ?? []).compactMap { store.label(id: $0)?.name }.joined(separator: ",")
            lines.append("- (\(t.id)) \(t.title) · \(t.priority.rawValue) · \(due) · \(project) · [\(tags)]")
        }
        if live.isEmpty { lines.append("(no open tasks)") }
        return lines.joined(separator: "\n")
    }

    private static func lastText(_ messages: [AnthropicClient.Message]) -> String? {
        for m in messages.reversed() where m.role == .assistant {
            for b in m.content {
                if case let .text(s) = b, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }
}

enum TaskOrganizerError: Error, LocalizedError {
    case unknownTool(String)
    var errorDescription: String? {
        switch self { case .unknownTool(let n): return "Unknown tool: \(n)" }
    }
}
