import Foundation
import VaultKit
import OSLog

struct QuickNoteStore {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "QuickNoteStore")
    static let noteSchemaVersion = 1

    var root: URL {
        AppSettings.shared.storageDir.appendingPathComponent(MeetingStore.quickNotesFolder, isDirectory: true)
    }

    func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(for note: QuickNote) -> URL {
        root.appendingPathComponent(note.slug, isDirectory: true)
    }

    /// Writes `note.json` via the versioned envelope (audit 2.3). Reads in
    /// `listNotes()` accept both the legacy raw shape and the new envelope.
    func writeNote(_ note: QuickNote) throws {
        try ensureRoot()
        let dir = directory(for: note)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let envelope = SchemaEnvelope(version: Self.noteSchemaVersion, data: note)
        let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
        try data.write(to: dir.appendingPathComponent("note.json"))
    }

    func writeTranscript(_ text: String, for note: QuickNote) throws {
        try text.write(to: directory(for: note).appendingPathComponent("transcript.md"),
                       atomically: true, encoding: .utf8)
    }

    func readTranscript(for note: QuickNote) -> String {
        let url = directory(for: note).appendingPathComponent("transcript.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Polished/clean version produced by TranscriptPolisher (filler removal,
    /// retraction handling, list detection, punctuation). Stored separately
    /// from `transcript.md` so the raw original is always preserved.
    func writePolished(_ text: String, for note: QuickNote) throws {
        try text.write(to: directory(for: note).appendingPathComponent("polished.md"),
                       atomically: true, encoding: .utf8)
    }

    func readPolished(for note: QuickNote) -> String {
        let url = directory(for: note).appendingPathComponent("polished.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Canonical recording path (the mic recorder writes here).
    func audioURL(for note: QuickNote) -> URL {
        directory(for: note).appendingPathComponent("audio.m4a")
    }

    /// Audio file extensions accepted on import (anything afconvert + AVFoundation
    /// can read).
    static let importableExtensions = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac", "mp4", "m4b"]

    /// The actual audio file present for a note — recorded (`audio.m4a`) or
    /// imported (`audio.<ext>`), whatever its extension.
    func existingAudioURL(for note: QuickNote) -> URL? {
        let dir = directory(for: note)
        for ext in (["m4a"] + Self.importableExtensions) {
            let u = dir.appendingPathComponent("audio.\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Copies an imported audio file into the note's folder, preserving its
    /// extension. Returns the destination URL.
    func importAudio(from src: URL, for note: QuickNote) throws -> URL {
        try ensureRoot()
        let dir = directory(for: note)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = src.pathExtension.isEmpty ? "m4a" : src.pathExtension.lowercased()
        let dest = dir.appendingPathComponent("audio.\(ext)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    func deleteNote(_ note: QuickNote) {
        try? FileManager.default.removeItem(at: directory(for: note))
    }

    func listNotes(limit: Int = 500) -> [QuickNote] {
        try? ensureRoot()
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: root,
                                                    includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        var notes: [QuickNote] = []
        for dir in contents {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let url = dir.appendingPathComponent("note.json")
            guard let data = try? Data(contentsOf: url) else { continue }
            // Tolerant of both the legacy raw shape and the new envelope.
            if let n: QuickNote = try? SchemaEnvelope.decode(
                QuickNote.self, from: data,
                currentVersion: Self.noteSchemaVersion,
                decoder: SharedCoders.decoder()
            ) {
                notes.append(n)
            }
        }
        return notes.sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }
}
