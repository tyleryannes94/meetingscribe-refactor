import Foundation
import EventKit
import OSLog

/// Actor-wrapped EventKit store. Replaces the previous pattern of holding
/// `let store = EKEventStore()` on the main-actor `CalendarService` AND
/// creating a SECOND `EKEventStore` inside a detached background task
/// (audit 5.3). Now there's exactly one EventKit store per app session,
/// and it's safe to query from any actor.
///
/// EventKit's documentation says individual `EKEventStore` instances are
/// safe to query across threads as long as you don't simultaneously mutate
/// from multiple threads; the actor enforces that contract.
@available(macOS 14.0, *)
actor CalendarStoreActor {
    static let shared = CalendarStoreActor()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "CalendarStore")
    private let store = EKEventStore()

    private init() {}

    /// Request full-access calendar permission. Returns whether it was granted.
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            log.error("Calendar access error: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.reportAsync(error, category: .calendar)
            return false
        }
    }

    /// Snapshot of all `EKCalendar`s currently exposed to us.
    func calendarOptions() -> [CalendarService.CalendarOption] {
        store.calendars(for: .event).map { cal in
            let hex = cal.cgColor.map(CalendarService.hex(from:)) ?? "#999999"
            return CalendarService.CalendarOption(id: cal.calendarIdentifier,
                                                  title: cal.title,
                                                  source: cal.source?.title ?? "",
                                                  color: hex)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Fetch meetings in a window. `enabledIDs.isEmpty` includes everything.
    func meetings(from: Date,
                  to: Date,
                  enabledIDs: Set<String>,
                  filterConferenceURLs: Bool) -> [Meeting] {
        let allCalendars = store.calendars(for: .event)
        var calendars = enabledIDs.isEmpty
            ? allCalendars
            : allCalendars.filter { enabledIDs.contains($0.calendarIdentifier) }
        // Stale-ID self-heal: EventKit regenerates `calendarIdentifier`s for
        // Google/CalDAV accounts. When a saved filter matches zero live
        // calendars, fall back to all of them rather than returning an empty
        // list (which would blank the user's meetings). Mirrors the app target.
        if calendars.isEmpty, !allCalendars.isEmpty, !enabledIDs.isEmpty {
            calendars = allCalendars
        }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        var result = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map(CalendarService.convert)
        if filterConferenceURLs {
            result = result.filter { ($0.conferenceURL ?? "").isEmpty == false }
        }
        return result
    }
}
