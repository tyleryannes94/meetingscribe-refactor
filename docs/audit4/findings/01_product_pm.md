# 01 — Projects/Tasks Feature, Product/PM Audit

**Lens:** I'm assessing whether MeetingScribe's Projects/Tasks feature could become the user's *primary* task & project tracker — the one that replaces Notion, Linear, Asana, and Things. That means judging feature completeness against those four products' table stakes (recurring work, dependencies, milestones, custom fields, saved views, reminders, my-work, reporting, import/export) AND identifying the one angle none of them have: tasks that are auto-extracted from the user's own meetings. Every finding below is grounded in what the code does today versus what a daily-driver tracker needs.

## Verified already-built (do NOT re-propose)

- **Three-tier hierarchy** Initiative › Project › Task, all persisted: `Initiative.swift`, `Project.swift` (`parentID` nesting + `initiativeID`), `ActionItem.projectID` (`ActionItem.swift:37`). Project rollups exist (`ActionItemStore.openCount(forInitiative:)` `ActionItemStore.swift:409`).
- **Core task fields:** status (open/inProgress/completed), priority (low→urgent), `dueDate`, `startDate`, `labelIDs`, `subtasks`, `sectionID`, `sortIndex`, `owner` + hard `ownerPersonID` link (`ActionItem.swift:22-62`).
- **Three view modes** list / table / board (kanban), with group-by, status/priority/this-week/overdue filters, search (`ActionItemsViewModel.swift:113-262`, `ActionItemsChrome.swift`).
- **Asana-style sections** within a project (`ProjectSection`, `ActionItemStore.swift:330-357`); **Trello/Notion colored labels** (`TaskLabel`, `ActionItemStore.swift:290-326`); **nested subtasks/checklists** (`ActionItemStore.swift:261-286`).
- **Notion-style task page** with markdown body, icon, properties panel, breadcrumb (`TaskPageView.swift`); **project pages** with embedded task databases (`ActionItemsProjectPage.swift`, `pageHasDatabase` `ActionItemStore.swift:619`).
- **Bidirectional external sync:** import + dedup from Linear (GraphQL) and Notion (DB query) via `mergeExternal` (`ActionItemStore.swift:188`, `TaskSyncService.swift`); push single tasks to Notion (`NotionActionItemService`) and create Linear issues (`createLinearIssue` + `pushToLinear` `ActionItemsChrome.swift:484`).
- **AI extraction from meetings** with owner/due parsing and "is this mine?" filtering (`ActionItemExtractor.swift`); re-extract reconciliation that preserves user edits (`reconcileExtracted` `ActionItemStore.swift:442`).
- **Multi-select + bulk status/priority/delete bar** in the LIST view (`ActionItemsListView.swift:142-184`); resizable persisted sidebar (`ActionItemsView.swift:42-43`); ⌥⌘N quick-add (`ActionItemsChrome.swift:353`); a Tasks **dashboard** landing with open/pages/recent-notes sections (`ActionItemsChrome.swift:6-124`).
- **Dashboards/Today surfaces** that read the store: `ActionItemsWidget`, `TodayView`, `StandupDigest`, `WeeklyRecap`, `NeedsAttentionWidget`.

---

## Improvements

### PM-1 — Recurring tasks
- **Problem:** No way to make a task repeat (daily standup, weekly report, monthly invoice). Things, Asana, and Notion all treat recurrence as table stakes; without it the user keeps recreating the same chores by hand and will keep a second app for them.
- **Evidence:** Missing entirely. `ActionItem` has no recurrence field (`ActionItem.swift:13-65`); grep for `recurr|repeat|cadence|RRule` across `Sources/` returns zero task-related hits.
- **Recommendation:** Add `var recurrence: Recurrence?` (rule: daily/weekly/monthly/custom interval + optional weekday set + end condition). On completing a recurring task, spawn the next instance with the rolled-forward due/start date. Surface a "Repeat" row in `TaskPageView` properties.
- **Impact:** Removes the single biggest reason a Things/Todoist user keeps a separate app; high daily-retention driver.
- **Effort:** M. **Deps:** none (additive optional field decodes against old JSON).

### PM-2 — Task dependencies (blocked-by / blocks)
- **Problem:** No relationships between tasks. Linear and Asana let you mark "blocked by" so work sequences and overdue-blockers surface. The hierarchy is purely containment (project/section/subtask), not sequencing.
- **Evidence:** Missing entirely. No `dependsOn`/`blockedBy` on `ActionItem` (`ActionItem.swift`); subtasks are leaf checklist items only (`Subtask` `ActionItem.swift:130`).
- **Recommendation:** Add `var blockedByIDs: [String]?` (+ derived `blocks`). Show a "Blocked" chip and gray/disable start when an upstream task is incomplete; add a dependency picker in `TaskPageView`. Optionally map to Linear's relations on push.
- **Impact:** Unlocks real project planning; a Linear replacement is impossible without it.
- **Effort:** M. **Deps:** PM-15 (entity picker reuse helps).

### PM-3 — Milestones / goals with target dates
- **Problem:** Initiatives and Projects have no target date, no progress %, no milestone concept. Linear "Cycles/Milestones", Asana "Milestones", and Notion goal DBs all let you track "are we on track for the launch?" Here a project is just a name + body.
- **Evidence:** `Project` has `status` (active/archived) but no `targetDate`/`startDate`/`milestones` (`Project.swift:9-34`); `Initiative` likewise (`Initiative.swift:6-17`).
- **Recommendation:** Add `targetDate`/`startDate` to `Project` and `Initiative`, plus an optional lightweight `Milestone` (name, date, taskIDs). Render a progress bar (done/total) and "due in N days" on project/initiative headers; the dashboard already computes done/total counts (`ActionItemsChrome.swift:268-294`) so the data is there.
- **Impact:** Turns the project tier from a folder into a goal tracker — core to displacing Notion/Asana for planning.
- **Effort:** M. **Deps:** none.

### PM-4 — Estimates & time tracking
- **Problem:** No effort estimate, no time logged. Linear (points/estimate) and Asana (time tracking) both have this; it powers capacity and reporting.
- **Evidence:** Missing entirely — no `estimate`/`timeSpent` on `ActionItem` (`ActionItem.swift`). Linear's `estimate` field isn't even read during import (`TaskSyncService.linearTask` `TaskSyncService.swift:88-103`).
- **Recommendation:** Add `var estimate: Double?` (points or hours, user-chosen unit in settings) and `var timeSpentMinutes: Int?` with a simple start/stop timer + manual log on the task page. Pull Linear's `estimate` in the import query.
- **Impact:** Enables workload/capacity (PM-5) and velocity reporting (PM-12); needed to retire Linear for an estimating team-of-one.
- **Effort:** M. **Deps:** PM-12 consumes it.

### PM-5 — Custom fields / properties
- **Problem:** Properties are a fixed schema (status, priority, dates, owner, labels, section). Notion's killer feature is user-defined properties (text/number/select/date/checkbox/relation). A Notion replacement must let the user add their own fields.
- **Evidence:** `ActionItem` is a fixed Codable struct (`ActionItem.swift:13-65`); the property panel hardcodes each row (`TaskPageView.swift:124-248`).
- **Recommendation:** Add `var customFields: [String: FieldValue]?` plus a per-workspace `FieldDefinition` registry (id, name, type, options). Render dynamic rows in the property panel and a dynamic column option in table view. Start with select/text/number/date.
- **Impact:** The largest single gap vs. Notion specifically; without it power users can't model their data.
- **Effort:** L. **Deps:** PM-7 (custom fields become filterable/columns).

### PM-6 — Reminders & due-date notifications
- **Problem:** Tasks never notify. The app HAS a notification system, but it only fires for meetings/transcription/daily-brief — nothing reads `dueDate`. A primary task app that stays silent on overdue work won't be trusted.
- **Evidence:** `NotificationManager.swift` schedules meeting/brief notifications only (`Notifications/NotificationManager.swift:114-177`); no task/due-date scheduling anywhere (grep `dueDate.*notif` → none).
- **Recommendation:** On set/changed `dueDate` (and optional `reminderAt`), schedule a `UNUserNotificationCenter` local notification; cancel on complete/reschedule. Add a "Remind me" row and a per-task reminder offset. Reuse the existing `NotificationManager`.
- **Impact:** Converts the app from passive list to active assistant; key trust-builder for Things/Todoist switchers.
- **Effort:** S/M. **Deps:** none (notification infra already exists).

### PM-7 — Saved / smart views (persisted filter+sort+group presets)
- **Problem:** Filter/sort/group state is ephemeral per-session view state; there's no way to save "My overdue, grouped by project" and return to it. Linear "Views", Notion saved views, and Asana saved searches are how power users navigate.
- **Evidence:** Filter/group/sort live in transient `@State`/VM properties, not persisted (`ActionItemsViewModel.swift:86-92`, `ActionItemsView.swift:12-37`). No `SavedView` model exists.
- **Recommendation:** Add a persisted `SavedView` (name, icon, filter signature, groupBy, sort, viewMode, scope) stored alongside the other JSON files; list saved views in the sidebar above projects. The filter logic to drive them already exists in `filteredSorted` (`ActionItemsViewModel.swift:113`).
- **Impact:** Makes the tool navigable at scale; the everyday muscle-memory that keeps people in Linear.
- **Effort:** M. **Deps:** consolidate filter state (the dead ViewModel issue noted in prior audit's TK-1).

### PM-8 — Unified "My Work" / inbox across projects
- **Problem:** There's a dashboard and "All tasks", but no single cross-project "what's on MY plate now" view that respects `ownerPersonID == me`, sorted by due. Asana "My Tasks", Things "Today", Linear "My Issues" are the daily home screen.
- **Evidence:** The dashboard shows generic "Open tasks" not filtered to the user (`ActionItemsChrome.swift:36-60`); `items(forPerson:)` exists (`ActionItemStore.swift:513`) and the extractor already knows the user's identity (`ActionItemExtractor.isMine` `ActionItemExtractor.swift:62`) but nothing assembles a personal Today/Upcoming/Overdue inbox.
- **Recommendation:** Add a top-of-sidebar "My Work" view: Overdue / Today / Upcoming / No date sections, scoped to the user (via `myNameAliases` + `ownerPersonID`). Make it the default landing.
- **Impact:** Gives the app a real home screen; this is the screen Things/Asana users open 20×/day.
- **Effort:** S/M. **Deps:** PM-6 pairs well; PM-7 (could be a built-in saved view).

### PM-9 — Natural-language quick capture
- **Problem:** Quick-add creates a literal "New task" then makes you edit fields (`addTask` `ActionItemsChrome.swift:397-407`). Things/Todoist parse "Email Sarah Friday 3pm !high #marketing" in one line. The app already has a date parser it doesn't reuse here.
- **Evidence:** `addTask` hardcodes title "New task" with no parsing (`ActionItemsChrome.swift:403`). A capable date/relative parser exists but only in extraction (`ActionItemExtractor.parseDueClause` incl. `NSDataDetector`, `ActionItemExtractor.swift:176-212`).
- **Recommendation:** Parse the quick-add string for due/start dates (reuse the extractor's parser), `!priority`, `@owner`, `#label`, `/project`. Show a parse preview chip.
- **Impact:** Capture speed is *the* reason Things/Todoist keep users; cheap to build since the parser exists.
- **Effort:** S/M. **Deps:** none.

### PM-10 — Global quick-capture (system-wide hotkey / menu bar)
- **Problem:** To add a task the user must open the app and navigate to Tasks. Things' global add and Todoist's quick-add hotkey let you capture from anywhere — essential so thoughts don't escape to a sticky note (or Notion).
- **Evidence:** Quick-add is only the in-tab toolbar button + ⌥⌘N which is app-window scoped (`ActionItemsChrome.swift:351-353`). The app has a menu bar (`MenuBarView.swift`) and a hotkey recorder (`HotkeyRecorder.swift`) — infra exists but isn't wired to task capture.
- **Recommendation:** Add a global hotkey opening a tiny capture window (NL-parsed per PM-9) that calls `store.createTask`; add "New task…" to the menu bar.
- **Impact:** Makes the app the *default* capture target, displacing whatever the user uses for fleeting tasks.
- **Effort:** M. **Deps:** PM-9 (parse the captured line).

### PM-11 — Trash / soft-delete + undo
- **Problem:** `delete(_:)` permanently removes a task immediately (`ActionItemStore.swift:482-485`); `deleteProject` hard-deletes and unlinks tasks (`ActionItemStore.swift:606-615`); bulk delete nukes the whole selection (`ActionItemsListView.swift:167`). One misclick = unrecoverable data loss. Every competitor has Trash + undo.
- **Evidence:** No `deletedAt`/trash concept; deletes are `removeAll` in place.
- **Recommendation:** Soft-delete via `var deletedAt: Date?` filtered out of normal views, a Trash view, auto-purge after 30 days, and a toast-level "Undo" after delete/bulk-delete (the app has `ToastCenter.swift`).
- **Impact:** Trust/safety — users won't commit their only task DB to an app that can lose data on a misclick.
- **Effort:** M. **Deps:** none.

### PM-12 — Reporting / analytics dashboard
- **Problem:** The only stats are per-project counts (`ActionItemsChrome.swift:268-294`). No completed-this-week, no throughput/velocity, no overdue trend, no per-person load. Linear Insights, Asana dashboards, and Notion charts are how managers justify the tool.
- **Evidence:** `stat()` shows raw open/in-progress/done counts only (`ActionItemsChrome.swift:281`); no time-series, no `updatedAt`-based completion analytics despite `createdAt`/`updatedAt` being stored (`ActionItem.swift:64-65`).
- **Recommendation:** Add an Insights view: completed-per-week bar, open vs. created trend, overdue count over time, breakdown by project/priority/owner. All derivable from existing timestamps + (with PM-4) estimates for velocity.
- **Impact:** Reporting is what makes a tool "real" for planning; differentiator vs. lightweight to-do apps.
- **Effort:** M/L. **Deps:** PM-4 (for velocity), benefits from a completion timestamp (PM-13).

### PM-13 — Distinct completion timestamp & status history
- **Problem:** "When was this done?" is approximated by `updatedAt`, which any edit bumps. No status-change history. Reporting (PM-12), "completed today" surfaces, and audit trails all need a real `completedAt`.
- **Evidence:** Only `createdAt`/`updatedAt` exist (`ActionItem.swift:64-65`); `setStatus` just flips status and bumps `updatedAt` (`ActionItemStore.swift:487`, `update` `:540`).
- **Recommendation:** Set `var completedAt: Date?` when status→completed (clear on reopen). Optionally a compact `statusHistory: [(Status, Date)]`. Dashboards already separate completed (`ActionItemsChrome.swift:270`).
- **Impact:** Foundational for accurate reporting and "done today/this week" views.
- **Effort:** S. **Deps:** enables PM-12; pairs with PM-8.

### PM-14 — Task comments & activity feed
- **Problem:** A task has a notes body and subtasks but no threaded comments or activity log. Asana/Linear/Notion all center collaboration (and even solo users) on comments — running commentary distinct from the description, plus an auto activity trail.
- **Evidence:** Missing entirely. `TaskPageView` exposes notes/body + subtasks only (`TaskPageView.swift:124-340`); no comment model.
- **Recommendation:** Add `var comments: [Comment]?` (author, text, date) rendered as a feed below the body, plus auto-logged events (status changed, due set). Even single-user, this captures *why/when* decisions were made — and meeting-extracted tasks can auto-seed the first comment with the source quote.
- **Impact:** Closes a visible gap vs. all three competitors; lays groundwork for the meeting-context differentiator (PM-19).
- **Effort:** M. **Deps:** none.

### PM-15 — Attachments / file & link references
- **Problem:** Can't attach a file, image, or reference link to a task. Notion/Asana/Linear all let you drop a screenshot or PDF on an issue. The app already manages a vault of files (meeting recordings, exports).
- **Evidence:** No attachment field on `ActionItem` (`ActionItem.swift`). VaultKit/storageDir infra exists (`ActionItemStore.swift:18-32`) but isn't used for task assets.
- **Recommendation:** Add `var attachments: [Attachment]?` (filename, relative vault path, type) with drag-drop onto the task page; copy files into a `task_attachments/` dir under storageDir.
- **Impact:** Removes a reason to keep tasks in Notion (where the spec/screenshot lives).
- **Effort:** M. **Deps:** none.

### PM-16 — Task & project templates
- **Problem:** Every new project/task starts blank. Asana templates and Notion templates let you stamp out a repeatable structure (e.g. "New feature: spec → build → QA → ship" sections + standard tasks). The app even has a `NoteTemplate` model for meetings but nothing for tasks/projects.
- **Evidence:** `createProject`/`createTask` create empty entities (`ActionItemStore.swift:146-180`, `:547-555`). `Models/NoteTemplate.swift` exists for notes only.
- **Recommendation:** Add a `ProjectTemplate` (sections + seed tasks + body) and "Save as template" / "New from template". Ship 2-3 built-ins (Sprint, Launch, Client onboarding).
- **Impact:** Speeds repeated workflows; a sticky Asana/Notion behavior.
- **Effort:** M. **Deps:** none.

### PM-17 — Full bulk-edit parity across all views (+ move/assign/due/undo)
- **Problem:** Multi-select bulk actions exist only in the LIST view and only do status/priority/delete. Table and board can't multi-select, and you can't bulk-move-to-project, bulk-assign, bulk-set-due, or bulk-relabel. Linear's bulk edit covers every field from every view.
- **Evidence:** Selection + bulk bar live only in `ActionItemsListView.swift:142-184` (`bulkSetStatus`/`bulkSetPriority`/`bulkDeleteTasks`); table (`ActionItemsTableView`) and board (`ActionItemsBoardView`) have no `taskSelection` wiring. Bulk ops loop one save per item (`for id in taskSelection { store.setStatus… }` `ActionItemsListView.swift:182`).
- **Recommendation:** Lift selection into the shared VM, add it to table/board, and extend the bar with Move-to-project / Assignee / Due / Labels. Add `store.bulkApply(ids:mutate:)` that mutates once and saves once (also fixes N-writes). Pair with undo (PM-11).
- **Impact:** Day-to-day speed at scale; consistency across views is expected from a Linear replacement.
- **Effort:** M. **Deps:** PM-11 (undo), filter-state consolidation.

### PM-18 — Two-way external sync (status/field write-back + bulk push)
- **Problem:** Sync is asymmetric: import pulls many fields, but push only creates a Notion page / Linear issue once — later local edits (status flip, due change) don't propagate back, and there's no bulk push. So Linear/Notion drift out of date and the user can't trust this as the source of truth replacing them.
- **Evidence:** `pushToNotion` updates an existing page only if `notionPageID != nil` but is invoked per-task on demand, not on edit (`ActionItemsChrome.swift:460-476`); Linear push is create-only (`createLinearIssue`, no update mutation — `TaskSyncService.swift:202`). No bulk push.
- **Recommendation:** On local edits to a linked task, queue a debounced write-back (Notion page update; add a Linear `issueUpdate` mutation). Add "Push selected to…" bulk action. Surface per-task sync state (queued/synced/error) instead of one shared `lastError`.
- **Impact:** Lets the user migrate off Notion/Linear gradually without the two diverging — the bridge that makes switching safe.
- **Effort:** M/L. **Deps:** PM-17 (bulk push), PM-13 (state).

### PM-19 — Lean into the AI/meeting differentiator (the moat)
- **Problem:** The app's unique edge — tasks born from meetings — is under-exploited. Extraction only keeps tasks owned by *me* (`isMine` drops everyone else's `ActionItemExtractor.swift:36,62`), discards due dates it can't parse, and never links the source transcript quote, suggests a project, or proposes a priority. Notion/Linear can't do any of this; it should be the headline reason to switch.
- **Evidence:** `isMine` filters out non-self action items entirely (`ActionItemExtractor.swift:62-85`); extracted items get `priority: .medium` always and no `projectID` (`ActionItemExtractor.swift:44-50`); the source quote/transcript offset isn't captured.
- **Recommendation:** (a) Optionally keep *others'* action items as a "Delegated/Waiting-on" list (huge for managers). (b) Auto-suggest project + priority from meeting context. (c) Store the source sentence + a deep link so each task shows "why" (feeds PM-14). (d) A review/triage inbox to accept/snooze/reassign freshly-extracted tasks before they hit the backlog.
- **Impact:** This is the single hardest-to-copy advantage and the strongest "switch from Notion" pitch; everything else is parity, this is the moat.
- **Effort:** M/L. **Deps:** PM-14 (source as first comment), PM-8 (triage inbox surface).

### PM-20 — Import / export (CSV / Markdown / JSON)
- **Problem:** Beyond the live API sync, there's no file import/export. Switching costs cut both ways: users won't commit without a clean exit (export), and can't bring an existing Todoist/Asana CSV in (import). The store even encodes pretty JSON but never exposes it.
- **Evidence:** No CSV/Markdown export of tasks (grep across Tasks UI → none); persistence writes envelope JSON to disk but there's no user-facing export/import (`ActionItemStore.writeEnvelope` `:744`). `ObsidianExporter`/`GoogleDriveService` exist for meetings, not tasks.
- **Recommendation:** Add Export (CSV + Markdown checklist + raw JSON) and Import (CSV with column mapping; Todoist/Asana templates). Reuse the existing exporter patterns.
- **Impact:** Removes adoption friction (bring data in) and lock-in fear (get it out) — both prerequisites for "make this my primary tracker".
- **Effort:** M. **Deps:** none.

### PM-21 — Calendar / timeline (Gantt) and per-task calendar placement
- **Problem:** `startDate` + `dueDate` are stored but only ever shown as text; there's no calendar or timeline view to see workload across dates, and tasks don't appear on the user's actual calendar. Asana Timeline, Notion Calendar/Timeline, and Things' calendar integration are core planning surfaces.
- **Evidence:** `startDate` exists (`ActionItem.swift:42`, `setStartDate` `ActionItemStore.swift:252`) but only list/table/board view modes exist (`ViewMode` `ActionItemsViewModel.swift:63`); no calendar/timeline mode. The app already integrates Calendar (meeting detection) so EventKit is available.
- **Recommendation:** Add a Calendar view mode (tasks placed by due/start) and a simple project Timeline/Gantt using start→due spans. Optionally mirror due-dated tasks to a dedicated EventKit calendar.
- **Impact:** Visual planning is why people pay for Asana/Notion; closes the "see my week" gap for Things switchers.
- **Effort:** L. **Deps:** PM-3 (milestones render on the timeline).

---

## Top 5 picks

1. **PM-19 — Lean into the meeting-AI differentiator.** This is the only feature on the list Notion/Linear/Asana *structurally cannot* match. Parity features make the app viable; this is what makes someone actively *choose* it. Delegated/waiting-on tracking + source-quote context + a triage inbox turn "another task app" into "the task app that watches my meetings for me." Highest strategic leverage.
2. **PM-6 — Reminders & due-date notifications.** A task tracker that never proactively tells you about overdue work cannot be a primary tracker — users won't trust it with commitments. The notification infra already exists, so this is low-cost, high-trust. Table stakes that's currently zero.
3. **PM-8 — Unified "My Work" inbox** (+ PM-13 completion timestamp). Every competitor's daily home screen. The data and identity logic already exist (`items(forPerson:)`, `isMine`); assembling the Today/Upcoming/Overdue personal view is the screen that creates the daily habit that displaces the incumbent.
4. **PM-11 — Trash / soft-delete + undo.** Nobody migrates their *only* task database into an app that can irreversibly lose data on a misclick (current `delete`/bulk-delete are hard removes). This is a cheap, pure prerequisite for trust — gates adoption regardless of feature richness.
5. **PM-7 — Saved / smart views** (with PM-1 recurring close behind). Saved views are how power users navigate at scale and the muscle memory that keeps people in Linear/Notion; recurring tasks (PM-1) is the most-cited reason Things/Todoist users won't leave. Together they cover "navigation at scale" and "the chores I do every week."

**Through-line:** the feature already has impressively complete *structure* (Initiative›Project›Task, three views, sections, labels, subtasks, bidirectional Linear/Notion sync, AI extraction). The gaps are in the *daily-use loop* (reminders, my-work, recurring, undo, saved views) and in *exploiting the one moat the competitors lack* (meeting-born tasks with context). Win the daily loop + double down on the AI angle and this becomes a credible Notion/Linear/Asana/Things replacement.
