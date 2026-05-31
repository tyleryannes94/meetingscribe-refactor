import Foundation

/// Opt-in, **local-only** usage metrics (P5-1 / P1-4) so the project's own KPIs
/// become measurable. Default OFF (`AppSettings.collectMetrics`); when off,
/// `record` is a no-op. Counts live in UserDefaults and are **never uploaded** —
/// there is no network code here on purpose.
@MainActor
final class MetricsStore {
    static let shared = MetricsStore()
    private init() {}

    enum Event: String, CaseIterable {
        case meetingRecorded
        case transcriptionRun
        case summaryGenerated
        case briefSynthesized
        case decisionCaptured
        case chatQuery

        var label: String {
            switch self {
            case .meetingRecorded:  return "Meetings recorded"
            case .transcriptionRun: return "Transcriptions run"
            case .summaryGenerated: return "Summaries generated"
            case .briefSynthesized: return "Pre-meeting briefs"
            case .decisionCaptured: return "Decisions captured"
            case .chatQuery:        return "Vault chat queries"
            }
        }
    }

    private let defaults = UserDefaults.standard
    private func key(_ e: Event) -> String { "metrics.\(e.rawValue)" }

    /// Increment a counter — no-op unless the user opted in.
    func record(_ event: Event, by amount: Int = 1) {
        guard AppSettings.shared.collectMetrics else { return }
        defaults.set(count(event) + amount, forKey: key(event))
    }

    func count(_ event: Event) -> Int { defaults.integer(forKey: key(event)) }

    /// All counters, for display in Settings.
    func snapshot() -> [(Event, Int)] { Event.allCases.map { ($0, count($0)) } }

    func reset() { Event.allCases.forEach { defaults.removeObject(forKey: key($0)) } }
}
