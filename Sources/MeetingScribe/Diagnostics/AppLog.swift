import Foundation
import OSLog

/// App-wide, disk-backed diagnostic log for errors and notable events
/// beyond transcription (which has its own `TranscriptionLog`). Lives at
/// `<storageDir>/logs/app.log`. Every entry is timestamped with a level,
/// category, message, and optional structured key/values.
///
/// Goal: when something fails in the field (polish, summary, recording,
/// Notion push, calendar load, etc.) the user can open this file — or we
/// can ask them to send it — and see exactly what happened. Mirrors the
/// `os.Logger` calls so console logging keeps working too.
///
/// Writes are serialized on a utility queue; the file auto-rotates at ~2 MB.
enum AppLog {
    enum Level: String { case info = "INFO", warn = "WARN", error = "ERROR" }

    private static let oslog = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "AppLog")
    private static let queue = DispatchQueue(label: "app.log", qos: .utility)
    private static let maxBytes = 2 * 1024 * 1024
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Path the log is written to. Public so Settings can offer "Reveal log".
    static var fileURL: URL {
        AppSettings.shared.storageDir
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("app.log")
    }

    static func info(_ category: String, _ message: String, _ extra: [String: String] = [:]) {
        write(.info, category, message, extra)
    }
    static func warn(_ category: String, _ message: String, _ extra: [String: String] = [:]) {
        write(.warn, category, message, extra)
    }
    static func error(_ category: String, _ message: String, _ extra: [String: String] = [:]) {
        write(.error, category, message, extra)
    }

    /// Convenience for catch blocks: logs an Error with its localized
    /// description plus type, and any extra context.
    static func error(_ category: String, _ message: String, error: Error,
                      _ extra: [String: String] = [:]) {
        var e = extra
        e["error"] = error.localizedDescription
        e["errorType"] = String(describing: type(of: error))
        write(.error, category, message, e)
    }

    // MARK: - Internals

    private static func write(_ level: Level, _ category: String,
                              _ message: String, _ extra: [String: String]) {
        // Mirror to the unified log immediately (best-effort, non-blocking).
        switch level {
        case .error: oslog.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warn:  oslog.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .info:  oslog.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
        let ts = formatter.string(from: Date())
        queue.async {
            do {
                let dir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                rotateIfNeeded()
                var line = "\(ts) [\(level.rawValue)] [\(category)] \(message)"
                if !extra.isEmpty {
                    let kv = extra.sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: " ")
                    line += "  {\(kv)}"
                }
                line += "\n"
                append(line)
            } catch {
                oslog.error("AppLog write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func append(_ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func rotateIfNeeded() {
        let url = fileURL
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        let keep = data.suffix(maxBytes / 2)
        if let s = String(data: keep, encoding: .utf8),
           let nl = s.firstIndex(of: "\n") {
            try? String(s[s.index(after: nl)...]).data(using: .utf8)?.write(to: url)
        } else {
            try? keep.write(to: url)
        }
    }
}
