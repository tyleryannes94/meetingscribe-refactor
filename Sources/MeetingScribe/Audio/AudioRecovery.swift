import Foundation
import VaultKit
import OSLog

/// Crash- and iCloud-resilient audio recovery (failsafes).
///
/// Two real-world failure modes this guards against:
///   1. **iCloud eviction.** The meeting library lives in iCloud Drive. When a
///      recording's `.m4a` segments are evicted, the on-disk entry becomes a
///      hidden placeholder named `.<name>.icloud`. The old discovery (which
///      matched `mic-…m4a` by prefix) skipped these, so a perfectly intact
///      recording looked like "no audio." We now recognize placeholders, count
///      them as present, and can download them on demand.
///   2. **App crash mid-recording.** Segments are written incrementally during
///      capture, but a crash means finalize/transcribe never ran. We drop a
///      `.recording.inprogress` marker at start and remove it on clean stop, so
///      a launch sweep can find interrupted recordings and recover them.
///
/// All methods are `nonisolated` / static so they can run off the main thread
/// from the audio pipeline's detached tasks.
enum AudioRecovery {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "AudioRecovery")

    /// Audio container/extensions we treat as a recoverable segment. Broader
    /// than the recorder's own `.m4a` so manually-uploaded files and raw `.wav`
    /// capture files are recoverable too.
    static let supportedExtensions: Set<String> = [
        "m4a", "wav", "mp3", "aac", "caf", "m4b", "aiff", "aif", "flac", "mp4", "mov"
    ]

    /// Marker file dropped in `audio/` while a recording is in flight.
    static let inProgressMarker = ".recording.inprogress"

    static func audioDir(for meetingDir: URL) -> URL {
        meetingDir.appendingPathComponent("audio", isDirectory: true)
    }

    // MARK: - Discovery (fast, non-blocking — safe to call from the main actor)

    /// Discovers mic/system segments tolerant of (a) any supported audio
    /// extension and (b) iCloud placeholder files. Returns the *real* (visible)
    /// URLs sorted by name. Does NOT download anything — call `ensureDownloaded`
    /// before you actually need the bytes.
    static func discoverSegments(in meetingDir: URL) -> (mic: [URL], system: [URL]) {
        let dir = audioDir(for: meetingDir)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return ([], []) }

        var realNames = Set<String>()
        for entry in entries {
            guard let real = realName(entry) else { continue }
            realNames.insert(real)
        }
        func pick(_ prefix: String) -> [URL] {
            realNames
                .filter { name in
                    name.hasPrefix(prefix) &&
                    supportedExtensions.contains((name as NSString).pathExtension.lowercased())
                }
                .sorted()
                .map { dir.appendingPathComponent($0) }
        }
        return (pick("mic-"), pick("system-"))
    }

    /// Maps a directory entry to the real (visible) filename. Unwraps iCloud
    /// placeholders (`.<name>.icloud`) and ignores unrelated dotfiles.
    private static func realName(_ entry: String) -> String? {
        if entry.hasPrefix(".") && entry.hasSuffix(".icloud") {
            return String(entry.dropFirst().dropLast(".icloud".count))
        }
        if entry.hasPrefix(".") { return nil }
        return entry
    }

    /// True if the folder holds recoverable audio of either kind (including
    /// evicted iCloud placeholders).
    static func hasRecoverableAudio(in meetingDir: URL) -> Bool {
        let s = discoverSegments(in: meetingDir)
        return !s.mic.isEmpty || !s.system.isEmpty
    }

    // MARK: - iCloud download

    /// Returns true when `url` is materialized on disk (downloaded, non-empty).
    static func isDownloaded(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .fileSizeKey])
        if let status = values?.ubiquitousItemDownloadingStatus {
            return status == .current
        }
        if let size = values?.fileSize { return size > 0 }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Triggers iCloud download for any evicted segment and waits (bounded) for
    /// them to materialize. Off-main only.
    static func ensureDownloaded(in meetingDir: URL, timeout: TimeInterval = 180) async {
        let (mic, sys) = discoverSegments(in: meetingDir)
        let urls = mic + sys
        guard !urls.isEmpty else { return }
        let fm = FileManager.default
        var triggered = false
        for url in urls where !isDownloaded(url) {
            try? fm.startDownloadingUbiquitousItem(at: url)
            triggered = true
        }
        guard triggered else { return }
        log.info("Downloading \(urls.count) evicted audio file(s) for \(meetingDir.lastPathComponent, privacy: .public)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if urls.allSatisfy({ isDownloaded($0) }) { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        log.warning("ensureDownloaded timed out for \(meetingDir.path, privacy: .public)")
    }

    // MARK: - Manifest rebuild

    /// Rebuilds `audio/manifest.json` from whatever segments are on disk.
    /// Returns the segment count. Idempotent.
    @discardableResult
    static func rebuildManifest(in meetingDir: URL) -> Int {
        let (mic, sys) = discoverSegments(in: meetingDir)
        let count = max(mic.count, sys.count)
        guard count > 0 else { return 0 }
        let now = Date()
        var segments: [AudioManifestDTO.Segment] = []
        for i in 0..<count {
            segments.append(.init(index: i + 1,
                                  micFile: mic.indices.contains(i) ? mic[i].lastPathComponent : nil,
                                  systemFile: sys.indices.contains(i) ? sys[i].lastPathComponent : nil,
                                  startedAt: now, endedAt: now))
        }
        let dto = AudioManifestDTO(schemaVersion: AudioManifestStore.currentSchemaVersion, segments: segments)
        try? AudioManifestStore.write(dto, meetingDir: meetingDir)
        return count
    }

    // MARK: - Crash markers

    /// Drop the in-progress marker at recording start.
    static func markRecordingStarted(in meetingDir: URL) {
        let dir = audioDir(for: meetingDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(inProgressMarker)
        let payload = ISO8601DateFormatter().string(from: Date())
        try? Data(payload.utf8).write(to: url, options: .atomic)
    }

    /// Remove the marker on a clean stop/cancel.
    static func clearRecordingMarker(in meetingDir: URL) {
        let url = audioDir(for: meetingDir).appendingPathComponent(inProgressMarker)
        try? FileManager.default.removeItem(at: url)
    }

    static func hasRecordingMarker(in meetingDir: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: audioDir(for: meetingDir).appendingPathComponent(inProgressMarker).path)
    }

    /// Launch sweep: returns meeting directories that still carry an in-progress
    /// marker (i.e. a recording that never cleanly stopped — almost always a
    /// crash). Each returned URL is the meeting dir (parent of `audio/`).
    static func meetingsWithInterruptedRecordings(under root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: nil,
                                             options: [.skipsPackageDescendants]) else { return [] }
        var dirs: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == inProgressMarker {
            // <meetingDir>/audio/.recording.inprogress → <meetingDir>
            dirs.append(url.deletingLastPathComponent().deletingLastPathComponent())
        }
        return dirs
    }
}
