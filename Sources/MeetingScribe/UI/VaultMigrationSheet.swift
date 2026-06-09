import SwiftUI

/// Shown once when the vault needs to be migrated to the date-partitioned layout.
@available(macOS 14.0, *)
struct VaultMigrationSheet: View {
    @ObservedObject var migrator: VaultMigrationManager
    let vaultURL: URL
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gear")
                .scaledFont(48)
                .foregroundStyle(.blue)

            Text("Vault Layout Update")
                .font(.title2.bold())

            Text("MeetingScribe needs to reorganize your meeting folders into a date-based layout. Your data stays on your Mac — nothing is deleted.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if migrator.isMigrating {
                VStack(spacing: 8) {
                    ProgressView(value: migrator.migrationProgress)
                    Text(migrator.migrationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !migrator.needsLayoutMigration {
                Label("Migration complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 12) {
                    Button("Later") { onDismiss() }
                        .buttonStyle(.bordered)
                    Button("Migrate Now") {
                        Task { await migrator.migrateLayout(vaultURL: vaultURL) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}
