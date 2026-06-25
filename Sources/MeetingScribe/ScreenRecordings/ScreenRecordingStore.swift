import Foundation
import VaultKit
import OSLog

/// On-disk CRUD for screen recordings, mirroring `QuickNoteStore`. One folder
/// per recording at `<storageDir>/ScreenRecordings/<slug>/`.
struct ScreenRecordingStore {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ScreenRecordingStore")
    static let schemaVersion = 1

    var root: URL {
        AppSettings.shared.storageDir.appendingPathComponent(MeetingStore.screenRecordingsFolder, isDirectory: true)
    }

    func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(for rec: ScreenRecording) -> URL {
        root.appendingPathComponent(rec.slug, isDirectory: true)
    }

    func writeRecording(_ rec: ScreenRecording) throws {
        try ensureRoot()
        let dir = directory(for: rec)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let envelope = SchemaEnvelope(version: Self.schemaVersion, data: rec)
        let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
        try data.write(to: dir.appendingPathComponent("recording.json"))
    }

    /// The screen-capture container (video + system audio, mic muxed when possible).
    func videoURL(for rec: ScreenRecording) -> URL {
        directory(for: rec).appendingPathComponent("recording.mov")
    }

    /// Sidecar mic track, only present when mic muxing fell back.
    func micSidecarURL(for rec: ScreenRecording) -> URL {
        directory(for: rec).appendingPathComponent("mic.m4a")
    }

    func thumbnailURL(for rec: ScreenRecording) -> URL {
        directory(for: rec).appendingPathComponent("thumbnail.png")
    }

    /// Where sampled frames (Phase 2 OCR / vision) are written.
    func framesDir(for rec: ScreenRecording) -> URL {
        directory(for: rec).appendingPathComponent("frames", isDirectory: true)
    }

    /// All audio tracks to feed the transcriber / overlay player: the mov plus
    /// the mic sidecar if the recording used one.
    func audioSources(for rec: ScreenRecording) -> [URL] {
        var urls = [videoURL(for: rec)]
        if rec.hasMic && rec.micIsSidecar {
            let mic = micSidecarURL(for: rec)
            if FileManager.default.fileExists(atPath: mic.path) { urls.append(mic) }
        }
        return urls
    }

    func writeTranscript(_ text: String, for rec: ScreenRecording) throws {
        try text.write(to: directory(for: rec).appendingPathComponent("transcript.md"),
                       atomically: true, encoding: .utf8)
    }

    func readTranscript(for rec: ScreenRecording) -> String {
        let url = directory(for: rec).appendingPathComponent("transcript.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func writeSummary(_ text: String, for rec: ScreenRecording) throws {
        try text.write(to: directory(for: rec).appendingPathComponent("summary.md"),
                       atomically: true, encoding: .utf8)
    }

    func readSummary(for rec: ScreenRecording) -> String {
        let url = directory(for: rec).appendingPathComponent("summary.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func deleteRecording(_ rec: ScreenRecording) {
        try? FileManager.default.removeItem(at: directory(for: rec))
    }

    func listRecordings(limit: Int = 500) -> [ScreenRecording] {
        try? ensureRoot()
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: root,
                                                    includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        var recs: [ScreenRecording] = []
        for dir in contents {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let url = dir.appendingPathComponent("recording.json")
            guard let data = try? Data(contentsOf: url) else { continue }
            if let r: ScreenRecording = try? SchemaEnvelope.decode(
                ScreenRecording.self, from: data,
                currentVersion: Self.schemaVersion,
                decoder: SharedCoders.decoder()
            ) {
                recs.append(r)
            }
        }
        return recs.sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }
}
