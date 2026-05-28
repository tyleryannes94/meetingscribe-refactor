import Foundation
import VaultKit
import OSLog

/// Owns the per-meeting audio segment bookkeeping. The manifest lives at
/// `<meetingDir>/audio/manifest.json` and is the single source of truth for
/// "how many segments has this meeting recorded, and where are they".
///
/// Replaces the old `Meeting.segmentCount` field as the authoritative count
/// (that field is still written for backward compatibility but no new code
/// path increments it directly).
///
/// Thread-safety: the audio pipeline calls into this from a single recording
/// task at a time per meeting. Each call rewrites the manifest atomically.
struct AudioManifestStore {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe",
                                    category: "AudioManifest")
    static let currentSchemaVersion = 1
    static let filename = "manifest.json"

    /// Reads the manifest at `<meetingDir>/audio/manifest.json`. If missing or
    /// unreadable, falls back to discovering segments by listing the `audio/`
    /// directory (handles meetings recorded before the manifest existed) AND
    /// upgrades by writing a fresh manifest as a side-effect.
    static func read(meetingDir: URL) -> AudioManifestDTO {
        let url = manifestURL(meetingDir: meetingDir)
        if let data = try? Data(contentsOf: url) {
            if let dto = try? SchemaEnvelope.decode(AudioManifestDTO.self,
                                                    from: data,
                                                    currentVersion: currentSchemaVersion) {
                return dto
            }
            log.warning("manifest.json at \(url.path, privacy: .public) failed to decode — rebuilding from disk")
        }
        // Build from filesystem.
        let dto = scanFilesystem(meetingDir: meetingDir)
        // Side-effect upgrade: persist if we found anything.
        if !dto.segments.isEmpty { try? write(dto, meetingDir: meetingDir) }
        return dto
    }

    /// Persist the manifest atomically.
    static func write(_ manifest: AudioManifestDTO, meetingDir: URL) throws {
        var m = manifest
        m.schemaVersion = currentSchemaVersion
        let env = SchemaEnvelope(version: currentSchemaVersion, data: m)
        let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(env)
        let url = manifestURL(meetingDir: meetingDir)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Append a new segment. Returns the index assigned to it (1-based).
    @discardableResult
    static func appendSegment(meetingDir: URL,
                              micFile: String?,
                              systemFile: String?,
                              startedAt: Date = Date()) throws -> Int {
        var manifest = read(meetingDir: meetingDir)
        let nextIndex = (manifest.segments.map(\.index).max() ?? 0) + 1
        manifest.segments.append(.init(index: nextIndex,
                                       micFile: micFile,
                                       systemFile: systemFile,
                                       startedAt: startedAt,
                                       endedAt: nil))
        try write(manifest, meetingDir: meetingDir)
        return nextIndex
    }

    /// Mark the last open segment as finished.
    static func closeLastSegment(meetingDir: URL, endedAt: Date = Date()) {
        var manifest = read(meetingDir: meetingDir)
        guard let lastIdx = manifest.segments.indices.last else { return }
        guard manifest.segments[lastIdx].endedAt == nil else { return }
        let s = manifest.segments[lastIdx]
        manifest.segments[lastIdx] = .init(index: s.index, micFile: s.micFile,
                                           systemFile: s.systemFile,
                                           startedAt: s.startedAt, endedAt: endedAt)
        try? write(manifest, meetingDir: meetingDir)
    }

    /// True if the meeting has at least one segment with audio of either kind.
    static func hasAnyAudio(meetingDir: URL) -> Bool {
        let m = read(meetingDir: meetingDir)
        return m.segments.contains { $0.micFile != nil || $0.systemFile != nil }
    }

    /// Convenience: total segment count.
    static func segmentCount(meetingDir: URL) -> Int {
        read(meetingDir: meetingDir).segments.count
    }

    // MARK: - Filesystem discovery (fallback for pre-manifest meetings)

    private static func scanFilesystem(meetingDir: URL) -> AudioManifestDTO {
        let audioDir = meetingDir.appendingPathComponent("audio", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: audioDir.path),
              let contents = try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) else {
            return AudioManifestDTO()
        }
        let mics = contents.filter { $0.lastPathComponent.hasPrefix("mic-") &&
                                     $0.pathExtension.lowercased() == "m4a" }
                           .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let systems = contents.filter { $0.lastPathComponent.hasPrefix("system-") &&
                                        $0.pathExtension.lowercased() == "m4a" }
                              .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let count = max(mics.count, systems.count)
        guard count > 0 else { return AudioManifestDTO() }
        let now = Date()
        var segments: [AudioManifestDTO.Segment] = []
        for i in 0..<count {
            let mic = mics.indices.contains(i) ? mics[i].lastPathComponent : nil
            let sys = systems.indices.contains(i) ? systems[i].lastPathComponent : nil
            segments.append(.init(index: i + 1, micFile: mic, systemFile: sys,
                                  startedAt: now, endedAt: now))
        }
        return AudioManifestDTO(schemaVersion: currentSchemaVersion, segments: segments)
    }

    private static func manifestURL(meetingDir: URL) -> URL {
        meetingDir.appendingPathComponent("audio", isDirectory: true)
                  .appendingPathComponent(filename)
    }
}
