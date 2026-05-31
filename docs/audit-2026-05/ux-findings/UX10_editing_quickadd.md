# Detail-Pane Editing & Quick-Add

Lens: every edit and every "create then immediately use" flow should be inline, autosaved, auto-focused, and reachable in ≤2 clicks — no modals for one-field fixes, no orphaned placeholder titles, no "press Enter or lose it."

## Lift from V4
- **PPL-1** (Phase 1) — inline person editing. The refactor already shipped inline identity editing in `PersonDetailView` (`beginIdentityEdit`/`saveIdentityEdit`, lines 337–359); extend that pattern to contact fields/tags so the `AddPersonSheet` modal is never required (see UX10-1).
- **D4-3** (Phase 3) — universal undo (toast + `UndoManager`). Directly de-risks autosave-on-blur and auto-delete-empty-on-create (FT10-2, UX10-2); cite as the safety net for the quick-add changes here.
- **DEF-3 / TDY-2** (Phase 1) — promote frequent create actions to the front. The Tasks dashboard `QuickActionCard`s and Today `QuickPill`s already do this; the gap is what happens *after* the click (UX10-2).
- **D1-5** (Phase 1) — clickable entity links. Pairs with FT10-4 (inline "create then link" from attendee chips).

## UX improvements (5)

### UX10-1 — Stop forcing the AddPersonSheet modal for field edits
- **Friction today:** `PersonDetailView` edits name/role/company inline (line 337+), but emails, phones, addresses, tags, birthday, and "favorite things" can ONLY be changed by opening the full `AddPersonSheet` modal (`showEdit = true`, `PersonDetailView.swift:455,562` → `:309`). That modal is a fixed 460×540 sheet (`AddPersonSheet.swift:102`) with no auto-focus. Fixing one phone number = 2 clicks to open + scroll + edit + Save + dismiss (≈4 interactions).
- **Fix:** Extend the existing inline-edit block to render the contact arrays (the `multiField` rows already exist) and the `EventTagSelector` inline in the identity panel. Reserve the modal only for first-time creation.
- **Clicks:** edit a phone 4→1 (click field, type, blur-save). Honors the 2-click rule inside a person.
- **Effort:** small-M.

### UX10-2 — Auto-focus + select the title on every "create" so rename is one keystroke
- **Friction today:** Every create path makes a placeholder-titled row and selects it but never focuses the title: `addTask()` → `createTask(title:"New task")` then `selectedTaskID` (`ActionItemsChrome.swift:403`), section `+` (`ActionItemsListView.swift:42`), board column `+` (`ActionItemsBoardView.swift:42`), dashboard cards (`ActionItemsChrome.swift:20,24`), Today `QuickPill` (`TodayView.swift:144`), and `createProject(name:"Untitled")`. The user lands on a task literally named "New task" and must hunt for the title field, click in, select-all, delete, then type. No `@FocusState` exists anywhere in the Tasks UI.
- **Fix:** Add `@FocusState` to the detail title field; on create, set it focused and pre-select the placeholder text so the first keystroke replaces it. (The inline `ActionItemRow.detailEditor` title at `TaskRowView.swift:345` is the focus target when `isExpanded`.)
- **Clicks:** rename a new task ~4→0 (just type).
- **Effort:** S.

### UX10-3 — Autosave title/name fields on blur, not only on Enter
- **Friction today:** All inline title fields commit ONLY via `onCommit` (Enter): `ProjectPageHeader` name (`ActionItemsProjectPage.swift:32`), `InitiativePage` name (`:213`), `ActionItemRow` Title and Assignee (`TaskRowView.swift:345,352`). A user who types a page title then clicks the body editor or another row loses the edit silently — a classic data-loss-feel bug. (Note the body editors already autosave via debounced timers — `MeetingNotesPage:385`, QuickNotes — so the pattern exists; titles are the inconsistent holdout.)
- **Fix:** Add a focus-loss handler (`.onChange(of: isFocused)` or `.onSubmit` + blur commit) that writes the draft when the field loses focus, mirroring the existing debounced-save pattern.
- **Clicks:** removes a silent failure; saves are now blur-safe. No added clicks.
- **Effort:** S.

### UX10-4 — Auto-focus the "New tag" / "New label" / "New section" fields when their UI opens
- **Friction today:** Creating a people tag opens a popover whose `TextField("New tag…")` is not focused (`AddPersonSheet.swift:232`) — extra click to focus. Same for the task "New label name" field (`TaskRowView.swift:483`) and the "Add section" inline field (`ActionItemsListView.swift:78`, set via `addingSection=true` with no focus). Each is one wasted click before typing.
- **Fix:** `@FocusState` bound to the field, set true when the popover/inline editor appears (`.onAppear` or on the toggle that reveals it).
- **Clicks:** create-a-tag 2→1 each. Reinforces "bring frequent actions to the front."
- **Effort:** S.

### UX10-5 — One-tap inline title rename on board cards and list rows (no detour into Edit Details)
- **Friction today:** To rename a task you must open the detail editor: a click toggles `isExpanded` (`TaskRowView.swift:178`) and only then does a Title field appear (`:345`); board cards have no rename at all — title is static `Text` (`ActionItemsBoardView.swift:117`) and the only menu route is "Set priority / Move / Delete." Renaming = 2 clicks minimum, board = impossible without switching to list.
- **Fix:** Double-click the row/card title to swap `Text` → focused inline `TextField` bound to `onTitle`, autosaving on blur (reuses UX10-3). Keeps the row compact; no panel detour.
- **Clicks:** rename in place 2→1; enables board rename (was impossible).
- **Effort:** small-M.

## Feature improvements (5)

### FT10-1 — Quick-add bar: type a title + Enter to create a task without opening detail
- **What/why:** Today every "New task" creates an empty placeholder row you then rename. Add a slim always-present "+ Add a task…" text row at the top of each list/section (and board column) — type, press Enter, task is created with that exact title, field stays focused for the next one (rapid entry, like Things/Todoist).
- **Value:** Capture a list of 5 tasks in 5 Enters instead of 5×(create→find→clear→type). Pairs with UX10-2.
- **Effort:** small-M. **Dependency:** none (`store.createTask(title:)` already takes a title).

### FT10-2 — Auto-discard untitled/empty quick-adds on blur
- **What/why:** Because create makes a placeholder immediately, abandoning the flow leaves litter named "New task"/"Untitled" in the vault. If a freshly-created item is left with the unchanged placeholder title and no other edits when it loses selection, silently delete it (with a 1-tap undo toast per D4-3).
- **Value:** Quick-add becomes consequence-free — create freely, only kept items survive.
- **Effort:** S. **Dependency:** D4-3 undo toast (recommended, not required).

### FT10-3 — Smart defaults on create from context (project, section, status, due)
- **What/why:** `createTask` already inherits the selected project/section/status (good). Extend: when created from a date-grouped list ("Tomorrow") prefill due=tomorrow; from a person's page prefill owner=that person; from a meeting prefill the linked meeting. The grouping keys already exist (`groupKey` in `ActionItemsListView.swift:212`).
- **Value:** The most common field is right before you touch it — fewer required edits per task.
- **Effort:** small-M. **Dependency:** none.

### FT10-4 — Inline "Add to People + link" from attendee/owner chips
- **What/why:** Attendee chips already have a right-click "Add to People" (`MeetingDetailHeader.swift:566`), but it's hidden in a context menu and doesn't open the new person for immediate use. Surface a visible "+ add" affordance on un-linked chips that creates the Person AND opens them inline for a quick role/tag add, then returns. Same for a task `owner` typed that matches no person → offer "create person."
- **Value:** Closes the "create then immediately use" loop between meetings↔people (fluid connection principle).
- **Effort:** small-M. **Dependency:** UX10-1 (inline person edit), D1-5.

### FT10-5 — Per-field "saved ✓" microconfirmation on autosave surfaces
- **What/why:** Inline editing + autosave is invisible — users don't trust that a blur saved. Add a tiny transient "Saved" tick next to a field after its debounced write fires (the timers already know when they flush: `MeetingNotesPage.flush()`, QuickNotes `flushRawSave`). Apply to title/notes/identity fields.
- **Value:** Builds trust in autosave-on-blur (makes UX10-1/-3 feel safe), no modal Save button needed.
- **Effort:** S. **Dependency:** UX10-3.

## Top 3 picks
1. **UX10-2 — auto-focus + select title on create** (S). The single highest-value low-lift win: every create path across Tasks, Today, and Pages currently dumps you on an item named "New task"; one `@FocusState` turns rename into pure typing.
2. **UX10-3 — autosave title fields on blur** (S). Kills a silent data-loss-feel bug (`onCommit`-only) that affects page names, initiative names, task titles, and assignees.
3. **UX10-1 — kill the AddPersonSheet modal for field edits** (small-M). Brings phone/email/tag editing inline, finishing the PPL-1 inline-edit story and honoring the 2-click rule inside a person.
