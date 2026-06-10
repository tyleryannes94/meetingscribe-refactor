import Foundation
import VaultKit

// Phase 1 (1C) — local-only activation / funnel instrumentation.
//
// The audit's strongest cross-group finding was "the app can't see itself": no
// funnel, no activation signal, no way to know what fraction of started
// recordings actually reach a usable summary. This is a deliberately tiny,
// privacy-preserving event log:
//
//   • Events are append-only JSON lines in Application Support (NEVER the synced
//     vault), so nothing about a user's meetings leaves the Mac.
//   • Payloads are coarse counts + enum kinds — no transcript text, no names.
//   • The file self-trims so it can't grow unbounded.
//
// Emit with `Task { await ActivityLog.shared.log(.recordStart) }` from anywhere.
// Read aggregate health with `await ActivityLog.shared.funnel()`.

/// A coarse, privacy-safe lifecycle signal. Add cases freely; old logs ignore
/// unknown kinds on read.
enum ActivityEvent: String, Codable, CaseIterable {
    case appLaunch
    case onboardingComplete
    case recordStart
    case recordStop
    case transcriptReady
    case summaryReady
    case summaryFailed
    case personAdded
    case paywallShown
}

/// One recorded event. `meta` holds only non-identifying scalars (durations,
/// counts, booleans as strings) — never free text from the user's content.
struct ActivityRecord: Codable {
    let kind: String
    let at: Date
    let meta: [String: String]?
}

/// Aggregate funnel health derived from the event log.
struct ActivityFunnel {
    var launches = 0
    var recordsStarted = 0
    var recordsStopped = 0
    var summariesReady = 0
    var summariesFailed = 0

    /// Fraction of started recordings that reached a usable summary — the
    /// audit's "Capture rate" north-star proxy. `nil` until at least one
    /// recording has started.
    var captureRate: Double? {
        guard recordsStarted > 0 else { return nil }
        return Double(summariesReady) / Double(recordsStarted)
    }
}

actor ActivityLog {
    static let shared = ActivityLog()

    /// Lives beside the derived SQLite index in Application Support — local,
    /// private, and excluded from any vault sync.
    private let fileURL: URL = VaultPaths.databaseURL
        .deletingLastPathComponent()
        .appendingPathComponent("activity-events.jsonl")

    /// Trim threshold — keep the log bounded without losing recent history.
    private let maxLines = 5_000

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    /// Append one event. Best-effort and never throws into callers — telemetry
    /// must not be able to break a real flow.
    func log(_ kind: ActivityEvent, meta: [String: String]? = nil, at: Date = Date()) {
        let record = ActivityRecord(kind: kind.rawValue, at: at, meta: meta)
        guard let data = try? encoder.encode(record),
              let line = String(data: data, encoding: .utf8) else { return }
        append(line + "\n")
    }

    /// All records currently on disk (most recent last). Decode is tolerant —
    /// malformed or unknown lines are skipped.
    func records() -> [ActivityRecord] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let d = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ActivityRecord.self, from: d)
        }
    }

    /// Aggregate funnel health across the full log.
    func funnel() -> ActivityFunnel {
        var f = ActivityFunnel()
        for r in records() {
            switch ActivityEvent(rawValue: r.kind) {
            case .appLaunch:      f.launches += 1
            case .recordStart:    f.recordsStarted += 1
            case .recordStop:     f.recordsStopped += 1
            case .summaryReady:   f.summariesReady += 1
            case .summaryFailed:  f.summariesFailed += 1
            default:              break
            }
        }
        return f
    }

    // MARK: - Private

    private func append(_ line: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? line.data(using: .utf8)?.write(to: fileURL)
            return
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) { try? handle.write(contentsOf: data) }
        }
        trimIfNeeded()
    }

    /// Keep only the most recent `maxLines` once the file grows past 1.5×, so
    /// trimming is amortized rather than per-write.
    private func trimIfNeeded() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines + maxLines / 2 else { return }
        let kept = lines.suffix(maxLines).joined(separator: "\n")
        try? kept.data(using: .utf8)?.write(to: fileURL)
    }
}
