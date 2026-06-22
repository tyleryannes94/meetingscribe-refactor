import SwiftUI

/// Inline "type-and-Enter" task creation, mirroring the subtask quick-add on
/// `TaskPageView`. Collapsed state shows a `+ Add task` row; on click it
/// becomes a focused text field. Pressing Enter creates the task via
/// `ActionItemStore.quickCreate(...)`, clears the field, and keeps focus so
/// the user can rip off several tasks back-to-back without ever leaving the
/// view. ESC or losing focus on an empty field collapses back to the button.
///
/// Used by the List, Board (one per column), Table, and Today views so a
/// task can be captured wherever the user already is, with the surrounding
/// context (project, section, status, due-date filter) inherited as defaults.
@available(macOS 14.0, *)
struct QuickAddTaskField: View {
    let placeholder: String
    let projectID: String?
    let sectionID: String?
    let status: ActionItem.Status
    /// When the view that owns this field implies a due date (e.g. the Today
    /// smart view, a "due this week" filter), pass it here so new captures
    /// don't fall off the end of the list the moment they're created.
    var contextDueDate: Date? = nil
    /// When the view that owns this field implies one or more labels (a label
    /// smart view, a tag-scoped board), they get applied to the new task.
    var contextLabelIDs: [String] = []
    /// Auto-collapse to the button when focus is lost AND the field is empty.
    /// Boards leave this off so the inline input stays open per column.
    var collapseOnBlur: Bool = true

    @EnvironmentObject var store: ActionItemStore
    @State private var draft: String = ""
    @State private var expanded: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if expanded {
                expandedField
            } else {
                collapsedButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedButton: some View {
        Button {
            expanded = true
            DispatchQueue.main.async { focused = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(NDS.brand.opacity(0.85))
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: NDS.rowRadius))
    }

    private var expandedField: some View {
        HStack(spacing: 8) {
            Image(systemName: status.systemImage).foregroundStyle(.secondary)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand {
                    draft = ""
                    expanded = false
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused && collapseOnBlur
                        && draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        expanded = false
                    }
                }
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: commit)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NDS.rowRadius)
                .strokeBorder(NDS.brand.opacity(focused ? 0.5 : 0.15), lineWidth: 1)
        )
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.quickCreate(parsing: trimmed,
                          projectID: projectID,
                          sectionID: sectionID,
                          status: status,
                          contextDueDate: contextDueDate,
                          contextLabelIDs: contextLabelIDs)
        draft = ""
        // Keep focus so the user can rattle off the next task immediately,
        // matching the rhythm of the subtask quick-add on TaskPageView.
        DispatchQueue.main.async { focused = true }
    }
}
