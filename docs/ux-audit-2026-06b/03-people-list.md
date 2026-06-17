# Audit — People List + Navigation

*Agent: people-list. `PeopleListView.swift`. Make the master list triage-able and task-aware.*

## Current problems
- Flat undifferentiated scroll (`List`, 319-326); with 500+ contacts no anchors — "who needs attention" invisible. Reconnect intelligence exists but is buried in the no-selection dashboard (`PeopleInsightsView.swift:84-101`).
- `PersonRow` (615-648) under-signals: avatar+name+type chip+role/company+relative last-contact; **no** overdue state, **no** task counts — though `overdueCheckInCount`(`PeopleStore.swift:1367`), `effectiveCheckInDays`, `items(forPerson:)` all exist. The 2pt health ring is the only attention cue.
- Sort exists (`PeopleSort`, behind `arrow.up.arrow.down`, 216-228) but **no grouping** — a sorted list still buries the 6 you're behind on among 500.
- Tasks↔People never meet in the list: hard link `ActionItem.ownerPersonID` only consumed in `PersonDetailView`.

## Proposed layout
Keep `HSplitView`; widen sidebar `260/320/380 → 280/340/420` (113). Add: a **triage segmented control** (All / ⚠ Needs attention / ☑ Has tasks) between search and chips (285-293); a **density toggle** (`@AppStorage("people.rowDensity")`) by the sort menu; **section grouping** (Overdue / This week / Everyone else) when not searching + no type filter.

### Grouping (replaces flat ForEach 311/319-324)
- **Overdue** = `relationshipType != .unset` && `daysSince(lastInteractionAt ?? createdAt) > effectiveCheckInDays` (extract `overdueCheckInCount`'s predicate into reusable `isOverdueForCheckIn(_:)`).
- **This week** = typed, last contact ≤7d OR birthday/special date ≤7d.
- **Everyone else** = remainder, in sort order. Collapsible `Section`s with counts (`OVERDUE · 4`).

### Richer PersonRow (615-648)
Add `@EnvironmentObject actionItems`; show an **overdue pill** (`NDS.danger` "Nd overdue") replacing the plain date when overdue, and a **task chip** `☑ open` (reddened if overdue>0), hidden when open=0. **Perf:** precompute `[personID:(open,overdue)]` once in the view (`onChange(of: actionItems.items)`), pass tuple into the row (mirror `encounterCountIndex` memoization) — `items(forPerson:)` is O(n), don't call per-row.

## Tasks + Meetings links
- Task chip tappable → select person + deep-link to their tasks (longer-term: Tasks tab pre-filtered via `TaskQuery.Filter.person` which exists at `TaskQuery.swift:140`).
- "Has open tasks" triage filters `taskIndex[id].open > 0`.
- Optional muted `📅 N` (meeting count = `encounterCount+meetingMentions`) in comfortable density.
- Overdue rows get a swipe/context "Mark reached out" (`bumpLastInteraction`) so triage never needs opening the profile.

## Build plan (each green; reuses existing primitives)
1. Extract `isOverdueForCheckIn(_:)` in `PeopleStore` (refactor `overdueCheckInCount`/`Names`). No UI.
2. Add `actionItems` env + `taskCounts` index in `PeopleListView` (compute in `.task`/`onChange`). No render yet. (Confirm `ActionItemStore` injected into People tab env.)
3. Richer `PersonRow`: overdue pill + task chip; pass `overdue`+`counts` from both ForEach sites.
4. Sectioned list (Overdue/This week/Everyone else) gated on no-search & no-type-filter; collapsible headers w/ counts.
5. Triage segmented control (All/Needs attention/Has tasks) applied in `filtered`.
6. Density toggle (comfortable/compact) threaded into `PersonRow`.
7. Widen sidebar frame; "Mark reached out" in `personRowMenu` when overdue.
8. Type-chip counts + task-chip → Tasks deep-link (`TaskQuery.Filter.person`).

Steps 1-2 zero-risk plumbing; 3-5 core value; 6-8 independent polish.
