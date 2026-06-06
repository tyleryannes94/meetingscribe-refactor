# 02 — Product / Notion-Parity Audit: Projects & Tasks as DOCS + DATABASE + WIKI

**Lens.** Notion is replaceable here only if MeetingScribe's pages stop being "a markdown blob with a fixed task table" and become a real *docs + database + knowledge-base* surface: block-based docs, databases with **custom typed properties** and **multiple saved views** over the same data, relations/rollups, templates, bidirectional links, and a wiki/home. The unfair advantage to lean on throughout is the one Notion can't match locally: **meetings → AI-populated pages, properties, and database rows**. This audit grades the Projects/Tasks feature against that knowledge-base bar, not against task-manager parity (covered separately in G2).

## Verified already-built (do NOT re-propose)

Grounded in code:

- **Notion-style page model**: `Project` has `icon`, `colorHex`, markdown `body`, `parentID` nesting, `databaseEnabled`, `meetingIDs`, `initiativeID` (`ActionItems/Project.swift:9-71`). Three-tier hierarchy Initiative › Project › Task (`Initiative.swift`, `Project.initiativeID`).
- **Nested pages & sub-pages**: recursive `PageTreeNode` sidebar tree with cycle-guarded reparenting (`ActionItemsSidebar.swift:233-330`, `ActionItemStore.setProjectParent:567`), sub-page section + inline "Add sub-page" (`ActionItemsChrome.swift:152-214`).
- **Page icon picker + accent color** on project header (`ActionItemsProjectPage.swift:22-31`), initiative icon/body (`InitiativePage:206-267`).
- **Live-preview markdown editor with a "/" slash menu** (Text/H1-3/lists/to-do/quote/divider/code/Template submenu) and **"@" mention picker** that inserts `meetingscribe://` links (`MarkdownEditor.swift:533-614`, `RichMarkdownEditor:638-735`).
- **Markdown note/page templates** (Meeting notes, 1:1, Standup, Decision log, Weekly review) inserted as snippets (`Models/NoteTemplate.swift`).
- **Cross-entity linking + one-directional backlinks**: links live inside the markdown as `meetingscribe://` URLs; `backlinks(toMeetingID:)` scans meeting/project bodies off-main (`WorkspaceIndex.swift:61-94`, `WorkspaceLinks.swift`).
- **Fast in-memory global search** across meetings/notes/projects/tasks/people/tags with ranked scoring (`WorkspaceIndex.search:106-284`).
- **Per-page "Add database" with a 3-view choice** (table/board/list) and free-form-doc vs database-page modes (`ActionItemsChrome.swift:131-219`). **Note:** the chosen view is stored in transient `@State viewMode`, *not* persisted on the page (see NP-3).
- **Task-as-page** with a property block (status/priority/assignee/start/due/project/section/labels/from-meeting), subtasks, markdown notes (`TaskPageView.swift`).
- **Labels** (colored, Trello-style) and **Asana-style sections** within a project (`ActionItem.swift:138`, `ProjectSection`, store CRUD).
- **AI auto-population**: `ActionItemExtractor` turns meeting summaries into tasks; project↔meeting links; Linear/Notion import & push (`ActionItemStore.mergeExternal`, `NotionActionItemService`, `TaskSyncService`).

---

## Improvements

### NP-1 — Custom, typed database properties (the core Notion database primitive)
- **Gap:** A "database" here is a hard-coded set of fields on `ActionItem` (status/priority/owner/due/labels/section). Users cannot add a property like `Effort (number)`, `Team (select)`, `Sprint (date range)`, `Customer (relation)`. This is the single biggest reason Notion isn't replaceable: in Notion every database is user-schema'd.
- **Evidence:** `ActionItem.swift:13-127` is a fixed struct; no property-definition model exists anywhere (no `PropertyDef`/`PropertyType` — confirmed by grep for `customProperty`/`PropertyType`, missing entirely).
- **Recommendation:** Add a `PropertyDef { id, name, type, options }` collection on `Project` (the database) and a `values: [propID: PropertyValue]` dictionary on `ActionItem`. Ship types incrementally: text, number, select, multi-select, date, checkbox, URL, person (reuse `ownerPersonID` plumbing). Render generically in `TaskPageView` property block and as table columns.
- **User impact:** Transforms each project from "a task list" into "a real database" — the unlock that makes the whole feature Notion-competitive.
- **Effort:** L
- **Dependencies:** Foundation for NP-2, NP-5, NP-7, NP-8, NP-9, NP-13.

### NP-2 — Multiple saved database VIEWS over the same data (table/board/list/calendar/gallery/timeline)
- **Gap:** Notion's defining feature is N views of one dataset, each with its own filter/sort/group, switchable in a tab strip. MeetingScribe has list/table/board but they share one global `viewMode`/`filter`/`groupBy` and only three view *types*. There's no calendar, timeline, or gallery, and you can't keep "By status (board)" and "This sprint (table)" side by side.
- **Evidence:** `ActionItemsView.swift:46-57` single `ViewMode`; `enableDatabase(_:view:)` just flips `viewMode` (`ActionItemsChrome.swift:216-219`) — not stored per page. No calendar/timeline/gallery code exists.
- **Recommendation:** Introduce a `DatabaseView { id, projectID, name, kind, filter, sort, groupBy }` model persisted per project; render a view-tab strip on the database header. Add Calendar (off `dueDate`/start) and Gallery (off page cover/icon) first — they pair naturally with meeting-driven dates and visual pages.
- **User impact:** Same data, many lenses, saved — the day-one Notion mental model.
- **Effort:** L
- **Dependencies:** NP-3 (per-view persistence), benefits from NP-1.

### NP-3 — Persist per-page/per-view filters, sorts, and groups
- **Gap:** Filter/sort/group are ephemeral `@State` on the whole tab, reset on navigation and shared across every project. Notion saves these *per view*.
- **Evidence:** `filter`, `priorityFilter`, `groupBy`, `tableSort` are `@State` in `ActionItemsView.swift:12-37`; nothing writes them to disk; switching projects doesn't restore a project's last view.
- **Recommendation:** Store the filter/sort/group struct inside each `DatabaseView` (NP-2). Even pre-NP-2, persist a per-project `lastView` so reopening a project restores its layout.
- **User impact:** "My filtered board" is still there tomorrow; each project remembers how the user works it.
- **Effort:** M
- **Dependencies:** NP-2.

### NP-4 — True block-based doc model (not a single markdown string)
- **Gap:** Page/task bodies are one markdown `String` rendered with live styling. There are no real blocks, so no per-block drag-reorder, no toggle/callout/columns, no embeds, no block-level comments, no synced blocks. The "/" menu inserts *text*, not block objects.
- **Evidence:** `Project.body: String` (`Project.swift:17`); `TaskPageView.bodyEditor` is one `RichMarkdownEditor` (`TaskPageView.swift:335-341`); slash menu does `insertBlockSnippet` of markdown (`MarkdownEditor.swift:548-560`).
- **Recommendation:** Move to an ordered `[Block]` model (`type`, `text`, `children`, `props`) serialized to portable markdown on save (keep file portability). Start with the blocks you already fake (heading/list/todo/quote/code/divider) plus **callout**, **toggle**, and **page-embed/link-to-page** blocks. This is the substrate for NP-11 (embeds), NP-12 (synced blocks), NP-15 (block comments).
- **User impact:** Pages feel like Notion documents, not a text area; enables everything richer.
- **Effort:** L
- **Dependencies:** None; unblocks NP-11/NP-12/NP-15.

### NP-5 — Relations & rollups between databases
- **Gap:** No way to relate a task/project to another database (e.g. Project → Customers, Task → "Blocked by" Task) or to roll up child values (e.g. Initiative shows Σ effort, % done across its projects). Only the fixed Initiative›Project›Task containment exists.
- **Evidence:** Relationships are hard-coded foreign keys (`projectID`, `initiativeID`, `ownerPersonID`); no generic relation type; rollups computed nowhere (grep `rollup` → missing).
- **Recommendation:** Add `relation` and `rollup` property types on top of NP-1: a relation stores target IDs; a rollup names a relation + target property + aggregation (count/sum/%/min-max/latest). Render rollups read-only in the property block and as table columns.
- **User impact:** The "connected databases" that make Notion a system of record rather than scattered lists.
- **Effort:** L
- **Dependencies:** NP-1.

### NP-6 — Database & page templates (incl. recurring) — and AI-seeded templates
- **Gap:** Templates today are markdown body snippets only. There's no "page template" (new page pre-filled with structure *and* property defaults *and* a starter database), no "database row template" (new task with preset properties/subtasks), and no recurring templates (e.g. weekly standup page auto-created).
- **Evidence:** `NoteTemplate` is body-only markdown (`Models/NoteTemplate.swift`); `createProject`/`createTask` take no template (`ActionItemStore.swift:146,548`).
- **Recommendation:** Add `PageTemplate`/`RowTemplate` records capturing icon, property defaults, subtasks, body blocks. Surface "New from template ▾" on the page/database "+". Tie to the differentiator: a **"Meeting follow-up" template** that AI fills from the linked meeting (owner, due, decisions). Add scheduled recurrence for standup/weekly-review pages.
- **User impact:** One-click structured pages; recurring rituals self-populate; AI does the typing.
- **Effort:** M
- **Dependencies:** NP-1 (property defaults), NP-4 (block templates) make it richer but a v1 works without.

### NP-7 — AI auto-extracts into typed properties, not just task titles
- **Gap:** The extractor produces title/owner/due tasks. With custom properties (NP-1), the differentiator becomes "the AI fills your database schema" — e.g. detect `Customer`, `Effort`, `Decision`, `Risk` from the transcript and populate those properties/select options.
- **Evidence:** `ActionItemExtractor` + `reconcileExtracted` only set the fixed fields (`ActionItemStore.swift:442-480`); no property inference.
- **Recommendation:** After NP-1, let extraction map transcript entities to the project's defined properties (with a confidence chip + one-click confirm), and auto-create select options it discovers. This is the headline "Notion can't do this locally from your calls" feature.
- **User impact:** Databases stay populated with zero manual data entry — the strongest replace-Notion argument.
- **Effort:** M
- **Dependencies:** NP-1.

### NP-8 — Linked databases (one source DB surfaced/filtered on many pages)
- **Gap:** A database belongs to exactly one project page. You can't drop a filtered *view* of an existing database onto another page (Notion "linked database" / "create linked view of database"), e.g. show "My tasks across all projects" on the Home page.
- **Evidence:** `pageHasDatabase` ties tasks to `projectID` 1:1 (`ActionItemStore.swift:619-622`); the dashboard hand-rolls a fixed "Open tasks" prefix(6) list (`ActionItemsChrome.swift:36-59`) rather than an embeddable view.
- **Recommendation:** Allow a block (NP-4) of type `linkedDatabaseView` referencing a source project + a saved `DatabaseView` (NP-2). The Home dashboard becomes composed of linked views instead of bespoke lists.
- **User impact:** Roll up work anywhere; build dashboards from real data, not snapshots.
- **Effort:** M
- **Dependencies:** NP-2, NP-4.

### NP-9 — Bidirectional / reciprocal links & a backlinks panel on pages and tasks
- **Gap:** Backlinks are computed for **meetings only**, one-directional, by file-scan, and aren't shown on Project or Task pages. Notion/Obsidian/Craft auto-create reciprocal links and show a "Linked references" panel everywhere.
- **Evidence:** `backlinks(toMeetingID:)` exists but there's no `backlinks(toProjectID:)`/`toTaskID:`; `ProjectPageHeader`/`TaskPageView` render no backlinks section (`WorkspaceIndex.swift:61-94`).
- **Recommendation:** Build one reverse-link index over all `meetingscribe://` references (incrementally on save), then show a "Linked references" panel on Project, Task, and Initiative pages. Auto-create the reciprocal entry when an @-mention is inserted.
- **User impact:** The workspace reads as a connected graph; "what references this project?" is answered in place.
- **Effort:** M
- **Dependencies:** Shares the reverse-link index with the cross-app backlink work (CP-8).

### NP-10 — Wiki / verified pages + a composable Home dashboard
- **Gap:** "Home" is a fixed dashboard of hard-coded sections (quick actions, open-tasks prefix(6), pages prefix(8), recent meetings). There's no editable wiki home, no "verified/owner" page metadata, no pinned/structured knowledge base.
- **Evidence:** `tasksDashboard` is entirely static layout (`ActionItemsChrome.swift:8-105`).
- **Recommendation:** Make Home an editable page (block doc, NP-4) the user composes from linked database views (NP-8), favorites (NP-14), and rich text. Add optional page metadata (owner, verified, last-reviewed) à la Notion Wiki for a knowledge base.
- **User impact:** A real team/personal home + wiki, not a fixed widget board.
- **Effort:** M
- **Dependencies:** NP-4, NP-8, NP-14.

### NP-11 — Embeds & file/image blocks
- **Gap:** No way to embed an image, file, PDF, video, Figma/Loom, or bookmark in a page. Notion pages routinely carry these.
- **Evidence:** Editor handles text-only markdown; no media block path (`MarkdownEditor.swift`); slash menu has no image/embed (`:548-560`).
- **Recommendation:** Add image/file blocks (store under the vault, reference by relative path so it stays local-first/portable) and a bookmark/link-preview block. URL embeds render a thumbnail card. Pair with meeting artifacts — embed the recording/transcript snippet directly in a project page.
- **User impact:** Pages hold the whole context (designs, docs, recordings), not just prose.
- **Effort:** M
- **Dependencies:** NP-4.

### NP-12 — Synced blocks (one block, many pages, edit anywhere)
- **Gap:** No synced/transcluded content. Notion's synced blocks keep a snippet identical across pages.
- **Evidence:** Single-string bodies (`Project.body`); no block identity to sync. Missing entirely.
- **Recommendation:** After NP-4, give blocks stable IDs and add a `syncedRef` block that transcludes another block's content and edits write back to the source. Highest-value first use: a synced "Decisions" or "Risks" block shared between a meeting page and its project.
- **User impact:** Single source of truth for shared snippets across the workspace.
- **Effort:** L
- **Dependencies:** NP-4.

### NP-13 — Page covers + richer icon picker (custom/emoji), and gallery off them
- **Gap:** Pages have an SF-Symbol icon from a 10-item hard-coded list and an accent color, but no page **cover** image and no emoji/custom-upload icon. Notion's covers/emoji are core to a browsable, visual workspace (and feed Gallery view).
- **Evidence:** Icon menu is a fixed 10-symbol list (`ActionItemsProjectPage.swift:22-26`); `Project` has no `coverImage` field (`Project.swift:9-34`).
- **Recommendation:** Add `coverImageRef` + emoji/custom icon support to `Project`/`Initiative`; render a cover band on the page header; use cover+icon as the card face in Gallery view (NP-2).
- **User impact:** Visually scannable, "designed" workspace — a big part of why people *enjoy* Notion.
- **Effort:** S
- **Dependencies:** Cover feeds NP-2 gallery.

### NP-14 — Favorites / pinned sidebar section & reorderable sidebar organization
- **Gap:** No favorites/pinned pages. The sidebar is fixed-order sections (Initiatives, Pages, Meeting notes); you can't pin the 3 pages you live in to the top. Notion's Favorites is a primary nav affordance.
- **Evidence:** `ProjectRail` renders fixed sections with no favorites concept (`ActionItemsSidebar.swift:44-113`); no `isFavorite`/pin field on `Project`.
- **Recommendation:** Add a `favoriteProjectIDs` set in `AppSettings` and a "Favorites" sidebar section above Initiatives; right-click → "Add to favorites". Optionally persist manual sidebar order.
- **User impact:** One-click to the pages that matter; the workspace feels personal.
- **Effort:** S
- **Dependencies:** None.

### NP-15 — Comments (page-level and block-level)
- **Gap:** No comments anywhere. Notion comments on pages/blocks are central to collaboration and to "decisions/discussion captured in context" — directly adjacent to MeetingScribe's meeting story.
- **Evidence:** No comment model in `ActionItems/`; grep finds none.
- **Recommendation:** Add a lightweight `Comment { id, targetID, blockID?, author, body, createdAt, resolved }` store; render a comment thread rail on Task/Project pages and inline block-comment markers (after NP-4). Single-user value: durable annotations on AI-generated content ("verify this", "wrong owner").
- **User impact:** Annotate and resolve discussion on the exact task/decision; supports eventual multi-user.
- **Effort:** M
- **Dependencies:** Block comments need NP-4; page-level comments stand alone.

### NP-16 — Full-text search *inside* page/task bodies, surfaced in-app with deep links
- **Gap:** Global search scores project `body` and task `notes`, but there's no in-Tasks search across page content, no jump-to-match, and the database search box only filters the visible task list by metadata.
- **Evidence:** `search()` includes `p.body`/`i.notes` haystacks (`WorkspaceIndex.swift:181-194`) but only as a contains-flag for ranking — no snippet/highlight/match-location; the tab's own search field filters tasks, not page text (`ActionItemsChrome.swift:342-345`).
- **Recommendation:** Return match snippets + entity-deep-links from `search()`, and add an in-page "find in page" + a workspace-wide content search that lands on the block. Consider an FTS index over bodies (People already use FTS5) for scale.
- **User impact:** "Where did we decide X?" returns the exact page and line — the knowledge-base payoff.
- **Effort:** M
- **Dependencies:** Benefits from NP-4 (block addressing) for jump-to-block.

### NP-17 — Breadcrumb spine & in-pane navigation for the page hierarchy
- **Gap:** Task pages show a one-level breadcrumb ("Tasks" / project name); Project and Initiative pages show none, so a deep `Initiative › Project › Sub-page › Task` location is invisible and you can't click an ancestor to navigate up. Notion's breadcrumb is always-present and clickable.
- **Evidence:** `TaskPageView.breadcrumb` is a single string (`TaskPageView.swift:70-79`); `ProjectPageHeader`/`InitiativePage` render no breadcrumb (`ActionItemsProjectPage.swift`).
- **Recommendation:** Compute the full ancestor chain (`initiativeID` → `parentID*`) and render a clickable breadcrumb on every page header. (Pairs with the global back/forward in CP-5.)
- **User impact:** Always know where you are; jump up the tree in one click.
- **Effort:** S
- **Dependencies:** None.

### NP-18 — Editable, inline-property table view (database table parity)
- **Gap:** The table view shows Owner/Priority/Due as **read-only text**; you must open the task to edit them. A Notion database table edits every cell in place, and can show/hide/reorder columns.
- **Evidence:** Owner is `Text(item.owner ?? "—")`, priority is plain `Text`, due is `Text(dueShort())` — all non-interactive (`ActionItemsTableView.swift:88-94`). No column show/hide/reorder; columns are hard-coded (`tableHeaderRow:40-54`).
- **Recommendation:** Make every cell an inline editor (reuse the list-row menus/popovers), and drive visible columns + order from the property set (NP-1) via the saved view (NP-2/NP-3). Add column resize/hide.
- **User impact:** Spreadsheet-speed editing — the table finally behaves like a database, not a report.
- **Effort:** M
- **Dependencies:** Inline edit standalone; columns-from-properties needs NP-1/NP-2.

### NP-19 — Calendar & timeline views off task/page dates (meeting-driven)
- **Gap:** Tasks carry `startDate`/`dueDate` and projects link meetings with dates, but there's no calendar or timeline/Gantt to see the schedule. Notion's Calendar/Timeline are headline view types, and dates here come "free" from meetings.
- **Evidence:** Only list/table/board exist (`ActionItemsView.ViewMode:46`); `startDate`/`dueDate` on `ActionItem.swift:42,32` are unused beyond a property field.
- **Recommendation:** Add Calendar (month/week off due/start) and Timeline (start→due bars grouped by project/initiative) as view kinds under NP-2. Overlay linked meeting dates so the plan and the calls sit on one timeline.
- **User impact:** See when work and meetings land; plan visually — a major Notion view users expect.
- **Effort:** M
- **Dependencies:** NP-2.

### NP-20 — Hover-preview / side-peek a page or task without leaving context
- **Gap:** Opening a task/sub-page swaps the whole right pane (`selectedTaskID`/`selectedProjectID`), losing the database you were in; there's no peek or hover-preview. Notion's peek + hover preview is core knowledge-base UX (also flagged app-wide in CP-1/CP-4).
- **Evidence:** Selecting a row sets `selectedTaskID` and replaces the pane (`ActionItemsView.swift:133-152`); no overlay/peek path.
- **Recommendation:** Reuse the planned side-peek (CP-1) inside Tasks: clicking a database row peeks the task page over the table; hovering a `meetingscribe://` link previews the target. "Open full" promotes it.
- **User impact:** Triage and cross-reference without losing your place — the connected-workspace feel.
- **Effort:** M
- **Dependencies:** CP-1 side-peek infra; NP-4 helps preview rendering.

### NP-21 — Database-level properties: created/edited time, created-by, and formula columns
- **Gap:** `ActionItem` stores `createdAt`/`updatedAt` but they're never exposed as sortable/filterable/displayable properties, and there are no formula properties (e.g. "days until due", "is overdue", status emoji).
- **Evidence:** `createdAt`/`updatedAt` set on every write (`ActionItemStore.update:540`) but absent from table columns and filters (`ActionItemsTableView.swift:40-54`).
- **Recommendation:** Surface created/edited time as built-in properties (column + sort + "edited last 7 days" filter), and add a `formula` property type (NP-1) with a small safe expression set over other properties.
- **User impact:** "Recently changed," "overdue in N days," computed status — the analytic columns power users build in Notion.
- **Effort:** M
- **Dependencies:** NP-1 (formula), NP-2/NP-18 (column surfacing).

---

## Top 5 picks

1. **NP-1 — Custom typed database properties.** The keystone. Without user-defined properties the feature is a styled task list, not a Notion-replaceable database. Unblocks NP-2, NP-5, NP-7, NP-8, NP-9, NP-18, NP-21. **Phase 1 foundation.**
2. **NP-2 — Multiple saved database views (+ calendar/gallery/timeline).** The defining Notion mental model: many lenses on one dataset. Highest perceived-parity jump per the comp set; lifts NP-3, NP-8, NP-19.
3. **NP-7 — AI auto-extracts into typed properties.** The differentiator Notion structurally can't match: your calls populate your *schema*, not just task titles. Turns NP-1 into a reason to switch, not just feature-match.
4. **NP-4 — True block-based doc model.** Converts pages from a markdown blob into real documents and is the substrate for embeds (NP-11), synced blocks (NP-12), block comments (NP-15), and jump-to-block search (NP-16).
5. **NP-9 — Bidirectional links & backlinks panel on every page.** Cheap, high-signal: makes the workspace a connected graph (answers "what references this?") and reuses the existing `meetingscribe://` link plumbing + a shared reverse-link index.

**Sequencing:** NP-1 → (NP-2, NP-18, NP-21) → (NP-7, NP-5, NP-8) database layer; NP-4 → (NP-11, NP-12, NP-15, NP-16) doc layer; NP-9/NP-13/NP-14/NP-17/NP-20 are independent quick-to-medium wins that make the existing surface feel like Notion immediately.
