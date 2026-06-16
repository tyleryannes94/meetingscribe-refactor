# Shared Briefing — MeetingScribe Tasks Feature 9-Agent Audit

You are one of 9 expert agents auditing the **Tasks feature** of MeetingScribe, a macOS SwiftUI app. Read this whole file before doing anything else.

## The target (what it is)

MeetingScribe is a macOS 14+ native app (SwiftUI + AppKit, Apple Silicon) that records meetings, transcribes them, and extracts action items. The Tasks feature is a standalone task tracker within the app — it has a 3-tier hierarchy (Initiative → Project → Task), supports syncing to Linear and Notion, has a Kanban home board, and can receive action items from meeting transcripts.

**Tech stack:** Swift 5.9+, SwiftUI, no third-party UI frameworks, JSON file persistence (not CoreData or SQLite), custom design system (`NDS`).

**Scope:** Focus ONLY on the Tasks feature — data model, UI, navigation, and interaction patterns.

## Where to read the live source (cite file:line)

Local repo: `/Users/tyleryannes/MeetingScribeRefactor/Sources/MeetingScribe/`

Key files:
- `ActionItems/ActionItem.swift` — core task model
- `ActionItems/ActionItemStore.swift` — store (mutations, queries)
- `ActionItems/Initiative.swift` — top-level Initiative model
- `ActionItems/Project.swift` — Project model (has parentID, initiativeID, sections, custom properties)
- `ActionItems/TaskQuery.swift` — composable query/filter engine
- `ActionItems/TaskProperties.swift` — custom property types (text, number, select, checkbox, date, url)
- `ActionItems/TaskSyncService.swift` — Linear + Notion sync
- `ActionItems/TaskPersistenceCoordinator.swift` — file persistence
- `ActionItems/TaskQuickAddParser.swift` — natural language quick-add
- `ActionItems/TaskChangeLog.swift` — change tracking
- `UI/ActionItemsView.swift` — main Tasks tab shell (285 lines)
- `UI/ActionItemsChrome.swift` — toolbar + main content switcher (625 lines)
- `UI/ActionItemsListView.swift` — task list rendering (467 lines)
- `UI/ActionItemsSidebar.swift` — left rail: initiatives, projects, people, meetings
- `UI/ActionItemsViewModel.swift` — view model (state: selectedProjectID, etc.)
- `UI/TaskPageView.swift` — Notion-style full-page task detail
- `UI/TaskRowView.swift` — inline expandable task row
- `UI/HomeTasksBoard.swift` — Kanban home board
- `UI/TaskInsightsView.swift` — analytics sheet
- `UI/TaskMetaCluster.swift` — property chips
- `UI/TaskQuickActions.swift` — quick action menu
- `UI/TaskShortcutsView.swift` — keyboard shortcuts
- `UI/TaskTrashView.swift` — deleted tasks

Also read: `UI/ActionItemsTableView.swift`, `UI/ActionItemsCalendarView.swift`, `UI/ActionItemsSidebar.swift`

## REQUIRED first step — read existing plans so you ADD net-new

There are no prior audit docs. The codebase itself contains the "plan" via comments prefixed with phase numbers (Phase 3, Phase 6, PM-12, etc.) and ID prefixes (D1-, P2-, NP-1, etc.). Grep for these to understand what's already been implemented or planned:

```
grep -rn "Phase [0-9]\|TODO\|FIXME\|Phase [0-9]" /Users/tyleryannes/MeetingScribeRefactor/Sources/MeetingScribe/ActionItems/ | head -40
```

## What is ALREADY IMPLEMENTED (do NOT just re-describe — go BEYOND it)

Based on the codebase read, these things exist:
- 3-tier hierarchy: Initiative → Project (with parentID for nesting) → Task
- Task model: title, status (open/inProgress/completed), priority, dueDate, startDate, owner, assignee linking to Person records, labels, subtasks, notes (markdown), recurrence, estimate (story points), blockers/dependencies, custom properties per project, source tracking (meeting vs manual)
- TaskPageView: full Notion-style page (breadcrumb, editable title, property block, subtasks, rich markdown editor)
- TaskRowView: inline expandable rows with hover states, completion animation, context menus, right-click quick menu
- ProjectRail sidebar: Home, Triage inbox, All tasks, Unsorted tasks, People facet, Waiting-on, Initiatives section, Pages section, Meeting notes section
- HomeTasksBoard: 3-column Kanban (open/in-progress/done) on Home page
- TaskInsightsView: analytics sheet (status counts, weekly completion, top projects)
- TaskQuery: composable declarative filter+sort engine (scope, filters, sort key)
- TaskQuickAddParser: natural language parsing for quick task creation
- Linear sync (GraphQL), Notion sync (push + pull)
- CSV import/export
- Calendar view (ActionItemsCalendarView)
- Table view (ActionItemsTableView)
- Triage inbox for meeting-extracted items
- Custom properties per project (text, number, select, checkbox, date, url)
- Task change log (audit trail)
- Keyboard shortcuts (TaskShortcutsView)
- Push to Notion/Linear from row and page
- Trash / restore

**Your job: read the source, find what's BROKEN, MISSING, or CLUNKY. Then propose NET-NEW improvements the codebase doesn't yet have. Focus ruthlessly on the stated goal: making Tasks faster to use, more fluid, Asana/Notion-quality, and better organized so work and personal tasks don't mesh together.**

## The user's explicit goals for this upgrade

Tyler wants:
1. **Much more fluid navigation** — fewer clicks to get anywhere
2. **Faster task creation** — create tasks quickly, make multiple back-to-back easily
3. **Better organization** — Initiatives → Projects → Tasks hierarchy should be obvious and usable, not buried
4. **Meeting → Tasks pull** — seamlessly bring in action items from meeting notes
5. **Work vs personal separation** — tasks shouldn't all be meshed together; clear organization by context
6. **Asana/Notion quality** — the current version is "really limited"; it should feel like a real, robust task tracker
7. **New sub-tabs or sections** on the Tasks page are welcome
8. **Revamped Home page** that is more functional

## Guiding principles for this audit

- **Cite file:line** for every claim about current behavior
- **Distinguish** clearly between "this exists but is broken/clunky" vs "this is net-new"
- Think like a daily user: what is slow, what requires too many clicks, what is confusing
- Focus on native macOS conventions: keyboard-first, fast, no web-app anti-patterns
- The data model is strong — most gaps are in the UI/UX layer
- Effort labels: S (< 1 day), M (1–3 days), L (3–7 days), XL (> 1 week)

## Output — write a markdown file, then return a short summary

1. **Write your full analysis** to: `/Users/tyleryannes/MeetingScribeRefactor/audit/findings/<YOUR_FILE>.md` (filename given in your task prompt)
2. **Structure the file:**
   ```
   # [Role] Findings — MeetingScribe Tasks Audit
   
   ## Top existing friction points (file:line citations)
   [What currently exists but is broken/clunky/slow]
   
   ## Existing items worth endorsing / prioritizing
   [Items already in the code comments/plan worth keeping]
   
   ## NET-NEW recommendations
   ### [ID]-1: [Title]
   - **What:** ...
   - **Why:** ...
   - **Effort:** S/M/L/XL | **Impact:** High/Med/Low
   - **Deps:** [none / other IDs]
   
   ## Top 3 picks
   1. [ID-N] — one line why
   2. ...
   3. ...
   ```
3. **Return a ~120–150 word summary**: your role, your top 3 net-new picks, your single highest-priority recommendation.

Be concrete and opinionated. Cite code. Avoid generic advice.
