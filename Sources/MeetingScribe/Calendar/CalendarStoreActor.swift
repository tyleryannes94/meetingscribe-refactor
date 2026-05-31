import Foundation
@preconcurrency import EventKit
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

    // MARK: - Write-back (P4-1)

    /// Append (or replace) the meeting recap inside the calendar event's notes,
    /// delimited by markers so re-running updates in place rather than stacking.
    /// Returns whether the save succeeded. Full-access calendar permission is
    /// already requested at onboarding.
    func attachRecap(toEventID id: String, markdown: String, deepLink: String) -> Bool {
        guard let event = store.event(withIdentifier: id) else { return false }
        let begin = "<!-- MeetingScribe recap -->"
        let end = "<!-- /MeetingScribe recap -->"
        let block = "\(begin)\n\(markdown)\n\n\(deepLink)\n\(end)"
        var notes = event.notes ?? ""
        if let r1 = notes.range(of: begin), let r2 = notes.range(of: end), r1.lowerBound < r2.upperBound {
            notes.replaceSubrange(r1.lowerBound..<r2.upperBound, with: block)
        } else {
            notes = notes.isEmpty ? block : notes + "\n\n" + block
        }
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            log.error("Calendar recap write failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.reportAsync(error, category: .calendar)
            return false
        }
    }

    /// Create a follow-up event on the user's default calendar. Returns the new
    /// event identifier, or nil on failure.
    @discardableResult
    func scheduleFollowUp(title: String, start: Date, durationMinutes: Int, notes: String?) -> String? {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        guard event.calendar != nil else { return nil }
        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            log.error("Follow-up create failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.reportAsync(error, category: .calendar)
            return nil
        }
    }

    /// Fetch meetings in a window. `enabledIDs.isEmpty` includes everything.
    func meetings(from: Date,
                  to: Date,
                  enabledIDs: Set<String>,
                  filterConferenceURLs: Bool) -> [Meeting] {
        let allCalendars = store.calendars(for: .event)
        let calendars = enabledIDs.isEmpty
            ? allCalendars
            : allCalendars.filter { enabledIDs.contains($0.calendarIdentifier) }
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
