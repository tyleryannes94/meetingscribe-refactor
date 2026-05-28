import SwiftUI

/// Settings section for iCloud encrypted backup: enable/disable, the last
/// backup date, and a manual "Back up now" button.
@available(macOS 14.0, *)
struct BackupSettingsView: View {
    @AppStorage("iCloudBackupEnabled") private var enabled = false
    @State private var lastBackup: Date? = iCloudBackupManager.shared.lastBackupDate
    @State private var isBackingUp = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Encrypted iCloud backup")
                    Text("Writes AES-256-encrypted archives of your meetings to iCloud Drive daily.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: enabled) { _, on in
                if on { BackupScheduler.shared.start() } else { BackupScheduler.shared.stop() }
            }

            HStack(spacing: 10) {
                Text(lastBackupLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    backupNow()
                } label: {
                    if isBackingUp {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Backing up…") }
                    } else {
                        Label("Back up now", systemImage: "arrow.up.to.line")
                    }
                }
                .controlSize(.small)
                .disabled(isBackingUp)
            }

            if let err = errorText {
                Text(err).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(enabled ? 1 : 0.7)
    }

    private var lastBackupLabel: String {
        guard let d = lastBackup else { return "No backup yet." }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return "Last backup: \(f.string(from: d))"
    }

    private func backupNow() {
        isBackingUp = true
        errorText = nil
        Task {
            do {
                _ = try await iCloudBackupManager.shared.runBackup()
                lastBackup = iCloudBackupManager.shared.lastBackupDate
            } catch {
                errorText = error.localizedDescription
            }
            isBackingUp = false
        }
    }
}
