# 04 — Tasks ↔ Meetings ↔ People Integration

> **Scope.** The three-way join between an `ActionItem` (a task), the `Meeting`
> (or voice note) it was extracted from, and the `Person` who owns it. This
> document is the exhaustive spec for making that join *coherent and navigable
> everywhere* — every surface that renders a task's meeting or owner should let
> you click through to it, counts should appear wherever a person or meeting is
> listed, unresolved owners should resurface for review, and the two divergent
> owner-matching code paths should collapse into one shared helper.
>
> **Status legend used throughout:** ✅ already implemented in the working tree ·
> 🟡 partially done · ❌ not started.
>
> **Audit date:** 2026-06. All file:line references are against the tree at the
> time of writing; line numbers drift, so the surrounding symbol name is given
> alongside each citation.

---

## 1. Linkage model

A task carries **two independent foreign keys**: one to its source meeting, one
to its owner person. Neither is mandatory; both are denormalized for render-time
cheapness. Understanding exactly how each is set, queried, and can go stale is
the foundation for the rest of this document.

### 1.1 Task → Meeting

Declared on `ActionItem` (`Sources/MeetingScribe/ActionItems/ActionItem.swift`):

| Field | Line | Type | Notes |
|-------|------|------|-------|
| `meetingID` | `ActionItem.swift:16` | `String` | Cross-reference to `Meeting.id`. **Empty string ⇒ manual / imported task.** Never optional. |
| `meetingTitle` | `ActionItem.swift:19` | `String` | Denormalized so the Tasks tab renders without touching the meetings store. Can drift if the meeting is later renamed. |
| `meetingDate` | `ActionItem.swift:20` | `Date` | Denormalized; drives `todayAndYesterday()` and `defaultSort`'s recency tiebreak. |

**Derived helpers** (`ActionItem.swift`):

- `var isManual: Bool { meetingID.isEmpty }` — line 124. The canonical "no source
  meeting" test. Used pervasively in the UI to decide whether to render the
  meeting chip at all.
- `var signature: String` — lines 202-205: `"\(meetingID)::\(title.lowercased().trimmed)"`.
  The dedup key. Re-extracting the same meeting line is idempotent because the
  signature is stable across re-extracts. **Critical coupling:** the signature is
  built from `meetingID`, so if `meetingID` were ever rewritten the task would
  silently un-dedup against its own history.
- `var needsTriage: Bool` — lines 129-131:
  `!meetingID.isEmpty && confirmedAt == nil && status != .completed && deletedAt == nil`.
  Only *meeting-sourced* tasks can be in triage; manual tasks are born confirmed.

**Where `meetingID` / `meetingTitle` / `meetingDate` are set:**

1. **Extraction** — `ActionItemExtractor.extract(from:sourceID:sourceTitle:sourceDate:)`
   (`ActionItemExtractor.swift:32-68`). Stamps `meetingID = sourceID`,
   `meetingTitle = sourceTitle`, `meetingDate = sourceDate`. Source-agnostic: a
   meeting passes `meeting.id/displayTitle/startDate` (lines 24-27); a voice note
   passes `note.id/title/createdAt` (`QuickNotesController.swift:255-256`).
2. **Push from a meeting** — `ActionItemStore.addTasks(_:fromMeetingID:meetingTitle:meetingDate:)`
   (`ActionItemStore.swift:397-451`). Stamps the same three fields from the
   passed meeting metadata; `source = pushedSource` ("push"), `confirmedAt = now`.
3. **Manual create** — `createTask(...)` (`ActionItemStore.swift:333-371`) sets
   `meetingID = ""`, `meetingTitle = ""`, `meetingDate = now`. So a manual task's
   `meetingDate` is its creation date — beware: `todayAndYesterday()` keys off
   `meetingDate`, so a freshly-created manual task *does* count as "today".
4. **Inline add from the meeting summary** — `MeetingSummaryTab.addActionItem()`
   (`MeetingSummaryTab.swift:540-547`) creates a manual task then *back-stamps*
   `meetingID/meetingTitle/meetingDate` from the current meeting and re-upserts.
   This is the one place a task transitions manual → meeting-linked after birth.
5. **Reconcile** — `reconcileExtracted(_:for:)` (`ActionItemStore.swift:1025-1074`)
   refreshes `meetingTitle`/`meetingDate` on existing items by signature (lines
   1048-1049) — so a renamed meeting's title *does* propagate to its tasks on the
   next re-extract, but **not** otherwise (see Gap §3.7).

`isManual` boolean: never persisted, always derived from `meetingID.isEmpty`.

### 1.2 Task → Person (owner)

Two coexisting representations (`ActionItem.swift`):

| Field | Line | Type | Notes |
|-------|------|------|-------|
| `owner` | `ActionItem.swift:23` | `String?` | Free-text display name ("Alice", "Me", "jane@acme.com"). Survives even when no Person record exists. |
| `ownerPersonID` | `ActionItem.swift:28` | `String?` | **Hard link** to `Person.id` (`PeopleStore.person(by:)`). `decodeIfPresent` so old JSON decodes as nil. Enables exact, bidirectional person↔task navigation. |
| `delegated` | `ActionItem.swift:93` | `Bool?` | `true` ⇒ owned by someone *else* — a "waiting-on" item. nil/false ⇒ mine. |

The pair is deliberate: `owner` is the resilient human-readable label that always
renders; `ownerPersonID` is the precise join used for navigation, per-person
counts, and the People-facet rail. They can disagree (e.g. owner text edited but
link kept — see `TaskPageView.swift:269-279`).

**`PersonResolver.resolveOwner` rules** (`PersonResolver.swift:105-114`):

```swift
static func resolveOwner(_ owner: String?, in people: [Person]) -> String? {
    guard let owner else { return nil }
    let trimmed = owner.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if selfTokens.contains(trimmed.lowercased()) { return nil }   // me/i/myself/my/self
    return resolve(trimmed, in: people)                            // email-first, exact-name-second
}
```

- **Self tokens** (`PersonResolver.swift:114`): `["me", "i", "myself", "my", "self"]`
  resolve to `nil` — the current user is not a contact. `ActionItemExtractor.isMine`
  (`ActionItemExtractor.swift:74-97`) owns the "is this the user's own task"
  distinction separately, driven by `AppSettings.myNameAliases/myNameTokens`.
- **`resolve(_:in:)`** (`PersonResolver.swift:70-99`): email-first
  (normalized-email exact match), then exact normalized display-name, then exact
  normalized **alias** match (lines 92-96, "Ty" → "Tyler"). **Never substring** —
  this is the bug-fix that killed "Dan matches Daniel". Returns nil when nothing
  confidently matches.

**Every place `ownerPersonID` gets resolved / set:**

1. **Pipeline finalize** — `MeetingPipelineController.swift:277-278`
   (`finalizeMeeting`): after extraction, for each item with nil `ownerPersonID`,
   `extracted[i].ownerPersonID = PersonResolver.resolveOwner(extracted[i].owner, in: knownPeople)`.
2. **Re-transcribe / regenerate** — `MeetingPipelineController.swift:438-439`
   (`transcribeNow`, `regenerateSummary` branch): identical backfill loop.
3. **Voice-note extraction** — `QuickNotesController.swift:261-262`: same loop,
   guarded by `if items[i].ownerPersonID == nil`, also stamps `source = "voice_note"`.
4. **Quick-add parser** — `ActionItemStore.createTask(parsing:)`
   (`ActionItemStore.swift:554-566`): `@name`/`>name` tokens resolve via
   `PersonResolver.resolve` then a first-name/prefix fallback, then
   `setOwnerPerson(...)`; `>` sets `delegated = true`.
5. **Meeting Actions row** — `MeetingActionRow.ownerMenu`
   (`MeetingActionRow.swift:67-93`): attendee-first assignment calls
   `store.setOwnerPerson(item.id, personID: p.id, ownerName: p.displayName)` (line 72);
   "Unassign" (line 79) clears both to nil.
6. **Task page assignee** — `TaskPageView.swift:265-310`: free-text edit clears a
   stale link unless the name still matches the linked person (269-279); the
   person-picker menu links exactly (289-293); "Unlink person" clears the id but
   keeps the name (283-286).
7. **Person profile quick-add** — `PersonDetailView.addTaskForPerson()`
   (`PersonDetailView.swift:1754-1760`): `createTask` then
   `setOwnerPerson(item.id, personID: current.id, ownerName: current.displayName)`.
8. **Store convenience** — `PeopleStore.resolveOwnerPersonID(_:)`
   (`PeopleStore.swift:1226-1228`) wraps `PersonResolver.resolveOwner` over the
   live `people` snapshot. (Currently only a convenience; the pipeline calls
   `PersonResolver` directly.)

**Store-level write APIs:**

- `setOwner(_:owner:)` — `ActionItemStore.swift:1248-1250`: sets `owner` only,
  leaves `ownerPersonID` untouched (can create disagreement).
- `setOwnerPerson(_:personID:ownerName:)` — `ActionItemStore.swift:1252-1257`:
  sets both in one write. The correct API for any UI that knows the Person.

### 1.3 Every store query that touches the linkage

| Method | Line | Returns |
|--------|------|---------|
| `items(for meetingID:)` | `ActionItemStore.swift:230-233` | Tasks for one meeting, sorted by priority weight then createdAt. |
| `items(forPerson personID:)` | `ActionItemStore.swift:1259-1261` | `items.filter { $0.ownerPersonID == personID }`. **Hard-link only — no owner-string fallback.** |
| `todayAndYesterday(now:)` | `ActionItemStore.swift:269-278` | Excludes `needsTriage`; keys off `meetingDate`. |
| `tasks(matching:)` | `ActionItemStore.swift:287-296` | Composable query; `TaskQuery` supports `.person(id)` scope (`TaskQuery.swift:140`) and `.ownerPersonID` filter (`TaskQuery.swift:158`). |
| `emitMeetingEncounters` task-attach | `PeopleStore.swift:1242-1244` | `meetingTasks.filter { $0.meetingID == meeting.id && $0.ownerPersonID == pid }`. |
| People-facet rail buckets | `ActionItemsSidebar.swift:484-495` | Open-task count per `ownerPersonID`; **resolved owners only** (`guard let pid = item.ownerPersonID` line 487). |
| Today person counts | `TodayView.swift:253, 346` | `items.filter { $0.ownerPersonID == p.id && $0.status != .completed }.count`. |
| Person context (MCP/chat) | `PersonContextBuilder.swift:93` | `$0.ownerPersonID == personID && status != .completed`. |
| Webhook payload | `WebhookService.swift:121` | Emits `ownerPersonID` (or "") per task. |

**Observation:** there is **no** `openCount(forPerson:)` / `overdueCount(forPerson:)`
store helper — every consumer re-implements the
`items.filter { $0.ownerPersonID == p.id && … }` predicate inline (sidebar, Today,
person context). This is the duplication §4.5 proposes to fold into the store. The
only person-keyed read in the store today is `items(forPerson:)`.

---

## 2. Surface audit

Every place a task's **meeting** or **owner** is rendered, and whether it is
navigable today. "Navigable" = clicking it opens the linked entity.

### 2.1 Meeting shown on a task

| # | Surface | File:line (symbol) | Renders meeting | Navigable? | Inconsistency |
|---|---------|--------------------|-----------------|------------|---------------|
| M1 | Tasks **table** "Meeting" column | `ActionItemsTableView.swift:184-199` (`tableRow`) | `meetingTitle`, brand color when linked | ✅ **Yes** → `router.openMeeting(m)` | — (reference implementation, ✅ done) |
| M2 | Tasks **list** row | `TaskRowView.swift:164-170` (`mainRow`) | `Label(item.meetingTitle, "calendar")` | ❌ **No** — plain `Label`, tertiary | Most-used surface, dead text |
| M3 | Tasks **board** card | `ActionItemsBoardView.swift:150` (`boardCard`) | `Text(item.meetingTitle)` tertiary | ❌ **No** | Dead text |
| M4 | **Meeting summary** inline action items | `MeetingSummaryTab.swift:530-534` (`InlineActionItemRow`) | — (you're already in the meeting) | n/a | Correct to omit |
| M5 | **Person profile** task row | `PersonDetailView.swift:1859-1872` (`taskRow`) | `Label(item.meetingTitle, "mic")` | ✅ **Yes** → `router.openMeeting(m)` | — (T3, ✅ done) |
| M6 | **Task page** "From meeting" property | `TaskPageView.swift:371-389` | `meetingTitle` brand | ✅ **Yes** — inline `MeetingPeekPanel` + "open full" | — (4-4, ✅ done) |
| M7 | Meeting **Actions** row | `MeetingActionRow.swift` | — (you're in the meeting) | n/a | Correct to omit |

### 2.2 Owner shown on a task

| # | Surface | File:line (symbol) | Renders owner | Navigable? | Inconsistency |
|---|---------|--------------------|---------------|------------|---------------|
| O1 | Tasks **table** "Owner" column | `ActionItemsTableView.swift:145-157` | `TaskOwnerLabel` | ✅ **Yes** when `ownerPersonID` → `router.openPerson` | — (T2, ✅ done) |
| O2 | Tasks **list** row | `TaskRowView.swift:137-155` | avatar + name | ✅ **Yes** when linked (P2-3) | — ✅ done |
| O3 | Tasks **board** card | `ActionItemsBoardView.swift:130-132` | `TaskOwnerAvatar` | ❌ **No** — avatar only, no link | Dead avatar |
| O4 | **Meeting summary** inline row | `MeetingSummaryTab.swift:611-625` (`InlineActionItemRow`) | avatar + name when linked | ✅ **Yes** → `router.openPerson` | — (T1, ✅ done) |
| O5 | Meeting summary **outcomesStrip** | `MeetingSummaryTab.swift:214-216` | `Text(owner)` tertiary | ❌ **No** | Dead text (read-only preview, lower priority) |
| O6 | **Task page** assignee | `TaskPageView.swift:303-308` | "open person" arrow button | ✅ **Yes** when linked | — ✅ done |
| O7 | Meeting **Actions** row | `MeetingActionRow.swift:82-90` | avatar + name | ❌ **No** — tap opens the assign *menu*, not the person | Defensible (it's the assignment control) |

### 2.3 Count / signal surfaces (task → person/meeting aggregates)

| # | Surface | File:line | Signal | Present? |
|---|---------|-----------|--------|----------|
| C1 | Tasks rail **People** facet | `ActionItemsSidebar.swift:497-536` | open-task count per person | ✅ Yes (resolved owners) |
| C2 | **Today** people strip | `TodayView.swift:253, 346` | open count per person | ✅ Yes |
| C3 | **People list** row | `PersonRow`, `PeopleListView.swift:615-648` | open-task count | ❌ **No** — recency only |
| C4 | **Meeting card** (Today) | `MeetingCard.swift` `content` (123-175) | open-task badge | ❌ **No** |
| C5 | Meeting summary action-items header | `MeetingSummaryTab.swift:482-501` | "N open" + triage bridge | ✅ Yes |
| C6 | Person profile Tasks section | `PersonDetailView.swift:1767-1770` | "N open" | ✅ Yes |

**Net inconsistency:** owner navigation is ~done everywhere except the board
(O3) and the read-only strip (O5); **meeting** navigation is done in the table,
person profile, and task page but **missing in the two highest-traffic Tasks
views (list M2, board M3)**. Count signals are present in the Tasks-internal
surfaces but **absent on the People list (C3) and meeting cards (C4)** — the two
places a user scans "who/what has open work" outside the Tasks tab.

---

## 3. Gap inventory

Numbered, with evidence and severity (P1 = user-visible broken affordance / dead
UI; P2 = missing-but-expected capability; P3 = latent correctness / debt).

### 3.1 — Dead meeting text in the Tasks **list** row · **P1**
`TaskRowView.swift:164-170` renders `Label(item.meetingTitle, systemImage: "calendar")`
as inert tertiary text. The table (M1) made the identical cell clickable; the
list — the default and most-used view — did not. Users learn the meeting is
clickable in one view and find it dead in another.

### 3.2 — Dead meeting text in the Tasks **board** card · **P1**
`ActionItemsBoardView.swift:150` — `Text(item.meetingTitle)` tertiary, no button.

### 3.3 — Dead owner avatar on the **board** card · **P2**
`ActionItemsBoardView.swift:130-132` renders `TaskOwnerAvatar(name: owner)` with
no navigation even when `ownerPersonID` is set. List (O2) and table (O1) both
navigate; the board does not.

### 3.4 — No open-task signal on **People list** rows · **P2**
`PersonRow` (`PeopleListView.swift:615-648`) shows last-interaction recency but
no task count. The data is one filter away (`items(forPerson:)`), and the Tasks
rail (C1) and Today (C2) already compute it — so a person who owns 6 open tasks
looks identical to one who owns none when scanning the People list.

### 3.5 — No open-task badge on **meeting cards** · **P2**
`MeetingCard.content` (`MeetingCard.swift:123-175`) has a health badge and an
outcome line but no "3 open tasks" affordance. `items(for: meeting.id)` is
available. A past meeting with unfinished follow-ups reads as "done".

### 3.6 — Unresolved owners never resurface · **P2**
When `PersonResolver.resolveOwner` returns nil (owner text present but no Person
match — a new name, a typo, a not-yet-added contact), the task keeps `owner` text
with `ownerPersonID == nil` **forever**. Evidence: the backfill loops
(`MeetingPipelineController.swift:277-278, 438-439`; `QuickNotesController.swift:261-262`)
only run at extraction time; nothing re-attempts resolution after the user later
adds that person to People. There is **no review surface** listing "tasks with an
owner name but no person link." These tasks are invisible to the People facet
(C1, resolved-only at `ActionItemsSidebar.swift:487`), to per-person counts, and
to the commitment ledger's hard-link path.

### 3.7 — Orphaned-from-meeting tasks (stale `meetingID` / `meetingTitle`) · **P3**
- **Deleted meeting:** nothing nulls a task's `meetingID` when its source meeting
  is deleted. The task's "Open meeting" button then silently degrades to plain
  text because `manager.meeting(id:)` returns nil (the guard at
  `ActionItemsTableView.swift:187` and `PersonDetailView.swift:1862`), but the
  task is still labeled "From <title>" forever and never relinks.
- **Stale title:** `meetingTitle` only refreshes on a re-extract that hits the
  same signature (`reconcileExtracted` line 1048). A meeting renamed without a
  re-extract leaves every task showing the *old* title even though the link still
  resolves. No invariant keeps the denormalized title in step.

### 3.8 — Two divergent owner-matchers · **P3**
There are **two** independent implementations of "does this task belong to this
person," and they disagree:

1. **`PersonResolver.resolveOwner` / `resolve`** (`PersonResolver.swift:70-114`)
   — email-first, exact-name-second, exact-alias-third, **never substring**.
   Used by every *write* path (pipeline, voice notes, quick-add).
2. **`PersonDetailView.ownerMatchesPerson`** (`PersonDetailView.swift:1731-1742`)
   with `ownerTokens` (1717-1729) — hard-link first, then a **first-name token
   match** *and* a **substring** match (`owner.contains(full)`, line 1741). Used
   by the person profile's `personTasks` (1744-1752) to display tasks.

The profile uses the looser matcher precisely because legacy tasks predate the
hard link — but that reintroduces the exact substring fuzziness `PersonResolver`
was written to eliminate. So a task can appear on Alice's profile (substring
match) while being invisible to the People-facet rail (hard-link only) — the same
task, two different answers about its owner.

### 3.9 — Non-navigable owner in meeting summary **outcomesStrip** · **P3**
`MeetingSummaryTab.swift:214-216` — read-only `Text(owner)`, never linked even
when `ownerPersonID` exists. Low traffic (it's a 5-item preview) but inconsistent
with the inline row directly below it (O4).

---

## 4. Proposed integration

Design goal: **one task is one node with two edges; every rendering of an edge is
a door.** Plus aggregate counts wherever an entity that *has* tasks is listed,
and a review loop that closes the unresolved-owner gap.

### 4.1 Make meeting + owner navigable everywhere

A single shared row affordance, reused by list / board / strip, so navigation can
never again be implemented per-view-and-forgotten.

- **New shared views** in a small file (e.g. `Sources/MeetingScribe/UI/TaskLinkChips.swift`):
  - `TaskMeetingChip(item:)` — renders nothing when `item.isManual`; otherwise a
    button that calls `router.openMeeting` when `manager.meeting(id:)` resolves,
    falling back to inert tertiary text (the exact pattern at
    `ActionItemsTableView.swift:184-199`). Centralizes the deleted-meeting guard.
    **Must branch on `source`** (see §6.4): a `"voice_note"`-sourced task routes
    via `router.route(kind: .voiceNote, id:)`, not `openMeeting`.
  - `TaskOwnerChip(item:, size:)` — avatar + name; button → `router.openPerson`
    when `ownerPersonID != nil`, else plain label (the pattern at
    `TaskRowView.swift:137-155`).
- **Already done (do not redo):** O1/O2/O4/O6 (owner nav in table, list, summary
  inline, task page); M1/M5/M6 (meeting nav in table, person profile, task page).
- **Remaining wiring:** swap M2 (`TaskRowView.swift:164-170`) and M3
  (`ActionItemsBoardView.swift:150`) to `TaskMeetingChip`; swap O3
  (`ActionItemsBoardView.swift:130-132`) to `TaskOwnerChip`; optionally O5/§3.9
  (`MeetingSummaryTab.swift:214-216`).

### 4.2 Count badges on person rows + meeting cards

- **People list row (C3):** add an open-task pill to `PersonRow`
  (`PeopleListView.swift:615-648`) using the new `store.openCount(forPerson:)`
  (§4.5). Render only when `> 0`; tap → Tasks tab scoped to that person
  (`ActionItemsView.personSentinel(person.id)` via `router.openTasks(route:)`,
  `WorkspaceRouter.swift:73-76`).
- **Meeting card (C4):** add an open-task badge to `MeetingCard.content`
  (`MeetingCard.swift:123-175`) from
  `store.items(for: meeting.id).filter { $0.status != .completed }.count`. Tap →
  Tasks tab scoped to the meeting (`env.selectedMeetingID`).

### 4.3 "Unassigned owners" review surface (closes §3.6)

- **New store helper** `unassignedOwnerTasks()` (§4.5): live tasks with a non-empty
  `owner` but `ownerPersonID == nil` and a *non-self* owner token.
- **New rail entry** in the `ActionItemsSidebar` People section header (next to the
  resolved buckets at `ActionItemsSidebar.swift:497-513`): "Unassigned (N)".
  Selecting it lists those tasks with an inline **resolve** control reusing
  `MeetingActionRow.ownerMenu`'s pattern (`MeetingActionRow.swift:67-93`) to pick
  a Person (`setOwnerPerson`) or create one.
- **Auto re-resolve hook:** when a Person is created/edited (`PeopleStore.updatePerson`),
  fire an opportunistic pass calling `PersonResolver.resolveOwner` over
  `unassignedOwnerTasks()` and `setOwnerPerson` on the now-matching ones. Cheap; the
  set is small. Keep it behind a single store method so it's testable in isolation.

### 4.4 Orphan guards (closes §3.7)

- **On meeting delete:** **do not** null `meetingID` — it would flip
  `isManual`/`needsTriage` and change `signature`, silently un-deduping the task
  against its own history. **Prefer the soft approach:** leave the ids, let
  `TaskMeetingChip` degrade to inert text (already the behavior at every nav call
  site's `manager.meeting(id:)` guard), and add a one-line "source meeting deleted"
  tooltip. Document the choice so it isn't "fixed" into the dangerous version.
- **Stale title:** add `store.refreshMeetingTitle(_ meetingID:, to:)` called from
  the meeting-rename path so the denormalized `meetingTitle` stays in step without
  needing a re-extract. Iterates `items.indices where meetingID == …`.

### 4.5 Unify the owner-matcher + new store helpers

**Collapse §3.8 into one path.** Add to `PersonResolver`:

```swift
/// True if `item` belongs to `person`. Hard link wins; otherwise falls back to
/// the SAME email-first / exact-name / exact-alias resolution used on write —
/// never substring. Replaces PersonDetailView.ownerMatchesPerson.
static func taskBelongs(_ item: ActionItem, to person: Person) -> Bool {
    if let pid = item.ownerPersonID { return pid == person.id }
    return resolveOwner(item.owner, in: [person]) == person.id
}
```

`PersonDetailView.personTasks` (`PersonDetailView.swift:1744-1752`) then filters
with `PersonResolver.taskBelongs($0, to: current)`; delete `ownerMatchesPerson`
(1731-1742) and `ownerTokens` (1717-1729). This intentionally *tightens* the
profile to exact matching, matching the rail/counts — legacy substring hits go
away, which is correct (they were the bug).

**New `ActionItemStore` helpers** (all `@MainActor`, beside `items(forPerson:)`
at `ActionItemStore.swift:1259`):

```swift
/// Open (non-completed) tasks hard-linked to a person.
func openCount(forPerson personID: String) -> Int {
    items.filter { $0.ownerPersonID == personID && $0.status != .completed }.count
}

/// Open AND overdue (due before today) tasks for a person.
func overdueCount(forPerson personID: String) -> Int {
    let start = Calendar.current.startOfDay(for: Date())
    return items.filter {
        $0.ownerPersonID == personID && $0.status != .completed
            && ($0.dueDate.map { $0 < start } ?? false)
    }.count
}

/// Live tasks naming an owner that resolved to no Person (excludes self tokens
/// and already-linked tasks) — the "Unassigned owners" review queue.
func unassignedOwnerTasks() -> [ActionItem] {
    items.filter { item in
        guard item.ownerPersonID == nil, item.status != .completed else { return false }
        guard let o = item.owner?.trimmingCharacters(in: .whitespacesAndNewlines),
              !o.isEmpty else { return false }
        return !PersonResolver.selfTokens.contains(o.lowercased())
    }
}
```

`TodayView.swift:253/346`, `PersonContextBuilder.swift:93`, and
`ActionItemsSidebar.swift:484-495` should adopt `openCount(forPerson:)` so the
predicate lives in exactly one place.

---

## 5. Exhaustive build plan

Small, independently-shippable increments. Each: title · files · change + sketch
· build-verification · risk. Build verification per `CLAUDE.md`:
`swift build -c release` (or `make app`) — warnings OK, errors block.

> **Increments already in the working tree** (do **not** re-implement):
> - ✅ **B0a** Owner→person link in summary `InlineActionItemRow`
>   (`MeetingSummaryTab.swift:611-625`).
> - ✅ **B0b** Table meeting-cell + owner navigation
>   (`ActionItemsTableView.swift:145-157, 184-199`).
> - ✅ **B0c** Person `taskRow` meeting link (`PersonDetailView.swift:1859-1872`).

### B1 — Shared `TaskMeetingChip` / `TaskOwnerChip` components · ❌
- **Files:** new `Sources/MeetingScribe/UI/TaskLinkChips.swift`.
- **Change:** extract the table's proven button-with-fallback into two reusable
  views (sketch in §4.1). `@EnvironmentObject router`; take `MeetingManager` (for
  `meeting(id:)`) or accept a resolved `Meeting?` to stay store-free and
  unit-friendly. `TaskMeetingChip` branches on `item.source == "voice_note"`.
- **Verify:** builds; no behavior change yet (nothing consumes them).
- **Risk:** Low. Pure additive.
- **Tests:** extract a tiny pure `linkState(for:)` and unit-test it (button iff
  link resolves; voice-note → voiceNote route; manual → nothing).

### B2 — Adopt `TaskMeetingChip` in the list row (closes §3.1) · ❌
- **Files:** `TaskRowView.swift:164-170`.
- **Change:** replace the `Label(item.meetingTitle, "calendar")` block with
  `TaskMeetingChip(item: item)`. Keep the `!item.isManual` guard inside the chip.
- **Verify:** build; click a list row's meeting → Meetings tab opens.
- **Risk:** Low. `ActionItemRow` already has `@EnvironmentObject router` (line 43).

### B3 — Adopt chips on the board card (closes §3.2, §3.3) · ❌
- **Files:** `ActionItemsBoardView.swift:130-132` (owner), `:150` (meeting).
- **Change:** swap `TaskOwnerAvatar` → `TaskOwnerChip(item:, size: 16)`;
  `Text(item.meetingTitle)` → `TaskMeetingChip(item:)`.
- **Verify:** build; click a card's owner avatar → People; meeting → Meetings.
- **Risk:** Medium — board cards are `.draggable` inside `BoardColumnView`. A
  nested `Button` can swallow the drag start; verify drag still works (the title
  is the drag handle, not the chips, so this should be fine, but confirm).

### B4 — `openCount(forPerson:)` / `overdueCount(forPerson:)` + adopt · ❌
- **Files:** `ActionItemStore.swift` (new helpers near :1259); refactor
  `TodayView.swift:253,346`, `ActionItemsSidebar.swift:484-495`,
  `PersonContextBuilder.swift:93`.
- **Change:** add helpers (§4.5); replace inline predicates with calls.
- **Verify:** build; counts unchanged in Tasks rail / Today.
- **Risk:** Low. Behavior-preserving refactor (assert identical filter).
- **Tests:** unit — seed items with mixed `ownerPersonID`/status/due, assert
  `openCount`/`overdueCount`.

### B5 — Open-task pill on People list rows (closes §3.4) · ❌
- **Files:** `PeopleListView.swift:615-648` (`PersonRow`).
- **Change:** inject `@EnvironmentObject actionItems: ActionItemStore`; render a
  pill from `actionItems.openCount(forPerson: person.id)` when `> 0`; tap →
  `router.openTasks(route: ActionItemsView.personSentinel(person.id))`.
- **Verify:** build; a person with open tasks shows the pill; tap scopes Tasks.
- **Risk:** Medium — `PersonRow` is in a `ForEach` over `filtered`; calling
  `openCount` per row is O(n·m). For large lists, precompute a `[personID: Int]`
  once in the parent and pass it down.

### B6 — Open-task badge on meeting cards (closes §3.5) · ❌
- **Files:** `MeetingCard.swift:123-175` (`content`).
- **Change:** for `variant == .past`, compute
  `manager.actionItems.items(for: meeting.id).filter { $0.status != .completed }.count`;
  render a small badge near the outcome line; tap → Tasks scoped to the meeting.
- **Verify:** build; a past meeting with open follow-ups shows "N open".
- **Risk:** Medium — `MeetingCard` is in a `LazyVStack`; the count read is cheap
  (in-memory filter) but runs on body eval. Cache per `meeting.id` if it shows up
  in profiling. **Do not read files** — the `transcriptReady` comment at
  `MeetingCard.swift:374` documents exactly this jank vector.

### B7 — Unify owner-matcher: `PersonResolver.taskBelongs` (closes §3.8) · ❌
- **Files:** `PersonResolver.swift` (add `taskBelongs`); `PersonDetailView.swift`
  (`personTasks` → use it; delete `ownerMatchesPerson` 1731-1742 + `ownerTokens`
  1717-1729).
- **Change:** sketch in §4.5.
- **Verify:** build; profile still lists hard-linked + exactly-resolvable tasks;
  substring-only legacy hits drop off (expected).
- **Risk:** Medium — **behavior change**: a profile that today shows a substring
  match loses it. Mitigate by landing B8 (re-resolve) first/together so legacy
  tasks get a real hard link before the tightening.
- **Tests:** unit — `taskBelongs` with hard link, exact name, alias, email,
  substring (must be false), self-token owner (false).

### B8 — Re-resolve unassigned owners on People mutation (closes §3.6, part 1) · ❌
- **Files:** `ActionItemStore.swift` (new `reresolveUnassignedOwners(against:)`);
  `PeopleStore.swift` (`updatePerson` / create paths fire it).
- **Change:** iterate `unassignedOwnerTasks()`, `PersonResolver.resolveOwner`,
  `setOwnerPerson` on matches. Batch into one save.
- **Verify:** build; add a contact "Alice", a pre-existing task owned "Alice"
  (no link) gets `ownerPersonID` set and appears in the People facet.
- **Risk:** Low-Medium. Guard against re-entrancy (don't observe the same store
  mutation it triggers). Keep it a single explicit method, not a reactive sink.
- **Tests:** unit — seed an unlinked-owner task, add a matching Person, assert link.

### B9 — "Unassigned owners" review rail (closes §3.6, part 2) · ❌
- **Files:** `ActionItemStore.swift` (`unassignedOwnerTasks`, §4.5);
  `ActionItemsView.swift` (new sentinel, e.g. `unassignedOwnersSentinel`, alongside
  the prefixes at `:88-107`); `ActionItemsSidebar.swift:497-513` (rail entry); list
  rendering reuses `MeetingActionRow.ownerMenu` resolve pattern.
- **Change:** add the helper + sentinel + a People-section header row
  "Unassigned (N)"; selecting it filters the main list to those tasks with an
  inline person-picker.
- **Verify:** build; tasks with unresolved owner names appear; picking a person
  links them and they leave the bucket.
- **Risk:** Medium — touches the sidebar selection model (`env.selectedProjectID`
  sentinel encoding, `ActionItemsView.swift:88-107`). Follow the existing
  `personSentinelPrefix` pattern exactly.

### B10 — `refreshMeetingTitle` on rename + degrade-tooltip (closes §3.7) · ❌
- **Files:** `ActionItemStore.swift` (`refreshMeetingTitle(_:to:)`); meeting-rename
  path in `MeetingManager`; `TaskMeetingChip` (add "source meeting deleted" help
  when `!item.isManual` but `meeting(id:)` is nil).
- **Change:** title-sync method + call site; chip tooltip.
- **Verify:** build; rename a meeting → its tasks show the new title without a
  re-extract; delete a meeting → its tasks' chip degrades with a tooltip.
- **Risk:** Low. Do **not** rewrite `meetingID` (would change `signature`).

### B11 — Owner nav in summary `outcomesStrip` (closes §3.9) · ❌
- **Files:** `MeetingSummaryTab.swift:214-216`.
- **Change:** swap `Text(owner)` for `TaskOwnerChip(item:, size: 12)`.
- **Verify:** build; a linked owner in the outcomes preview navigates.
- **Risk:** Low.

**Suggested order:** B1 → B2 → B3 → B11 (navigation sweep) · B4 → B5 → B6 (counts)
· B8 → B7 (re-resolve before tightening) → B9 (review surface) → B10 (orphans).

---

## 6. Edge cases

1. **Non-person owners ("me" / self tokens).** `owner == "Me"`/"I"/"myself" must
   never get an `ownerPersonID`. Enforced at `PersonResolver.swift:109` (resolve
   returns nil) and excluded from `unassignedOwnerTasks()` (§4.5) so the review
   queue isn't polluted by the user's own tasks. `ActionItemExtractor.isMine`
   (`ActionItemExtractor.swift:74-97`) is the *separate*, profile-driven owner of
   the "is this mine" question — don't conflate `ownerPersonID == nil` with
   "delegated". `TaskOwnerChip` renders a self-owned task as a plain
   non-navigable label (correct — there's no contact to open).

2. **Deleted meetings.** `meetingID` points at a gone `Meeting`. Every meeting-nav
   call site already guards with `manager.meeting(id:)` returning nil (table
   `:187`, person profile `:1862`, task page peek). `TaskMeetingChip` must
   replicate that guard and degrade to inert text (§4.4). **Do not** null
   `meetingID` on delete — it would flip `isManual`/`needsTriage` and break
   `signature` dedup. The task keeps its history; only the door closes.

3. **Manual tasks.** `meetingID == ""`. `TaskMeetingChip` renders **nothing**
   (guard on `item.isManual`). `meetingDate == createdAt`, so manual tasks
   legitimately appear in `todayAndYesterday()`. They are born `confirmedAt = now`
   (`createTask`, `ActionItemStore.swift:333-371`), so never `needsTriage`. The
   summary inline add (`MeetingSummaryTab.swift:540-547`) is the one path that
   promotes a manual task to meeting-linked after creation — verify it also runs
   owner-resolve backfill if an owner is later set (currently it does not; minor
   follow-up, not in the core plan).

4. **Voice-note-sourced tasks.** `source == "voice_note"`
   (`QuickNotesController.swift:260`), `meetingID == note.id`. **`manager.meeting(id:)`
   returns nil** because a note is not a `Meeting` — so a naïve `TaskMeetingChip`
   would degrade to inert text even though the source *does* exist (as a voice
   note). The fix: `TaskMeetingChip` branches on `source` and routes
   `"voice_note"` tasks via `router.route(kind: .voiceNote, id: item.meetingID)`
   (`WorkspaceRouter.swift:239-241`), else `router.openMeeting`. Flag this in
   B1/B2 so the chip isn't hardwired to meetings.

5. **Delegated / waiting-on.** `delegated == true` (`ActionItem.swift:93`; set on
   extraction for others' items at `ActionItemExtractor.swift:61`, on `>name`
   quick-add at `ActionItemStore.swift:565`). These still carry an owner (someone
   else) and should resolve to a Person like any other — they power the per-person
   **commitment ledger** (`PersonDetailView.commitmentLedger`, `:1801-1817`, splits
   "Waiting on X" vs "X's open items") and the rail "Waiting on" bucket
   (`ActionItemsSidebar.waitingTasks`, `:542-546`). `taskBelongs` (§4.5) must work
   identically for delegated tasks (it does — it ignores `delegated`). The
   "Unassigned owners" queue (§4.3) **should include** delegated tasks whose owner
   name didn't resolve — those are commitments you're tracking against a person who
   isn't in People yet, the highest-value resolves.

6. **Owner text edited, link kept/cleared.** `TaskPageView.swift:269-279`: editing
   the assignee free-text keeps the hard link only if the new text still equals the
   linked person's `displayName`, else clears `ownerPersonID`. This is the one path
   that can *intentionally* create owner/link disagreement (a nickname).
   `taskBelongs` trusts the hard link first, so the task stays on the right profile
   regardless of the typed nickname — correct.

7. **Imported tasks (Linear/Notion).** `mergeExternal` (`ActionItemStore.swift:576-623`)
   sets `owner` from the external system but **never** resolves `ownerPersonID`.
   So every imported task with an owner lands in the "Unassigned owners" queue
   (§4.3) — acceptable (the user can link them), but consider running the resolve
   backfill inside `mergeExternal` for parity with extraction (follow-up).
