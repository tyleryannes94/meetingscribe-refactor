import SwiftUI

/// A persisted, named filter combination for the Meetings list (C1-5). Selecting
/// a saved view re-applies its scope + filters in one click, so common slices
/// ("Customer calls", "1:1s", "this project") become tabs alongside
/// All / Upcoming / Past.
///
/// `scopeRaw` mirrors `MeetingsView.Scope.rawValue` ("all" / "upcoming" / "past")
/// so this model stays decoupled from the view's nested enum. Person filtering is
/// intentionally absent — attendee→person resolution lives in PeopleStore, which
/// isn't in the Meetings list's environment; tag / source / has-recording cover
/// the shipped dimensions.
struct SavedView: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Matches `MeetingsView.Scope.rawValue`.
    var scopeRaw: String
    var tagID: String?
    var source: MeetingSource?
    var requiresRecording: Bool
}

/// JSON ⇄ String bridge so the saved-view array round-trips through a single
/// `@AppStorage` String (the same lightweight-prefs idiom the Meetings tab uses
/// for `meetings.scope`). Decode is tolerant: malformed/empty payloads yield `[]`.
enum SavedViewStore {
    static func decode(_ json: String) -> [SavedView] {
        guard let data = json.data(using: .utf8), !data.isEmpty,
              let views = try? JSONDecoder().decode([SavedView].self, from: data)
        else { return [] }
        return views
    }

    static func encode(_ views: [SavedView]) -> String {
        guard let data = try? JSONEncoder().encode(views),
              let json = String(data: data, encoding: .utf8)
        else { return "" }
        return json
    }
}

/// Lightweight sheet that names the current filter combination and saves it as a
/// new tab. Shows a read-only summary of what will be captured so the user knows
/// exactly what the named view will pin.
@available(macOS 14.0, *)
struct SaveViewSheet: View {
    let scopeLabel: String
    let tagName: String?
    let sourceName: String?
    let requiresRecording: Bool
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""

    private var summaryParts: [String] {
        var parts = [scopeLabel]
        if let tagName { parts.append("Tag: \(tagName)") }
        if let sourceName { parts.append("Source: \(sourceName)") }
        if requiresRecording { parts.append("Has recording") }
        return parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Save view").scaledFont(15, weight: .semibold)
                    .foregroundStyle(NDS.textPrimary)
                Text("Pin the current filters as a one-click tab.")
                    .scaledFont(12)
                    .foregroundStyle(NDS.textSecondary)
            }

            TextField("View name", text: $name)
                .scaledFont(13)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(NDS.hairline, lineWidth: 1))
                .onSubmit(commit)

            VStack(alignment: .leading, spacing: 5) {
                Text("Captures").scaledFont(10, weight: .semibold)
                    .foregroundStyle(NDS.textTertiary)
                FlowChips(parts: summaryParts)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(NDS.bg)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}

/// Read-only chip row summarizing a saved view's captured filters.
@available(macOS 14.0, *)
private struct FlowChips: View {
    let parts: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(parts, id: \.self) { p in
                Text(p)
                    .font(NDS.tiny)
                    .foregroundStyle(NDS.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(NDS.fieldBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 1))
            }
        }
    }
}
