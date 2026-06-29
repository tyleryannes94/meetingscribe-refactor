import Foundation

/// Tiny time-based throttle so repeated `.onAppear` refreshes coalesce into at
/// most one disk scan per `interval`. Extracted from the inline pattern already
/// used by `CalendarService.refreshUpcoming` (30 s) and
/// `MeetingManager.refreshPastMeetings` (2 s) so the voice-note and
/// screen-recording controllers — whose `refresh()` re-scans the vault
/// synchronously on every keep-alive tab re-appearance — can share it.
///
/// Lives in the data layer (on the `@StateObject` controller) rather than as a
/// SwiftUI `@State` gate so the throttle window survives view-body rebuilds.
struct RefreshThrottle {
    private var last: Date = .distantPast
    let interval: TimeInterval

    init(interval: TimeInterval = 30) { self.interval = interval }

    /// Returns true — and arms the next window — when enough time has elapsed
    /// (or `force` is set). Returns false to skip a redundant refresh.
    mutating func shouldRun(force: Bool = false, now: Date = Date()) -> Bool {
        if !force, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }

    /// Reset so the next `shouldRun()` returns true — call after an external
    /// mutation (a write) that the cached snapshot must reflect immediately.
    mutating func invalidate() { last = .distantPast }
}
