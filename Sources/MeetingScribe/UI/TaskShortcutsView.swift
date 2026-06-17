import SwiftUI

/// Keyboard-shortcut cheat-sheet for the Tasks tab (UX-22) — makes the
/// otherwise-invisible navigation/quick-add keys discoverable.
@available(macOS 14.0, *)
struct TaskShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(keys: String, action: String)] = [
        ("⌥⌘N", "New task (natural-language quick-add)"),
        ("↑ / ↓  ·  J / K", "Move the list cursor"),
        ("Return", "Open the focused task"),
        ("Space", "Toggle the focused task done"),
        ("Click the list first", "to focus it, then use the keys above")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "keyboard").foregroundStyle(NDS.textSecondary)
                Text("Keyboard shortcuts").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(NDS.divider)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        Text(row.keys)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(NDS.brand)
                            .frame(width: 150, alignment: .leading)
                        Text(row.action).foregroundStyle(NDS.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    Divider().overlay(NDS.divider).opacity(0.4)
                }
            }
            Spacer()
        }
        .frame(minWidth: 440, maxWidth: 440, minHeight: 300)
        .background(NDS.bg)
    }
}
