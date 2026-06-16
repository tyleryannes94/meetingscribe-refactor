# Interaction Design & Speed Findings — MeetingScribe Tasks Audit

**Agent ID:** D2 | **Lens:** Keyboard navigation, quick-add flows, inline editing, rapid task creation

---

## Top existing friction points (file:line citations)

### 1. Quick-add popover closes after one task — but only if you hit Esc

`ActionItemsChrome.swift:474–475` has a comment that says "Popover stays open + cleared for rapid multi-entry; Esc closes it." This is partially right: after `commitQuickAdd()` fires, `quickAddText` is cleared and the popover stays open. **The problem is focus.** A SwiftUI popover does not automatically refocus the `TextField` after submit — the field loses first-responder status. The user presses Enter and the cursor goes nowhere. Creating 5 tasks back-to-back means 4 extra clicks into the field between tasks. There is no `.focused()` binding or `@FocusState` in `quickAddPopover` (`ActionItemsChrome.swift:450–461`).

### 2. The in-app "New" button (⌥⌘N) and the global QuickEntryController are two different flows with different UX

The global floating panel (`QuickEntryWindow.swift:4–224`) correctly uses `@FocusState` and auto-focuses on `.onAppear` (line 196). The in-app popover in `ActionItemsChrome.swift:450` does **not**. A user who is already inside Tasks and hits ⌥⌘N gets the popover variant — the worse one.

### 3. "Tap to expand" opens a detail panel, not an editable row

`ActionItemsListView.swift:427–429`: `onToggleExpand` is wired to `selectedTaskID = item.id`, which opens the full `TaskPageView` side panel. This is fine for deep edits. But `isExpanded` in `ActionItemRow` (`TaskRowView.swift:17`) is never `true` from the list — `editingID` drives it, and `editingID` is a separate state variable that the list view appears to set only in `ActionItemsListView.swift:427`. Cross-referencing the `row(for:)` builder, `isExpanded: editingID == item.id` but `onToggleExpand` sets `selectedTaskID`, not `editingID`. The inline `detailEditor` (the expandable form in `TaskRowView.swift:414–492`) therefore never renders in normal list usage. The inline editing affordance built into `ActionItemRow` is entirely dead code from the user's perspective.

### 4. No keyboard shortcut to assign priority, due date, or project from the list

`TaskShortcutsView.swift:9–15` documents exactly 5 shortcuts: move cursor (↑↓ jk), open focused task (Return), toggle done (Space), new task (⌥⌘N). There is no `p` for priority, `d` for due date, `m` for move to project. Every property change from the list requires a mouse click into a popover or menu. This is the single biggest keyboard gap versus Asana/Linear/Things.

### 5. Title editing in the row requires expanding then committing with Return or Tab

`TaskRowView.swift:420–423`: the `TextField` for title uses `onCommit` — it saves only when the user presses Return. There is no debounce. `TaskPageView.swift:131–134` uses `onChange(of: titleDraft)` with live saves — the page and the row are inconsistent in save behavior.

### 6. Date picker in the row requires two clicks (chip → graphical calendar → Done)

`TaskRowView.swift:282–314`: clicking the due chip opens a popover with a full graphical `DatePicker`. "Done" requires a third click. For common relative dates ("today", "tomorrow") the user has to navigate a calendar. Notion and Things let you type "tom" or "fri" directly; this field only accepts clicks.

### 7. After pressing Enter in quick-add, view mode is reset to list but focus goes to the list body, not the quick-add

`ActionItemsChrome.swift:473`: `viewMode` is switched if needed, but neither `selectedTaskID` is cleared nor focus is returned to the text field. The keyboard cursor lands in the list (requiring a click or ⌥⌘N again to continue adding). The QuickEntryController global variant correctly re-focuses and clears (`QuickEntryWindow.swift:220–222`).

### 8. Keyboard navigation only works in the flat list — grouped and sectioned views are unsupported

`ActionItemsListView.swift:135–140`: `onKeyPress` handlers are attached only to `listBody`, and `moveFocus` operates on `projectFiltered` (line 146). When `groupBy != .none` the same `listBody` is used but the rendered order of `projectFiltered` may not match what's on screen (groups reorder items). The sectioned list (`sectionedListBody`, line 8) has zero keyboard handlers.

### 9. The inline subtask field in TaskPageView does not advance to a new line on Enter — it fires `addSubtask` and then focus is lost

`TaskPageView.swift:424–425`: `onCommit` + `onSubmit` both call `addSubtask()`, which clears `newSubtask`. No `@FocusState` keeps focus in the field, so adding 3 subtasks in a row requires clicking back into the field each time. This mirrors the quick-add focus problem.

### 10. Context menu for status exposes "Mark done / Mark open" as a top-level item AND inside a "Status" submenu

`TaskQuickActions.swift:26–39`: the toggle button and the full `Menu("Status")` submenu are both present. This is redundant and makes the menu visually noisy for the most common action.

---

## Existing items worth endorsing / prioritizing

- **QuickEntryController** (`QuickEntryWindow.swift`) is genuinely well-designed — non-activating panel, live-meeting annotation, focus-on-appear. It should be the canonical quick-add path; the in-app popover should mirror its behavior.
- **`TaskQuickAddParser`** parses `!priority`, `#label`, `@person`, `>name` (delegated), and NLDataDetector dates in one line. The grammar is solid; the friction is in the entry UI wrapping it, not the parser itself.
- **D3-2 completion animation** (TaskRowView.swift:217–238) — the Things-style beat on the status button is a good micro-interaction; keep it.
- **Bulk-select toolbar** (`ActionItemsListView.swift:182–228`) is well-executed for batch operations.
- **`moveFocus` + Space to toggle done** in `listBody` is a good foundation — just needs to be extended (see D2-3).

---

## NET-NEW recommendations

### D2-1: Refocus the quick-add text field after every submission
- **What:** Add `@FocusState private var quickAddFocused: Bool` to `quickAddPopover`. Bind it to the `TextField`. In `commitQuickAdd()`, after clearing `quickAddText`, set `quickAddFocused = true` (or trigger it via a short `DispatchQueue.main.async` if SwiftUI batches the state change). Same fix needed in `subtasks()` in `TaskPageView` and in `ActionItemRow.subtasksSection`.
- **Why:** Without auto-refocus, creating 5 tasks requires 4 extra mouse clicks. This is the single most direct fix for rapid task creation speed.
- **Effort:** S | **Impact:** High
- **Deps:** none

### D2-2: Wire `editingID` so the inline `detailEditor` in `ActionItemRow` is actually reachable
- **What:** In `ActionItemsListView.swift row(for:)`, change `onToggleExpand` to set `editingID = item.id` (and clear `selectedTaskID`) instead of always opening the page. Add a second gesture (double-click or Return) to open the full page. This way a single tap expands the inline editor; double-click or the `→` arrow key opens `TaskPageView`.
- **Why:** The inline `detailEditor` was built (`TaskRowView.swift:414–492`) but is unreachable. It enables fast property edits without leaving the list, which is exactly the Notion database-row-expand pattern users expect.
- **Effort:** S | **Impact:** High
- **Deps:** none

### D2-3: Keyboard property shortcuts in the list (p = priority, d = due, e = estimate, m = move)
- **What:** Extend the `.onKeyPress` block in `listBody` (currently `ActionItemsListView.swift:135–140`) to handle:
  - `p` → cycle priority on focused task (low → medium → high → urgent → low)
  - `d` → open due date popover anchored to focused row
  - `e` → open estimte picker
  - `m` → open project-move menu
  - `Delete` / `Backspace` → trash focused task with undo toast
  Also add these to `TaskShortcutsView` so they appear in the cheat sheet.
- **Why:** Linear, Asana, and Notion all support property keyboard shortcuts in list views. Without them the list is a read-only browser once you're keyboard-navigating. These are all one-keystroke actions that eliminate 2–3 clicks each.
- **Effort:** M | **Impact:** High
- **Deps:** D2-2 (to know which row is "focused")

### D2-4: Replace the graphical date-picker popover with a type-ahead date field
- **What:** Replace the `DatePicker(.graphical)` popover (used in `TaskRowView.swift:295–314` and `TaskPageView.swift:386–395`) with a `TextField` that pipes input through `TaskQuickAddParser`'s `NSDataDetector` path. Show the parsed date as a preview chip below the field. Fall back to the graphical picker via a calendar icon. Accept common shorthands: "tod", "tom", "fri", "6/12", "+3d".
- **Why:** The parser already handles all these inputs; it's only used in the quick-add bar, not in individual property fields. Two extra clicks (open popover → navigate calendar → Done) are avoidable for the 90% case where the user knows the date in natural language.
- **Effort:** M | **Impact:** High
- **Deps:** none

### D2-5: Extend keyboard navigation to sectioned and grouped list views
- **What:** In `sectionedListBody` (`ActionItemsListView.swift:8`), attach the same `.onKeyPress` handlers. Flatten the visible order across sections for `moveFocus`. Add `focusedTaskID` rendering (brand-colored left bar, `ActionItemsListView.swift:119`) to `sectionGroup` rows. Also handle the `grouped` case in `listBody` where `groupBy != .none`.
- **Why:** A user navigating a project with sections loses all keyboard shortcuts the moment sections are added. This creates an inconsistent experience and penalizes users who structure their work well.
- **Effort:** M | **Impact:** Med
- **Deps:** none

### D2-6: "Rapid-entry mode" — Enter creates a new task and immediately opens quick-add for the next one
- **What:** Add a `⌘Return` shortcut in the quick-add popover that (a) commits the current task and (b) immediately opens a new quick-add popover pre-positioned below the new task row, rather than dismissing. This is the Notion database "Tab to create new row" pattern. The existing `quickAddPopover` already stays open on Enter; this variant would also scroll the new task into view and highlight it.
- **Why:** Power users adding 10+ tasks from a meeting need a tight creation loop. The current path (⌥⌘N → type → Enter → ⌥⌘N again) is already faster than most competitors but `⌘Return` as "save + next" would cut the per-task overhead from 3 keystrokes (⌥⌘N) to 2 (⌘↩).
- **Effort:** S | **Impact:** Med
- **Deps:** D2-1

### D2-7: Collapse "Mark done/open" duplicate in context menu
- **What:** In `TaskQuickMenu` (`TaskQuickActions.swift:26–39`), remove the top-level `Button("Mark done / Mark open")` and let the `Menu("Status")` submenu be the only path. Rename the submenu title to "Set Status" and put the toggle action as the first checkmark item.
- **Why:** Two overlapping controls for the same action creates hesitation. The `statusButton` in the row already provides the one-click toggle; the context menu should be the power path (set to specific value), not a duplicate of the quick toggle.
- **Effort:** S | **Impact:** Low
- **Deps:** none

### D2-8: Persist quick-add popover position and make it keyboard-dismissible from anywhere
- **What:** The in-app quick-add popover (`ActionItemsChrome.swift:371–375`) is anchored to the "New" toolbar button, so on a wide monitor it pops up at the top-right corner, far from where the user is looking. Make it a floating `NSPanel` (like `QuickEntryController`) that appears at screen center (or remembers its last position). Wire `Esc` to dismiss it regardless of which view has focus.
- **Why:** The global `QuickEntryController` already does this correctly. Unifying both entry points to use the same panel removes the "which one do I use?" decision and eliminates the far-anchor UX issue.
- **Effort:** M | **Impact:** Med
- **Deps:** D2-1

---

## Top 3 picks

1. **D2-1 — Auto-refocus after quick-add submit** — the most direct fix for the "create 5 tasks" benchmark. S-effort, maximum impact on the stated goal.
2. **D2-2 — Wire inline detailEditor so single-tap expands, double-tap opens page** — unlocks a fully-built but currently dead interaction, making the list feel like Notion without building anything new.
3. **D2-3 — Keyboard property shortcuts (p/d/e/m)** — the keypress foundation already exists; adding 4 more handlers turns the list from a navigation widget into a real keyboard-driven task manager.
