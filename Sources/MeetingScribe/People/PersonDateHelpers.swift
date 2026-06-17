import Foundation

/// Shared "is there a birthday or recurring special date for this person in the
/// next N days?" predicate. Lives outside `PeopleListView` and
/// `PeopleInsightsView` so both can use it without duplicating the
/// next-occurrence math (L9 / 03-Inc9).
@available(macOS 14.0, *)
enum PersonDateHelpers {
    /// True when `p` has a birthday or a recurring/upcoming special date that
    /// falls within `[now, now + days]`. One-off special dates count only when
    /// still in the future.
    static func nextSpecialDateWithin(_ p: Person, days: Int, now: Date = Date(),
                                      cal: Calendar = .current) -> Bool {
        if let bday = p.birthday, let next = nextOccurrence(of: bday, after: now, cal: cal),
           within(next, days: days, now: now, cal: cal) {
            return true
        }
        for sd in p.specialDates {
            let label = sd.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            let when: Date?
            if sd.recurring {
                when = nextOccurrence(of: sd.date, after: now, cal: cal)
            } else {
                when = cal.startOfDay(for: sd.date) >= cal.startOfDay(for: now) ? sd.date : nil
            }
            if let when, within(when, days: days, now: now, cal: cal) { return true }
        }
        return false
    }

    /// Next time the same month/day combination lands on or after `after`.
    static func nextOccurrence(of date: Date, after: Date, cal: Calendar) -> Date? {
        let comps = cal.dateComponents([.month, .day], from: date)
        guard let month = comps.month, let day = comps.day else { return nil }
        let year = cal.component(.year, from: after)
        for y in [year, year + 1] {
            if let d = cal.date(from: DateComponents(year: y, month: month, day: day)),
               cal.startOfDay(for: d) >= cal.startOfDay(for: after) {
                return d
            }
        }
        return nil
    }

    private static func within(_ date: Date, days: Int, now: Date, cal: Calendar) -> Bool {
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                   to: cal.startOfDay(for: date)).day ?? 9999
        return d >= 0 && d <= days
    }
}
