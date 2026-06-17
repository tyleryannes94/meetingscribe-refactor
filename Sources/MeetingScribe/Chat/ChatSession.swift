import Foundation
import VaultKit
import OSLog

/// Owns the running Chat. Holds the conversation, drives the
/// tool-use loop against the local Ollama instance, and exposes a
/// Combine-friendly Published snapshot for the SwiftUI chat panel.
@MainActor
final class ChatSession: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Chat")
    /// Chat runs entirely against the local Ollama instance — no API
    /// keys, no outbound traffic.
    private let ollama = OllamaChatClient()
    private(set) var tools: ChatTools?
    private var manager: MeetingManager?

    @Published private(set) var messages: [AnthropicClient.Message] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?
    /// A short description of where the user currently is in the app, so the
    /// assistant can answer "about this page" without being told. Updated by
    /// the views as the user navigates.
    @Published var pageContext: String = ""
    /// P2: a short human label for the current scope (e.g. a meeting title or a
    /// person's name) shown as a breadcrumb pill above the input so users see
    /// what the assistant is grounded on without a heavy header. Empty on
    /// top-level pages (no pill).
    @Published var contextLabel: String = ""
    /// The entity the chat was opened on (a person, a meeting). Once set, it
    /// sticks across top-level navigation so a conversation that started on
    /// Horst's profile keeps grounding tool calls on Horst even when the user
    /// moves to Tasks. Replaced when the chat is opened on a different entity
    /// or cleared by `reset()`.
    private var anchorContext: String = ""
    private var anchorLabel: String = ""

    func setContext(_ context: String, label: String = "") {
        if !label.isEmpty {
            // Entity-grounded context (person / meeting detail). Become the
            // sticky anchor; replace any prior anchor (the user is now on a
            // different entity) and update the published page state to match.
            anchorContext = context
            anchorLabel = label
            if context != pageContext { pageContext = context }
            if label != contextLabel { contextLabel = label }
            persistAnchor()
        } else if anchorLabel.isEmpty {
            // No anchor — safe to track wherever the user navigated to.
            if context != pageContext { pageContext = context }
            if !contextLabel.isEmpty { contextLabel = "" }
        }
        // Else: anchor is active and the caller is reporting top-level
        // section navigation. Leave the anchor (and the breadcrumb pill) in
        // place; the chat is still grounded on the entity it was opened on.
    }

    // Persist the conversation across relaunches (V5 TS-1) — it was in-memory
    // only, so every restart wiped the chat.
    private static let cacheName = "chat-session"
    private static let cacheVersion = 1
    private static let anchorCacheName = "chat-anchor"
    private static let anchorCacheVersion = 1

    private struct AnchorState: Codable { let context: String; let label: String }

    /// Default init for @StateObject. Must call `attach(manager:)`
    /// before any user message lands or tools will be unavailable.
    init() {
        if let saved = VaultCache.load([AnthropicClient.Message].self,
                                       name: Self.cacheName, version: Self.cacheVersion) {
            messages = saved
        }
        if let anchor = VaultCache.load(AnchorState.self,
                                        name: Self.anchorCacheName,
                                        version: Self.anchorCacheVersion) {
            anchorContext = anchor.context
            anchorLabel = anchor.label
            pageContext = anchor.context
            contextLabel = anchor.label
        }
    }

    private func persist() {
        VaultCache.save(messages, name: Self.cacheName, version: Self.cacheVersion)
    }

    private func persistAnchor() {
        VaultCache.save(AnchorState(context: anchorContext, label: anchorLabel),
                        name: Self.anchorCacheName,
                        version: Self.anchorCacheVersion)
    }

    func attach(manager: MeetingManager) {
        self.manager = manager
        self.tools = ChatTools(manager: manager)
    }

    var systemPrompt: String {
        let effective = anchorContext.isEmpty ? pageContext : anchorContext
        let contextBlock = effective.isEmpty ? "" : """

        WHERE THE USER IS RIGHT NOW (PRIMARY CONTEXT — read this every turn):
          \(effective)
          For ANY ambiguous question (pronouns, "this", "they", "next week",
          "the trip", "what about…"), assume it's about the entity above.
          If the context names a person with an id, use that id directly for
          get_person / get_person_messages / list_person_meetings /
          attach_note_to_person — do NOT call list_people first when the id
          is right there.
          If an earlier tool result in THIS conversation already revealed an
          entity id (person id, meeting id), keep using that id for follow-up
          calls. Do NOT ask the user to re-specify the person/meeting and do
          NOT call list_people again just to learn the id you already saw.

        """
        return """
        You are the in-app Chat assistant inside MeetingScribe, the user's local
        meeting recorder. The user's name is Tyler. You run entirely on the
        user's machine (no cloud). Tools available:
        \(contextBlock)

        OVERVIEW (use this first):
          get_overview — one call returns recent meetings, ALL open action
          items, and recent voice notes. Call this FIRST for any broad question
          ("what are my action items", "what meetings did I have", "what's due",
          "what came out of yesterday's calls").

        MEETING DATA (read-only):
          list_meetings, get_meeting, get_transcript, get_notes,
          get_summary, list_voice_notes, get_voice_note.

        PEOPLE (second-brain contact graph + iMessage):
          list_people — find someone by name / email / phone (ALWAYS call
            this first when the user asks about a specific person).
          get_person — full profile: contact info, bio, memories,
            relationships, linked meeting IDs.
          get_person_messages — iMessage / SMS conversation stats + recent
            message snippets. Use for "what's the last text from X",
            "summarize my texts with X", "when did I last hear from X".
            Requires Full Disk Access; if it fails, surface the error
            verbatim so the user knows what to enable.
          list_person_meetings — meetings the person attended or was
            mentioned in.
          attach_note_to_person — save text (typically your own analysis
            output: relationship summary, sentiment trends, topics, etc.)
            onto a person's record so the user can find it later. Use
            whenever the user says "save this", "attach to X", "keep this
            analysis", or asks you to remember the result.

        TASKS & PROJECTS:
          list_action_items, create_task, set_action_status,
          set_action_priority, set_action_due_date, list_projects.

        INTEGRATIONS (act on connected services):
          push_action_item_to_notion, sync_external_tasks (pull Linear/Notion
          into Tasks), linear_list_projects, linear_list_teams,
          linear_create_issue (call linear_list_teams first to get team_id),
          export_meeting_to_drive.
          Only use an integration tool if the user asks for it. If a tool says a
          connector isn't configured, tell the user to set it up in the
          Integrations tab — don't pretend it worked.

        FILES IN CHAT FOLDERS (read + write, sandboxed):
          list_chat_folders, list_files, read_file, write_file, edit_file,
          search_files.

        CRITICAL rules:
          • To invoke a tool, USE THE TOOL CALL MECHANISM — populate the
            `tool_calls` field on your response. NEVER write the tool name
            or its JSON arguments as plain text in your reply. If you find
            yourself typing `{"name": ...}` in the message body, stop and
            actually issue the tool call instead.
          • For ANY question about meetings, action items, tasks, or recent
            activity, your FIRST step is to call get_overview. Never answer
            "there are no meetings / no action items" from memory — you must
            call a tool and report what it returns. The user DOES have data.
          • For questions about action items / tasks, use get_overview or
            list_action_items — NOT list_meetings (which only lists calls).
          • To read what was said in a call, call get_transcript or get_summary
            with the meeting id from get_overview / list_meetings.
          • For anything about a specific PERSON (texts, meetings with
            them, contact info, what you've been working on together):
            FIRST call list_people with their name to get the person id,
            THEN call get_person / get_person_messages /
            list_person_meetings with that id. Do NOT search meetings
            blindly hoping the name surfaces — go through list_people.
          • If a tool returns an empty list, REPORT that ("nothing found in
            the last N days") and STOP. Do not retry the same tool with
            different parameters more than once unless the user asks.
          • NEVER call the same tool with the same arguments twice in one
            conversation. If you already called `get_person` for someone,
            the result is in the transcript — read it again, don't re-call
            the tool. Repeated identical calls will be rejected and waste
            the user's time.
          • Be concise. Prefer 1–3 sentences unless the user asks for depth.
          • For file tasks, start by calling list_chat_folders, then
            list_files / read_file before editing. Prefer edit_file over
            write_file; include enough context in `old_string` to match once.
          • If the user asks something that doesn't require a tool, just
            answer directly.
          • You are a productivity assistant for the user's own meeting
            notes and tasks. There is nothing harmful about summarizing
            their own data — never refuse on safety grounds. If a request
            is truly out of scope (e.g. unrelated to the app), say so
            briefly and offer what you CAN do.
        """
    }

    /// Submit a user message and run the tool-use loop. Streams progress
    /// back to `messages` so the UI can render the in-flight conversation.
    func sendUserMessage(_ text: String) async {
        let userMessage = AnthropicClient.Message(role: .user, content: [.text(text)])
        messages.append(userMessage)
        await run()
    }

    /// Re-run from the current message list. Used after a scheduled task
    /// completes to fold its result back into a chat for review.
    func run() async {
        guard !isRunning else { return }
        guard let toolsRef = tools else {
            lastError = "Chat tools not attached — restart the app."
            return
        }
        isRunning = true
        lastError = nil
        defer { isRunning = false }
        // Retrieve-then-ground (C2-2): pull the most relevant vault passages for
        // the latest question via hybrid search and inject them — with their
        // meetingscribe:// links — into the system prompt so the model answers
        // grounded in real meetings and cites them. Tools remain available.
        MetricsStore.shared.record(.chatQuery)   // local-only metric (P5-1)
        let grounded = await groundedSystemPrompt()
        do {
            messages = try await dispatch(
                messages: messages,
                system: grounded,
                tools: toolsRef.tools,
                progress: { [weak self] msg in self?.messages.append(msg) },
                runTool: { name, input in
                    await toolsRef.run(name: name, input: input)
                }
            )
        } catch {
            lastError = error.localizedDescription
            log.error("Chat failed: \(error.localizedDescription, privacy: .public)")
        }
        trimHistory()
    }

    /// Bound the in-memory conversation so a long-running chat can't grow without
    /// limit and get OOM-killed. (V5 PS-2) Trims oldest turns but only at a
    /// `.user` boundary, so tool_use/tool_result pairs and the user/assistant
    /// alternation stay valid.
    private let maxMessages = 60
    private func trimHistory() {
        guard messages.count > maxMessages else { return }
        var cut = messages.count - maxMessages
        while cut < messages.count && messages[cut].role != .user { cut += 1 }
        if cut > 0 && cut < messages.count { messages.removeFirst(cut) }
        persist()
    }

    /// All Chats go through the local Ollama instance.
    private func dispatch(messages: [AnthropicClient.Message],
                          system: String?,
                          tools: [AnthropicClient.Tool],
                          progress: @MainActor (AnthropicClient.Message) -> Void,
                          runTool: @escaping (String, [String: JSONValue]) async -> Result<String, Error>
    ) async throws -> [AnthropicClient.Message] {
        return try await ollama.send(messages: messages,
                                      system: system,
                                      tools: tools,
                                      progress: progress,
                                      runTool: runTool)
    }

    func reset() {
        messages = []
        lastError = nil
        anchorContext = ""
        anchorLabel = ""
        pageContext = ""
        contextLabel = ""
        persist()
        persistAnchor()
    }

    // MARK: - Retrieve-then-ground (C2-2)

    /// Plain text of the most recent user message.
    private func lastUserText() -> String {
        guard let msg = messages.last(where: { $0.role == .user }) else { return "" }
        return msg.content.compactMap { c -> String? in
            if case .text(let t) = c { return t } else { return nil }
        }.joined(separator: " ")
    }

    /// systemPrompt augmented with retrieved, citable vault context for the
    /// current question. Returns the bare systemPrompt when there's nothing to
    /// retrieve (e.g. greetings, or an empty/unbuilt index).
    private func groundedSystemPrompt() async -> String {
        let query = lastUserText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 4, let manager else { return systemPrompt }

        let results = await PeopleStore.shared.searchVaultHybrid(query, limit: 6)
        let meetings = results.filter { $0.entityKind == "meeting" }.prefix(5)
        guard !meetings.isEmpty else { return systemPrompt }

        let df = DateFormatter(); df.dateStyle = .medium
        var blocks: [String] = []
        for r in meetings {
            guard let m = manager.meeting(forEntityID: r.entityID) else { continue }
            let summary = manager.summaryMarkdown(for: m)
            let snippet = summary.isEmpty ? "(no summary)" : String(summary.prefix(1200))
            blocks.append("""
            ### \(m.displayTitle) — \(df.string(from: m.startDate))
            Link: meetingscribe://meeting/\(m.id)
            \(snippet)
            """)
        }
        guard !blocks.isEmpty else { return systemPrompt }

        return systemPrompt + """


        ─────────────────────────────────────────────
        RETRIEVED VAULT CONTEXT (for THIS question)
        ─────────────────────────────────────────────
        The passages below were retrieved from the user's own meetings by hybrid
        search. When the answer is in them, ground your reply in them and CITE
        each meeting you use as a markdown link to its Link above, e.g.
        [Weekly sync](meetingscribe://meeting/<id>). If they don't cover the
        question, say so plainly and offer to search differently or use a tool —
        do NOT invent meetings or details.

        \(blocks.joined(separator: "\n\n"))
        """
    }
}
