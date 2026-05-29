# MeetingScribe — UX/UI Audit 2 (MeetingScribeRefactor)

Audited target: `/Users/tyleryannes/MeetingScribeRefactor/Sources/MeetingScribe`
(NOT `~/MeetingScribe`). All file:line references below point at the Refactor tree.

This is the rebuilt app: warm design system (`NotionDesign.swift`), `NavigationSplitView`
for Meetings, two-column People (HSplitView), summary-first detail tabs, inline action
items, follow-up button, pre-meeting brief. The audit assesses CURRENT state. Each finding
is tagged **already-good / partially-done / still-broken**.

---

## TL;DR — what the rebuild already fixed

- **Meetings tab no longer uses inline expand/collapse.** It is a real two-pane
  `NavigationSplitView` (`MeetingsView.swift:30`) — list left, full-page detail right.
- **People CRM is two-column** (list + detail, `PeopleListView.swift:35-38`) with edit/delete
  surfaced and lots of inline add affordances (encounters, memories, relationships, photos).
- **Pre-meeting brief is real and wired in** — `.upcoming` meetings show `PreMeetingBriefView`
  instead of a dead placeholder (`MeetingTranscriptTab.swift:28`).
- **Follow-up button restored** — `MeetingSummaryTab.swift:101` (`followUpButton`) surfaces
  the previously-dead `FollowUpView`.
- **Inline action items in the summary** — `MeetingSummaryTab.swift:132` (`actionItemsSection`).
- **Summary-first default** for past meetings with a summary (`UnifiedMeetingDetail.swift:239`).
- **A real onboarding flow** pre-explains every macOS permission (`OnboardingSheet.swift`).
- **People top-padding fix is present** (`PeopleListView.swift:133`, `.padding(.top, 60)`) — see
  caveat below.

---

## Non-negotiables verification

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| 1 | Clean spacing; People tab not cut off | **PARTIAL** | Fix is a magic-number hack: `PeopleListView.swift:133` hard-codes `.padding(.top, 60)`; detail comment claims a matching 72pt inset that the detail pane does **not** actually apply (`PersonDetailView.swift:218-282` has no top inset). |
| 2 | People CRM editing EASIER (inline, not modal-only) | **PARTIAL** | Core identity edit is still **modal-only** (`PersonDetailView.swift:342` → `AddPersonSheet`). BUT memories/encounters/relationships/photos/notes-analysis are all inline-add. Mixed model. |
| 3 | Today = functional central hub | **PARTIAL** | Good: record CTA, quick-action pills, today's calls, action-items widget, suggested people. Bad: still uses inline expand (#4), `calendarLink` is dead code (`TodayView.swift:173`), no "next meeting" countdown / upcoming-week glance. |
| 4 | NEVER collapse/expand — click IN with back arrow | **VIOLATED** | `TodayView.swift:23` `expandedMeetingID`, `:245` "Collapse" button, `:296` `toggle()`. `CalendarTabView.swift:20,487,498` (dead file, but still present). Meetings tab is compliant. |
| 5 | Use FULL screen width; no wasted space | **VIOLATED** | maxWidth caps everywhere: `TodayView.swift:60` (920), `PersonDetailView.swift:277` (720), `NotionDesign.swift:11` `contentMaxWidth=720`. Wide monitors get rivers of empty gutter. |
| 6 | Default views: upcoming → past → all; sort next-upcoming / most-recent | **PARTIAL** | Sorting is correct everywhere. But `MeetingsView.swift:26` defaults `scope = .all` (not upcoming-first) and resets every visit (not persisted). |
| 7 | Restore lost buttons/editing | **MOSTLY-OK** | Follow-up, export, recover, transcribe-now, inline tasks all restored. Gaps: no per-attendee "add to People" action; CalendarTabView's month/week views are orphaned (lost from nav entirely). |

---

# UX-1 — Visual design, spacing & layout system

### [P1] Wasted horizontal space from maxWidth caps — *still-broken*
- `TodayView.swift:60` `.frame(maxWidth: 920)`, `PersonDetailView.swift:277` `.frame(maxWidth: 720)`,
  `NotionDesign.swift:11` `contentMaxWidth = 720`, `ActionItemsChrome.swift:102` `.notionPageColumn()`.
- On a 27" display the content column is a narrow ribbon with large empty margins; violates
  non-negotiable #5.
- **Fix:** raise caps to ~1100–1200, or make them adaptive (`min(geo.width - gutters, cap)`),
  and let the meeting/person detail panes truly fill. Keep a readable measure only for prose
  (summary/transcript), not for lists, cards, and tables.

### [P2] Two parallel design systems coexist — *partially-done*
- The rebuild introduced warm `NDS` tokens, but a lot of surfaces still use raw AppKit colors:
  `CalendarTabView.swift:44` `Color(NSColor.windowBackgroundColor)`, ActionItems board uses
  `Color(NSColor.controlBackgroundColor)` throughout (`ActionItemsBoardView.swift:55,77,148`).
  Result: Tasks/Calendar look colder and slightly off-palette vs Today/Meetings/People.
- **Fix:** migrate ActionItems board + any `NSColor.*` surfaces to `NDS.bg/fieldBg/hairline`.

### [P2] Magic-number top padding instead of safe-area handling — *partially-done*
- `PeopleListView.swift:133` `.padding(.top, 60)` is a hard-coded guess to clear the Tahoe
  toolbar overlay. The inline comment claims the detail pane uses a matching 72pt inset, but
  `PersonDetailView.swift` applies **none** — so the two panes do NOT line up, and a window
  toolbar height change will re-clip or over-pad.
- **Fix:** use `.safeAreaInset` / `.toolbarBackground`-aware layout, or a shared constant
  applied to both panes. Remove the misleading comment.

### [P2] Inconsistent button system adoption — *partially-done*
- `NotionDesign.swift` defines a full `MS*ButtonStyle` family, yet many call sites still use
  `.borderedProminent` / `.bordered` / `.borderless` (`MeetingCard.swift:164,214`,
  `MeetingSummaryTab.swift:92,108`, `PersonDetailView.swift:497,552`). Heights and corner radii
  drift across the app.
- **Fix:** adopt `MSPrimary/Secondary/Tertiary` consistently; reserve native styles for menus.

### [already-good] Warm palette + dynamic light/dark
- `NDS.dyn` (`NotionDesign.swift:51`) resolves per-appearance sRGB; warm neutrals replace the
  old cold navy. The `AppearanceToggle` (`:425`) is a nice touch. Typography tokens are coherent.

---

# UX-2 — Navigation & information architecture

### [P0] Orphaned CalendarTabView — *still-broken (dead code / lost feature)*
- `CalendarTabView.swift` (month grid, week kanban, list) is **not referenced by any Swift
  source** — only by old audit `.md` files. MainWindow's nav has no `.calendar` case
  (`MainWindow.swift:9-10`), and `TodayView.calendarLink` (`TodayView.swift:173`) routes to
  `.meetings`, never to this view.
- Net effect: the month/week calendar UI the rebuild built is **completely unreachable**. Either
  a feature was silently lost, or ~500 lines of dead code ship in the binary.
- **Fix:** decide — either (a) re-expose month/week as a view-mode toggle inside MeetingsView,
  or (b) delete `CalendarTabView.swift`. Right now it's the worst of both: shipped but invisible.

### [P1] Meetings scope default & non-persistence — *partially-done*
- `MeetingsView.swift:26` `@State private var scope: Scope = .all`. Non-negotiable #6 asks for
  upcoming-first, and the value resets to `.all` on every tab revisit (not `@AppStorage`).
- **Fix:** default `.upcoming` and persist via `@AppStorage("meetings.scope")`. (Note: the
  group ordering for `.all` already does Upcoming → Today → Earlier — good.)

### [P1] No selection persistence / deep-link affordance in Meetings — *partially-done*
- `MeetingsView` selection is local `@State` (`:19`) and re-creates the detail on every id
  change (`:51`). There's no "open this meeting" entry from search into the Meetings tab — the
  search palette opens meetings in a **separate sheet** (`MainWindow.swift:293,400`) rather than
  selecting them in the split view. Two different "open a meeting" experiences.
- **Fix:** route `routeEntity(.meeting)` into MeetingsView selection (post a notification like
  People already does) so there's one canonical meeting surface.

### [P2] Two competing meeting-detail presentations — *still-broken*
- A meeting detail appears as: (a) full split-view page in Meetings, (b) inline expansion in
  Today, (c) modal sheet from search/Calendar. Three layouts for one entity is confusing and
  triples maintenance.
- **Fix:** standardize on the split-view page; have Today/search push into it.

### [already-good] Rail grouping + collapse 7→5
- `MainWindow.swift:31-42` groups nav into WORKSPACE / ORGANIZE, folds Calendar into Meetings
  and Integrations into Settings. Cleaner IA. ⌘1–⌘7 shortcuts + ⌘K search are wired.

---

# UX-3 — Interaction design, affordances & editing

### [P0] Today still expands/collapses instead of navigating — *still-broken (violates #4)*
- `TodayView.swift:23` `expandedMeetingID`; `:208 cardWithDetail` renders an inline
  `UnifiedMeetingDetail` with a **"Collapse"** button at `:245`; `:296 toggle()`.
- The whole 520pt detail panel (`:253 .frame(minHeight: 520)`) is jammed inside a card in a
  scroll view — cramped, and exactly the pattern Tyler banned.
- **Fix:** make Today cards navigate into the same detail page Meetings uses (click → select +
  switch to Meetings, or a `NavigationStack` push), with a back arrow. Delete `expandedMeetingID`,
  `cardWithDetail`, `inlineDetail`, `toggle`, and the Collapse button.

### [P1] People identity editing is modal-only — *partially-done (violates #2 spirit)*
- `PersonDetailView.swift:342` Edit → `AddPersonSheet` (`:289`). Name/company/role/email/phone/
  birthday/address/notes all require opening a 460×540 modal, even to fix one typo.
- Meanwhile memories (`:651`), encounters (`:546`), relationships (`:564`), photos (`:492`) ARE
  inline. The inconsistency is the problem: the most-edited fields are the modal-locked ones.
- **Fix:** make the identity panel fields inline-editable (tap-to-edit text, like the meeting
  header's `editingHeader` pattern at `MeetingDetailHeader.swift:86`). Keep the sheet for
  first-create only.

### [P2] "Notes" label collision in Person detail — *still-broken*
- `PersonDetailView.swift:537` renders the bio under header **"Notes"**, AND
  `attachedNotesSection` (`:816`) is also titled **"Notes"** — both in the same Notes tab. Two
  different things, identical label, stacked. Confusing.
- **Fix:** rename bio section to "About" / "Bio"; keep "Notes" for attached analyses.

### [P2] Attached-note chevron is a mini expand/collapse — *still-broken (minor #4)*
- `PersonDetailView.swift:849-853` toggles `noteExpansion[id]` with a chevron to expand a note
  body in place. Same anti-pattern, smaller scale. Acceptable for a 2-line preview but worth
  noting against the "never expand" rule.

### [P2] Recurring-series action overflow is deep — *partially-done*
- `MeetingDetailHeader.swift:230 overflowMenu` nests Recover… and Export… as **submenus inside**
  the `···` menu. Useful actions (Reveal in Finder, Export PDF) are 2–3 clicks deep.
- **Fix:** promote Export to a first-class header button for past meetings; it's a top-3 action.

### [already-good] Meeting-card primary action consolidation
- `MeetingCard.swift:190` collapses the old 3-button upcoming row into one "Join & Record"
  split-button with a dropdown for the rare cases. Strong decision-under-pressure design.

### [already-good] Inline action items with one-tap done
- `MeetingSummaryTab.swift:160 InlineActionItemRow` — checkbox toggles status without leaving
  the summary. Board view has full drag-and-drop (`ActionItemsBoardView.swift:51-72`).

---

# UX-4 — Empty states, defaults & onboarding

### [P1] Today defaults to inline detail, not a glanceable hub — *partially-done (#3)*
- The hub shows record CTA + pills + today's calls + tasks widget + suggested people — good
  coverage. But there's **no "next meeting in 12 min" countdown**, no upcoming-week peek, and
  the dead `calendarLink` (`TodayView.swift:173`) suggests a planned "see all calls" entry that
  was never wired into the feed (it's defined but never placed in `feed`).
- **Fix:** add a compact "Next up" strip (soonest meeting + Join&Record), and either wire or
  delete `calendarLink`.

### [P2] Tasks default lands on flat "All tasks", dashboard hidden — *partially-done*
- `ActionItemsView.swift:23` defaults `selectedProjectID = nil` (All tasks) with a comment
  explaining the dashboard is "one click away" — but there's **no visible affordance** telling
  the user the dashboard exists; you must know to click a sentinel.
- **Fix:** add a "Home/Dashboard" entry at the top of the ProjectRail so the rich
  `tasksDashboard` is discoverable.

### [already-good] Strong empty states across the app
- Meetings (`MeetingsView.swift:154`), People (`PeopleListView.swift:219`), Tasks
  (`ActionItemsChrome.swift:409`), Today (`TodayView.swift:257`), summary
  (`MeetingSummaryTab.swift:63`) all have icon + heading + guidance + a primary action. This is
  genuinely well done.

### [already-good] Onboarding pre-explains permissions before the OS dialog
- `OnboardingSheet.swift` walks vault location → mic → screen recording → calendar →
  notifications → accessibility, each with bullets and a Skip. Materially improves grant rate vs
  raw system prompts. Includes the "quit + relaunch after Screen Recording" caveat (`:312`).

### [P2] Pre-meeting brief empty state conflates two causes — *partially-done*
- `PreMeetingBriefView.swift:124` says "first meeting OR Calendar access not granted." Mixing a
  benign state with a permission failure means a permission problem reads as "no history."
- **Fix:** check calendar authorization explicitly and show a Grant Access button when that's
  the real cause.

---

# UX-5 — Accessibility, responsiveness & full-screen layout

### [P0] Full-screen layout wastes width on large displays — *still-broken (#5)*
- Covered in UX-1; from an a11y/responsiveness lens the harm is that low-vision users who run
  large windows + larger text get *less* usable content because of the fixed `maxWidth` caps
  (`TodayView.swift:60`, `PersonDetailView.swift:277`, `NDS.contentMaxWidth`).
- **Fix:** adaptive max-widths; never cap list/table/card surfaces.

### [P1] Heavy reliance on color-only status encoding — *still-broken*
- Status dots carry meaning with color alone: `MeetingsView.swift:331 statusDot`
  (green/orange/red/yellow), priority pips `MeetingSummaryTab.swift:194` /
  `ActionItemsWidget.swift:139`, recording health dots `MeetingDetailHeader.swift:493`. Several
  have **no `.help()` and no text label** — invisible to colorblind users and VoiceOver.
- **Fix:** pair each color dot with a glyph or accessibilityLabel (the meeting-card past-status
  pill at `MeetingCard.swift:254` already does this correctly with text — replicate that).

### [P1] Sparse VoiceOver labeling on icon-only controls — *partially-done*
- `NavRailItem` has `.accessibilityLabel` (`MainWindow.swift:504`) — good. But icon-only buttons
  elsewhere lack labels: trash button `PersonDetailView.swift:346` (image only), the `xmark.circle.fill`
  remove buttons (encounters `:1083`, memories `:666`, relationships `:585`), the `···` overflow
  (`MeetingDetailHeader.swift:319`). Screen-reader users hear "button" with no context.
- **Fix:** add `.accessibilityLabel` (and they already mostly need `.help()` too).

### [P2] 44pt tap targets defined but not applied — *partially-done*
- `NotionDesign.swift:278 minTap()` exists specifically to guarantee 44pt hit areas, but I found
  **no call sites** using it. Many icon buttons render at 12–16pt glyphs with `.borderless`
  (e.g. `PersonDetailView.swift:585,666,1083`), well under the target.
- **Fix:** apply `.minTap()` to icon-only buttons (it preserves visual size).

### [P2] Fixed-size sheets ignore Dynamic Type — *still-broken*
- `AddPersonSheet.swift:104` `.frame(width: 460, height: 540)`, `AddEncounterSheet`
  `PersonDetailView.swift:1140` 420×460, `OnboardingSheet.swift:44` 480×480, meeting sheet
  `MainWindow.swift:406` 860×680. At larger accessibility text sizes these clip or scroll
  awkwardly.
- **Fix:** use `minWidth/minHeight` + `idealWidth`, let content drive height.

### [P2] Narrow-window chat auto-hide is good but Meetings double-pane can crowd — *partially-done*
- `MainWindow.swift:240` hides chat under 860px (nice). But MeetingsView's split (300–480 list +
  detail) plus the 240px rail can still feel tight on a 13" laptop; the detail header packs title,
  meta, chips, attendees, conference link, tags, action row, and CTA buttons
  (`MeetingDetailHeader.swift:8-80`) into a fixed-padding column.
- **Fix:** allow the list pane to collapse to icons, or let the user hide the rail too.

### [already-good] Text selection + keyboard shortcuts
- `textSelection(.enabled)` on transcripts/summaries/contacts (`PersonDetailView.swift:533`,
  `MeetingDetailHeader.swift:114`). Keyboard shortcuts: ⌘K, ⇧⌘P, ⌘1–7, ⌥⌘N. Good baseline.

---

# New ideas (not in the original brief)

1. **Unified meeting surface.** Kill the 3-way split (page / inline / sheet). One detail page,
   reached by selection or push, everywhere. Removes ~200 lines and a whole class of bugs.
2. **"Today → next meeting" hero.** A single prominent "Next: <title> in 12 min · Join & Record"
   strip is the highest-value glance for a meeting app and is currently missing.
3. **Inline person editing as the default.** Tap-to-edit identity fields; reserve the sheet for
   create. Directly satisfies #2 and matches the meeting-header pattern that already exists.
4. **Calendar month/week as a Meetings view-mode toggle.** Reuse the orphaned `CalendarTabView`
   logic behind a List / Month / Week segmented control in MeetingsView's list header.
5. **Per-attendee "Add to People".** In the meeting header attendee chips
   (`MeetingDetailHeader.swift:505 AttendeeChip`), add a hover action to create/link a Person —
   closes the loop between Meetings and the CRM.
6. **Accessibility pass with `minTap()` + labels** as a single sweep — the primitives already
   exist (`minTap`, NDS), they're just not applied.

---

## Priority rollup

| Severity | Findings |
|---|---|
| **P0** | CalendarTabView orphaned/dead (UX-2); Today expand/collapse (UX-3, #4); full-screen width waste (UX-5/UX-1, #5) |
| **P1** | Meetings scope default+persistence (#6); People modal-only identity edit (#2); maxWidth caps (UX-1); color-only status (a11y); icon-button VoiceOver labels; Today hub gaps (#3) |
| **P2** | Two design systems; padding magic numbers; button-style drift; "Notes" label collision; attached-note chevron; Tasks dashboard discoverability; fixed-size sheets; minTap unused; brief empty-state conflation; export buried |
