# MeetingScribe — PM Audit v2 (Post-Rebuild)

**Target:** `/Users/tyleryannes/MeetingScribeRefactor` (the correct, newly-rebuilt repo — NOT `~/MeetingScribe`)
**Date:** 2026-05-29
**Method:** Static code read of `Sources/MeetingScribe/**`, `Sources/MeetingScribeMCP/main.swift`, planning docs (`README.md`, `MASTER_PLAN_V2.md`, `HANDOFF.md`).
**Perspectives:** PM-1 Core workflow · PM-2 People CRM · PM-3 Tasks/Projects · PM-4 Today/retention · PM-5 Integrations/portability/differentiation.

---

## What the rebuild actually shipped (verified in code)

The rebuild is real and substantial. Confirmed in source:

- **Summary-first meeting tabs.** `UnifiedMeetingDetail` defaults past meetings to the Summary tab (`applySmartTabDefault`, lines 239–255). Tabs: Summary / Transcript / My Notes / Chat.
- **Inline action items in the summary.** `MeetingSummaryTab.actionItemsSection` renders extracted items inline with a one-tap "mark done" (`InlineActionItemRow`, lines 132–211).
- **Follow-up button is wired.** `followUpButton` (MeetingSummaryTab:101) opens `FollowUpView` in a sheet — previously dead code, now reachable. Generates via Ollama; **copy/share only, no send.**
- **Pre-meeting brief.** `PreMeetingBriefView` shows prior meetings with shared attendees + open action items for `.upcoming` meetings.
- **Regenerate / Generate summary.** `MeetingSummaryTab.emptySummaryView` exposes a "Generate Summary" button calling `pipelineController.transcribeNow(regenerateSummary: true)`.
- **People two-column.** `PersonDetailView` is a fixed 280pt identity panel + tabbed right column (Notes / Meetings / Messages).
- **Meetings = NavigationSplitView.** `MeetingsView` is a true 2-column split (list left, full-page detail right) — replaces the old accordion in the Meetings tab.
- **Coach tab removed.** `TopLevelSection` has exactly 5 cases: today, meetings, people, actions (Tasks), notes (Voice Notes). No Coach.
- **Vault migration.** `VaultMigrationManager` + `VaultMigrationSheet` wired in `MeetingScribeApp`. `iCloudInboxWatcher` is instantiated at startup.
- **MCP is still 100% read-only** (12 tools, all `get_*` / `list_*`; main.swift:190 comment "Read-only. We don't write back").

---

## Tyler's 5 explicit requirements — verification

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | People CRM easier to edit | **PARTIAL** | `AddPersonSheet(editing:)` supports full edit (name, company, role, email, phone, address, birthday, favorites, bio, tags). Edit button in `PersonDetailView.identityPanel` opens it. Encounters/relationships/memories/photos all addable. BUT: all editing is **sheet/modal-based**, not inline. Single email/phone/address only (`replacingFirst`) — can't manage multiple. No inline click-to-edit on the detail card. |
| 2 | Today more functional hub | **PARTIAL** | `TodayView` has header, primary Record button, secondary quick-action pills (Join & record / Voice note / New task / New page), live recording card, today's meetings, `ActionItemsWidget`, `SuggestedPeopleView`. Solid. BUT: still uses **expand/collapse** inline detail (violates req #3); no "what's next" focus / streak / weekly digest / overdue-task surfacing beyond the widget. |
| 3 | Replace collapse/expand with click-into + back arrow | **PARTIAL / INCONSISTENT** | **Meetings tab: SHIPPED** — `MeetingsView` is a NavigationSplitView, click selects → full-page detail (no accordion). **Today tab: NOT done** — `TodayView.cardWithDetail` (lines 207–255) still toggles `expandedMeetingID` and renders inline `UnifiedMeetingDetail` with a "Collapse" chevron. `MeetingCard` still takes `isExpanded` + rotates a chevron. No back-arrow navigation in Today. |
| 4 | Defaults upcoming→past→all, sorted | **PARTIAL** | Sorting is correct everywhere (upcoming ascending, past descending). BUT the **default scope in `MeetingsView` is `.all`** (`@State private var scope: Scope = .all`, line 21), not upcoming-first. The `.all` group order is Upcoming → Today → Earlier, which approximates the intent, but the literal "default to upcoming, then past, then all" toggle ordering isn't the active default. |
| 5 | Restore lost buttons/editing from rebuild | **MOSTLY SHIPPED** | Follow-up button restored & wired. Generate/Regenerate summary present. Import meeting/audio/transcript present (`PersistentToolbarButtons`, `fileImporter`s). Tasks have full inline CRUD (`TaskRowView`: title/owner TextFields, DatePicker, status, priority, subtasks). Voice note, ad-hoc record, Join & Record all present. No obviously-missing button found vs. README feature table. |

**Net:** 0 of 5 fully shipped; all 5 are partial-to-mostly. The two cleanest gaps are **#3 (Today still expand/collapse)** and **#4 (default scope = all, not upcoming)** — both small, high-signal fixes Tyler will notice immediately.

---

## PM-1 — Core Workflow (record → transcribe → summarize → act)

**State:** Strong. Recording (ad-hoc, calendar, Join & Record, impromptu detect), 5-min chunked live transcription, final pass, Ollama summary, inline action items, follow-up draft. The loop is intact and summary-first.

**Gaps:** Follow-up can't actually send (copy/share only). No speaker labels surfaced in summary UI despite `SpeakerDiarization.swift` existing. No "share meeting" (PDF/email/link) export from the detail. Regenerate-summary is buried in the empty state, not available when a summary already exists.

| # | Title | Problem / JTBD | Solution | Effort | Impact | Priority |
|---|---|---|---|---|---|---|
| 1.1 | Always-available "Regenerate summary" | When a summary exists but is poor, the only regen path is the empty state | Add a "Regenerate" overflow action on the Summary tab toolbar (reuse `transcribeNow(regenerateSummary:)`) whenever a transcript exists | S | High | **P0** |
| 1.2 | Send follow-up, not just copy | "Draft follow-up" dead-ends at clipboard; the JTBD is to *send* it | Add "Open in Mail" (`mailto:` / `NSSharingService`) + per-attendee recipient prefill from `meeting.attendees` | S | High | **P0** |
| 1.3 | Custom summary templates | One-size summary doesn't fit a 1:1 vs. an all-hands | Per-tag summary prompt templates (decisions/risks/next-steps presets) selectable on the meeting | M | Med | P1 |
| 1.4 | Speaker-labeled transcript & summary | "Who said what" is the #1 transcript ask; diarization code exists but isn't surfaced | Wire `SpeakerDiarization` output into transcript rendering + attribute action items to speakers | L | High | P1 |
| 1.5 | One-click share/export meeting | Send a polished recap outside the app | "Share" menu → Markdown / PDF / copy-rich-text, reusing `MeetingExporter`/`ObsidianExporter` | M | Med | P1 |

---

## PM-2 — People CRM

**State:** Genuinely differentiated — the iMessage analysis + meeting backlinks + relationship graph is the moat (MASTER_PLAN_V2 agrees). Detail view is clean: identity panel, encounters, relationships, memories, photos, attached notes, conversation analysis presets.

**Gaps:** Editing is modal-only (req #1). Single email/phone/address per person. No "stay in touch" / last-contacted nudges despite having `lastDate` from message stats. No quick-add-from-meeting-attendee flow. Graph demoted to experimental.

| # | Title | Problem / JTBD | Solution | Effort | Impact | Priority |
|---|---|---|---|---|---|---|
| 2.1 | Inline-edit person fields | Modal sheet for a one-word company change is heavy (req #1) | Make identity-panel fields click-to-edit-in-place (TextField on tap, autosave on blur), like Tasks already do | M | High | **P0** |
| 2.2 | Multiple emails/phones/addresses | `replacingFirst` throws away a person's other contact points | Editable list rows (+/− per contact field) in `AddPersonSheet` and inline | M | Med | P1 |
| 2.3 | "Stay in touch" nudges | Relationship rot — you forget to follow up with people you care about | Surface "haven't talked to X in N days" on Today, derived from message `lastDate` + meeting history; snooze/done | M | High | P1 |
| 2.4 | Promote attendees → People in one tap | Meeting attendees aren't auto-linked to CRM records | "Add to People" affordance on attendee chips in meeting detail; dedupe via `NameSimilarity` | S | Med | P1 |
| 2.5 | Person timeline (unified) | Meetings, messages, encounters, notes are in separate tabs | A single chronological "Timeline" tab merging all interaction types | L | Med | P2 |

---

## PM-3 — Tasks / Projects

**State:** The strongest subsystem. `ActionItemsView` offers list/table/board views, projects, initiatives, per-meeting note pages, full inline CRUD (`TaskRowView`), filters (week/open/overdue/etc.), grouping, Notion push (`NotionActionItemService`). Feels like Linear/Asana.

**Gaps:** No recurring tasks. No "my tasks today" cross-surface (only the Today widget). No dependencies/blocking. Notion push is one-way (no pull-back of status). No keyboard-first quick-add.

| # | Title | Problem / JTBD | Solution | Effort | Impact | Priority |
|---|---|---|---|---|---|---|
| 3.1 | Two-way Notion sync | Push is one-way; status changes in Notion don't reflect back | Poll/webhook Notion DB → reconcile status/due into `ActionItemStore` (`TaskSyncService` exists as a hook) | L | Med | P1 |
| 3.2 | Quick-add task from anywhere (⌘N) | Capture friction kills task hygiene | Global ⌘N quick-add palette (title + optional project/due via natural language) | S | High | **P0** |
| 3.3 | Recurring tasks | "Weekly status report" must be recreated each time | `recurrence` field + regeneration on completion | M | Med | P2 |
| 3.4 | Task dependencies / blocking | Can't model "X blocks Y" | `blockedBy` relation + visual indicator in board/table | M | Low | P2 |
| 3.5 | Daily task digest notification | Tasks live in the app; you forget them | Morning local notification: today's due + overdue, deep-link into Tasks | S | Med | P1 |

---

## PM-4 — Today as Daily Hub + Retention

**State:** Functional hub (req #2 partial). Header, primary CTA, pills, live card, today's meetings, action-items widget, suggested people.

**Gaps:** Still uses expand/collapse (req #3 violation in this tab). No "next meeting" countdown/prep CTA at the top. No streaks/digest/end-of-day recap. No overdue surfacing distinct from the generic widget. Calendar-link card exists but routes to Meetings.

| # | Title | Problem / JTBD | Solution | Effort | Impact | Priority |
|---|---|---|---|---|---|---|
| 4.1 | Replace Today expand/collapse with click-into | Direct req #3; inconsistent with Meetings tab | Make Today meeting cards navigate to the full-page detail (push or select-into Meetings) with a back arrow; delete `expandedMeetingID`/`isExpanded` path | M | High | **P0** |
| 4.2 | "Up next" prep banner | The single most useful daily glance is *what's my next meeting and am I ready* | Top-of-Today banner: next meeting, countdown, attendees, "open brief", "Join & record" | M | High | **P0** |
| 4.3 | End-of-day recap | Retention hook: a satisfying close to the day | Evening summary: meetings recorded, tasks done, follow-ups pending; optional notification | M | Med | P1 |
| 4.4 | Overdue + today's tasks promoted | Open tasks are buried in one widget | Dedicated "Needs attention" block (overdue, due-today, follow-ups not sent) above meetings | S | High | **P0** |
| 4.5 | Default scope upcoming-first | Direct req #4 | Change `MeetingsView` default `scope` to `.upcoming`; keep all/past toggles | S | Med | **P0** |

---

## PM-5 — Integrations, Portability, Differentiation

**State:** Local-first (no telemetry), Ollama + whisper.cpp, EventKit calendar, Obsidian/Drive export, read-only MCP (12 tools), Notion push for tasks, vault migration to date-partitioned + iCloud, iPhone inbox watcher scaffolded.

**Gaps:** **MCP is read-only** — Claude can't create tasks, add people, or draft follow-ups via the agent. iPhone Shortcuts inbox is scaffolded but unproven end-to-end. No CRM/Slack/Gmail-thread integrations. Follow-up doesn't reach email. No web/mobile view of the vault beyond Obsidian.

| # | Title | Problem / JTBD | Solution | Effort | Impact | Priority |
|---|---|---|---|---|---|---|
| 5.1 | Write-capable MCP tools | Claude can read everything but change nothing — half the agent value is missing | Add `create_action_item`, `update_action_item`, `add_person`, `add_memory`, `create_meeting_note` to MCP (NSFileCoordinator writes) | M | High | **P0** |
| 5.2 | Email/calendar integration for follow-ups | Follow-up dies at clipboard; sending closes the loop | Gmail/Mail send + "schedule next meeting" via EventKit write from the follow-up sheet | M | High | P1 |
| 5.3 | Verify iPhone Shortcuts inbox e2e | Mobile capture is the killer convenience; currently unproven | Ship + test the 4 Shortcuts (quick note, action item, add person, voice note) against `iCloudInboxWatcher` | M | High | P1 |
| 5.4 | "Find everything about X" unified search | The moat is the graph; search should query people+meetings+tasks+messages at once | Wire the FTS5 v2 `searchAll()` into `GlobalSearchView` with recency boost | M | High | P1 |
| 5.5 | Auto-CRM-enrich from message activity | Differentiation: a CRM that maintains itself | Background job: update `lastContacted`, suggest tags/relationships from message+meeting signal | L | Med | P2 |

---

## NEW feature ideas (cross-cutting, genuinely net-new)

- **Relationship intelligence digest** (weekly): "people you're drifting from," "warm intros you could make" from the graph. Extends the moat.
- **Meeting prep auto-draft**: before an upcoming meeting, auto-generate talking points from the pre-meeting brief + open action items + last conversation.
- **Voice-note → task/person router**: speak "remind me to send Alice the deck Friday" → parsed into a task linked to the Alice person record.
- **"Ask my second brain" home answer box**: natural-language query on Today that runs the chat agent against the unified FTS5 index.

---

## Top priorities (P0 roll-up)

1. **4.1** Today click-into navigation (req #3)
2. **4.5** Default scope upcoming-first (req #4)
3. **4.4** Promote overdue/today's tasks on Today (req #2)
4. **2.1** Inline-edit person fields (req #1)
5. **1.2** Send follow-up (not just copy)
6. **1.1** Always-available regenerate summary
7. **5.1** Write-capable MCP tools
8. **3.2** Global quick-add task (⌘N)

These eight close all five of Tyler's explicit requirements and unlock the highest-leverage workflow/agent gaps.
