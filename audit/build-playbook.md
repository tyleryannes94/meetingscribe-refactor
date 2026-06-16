# MeetingScribe Tasks — Claude Code Build Playbook
*Copy-paste prompts for each build phase. Paste the ground-rules prompt once, then one phase prompt per session.*

---

## GROUND-RULES PROMPT
*Paste this once at the start of any Claude Code session, or add it to `CLAUDE.md`.*

```
You are building improvements to MeetingScribe, a macOS SwiftUI app.
Repo: ~/MeetingScribeRefactor (local), https://github.com/tyleryannes94/meetingscribe-refactor (remote)
Default branch: main

## Rules
- After EVERY code change, ask once: "Push these changes to tyleryannes94/meetingscribe-refactor?"
- On yes: git add -A && git commit -m "<category>: <message>" && git push
- After non-trivial Swift edits, run `swift build -c release` before pushing. Errors block push; warnings do not.
- Commit style: imperative, lowercase after prefix (feat:, fix:, refactor:, chore:). Under 72 chars.
- macOS 14+, Apple Silicon (M2), SwiftUI + AppKit, no third-party UI frameworks.
- Design system: NDS (all colors/fonts/spacing go through NDS tokens).
- All changes are additive where possible — existing JSON decodes must not break (use `decodeIfPresent` for new fields).
- The audit master plan is at: ~/MeetingScribeRefactor/audit/master-plan.md — read it before starting.
- Per-agent findings are at: ~/MeetingScribeRefactor/audit/findings/*.md
- Do NOT touch Meetings, People, or Home tabs — Tasks only.
```

---

## PHASE 0 — Architecture Foundation
*No visible UI changes. These unblock everything else.*

```
Read ~/MeetingScribeRefactor/audit/master-plan.md (Phase 0 section) and the following files in full:
- Sources/MeetingScribe/UI/ActionItemsView.swift
- Sources/MeetingScribe/UI/ActionItemsViewModel.swift
- Sources/MeetingScribe/UI/ActionItemsChrome.swift
- Sources/MeetingScribe/UI/ActionItemsListView.swift
- Sources/MeetingScribe/UI/ActionItemsSidebar.swift
- Sources/MeetingScribe/ActionItems/ActionItemStore.swift

Then implement these 4 items in order:

A0-1 — Complete ViewModel migration:
- Instantiate ActionItemsViewModel as @StateObject in ActionItemsView (not @ObservedObject or @State)
- Move all @State vars for filter/sort/viewMode into the ViewModel
- Deduplicate GroupBy, Filter, ViewMode enums — keep the ViewModel's definitions, delete duplicates from the view
- Replace `var filtered` in ActionItemsListView with `vm.filteredSorted(items:)` 
- Do NOT change any visible behavior — this is a pure refactor

A0-2 — Typed TasksRoute enum:
- Create Sources/MeetingScribe/UI/TasksRoute.swift
- Define: enum TasksRoute: Hashable { case home, today, triage, allTasks, noProject, waitingOn, project(String), initiative(String), person(String), meeting(String), task(String) }
- Replace all selectedProjectID sentinel string comparisons in ActionItemsView/Chrome/Sidebar with this enum
- Constants like ActionItemsView.homeSentinel become TasksRoute.home

A0-3 — TasksEnvironment:
- Create Sources/MeetingScribe/UI/TasksEnvironment.swift
- Define: class TasksEnvironment: ObservableObject { @Published var route: TasksRoute = .home; @Published var selectedTaskID: String? = nil }
- Replace the 3-binding prop drilling (@Binding var selectedProjectID, selectedMeetingID, selectedInitiativeID) through ProjectRail, PageTreeNode, InitiativeNode with @EnvironmentObject var env: TasksEnvironment
- Fix the P0-3 bug: in PageTreeNode.onTapGesture, clear env.route's initiative state when tapping a project

A0-4 — O(1) store index:
- In ActionItemStore, add: private var itemIndex: [String: Int] = [:]
- Rebuild it in the setter: whenever items is assigned, rebuild itemIndex from scratch
- Update on append: after items.append(new), itemIndex[new.id] = items.count - 1
- Update on remove: after delete, rebuild index (full rebuild is fine for correctness)
- Replace all items.firstIndex(where: { $0.id == id }) with itemIndex[id] in update(_:mutate:), blockers(for:), reachableViaBlockers

Run swift build -c release after each item. Fix any errors before proceeding.
```

---

## P0 BUGS — Fix immediately (can run before or alongside Phase 0)

```
Read ~/MeetingScribeRefactor/audit/master-plan.md (Critical Bugs section).
Fix these 5 bugs in order:

P0-1 — Quick-add auto-refocus:
In ActionItemsChrome.swift, find quickAddPopover. Add @FocusState private var quickAddFocused: Bool.
Bind the quick-add TextField's `focused` to $quickAddFocused.
In commitQuickAdd() (the function that runs on Enter), after clearing quickAddText, set quickAddFocused = true inside Task { @MainActor in }.
Same fix in TaskPageView.subtasks(): the "Add subtask…" TextField should refocus after addSubtask().

P0-2 — Wire inline detailEditor:
In ActionItemsListView.swift, find row(for:). The onToggleExpand closure currently sets selectedTaskID.
Change it to: editingID = (editingID == item.id) ? nil : item.id
Add a double-click gesture (or the Return key press) that sets selectedTaskID = item.id (to open full page).
Confirm ActionItemRow renders detailEditor when item.id == editingID (check TaskRowView.swift line ~413).

P0-3 — PageTreeNode stale highlight:
In ActionItemsSidebar.swift, find PageTreeNode's onTapGesture.
After setting selectedProjectID = project.id, also set selectedInitiativeID = nil.
(After A0-3, this becomes env.route = .project(project.id) which implicitly clears initiative.)

P0-4 — Hide archived items:
In ActionItemStore.swift, find sortedInitiatives() and standaloneTopProjects().
Add .filter { $0.status == .active } to both.
In ProjectRail, at the very bottom of the ScrollView, add a Button("Show archived") that toggles @State var showArchived. When showArchived is true, also show a filtered-to-archived section for both initiatives and pages.

P0-5 — Fix "This Week" filter:
In ActionItemsListView.swift around line 280, find the thisWeek filter branch.
Remove any createdThisWeek condition. "This Week" should mean ONLY: item.dueDate falls between the start and end of the current calendar week.

Run swift build -c release. Fix errors. Then ask to push.
```

---

## PHASE 1 — Work/Personal Context Separation + Today View
*Most impactful phase. Read master-plan.md Phase 1 section first.*

```
Read ~/MeetingScribeRefactor/audit/master-plan.md (Phase 1) and:
- Sources/MeetingScribe/ActionItems/Initiative.swift
- Sources/MeetingScribe/ActionItems/ActionItem.swift
- Sources/MeetingScribe/ActionItems/TaskQuery.swift
- Sources/MeetingScribe/ActionItems/ActionItemStore.swift (sections on initiatives)
- Sources/MeetingScribe/UI/ActionItemsSidebar.swift
- Sources/MeetingScribe/UI/HomeTasksBoard.swift

Implement in order:

1-1 — WorkspaceContext model + contextID:
Create Sources/MeetingScribe/ActionItems/WorkspaceContext.swift:
  struct WorkspaceContext: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var colorHex: String?
    var sortIndex: Double?
    var createdAt: Date = Date()
  }
Add to ActionItemStore: @Published private(set) var contexts: [WorkspaceContext] = []
Persist to contexts.json alongside action_items.json.
Add var contextID: String? to Initiative and ActionItem (use decodeIfPresent).
Seed two defaults on first launch: WorkspaceContext(name: "Work", colorHex: "#4F8DFD") and WorkspaceContext(name: "Personal", colorHex: "#34C759").
Add to TaskQuery.Scope: case context(String) — resolved by TaskQueryEngine to tasks whose Initiative.contextID matches.
Add store methods: func createContext(name:colorHex:) -> WorkspaceContext, func deleteContext(_:), func setContext(_ itemID: String, contextID: String?), func setInitiativeContext(_ initiativeID: String, contextID: String?).

1-2 — Context switcher in sidebar:
In ProjectRail, above the railItem("Home"...) call, add a compact segmented/pill control showing all context names + "All".
Bind selection to @State var activeContextID: String? (nil = All).
When a context is selected, filter the Initiatives tree to show only initiatives with that contextID.
Also pass activeContextID into ActionItemsView so task lists can be pre-scoped (pass as a filter to TaskQuery).
Use NDS color tokens — active pill uses the context's colorHex, inactive is NDS.fieldBg.

1-3 — "Today" smart view:
Add TasksRoute.today to the enum (if A0-2 is done) or add a new sentinel.
In ProjectRail, add railItem("Today", icon: "sun.max.fill", ...) BELOW Home and ABOVE Triage inbox.
Badge: count of overdue + due-today tasks (recompute live).
In ActionItemsChrome, add a todayPane case: an ActionItemsListView scoped to a TaskQuery with filters.overdue=true OR filters.dueWithinDays=0, sorted by .due ascending, grouped by Initiative name.
Make .today the default route when the Tasks tab is first opened (replace the current default).

1-4 — Home board focus filter:
In HomeTasksBoard.swift, above the ScrollView, add a FilterBar HStack:
  - Segmented: "Today" / "This Week" / "All" — changes a @State var timeScope
  - Context pills matching the user's WorkspaceContexts + "All"
In items(_ status:), extend the filter to:
  - If timeScope == .today: also require dueDate == today OR status == .inProgress
  - If timeScope == .thisWeek: require dueDate within next 7 days
  - If context is selected: require the task's project's initiative's contextID matches
Replace `ForEach(list.prefix(8))` with a ScrollView-wrapped column (max height 400pt, no cap).
Make the "+N more" Text a Button that deep-links to Tasks in list view, status filter matching the column.

1-5 — Context color coding:
In TaskRowView.mainRow, add a 3pt wide RoundedRectangle left bar using the task's context color.
  - Resolve: task → projectID → project → initiativeID → initiative → contextID → context → colorHex
  - If no context, omit the bar
In HomeTasksBoard.card, add a 3pt colored top stripe using the same resolution.
Cache the context color lookup on the store (add func contextColor(for item: ActionItem) -> Color?).

Run swift build -c release after each item. Ask to push after all 5 items pass.
```

---

## PHASE 2 — Speed & Daily Fluency
*All items are largely independent. Can be split into multiple PRs.*

```
Read ~/MeetingScribeRefactor/audit/master-plan.md (Phase 2) and:
- Sources/MeetingScribe/UI/ActionItemsChrome.swift (quickAddPopover area)
- Sources/MeetingScribe/UI/ActionItemsListView.swift (onKeyPress block, row(for:))
- Sources/MeetingScribe/UI/TaskRowView.swift (dueChip, priorityPicker)
- Sources/MeetingScribe/ActionItems/TaskQuickAddParser.swift

RISKY ITEMS: 2-2 and 2-3 touch core row interaction — test carefully after each.

Implement:

2-1 (already done in P0-1 — skip if P0 phase is complete)

2-2 — Wire inline detail editor (if P0-2 not yet done — skip if already fixed):
Already described in P0-2 above.

2-3 — Extend TaskQuickAddParser with @Project and due:date:
In TaskQuickAddParser.swift, add parsing for:
  - @Word or @"Multi Word" → fuzzy-match against store.projects by name → set projectID on the result
  - due:today, due:tomorrow, due:friday, due:next-week, due:+3d → parse to a Date and set dueDate
  - Add these to the hint string shown in the quick-add popover: "Try @Project, due:friday, !high"
Surface: in ActionItemsChrome quickAddPopover, show a 1-line hint below the TextField.

2-4 — Keyboard property shortcuts in list:
In ActionItemsListView.swift, find the .onKeyPress block (around line 135).
Add handlers for (only when a task row is focused/selected):
  - "p": cycle priority for the focused task (open → medium → high → urgent → low → open)
  - "d": open a small inline date-entry TextField overlay anchored below the row (parse via TaskQuickAddParser date logic from 2-3)
  - "e": open a small popover with the estimate picker (1,2,3,5,8,13 buttons)
  - "m": open a Menu listing all projects for move-to
  - All of these should work with the single focusedTaskID state

2-5 — Type-ahead date field:
Create a new view: DateTypeAheadField(date: Binding<Date?>, onCommit: () -> Void).
It renders a TextField. On change, run NSDataDetector for date recognition + the quick-add shorthands from 2-3.
Show parsed result as a small green chip below the field.
Show a small calendar icon button next to the field that opens the graphical DatePicker as a fallback.
Replace DatePicker(.graphical) popover in TaskRowView.dueChip and TaskPageView.dateButton with DateTypeAheadField.

2-6 — ⌘-click / shift-click multi-select:
In ActionItemsListView, add @State var taskSelection: Set<String> = [].
On each row's .contentShape(Rectangle()).onTapGesture:
  - Normal tap: existing behavior (expand/open)
  - .command modifier: taskSelection.insert(item.id) (or remove if already selected)
  - .shift modifier: range-select from last selected to this row
When taskSelection is non-empty, show a bulk action bar fixed at the bottom of the list pane:
  Buttons: "Mark Done", "Set Priority ▾", "Move to Project ▾", "Delete" (destructive, with count)
  Also show: "✕ Clear selection" button
Use .onTapGesture { } with modifiers parameter (SwiftUI 5.9+).

2-7 — Compact priority dot:
In TaskRowView.mainRow, replace the priorityPicker capsule with:
  Circle().fill(priorityColor).frame(width: 10, height: 10)
  .help(item.priority.label)
  .contextMenu { ForEach(ActionItem.Priority.allCases) { p in Button(p.label) { onPriority(p) } } }
Full capsule with text label stays in the expanded detailEditor and in TaskPageView.

2-8 — Hide unused sync buttons:
In TaskRowView.syncButtons (the trailing Linear/Notion buttons), add a condition:
Only show if: item.source == "linear" (has Linear URL) OR item.source == "notion" (has Notion URL) OR (app-level Linear API key is set AND item.projectID's project has a linearProjectID) OR (app-level Notion key is set AND project has notionDatabaseID).
For tasks where none of these are true, render Color.clear.frame(width: 0) instead.

Run swift build -c release. Ask to push.
```

---

## PHASE 3 — Navigation & Structure
*Requires Phase 0 (A0-2, A0-3) to be complete first.*

```
Read ~/MeetingScribeRefactor/audit/master-plan.md (Phase 3) and:
- Sources/MeetingScribe/UI/ActionItemsSidebar.swift (full)
- Sources/MeetingScribe/UI/ActionItemsChrome.swift (projectPane area)
- Sources/MeetingScribe/UI/WorkspaceRouter.swift
- Sources/MeetingScribe/ActionItems/TaskQuery.swift

Implement in order (3-3 first, it unlocks others):

3-3 — TaskQuery.Scope.initiative:
In TaskQuery.swift, add case initiative(String) to Scope enum.
In TaskQueryEngine, resolve it: expand to anyProjects(store.projects.filter { $0.initiativeID == id }.map(\.id)).

3-9 — Hide archived (if P0-4 not done): see P0-4 above.

3-6 — Clickable breadcrumb:
Create BreadcrumbBar view: takes [BreadcrumbItem] (label + action closure).
In TaskPageView.breadcrumbBar, replace the current single "< Tasks" back button with BreadcrumbBar showing:
  [Context name] > [Initiative name] > [Project name] > (current task title is the page heading, not in breadcrumb)
  Each segment is a tappable Button that routes via TasksRoute.
In the project pane header (ActionItemsChrome.projectPane), add the same breadcrumb for: [Context] > [Initiative] > [Project].
Segments are omitted if not applicable (e.g., project with no initiative shows just project name).

3-2 — Initiative roll-up view:
When env.route == .initiative(id) (requires A0-2/A0-3), the content pane shows:
  Top section (compressed, ~200pt): the existing initiative page (name, body, project grid)
  Divider with "Tasks" eyebrow label
  Bottom section: ActionItemsListView scoped to TaskQuery(scope: .initiative(id), filters: .init(includeCompleted: false))
  Quick-add bar above the list: a TextField "Add task…" that (on commit) creates a task and (if initiative has multiple projects) shows a project picker sheet; if only one project, assigns directly.
  Progress bar below initiative title: completion(forInitiative: id) from ActionItemStore.

3-4 — Sidebar zone separation:
Split ProjectRail's ScrollView into two labeled zones:
  Zone 1 "SMART VIEWS": Home, Today, Triage, All tasks, My Tasks (placeholder for Phase 5), Unsorted, People, Waiting-on
  Zone 2 "MY WORK": Initiatives tree, Pages tree
  Separate the zones with: Text("MY WORK").font(NDS.tiny.weight(.semibold)).foregroundStyle(NDS.textTertiary).padding(...) and a subtle Divider.
  Keep Meeting Notes at the bottom of Zone 2, collapsed by default (already is).

3-5 — Initiative context menu expansion:
In ActionItemsSidebar.swift, find InitiativeNode.contextMenu (around line 648).
Add:
  - Rename: show an inline TextField under the node (same pattern as commitNew), commit sets store.renameInitiative(id, name:)
  - Archive/Unarchive: toggle initiative.status between .active and .archived (add store method)
  - Change icon: a small SF Symbol picker popover (grid of common symbols); store via store.setInitiativeIcon(id, icon:)
  - Assign context: a sub-menu listing all WorkspaceContexts; calls store.setInitiativeContext(id, contextID:)
  - Add drag handle: .draggable for reordering; update sortIndex on drop

3-7 — Pinned projects rail:
In AppSettings, add var pinnedProjectIDs: [String] = [] (persisted).
In ProjectRail, add a "PINNED" section at the very top (below context switcher, above Zone 1):
  - Only shown when pinnedProjectIDs is non-empty
  - Each pinned item: same style as railItem, with a pin icon and an "Unpin" right-click option
  - A "Pin to top" option in PageTreeNode and InitiativeNode context menus
  - Max 5 pinned items

3-8 — WorkspaceRouter history for Tasks:
In WorkspaceRouter.NavState (WorkspaceRouter.swift:81), add: var tasksRoute: TasksRoute? = nil
In goBack()/goForward(), restore env.route from the NavState snapshot.
In TasksEnvironment, observe route changes and push snapshots to the router's history stack.

3-10 — @SceneStorage nav state:
In ActionItemsView (or TasksEnvironment), persist route (as rawValue string) and selectedTaskID using @SceneStorage.
On appear: restore from @SceneStorage if present.

Run swift build -c release. Ask to push.
```

---

## PHASE 4 — Meeting → Tasks Integration

```
Read ~/MeetingScribeRefactor/audit/master-plan.md (Phase 4) and:
- Sources/MeetingScribe/UI/ActionItemsChrome.swift (TriageInboxView area)
- Sources/MeetingScribe/ActionItems/ActionItem.swift (meetingID, meetingTitle, isManual fields)
- Sources/MeetingScribe/UI/TaskPageView.swift (bodyEditor section)

Implement:

4-1 — Group triage by meeting:
In TriageInboxView (found in ActionItemsChrome.swift), refactor the flat ForEach:
  Group items by meetingID using Dictionary(grouping:).
  Render each group as a DisclosureGroup with a custom label:
    HStack: meeting title (bold) + date + attendee avatar stack (up to 3) + task count badge
  Group header trailing: two buttons:
    "Add all to project…" → Menu listing all projects; on select, calls store.setProject(id, projectID:) + store.confirmTriage(id) for each item in the group
    "Dismiss meeting" → calls store.discardTriage(id) for each item in the group, with undo via ToastCenter
  Within each group, keep individual TriageRow items with their own Add/Discard controls.

4-2 — Smart project suggestion in triage:
In TriageRow (wherever it is defined), compute:
  let suggestion = store.projects.max(by: { meetingFuzzyScore($0.name, item.meetingTitle) < meetingFuzzyScore($1.name, item.meetingTitle) })
  where meetingFuzzyScore is a simple function: count of shared words (case-insensitive) between project name and meeting title.
  If score > 0, render a "→ [ProjectName]?" chip before the "Add" button. Tapping the chip confirms the item to that project.
  If tapped again, opens the full project picker.

4-3 — "Insert meeting context" in task body:
In TaskPageView.bodyEditor, add a small toolbar above RichMarkdownEditor:
  Show this toolbar only when !item.isManual (i.e., the task came from a meeting).
  One button: "Insert meeting notes" (SF Symbol: calendar.badge.plus)
  On tap: load the meeting's summary from AppSettings.shared.storageDir/meetings/<meetingID>/summary.md (read as String).
  Append to noteDraft: "\n\n---\n**From:** \(item.meetingTitle)\n\n\(summaryContent.prefix(2000))"
  Schedule a save flush.

4-4 — Inline meeting peek panel:
Create MeetingPeekPanel: a popover/sheet that shows:
  - Meeting title (large, bold) + date + attendee names
  - "Summary" section: first 400 chars of summary.md, with "Show more" chevron
  - "Decisions" section: extracted from summary.md (look for lines starting with "Decision:" or "Decided:")
  - "Open full meeting →" button that fires router.openMeeting(meetingID)
  - Width: 380pt, shown as a .popover(isPresented:) anchored to the "From meeting" chip.
In TaskPageView.properties section, find the "From meeting" NotionPropertyRow button.
  Change the tap action from router.openMeeting to: meetingPeekShown = true
  Add .popover(isPresented: $meetingPeekShown) { MeetingPeekPanel(meetingID: item.meetingID, ...) }
Same in TriageRow where the meeting chip is shown.

4-5 — Meeting provenance strip:
In TaskPageView, above the properties block (after titleRow), add:
  if !item.isManual {
    HStack { Image(systemName: "calendar"); Text("From \(item.meetingTitle)"); Spacer(); Button("View") { meetingPeekShown = true } }
      .padding(10)
      .background(NDS.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      .overlay(alignment: .leading) { Rectangle().fill(NDS.brand).frame(width: 3) }
  }

4-6 — Source badge on cards and rows:
In HomeTasksBoard.card(_:), after the label color strips, add a small icon top-right:
  if !item.isManual: Image(systemName: "calendar.badge.checkmark").foregroundStyle(NDS.textTertiary).font(.caption2)
  else if item.source == "linear": Image(systemName: "l.square").foregroundStyle(NDS.brand).font(.caption2)
  else if item.source == "notion": Image(systemName: "n.square").foregroundStyle(.purple).font(.caption2)
In TaskRowView.mainRow sub-row HStack, add the same badge after the meeting title label.

4-7 — Triage status bridge in meeting summary:
Find MeetingSummaryTab.swift or equivalent. Find the section that shows action item count.
Replace plain count with:
  let triageCount = store.items.filter { $0.meetingID == meeting.id && $0.needsTriage }.count
  if triageCount > 0 {
    Button("\(triageCount) in Tasks inbox — review →") { route to triage inbox filtered to this meeting }
  } else {
    Label("All in Tasks ✓", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
  }

4-8 — Re-extract from empty state:
In TriageInboxView empty state (where it shows "No items waiting"), add:
  Button("Re-extract from past meetings") { manager.backfillActionItemsIfNeeded(force: true) }
  .buttonStyle(.bordered)

Run swift build -c release. Ask to push.
```

---

## PHASE 5 — Saved Views, Recurrence, & Power Features

```
Read ~/MeetingScribeRefactor/audit/master-plan.md (Phase 5) and:
- Sources/MeetingScribe/ActionItems/TaskQuery.swift
- Sources/MeetingScribe/ActionItems/ActionItemStore.swift
- Sources/MeetingScribe/UI/ActionItemsSidebar.swift
- Sources/MeetingScribe/ActionItems/ActionItem.swift (recurrence, seriesID fields)

Implement:

5-5 — Extended GroupBy (do this first, others depend on it):
In ActionItemsViewModel (or ActionItemsView's GroupBy enum), add cases:
  .owner, .label, .project, .initiative, .customSelect(propertyID: String)
In the filteredSorted() or equivalent grouping logic, handle each new case.
Add these options to the GroupBy picker in the toolbar (a Menu with all cases listed).
Store active GroupBy per-view in AppSettings under a key like "tasks.groupBy.\(routeKey)".

5-1 — Saved Views:
Create Sources/MeetingScribe/ActionItems/SavedTaskView.swift:
  struct SavedTaskView: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var icon: String? // SF Symbol
    var query: TaskQuery
    var sortIndex: Double?
    var isPinned: Bool = false
  }
Add to ActionItemStore: @Published private(set) var savedTaskViews: [SavedTaskView] = []
Persist to saved_task_views.json.
Add store methods: createSavedTaskView(name:icon:query:), updateSavedTaskView(_:), deleteSavedTaskView(_:).
Seed 3 built-in views (not deletable, isBuiltIn: Bool = false added to model):
  - "My Open Tasks": scope=.all, filters=.init(statuses: [.open, .inProgress], includeCompleted: false)
  - "Overdue": filters=.init(overdue: true, includeCompleted: false)
  - "Due This Week": filters=.init(dueWithinDays: 7, includeCompleted: false)
In ProjectRail Zone 1 (Phase 3-4 layout), add a "VIEWS" section showing all savedTaskViews as railItems.
In the TasksRoute enum, add: case savedView(String) — the String is the SavedTaskView.id.
In the main toolbar (when any filter is active), add a "Save view…" button that opens a small popover to name and confirm the current query as a new SavedTaskView.

5-3 — Recurrence series UI:
(a) In TaskRowView.mainRow sub-row, add after the subtask count:
  if item.recurrence != nil { Image(systemName: "repeat").font(.caption2).foregroundStyle(NDS.brand) }
Same in HomeTasksBoard.card.
(b) Add railItem("Recurring", icon: "repeat", id: "__recurring__") in ProjectRail Zone 1.
  When selected, show: TaskQuery(scope: .all, filters: .init(includeCompleted: false)) filtered post-query to only items where recurrence != nil.
(c) In TaskPageView.properties recurrence picker, when the user changes recurrence on a task that has a seriesID:
  Show a sheet: "Change recurrence for: This task only / This and all future tasks"
  If "all future": find all store.items where seriesID == item.seriesID && createdAt >= item.createdAt, apply the same recurrence change to each.
(d) In the recurrence picker Menu, add a "Custom…" option that opens a sheet with interval (Int) + frequency (daily/weekly/monthly) fields.

5-2 — My Tasks rail item:
Add railItem("My Tasks", icon: "person.fill", id: "__mytasks__") at top of Zone 1 (after Today, before Triage).
When selected, show a pane with 4 DisclosureGroup sections:
  - "Recently Assigned" (createdAt in last 7 days, sorted by createdAt desc, limit 20)
  - "Today" (dueDate == today or user has pinned via a new @AppStorage "tasks.pinnedToToday" Set<String>)
  - "Upcoming" (dueDate between tomorrow and 14 days from now)
  - "Later" (no dueDate or dueDate 15+ days out)
All sections filter to tasks where ownerPersonID == the logged-in user's Person record id (get from AppSettings.shared or PeopleStore).
Add a "Pin to Today" right-click option on any task row.

5-4 — Task templates:
Create Sources/MeetingScribe/ActionItems/TaskTemplate.swift:
  struct TaskTemplate: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var defaultTitle: String = ""
    var defaultPriority: ActionItem.Priority = .medium
    var defaultLabelIDs: [String] = []
    var defaultEstimate: Double? = nil
    var defaultSubtasks: [String] = []
    var defaultRecurrence: RecurrenceRule? = nil
    var contextID: String? = nil
    var projectID: String? = nil
  }
Add to ActionItemStore: @Published private(set) var taskTemplates: [TaskTemplate] = []
Persist to task_templates.json.
Add store method: createTask(fromTemplate: TaskTemplate, projectID: String?) -> ActionItem
  (pre-fills title from template.defaultTitle, priority, labels, creates subtasks, sets recurrence)
In the project header's + button Menu, add "New task from template…" → sub-Menu listing all templates.
In TaskPageView breadcrumb overflow Menu (the "..." button), add "Save as template" → popover to name the template, then calls store.createTemplate(from: item).

5-6 — Initiative targetDate + expanded Project.Status:
In Initiative.swift, add: var targetDate: Date? (decodeIfPresent, nil default)
In Project.swift, change Status enum to: case active, onHold, completed, archived
  Add migration: if decoded status == nil → .active
Add store methods: setInitiativeTargetDate(_:date:), setProjectStatus(_:status:)
In TaskPageView (when showing a project), show the targetDate as a "Target" property row.

5-7 — Field-level change events:
In TaskChangeLog.swift / TaskChangeEvent struct, add:
  var field: String? = nil
  var oldValue: String? = nil  // JSON-encoded
  var newValue: String? = nil  // JSON-encoded
In ActionItemStore.update(_:mutate:):
  Before applying mutation, capture a snapshot of the item.
  After applying mutation, diff against snapshot field by field.
  For each changed field, append a TaskChangeEvent with field=fieldName, oldValue=JSON(old), newValue=JSON(new).
Add func undoLastChange() to ActionItemStore:
  Read the last event with a non-nil field.
  Parse oldValue and restore that field via the appropriate store setter.
  Mark the event as undone (add var undone: Bool = false to event).
Wire ⌘Z to ActionItemStore.undoLastChange() in ActionItemsView.

Run swift build -c release after each major item. Ask to push.
```

---

## PHASE 6 — Optional / Hardening

```
These are independent improvements. Pick any you want to implement.
Read master-plan.md Phase 6 section for full details.

Priorities within Phase 6 (highest ROI first):
1. 6-4: Write-ahead backup in TaskPersistenceCoordinator.writeNow (data safety, S effort)
2. 6-5: Initiative completion arc in sidebar (uses existing store.progressForInitiative, S effort)
3. 6-3: Property drawer replacing in-place row expand (L effort, high UX impact)
4. 6-7: NavigationSplitView migration (requires Phase 0 complete, M effort)
5. 6-6: Keyboard sidebar navigation (M effort, nice-to-have)
6. 6-1: Sprint/Cycle primitive (L effort, for power users)
7. 6-2: Calendar drag-to-reschedule (M effort, nice polish)
```

---

## RESCUE PROMPT (When Stuck)

```
I'm implementing [ITEM-ID] from ~/MeetingScribeRefactor/audit/master-plan.md.
I'm stuck because: [describe the problem].
The relevant files are: [list files].
The specific code I'm working on is at [file:line].
Please read those files and suggest a minimal fix that doesn't break existing behavior.
Do NOT refactor anything outside the scope of [ITEM-ID].
```

---

## PR DESCRIPTION TEMPLATE

```
## What
[1–2 sentence summary of what changed]

## Audit items implemented
- ITEM-ID: description

## Testing
- [ ] swift build -c release passes
- [ ] Existing task rows still render correctly
- [ ] No regressions on: task creation, triage inbox, sync buttons, TaskPageView
- [ ] Tested with 0 tasks, 1 task, and 50+ tasks
- [ ] Tested with no initiatives and with multiple initiatives

## Notes
[Any caveats, future work, or deliberate scope exclusions]
```
