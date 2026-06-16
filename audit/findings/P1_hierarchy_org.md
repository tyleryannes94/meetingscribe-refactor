# Hierarchy & Organization — MeetingScribe Tasks Audit
**Agent ID prefix: P1-**
**Lens: Initiative → Project → Task structure, Work vs Personal separation, Sections, Sidebar surfacing**

---

## Top existing friction points (file:line citations)

### 1. Initiative is a dead-end — you can't create tasks from it
`InitiativePage` (ActionItemsProjectPage.swift:297–369) shows a title, a markdown body, and a list of child projects. Clicking a project navigates away. There is no way to create a task directly under an initiative, view all tasks across all its projects in one scroll, or see a roll-up status board. An initiative page today is purely an index card, not a workspace.

The `TaskQuery.Scope` enum (TaskQuery.swift:15–25) has `anyProjects(Set<String>)` which is exactly the right primitive for this, but nothing in the UI ever constructs that scope from an initiative selection. The `completion(forInitiative:)` store method (ActionItemStore.swift:150–154) computes done/total — it is never rendered on the `InitiativePage` beyond a single "N open" chip (ActionItemsProjectPage.swift:318).

### 2. No workspace-level context flag on a task — "Work" and "Personal" bleed together
`ActionItem` (ActionItem.swift:13–178) has `projectID`, `sectionID`, `labelIDs`, and `initiativeID` on its parent `Project` — but **no first-class context/workspace field**. A user who wants all work tasks to stay invisible when they're in personal mode has no affordance for that. Labels are the only workaround, but they are not hierarchical and they are not enforced at any scope boundary.

`Initiative.swift:6–24` carries no `type` or `context` discriminator — there is no "this is my Work space" concept at the model layer.

### 3. "New page" creates a standalone page, not a project inside an initiative
`commitNew()` (ActionItemsSidebar.swift:175–184) calls `store.createProject(name:)` with no `initiativeID` — it always lands in the "Pages" section. The hover `+` button on an initiative node (ActionItemsSidebar.swift:623–628) creates a project and calls `setProjectInitiative` as a second step, but creates it with name "Untitled" and immediately navigates away. There is no inline-name prompt on initiative-scoped project creation, unlike the `TextField` on standalone page creation (ActionItemsSidebar.swift:115–119). Net result: projects added from initiative rows are always named "Untitled" and require a rename.

### 4. Initiative node context menu is missing rename and archive actions
`InitiativeNode.contextMenu` (ActionItemsSidebar.swift:648–656) only offers "Delete initiative". Asana, Linear, and Notion all provide rename, archive/pause, change icon, and "move project here" from context menus. Rename is only possible by navigating to the initiative page and editing the title field — two more clicks than necessary.

### 5. Sections exist in the store but surfacing is unclear
`ProjectSection` (Project.swift:86–91) and `createSection` (ActionItemStore.swift:603–610) are fully implemented, including undo (ActionItemStore.swift:1130–1140). But `ActionItemsListView` is not audited here — the concern is that sections have no sidebar entry; there is no visual signal in the rail that a project has N sections. Users discover sections only by opening a project. This makes section-as-organizer invisible.

### 6. `standaloneTopProjects()` and initiative projects live in separate sidebar buckets with no way to move between them via drag
The rail shows "Initiatives" and then a separate "Pages" section (ActionItemsSidebar.swift:98–119). A project is either in one or the other. To re-home a standalone project into an initiative, users must use a context menu or programmatic call — there is no drag-and-drop reparenting in the sidebar.

### 7. TaskQuery has no `initiative` scope variant
`TaskQuery.Scope` (TaskQuery.swift:15–25) has `project`, `noProject`, `anyProjects`, `person`, `meeting` — but no `initiative`. The engine caller must resolve initiative→projectIDs manually each time (ActionItemStore.swift:150–154 does this for the badge count, but nothing builds a query from it for the main list). This means filtered list views can't be scoped to an initiative natively.

---

## Existing items worth endorsing / prioritizing

- **`completion(forInitiative:)` (ActionItemStore.swift:149–154)** — the roll-up math is already written. Just needs to be wired into a visual progress bar on the initiative page and sidebar node.
- **`anyProjects` scope in TaskQuery** — excellent groundwork; just needs a calling convention from the initiative selection path.
- **Undo for `deleteInitiativeWithUndo`, `deleteSectionWithUndo`, `deleteProjectKeepingChildrenWithUndo`** — all three are correct and safe; keep them and surface them consistently.
- **`meetingIDs` on `Project`** — linking a meeting to a project is the right model for meeting→task provenance; should be surfaced visually.

---

## NET-NEW recommendations

### P1-1: Workspace concept — first-class context (Work / Personal / Other) above Initiatives
- **What:** Add a `WorkspaceContext: String` (or an enum `context: ContextKind` where `ContextKind` is `work | personal | custom`) to both `Initiative` and the standalone `Project`. Add a top-level switcher in the sidebar header — a segmented control or tab strip that filters the entire rail to one context. When "Personal" is selected, all work initiatives, projects, and tasks vanish from every list view, triage inbox, and badge counts. Tasks created in Personal context inherit `context: .personal`. A new `TaskQuery.Scope` case `context(String)` enables filtered queries.
- **Why:** The #1 user complaint is work/personal bleed. This is the root fix. Labels do not solve it because they do not enforce scope boundaries — they are display-only. A workspace-level context switch changes what is *visible*, not just what is *colored*.
- **Effort:** M (2 days) | **Impact:** High
- **Deps:** none (additive field; old JSON decodes nil → defaults to `.work`)

### P1-2: Initiative-scoped task roll-up view with inline task creation
- **What:** When a user selects an initiative in the sidebar, the right pane currently shows only the project index (ActionItemsProjectPage.swift:297). Replace this with a two-panel layout: top half = existing project index (compressed); bottom half = a `ActionItemsListView` scoped to `TaskQuery(scope: .anyProjects(projectIDs), filters: .init(includeCompleted: false))`. Add a quick-add bar at the top of the list that creates a task in the initiative's first project (or prompts to pick a project if multiple exist). Also render the `completion(forInitiative:)` result as a progress bar beneath the initiative title.
- **Why:** Initiatives are useless if you can't act on them. Currently you have to click into each project to see its tasks — 3–4 clicks per project. The `anyProjects` scope and `completion(forInitiative:)` methods already exist; this is pure UI wiring.
- **Effort:** M (1–2 days) | **Impact:** High
- **Deps:** TaskQuery.Scope (already has `anyProjects`)

### P1-3: Initiative context menu — rename, archive, change icon, set context
- **What:** Expand `InitiativeNode.contextMenu` (ActionItemsSidebar.swift:648–656) to include: inline rename (popover text field), archive/unarchive (toggle `initiative.status`), change icon (SF Symbol picker), assign context (Work / Personal). Mirror the same actions on the initiative page header. Add a "Reorder" drag handle to `InitiativeNode` so initiatives can be sorted in the sidebar without editing sortIndex programmatically.
- **Why:** Right now right-clicking an initiative shows only "Delete" — the most destructive action is the only action. This inverts the intended behavior. Users will avoid right-clicking at all or accidentally delete things.
- **Effort:** S (< 1 day) | **Impact:** Med
- **Deps:** P1-1 (for context assignment)

### P1-4: Sidebar section badge — show section count on project rows
- **What:** In `PageTreeNode.row` (ActionItemsSidebar.swift:521–574), add a secondary line beneath the project name when `store.sections(forProject: project.id).count > 0`: "3 sections". Alternatively, render a small pill badge. When the user hovers, show "Add section" alongside "Add sub-page".
- **Why:** Sections are invisible from the sidebar. A user building a project with Sprint 1 / Sprint 2 / Backlog sections has no way to know those sections exist without navigating into the project. The store method `sections(forProject:)` (ActionItemStore.swift:599–601) already returns the data.
- **Effort:** S (< 1 day) | **Impact:** Med
- **Deps:** none

### P1-5: `TaskQuery.Scope.initiative(String)` — first-class initiative scope
- **What:** Add `case initiative(String)` to `TaskQuery.Scope` (TaskQuery.swift:15). In `TaskQueryEngine`, resolve it to `anyProjects(store.projects(forInitiative: initiativeID).map(\.id))`. This makes initiative-scoped queries a one-liner at every call site instead of requiring callers to resolve project IDs manually.
- **Why:** Today `completion(forInitiative:)` and the open-count badge each inline their own project-ID resolution (ActionItemStore.swift:150–154, 678–681). They will drift. One `Scope.initiative` case removes the duplication and opens the door to saved views scoped to an initiative.
- **Effort:** S (< 1 day) | **Impact:** Med
- **Deps:** none (pure additive to an enum; existing callers unchanged)

### P1-6: Inline project name prompt on initiative `+` hover button
- **What:** In `InitiativeNode.body` (ActionItemsSidebar.swift:604–672), replace the hover `+` action (ActionItemsSidebar.swift:623–628) that creates an "Untitled" project and navigates away with the same `TextField` + `onCommit` pattern used by `commitNew()` (ActionItemsSidebar.swift:175–184). Show the text field indented under the initiative node, commit creates the project with the given name and the initiative already set.
- **Why:** Every project added from the initiative sidebar row starts as "Untitled" and requires a rename. This is 100% friction, zero added UX benefit.
- **Effort:** S (< 1 day) | **Impact:** Med
- **Deps:** none

### P1-7: Archived initiative / project collapse — hide from default sidebar view
- **What:** Both `Initiative.Status` (Initiative.swift:19–23) and `Project.Status` (Project.swift:42–46) have an `archived` case, but `sortedInitiatives()` (ActionItemStore.swift:632–638) and `standaloneTopProjects()` (ActionItemStore.swift:671–673) return archived items without filtering. The sidebar renders archived initiatives alongside active ones with no visual distinction. Add a filter: by default hide archived; add a "Show archived" toggle at the bottom of the sidebar. Add a faded style to archived items in the filtered list.
- **Why:** A user with 10 completed quarterly initiatives will have a cluttered sidebar that grows forever. This is the most common complaint about Asana's sidebar from power users.
- **Effort:** S (< 1 day) | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **P1-1 (Workspace Context)** — Work/Personal bleed is Tyler's explicit #5 goal and there is zero model support for it today. Every other org improvement is downstream of this.
2. **P1-2 (Initiative roll-up task view)** — Initiatives are currently read-only index cards. This converts them into the highest-leverage navigation layer in the app with ~1.5 days of UI wiring on top of already-working store methods.
3. **P1-5 (TaskQuery initiative scope)** — Smallest effort, highest structural leverage: eliminates duplicated project-ID resolution in 4+ places and unlocks saved views scoped to an initiative.
