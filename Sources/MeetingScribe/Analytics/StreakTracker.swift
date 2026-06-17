import Foundation

/// Local habit tracking for the compounding-value loop (5-D). Distinct from the
/// opt-in `MetricsStore` telemetry: streaks are a personal motivator, always on,
/// and never leave the device (plain UserDefaults). A "streak day" is a day with
/// both an app open and a capture action (task / note / encounter created).
@MainActor
final class StreakTracker: ObservableObject {
    static let shared = StreakTracker()
    private init() { recompute() }

    enum Signal { case dailyOpen, captureAction }

    @Published private(set) var currentStreak = 0

    private let defaults = UserDefaults.standard
    private let openKey = "streak.openDays"        // [String] of yyyy-MM-dd
    private let captureKey = "streak.captureDays"

    func record(_ signal: Signal) {
        let key = signal == .dailyOpen ? openKey : captureKey
        var days = Set(defaults.stringArray(forKey: key) ?? [])
        let today = Self.dayKey(Date())
        guard !days.contains(today) else { if currentStreak == 0 { recompute() }; return }
        days.insert(today)
        // Bound the history we keep.
        if days.count > 400 {
            let sorted = days.sorted().suffix(400)
            days = Set(sorted)
        }
        defaults.set(Array(days), forKey: key)
        recompute()
    }

    /// Consecutive days (ending today or yesterday) that have BOTH an open and a
    /// capture. Today counts even if incomplete-so-far isn't both yet — we look
    /// back from the most recent fully-qualified day.
    private func recompute() {
        let opens = Set(defaults.stringArray(forKey: openKey) ?? [])
        let captures = Set(defaults.stringArray(forKey: captureKey) ?? [])
        let qualified = opens.intersection(captures)
        guard !qualified.isEmpty else { currentStreak = 0; return }

        let cal = Calendar.current
        var streak = 0
        // Start from today; if today isn't qualified yet, start from yesterday so
        // an in-progress day doesn't reset a real streak.
        var cursor = qualified.contains(Self.dayKey(Date()))
            ? Date()
            : cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        while qualified.contains(Self.dayKey(cursor)) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        currentStreak = streak
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
