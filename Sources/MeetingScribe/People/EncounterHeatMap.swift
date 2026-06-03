import SwiftUI

/// D4-6 / P2-4 — a compact 13-week encounter heat map. One cell per week,
/// color intensity = number of encounters that week, oldest (left) to current
/// (right). Surfaces consistency at a glance and shows the current connection
/// streak. No third-party library; data is just the encounter dates.
@available(macOS 14.0, *)
struct EncounterHeatMap: View {
    /// Encounter dates for the person (order doesn't matter).
    let dates: [Date]
    /// Optional aspirational cadence (P2-8), shown as an annotation.
    var goalDays: Int? = nil

    private static let weeks = 13

    /// `counts[i]` = encounters in week `i`, where 0 = current week and 12 =
    /// twelve weeks ago. Future-dated encounters are ignored.
    private var counts: [Int] {
        var c = Array(repeating: 0, count: Self.weeks)
        let now = Date()
        for d in dates {
            let days = Int(now.timeIntervalSince(d) / 86_400)
            guard days >= 0 else { continue }
            let wk = days / 7
            if wk < Self.weeks { c[wk] += 1 }
        }
        return c
    }

    /// Consecutive most-recent weeks (from current week backward) with at least
    /// one encounter.
    private var streakWeeks: Int {
        var n = 0
        for v in counts { if v > 0 { n += 1 } else { break } }
        return n
    }

    var body: some View {
        let c = counts
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                // Render oldest → newest so "now" sits on the right.
                ForEach(Array((0..<Self.weeks).reversed()), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.color(for: c[i]))
                        .frame(width: 14, height: 14)
                        .help(Self.cellHelp(weeksAgo: i, count: c[i]))
                }
            }
            HStack(spacing: 6) {
                Text("Last 13 weeks").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                if streakWeeks > 0 {
                    Text("· Current streak: \(streakWeeks) week\(streakWeeks == 1 ? "" : "s")")
                        .font(NDS.tiny).foregroundStyle(NDS.brand)
                }
                if let g = goalDays {
                    Text("· Goal: every \(g)d").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }

    private static func color(for count: Int) -> Color {
        switch count {
        case 0:  return NDS.hairline.opacity(0.6)
        case 1:  return NDS.brand.opacity(0.30)
        case 2:  return NDS.brand.opacity(0.55)
        case 3:  return NDS.brand.opacity(0.78)
        default: return NDS.brand
        }
    }

    private static func cellHelp(weeksAgo: Int, count: Int) -> String {
        let when: String
        switch weeksAgo {
        case 0:  when = "this week"
        case 1:  when = "last week"
        default: when = "\(weeksAgo) weeks ago"
        }
        let noun = count == 1 ? "encounter" : "encounters"
        return "\(count) \(noun) — \(when)"
    }
}
