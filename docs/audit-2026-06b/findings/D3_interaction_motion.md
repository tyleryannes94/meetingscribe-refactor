# Design — Interaction Design, Motion & Power-User Flows
> Lens: does every press, hover, drag, keystroke and transition feel as deliberate as Things 3, Linear, Arc, Family — and can a power user fly through the app without touching the mouse?

## Full-app audit (through my lens)

### Strong (genuinely good bones — protect these)
- **Toast + undo pattern is real and widely adopted.** `ToastCenter` (`Sources/MeetingScribe/UI/ToastCenter.swift:21-38`) backs ~20 call sites — task/person/section deletes, tag renames, bulk deletes all offer Undo (`ActionItemsListView.swift:253`, `PeopleListView.swift:311,415`, `TagStore.swift:119`). This is the optimistic-delete pattern Linear uses.
- **A canonical spring exists.** `NDS.springStandard` (`.spring(response: 0.32, dampingFraction: 0.80)`, `NotionDesign.swift:237`) plus the `NDS.motion(_:reduce:)` Reduce-Motion gate (`NotionDesign.swift:215`) is exactly the right primitive — the problem is adoption, not design (see Weak).
- **The Tasks list already has a Linear-grade keyboard model.** `ActionItemsListView.swift:135-140`: ↑/↓, `j`/`k`, ⏎ open, space toggle-done. This is the best interaction surface in the app — and it's stranded on one view.
- **Kanban drag-drop ordering math is correct.** Midpoint `sortIndex` insertion (`ActionItemsBoardView.swift:86-106`) means stable, non-shifting reorder — the hard part is done; only the *feel* is missing (see Weak).
- **TriageInboxView is the motion exemplar.** Insert/remove via `NDS.springStandard` + `.move(edge:.top).combined(with:.opacity)` (`TriageInboxView.swift:26-53`) — every list in the app should feel like this.
- **MeetingCard hover** is properly layered: shadow lift + 1.005 scale + interruptible spring, all reduce-motion gated (`MeetingCard.swift:51-58`).
- **Back/forward history already exists** — `WorkspaceRouter.canGoBack/goBack` wired to toolbar chevrons (`MainWindow.swift:434-445`). The plan lists this as Phase-2A future work; it has shipped. What's missing is only the ⌘[ / ⌘] key bindings (no such `keyboardShortcut` anywhere in the target).

### Weak / missing (where it reads cheap or breaks the power-user contract)
1. **Zero `NSUndoManager` integration anywhere** (grep across `Sources/`: no `undoManager`/`registerUndo` hits). ⌘Z does nothing for task title edits, status changes, priority changes, person field edits, encounter logs. Undo exists *only* as a 6-second click-target on delete toasts. A premium Mac app honors ⌘Z universally.
2. **The motion tokens exist but ~80% of call sites bypass them.** `NDS.motionFast/Standard/Slow` (`NotionDesign.swift:232-234`) are barely referenced; the codebase is littered with ad-hoc literals — `.easeOut(duration: 0.12)` (`TaskRowView.swift:65`), `0.1` (`MeetingsView.swift:523`), `0.18` (`PersonDetailView.swift:480`, `MainWindow.swift:412`), `0.15` (`QuickEncounterSheet.swift:124`, `MainWindow.swift:456`), `0.2` (`ToastCenter.swift:69`). Five-plus distinct durations for the same semantic action (hover) = no motion *language*, just motion *incidents*. Most of these also skip `NDS.motion()` so Reduce Motion doesn't disable them.
3. **Completing a task by mouse requires a menu.** `statusButton` is a `Menu` (`TaskRowView.swift:183-200`): click → popup → choose "Completed". Keyboard space-bar toggles in one stroke but the mouse path is 2 clicks + travel, and there is **no completion animation at all** — strikethrough flips instantly, the row never celebrates or settles. This is the single most-repeated interaction in the app and it's the furthest from the Things 3 benchmark.
4. **⌘K is a window-attached `.sheet`** (`MainWindow.swift:468-475`), fixed 620×480 (`GlobalSearchView.swift:59`), opaque `NDS.bg`. It drops down with stock sheet motion and sheet chrome — not a floating, blurred, spring-in palette (Raycast/Linear). Worse, mouse hover does not move the selection — only the keyboard `selection` index highlights (`GlobalSearchView.swift:198`), so hovering row 5 while selection sits on row 0 and pressing ⏎ opens row 0. Mixed-modal mismatch.
5. **Drag-drop has zero choreography.** No `isTargeted` bindings on any `dropDestination` (`ActionItemsBoardView.swift:61,72`; `ActionItemsListView.swift:62`): no column highlight, no gap-opening, no animated landing — cards teleport on drop. The drop *math* is premium; the drop *feel* is 2009.
6. **QuickEncounterSheet violates its own interaction contract.** The doc-comment promises "Tap a Kind chip … auto-saves on tap … sheet dismisses automatically after step 1" (`QuickEncounterSheet.swift:71-74`), but tapping a chip only sets `selectedKind` (`:124-127`); saving requires the separate Save button or ⏎ (`:188-196`). The habit-loop's hero gesture is 2-3 clicks pretending to be 1. It also uses off-system `.borderedProminent`/`.roundedBorder` (`:157,194`) instead of MS button styles.
7. **The FloatingOverlay window pops with no animation.** Show/hide is raw `orderFrontRegardless()` / `orderOut(nil)` (`FloatingOverlay.swift:132-136`) — no alpha fade, no slide. State morphs (recording→transcribing→done) hard-swap content. Every system-level HUD on macOS animates; this one blinks.
8. **No modern motion APIs anywhere**: zero `matchedGeometryEffect`, zero `.contentTransition(.numericText())`, one lone `symbolEffect` (`NotionDesign.swift:317`). The record-dock timer (`MeetingRecordDock.swift:33-37`), health scores, badge counts all jump-cut digits. Section switches are an opacity cross-fade in a ZStack (`MainWindow.swift:94-110`) — fine — but list→detail has no element continuity.
9. **Hover is reimplemented bespoke 15+ times.** Each of `TaskRowView.swift:38`, `MeetingsView.swift:522`, `TodayView.swift:674-675`, `MainWindow.swift:647,684`, `NotionDesign.swift:434,600,648`, `FloatingOverlay.swift:499` owns a private `@State hovering` with its own duration (0.08–0.2s) and effect (background / scale 1.005 / 1.03 / shadow). `NewMeetingSheet` rows have **no** hover state at all (`NewMeetingSheet.swift:38-56`) — dead under the pointer.
10. **Keyboard coverage is an island.** j/k lives only in the Tasks list; Meetings and People lists have no arrow/vim navigation, no Esc-to-deselect, no type-ahead. There is no shortcut-discovery surface (no "?" overlay; shortcuts are only discoverable via the menu bar). `GlobalSearchView` Esc works (`:69`) but no ⌘⏎/⌥⏎ secondary-open verbs.
11. **Slash and @-mention menus are stock `NSMenu` popups** (`MarkdownEditor.swift:601-610`, `presentMentionMenu`). They block typing — no type-to-filter-as-you-type inline popover (Notion/Linear/Craft standard). The plan's 2H item ("`[[`/@person autocomplete") will under-deliver if built on NSMenu.

## Existing-plan items I rank highest
1. **Gate all motion through `NDS.motion()` (1F)** — the prerequisite for everything in my lens; today's 5-site adoption claim is still roughly true.
2. **Drag-to-reorder affordance on Action Items (2H)** — only planned item touching drag *feel*; pair it with D3-5 below.
3. **Recents rail + ⌘K quick-switcher (2A)** — the palette exists; the plan should fund its redesign (D3-4), not a rebuild.
4. **Attendee chip hover card with "Add to People" (2A)** — the highest-value hover interaction in the app and a people-pillar win.
5. **Loading skeleton tri-state (1F)** — perceived responsiveness; stops "No summary" flashing as an error state.
6. **In-meeting scratchpad (2D)** — the one surface where typing latency and live feedback *are* the product.

## NET-NEW recommendations

### D3-1 — NDS Motion Language spec + lint enforcement
- **What/why:** Codify three semantic tiers in `NotionDesign.swift` — `NDS.microMotion` (hover/press, ease-out 0.12), `NDS.springStandard` (state/selection, exists), `NDS.springStructural` (panes/sheets/insert-remove, response 0.45) — each pre-wrapped in a Reduce-Motion-aware view modifier (`.ndsAnimate(.micro, value:)`). Then sweep the ~40 ad-hoc `.easeOut(duration:)`/raw `.spring(` literals (TaskRowView:65, MeetingsView:523, PersonDetailView:480,521, MainWindow:412,456, QuickEncounterSheet:124,146,252, ToastCenter:69, GlobalSearchView:149 …) and add a design-lint rule (the repo already has design-lint in CI per `HELD-ITEMS.md`) banning raw duration literals in `UI/` and `People/`.
- **User value:** Every surface decelerates the same way → the app reads as one designed object; Reduce Motion actually works app-wide.
- **Effort:** M · **Impact:** High · **Depends on:** none (extends plan item 1F)

### D3-2 — One-click task completion with a celebration micro-moment
- **What/why:** Split `TaskRowView.statusButton` (`TaskRowView.swift:183-200`): left-click = toggle open↔completed (today it opens a Menu); right-click/the existing context menu keeps the full status picker. On completion: SF Symbol `.bounce` symbolEffect on the check, 150ms color spring, strikethrough drawn-in after a 250ms beat, and (in filtered views) the row departs with the TriageInbox spring after ~800ms so the user *sees* the win before it leaves. Space-bar parity already exists (`ActionItemsListView.swift:140`).
- **User value:** The most frequent action in the app drops from 2 clicks to 1 and gains the dopamine beat that makes Things 3 addictive.
- **Effort:** S · **Impact:** High · **Depends on:** D3-1 (uses motion tiers)

### D3-3 — Real ⌘Z: bridge stores to NSUndoManager
- **What/why:** Zero `registerUndo` calls exist in the target. Add an `UndoableStore` helper that registers inverse ops on the window's `undoManager` for `ActionItemStore` mutations (title/status/priority/project/due), `PeopleStore` field edits, and encounter logs. Unify with `ToastCenter`: destructive toasts show "⌘Z" hint and the toast's undo closure registers as the undo action, so ⌘Z works even after the toast expires.
- **User value:** Edits stop being scary; power users edit fearlessly at speed. Table-stakes for "expensive" on macOS.
- **Effort:** M · **Impact:** High · **Depends on:** none

### D3-4 — Redesign ⌘K as a floating command palette (the premium spec for plan item 2A)
- **What/why:** Replace the `.sheet` presentation (`MainWindow.swift:468`) with a centered borderless overlay/NSPanel: `.ultraThinMaterial` ground, 0.98→1.0 scale + opacity spring entrance, hairline + soft shadow. Fix the modal mismatch: `onHover` moves `selection` (GlobalSearchView:198 highlights only the keyboard index today). Add a footer hint bar (↑↓ · ⏎ open · ⌘⏎ open + keep palette · esc), result-type section icons, and frecency-ranked recents on empty query (recents tracking is also planned 2A — surface it here first).
- **User value:** The single most-used power surface goes from "stock macOS dialog" to Raycast/Linear class; hover/keyboard never disagree about what ⏎ opens.
- **Effort:** M · **Impact:** High · **Depends on:** D3-1

### D3-5 — Drop-target choreography for board + list drag-drop
- **What/why:** Add `isTargeted:` bindings to every `dropDestination` (`ActionItemsBoardView.swift:61,72`, `ActionItemsListView.swift:62`): targeted column gets an accent ring + 2% tint; targeted row position opens an animated 8pt gap (placeholder spring); on drop, the card lands with `springStandard` instead of teleporting; auto-scroll when dragging near scroll edges. Reuse the existing midpoint-sortIndex math untouched.
- **User value:** Drag stops feeling like a file-manager fallback and starts feeling like Things/Linear board manipulation; users trust where the card will land *before* releasing.
- **Effort:** M · **Impact:** Med-High · **Depends on:** D3-1; complements plan 2H drag-affordance

### D3-6 — Make QuickEncounterSheet honor its 1-tap contract (optimistic log + undo)
- **What/why:** The sheet's own spec says chip-tap auto-saves (`QuickEncounterSheet.swift:71-74`) but the code requires chip → Save (`:124-127,188-196`). Make chip-tap save optimistically and dismiss immediately, with a `ToastCenter` toast: "Logged ☕️ with Priya · Add note · Undo". "Add note" reopens an expanded composer for mood/note/date. Migrate buttons/fields to MS styles while in there.
- **User value:** The habit loop's hero gesture truly becomes 1 click (today 2-3); undo + add-note keep the depth without taxing the common case.
- **Effort:** S · **Impact:** High · **Depends on:** D3-3 (undo), none hard

### D3-7 — Numeric & symbol content transitions
- **What/why:** Zero `.contentTransition` in the app. Apply `.contentTransition(.numericText())` to the record-dock timer (`MeetingRecordDock.swift:33-37`), health-score badge, task/section counts (`ActionItemsBoardView.swift:39`), and Today stats; `.symbolEffect(.bounce, value:)` on status/priority icon changes. All gated by `NDS.motion`.
- **User value:** Numbers roll instead of blink — the small physics that separates Family/Arc-tier polish from a web dashboard. Nearly free.
- **Effort:** S · **Impact:** Med · **Depends on:** D3-1

### D3-8 — Unify the keyboard model: list navigation everywhere + "?" shortcut overlay
- **What/why:** Extract the Tasks-list key handling (`ActionItemsListView.swift:135-140`) into a reusable `ListKeyNavigator` and apply to Meetings and People lists (↑↓/j/k move focus ring, ⏎ open, space quick-action: People = log encounter, Meetings = open). Add Esc-to-deselect/close-detail, bind ⌘[ / ⌘] to the already-shipped `router.goBack()/goForward()` (`MainWindow.swift:434-445` — toolbar-only today), and a "?"-key cheat-sheet overlay listing every shortcut (Linear's `?`).
- **User value:** The whole app becomes mouse-optional; the existing best-in-app interaction stops being a Tasks-only secret.
- **Effort:** M · **Impact:** High · **Depends on:** none

### D3-9 — Animate the FloatingOverlay window lifecycle + state morphs
- **What/why:** Wrap show/hide (`FloatingOverlay.swift:132-136`) in `NSAnimationContext`: fade-in + 8pt rise on `orderFront`, fade-out before `orderOut`. Inside the pill, crossfade recording→transcribing→done with an animated width change (single capsule that morphs, not three swapped layouts), reduce-motion gated.
- **User value:** The most system-visible surface (it floats over *other apps*) stops blinking in and out like a debug window — this is where strangers judge the app's quality.
- **Effort:** S · **Impact:** Med-High · **Depends on:** D3-1

### D3-10 — `.ndsHover(_:)` hover/press standard (kill 15 bespoke implementations)
- **What/why:** One modifier with four semantic styles — `.row` (bg tint, 0.12 ease), `.card` (shadow lift + 1.005 scale spring), `.icon` (bg + hairline), `.pill` (tint deepen + 1.03 scale) — replacing the private `@State hovering` copies in TaskRowView:38-65, MeetingsView:522-523, TodayView:674-675, MainWindow:647,684, NotionDesign:434,600,648, FloatingOverlay:499-524, and adding hover to the dead NewMeetingSheet rows (`NewMeetingSheet.swift:38-56`). Include a standard *pressed* state (scale 0.98/dim) for plain-button rows, which currently give zero press feedback.
- **User value:** Every interactive element acknowledges the pointer identically — the strongest subconscious "expensive" signal on desktop.
- **Effort:** M · **Impact:** High · **Depends on:** D3-1

### D3-11 — Inline type-to-filter mention/slash popover (replaces NSMenu)
- **What/why:** The planned 2H "`[[`/@person autocomplete" will land on the existing `NSMenu` popups (`MarkdownEditor.swift:601+`), which block typing. Build a caret-anchored, non-activating panel: keep typing to filter, ↑↓ to choose, ⏎ inserts, Esc dismisses and keeps the literal "@" — person rows show avatar + health dot (people-pillar tie-in). The caret-rect math already exists (`caretPoint`, `MarkdownEditor.swift:587-599`).
- **User value:** Note-taking @-mentions reach Notion/Craft fluency — critical for the in-meeting scratchpad (2D) where users type under time pressure.
- **Effort:** M · **Impact:** Med-High · **Depends on:** none (supersedes the NSMenu path of 2H)

### D3-12 — Toast v2: stacking, hover-pause, action affordance
- **What/why:** `ToastCenter` is single-slot with a fixed 6s timer (`ToastCenter.swift:21-27`) — a second toast silently destroys the first one's undo. Allow a 3-deep stack with staggered spring entrances, pause the dismiss timer on hover, add a thin progress hairline showing time remaining, and support one primary action ("Open", "Add note") beyond Undo.
- **User value:** Undo guarantees survive bursts of activity (bulk triage, multi-delete); hover-to-read matches user instinct.
- **Effort:** S · **Impact:** Med · **Depends on:** D3-3, D3-6 (both lean on toasts)

## Top 3 picks
1. **D3-2 — One-click task completion + celebration** — highest frequency × biggest gap vs benchmark, S effort.
2. **D3-1 — Motion Language spec + lint** — the multiplier; nothing else lands coherently without it.
3. **D3-4 — Floating ⌘K palette redesign** — converts the planned nav backbone's centerpiece from stock to signature.

**Single highest-priority rec overall:** **D3-1**. Every other motion/interaction fix in this audit (and the existing plan's 1F/2A/2H items) inherits its quality ceiling from whether the app has one enforced motion language or forty ad-hoc durations.
