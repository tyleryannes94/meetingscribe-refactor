# Handoff: MeetingScribe — UX Redesign v2

## Overview
A full UX redesign across four major areas of MeetingScribe, building on the approved "Bloom"
visual language (plum-ink base, coral primary, lilac brand, mint/sky/gold semantics, Bricolage
Grotesque display / Plus Jakarta Sans body). The work is additive to the Bloom visual overhaul
already handed off in `design_handoff_bloom_redesign/`.

**Areas covered:**
1. **Toolbar** — Named, page-tailored top-right buttons; separate recording indicators per source
2. **Meetings** — Smart meeting list grouping; Notion-parity notes editor; Notes + Actions tabs; push action items → Tasks; attendee click-through to People
3. **People** — Full two-pane redesign; tabbed work area; custom `Analyze…` scope + preset popover; add-email inline; add person to meeting
4. **Tasks** — Unified workspace: Triage inbox (meeting action items), smart views mixing projects, List / Board / Calendar in one place; 2-way links to Meetings & People

## Design Files
The prototype at `MeetingScribe Prototype.html` is a **high-fidelity HTML/React design reference** — not production code. Implement it in SwiftUI using the existing component layer (`NotionDesign.swift`, `MSComponents.swift`, `MSAvatar.swift`, the `NDS` token system). Every token value, color, radius, and typeface below is final.

See `../design_handoff_bloom_redesign/README.md` for the base Bloom token sheet (colors, radii, typography, motion). This document describes only the UX changes layered on top.

---

## 1. Toolbar — Named, Page-Tailored Top-Right Buttons

### Current state
Unlabeled icon-only buttons across all pages (search, mic, record, download, video, refresh).

### Target state
Buttons are **named and contextual** — the set changes per page. Recording states surface directly in the toolbar.

### Button sets per page

| Page | Buttons (left → right) |
|---|---|
| Today | `Search` · divider · `Voice note` (mic) · `Record` (red rec dot) · **`New meeting`** (coral primary) |
| Meetings | `Search` · `Import calendar` · divider · `Record` (red) · **`New meeting`** (coral primary) |
| People | `Search` · `Import` · divider · **`Add person`** (coral primary) |
| Tasks | `Search` · `Filter` · divider · **`New task`** (coral primary) |
| Voice Notes | `Search` · divider · **`New voice note`** (coral primary) |

**When a meeting is actively recording:** inject a `● Stop recording` button (red tint — `--danger` bg/border, pulsing red dot) as the leftmost item before the other buttons. This replaces any separate "Stop recording" UI inside the meeting detail.

### Implementation
- **File:** `Sources/MeetingScribe/UI/MainWindow.swift`
- Read `WorkspaceRouter.currentRoute` to switch button sets.
- Each labelled button: `MSLabelledToolbarButton(icon: SFSymbol, label: String, style: .ghost | .primary | .recording)`.
- Primary (coral gradient) = `MSPrimaryButtonStyle` at height 28, radius 9, font 12.5/600.
- Recording state = `NDS.danger` tint. Pulse the dot with `NDS.motion(.easeInOut, reduce: false)`.
- Keep the existing `⌘K` shortcut and chat toggle icon (unlabelled) at far right.

---

## 2. Recording Indicators — Two Distinct Treatments

### Rule
**Meeting recording** = in-app only, never a system-level hover overlay.
**Voice note** = floating system-level pill that sits above all apps.

### 2A. Meeting recording — docked in-app bar

Shown in the bottom-right of the app window **when recording a meeting and the user is NOT on the Meetings tab.** When they navigate to Meetings, this bar hides (the detail header already shows the live state).

**Anatomy (Style A — default):**
```
┌──────────────────────────────────────────┐
│  3px gradient top bar (danger → accent)  │
│  ●REC  RECORDING MEETING    1:23         │
│  Product × Design – Do not book over     │
│  Maya, Sam, Jules · System + Mic         │
│  [~~~~~~waveform~~~~~]  [Open & add notes] [■] │
└──────────────────────────────────────────┘
```
- Width: 308px, radius 16, `NDS.surfaceOverlay` fill, `NDS.danger` border @ 38% alpha, blur 10
- Top accent bar: 3px, `linear-gradient(90deg, --danger, --accent)`
- Waveform: `AudioLevelMeter` component (already exists), stroke `--danger` @ 70% alpha
- "Open & add notes" → `MSPrimaryButtonStyle .xs` → navigates to the live meeting note
- Stop icon → ghost `.xs` → calls `AudioRecorder.stop()`

**Style B (Tweak variant):** pill-shaped compact bar: `[●] 1:23 · Meeting title [Notes] [■]`
- All on one line, border-radius 999, bg `NDS.surface2`, border `NDS.danger` @ 40%

**Placement:** SwiftUI `.overlay(alignment: .bottomTrailing)` on the main window content area, padding 18pt, `z-index` above content but below sheets.

**File:** `Sources/MeetingScribe/UI/FloatingOverlay.swift` — add `MeetingRecordDock` view. Condition: `audioRecorder.isRecording && router.currentRoute != .meetings`.

### 2B. Voice note — floating hover pill

A `NSPanel` (non-activating, floating window level) that sits above all apps, draggable, gold-tinted.

**Anatomy (Style A):**
```
┌──────────────────────────────┐
│  ≡≡ VOICE NOTE · OVER ANY APP│  ← drag handle, 10px letter-spacing, gold
│  🎤  ~~waveform~~  0:32      │
│  [✓ Save note]   [🗑]        │
└──────────────────────────────┘
```
- Width: 236px, radius 14, `rgba(34,26,8,.96)`, border `--gold` @ 45% alpha, shadow + outer glow `--gold` @ 10%
- Drag: `-[window setMovableByWindowBackground:YES]` on the panel
- Save → transcribes and saves to `QuickNoteStore`; Discard → cancels

**Style B:** minimal gold circle/pill `[🎤 0:32 [■]]`, fully rounded

**File:** `Sources/MeetingScribe/UI/FloatingOverlay.swift` — extend existing `FloatingRecordingOverlay` (or create `VoiceNoteHoverPanel` as a companion `NSPanel`). Keep meeting recording strictly in-app.

---

## 3. Meetings — Smart List + Notion Editor + Actions tab

### 3A. Meeting list sidebar — smart grouping

Replace the flat list with pinned groups. The existing `All / Upcoming / Past` filter tabs become a **secondary mode** (Variant B). Default (Variant A) is always-grouped:

```
● NOW  (if recording — always shown regardless of filter)
  └─ Product × Design… [● live dot]

TODAY
  └─ Product Sync — Skio  10:30 · 3 att · [●]
  └─ Skio Analytics Sync  10:00 · 2 att · [●]

UPCOMING TODAY
  └─ Planning Call — Q3  2:00 PM · 60m
  └─ Recharge Standup     4:00 PM · 30m

PAST · RECORDED
  └─ Contract review  Jun 2 · [●] summary
  └─ 1:1 Devon        Jun 8 · [●] summary
```

Section headers: `NDS.eyebrow` style (11pt/700/uppercase/`NDS.textTertiary`). "NOW" header color = `NDS.danger`.
Selected row: `NDS.lilac-soft` bg + `NDS.lilac` @ 32% border.
Live row: pulsing red dot on the right edge.

**File:** `Sources/MeetingScribe/UI/MeetingsView.swift`  
Refactor the list into `MeetingListSection` views. Source groups from `MeetingStore` using computed `todayMeetings`, `upcomingMeetings`, `pastMeetings` (already available).

### 3B. Meeting detail — tab changes

Add two new tabs and reorder:

| Order | Tab | New? |
|---|---|---|
| 1 | Summary | existing |
| 2 | **Notes** | **redesigned** |
| 3 | **Actions** | **new** |
| 4 | Transcript | existing |
| 5 | Ask AI | existing (Chat) |

Badge on Actions tab: count of unconfirmed/unpushed action items.

When recording is live, default to **Notes** tab instead of Summary.

**File:** `Sources/MeetingScribe/UI/MeetingDetailHeader.swift` + the five tab view files.

### 3C. Notes tab — Notion-parity editor

The existing `MarkdownEditor` needs a visual upgrade to match Notion's feel.

**Toolbar (always visible above the editor):**
```
[H1] [H2] [H3] | [B] [I] [<>] ["] | [• list] [1. list] | [@ link] [⊞] | [/]
```
- Row of ghost `.xs` buttons, 7px gap, 1px dividers between groups
- H1/H2/H3: weight 800 labels; B = bold label; I = italic label; others = SF Symbol icons
- `/` button: monospace, triggers the block-type command menu

**Floating selection toolbar:** appears 8pt above selected text.
```
[B] [I] [U] | [🔗 Link]
```
- `NSPanel` or `popover` anchored to selection rect, auto-dismissed on deselect

**Editor area:** `NSTextView` (already used in `MarkdownEditor.swift`) styled:
- Font: Plus Jakarta Sans 14pt, `NDS.textPrimary`
- Line height: 1.8× (set via paragraph style)
- Caret: `NDS.accent` (coral)
- Min height: expands to fill tab body
- Placeholder: `"Type / for blocks, @ to link a meeting or person…"` in `NDS.textTertiary`

**Push to Tasks button:** appears below editor when content is non-empty:
```
[→ Push notes → Tasks]  [↓ Export]
```
→ Parses editor content for action-item-like lines (starts with `- [ ]` or `TODO:`) and creates draft `ActionItem` objects routed to `ActionItemStore`, pre-associated with this meeting.

**Files:** `Sources/MeetingScribe/UI/MarkdownEditor.swift`, `Sources/MeetingScribe/UI/MeetingNotesTab.swift`

### 3D. Actions tab

Dedicated tab showing all `ActionItem` objects extracted from this meeting.

**Layout:**
```
ACTIONS FROM THIS MEETING                [Push all 2 → Tasks]
────────────────────────────────────────
☐  Circulate revised contract terms     Wed · Devon → [→ Tasks]
☐  Build usage-based pricing model      Fri · Jules → [→ Tasks]
☑  Share recording link                 Done         [✓ In Tasks]
                                        [+ Add action item]
```

- Each row: `TaskCheckbox` + title + `DueChip` + owner `MSAvatar` + push button
- "→ Tasks" button: creates confirmed `ActionItem` in `ActionItemStore`, marks it pushed (shows "✓ In Tasks" badge)
- "Push all N → Tasks": bulk-pushes all unchecked, unconfirmed items
- Check = toggle `ActionItem.isCompleted`
- "+ Add action item": inline text field that creates a new `ActionItem` for this meeting

**Files:** `Sources/MeetingScribe/UI/MeetingNotesTab.swift` (rename to `MeetingActionsTab.swift` or add alongside)

### 3E. Attendee chips → person deep-link

Each attendee chip in `MeetingDetailHeader` should be **tappable**:
- Tap → look up `Person` by email in `PeopleStore` → if found, navigate to `PersonDetailView`
- If email not in PeopleStore, chip shows `+ People` badge → tap opens `AddPersonSheet` pre-filled with name/email from the calendar invite

**File:** `Sources/MeetingScribe/UI/MeetingDetailHeader.swift`

---

## 4. People — Two-Pane Redesign

### Layout change

The current single-column scroll (14 stacked sections) is replaced with a **two-pane** layout:

```
┌──────────────┬─────────────────────────────────────────────────────┐
│  People list │  Identity / Contact left pane  │  Tabbed work area  │
│  (288px)     │  (Variant A: 288px, B: 240px)  │  (fills remaining) │
└──────────────┴──────────────────────────────────────────────────────┘
```

### 4A. Identity / Contact — fixed left pane

Always-visible, non-scrolling summary of the person.

**Sections (top to bottom):**
1. **Avatar** — `MSAvatar` 64×64 (radius 18)
2. **Name** — Bricolage 20pt/800; **Role · Company** — 12.5pt `NDS.textSecondary`
3. **Tag chips** — `NDS.chip .t-gray`, wrapping row
4. **Cadence nudge card** — shown only when `cadence != .healthy && cadence != .new`:
   - Gold-bordered card (`NDS.warn` @ 28% alpha border)
   - "Last spoke Nd ago · usually every Nd" + `[Reconnect]` primary button
5. **Quick actions row** — `[Log encounter]` `[Suggest]` secondary `.xs`
6. **CONTACT section:**
   - Email rows (each clickable `mailto:`). Primary email gets a "primary" micro-badge.
   - `+ Add email` button (inline, opens `AddEmailPopover`)
   - Phone (clickable `tel:`)
   - Location, Birthday, First met — icon + label rows, 12.5pt
7. **CADENCE section:**
   - Status badge (`Healthy`/`Slipping`/`At risk`) + "every ~Nd" label
   - 13-week encounter heatmap: `EncounterHeatMap` component (already exists — just surface it here at compact size, 16×16 cells, 3px gap)

**Add-email popover:**  
`NSPopover` / SwiftUI `.popover`, contains a single `TextField` + `[Add]` / `[Cancel]`. On confirm, calls `PeopleStore.addEmail(to: person, email: newEmail)`.

**File:** `Sources/MeetingScribe/People/PersonDetailView.swift` — split current single-view into `PersonIdentityPane` + `PersonWorkPane`.

### 4B. Tabbed work area

Five tabs replacing the current section-jump scroll rail:

| Tab | Contents |
|---|---|
| **Overview** | Memories (editable note cards) + Favorite things (heart chips) + AI suggestions card |
| **Meetings** | `meetingHistorySection` + `mentionedInSection` from current view, redesigned as clickable cards. Add `[Add {name} to a meeting]` button at top. |
| **Tasks** | `tasksSection` from current view. Shows tasks where `ownerMatchesPerson`. Add `[New task for {name}]`. |
| **Messages** | Stats card (total/reply cadence/you-initiate/last-30d) + bar chart + `Analyze…` button |
| **Notes** | `memoriesSection` + `attachedNotesSection` merged, with `NSTextView` quick-add at top |

Use `MSSegmentedTabBar` (or adapt existing tab bar component) with pill-style active tab (coral gradient fill).

**File:** `Sources/MeetingScribe/People/PersonDetailView.swift`

### 4C. Analyze… popover — full scope + preset

Replace the current single "Analyze messages" button with an `Analyze…` button that opens a structured popover:

**Popover (320pt wide, `NDS.surface` bg, radius 16, shadow):**

```
Analyze messages                              [×]
────────────────────────────────────────────
WHAT TO ANALYZE
  ○ Relationship summary        (heart icon)
  ○ Sentiment & trends          (chart icon)
  ● Topics & themes             (tag icon)
  ○ Communication style         (chat icon)
  ○ Pending action items        (checklist)
  ○ Custom prompt…              (pencil)

[custom text field — shown only when "Custom" selected]

TIME RANGE
  [Last 30d] [Last 90d] [Last 6mo] [This year] [Recent 1000] [All time]
  (pill toggle chips — minichip style)

────────────────────────────────────────────
          [✦ Run analysis]  ← coral primary full-width
```

On "Run analysis": call `MessagesAnalyzer.analyze(person: person, recentLimit: scopeLimit)` with the correct `recentLimit` value for the selected scope, then pass the resulting snippets + stats to Ollama with the selected preset's prompt template from `ConversationAnalysisPreset.template(personName:)`.

**Scope → `recentLimit` mapping:**
```swift
switch scope {
  case .last30:     cutoff = Date().addingTimeInterval(-30*86400)
  case .last90:     cutoff = Date().addingTimeInterval(-90*86400)
  case .last6mo:    cutoff = Date().addingTimeInterval(-180*86400)
  case .year:       cutoff = Date().addingTimeInterval(-365*86400)
  case .recent1000: recentLimit = 1000  // existing path
  case .allTime:    recentLimit = 100_000  // existing path
}
```
Note: `MessagesAnalyzer.analyze` currently takes `recentLimit` (message count). For date-based scopes, add a `since: Date?` parameter to the function and filter by `message.date >= since` in the SQL query.

**Files:** `Sources/MeetingScribe/People/PersonDetailView.swift`, `Sources/MeetingScribe/People/MessagesAnalyzer.swift`

### 4D. Add person to meeting (Meetings tab in person detail)

In the **Meetings tab** of the person detail, add a `[Add {name} to a meeting]` button at the top.
Tap → sheet listing upcoming meetings from `MeetingStore`. Select one → calls `MeetingStore.addAttendee(email: person.primaryEmail, to: meeting)`.

**File:** `Sources/MeetingScribe/People/PersonDetailView.swift`

---

## 5. Tasks — Unified Workspace

### Current state
Tasks are split across `ActionItemsBoardView`, `ActionItemsListView`, `ActionItemsTableView`, `ActionItemsCalendarView`, `ActionItemsGalleryView` with a projects sub-nav. Meeting-extracted action items require manual discovery.

### Target state
One unified workspace with:
- A **Triage inbox** that surfaces meeting-extracted, unconfirmed action items for fast review
- **Smart views** (My day, This week, Overdue) that work across all projects
- Projects and Initiatives mixed into one sub-nav — no separate database views required
- Same List / Board / Calendar switch, but always accessible from any smart view

### 5A. Sub-navigation (unified sidebar)

Replace the current projects-only sub-nav with a two-section structure:

```
WORKSPACE
  📥 Triage inbox        [3]   ← unconfirmed fromMeeting items
  ≡  All tasks           [5]
  ☀  My day              [1]
  📅 This week           [4]
  ⚠  Overdue             [1]   ← danger badge

PROJECTS
  ●  Skio Integration    [3]
  ●  Q3 Roadmap          [1]
  ●  Onboarding revamp   [1]
  [+ New project]

INITIATIVES
  ⊞  Growth FY26
```

Active row: `NDS.accent-soft` bg + `NDS.txt` weight 700.
Overdue count: `NDS.danger` tint badge.
Triage count: `NDS.accent` (coral) tint badge.

**File:** `Sources/MeetingScribe/UI/ActionItemsSidebar.swift`

### 5B. Triage inbox view

When "Triage inbox" is selected, the main area shows **unconfirmed meeting-extracted tasks** awaiting review.

```
FROM YOUR MEETINGS                [coral header band, NDS.accent-soft bg]
──────────────────────────────────────────────────────────────────────
✦  Follow up with Maya on pricing     Thu · maya@skio.com
   ↳ From: Product Sync — Skio        [Project ▾]  [✓ Add]  [🗑]

✦  Send Theo the security one-pager   Wed · theo@northwind.io
   ↳ From: Theo / intro                [Project ▾]  [✓ Add]  [🗑]

✦  Book Q3 roadmap readout            · me
   ↳ From: Skio Analytics Sync        [Project ▾]  [✓ Add]  [🗑]
```

- Each row: sparkle icon + title + due badge + owner avatar + meeting source chip + `[Project]` dropdown + `[Add]` + `[Discard]`
- `[Add]` → sets `ActionItem.isConfirmed = true`, moves to confirmed tasks
- `[Project ▾]` → popover listing projects → sets `ActionItem.projectID`
- `[Discard]` → deletes item from store
- `[Push all N → Tasks]` button in header bulk-confirms all

**Source data:** `ActionItemStore.pendingTriage` — items where `isConfirmed == false && meetingID != nil`.

**File:** `Sources/MeetingScribe/UI/ActionItemsView.swift` + `ActionItemsViewModel.swift`

### 5C. Smart views — mixed-project lists

When "All tasks", "My day", "This week", or "Overdue" is selected, show tasks across ALL projects in grouped sections:

```
● IN PROGRESS  (2)
  [task card]
  [task card]

● TO DO  (3)
  [task card]
  ...

● COMPLETED  (2)   (collapsed by default if > 5)
  [task card]
```

**Task card (list view):**
```
☐  Circulate revised contract terms    ← checkbox left
   [High ↑] [Wed ⏰] [Skio Integration ●] [Product Sync ↗]   ← badges row
                                                 devon avatar →
```
- 3px left accent bar for High (`NDS.danger`) and Med (`NDS.warn`) priority
- Project chip: dot + name, `t-gray` tint
- Meeting source chip: clickable → opens that meeting
- Owner avatar: clickable → opens that person's detail

**My day filter:** tasks due today or explicitly flagged "Today".
**This week filter:** tasks with due date within the current calendar week.
**Overdue filter:** tasks with `dueDate < today && !isCompleted`.

**Files:** `Sources/MeetingScribe/UI/ActionItemsListView.swift`, `ActionItemsViewModel.swift`, `ActionItemsChrome.swift`

### 5D. View switcher always visible

The List / Board / Calendar / Table segmented control must be accessible from every smart view, not just project pages. Put it in `ActionItemsChrome` (the top bar) so it persists across sub-nav selections.

```
Tasks           All tasks  ·  5 open · 3 to triage
[≡ List] [⊞ Board] [📅 Calendar]          [🔍 Filter] [+ New task]
```

**File:** `Sources/MeetingScribe/UI/ActionItemsChrome.swift`

### 5E. Two-way cross-links

**Meeting → Task:** In the meeting Actions tab, each action item gets a `→ Tasks` button (see §3D). Pushing creates an `ActionItem` with `meetingID` set. In the task card and task detail, a "from meeting" chip shows and is clickable → navigates to that meeting.

**Person → Task:** Tasks tab in person detail shows tasks where `ownerToken` matches the person's email/name (logic in `PersonDetailView.ownerMatchesPerson` already exists). "+ New task for {name}" pre-fills `owner` with the person's name and posts to `ActionItemStore`.

**Task → Person:** Owner avatar on task card is tappable → navigates to `PersonDetailView` for that person.

---

## Design Tokens (delta from Bloom base)

All tokens are unchanged from `design_handoff_bloom_redesign/README.md`. No new colors introduced.

New semantic usages in this redesign:

| Usage | Token |
|---|---|
| Triage inbox accent | `NDS.accent` (coral) |
| Triage row background | `NDS.accentSoft` (coral @ 16%) |
| Recording pill/bar border | `NDS.danger` @ 38–40% alpha |
| Voice note pill background | `rgba(34,26,8,.96)` (warm near-black) |
| Voice note gold tint | `NDS.gold` (`#ffce6b`) |
| Meeting source chip | `NDS.lilac-soft` bg + `NDS.lilac` text (`.t-iris`) |
| Editor caret | `NDS.accent` |

---

## Files to Edit (ranked by impact)

| File | Changes |
|---|---|
| `MainWindow.swift` | Tailored top-right toolbar per route; recording state in toolbar |
| `FloatingOverlay.swift` | `MeetingRecordDock` view; `VoiceNoteHoverPanel` NSPanel |
| `MeetingsView.swift` | Grouped list (NOW / TODAY / UPCOMING / PAST) |
| `MeetingDetailHeader.swift` | Tappable attendee chips → person deep-link; `+ People` badge for non-linked emails |
| `MeetingNotesTab.swift` | Notion-parity editor (toolbar, floating selection bar, push-to-tasks); rename to also cover Actions tab |
| `MarkdownEditor.swift` | Block toolbar, floating selection toolbar, 1.8× line height |
| `PersonDetailView.swift` | Two-pane split (`PersonIdentityPane` + `PersonWorkPane`); 5 tabs; `AnalyzePopover`; add-email inline; add-to-meeting |
| `MessagesAnalyzer.swift` | Add `since: Date?` param; map date-scopes to SQL cutoff |
| `ActionItemsSidebar.swift` | Triage inbox + smart views + projects all in one sub-nav |
| `ActionItemsChrome.swift` | View switcher always visible; title reflects smart view |
| `ActionItemsListView.swift` | Grouped sections (in-progress / to-do / done); cross-link badges |
| `ActionItemsViewModel.swift` | `pendingTriage` computed property; smart view filters |

---

## Interactions & Motion

All existing motion contracts from Bloom apply (`NDS.springStandard`, reduce-motion gates). New additions:

- **Triage card accept:** task row slides up and fades out with `NDS.springStandard` when confirmed/dismissed
- **Recording dock entrance:** `AnyTransition.move(edge: .bottom).combined(with: .opacity)`, spring
- **Voice note pill drag:** no animation while dragging; spring settle on release
- **Tab switch in Person detail:** `.animation(.easeOut(duration: 0.18))` cross-fade on content only, not the tab bar
- **Analyze popover:** `NSPopover` fade-in (default macOS); result card slides in from bottom with opacity

---

## Files in This Bundle

```
design_handoff_ux_redesign_v2/
  README.md                    ← this document
  prototype/                   ← symlink / copy of proto/ folder
    styles.css
    data.jsx
    recording.jsx
    shell.jsx
    tasks.jsx
    people.jsx
    meetings.jsx
    today.jsx
    app.jsx
    tweaks-panel.jsx
MeetingScribe Prototype.html   ← open in browser to review all screens
```

### How to use this bundle
1. Open `MeetingScribe Prototype.html` in a browser.
2. Use the **Tweaks panel** (toolbar top-right → Tweaks toggle) to switch A/B variants:
   - **Meetings A/B** — grouped list hero vs. filter tabs
   - **People A/B** — wide vs. compact identity pane
   - **Tasks A/B** — smart list vs. board
   - **Recording A/B** — labelled bar vs. compact pill
   - Demo toggles — turn meeting/voice recording on/off to see the indicators
3. Click nav items to explore each section. Meetings attendees are clickable → People. Tasks meeting-source chips are clickable → Meetings.
4. Implement on a new git branch; run `scripts/design-lint.sh` after each section to keep NDS drift at 0.
