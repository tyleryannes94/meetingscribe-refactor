# Group 2 — TODAY tab (Home / glanceable launch screen)

Lens: Today is the FIRST screen on open. It must render *instantly* (cache-first),
read like a 5-second glance, and be the connective hub that pulls live from every
other tab. Optimize for cold-start speed, glance-ability, and the 3-click rule.

## Audit (through my lens)

**Structure today.** `TodayView.swift` is a single `ScrollView` → `VStack(spacing:22)`
stacking **13** sections in fixed order (`TodayView.swift:44-91`): header, quickActions,
upNextCard, liveSection, NeedsAttentionWidget, todaySection, ActionItemsWidget,
followUpsSection, commitmentsSection, decisionsSection, onThisDaySection,
SuggestedPeopleView, ReconnectView. Strong content, but it's a **vertical wall** — no
top-of-page glanceable summary, no prioritization, and three near-duplicate task
surfaces (NeedsAttention + ActionItems + Commitments) compete for the same eye.
The "Action items today & yesterday" widget and "Needs attention" widget overlap
heavily in meaning.

**Cold-start / first-open behavior (the hard constraint).**
- Calendar is cache-warmed: `CalendarService.init` reads `.upcoming-cache.json` off-main
  and republishes (`CalendarService.swift:31-51`), so today's meetings can paint on launch.
  Good — but it's the **only** cached surface.
- *Everything else on Today is computed live with no snapshot:* `pastMeetings`
  (`MeetingManager.swift:31`, hydrated async in `refreshPastMeetings`, :428-441),
  `decisions.decisions`, `actionItems.items`, follow-ups, commitments, on-this-day.
  On first open, before stores hydrate, half the feed is empty then pops in — no
  skeleton, visible reflow.
- `onAppear` (`TodayView.swift:31-39`) immediately fires **six** refresh/backfill
  jobs — `refreshUpcoming`, `refreshPastMeetings`, `backfillActionItemsIfNeeded`,
  `backfillPeopleIfNeeded`, `backfillSearchIndexIfNeeded`, `backfillEmbeddingsIfNeeded`,
  `backfillDecisionsIfNeeded`. Embeddings/decisions/person-extraction are the heaviest
  CPU work in the app and they're kicked off on the *first* frame of the *first* screen,
  contending with first render. There's TTL throttling (`pastMeetingsRefreshInterval`
  2s, `upcomingRefreshInterval` 30s) but no launch-deferral.

**Recompute cost on every render.** Each section is a computed property doing fresh
filter+sort over the full stores on every SwiftUI re-render: `pendingFollowUps`
(filters all pastMeetings, :98-106), `commitmentsSection` (filters all action items
twice, :154-158), `onThisDay` (date-component math over all pastMeetings, :243-257),
and `ReconnectView` computes a **median inter-encounter gap per person** inline
(`SuggestedPeopleView.swift:96-112`). Any unrelated `@Published` change on manager
re-runs all of it. PreMeetingBrief correctly snapshots into `@State` (:18-19) — Today
should do the same.

**Click counts (mostly good already).** Record ≤1 click (primary button :351), Join &
record 1 click (:402), mark task done 1 click, open meeting 1 click. Within the 3-click
rule. The gap is *glance* speed, not click depth.

**Tab integration gaps.** Today pulls from Meetings, Tasks, People, Decisions — but
**nothing from the Notes tab** (no recent-notes / pinned-note surface). People
integration is one-directional (suggestions + reconnect nudges) with a 50ms
`asyncAfter` notification hack to open a person (`TodayView.swift:578-584`) instead of
shared routed selection.

## NET-NEW recommendations

### TT-1 — Persisted "Today Snapshot" rendered instantly on launch (cache-first home)
**What/why:** Add a `TodaySnapshot` Codable struct (counts + top-N items for each
section: up-next meeting, needs-attention items, top decisions, follow-ups, commitments,
on-this-day) persisted to `.today-snapshot.json` alongside the existing upcoming cache.
On `init`, decode off-main and render the *entire* Today feed from the snapshot
immediately (like `CalendarService.swift:42-49` does for upcoming). Refresh the snapshot
in the background after stores hydrate, then diff-in. Mirrors how Things/Sunsama paint
"Today" instantly from local state.
**UX impact:** First open paints a full, real home in <100ms instead of an empty/popping
feed. No before→after click change; this is perceived-speed.
**Perf/stability:** The single biggest first-open win. One small JSON read replaces
waiting on 5 stores + EventKit. Cap each list to top 6–8 so the file stays tiny. Crash-safe
(atomic write, schema-versioned envelope like `SchemaEnvelope`). Effort M. Impact High.
**Deps:** none (extends existing cache pattern).

### TT-2 — Defer heavy backfills off the first frame
**What/why:** `onAppear` launches embeddings/decisions/person-extraction immediately
(`TodayView.swift:34-38`). Gate the expensive three behind a `Task` with a short delay
(or `.task` + `Task.yield()` after first paint, or trigger on app-idle / ResourceGovernor
green) so first render isn't competing for CPU. Keep the cheap `refreshUpcoming` /
`refreshPastMeetings` eager.
**UX impact:** None visible except a faster, jank-free first paint.
**Perf/stability:** Directly improves cold-start smoothness and reduces launch CPU/thermal
spike; pairs with ResourceGovernor. Effort S. Impact High. **Deps:** TT-1 (snapshot covers
the gap while backfills are deferred).

### TT-3 — Glanceable "status strip" hero at top
**What/why:** Above the section wall, add one compact row of tappable summary chips:
"Next at 2:00 · 3 due today · 2 follow-ups · 1 decision." Each chip scrolls-to / routes to
its section. Modern dashboards (Sunsama, Akiflow, Fantastical) lead with a single-glance
summary, not a scroll. Reads entirely from the TT-1 snapshot.
**UX impact:** 5-second glance to know "what matters today" without scrolling.
Chip→section in 1 click. **Perf:** Renders from cached counts, zero new computation.
Effort S. Impact High. **Deps:** TT-1.

### TT-4 — Snapshot the per-section computed lists into `@State`
**What/why:** Move `pendingFollowUps`, commitments split, `onThisDay`, and the reconnect
median-gap math out of inline computed properties into `@State` populated once in
`onAppear`/`onChange` (the pattern PreMeetingBrief already uses, `PreMeetingBriefView.swift:18-19`).
**UX impact:** None visible. **Perf/stability:** Eliminates O(n) filter/sort/median passes
on every unrelated re-render — major scroll/runtime smoothness win as meeting count grows.
Effort M. Impact High. **Deps:** none (independent of TT-1, complementary).

### TT-5 — Consolidate the three task surfaces into one prioritized "Today's work" block
**What/why:** NeedsAttentionWidget (overdue/due-today), ActionItemsWidget (today+yesterday),
and the Commitments owe/owed split present overlapping items in three boxes. Merge into a
single block with segments (Overdue · Due today · You owe · Owed to you), de-duplicated.
**UX impact:** Removes redundancy and decision fatigue; one place to triage. Mark-done stays
1 click. **Perf:** Fewer view subtrees + one filtered pass instead of three. Effort M.
Impact Med-High. **Deps:** TT-4.

### TT-6 — Pull recent/pinned Notes into Today (close the missing-tab gap)
**What/why:** Today integrates 4 of 5 tabs but never the Notes tab. Add a compact
"Recent notes" surface (last edited / pinned) sourced from the notes store, cached into the
TT-1 snapshot. Makes Today the true cross-tab hub the briefing asks for.
**UX impact:** Note reachable from home in 1 click instead of tab-switch + scan.
**Perf:** Top-N only, from snapshot. Effort S-M. Impact Med. **Deps:** TT-1.

### TT-7 — Skeleton placeholders + section collapse/reorder
**What/why:** While the background refresh runs post-snapshot, show lightweight skeletons
for not-yet-hydrated sections instead of empty space; let users collapse/hide low-value
sections (persisted). Auto-hide empty sections is already done (good) — add ordering control.
**UX impact:** No reflow flash; users tune their home. **Perf:** Skeletons are static shapes
(cheap); collapse state avoids building hidden subtrees. Effort M. Impact Med. **Deps:** TT-1.

### TT-8 — Route person opening through shared selection (kill the asyncAfter hack)
**What/why:** `openPerson` posts a NotificationCenter event behind a 50ms `asyncAfter`
(`TodayView.swift:578-584`) hoping People mounts first — racy. Replace with a routed
pending-selection on `WorkspaceRouter` (set section + pendingPersonID; People reads it on
appear), matching how meetings already route via `router.openMeeting`.
**UX impact:** Reliable 1-click person open from Today nudges. **Perf/stability:** Removes a
timing race that can silently no-op or crash if People isn't ready. Effort S. Impact Med.
**Deps:** WorkspaceRouter (exists).

## Top 3 picks
1. **TT-1 — Persisted Today Snapshot (cache-first instant home).** Phase 1 (foundational
   perf/infra). The single highest-value change: turns Today from "empty then pops in" into
   an instant full home, and underpins TT-3/TT-6/TT-7.
2. **TT-2 — Defer heavy backfills off the first frame.** Phase 1. Cheap, removes the
   launch CPU contention that makes the first screen feel slow.
3. **TT-4 — Snapshot per-section lists into `@State`.** Phase 2. Kills per-render
   recompute for runtime smoothness as data grows.
   (TT-3 status strip → Phase 3; TT-5 consolidation + TT-6 Notes + TT-7 skeletons →
   Phase 3–4 higher-level UX; TT-8 routing → Phase 2 with the integration work.)
