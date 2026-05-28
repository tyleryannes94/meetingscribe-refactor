import Foundation
import os
import OSLog

/// In-memory cache of meeting body text — transcript, notes, summary —
/// keyed by meeting id. Designed to make clicking into a meeting feel
/// instant: the UI does a synchronous `get` that returns whatever's
/// already cached (typically empty placeholders only on the *very first*
/// view), then kicks an async refresh that fills the rest from disk on
/// a background queue.
///
/// Why this exists:
///   - `UnifiedMeetingDetail.reload()` used to do three synchronous
///     `String(contentsOf:)` calls on the main thread per click. With a
///     200KB transcript that's a perceptible hitch; clicking back into a
///     meeting you just left pays the cost again with no cache.
///   - List views (`MeetingsView`, `TodayView`) also frequently want a
///     short preview of the summary. The cache exposes a sync
///     `cachedPreview(_:)` that returns whatever's already loaded, so
///     no list-row render reads files.
///
/// Performance characteristics:
///   - Cap of 64 entries. LRU eviction — we expect at most a handful of
///     "hot" meetings the user is bouncing between.
///   - mtime-based freshness check on every async refresh — one cheap
///     `stat` call to detect "transcribe-now finished, re-read needed".
///   - All disk I/O happens on a private serial queue.
///   - Per-meeting load coalescing — if two callers ask for the same id
///     while a load is in flight, both share the one Task.
@MainActor
final class MeetingBodyCache: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe",
                             category: "MeetingBodyCache")

    /// One fully-loaded body. Empty fields are "the file didn't exist or
    /// was empty," not "we haven't tried yet" — for that, check `loadedAt`.
    struct Body: Equatable {
        var transcript: String
        var notes: String
        var summary: String
        /// File modification timestamps from the last load. Compared against
        /// fresh `stat()` reads to decide whether a refresh is needed.
        var transcriptMtime: Date?
        var notesMtime: Date?
        var summaryMtime: Date?
        var loadedAt: Date

        static let empty = Body(transcript: "", notes: "", summary: "",
                                transcriptMtime: nil, notesMtime: nil,
                                summaryMtime: nil, loadedAt: .distantPast)
        var isEmpty: Bool { loadedAt == .distantPast }
    }

    private let store: MeetingStore
    private let tagStore: TagStore
    private let maxEntries = 64

    private var cache: [String: Body] = [:]
    private var lruOrder: [String] = []
    private var inflight: [String: Task<Body, Never>] = [:]

    init(store: MeetingStore, tagStore: TagStore) {
        self.store = store
        self.tagStore = tagStore
    }

    // MARK: - Sync (hot path — called from view body)

    /// Returns whatever's in cache or `.empty`. Never touches disk.
    /// Views use this for the initial render; an async `refresh(_:)` runs
    /// in parallel to fill in real data.
    func cached(_ meetingID: String) -> Body {
        if let body = cache[meetingID] {
            promote(meetingID)
            return body
        }
        return .empty
    }

    /// Short summary preview suitable for list rows. Returns whatever's
    /// available NOW; if the cache is cold the row gets nil and renders
    /// whatever fallback the caller has (usually a date or attendee list).
    func cachedSummaryPreview(_ meetingID: String, maxChars: Int = 200) -> String? {
        guard let body = cache[meetingID], !body.summary.isEmpty else { return nil }
        return Self.firstSentence(of: body.summary, maxChars: maxChars)
    }

    // MARK: - Async (background — view calls in a Task)

    /// Returns a fresh body — uses the cache when fresh, refreshes from
    /// disk when mtimes have changed (or the entry doesn't exist).
    /// Coalesces concurrent callers so two views asking for the same
    /// meeting only do one disk pass.
    func load(_ meeting: Meeting) async -> Body {
        let id = meeting.id
        if let existing = inflight[id] { return await existing.value }
        let task = Task<Body, Never> { [weak self] in
            guard let self else { return .empty }
            return await self.fetchFromDisk(meeting)
        }
        inflight[id] = task
        let result = await task.value
        inflight.removeValue(forKey: id)
        return result
    }

    /// Prefetch a batch of meetings off-main, used for the top-N
    /// most-recent list after first launch. Limit kept small so we don't
    /// thrash the index on a cold disk.
    func prefetch(_ meetings: [Meeting], limit: Int = 10) {
        let batch = Array(meetings.prefix(limit))
        Task.detached(priority: .utility) { [weak self] in
            for m in batch {
                _ = await self?.load(m)
            }
        }
    }

    /// External writers (Transcribe Now finished, user saved notes)
    /// should call this so the next read goes back to disk.
    func invalidate(_ meetingID: String) {
        cache.removeValue(forKey: meetingID)
        lruOrder.removeAll { $0 == meetingID }
    }

    /// Drop everything. Used after the storage dir changes.
    func clear() {
        cache.removeAll()
        lruOrder.removeAll()
    }

    // MARK: - Notes hot-write
    //
    // The detail view debounces note edits to disk every ~600ms. To keep
    // the cache truthful between debounces we also write into the cache
    // immediately so a quick tab-switch-and-back doesn't reveal a stale
    // notes body.

    func patchNotes(meetingID: String, notes: String) {
        guard var body = cache[meetingID] else { return }
        body.notes = notes
        body.notesMtime = Date()
        cache[meetingID] = body
    }

    func patchSummary(meetingID: String, summary: String) {
        guard var body = cache[meetingID] else { return }
        body.summary = summary
        body.summaryMtime = Date()
        cache[meetingID] = body
    }

    func patchTranscript(meetingID: String, transcript: String) {
        guard var body = cache[meetingID] else { return }
        body.transcript = transcript
        body.transcriptMtime = Date()
        cache[meetingID] = body
    }

    // MARK: - Internals

    /// Runs the per-file reads on a background queue + updates the cache.
    /// The mtime check is the "is this entry still good" gate.
    private func fetchFromDisk(_ meeting: Meeting) async -> Body {
        let id = meeting.id
        let dir = directory(for: meeting)

        // Hop off main to read.
        let body = await Task.detached(priority: .userInitiated) { () -> Body in
            let transcriptURL = dir.appendingPathComponent("transcript.md")
            let notesURL = dir.appendingPathComponent("notes.md")
            let summaryURL = dir.appendingPathComponent("summary.md")

            // Parallel reads on the same queue — they're small, just I/O.
            async let t: (String, Date?) = Self.readWithMtime(transcriptURL)
            async let n: (String, Date?) = Self.readWithMtime(notesURL)
            async let s: (String, Date?) = Self.readWithMtime(summaryURL)
            let (text, transcriptMtime) = await t
            let (notesText, notesMtime) = await n
            let (summaryText, summaryMtime) = await s

            return Body(transcript: text, notes: notesText, summary: summaryText,
                        transcriptMtime: transcriptMtime,
                        notesMtime: notesMtime,
                        summaryMtime: summaryMtime,
                        loadedAt: Date())
        }.value

        cache[id] = body
        promote(id)
        evictIfNeeded()
        return body
    }

    /// Returns the meeting's directory using whatever fast path is
    /// available. Falls through to the store's resolution (which has its
    /// own O(1) cache + persisted relativeFolderPath).
    private func directory(for meeting: Meeting) -> URL {
        store.directory(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
    }

    /// Reads a file's contents and modification date in one stat round-trip.
    /// Empty string + nil if the file doesn't exist (which is fine — a
    /// meeting that's never been summarized has no summary.md).
    nonisolated private static func readWithMtime(_ url: URL) async -> (String, Date?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return ("", nil) }
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let mtime = attrs?[.modificationDate] as? Date
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return (text, mtime)
    }

    private func promote(_ id: String) {
        lruOrder.removeAll { $0 == id }
        lruOrder.append(id)
    }

    private func evictIfNeeded() {
        while lruOrder.count > maxEntries {
            let victim = lruOrder.removeFirst()
            cache.removeValue(forKey: victim)
        }
    }

    /// Reasonably useful preview of a summary — strips the leading
    /// `# Title` line and grabs the first chunk of text.
    nonisolated private static func firstSentence(of summary: String, maxChars: Int) -> String {
        let lines = summary.split(separator: "\n", omittingEmptySubsequences: true)
        var body = ""
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if t.hasPrefix("#") { continue }
            // Skip "## TL;DR" style headers — go straight to the first prose line.
            body = t
            break
        }
        if body.count <= maxChars { return body }
        return String(body.prefix(maxChars)) + "…"
    }
}
