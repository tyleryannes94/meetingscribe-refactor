# MASTER — De-tab Meetings + People, Fix Buttons, Integrate Tasks

*Consolidated plan for the round-2 deep redesign (`docs/ux-audit-2026-06b`). Reconciles all five area docs (`01`–`05`) into one complete problem inventory, the cross-cutting decisions, and one global build sequence. **Every numbered finding from every doc is reproduced below** — grouped by area, with file:line evidence and severity preserved. The `01`–`05` docs hold the full detail (700–900 lines each); this is the index + sequencer.*

## Goal
Replace the tabbed Meeting- and Person-detail views with single scrolling canvases of collapsible `MSSection`s (everything visible at once), fix the inconsistent/"weird" button sizes by routing every action through the existing `MS*ButtonStyle` system, make the People list answer "who needs me right now?", and make Tasks feel connected to the meeting they came from and the person who owns them.

## Area map
| Doc | Area | Headline change |
|-----|------|-----------------|
| 01-meeting-detail.md | Meeting detail | 4 tabs → one collapsible canvas (flag-gated migration) |
| 02-person-detail.md | Person detail | de-cram to compact header + `MSSection` stack; fix buttons; de-tab |
| 03-people-list.md | People list | triage grouping + richer rows + task signals |
| 04-tasks-integration.md | Tasks ↔ Meetings/People | navigable owner/meeting everywhere; count badges; unify matchers |
| 05-layout-components.md | Shared system | button rules + `MSSection` + spacing + CI lint guard |

---

## Complete problem inventory

### A. Meeting detail (from `01`)
| ID | Problem | Evidence | Severity |
|----|---------|----------|----------|
| **P1** | Tab fragmentation: one page cut into four | `DetailTab` (`MeetingTranscriptTab.swift:172`) drives exclusive `switch tab` (`UnifiedMeetingDetail.swift:157-164`) via `MSPillTabs` (`tabPicker:254`) | high |
| **P2** | Action items rendered in **three** places, two stale | `outcomesStrip` (`MeetingSummaryTab.swift:195-235`) read-only preview · `actionsBody` (`UnifiedMeetingDetail.swift:277-320`) the real CRUD · `actionItemsSection` (`MeetingSummaryTab.swift:472-537`) a 2nd full list via legacy `pastSummaryBody` | high |
| **P3** | `applySmartTabDefault` guesses the page & races a 300ms timer | `:427-444`, `Task.sleep` `:436`, fills vs `reload()` `:369` non-deterministically; `hasAppliedTabDefault` guard `:428` | medium |
| **P4** | Cross-tab teleports lose scroll + notes caret | `highlightsStrip` `tab=.transcript` (`MeetingSummaryTab.swift:168`); `consumeTranscriptQuery` (`MeetingTranscriptTab.swift:58`); `reviewBanner onReviewTasks` (`UnifiedMeetingDetail.swift:139`) | medium |
| **P5** | Mode-multiplexed content hidden in tab slots | `transcriptBody` (`MeetingTranscriptTab.swift:19-51`) is live/upcoming(brief)/past by mode | medium |
| **P6** | Header density eats 250–300pt before content | `header` (`MeetingDetailHeader.swift:8-106`) stacks 8 rows + reviewBanner + audioBar + tabPicker | low–med |
| **P7** | Generating/failed summary states duplicated & inconsistent | new `summaryGeneratingBanner`/`summaryFailedBanner` (`MeetingSummaryTab.swift:70/91`) vs legacy `pastSummaryBody`/`emptySummaryView` (`:335/400`); 240pt cap mismatch | medium |

### B. Person detail (from `02`)
| ID | Problem | Evidence | Severity |
|----|---------|----------|----------|
| **P1-A** | Three-column cram on default width | `body:366-375` forces identityPane(300)+workArea+chat(320) all visible; ~880pt min | P1 |
| **P1-B** | 300pt identityPane overload (7 stacked sections) | `:503-518`; `EncounterHeatMap:1677` etc. clip inside 268pt usable | P1 |
| **P1-C** | Two ragged FlowLayout button rows, mixed heights | Row1 `:852-875` (34pt Primary + 30pt Secondary mix); Row2 `:880-897` (`.borderless`+`.font(NDS.small)`) | P1 |
| **P1-D** | Sub-44pt taps on important verbs | Log encounter/Relationship/Ask AI `:884/889/895` borderless, no `.minTap()` | P1 |
| **P1-E** | `.borderedProminent` reconnect/health CTAs | `healthWhyPopover:1003-1006`; dead `header:1525-1528` | P1/P2 |
| **P1-F** | Bare `Button("Add")`/`Button("Run")` everywhere | `:1073,1134,1782,1890,2308,2354,2827,1269,1600` | P1 |
| **P1-G** | "A bunch of unnecessary tabs" | `MSPillTabs:574` so narrow it had to scroll (`MSComponents.swift:88-92`); hides Tasks under Meetings | P1 |
| **P2-H** | Scrolling section-nav pills (dead cram tell) | `sectionNav`/`sectionNavItems:698-738` | P2 |
| **P2-I** | Duplicate "Brief Me" + duplicate "Notes" | Brief Me `:856` & `:1525`; Notes = bio `:1655` & attached `:2576` | P2 |
| **P2-J** | Inline-text-action `.borderless` clusters | Analyze `:2431`, addEmail `:1564`, Suggest `:1172`, photos `:1601`, Save-to-notes `:2524` | P2 |
| **P3-K** | Menus with no chrome | `:1048,1708,2394` `.menuStyle(.borderlessButton)` → want `.msMenuButtonChrome()` | P3 |

### C. People list (from `03`)
| ID | Problem | Evidence | Severity |
|----|---------|----------|----------|
| **P-1** | Flat, undifferentiated scroll | single `ForEach(filtered):319-324`, no anchors among 500+ | P1 |
| **P-2** | `PersonRow` under-signals (no overdue, no task counts) | `:614-653`; `items(forPerson:)` exists `ActionItemStore.swift:1259` | P1 |
| **P-3** | Reconnect intelligence buried in no-selection dashboard | `goneCold`/etc. `PeopleInsightsView:84-147`, only when `selection==nil` `:557` | P1 |
| **P-4** | No grouping (sort ≠ triage) | `sorted(_:):71-82` reorders but can't bucket | P1 |
| **P-5** | Tasks↔People never meet in the list | `ownerPersonID` consumed only in `PersonDetailView`; list has no `ActionItemStore` | P2→P1 |
| **P-6** | Static geometry/density | sidebar fixed `260/320/380:113`; row fixed `.padding(.vertical,3)` | P3 |
| **P-7** | Snapshot/live row divergence risk | `SnapshotPersonRow:589-612` vs `PersonRow` independent (accepted; document) | P3 |
| **P-8** | Sort axis & triage axis conflated | one `PeopleSort:565-584` hidden in icon menu, disabled while searching | P2 |
| **P-9** | No bridge from "looking at person" → "what they owe" | no one-tap list→scoped-Tasks despite `personSentinel` existing | P2 |

### D. Tasks integration (from `04`)
| ID | Gap | Evidence | Severity |
|----|-----|----------|----------|
| **3.1** | Dead meeting text in Tasks **list** row | `TaskRowView.swift:164-170` inert | P1 |
| **3.2** | Dead meeting text in Tasks **board** card | `ActionItemsBoardView.swift:150` | P1 |
| **3.3** | Dead owner avatar on **board** card | `ActionItemsBoardView.swift:130-132` | P2 |
| **3.4** | No open-task signal on **People list** rows | `PersonRow:615-648` | P2 |
| **3.5** | No open-task badge on **meeting cards** | `MeetingCard.content:123-175` | P2 |
| **3.6** | Unresolved owners never resurface | backfill only at extraction (`MeetingPipelineController.swift:277-278,438-439`; `QuickNotesController.swift:261-262`); no review surface | P2 |
| **3.7** | Orphaned-from-meeting tasks (stale `meetingID`/`meetingTitle`) | nothing nulls on delete; title only refreshes on re-extract (`reconcileExtracted:1048`) | P3 |
| **3.8** | Two divergent owner-matchers | `PersonResolver.resolveOwner:70-114` (strict) vs `PersonDetailView.ownerMatchesPerson:1731-1742` (substring) | P3 |
| **3.9** | Non-navigable owner in summary `outcomesStrip` | `MeetingSummaryTab.swift:214-216` read-only `Text(owner)` | P3 |

### E. Layout/components — worst button offenders (from `05`)
| Rank | Offender | Why weird |
|------|----------|-----------|
| 1 | `PersonDetailView.swift:1525-1532` (dead 2nd identity header) | `.borderedProminent` Brief Me + bare-default Edit/Delete; duplicate of correct cluster `:856-874` — **fix/delete first** |
| 2 | `MeetingSummaryTab.swift:446-447` (`followUpButton`) | `.borderedProminent` blue hero on a coral page |
| 3 | `MeetingSummaryTab.swift:714,720` (Save&regenerate / Just save) | bare `Button(...).controlSize(.small)`, not the MSPrimary+MSSecondary pair |
| 4 | `PersonDetailView.swift:1006` (Log a check-in) | `.borderedProminent.tint(NDS.brand)` invents a lilac native CTA |
| 5 | `PersonDetailView.swift:884,889,895,1172,1601,2431,2524,2528,2611,2618` | `.borderless`+`.font(NDS.small/.tiny)` link-blue, drifting 11/12pt heights |
| 6 | `PersonDetailView.swift:2036,2122` region | mixed bordered/borderless in one cluster |

Ad-hoc tally (repo-wide, `05` §2.2): ~29 `.borderedProminent`, 11 `.bordered`, 88 `.controlSize`, 75 `.borderless`, 200 `.plain` vs 22/25 `MS*` styled.

---

## Cross-cutting decisions
- **One collapsible primitive — `MSSection`** (built Phase F, `MSComponents.swift`). Both canvases stack these; collapse state persists via `section.<key>.expanded`. (01 §4.3, 02 §0.2/§4.2, 05 §4.) Key convention `section.meeting.*` / `section.person.*` (05 §4.7).
- **One button system** — every action uses an `MS*ButtonStyle`; bans `.bordered`/`.borderedProminent`/`.controlSize`/bare `.borderless` for actions. Wrappers `MSInlineButton` (28pt tertiary) + `msMenuButtonChrome()` (built Phase F). (05 §3, referenced by 01/02.)
- **Shared canvas column recipe** — `maxWidth 760` **centered**, h-pad `NDS.spaceLG`, between-section `NDS.spaceXL`, within-section `NDS.spaceSM`; one density. Both canvases currently left-pin at hard-coded 20 (`UnifiedMeetingDetail.swift:315-317`, `PersonDetailView.swift:583-585`) — fix to centered tokens. (05 §5.)
- **Unified owner-matcher** — collapse the two implementations into one `PersonResolver.taskBelongs` used by both the profile and the People facet. (04 §3.8/§4.5.)
- **Reuse existing deep-link** — People→Tasks uses the existing `ActionItemsView.personSentinel` route; no new router/TaskQuery plumbing. (03 §4.1, 04.)
- **Per-row task counts are memoized**, never per-row `items(forPerson:)` (O(n·rows)); a `[personID:(open,overdue)]` index mirrors `encounterCountIndex`. (03 §3.8.)
- **CI guard** — extend `design-lint.sh` to fail on `.borderedProminent`/`.bordered`/`.controlSize` on `Button`. (05 §6.3.)

## Hard constraints (do not fight)
- **C-A:** `MarkdownEditor`/`RichMarkdownEditor` is `NSScrollView`-backed (`isVerticallyResizable`, `greatestFiniteMagnitude`) — it CANNOT nest in an outer `ScrollView`. The notes/transcript/chat panes get **bounded explicit heights** and scroll internally; the page scrolls via collapsed short headers. A top-level `ScrollView` is safe only once every long child has a fixed frame. (01 §3 C-A.)
- **C-B:** `TranscriptSyncView` is heavy — lazy-mount behind a collapsed disclosure (`if expanded { … }`). (01 §3 C-B.)
- **C-C:** transcript slot multiplexes live/upcoming/past — keep the multiplex, relabel the section per mode. (01 §3 C-C.)
- **C-D:** one shared `AudioPlayerController`. (01 §3 C-D.)
- **Person "fit is good now"** — current no-clip safety = FlowLayout wraps + scrolling pills; the redesign moves actions to the wide canvas (≥480–560pt) and keeps FlowLayout for the metadata row. Flag fit risk on every person step (R1 name overflow, R2 metadata wrap, R3 mins). (02 §5.)

---

## Complete build sequence (every increment from every doc)

Phase order **F → B → T → L → M → P → X**. ✅ = merged. Each increment compiles green before merge; `make install` every ~2.

### Phase F — Foundation ✅
- **F1** ✅ `MSInlineButton` + `msMenuButtonChrome()` (`MSComponents.swift`).
- **F2** ✅ `MSSection` collapsible (+ `EmptyView` convenience init).

### Phase B — Buttons (05 Group A + 02 Phase A)
- **B1** ✅ Meeting-header: Options menu → `msMenuButtonChrome()`; attendee-rail → `MSInlineButton` (`MeetingDetailHeader.swift`).
- **B2** Delete dead person code: `header:1511-1534`, `tagRow:1536-1540`, `sectionNav`/`sectionNavItems:698-738` (clears offender #1 + P2-H). *(02-A1)*
- **B3** `healthWhyPopover` "Log a check-in" `.borderedProminent`→`MSPrimaryButtonStyle` (`PersonDetailView.swift:1003-1006`, offender #4). *(02-A2)*
- **B4** Person `.borderless`/bare text actions → `MSInlineButton` (tags/favorites/talking-points/memories/photos/suggest/analyze/save/deep, P1-F/P2-J, offender #5). *(02-A3)*
- **B5** Person glyph buttons → `NotionIconButton`+`.minTap()` or `.plain`+`.minTap()` (chip×, reset chat, remove-rel, log-meeting+, memory delete, dismiss, expand/delete, encounter delete). *(02-A4)*
- **B6** Person menu chrome: `relationshipTypePicker:1041-1049`, `checkInGoalMenu:1704-1710`, Scan menu `:2387-2394` → `.msMenuButtonChrome()` (P3-K). *(02-A5)*
- **B7** Person sheet/popover footers → Secondary; sheet confirms → Primary (addEmail/reconnect/evidence/customPrompt/addToMeeting/AddRelationshipSheet). *(02-A6)*
- **B8** `MeetingSummaryTab.swift:446-447` `followUpButton` `.borderedProminent`→`MSPrimaryButtonStyle` (offender #2). *(05 Group A)*
- **B9** `MeetingSummaryTab.swift:714,720` Save&regenerate/Just save → MSPrimary+MSSecondary pair (offender #3). *(05 Group A)*

### Phase T — Tasks linkage (04 build plan)
- **T1** ✅ Owner→person nav in meeting summary `InlineActionItemRow` (`MeetingSummaryTab.swift`).
- **T2** ✅ Table meeting-cell + owner navigate (`ActionItemsTableView.swift`).
- **T3** ✅ Person `taskRow` source-meeting link (`PersonDetailView.swift`).
- **T4** ✅ `openCount/overdueCount(forPerson:)` + `unassignedOwnerTasks()` (`ActionItemStore.swift`). *(04-B4)*
- **T5** Shared `TaskMeetingChip`/`TaskOwnerChip` components. *(04-B1)*
- **T6** Adopt `TaskMeetingChip` in the Tasks **list** row — closes 3.1 (`TaskRowView.swift:164-170`). *(04-B2)*
- **T7** Adopt chips on the **board** card — closes 3.2, 3.3 (`ActionItemsBoardView.swift:130-132,150`). *(04-B3)*
- **T8** Open-task badge on **meeting cards** — closes 3.5 (`MeetingCard.swift:123-175`). *(04-B6)*
- **T9** Open-task pill on People-list rows — closes 3.4 (same chip as L3; built once). *(04-B5)* ✅
- **T10** Unify owner-matcher → `PersonResolver.taskBelongs` — closes 3.8. *(04-B7)*
- **T11** Re-resolve unassigned owners on People mutation — closes 3.6 pt1. *(04-B8)*
- **T12** "Unassigned owners" review rail — closes 3.6 pt2 (`ActionItemsSidebar`). *(04-B9)*
- **T13** `refreshMeetingTitle` on rename + deleted-meeting degrade tooltip — closes 3.7. *(04-B10)*
- **T14** Owner nav in summary `outcomesStrip` — closes 3.9 (`MeetingSummaryTab.swift:214-216`). *(04-B11)*

### Phase L — People list (03 build plan)
- **L1** ✅ Extract `isOverdueForCheckIn`/`daysOverdue` (`PeopleStore.swift`). *(03-Inc1)*
- **L2** ✅ Inject `ActionItemStore` + memoized task-count index (`PeopleListView.swift`). *(03-Inc2)*
- **L3** ✅ `PersonRow` task chip. *(03-Inc3, = T9)*
- **L4** ✅ `PersonRow` overdue pill. *(03-Inc4)*
- **L5** ✅ Section grouping + triage segmented control. *(03-Inc5 + Inc6)*
- **L6** Density toggle (comfortable/compact) + optional meeting-count signal. *(03-Inc7)*
- **L7** ✅ Widen sidebar `280/340/420`. *(03-Inc9)*
- **L8** ✅ Task-chip deep-link + "Mark reached out" row action. *(03-Inc8)*
- **L9** Birthday/special-date clause for "This week" grouping. *(03-Inc9)*
- **L10** Polish + edge passes (search-mode no-grouping, snapshot divergence note, select-mode). *(03-Inc10)*

### Phase M — Meeting canvas de-tab (01 build plan; flag `meetingCanvasV2`)
- **M0** Confirm `MSSection`+tokens (done via F). *(01-Step0)*
- **M1** Flag + canvas scaffold (flag-off identical). *(01-Step1)*
- **M2** Canvas chrome split: top `ScrollView` group vs bottom group (C-A). *(01-Step2)*
- **M3** Outcomes section (the P2 merge: `MeetingActionRow` CRUD + decisions; drop preview + legacy `actionItemsSection`). *(01-Step3)*
- **M4** Highlights section. *(01-Step4)*
- **M5** Notes section (bounded editor + drag grabber, C-A). *(01-Step5)*
- **M6** Summary section (+ generating/failed unification, P7). *(01-Step6)*
- **M7** Transcript section (lazy + mode-multiplex, C-B/C-C). *(01-Step7)*
- **M8** Ask AI section + rewire teleports to scroll-to-anchor (P4). *(01-Step8)*
- **M9** Related & linked section + reviewBanner rewire; flip the flag. *(01-Step9)*
- **M10** Cleanup: delete `tabPicker`/`switch tab`/`applySmartTabDefault`/`actionsBody`/legacy bodies/`DetailTab`. *(01-Step10)*

### Phase P — Person canvas de-tab (02 build plan)
- **P1** `compactHeader` var (avatar + name + one Primary "Brief Me" + ⋯ overflow; type+health in FlowLayout metadata row). *(02-B1)*
- **P2** Swap `identityPanel` button rows for `compactHeader` (still in identityPane — tightest fit test). *(02-B2)*
- **P3** Introduce `personCanvas` (one ScrollView, sections inline, no tabs yet). *(02-C1)*
- **P4** Repoint `body` to two-column split; delete `detailPane`/`identityPane`/`workArea`/`workContent`. *(02-C2)*
- **P5** Convert each section to `MSSection` (strip per-section eyebrows; rename Notes→About/Saved analyses); promote **Tasks** to top-level expanded. *(02-D1)*
- **P6** Delete `MSPillTabs` usage + `PersonTab` + `personTab`. *(02-D2)*
- **P7** Rewrite `keyboardVerbs` (N expand-then-focus memories; T focus task field; drop ⌘1–5). *(02-E1)*
- **P8** Empty-states + consistency pass (self-hide vs inline empty line; provenanceFooter once). *(02-F1)*
- **P9** Reduce-motion + a11y labels. *(02-F2)*
- **P10** Build verification. *(02-F3)*

### Phase X — Cleanup / system
- **X1** Standardize both canvas columns to centered `maxWidth 760` + `NDS.spaceXL`/`spaceLG` tokens. *(05 §5)*
- **X2** `MSSection` adoption sweep for any remaining bare-VStack sections (05 Group B).
- **X3** Extend `design-lint.sh` to fail on `.borderedProminent`/`.bordered`/`.controlSize` on `Button` (05 Group C).

**Suggested order:** F ✅ → B1 ✅ → T1–T4 ✅ → L1–L5 ✅ → L7,L8 ✅ → **B2–B9 → L6,L9,L10 → T5–T8 → M1–M10 → P1–P10 → T10–T14 → X1–X3.** (T9/L3 are the same chip — already built.)

**Counts:** ~42 distinct problems/gaps (7 + 11 + 9 + 9 + 6 offenders) across the five docs; ~57 build increments (B:9, T:14, L:10, M:11, P:10, X:3), of which 13 are ✅ merged.
