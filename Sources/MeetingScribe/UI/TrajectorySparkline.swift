import SwiftUI

/// A tiny 12-week encounter-frequency sparkline (2-H). Shows *trajectory*
/// (accelerating / decelerating) rather than just current state, so the
/// KeepInTouchBoard card and person profile reveal whether a relationship is
/// warming up or cooling off at a glance. Pure SwiftUI bars — no new persistence;
/// counts are derived from the encounters the vault already has.
struct TrajectorySparkline: View {
    /// Weekly counts, oldest → newest.
    let weeklyCounts: [Int]
    var tint: Color = NDS.brand

    var body: some View {
        GeometryReader { geo in
            let maxV = CGFloat(max(weeklyCounts.max() ?? 0, 1))
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(weeklyCounts.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(tint.opacity(c == 0 ? 0.15 : 0.75))
                        .frame(height: max(1.5, geo.size.height * CGFloat(c) / maxV))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// Bucket interaction dates into the last `weeks` weekly counts (newest last).
    static func weeklyCounts(from dates: [Date], weeks: Int = 12, now: Date = Date()) -> [Int] {
        var buckets = Array(repeating: 0, count: weeks)
        for d in dates {
            let days = Int(now.timeIntervalSince(d) / 86_400)
            guard days >= 0 else { continue }
            let weeksAgo = days / 7
            if weeksAgo < weeks { buckets[weeks - 1 - weeksAgo] += 1 }
        }
        return buckets
    }
}
