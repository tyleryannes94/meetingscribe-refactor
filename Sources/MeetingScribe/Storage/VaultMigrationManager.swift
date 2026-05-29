import Foundation
import OSLog

/// Manages one-time vault migrations. Each migration is idempotent —
/// safe to re-run if interrupted.
@available(macOS 14.0, *)
@MainActor
final class VaultMigrationManager: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "VaultMigration")

    @Published var isMigrating = false
    @Published var migrationProgress: Double = 0
    @Published var migrationStatus = ""
    @Published var needsLayoutMigration = false

    private let migratedKey = "vault.layoutMigration.v2.completed"

    init() {
        needsLayoutMigration = !UserDefaults.standard.bool(forKey: migratedKey)
    }

    /// Migrate from tag-grouped layout (TagFolder/slug/) to date-partitioned
    /// layout (meetings/yyyy/yyyy-MM/slug/).
    func migrateLayout(vaultURL: URL) async {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }

        isMigrating = true
        migrationStatus = "Scanning existing meetings…"

        let fm = FileManager.default
        let destBase = vaultURL.appendingPathComponent("meetings", isDirectory: true)

        do {
            // Find all meeting.json files in the current layout
            let enumerator = fm.enumerator(at: vaultURL,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey],
                options: [.skipsHiddenFiles])

            var meetingDirs: [URL] = []
            while let url = enumerator?.nextObject() as? URL {
                if url.lastPathComponent == "meeting.json" {
                    meetingDirs.append(url.deletingLastPathComponent())
                }
            }

            let total = Double(meetingDirs.count)
            var moved = 0
            var failures = 0

            for dir in meetingDirs {
                // Parse the meeting.json to get the date
                let jsonURL = dir.appendingPathComponent("meeting.json")
                guard let data = try? Data(contentsOf: jsonURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let startStr = json["startDate"] as? String else {
                    // Can't determine the date → can't place it. Count it as a
                    // failure so the migration isn't marked complete and we
                    // retry next launch instead of stranding it. (ENG-B)
                    failures += 1
                    log.error("Skipping unparseable meeting.json at \(dir.lastPathComponent)")
                    continue
                }

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let date = formatter.date(from: startStr) ?? Date()

                let cal = Calendar.current
                let year = cal.component(.year, from: date)
                let month = cal.component(.month, from: date)
                let yearStr = String(year)
                let monthStr = String(format: "%d-%02d", year, month)

                let destDir = destBase
                    .appendingPathComponent(yearStr, isDirectory: true)
                    .appendingPathComponent(monthStr, isDirectory: true)
                    .appendingPathComponent(dir.lastPathComponent, isDirectory: true)

                // Skip if already in the right place (idempotent re-run).
                if dir.path == destDir.path {
                    moved += 1
                    migrationProgress = Double(moved + failures) / total
                    continue
                }

                do {
                    try fm.createDirectory(at: destDir.deletingLastPathComponent(),
                                          withIntermediateDirectories: true)
                    try fm.moveItem(at: dir, to: destDir)
                    moved += 1
                } catch {
                    // Previously the failure was swallowed AND counted as
                    // moved, so a partial migration was marked complete and the
                    // unmoved meetings were stranded in the old layout. (ENG-B)
                    failures += 1
                    log.error("Failed to move \(dir.lastPathComponent): \(error.localizedDescription)")
                }

                migrationProgress = Double(moved + failures) / total
                migrationStatus = "Moved \(moved) of \(Int(total)) meetings…"
            }

            // Only mark the migration complete when EVERY discovered meeting
            // landed at its desired location. On any failure leave the flag
            // false so the next launch retries (the move is idempotent: an
            // already-moved meeting hits the dir.path == destDir.path path). (ENG-B)
            if failures == 0 {
                UserDefaults.standard.set(true, forKey: migratedKey)
                needsLayoutMigration = false
                migrationStatus = "Migration complete."
            } else {
                migrationStatus = "Migration incomplete — \(failures) item(s) couldn't be moved. Will retry on next launch."
            }
        }

        isMigrating = false
    }
}
