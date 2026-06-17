# BUILD-PROMPTS — De-tab Meetings + People, Fix Buttons, Integrate Tasks

*Ordered, paste-and-build increment list. Covers every buildable step from all
five area docs (01-05), mapped into the global phase order from MASTER.md.*

**House rule (every increment).** Each increment must compile before merge: run
`swift build -c release` from `~/MeetingScribeRefactor` and confirm `Build
complete!` with no real `error:` (warnings are fine). Run `make install` roughly
every ~2 increments to click-test in the real app. Per CLAUDE.md, after applying
edits ask once whether to commit and push.

**Phase order:** F (foundation) → B (buttons) → T (tasks) → L (people list) →
M (meeting canvas) → P (person canvas) → X (cleanup). Within a phase the listed
order is the dependency order.

Legend: ✅ DONE (merged) · ❌ remaining. IDs in parentheses are the source doc's
own increment IDs.

---

## Phase F — Foundation (05-layout-components)

### ✅ F0 — Confirm `MSSection` + button styles + tokens (DONE)
- **Files:** none (verification only).
- **Change:** `MSSection`, `MSSectionHeader`, `MSInlineButton`,
  `msMenuButtonChrome`, `MSEmptyState`, `MSSkeleton`, `NotionIconButton`, the four
  `MS*ButtonStyle`, and all `NDS` tokens exist (`MSComponents.swift`,
  `NotionDesign.swift`). Greenfield `MSSection` — this work is its first consumer.
- **Verify:** `swift build -c release` baseline green.

### ❌ F1 (05 §5.1) — Centered 760 canvas-column recipe helper
- **Files:** `MSComponents.swift` (or `NotionDesign.swift`).
- **Change:** add a small reusable modifier/recipe for the canvas column: `maxWidth
  760` then `maxWidth: .infinity, alignment: .center` (replacing the current
  left-pinned clamp), with `NDS.spaceXL` h/v padding. Both canvases adopt it in M/P.
- **Verify:** builds; a sample `ScrollView { ... }.canvasColumn()` centers on a wide window.

### ❌ F2 (05 §1.6) — Standardize the eyebrow + spring tokens
- **Files:** `MSComponents.swift`, `NotionDesign.swift`.
- **Change:** eyebrow convention = `NDS.sectionLabel` + `.textCase(.uppercase)` +
  `.tracking(0.6)` wherever section labels render; replace the four hard-coded
  `.spring(response:0.3, dampingFraction:0.7)` press springs
  (`NotionDesign.swift:509,545,563,579`) with `NDS.springStandard`.
- **Verify:** builds; section labels render uniformly; press feel unchanged.

---

## Phase B — Button normalization (05 Group A · 01 header · 02 Phase A)

### ✅ B1 (01) — Meeting-header buttons (DONE)
- Meeting header Save/Cancel (Primary/Secondary), `MSInlineButton`,
  `msMenuButtonChrome` "Options", `MSDangerButtonStyle` Stop already follow the
  role table (`MeetingDetailHeader.swift:35/44/128/131/210/401-408`).

### ❌ B2 (05 A1 / 02 A1) — PersonDetailView dead secondary identity header (worst offender)
- **Files:** `PersonDetailView.swift:1525-1532`.
- **Change:** "Brief Me" `.borderedProminent` → `MSPrimaryButtonStyle`; bare Edit →
  `MSSecondaryButtonStyle`; `Delete(role:.destructive)` → keep role + apply
  `MSSecondaryButtonStyle` (destructive-tinted secondary). Ideally delete this dead
  `header` entirely and reuse the canonical cluster at `:856-874`.
- **Verify:** the two "Brief Me/Edit/Delete" clusters render identically; lint no longer flags the line.

### ❌ B3 (05 A2 / 02 A2) — PersonDetailView health-popover CTA
- **Files:** `PersonDetailView.swift:1003-1006`.
- **Change:** "Log a check-in" `.borderedProminent.controlSize(.small).tint(NDS.brand)`
  → `.buttonStyle(MSPrimaryButtonStyle())` (drop `.tint`).
- **Verify:** popover button renders coral 34pt.

### ❌ B4 (05 A3) — MeetingSummaryTab `followUpButton`
- **Files:** `MeetingSummaryTab.swift:444-447`.
- **Change:** `.borderedProminent.controlSize(.regular)` → `MSPrimaryButtonStyle`;
  remove the label's `.font(.callout)` (`:444`).
- **Verify:** "Draft follow-up…" renders coral 34pt.

### ❌ B5 (05 A4) — MeetingSummaryTab feedback pair
- **Files:** `MeetingSummaryTab.swift:714, 720`.
- **Change:** "Save & regenerate" → `MSPrimaryButtonStyle`; "Just save" →
  `MSSecondaryButtonStyle`; remove both `.controlSize(.small)`; keep `.disabled` on the primary.
- **Verify:** the pair matches the Primary+Secondary pattern used elsewhere.

### ❌ B6 (02 A3 / 05 A5) — PersonDetailView bare/`.borderless` text actions → `MSInlineButton`
- **Files:** `PersonDetailView.swift` — 02 §3 #11,13,14,16,24,27,43,45,48,50,53
  (tag/favorite/talking-point/memory/photos/suggest/analyze/save/deep/suggestionRow
  "Add"/"Run"/"Refresh"); lines incl. `1073, 1134, 1172, 1269, 1564, 1600, 2308,
  2354, 2431, 2524, 2827`.
- **Change:** each → `MSInlineButton("Title", systemImage:) { action }`; preserve
  `.disabled`/`.help`/`.accessibilityLabel` (attach to the `MSInlineButton`).
  Colored semantic links (`NDS.accent/mint/textTertiary` at `:1564, 2319, 2365,
  2977`) need per-case judgement.
- **Verify:** each renders 28pt muted; visually scan each section.

### ❌ B7 (02 A4) — PersonDetailView glyph buttons → `NotionIconButton`+`.minTap()` or `.plain`+`.minTap()`
- **Files:** `PersonDetailView.swift` — `.minTap()` only (tint meaningful): #29
  (task checkbox done/open, `:1835-1842`), #44 (talking-point done mint, `:2316`).
  `NotionIconButton`+`.minTap()` (tint-neutral): #12 (favorite × `:1118`), #17
  (reset chat `:1366`), #33 (remove-rel `:1906`), #36 (log-meeting + `:2032`), #46
  (memory delete `:2362`), #51 (analysis dismiss `:2525`), #54/#55 (note
  expand/delete `:2606/2612`), #58 (encounter delete `:2976`, in `EncounterRow`).
- **Verify:** each glyph has a 44pt hit area; colored glyphs keep their color; VoiceOver labels survive.

### ❌ B8 (02 A5) — PersonDetailView menu chrome
- **Files:** `PersonDetailView.swift` — `relationshipTypePicker` (`:1041-1049`),
  `checkInGoalMenu` (`:1704-1710`), Scan menu (`:2387-2394`).
- **Change:** apply `.msMenuButtonChrome()` to each `Menu` label; keep `.fixedSize()`
  on Scan; test for double-chrome with `.menuStyle(.borderlessButton)`.
- **Verify:** triggers read as 30pt secondary buttons.

### ❌ B9 (02 A6) — PersonDetailView sheet/popover footers → Secondary; confirms → Primary
- **Files:** `PersonDetailView.swift` — 02 §3 #25,38,39,40,41,42,52,56,61 (addEmail
  Cancel, reconnect Copy/Done, evidence Compile/Copy/Done, customPrompt Cancel,
  addToMeeting Done, AddRelationshipSheet Cancel → Secondary; customPrompt Run,
  AddRelationshipSheet Save → Primary).
- **Verify:** sheets render consistent 30/34pt footers.

### ❌ B10 (05 A6) — PeopleListView `.borderless` actions
- **Files:** `PeopleListView.swift:514` ("Manage tags"), `:737`.
- **Change:** text actions → `MSInlineButton`; icon clears → `NotionIconButton`+`.minTap()`.
- **Verify:** builds; actions normalized.

### ❌ B11 (05 A7) — PersonDetailView remaining bordered/borderless near MS buttons
- **Files:** `PersonDetailView.swift:2036, 2122` region; `:1121, 1367, 1909`.
- **Change:** text → `MSInlineButton`; icon → `NotionIconButton`+`.minTap()` (judge each).
- **Verify:** no mixed bordered/borderless in a cluster.

### ❌ B12 (05 A8) — Untitled* alias sweep (repo-wide, low priority)
- **Files:** anywhere `UntitledPrimaryButtonStyle`/`UntitledSecondaryButtonStyle` survive.
- **Change:** → `MSPrimaryButtonStyle`/`MSSecondaryButtonStyle`.
- **Verify:** builds; grep shows no `Untitled*ButtonStyle` call sites.

---

## Phase T — Tasks integration (04-tasks-integration)

### ✅ T1 / ✅ T2 / ✅ T3 (04 B0a/B0b/B0c) — DONE
- Owner→person link in summary `InlineActionItemRow` (`MeetingSummaryTab.swift:611-625`).
- Table meeting-cell + owner navigation (`ActionItemsTableView.swift:145-157, 184-199`).
- Person `taskRow` meeting link (`PersonDetailView.swift:1859-1872`).

### ❌ T4 (04 B1) — Shared `TaskMeetingChip` / `TaskOwnerChip` components
- **Files:** new `Sources/MeetingScribe/UI/TaskLinkChips.swift`.
- **Change:** extract the table's button-with-fallback into two reusable views:
  `TaskMeetingChip(item:)` (nothing when `isManual`; button → `openMeeting` when
  `meeting(id:)` resolves, else inert text; branches `source == "voice_note"` →
  `router.route(kind:.voiceNote, id:)`) and `TaskOwnerChip(item:, size:)`
  (avatar+name; button → `openPerson` when `ownerPersonID != nil`, else plain).
  `@EnvironmentObject router`. Add a pure `linkState(for:)` for unit-testing.
- **Verify:** builds; nothing consumes them yet.

### ❌ T5 (04 B2) — Adopt `TaskMeetingChip` in the Tasks list row (closes §3.1)
- **Files:** `TaskRowView.swift:164-170`.
- **Change:** replace `Label(item.meetingTitle, "calendar")` with `TaskMeetingChip(item:)`.
- **Verify:** click a list row's meeting → Meetings tab opens.

### ❌ T6 (04 B3) — Adopt chips on the board card (closes §3.2, §3.3)
- **Files:** `ActionItemsBoardView.swift:130-132` (owner), `:150` (meeting).
- **Change:** `TaskOwnerAvatar` → `TaskOwnerChip(item:, size:16)`;
  `Text(item.meetingTitle)` → `TaskMeetingChip(item:)`.
- **Verify:** click owner → People, meeting → Meetings; **confirm card drag still works** (nested-button risk).

### ❌ T7 (04 B11) — Owner nav in summary `outcomesStrip` (closes §3.9 / O5)
- **Files:** `MeetingSummaryTab.swift:214-216`.
- **Change:** swap `Text(owner)` for `TaskOwnerChip(item:, size:12)`.
- **Verify:** a linked owner in the outcomes preview navigates. (Note: outcomesStrip
  is slated to merge into the meeting-canvas Outcomes section in M3; this keeps
  flag-off correct in the interim.)

### ❌ T8 (04 B4) — `openCount(forPerson:)` / `overdueCount(forPerson:)` + adopt
- **Files:** `ActionItemStore.swift` (new helpers near `:1259`); refactor
  `TodayView.swift:253,346`, `ActionItemsSidebar.swift:484-495`,
  `PersonContextBuilder.swift:93`.
- **Change:** add helpers (MASTER decision 8 / 04 §4.5); replace inline predicates.
- **Verify:** counts unchanged in Tasks rail / Today. Unit-test the helpers.

### ❌ T9 (04 B5) — Open-task pill on People list rows (closes §3.4 / C3)
- **Files:** `PeopleListView.swift:615-648` (`PersonRow`).
- **Change:** render a pill from a precomputed count (use the L-phase
  `taskCounts` index — do NOT call `openCount` per row); tap →
  `router.openTasks(route: ActionItemsView.personSentinel(person.id))`.
- **Verify:** a person with open tasks shows the pill; tap scopes Tasks. (Coordinate
  with L Increment 3 — the same chip; build once, in whichever phase lands first.)

### ❌ T10 (04 B6) — Open-task badge on meeting cards (closes §3.5 / C4)
- **Files:** `MeetingCard.swift:123-175` (`content`).
- **Change:** for `variant == .past`, compute `manager.actionItems.items(for:
  meeting.id).filter { $0.status != .completed }.count`; render a small badge near
  the outcome line; tap → Tasks scoped to the meeting. Do NOT read files in body
  (jank vector documented at `MeetingCard.swift:374`).
- **Verify:** a past meeting with open follow-ups shows "N open".

### ❌ T11 (04 B8) — Re-resolve unassigned owners on People mutation (closes §3.6 part 1)
- **Files:** `ActionItemStore.swift` (new `reresolveUnassignedOwners(against:)`);
  `PeopleStore.swift` (`updatePerson`/create paths fire it).
- **Change:** iterate `unassignedOwnerTasks()`, `PersonResolver.resolveOwner`,
  `setOwnerPerson` on matches; batch one save; guard re-entrancy.
- **Verify:** add a contact "Alice"; a pre-existing "Alice"-owned unlinked task gets `ownerPersonID` set.

### ❌ T12 (04 B7) — Unify owner-matcher: `PersonResolver.taskBelongs` (closes §3.8)
- **Files:** `PersonResolver.swift` (add `taskBelongs`); `PersonDetailView.swift`
  (`personTasks` → use it; delete `ownerMatchesPerson` `:1731-1742` + `ownerTokens` `:1717-1729`).
- **Change:** hard-link first, else `resolveOwner` over `[person]` — never substring.
- **Verify:** profile lists hard-linked + exactly-resolvable tasks; substring-only
  legacy hits drop off (expected). **Land T11 before/with this** so legacy tasks
  get hard links first. Unit-test `taskBelongs`.

### ❌ T13 (04 B9) — "Unassigned owners" review rail (closes §3.6 part 2)
- **Files:** `ActionItemStore.swift` (`unassignedOwnerTasks`, §4.5);
  `ActionItemsView.swift` (new `unassignedOwnersSentinel` alongside `:88-107`);
  `ActionItemsSidebar.swift:497-513` (rail entry). List reuses
  `MeetingActionRow.ownerMenu` resolve pattern.
- **Change:** People-section header "Unassigned (N)"; selecting it filters the list
  to those tasks with an inline person-picker. Follow the `personSentinelPrefix` pattern exactly.
- **Verify:** unresolved-owner tasks appear; picking a person links them and they leave the bucket.

### ❌ T14 (04 B10) — `refreshMeetingTitle` on rename + degrade tooltip (closes §3.7)
- **Files:** `ActionItemStore.swift` (`refreshMeetingTitle(_:to:)`); meeting-rename
  path in `MeetingManager`; `TaskMeetingChip` (add "source meeting deleted" help
  when `!isManual` but `meeting(id:)` nil).
- **Change:** title-sync method + call site; chip tooltip. Do NOT rewrite `meetingID`.
- **Verify:** rename a meeting → its tasks show the new title without re-extract; delete → chip degrades with tooltip.

*Suggested T order (04 §5): T4 → T5 → T6 → T7 (nav sweep) · T8 → T9 → T10 (counts)
· T11 → T12 (re-resolve before tighten) → T13 (review surface) → T14 (orphans).*

---

## Phase L — People list (03-people-list)

### ❌ L1 (03 Increment 1) — Extract `isOverdueForCheckIn` / `overdueDays` (pure refactor)
- **Files:** `PeopleStore.swift`.
- **Change:** add `isOverdueForCheckIn(_:now:)` + `overdueDays(_:now:)` (§3.4);
  rewrite `overdueCheckInCount` (`:1367-1375`) + `overdueCheckInNames` (`:1379-1390`)
  to call them.
- **Verify:** nav-rail badge count identical; no UI render change. **Risk: zero.**

### ❌ L2 (03 Increment 2) — Inject `ActionItemStore` + build the task-count index (no render)
- **Files:** `PeopleListView.swift`; possibly `MainWindow.swift`/app root.
- **Change:** add `@EnvironmentObject var actionItems: ActionItemStore`, `@State
  taskCounts: [String:TaskCounts]`, `TaskCounts` struct, `rebuildTaskCounts()`
  (one O(tasks) pass, §3.8), wire `.task` + `.onChange(of: actionItems.items)`. No render yet.
- **Verify (RUNTIME):** PRE-WORK — grep the app root for the store's
  `.environmentObject(`; then `make install`, open People tab, no crash (missing
  injection is a crash, not a compile error).

### ❌ L3 (03 Increment 3) — `PersonRow` task chip
- **Files:** `PeopleListView.swift`.
- **Change:** add `let counts: TaskCounts` to `PersonRow`; thread `taskCounts[id] ??
  .zero` at both call sites (`:312` select, `:321` live); render `☑ N` (or `☑ N·M`
  when overdue), tinted `NDS.danger` if overdue. Non-interactive for now.
- **Verify:** chip shows, reddens when overdue; `.zero` keeps zero-task rows unchanged.
  (This is the same chip as T9 — build once.)

### ❌ L4 (03 Increment 4) — `PersonRow` overdue pill
- **Files:** `PeopleListView.swift`.
- **Change:** when `people.isOverdueForCheckIn(person)`, replace the relative-date
  `Text` (`:642-645`) with the `"Nd overdue"` pill (`NDS.danger`); else keep the date.
- **Verify:** typed-past-cadence person shows the pill; others show the date.

### ❌ L5 (03 Increment 5) — Section grouping (recency-only "This week" first)
- **Files:** `PeopleListView.swift`.
- **Change:** add `PeopleSection`, `collapsed: Set<String>`, the `sections`
  computed partition (§3.5; OVERDUE / THIS WEEK recency-only / EVERYONE ELSE;
  Overdue sorted by `overdueDays` desc), `sectionHeader(_:)`. Swap the live-list
  `ForEach(filtered)` (`:319-324`) for the sectioned form **only when not querying**
  (gate on `debouncedQuery.isEmpty`; else flat). Keep select-mode list flat.
- **Verify:** correct headers/counts; collapse/expand + selection work; searching reverts to flat.

### ❌ L6 (03 Increment 6) — Triage segmented control
- **Files:** `PeopleListView.swift`.
- **Change:** add `TriageFilter` (`all`/`needsAttention`/`hasTasks`), `@State
  triage`, the segmented `Picker` between search and `tagChips` (hidden while
  querying), and the triage predicate in `filtered` (§3.3 — `.needsAttention` =
  overdue-relationship ∪ overdue-task; `.hasTasks` = open>0).
- **Verify:** each segment filters correctly; "All" unchanged.

### ❌ L7 (03 Increment 7) — Density toggle + meeting count
- **Files:** `PeopleListView.swift`.
- **Change:** add `RowDensity` (`comfortable`/`compact`),
  `@AppStorage("people.rowDensity")`, a density menu button next to sort in
  `actionsRow`, thread density into `PersonRow`, apply comfortable/compact geometry
  + the comfortable-only `📅 N` meeting-count (O(1) via the encounter index).
- **Verify:** toggle flips avatar size/padding + `📅 N`; persists across relaunch.

### ❌ L8 (03 Increment 8) — Task chip deep-link + "Mark reached out"
- **Files:** `PeopleListView.swift`.
- **Change:** make the task chip a `Button` that selects the person and calls
  `router.openTasks(route: ActionItemsView.personSentinel(person.id))` (§4.2). Add
  the trailing swipe action + the conditional `personRowMenu` item "Mark reached
  out" → `bumpLastInteraction` (§4.4), shown only when overdue.
- **Verify (RUNTIME):** `make install`; chip tap → Tasks scoped to person; swipe/right-click → person leaves OVERDUE. (Chip must not be swallowed by row selection.)

### ❌ L9 (03 Increment 9) — Widen sidebar + birthday clause for "This week"
- **Files:** `PeopleListView.swift`; small shared helper file for `nextSpecialDateWithin`.
- **Change:** widen frame at `:113` to `280/340/420` (§3.2). Extract
  `nextSpecialDateWithin(_:days:)` from `PeopleInsightsView.nextOccurrence`/`comingUp`;
  add the birthday clause to "This week"; refactor `comingUp` to call the helper.
- **Verify:** birthday/special-date-within-7-days people appear in THIS WEEK; dashboard "Coming up" unchanged.

### ❌ L10 (03 Increment 10) — Polish + edge passes
- **Files:** `PeopleListView.swift`.
- **Change:** empty-section suppression, accessibility labels on pill/chip, optional
  undo toast for "Mark reached out", verify ghost footer still only in all/no-tag/no-query state.
- **Verify:** full pass against 03 §6 (search mode, empty, snapshot, select mode, 500+, ghosts, two-way selection).

---

## Phase M — Meeting canvas de-tab (01-meeting-detail)

*Strategy: flag-gated parallel build behind `@AppStorage("meetingCanvasV2")`;
flag-off path stays byte-for-byte today's UI until cutover (M9). Each step's
verify includes click-testing past / live (record 10s + stop) / upcoming with the
flag on and off.*

### ❌ M0 (01 Step 0) — Confirm `MSSection` + tokens (no code)
- **Verify:** `swift build -c release` baseline green. (Phase F merged.)

### ❌ M1 (01 Step 1) — Flag + canvas scaffold (flag-off identical)
- **Files:** `UnifiedMeetingDetail.swift`.
- **Change:** add `@AppStorage("meetingCanvasV2") var canvasV2 = false`. In `body`,
  `if canvasV2 { canvasBody } else { tabbedBody }` where `tabbedBody` is today's
  `Group { switch tab … }` extracted verbatim and `canvasBody` is a
  `GeometryReader`/`VStack` shell rendering today's `combinedNotesBody` (proves the
  C-A shell). `tabPicker` only when `!canvasV2`.
- **Verify:** flag-off identical; flag-on notes canvas renders + editor typeable.

### ❌ M2 (01 Step 2) — Canvas chrome split (top ScrollView vs bottom group)
- **Files:** `UnifiedMeetingDetail.swift`.
- **Change:** in `canvasBody` lay out the two groups (§4.1): empty `ScrollView` +
  `ScrollViewReader` over a `VStack` for the top group; empty `VStack` for the
  bottom group; `Divider().overlay(NDS.divider)` between. Define `SectionAnchor`
  enum (`outcomes, summary, transcript`) and `contentMaxWidth = 760`.
- **Verify:** flag-on shows empty scaffold; build green.

### ❌ M3 (01 Step 3) — Outcomes section (the §P2 triple-render merge)
- **Files:** `UnifiedMeetingDetail.swift` (new `outcomesSection`),
  `MeetingActionRow.swift` (add owner person-jump).
- **Change:** `MSSection("Outcomes", systemImage:"checklist", count: items.count,
  persistenceKey:"meeting.outcomes", defaultExpanded: <mode/content rule>)`:
  `ForEach` `MeetingActionRow` + decision rows (from `outcomesStrip:220`) + "Add
  action item" (`actionsBody:306`); trailing = triage pill + "Add all N → Tasks" +
  "→ Tasks inbox"; empty `MSEmptyState` for `.past`, omitted for `.upcoming`. Lift
  `router.openPerson` into `MeetingActionRow.ownerMenu` label (from doomed
  `InlineActionItemRow:613`). Tag `.id(SectionAnchor.outcomes)`; add to top ScrollView.
- **Verify:** create/toggle/assign/due/confirm; triage pill + "Add all" work; matches `actionsBody`.

### ❌ M4 (01 Step 4) — Highlights section
- **Files:** `UnifiedMeetingDetail.swift`.
- **Change:** wrap `highlightsStrip` content (`MeetingSummaryTab.swift:154-190`) in
  `MSSection("Highlights", systemImage:"flag.fill", persistenceKey:"meeting.highlights")`.
  Do NOT wire the chip `tab = .transcript` yet (M8). Omitted when no marks; top ScrollView.
- **Verify:** marks render as chips; hidden when none.

### ❌ M5 (01 Step 5) — Notes section (bounded editor + grabber, C-A)
- **Files:** `UnifiedMeetingDetail.swift`, reuse `MeetingNotesTab.swift`.
- **Change:** build `notesSection` in the bottom group (outside the top ScrollView).
  Reuse `currentNotesEditor`/`notesEditor` but place `RichMarkdownEditor` at
  `.frame(height: notesPaneHeight)` + drag grabber (§4.5);
  `@AppStorage("meeting.notes.height")`. Keep "Push to-dos → Tasks" in trailing;
  keep `previousCallsSidebar` split inside the bounded frame.
  `MSSection("Your notes", systemImage:"doc.text", persistenceKey:"meeting.notes", defaultExpanded:true)`.
- **Verify (critical C-A):** paste 50+ lines → editor scrolls internally, page does
  NOT grow unbounded; grabber resizes; autosave fires.

### ❌ M6 (01 Step 6) — Summary section (+ generating/failed unification, §P7)
- **Files:** `UnifiedMeetingDetail.swift`, reuse `MeetingSummaryTab.swift`.
- **Change:** `summarySection` for `.past` in the top ScrollView. Body order:
  `hasRealSummary` → read-only `MarkdownEditor` bounded (§4.4) + `SummaryEditByAsking`
  + `SummaryFeedbackRow`; else `isSummaryGenerating` → `summaryGeneratingBanner`;
  else `bodyLoaded && !transcript.isEmpty` → `summaryFailedBanner`; else `!bodyLoaded`
  → `MSSkeleton(lines:4)`; else omitted. Trailing = `copyMenu` + `followUpButton`.
  Pick the canvas banners as the single source of truth (legacy
  `pastSummaryBody`/`emptySummaryView` slated for X-cleanup). Tag
  `.id(SectionAnchor.summary)`; `defaultExpanded:true` for `.past`; hidden live/upcoming.
- **Verify:** past w/ summary expanded by default (no 300ms race, §P3); generating
  shows banner+tokens; engine-off shows Generate retry; edit-by-asking + 👍/👎 + copy work.

### ❌ M7 (01 Step 7) — Transcript section (lazy + mode-multiplex, C-B/C-C)
- **Files:** `UnifiedMeetingDetail.swift`, reuse `MeetingTranscriptTab.swift`.
- **Change:** `transcriptSection` in the bottom group. Title via
  `transcriptSectionTitle` (§C-C); `defaultExpanded` `.past`→false,
  `.live`/`.upcoming`→true; lazy mount with `transcriptEverExpanded` latch (§C-B);
  body is the existing `transcriptBody` switch with each view given a bounded
  `.frame(height:)` via geo; `.past` empty → omitted, `!bodyLoaded` →
  `MSSkeleton(lines:8)`; pass shared `audioController` (C-D) unchanged;
  persistenceKey `meeting.transcript`; tag `.id(SectionAnchor.transcript)`.
- **Verify:** past collapsed by default, parses only on first open (temporary log);
  timestamp seek drives `audioBar`; live auto-scrolls; upcoming shows brief.

### ❌ M8 (01 Step 8) — Ask AI section + rewire teleports to scroll-to-anchor (§P4)
- **Files:** `UnifiedMeetingDetail.swift`, `MeetingChatTab.swift` (no logic change),
  `MeetingSummaryTab.swift` (highlights chip), `MeetingTranscriptTab.swift` (`consumeTranscriptQuery`).
- **Change:** `chatSection` `MSSection("Ask AI", systemImage:"bubble.left.and.sparkles",
  persistenceKey:"meeting.chat", defaultExpanded:false)` wrapping `chatBody` at
  bounded height, lazy-mounted, bottom group last. Rewire `highlightsStrip` chip
  and `consumeTranscriptQuery` to a new `revealTranscript(seedSearch:)` (sets
  `transcriptExpanded = true`, sets `transcriptSearchSeed`,
  `proxy.scrollTo(.transcript)`) instead of `tab = .transcript`; guard behind
  `canvasV2` so flag-off keeps `tab = .transcript`.
- **Verify:** highlight chip + search deep-link expand+scroll to transcript with the moment searched; Ask AI lazy-mounts.

### ❌ M9 (01 Step 9) — Related & linked section + reviewBanner rewire; flip the flag
- **Files:** `UnifiedMeetingDetail.swift`, reuse `relatedMeetingsStrip`/`backlinksPanel`.
- **Change:** `relatedSection` `MSSection("Related & linked", systemImage:"link",
  persistenceKey:"meeting.related")` merging `relatedMeetingsStrip`
  (`MeetingSummaryTab.swift:123`) + `backlinksPanel` (`MeetingNotesTab.swift:161`),
  hidden when both empty, top ScrollView last. Rewire `reviewBanner.onReviewTasks`
  under `canvasV2` to expand Outcomes + `scrollTo(.outcomes)`; move `reviewBanner`
  under the header as chrome. **Flip `meetingCanvasV2` default to `true`.**
- **Verify:** full soak — past/live/upcoming, recurring, no-transcript, engine-off;
  all anchors scroll; everything reachable without tabs.

---

## Phase P — Person canvas de-tab (02-person-detail)

*Phase A buttons are covered by B2-B9 above. Below = 02 Phases B-F (structure).*

### ❌ P1 (02 A1 dead-code) — Delete dead person code
- **Files:** `PersonDetailView.swift`.
- **Change:** remove `header` (`:1511-1534`), `tagRow` (`:1536-1540`),
  `sectionNav(_:)` + `sectionNavItems` (`:698-738`) — all unreferenced (P2-H).
- **Verify:** builds; grep shows no remaining call sites. (Do before P3 if B2 didn't already delete `header`.)

### ❌ P2 (02 B1) — Add `compactHeader` var
- **Files:** `PersonDetailView.swift`.
- **Change:** build §4.1: Row 1 `HStack` (MSAvatar 48, name/subtitle, Spacer, Brief
  Me Primary, ⋯ overflow Menu with Edit name & role / Edit all fields… / Log
  encounter / Add relationship / Add to a meeting / Delete[destructive]) + Row 2
  `FlowLayout` (type picker, health badge, known-since). Keep `beginIdentityEdit()`
  name tap + the inline `editingIdentity` form full-width.
- **Verify:** header renders; overflow lists all items. **R1** name `lineLimit(1).truncationMode(.tail)` + `Spacer(minLength:8)`; **R2** Row 2 is `FlowLayout`.

### ❌ P3 (02 B2) — Swap `identityPanel`'s button rows for `compactHeader` (still in identityPane)
- **Files:** `PersonDetailView.swift`.
- **Change:** render `compactHeader` at the top of `identityPane`; delete the two
  FlowLayout button rows (`:852-897`) + standalone `relationshipTypePicker`/`healthBadge` (`:899-907`).
- **Verify:** the 300pt rail leads with the compact header at its tightest width (early fit test).

### ❌ P4 (02 C1) — Introduce `personCanvas`
- **Files:** `PersonDetailView.swift`.
- **Change:** new `ScrollView` whose content is `compactHeader` + a
  `VStack(spacing:18)` placeholder re-rendering the existing identityPane sections +
  workContent inline (no tabs) — proves single-column before MSSection conversion.
- **Verify:** everything visible in one scroll at narrow + wide widths.

### ❌ P5 (02 C2) — Repoint `body` to the two-column split
- **Files:** `PersonDetailView.swift`.
- **Change:** replace `detailPane` child of the `HSplitView` with `personCanvas`;
  lower mins (`personCanvas.frame(minWidth:480, idealWidth:720)`,
  `personChatColumn.frame(minWidth:300, idealWidth:360, maxWidth:460)`); move
  `.background(NDS.bg)` + `.background(keyboardVerbs)` onto `personCanvas`. Delete
  `detailPane`, `identityPane`, `workArea`, `workContent`.
- **Verify:** chat still present; one scroll on the left. **Risk: high** — biggest structural change.

### ❌ P6 (02 D1) — Wrap each builder in `MSSection` (the §4.2 table)
- **Files:** `PersonDetailView.swift`.
- **Change:** in order per §4.2: Reconnect, Insight (direct, not a section), **Tasks**
  (#3, top-level, `defaultExpanded:true`, count = open items, §6 promotion), Tags,
  Contact, **Favorites** (collapsed, between Tags and Contact — §8.5 note),
  Relationships, In common (self-hide), Meetings (+ mentioned-in), Decisions
  (self-hide), Encounters, Messages (collapsed, no auto-scan), Discuss next time,
  Memories, **About** (renamed from bio "Notes"), **Saved analyses** (renamed from
  attached "Notes"), AI suggestions, Perf-review evidence, Photos (conditional).
  Use exact title/systemImage/count/persistenceKey/defaultExpanded from the table;
  move add-actions into `trailing:`; `.padding(.horizontal,20)` once on the canvas
  VStack. **Strip each builder's own `Text(title).font(NDS.sectionLabel)` header**
  (now provided by `MSSection`) — affects `tagsEditSection:1060`,
  `favoritesEditSection:1112`, `relationshipsSection:1888`, `encountersSection:1668`,
  `tasksSection:1766`, `memoriesSection:2348`, `talkingPointsSection:2303`,
  `attachedNotesSection:2576`, `messagesSection:2378`, `decisionsSection:1421`,
  `mentionedInSection:2003`, `inCommonSection:1952`, `notes:1657`, `evidenceSection:2234`,
  `aiSuggestionsSection:1161`, `photosSection:1598`. Story timeline intentionally
  dropped (delete `StoryItem`/`storyItems` `:595-625` if dropped).
- **Verify:** each section collapses/expands; counts correct; state persists across relaunch; no double titles. Do a handful at a time, building between.

### ❌ P7 (02 D2) — Delete `MSPillTabs` + `PersonTab` + `personTab`
- **Files:** `PersonDetailView.swift`.
- **Change:** remove `PersonTab` enum (`:287-299`), `@State personTab` (`:286`), the
  `.animation(.easeOut(0.18), value: personTab)`, all references.
- **Verify:** builds; grep `PersonTab|personTab` → zero. (Do with P8 — `keyboardVerbs` references `personTab`.)

### ❌ P8 (02 E1) — Rewrite `keyboardVerbs`
- **Files:** `PersonDetailView.swift:344-360`.
- **Change:** `N` (memory): set `section.person.memories.expanded = true` then
  `DispatchQueue.main.async { memoryFieldFocused = true }` (expand-before-focus
  gotcha, §8.4); `L`: `showAddEncounter = true`; `T`: add `@FocusState
  taskFieldFocused`, focus the quick-add field. Drop ⌘1-5 tab shortcuts. Optional `ScrollViewReader` for scroll-to.
- **Verify:** N/L/T work without tabs; no `personTab` reference remains.

### ❌ P9 (02 F1) — Empty-states + consistency pass
- **Files:** `PersonDetailView.swift`.
- **Change:** self-hiding sections (In common, Decisions, Reconnect, Photos) guard
  the whole `MSSection` with the existing `if`; others show their empty-state line
  inside the expanded body; `provenanceFooter` renders once at the bottom (not a section).
- **Verify:** new contact (mostly empty) + rich contact — no double headers, no orphaned buttons, no clipped rows at `minWidth:480`.

### ❌ P10 (02 F2) — Reduce-motion + accessibility
- **Files:** `PersonDetailView.swift`.
- **Change:** confirm no added `.animation` ignores reduce-motion (old `value:
  personTab` is gone); every icon-only button has an `.accessibilityLabel`
  (`.plain`+`.minTap()` checkbox/done glyphs need explicit ones).
- **Verify:** Reduce Motion → sections snap; VoiceOver labels present.

---

## Phase X — Cleanup (after soak)

### ❌ X1 (01 Step 10) — Delete the meeting tab machinery
- **Files:** all five meeting files. **Only after M9 soaks.**
- **Change:** remove the `meetingCanvasV2` flag + `tabbedBody` branch, then delete
  every dead symbol: `enum DetailTab` (`MeetingTranscriptTab.swift:172`), `@State
  var tab` (`:32`), `hasAppliedTabDefault` (`:37`), `summaryExpanded` (`:34`),
  `applySmartTabDefault()` (`:427`), `tabPicker` (`:254`), `actionsBody` (`:277`),
  `placeholder(...)` (`:321`), `combinedNotesBody` (`MeetingSummaryTab.swift:11`),
  `outcomesStrip` (`:195`), `summaryBody`/`pastSummaryBody` (`:277`/`:335`),
  `emptySummaryView` (`:400`), `actionItemsSection(_:)` (`:472`),
  `InlineActionItemRow` (`:569`). Keep all reused builders (header file,
  `MeetingActionRow`, `summaryGeneratingBanner`/`summaryFailedBanner`,
  `SummaryEditByAsking`, `SummaryFeedbackRow`, `copyMenu`, `followUpButton`,
  `currentNotesEditor`, `transcriptBody`, `chatBody`, `backlinksPanel`,
  `relatedMeetingsStrip`, `MarkdownEditor.swift`).
- **Verify:** build green with zero references to deleted symbols (grep each name); click-test all three modes.

### ❌ X2 (02 D2/§8.5) — Person dead-state cleanup
- **Files:** `PersonDetailView.swift`.
- **Change:** confirm `personTab`/`PersonTab` fully removed (P7); drop
  `askAIAboutPerson()` if "Ask AI" (#9) was dropped; remove `StoryItem`/`storyItems`
  if Story dropped (P6).
- **Verify:** builds; grep shows no dangling references.

### ❌ X3 (05 C1) — design-lint button-chrome guard, then flip CI to `fail`
- **Files:** `scripts/design-lint.sh`.
- **Change:** add `scan` calls for `.buttonStyle(.borderedProminent)`,
  `.buttonStyle(.bordered)`, and a `.controlSize(` scan excluding
  `ProgressView|TextField` and `// design-lint:allow` (05 §6.3 sketch). Flip to
  `fail` mode in CI only after B-phase drives the count to zero.
- **Verify:** `scripts/design-lint.sh warn` → 0 across `UI/` + `People/`; `fail` exits 0.

---

## Suggested overall order

F1 → F2 · B2 → B3 → B4 → B5 → B6 → B7 → B8 → B9 → B10 → B11 → B12 · T4 → T5 → T6 →
T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14 · L1 → L2 → L3 → L4 → L5 → L6 → L7 → L8 →
L9 → L10 · M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9 · P1 → P2 → P3 → P4 → P5 → P6
→ P7+P8 → P9 → P10 · X1 → X2 → X3. (T9/L3 are the same chip — build it once;
remember `make install` every ~2 increments and the C-A/fit/perf verifies.)
