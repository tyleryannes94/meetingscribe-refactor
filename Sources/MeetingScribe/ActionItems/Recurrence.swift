import Foundation

/// How a task repeats (P2-5). A small RFC-5545-style subset — frequency +
/// interval — which is enough for the everyday "daily standup / weekly report /
/// monthly invoice" chores that keep people on Things/Todoist. When a recurring
/// task is completed, `ActionItemStore` spawns the next instance with the due
/// (and start) dates rolled forward; instances are related by `seriesID`.
struct RecurrenceRule: Codable, Hashable, Sendable {
    enum Frequency: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
        var calendarComponent: Calendar.Component {
            switch self {
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
            case .yearly: return .year
            }
        }
    }

    var frequency: Frequency
    /// Every N periods (1 = every day/week/…). Clamped to ≥1 when applied.
    var interval: Int = 1

    /// Human label for the property chip.
    var label: String {
        interval <= 1 ? frequency.label : "Every \(interval) \(frequency.label.lowercased())"
    }

    /// The next occurrence strictly after `date`, or nil if it can't be computed.
    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: frequency.calendarComponent, value: max(1, interval), to: date)
    }
}
