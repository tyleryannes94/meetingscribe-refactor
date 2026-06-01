# MeetingScribe — Claude Code Build Playbook (V5: UX + Performance, 4 Phases)

Copy-paste prompts to have Claude Code build out **Master Plan V5** (UX, layout, tab integration, performance) in 4 phases. Each phase radically improves the app; performance/caching/crash-safety is the Phase-1 spine that the rest inherits.

## How to use
- Run **one prompt per Claude Code session**, in order. Don't start the next phase until the current PR is open and green.
- **Paste PROMPT 0 first** (once); optionally append it to `~/MeetingScribeRefactor/CLAUDE.md`.
- Each block between `===== COPY =====` markers is self-contained.
- Full per-item detail (problem, `file:line`, perf note) is in `docs/audit-2026-05b/` once you commit it (see "Reference docs" below). Item IDs (e.g. `PC-1`, `SD-3`) map there + to `MASTER_PLAN_V5_UX_Performance.md`.

## Build order
1. **PROMPT 1 — Phase 1: Instant & Stable Foundation** (cache-first open, skeletons, kill main-thread I/O, indexes, crash-safety)
2. **PROMPT 2 — Phase 2: One Native, Connected Workspace** (NavigationSplitView shell, shared components, cross-tab entity index, VaultEventBus, fluid nav)
3. **PROMPT 3 — Phase 3: Per-Tab Excellence & Click-Reduction**
4. **PROMPT 4 — Phase 4: Premium Native Polish & Best-in-Class Recall**

Git model: **one branch + one PR per phase** (large phases split into multiple PRs on the phase branch).

## Reference docs (do this once before Phase 1)
The plan + findings need to be in the repo so Claude Code can read the evidence. From your terminal:

```bash
cd ~/MeetingScribeRefactor
git checkout main && git pull
mkdir -p docs/audit-2026-05b
# copy MASTER_PLAN_V5_UX_Performance.md, ClaudeCode_Build_Playbook_V5.md,
# and the audit2/findings/ folder into docs/audit-2026-05b/ (from the outputs folder)
git add docs/audit-2026-05b/
git commit -m "docs: add V5 UX/perf audit, 4-phase plan, and build playbook"
git push origin main
```

(If you'd like, I can place these files into the repo for you and give you the exact commit/push commands, like last time.)

---

## PROMPT 0 — Ground rules (paste once / append to CLAUDE.md)

```text
You are working in MeetingScribe at ~/MeetingScribeRefactor (remote: tyleryannes94/meetingscribe-refactor, default branch main). NEVER touch ~/MeetingScribe or the frost repo.

We are executing a 4-phase UX + performance build (Master Plan V5). Reference docs are in docs/audit-2026-05b/:
- MASTER_PLAN_V5_UX_Performance.md (the plan)
- findings/*.md (full per-item detail with file:line evidence)
Read the relevant plan section + findings file before implementing any item. Item IDs (e.g. PC-1, SD-3, CN-1) map to those files.

GROUND RULES for every phase:
1. Branch + PR per phase. Start by: checkout main, pull, then create the branch I name. Commit per item or tight group. At phase end, push and open a PR; do not merge — I will. Split large phases into multiple PRs on the same branch by sub-section.
2. Commit style: imperative, category prefix (feat:/fix:/refactor:/perf:/docs:), under 72 chars; body wrapped at 80 explaining WHY when non-obvious. No trailers.
3. Build verification BEFORE every commit of non-trivial Swift: run `swift build -c release` (or `make app`). Errors block the commit.
4. Smoke test before opening a PR where the phase touches capture/UI: `make app`, launch, record a ~30s meeting, stop, confirm transcript + summary + notification fire and nothing is lost. Note it in the PR.
5. PERFORMANCE IS A REQUIREMENT, NOT A NICE-TO-HAVE. Every change must keep or improve cold-start, scroll smoothness, memory, and crash-resistance. Do disk/CPU work OFF the main thread; back hot paths with caches/indexes; render cache-first then reconcile; never read a file body to answer a boolean. If you add a cache, make it bounded (byte/count limit) and corruption-safe.
6. Do NOT regress the capture→transcribe→summarize→persist pipeline. If an item touches MeetingManager / MeetingPipelineController / LiveTranscriber / WhisperRunner / the stores, call it out and proceed carefully with tests.
7. Environment: macOS 26 / Apple Silicon. Use /usr/bin/open directly in scripts. Signing identity "MeetingScribe Local Signer"; bundle id com.tyleryannes.MeetingScribe.
8. Scope discipline: implement ONLY the current phase's items. Note out-of-scope findings in the PR under "Found but out of scope".
9. Prefer reusing the existing infra (MeetingBodyCache, ThumbnailCache, .upcoming-cache.json, ResourceGovernor, MetricsStore, WorkspaceRouter, ToastCenter) over inventing parallel systems.

WORKFLOW each phase: read plan+findings → list the phase's items + flag pipeline-risky ones → implement with build gating → smoke test → push branch → open PR (checklist of items, before/after click counts where relevant, perf notes, out-of-scope findings) → report back with branch, PR link, items done, anything blocked.

Confirm you've read docs/audit-2026-05b/MASTER_PLAN_V5_UX_Performance.md before starting Phase 1.
```

---

## PROMPT 1 — Phase 1: Instant & Stable Foundation

```text
Phase 1: Instant & Stable Foundation. Branch: perf/p1-instant-stable.

Read docs/audit-2026-05b/MASTER_PLAN_V5_UX_Performance.md "Phase 1" and the cited findings (findings/G4_perf_coldstart.md, G4_perf_runtime.md, G4_perf_stability.md, G4_perf_perceived.md, G5_comp_perf.md, plus G2_tab_today.md, G3_sync_consistency.md for the snapshot/skeleton items). Build it as multiple PRs on this branch in this order:

PR-A Caching spine & instant open:
- PC-3: a shared `VaultCache` layer (atomic write, versioning, TTL, corruption recovery).
- PC-1/CB-1/TT-1/SC-6/PP-3/TM-1: a Launch Snapshot — persist tiny per-surface snapshots (Today feed, meeting list rows, people list, task list) and render them synchronously on frame 0, then reconcile when stores hydrate. Reuse the existing .upcoming-cache.json/_people-cache.json patterns; route through VaultCache.
- PC-2: move SecondBrainDB sqlite3_open + quick_check off the launch thread.
- TT-2/PC-5/PC-8: defer heavy backfills (embeddings/decisions/person-extraction) off the first-paint frame; lazy-construct non-first-screen @StateObjects.
- CB-3: apply the SQLite production pragma profile (synchronous=NORMAL, mmap_size, cache_size, busy_timeout).
- PC-7/CB-8: add local-only cold-start instrumentation to MetricsStore + a launch budget.

PR-B Skeletons & honest loading:
- PP-1/PC-4: a tri-state loadState (loading/loaded/empty) keyed on loadedAt, on detail tabs + lists (kills the "No summary/No transcript" cold-cache flash).
- DI-1/DV-4/PP-2/SC-4: an MSSkeleton/.redacted primitive, gated to true cache-misses and reduce-motion-aware.
- DV-5/SC-3: MSEmptyState on ContentUnavailableView for empty/zero/error states.

PR-C Kill main-thread I/O & O(n) render work:
- PR-1/PS-1/TM-2: stop MeetingCard.hasFile reading the whole transcript via String(contentsOf:) (MeetingCard.swift:316); drive status from meeting.health; route list/card status through cache.
- PR-3/TP-1: [String:Person] index in PeopleStore; O(1) person(by:) + encounterCount.
- PR-2: [String:MeetingTag] index in TagStore + per-meeting tag cache.
- DI-2/PR-5/TP-2: async, fade-in, disk-persisted thumbnail cache used everywhere incl. graph nodes.
- PR-4: memoize + debounce the People list pipeline.
- TK-2/PR-7/SP-4: debounced, coalesced, off-main persistence; batch bulk-edit writes (no full-DB encode on the main actor per edit).

PR-D Crash-prevention & stability:
- PS-3: hard crash capture (NSSetUncaughtExceptionHandler + signal handlers) into the diagnostics bundle.
- PS-5/PS-2/PS-6: byte-bound caches (totalCostLimit + body-byte cap); bound the Chat conversation; cache+bound backlinks.
- PS-4: race-proof the off-main PeopleStore.load().
- CB-6: vault write-ahead journal + startup resume/integrity sweep.
- PS-8: a stability test floor (long-meeting fuzz + race tests).

Follow the ground rules. Measure cold-start before/after with the new instrumentation and report the delta in the PR. Smoke test heavily. Report back per PR.
```

---

## PROMPT 2 — Phase 2: One Native, Connected Workspace

```text
Phase 2: One Native, Connected Workspace. Branch: feat/p2-connected-workspace. Depends on Phase 1 (build on the cache/skeleton/index primitives).

Read docs/audit-2026-05b/MASTER_PLAN_V5_UX_Performance.md "Phase 2" and cited findings (G5_comp_macos.md, G1_design_layout.md, G1_design_nav.md, G3_sync_datamodel.md, G3_sync_consistency.md, G3_sync_propagation.md, G5_comp_pkm.md). Build as multiple PRs on this branch:

PR-A Native shell & unified layout:
- CM-1: adopt NavigationSplitView for the shell (sidebar + detail), keep tab warmth via @SceneStorage; retire the ZStack keep-alive + splitPaneTopInset/padding(.top,48) hacks.
- DL-1/DL-5: one shared WorkspaceSplit pane primitive (unify the 4 pane systems + sidebar-width triples); promote the top inset into it.
- CM-2/DL-2/DN-8: restore window frame + .defaultSize; collapsible, keyboard-focusable sidebars.
- DL-3/DL-4: reading-measure cap on prose panes; width-adaptive density tiers off one root GeometryReader.

PR-B Shared component library:
- SC-1: MSList selectable-list primitive (List(selection:)) — keyboard nav + selection everywhere; host for skeletons + snapshot cache + row context menus.
- SC-2: MSSearchField + universal ⌘F-focus + Esc-clear.
- SC-5/SD-6: MSTagPicker over one unified TagRegistry (merge meeting vs people tag namespaces).
- DV-2/SC-8: extract MSCard/MSListRow/MSSurface; collapse to one button vocabulary.
- SC-7: row-level context menus in MSList.

PR-C Cross-tab entity graph:
- SD-3/TP-7: a cache-backed EntityGraphIndex actor (persisted reverse index: person→meetings/tasks/decisions, meeting→tasks/backlinks) built at write-time.
- SD-2: stable personID on meeting attendees + persisted resolver (replace email/substring matching).
- SD-4: persisted backlink rows (replace file-scanning backlinks()).
- SD-5: Decision person edge (commitOwnerPersonID/relatedPersonIDs).
- SD-8: index lifecycle + integrity guard.

PR-D Live propagation:
- SP-2: a typed, coalesced VaultEventBus (debounced, ID-scoped) — surgical cache/FTS invalidation, no nuke-all.
- SP-1/SP-5: app-side vaultChanged/inboxChanged observer + idempotent reloadFromDisk() (so MCP/Shortcut edits appear live).
- SP-3: make AttendeeChip + MeetingSummaryTab observe PeopleStore.
- DI-3/PP-5: generalized optimistic-edit + reconcile via ToastCenter with Undo.
- SP-8: subscribe Today to the bus.

PR-E Fluid navigation:
- SD-1/DN-7: shared selectedPersonID/focus in WorkspaceRouter; route ALL nav through the router (kill NotificationCenter/asyncAfter hops).
- CP-1: side-peek overlay for cross-entity links (open linked entity without losing place).
- DN-1/CP-5: global back/forward (⌘[/⌘]) + breadcrumb spine.
- DN-4/DN-6: cache-backed Recently-viewed rail + empty-⌘K recents + quick-switcher.

Follow the ground rules. CM-1 (NavigationSplitView) is the riskiest — its own PR, fully smoke-tested. Keep MeetingStore/BodyCache warm so first paint stays skeleton-free. Report back per PR with before→after click counts.
```

---

## PROMPT 3 — Phase 3: Per-Tab Excellence & Click-Reduction

```text
Phase 3: Per-Tab Excellence & Click-Reduction. Branch: feat/p3-per-tab. Depends on Phase 2 (every list is now MSList; nav/index/bus exist).

Read docs/audit-2026-05b/MASTER_PLAN_V5_UX_Performance.md "Phase 3" and cited findings (G2_tab_today.md, G2_tab_meetings.md, G2_tab_people.md, G2_tab_tasks.md, G2_tab_secondary.md, G5_comp_notetakers.md, G5_comp_pkm.md). Apply the 3-click/2-click rule; report before→after click counts. Build as one PR per tab on this branch:

TODAY: TT-3/TT-5 (status-strip hero; consolidate the 3 task surfaces into one "Today's work" block); TT-6/TT-4/TT-8 (pull Notes into Today; snapshot section lists into @State; route person-open through shared selection).

MEETINGS: CN-1/TM-5 (Enhanced Notes merged canvas — collapse Transcript/Notes/Summary into one default view; always-present Outcomes strip with action-items + decisions; render cached merged markdown, lazy-load transcript on toggle); TM-4/TM-7/TM-8 (decisions capture to ledger; virtualize/paginate long transcripts + in-transcript find; collapsible compact reading header); CN-2/TM-9 (clickable outline/jump-to-moment rail; attendee→Person hover card + "Add all to People").

PEOPLE: TP-3/TP-9 (background graph build + progressive layout + skeleton; lazy section scaffold for the 14-section page); TP-5/TP-8/TP-4 (Person→Decisions/Commitments section; inline reconnect/cadence on "gone cold"; surface the dead find-path feature).

TASKS: TK-1 (collapse to the existing dead ActionItemsViewModel as the single cached source of truth); TK-3/TK-4 (multi-select + bulk action bar; keyboard-first nav & quick-set); TK-5/TK-8/TK-9 (editable virtualized table + richer board cards; resizable persisted-width sidebar; cached group-by buckets + saved views).

SECONDARY: TS-4 (sectioned Settings + revive the orphaned IntegrationsView, lazy section bodies); TS-1/TS-5 (persist & thread the Chat session; voice notes as first-class linkable entity); CP-2/TS-2/TS-6 (⌘K contextual command runner; Settings + recent searches in ⌘K; context-aware chat prompts + "Ask about this"); CN-6/PP-6 (sub-30s summary-ready path with optimistic skeleton over stale content).

Follow the ground rules. Each tab is its own PR. Keep everything cache-backed and off-main (lists are MSList; heavy builds behind skeletons). Report back per PR.
```

---

## PROMPT 4 — Phase 4: Premium Native Polish & Best-in-Class Recall

```text
Phase 4: Premium Native Polish & Best-in-Class Recall. Branch: feat/p4-polish-recall. Depends on Phases 1-3.

Read docs/audit-2026-05b/MASTER_PLAN_V5_UX_Performance.md "Phase 4" and cited findings (G1_design_visual.md, G5_comp_macos.md, G1_design_interaction.md, G5_comp_notetakers.md, G5_comp_perf.md, G5_comp_pkm.md, G2_tab_people.md). Build as multiple PRs on this branch:

PR-A Design system & native feel:
- DV-3: mechanically collapse the three type systems (NDS tokens + raw .system(size:) + SwiftUI styles, 590+ calls) into NDS Font.TextStyle tokens; finish Dynamic Type.
- DV-1/DV-6/DV-9: spacing + elevation scale with a lint; tokenize remaining color leaks + semantic status colors; tokenize/cache shadows.
- CM-3/DV-7: semantic system colors + materials (macOS 26 Liquid Glass-ready), NDS as a thin alias; native translucency on chrome.
- CM-4/CM-6/CM-7/CM-5: one native .toolbar with trailing search; native sidebar disclosure + badges; native control idioms; hold-⌘ shortcut reveal + type-to-jump.
- DV-8/DL-4: density (compact/comfortable) toggle backed by the spacing scale.

PR-B Interaction delight:
- CP-4: hover-preview on backlinks + attendee chips.
- DI-7/DI-6/DI-5/DI-4: hover-reveal quick actions on rows; drag-and-drop in Tasks + drop-to-import on meetings; two-stage tab transition; persistent progress toast for long jobs.

PR-C Best-in-class recall & competitive parity:
- CN-7/CN-4: "Ask across all meetings" with cited, deep-linked answers (100% local); preset "ask this meeting" chips.
- CN-5/CN-8/CN-9: one-click highlight/clip → timestamped & shareable; density/comfort + scannable rows; visible local-first "instant, offline, no bot" trust strip.
- CB-4/CB-5/CB-2: predictive prefetch on hover/selection; off-main markdown render with cached AttributedString; persist MeetingBodyCache + thumbnails across launches.
- CP-6/CP-8/TP-10: optional two-pane list+detail mode; symmetric backlinks for People/Tasks/Notes; saved smart segments.

Follow the ground rules. DV-3 (type-system collapse) is large and mechanical — its own PR, verify no visual regressions via before/after screenshots of each tab. Report back per PR.
```

---

## Reusable snippets

### Per-phase PR description template
```text
## <Phase / sub-PR>
Items completed: <IDs as checklist>
Plan refs: docs/audit-2026-05b/MASTER_PLAN_V5_UX_Performance.md + <findings files>
### Verification
- swift build -c release: PASS/FAIL · Tests added: <list> · Smoke test: PASS / N/A
- Perf: cold-start before→after <ms>; scroll/typing jank notes; memory notes
- Click budget: <surface: before→after>
### Found but out of scope
- <...>
### Risk notes
- <pipeline-adjacent changes, new caches (bounded? corruption-safe?), migrations>
```

### Perf/stability acceptance checklist (every PR)
```text
- No synchronous disk reads or O(n) scans added in a SwiftUI view body.
- New caches are bounded (byte/count) and corruption-safe (atomic write + recover).
- Disk/CPU work runs off the main actor; UI renders cache-first then reconciles.
- Cold-start time did not regress (check MetricsStore instrumentation).
- No new force-unwraps/try! on user-data paths; new shared mutable state is race-safe.
```

### "You're stuck" rescue prompt
```text
You seem blocked. (1) Commit what compiles. (2) Summarize the failure (error + file:line) and what you tried. (3) Give 2 options with trade-offs. (4) Recommend one and wait. Don't force a change that breaks the build, the capture pipeline, or cold-start performance.
```
