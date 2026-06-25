# MeetingScribe — UX Redesign **v4 (clean handoff, 2026-06-25)**

> **READ THIS FIRST — for Claude Code / any build agent.**
>
> This handoff **supersedes** every earlier one (`design_handoff_bloom_redesign 2/`,
> `design_handoff_ux_redesign_v2/`, and the previous `handoff_2026-06-25/`).
>
> It differs from earlier handoffs in one important way: **the file map below was
> verified against the live Swift source on `main`** (`tyleryannes94/meetingscribe-refactor`).
> Earlier handoffs referenced files that **do not exist** (e.g. `MeetingsView` was fine,
> but `MeetingDetailHeader.swift`, `MeetingNotesTab.swift`, and an editable
> `MarkdownEditor.swift` were invented). Those wrong paths are the single biggest reason
> a build agent "keeps not building it correctly" — it goes looking for files that aren't
> there, can't reconcile the described structure, and stalls.
>
> **Most of this redesign is already implemented on `main`.** This is a *conformance +
> finishing* pass, not a from-scratch build. For each screen below you get: the **real**
> file(s), **what already exists**, and the **exact remaining diff**. Build to the
> prototype in `prototype/` and the screenshots in `screens/`; when something on `main`
> already matches, leave it and move on.

---

## 0. How to use this package

```
handoff_2026-06-25/   (this folder)
├── HANDOFF.md                 ← source of truth (this file)
├── README-FIRST.md            ← the exact prompt to paste into Claude Code
├── FILE_MAP.md                ← screen → real Swift file lookup (quick reference)
├── prototype/                 ← high-fidelity design prototype (browser, NOT app source)
│   ├── MeetingScribe.dc.html  ← the app shell: nav rail, toolbar, all pages, settings, modals
│   ├── MeetingDetail.dc.html  ← meeting detail + Edit mode (embedded by the shell)
│   ├── PersonWork.dc.html     ← person tabbed work area (Overview/Meetings/Tasks/Messages/Notes)
│   ├── TaskDetail.dc.html     ← task detail + property popover editors
│   ├── VoiceNotePill.dc.html  ← floating voice-note hover pill — Recording / Transcribing / Saved
│   └── support.js             ← prototype runtime (IGNORE for the Swift build)
└── screens/                   ← reference PNGs (01-today … 11-new-item-modal)
```

**The `.dc.html` files are a design prototype, not app source.** They render in a browser via
a small runtime (`support.js`). Read them for exact layout, inline styles, colors, spacing, and
interaction logic, then translate to SwiftUI. **Do not port `support.js`.** All styling is inline;
all view-model/state logic is in the `<script data-dc-script>` class at the bottom of each file —
look in `renderVals()` for the behavior of every control. Each prototype file also opens
standalone in a browser (each carries its own theme tokens + a representative data sample), so you
can inspect any one screen in isolation.

To view everything: open `prototype/MeetingScribe.dc.html` in a browser. Click the nav items to
walk Today / Meetings / People / Tasks / Voice Notes; open Settings (gear, bottom of rail); the
toolbar's coral button opens the New-item modal. Attendee chips in a meeting link to People; a
task's meeting-source chip links to Meetings.

---

## 1. Design language — "Bloom" (already implemented as the `NDS` token set)

Dark plum base, warm coral primary, lilac brand accent. Headings in **Bricolage Grotesque**
(700–800), body in **Plus Jakarta Sans**. These values are **already** in
`Sources/MeetingScribe/UI/NotionDesign.swift` as the `NDS` enum — use those tokens, don't
hard-code hex. The prototype's CSS variables map 1:1 to `NDS`:

| Prototype var | Hex | `NDS` token |
|---|---|---|
| `--bg` | `#15121a` | `NDS.appBg` |
| `--sidebar` | `#100d15` | `NDS.sidebarBg` |
| `--surface` | `#1e1925` | `NDS.surface` |
| `--surface-2` | `#271f31` | `NDS.surface2` |
| `--surface-3` | `#322843` | `NDS.surface3` |
| `--line` | `rgba(245,238,250,.09)` | `NDS.hairline` / `NDS.divider` |
| `--line-2` | `rgba(245,238,250,.16)` | `NDS.hairlineStrong` |
| `--txt` | `#f3eef6` | `NDS.textPrimary` |
| `--txt-2` | `rgba(243,238,246,.68)` | `NDS.textSecondary` |
| `--txt-3` | `rgba(243,238,246,.44)` | `NDS.textTertiary` |
| `--accent` / `--accent-2` | `#ff9173` / `#f06a4c` | `NDS.accent` (gradient `NDS.brandMarkGradient` / coral 135°) |
| `--accent-soft` | `rgba(255,145,115,.16)` | `NDS.accentSoft` |
| `--lilac` / `--lilac-soft` | `#b79cff` / 16% | `NDS.lilac` / `NDS.lilacSoft` (brand / active nav / AI) |
| `--mint` | `#74e0bc` | `NDS.mint` (success / completed / Healthy) |
| `--sky` | `#8ab4ff` | `NDS.sky` (info / To-do / New) |
| `--gold` | `#ffce6b` | `NDS.gold` (warning / due / In-progress / Slipping) |
| `--danger` | `#ff7a8a` | `NDS.danger` (recording / At-risk / High) |

Conventions (all already encoded in `NDS` + `MSComponents.swift`):
- **Primary action** = coral gradient `linear-gradient(135deg,#ff9173,#f06a4c)`, `#2a1208` text → `MSPrimaryButtonStyle`.
- **Active nav item** = `NDS.rowSelected` (lilac-soft) fill, lilac icon → see `NavRailItem` in `MainWindow.swift`.
- **Eyebrow labels** = 10px/700/1px-tracking/uppercase/`NDS.textTertiary`.
- Card radius 14–18; pill/chip 999; buttons 9–11.
- Avatars: rounded-square, per-person gradient, initials in `#241636` → `MSAvatar.swift`.
- **Cadence colors:** Healthy=mint, Slipping=gold, At risk=danger, New=sky → `RelationshipType+Color.swift`.
- Reusable building blocks live in `MSComponents.swift`: `MSSection`, `MSEmptyState`, `MSSkeleton`,
  `MSInlineButton`, `MSPrimaryButtonStyle`, `MSSecondaryButtonStyle`. **Prefer these over raw SwiftUI controls.**

> If a screen is using cold `NSColor.*` or raw `.bordered` buttons instead of `NDS`/`MS*`,
> migrate it (this was flagged as LAY-4 in `MASTER_PLAN_V3.md`).

---

## 2. The corrected file map (the part earlier handoffs got wrong)

| Screen / area | ❌ Wrong name in old handoffs | ✅ Real file(s) on `main` |
|---|---|---|
| App shell / nav / toolbar | — | `UI/MainWindow.swift` (+ `ToolbarModel` for the per-page button sets) |
| Recording dock + stop pill | `FloatingOverlay.swift` (partly right) | `UI/MainWindow.swift` mounts `MeetingRecordDock` + `RecordingStopPill`; voice-note hover panel lives in `UI/FloatingOverlay.swift` |
| Today | `TodayView.swift` (right) | `UI/TodayView.swift` |
| Meetings list | `MeetingsView.swift` (right) | `UI/MeetingsView.swift` |
| **Meeting detail + tabs + Edit** | **`MeetingDetailHeader.swift` + `MeetingNotesTab.swift` (DO NOT EXIST)** | **`UI/UnifiedMeetingDetail.swift`** (one view; `MeetingTab` enum; modes `.live/.upcoming/.past`) |
| Notes editor | editable `MarkdownEditor.swift` (wrong) | `RichMarkdownEditor` = editable; `MarkdownEditor` = **read-only** renderer (summary) |
| Attendee → person | `MeetingDetailHeader.swift` | `MeetingPeopleRail` + `MeetingPersonConnectPanel` (used by `UnifiedMeetingDetail`) |
| People roster | `PeopleListView.swift` (right) | `UI`→`People/PeopleListView.swift` |
| Person profile + tabs + Edit | `PersonDetailView.swift` (right) | `People/PersonDetailView.swift` |
| Person create/edit modal | `AddPersonSheet.swift` (right) | `People/AddPersonSheet.swift` |
| Message analysis | `MessagesAnalyzer.swift` (right) | `People/MessagesAnalyzer.swift` |
| Tasks workspace | `ActionItemsView.swift` (right) | `UI/ActionItemsView.swift` |
| Tasks sub-nav | `ActionItemsSidebar.swift` (right) | `UI/ActionItemsSidebar.swift` |
| Tasks top bar / view switch | `ActionItemsChrome.swift` (right) | `UI/ActionItemsChrome.swift` |
| Tasks list / board | `ActionItemsListView.swift` / `ActionItemsBoardView.swift` | same (right) |
| Task property editing | "popover pickers" (no file) | `UI/ActionItemsPropertyDrawer.swift` + the board's inspector |
| Tasks view-model / filters | `ActionItemsViewModel.swift` (right) | `UI/ActionItemsViewModel.swift` |
| Voice Notes | — | `UI/QuickNotesView.swift` (store: `QuickNotes/QuickNoteStore.swift`) |
| Settings | `SettingsView.swift` (right) | `UI/SettingsView.swift` (opened via `SettingsLink`) |
| New meeting modal | "New-item modal" | `NewMeetingSheet` (presented from `MainWindow.swift`) |

Data layer (unchanged by this redesign): `People/Person.swift` + `People/PeopleStore.swift`;
`Models/Meeting.swift` + `Storage/MeetingStore.swift` + `MeetingManager.swift`;
`ActionItems/ActionItem.swift` + `ActionItems/ActionItemStore.swift` (+ `Project.swift`,
`Initiative.swift`); `QuickNotes/QuickNote.swift`. **No schema changes are required.**

---

## 3. Global chrome — `MainWindow.swift`  (mostly built)

The shell is a left **nav rail** (240px, `NDS.sidebarBg`) + a keep-alive `ZStack` of tab views +
an optional right **assistant rail** (`ChatSidebar`, default **closed**). The title bar carries a
page crumb (or a live **`RecordingStopPill`** while recording), browser-style back/forward
(`WorkspaceRouter`), and a **page-tailored toolbar**.

**Already built — verify, don't rebuild:**
- Nav rail with `WORKSPACE` (Today, Meetings, People) + `ORGANIZE` (Tasks, Voice Notes) groups, plus
  `Decisions` and `Integrations` sections that also exist in `TopLevelSection`. Active = lilac-soft
  pill; rail badges (`NavRailItem.Badge`) show overdue tasks (danger), drifting people (gold),
  finalizing meetings (pulse). Settings gear pinned bottom (`SettingsGearButton` → `SettingsLink`).
- **Page-tailored toolbar** via `ToolbarModel.items(for: section, isRecordingMeeting:)`. The button
  sets already match the comp: Today → Search · Voice note · **New meeting**; Meetings → Search ·
  Import calendar · **New meeting**; People → Search · Import · **Add person**; Tasks → Search ·
  Filter · **New task**; Voice → Search · **New voice note**. `runToolbarAction` wires each.
- **`RecordingStopPill`** ("Stop · MM:SS") in the title bar while a meeting records.
- **`MeetingRecordDock`** docked bottom-trailing when recording **and not on Meetings**
  (`RecordingPresentation.showsMeetingDock`). In-app only — never a system overlay.
- **Assistant rail default-closed** (`@AppStorage("chatRailVisible") = false`), auto-collapses under
  860px, toggled from the toolbar. ⌘K opens the floating `GlobalSearchView` palette.

**Remaining diff:**
- **GC-1 (P0 — currently broken):** the voice-note recording indicator is a **floating, gold-tinted,
  system-level hover pill** (an `NSPanel`, non-activating, floating window level, draggable via
  `setMovableByWindowBackground`) that sits above all apps — distinct from the in-app coral meeting
  dock. **The shipping version is broken: it's too narrow, so every label truncates** ("V…", "few
  se…", "C…", "O…" — see the attached screenshots). The corrected design is fully specced in
  **`prototype/VoiceNotePill.dc.html`** (open it; the switcher previews all three states), and it's
  wired into the shell (start a voice note → the pill appears bottom-center). Rebuild
  `UI/FloatingOverlay.swift` (`FloatingRecordingOverlay` / a new `VoiceNoteHoverPanel`) to match it.

  **Three states (one pill, ~410–466px wide, radius 18, warm near-black `linear-gradient(180deg,#221b1a,#191420)`, 1px `--gold` @ 26% border, soft gold glow, left drag-grip):**
  | State | Anatomy (left → right) |
  |---|---|
  | **Recording** | soft-red circle w/ pulsing `--danger` dot · "Voice note" + "Recording · M:SS" (gold, tabular) · animated **gold** waveform · red **stop** button (40×40, rounded) · ghost **×** (cancel/discard) |
  | **Transcribing** | gold spinner · "Transcribing" + "Whisper is running locally · usually a few seconds" (wraps to 2 lines — never truncate it) · ghost **×** |
  | **Saved** | green-mint check circle · "Voice note saved" + 1-line snippet (snippet may ellipsize; **title must not**) · **Copy** button · **Open** button (lilac) · ghost **×** |

  **Anti-truncation rules (this is the actual bug — enforce them):** the pill **sizes to its content**
  (don't pin a width too small for it); the text column is `flex:1; min-width:0` with **single-line
  ellipsis only on secondary text** (time, snippet) — **titles and button labels never truncate**;
  buttons and the waveform are `flex:0 0 auto`. SwiftUI: `.fixedSize()` / generous `idealWidth` on the
  panel, `.lineLimit(1).truncationMode(.tail)` on secondary text only, `.layoutPriority` so labels win
  over the snippet. Keep meeting recording strictly in-app (the coral `MeetingRecordDock`).
- **GC-2 (P2):** the app shell is still an opacity-`ZStack` tab switcher; the long-term direction
  (`MASTER_PLAN_V3` NAV-4) is a real `NavigationSplitView` with the rail as sidebar. Optional; not
  required for visual conformance.

---

## 4. Today — `TodayView.swift`  (partial)

Greeting (Bricolage 31px) + "date · N meetings · N tasks due". Two columns: **left** = live-recording
banner (if recording) with "Open & add notes" → opens the live meeting, then **Up next** meeting
cards (time · title · dur/attendees · status badge); **right** = **Due today** card (checkbox · title ·
due badge · owner avatar · "All tasks →") and **Reconnect** card (slipping/at-risk people + cadence
chip → opens person). Everything is click-through. See `screens/01` + prototype Today.

**Remaining diff (highest-signal; from `MASTER_PLAN_V3`):**
- **TDY-1 (P0):** opening a Today meeting card must **navigate into the shared
  `UnifiedMeetingDetail`** (select-into Meetings) with a back arrow — **delete the inline
  expand/collapse** (`expandedMeetingID`, `cardWithDetail`, `inlineDetail`, `toggle`, the "Collapse"
  button, `MeetingCard.isExpanded`, the forced `minHeight: 520`). This is the #1 fix the user notices.
- **TDY-2 (P0):** add an **"Up next" hero** at top — next meeting + countdown + attendees +
  "Open brief" + "Join & Record".
- **TDY-3 (P1):** a **"Needs attention"** block above the meeting list — overdue + due-today tasks +
  follow-ups not yet sent.
- **TDY-4 (P0):** remove the `920` width cap (`TodayView.swift:60`) — use full width (keep a ~720
  reading measure only for prose). See LAY-1.

---

## 5. Meetings — "Focused"  ·  list `MeetingsView.swift`, detail `UnifiedMeetingDetail.swift`  (mostly built)

**List (`screens/02`):** centered column, filter chips (All / Today / Upcoming / Past), time-grouped
sections **● NOW** (red) / **TODAY** / **UPCOMING** / **PAST · RECORDED**. Each row: live dot (if
recording) · tabular time · title + "dur · source" · attendee avatar stack · status badge · chevron.
Whole row opens the detail **as a full page** (Meetings is already a `NavigationSplitView`).

- **DEF-1 (P0):** default the scope to **`.upcoming`** and persist via
  `@AppStorage("meetings.scope")` — today it defaults to `.all` and resets each visit
  (`MeetingsView.swift:26`).
- **DEF-2 (P1):** make the list a focusable `List(selection:)` so ↑/↓/Enter work.

**Detail — `UnifiedMeetingDetail.swift` (already a single tabbed view; do NOT split into header/tab
files):** one view, `mode = .live | .upcoming(Meeting) | .past(Meeting)`. The `MeetingTab` enum is
already: `.brief` (label **"Summary"**), `.outcomes` (label **"Actions"**, badge = items needing
triage), `.notes`, `.transcript`, `.related`. Live recording defaults to **Notes**; past defaults to
Summary.

**Already built here — verify, don't rebuild:** breadcrumb back; title/date header; status-based
primary action (Join & record / Stop recording / Regenerate); **inline Edit** of header
(`editingHeader`, `titleDraft`, `descriptionDraft`); **attendee → person** via `MeetingPeopleRail` +
`MeetingPersonConnectPanel` (link-to-existing or add-as-new inline, ⌥⌘P toggles the rail);
tag changes via `tagStore`; live waveform / `LiveTranscriptScroll` while recording; Summary tab
(`MarkdownEditor` read-only render + Regenerate + edit-by-asking + feedback + **Draft follow-up**);
**Notes** tab (`RichMarkdownEditor` with `/` blocks + `@` mentions + "Push to-dos → Tasks");
**Outcomes/Actions** tab (`MeetingActionRow` full CRUD + "Add all N → Tasks" + "Add action item");
Transcript tab (`TranscriptSyncView`, speaker labels, click-to-seek); audio player.

**Remaining diff:**
- **MTG-1 (P1, "Edit mode" — `screens/04`):** surface **per-meeting capture toggles** (Microphone /
  System audio) in the header Edit state. The state already exists (`captureMicDraft`,
  `captureSystemDraft`, persisted via `manager.updateMeeting`) — render the two toggle chips when
  `editingHeader` is true, with the helper text "Capture sources for this meeting". This is where
  recording sources live now (out of global Settings — see §10).
- **MTG-2 (P1):** confirm the **tag add/remove** affordance in Edit mode matches the prototype
  (remove ×, "+ Tag" popover with free text + suggestions).
- **MTG-3 (P2):** promote **Draft follow-up** to the top of the Summary tab (DEF-3) — and wire
  "Open in Mail" (`mailto:`/`NSSharingService` prefilled from attendees).

---

## 6. People — "Roster + Profile"  ·  `PeopleListView.swift` + `PersonDetailView.swift`  (partial)

**Roster (`screens/05`, 312px):** "People" + **Add**, search, then groups **Colleagues / Clients /
Prospects**; each row = avatar tile · name · role · cadence dot. **Profile (right):** a **horizontal**
header — large avatar + name + "role · company" + tag row, right-aligned **Message · Log · Edit**;
below it a **horizontal facts strip** (Email, Phone, Location, Birthday, Cadence, First met); then the
**tabbed work area** = `PersonWork.dc.html` in the prototype → in the app this is the lower half of
`PersonDetailView.swift`: **Overview** (Memories, Favorite things, AI suggestions, At-a-glance),
**Meetings**, **Tasks**, **Messages** (stats + bars + Analyze), **Notes**.

**Already built — verify:** two-column layout with sticky identity panel; memories/encounters/
relationships add inline; `EncounterHeatMap`; `PersonAISuggestions`; `MessagesAnalyzer` ("Analyze
conversations" → local Ollama summary).

**Remaining diff (from `MASTER_PLAN_V3` — the headline People work):**
- **PPL-1 (P0):** make the **identity-panel fields click-to-edit in place** (name, role, company,
  email, bio), autosave on blur — **mirror the meeting header's `editingHeader` pattern**. Reserve
  `AddPersonSheet.swift` for **first-create only**; today quick edits are modal-only
  (`PersonDetailView.swift:342`). The prototype shows the inline Edit toggle (`screens/06`).
- **PPL-2 (P1):** **multi-value** emails/phones/addresses with +/− and work/home labels — stop
  dropping the 2nd value via `replacingFirst`. Prototype shows "+ Add email" inline.
- **PPL-3 (P1):** make identity tag chips **tappable to filter** the roster; add tags inline with
  remove × + an add-tag popover (free text + suggestions), like the meeting tag editor.
- **PPL-4 (P1):** the person's **Meetings tab should show all calendar meetings** with them, not only
  recorded ones (1:1s often aren't recorded → tab reads empty). Add "Add {name} to a meeting".
- **PPL-5 (P2):** rename the bio section "Notes" → **"About"** to end the collision with attached
  analyses (`PersonDetailView.swift:537` vs `:816`).
- **LAY (P0):** remove the `720` width cap (`PersonDetailView.swift:277`) — full width, prose measure
  only for long text.

The **Analyze…** popover (prototype Messages tab) maps onto `MessagesAnalyzer.analyze`. If you build
the full scope/preset popover (relationship summary / sentiment / topics / style / pending items /
custom prompt, with time-range chips), add a `since: Date?` parameter to `analyze` and filter the SQL
by `message.date >= since`; map Last 30/90d / 6mo / Year / Recent 1000 / All time to the cutoff.

---

## 7. Tasks — "Inspector"  ·  `ActionItemsView.swift` (+ sidebar/chrome/list/board/property-drawer)  (mostly built)

Header "Tasks" + meta + filter chips (All / Mine / From meetings [count] / Done). Main area = a
**3-lane board** (To do · In progress · Completed); each card = project + meeting badges, title,
priority + due badges, owner avatar. Selecting a card loads it in a **persistent right inspector**
(380px) = `TaskDetail.dc.html` in `inspector` layout; "Full view" expands it. See `screens/07`.

**Already built — verify:** the board (`ActionItemsBoardView.swift`), list
(`ActionItemsListView.swift`), the sub-nav (`ActionItemsSidebar.swift`) with smart views + projects +
initiatives, the chrome/view-switcher (`ActionItemsChrome.swift`), filters + triage
(`ActionItemsViewModel.swift`), and the property editor (`ActionItemsPropertyDrawer.swift`).

**Remaining diff — the core "clunky edit" fix (prototype `TaskDetail.dc.html`):**
- **TSK-1 (P0):** in the inspector, each property row must be a **pill that opens a popover picker** —
  **Status** (To do / In progress / Completed, colored dot), **Priority** (High / Medium / Low,
  arrow/dash/dot), **Due** (Today / Tomorrow / Wed / Fri / Next week / No date), **Project** (project
  list / No project), **Assignee** (You + roster avatars). Current value checked; pick updates
  immediately and closes. Build/reconcile this in `ActionItemsPropertyDrawer.swift` — no separate edit
  screen, no modal-in-modal.
- **TSK-2 (P1):** title inline-editable (contenteditable equivalent); **Subtasks** add via an inline
  "Add subtask… (Enter)" row with a live progress bar; an **Activity** timeline below.
- **TSK-3 (P1):** tasks extracted from meetings show a lilac **"Extracted from <meeting>"** chip that
  links back to the meeting; the owner avatar links to the person (`ActionItem.meetingID` /
  `ownerToken` already exist).

---

## 8. Voice Notes — `QuickNotesView.swift`  (verify against comp)

**List (300px):** "Voice Notes" + a big coral **New voice note** button; rows = waveform icon · title ·
"date · duration". **Detail:** title/date/duration, audio player (play, progress, speed), **AI
summary**, **Transcript** card, **"Push → Tasks"**. **Recording state (`screens/09`):** the New button
turns red ("Stop recording"); a centered card shows "RECORDING · 00:08", an animated live waveform,
and **"Stop & transcribe"**. Recording is driven by `manager.startQuickNote()` / `stopQuickNote()`
(already wired from the toolbar). Reconcile `QuickNotesView.swift` layout/spacing to the prototype.

> The **floating system-level pill** that appears while a voice note records/transcribes/saves (above
> all apps, not inside this page) is a separate component — see **§3 GC-1** and
> **`prototype/VoiceNotePill.dc.html`**. It is currently broken (truncating) and is **P0**.

---

## 9. New-item modal — `NewMeetingSheet` + `AddPersonSheet.swift` + inline task create  (verify)

The prototype shows **one** context-aware modal (`screens/11`); the app implements it as **per-type
sheets**, which is fine — keep them, just reconcile styling to the comp:
- **New meeting:** Title · When · Capture sources (Microphone / System audio chips) → `NewMeetingSheet`
  (presented from `MainWindow.swift`, `showNewMeeting`).
- **Add person:** Name · Role & company · Relationship (Colleague / Client / Prospect) →
  `AddPersonSheet.swift` (`activeSheet = .addPerson`, also from the People roster "Add").
- **New task:** the toolbar "New task" currently switches to Tasks and calls
  `actionItems.createTask("New task")`. To match the comp, present a small sheet (Task · Priority ·
  Due) **and auto-open the new task focused for rename** (TDY-5) instead of dropping an "Untitled".

---

## 10. Settings — `SettingsView.swift`  (verify; per-meeting capture moved onto the meeting)

A single Settings scene (opened via the rail gear → `SettingsLink`) with a left category rail and a
right detail pane of grouped rows (label/description + a toggle or value-pill). Categories
(`screens/10`): **General · Recording · Transcription · AI & Summaries · Integrations · MCP Server**.
Notable:
- **Recording** holds **default** sources + automation (auto-start, detect Zoom/Meet). **Per-meeting**
  sources now live on the meeting Edit mode (§5, MTG-1) — do **not** duplicate them here.
- **Transcription** = whisper.cpp model + live transcript. **AI** = Ollama model + auto-summarize.
- **Integrations** = the connectors in `IntegrationsView.swift`. **MCP Server** = install in Claude
  Desktop + allow write tools (the 5 write tools are already implemented — see README MCP section).
- Everything is local-first (no API keys / outbound).

---

## 11. Data model (matches the existing stores — no schema changes)

- **Person** → `People/Person.swift` / `People/PeopleStore.swift`: id, name, role, company, emails[],
  phone, location, relationship (Colleague/Client/Prospect), tags[], firstMet, cadence + cadenceDays +
  lastSpokeDays, birthday, favorites[], memories[], message stats.
- **Meeting** → `Models/Meeting.swift` / `Storage/MeetingStore.swift` / `MeetingManager.swift`: id,
  title, startDate, attendees, conferenceURL, tags, status (recording/scheduled/summary/transcribed),
  `captureMic`/`captureSystem` (per-meeting overrides).
- **Task / ActionItem** → `ActionItems/ActionItem.swift` / `ActionItemStore.swift`: id, title, status,
  priority, due, project, owner (`me` | personRef), `meetingID`, `needsTriage`. Subtasks, activity.
  `Project.swift`, `Initiative.swift`.
- **Voice note** → `QuickNotes/QuickNote.swift` / `QuickNoteStore.swift`: id, title, date, duration,
  summary, transcript.

---

## 12. Build order (closes the user's complaints fastest)

This sequence front-loads the changes the user feels immediately, then the data-integrity fixes from
`MASTER_PLAN_V3` (those are independent of this UI work and remain P0 on their own).

1. **Nav model + width (P0):** TDY-1/TDY-4 (kill Today's inline expand → click-into `UnifiedMeetingDetail` + back; remove 920 cap), LAY person 720 cap, DEF-1 (Meetings upcoming-first). Closes "never collapse/expand" + "full width" + "defaults".
2. **Inline editing (P0):** PPL-1 (person fields click-to-edit, retire the modal for quick edits), TSK-1/TSK-2 (task property popovers + subtasks/activity), MTG-1 (per-meeting capture toggles in Edit mode). Closes "easier to edit / clunky selection".
3. **Today depth (P0/P1):** TDY-2 (up-next hero), TDY-3 (needs-attention).
4. **People depth (P1):** PPL-2/3/4/5; the Analyze… scope popover.
5. **Polish + the broken pill:** **GC-1 (P0 — rebuild the floating voice-note hover pill to the
   3-state spec; it currently truncates every label)**, MTG-3 (follow-up to top + Open in Mail),
   Voice/Settings/New-modal styling reconcile, LAY-4 (`NSColor` → `NDS`). GC-1 is independent — do it
   as soon as convenient.
6. **Data integrity (independent P0 — see `MASTER_PLAN_V3` §3.6):** live-transcript truncation,
   vault migration, finalize/transcribe race, model checksum, recording-state bug. Not UI, but the
   highest-stakes work in the repo.

> When `main` already matches the prototype (most of §3, §5, §7), **leave it** and reconcile only
> spacing / header structure / the editing affordances called out above. Treat the prototype's
> hierarchy and interaction flow as the spec; reuse the existing stores and `MSComponents`.

---

## 13. Responsive & adaptive layout — REQUIRED for every screen

The prototype is drawn at a fixed **1440×900** window so you can read exact spacing — **it is a
reference frame, not a fixed size**. Every screen you build or touch must **fit any window size and
reflow gracefully**, from a narrow ~700px window up to an ultra-wide display. This is a hard
requirement, not polish: no horizontal scrollbars on the app frame, no clipped panes, no content
hidden under the toolbar, nothing pinned to a width that overflows.

### 13.1 Hard rules (SwiftUI)
- **No fixed pixel widths on content.** Replace `.frame(width:)` on panes/cards/lists with
  `.frame(minWidth:, idealWidth:, maxWidth:)` and `.frame(maxWidth: .infinity)` for fill. Fixed widths
  are only allowed for genuinely fixed chrome (nav rail 240, an inspector's *ideal* width) — and even
  those use `minWidth/idealWidth/maxWidth` so they can shrink, never a bare `width:`.
- **Remove the content-width caps** (`NDS.contentMaxWidth = 720`, `TodayView:60` 920,
  `PersonDetailView:277` 720). Keep a reading measure (~`min(width − gutters, 720)`) **only** for long
  prose (summary/transcript). Everything else uses the full width. (LAY-1.)
- **Every horizontal group of chips/badges/buttons/tags must wrap** — use the existing `FlowLayout`
  (already in the codebase) or `ViewThatFits`, never a single non-wrapping `HStack`. Applies to:
  attendee chips, tag rows, filter chips, facts strip, favorite-things, toolbar button sets, task
  badges, the New-item chip groups.
- **Text must truncate or wrap, never push layout.** Titles/names: `.lineLimit(1)` +
  `.truncationMode(.tail)` inside a `minWidth: 0` flexible container. Body/prose: wrap with
  `.fixedSize(horizontal: false, vertical: true)`. Give flexible children `minWidth: 0` so a long
  string can't inflate a row past the pane (this is the SwiftUI equivalent of `min-width:0` on a flex
  child — the #1 cause of overflow).
- **Multi-pane screens collapse by breakpoint** (see 13.3). A 3-pane screen (roster · profile · tabs;
  or board · inspector) must drop panes as width shrinks rather than squeezing them all.
- **Scroll regions are bounded.** Each pane owns its own `ScrollView`; never let an inner
  self-scrolling AppKit view (transcript, `RichMarkdownEditor`) sit in an unbounded outer scroll — give
  it a `GeometryReader`-derived height (the pattern already used in `UnifiedMeetingDetail`).
- **Drive layout off available size, not the screen.** Use `GeometryReader` / container size and
  size classes, not `NSScreen` — so the app reflows when the user resizes the *window*, not just on
  different displays.

### 13.2 The same rules, in the prototype's CSS terms (so the comp and the app agree)
The prototype already follows most of these; honor them as you translate and when editing the
`.dc.html` files:
- Containers fill with `flex:1; min-width:0;` (the `min-width:0` is mandatory on every flex child that
  holds text — it's why titles ellipsize instead of stretching the row).
- Chip/tag/badge/button rows use `display:flex; flex-wrap:wrap; gap:…` — **never** rely on inline-block
  + whitespace.
- Panels that fill use `max-width:100%` and a flexible basis; the reading-measure prose blocks use
  `max-width:720px`.
- Truncation: `overflow:hidden; text-overflow:ellipsis; white-space:nowrap;` for single-line labels;
  natural wrapping (+ `text-wrap:pretty`) for paragraphs.
- Grids that must reflow use `grid-template-columns: repeat(auto-fit, minmax(<min>, 1fr))` so columns
  collapse instead of overflowing (e.g. the Today two-column area, the facts strip, the message-stats
  row).
- Use `gap` for spacing between siblings, not per-child margins, so wrapping stays even.

### 13.3 Breakpoints (window/container width)
Adapt at these widths (they line up with the existing 860px chat-rail auto-collapse in
`MainWindow.swift`):

| Width | Behavior |
|---|---|
| **≥ 1200px (regular)** | Full multi-pane: nav rail + content (+ inspector/people-rail) + optional assistant rail. Prototype baseline. |
| **860–1200px** | Assistant rail auto-hides (already implemented). Tasks inspector and the meeting people-rail become **toggle-on overlays** rather than always-on columns. People stays roster + profile but the profile work-area tabs may stack. |
| **700–860px** | Collapse to **two panes max**: a list/roster pane + a detail pane (detail can present as a pushed page with a back arrow). Facts strips and stat rows wrap to multiple lines. |
| **< 700px (compact)** | Treat as **mobile/compact** — see §14. Single column, navigation becomes a bottom tab bar / menu, details are full-screen pushes, inspectors become sheets. |

When in doubt, prefer **stacking** (vertical) over **shrinking** (squeezing columns below their
content's minimum).

---

## 14. Mobile / compact layout — REQUIRED (the app is also reached from a phone)

When the horizontal size class is **compact** (iPhone, a narrow window, or the app surfaced on a
phone), the multi-pane Mac layout does not work — adapt it. Gate this on
`horizontalSizeClass == .compact` (or container width `< 700px`), not on OS, so a narrow Mac window
gets the same treatment.

### 14.1 Navigation
- Replace the **left nav rail** with a **bottom tab bar** (Today · Meetings · People · Tasks · Voice)
  — the same 5 primary `TopLevelSection`s. Move Decisions / Integrations / Settings into a "More"
  tab or the top-bar overflow.
- Replace every **side-by-side list+detail** with a **navigation stack**: tapping a row **pushes** the
  detail full-screen with a back button (Meetings list → meeting; roster → person; task list → task).
  No split view, no persistent inspector.
- The **task inspector** and the **meeting people-rail** become **bottom sheets / pushed screens**, not
  columns. The Tasks board scrolls **lanes horizontally** (snap), or switches to the single-column List
  view by default on compact.

### 14.2 Sizing, touch & type
- **Touch targets ≥ 44×44pt.** Bump the prototype's compact controls (28–30px toolbar buttons, 16–18px
  checkboxes, small chips) up to ≥44pt hit areas on compact — use padding to grow the tappable area
  without necessarily enlarging the glyph.
- **Type scale up** one step on compact for body/labels; keep Bricolage display sizes but allow them to
  shrink with `minimumScaleFactor(0.85)` and wrap. Respect Dynamic Type — use relative font styles, not
  only fixed point sizes.
- **Full-width content**, comfortable gutters (16pt). Cards go edge-to-edge with internal padding.
- **Popover property pickers → action sheets / menus.** The task Status/Priority/Due/Project/Assignee
  popovers (TSK-1) present as native sheets/menus on compact, not anchored popovers.
- **Modals are full-screen** (or large detents) on compact — New meeting / Add person / New task /
  Settings become full-screen covers or `.sheet` with `.presentationDetents([.large])`, not the
  centered 520px desktop card.
- **Assistant** is a full-screen modal, never a side rail.

### 14.3 Reflow specifics per screen (compact)
- **Today:** single column — up-next hero, then "needs attention", then meetings, then due-today /
  reconnect stacked. No two-column grid.
- **Meetings:** list → push to `UnifiedMeetingDetail`; the tab rail (Summary/Notes/Actions/Transcript)
  becomes a top **segmented control / scrollable tab strip**; the people-rail is a sheet.
- **People:** roster → push to profile; the horizontal header stacks (avatar over name over actions);
  the facts strip becomes a 2-up wrapping grid; work-area tabs become a scrollable tab strip.
- **Tasks:** default to **List** view (not Board); tapping a task pushes the detail; property editors
  are sheets/menus.
- **Voice Notes:** list → push to detail; record state is a full-width card.

### 14.4 Honor safe areas & inputs
- Respect top/bottom safe-area insets (notch, home indicator); keep the bottom tab bar above the home
  indicator.
- Keep interactive content clear of the keyboard (`.scrollDismissesKeyboard`, avoid fixed bottom bars
  overlapping the keyboard).

> If the phone surface is a **web** view of this design rather than a native iOS target, the same
> §13/§14 rules apply in CSS: a mobile-first stylesheet, `@media (max-width: 700px)` to switch the rail
> to a bottom tab bar and split views to single-column stacks, `min-height: 44px` hit targets,
> `env(safe-area-inset-*)` padding, and `flex-wrap`/`auto-fit` grids throughout.
