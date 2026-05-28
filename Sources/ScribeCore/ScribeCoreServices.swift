import Foundation
import VaultKit
import OSLog

/// Manages all services running inside Scribe Core daemon.
@available(macOS 14.0, *)
@MainActor
final class ScribeCoreServices {
    static let shared = ScribeCoreServices()
    private let log = Logger(subsystem: "com.tyleryannes.ScribeCore", category: "Services")

    // These will be populated when audio/transcription/AI files are moved here
    // For now: command file watcher is the entry point for IPC
    private var commandWatcher: VaultCommandWatcher?

    func start() async {
        log.info("Scribe Core starting")
        let vaultURL = AppSettings.vaultURL

        // Start the command file watcher (IPC with Scribe UI)
        commandWatcher = VaultCommandWatcher(vaultURL: vaultURL)
        commandWatcher?.start()

        // Notify UI that core is running
        DarwinNotifier.post(DarwinNotifier.recordingStopped) // use as "ready" signal
        log.info("Scribe Core ready. Vault: \(vaultURL.path)")
    }

    func stop() async {
        commandWatcher?.stop()
        log.info("Scribe Core stopped")
    }
}
