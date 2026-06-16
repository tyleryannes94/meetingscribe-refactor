import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Initiative roll-up (3-2)

    /// An initiative is no longer a dead end: its pane shows the initiative page
    /// (compressed) on top, a completion bar, and beneath it the live task list
    /// across all of the initiative's projects, with an inline quick-add.
    @ViewBuilder
    func initiativeRollup(_ id: String) -> some View {
        if let initiative = store.initiative(id: id) {
            let projs = store.projects(forInitiative: id)
            let tasks = store.tasks(matching: TaskQuery(scope: .initiative(id),
                                                        filters: .init(includeCompleted: false)))
            VStack(spacing: 0) {
                // Compressed initiative page (name, body, project grid).
                InitiativePage(store: store, initiativeID: id, onOpenProject: { pid in
                    env.selectedInitiativeID = nil; env.selectedProjectID = pid
                })
                .frame(maxHeight: 240)
                Divider().overlay(NDS.divider)
                initiativeProgress(id)
                Divider().overlay(NDS.divider)
                initiativeTasksSection(initiative, projects: projs, tasks: tasks)
            }
        }
    }

    private func initiativeProgress(_ id: String) -> some View {
        let (done, total) = store.completion(forInitiative: id)
        let frac = total == 0 ? 0 : Double(done) / Double(total)
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NDS.fieldBg).frame(height: 6)
                    Capsule().fill(NDS.brand).frame(width: geo.size.width * frac, height: 6)
                }
            }
            .frame(height: 6)
            Text("\(done)/\(total)")
                .font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textSecondary)
        }
        .padding(.horizontal, 32).padding(.vertical, 10)
    }

    @ViewBuilder
    private func initiativeTasksSection(_ initiative: Initiative,
                                        projects projs: [Project],
                                        tasks: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Tasks").scaledFont(13, weight: .semibold)
                    .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                Text("\(tasks.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
            }
            // Quick-add: pick the destination project (when there's more than
            // one) then type a task — created right under the initiative (3-2).
            HStack(spacing: 8) {
                Image(systemName: "plus").scaledFont(11).foregroundStyle(NDS.textTertiary)
                TextField("Add task…", text: $initiativeAddText,
                          onCommit: { commitInitiativeTask(initiative, projects: projs) })
                    .textFieldStyle(.plain).font(NDS.body)
                    .onSubmit { commitInitiativeTask(initiative, projects: projs) }
                if projs.count > 1 {
                    Menu {
                        ForEach(projs) { p in
                            Button(p.name) { initiativeAddProjectID = p.id }
                        }
                    } label: {
                        let name = initiativeAddProjectID.flatMap { id in projs.first { $0.id == id }?.name }
                        Text(name ?? projs.first?.name ?? "Project").font(NDS.small)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))

            if tasks.isEmpty {
                Text("No open tasks across this initiative's projects.")
                    .font(.caption).foregroundStyle(.tertiary).padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) { ForEach(tasks) { row(for: $0) } }
                }
            }
        }
        .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func commitInitiativeTask(_ initiative: Initiative, projects projs: [Project]) {
        let raw = initiativeAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        // Default to the chosen project, else the initiative's first project,
        // else unfiled (the user can move it later).
        let pid = initiativeAddProjectID ?? projs.first?.id
        if let pid, let p = store.project(id: pid), !store.pageHasDatabase(p) {
            store.setProjectDatabaseEnabled(pid, true)
        }
        _ = store.createTask(parsing: raw, projectID: pid)
        initiativeAddText = ""
    }
}
