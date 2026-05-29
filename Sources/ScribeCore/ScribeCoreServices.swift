import Foundation
import VaultKit
import OSLog

/// Manages all services running inside Scribe Core daemon.
@available(macOS 14.0, *)
@MainActor
final class ScribeCoreServices {
    static let shared = ScribeCoreServices()
    private let log = Logger(subsystem: "com.tyleryannes.ScribeCore", category: "Services")

    private var commandWatcher: VaultCommandWatcher?
    private let audioRecorder = AudioRecorder()

    /// Directory for the currently-active recording, set at startRecording time.
    private var activeRecordingDir: URL?
    /// Segment counter for the current recording session.
    private var activeSegment: Int = 0

    func start() async {
        log.info("Scribe Core starting")
        let vaultURL = AppSettings.vaultURL

        // Start the command file watcher (IPC with Scribe UI)
        commandWatcher = VaultCommandWatcher(vaultURL: vaultURL)
        commandWatcher?.start()

        // Observe IPC signals posted by VaultCommandWatcher
        DarwinNotifier.observe(DarwinNotifier.startRecording) { [weak self] in
            Task { @MainActor in await self?.handleStartRecording() }
        }
        DarwinNotifier.observe(DarwinNotifier.stopRecording) { [weak self] in
            Task { @MainActor in await self?.handleStopRecording() }
        }
        DarwinNotifier.observe(DarwinNotifier.transcribeNow) { [weak self] in
            // Transcription is handled by the UI process; ScribeCore only
            // needs to acknowledge the signal for now.
            self?.log.info("transcribeNow signal received (handled by UI process)")
        }

        // Notify UI that core is running
        DarwinNotifier.post(DarwinNotifier.recordingStopped) // use as "ready" signal
        log.info("Scribe Core ready. Vault: \(vaultURL.path)")
    }

    func stop() async {
        commandWatcher?.stop()
        log.info("Scribe Core stopped")
    }

    // MARK: - Audio recording handlers

    private func handleStartRecording() async {
        guard activeRecordingDir == nil else {
            log.warning("startRecording signal received but already recording — ignoring")
            return
        }

        // Build a timestamped directory under the vault for this recording.
        let dateStr = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let dir = AppSettings.vaultURL
            .appendingPathComponent("meetings/scribecore-\(dateStr)", isDirectory: true)
        activeSegment = 1

        do {
            try await audioRecorder.start(in: dir, segment: activeSegment)
            activeRecordingDir = dir
            DarwinNotifier.post(DarwinNotifier.recordingStarted)
            log.info("Recording started in \(dir.path)")
        } catch {
            log.error("AudioRecorder.start failed: \(error.localizedDescription, privacy: .public)")
            activeRecordingDir = nil
        }
    }

    private func handleStopRecording() async {
        guard activeRecordingDir != nil else {
            log.warning("stopRecording signal received but not recording — ignoring")
            return
        }

        _ = await audioRecorder.stop()
        activeRecordingDir = nil
        DarwinNotifier.post(DarwinNotifier.recordingStopped)
        log.info("Recording stopped")
    }
}
