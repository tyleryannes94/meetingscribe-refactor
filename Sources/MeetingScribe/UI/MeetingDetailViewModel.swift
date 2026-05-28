import Foundation
import Observation
import OSLog

/// Owns body loading + cancellation for ONE detail-view appearance.
///
/// Replaces the previous pattern in `UnifiedMeetingDetail.reload()` of
/// three synchronous main-thread file reads on every click. The view
/// now:
///   1. Reads `cache.cached(id)` synchronously — instant first paint
///      with whatever was already loaded (typically empty only on the
///      very first session view of that meeting).
///   2. Kicks an async `load(meeting)` that fills in the latest from
///      disk and updates the published properties.
///
/// Cancellation: switching meetings (or dismissing the detail view)
/// cancels the in-flight task so a slow disk read on meeting A never
/// races to overwrite meeting B's freshly-rendered state.
@available(macOS 14.0, *)
@MainActor
@Observable
final class MeetingDetailViewModel {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe",
                             category: "MeetingDetailVM")

    private(set) var transcript: String = ""
    private(set) var notes: String = ""
    private(set) var summary: String = ""
    private(set) var isLoading: Bool = false
    /// True when the body data is coming from the in-memory cache rather
    /// than disk — useful for "Updated just now / a moment ago" badging
    /// if the UI ever wants it.
    private(set) var loadedFromCache: Bool = false
    /// Most recently loaded meeting id — used to ignore late completions
    /// that finish after the user has switched away.
    private(set) var currentMeetingID: String?

    private weak var cache: MeetingBodyCache?
    private var loadTask: Task<Void, Never>?

    init(cache: MeetingBodyCache?) {
        self.cache = cache
    }

    /// Show what we already have synchronously, then refresh in the
    /// background. Cancels any in-flight load for the previous meeting.
    func show(_ meeting: Meeting) {
        // Cancel the previous load — a slow read for a different meeting
        // must not be allowed to write into our state.
        loadTask?.cancel()
        currentMeetingID = meeting.id

        // 1. Synchronous cache read — instant first paint.
        let snap = cache?.cached(meeting.id) ?? .empty
        applyIfCurrent(meeting.id, snap)
        loadedFromCache = !snap.isEmpty
        isLoading = snap.isEmpty

        // 2. Async refresh from disk.
        loadTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await self.cache?.load(meeting) ?? .empty
            guard !Task.isCancelled else { return }
            self.applyIfCurrent(meeting.id, loaded)
            if self.currentMeetingID == meeting.id {
                self.isLoading = false
                self.loadedFromCache = false
            }
        }
    }

    /// Clear state — call when leaving the view entirely.
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        transcript = ""
        notes = ""
        summary = ""
        isLoading = false
        loadedFromCache = false
        currentMeetingID = nil
    }

    /// Optimistic write — when the user types in the notes field we
    /// update the cache + our own state right away. The debounced
    /// disk persistence runs separately.
    func patchNotes(_ text: String) {
        notes = text
        if let id = currentMeetingID {
            cache?.patchNotes(meetingID: id, notes: text)
        }
    }

    /// Called by the manager after a Transcribe Now run finishes for
    /// this meeting — drops the cache entry and re-loads.
    func forceRefresh(_ meeting: Meeting) {
        cache?.invalidate(meeting.id)
        show(meeting)
    }

    private func applyIfCurrent(_ id: String, _ body: MeetingBodyCache.Body) {
        guard currentMeetingID == id else { return }
        transcript = body.transcript
        notes = body.notes
        summary = body.summary
    }
}
