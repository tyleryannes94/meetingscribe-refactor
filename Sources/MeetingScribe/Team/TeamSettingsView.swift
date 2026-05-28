import SwiftUI

/// Settings section for Team workspaces (foundation/stub). Create a workspace,
/// invite members by email, and see which meetings are shared. Backed by the
/// in-memory `TeamSyncService` until CloudKit shared zones are wired up.
@available(macOS 14.0, *)
struct TeamSettingsView: View {
    @State private var workspaces: [TeamWorkspace] = []
    @State private var selectedID: String?
    @State private var newWorkspaceName = ""
    @State private var inviteEmail = ""

    private var selected: TeamWorkspace? {
        workspaces.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team workspaces")
                .font(.headline)
            Text("Share meetings with teammates. Sync over CloudKit shared zones is coming; "
                 + "this manages workspaces locally for now.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                TextField("New workspace name", text: $newWorkspaceName)
                    .textFieldStyle(.roundedBorder)
                Button("Create") { createWorkspace() }
                    .disabled(newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if workspaces.isEmpty {
                Text("No workspaces yet.").font(.caption).foregroundStyle(.tertiary)
            } else {
                Picker("Workspace", selection: $selectedID) {
                    ForEach(workspaces) { ws in Text(ws.name).tag(Optional(ws.id)) }
                }
            }

            if let ws = selected {
                Divider()
                memberSection(ws)
                sharedMeetingsSection(ws)
            }
            Spacer()
        }
        .task { await reload() }
    }

    private func memberSection(_ ws: TeamWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Members (\(ws.members.count))").font(.subheadline.weight(.semibold))
            ForEach(ws.members) { m in
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                    Text(m.displayName)
                    Text(m.role.rawValue.capitalized)
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack {
                TextField("Invite by email", text: $inviteEmail)
                    .textFieldStyle(.roundedBorder)
                Button("Invite") { invite(into: ws.id) }
                    .disabled(inviteEmail.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func sharedMeetingsSection(_ ws: TeamWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shared meetings (\(ws.sharedMeetingIDs.count))").font(.subheadline.weight(.semibold))
            if ws.sharedMeetingIDs.isEmpty {
                Text("Share a meeting from its detail view to add it here.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(ws.sharedMeetingIDs, id: \.self) { id in
                    Label(id, systemImage: "calendar").font(.caption)
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        workspaces = await TeamSyncService.shared.allWorkspaces()
        if selectedID == nil { selectedID = workspaces.first?.id }
    }

    private func createWorkspace() {
        let name = newWorkspaceName.trimmingCharacters(in: .whitespaces)
        newWorkspaceName = ""
        Task {
            let ws = await TeamSyncService.shared.createWorkspace(name: name)
            await reload()
            selectedID = ws.id
        }
    }

    private func invite(into workspaceID: String) {
        let email = inviteEmail.trimmingCharacters(in: .whitespaces)
        inviteEmail = ""
        Task {
            await TeamSyncService.shared.invite(email: email, to: workspaceID)
            await reload()
        }
    }
}
