# Audit — Tasks ↔ Meetings ↔ People Integration

*Agent: tasks. Make a task always one click from its source meeting + owner, and surface counts without drilling in.*

## Current linkage model
- **Task→Meeting** (denormalized): `ActionItem.meetingID`/`meetingTitle`/`meetingDate` (`ActionItem.swift:16-20`); `isManual = meetingID.isEmpty` (124); `signature = "meetingID::title"` dedup (202-205); `ActionItemStore.items(for:)` (230-233); extraction stamps via `ActionItemExtractor.extract(from:meeting:)` (24-64). Reverse jump only on the full task page (`TaskPageView.openSourceMeeting` 538-543).
- **Task→Person**: `owner: String?` + `ownerPersonID: String?` (`ActionItem.swift:23-28`); resolved by `PersonResolver.resolveOwner` (105-111, email-first then exact-name, never substring; self-tokens → nil). Backfilled in `MeetingPipelineController` (277-278, 438-439), `QuickNotesController` (261-262), `createTask(parsing:)` (553-566). `items(forPerson:)` matches `ownerPersonID` only (1259-1261). `delegated` = waiting-on.

## Where it surfaces today
- Meeting summary `actionItemsSection` (`MeetingSummaryTab.swift:472-537`): owner = **plain text, no avatar, no link** (610-612).
- Person `tasksSection`/`commitmentLedger`/`taskRow` (1762-1873): meeting title **not clickable** (1859-1862); matching = `ownerMatchesPerson` (hard link OR fuzzy, 1731-1742).
- Tasks tab: list row owner navigates (`TaskRowView.swift:140-155`) + task page (303-308), but **table** owner (`TaskOwnerLabel`, `ActionItemsTableView.swift:146`) and meeting column (174-177) are **dead** (no nav).

## Gaps
1. Table row is a dead end (meeting col + owner don't navigate). 2. Meeting title only jumps from the task page. 3. Meeting summary owner unlinked. 4. People list shows no task signal. 5. Meeting card shows no open-task badge. 6. Unresolved owners (`owner` set, `ownerPersonID` nil) never resurface. 7. Orphaned-from-meeting tasks (stale `meetingID` after delete) → silent dead jump. 8. Two divergent owner-matchers (profile fuzzy vs rail hard-link-only).

## Navigation primitives (reuse): `router.openMeeting`/`openPerson`/`route(.actionItem,id:)`; `MSAvatar`/`TaskOwnerAvatar`.

## Build plan (small, green, mostly model-free)
1. **Meeting-summary owner navigates** — `MeetingSummaryTab.swift:610-612`: when `ownerPersonID != nil`, render `MSAvatar(14)`+name as `Button { router.openPerson(pid) }` (copy `TaskRowView` 140-149); inject `router`.
2. **Table meeting cell + owner navigate** — `ActionItemsTableView.swift`: wrap meeting `Text` (174-177) in `Button { router.openMeeting }`; owner cell (146) navigates when `ownerPersonID != nil`.
3. **Clickable source meeting on profile** — `PersonDetailView.taskRow:1859-1862` meeting label → `Button { router.openMeeting }`.
4. **Store helpers (no UI)** — `ActionItemStore`: `openCount(forPerson:)`, `overdueCount(forPerson:)`, `unassignedOwnerTasks`. Unit-tested.
5. **Open-task badge on `MeetingCard`** (~121-195): "N open" chip from `items(for:)` when >0.
6. **Person-row open/overdue badge** (`PeopleListView.PersonRow`) using #4 (pairs with `03` step 3).
7. **"Unassigned owners" rail bucket** (`ActionItemsSidebar` near 497-513) via `__unassigned__` sentinel; "link to person" reuses `TaskPageView` picker (289-293, `setOwnerPerson`).
8. **Orphan guard + unify matcher** — `TaskPageView:371-387` show "meeting deleted" non-interactive when `meeting(id:)==nil`; extract `ownerMatchesPerson` into one shared helper used by both profile + `items(forPerson:)`.

Order: 1→2→3 (nav parity, no model change), 4 (foundation), 5→6 (badges), 7→8 (gaps). Interleaves with `02`/`03`.
