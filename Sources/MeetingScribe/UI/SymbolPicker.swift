import SwiftUI

/// Searchable SF Symbol picker (VD-16). Replaces the hardcoded 10-symbol menus
/// on project/initiative headers so pages can have distinct, scannable icons.
/// Bindable to the stored symbol name; renders as a tinted rounded tile grid.
@available(macOS 14.0, *)
struct SymbolPicker: View {
    @Binding var selection: String
    var tint: Color = NDS.brand
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: NDS.spaceSM), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: NDS.spaceMD) {
            MSSearchField(placeholder: "Search symbols", text: $query, autoFocus: true)
            ScrollView {
                LazyVGrid(columns: columns, spacing: NDS.spaceSM) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            selection = name
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .scaledFont(16, weight: .medium)
                                .frame(width: 34, height: 34)
                                .foregroundStyle(name == selection ? .white : tint)
                                .background(
                                    RoundedRectangle(cornerRadius: NDS.radius, style: .continuous)
                                        .fill(name == selection ? tint : tint.opacity(0.12))
                                )
                                .accessibilityLabel(name)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, NDS.spaceXS)
            }
        }
        .padding(NDS.spaceMD)
        .frame(width: 320, minHeight: 360)
    }

    private var filtered: [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Self.symbols }
        return Self.symbols.filter { $0.contains(q) }
    }

    /// A curated, render-safe SF Symbol set for page/project icons — broad
    /// enough to give pages identity without shipping the full catalog.
    static let symbols: [String] = [
        "folder", "folder.fill", "doc", "doc.text", "tray.full", "archivebox",
        "flag", "flag.fill", "bookmark", "star", "star.fill", "heart",
        "bolt", "flame", "sparkles", "lightbulb", "target", "scope",
        "calendar", "clock", "checklist", "list.bullet", "checkmark.circle",
        "person", "person.2", "person.3", "building.2", "briefcase",
        "hammer", "wrench.and.screwdriver", "gearshape", "paintbrush", "ruler",
        "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis", "gauge",
        "globe", "map", "location", "airplane", "car", "house",
        "cart", "creditcard", "dollarsign.circle", "banknote",
        "envelope", "bubble.left", "phone", "megaphone", "bell",
        "book", "graduationcap", "pencil", "highlighter", "paperclip",
        "leaf", "drop", "sun.max", "moon", "cloud", "music.note",
        "gamecontroller", "camera", "photo", "film", "mic", "headphones"
    ]
}
