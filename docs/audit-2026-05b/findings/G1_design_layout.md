# Design — Layout & Space Usage

Lens: window/pane structure, responsive behavior across window sizes, full-width usage, split-view ergonomics, information density, the chat rail's effect on layout, and multi-column vs single-column choices.

## Audit (through my lens)

**Verified built (don't re-propose):** `WorkspaceRouter` single navigation surface (`WorkspaceRouter.swift:13`); keep-alive ZStack tab cache w/ 0.15s cross-fade and lazy first-build (`MainWindow.swift:90-106`); chat rail defaults CLOSED and auto-collapses below 860px (`MainWindow.swift:63,248`); 240px nav rail (`MainWindow.swift:165`); Meetings list+detail (`MeetingsView.swift:53`); People HSplitView with insights dashboard fallback instead of dead space (`PeopleListView.swift:68,418`); cached first-paint reload in detail (`UnifiedMeetingDetail.swift:166-226`).

**The core finding — four DIFFERENT split-pane systems, no shared layout primitive.** Each top-level tab invents its own structure:
- Meetings: `NavigationSplitView` with hardcoded `.constant(.all)`, list `min:300 ideal:360 max:480` (`MeetingsView.swift:53-60`).
- People: `HSplitView`, sidebar `min:260 ideal:320 max:380`, detail `min:380` (`PeopleListView.swift:68-70`).
- Voice Notes: `HSplitView`, sidebar `min:240 ideal:320 max:360` (`QuickNotesView.swift:18-20`).
- Tasks: plain `HStack` with a **fixed `width: 230`** rail that cannot resize or collapse (`ActionItemsView.swift:104-110`).
- Today: single `ScrollView` column, no detail pane (`TodayView.swift:44`).

So a user dragging the People divider learns a gesture that silently fails to exist in Meetings (NavigationSplitView ignores manual drags here) and in Tasks (fixed HStack). Three different sidebar min/ideal/max triples (300/360/480 vs 260/320/380 vs 240/320/360) mean panes jump width as you tab-switch — visually jarring and a density-control inconsistency. This is the single biggest layout-polish problem.

**Responsive behavior is binary and incomplete.** The only width breakpoint in the entire app is the chat rail's `>= 860` gate (`MainWindow.swift:248`). Nothing else adapts: at a wide window (1600px+) the Meetings detail and Today feed stretch edge-to-edge with no measure cap on prose, while at ~720px min width (`MeetingScribeApp.swift:49`) a Meetings split (240 rail + 300 list + detail) leaves the detail pane cramped under ~180px with no auto-collapse of the list. There's no "compact at narrow / comfortable at wide" density story.

**Full-width usage is uneven.** Today explicitly removes the measure cap (`TodayView.swift:88-90`, padding 28) — good for cards. But the Meetings Summary/Transcript prose body has **no max-measure**, so on a wide window summary text runs to 1200px+ line lengths (unreadable). Contrast PersonDetailView which DOES cap at 920 (`PersonDetailView.swift:249`) and Insights at 760. The prose cap is applied inconsistently across exactly the views that need it most.

**The 72/60px top inset is a workaround, repeated 5×.** `splitPaneTopInset = 60` (`NotionDesign.swift:20`) is hand-pasted into every split pane (`UnifiedMeetingDetail.swift:83`, `PeopleListView.swift:194`, `PersonDetailView.swift:248`, `PeopleInsightsView.swift:55`) to dodge the translucent Tahoe toolbar clipping content. Easy to forget on a new pane (it's a manual `Color.clear.frame`), and it burns 60px of vertical space on every split view at all window heights.

**Click counts (current):** Today meeting → detail = 1 click but routes to a *different tab* (Meetings), losing Today context. Tasks rail can't be hidden to reclaim space (0 affordance). Chat rail toggle = 1 click (toolbar) but on a 1100px window opening it drops content to ~720px with no warning.

## NET-NEW recommendations

### DL-1 — One shared `WorkspaceSplit` primitive (unify the four pane systems)
**What/why:** Extract a single `WorkspaceSplit(sidebar:detail:)` wrapper (resizable `HSplitView` under the hood) with ONE canonical sidebar width triple (e.g. `min:280 ideal:340 max:420`) and built-in top inset. Migrate Meetings, People, Voice Notes, Tasks onto it. Kills the NavigationSplitView/HSplitView/HStack divergence and the three conflicting width triples.
**UX impact:** Sidebar width stops jumping on tab-switch; the resize gesture works everywhere (Tasks rail becomes resizable, before→after: not-resizable → drag-to-resize). Consistent muscle memory across the workspace (req #3 integration).
**Perf/stability:** Pure refactor, no new allocations; one code path is easier to keep crash-free than four. `HSplitView` is cheaper than `NavigationSplitView`'s column machinery. Persist divider position in `@AppStorage` (cheap) so layout is stable across launches.
**Effort:** M · **Impact:** High · **Deps:** none.

### DL-2 — Collapsible sidebars with a uniform toggle (reclaim full width)
**What/why:** Add a persistent `sidebar.toggle` button (⌘⌥S) to each split tab so the list/rail can collapse to 0 and the detail goes full-width. Tasks' fixed 230px rail (`ActionItemsView.swift:110`) currently can't be hidden at all.
**UX impact:** On a focused read (a long transcript or a task page), 1 click reclaims ~340px. before→after: no way to widen detail → 1-click full-width. Pairs with DL-1.
**Perf/stability:** Collapsing unmounts nothing (keep-alive), just animates width; trivial. Store collapsed state per-tab in `@AppStorage`.
**Effort:** S · **Impact:** Med · **Deps:** DL-1.

### DL-3 — Reading-measure cap on ALL prose panes (fix wide-window line length)
**What/why:** Apply the PersonDetail pattern (`maxWidth: ~760, alignment: .leading`) to the Meetings Summary and Transcript bodies, which currently have no cap and run to full window width. Centralize as `NDS.proseMeasure` so it's one constant, not scattered magic numbers (760/920/900 today).
**UX impact:** Summary/transcript text becomes readable at any window size (45–80ch line length). No click change — pure legibility/density win on the highest-value content.
**Perf/stability:** A frame modifier; zero cost. Reduces layout thrash on resize because text reflow is bounded.
**Effort:** S · **Impact:** High · **Deps:** none.

### DL-4 — Width-adaptive density tiers (compact / regular / wide)
**What/why:** Replace the single 860px chat gate with a small `LayoutSize` enum derived from `GeometryReader` width (e.g. <980 compact, 980–1400 regular, >1400 wide). Drive: list row padding, whether the chat rail can open, and whether Meetings/People auto-collapse their list when the window is too narrow for three panes.
**UX impact:** Narrow windows stop cramming three panes into 180px detail; wide windows can show denser rows. Self-tuning — no manual toggling. Today already partly does this with FlowLayout pills (`TodayView.swift:365`); generalize it.
**Perf/stability:** One `GeometryReader` at the MainWindow root (already present, `MainWindow.swift:244`) publishing an enum via Environment — far cheaper than per-view geometry readers. Cache the tier; only re-evaluate on resize end.
**Effort:** M · **Impact:** High · **Deps:** none.

### DL-5 — Promote the top inset into the split primitive (delete 5 copies)
**What/why:** Fold `splitPaneTopInset` into DL-1's `WorkspaceSplit` (or a `.workspaceToolbarInset()` modifier) so no view hand-pastes `Color.clear.frame(height: 60)`. Reclaim the 60px where a pane has its own header by insetting the toolbar safe-area instead of stacking a spacer.
**UX impact:** New panes can't forget the inset (no more clipped titles); ~60px vertical reclaimed on panes that don't need a full spacer — more content above the fold.
**Perf/stability:** Removes 4–5 always-present `Color.clear` layers; negligible but real. No crash surface change.
**Effort:** S · **Impact:** Med · **Deps:** DL-1.

### DL-6 — In-tab Meeting detail on Today (stop the context jump)
**What/why:** Clicking a Today meeting card calls `router.openMeeting` which flips to the Meetings tab (`TodayView.swift:490`, `WorkspaceRouter.swift:43-46`), abandoning the Today feed. Add an inspector/overlay detail (or a right-side detail pane on wide windows via DL-4) so the meeting opens *in place* on Today.
**UX impact:** before→after: 1 click + full tab-context loss → 1 click in-place, back is free. Today becomes a true hub (req #4). On narrow windows, fall back to the current tab-switch.
**Perf/stability:** Reuses the already-cached `UnifiedMeetingDetail.reload()` (`UnifiedMeetingDetail.swift:166`) — body comes from `bodyCache` instantly, no new disk reads. Render only when wide tier (DL-4) so narrow windows pay nothing.
**Effort:** M · **Impact:** Med · **Deps:** DL-4.

### DL-7 — Chat rail as an overlay inspector on narrow windows (don't steal content width)
**What/why:** Below the wide tier, render the chat rail as a floating/overlay inspector (or push-over) rather than a third hard column that shrinks content (`MainWindow.swift:257-261`). Today on an 1100px window, opening chat squeezes the middle pane.
**UX impact:** Chat opens without collapsing the user's working content; on wide windows keep the current side-by-side. Predictable: content width no longer lurches when toggling chat.
**Perf/stability:** Overlay is the same `ChatSidebar` view, just a different container; no extra state. Keep the `>=860` gate as the side-by-side threshold and overlay below it.
**Effort:** M · **Impact:** Med · **Deps:** DL-4.

### DL-8 — Skeleton placeholders for split detail panes on first open
**What/why:** The detail panes paint from cache instantly when warm, but on a true cold first-open (cache miss) the Summary/Transcript area is blank until the async `bodyCache.load` returns (`UnifiedMeetingDetail.swift:195-206`). Add lightweight shimmer skeletons (header bar + 6 text lines) shown only while `transcript`/`summary` are empty and a load is in-flight.
**UX impact:** First open *feels* instant even on a cache miss — no blank flash. Reinforces the cache-first architecture visibly.
**Perf/stability:** Skeleton is static shapes (no data); cheaper than rendering real content. Gate on `bodyLoadTask != nil && summary.isEmpty` so it never shows on warm paint.
**Effort:** S · **Impact:** Med · **Deps:** none.

## Top 3 picks

1. **DL-1 — Shared `WorkspaceSplit` primitive** → **Phase 1** (foundational; every later layout item builds on one pane system, and it removes a real divergence/crash-surface).
2. **DL-3 — Reading-measure cap on all prose panes** → **Phase 2** (tiny effort, immediate legibility win on the highest-value content; pairs with the density work).
3. **DL-4 — Width-adaptive density tiers** → **Phase 2** (unlocks DL-6/DL-7 and makes the app feel native at every window size, cheaply via one root GeometryReader).
