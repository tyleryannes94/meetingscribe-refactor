import Foundation
import VaultKit
import SwiftUI
import OSLog

/// Drives one "Plan with AI" run against the local Ollama chat client.
///
/// Builds the seed turn from the active session, runs the tool-use loop with
/// the planner's five tools, streams events back to the UI via the
/// `BrainDumpPlanRunner` (so the activity log fills in live), and leaves the
/// session in `.reviewing` state when the assistant emits its final turn.
@MainActor
final class BrainDumpPlanner {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "BrainDumpPlanner")
    private let chatClient = OllamaChatClient()

    func plan(sessionID: String,
              store: BrainDumpStore,
              actionItems: ActionItemStore,
              contexts: [WorkspaceContext],
              pageContext: String? = nil,
              progress: @escaping (BrainDumpPlannerEvent) -> Void) async throws -> String? {
        guard var session = store.session(sessionID) else {
            throw BrainDumpToolError.badInput("Session not found.")
        }

        store.setState(sessionID, .planning)
        progress(.started)

        let openTasks = actionItems.items
            .filter { $0.deletedAt == nil && $0.status != .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(40)
            .map { (id: $0.id,
                    title: $0.title,
                    project: $0.projectID.flatMap { actionItems.project(id: $0)?.name } ?? "") }

        let system = BrainDumpPrompts.systemPrompt(
            now: Date(),
            userName: AppSettings.shared.userName,
            contexts: contexts,
            projects: actionItems.projects
                .filter { $0.status != .archived }
                .map { (id: $0.id, name: $0.name) },
            initiatives: actionItems.initiatives
                .filter { $0.status != .archived }
                .map { $0.name },
            tags: actionItems.labels.map { $0.name },
            openTasks: Array(openTasks),
            pageContext: pageContext,
            focusMinutes: AppSettings.shared.brainDumpDefaultFocusMinutes,
            workdayStartHour: AppSettings.shared.brainDumpWorkdayStartHour,
            workdayEndHour: AppSettings.shared.brainDumpWorkdayEndHour
        )

        let seedText = BrainDumpPrompts.seedUserTurn(session: session)
        let seed = AnthropicClient.Message(role: .user, content: [.text(seedText)])

        let handlers = BrainDumpToolHandlers(
            sessionID: sessionID,
            store: store,
            actionItems: actionItems,
            progress: progress
        )

        do {
            let final = try await chatClient.send(
                messages: [seed],
                system: system,
                tools: BrainDumpToolHandlers.planTools,
                maxIterations: 12,
                progress: { _ in }
            ) { name, input in
                if let result = await handlers.run(name: name, input: input) {
                    return result
                }
                return .failure(BrainDumpToolError.badInput("Unknown tool: \(name)"))
            }
            store.setState(sessionID, .reviewing)
            session = store.session(sessionID) ?? session
            let reasoning = Self.lastTextBlock(in: final)
            progress(.finished(reasoning: reasoning))
            return reasoning
        } catch {
            store.setState(sessionID, .draft)
            progress(.failed(message: error.localizedDescription))
            throw error
        }
    }

    private static func lastTextBlock(in messages: [AnthropicClient.Message]) -> String? {
        for message in messages.reversed() where message.role == .assistant {
            for block in message.content {
                if case let .text(s) = block, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }
}

/// Lightweight observable wrapper the BrainDumpView uses to track an in-flight
/// plan run. Exposes the live event list (for the activity log) and an
/// `isRunning` flag for button state.
@MainActor
final class BrainDumpPlanRunner: ObservableObject {
    @Published private(set) var events: [BrainDumpPlannerEvent] = []
    @Published private(set) var isRunning = false
    @Published var lastError: String?
    @Published var lastReasoning: String?

    private let planner = BrainDumpPlanner()

    func reset() {
        events.removeAll()
        lastError = nil
        lastReasoning = nil
    }

    func run(sessionID: String,
             store: BrainDumpStore,
             actionItems: ActionItemStore,
             contexts: [WorkspaceContext],
             pageContext: String? = nil) {
        guard !isRunning else { return }
        isRunning = true
        reset()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let reasoning = try await self.planner.plan(
                    sessionID: sessionID,
                    store: store,
                    actionItems: actionItems,
                    contexts: contexts,
                    pageContext: pageContext,
                    progress: { [weak self] event in
                        self?.events.append(event)
                    }
                )
                self.lastReasoning = reasoning
            } catch {
                self.lastError = error.localizedDescription
            }
            self.isRunning = false
        }
    }
}
