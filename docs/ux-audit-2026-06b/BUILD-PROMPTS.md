# Deep Page Redesign — Build Prompts (2026-06 round 2)

*Ordered, paste-and-build. House rules: `swift build -c release` → confirm `Build complete!` + no real `error:` BEFORE merge; squash-merge; `make install` every ~2 increments. Each prompt is one mergeable increment.*

## Phase F — Foundation (do first; everything depends on it)
- **F1** In `MSComponents.swift` add `MSInlineButton(title:systemImage:action:)` (wraps `MSTertiaryButtonStyle`) and `View.msMenuButtonChrome()` (surface + `NDS.radius` + hairline + `buttonSecondaryH`). Add a header comment with the role→style→height table. No call-site changes.
- **F2** In `MSComponents.swift` add `MSSection<Content,Trailing>` (collapsible: chevron + `NDS.sectionLabel` title + optional count + `trailing()` outside the toggle hit area; `@AppStorage("section.<key>.expanded")` when `persistenceKey` set else `@State`; `NDS.motion` animation) + an `EmptyView` convenience init. Pure addition.

## Phase B — Button cleanup (after F1)
- **B1** `MeetingDetailHeader.swift:404-417` Options menu → `msMenuButtonChrome()` (radius 14 to match the primary CTA); attendee-rail buttons (36-57) → `MSInlineButton`.
- **B2** `PersonDetailView.swift`: `:1006` `.borderedProminent.controlSize(.small)` → `MSPrimaryButtonStyle`; `:884/889/895` `.borderless`+small → `MSInlineButton`; `:1073/1134` bare `Button("Add")` → `MSTertiaryButtonStyle`; `.borderless` accessories `:1170/1562/1601/1708/1881/2382/2421` → `MSTertiaryButtonStyle`; icon-only `.borderless` → `.minTap()`.

## Phase T — Tasks linkage (independent; after F)
- **T1** `MeetingSummaryTab.swift:610-612` — owner chip → avatar + `Button { router.openPerson(ownerPersonID) }` when set; inject `router`.
- **T2** `ActionItemsTableView.swift` — meeting cell (174-177) → `Button { router.openMeeting }`; owner (146) navigates when `ownerPersonID != nil`.
- **T3** `PersonDetailView.taskRow:1859-1862` — meeting label → `Button { router.openMeeting }`.
- **T4** `ActionItemStore` — add `openCount(forPerson:)`, `overdueCount(forPerson:)`, `unassignedOwnerTasks` (+ unit test). No UI.
- **T5** `MeetingCard.swift` (~121-195) — "N open" task chip from `items(for:)` when >0.
- **T7** `ActionItemsSidebar` — "Unassigned owners" bucket via `__unassigned__` sentinel; link-to-person reuses `TaskPageView` picker (289-293).
- **T8** `TaskPageView:371-387` — "meeting deleted" non-interactive state when `meeting(id:)==nil`; extract one shared `ownerMatchesPerson` helper used by profile + `items(forPerson:)`.

## Phase M — Meeting canvas de-tab (after F2)
- **M1** `@AppStorage("meetingCanvasV2")` flag + `canvasBody` scaffold (renders existing `combinedNotesBody`); `body` switches on flag. Off = unchanged.
- **M2** Outcomes `MSSection` (merge `actionsBody` CRUD + decisions; drop read-only preview + legacy `actionItemsSection`; triage badge + "→ Tasks" in header).
- **M3** Notes `MSSection`: `currentNotesEditor` in `.frame(minHeight:240, idealHeight: geo*0.4)` + drag-resize (Constraint A).
- **M4** Summary `MSSection` + generating/failed banners.
- **M5** Transcript `MSSection` lazy + mode-multiplexed (Constraints B/C).
- **M6** Ask AI `MSSection` lazy fixed-height.
- **M7** Related/linked + rewire `consumeTranscriptQuery`/highlights/`reviewBanner` to expand+scroll, not `tab=`.
- **M8** Flip `meetingCanvasV2` default true; soak.
- **M9** Delete `tabPicker`/`switch tab`/`applySmartTabDefault`/`actionsBody`/legacy bodies/`DetailTab`.

## Phase P — Person canvas de-tab (after F2 + B2)
- **P1** Compact header: replace both `identityPanel` button rows with `Brief Me` (primary) + `⋯` overflow (Edit/Edit all/Log encounter/Add relationship/Ask AI/Delete); type menu + health in a `FlowLayout` metadata row. **Eyeball fit vs baseline.**
- **P2** Collapse inner two-pane into one `ScrollView` column, still keyed off `personTab` (transitional).
- **P3** Convert sections to `MSSection` (table in `02`); promote **Tasks** to top-level expanded section; delete `PersonTab`/`personTab`/`workArea`/`workContent`/`MSPillTabs` use; repoint `keyboardVerbs` (N→notes section, T→Tasks; drop ⌘1-5).

## Phase L — People list (independent)
- **L1** `PeopleStore` — extract `isOverdueForCheckIn(_:)` (refactor `overdueCheckInCount`/`Names`). No UI.
- **L2** `PeopleListView` — `@EnvironmentObject actionItems` + `taskCounts` index (compute in `.task`/`onChange`). No render.
- **L3** Richer `PersonRow`: overdue pill + task chip; pass `overdue`+`counts` from both ForEach sites.
- **L4** Sectioned list (Overdue/This week/Everyone else) when no-search & no-type-filter; collapsible headers w/ counts.
- **L5** Triage segmented control (All/Needs attention/Has tasks) in `filtered`.
- **L6** Density toggle threaded into `PersonRow`.
- **L7** Widen sidebar `280/340/420`; "Mark reached out" in `personRowMenu` when overdue.
- **L8** Type-chip counts + task-chip → Tasks deep-link (`TaskQuery.Filter.person`).

## Phase X — Cleanup
- **X1** Standardize both canvas `VStack`s to `spacing: NDS.spaceXL`; extend `design-lint.sh` to fail on `.borderedProminent`/`.bordered`/`.controlSize` on `Button`.
- **X2** Retire unused `MSPillTabs`/`DetailTab`/`PersonTab` if no remaining references.

**Suggested overall order:** F1·F2 → B1·B2 → T1·T2·T3 → L1·L2·L3·L4 → M1…M9 → P1·P2·P3 → T4·T5·T6 → L5…L8 → T7·T8 → X.
