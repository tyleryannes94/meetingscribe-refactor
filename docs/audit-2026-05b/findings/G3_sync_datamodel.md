# G3 Staff Engineer — Cross-Tab Data Model & Shared Context

**Lens:** Do the 5 tabs (`today, meetings, people, actions, notes`) share one selection/context model and cheap reverse indexes, so navigating from any entity to its related entities (person→meetings/tasks/decisions) is fluid and instant — or are they islands stitched by string-matching and O(n) scans?

---

## Audit (through my lens)

### What's already connected (verify-don't-repropose)
- **One canonical nav router exists.** `WorkspaceRouter` (`UI/WorkspaceRouter.swift:13`) is the single source of truth for the active `section` and `selectedMeetingID`. `openMeeting` (`:43`), `openPerson` (`:50`), and `open(entity:)`/`route(kind:id:)` (`:60`/`:64`) collapse the old four-way meeting-open into one surface. Good foundation — D1-1 shipped.
- **Deep-link scheme is modeled.** `WorkspaceLink` / `WorkspaceEntity` (`Models/WorkspaceLinks.swift:46-98`) define the `meetingscribe://<kind>/<id>` grammar and 8 entity kinds incl. `.person`, `.tag`, `.actionItem`.
- **ID-based links on tasks.** `ActionItem` carries `meetingID` (`ActionItem.swift:16`), `ownerPersonID` (`:28`), `projectID` (`:37`) — real foreign keys, bidirectional-capable.
- **Shared singleton stores with `@Published`.** `PeopleStore.shared`, `ActionItemStore`, `TagStore` are `ObservableObject`s; an edit in one tab does propagate reactively to any view observing the same store. Cross-tab *data* sync (tag a person → People list updates) works via shared state.
- **FTS engine is live.** `SecondBrainDB` ships `vault_content` + `vault_fts` (`People/SecondBrainDB.swift:179-218`) with auto-sync triggers, BM25+recency ranking (`:341`), and a semantic `relatedMeetings(toID:)` (`:427`). This is the right substrate for cache-backed indexes.

### Where the tabs are still islands

1. **No shared *selection context* — only a meeting ID.** `WorkspaceRouter` holds `selectedMeetingID` (`:27`) and nothing else. There is no `selectedPersonID`, no `activeContext`. Selecting a person does **not** carry to Meetings/Tasks/Decisions; person opening is fire-and-forget via `NotificationCenter.post(.meetingScribeOpenPerson)` (`WorkspaceRouter.swift:52`), consumed by `PeopleListView.onReceive` (`PeopleListView.swift:93`). The router can't observe or react to the current person, so "show this person's tasks/meetings/decisions in the other tabs" is impossible today. `selectedPerson` exists only privately inside `PeopleGraphViewModel.swift:115` — not shared.

2. **Person↔meeting is string-matching, not an ID edge.** `Meeting.attendees: [String]` (`Models/Meeting.swift:9`) are plain display strings — no `personID`. `attendeeMatches` (`PersonDetailView.swift:799-806`) does `m.attendees.contains { a.contains(email) || a.contains(personName) }`. This is fragile (name collisions, "Horst Carreño-Bauer" diacritic issues the search code already fought, `WorkspaceIndex.swift:200-231`) **and** runs as `manager.pastMeetings.filter(attendeeMatches)` on **every** PersonDetail render (`PersonDetailView.swift:822`) and again on calendar load (`:814`). O(meetings × attendees) per open.

3. **No reverse indexes — everything is an O(n) filter or disk scan.**
   - `ActionItemStore.items(forPerson:)` (`ActionItemStore.swift:513`), `items(for:meetingID)` (`:72`), `items(forProject:)` (`:78`), `openCount(forProject:)` (`:94`) all `items.filter { … }` — linear every call, every render.
   - `MeetingManager.backlinks(toMeetingID:)` (`WorkspaceIndex.swift:61-94`) reads **two files (`notes.md`+`summary.md`) off disk for every other past meeting** and `.contains(target)` scans them. O(n) disk I/O per meeting open (it's correctly off-main and "loaded last," `UnifiedMeetingDetail.swift:214`, but still scales linearly with library size).
   - `WorkspaceIndex.search` (`:106`) and `workspaceEntities()` (`:11`) rebuild the full entity list / scan all people+meetings+items in-memory on each call.

4. **Decisions have no person edge at all.** `Decision` carries only `meetingID`/`meetingTitle` (`Decisions/DecisionStore.swift:8-9`) — no `personID`, no owner. The Decisions/Commitments ledger therefore cannot surface on a Person ("what did X commit to") nor on a Task. A grep for `person` in `Decisions/` returns nothing.

5. **Two disjoint tag namespaces.** Meeting tags live in `TagStore`; people tags in `PeopleTagStore.shared` (`WorkspaceIndex.swift:305`). The same tag name is two unrelated objects, so `#sprint` can't unify a meeting and a person under one tag context (`tagSearch` has to query both stores separately, `:294`/`:309`).

**Net:** data *sync* (shared `@Published` stores) is decent; *contextual navigation* is the gap. Selecting a person is a dead-end w.r.t. the other four tabs, and the joins that would make it fluid are O(n) scans + string matching with no persisted index.

---

## NET-NEW recommendations

### SD-1 — Add `selectedPersonID` (+ generic `focus`) to `WorkspaceRouter`; make context carry across tabs
**What/why:** Promote selection from "meeting only" to a small shared context: `@Published var selectedPersonID`, plus an optional `focus: WorkspaceEntity?` the other tabs can read. `openPerson` sets it before flipping section. Meetings/Tasks/Decisions views observe it and offer a "Filtered to {Person}" scope chip.
**UX impact:** Click a person → jump to Tasks already scoped to their items (before: open Tasks, type their name in a filter = 3+ clicks → after: 1 click, or 0 if a "Their tasks" affordance is on the Person page). Person→Meetings, Person→Decisions same.
**Perf/stability:** Two published scalars; negligible memory. No new scans if backed by SD-2/3 indexes. Reactive, no polling.
**Effort:** S · **Impact:** High · **Deps:** SD-2/SD-3 for the cheap reads.

### SD-2 — Stable `personID` on meeting attendees + a persisted attendee resolver
**What/why:** Replace `attendees: [String]` matching with resolved IDs. Add `attendeePersonIDs: [String]` to `Meeting` (keep the string array for display/back-compat) and resolve once at finalize/import via a normalized email/name key, persisting the map. Kills the string-substring matching that already caused the diacritic bugs documented in `WorkspaceIndex.swift:200`.
**UX impact:** Person↔meeting links become exact and bidirectional — no more wrong/missing matches; "In your recordings" rows are trustworthy.
**Perf/stability:** Resolution moves from per-render to once-at-write (cache-backed). Eliminates the O(meetings×attendees) scan in `PersonDetailView.swift:822`. Lower crash surface (no Unicode edge cases at read time).
**Effort:** M · **Impact:** High · **Deps:** SD-3 (the index that stores the edges).

### SD-3 — Cache-backed reverse-index actor: `EntityGraphIndex` (person→meetings/tasks/decisions, meeting→tasks/backlinks)
**What/why:** A single in-memory index built once at launch and incrementally maintained on store mutations, backed/persisted in the existing SQLite (`SecondBrainDB`). Dictionaries: `personMeetings[id]`, `personTasks[id]`, `personDecisions[id]`, `meetingTasks[id]`, `meetingBacklinks[id]`. Replace every `items.filter`/`pastMeetings.filter`/disk-scan with an O(1) dictionary lookup. Persist edges in a `links(src,dst,kind)` table so first-open is a cheap query, not a rebuild.
**UX impact:** Instant related-entity panels on every tab; enables SD-1's contextual scoping to feel immediate.
**Perf/stability:** Converts O(n) (and O(n) *disk reads* for backlinks, `WorkspaceIndex.swift:74-85`) into O(1) reads. Incremental updates are O(1) per mutation. Persisted edges = fast first open (no full re-scan); falls back to a background rebuild if the cache is missing/stale. Lower memory churn than rebuilding entity arrays each search.
**Effort:** L · **Impact:** High · **Deps:** SD-2 (IDs), SD-5 (decision edges) to populate person→decisions.

### SD-4 — Replace the file-scanning `backlinks(toMeetingID:)` with persisted link rows
**What/why:** When notes/summary are written, parse out `meetingscribe://` targets once and write `links` rows (SD-3 table). `backlinks` becomes a single indexed query instead of reading 2 files per meeting.
**UX impact:** Backlinks panel (`MeetingNotesTab.swift:126`) appears instantly on meeting open instead of after a utility-priority disk crawl.
**Perf/stability:** Removes N file opens per meeting view — big win on slow/scanned disks (the code itself warns about scanner-intercepted opens, `ActionItemStore.swift:36`). Write-time cost is trivial (one parse already happening for rendering).
**Effort:** M · **Impact:** Med · **Deps:** SD-3.

### SD-5 — Give `Decision` a person edge (`commitOwnerPersonID` / `relatedPersonIDs`)
**What/why:** Add owner/related-person IDs to `Decision` (`DecisionStore.swift:7`), populated from the same attendee resolver (SD-2) and the commitment parser. Index into SD-3's `personDecisions`.
**UX impact:** Person page gains a "Decisions & commitments" section ("X committed to ship by Fri"); Tasks can show the decision that spawned them. Closes the loop the V4 ledger started.
**Perf/stability:** Pure additive fields; cheap. Indexed lookup via SD-3, no scans.
**Effort:** M · **Impact:** Med · **Deps:** SD-2, SD-3.

### SD-6 — Unify the two tag namespaces behind one `TagRegistry`
**What/why:** `TagStore` (meetings) and `PeopleTagStore` (people) are disjoint (`WorkspaceIndex.swift:294` vs `:309`). Introduce a shared tag identity (canonical name → one `Tag`), letting both stores reference it. `#sprint` then resolves to one context spanning meetings + people + (via SD-3) tasks.
**UX impact:** Clicking a tag anywhere shows one unified filtered context across tabs; tagging is consistent. `tagSearch` collapses to one lookup.
**Perf/stability:** One canonical table; dedupes storage. Reverse `tag→entities` index lives in SD-3. Migration is one-time; guard with the existing schema-version path (`MeetingStore.indexSchemaVersion`, `MeetingStore.swift:33`).
**Effort:** M · **Impact:** Med · **Deps:** SD-3.

### SD-7 — Context-aware deep links + a "Related" rail driven by the index
**What/why:** Extend `route(kind:id:)` so a person/tag link can pass an optional scope that the destination tab applies (e.g. `meetingscribe://person/<id>?show=tasks`). Add a small shared "Related" panel component, fed by SD-3, reused on Meeting/Person/Task detail.
**UX impact:** Every entity detail shows its neighbors and is one click from each — the "one connected workspace" feel. Deep links from MCP/Shortcuts can land you in a *scoped* view.
**Perf/stability:** Reuses SD-3 (O(1) reads), one shared SwiftUI component → fewer divergent code paths, lower regression risk.
**Effort:** M · **Impact:** High · **Deps:** SD-1, SD-3.

### SD-8 — Index lifecycle + integrity guard (build/verify/rebuild)
**What/why:** SD-3's persisted edges need a `quick_check`-style validity gate and a background rebuild path so a stale/corrupt index degrades gracefully to a one-time scan instead of showing wrong links. Tie into the existing `MeetingStore` cache-invalidation hooks (`MeetingStore.swift:81-84`).
**UX impact:** Links are never silently wrong; no crash on a torn cache.
**Perf/stability:** First open uses the persisted index (fast); on mismatch it rebuilds off-main with a skeleton state. Directly serves the audit's cold-start + crash-resistance constraint.
**Effort:** S · **Impact:** Med · **Deps:** SD-3.

---

## Top 3 picks

1. **SD-3 — Cache-backed `EntityGraphIndex` reverse-index actor.** *Phase 1* (foundational/perf+infra). The keystone: turns every cross-tab join from O(n) (and O(n) disk reads) into O(1), persisted for fast first-open. Everything else's fluidity depends on it.
2. **SD-1 — Shared `selectedPersonID`/`focus` in `WorkspaceRouter`.** *Phase 2.* The smallest change that makes selecting a person actually *carry* to Meetings/Tasks/Decisions — the core "one workspace" win. Cheap once SD-3 backs the reads.
3. **SD-2 — Stable `personID` on attendees + resolver.** *Phase 1/2.* Replaces brittle string-matching with exact, cached ID edges; prerequisite for trustworthy person→meeting context and for SD-3's edges.

**Single highest-value:** SD-3 — the reverse-index actor is the infrastructure that makes contextual cross-tab navigation both possible *and* cheap.

**Perf/caching insight:** The app already has the right substrate (SQLite + `vault_fts` triggers in `SecondBrainDB`). The fix is to stop recomputing relationships at render time (per-render `pastMeetings.filter` + 2-file-per-meeting backlink scans) and instead **persist the edges once at write-time** into an incrementally-maintained index, so first-open and every related-entity panel are O(1) reads, not O(n) scans.
