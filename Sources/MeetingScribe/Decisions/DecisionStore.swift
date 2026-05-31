import Foundation
import OSLog

/// One decision made in a meeting, lifted out of that meeting's summary into a
/// queryable cross-meeting ledger. (P1-1 / C1-11 / C2-8)
struct Decision: Identifiable, Codable, Hashable {
    var id: String
    var meetingID: String
    var meetingTitle: String
    var date: Date
    var text: String
}

/// The Decision Ledger: a vault-wide, queryable record of decisions extracted
/// from meeting summaries' "Key Decisions" sections, so they stop dying inside
/// one meeting's markdown. Persisted to `<vault>/decisions.json`.
@available(macOS 14.0, *)
@MainActor
final class DecisionStore: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Decisions")
    @Published private(set) var decisions: [Decision] = []

    private var fileURL: URL { AppSettings.shared.storageDir.appendingPathComponent("decisions.json") }

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Decision].self, from: data) else { return }
        decisions = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(decisions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Replace this meeting's decisions with those parsed from its summary.
    /// Idempotent — safe to call again after a re-transcribe.
    func extract(from summary: String, meeting: Meeting) {
        let parsed = Self.parseDecisions(from: summary)
        let existing = decisions.filter { $0.meetingID == meeting.id }
        // No-op if nothing changed, so a backfill pass over unchanged meetings
        // doesn't churn the file.
        if existing.map(\.text) == parsed { return }
        decisions.removeAll { $0.meetingID == meeting.id }
        for text in parsed {
            decisions.append(Decision(
                id: "\(meeting.id)::\(abs(text.hashValue))",
                meetingID: meeting.id,
                meetingTitle: meeting.displayTitle,
                date: meeting.startDate,
                text: text))
        }
        decisions.sort { $0.date > $1.date }
        save()
    }

    /// Pull the bulleted lines under a "## Key Decisions" (or "## Decisions")
    /// heading, dropping the "None." placeholder.
    static func parseDecisions(from summary: String) -> [String] {
        var inSection = false
        var out: [String] = []
        for raw in summary.components(separatedBy: .newlines) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") {
                let lower = t.lowercased()
                inSection = lower.contains("key decision") || lower.hasSuffix("decisions")
                continue
            }
            guard inSection else { continue }
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                let txt = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let low = txt.lowercased()
                if !txt.isEmpty, low != "none.", low != "none" { out.append(txt) }
            }
        }
        return out
    }
}
