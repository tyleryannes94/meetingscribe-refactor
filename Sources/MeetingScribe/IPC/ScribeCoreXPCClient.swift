import Foundation
import Combine
import OSLog

/// Client-side interface from Scribe UI → Scribe Core daemon.
/// Phase 1: uses file-based commands in vault/_commands/
/// Phase 2: will switch to NSXPCConnection
@available(macOS 14.0, *)
@MainActor
final class ScribeCoreXPCClient: ObservableObject {
    static let shared = ScribeCoreXPCClient()
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ScribeCoreXPCClient")

    private var vaultURL: URL {
        AppSettings.shared.storageDir
    }

    private var commandsURL: URL {
        vaultURL.appendingPathComponent("_commands", isDirectory: true)
    }

    // MARK: - Recording commands

    func startRecording() async throws {
        try await sendCommand("start-recording")
    }

    func stopRecording() async throws {
        try await sendCommand("stop-recording")
    }

    // MARK: - File command protocol

    private func sendCommand(_ command: String) async throws {
        let requestID = UUID().uuidString
        let payload: [String: String] = [
            "command": command,
            "requestedAt": ISO8601DateFormatter().string(from: Date()),
            "requestID": requestID
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let commandURL = commandsURL.appendingPathComponent("\(command).json")
        try FileManager.default.createDirectory(at: commandsURL, withIntermediateDirectories: true)
        try data.write(to: commandURL, options: .atomic)

        log.info("Sent command: \(command) (id: \(requestID))")

        // Wait up to 5 seconds for response
        let responseURL = commandsURL.appendingPathComponent("\(requestID)-response.json")
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if FileManager.default.fileExists(atPath: responseURL.path) {
                try? FileManager.default.removeItem(at: responseURL)
                return
            }
        }
        log.warning("No response received for command: \(command) within 5s — Scribe Core may not be running")
    }
}
