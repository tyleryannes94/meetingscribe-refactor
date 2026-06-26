import Foundation

/// Pre-built, reused `DateFormatter`s for hot list/row code paths.
///
/// Building a `DateFormatter` is expensive (ICU locale/calendar setup), and the
/// app was constructing fresh ones inside per-row view bodies and per-item
/// grouping keys — i.e. dozens of allocations per render while scrolling. These
/// shared instances are built once and reused. All call sites are SwiftUI view
/// bodies / view-models running on the main thread, so single-threaded reuse is
/// safe (a `DateFormatter` is fine to reuse, just not to mutate concurrently).
enum AppDateFormat {
    /// "3:04 PM"
    static let time12: DateFormatter = build("h:mm a")
    /// "Jun 26"
    static let monthDay: DateFormatter = build("MMM d")
    /// "Jun 26, 2026"
    static let monthDayYear: DateFormatter = build("MMM d, yyyy")
    /// "Thu, Jun 26"
    static let weekdayMonthDay: DateFormatter = build("EEE, MMM d")

    private static func build(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
}
