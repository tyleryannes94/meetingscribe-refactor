import Foundation
import VaultKit

/// In-process Chat tool façade. Tool NAMES + input schemas intentionally
/// mirror what the bundled MeetingScribeMCP server exposes so the model's
/// "mental model" is the same whether it's talking to the in-app chat or
/// to the external MCP through Claude Desktop. The actual work is done by
/// directly calling MeetingStore / QuickNoteStore / TagStore — no
/// subprocess spawn, no JSON-RPC.
///
/// Phase 0 split: this used to be a 916-line god-object. It's now a thin
/// router that owns four domain-specific handlers:
///
///   • `MeetingChatTools`     — read-only meeting + voice-note tools
///   • `ActionItemChatTools`  — action items + tasks/projects + Notion push
///   • `IntegrationChatTools` — Linear, Google Drive, external task sync
///   • `FileChatTools`        — sandboxed reads/writes in approved folders
///   • `PeopleChatTools`      — second-brain People graph + iMessage stats
///
/// Each handler owns its tool catalog and dispatcher. Adding or removing
/// a tool now touches one ~200-line file instead of the giant switch.
///
/// Public surface is unchanged: `tools` returns the merged catalog;
/// `run(name:input:)` walks the handlers in order until one claims the
/// tool name. `ChatSession.swift` doesn't need to change.
@MainActor
final class ChatTools {
    let manager: MeetingManager

    // The four domain handlers. Stored as `let` because none of them are
    // ever rebuilt — the manager reference is stable for the lifetime of
    // the ChatSession.
    private let meetingTools: MeetingChatTools
    private let actionItemTools: ActionItemChatTools
    private let integrationTools: IntegrationChatTools
    private let fileTools: FileChatTools
    private let peopleTools: PeopleChatTools
    private let decisionTools: DecisionChatTools   // 4-C

    /// Order matters for `run(name:input:)` only as a tiebreaker — tool
    /// names are unique across handlers, so the first non-nil `run` wins
    /// and we never traverse the rest. The catalogs are concatenated in
    /// the same order so `tools` is stable across launches.
    private var handlers: [any ChatToolHandler] {
        [meetingTools, actionItemTools, integrationTools, fileTools, peopleTools, decisionTools]
    }

    init(manager: MeetingManager) {
        self.manager = manager
        self.meetingTools     = MeetingChatTools(manager: manager)
        self.actionItemTools  = ActionItemChatTools(manager: manager)
        self.integrationTools = IntegrationChatTools(manager: manager)
        self.fileTools        = FileChatTools()
        self.peopleTools      = PeopleChatTools(manager: manager)
        self.decisionTools    = DecisionChatTools(manager: manager)
    }

    // MARK: - Catalog (Anthropic.Tool schemas)

    var tools: [AnthropicClient.Tool] {
        handlers.flatMap { $0.tools }
    }

    // MARK: - Dispatch
    //
    // Walks each handler in priority order. The first one that returns
    // a non-nil Result owns the tool. If none claim it, we surface the
    // same "Unknown tool" error the old monolithic switch did.

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error> {
        for handler in handlers {
            if let result = await handler.run(name: name, input: input) {
                return result
            }
        }
        return .failure(AnthropicClient.ClientError
            .toolExecutionFailed(name, "Unknown tool"))
    }
}

/// Common shape every domain handler exposes. Lets `ChatTools` iterate
/// them generically rather than hard-coding the names.
@MainActor
protocol ChatToolHandler {
    var tools: [AnthropicClient.Tool] { get }
    /// Return `nil` if `name` isn't a tool this handler owns — the façade
    /// uses that as a "next handler please" signal.
    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>?
}

extension MeetingChatTools:     ChatToolHandler {}
extension ActionItemChatTools:  ChatToolHandler {}
extension IntegrationChatTools: ChatToolHandler {}
extension FileChatTools:        ChatToolHandler {}
extension PeopleChatTools:      ChatToolHandler {}
