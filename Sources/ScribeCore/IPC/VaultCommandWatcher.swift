import Foundation
import VaultKit
import OSLog

/// Watches vault/_commands/ for JSON command files dropped by the Scribe UI.
/// This is the Phase 1 IPC mechanism (file-based), later supplemented by XPC.
@available(macOS 14.0, *)
@MainActor
final class VaultCommandWatcher {
    private let log = Logger(subsystem: "com.tyleryannes.ScribeCore", category: "CommandWatcher")
    private let vaultURL: URL
    private var source: DispatchSourceFileSystemObject?
    private let commandsURL: URL

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
        self.commandsURL = vaultURL.appendingPathComponent("_commands", isDirectory: true)
    }

    func start() {
        try? FileManager.default.createDirectory(at: commandsURL, withIntermediateDirectories: true)

        let fd = open(commandsURL.path, O_EVTONLY)
        guard fd >= 0 else {
            log.error("Cannot open commands directory for watching")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        src.setEventHandler { [weak self] in
            self?.processCommandDirectory()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.source = src
        log.info("Command watcher started at \(self.commandsURL.path)")
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func processCommandDirectory() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: commandsURL, includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix("-response.json") })
        else { return }

        for file in files {
            processCommand(at: file)
        }
    }

    private func processCommand(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let cmd = try? JSONDecoder().decode(VaultCommand.self, from: data)
        else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        log.info("Received command: \(cmd.command)")

        switch cmd.command {
        case "start-recording":
            DarwinNotifier.post(DarwinNotifier.recordingStarted)
            // TODO: wire to AudioRecorder when moved to ScribeCore
            writeResponse(requestID: cmd.requestID, success: true, error: nil)
        case "stop-recording":
            DarwinNotifier.post(DarwinNotifier.recordingStopped)
            // TODO: wire to AudioRecorder when moved to ScribeCore
            writeResponse(requestID: cmd.requestID, success: true, error: nil)
        default:
            log.warning("Unknown command: \(cmd.command)")
            writeResponse(requestID: cmd.requestID, success: false, error: "unknown command")
        }

        // Remove processed command file
        try? FileManager.default.removeItem(at: url)
    }

    private func writeResponse(requestID: String, success: Bool, error: String?) {
        let response: [String: Any] = [
            "requestID": requestID,
            "success": success,
            "error": error as Any,
            "respondedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        let dest = commandsURL.appendingPathComponent("\(requestID)-response.json")
        try? data.write(to: dest, options: .atomic)
    }
}

struct VaultCommand: Codable {
    let command: String
    let requestedAt: String
    let requestID: String
}
