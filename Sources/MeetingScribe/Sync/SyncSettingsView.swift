import SwiftUI

/// Settings pane section for iCloud sync. Toggling on starts the (stubbed)
/// `CloudKitSyncEngine`; toggling off stops it. The status line reflects the
/// engine's reported `SyncStatus`.
///
/// Drop this into the existing Settings window with `SyncSettingsView()` — it's
/// intentionally self-contained (its own `@AppStorage` flag + engine instance)
/// so it can be wired in without threading a dependency through `MeetingManager`.
@available(macOS 14.0, *)
struct SyncSettingsView: View {
    @AppStorage("icloudSyncEnabled") private var syncEnabled = false
    @State private var engine = CloudKitSyncEngine()
    @State private var statusLabel = SyncStatus.idle.label

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $syncEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync with iCloud")
                    Text("Keep meetings, tasks, and people in sync across your devices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: syncEnabled) { _, on in
                Task { await apply(enabled: on) }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text("Status: \(statusLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await apply(enabled: syncEnabled) }
    }

    private var statusColor: Color {
        switch statusLabel {
        case SyncStatus.upToDate.label: return .green
        case SyncStatus.syncing.label:  return .orange
        default:                        return .secondary
        }
    }

    private func apply(enabled: Bool) async {
        if enabled {
            await engine.startSync()
        } else {
            await engine.stopSync()
        }
        statusLabel = await engine.status.label
    }
}
