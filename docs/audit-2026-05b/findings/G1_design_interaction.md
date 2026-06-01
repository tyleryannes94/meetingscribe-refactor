# Design — Interaction Design & Motion

Lens: transitions, perceived performance (skeletons, optimistic UI, progressive loading), feedback/affordances, micro-interactions, reduce-motion — perceived performance *is* interaction design, so I lean hardest on the speed/caching constraint.

## Audit (through my lens)

**What's already solid (verified in code — do NOT re-propose):**
- `ToastCenter` + `ToastOverlay` exist with an Undo affordance, 6s auto-dismiss, and a clean `.move(edge:.bottom).combined(with:.opacity)` transition (`ToastCenter.swift:21,66,69`).
- Tab switching is a keep-alive ZStack with a 0.15s cross-fade and lazy first-build; the old background `prewarmOtherTabs` was deliberately killed for first-paint perf (`MainWindow.swift:90-106,220-225`). Tabs build on first selection backed by a warm `MeetingStore` index + `MeetingBodyCache`.
- Meeting detail uses sync-cache-paint + async-disk-refresh so clicking a meeting no longer hitches (`UnifiedMeetingDetail.swift:161-180`). Just-stopped meeting body is prefetched (`MainWindow.swift:391-398`).
- Reduce Motion is handled in 6 files — the recording `PulsingDot` goes static (`FloatingOverlay.swift:470,484`), and `pulsingSymbol(active:)` gates SF Symbol pulse on motion (`NotionDesign.swift:126-132`).
- FloatingOverlay HUD is genuinely good: pulsing dot, live audio meter, transcribing spinner, done-pill with Copy/Open, hover spring on `OverlayButton` (`FloatingOverlay.swift:497-529`). Meeting recording now promotes to the same HUD (D4-1).
- Hover states on nav rail (`MainWindow.swift:459,484`), press-scale button styles with 0.1s ease (`NotionDesign.swift:294,311,326`).

**Gaps (the opportunity space):**
1. **No skeletons anywhere.** Grep for `skeleton|shimmer|redacted` returns only diagnostics/placeholder hits. Every loading path is either a bare `ProgressView` spinner (27 occurrences across 18 files) or an instant empty state. On a cold open where the index cache is *cold* (first-ever launch, or after cache eviction), lists pop from blank → full with no intermediate structure, and the actionable empty state ("No meetings yet") can briefly flash *before* data loads — empty and loading are not distinguished.
2. **`placeholder(...)` conflates empty and loading** (`UnifiedMeetingDetail.swift:150-158`): a meeting whose body is still being read shows the same "No transcript" placeholder as one that genuinely has none, until the async refresh lands. No "loading transcript…" intermediate.
3. **ThumbnailCache decode is synchronous on the main thread** (`ThumbnailCache.swift:18-24`): first scroll past an un-cached photo runs `CGImageSourceCreateThumbnailAtIndex` inline, so the People grid stutters on first reveal of each new face. There is no async load + fade-in.
4. **Tab cross-fade is uniform 0.15s opacity** (`MainWindow.swift:96`) — fine, but content inside the newly-shown tab does not itself animate in, so a freshly-built tab "snaps" its list into place after the fade completes (two-stage feel).
5. **Few optimistic mutations.** Summary generation shows "Generating…" tied to `transcribingMeetingIDs` (`MeetingSummaryTab.swift:82,90`) — good — but adding a person, adding a tag, completing a task, and adding an encounter wait for the store round-trip before the row appears/updates; there's no insert-then-reconcile. Most are fast locally, but the *feel* is "click → tiny pause → appears" rather than instant.
6. **Toast is the only global feedback channel and it's bottom-center only.** No inline success affordance for in-context actions (e.g. tag applied), no progress toast for long jobs (import/transcribe) — those live only in the toolbar as tiny "N finalizing" text (`MainWindow.swift:573-579`), easy to miss.
7. **No drag-and-drop affordances** in Tasks (reorder/move-between-projects) or for importing audio onto a meeting card — import is menu/file-panel only (`MainWindow.swift:498-507`).

Click counts: opening a meeting from anywhere is already 1 click via `WorkspaceRouter` (`WorkspaceRouter.swift:43`). Import meeting = 2 clicks + file panel. Reorder a task = not possible (no DnD).

## NET-NEW recommendations

### DI-1 — Skeleton scaffolds for every list's first paint
**What/why:** Add a lightweight `SkeletonRow` / `SkeletonCard` (gray rounded rects, optional 1.2s shimmer gated by Reduce Motion) shown when a tab's data source is *loading and empty* — distinct from the actionable "truly empty" state. Drive it off an explicit `loadState` (`.loading | .empty | .loaded`) on each view model rather than `array.isEmpty`. Skeletons for Meetings list, People grid, Tasks, Today widgets.
**UX impact:** Cold first-open *feels* instant — structure appears in <16ms while real rows stream in, instead of a blank pane then a pop. Kills the empty-state flash (item 1/2). No click change.
**Perf/stability:** Pure SwiftUI shapes, near-zero cost, no data dependency — they render *before* the cache read returns, which is the whole point. Shimmer is a single `LinearGradient` offset animation; disabled under Reduce Motion. Caching synergy: the warm-index path skips straight to `.loaded`, so skeletons only ever show on genuinely-cold reads. **Effort: M. Impact: High. Deps:** small `loadState` enum on the 4 view models.

### DI-2 — Async, fade-in thumbnails (move decode off main)
**What/why:** Wrap `ThumbnailCache.thumbnail` in an async loader (`Task.detached` decode → publish on main) with a `.transition(.opacity)` fade and a neutral monogram placeholder while decoding.
**UX impact:** People grid scrolls glassy-smooth on first reveal; faces fade in instead of the row hitching. No click change.
**Perf/stability:** Directly removes a main-thread `CGImageSource` decode from the scroll path (item 3) — the single biggest People-scroll jank source. Memory unchanged (same NSCache, countLimit 256). Add a tiny in-flight-key set to dedupe concurrent loads of the same URL. **Effort: S. Impact: High. Deps:** none (ThumbnailCache.swift only).

### DI-3 — Optimistic mutations with reconcile + Undo
**What/why:** For add-person, add/remove-tag, complete-task, add-encounter: insert/flip the model in memory immediately, fire the store write in the background, and reconcile (or roll back + toast) on completion. Reuse the existing `ToastCenter` Undo path (`ToastCenter.swift:30`) for rollback.
**UX impact:** Every quick edit feels instant; tagging a person updates People list + meeting + tasks in the same frame (directly serves the cross-tab "edits reflect everywhere instantly" goal). Removes the click→pause→appear lag (item 5).
**Perf/stability:** Moves disk/store latency off the interaction; if a write fails, the toast offers Undo so no silent data loss. Slightly more code paths to test — guard with the reconcile step so the optimistic and persisted states can't diverge. **Effort: M. Impact: High. Deps:** ToastCenter (exists).

### DI-4 — Persistent progress toast for long jobs (import / transcribe / summarize)
**What/why:** Extend `ToastCenter` with a non-auto-dismissing `progress` variant (determinate where possible, else indeterminate) for import/transcription/summary, replacing the easy-to-miss toolbar "N finalizing" text.
**UX impact:** User gets clear, glanceable feedback that work is happening and when it's done (a success toast on completion → 1-click "Open" to the result). Surfaces background work that's currently nearly invisible (item 6).
**Perf/stability:** Subscribes to existing `transcribingMeetingIDs` / pipeline state — no new polling. Pure presentation. **Effort: S. Impact: Med. Deps:** ToastCenter extension.

### DI-5 — Two-stage tab transition: cross-fade + content settle
**What/why:** Keep the 0.15s tab cross-fade but add a subtle 8px slide-up + opacity on the *incoming* tab's content root (gated by Reduce Motion), so the new tab feels like it arrives rather than snapping after the fade.
**UX impact:** Tab switches feel deliberate and alive instead of two-stage (item 4). No click change.
**Perf/stability:** One transform animation on an already-built view; trivial cost. Must respect `accessibilityReduceMotion` (fall back to plain opacity). **Effort: S. Impact: Med. Deps:** none.

### DI-6 — Drag-and-drop in Tasks + drop-to-import on meetings
**What/why:** Add `.draggable`/`.dropDestination` so tasks reorder within and move between projects, and so dropping an audio file onto a meeting card/detail imports it (currently file-panel only).
**UX impact:** Reorder a task: impossible → drag (0 dialogs). Import audio: 2 clicks + panel → 1 drag. Modern, expected affordance.
**Perf/stability:** SwiftUI native DnD; reorder mutates the in-memory ordered array then persists async (pairs with DI-3 optimistic pattern). No load-time cost. **Effort: M. Impact: Med. Deps:** DI-3 reconcile pattern (recommended).

### DI-7 — Hover-reveal quick actions on list rows
**What/why:** On meeting/person/task rows, reveal 1–2 trailing icon actions on hover (e.g. meeting: Open + Copy summary link; person: Ask AI; task: complete checkbox always visible). Currently primary actions require opening the detail first.
**UX impact:** Common post-open actions move from inside-detail (2+ clicks) to inline (1 click) without adding permanent visual clutter. Reinforces the "every action ≤2 clicks" goal.
**Perf/stability:** Hover state is already used on rows (`MainWindow.swift:459`); reuse the pattern. Render the action buttons lazily on hover so non-hovered rows stay cheap. **Effort: M. Impact: Med. Deps:** none.

### DI-8 — Spinner→content fade + min-display floor on detail panes
**What/why:** When a meeting body loads async (`UnifiedMeetingDetail.reload`), show a transcript/summary *skeleton* (not the empty placeholder) until the disk refresh resolves, and cross-fade to real content. Add a ~120ms minimum so fast cache hits don't flash a spinner for one frame.
**UX impact:** Removes the "No transcript → actual transcript" flash on slower reads (item 2); content feels like it was always there on warm cache.
**Perf/stability:** Skeleton is free; the min-display floor prevents a jarring spinner blink on the common warm-cache path. Drive off the same `loadState` from DI-1. **Effort: S. Impact: Med. Deps:** DI-1.

## Top 3 picks

1. **DI-1 — Skeleton scaffolds (Phase 1).** Foundational + perf-aligned: introduces the `loadState` enum the whole audit can build on, and makes cold first-open feel instant for free. The single highest-value item — it's the missing half of the caching story (cache makes data *arrive* fast; skeletons make the *wait* feel fast).
2. **DI-2 — Async fade-in thumbnails (Phase 1).** Removes the only confirmed main-thread decode in a scroll path; small, isolated, immediate smoothness win in People.
3. **DI-3 — Optimistic mutations + Undo reconcile (Phase 2).** Makes cross-tab edits feel instant and unifies the "edit once, reflects everywhere" goal with a safety net via the existing ToastCenter.

Perf/caching insight: the app already nails *data* speed (warm index, body cache, killed prewarm). The unaddressed half is *perceived* speed during the cold/async window — skeletons (DI-1/DI-8) and off-main thumbnail decode (DI-2) are nearly free and convert the existing cache work into a visibly instant first open.
