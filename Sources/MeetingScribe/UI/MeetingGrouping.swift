import Foundation

/// Smart grouping for the Meetings list (redesign §3A): NOW / TODAY /
/// UPCOMING TODAY / UPCOMING / PAST · RECORDED. Pure and deterministic (takes
/// `now` so it's testable) — `MeetingsView` renders the returned sections in
/// order; the existing flat All/Upcoming/Past filter becomes the secondary mode.
enum MeetingGrouping {

    enum Section: String, CaseIterable, Identifiable {
        case now            // actively recording
        case today          // today, already started / past
        case upcomingToday  // today, still to come
        case upcoming       // future days
        case pastRecorded   // earlier days

        var id: String { rawValue }
        var title: String {
            switch self {
            case .now:           return "NOW"
            case .today:         return "TODAY"
            case .upcomingToday: return "UPCOMING TODAY"
            case .upcoming:      return "UPCOMING"
            case .pastRecorded:  return "PAST · RECORDED"
            }
        }
    }

    /// Classify + sort `meetings` into ordered, non-empty sections. `meetings`
    /// may freely mix past (recorded) and upcoming (calendar) items; duplicates
    /// by `id` are collapsed (a live meeting present in both lists shows once,
    /// under NOW). `liveMeetingID` is the meeting currently recording, if any.
    static func group(_ meetings: [Meeting],
                      liveMeetingID: String? = nil,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> [(section: Section, meetings: [Meeting])] {
        // Collapse duplicates by id, keeping the first occurrence.
        var byID: [String: Meeting] = [:]
        var order: [String] = []
        for m in meetings where byID[m.id] == nil { byID[m.id] = m; order.append(m.id) }
        let unique = order.compactMap { byID[$0] }

        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return []
        }

        var buckets: [Section: [Meeting]] = [:]
        for m in unique {
            let section: Section
            if let liveMeetingID, m.id == liveMeetingID {
                section = .now
            } else if m.startDate < startOfToday {
                section = .pastRecorded
            } else if m.startDate >= startOfTomorrow {
                section = .upcoming
            } else {
                // Today: split on whether it has already started.
                section = m.startDate <= now ? .today : .upcomingToday
            }
            buckets[section, default: []].append(m)
        }

        func sorted(_ s: Section, _ items: [Meeting]) -> [Meeting] {
            switch s {
            case .now:
                return items
            case .today, .pastRecorded:
                return items.sorted { $0.startDate > $1.startDate }   // newest first
            case .upcomingToday, .upcoming:
                return items.sorted { $0.startDate < $1.startDate }   // soonest first
            }
        }

        return Section.allCases.compactMap { s in
            guard let items = buckets[s], !items.isEmpty else { return nil }
            return (s, sorted(s, items))
        }
    }
}
