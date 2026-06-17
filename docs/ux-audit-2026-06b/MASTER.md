# MASTER — De-tab Meetings + People, Fix Buttons, Integrate Tasks

*Consolidated plan for ux-audit-2026-06b. Reconciles all five area docs into one
problem inventory, one set of cross-cutting decisions, and one global build
sequence. Faithful to the source docs — every numbered finding is reproduced
below, grouped by area, with its file:line evidence and severity preserved.*

## Goal

Turn the two dense, tabbed detail surfaces — **Meeting detail**
(`UnifiedMeetingDetail`) and **Person detail** (`PersonDetailView`) — into
**single vertically-scrolling canvases of collapsible `MSSection` blocks**.
Along the way:

1. **De-tab.** Replace the meeting `DetailTab` picker (Meeting / Actions /
   Transcript / Ask AI) and the person `MSPillTabs` (`PersonTab`) with one scroll
   column of `MSSection`s whose expand/collapse state persists. No tab switch
   loses scroll position; nothing hides in a slot you have to discover.
2. **Fix button sizes.** Normalize every button to the Phase-F role table
   (Primary 34 / Secondary 30 / Tertiary 28 / Icon 30-visible-44-hit / Danger 34 /
   Menu-chrome 30). Kill the `.borderedProminent` / `.bordered` / `.controlSize` /
   bare-`.borderless` drift, and add a CI lint guard so it stays killed.
3. **Integrate Tasks.** Make the task↔meeting↔owner three-way join coherent and
   navigable everywhere (every rendered edge is a door), surface open-task counts
   on People rows and meeting cards, add a triage-able People list, promote the
   person Tasks section to top-level, unify the two divergent owner-matchers, and
   close the unresolved-owner / orphaned-meeting gaps.

The shared substrate (`05-layout-components`) is the keystone — it ships first;
the two canvases and the Tasks integration stack on top of it.

---

## Phase / area map

| Phase | Code | Area / source doc | What it delivers |
|---|---|---|---|
| Foundation | **F** | 05-layout-components | Confirm `MSSection`, button styles, tokens exist; button-style swaps (Group A); centered 760 canvas recipe; design-lint guard |
| Buttons | **B** | 05 (Group A) + 01 (header) + 02 (Phase A) | Every banned native button → sanctioned `MS*` style across the five files |
| Tasks | **T** | 04-tasks-integration | Navigable meeting/owner chips, count badges, store helpers, unassigned-owner review, orphan guards, unified matcher |
| People list | **L** | 03-people-list | Overdue predicate, task index, richer row, triage control, grouping, density, deep-links |
| Meeting canvas | **M** | 01-meeting-detail | De-tab `UnifiedMeetingDetail` into the 7-section meeting canvas |
| Person canvas | **P** | 02-person-detail | De-tab `PersonDetailView` into the compact-header + 18-section person canvas |
| Cleanup | **X** | 01 §6 / 02 / 04 | Delete dead tab machinery, dead vars, flag branches |

---

## Complete problem inventory

Every numbered problem from each doc, grouped by area, with original IDs,
file:line evidence, and severity. Where two docs found the same thing, both are
listed and the overlap is noted.

### Meeting detail (01-meeting-detail.md)

- **P1 — Tab fragmentation: one page cut into four. Severity: high.** `DetailTab`
  (`MeetingTranscriptTab.swift:172`) drives an exclusive `switch tab`
  (`UnifiedMeetingDetail.swift:157-164`) via `MSPillTabs` (`tabPicker`, `:254`).
  Only one of {Meeting, Actions, Transcript, Ask AI} on screen; tab round-trips
  throw away scroll positions (each arm has its own `ScrollView`/`VSplitView`).
- **P2 — Action items rendered in three places, two stale. Severity: high.**
  (1) `outcomesStrip` (`MeetingSummaryTab.swift:195-235`) read-only preview;
  (2) `actionsBody` (`UnifiedMeetingDetail.swift:277-320`) the real CRUD surface
  (`MeetingActionRow` + "Add all N → Tasks" + "Add action item");
  (3) `actionItemsSection(_:)` (`MeetingSummaryTab.swift:472-537`) a second full
  list (`InlineActionItemRow`) reachable via `pastSummaryBody` (`:393`).
  *Overlaps with 04 §3.9 / O5 (non-navigable owner in outcomesStrip).*
- **P3 — `applySmartTabDefault` guesses the page and races a timer. Severity:
  medium.** `applySmartTabDefault()` (`UnifiedMeetingDetail.swift:427-444`) fires
  a 300 ms `Task.sleep` (`:436`) that flips `summaryExpanded` based on whether
  `summary` is non-empty at that instant; `reload()` (`:369`) fills it async →
  non-deterministic. Guards `hasAppliedTabDefault` (`:428`) + reset (`:173`)
  exist only to stop re-firing.
- **P4 — Cross-tab teleports lose scroll and notes context. Severity: medium.**
  `highlightsStrip` → `tab = .transcript` (`MeetingSummaryTab.swift:168`);
  `consumeTranscriptQuery()` → `tab = .transcript` (`MeetingTranscriptTab.swift:58`);
  `reviewBanner.onReviewTasks` → `tab = .actions` (`UnifiedMeetingDetail.swift:139`).
  Each teleport unmounts the arm, loses scroll/caret, mounts target at top.
- **P5 — Mode-multiplexed content hidden in tab slots. Severity: medium.**
  `transcriptBody` (`MeetingTranscriptTab.swift:19-51`) overloads the Transcript
  tab to be `LiveTranscriptScroll` / `PreMeetingBriefView` (relabeled "Brief",
  `tabPicker:262`) / `TranscriptSyncView` by mode. Upcoming brief is behind a tab
  users don't open; live transcript is one tab from the notes.
- **P6 — Header density. Severity: low-medium.** `header`
  (`MeetingDetailHeader.swift:8-106`) stacks spine + title/meta/chips/CTA/overflow
  + attendee scroll + shared-history + conference-URL + `TagPicker` + upcoming row
  + status banner, then `reviewBanner`/`audioBar`/`tabPicker` follow; canvas can
  start 250-300pt down.
- **P7 — Generating / failed summary states duplicated and inconsistent.
  Severity: medium.** New canvas: `summaryGeneratingBanner`
  (`MeetingSummaryTab.swift:70`) + `summaryFailedBanner` (`:91`). Legacy:
  `pastSummaryBody` (`:335`) inline tokens (`:339-349`) + `emptySummaryView`
  (`:400`). Two visual languages; token preview capped at 240pt (`:82`) in one
  place, uncapped (`:347`) in the other.

### Person detail (02-person-detail.md)

- **P1-A — Three-column cram on the default width. Severity: P1.** `body`
  (`:366-375`) forces identityPane(300) + workArea(min ~260 inside `maxWidth:760`)
  + chat(min 320); HSplitView floor ~880pt before either side breathes.
- **P1-B — 300pt identityPane overload (7 stacked sections). Severity: P1.**
  `identityPane` (`:503-518`) stacks identity + insight + tags + contact +
  relationships + encounters + photos into a fixed 300pt rail (268pt usable);
  `EncounterHeatMap` (`:1677`), rel rows, tag chips all wrap/clip.
- **P1-C — Two ragged FlowLayout button rows with mixed heights. Severity: P1.**
  Row 1 (`:852-875`): Brief Me (Primary 34) / Edit (Secondary 30) / ⋯ (Secondary
  30 icon) / trash (Secondary 30 icon). Row 2 (`:880-897`): Log encounter /
  Relationship / Ask AI all `.borderless`+`NDS.small`.
- **P1-D — Sub-44pt taps on important verbs. Severity: P1.** Row 2 verbs
  (`:884, :889, :895`) are `.borderless`+`NDS.small`, no `.minTap()`, ~20pt tall —
  core CRM loop verbs under the 44pt tap minimum.
- **P1-E — `.borderedProminent` reconnect/health CTAs (raw style violation).
  Severity: P1 (live popover) / P2 (dead header).** `healthWhyPopover` "Log a
  check-in" `.borderedProminent`+`controlSize(.small)`+`.tint` (`:1003-1006`);
  dead `header` "Brief Me" `.borderedProminent` (`:1525-1528`). *Overlaps with
  05 §2.3 #1 and #4 (worst offenders).*
- **P1-F — Bare `Button("Add")` / `Button("Run")` everywhere. Severity: P1.**
  `:1073` (tags), `:1134` (favorites), `:1782` (tasks), `:1890` (relationships,
  `.borderless`), `:2308` (talking points), `:2354` (memories); `Button("Run")`
  `:2827` (deep); `:1269` (suggestions); `:1600` (photos).
- **P1-G — "A bunch of unnecessary tabs." Severity: P1.** `MSPillTabs` (`:574`)
  with 4 tabs in a column so narrow `MSPillTabs` was made horizontally scrolling
  (`MSComponents.swift:88-92`); tabs hide content (Tasks under Meetings, §1.5).
- **P2-H — Scrolling section-nav pills (cram tell, dead). Severity: P2.**
  `sectionNav`/`sectionNavItems` (`:698-738`) — horizontally-scrolling pill rail
  of 9 jump-chips, superseded; remove.
- **P2-I — Duplicate "Brief Me" + duplicate "Notes." Severity: P2.** "Brief Me"
  in live `identityPanel` (`:856`) and dead `header` (`:1525`); "Notes" is both
  the bio (`:1655`) and attached notes (`:2576`).
- **P2-J — Inline-text-action `.borderless` clusters. Severity: P2.**
  `analysisPresetMenu` Analyze (`:2431`), `addEmailControl` (`:1564`),
  `aiSuggestionsSection` Suggest (`:1172`), photos Add (`:1601`), Save-to-notes
  (`:2524`), etc. *Overlaps with 05 §2.3 #5.*
- **P3-K — Borderless menus without chrome. Severity: P3.** `checkInGoalMenu`
  (`:1704-1710`), `relationshipTypePicker` (`:1041-1049`), `messagesSection` Scan
  (`:2387-2394`) use `.menuStyle(.borderlessButton)` with no chrome; sanctioned is
  `.msMenuButtonChrome()`.

(02 §3 carries a full 61-row per-button audit — every individual button's
current style → target style, with the role→style→height contract rules. Those
rows become the B-phase increments in BUILD-PROMPTS rather than being duplicated
line-by-line here.)

### People list + navigation (03-people-list.md)

- **P-1 — Flat, undifferentiated scroll. Severity: P1.** Single
  `ForEach(filtered)` (`:319-324`), no section anchors; with 500+ contacts the
  4-6 overdue people are buried among hundreds of dormant imports.
- **P-2 — `PersonRow` under-signals. Severity: P1.** `PersonRow` (`:614-653`):
  avatar + name + type chip + role/company + relative date; no overdue state, no
  task count (only a 2pt health ring). *Overlaps with 04 §3.4 / C3.*
- **P-3 — Reconnect intelligence buried in the no-selection dashboard. Severity:
  P1.** `goneCold`/`comingUp`/`mostActive` (`PeopleInsightsView.swift:84-147`)
  shown only when `selection == nil` (`:557-558`); invisible during triage. The
  "Mark reached out" affordance (`:37-43`) is likewise dashboard-only.
- **P-4 — No grouping. Severity: P1.** `sorted(_:)` (`:71-82`) reorders but can't
  bucket; overdue 6 interleaved with 494 others; sort ≠ triage.
- **P-5 — Tasks↔People never meet in the list. Severity: P2 → P1 for task-driven
  users.** `ActionItem.ownerPersonID` consumed only inside `PersonDetailView`
  (`:230`, `:404`); the list has no `ActionItemStore` in env, no "who owes me
  open tasks" entry, despite `TaskQuery.Scope.person` + a complete deep-link path
  existing. *Overlaps with 04 §3.4 / C3.*
- **P-6 — Static geometry / density. Severity: P3.** Sidebar fixed `260/320/380`
  (`:113`); row fixed `.padding(.vertical,3)` + 28pt avatar; no density control.
- **P-7 — Snapshot/live divergence risk. Severity: P3 (watch-item).**
  `SnapshotPersonRow` (`:589-612`) and `PersonRow` (`:614-653`) are independent;
  new live-row signals momentarily absent on snapshot. Acceptable (sub-second,
  `allowsHitTesting(false)`); will NOT add task/overdue signals to the snapshot.
- **P-8 — Sort axis and triage axis conflated. Severity: P2.** One ordering lever
  (`PeopleSort`, `:565-584`), hidden behind an icon menu (`:216-228`), disabled
  while searching (`:227`); no "which subset" lever.
- **P-9 — No bridge from "looking at this person" to "what do they owe me."
  Severity: P2.** From the list you can open a profile but not one-tap into the
  Tasks tab scoped to that person, despite `personSentinel` existing.

### Tasks integration (04-tasks-integration.md)

- **§3.1 — Dead meeting text in Tasks list row. Severity: P1.**
  `TaskRowView.swift:164-170` renders `Label(item.meetingTitle, "calendar")` inert
  (the table M1 made the identical cell clickable). (Surface M2.)
- **§3.2 — Dead meeting text in Tasks board card. Severity: P1.**
  `ActionItemsBoardView.swift:150` — `Text(item.meetingTitle)`, no button. (M3.)
- **§3.3 — Dead owner avatar on the board card. Severity: P2.**
  `ActionItemsBoardView.swift:130-132` — `TaskOwnerAvatar`, no nav even when
  `ownerPersonID` set. (O3.)
- **§3.4 — No open-task signal on People list rows. Severity: P2.** `PersonRow`
  (`PeopleListView.swift:615-648`) shows recency, no task count. *Overlaps with
  03 P-2 / P-5.* (C3.)
- **§3.5 — No open-task badge on meeting cards. Severity: P2.**
  `MeetingCard.content` (`MeetingCard.swift:123-175`) has health + outcome line,
  no "3 open tasks". (C4.)
- **§3.6 — Unresolved owners never resurface. Severity: P2.** When
  `PersonResolver.resolveOwner` returns nil, the task keeps owner text with
  `ownerPersonID == nil` forever; backfill loops
  (`MeetingPipelineController.swift:277-278, 438-439`;
  `QuickNotesController.swift:261-262`) run only at extraction; no review surface.
- **§3.7 — Orphaned-from-meeting tasks (stale `meetingID`/`meetingTitle`).
  Severity: P3.** Deleted meeting: nothing nulls `meetingID`; "Open meeting"
  degrades to text (guards at `ActionItemsTableView.swift:187`,
  `PersonDetailView.swift:1862`) but stays labeled "From <title>". Stale title:
  refreshes only on a re-extract hitting the same signature
  (`reconcileExtracted:1048`).
- **§3.8 — Two divergent owner-matchers. Severity: P3.**
  (1) `PersonResolver.resolveOwner`/`resolve` (`PersonResolver.swift:70-114`) —
  email/exact-name/exact-alias, never substring; used on every write.
  (2) `PersonDetailView.ownerMatchesPerson` (`:1731-1742`) + `ownerTokens`
  (`:1717-1729`) — hard-link first, then first-name token + substring
  (`owner.contains(full)`, `:1741`); used by `personTasks` (`:1744-1752`) to
  display. They disagree.
- **§3.9 — Non-navigable owner in meeting summary outcomesStrip. Severity: P3.**
  `MeetingSummaryTab.swift:214-216` — read-only `Text(owner)`, never linked even
  when `ownerPersonID` exists. *Overlaps with 01 P2 (third action render).* (O5.)

(04 §2 surface audit also catalogs the already-done items — M1/M5/M6 meeting nav,
O1/O2/O4/O6 owner nav, C1/C2/C5/C6 counts — preserved in the DONE markers below.)

### Layout & components (05-layout-components.md)

- **Drift class — native button chrome (repo-wide tally, §2.2).**
  `.buttonStyle(.borderedProminent)` ×29 (BAN); `.buttonStyle(.bordered)` ×11
  (BAN); `.controlSize(...)` ×88 (BAN on a `Button`; OK on ProgressView/TextField);
  `.buttonStyle(.borderless)` ×75 (BAN on a visible text action). These render
  native blue/gray push buttons ignoring the Bloom palette and 30/34pt tokens.
- **Worst offenders (§2.3), all within the five spec files:**
  1. `PersonDetailView.swift:1525-1532` — dead secondary identity header, "Brief
     Me" `.borderedProminent` + bare Edit/Delete. *Same as 02 P1-E / P2-I.* Worst
     single offender — fix first.
  2. `MeetingSummaryTab.swift:446-447` — `followUpButton`
     `.borderedProminent.controlSize(.regular)` + self-set `.font(.callout)` (`:444`).
  3. `MeetingSummaryTab.swift:714, 720` — "Save & regenerate" / "Just save" bare
     `Button.controlSize(.small)`, no style.
  4. `PersonDetailView.swift:1006` — health-popover "Log a check-in"
     `.borderedProminent.controlSize(.small).tint(NDS.brand)` (invents a lilac
     CTA). *Same as 02 P1-E.*
  5. `PersonDetailView.swift:884, 889, 895, 1172, 1601, 2431, 2524, 2528, 2611,
     2618` — `.borderless`+`NDS.small/.tiny` inline text cluster. *Same as 02 P2-J.*
  6. `PersonDetailView.swift:2036, 2122` region — mixed bordered/borderless next
     to `MSSecondaryButtonStyle`.
- **Eyebrow tracking inconsistent (§1.6).** `NotionEyebrow` `.tracking(0.6)`,
  `MSTintedHeaderCard` `.tracking(0.8)` (`MSComponents.swift:56`),
  `MSSectionHeader`/`MSSection` none. Standardize on `NDS.sectionLabel` +
  uppercase + `.tracking(0.6)`.
- **Hard-coded press springs (§1.5).** The four `MS*ButtonStyle` press animations
  hard-code `.spring(response: 0.3, dampingFraction: 0.7)`
  (`NotionDesign.swift:509, 545, 563, 579`) instead of `NDS.springStandard`. Don't
  introduce new hard-coded springs.
- **Untitled* legacy aliases (§2.1).** `UntitledPrimaryButtonStyle`
  (`NotionDesign.swift:497-511`) / `UntitledSecondaryButtonStyle` (`:514-526`)
  hard-code padding instead of tokens; treat any survivor as a swap target.
- **Canvas column left-pinned, not centered (§5.1).** Both canvases use
  `.padding(20).frame(maxWidth:760, alignment:.leading).frame(maxWidth:.infinity,
  alignment:.leading)` (`UnifiedMeetingDetail.swift:315-317`,
  `PersonDetailView.swift:583-585`) — centers the clamp then re-pins left; on a
  wide window the column hugs the left edge. Redesign centers at 760 with
  `NDS.spaceXL` padding.
- **`MSSection` adopted in zero call sites (§4).** Defined and merged
  (`MSComponents.swift:216-311`) but a grep for `MSSection(` in `Sources/` returns
  nothing — the redesign is its first consumer.

---

## Cross-cutting decisions

Shared decisions that touch more than one area, with the docs each came from.

1. **Shared `MSSection` is the de-tabbing spine.** `MSComponents.swift:216-311`:
   `MSSection(title, systemImage:, count:, persistenceKey:, defaultExpanded:,
   trailing:, content:)`. Chevron + eyebrow + count + a `trailing` accessory kept
   outside the toggle hit area; collapse persists under
   `@AppStorage("section.<key>.expanded")`; reduce-motion-aware; owns no
   horizontal padding (host wraps). *From 05 §4; consumed by 01 §4.3, 02 §4.2.*
   **Persistence-key namespacing:** `meeting.<x>` and `person.<x>` only (component
   prepends `section.`, appends `.expanded`); never collide. *05 §4.7.*

2. **One sanctioned button style per role (the button system).** Primary 34 /
   Secondary 30 / Tertiary `MSInlineButton` 28 / Icon `NotionIconButton`+`.minTap()`
   30-visible-44-hit / Danger 34 / Menu `.msMenuButtonChrome()` 30. Bans:
   `.borderedProminent`, `.bordered`, `.controlSize` on a Button, `.tint` to
   recolor a native button, `.borderless` on a visible text action, hand-built
   chrome. One Primary per section/header. *From 05 §2-3; the contract for 02 §3
   (61-button audit) and 01 (header buttons).*

3. **Canvas column recipe.** Max content width **760**, **centered**
   (`.frame(maxWidth:760).frame(maxWidth:.infinity, alignment:.center)`),
   `NDS.spaceXL` (24) horizontal + vertical padding, `NDS.spaceXL` between
   sections, `NDS.spaceMD` (12) within a section, `NDS.spaceSM` (8) per action
   row. Top inset (`splitPaneTopInset` 60 / `tabTopInset` 14) comes from the host,
   don't re-add. *From 05 §5; applied by 01 §4 and 02 §4. Note: the meeting canvas
   uses 20pt h-padding to match the header inset per 01 §4.3 — a deliberate local
   exception to the spaceXL rule; the person canvas uses 20pt per 02 §9.2.*

4. **Unified owner-matcher.** Collapse the two divergent matchers into
   `PersonResolver.taskBelongs(_:to:)` (hard-link first, else the same
   email/exact-name/exact-alias resolution used on write — never substring).
   `PersonDetailView.personTasks` adopts it; delete `ownerMatchesPerson` +
   `ownerTokens`. *From 04 §3.8 / §4.5; intentionally tightens the profile to
   match the rail/counts, so land re-resolve (04 B8) before tightening.*

5. **Shared task-link chips (deep-link reuse).** New
   `Sources/MeetingScribe/UI/TaskLinkChips.swift`: `TaskMeetingChip(item:)`
   (button → `router.openMeeting` when `meeting(id:)` resolves, else inert text;
   branches on `source == "voice_note"` → `router.route(kind:.voiceNote)`; nothing
   when `isManual`) and `TaskOwnerChip(item:, size:)` (avatar+name, button →
   `router.openPerson` when linked). Reused by Tasks list/board, meeting
   outcomesStrip, and the meeting canvas Outcomes section. *From 04 §4.1.*

6. **Person-scope task deep-link path (reuse, do not rebuild).**
   `router.openTasks(route: ActionItemsView.personSentinel(person.id))` — the
   existing `personSentinel` → `TasksRoute.person` → `TaskQuery.Scope.person` chain.
   Used by both the People-list task chip (03 §4.2, 04 §4.2) and the person
   canvas. *From 03 §4.1, 04 §4.2.*

7. **Reusable overdue predicate.** Extract `PeopleStore.isOverdueForCheckIn(_:)`
   + `overdueDays(_:)` from `overdueCheckInCount` (`:1367-1375`) /
   `overdueCheckInNames` (`:1379-1390`); pure refactor (nav badge unchanged).
   Single source of truth for the nav badge, the People "Needs attention" triage,
   the OVERDUE section, and the row pill. *From 03 §3.4; consumed by 03 §3.3/3.5/3.6.*

8. **Memoized per-person task-count index.** Mirror `encounterCountIndex` — one
   O(tasks) pass on task mutation into `[personID:TaskCounts]`, never
   `items(forPerson:)` per row (O(people×tasks)). New store helpers
   `openCount(forPerson:)` / `overdueCount(forPerson:)` / `unassignedOwnerTasks()`
   fold the duplicated inline predicates (TodayView, sidebar, PersonContextBuilder)
   into one place. *From 03 §3.8, 04 §4.5.*

9. **Bounded-height rule for self-scrolling panes (the C-A physics).** Every
   descendant containing `MarkdownEditor` / `RichMarkdownEditor` /
   `TranscriptSyncView` / `LiveTranscriptScroll` / `ChatPanel` must have a finite
   frame height before mount; the outer canvas is NOT a `ScrollView` around the
   editor. *From 01 §3 (C-A); the meeting canvas is the primary consumer; the
   person canvas's chat column is already separate so it's lower-risk there.*

10. **Design-lint CI guard.** Extend `scripts/design-lint.sh` with a button-chrome
    scan (`.borderedProminent`, `.bordered`, `.controlSize` on a Button excluding
    ProgressView/TextField), with a `// design-lint:allow` escape hatch; flip to
    `fail` in CI only after B-phase drives the count to zero. *From 05 §6 Group C.*

11. **Eyebrow + spring standardization.** Eyebrow = `NDS.sectionLabel` + uppercase
    + `.tracking(0.6)`; any new animation through `NDS.motion(_:reduce:)`; no new
    hard-coded springs (use `NDS.springStandard`). *From 05 §1.5-1.6, §7.*

---

## Global build sequencing

Dependency-ordered phases. The foundation ships first because both canvases and
Tasks stack on it. Within Tasks/People-list the order is "plumbing → signals →
structure → geometry → deep-links". The two big canvases (M, P) are
flag-gated / incremental and come after their button cleanup. Cleanup (X) is
last, after soak.

```
F (foundation: confirm primitives, button swaps, canvas recipe, lint guard)
│
├─ B (button normalization across the five files; depends on F's role table)
│
├─ T (tasks integration; chips + store helpers + counts + review + matcher)
│      │
│      └─ L (people list; consumes T's openCount + the overdue predicate)
│
├─ M (meeting canvas de-tab; depends on B for in-section buttons, T for the
│      Outcomes merge + navigable owner)
│
└─ P (person canvas de-tab; depends on B (Phase A buttons), T (taskBelongs,
       owner chips), and the promoted Tasks section)
│
X (cleanup: delete tab machinery, dead vars, flag branches — after soak)
```

Hard ordering edges:
- **F → everything.** `MSSection`, the button styles, and the canvas recipe must
  exist and be confirmed first. (Already merged — see DONE.)
- **B before M and P's structural change.** Buttons inside each section should be
  correct before the section container swaps (05 Group A before Group B; 02 Phase
  A before Phase C/D).
- **T (B8 re-resolve) before T (B7 tighten matcher).** Tightening the profile
  matcher drops legacy substring hits — land the re-resolve pass first/together so
  those tasks get real hard links (04 §3.8 risk).
- **T (openCount, overdue predicate) before L.** The People-list row pill, triage,
  and grouping all consume them.
- **L grouping (Increment 5) before triage (6) is fine**, but both gate on the
  task index (Increment 2) and the predicate (Increment 1).
- **M Outcomes merge (Step 3) needs `MeetingActionRow` owner-jump** (lift from the
  doomed `InlineActionItemRow`) — a small T-adjacent edit.

### Already DONE (do not re-implement)

- **Phase F (foundation) merged.** `MSSection`, `MSSectionHeader`,
  `MSInlineButton`, `msMenuButtonChrome`, `MSEmptyState`, `MSSkeleton`,
  `NotionIconButton`, the four `MS*ButtonStyle`, and all `NDS` tokens exist
  (05 Step 0 confirms; greenfield `MSSection` — first consumer is this work).
- **B1 (meeting-header buttons) merged.** The meeting header's Save/Cancel
  (Primary/Secondary), `MSInlineButton`, `msMenuButtonChrome` "Options", and the
  `MSDangerButtonStyle` Stop already follow the role table
  (`MeetingDetailHeader.swift:35/44/128/131/210/401-408`).
- **T1 merged** — owner→person link in summary `InlineActionItemRow`
  (`MeetingSummaryTab.swift:611-625`; 04 B0a / surface O4).
- **T2 merged** — Tasks table meeting-cell + owner navigation
  (`ActionItemsTableView.swift:145-157, 184-199`; 04 B0b / M1 / O1).
- **T3 merged** — person `taskRow` meeting link
  (`PersonDetailView.swift:1859-1872`; 04 B0c / M5).
- Also already navigable per 04 §2 (not separate increments): O2 (list-row owner),
  O6 (task-page assignee), M6 (task-page "From meeting"); count surfaces C1
  (rail People facet), C2 (Today), C5 (summary header), C6 (profile Tasks).

Everything else (the B2… button swaps, T B1-B11 minus B0a-c, all of L, all of M,
all of P, X) is remaining — enumerated in BUILD-PROMPTS.md.

---

## Known hard constraints

1. **MarkdownEditor can't nest in an outer ScrollView (C-A).**
   `MarkdownEditor.makeNSView` (`MarkdownEditor.swift:26-76`) builds its own
   `NSScrollView` with an unbounded-height text view; inside a SwiftUI `ScrollView`
   it gets infinite proposed height, the inner scroller never engages, two scroll
   systems fight, long notes push everything off-screen. `RichMarkdownEditor`
   (`:707`), `TranscriptSyncView` (`:114-123`), `LiveTranscriptScroll`
   (`MeetingTranscriptTab.swift:84`), and `ChatPanel` have the same shape. **The
   meeting canvas outer container is NOT a ScrollView around these** — short
   sections scroll together in one `ScrollView`; the editor/transcript/chat sit at
   explicit `geo`-derived bounded heights below it. Summary (read-only
   `MarkdownEditor`) gets a capped internal scroll `min(420, max(180, h*0.45))`.
   *01 §3 C-A; the single highest-risk constraint on the meeting canvas.*

2. **Lazy transcript (C-B).** `TranscriptSyncView` parses the raw transcript on
   appear (`:124-128`), builds a speaker map, renders a `LazyVStack` of hundreds of
   segments — the most expensive thing on the page. Never mount eagerly: gate on
   the section's expanded state + a `transcriptEverExpanded` latch; `.past`
   defaults collapsed, `.live`/`.upcoming` expanded. *01 §3 C-B.*

3. **Mode multiplex (C-C / C-D).** The transcript slot is three unrelated views by
   mode (live scroll / pre-meeting brief / synced transcript). Keep the `switch
   mode` inside the section body but make the section title + default-collapse
   mode-aware (`transcriptSectionTitle`); omit the whole section for `.past` with
   no transcript (no empty husk). One shared `AudioPlayerController` (C-D) stays as
   `@StateObject` on the parent so audio survives a collapsed transcript. *01 §3
   C-C / C-D.*

4. **Person "fit is good" risk.** The user confirmed nothing clips today. The
   redesign widens the constraint (300pt rail → ~720pt canvas) which is safer, but
   three new fit risks must be guarded: **R1** compactHeader Row 1 (long name +
   Brief Me + ⋯) — `lineLimit(1).truncationMode(.tail)` + `Spacer(minLength:8)`,
   buttons right-anchored and never clip; **R2** compactHeader Row 2 (type picker +
   health + known-since) — must be a `FlowLayout` so it wraps; **R3** HSplitView
   mins lowered (detail 560→480, chat 320→300, floor ~780) — keep generous
   idealWidths. **Rule: never a fixed-width HStack of ≥2 growable text controls —
   put it in a FlowLayout.** *02 §5.*

5. **Board-card drag vs nested button.** `ActionItemsBoardView` cards are
   `.draggable`; a nested `TaskMeetingChip`/`TaskOwnerChip` button can swallow the
   drag start — verify drag still works (the title is the drag handle). *04 B3.*

6. **`ActionItemStore` env injection is a runtime, not compile, dependency.**
   Injecting it into the People list (03 Increment 2) needs a `make install`
   runtime check — a missing `@EnvironmentObject` is a crash, not a build error.
   *03 §5 Increment 2.*

7. **People-list perf invariants.** The synchronous `snapshotRows` fast-path must
   render frame-0; no O(n²) per render (memoize task counts); search stays FTS5
   relevance-ordered with NO grouping/sort while querying; `selection` ↔
   `router.selectedPersonID` two-way sync intact. *03 §0.3.*

8. **Don't null `meetingID` on meeting delete.** It would flip
   `isManual`/`needsTriage` and change `signature`, silently un-deduping the task
   against its own history. Prefer the soft degrade (inert chip + "source meeting
   deleted" tooltip). *04 §3.7 / §4.4 / §6.2.*
