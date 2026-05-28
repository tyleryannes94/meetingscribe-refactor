import Foundation
import VaultKit
import OSLog

/// Reads/writes meeting artifacts on disk. Each meeting lives in a folder
/// grouped by its primary tag:
///
///   <storageDir>/<TagFolder>/<yyyy-MM-dd-HHmm-title>/
///     ├── meeting.json
///     ├── mic.m4a            (merged final)
///     ├── system.m4a         (merged final)
///     ├── audio/             (per-segment originals + manifest.json)
///     ├── transcript.md
///     ├── notes.md           (user notes — editable)
///     ├── summary.md         (AI summary)
///     └── chunks/            (rolling wav chunks during recording — cleaned after)
///
/// `TagFolder` is the meeting's primary tag's `folderName`, or "Untagged" if
/// no tag is set. Quick notes live under `<storageDir>/QuickNotes/<slug>/`
/// and are not handled here (see QuickNoteStore).
///
/// Performance: directory lookups are O(1) via two paths:
///   • `Meeting.relativeFolderPath` (persisted on every write)
///   • A process-local `[meetingID: relativePath]` cache populated on read
///
/// The legacy O(N) walk is only used as a fallback for meetings written
/// before relativeFolderPath existed, and it self-heals (writes the
/// resolved path back to disk so the next access is O(1)).
final class MeetingStore {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "MeetingStore")

    static let meetingSchemaVersion = 2
    static let indexSchemaVersion = 2
    static let untaggedFolder = "Untagged"
    static let quickNotesFolder = "QuickNotes"
    /// Sub-folders we never treat as meeting groupings (case-sensitive matches).
    private static let reservedFolders: Set<String> = [
        "models", "QuickNotes", "logs", "diagnostics"
    ]

    var root: URL { AppSettings.shared.storageDir }

    // MARK: - Directory cache

    /// Process-local cache: meetingID → relative folder path. Eliminates the
    /// O(N) tree walk previously done inside `findExistingDirectory`. Bounded
    /// in size by the number of meetings (small) and invalidated on move /
    /// delete. Concurrency: store is constructed once per app launch and
    /// shared via `MeetingManager.store`, so we serialize cache access on a
    /// private concurrent queue with barriers for writes.
    private let cacheQueue = DispatchQueue(label: "MeetingStore.cache",
                                           attributes: .concurrent)
    private var _directoryByID: [String: String] = [:]

    // MARK: - In-memory index cache (perf rebuild)
    //
    // Was: every `listPastMeetings()` did a fresh disk read + JSON decode
    // of `.meeting-index.json`. With 200+ meetings that's a non-trivial
    // hitch repeated on every onAppear across multiple tabs. Now we hold
    // the parsed list in memory and invalidate it on writes.
    private var _indexMemoryCache: [Meeting]?
    private func cachedIndex() -> [Meeting]? {
        cacheQueue.sync { _indexMemoryCache }
    }
    private func setCachedIndex(_ list: [Meeting]?) {
        cacheQueue.async(flags: .barrier) { self._indexMemoryCache = list }
    }
    /// Synchronously refresh the in-memory cache from the freshest copy
    /// we have. Used after a write so the next read is instant.
    private func refreshMemoryIndexFromDisk() {
        let list = readIndexFromDisk() ?? scanDiskForMeetings()
        setCachedIndex(list)
    }

    private func cachedRelativePath(forID id: String) -> String? {
        cacheQueue.sync { _directoryByID[id] }
    }
    private func setCachedRelativePath(_ path: String, forID id: String) {
        cacheQueue.async(flags: .barrier) { self._directoryByID[id] = path }
    }
    private func invalidateCache(forID id: String) {
        cacheQueue.async(flags: .barrier) { self._directoryByID.removeValue(forKey: id) }
    }
    private func clearCache() {
        cacheQueue.async(flags: .barrier) { self._directoryByID.removeAll() }
    }

    func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Directory resolution

    /// Returns the folder where this meeting *should* live based on its
    /// primary tag (or Untagged). Does not create the folder.
    func desiredDirectory(for meeting: Meeting, primaryTag: MeetingTag?) -> URL {
        let group = primaryTag?.folderName ?? Self.untaggedFolder
        return root
            .appendingPathComponent(group, isDirectory: true)
            .appendingPathComponent(meeting.slug, isDirectory: true)
    }

    /// Returns the actual on-disk directory for this meeting. O(1) when
    /// `relativeFolderPath` is set or the cache is warm; falls back to a
    /// one-time tree walk for legacy meetings (and writes the result back
    /// to the cache + meeting.json so subsequent calls are O(1)).
    func directory(for meeting: Meeting, primaryTag: MeetingTag?) -> URL {
        // 1. Persisted path on the model itself.
        if let rel = meeting.relativeFolderPath, !rel.isEmpty {
            let url = root.appendingPathComponent(rel, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                setCachedRelativePath(rel, forID: meeting.id)
                return url
            }
        }
        // 2. Process-local cache.
        if let rel = cachedRelativePath(forID: meeting.id) {
            let url = root.appendingPathComponent(rel, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            invalidateCache(forID: meeting.id)
        }
        // 3. Desired path (covers the "tag hasn't drifted from slug" case).
        let desired = desiredDirectory(for: meeting, primaryTag: primaryTag)
        if FileManager.default.fileExists(atPath: desired.path) {
            cacheResolvedPath(desired, for: meeting)
            return desired
        }
        // 4. Tree walk fallback.
        if let found = findExistingDirectoryOnDisk(forMeetingID: meeting.id) {
            cacheResolvedPath(found, for: meeting)
            return found
        }
        return desired
    }

    func chunksDirectory(for meeting: Meeting, primaryTag: MeetingTag?) -> URL {
        directory(for: meeting, primaryTag: primaryTag).appendingPathComponent("chunks", isDirectory: true)
    }

    /// Records a freshly-resolved directory in both the in-memory cache and
    /// (best-effort) persists the relative path back to `meeting.json` so the
    /// next launch is O(1) too.
    private func cacheResolvedPath(_ url: URL, for meeting: Meeting) {
        let rel = relativePath(from: url)
        setCachedRelativePath(rel, forID: meeting.id)
        // Self-heal: rewrite meeting.json with the resolved path so future
        // reads skip even the cache lookup.
        if meeting.relativeFolderPath != rel {
            var updated = meeting
            updated.relativeFolderPath = rel
            try? writeMeetingFile(updated, in: url)
        }
    }

    private func relativePath(from url: URL) -> String {
        let rootPath = root.path
        let p = url.path
        if p.hasPrefix(rootPath) {
            var rel = String(p.dropFirst(rootPath.count))
            while rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        }
        return url.lastPathComponent
    }

    // MARK: - Coordinated writes

    /// Writes `data` to `url` via NSFileCoordinator so iCloud Drive / any
    /// other NSFilePresenter sees a consistent file at all times.
    func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing,
                               error: &coordinatorError) { resolvedURL in
            do {
                let dir = resolvedURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: resolvedURL, options: .atomic)
            } catch { writeError = error }
        }
        if let err = coordinatorError ?? writeError { throw err }
    }

    /// Writes a UTF-8 string to `url` via NSFileCoordinator.
    func coordinatedWrite(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try coordinatedWrite(data, to: url)
    }

    // MARK: - Read / write per-file

    /// Writes the meeting JSON in the canonical location (resolved via the
    /// tag) and refreshes its `relativeFolderPath`. Also keeps the index
    /// in sync so the next `listPastMeetings()` is O(1).
    func writeMeeting(_ meeting: Meeting, primaryTag: MeetingTag?) throws {
        try ensureRoot()
        let dir = directory(for: meeting, primaryTag: primaryTag)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var updated = meeting
        updated.relativeFolderPath = relativePath(from: dir)
        try writeMeetingFile(updated, in: dir)
        setCachedRelativePath(updated.relativeFolderPath ?? "", forID: meeting.id)
        upsertInIndex(updated)
        updateRecentJSON(vaultURL: root)
    }

    /// Writes `_recent.json` at the vault root — a lightweight stub array of
    /// the 200 most-recent meetings from the last 90 days. Used by the iPhone
    /// Shortcuts integration to populate meeting-picker UIs without reading
    /// every individual `meeting.json`.
    func updateRecentJSON(vaultURL: URL) {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let allMeetings = cachedIndex() ?? []
        let recent = allMeetings
            .filter { $0.startDate > cutoff }
            .sorted { $0.startDate > $1.startDate }
            .prefix(200)
            .map { m -> [String: Any] in
                let hasSummary: Bool = {
                    guard let rel = m.relativeFolderPath, !rel.isEmpty else { return false }
                    let summaryURL = vaultURL
                        .appendingPathComponent(rel)
                        .appendingPathComponent("summary.md")
                    return FileManager.default.fileExists(atPath: summaryURL.path)
                }()
                let stub: [String: Any] = [
                    "id":           m.id,
                    "title":        m.displayTitle,
                    "startDate":    ISO8601DateFormatter().string(from: m.startDate),
                    "folderPath":   m.relativeFolderPath ?? "",
                    "hasSummary":   hasSummary,
                    "participants": m.attendees
                ]
                return stub
            }
        guard let data = try? JSONSerialization.data(
            withJSONObject: Array(recent),
            options: [.prettyPrinted]
        ) else { return }
        let url = vaultURL.appendingPathComponent("_recent.json")
        try? data.write(to: url, options: .atomic)
    }

    /// Low-level write — writes `meeting.json` in `dir` directly, no
    /// directory resolution. Used by self-healing paths that already know
    /// the directory.
    private func writeMeetingFile(_ meeting: Meeting, in dir: URL) throws {
        let envelope = SchemaEnvelope(version: Self.meetingSchemaVersion, data: meeting)
        let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
        try coordinatedWrite(data, to: dir.appendingPathComponent("meeting.json"))
    }

    func readMeeting(at dir: URL) -> Meeting? {
        let url = dir.appendingPathComponent("meeting.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        // SchemaEnvelope.decode accepts both legacy raw payloads and the
        // new versioned envelope, so older files keep working.
        return try? SchemaEnvelope.decode(
            Meeting.self,
            from: data,
            currentVersion: Self.meetingSchemaVersion,
            decoder: SharedCoders.decoder()
        )
    }

    func writeTranscript(_ text: String, for meeting: Meeting, primaryTag: MeetingTag?) throws {
        let url = directory(for: meeting, primaryTag: primaryTag).appendingPathComponent("transcript.md")
        try coordinatedWrite(text, to: url)
    }

    func readTranscript(for meeting: Meeting, primaryTag: MeetingTag?) -> String {
        let url = directory(for: meeting, primaryTag: primaryTag).appendingPathComponent("transcript.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func writeUserNotes(_ text: String, for meeting: Meeting, primaryTag: MeetingTag?) throws {
        let url = directory(for: meeting, primaryTag: primaryTag).appendingPathComponent("notes.md")
        try coordinatedWrite(text, to: url)
    }

    func readUserNotes(for meeting: Meeting, primaryTag: MeetingTag?) -> String {
        let url = directory(for: meeting, primaryTag: primaryTag).appendingPathComponent("notes.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func writeSummary(_ markdown: String, for meeting: Meeting, primaryTag: MeetingTag?) throws {
        let url = directory(for: meeting, primaryTag: primaryTag).appendingPathComponent("summary.md")
        try coordinatedWrite(markdown, to: url)
    }

    func readSummary(for meeting: Meeting, primaryTag: MeetingTag?) -> String {
        let url = directory(for: meeting, primaryTag: primaryTag).appendingPathComponent("summary.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func cleanChunks(for meeting: Meeting, primaryTag: MeetingTag?) {
        let dir = chunksDirectory(for: meeting, primaryTag: primaryTag)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Async file reads (perf rebuild)
    //
    // Sync variants above are kept for back-compat but should be avoided
    // on the main thread. These versions hop off-main for the actual
    // file I/O, which keeps clicking into a meeting glitch-free even
    // when the transcript is hundreds of KB.

    nonisolated func readTranscriptAsync(at dir: URL) async -> String {
        await Self.readFileAsync(dir.appendingPathComponent("transcript.md"))
    }
    nonisolated func readUserNotesAsync(at dir: URL) async -> String {
        await Self.readFileAsync(dir.appendingPathComponent("notes.md"))
    }
    nonisolated func readSummaryAsync(at dir: URL) async -> String {
        await Self.readFileAsync(dir.appendingPathComponent("summary.md"))
    }
    nonisolated private static func readFileAsync(_ url: URL) async -> String {
        await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }.value
    }

    /// Warm the in-memory index on a background queue so the very first
    /// `listPastMeetings()` call from the UI is instant. Called once at
    /// app launch.
    func preloadIndex() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            try? self.ensureRoot()
            if let onDisk = self.readIndexFromDisk() {
                self.setCachedIndex(onDisk)
            } else {
                let scanned = self.scanDiskForMeetings()
                self.setCachedIndex(scanned)
                self.writeIndex(scanned)
            }
        }
    }

    // MARK: - Folder management

    /// Moves a meeting's folder to a new primary-tag group on disk.
    /// Safe to call when the tag hasn't actually changed (it's a no-op then).
    func moveMeeting(_ meeting: Meeting, to newTag: MeetingTag?) throws {
        guard let current = findExistingDirectoryOnDisk(forMeetingID: meeting.id) else { return }
        let target = desiredDirectory(for: meeting, primaryTag: newTag)
        if current.path == target.path { return }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // If something already exists at target, append a suffix.
        var finalTarget = target
        var suffix = 2
        while FileManager.default.fileExists(atPath: finalTarget.path) {
            finalTarget = target.deletingLastPathComponent()
                .appendingPathComponent("\(target.lastPathComponent)-\(suffix)")
            suffix += 1
        }
        try FileManager.default.moveItem(at: current, to: finalTarget)
        log.info("Moved meeting \(meeting.id, privacy: .public) → \(finalTarget.path, privacy: .public)")
        invalidateCache(forID: meeting.id)
        // Refresh cached path + persist the moved meeting's new path.
        var updated = meeting
        updated.relativeFolderPath = relativePath(from: finalTarget)
        try writeMeetingFile(updated, in: finalTarget)
        setCachedRelativePath(updated.relativeFolderPath ?? "", forID: meeting.id)
        upsertInIndex(updated)
    }

    // MARK: - Discovery

    /// Versioned index file. Format:
    ///   { schemaVersion: 2,
    ///     generatedAt: <ISO8601>,
    ///     meetings: [Meeting] }
    /// Writes go through `writeIndex(_:)`; reads are tolerant of the legacy
    /// raw-array format too.
    struct IndexFile: Codable {
        var schemaVersion: Int
        var generatedAt: Date
        var meetings: [Meeting]
    }

    private var indexURL: URL {
        root.appendingPathComponent(".meeting-index.json")
    }

    /// Returns ALL past meetings. Layered cache:
    ///   1. In-memory list (instant; no disk).
    ///   2. On-disk versioned index file (one JSON decode).
    ///   3. Full directory walk fallback (only when index missing).
    /// Set `forceRescan: true` to bypass everything (Refresh button).
    func listPastMeetings(limit: Int = 500, forceRescan: Bool = false) -> [Meeting] {
        try? ensureRoot()
        if !forceRescan, let cached = cachedIndex() {
            return Array(cached.sorted { $0.startDate > $1.startDate }.prefix(limit))
        }
        if !forceRescan, let onDisk = readIndexFromDisk() {
            setCachedIndex(onDisk)
            return Array(onDisk.sorted { $0.startDate > $1.startDate }.prefix(limit))
        }
        let scanned = scanDiskForMeetings()
        writeIndex(scanned)
        return Array(scanned.sorted { $0.startDate > $1.startDate }.prefix(limit))
    }

    /// Forces a full disk re-scan and rewrites the index. Use this after
    /// the user moves the storage folder, or as a manual "rebuild" action.
    ///
    /// WARNING: performs a synchronous directory walk. Must NOT be called
    /// from an `@MainActor` context. Prefer `rebuildIndexAsync()` from UI
    /// or any context where the calling thread is unknown.
    @discardableResult
    func rebuildIndex() -> [Meeting] {
        try? ensureRoot()
        clearCache()
        let scanned = scanDiskForMeetings()
        writeIndex(scanned)
        return scanned
    }

    /// Async-safe variant of `rebuildIndex()`. Dispatches the disk scan to
    /// a background task so the caller's actor (e.g. `@MainActor`) is never
    /// blocked. Returns the freshly-scanned meeting list.
    @discardableResult
    func rebuildIndexAsync() async -> [Meeting] {
        await Task.detached(priority: .utility) { [weak self] () -> [Meeting] in
            guard let self else { return [] }
            return self.rebuildIndex()
        }.value
    }

    /// Persists the in-memory list to the index file. Memory cache is
    /// updated synchronously; disk write happens on a background queue
    /// so the calling thread (often the main thread from a UI write) is
    /// not blocked on JSON encode + atomic file rename.
    func writeIndex(_ meetings: [Meeting]) {
        setCachedIndex(meetings)
        let url = indexURL
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
            } catch {
                // Best-effort — most likely the dir already exists.
            }
            let env = IndexFile(schemaVersion: Self.indexSchemaVersion,
                                generatedAt: Date(),
                                meetings: meetings)
            let enc = SharedCoders.encoder(sorted: true)
            if let data = try? enc.encode(env) {
                try? self.coordinatedWrite(data, to: url)
            }
        }
    }

    /// Upserts a single meeting into the cached index without re-walking
    /// disk. Called from writeMeeting so subsequent listPastMeetings
    /// reflects the change immediately.
    ///
    /// When the in-memory cache is cold AND no index file exists yet, the
    /// fallback is a full disk scan (`scanDiskForMeetings`). That scan is
    /// expensive (O(N) file I/O) and must never block the main thread, so
    /// we dispatch it — along with the subsequent index write — to a
    /// background task. The meeting being upserted is captured and merged
    /// in once the scan finishes.
    func upsertInIndex(_ meeting: Meeting) {
        // Fast path: in-memory cache or on-disk index already available.
        if let existing = cachedIndex() ?? readIndexFromDisk() {
            var list = existing
            if let i = list.firstIndex(where: { $0.id == meeting.id }) {
                list[i] = meeting
            } else {
                list.append(meeting)
            }
            writeIndex(list)
            return
        }

        // Slow path: no cache and no index file — full disk scan required.
        // Dispatch off the calling thread (which may be @MainActor) so the
        // directory walk doesn't block the UI.
        let meetingToUpsert = meeting
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var list = self.scanDiskForMeetings()
            if let i = list.firstIndex(where: { $0.id == meetingToUpsert.id }) {
                list[i] = meetingToUpsert
            } else {
                list.append(meetingToUpsert)
            }
            self.writeIndex(list)
        }
    }

    func removeFromIndex(meetingID: String) {
        var list = cachedIndex() ?? readIndexFromDisk() ?? []
        list.removeAll { $0.id == meetingID }
        writeIndex(list)
        invalidateCache(forID: meetingID)
    }

    private func readIndexFromDisk() -> [Meeting]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        let dec = SharedCoders.decoder()
        if let env = try? dec.decode(IndexFile.self, from: data) {
            return env.meetings
        }
        return try? dec.decode([Meeting].self, from: data)
    }

    /// Heavy: walks every directory under root, reads meeting.json files.
    /// Only used on first launch (no index yet) or rebuildIndex().
    private func scanDiskForMeetings() -> [Meeting] {
        var results: [Meeting] = []
        enumerateMeetingDirectories { dir in
            if let m = readMeeting(at: dir) {
                results.append(m)
                setCachedRelativePath(relativePath(from: dir), forID: m.id)
            }
        }
        return results
    }

    /// O(N) lookup used only when the cache misses and the desired path
    /// doesn't exist. Self-healing: callers update the cache after.
    private func findExistingDirectoryOnDisk(forMeetingID id: String) -> URL? {
        var found: URL?
        enumerateMeetingDirectories { dir in
            guard found == nil else { return }
            if let m = readMeeting(at: dir), m.id == id { found = dir }
        }
        return found
    }

    // MARK: - One enumerator to rule them all

    /// Calls `body` once for every directory containing a `meeting.json`
    /// — both top-level and one-level-nested (the tag-folder layout).
    /// Skips reserved subfolders (models, QuickNotes, logs, etc.).
    ///
    /// This is the single helper that replaces three previously near-
    /// identical walks. Any future layout change goes in one place.
    private func enumerateMeetingDirectories(_ body: (URL) -> Void) {
        let fm = FileManager.default
        let topLevel = (try? fm.contentsOfDirectory(at: root,
                                                    includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        for url in topLevel {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if Self.reservedFolders.contains(url.lastPathComponent) { continue }
            if fm.fileExists(atPath: url.appendingPathComponent("meeting.json").path) {
                body(url)
                continue
            }
            let inner = (try? fm.contentsOfDirectory(at: url,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? []
            for sub in inner {
                guard (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if fm.fileExists(atPath: sub.appendingPathComponent("meeting.json").path) {
                    body(sub)
                }
            }
        }
    }

    /// Public read-only enumerator (used by startup cleanup tasks and tests).
    func forEachMeetingDirectory(_ body: (URL) -> Void) {
        enumerateMeetingDirectories(body)
    }

    /// Searches all meeting directories for one matching `id`. Public
    /// surface for legacy callers that don't have the Meeting in hand
    /// (e.g. a JSON-RPC tool call by id).
    func findExistingDirectory(forMeetingID id: String) -> URL? {
        if let rel = cachedRelativePath(forID: id) {
            let url = root.appendingPathComponent(rel, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            invalidateCache(forID: id)
        }
        return findExistingDirectoryOnDisk(forMeetingID: id)
    }

    // MARK: - Startup cleanup (3.4B: orphaned chunks)

    /// Deletes any `chunks/` subdirectory whose newest file is older than
    /// `olderThan` (default 24h) — typically left behind by mid-meeting
    /// crashes. Called once on app launch from MeetingScribeApp.startServices.
    func cleanupOrphanedChunks(olderThan interval: TimeInterval = 24 * 60 * 60) {
        let cutoff = Date().addingTimeInterval(-interval)
        var cleaned = 0
        var bytesCleaned: Int64 = 0
        enumerateMeetingDirectories { dir in
            let chunks = dir.appendingPathComponent("chunks", isDirectory: true)
            guard FileManager.default.fileExists(atPath: chunks.path) else { return }
            // Newest file in chunks/ — if it's older than cutoff, the whole
            // dir is stale.
            let newest = (try? FileManager.default.contentsOfDirectory(
                at: chunks, includingPropertiesForKeys: [.contentModificationDateKey]
            ))?.compactMap { url -> Date? in
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }.max()
            guard let newest, newest < cutoff else { return }
            let size = directorySize(at: chunks)
            try? FileManager.default.removeItem(at: chunks)
            cleaned += 1
            bytesCleaned += size
        }
        if cleaned > 0 {
            log.info("Cleaned \(cleaned) orphaned chunks dir(s), reclaimed \(bytesCleaned) bytes")
            AppLog.info("Storage", "Orphaned chunks cleanup",
                        ["dirs": "\(cleaned)", "bytes": "\(bytesCleaned)"])
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in enumerator {
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
