# G3 — Cross-Tab Pattern & Component Consistency

Lens: the same interaction (list, select, search, tag, empty/loading) should look and behave identically in every tab, backed by shared primitives so we optimize (lazy render, skeletons, keyboard nav, caching) once and get it everywhere.

## Audit (through my lens)

I verified against live source, not the old plan. The prior `UX_QUICKWINS_PLAN.md` / Build Playbook explicitly scoped a shared search field (`UX9-4/FT9-1`), actionable empty states (`UX9-1`), and loading skeletons (`FT9-2`) — but **none of the shared components were built**. Only a one-off Meetings empty-state CTA shipped (per `SESSION_IMPROVEMENTS_2026-05-31.md`). So the consistency work is still open, and this audit specifies the actual component architecture rather than re-stating "make them consistent."

### 1. List primitive is forked three ways — keyboard nav is inconsistent
- **People** uses native `List(selection:)` — `PeopleListView.swift:227` (multi-select) and `:236` (single-select). This gives free arrow-key navigation, type-ahead, and selection highlight.
- **Meetings** uses `ScrollView { LazyVStack { ForEach { Button } } }` — `MeetingsView.swift:153-182`, row at `:176`. **No keyboard navigation, no selection model** — you can only mouse-click rows.
- **Tasks** uses the same ScrollView+Button pattern in three view modes — `ActionItemsListView.swift:12/67/104`, `ActionItemsTableView.swift:9-13`, `ActionItemsBoardView.swift:9-52`. Again **no list keyboard nav**.
- **Today** is ScrollView+Button cards (`TodayView.swift:45,117,176,210,268`).
- **Global search** is the *only* place with hand-rolled arrow-key nav (`GlobalSearchView.swift:67-69` `onKeyPress(.downArrow/.upArrow/.escape)`).
- Net: arrow keys move the selection in People, do nothing in Meetings/Tasks, and are custom-coded in Search. `QuickNotesView.swift:55` adds a *fourth* variant (`List(selection:)` again). There is no keyboard "open selected" (Return) in any list except Search's `onSubmit`.

### 2. Search fields — four+ hand-rolled copies, no `.searchable`, divergent styling
Zero use of SwiftUI `.searchable` anywhere. Each tab rebuilds an `HStack { magnifyingglass + TextField + clear-X }`:
- `MeetingsView.swift:100-119` — radius **8**, icon 12pt, clear button `.plain`, has hairline overlay.
- `PeopleListView.swift:205-216` — radius `NDS.radius`, clear button `.borderless`, no overlay.
- `ActionItemsChrome.swift:343-348` — radius **7**, fixed width 130, no clear button at all.
- `GlobalSearchView.swift:99-108` — `.title3` font, has `.focused` + `.onSubmit` + Esc clear.
- `PersonDetailView.swift:1873`, `Graph/GraphFilterBar.swift:18`, `iPhone/ContactsImportView.swift:71` — three more variants.
Result: inconsistent corner radius (7/8/NDS.radius), inconsistent clear affordance, only Global Search supports Esc-to-clear, no tab supports ⌘F-to-focus (`keyboardShortcut("f")` appears nowhere).

### 3. Tag UI is forked into two parallel stacks with different interaction models
- **Meetings** tag via `TagPicker.swift` — a chip row + "+" that opens a **popover with a checkbox list** + inline create. Backed by `TagStore`. Used only by `MeetingDetailHeader.swift` and `MeetingCard`/`TodayView` (read-only chips via `TagChipMini`, `MeetingCard.swift:349`).
- **People** tag via a completely separate stack: `PeopleTagStore`, a **Menu**-based "Add tag" (`PersonDetailView.swift:448-489`), `EventTagSelector` popover (`AddPersonSheet.swift:93`), and `TagManagementSheet.swift` for rename/delete. `TagChip` is shared (`TagPicker.swift:91`) but the *picker* is not.
- Net: two tag stores, two add-tag interaction patterns (popover-checkbox vs Menu), and rename/delete exists only for people-tags. Tagging a meeting and tagging a person feel like different apps.

### 4. Empty states — four divergent implementations, mixed actionability
- `MeetingsView.swift:187` — icon 32pt, `.font(.headline)`, actionable (record CTA).
- `TodayView.swift:495` — icon 36pt, actionable (import), `UntitledSecondaryButtonStyle`.
- `ActionItemsChrome.swift:409` — icon 40pt, actionable, `.borderedProminent`.
- `PeopleListView.swift:397` — icon 36pt, **no CTA / dead-end**.
Different icon sizes (32/36/40), different title fonts, three different button styles, mixed actionability. No use of `ContentUnavailableView` (macOS 14+) despite the plan calling for it.

### 5. No loading/skeleton state anywhere — only bare spinners
`grep redacted|Skeleton|shimmer` → zero hits in `UI/`+`People/`. Loading is `ProgressView()` only (e.g. `ActionItemsChrome.swift` sync spinner). First-open and transcribe/summarize show spinners or empty panes, never a skeleton of the eventual layout — so cold open *feels* slow even when data is cached.

### 6. Context menus are inconsistent on list rows
`.contextMenu` exists on `MeetingDetailHeader.swift:716`, `ActionItemsSidebar.swift:197/312/393`, `TaskRowView.swift:68`, `Graph/PersonNodeView.swift:89`, `PersonDetailView.swift:960` — but **NOT** on Meetings list rows (`MeetingListRow`) or People list rows (`PersonRow`). Right-clicking a meeting or person in the main list does nothing; right-clicking a task or graph node gives a menu.

### 7. Two button-style families coexist
`NotionDesign.swift` defines both `Untitled{Primary,Secondary}ButtonStyle` (`:253/:267`) and `MS{Primary,Secondary,Danger,Tertiary}ButtonStyle` (`:284-331`). Tabs mix them (TodayView uses Untitled*, ActionItems uses `.borderedProminent`, People bulk bar uses raw `Button`). No single canonical button vocabulary.

## NET-NEW recommendations

**SC-1 — `MSList` selectable-list primitive (one list, keyboard everywhere).** Build a generic `MSList<Item, Row>` wrapping `List(selection:)` with a `LazyVStack`-backed fast path, standard selection highlight, arrow-key nav, Return-to-open, and an optional `onDelete`. Migrate Meetings (`MeetingsView.swift:153`), all three Tasks views, Today card columns, and QuickNotes onto it; People is already `List(selection:)` so it becomes the reference impl. *UX:* keyboard select/open works in every tab (today: only People + custom Search). Opening the 5th meeting: mouse-only (1 click after scroll) → ↓↓↓↓⏎ (zero mouse). *Perf/stability:* one place to tune lazy rendering, row recycling, and `.id()` churn (MeetingsView re-creates rows on selection at `:74` — fix once); native `List` recycles cells, lowering memory on long lists vs unbounded LazyVStack. Cache-friendly: list reads from already-persisted stores, no new I/O. *Effort:* L. *Impact:* High. *Deps:* none (foundational).

**SC-2 — `MSSearchField` shared component + ⌘F-to-focus + Esc-to-clear.** One view: leading magnifyingglass, plain `TextField`, trailing clear-X, `NDS.radius`, hairline, `@FocusState`, Esc clears, `keyboardShortcut("f")` focuses the current tab's field. Replace the 7 copies (`MeetingsView:100`, `PeopleListView:205`, `ActionItemsChrome:343`, `GlobalSearchView:99`, `PersonDetailView:1873`, `GraphFilterBar:18`, `ContactsImportView:71`). *UX:* identical search affordance + ⌘F in every tab (today ⌘F does nothing anywhere); Esc-to-clear everywhere (today only Search). *Perf/stability:* trivial; centralizes a `.debounce` so each tab's filter recomputes on a throttle instead of per-keystroke (Tasks/People filter large arrays). *Effort:* S. *Impact:* High. *Deps:* none.

**SC-3 — `MSEmptyState` built on `ContentUnavailableView`.** One component taking icon, title, message, and optional primary/secondary actions. Replace the four divergent empties (`MeetingsView:187`, `TodayView:495`, `ActionItemsChrome:409`, `PeopleListView:397`) and give People list a CTA (today a dead-end). *UX:* consistent sizing/typography; every empty state is actionable (People list gains "Add person / Import"). *Perf/stability:* none (cheaper — drops bespoke layout code). *Effort:* S. *Impact:* Med. *Deps:* SC-1 nice-to-have (lists host it).

**SC-4 — `MSSkeleton` loading primitive (redacted placeholders).** A reusable skeleton that renders N greyed/`.redacted(reason:.placeholder)` rows matching the real row layout, with a subtle shimmer. Show it on first-open of each list while stores hydrate, and in the meeting detail during transcribe/summarize instead of a bare spinner. *UX:* cold open *feels* instant — the structure paints immediately, then fills. *Perf/stability:* pure win for perceived first-open; pair with SC-6 so the skeleton is shown only until the persisted cache resolves (usually <1 frame on warm cache), avoiding flash. No extra memory (placeholders are discarded on data arrival). *Effort:* M. *Impact:* High (directly serves the first-open hard constraint). *Deps:* SC-1.

**SC-5 — Unified `MSTagPicker` over a tag-source protocol.** Define `TagSource` (allTags / tags(for:) / add / remove / create / rename / delete) and adopt it in both `TagStore` and `PeopleTagStore`. Build one `MSTagPicker(source:)` (chip row + popover-with-checkboxes + inline create, the `TagPicker.swift` model) and one `MSTagManagementSheet`. Replace the Menu-based people flow (`PersonDetailView:448`, `EventTagSelector`) and the meeting `TagPicker`. *UX:* tagging a person and a meeting are identical (today: Menu vs popover); rename/delete available for both (today people-only). Tag a person: open detail → Menu → pick (still 2) but now matches Meetings; gains multi-toggle popover. *Perf/stability:* one cached `allTags` query path; popover lazy-loads its list. *Effort:* M. *Impact:* Med. *Deps:* none, but pairs with SC-7.

**SC-6 — Persisted list-snapshot cache feeding every `MSList` on cold start.** Add a tiny per-tab on-disk snapshot (codable array of the lightweight row models: id/title/date/subtitle/tagIDs) written on store mutation, read synchronously at launch so `MSList` paints real rows before the full stores finish loading. *UX:* first open of Meetings/People/Tasks shows actual content immediately, not a spinner. *Perf/stability:* this is the central first-open accelerator — pairs with SC-4 (skeleton only if no snapshot yet). Bounded memory (row models only, not bodies); crash-safe (atomic write, snapshot is disposable/rebuildable). *Effort:* M. *Impact:* High. *Deps:* SC-1.

**SC-7 — Row-level context menu in the `MSList` row protocol.** Give `MSList` a `contextMenu` builder so every row (meeting, person, task, note) gets a right-click menu with the tab's primary actions (open, tag via SC-5, delete, copy link). Fills the gap on `MeetingListRow` and `PersonRow` (today no menu) and matches Tasks/graph which already have one. *UX:* right-click works the same on every list row; common actions reachable in 1 click without opening detail. *Perf/stability:* menus build lazily on invoke — no scroll cost. *Effort:* S. *Impact:* Med. *Deps:* SC-1, SC-5.

**SC-8 — Collapse to one button-style vocabulary.** Pick one family (recommend `MS*`) and delete/alias `Untitled*` (`NotionDesign.swift:253/267`); replace ad-hoc `.borderedProminent` / raw `Button` (ActionItems empty, People bulk bar) with `MSPrimary/Secondary/Tertiary/Danger`. *UX:* consistent button weight/hierarchy across tabs. *Perf/stability:* negligible; reduces style surface. *Effort:* S. *Impact:* Low-Med. *Deps:* none.

## Top 3 picks

1. **SC-1 — `MSList` selectable-list primitive** — Phase **1** (foundational). Unifies selection + keyboard nav and is the host for SC-3/4/6/7; fixes the per-selection row re-creation in MeetingsView. The single highest-leverage item: it makes Meetings/Tasks keyboard-navigable like People and gives us one place to optimize lazy rendering and memory.
2. **SC-6 — Persisted list-snapshot cache** — Phase **1** (perf/infra). The core first-open accelerator: real rows paint from disk before stores hydrate. Directly serves the audit's speed/first-open hard constraint.
3. **SC-2 — `MSSearchField` + ⌘F/Esc** — Phase **2** (high-visibility UX). Cheap, replaces 7 forks, and adds universal ⌘F-focus + Esc-clear + debounced filtering.

Sequencing: P1 = SC-1, SC-6, SC-4 (skeleton). P2 = SC-2, SC-3 (search + empty states). P3 = SC-5, SC-7 (unified tag picker + row context menus). P4 = SC-8 (button vocabulary polish).
