import Foundation
import OSLog

/// Triggers a daily iCloud backup. Checks roughly hourly whether ≥24h have
/// elapsed since the last successful backup and, if so, runs one. Off unless
/// `backupEnabled` is set in Settings.
@MainActor
final class BackupScheduler {
    static let shared = BackupScheduler()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Backup")
    private var timer: Timer?
    private let interval: TimeInterval = 60 * 60          // re-check hourly
    private let backupCadence: TimeInterval = 60 * 60 * 24 // back up daily

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "iCloudBackupEnabled") }

    private init() {}

    func startIfEnabled() {
        guard Self.isEnabled else { return }
        start()
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runIfDue() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Kick an immediate due-check at launch.
        Task { await runIfDue() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func runIfDue() async {
        guard Self.isEnabled else { return }
        let last = iCloudBackupManager.shared.lastBackupDate
        if let last, Date().timeIntervalSince(last) < backupCadence { return }
        do {
            _ = try await iCloudBackupManager.shared.runBackup()
        } catch {
            log.error("Scheduled backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
