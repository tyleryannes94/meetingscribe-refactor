import SwiftUI

/// ⌘K jump palette (3-1): a floating omnibox that searches initiatives, projects,
/// and tasks at once, each result showing its parent hierarchy. Selecting one
/// routes there. Tasks-scoped (not global search).
@available(macOS 14.0, *)
struct TasksJumpPalette: View {
    @ObservedObject var store: ActionItemStore
    @Binding var isPresented: Bool
    let onSelect: (TasksRoute) -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Hit: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let route: TasksRoute
    }

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var initiativeHits: [Hit] {
        guard !q.isEmpty else { return [] }
        return store.sortedInitiatives()
            .filter { $0.name.lowercased().contains(q) }
            .prefix(6)
            .map { Hit(id: "i" + $0.id, title: $0.name, subtitle: "Initiative",
                       icon: $0.icon ?? "flag.fill", route: .initiative($0.id)) }
    }
    private var projectHits: [Hit] {
        guard !q.isEmpty else { return [] }
        return store.projects
            .filter { $0.name.lowercased().contains(q) }
            .prefix(8)
            .map { p in
                let ini = p.initiativeID.flatMap { store.initiative(id: $0)?.name }
                return Hit(id: "p" + p.id, title: p.name,
                           subtitle: ini.map { "\($0) / Project" } ?? "Project",
                           icon: p.icon ?? "doc.text", route: .project(p.id))
            }
    }
    private var taskHits: [Hit] {
        guard !q.isEmpty else { return [] }
        return store.items
            .filter { !$0.isTrashed && $0.title.lowercased().contains(q) }
            .prefix(10)
            .map { t in
                let proj = t.projectID.flatMap { store.project(id: $0)?.name }
                return Hit(id: "t" + t.id, title: t.title,
                           subtitle: proj.map { "\($0) / Task" } ?? "Task",
                           icon: "circle", route: .task(t.id))
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(NDS.textTertiary)
                TextField("Jump to initiative, project, or task…", text: $query)
                    .textFieldStyle(.plain).font(NDS.title)
                    .focused($focused)
                    .onSubmit(selectFirst)
            }
            .padding(14)
            Divider().overlay(NDS.divider)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    group("Initiatives", initiativeHits)
                    group("Projects", projectHits)
                    group("Tasks", taskHits)
                    if q.isEmpty {
                        Text("Type to search your workspace").font(NDS.small)
                            .foregroundStyle(NDS.textTertiary).padding(16)
                    } else if initiativeHits.isEmpty && projectHits.isEmpty && taskHits.isEmpty {
                        Text("No matches").font(NDS.small).foregroundStyle(NDS.textTertiary).padding(16)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 540, height: 440)
        .onAppear { focused = true }
        .onExitCommand { isPresented = false }
    }

    @ViewBuilder
    private func group(_ title: String, _ hits: [Hit]) -> some View {
        if !hits.isEmpty {
            Text(title.uppercased()).font(NDS.tiny.weight(.semibold))
                .foregroundStyle(NDS.textTertiary).tracking(0.6)
                .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
            ForEach(hits) { hit in
                Button { choose(hit.route) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: hit.icon).scaledFont(13).foregroundStyle(NDS.brand).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hit.title).font(NDS.body).foregroundStyle(NDS.textPrimary).lineLimit(1)
                            Text(hit.subtitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func choose(_ route: TasksRoute) {
        onSelect(route)
        isPresented = false
    }

    private func selectFirst() {
        if let first = (initiativeHits + projectHits + taskHits).first { choose(first.route) }
    }
}
