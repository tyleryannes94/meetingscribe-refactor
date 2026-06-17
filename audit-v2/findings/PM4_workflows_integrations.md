# Cross-Feature Workflows & Integrations Findings — MeetingScribe v2 Audit

**Agent ID:** PM4  
**Sub-lens:** End-to-end user journeys spanning multiple tabs + the external integration ecosystem

---

## Top friction points / gaps (file:line citations)

### 1. Export is manual-only; no automatic post-meeting push
`ObsidianExporter.writeMarkdownFile(for:to:)` is called after each save/transcription (ObsidianExporter.swift:10–57) and the in-folder `.md` is written automatically — but the Notion push (`NotionActionItemService.push(_:)`) and Google Drive export (`IntegrationChatTools.exportMeetingToDrive`) are both purely on-demand. After a meeting ends, the user must manually trigger each destination separately. There is no "on meeting complete → push to configured integrations" pipeline.

### 2. Notion sync is one-way and action-item-only
`NotionActionItemService` can push and update tasks (NotionActionItemService.swift:45–80) but cannot pull. Meeting summaries, decisions, and people context never flow to Notion. The Notion DB schema expected (Name, Status, Priority, Due, Meeting, Owner) is flat — no relationship to the source meeting page, no decisions property, no attendees. A status change in Notion does not flow back to the local `ActionItem`.

### 3. Linear integration is chat-tool-only — invisible from the UI
`IntegrationChatTools` exposes `linear_create_issue`, `linear_list_projects`, `linear_list_teams`, and `sync_external_tasks` (IntegrationChatTools.swift:23–65). None of these are surfaced as right-click actions on tasks, as a button on a meeting's action-items list, or as a keyboard shortcut. Users must know to type a chat command. This buries the most powerful integration behind a discovery wall.

### 4. Google Drive export includes no meeting metadata cross-linking
`exportMeetingToDrive` builds a flat markdown doc (IntegrationChatTools.swift:141–147) using `MeetingExporter.combinedMarkdown` — no frontmatter, no people wikilinks, no action item checklist. In contrast, the Obsidian export (ObsidianExporter.swift:100–138) is rich: YAML frontmatter, `[[wikilinks]]` for attendees, `#tags`, and an action items checklist. The Drive export is a second-class citizen.

### 5. Calendar integration is read-only; no write-back
`CalendarService` reads upcoming meetings and seeds the pre-meeting brief (CalendarService.swift:23–100) but never writes back. When an action item has a due date, it is not added to the user's calendar. Meeting follow-ups, 1:1 prep reminders, and "keep-in-touch" scheduled check-ins from the People tab are not reflected in Calendar.

### 6. No end-to-end workflow automation: recording → summary → tasks → notify
The core journey (record → transcribe → summarize → extract action items → assign owners → push to Notion/Linear → notify attendees) has no single orchestration path. Each step is siloed. There is no post-meeting workflow config (e.g., "when a meeting with tag 'standup' ends: push action items to Linear team X, export summary to Drive, log encounter in People").

### 7. WebAPI exposes data but no integration webhooks
`WebAPI.handle()` (WebAPI.swift:32–63) routes to meetings, people, tasks, voice notes, search, inbox — all read/write endpoints for the phone companion UI. But there is no outbound webhook system: no "notify me at this URL when a meeting finishes" or "ping Linear when an action item status changes." External tools can pull data but cannot subscribe to events.

### 8. ShareSelection friction gate on every export
Every manual export shows a 3-checkbox NSAlert (MeetingExporter.swift:76–109) asking what to include. While correct for privacy (private notes default OFF), this adds a mandatory confirmation click to every export. For configured integrations (Obsidian vault, Notion, Drive) where the user has already decided what they want, this is friction. There is no "remember my choice for this destination" behavior.

### 9. No cross-integration consistency: attendees are plain strings, not Person links
`MeetingExporter.combinedMarkdown` (MeetingExporter.swift:38–55) outputs attendees as a comma-separated string. `ObsidianExporter.markdown` (ObsidianExporter.swift:107–121) writes them as `[[wikilinks]]`. `NotionActionItemService.properties` (NotionActionItemService.swift:123–156) puts `Owner` as a plain rich_text string. Attendee resolution (`PersonResolver`) is available in the codebase but not plumbed into any export path except Obsidian.

### 10. The MCP server (external Claude usage) and the internal AI chat are separate tool sets
`IntegrationChatTools` (IntegrationChatTools.swift) and the MCP server (`MCPInstaller.swift`) are parallel stacks that don't share tool definitions. A change to how Linear issues are created must be duplicated. Integration capabilities added to the chat are invisible to MCP clients and vice versa.

---

## Existing items to endorse (from prior plan or codebase)

- **Obsidian wikilink + frontmatter export** (ObsidianExporter.swift) — the richest export in the codebase; the pattern should be replicated for Notion and Drive.
- **Safe-default share selection** (`ShareSelection.safeDefault`) — the privacy-first approach is correct; the friction should be addressed with saved preferences, not by removing the check.
- **WebAPI token-auth pattern** — the QR-code handshake (`WebAPI.swift:68–78`) is clean. It can be extended for webhook registration without redesigning auth.
- **`sync_external_tasks` chat tool** — the one-liner that pulls from both Linear and Notion simultaneously is underused but the right model. Surface this as a toolbar button, not just a chat command.

---

## NET-NEW recommendations

### PM4-1: Post-Meeting Workflow Engine
- **What:** Add a `PostMeetingWorkflow` model: a user-configurable set of trigger conditions (meeting tag, attendee count, calendar, title pattern) → ordered actions (push action items to Notion, create Linear issues per action item, export summary to Drive, write Obsidian note, log encounters in People, send follow-up draft to Mail). Runs automatically when a meeting's transcript + summary are ready.
- **Why (second-brain angle):** The most valuable moment in a meeting tool is the 5 minutes after the meeting ends. Today that requires 4–6 manual steps across tabs. Automating this makes MeetingScribe feel like an active co-pilot, not a passive recorder.
- **Cross-feature connections:** Meetings → Tasks (action item extraction), Tasks → Notion/Linear (push), Meetings → People (encounter log), Meetings → Drive/Obsidian (export), Calendar (follow-up block scheduling)
- **Effort:** L | **Impact:** High
- **Deps:** PM4-3 (unified export model)

### PM4-2: Notion Bidirectional Sync (Meetings + Decisions, not just Tasks)
- **What:** Expand `NotionActionItemService` into a `NotionSyncService` that: (a) creates a meeting summary page in a configured "Meetings" database with title, date, attendees (as Notion relations to a People DB if configured), decisions, and action items as sub-items; (b) pulls status changes from Notion action item pages back to local `ActionItem.status`; (c) offers a "Notion meeting template" the user can customize.
- **Why (second-brain angle):** Many users already use Notion as their external second brain. MeetingScribe should be the write-head for that system, not a parallel silo. Two-way sync means the user's task manager and the app stay coherent.
- **Cross-feature connections:** Meetings → Notion (meeting pages), Tasks → Notion (action items with back-links to meeting page), People → Notion (person relations)
- **Effort:** L | **Impact:** High
- **Deps:** None (additive to existing `NotionActionItemService`)

### PM4-3: Unified Export Renderer (parity across Obsidian, Notion, Drive, PDF, Markdown)
- **What:** Extract a `MeetingDocument` struct that represents a fully-assembled meeting export (frontmatter, attendees with `Person` links, summary, decisions, action items, notes, transcript). All exporters (`ObsidianExporter`, `MeetingExporter`, `NotionActionItemService`, Drive export) render from this single model. Each destination applies its own format adapter (YAML frontmatter, Notion blocks, Drive markdown, PDF).
- **Why (second-brain angle):** Currently the richest data (person links, decisions, action items) exists only in the Obsidian export. Every other destination is impoverished. Parity ensures the user's external tools are as rich as the in-app view.
- **Cross-feature connections:** Meetings → all export targets, People (person resolution in every export)
- **Effort:** M | **Impact:** High
- **Deps:** None

### PM4-4: Linear Action-Item Context Menu + Auto-Create on Task Acceptance
- **What:** Add a "Create in Linear" right-click action on any `ActionItem` row (and a keyboard shortcut ⌘⇧L). On trigger: pre-fill from the action item's title, owner (mapped to Linear assignee if the People → Linear handle mapping exists), due date, and meeting description. Optionally, surface an app-level setting "auto-create Linear issues for action items I accept from meetings."
- **Why (second-brain angle):** Action items extracted from meetings should flow to where work actually happens with zero friction. Today this requires remembering to type a chat command. A context menu makes it discoverable.
- **Cross-feature connections:** Tasks → Linear, Meetings (source context in Linear description), People (owner → Linear assignee)
- **Effort:** M | **Impact:** High
- **Deps:** PM4-3 (for description rendering)

### PM4-5: Calendar Write-Back — Due Dates + Follow-Up Scheduling
- **What:** When an action item has a due date, offer "Add to Calendar" from the task row. For 1:1s, offer a "Schedule follow-up" button on the People tab that creates a calendar event with the pre-meeting brief pre-loaded as the event notes URL (`meetingscribe://person/{id}`). For keep-in-touch reminders, write the scheduled check-in as a calendar event.
- **Why (second-brain angle):** The calendar is the user's primary commitment surface. Keeping it in sync with MeetingScribe's task and people data turns the app from a recorder into a commitment tracker.
- **Cross-feature connections:** Tasks → Calendar, People (keep-in-touch → Calendar), Meetings (pre-meeting brief URL in event notes)
- **Effort:** M | **Impact:** High
- **Deps:** None

### PM4-6: Outbound Webhook System for External Automation
- **What:** Add a webhook registration endpoint to `WebAPI`: `POST /api/webhooks` (event types: `meeting.completed`, `action_item.created`, `action_item.status_changed`, `person.encounter_logged`). On each event, fire a configurable HTTPS POST with a signed payload. Pairs naturally with Zapier, Make, or a custom n8n workflow.
- **Why (second-brain angle):** Many power users want to pipe MeetingScribe events into their existing automation stacks (Slack notifications, calendar blocking, CRM updates). Webhooks make this zero-code.
- **Cross-feature connections:** All tabs (any event can trigger a webhook), WebAPI
- **Effort:** M | **Impact:** Med
- **Deps:** None

### PM4-7: Saved Export Preferences Per Destination
- **What:** Replace the always-shown `confirmShareSelection` NSAlert with a per-destination saved preference (stored in `ExportSettings`). First time to any destination: show the confirmation and save the choice. Subsequent exports: use the saved preference with a subtle "what's included" disclosure label (not a blocking modal). Add a "reset export prefs" option in Settings.
- **Why (second-brain angle):** Every extra confirmation click breaks flow. Users configuring Obsidian or Drive have already decided what they want. Saved preferences keep the privacy protection while eliminating repetitive interruptions.
- **Cross-feature connections:** All export paths
- **Effort:** S | **Impact:** Med
- **Deps:** None

### PM4-8: Unified Integration Status + Health Dashboard
- **What:** Add an "Integrations" section to Settings (or a dedicated Integrations tab) showing: connection status for each service (Notion, Linear, Drive, Obsidian, Calendar, iMessage), last sync time, error log (last 3 errors per service), and a "Test connection" button. Surface a persistent toolbar indicator (green/yellow dot) when any integration is in an error state.
- **Why (second-brain angle):** Currently, integration failures surface as cryptic chat tool errors (`NotionError.missingAPIKey` → "Notion API key isn't set"). Users have no passive awareness that a push is broken. A health dashboard surfaces issues proactively.
- **Cross-feature connections:** All integrations, Today view (surface integration health in the morning brief)
- **Effort:** S–M | **Impact:** Med
- **Deps:** None

### PM4-9: People → Attendee Resolution in All Export Paths
- **What:** In every export that includes attendees (Drive export, Notion meeting page, PDF), run `PersonResolver` against the attendee name list and annotate with the local person's title/company/relationship context. In Notion: create relations to a People database if configured. In Drive/Obsidian: include a "People context" section with each attendee's current role and last interaction date.
- **Why (second-brain angle):** The People graph is the connective tissue of the second brain. Exports that include rich people context turn a static doc into a relationship-aware artifact the recipient (or the user's future self) can act on.
- **Cross-feature connections:** People → all export targets, Meetings
- **Effort:** M | **Impact:** Med
- **Deps:** PM4-3

### PM4-10: Shared Tool Definition Registry (MCP + In-App Chat Parity)
- **What:** Extract integration tool definitions from `IntegrationChatTools` into a shared `IntegrationToolRegistry` that both the in-app chat (via `AnthropicClient.Tool`) and the MCP server consume. When a new integration is added (e.g., Slack), register it once and it appears in both surfaces automatically.
- **Why (second-brain angle):** The current parallel stacks mean capability drift is inevitable — a Linear improvement added to the chat may never appear in MCP and vice versa. A shared registry is a prerequisite for a coherent AI-powered integration surface.
- **Cross-feature connections:** Chat, MCP server, all integrations
- **Effort:** M | **Impact:** Med
- **Deps:** None

---

## Top 3 picks

1. **PM4-1 (Post-Meeting Workflow Engine)** — Automates the highest-value moment in the user journey. Transforms 6 manual steps into zero. The single change most likely to make a v1 → v2 feel like a qualitative leap.
2. **PM4-2 (Notion Bidirectional Sync)** — Most requested integration pattern. Notion is the most common external second brain. Two-way sync makes MeetingScribe the authoritative write-head for the user's knowledge system.
3. **PM4-4 (Linear Action-Item Context Menu)** — Highest-leverage single UI change. Surfaces the most powerful integration at the exact moment the user decides to act on a task. Zero discovery cost.
