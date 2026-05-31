# UX09 — Cross-Tab Consistency (empty states, loading, keyboard nav, affordances)

Patterns that *should* be identical across Meetings / People / Tasks / Notes but
aren't. These are the cheapest, highest-polish wins: each one makes a behavior
the user already learned in one tab work the same way in the next. Verified
against the live source in `~/MeetingScribeRefactor/Sources/MeetingScribe`.

## Lift from V4
- **D2-3** — unify accent to brand purple (consistency of the *color* affordance; my items unify the *behavioral* affordances around it).
- **D5-1** — reduce-motion pass; relevant because the same always-on `symbolEffect(.pulse, options: .repeating)` is duplicated per-surface (`MeetingsView.swift:448`, `MeetingCard`), so a consistency sweep and the a11y sweep are the same edit.
- **D1-5** — clickable person↔meeting↔task rows; the "dead row" problem is a consistency defect (some rows navigate, identical-looking ones don't).
- **D2-1 / D2-6** — design-system enforcement (`MSCard/MSListRow`); the button-style split (UX9-2) is exactly the drift D2-6 predicts.

---

## UX improvements (5)

### UX9-1 — Make every list empty state actionable (kill dead empty states)
**Friction today.** Empty states are wildly inconsistent. QuickNotes' empty state
has a CTA button (`QuickNotesView.swift:47` "Import audio file"); People's empty
state is backed by an always-visible Add/Import row (`PeopleListView.swift:136,220`).
But the **Meetings** empty state is dead text with no action — `emptyState`
(`MeetingsView.swift:179-192`) just says "Meetings appear after you record…"
with no Record button. Tasks dashboard empties are bare one-liners via
`dashEmpty(_:)` (`ActionItemsChrome.swift:39,63,84,119`) — "No open tasks. Nice."
with no "New task" affordance even though the toolbar button exists.
**Fix.** Give every primary-list empty state one consistent CTA: Meetings →
"Record a meeting" / "Sync calendar"; Tasks dash → reuse the existing `addTask()`
as a "+ New task" button inline. Standardize on one `EmptyStateView(icon, title,
subtitle, action)` helper (also resolves the lack of `ContentUnavailableView` —
zero uses in the whole codebase).
**Clicks.** From an empty Meetings tab to recording: today the action isn't on
screen at all → 1 click. Effort **small-M** (one shared view + 3 call sites).

### UX9-2 — Collapse the two parallel primary-button systems into one
**Friction today.** There are **two** primary-button styles doing the same job:
`UntitledPrimaryButtonStyle` (padding-based, drop-shadow; `NotionDesign.swift:196`)
and `MSPrimaryButtonStyle` (fixed-height, no shadow; `NotionDesign.swift:227`).
`TodayView.swift` uses BOTH in the same view (`MSPrimaryButtonStyle` at :133,177
and `UntitledSecondaryButtonStyle` at :297), while Tasks uses `Untitled*`
(`ActionItemsChrome.swift:352`) and People/MeetingDetail use `MS*`. The user sees
a brand-purple primary button that is a different height/shadow depending on which
tab they're in.
**Fix.** Pick `MS*` as canonical (it's the documented "full button system,"
`NotionDesign.swift:224`), alias `Untitled*` to it, migrate the ~3 call sites.
Pure visual consistency, no behavior change.
**Clicks.** n/a (visual). Effort **S**.

### UX9-3 — Give the Meetings list the same keyboard/selection model as every other list
**Friction today.** People (`PeopleListView.swift:166`), QuickNotes
(`QuickNotesView.swift:55`) and Tasks list all use SwiftUI `List(selection:)`,
which gives free arrow-key navigation, multi-select, and `onDelete`. The
**Meetings** list is hand-rolled: a `ScrollView`+`LazyVStack` of plain `Button`s
(`MeetingsView.swift:144-175`) — so on the most-used tab you **cannot arrow up/down
between meetings**, there's no `onDelete`, and no selection highlight beyond the
manual `isSelected` tint. GlobalSearch is the only place with arrow-key nav
(`GlobalSearchView.swift:67-69`), proving the pattern exists but wasn't applied.
**Fix.** Port the meeting list to `List(selection: $selectedMeeting)` so keyboard
nav, type-select, and delete come for free and match the other three tabs.
**Clicks.** Browsing 10 meetings by keyboard: impossible today → arrow keys.
Effort **small-M**.

### UX9-4 — One shared search field (placement, clear-X, Esc-to-clear) everywhere
**Friction today.** Search is hand-rolled in 5+ places with different chrome:
Meetings (`MeetingsView.swift:93-111`, has clear-X), People
(`PeopleListView.swift:145-154`, has clear-X), Tasks (`ActionItemsChrome.swift:342`,
**no** clear-X, fixed 130pt width), GlobalSearch, TranscriptSync. None use the
native `.searchable` modifier (zero matches) and **none clear on Esc** — only
GlobalSearch handles `.onKeyPress(.escape)` (`GlobalSearchView.swift:69`). So the
clear gesture the user learns in People silently doesn't exist in Tasks.
**Fix.** Extract one `MSSearchField` (magnifier + field + clear-X + Esc-to-clear)
and drop it into all list headers. Consistent affordance + a keyboard escape hatch.
**Clicks.** Clearing a Tasks search: today drag-select+delete the text → 1 click
(X) or 1 key (Esc). Effort **small-M**.

### UX9-5 — Consistent row context menus + hover affordance across lists
**Friction today.** Right-click behavior is inconsistent. Tasks rows
(`TaskRowView.swift`) and PersonDetail (`PersonDetailView.swift`) have
`contextMenu`; but **PeopleList rows** (`PersonRow`, `PeopleListView.swift:249`)
and **Meetings list rows** (`MeetingListRow`, `MeetingsView.swift:414`) have none —
so "right-click a person to tag/delete" works nowhere in the list even though it
works on the detail page. Hover is also uneven: Meetings rows animate a hover tint
(`MeetingsView.swift:500-501`) but People `List` rows rely on default styling.
**Fix.** Add a small shared `.rowContextMenu()` (Open, Tag, Delete) to PeopleList
and Meetings rows, mirroring Tasks. Brings the frequent actions (tag/delete) to a
right-click instead of forcing a click-into-detail first.
**Clicks.** Delete/tag a person from the list: today click-in → action = 2 clicks
→ right-click → action = 1 interaction. Effort **S**.

---

## Feature improvements (5)

### FT9-1 — `⌘F` focuses the current tab's search field
Each tab already has a search field, but there's no keyboard way to jump to it
(`⌘K` opens *global* search instead). Add a `@FocusState` + `⌘F` shortcut wired to
the active tab's `MSSearchField` (depends on UX9-4). One reflex that works the
same everywhere. **Effort S.** Dep: UX9-4.

### FT9-2 — Loading skeleton/label instead of bare spinners
~30 bare `ProgressView().controlSize(.small)` calls (e.g. `MainWindow.swift:553,581,596`,
`MeetingSummaryTab.swift:81`, `PersonDetailView.swift:803,863`) with no label, so the
user can't tell *what* is loading. Only two spinners have text
(`ActionItemsProjectPage.swift:163` "Loading…", `ContactsImportView.swift:80`).
Add a tiny `MSLoading("Transcribing…")` helper and use it for the long ops
(transcribe, summarize, sync) so feedback is legible and uniform. **Effort S.**

### FT9-3 — Inline "Undo" toast after destructive list actions
Deletes across `onDelete` (QuickNotes `:60`, Tasks list, People) and the
right-click deletes (FT from UX9-5) are immediate and irreversible. A shared
auto-dismiss "Deleted — Undo" toast (also seeds V4's D4-3 universal undo) makes
every list delete safe and consistent. **Effort small-M.**

### FT9-4 — Keyboard delete + multi-select on the lists that already use `List`
People and QuickNotes use `List(selection:)` but `selection` is a single `String?`
(`PeopleListView.swift:15`, `QuickNotesView.swift:14`); there's no `Delete`-key
binding and no multi-select. Switch to `Set<String>` selection + an `onDeleteCommand`
so the Delete key and shift-click range-select work uniformly (and gives FEAT-B
people bulk-select its selection model for free). **Effort small-M.** Dep: pairs
with FEAT-B.

### FT9-5 — Standard "Today / chevrons" date-nav control reused beyond Meetings
The Meetings month view has a polished prev/next-chevrons + "Today" reset control
(`MeetingsView.swift:284-300`) with proper `accessibilityLabel`s. Nothing else
reuses it — the Today tab and any future timeline re-invent date headers. Extract
`MSMonthNav` so temporal surfaces share one affordance. **Effort S.**

---

## Top 3 picks
1. **UX9-1 — actionable empty states.** Highest polish-per-hour: turns three dead
   screens (esp. Meetings) into a first-action launchpad; one shared view, ~3 sites.
2. **UX9-3 — `List(selection:)` for Meetings.** The busiest tab is the only one
   without keyboard navigation; switching to the same `List` the other three tabs
   use buys arrow-nav + delete + multi-select essentially for free.
3. **UX9-2 — one primary-button system.** Smallest diff, most-visible fix: stop the
   same brand button changing height/shadow between tabs (TodayView uses both today).

**Single highest-value low-lift win:** UX9-1 — every primary list should greet an
empty user with the same one-click way to fill it; Meetings and Tasks currently
don't, and it's a shared-helper edit measured in hours.
