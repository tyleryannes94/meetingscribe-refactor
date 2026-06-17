# AI Chat & Second Brain UX Findings — MeetingScribe v2 Audit

## Top friction points / gaps (file:line citations)

### 1. Chat rail is hidden by default — buried discoverability
`MainWindow.swift:73` sets `@AppStorage("chatRailVisible") private var chatVisible = false`. New users land on a full-width app with no hint that an AI assistant exists. There is no coach mark, empty-state nudge, or onboarding step that introduces the chat rail. The rail's toggle affordance is also not visible in a screenshot — it's buried in the toolbar (not audited yet), and the UX comment at line 70–72 says the default-closed choice was intentional for "first-run users" but provides no alternative entry point.

### 2. Chat has no proactive surface — it is 100% reactive
`ChatSession.swift` exposes no scheduled, push, or background analysis pathway. The AI only runs when the user opens the rail and types. There is no mechanism to:
- Surface "You haven't followed up with Jane since your meeting 2 weeks ago"
- Alert "3 open action items from Monday's call are now overdue"
- Offer "Here's the pre-meeting brief for your 2pm call — want me to pull talking points?"
The `systemPrompt` in `ChatSession.swift:52-155` is rich in tool coverage but entirely query-driven.

### 3. Tool palette is invisible to the user — capability gap is unaddressed
`ChatPanel.swift:63-100` shows only a generic "Ask anything" heading and up to 4 static example prompts (defined at each call site, e.g. `MeetingChatTab.swift:13-18`). Users have no way to discover the full tool surface: iMessage analysis, Linear issue creation, Notion push, file read/write, relationship graph queries, semantic search. The example prompts are meeting-scoped when the chat is inside a meeting detail, but the global `ChatSidebar` variant (`ChatSidebar.swift:19`) has no documented example prompts at all in the call site.

### 4. No tool-use transparency or "what just happened" narration
`ChatBubble.swift:196-227` renders `toolUse` blocks as a raw `wrench.adjustable` icon with the tool name and JSON in monospaced text. This is developer-debug output, not a UX surface. Users cannot understand what the AI did or why. Worse, `toolResult` blocks are truncated at 300 characters in compact density — meaning the AI may have retrieved full meeting data that the user can't inspect.

### 5. Chat history trimming is silent and destructive
`ChatSession.swift:204-210` trims to 60 messages at a `.user` boundary. No UI indication is shown. A long-running session silently loses early context, and the user has no way to see this happened or export/archive the conversation.

### 6. Semantic search (embeddings) is entirely invisible to the user
`ChatSession.swift:246-283` — `groundedSystemPrompt()` runs hybrid search and injects meeting snippets into the system prompt as invisible grounding context. The user never sees which meetings were retrieved or that grounding occurred. When the AI cites a meeting via a `meetingscribe://` link in a response, there's no indication the link is navigable, and `ChatBubble` renders it as plain markdown text without a tap handler to actually open the meeting.

### 7. No cross-entity write-back from chat to People/Tasks surfaces
The AI can call `attach_note_to_person` and `create_task`, but there is no confirmation UX — no toast, no inline card in the chat confirming the save, no navigation shortcut to jump to the newly created item. The only acknowledgement is whatever markdown text the LLM generates, which small local models often omit.

### 8. Meeting-scoped chat uses a separate `meetingChat` session (not the global one)
`MeetingChatTab.swift` injects a `meetingChat` session with a `contextPrefix` string. This is a different session from the global `chatSession` owned in `MainWindow`. Users lose continuity — a question answered in the meeting chat tab cannot be referenced in the sidebar chat, and vice versa. The second brain is fragmented at the session layer.

### 9. No ambient / pinned AI insights on People detail or Meeting detail
There is no "AI insight card" that auto-generates and stays visible (not requiring a query). For example, PersonDetailView has no persistent "AI says: last met 3 weeks ago, 2 open tasks, relationship health: fading" card. The AI only shows up when the chat rail is open.

### 10. No "Ask about this" contextual entry point from any entity card
In the People list, Meetings list, or Tasks list, there is no "Ask AI about this person/meeting/task" affordance — right-click menu, swipe action, or toolbar button. The only way to ask the AI about something is to open the chat rail and rephrase what you already see on screen.

---

## Existing items to endorse (from prior plan or codebase)

- **Retrieve-then-ground (C2-2)** in `ChatSession.swift:177-283`: the hybrid search + citation injection is an excellent architectural decision. It just needs to be surfaced visibly to the user (show "retrieved 3 meetings" in the chat UI).
- **Page context injection** (`ChatSession.swift:52-65`): the `pageContext` string that updates as the user navigates is smart and should be preserved and expanded. Currently it's set via `contextLabel(section)` in MainWindow but the actual label content was not inspected — worth auditing for richness.
- **Meeting-scoped example prompts** (`MeetingChatTab.swift:13-18`): good UX pattern, just needs to extend to the global sidebar and People/Task contexts.
- **`attach_note_to_person` tool** (`PeopleChatTools.swift:102-126`): allows the AI to write analysis back into the People graph. Core to the second brain loop — just needs confirmation UX.
- **Per-attendee relationship context injection** (`MeetingChatTab.swift:44-65`, comment `P1-10`): injecting `memories`, `talkingPoints`, and `relationshipType` into the meeting chat context is exactly the right second-brain pattern.

---

## NET-NEW recommendations

### UX5-1: Proactive AI Nudge Engine — "Ambient Second Brain"
- **What:** A background Ollama pass (scheduled daily/post-meeting) that generates short, actionable nudges stored in a `ProactiveInsights` model. Nudges surface in three places: (a) a "Heads up" section at the top of the chat rail when opened, (b) a badge on the chat toggle button, (c) as dismissible cards on the Today dashboard. Examples: "You haven't replied to Sarah's follow-up from your meeting on Monday", "3 action items from last week are overdue and assigned to you", "Your next meeting with the Acme team is in 2 hours — want a brief?"
- **Why (second-brain angle):** A second brain that only responds to queries is a search engine. A second brain that surfaces what you forgot to do is a cognitive partner. This is the single biggest gap between the current app and the stated v2 vision.
- **Cross-feature connections:** Today dashboard (new widget), Chat rail (notification badge + top-of-rail cards), People (overdue keep-in-touch), Meetings (upcoming meeting brief trigger), Tasks (overdue alert)
- **Effort:** L | **Impact:** High
- **Deps:** none — builds on existing Ollama infrastructure

### UX5-2: Capability Discovery Panel ("What can I ask?")
- **What:** A persistent or togglable "capabilities" panel inside the chat empty state and accessible via a `?` button in the input bar. Shows grouped, tappable example prompts organized by domain: Meetings, People, Tasks, Integrations, Files. Each prompt is a real query that fires when tapped. A "Surprise me" button picks a random high-value query from the user's actual data (e.g. "Summarize my last 3 conversations with [most-frequent-contact]").
- **Why (second-brain angle):** The most powerful tool is useless if users don't know it exists. The capability gap between what the AI can do (iMessage analysis, Linear issue creation, relationship health, semantic recall across all meetings) and what users know to ask is enormous.
- **Cross-feature connections:** Chat rail, all tabs (contextual prompts change based on active tab/entity)
- **Effort:** S | **Impact:** High
- **Deps:** none

### UX5-3: Inline AI Insight Cards on Entity Detail Views
- **What:** A non-modal, auto-generated AI card pinned to the top of PersonDetailView and UnifiedMeetingDetail. For People: "Relationship health: fading — last meeting was 3 weeks ago, 1 open ask, no recent messages." For Meetings: "Follow-up status: 2/4 action items completed, follow-up email not sent." The card is generated once via a lightweight Ollama call after the entity is first loaded (or when data changes), cached, and shown without the user asking. A "Ask about this" button on the card opens the chat rail with that entity pre-contextualized.
- **Why (second-brain angle):** Proactive context on the entity itself, not behind a chat modal, is what makes the app feel like a second brain rather than a chat interface that happens to have access to your data.
- **Cross-feature connections:** People tab, Meetings tab, Today dashboard (person cards in 1:1 section)
- **Effort:** M | **Impact:** High
- **Deps:** UX5-1 (same background Ollama infrastructure)

### UX5-4: Unified Chat Session with Entity Deep-Link Navigation
- **What:** Consolidate the meeting-scoped `meetingChat` session and the global `chatSession` into a single persistent `ChatSession` with a `focusContext` that changes when the user navigates. When the AI cites a `meetingscribe://` link in a response, render it as a tappable navigation chip (not plain text) that opens the referenced entity inline. Add a `Go to [entity]` affordance on every AI response that mentions a person, meeting, or task by ID.
- **Why (second-brain angle):** Session fragmentation destroys the "continuous memory" illusion. The AI should remember that you discussed a person in the context of a meeting and maintain that thread across navigation.
- **Cross-feature connections:** Meetings tab (chat tab), Chat sidebar, WorkspaceRouter
- **Effort:** M | **Impact:** High
- **Deps:** none

### UX5-5: "Ask about this" Contextual Entry Points on Every Entity
- **What:** Add a right-click / toolbar button / swipe affordance on every entity card (person row, meeting row, task row) that fires a pre-built query to the AI: "Tell me about [entity name]" or "What should I know before my next meeting with [person]?" Fires `WorkspaceRouter.openChat(query:)` (already exists at `MainWindow.swift:476-479`) with a templated prompt.
- **Why (second-brain angle):** Reduces the activation energy to zero. The user goes from "I see this meeting" to "I understand this meeting" in one click, without needing to know the chat exists or how to phrase a query.
- **Cross-feature connections:** People tab, Meetings tab, Tasks tab, Today dashboard
- **Effort:** S | **Impact:** Med
- **Deps:** none (WorkspaceRouter.openChat already implemented)

### UX5-6: Tool-Use Narration and Write-Back Confirmation Cards
- **What:** Replace the raw `toolUse`/`toolResult` bubble rendering in `ChatBubble.swift:196-227` with human-readable narration: "Looking up your meetings from the last 14 days…", "Found 3 open tasks from Monday's sync.", "Saved a relationship summary to Jane's profile." For write operations (`create_task`, `attach_note_to_person`, `push_action_item_to_notion`), show an inline confirmation card with a "Go to →" navigation link.
- **Why (second-brain angle):** Trust in an AI system depends on legibility — the user needs to know what the AI did, not just read its prose output. This is especially important for write operations that modify the user's data.
- **Cross-feature connections:** Chat rail, all tabs (navigation targets)
- **Effort:** M | **Impact:** Med
- **Deps:** none

### UX5-7: Chat History Export and Session Memory Digest
- **What:** Before the `trimHistory()` cut at 60 messages (`ChatSession.swift:204`), automatically summarize the trimmed turns into a "conversation digest" entry in the system prompt prefix (not the messages array). Add a "Export conversation" button to save the full chat as markdown. Show a subtle "Earlier context summarized" indicator when trimming has occurred.
- **Why (second-brain angle):** Conversation history IS memory. Silent loss of context is anti-second-brain. Summarizing trimmed turns keeps the model aware of what was discussed while respecting context limits.
- **Cross-feature connections:** Chat rail, file export
- **Effort:** S | **Impact:** Med
- **Deps:** none

### UX5-8: Semantic Search Transparency — "Why this answer?"
- **What:** When `groundedSystemPrompt()` retrieves meetings (`ChatSession.swift:246-283`), surface the retrieved sources as a collapsed "Sources" disclosure group at the bottom of the AI response, showing meeting title + date + a 2-line excerpt. Each source is a navigation chip that opens the meeting. This is the "grounding receipt" the user needs to trust AI answers.
- **Why (second-brain angle):** Grounded answers with visible provenance are more useful and more trustworthy than opaque responses. The infrastructure already exists — it just needs UI exposure.
- **Cross-feature connections:** Meetings tab (deep link navigation from sources), Chat rail
- **Effort:** S | **Impact:** Med
- **Deps:** none (C2-2 already implemented server-side)

---

## Top 3 picks

1. **UX5-1 (Proactive AI Nudge Engine)** — transforms the app from a reactive chatbot into an actual second brain; highest alignment with Tyler's v2 vision of proactive, not reactive intelligence.
2. **UX5-3 (Inline AI Insight Cards)** — gets AI context into the user's flow without requiring them to open a chat rail; closes the ambient intelligence gap on entity detail views.
3. **UX5-2 (Capability Discovery Panel)** — smallest effort, highest discoverability lift; the tool suite is already built, users just don't know it exists.
