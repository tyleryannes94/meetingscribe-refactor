# Emerging AI Productivity Frontier Findings — MeetingScribe v2 Audit

**Agent ID prefix: C5-**
**Sub-lens:** Agentic/Ambient AI — what MeetingScribe must architect for now to stay defensible as the frontier moves.

---

## Competitive landscape snapshot (June 2026)

### What big players are shipping

**ChatGPT Memory (OpenAI)** — as of April 2025, ChatGPT references ALL past conversations, not just explicit saved memories. It builds implicit user models across every interaction. This is a direct attack on apps that store context locally; the question becomes "why should my second brain live in MeetingScribe instead of just in ChatGPT?" The answer must be: MeetingScribe has *structured, verifiable, meeting-sourced* data that ChatGPT cannot construct from chat logs alone (transcripts, action-item provenance, relationship graphs, calendar linkage).

**Limitless AI Pendant → Meta acquisition** — Limitless (always-on wearable) was acquired by Meta in late 2025 and is being folded into Meta AI Glasses (Ray-Ban Meta / Oakley Meta). Meta is building ambient always-on capture into mass-market eyewear. This signals that *ambient capture is becoming infrastructure*, not a product differentiator. MeetingScribe's screen-recording/mic capture moat will erode as ambient capture commoditizes. The moat must shift to what you do WITH the captured data: structured relationships, decision provenance, and actionable intelligence.

**Claude Projects / Anthropic** — Claude can now maintain context across project-scoped documents and memory. Users are building "personal wikis" in Projects. MeetingScribe already integrates `AnthropicClient.swift` for cloud analysis — it is uniquely positioned to be the *data source* for Claude Projects rather than competing with them; meetings and people data fed into a Claude Project would be far richer than manually curated docs.

**Perplexity Assistant / AI search** — proactive push answers, not reactive queries. The category is clearly moving from "answer when asked" to "tell me before I ask." MeetingScribe's `WeeklyRecap` and `StandupDigest` are primitive versions of this; they need to become truly proactive, scheduled, and personalized rather than on-demand-generated markdown files.

**Apple Intelligence (macOS Sequoia / Tahoe)** — on-device SLMs with system-level context (Calendar, Mail, Notes). Apple has privileged access to the ambient context layer. MeetingScribe's defense: Apple Intelligence can't know what was *said in a meeting* — only MeetingScribe has the transcript, and only MeetingScribe has the structured CRM of commitments and decisions built from that transcript.

---

## Top friction points / gaps (file:line citations)

### 1. MCP server is install-and-forget, no bidirectional agent loop
`MCPInstaller.swift:38–46` registers a binary with Claude Desktop via `claude_desktop_config.json`. The integration is one-directional: Claude Desktop queries MeetingScribe data. There is no mechanism for MeetingScribe to *push* context to an agentic orchestrator — no webhooks, no event subscription, no "here's what just happened in your last meeting, here's what I need you to do." In the agentic era, tools don't wait to be called; they emit events.

### 2. WebAPI.swift is a mobile companion API, not an agent surface
`WebAPI.swift:50–60` routes to health/today/recording/chat/meetings/people/projects/tasks/voicenotes/search. This is a solid REST surface for the companion phone app. But it has no streaming endpoints, no webhook registration, no `POST /api/subscribe` for external agents to receive real-time meeting-complete events. An AI agent running in Claude/GPT/a home automation system cannot subscribe to "notify me when a meeting ends and surfaces a commitment."

### 3. No temporal context propagation — the app knows nothing about "now" proactively
`TodayView.swift:41–51` backfills data on `onAppear`. The app waits for the user to open it. There is no background daemon that checks: "meeting starts in 10 minutes → pre-fetch brief → push notification → open app." macOS background tasks (`BGTaskScheduler` equivalent via `NSBackgroundActivityScheduler`) are unused. The app is reactive to user launches, not proactive about calendar events.

### 4. Ollama is used for summarization but not for autonomous planning
`OllamaService.swift` generates summaries and responses. There is no "agentic loop" where Ollama is given a goal ("ensure all action items from today's meetings have been triaged") and iterates with tool calls to check, create, and notify. The `ChatTools.swift` tool-use infrastructure already exists for human-initiated calls — it is architecturally one step from being a scheduled autonomous agent, but that step hasn't been taken.

### 5. No privacy-preserving sync for cross-device or team use
The local-first architecture (`AppSettings.shared.storageDir`) is a privacy moat but also a ceiling. There is no encrypted sync story — no way for the data to follow the user to another Mac, no way to share a meeting intelligence brief with a trusted colleague (beyond exporting to Notion). As ambient AI becomes multi-device (phone captured it, Mac processed it, glasses are wearing it), MeetingScribe's purely local storage becomes a friction point.

---

## Existing items to endorse (from prior plan or codebase)

- **MCP server architecture** — the pattern of exposing app data as MCP tools is exactly right for the agentic era. It means MeetingScribe becomes a *data hub* that any MCP-capable agent can query. Endorse expanding the tool surface.
- **`AnthropicClient.swift`** — already integrated; this is the bridge to Claude-native agentic workflows. Endorse using it for cloud-side orchestration when local Ollama is insufficient for multi-step reasoning.
- **`ResourceGovernor.swift`** — thermal/battery gating infrastructure. Endorse extending it as the single arbiter for all background agentic work.
- **Pre-meeting brief** (`PreMeetingBriefView.swift`) — the right product instinct for proactive AI. Endorse making it auto-triggered (push notification, not just visible when user navigates there).

---

## NET-NEW recommendations

### C5-1: Event Bus + Agent Webhook Layer — make MeetingScribe an agentic data source
- **What:** Add an internal `MeetingScribeEventBus` (lightweight `AsyncStream`-based publisher) that emits typed events: `meetingDidComplete(id:)`, `actionItemCreated(id:ownerID:)`, `personRelationshipHealthChanged(id:score:)`, `decisionRecorded(id:)`. Expose a `POST /api/webhooks` endpoint in `WebAPI.swift` where external agents (local Claude Desktop orchestrators, Home automation, shortcuts) can register a URL. On each event, `WebAPI` POSTs a JSON payload to registered hooks. Locally, MCP tool calls can also listen to this bus to push proactive context into active Claude conversations via a `server-sent-events` endpoint.
- **Why (second-brain angle):** The agentic era requires tools that *emit* as well as respond. MeetingScribe sitting silently until queried is the wrong posture. The event bus makes every workflow automation possible without custom integrations per use-case.
- **Cross-feature connections:** Meetings (emit on pipeline complete), People (emit on health change), Tasks (emit on creation/completion), MCP server (consume events to push context), WebAPI (webhook dispatch).
- **Effort:** L | **Impact:** High
- **Deps:** None

### C5-2: Proactive Calendar-Aware Push — pre-meeting brief as a push notification
- **What:** Register a `NSBackgroundActivityScheduler` job that runs every 15 minutes, checks Calendar for meetings starting within 20 minutes (already fetched via the existing Calendar integration), and if a pre-meeting brief hasn't been generated for that meeting, triggers generation + sends a macOS `UserNotification` with a "View Brief" action that deep-links to `PreMeetingBriefView`. Brief generation should run on-device via Ollama (or fall back to `AnthropicClient` if Ollama is not running). This closes the gap where the user has to remember to open MeetingScribe before a meeting.
- **Why (second-brain angle):** The second brain's job is to know what you need before you know you need it. A meeting brief that appears in your notification center 15 minutes before the call, unsolicited, is the definition of ambient intelligence. Apple Intelligence can only give you Calendar event details; MeetingScribe gives you relationship history, open commitments, and talking points.
- **Cross-feature connections:** Calendar integration (trigger), People (relationship context), Meetings (prior meeting history), Today tab (shows active brief card).
- **Effort:** M | **Impact:** High
- **Deps:** None

### C5-3: Claude Projects Integration — MeetingScribe as a living knowledge source
- **What:** Add a "Sync to Claude Project" action that exports structured data (person relationship briefs, meeting summaries by project, decision log, open action items) as a set of markdown documents into a named Claude Project via the `AnthropicClient`. Schedule this sync weekly (or post-meeting for key contacts). Include an `INSTRUCTIONS.md` that tells the Claude Project how to use the data. This turns MeetingScribe into the *canonical data source* for a user's Claude-powered AI assistant — rather than the two products competing, they compose.
- **Why (second-brain angle):** ChatGPT and Claude Projects are winning the "personal AI memory" space by accumulating conversational history. MeetingScribe wins by being the structured truth layer beneath that: transcripts, relationships, decisions, commitments — things Claude Projects can't generate from chat alone. Making the sync explicit gives users a reason to keep both.
- **Cross-feature connections:** People (person briefs), Meetings (project-scoped summaries), Tasks (open commitments), AnthropicClient (API calls), Settings (sync schedule).
- **Effort:** M | **Impact:** High
- **Deps:** None

### C5-4: Autonomous Post-Meeting Agentic Loop — local Ollama agent
- **What:** After a meeting pipeline completes (`MeetingPipelineController` post-processing), trigger a short autonomous agent run using the existing `ChatTools` tool-use infrastructure but without a human in the loop. The agent receives the fresh meeting summary + attendees + action items and iterates over a fixed goal: (1) check if any action item owner already has an open task in `ActionItemStore`; if not, create it; (2) update each attendee person's `lastContactDate` and `encounterLog`; (3) check if any decision references a prior decision in `DecisionStore`; if so, link them. Log what it did in a `AgentRunLog` struct (displayed in Settings → Agent Activity). This is not general-purpose AGI — it's a constrained, auditable, single-purpose loop.
- **Why (second-brain angle):** The meeting→people→tasks seam is currently manual at every joint (per PM1 findings). A constrained post-meeting agent automates the "did everything get captured?" work that currently requires the user to remember to do it. Local Ollama means zero latency and zero cost.
- **Cross-feature connections:** Meetings (trigger), People (encounter update), Tasks (auto-creation), Decisions (cross-linking), Settings (audit log).
- **Effort:** L | **Impact:** High
- **Deps:** C5-1 (event bus as trigger), PM3-5 (ResourceGovernor gating)

### C5-5: Privacy-Preserving Encrypted Vault Sync (local-first + E2E)
- **What:** Implement optional encrypted sync using Apple's `CKContainer` (CloudKit private database) — the data never leaves the user's iCloud account, is encrypted end-to-end, and syncs to iPhone (companion app already exists via `WebAPI.swift`) and other Macs. Use `SchemaEnvelope` versioning already in place for forward compatibility. Explicitly market this as "your data never touches our servers or any AI cloud unless you choose to send it" — the privacy differentiator against ChatGPT Memory (which trains on data by default) and Meta AI Glasses (always-on ambient capture going to Meta's servers).
- **Why (second-brain angle):** As ambient AI proliferates and users become more privacy-conscious (especially after Limitless/Meta acquisition), "your second brain stays yours" is a defensible positioning that big players structurally cannot match. Local-first + E2E sync is the moat.
- **Cross-feature connections:** All data stores (sync), Settings (CloudKit toggle), iPhone companion (receive synced data).
- **Effort:** XL | **Impact:** High
- **Deps:** None (but should be a v2.1 commitment, not v2.0 launch)

### C5-6: MCP Tool Surface Expansion — agentic superpowers for Claude Desktop users
- **What:** Expand the MCP server (currently registered via `MCPInstaller.swift`) to expose 8–10 new fine-grained tools beyond basic data retrieval: `create_task_from_meeting`, `get_relationship_brief(personName:)`, `get_open_commitments(to:from:)`, `list_decisions_by_project`, `generate_pre_meeting_brief(meetingID:)`, `add_memory(personID:text:)`, `search_all(query:semanticMode:)`. Each tool maps to existing store methods. This makes MeetingScribe the richest MCP data source for professional context among all macOS apps, and makes it indispensable to Claude Desktop power users.
- **Why (second-brain angle):** MCP is becoming the USB-C of AI agents. Being a first-class MCP server with a rich tool surface means any Claude-based agent (Desktop, mobile, or future hardware) can act on MeetingScribe data without opening the app. The app becomes infrastructure, not just a destination.
- **Cross-feature connections:** MCP server (tool definitions), all stores (backing implementations), Claude Desktop (consumer).
- **Effort:** M | **Impact:** High
- **Deps:** C5-1 (event bus for real-time tools)

---

## Positioning analysis: what keeps MeetingScribe defensible

The ambient AI wave (Meta Glasses, Apple Intelligence, ChatGPT Memory) commoditizes *capture*. Every device will soon record and summarize. MeetingScribe's durable moat is the combination of:

1. **Structured relationship graph** — not a chat log, but a typed data model: Person → Encounters → Memories → Action Items → Decisions → Meetings. No ambient capture product builds this.
2. **Commitment provenance** — every task has a `meetingID` origin. You can prove where a commitment was made, to whom, and when. This is legally and professionally valuable in a way that "ChatGPT remembers you have a meeting" is not.
3. **Local processing = zero data egress** — privacy-first users (executives, lawyers, therapists, therapists, healthcare) cannot use Meta AI Glasses or ChatGPT Memory for sensitive meetings. MeetingScribe can be the tool for conversations that cannot leave the device.
4. **MCP hub = composable brain** — as agent orchestrators proliferate, being a rich MCP server means MeetingScribe becomes a layer in other workflows, not a destination that competes with them.

---

## Top 3 picks

1. **C5-2 (Proactive Calendar Push)** — closes the single biggest ambient AI gap today with M effort; transforms the app from reactive to proactive without architectural risk.
2. **C5-4 (Post-Meeting Agentic Loop)** — turns the manual meeting→people→tasks seam into an autonomous process; this is the clearest "second brain doing work for you" moment in the product.
3. **C5-6 (MCP Tool Surface Expansion)** — the fastest path to becoming indispensable to Claude Desktop users and positioning MeetingScribe as the structured data hub for personal AI agents.
