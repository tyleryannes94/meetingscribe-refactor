# UI Architecture & Refactoring Complexity Findings — MeetingScribe Tasks Audit

**Agent ID:** E2 | **Lens:** SwiftUI view architecture, state management, refactoring cost

---

## Top existing friction points (file:line citations)

### 1. ViewModel exists but is never wired in — the view still owns all state

`ActionItemsViewModel` (`ActionItemsViewModel.swift:15`) was extracted in "Batch 7 (audit 6.1)" per its own docstring, but it is **never instantiated**. No file in the UI directory contains `ActionItemsViewModel()` or `@StateObject var vm: ActionItemsViewModel`. The result: `ActionItemsView` still carries **29 `@State` vars** (lines 13–60) alongside `@ObservedObject var store` and two `@EnvironmentObject` injections. The extraction is a ghost: the ViewModel has a full `filteredSorted()` and `groupItems()` implementation that is never called.

### 2. Filtering logic is duplicated in three places

- `ActionItemsViewModel.filteredSorted()` — `ActionItemsViewModel.swift:113–173`
- `ActionItemsListView` extension `var filtered` — `ActionItemsListView.swift:260–314`
- `ActionItemsListView` extension `var tableSorted` — `ActionItemsTableView.swift:35–51`

All three implement status/priority/date filtering independently with different edge-case behavior (e.g. `thisWeek` logic differs between ViewModel and ListViewExt). `ownerScope` filtering (`.mine`/`.delegated`) exists only in the ListViewExt version and is absent from the ViewModel.

### 3. Enum definitions are fully duplicated between View and ViewModel

`ViewMode`, `Filter`, `GroupBy`, and `TableSort` are each defined **twice** — once as nested types in `ActionItemsView` (lines 62–149) and again in `ActionItemsViewModel` (lines 19–79). The ViewModel's `GroupBy` has different cases (`project`, `owner`, `dueDay`) than the View's (`meeting`, `status`, `dueDate`) — they have **silently diverged** with no compiler error.

### 4. Three-binding prop drilling through every sidebar node

`ProjectRail`, `PageTreeNode`, and `InitiativeNode` each receive:
```
@Binding var selectedProjectID: String?
@Binding var selectedMeetingID: String?
@Binding var selectedInitiativeID: String?
```
(`ActionItemsSidebar.swift:13–15`, `489–492`, `593–595`). A tap in any leaf node must reset all three to correctly clear prior selection. This is error-prone — `InitiativeNode`'s tap gesture at line 643 correctly clears both, but `PageTreeNode`'s `onTapGesture` at line 562 only sets `selectedProjectID` without clearing `selectedInitiativeID`, so a tap on a project while an initiative is selected leaves the initiative header highlighted.

### 5. Sentinel-string navigation is a hidden state machine

`selectedProjectID` doubles as a navigation router via sentinel strings: `"__home__"`, `"__triage__"`, `"__none__"`, `"__person__<id>"`, `"__waiting__"` (lines 76–88 of `ActionItemsView.swift`). The routing switch in `ActionItemsView.body` (lines 175–201) is a long `if-else` chain that evaluates `selectedTaskID`, `selectedInitiativeID`, `selectedProjectID`, and `selectedMeetingID` in a fragile priority order. Any new surface added to the left rail requires extending this chain in exactly the right position.

### 6. `ActionItemsChrome.swift` is an extension on `ActionItemsView` that directly mutates view state

`ActionItemsChrome.swift` is a 625-line `extension ActionItemsView` containing the dashboard, toolbar, project page, and push logic. Because Swift extensions on a struct type share the struct's stored properties, functions like `commitQuickAdd()` (line 463) and `addTask()` (line 508) mutate `viewMode`, `filter`, and `selectedTaskID` directly without any intermediary — making it impossible to unit-test this logic and impossible to extract individual panels into standalone views without carrying the entire view's state.

### 7. The `row(for:)` call site passes 19 closure parameters

`ActionItemsListView.swift:419–465` constructs each `ActionItemRow` with 19 labeled closures (`onStatus`, `onPriority`, `onDue`, `onStart`, `onTitle`, `onOwner`, `onNotes`, `onProject`, `onCreateProject`, `onSection`, `onToggleLabel`, `onCreateLabel`, `onAddSubtask`, `onToggleSubtask`, `onDeleteSubtask`, `onDelete`, `onPush`, `onOpenNotion`, `onPushLinear`, `onOpenLinear`). This is the deepest prop-drilling site in the feature. Adding any new row capability requires threading a new closure through the call site.

### 8. `NavigationSplitView` is not used anywhere in the Tasks feature

The entire Tasks UI is a hand-rolled `HStack(spacing: 0)` with a custom drag-resizable divider (`ActionItemsView.swift:152–170`). macOS 14's `NavigationSplitView` provides sidebar collapse, split-pane persistence, full-screen layout adaptation, and accessibility for free. The hand-rolled version reproduces the resize behavior but loses all sidebar-collapse affordances and VoiceOver landmark semantics.

---

## Existing items worth endorsing / prioritizing

- **`ProjectRail` as a standalone struct** (`ActionItemsSidebar.swift:7`): The decision to keep `ProjectRail` as its own `View` (not an extension) is correct and should be the template for the full refactor. The sidebar subtypes (`PageTreeNode`, `InitiativeNode`, `WaitingRow`, `SidebarRow`) are well-factored small views.
- **`TaskPageView` as a standalone struct** (`TaskPageView.swift:8`): This is already isolated from `ActionItemsView`, takes only `store`, `itemID`, and callbacks, and can be moved to any navigation container without changes.
- **`WorkspaceRouter.pendingTaskID`** (`WorkspaceRouter.swift:65`): The "mailbox" pattern for cross-tab task deep-linking is clean and should be preserved and extended to cover initiative/project deep-links from future home page widgets.
- **`ActionItemsViewModel.filteredSorted()` and `groupItems()`**: These implementations are correct and well-factored. They should be the authoritative implementations once the ViewModel is actually wired in.
- **`ToastCenter` undo integration** in bulk operations and delete: already implemented and worth keeping in any rebuild.

---

## NET-NEW recommendations

### E2-1: Complete the ViewModel migration (the half-done extraction)
- **What:** Instantiate `ActionItemsViewModel` as `@StateObject` in `ActionItemsView`. Move all 29 `@State` vars into the ViewModel. Delete the duplicate enum definitions from `ActionItemsView`. Unify `GroupBy` (merge `meeting`, `status`, `project`, `owner`, `dueDay` into one canonical enum in the ViewModel). Delete `var filtered` from `ActionItemsListView.swift` and replace all call sites with `vm.filteredSorted(items: store.items)`.
- **Why:** The ViewModel already exists and has the right shape. Right now the codebase maintains two diverging implementations of the same logic. This is the single highest-leverage cleanup: once the ViewModel is the source of truth, every per-view file (`ActionItemsListView`, `ActionItemsTableView`, `ActionItemsBoardView`) can consume `vm.filteredSorted()` and stop reimplementing it.
- **Effort:** M (1–2 days) | **Impact:** High
- **Deps:** none

### E2-2: Replace sentinel-string routing with a typed `TasksRoute` enum
- **What:** Introduce:
  ```swift
  enum TasksRoute: Hashable {
      case home
      case allTasks
      case triage
      case project(String)
      case noProject
      case person(String)
      case waiting
      case initiative(String)
      case meeting(String)
      case task(String)
  }
  ```
  Move the `if-else` dispatch chain in `ActionItemsView.body` (lines 175–201) to a `switch` over a single `@State var route: TasksRoute`. The ViewModel's `selectedProjectID` string is then a derived property for sidebar badge logic, not the source of truth.
- **Why:** The current sentinel system is invisible to the compiler. Adding a new route (e.g. a "Today" focus view) requires touching the `if-else` chain in exactly the right order, plus adding a new sentinel constant. A typed enum makes invalid states unrepresentable and lets each sub-view be navigated to via `NavigationStack` path appending in the future.
- **Effort:** M | **Impact:** High
- **Deps:** E2-1

### E2-3: Migrate Tasks shell to `NavigationSplitView`
- **What:** Replace the `HStack + manual drag divider` in `ActionItemsView.body` with:
  ```swift
  NavigationSplitView(columnVisibility: $columnVisibility) {
      ProjectRail(...)
  } detail: {
      TasksDetailRouter(route: vm.route, ...)
  }
  ```
  Use `.navigationSplitViewColumnWidth(min:ideal:max:)` for the sidebar.
- **Why:** `NavigationSplitView` gives sidebar collapse (⌘-Control-S), correct sidebar-to-detail focus transitions, full-screen layout handling, and VoiceOver landmarks for free. The hand-rolled drag resizer (`ActionItemsView.swift:159–172`) is good UX that can be preserved with `.navigationSplitViewColumnWidth`. The `AppStorage("tasks.railWidth")` persistence can be passed as `ideal:` width so user preference is preserved.
- **Effort:** M | **Impact:** Med (UX polish + accessibility)
- **Deps:** E2-2

### E2-4: Introduce a `TasksEnvironment` to eliminate the 3-binding prop-drilling into sidebar
- **What:** Define:
  ```swift
  @Observable final class TasksEnvironment {
      var route: TasksRoute = .home
      var store: ActionItemStore
  }
  ```
  Inject via `.environment(tasksEnv)`. `ProjectRail`, `PageTreeNode`, `InitiativeNode` read `@Environment(TasksEnvironment.self)` instead of receiving three `@Binding` parameters. This also fixes the bug where `PageTreeNode`'s `onTapGesture` (`ActionItemsSidebar.swift:562`) fails to clear `selectedInitiativeID`.
- **Why:** The three-binding pattern forces every sidebar node to know about the full selection model. With a shared environment object, a `PageTreeNode` simply sets `env.route = .project(id)` and the old route is automatically displaced.
- **Effort:** S–M | **Impact:** High (bug fix + cleaner architecture)
- **Deps:** E2-2

### E2-5: Extract `ActionItemRow` mutation into a `TaskMutator` protocol / thin wrapper
- **What:** Replace the 19-closure `row(for:)` call site (`ActionItemsListView.swift:419–465`) with a single `store`-backed `TaskMutator` struct that conforms to a protocol defining all mutation operations. `ActionItemRow` takes one `mutator: TaskMutator` parameter.
- **Why:** Every new task capability (e.g. adding recurrence editing, sprint assignment, or time-tracking from a row) requires threading a new closure through the call site. A mutator wrapper reduces the row's init to 5–6 stable parameters and lets the row's conformance grow without changing call sites.
- **Effort:** S | **Impact:** Med
- **Deps:** none (independent)

### E2-6: Add a `@SceneStorage`-backed `TasksNavState` to survive window restores
- **What:** Use `@SceneStorage` to persist `route` (as a rawValue string), `viewMode`, `railWidth`, and `selectedTaskID` across app restarts and multiple windows. Currently `@AppStorage("tasks.railWidth")` is the only persisted Tasks UI state; everything else resets on relaunch.
- **Why:** If the user was editing a task when they quit, they have to re-navigate from scratch on relaunch. Notion and Linear both restore the last open document on relaunch. This is a 1-day win with high perceived quality impact.
- **Effort:** S | **Impact:** Med
- **Deps:** E2-2 (needs typed route to serialize)

---

## Top 3 picks

1. **E2-1** — Wire in the already-written ViewModel. It eliminates duplicate filtering logic across three files, kills the enum duplication, and is the prerequisite for all other refactoring. This is work that was started and abandoned mid-PR.
2. **E2-4** — `TasksEnvironment` to kill the three-binding prop drill and simultaneously fix the selection-clearing bug in `PageTreeNode` where tapping a project while an initiative is selected leaves the initiative highlighted.
3. **E2-2** — Typed `TasksRoute` enum to replace the sentinel-string if-else chain. The current string-switch dispatch is the main reason new surfaces (a "Today" focus, a work/personal context switcher) are hard to add safely.
