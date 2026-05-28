import SwiftUI

/// The control strip above the mindmap canvas (Phase 7): a horizontally
/// scrolling list of tag chips (toggle to filter), a search field (matching
/// nodes stay bright, the rest fade), and Reset / Re-layout / List-View
/// actions. Binds straight to the `PeopleGraphViewModel`.
@available(macOS 14.0, *)
struct GraphFilterBar: View {
    @Bindable var viewModel: PeopleGraphViewModel
    /// Tags present in the current people set, resolved to (id, name, color).
    let availableTags: [GraphTagPill]
    var onExit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(NDS.textTertiary)
                TextField("Search people…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                if !viewModel.searchQuery.isEmpty {
                    Button { viewModel.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                }

                Divider().frame(height: 16)

                Button {
                    viewModel.resetFilters()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Clear search and tag filters")

                Button {
                    viewModel.applyForceLayout()
                } label: {
                    Label("Re-layout", systemImage: "wand.and.stars")
                }
                .help("Re-run the force layout")

                Button {
                    onExit()
                } label: {
                    Label("List View", systemImage: "list.bullet")
                }
                .help("Back to the people list")
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))

            if !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableTags) { tag in
                            let active = viewModel.selectedTags.contains(tag.id)
                            Button { viewModel.toggleTag(tag.id) } label: {
                                Text(tag.name)
                                    .font(NDS.tiny)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .foregroundStyle(active ? .white : tag.color)
                                    .background(active ? tag.color : tag.color.opacity(0.14), in: Capsule())
                                    .overlay(Capsule().strokeBorder(tag.color.opacity(active ? 0.0 : 0.4), lineWidth: 1))
                                    .scaleEffect(active ? 1.06 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: active)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }
}
