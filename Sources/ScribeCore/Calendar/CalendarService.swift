import Foundation
import EventKit
import VaultKit
import OSLog

/// Day-grouping for the upcoming list.
enum DayGroup: String, CaseIterable, Identifiable {
    case today, tomorrow, restOfWeek
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .restOfWeek: return "Rest of week"
        }
    }
}

/// SwiftUI-facing wrapper around `CalendarStoreActor`. Publishes the
/// upcoming-meetings list and authorization state for the UI; delegates
/// every EventKit call into the shared actor so we no longer pay the
/// double-store cost (audit 5.3).
@available(macOS 14.0, *)
@MainActor
final class CalendarService: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Calendar")

    @Published var upcoming: [Meeting] = []
    @Published var authorized: Bool = false

    private var cacheURL: URL {
        AppSettings.storageDir.appendingPathComponent(".upcoming-cache.json")
    }

    static let cacheSchemaVersion = 1

    init() {
        // Warm the list from the last session's cache so today's meetings
        // render instantly on cold start. Read OFF the main thread — the file
        // open can stall on slow/scanned disks and would block app launch.
        let url = cacheURL
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let cached: [Meeting] = try? SchemaEnvelope.decode(
                    [Meeting].self, from: data,
                    currentVersion: Self.cacheSchemaVersion,
                    decoder: SharedCoders.decoder())
            else { return }
            await MainActor.run { self?.upcoming = cached }
        }
    }

    private func saveCache(_ list: [Meeting]) {
        let env = SchemaEnvelope(version: Self.cacheSchemaVersion, data: list)
        guard let data = try? SharedCoders.encoder(sorted: true).encode(env) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Describes one EventKit calendar so the Settings UI can show the user
    /// all calendars across all their connected accounts (Google work x N,
    /// iCloud, Outlook, etc.) and let them check which ones to read.
    struct CalendarOption: Identifiable, Hashable {
        let id: String          // EKCalendar.calendarIdentifier
        let title: String       // human name
        let source: String      // account source
        let color: String       // hex
    }

    /// All calendars EventKit currently exposes to us. Hops to the actor
    /// for the underlying read.
    func availableCalendars() async -> [CalendarOption] {
        guard authorized else { return [] }
        return await CalendarStoreActor.shared.calendarOptions()
    }

    func requestAccess() async {
        authorized = await CalendarStoreActor.shared.requestAccess()
    }

    /// Meetings between `from` and `to`. Excludes all-day events. When
    /// `filterConferenceURLs` is true, only events with a Zoom/Meet/Teams/Webex
    /// URL are returned. Async because EventKit reads now happen on the actor.
    func meetings(from: Date, to: Date, filterConferenceURLs: Bool) async -> [Meeting] {
        guard authorized else { return [] }
        let enabledIDs = AppSettings.enabledCalendarIDs
        return await CalendarStoreActor.shared.meetings(from: from, to: to,
                                                        enabledIDs: enabledIDs,
                                                        filterConferenceURLs: filterConferenceURLs)
    }

    /// TTL on EventKit queries. Four tabs all call refreshUpcoming() on
    /// appear, plus the menu bar; without this we'd hit EventKit dozens
    /// of times per second on launch.
    private var lastUpcomingRefresh: Date = .distantPast
    private let upcomingRefreshInterval: TimeInterval = 30.0

    /// Refreshes the upcoming list (next 7 business days). Cached for ~30s
    /// so back-to-back .onAppear calls are free.
    func refreshUpcoming(force: Bool = false) {
        if !force, Date().timeIntervalSince(lastUpcomingRefresh) < upcomingRefreshInterval {
            return
        }
        guard authorized else { return }
        lastUpcomingRefresh = Date()
        let cal = Calendar.current
        let now = Date()
        let startWindow = cal.startOfDay(for: now)
        let endWindow = cal.date(byAdding: .day, value: 8, to: startWindow) ?? now.addingTimeInterval(7 * 86400)
        let from = now.addingTimeInterval(-30 * 60)
        let enabledIDs = AppSettings.enabledCalendarIDs
        let filter = AppSettings.filterToConferenceLinks
        Task {
            let result = await CalendarStoreActor.shared.meetings(from: from, to: endWindow,
                                                                  enabledIDs: enabledIDs,
                                                                  filterConferenceURLs: filter)
            self.upcoming = result
            self.saveCache(result)
        }
    }

    /// Returns the upcoming list, grouped into Today / Tomorrow / Rest of
    /// (the next 7 business days). Business days = excluding Saturday & Sunday
    /// for the "rest of week" bucket.
    func groupedUpcoming() -> [(DayGroup, [Meeting])] {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        let startOfDayAfterTomorrow = cal.date(byAdding: .day, value: 2, to: startOfToday)!

        var businessDayStarts: Set<Date> = []
        var d = startOfDayAfterTomorrow
        var added = 0
        while added < 7 {
            let weekday = cal.component(.weekday, from: d)
            if weekday != 1 && weekday != 7 {
                businessDayStarts.insert(cal.startOfDay(for: d))
                added += 1
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }

        var today: [Meeting] = []
        var tomorrow: [Meeting] = []
        var rest: [Meeting] = []
        for m in upcoming {
            let dayStart = cal.startOfDay(for: m.startDate)
            if dayStart == startOfToday { today.append(m) }
            else if dayStart == startOfTomorrow { tomorrow.append(m) }
            else if businessDayStarts.contains(dayStart) { rest.append(m) }
        }
        return [(.today, today), (.tomorrow, tomorrow), (.restOfWeek, rest)]
    }

    // MARK: - Conversion helpers (used by CalendarStoreActor)

    /// Static + nonisolated so it's callable from `CalendarStoreActor`
    /// without a main-actor hop.
    nonisolated static func convert(_ event: EKEvent) -> Meeting {
        let attendees = (event.attendees ?? []).compactMap { participant -> String? in
            let name = participant.name ?? ""
            let urlString = participant.url.absoluteString
            let email = urlString.hasPrefix("mailto:")
                ? String(urlString.dropFirst("mailto:".count))
                : urlString
            return name.isEmpty ? email : "\(name) <\(email)>"
        }
        return Meeting(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            attendees: attendees,
            notes: event.notes,
            location: event.location,
            conferenceURL: extractConferenceURL(from: event),
            calendarName: event.calendar?.title,
            seriesID: event.hasRecurrenceRules ? event.calendarItemIdentifier : nil,
            userDescription: nil,
            userTitle: nil,
            isImpromptu: false
        )
    }

    nonisolated static func hex(from cg: CGColor) -> String {
        guard let components = cg.components, components.count >= 3 else { return "#999999" }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    nonisolated static func extractConferenceURL(from event: EKEvent) -> String? {
        let blobs = [event.notes ?? "", event.location ?? "", event.url?.absoluteString ?? ""]
        let combined = blobs.joined(separator: "\n")
        let patterns = [
            #"https?://[^\s]*zoom\.us/[^\s]+"#,
            #"https?://meet\.google\.com/[^\s]+"#,
            #"https?://[^\s]*teams\.microsoft\.com/[^\s]+"#,
            #"https?://[^\s]*teams\.live\.com/[^\s]+"#,
            #"https?://[^\s]*webex\.com/[^\s]+"#
        ]
        for p in patterns {
            if let range = combined.range(of: p, options: .regularExpression) {
                return String(combined[range])
            }
        }
        return nil
    }
}
