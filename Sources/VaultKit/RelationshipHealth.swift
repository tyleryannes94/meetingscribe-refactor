import Foundation

// Phase 2 (2B) — a single, shared definition of "relationship health" as a
// normalized 0–100 score + band. Lives in VaultKit so the app UI (health ring,
// Today ordering) and the MCP server (`get_relationship_health`) compute the
// EXACT same number rather than drifting apart. Pure and dependency-free.
//
// The score blends three signals, all derivable from data the vault already has
// (no new stored fields, no migration):
//   • recency  — how long since the last interaction, relative to this
//                relationship's expected cadence (the dominant factor);
//   • frequency — how many encounters have been logged at all;
//   • consistency — how regular the cadence has been (median gap vs. expected).
public struct RelationshipHealth: Equatable, Sendable {
    public enum Band: String, Sendable {
        case thriving   // ≥ 75 — warm and current
        case steady     // ≥ 50 — healthy, on cadence
        case drifting   // ≥ 25 — slipping, worth a nudge
        case overdue    // < 25 — gone quiet, reconnect

        public init(score: Int) {
            switch score {
            case 75...:  self = .thriving
            case 50..<75: self = .steady
            case 25..<50: self = .drifting
            default:      self = .overdue
            }
        }
    }

    /// 0–100, higher is healthier.
    public let score: Int
    public let band: Band

    /// - Parameters:
    ///   - daysSinceLast: days since the most recent interaction/encounter.
    ///   - cadenceDays: expected days between touches for this relationship.
    ///   - encounterCount: total encounters logged for the person.
    ///   - medianGapDays: median gap between logged encounters (0 if < 2 known).
    public init(daysSinceLast: Int, cadenceDays: Int, encounterCount: Int, medianGapDays: Int) {
        let cadence = max(cadenceDays, 1)

        // Recency (0–55): full credit until 0.75× cadence, decaying to 0 by 3× cadence.
        let ratio = Double(max(daysSinceLast, 0)) / Double(cadence)
        let recency = 55.0 * Self.clamp(1.0 - max(0.0, ratio - 0.75) / 2.25, 0, 1)

        // Frequency (0–30): 8+ logged encounters earns full credit.
        let frequency = 30.0 * Self.clamp(Double(max(encounterCount, 0)) / 8.0, 0, 1)

        // Consistency (0–15): rewards a regular cadence; neutral until enough history.
        let consistency: Double
        if encounterCount < 2 {
            consistency = 0
        } else if medianGapDays <= 0 {
            consistency = 8
        } else {
            let overshoot = max(0.0, Double(medianGapDays - cadence)) / Double(cadence * 2)
            consistency = 15.0 * Self.clamp(1.0 - overshoot, 0, 1)
        }

        let total = Int((recency + frequency + consistency).rounded())
        self.score = min(100, max(0, total))
        self.band = Band(score: self.score)
    }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, x))
    }
}
