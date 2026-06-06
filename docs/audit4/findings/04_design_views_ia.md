# 04 — Design: Views, Visual System & Information Architecture (Tasks/Projects)

Lens: I audit the Projects/Tasks feature purely as a *visual system + set of views over task data* — the thing that makes a user pick this over Notion/Asana/Linear. Two questions drive every finding: (1) can the user *see* their work the way the work is shaped (by date, by timeline, by owner, as cards) and (2) does the surface look *systematized* — one type/spacing/color/elevation language, accessible color, real iconography, avatars, progress, covers, and a legible Initiative›Project›Task IA. I stay off the perf/data-model/interaction beats already covered in `G2_tab_tasks.md` (TK-*), `G1_design_visual.md` (DV-*), nav, and sync; those are referenced, not repeated.

## Verified already-built (do NOT re-propose)

Grounded in code so we don't re-suggest these:

- **Three views exist:** List, Table, Board(kanban). View switcher `ActionItemsView.ViewMode` (`ActionItemsView.swift:46-57`), tabs `viewTab` (`ActionItemsChrome.swift:373`), board `ActionItemsBoardView.swift`, table `ActionItemsTableView.swift`. Board has drag-reorder with midpoint `sortIndex` (`ActionItemsBoardView.swift:84-104`).
- **Grouped/sectioned list:** group-by Meeting/Priority/Status/Due (`ActionItemsListView.swift:285`), ordered group keys (`:271`), plus Asana-style per-project sections with drag-to-section (`sectionedListBody`, `:8-30`).
- **IA tree:** Initiative›Project›Task with a recursive sidebar (`ActionItemsSidebar.swift` — `InitiativeNode`, `PageTreeNode`, infinite nesting via `depth`), open-count badges per node, resizable+persisted rail width (`ActionItemsView.swift:43,117-132`, TK-8 done).
- **Page chrome:** project page header with editable icon picker + name + markdown body (`ProjectPageHeader`, `ActionItemsProjectPage.swift:7-118`), initiative page (`InitiativePage:197`), task-as-page with property block + subtasks (`TaskPageView.swift`), breadcrumb bar (`TaskPageView.swift:70`).
- **Design tokens (NDS):** warm dynamic light/dark palette (`NotionDesign.swift:44-55`), 6 type tokens mapped to scaling `TextStyle`s (`:76-81`), `NotionChip`/`NotionEyebrow`/`NotionPropertyRow`/`QuickActionCard`, `selectColor()` deterministic chip color (`:98`), `motion()` reduce-motion gate, Light/Dark `AppearanceToggle` (`:491`).
- **Labels/chips:** colored `TaskLabel` with palette (`ActionItem.swift:138-150`), chips on cards/rows; priority chips; subtask progress count `n/m` on board cards (`ActionItemsBoardView.swift:118`) and task page.
- **Dashboard landing** with quick-action cards + Open/Pages/Recent sections (`ActionItemsChrome.swift:8-105`).
- **Multi-select + bulk bar** already added in list (`taskSelectToolbar`, `ActionItemsListView.swift:142-176`) — TK-3 shipped; do not re-propose as an interaction, but its *visual* treatment is fair game.

---

## Improvements

### VD-1 — Calendar view (month/week) over due & start dates
- **Problem:** Dates are first-class on every task (`startDate`, `dueDate` in `ActionItem.swift:32,41`) but there is *no* way to see tasks on a calendar. Due dates only appear as a sortable column or a group bucket. This is the single biggest view-parity gap vs Notion/Asana/Linear, all of which ship a calendar.
- **Evidence:** `ViewMode` is only `list/table/board` (`ActionItemsView.swift:46`); missing.
- **Recommendation:** Add a `.calendar` `ViewMode`. Month grid + week toggle; each task renders as a chip in its `dueDate` cell, colored by priority (VD-9), draggable across days to reschedule (reuse `setDueDate`). Show start→due as a span when both exist. Tasks with no date sit in a right "Unscheduled" rail you drag from.
- **User impact:** "What's due this week, visually" in one click; drag-to-reschedule is faster than opening each task. This is the headline reason users stay in Notion.
- **Effort:** L · **Deps:** none (data exists); pairs with VD-9 color system.

### VD-2 — Timeline / Gantt view over start→due spans
- **Problem:** `startDate` exists but is *only* ever shown as a single property row; there is no horizontal time axis, so no one can see overlap, sequencing, or a project's shape over time. Initiatives (multi-project, multi-week) have nowhere to live visually.
- **Evidence:** `startDate` set via `setStartDate` and shown once (`TaskPageView.swift:190`); no timeline view — missing.
- **Recommendation:** A `.timeline` view: rows = tasks (or grouped by project/section/assignee swimlane), x-axis = days/weeks, each task a bar from `startDate` to `dueDate` (1-day pill if only due set). Drag bar ends to set dates; today-line marker; zoom day/week/month. At the initiative level, collapse each project to one summary bar.
- **User impact:** Planning + dependency-at-a-glance that list/board can't give; the feature managers cite when choosing Asana/Linear Cycles.
- **Effort:** L · **Deps:** VD-9 (bar color), benefits from VD-3 swimlanes.

### VD-3 — Swimlane board (group columns by a second dimension)
- **Problem:** The board is one-dimensional: columns are *always* status (`ForEach(ActionItem.Status.allCases)`, `ActionItemsBoardView.swift:11`). You can't see status × assignee or status × priority, which is the core Jira/Linear board power-move.
- **Evidence:** `boardBody`/`boardColumn` hardcode status (`ActionItemsBoardView.swift:8-31`); missing rows dimension.
- **Recommendation:** Add a "Group rows by" selector (Assignee / Priority / Project / Label / None). When set, render horizontal swimlanes: each lane is a labeled row band, status columns repeat inside it, drop still routes via `dropCard`. Lane header shows the value chip + count.
- **User impact:** Stand-up board ("show me each person's column") and triage board ("urgent lane up top") without leaving the board.
- **Effort:** M · **Deps:** TK-1 (cached buckets) recommended.

### VD-4 — Gallery / card view with project covers
- **Problem:** There is no large-card "gallery" — the visually richest, most Notion-defining view. `Project` already has `icon` and `colorHex` (`Project.swift:13,15`) but no cover, and projects are only ever shown as one-line sidebar/list rows.
- **Evidence:** `colorHex` largely unused for surfaces; no gallery `ViewMode`; missing.
- **Recommendation:** (a) Add `coverHex`/`coverSymbol` (or reuse `colorHex`) to `Project`/`Initiative` and render a gradient/symbol cover banner atop each page header (`ProjectPageHeader`, `ActionItemsProjectPage.swift:19`). (b) Add a `.gallery` task `ViewMode`: a `LazyVGrid` of larger cards (title, labels, due chip, assignee avatar, subtask progress bar) — essentially the board card promoted to a grid cell.
- **User impact:** Pages stop looking like a flat list of gray rows; covers give projects identity and scannability — the "this feels like a real workspace" moment.
- **Effort:** M · **Deps:** VD-7 (avatars), VD-10 (progress), VD-9 (color).

### VD-5 — Accessibility-safe, tokenized priority/status color system
- **Problem:** Priority colors are raw system `.gray/.blue/.orange/.red` *re-defined in at least three files*, none colorblind-safe and none routed through NDS. Status colors likewise. Drifts and fails WCAG/deuteranopia (red vs orange vs gray are the classic confusions).
- **Evidence:** `priorityColor` raw `.gray/.blue/.orange/.red` in `ActionItemsTableView.swift:132-139`; board status dot `.green/.orange/.blue` (`ActionItemsBoardView.swift` via shared); duplicate in `TaskPageView.swift:378-385` (this one uses NDS — proof of drift); table status glyph `.blue` (`ActionItemsTableView.swift:79`); meeting-notes row `.blue` (`ActionItemsProjectPage.swift:343`).
- **Recommendation:** One `NDS.priority(_:)`/`NDS.status(_:)` returning dynamic, colorblind-tuned colors (e.g. urgent=red+ a shape/▲ icon, high=amber, med=blue, low=slate) plus a *non-color redundancy* (priority flag-fill count or a leading bar) so color isn't the only signal. Delete the three local `priorityColor`/status switches.
- **User impact:** Consistent semantics across list/table/board/calendar; usable by colorblind users (~8% of men); kills a drift class.
- **Effort:** S · **Deps:** none (foundational for VD-1/2/4).

### VD-6 — Assignee avatars everywhere (not bare text/none)
- **Problem:** Tasks hard-link to People (`ownerPersonID`, `ActionItem.swift:28`) but no view shows a *face*. Table prints `item.owner ?? "—"` as gray text (`ActionItemsTableView.swift:88`); board and list rows show *nothing* for owner; only the task page has the person link UI. People already ship avatars elsewhere (15 files use `Circle()`/avatar patterns) — the Tasks feature just never adopted them.
- **Evidence:** plain text owner (`ActionItemsTableView.swift:88`); no avatar in `boardCard` (`ActionItemsBoardView.swift:106-152`) or `ActionItemRow`; missing.
- **Recommendation:** Extract a shared `MSAvatar(person:size:)` (monogram from initials on a `selectColor(name)` disc, photo if available) and place it on table Owner cell, board card footer, list row trailing, and calendar/gallery cards. Overlap-stack when a card has multiple linked people.
- **User impact:** "Who owns this" becomes a glance, not a read; the surface instantly looks like a team tool, not a checklist.
- **Effort:** S–M · **Deps:** VD-9 color for disc tint.

### VD-7 — Project & initiative progress indicators (% complete bar / ring)
- **Problem:** Nowhere shows how *done* a project or initiative is. Sidebar/pages show only an open *count* (`openCount(forProject:)`, `ActionItemStore.swift:93`); there's no completed-vs-total ratio, ring, or bar. Subtask progress exists per-task but never rolls up.
- **Evidence:** only `openCount` helpers (`ActionItemStore.swift:93,409`); no `% complete`/Gauge/`ProgressView(value:)` in Tasks (the one `ProgressView(value:)` is migration, `VaultMigrationSheet.swift:25`); missing.
- **Recommendation:** Add `store.completion(forProject:)`/`forInitiative:` → (done,total). Render a thin determinate bar in the project page header (`ProjectPageHeader`) and a small ring on each sidebar project node + initiative node, and in the gallery card. Dashboard gets a per-project progress list.
- **User impact:** Status at a glance; "Q2 Analytics is 70% done" without counting. A core PM dashboard expectation.
- **Effort:** S · **Deps:** VD-9 (bar color); pairs with VD-4/VD-19.

### VD-8 — Density toggle (Comfortable / Compact) for views
- **Problem:** Row padding is hardcoded per view and there's no way to fit more rows. Chat already proves the pattern (`ChatPanel.density`, `ChatPanel.swift:18,31`) but Tasks never adopted it. A 50-row backlog wastes a third of the screen on whitespace.
- **Evidence:** fixed `.padding(.vertical, 7)` table (`ActionItemsTableView.swift:98`), `.padding(10)` board card (`ActionItemsBoardView.swift:147`), list spacing `8` (`ActionItemsListView.swift:107`); no `ui.density` for Tasks (only ChatPanel has density). Missing.
- **Recommendation:** `@AppStorage("tasks.density")` swapping a `NDS.space` row-pad/spacing pair (needs the DV-1 spacing scale). Toolbar segmented control (comfortable ⇄ compact). Apply to list/table/board card paddings.
- **User impact:** Power users see ~40% more rows per screen → fewer scrolls; casual users keep the airy default.
- **Effort:** M · **Deps:** DV-1 (spacing scale, from G1), affects all view files.

### VD-9 — Sticky, well-designed group/section headers
- **Problem:** Group headers in the list scroll away with content and are visually thin (a 13pt uppercased label + count, no background), so when scrolling a long grouped list you lose your place. Asana/Linear pin section headers.
- **Evidence:** `section(title:items:)` is a plain `VStack` header that scrolls (`ActionItemsListView.swift:303-319`); `sectionGroup` same (`:32-72`); no `pinnedViews`.
- **Recommendation:** Use `LazyVStack(pinnedViews: .sectionHeaders)` + `Section`, give headers a subtle `NDS.bg`/material backing, a collapse chevron (persist collapsed set), and the group's aggregate (count + mini progress). Same treatment for project sections and swimlanes.
- **User impact:** Always know which bucket you're in; collapse noisy groups. Reads as a real grouped database.
- **Effort:** S–M · **Deps:** none.

### VD-10 — Board card redesign: due chip + avatar + cleaner hierarchy
- **Problem:** Board cards are visually weak and off-system: raw `Color(NSColor.controlBackgroundColor)` fill and `separatorColor` border (not NDS surfaces), no due date, no assignee, label bars are 4pt slivers, and the ellipsis menu competes with content. Reads as a prototype next to Linear cards.
- **Evidence:** `boardCard` (`ActionItemsBoardView.swift:106-152`) — `Color(NSColor.controlBackgroundColor)` (`:149`), no `dueDate`/owner shown, label capsules `height:4` (`:114`).
- **Recommendation:** Reskin via the shared `MSCard` (DV-2): NDS surface + `cardRadius`, hairline, hover-elevation; footer row = priority chip · due chip (red if overdue) · `MSAvatar` (VD-6); labels as readable mini-chips; subtle left priority bar (VD-5). Move the menu to hover-only.
- **User impact:** The board becomes the demo-worthy view; parity with Linear/Trello card density.
- **Effort:** S–M · **Deps:** VD-5, VD-6, DV-2.

### VD-11 — Editable table cells + column customization
- **Problem:** The table is read-only for the fields that matter — Owner and Priority are static `Text` (`ActionItemsTableView.swift:88-92`), so editing means opening the page. Columns are fixed (Task/Project/Owner/Priority/Due/Meeting); you can't hide, add (Status/Labels/Start), or reorder them. Notion/Airtable tables are defined by editable, configurable columns.
- **Evidence:** static cells (`ActionItemsTableView.swift:88-96`); hardcoded `tableHeaderRow` widths (`:40-49`); missing config.
- **Recommendation:** Make Owner (person menu), Priority, Status, Due inline-editable (reuse the list-row menus/popovers); add a "Columns" menu to toggle/reorder a `[Column]` set persisted in `@AppStorage`; show Labels and Start as optional columns; right-align/monospace the due column.
- **User impact:** Table becomes a real spreadsheet — edit in place, see exactly the fields you want. Removes the 3-click "open to edit" tax (overlaps TK-5 but framed as column IA).
- **Effort:** M · **Deps:** VD-5, VD-6.

### VD-12 — Breadcrumbs reflect the full Initiative›Project›Task path
- **Problem:** The only breadcrumb is the task page's, and it's a *single* hop — `breadcrumb` is just the project name or "All tasks" (`ActionItemsView.swift:166-169`, rendered `TaskPageView.swift:70`). Project and initiative pages have *no* breadcrumb at all, so in a deep tree you can't see or click your way back up.
- **Evidence:** single-segment `taskBreadcrumb` (`ActionItemsView.swift:166`); `ProjectPageHeader`/`InitiativePage` have no breadcrumb; missing.
- **Recommendation:** A reusable `BreadcrumbBar([crumb])` showing Initiative › Parent pages › Project › Task, each segment clickable (sets the matching selection). Walk `parentID` for page ancestry and `initiativeID` for the top. Put it atop project, initiative, and task panes.
- **User impact:** Orientation + 1-click up-navigation in deep trees; matches Notion's path bar.
- **Effort:** S · **Deps:** none.

### VD-13 — Native, illustrated empty states (per view, actionable)
- **Problem:** Empty states are hand-rolled and generic. The main one is a `VStack` + `.headline`/`.caption` system fonts off the NDS scale (`ActionItemsChrome.swift:409-433`); calendar/board/each-project-empty have no tailored zero-state. No use of macOS `ContentUnavailableView`.
- **Evidence:** `emptyState` raw `.font(.headline)`/`.caption` (`ActionItemsChrome.swift:413-414`); board empty = bare filler (`ActionItemsBoardView.swift:66`); section empty = tiny gray text (`ActionItemsListView.swift:62-65`).
- **Recommendation:** `ContentUnavailableView` (or a shared `MSEmptyState`) per context with a relevant SF Symbol, NDS type, and a primary action: empty project → "Add first task"; empty board column → ghost "+"; empty calendar → "No tasks scheduled". Consistent voice + iconography.
- **User impact:** Empty surfaces become a clear next step, not a void; on-brand and accessible. (Complements DV-5 globally; this is the Tasks-specific application.)
- **Effort:** S · **Deps:** none.

### VD-14 — Tasks dashboard data-viz (status donut, due-soon, by-project bars)
- **Problem:** The dashboard is three link lists (Open/Pages/Recent, `ActionItemsChrome.swift:36-100`) with zero visualization. The header has three count chips (`stat`, `:281`) but no chart. For a "do I prefer this over Asana" judgment, the home view should *show* the shape of the work.
- **Evidence:** `tasksDashboard` is list-only (`ActionItemsChrome.swift:8-105`); no `Chart`/`Gauge` anywhere in Tasks.
- **Recommendation:** Add a compact viz band using Swift `Charts`: a status donut (open/in-progress/done), an "overdue / due this week / later" bar, and a top-projects horizontal bar by open count. Each segment clickable → sets the matching filter (donut "Open" → `filter=.open`).
- **User impact:** Instant situational awareness + a one-click drill path; the dashboard earns its place as the landing.
- **Effort:** M · **Deps:** VD-5 colors, VD-7 completion helper.

### VD-15 — Overdue / due-today visual urgency treatment
- **Problem:** Due dates render in uniform secondary gray with no urgency signal — overdue looks identical to next-month. Table due is gray monospace (`ActionItemsTableView.swift:93-94`); board cards show no due at all. Users can't spot what's late without reading every date.
- **Evidence:** `dueShort` returns plain "MMM d", styled `.foregroundStyle(.secondary)` regardless of overdue (`ActionItemsTableView.swift:93`); `groupKey` knows "Overdue"/"Today" (`ActionItemsListView.swift:294-297`) but rows don't color it.
- **Recommendation:** A `DueChip` view: red text/dot if overdue, amber if due today, normal otherwise; relative phrasing ("2d overdue", "Today", "Fri"). Use it in table, list row, board, calendar, gallery.
- **User impact:** Late work is impossible to miss; triage by eye. A small, high-frequency win.
- **Effort:** S · **Deps:** VD-5.

### VD-16 — Project/initiative icon system: pickers + colored disc tiles
- **Problem:** Icon support is half-built and inconsistent. Project icon picker is a hardcoded 10-symbol menu (`ActionItemsProjectPage.swift:23-24`); initiatives have an `icon` field but *no picker* (always `flag.fill`, `InitiativePage` `:211` and `InitiativeNode` `:362`); icons render as bare glyphs, not the colored rounded tiles that give Notion pages identity.
- **Evidence:** fixed 10-icon list (`ActionItemsProjectPage.swift:23`); no initiative icon picker; glyphs not tiled (`PageTreeNode` icon `:285`).
- **Recommendation:** A shared `SymbolPicker` (searchable, categorized) used by both projects and initiatives; render icons as `selectColor`-tinted rounded tiles (like `QuickActionCard`'s 36pt tile, `NotionDesign.swift:374`) in sidebar nodes, page headers, gallery cards.
- **User impact:** Pages get distinct, colorful identity → scannable sidebar and headers; initiative icons finally editable.
- **Effort:** S–M · **Deps:** VD-4 (covers share the picker plumbing).

### VD-17 — Saved views / view presets per project (persisted view + filter)
- **Problem:** View mode, filter, group-by, and table sort are transient `@State` (`ActionItemsView.swift:18,36,46`) — reset on relaunch and shared globally, so each project can't remember "show me this as a board grouped by assignee." Notion/Airtable's defining IA is *named saved views* per database.
- **Evidence:** all view state is ephemeral `@State` (`ActionItemsView.swift:12-37`); no persisted view model; missing.
- **Recommendation:** A `SavedView` struct (name, viewMode, filter, group/swimlane, sort, visible columns) stored per project; a small view-tab strip atop the database pane ("Board", "My tasks", "Timeline"). Default per project remembered. Builds naturally on TK-1's ViewModel.
- **User impact:** Each project opens in *its* right shape; switching contexts is one tab, not re-configuring filters every time.
- **Effort:** M · **Deps:** TK-1 (single ViewModel), VD-3/VD-1/VD-2 (views to save).

### VD-18 — Responsive layout at narrow/wide windows
- **Problem:** Layout assumes a wide window. The board uses fixed 280px columns in a horizontal scroll (`ActionItemsBoardView.swift:75`) and the table has fixed pixel column widths summing to ~660px + flexible title (`ActionItemsTableView.swift:40-49`); at a narrow window the table title collapses and meeting/owner columns crowd, while at very wide windows content is capped but views don't add columns. No `@Environment` size adaptation.
- **Evidence:** fixed widths (`ActionItemsTableView.swift:42-48`, `ActionItemsBoardView.swift:75`); `contentMaxWidth=1100` cap (`NotionDesign.swift:16`).
- **Recommendation:** Read available width (GeometryReader/`@Environment(\.horizontalSizeClass)` proxy): below a threshold, table drops to its 3 essential columns (status, title, due) and the rail auto-collapses; board columns flex within a min/max; gallery grid reflows column count. Define 2–3 breakpoints in NDS.
- **User impact:** Usable in a half-screen window (common on laptops) without horizontal scrolling or clipping; uses big displays better.
- **Effort:** M · **Deps:** VD-11 (column config), DV-1.

### VD-19 — Tokenize board/page surfaces off raw AppKit colors
- **Problem:** Several Tasks surfaces bypass NDS and use raw AppKit system colors, so they don't match the warm palette and break in one appearance: board columns `Color(NSColor.controlBackgroundColor).opacity(0.25)` (`ActionItemsBoardView.swift:78`), card fill/border (`:149-151`), drag preview (`:56`), meeting-notes row fill (`ActionItemsProjectPage.swift:377`). These read cold/gray against the warm `NDS.bg`.
- **Evidence:** raw `NSColor.controlBackgroundColor`/`separatorColor` (`ActionItemsBoardView.swift:56,78,149,151`; `ActionItemsProjectPage.swift:377`).
- **Recommendation:** Route all of these through `NDS.fieldBg`/`rowHover`/`hairline`/`cardRadius` (and the future `MSCard`). Add an `NDS.columnBg` token for kanban lanes.
- **User impact:** Board/notes surfaces finally match the rest of the app in both light and dark; no more gray-on-warm mismatch.
- **Effort:** S · **Deps:** DV-2 (MSCard) ideally.

### VD-20 — Mini-map / outline for deep page bodies & big boards
- **Problem:** Project pages can hold long markdown bodies (`RichMarkdownEditor`, min 220 / max ∞, `ActionItemsProjectPage.swift:58`) and boards can be very wide, but there's no overview to jump within them — no heading outline for the page, no column minimap for the board. Long pages become a scroll-hunt.
- **Evidence:** body editor is a single unbounded scroll (`ProjectPageHeader` body `:51-59`); board is one big 2-axis scroll (`ActionItemsBoardView.swift:9`); no outline/minimap — missing.
- **Recommendation:** (a) A collapsible right-edge **outline** of the page's markdown headings (parse `#`/`##`) that scrolls-to on click (Notion's table of contents). (b) For wide boards, a thin top scrubber showing column positions. Both opt-in, only when content exceeds a threshold.
- **User impact:** Navigate long project docs and wide boards without endless scrolling; makes pages viable as real documents.
- **Effort:** M · **Deps:** none.

### VD-21 — Motion/transition language for view + page switches
- **Problem:** Switching view mode, opening a task page, or expanding tree nodes is an instant hard cut (state flips with no transition), except the disclosure-chevron rotation. There's a `motion()` reduce-motion gate (`NotionDesign.swift:116`) but it's barely used in Tasks, so the feature feels static/abrupt vs the polished slide/fade of Linear.
- **Evidence:** view switch is a bare `viewMode = m` (`ActionItemsChrome.swift:375`); task open is `selectedTaskID = item.id` with no transition (`ActionItemsListView.swift:334`); only chevron rotates (`ActionItemsSidebar.swift:277`).
- **Recommendation:** Add subtle, reduce-motion-gated transitions: cross-fade/slide between view modes, push/slide for opening a task page (with `matchedGeometryEffect` on the title where cheap), height-animate tree expand. Centralize durations in NDS (`motionFast/Std`).
- **User impact:** The app feels alive and intentional; perceived quality jump at near-zero cost. Respects Reduce Motion.
- **Effort:** S–M · **Deps:** DV-1 (motion tokens), must use `NDS.motion`.

---

## Top 5 picks

1. **VD-1 — Calendar view.** The largest missing-view gap and the clearest reason users stay in Notion/Asana. Data already exists; pure additive view. Pairs with VD-9/VD-15 urgency colors.
2. **VD-5 — Accessibility-safe color system.** Foundational: every other view (calendar, timeline, board, gallery, dashboard viz) depends on one consistent, colorblind-safe priority/status palette. Cheap, removes a 3-file drift, unblocks VD-1/2/4/10/14/15.
3. **VD-2 — Timeline/Gantt.** Highest-ceiling planning view; the thing managers pick Linear Cycles / Asana Timeline for. Activates the otherwise-invisible `startDate` field and gives initiatives a home.
4. **VD-6 — Assignee avatars.** Small effort, large "this is a team tool" perception jump; the link data already exists and is currently rendered as gray text or nothing. Feeds board/gallery/calendar cards.
5. **VD-7 — Project/initiative progress indicators.** Turns the Initiative›Project IA into a status dashboard at a glance; a core PM expectation that's currently absent. Small, and it powers VD-4/VD-14/VD-19.

Sequencing note: VD-5 (color) + a shared `MSAvatar`/`MSCard`/`DueChip` component layer should land first — they're the substrate VD-1/2/4/10/14/15 all draw on.
