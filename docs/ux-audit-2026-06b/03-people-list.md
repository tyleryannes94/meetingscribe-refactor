# Audit — People List + Navigation (Exhaustive Redesign Spec)

*Agent: people-list. Primary surface: `Sources/MeetingScribe/People/PeopleListView.swift`.*
*Goal: turn the master list from a flat, undifferentiated scroll into a **triage-able, task-aware** surface — without regressing launch performance, search, select-mode, board/graph modes, or the snapshot fast-path.*

This document is intentionally exhaustive. It catalogs the existing architecture line-by-line, enumerates the problems with evidence and severity, specifies the target layout and predicates precisely, defines the Tasks/Meetings linkage, and lays out a long sequence of small, individually-shippable build increments. Every increment is designed to compile green on its own (`swift build -c release`) and to reuse existing primitives (`overdueCheckInCount`'s predicate, `encounterCountIndex`'s memoization pattern, the `personSentinel` task deep-link path) rather than invent new machinery.

---

## 0. Scope, constraints, and non-goals

### 0.1 In scope
- The People-tab **sidebar** (`PeopleListView.sidebar`, `PeopleListView.swift:245-330`): search field, tag chips, relationship-type chips, the `List`, the ghost footer, and the bulk bar.
- The **`PersonRow`** (`PeopleListView.swift:614-653`) — the per-person row that under-signals today.
- The **no-selection dashboard** relationship between `PeopleInsightsView` (`PeopleInsightsView.swift`) and the list (the reconnect intelligence is *only* in the dashboard today; we want a copy of it on the rows).
- A new **triage segmented control** and **section grouping** in the sidebar.
- A new **density toggle**.
- **Tasks↔People** linkage in the row (task chip, deep-link, "Has tasks" filter, "Mark reached out" action).

### 0.2 Out of scope (do NOT touch)
- `boardMode` (`KeepInTouchBoard`, `PeopleListView.swift:90-105`) and `graphMode` (`PeopleGraphView`, `:106-110`) — they replace the list/detail wholesale and are governed by other agents.
- `PersonDetailView.swift` — the detail pane is the `02-person-detail` agent's surface. We only *deep-link into* tasks from the list; we do not edit the detail.
- The Tasks tab internals (`ActionItemsView.swift`, `TasksEnvironment.swift`) — we *consume* their existing person-scope deep-link API, we do not modify it.
- `Sources/**` are not modified by this agent at spec-writing time; this file is the plan only.

### 0.3 Hard constraints
1. **Launch perf**: the synchronous `snapshotRows` fast-path (`PeopleListView.swift:40-41`, fed by `PeopleStore.loadListSnapshot()` / `ListSnapshot`) must keep rendering frame-0 before the store hydrates. New per-row computation must NOT block the main thread per keystroke or per render.
2. **No O(n²)**: `ActionItemStore.items(forPerson:)` (`ActionItemStore.swift:1259-1261`) is an O(n) filter over the whole task array. Calling it inside a `ForEach` row body would be O(people × tasks) per render. We MUST memoize a `[personID:(open,overdue)]` index (mirror of `encounterCountIndex`, `PeopleStore.swift:47/52-56`) and pass a precomputed tuple into the row.
3. **Search invariant**: while `debouncedQuery` is non-empty, results come back **relevance-ranked** from FTS5 (`PeopleStore.filteredPeople`, `:1526-1548`) and MUST stay in that order. **No grouping, no sort** during search (mirrors `filtered`'s `guard debouncedQuery.isEmpty else { return typeFiltered }`, `:61`).
4. **Two-way router sync**: `selection` ↔ `router.selectedPersonID` (`:150-164`) must keep working; deep-links and back/forward history depend on it.

---

## 1. Current architecture catalog

### 1.1 `PeopleListView` — `@State` / `@AppStorage` / `@StateObject` inventory

| Symbol | Line | Type | Role |
|---|---|---|---|
| `people` | `:8` | `@EnvironmentObject PeopleStore` | canonical people/encounters graph |
| `peopleTags` | `:9` | `@EnvironmentObject PeopleTagStore` | tag names for chips |
| `manager` | `:10` | `@EnvironmentObject MeetingManager` | calendar-attendee import source |
| `router` | `:11` | `@EnvironmentObject WorkspaceRouter` | deep-link + selection sync + history |
| `importer` | `:12` | `@StateObject PeopleImportController` | import progress/status |
| `query` | `:14` | `@State String` | live search text |
| `debouncedQuery` | `:17` | `@State String` | 180ms-debounced mirror; the filter pipeline reads this |
| `tagFilters` | `:19` | `@State Set<String>` | AND-tag filter |
| `showTagManager` | `:20` | `@State Bool` | sheet toggle |
| `selection` | `:21` | `@State String?` | the selected person id |
| `showAdd` | `:22` | `@State Bool` | add-person sheet |
| `showImportFromContacts` | `:23` | `@State Bool` | contacts-search sheet |
| `showGhosts` | `:24` | `@State Bool` | reveal low-signal contacts |
| `showDuplicates` | `:25` | `@State Bool` | duplicate-review sheet |
| `dedupResult` | `:26` | `@State String?` | post-merge alert message |
| `graphMode` | `:28` | `@State Bool` | force-directed mindmap mode |
| `boardMode` | `:30` | `@State Bool` | keep-in-touch health-band board |
| `selectMode` | `:33` | `@State Bool` | multi-select toggle |
| `multiSelection` | `:34` | `@State Set<String>` | checked ids for bulk actions |
| `bulkConfirmDelete` | `:35` | `@State Bool` | confirm dialog |
| `bulkConfirmMerge` | `:36` | `@State Bool` | confirm dialog |
| `snapshotRows` | `:40-41` | `@State [ListSnapshot.Row]` | frame-0 launch snapshot, loaded synchronously |
| `sortRaw` | `:43` | `@AppStorage("people.sortOrder")` | persisted sort, default `.recent` |
| `relationshipTypeFilter` | `:47` | `@State RelationshipType?` | active type filter; nil = all |

### 1.2 View builders (the whole sidebar tree)

- **`body`** (`:88-165`): `Group` switching `boardMode` / `graphMode` / `HSplitView`. Sidebar frame is `minWidth: 260, idealWidth: 320, maxWidth: 380` (`:113`); detail `minWidth: 380` (`:114`). All the `.sheet`, `.alert`, `.onAppear`, `.onChange` modifiers hang off the `Group`. Notably `.task { people.rebuildIndexIfNeeded() }` (`:118`) builds the FTS5 index once on appear, and the debounce pipeline lives in `.onChange(of: query)` (`:119-126`).
- **`filtered`** (`:49-63`): the computed list. (1) `people.filteredPeople(query:tagID:includeGhosts:)` with `tagFilters.first`; (2) AND-tag refine when `tagFilters.count > 1`; (3) `relationshipTypeFilter` refine; (4) if querying, return as-is (relevance order); else `sorted(...)`.
- **`presentTypes`** (`:66-69`): which `RelationshipType`s are actually in use (drives type-chip visibility — only shown when `> 1`).
- **`sorted(_:)`** (`:71-82`): switches on `PeopleSort` — `.recent` (lastInteractionAt desc), `.name`, `.meetings` (via `meetingCount`), `.newest` (createdAt desc).
- **`meetingCount(_:)`** (`:84-86`): `people.encounterCount(for:) + p.meetingMentions.count`.
- **`applyTagFilter(_:)`** (`:168-178`): resolves a typed tag name → tag id, or falls back to setting `query`.
- **`importMenuItems`** (`:180-195`): the Import menu (Apple/Gmail/calendar/file + Find/Merge duplicates).
- **`actionsRow`** (`:199-241`): Add Person, Import menu, **Sort menu** (`arrow.up.arrow.down`, disabled while querying, `:216-228`), and the **Select** toggle (`:230-238`).
- **`sidebar`** (`:245-330`): title row (`:247-273`, with board/graph icon buttons), `actionsRow`, importer status, **`MSSearchField`** (`:285-286`), **`tagChips`** (`:288`), **`relationshipTypeChips`** when `presentTypes.count > 1` (`:291-293`), `Divider()`, then the branchy body:
  - empty + no snapshot → `emptyState` (`:299`)
  - empty + snapshot → non-hit-testable `List` of `SnapshotPersonRow` (`:303-307`)
  - `selectMode` → `List(selection: $multiSelection)` of `PersonRow().tag(id)` + `bulkBar` (`:310-317`)
  - else → `List(selection: $selection)` of `PersonRow().tag(id).contextMenu{...}` + `ghostFooter` (`:319-328`)
- **`personRowMenu(_:)`** (`:333-350`): right-click — Open, Add tag (submenu of unused tags), Delete (with undo).
- **`deleteWithUndo(_:)`** (`:353-361`): snapshots person + encounters, deletes, shows undo toast.
- **`bulkBar`** (`:367-422`): "N selected", Tag menu, Merge (≥2), Delete; plus the two confirmation dialogs.
- **`ghostFooter`** (`:469-488`): only when `debouncedQuery.isEmpty && tagFilters.isEmpty && people.ghostCount > 0`; toggles `showGhosts`.
- **`tagChips`** (`:491-518`): "All" + a chip per *used* tag (AND semantics) + a Manage-tags button.
- **`relationshipTypeChips`** (`:522-540`): "All" + a chip per present type.
- **`emptyState`** (`:542-546`): `MSEmptyState`.
- **`detail`** (`:551-561`): selected → `PersonDetailView`; else `PeopleInsightsView(onOpen:)`.

### 1.3 `PersonRow` contents (`:614-653`)

```
HStack(spacing: 10) {
  MSAvatar(name:, size: 28, ringColor: healthRingColor(for:in:))   // :625-626
  VStack(alignment: .leading, spacing: 2) {
    HStack(spacing: 4) {
      Text(displayName).scaledFont(13.5, .semibold).lineLimit(1)    // :629
      if relationshipType != .unset { RelationshipTypeChip(type:, showLabel: false) }  // :631-633
    }
    if !subtitle.isEmpty { Text(subtitle).font(NDS.tiny).foregroundStyle(textTertiary).lineLimit(1) }  // role · company, :635-637
  }
  Spacer(minLength: 0)
  if let last = lastInteractionAt {
    Text(relative.localizedString(for: last, relativeTo: Date())).font(NDS.tiny).foregroundStyle(textTertiary)  // :642-645
  }
}
.padding(.vertical, 3)   // :647
```

The **only** attention signal a row carries today is the avatar's **health ring** (`healthRingColor`, `MSAvatar.swift:10-30`), a ~2pt ring whose color is `mint/sky/gold/danger` for `thriving/steady/drifting/overdue`. There is **no overdue text**, **no task count**, **no meeting count**. `subtitle` is `[role, company]` joined with `·` (`:619-621`). The relative-date formatter is a static `RelativeDateTimeFormatter` (`unitsStyle: .abbreviated`, `:650-652`). `SnapshotPersonRow` (`:589-612`) is the parallel snapshot variant — same geometry, driven by `ListSnapshot.Row` (`name/subtitle/lastEpoch`), with a generic `person.circle.fill` glyph rather than `MSAvatar` and **no** ring/type/task signals.

### 1.4 Sort + filter machinery
- **Sort** is `PeopleSort` (`:565-584`): `recent | name | meetings | newest`, persisted via `@AppStorage("people.sortOrder")` (`:43`), applied in `sorted(_:)` only when not querying, surfaced behind the `arrow.up.arrow.down` menu (`:216-228`, **disabled while querying** because relevance order wins).
- **Filter** is three stacked layers in `filtered` (`:49-63`): tag (store-level single tag + view-level AND-refine), relationship type, and the search/sort fork.
- **Store-side filtering** (`PeopleStore.filteredPeople`, `:1526-1548`): with a query → FTS5 `db.searchPersonIDs(q)` mapped through an id→Person dict, falling back to in-memory `matches(...)` if the index is cold; with no query → sorted by `relevanceScore(encounterCount:)` then `recencyThenName`. Tag filter applied after. Ghosts hidden only on the fully-unfiltered list (`includeGhosts == false && q.isEmpty && tagID == nil`, `:1544-1546`).

### 1.5 What `PeopleStore` already computes (reusable)
- **`encounterCount(for:)`** (`:145`) — O(1) via `encounterCountIndex` (`:47`), rebuilt in `rebuildEncounterCounts()` (`:52-56`) on every `encounters` `didSet` (`:39-41`). **This is the memoization pattern we mirror for task counts.**
- **`overdueCheckInCount`** (`:1367-1375`): `people.reduce` where `relationshipType != .unset` and `daysSince(lastInteractionAt ?? createdAt) > effectiveCheckInDays`. **This is the predicate we extract into `isOverdueForCheckIn(_:)`.**
- **`overdueCheckInNames(limit:)`** (`:1379-1390`): same predicate, returns most-overdue names; used by the weekly digest. Will reuse the extracted predicate.
- **`effectiveCheckInDays`** (`Person.swift:302-304`): `checkInCadenceDays ?? relationshipType.defaultCheckInDays` (`RelationshipType.defaultCheckInDays`, `Person.swift:98-108`: partner 1, family 7, closeFriend 14, friend 21, colleague 30, acquaintance 60, unset 14).
- **`ghostCount`** (`:1551-1553`), **`usedTagIDs()`** (`:1557-1559`), **`bumpLastInteraction(personID:date:)`** (`:671-678`, moves `lastInteractionAt` forward only, re-sorts), **`encounters(for:)`** (`:689-691`), **`person(by:)`** (`:550-552`, O(1) via `personIndex`).

### 1.6 What `PeopleInsightsView` already computes (the buried intelligence)
- **`goneCold`** (`:84-101`): people with `lastInteractionAt` older than `min(relationshipType.reconnectThresholdDays, checkInCadenceDays ?? .max)`, sorted oldest-first, top 8. Note: this uses **`reconnectThresholdDays`** (`Person.swift:114-124`, looser: partner 7 / family 14 / closeFriend 21 / friend 30 / colleague 45 / acquaintance 90), **not** `effectiveCheckInDays`. (See §3.4 — the row "overdue" predicate uses `effectiveCheckInDays` to match `overdueCheckInCount`; this is a deliberate distinction worth preserving.)
- **`comingUp`** (`:106-139`): birthdays + special dates within 30 days, next-occurrence resolved (`nextOccurrence`, `:150-161`), top 8.
- **`mostActive`** (`:141-147`): `encounterCount + meetingMentions.count`, descending, top 8.
- **`card`/`row`** building blocks (`:166-197`); the Reconnect card has an inline **"Mark reached out"** button (`:37-43`) that calls `bumpLastInteraction(personID:date: Date())` — the exact action we want as a row swipe/context action.

This dashboard is **only visible when nothing is selected** (`detail`, `:557-558`). The moment a person is selected it disappears — so the reconnect signal is invisible during the most common workflow (browsing/triaging the list with someone open).

---

## 2. Problem inventory

> Severity: **P1** = breaks the core "who needs me?" job; **P2** = real friction; **P3** = polish.

**P-1 — Flat, undifferentiated scroll. (P1)**
Evidence: the live list is a single `ForEach(filtered)` (`:319-324`) with no section anchors. With 500+ contacts (the explicit design target, per the graph-mode demotion comment `:251-253`) the 4–6 people you're actually behind on are visually identical to and buried among hundreds of dormant imports. The reconnect intelligence that *could* float them exists (`goneCold`, `overdueCheckInCount`) but never reaches the list.

**P-2 — `PersonRow` under-signals. (P1)**
Evidence: `PersonRow` (`:614-653`) shows avatar + name + type chip + role/company + a relative last-contact string. There is **no overdue state** (the row for someone 40 days past their 7-day cadence looks the same as someone contacted yesterday, save a 2pt ring), and **no task counts** — even though `ActionItem.ownerPersonID` hard-links tasks to people and `items(forPerson:)` (`ActionItemStore.swift:1259`) exists. "This person owes me 3 follow-ups, 1 overdue" is invisible in the list.

**P-3 — Reconnect intelligence buried in the no-selection dashboard. (P1)**
Evidence: `goneCold`/`comingUp`/`mostActive` live in `PeopleInsightsView` (`:84-147`), shown only when `selection == nil` (`:557-558`). During normal triage (someone is selected) the user sees zero reconnect signal. The "Mark reached out" affordance (`:37-43`) is likewise only reachable from the empty-detail dashboard.

**P-4 — No grouping. (P1)**
Evidence: `sorted(_:)` (`:71-82`) can reorder but cannot *bucket*. Even sorted by recency, the overdue 6 are interleaved with 494 others — there is no "Overdue (4)" anchor a user can jump to. Sort ≠ triage.

**P-5 — Tasks↔People never meet in the list. (P2 → P1 for task-driven users)**
Evidence: the hard link `ActionItem.ownerPersonID` is consumed only inside `PersonDetailView` (`actionItems` env at `:230`, used `:404`). The list has no `ActionItemStore` in its environment at all and no task signal. There is no "show me people who owe me open tasks" entry point, despite `TaskQuery.Scope.person` (`TaskQuery.swift:27`, `:140`) and a complete person-scope deep-link path already existing in the Tasks tab (see §4.1).

**P-6 — Static geometry / density. (P3)**
Evidence: the sidebar is fixed `260/320/380` (`:113`); the row is a fixed `.padding(.vertical, 3)` with a 28pt avatar (`:625/647`). At 500+ contacts a denser mode would show far more per screen; at 30 contacts a comfortable mode with meeting counts reads better. There is no density control. (The sort menu `:216-228` is the natural neighbor for one.)

**P-7 — Snapshot/live divergence risk. (P3, watch-item)**
Evidence: `SnapshotPersonRow` (`:589-612`) and `PersonRow` (`:614-653`) are independent. Any signal we add to the live row will momentarily *not* appear on the snapshot rows at cold launch. This is acceptable (the snapshot is a sub-second placeholder and is `allowsHitTesting(false)`, `:307`) but the spec must say so explicitly so a reviewer doesn't file it as a bug. We will NOT add task/overdue signals to the snapshot row (the snapshot digest has no task data and we won't bloat it).

**P-8 — The sort axis and the triage axis are conflated. (P2)**
Evidence: there is exactly one ordering lever (`PeopleSort`, `:565-584`) and it is hidden behind an icon menu (`:216-228`) and *disabled while searching* (`:227`). A user who wants "who's overdue" has no lever for it — they must mentally scan the (possibly recency-sorted) list and read each 2pt ring. Sort answers "in what order" but the user's real question is "which subset" — a filter/grouping question the current UI cannot express. The redesign separates the two: triage (subset/grouping) on the visible segmented control + section headers; sort (within-section ordering) stays on the menu.

**P-9 — No bridge from "I'm looking at this person" to "what do they owe me". (P2)**
Evidence: from the list you can open a profile (`selection`), but to see their tasks you must open the profile and scroll to its action-items section (`PersonDetailView` task section around `:404`). There is no one-tap path from the list to the Tasks tab scoped to that person — even though that scoped view already exists (`personSentinel`, §4.1). The task chip closes this gap (§4.2).

**User-impact summary.** The cluster P-1/P-3/P-4/P-8 is the same wound from four angles: *the list cannot answer "who needs me right now"*. P-2/P-5/P-9 are the second wound: *the list is blind to the task graph*. The redesign treats both: grouping + triage + the overdue pill resolve the first; the task index + chip + deep-link + "Has tasks" filter resolve the second. P-6/P-7 are secondary polish.

---

## 3. Proposed layout

### 3.1 Overview

```
┌─ People sidebar (widened) ───────────────┐
│ People               [board][graph]      │  title row (:247-273) — unchanged
│ [Add Person][Import ▾]  [↕ sort][≡ density][Select]  ← density added next to sort
│ status (importer)                        │
│ [🔍 Search name, company, role…]          │
│ ┌ All │ ⚠ Needs attention │ ☑ Has tasks ┐ │  ← NEW triage segmented control
│ tag chips ───────────────────────────────│
│ relationship-type chips (if >1) ──────────│
│ ──────────────────────────────────────── │
│ ▾ OVERDUE · 4                             │  ← NEW collapsible sections
│    • Alex Rivera   [3d overdue][☑ 2·1]   │  ← richer PersonRow
│    • …                                    │
│ ▾ THIS WEEK · 6                           │
│ ▾ EVERYONE ELSE · 488                     │
│ Show 312 more contacts (ghosts)           │  ghostFooter (:469-488)
└───────────────────────────────────────────┘
```

The segmented control and grouping appear **only** in the default browse state (no query). During search, the list reverts to a single flat relevance-ordered `ForEach` (see §6.1).

### 3.2 Widened sidebar
Change the frame at `:113` from `minWidth: 260, idealWidth: 320, maxWidth: 380` to **`minWidth: 280, idealWidth: 340, maxWidth: 420`**. Rationale: the richer row needs room for an overdue pill + task chip on the trailing edge without truncating the name/subtitle. Keep `detail.frame(minWidth: 380)` (`:114`) so the split still collapses sanely on small windows.

### 3.3 Triage segmented control
A `Picker(.segmented)` placed **between the search field (`:285-286`) and `tagChips` (`:288`)**, bound to a new `@State private var triage: TriageFilter = .all`. Hidden while `!debouncedQuery.isEmpty` (search owns ordering and population).

```swift
enum TriageFilter: String, CaseIterable, Identifiable {
    case all, needsAttention, hasTasks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:            return "All"
        case .needsAttention: return "Needs attention"
        case .hasTasks:       return "Has tasks"
        }
    }
    var icon: String {
        switch self {
        case .all:            return "person.2"
        case .needsAttention: return "exclamationmark.circle"
        case .hasTasks:       return "checklist"
        }
    }
}
```

Predicates (applied in `filtered` *after* tag/type filters, *before* grouping, only when not querying):
- **`.all`**: no extra predicate.
- **`.needsAttention`**: `people.isOverdueForCheckIn(person)` (see §3.4) **OR** the person has ≥1 overdue task (`taskCounts[id]?.overdue ?? 0 > 0`). Union of relationship-overdue and task-overdue is the honest definition of "needs attention".
- **`.hasTasks`**: `(taskCounts[id]?.open ?? 0) > 0`.

### 3.4 The reusable overdue predicate (extract from `overdueCheckInCount`)
Add to `PeopleStore` (refactor `overdueCheckInCount` `:1367-1375` and `overdueCheckInNames` `:1379-1390` to call it):

```swift
/// True when a *typed* person is past their check-in cadence. Untyped one-off
/// imports never count (mirrors overdueCheckInCount's guard). Single source of
/// truth for the nav badge, the "Needs attention" triage, and the OVERDUE section.
func isOverdueForCheckIn(_ p: Person, now: Date = Date()) -> Bool {
    guard p.relationshipType != .unset else { return false }
    let last = p.lastInteractionAt ?? p.createdAt
    let daysSince = Int(now.timeIntervalSince(last) / 86400)
    return daysSince > p.effectiveCheckInDays
}

/// Days a typed person is overdue (0 if not overdue) — for the row's pill text.
func overdueDays(_ p: Person, now: Date = Date()) -> Int {
    guard p.relationshipType != .unset else { return 0 }
    let last = p.lastInteractionAt ?? p.createdAt
    let daysSince = Int(now.timeIntervalSince(last) / 86400)
    return max(0, daysSince - p.effectiveCheckInDays)
}
```

Then `overdueCheckInCount` becomes `people.reduce(0) { isOverdueForCheckIn($1) ? $0 + 1 : $0 }`, and `overdueCheckInNames` filters on `isOverdueForCheckIn` and sorts by `overdueDays` desc. **Net behavior unchanged** — pure refactor, so the nav-rail badge (which consumes `overdueCheckInCount`) is unaffected.

> Note the intentional split: the **OVERDUE section** and **Needs-attention** triage use `effectiveCheckInDays` (tighter, matches the badge). The dashboard's `goneCold` keeps using `reconnectThresholdDays` (looser). We do not unify them — they answer different questions ("past cadence" vs. "drifting").

### 3.5 Section grouping (replaces the flat `ForEach`)
When not querying, partition `filtered` into three ordered buckets, each a collapsible `Section` with a count header (`OVERDUE · 4`). Predicates evaluated top-down (first match wins, so a person appears in exactly one section):

- **Overdue** = `people.isOverdueForCheckIn(person)`. (Typed people past cadence.)
- **This week** = NOT overdue, AND (`person.lastInteractionAt` within the last 7 days) OR (a birthday/special date within the next 7 days). The birthday test reuses the next-occurrence logic; to avoid duplicating `PeopleInsightsView.nextOccurrence` (`:150-161`), extract a small free helper `nextSpecialDateWithin(_ p: Person, days: Int) -> Bool` into a shared file (e.g. alongside `Person`), and have both `PeopleInsightsView.comingUp` and this section call it. (If extraction is deemed too invasive for one increment, ship "This week" as recency-only first, add the birthday clause in a follow-up increment.)
- **Everyone else** = the remainder, in the active `PeopleSort` order.

Within Overdue, sort by `overdueDays` descending (most-overdue first) — this is the natural triage order and matches `overdueCheckInNames`. Within the other two sections, keep the active `PeopleSort` order.

Section state: a `@State private var collapsed: Set<String>` keyed by a stable section id (`"overdue"`, `"thisWeek"`, `"everyone"`). Persist nothing (collapse is ephemeral). Default: all expanded. Empty sections render no header (skip when count == 0).

Implementation shape (inside the live-list branch, `:319-328`):
```swift
List(selection: $selection) {
    ForEach(sections) { section in   // [PeopleSection] computed below
        Section {
            if !collapsed.contains(section.id) {
                ForEach(section.people) { person in
                    PersonRow(person: person, counts: taskCounts[person.id] ?? .zero)
                        .tag(person.id)
                        .contextMenu { personRowMenu(person) }
                }
            }
        } header: { sectionHeader(section) }   // tappable, toggles collapsed
    }
}
```
where
```swift
private struct PeopleSection: Identifiable { let id: String; let title: String; let people: [Person] }
```
and `sections` is a computed property that runs the partition over `filtered`. Critically, the partition runs **once per `filtered` recompute**, not per row.

### 3.6 Richer `PersonRow`
Add a precomputed `counts` parameter (NOT a store lookup inside the row):

```swift
private struct PersonRow: View {
    let person: Person
    let counts: TaskCounts          // NEW — (open, overdue), precomputed
    @EnvironmentObject var people: PeopleStore
    ...
}
struct TaskCounts: Equatable { var open: Int; var overdue: Int; static let zero = TaskCounts(open: 0, overdue: 0) }
```

Trailing-edge stack (replaces the bare relative-date `Text` at `:642-645`):
1. **Overdue pill** — when `people.isOverdueForCheckIn(person)`: a small capsule `"\(people.overdueDays(person))d overdue"` in `NDS.danger` (`NotionDesign.swift:66`), `radiusSmall` (`:26`), `NDS.tiny`. This *replaces* the relative-date string for overdue rows (the date is implied by "Nd overdue"). For non-overdue rows, keep the existing relative-date `Text`.
2. **Task chip** — when `counts.open > 0`: a capsule `☑ \(counts.open)` (or `☑ \(counts.open)·\(counts.overdue)` when `counts.overdue > 0`), tinted `NDS.danger` if `counts.overdue > 0` else `NDS.textTertiary`. Hidden entirely when `counts.open == 0`. The chip is the deep-link affordance (§4.2).
3. **Meeting count** (comfortable density only) — a muted `📅 \(meetingCount)` where `meetingCount = people.encounterCount(for: person.id) + person.meetingMentions.count`. O(1) per row via the encounter index, so it can stay a row-side call (unlike `items(forPerson:)`).

The pill + chip live in a trailing `HStack(spacing: 6)`. The leading content (avatar/name/type/subtitle) is unchanged.

### 3.7 Density toggle
A new `@AppStorage("people.rowDensity") private var densityRaw = RowDensity.comfortable.rawValue`, surfaced as a menu button next to the sort menu in `actionsRow` (`:216-228`):
```swift
enum RowDensity: String, CaseIterable { case comfortable, compact }
```
- **Comfortable**: `.padding(.vertical, 3)` (current), 28pt avatar, meeting-count signal shown.
- **Compact**: `.padding(.vertical, 1)`, 22pt avatar, no meeting-count, subtitle still `lineLimit(1)`. Roughly +35% rows/screen.

Pass density into `PersonRow` as a parameter (cleaner for previews than reading `@AppStorage` in the row). `SnapshotPersonRow` ignores density (always comfortable — it's a momentary placeholder).

### 3.8 Performance approach (the load-bearing decision)
Mirror `encounterCountIndex`. Add to `PeopleListView`:

```swift
@EnvironmentObject var actionItems: ActionItemStore   // confirm injected — see §5 Increment 2
@State private var taskCounts: [String: TaskCounts] = [:]
```

Build the index **once per task-array change**, off the per-row path:
```swift
private func rebuildTaskCounts() {
    let now = Date()
    var idx: [String: TaskCounts] = [:]
    for item in actionItems.items {                      // single O(n) pass
        guard let pid = item.ownerPersonID, item.status != .completed else { continue }
        var c = idx[pid] ?? .zero
        c.open += 1
        if let due = item.dueDate, due < now { c.overdue += 1 }
        idx[pid] = c
    }
    taskCounts = idx
}
```
Triggered by `.onChange(of: actionItems.items) { _, _ in rebuildTaskCounts() }` and once in `.task` (alongside `rebuildIndexIfNeeded()` at `:118`). This is **one O(tasks) pass on task mutation**, never O(people × tasks) per render. The row receives `taskCounts[id] ?? .zero` — a dictionary lookup, O(1).

> Why not `items(forPerson:)` per row? `items(forPerson:)` (`ActionItemStore.swift:1259-1261`) is `items.filter {...}` — O(tasks). Called inside `ForEach(filtered)` it is O(people × tasks) on *every* list render (every keystroke, every selection change). The memoized index is the same pattern the store already uses for `encounterCountIndex` (`PeopleStore.swift:47/52-56`) and `ActionItemStore`'s own `itemIndex` (`ActionItemStore.swift:24-30`).

> Alternative considered: compute `taskCounts` in `ActionItemStore` itself (a published `[String:TaskCounts]` keyed by owner). Cleaner (one source of truth, no env coupling in the list) but touches the store's hot path and a busier file. Defer; the view-local index is the smaller, lower-risk first move and can be promoted into the store later without changing the row API.

---

## 4. Tasks + Meetings links

### 4.1 The existing person-scope deep-link path (reuse, do not rebuild)
The Tasks tab already supports scoping to a person. The full chain:
1. `ActionItemsView.personSentinel(_ id:)` (`ActionItemsView.swift:96-97`) encodes a person id into a `selectedProjectID` sentinel string (`"__person__" + id`).
2. `TasksEnvironment` decodes it (`TasksEnvironment.swift:63-64`) into `TasksRoute.person(id)`, which resolves to `TaskQuery.Scope.person(id)` (`TaskQuery.swift:27`, matched at `:140`).
3. `WorkspaceRouter.openTasks(route: String)` (`WorkspaceRouter.swift:73-76`) sets `pendingTasksRoute` and switches `section = .actions`.
4. `ActionItemsView.consumePendingTasksRoute()` (`ActionItemsView.swift:298-305`) assigns `pendingTasksRoute` into `env.selectedProjectID`.

So from the People list, deep-linking a person's tasks is exactly:
```swift
router.openTasks(route: ActionItemsView.personSentinel(person.id))
```
No new router state, no new TaskQuery plumbing. (`TaskQuery.Filters.ownerPersonID` `:41` also exists but the scope route is the higher-level, already-wired path.)

### 4.2 Task chip → deep-link
The row's task chip (§3.6) is a trailing `Button` (which naturally captures the hit so it doesn't merely select the row) that does:
```swift
selection = person.id                                                 // keep the person open
router.openTasks(route: ActionItemsView.personSentinel(person.id))    // jump to their tasks
```
Tapping the chip both selects the person *and* lands the Tasks tab pre-filtered to that person.

### 4.3 "Has tasks" triage filter
`TriageFilter.hasTasks` (§3.3) filters `filtered` to `(taskCounts[id]?.open ?? 0) > 0`. This is the list-level entry point for "who do I owe / who owes me follow-ups". Pairs with `.needsAttention` which unions relationship-overdue and task-overdue.

### 4.4 "Mark reached out" — swipe + context action
The single highest-value triage action. Reuses `PeopleStore.bumpLastInteraction(personID:date:)` (`:671-678`, the same call the dashboard's reconnect button makes at `PeopleInsightsView.swift:38`).
- **Context menu**: add to `personRowMenu(_:)` (`:333-350`), shown only when `people.isOverdueForCheckIn(person)`:
  ```swift
  if people.isOverdueForCheckIn(person) {
      Button { people.bumpLastInteraction(personID: person.id, date: Date()) }
          label: { Label("Mark reached out", systemImage: "checkmark.circle") }
  }
  ```
- **Swipe**: `.swipeActions(edge: .trailing)` on the row with the same action, tinted `NDS.mint`. After the bump, the `recencyThenName` re-sort (triggered inside `bumpLastInteraction`) moves the person out of OVERDUE on the next recompute — instant, satisfying feedback. An undo toast mirroring `deleteWithUndo` is optional (the action is non-destructive; lower priority).

### 4.5 Meeting-count signal (optional)
The comfortable-density `📅 N` (§3.6 item 3) uses `encounterCount(for:) + meetingMentions.count` — the same number `mostActive` (`PeopleInsightsView.swift:143`) and `meetingCount` (`PeopleListView.swift:84-86`) already compute. O(1) per row via the existing encounter index, so it's safe to compute row-side. Purely informational; not a deep-link (tapping the row already opens the profile which has the meeting list).

---

## 5. Exhaustive build plan

Each increment is small, compiles green, and is independently shippable. Order is **zero-risk plumbing first**, then visible signals, then structure, then geometry, then deep-links. After each non-trivial Swift edit: `swift build -c release` (per CLAUDE.md). Warnings OK; errors block.

### Increment 1 — Extract `isOverdueForCheckIn` / `overdueDays` (pure refactor)
- **Files**: `PeopleStore.swift`.
- **Change**: add `isOverdueForCheckIn(_:now:)` and `overdueDays(_:now:)` (§3.4); rewrite `overdueCheckInCount` (`:1367-1375`) and `overdueCheckInNames` (`:1379-1390`) to call them.
- **Verify**: build; confirm nav-rail badge count is identical (the badge reads `overdueCheckInCount`). No UI render change.
- **Risk**: **Zero** — net behavior unchanged; only call sites are the badge and weekly digest, both unaffected.

### Increment 2 — Inject `ActionItemStore` + build the task-count index (no render yet)
- **Files**: `PeopleListView.swift`; possibly `MainWindow.swift` (`:411` `case .people: PeopleListView()`) or the app root if the env object isn't already present.
- **Change**: add `@EnvironmentObject var actionItems: ActionItemStore`, `@State taskCounts`, `rebuildTaskCounts()` (§3.8), wire `.task` + `.onChange(of: actionItems.items)`. Do **not** render anything from it yet.
- **Verify (PRE-WORK)**: confirm `ActionItemStore` is in the People tab's environment. `PersonDetailView` already declares `@EnvironmentObject var actionItems` (`PersonDetailView.swift:230`) and is reached from this tab, which strongly implies the store is injected app-wide — but **grep the app root / `MainWindow.swift` for `.environmentObject(` of the action-item store and confirm before relying on it.** A missing `@EnvironmentObject` is a runtime crash, not a compile error — this increment needs a runtime check (`make install`, open People tab, no crash).
- **Risk**: **Low** (env wiring); the only real hazard is a missing injection, caught by the runtime check.

### Increment 3 — `PersonRow` task chip
- **Files**: `PeopleListView.swift`.
- **Change**: add `let counts: TaskCounts` to `PersonRow`; thread `taskCounts[person.id] ?? .zero` at both call sites (`:312` select-mode, `:321` live). Render the task chip (§3.6 item 2) in a trailing `HStack`. Chip non-interactive for now (deep-link comes in Increment 8).
- **Verify**: build; open People with some person-linked tasks; chip shows `☑ N`, reddens when overdue.
- **Risk**: **Low** — additive to the row; `.zero` default keeps zero-task rows visually unchanged.

### Increment 4 — `PersonRow` overdue pill
- **Files**: `PeopleListView.swift`.
- **Change**: in `PersonRow`, when `people.isOverdueForCheckIn(person)`, replace the relative-date `Text` (`:642-645`) with the `"Nd overdue"` pill (`NDS.danger`); else keep the date.
- **Verify**: build; a typed person past cadence shows the pill; others show the date.
- **Risk**: **Low** — `PersonRow` already has `@EnvironmentObject people` (`:617`), so `isOverdueForCheckIn` is reachable.

### Increment 5 — Section grouping (recency-only "This week" first)
- **Files**: `PeopleListView.swift`.
- **Change**: add `PeopleSection`, `collapsed: Set<String>`, the `sections` computed partition (§3.5; "This week" = recency-only this increment), `sectionHeader(_:)`. Swap the live-list `ForEach(filtered)` (`:319-324`) for the sectioned form. **Only when not querying** — gate behind `debouncedQuery.isEmpty` (else fall through to the flat list, §6.1).
- **Verify**: build; confirm OVERDUE/THIS WEEK/EVERYONE ELSE headers with correct counts; collapse/expand works; selection still works; searching reverts to flat.
- **Risk**: **Medium** — the largest structural change. Keep the select-mode list (`:310-317`) flat and ungrouped (bulk select doesn't need triage). Watch: `List` section selection on macOS 14 must still drive `$selection`.
- **Code sketch (the partition)**:
  ```swift
  private var sections: [PeopleSection] {
      // Search owns ordering — never group while querying (callers gate this,
      // but guard defensively too).
      guard debouncedQuery.isEmpty else {
          return [PeopleSection(id: "all", title: "", people: filtered)]
      }
      let cal = Calendar.current; let now = Date()
      var overdue: [Person] = [], week: [Person] = [], rest: [Person] = []
      for p in filtered {
          if people.isOverdueForCheckIn(p) { overdue.append(p); continue }
          let recent = p.lastInteractionAt.map {
              (cal.dateComponents([.day], from: $0, to: now).day ?? 99) <= 7
          } ?? false
          if recent { week.append(p) } else { rest.append(p) }   // birthday clause added in Increment 9
      }
      overdue.sort { people.overdueDays($0) > people.overdueDays($1) }
      var out: [PeopleSection] = []
      if !overdue.isEmpty { out.append(.init(id: "overdue",  title: "Overdue",       people: overdue)) }
      if !week.isEmpty    { out.append(.init(id: "thisWeek", title: "This week",     people: week)) }
      if !rest.isEmpty    { out.append(.init(id: "everyone", title: "Everyone else", people: rest)) }
      // When nothing is overdue/recent, present a single unlabeled "all" section
      // so the list never shows a lone "Everyone else · N" header for the whole graph.
      if out.count == 1, out[0].id == "everyone" {
          return [PeopleSection(id: "all", title: "", people: rest)]
      }
      return out
  }
  ```
  `week`/`rest` are already in `filtered`'s sort order (the partition preserves input order), so no re-sort is needed for those two sections.

### Increment 6 — Triage segmented control
- **Files**: `PeopleListView.swift`.
- **Change**: add `TriageFilter`, `@State triage`, the segmented `Picker` between search and `tagChips` (hidden while querying), and the triage predicate in `filtered` (§3.3). Reuse `isOverdueForCheckIn` and `taskCounts`.
- **Verify**: build; "Needs attention" shows only overdue-relationship ∪ overdue-task people; "Has tasks" shows only `open > 0`; "All" unchanged.
- **Risk**: **Low** — pure filter layer atop existing `filtered`.

### Increment 7 — Density toggle + meeting count
- **Files**: `PeopleListView.swift`.
- **Change**: add `RowDensity`, `@AppStorage("people.rowDensity")`, the density menu button in `actionsRow`, thread density into `PersonRow`, apply the comfortable/compact geometry + meeting-count signal (§3.6 item 3, §3.7).
- **Verify**: build; toggle flips avatar size/padding and shows/hides `📅 N`; persists across relaunch.
- **Risk**: **Low** — geometry only; meeting count is O(1) via the encounter index.

### Increment 8 — Task chip deep-link + "Mark reached out"
- **Files**: `PeopleListView.swift`.
- **Change**: make the task chip a `Button` that selects the person and calls `router.openTasks(route: ActionItemsView.personSentinel(person.id))` (§4.2). Add the swipe action and the conditional context-menu item for "Mark reached out" → `bumpLastInteraction` (§4.4).
- **Verify (RUNTIME)**: `make install`; tap a task chip → Tasks tab opens scoped to that person; swipe/right-click "Mark reached out" → person leaves OVERDUE.
- **Risk**: **Medium** — the chip tap must not be swallowed by row selection; verify the `Button` captures the hit. The deep-link relies on the `personSentinel` chain (§4.1) being intact — verified by behavior, not compile.

### Increment 9 — Widen sidebar + birthday clause for "This week"
- **Files**: `PeopleListView.swift`; small shared helper file for `nextSpecialDateWithin`.
- **Change**: widen the frame at `:113` to `280/340/420` (§3.2). Extract `nextSpecialDateWithin(_:days:)` from `PeopleInsightsView.nextOccurrence`/`comingUp` and add the birthday clause to "This week" (§3.5); refactor `comingUp` to call the shared helper.
- **Verify**: build; people with a birthday/special date in the next 7 days appear in THIS WEEK even with recent contact; dashboard "Coming up" unchanged.
- **Risk**: **Low–Medium** — the only cross-file touch (`PeopleInsightsView`); keep the extraction behavior-preserving.

### Increment 10 — Polish + edge passes
- **Files**: `PeopleListView.swift`.
- **Change**: empty-section suppression, accessibility labels on pill/chip, optional undo toast for "Mark reached out", verify ghost footer still appears only in the all/no-tag/no-query state (§6.6).
- **Verify**: full pass against §6.
- **Risk**: **Low**.

> After the relevant increments land, per CLAUDE.md the agent should ask once: "Push these changes to `tyleryannes94/meetingscribe-refactor`?" before committing.

---

## 6. Edge cases & testing

### 6.1 Search mode (relevance order, NO grouping)
- When `!debouncedQuery.isEmpty`: hide the triage control (§3.3), hide section headers, render a **single flat `ForEach`** of the FTS-ranked `filtered` (which already returns relevance order, `PeopleListView.swift:61` + `PeopleStore.swift:1529-1533`). Do **not** apply triage or sort. Density still applies; the task chip/overdue pill still render (row-level, order-agnostic).
- Test: type a query → results are relevance-ordered, no section headers; clear the query → grouping returns.

### 6.2 Empty list
- `people.people.isEmpty && snapshotRows.isEmpty` → `emptyState` (`:299`) unchanged. No triage control, no sections (they only render in the populated live branch).
- Test: fresh install / empty store shows the `MSEmptyState` exactly as today.

### 6.3 Snapshot rows (cold launch)
- The `snapshotRows` branch (`:303-307`) is unchanged: flat, non-hit-testable, no triage/sections/task-chips (the snapshot digest `ListSnapshot.Row` carries no task or relationship-type data, `PeopleStore.swift:116-124`). Intentional (P-7) — the snapshot is a sub-second placeholder. The moment `people.people` is non-empty, the live grouped list replaces it.
- Test: relaunch with a populated store → snapshot rows flash plain, then the grouped live list appears with pills/chips.

### 6.4 Select mode
- The select-mode list (`:310-317`) stays **flat and ungrouped** — bulk tag/merge/delete doesn't need triage, and section headers would complicate `List(selection: $multiSelection)`. `PersonRow` in select mode still shows pill/chip (read-only context) but the chip's tap is inert in select mode (the row's gesture is the multi-select toggle). `bulkBar` (`:367-422`) unchanged.
- Test: tap Select → flat list, checkboxes work; pills/chips visible but chip deep-link does nothing while selecting.

### 6.5 Large lists (500+)
- The partition runs once per `filtered` recompute (§3.5), not per row. `taskCounts` is one O(tasks) pass per task mutation (§3.8). `meetingCount` is O(1) per row via `encounterCountIndex`. No per-row `items(forPerson:)`. Collapsing EVERYONE ELSE (488 rows) lets the user focus on the ~10 actionable rows.
- Test: seed 500+ people + a few hundred tasks; scroll + type + toggle density → no main-thread hitch; OVERDUE/THIS WEEK stay small and instantly scannable.

### 6.6 Ghosts
- `ghostFooter` (`:469-488`) condition is unchanged: only when `debouncedQuery.isEmpty && tagFilters.isEmpty && people.ghostCount > 0`. With triage active (`.needsAttention`/`.hasTasks`), ghosts are already excluded (untyped, no tasks) so the footer is irrelevant but harmless. When `showGhosts` is on, ghosts join EVERYONE ELSE (never overdue — untyped — and won't have tasks, so they can't reach the other sections).
- Test: with hidden ghosts, footer shows "Show N more contacts"; toggling reveals them in EVERYONE ELSE only; triage filters hide them again.

### 6.7 Two-way selection / router
- `selection` ↔ `router.selectedPersonID` sync (`:150-164`) is untouched. The task chip sets `selection` *and* calls `router.openTasks(...)` — verify this doesn't fight the `onChange(of: selection)` router push (it shouldn't; both end states are consistent).
- Test: deep-link a person from search palette → still selects + scrolls; tap a task chip → person stays selected and Tasks tab opens scoped.

### 6.8 Regression checklist
- Sort menu still disabled while querying (`:227`); sort still applies within EVERYONE ELSE / THIS WEEK.
- Tag chips + AND semantics (`:498-505`) still filter before grouping.
- Relationship-type chips (`:522-540`) still filter before grouping.
- Context menu (Open / Add tag / Delete-with-undo) intact (`:333-350`), now with the conditional "Mark reached out".
- Board/graph modes (`:90-110`) untouched.
- `bumpLastInteraction` re-sort moves a person out of OVERDUE without a manual refresh.

---

## 6.9 Edge-case matrix (state combinations)

The sidebar body has historically been a chain of `if/else` branches (`:297-328`). The redesign adds two orthogonal axes (triage filter × grouping) on top of the existing axes (querying? / select mode? / empty? / snapshot?). The matrix below enumerates the resulting render decision so no combination is left undefined.

| Querying? | Empty store? | Snapshot only? | Select mode? | Render |
|---|---|---|---|---|
| — | yes | no | — | `emptyState` (`:299`); no triage, no sections |
| — | yes | yes | — | non-hit-testable snapshot `List` (`:303-307`); no triage/sections |
| no | no | no | yes | flat `List(selection:$multiSelection)` + `bulkBar`; pills/chips read-only |
| no | no | no | no | **grouped** `List(selection:$selection)` (OVERDUE/THIS WEEK/EVERYONE) + `ghostFooter`; triage control visible |
| yes | no | no | yes | flat select-mode list, FTS order; triage hidden |
| yes | no | no | no | **flat** `List(selection:$selection)`, FTS relevance order; triage + section headers hidden; `ghostFooter` hidden (query ≠ empty) |

Decision rule, in priority order, for the body branch:
1. `people.people.isEmpty` → snapshot or empty (existing `:297-308`).
2. `selectMode` → flat select-mode list (existing `:309-317`, unchanged structurally).
3. `!debouncedQuery.isEmpty` → **flat** live list, FTS order, no triage/sections.
4. else → **grouped** live list with the triage filter applied.

Triage control visibility = (`!people.people.isEmpty && debouncedQuery.isEmpty && !selectMode`). It must not appear in the empty/snapshot/search states.

## 6.10 State & data-flow dependency map

Understanding what recomputes when keeps the perf guarantees honest. The new derived values and their inputs:

- `filtered` (`:49-63`) depends on: `people.people`, `encounters` (via relevance/recency sort), `debouncedQuery`, `tagFilters`, `relationshipTypeFilter`, `sortRaw`, **and now** `triage` + `taskCounts`. SwiftUI recomputes it on any of these. Adding `triage`/`taskCounts` to its inputs means the body re-derives when a task mutates — desired (the chip/pill must update), and cheap because `taskCounts` is a dictionary lookup per person.
- `sections` (new) depends on: `filtered` + `collapsed`. The partition is one O(filtered) pass; `collapsed` only changes which `ForEach` bodies are emitted, not the partition.
- `taskCounts` (new `@State`) is recomputed only by `rebuildTaskCounts()`, which fires on `.task` and `.onChange(of: actionItems.items)`. It is **not** a computed property — it is cached state, so list re-renders that don't change `actionItems.items` do not re-scan tasks.
- `presentTypes` (`:66-69`) and `usedTagIDs()` are unchanged; chip visibility logic is untouched.

Invalidation edges to double-check during implementation:
- A new encounter (`addEncounter`, `PeopleStore.swift:627`) bumps `lastInteractionAt` and re-sorts `people` → `filtered` recomputes → a person may move from OVERDUE to THIS WEEK. Verify this happens without a manual refresh (it should, since `people` is `@Published`).
- Completing a task elsewhere (Tasks tab) mutates `actionItems.items` → `rebuildTaskCounts()` → the chip count drops. Verify the People list updates live while open.
- `bumpLastInteraction` (`:671`) from the swipe action mutates `people` → re-sort → row exits OVERDUE. This is the feedback loop in §4.4.

## 6.11 Visual anatomy: before → after (comfortable density)

```
BEFORE (:624-647)
┌──────────────────────────────────────────────┐
│ (○) Alex Rivera  [type]                  3w   │   ← only signal: 2pt ring + relative date
│     Eng Lead · Acme                            │
└──────────────────────────────────────────────┘

AFTER (overdue, with tasks)
┌──────────────────────────────────────────────┐
│ (○) Alex Rivera  [type]   [3d overdue][☑2·1] │   ← pill (danger) + task chip (danger)
│     Eng Lead · Acme                   📅 7    │   ← meeting count (comfortable only)
└──────────────────────────────────────────────┘

AFTER (not overdue, no tasks) — visually identical to BEFORE plus optional 📅
┌──────────────────────────────────────────────┐
│ (○) Sam Okafor  [type]                   3w   │
│     PM · Globex                       📅 2    │
└──────────────────────────────────────────────┘
```

The key property: a non-overdue, task-free person looks essentially as it does today (only the optional muted meeting count is added). The redesign adds *contrast* — actionable rows gain loud trailing affordances; quiet rows stay quiet.

## 6.12 Open questions / decisions to confirm with the user

1. **Does "Needs attention" union task-overdue?** (§3.3) Spec says yes (relationship-overdue ∪ task-overdue). If the user wants relationship-only, drop the task clause — trivial.
2. **Should the snapshot row gain a static overdue dot?** Currently no (§6.3, P-7). Could be added later by extending `ListSnapshot.Row` with a precomputed `overdue: Bool`, but that bloats the launch digest. Deferred.
3. **Meeting-count `📅` placement** — second line (under subtitle) vs. trailing. Spec puts it on the trailing/secondary line in comfortable density; confirm it doesn't crowd the pill/chip on narrow windows (the widened sidebar §3.2 buys the room).
4. **"This week" recency window** — fixed 7 days, or tied to `effectiveCheckInDays`? Spec uses a flat 7 days for predictability (a partner with a 1-day cadence would otherwise never qualify). Confirm.
5. **Promote `taskCounts` into `ActionItemStore`?** Deferred per §3.8's "alternative considered". If multiple surfaces end up needing owner-task counts, promote then.

---

## 7. Token / primitive reference (for implementers)

- Colors: `NDS.danger` (`NotionDesign.swift:66`, overdue/destructive), `NDS.mint` (`:63`, success/done), `NDS.gold` (`:65`, warning), `NDS.brand` (`:52`), `NDS.textTertiary` (`:98`), `NDS.fieldBg` (`:100`).
- Type: `NDS.tiny` (`:171`), `NDS.small` (`:170`), `NDS.body` (`:169`), `NDS.pageTitle` (`:167`); `.scaledFont(...)` for the name (matches `:629`).
- Geometry: `NDS.radiusSmall` (`:26`, pills/chips), `NDS.radius` (`:28`), `NDS.splitPaneTopInset` (`:20`, top-padding parity with detail pane).
- Components: `MSFilterChip` (via the `FilterChip` alias `:658-664`), `RelationshipTypeChip` (`:632`), `MSAvatar` (`MSAvatar.swift:37`), `MSSearchField` (`:285`), `MSEmptyState` (`:543`), `.msCard()` (dashboard cards).
- Store calls: `people.isOverdueForCheckIn(_:)` / `people.overdueDays(_:)` (new, §3.4), `people.bumpLastInteraction(personID:date:)` (`:671`), `people.encounterCount(for:)` (`:145`), `people.person(by:)` (`:550`).
- Tasks: `ActionItemStore.items` (`:15`), `ActionItem.ownerPersonID`, `ActionItem.Status` (`ActionItem.swift:137-138`, `.completed`), `ActionItem.dueDate`, `ActionItemsView.personSentinel(_:)` (`ActionItemsView.swift:96-97`), `WorkspaceRouter.openTasks(route:)` (`WorkspaceRouter.swift:73-76`), `TaskQuery.Scope.person` (`TaskQuery.swift:27`).
