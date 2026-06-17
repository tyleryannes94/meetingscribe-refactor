import Foundation
import AVFoundation
import OSLog

/// Owns everything voice-note related: live recording state, per-note
/// transcription / polishing progress, per-note error strings, import flow.
///
/// Extracted from `MeetingManager` in Batch 6 (audit 5.1). Views that only
/// care about quick notes now observe this object directly — they no longer
/// re-render when meeting recording, calendar refresh, or action-item
/// backfill state changes on the manager.
///
/// Depends on `OllamaService` (already shared via the manager) for the
/// auto-polish pass. Audio capture goes through `MicOnlyRecorder`.
@available(macOS 14.0, *)
@MainActor
final class QuickNotesController: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "QuickNotes")

    enum RecordState: Equatable {
        case idle, recording(startedAt: Date), transcribing, error(String)
    }

    @Published private(set) var state: RecordState = .idle
    @Published private(set) var notes: [QuickNote] = []
    /// IDs of quick notes currently being transcribed.
    @Published private(set) var transcribing: Set<String> = []
    /// IDs of quick notes currently being polished.
    @Published private(set) var polishing: Set<String> = []
    /// IDs of quick notes currently being rewritten into a TCREI AI prompt.
    @Published private(set) var structuringPrompt: Set<String> = []
    /// Per-note error string for the detail view to surface failures inline.
    @Published private(set) var errors: [String: String] = [:]

    private let store = QuickNoteStore()
    private let recorder = MicOnlyRecorder()
    private let transcriber = QuickTranscribe()
    private let polisher = TranscriptPolisher()
    private let promptRewriter = PromptRewriter()
    private var pendingNote: QuickNote?

    /// 3-D: injected so a finished voice note can auto-extract action items into
    /// the task store, the same way meetings do. Optional so the controller can
    /// still be built without it (extraction is then skipped).
    private let actionItems: ActionItemStore?
    private let ollama = OllamaService()

    init(actionItemStore: ActionItemStore? = nil) {
        self.actionItems = actionItemStore
    }

    /// Hook called after a new dictation note finishes transcribing. Lets
    /// MeetingScribeApp / FloatingOverlay reuse the same dictation pipeline.
    var onDictationNoteFinalized: ((QuickNote) -> Void)?

    /// Called on the main queue with the latest normalized mic level while
    /// recording is active. Forwarded to `MicOnlyRecorder.onLevel`. Set by
    /// the owner (MeetingManager) to push levels into RecordingMonitor.
    var onLevelUpdate: ((Float) -> Void)? {
        get { recorder.onLevel }
        set { recorder.onLevel = newValue }
    }

    func refresh() {
        notes = store.listNotes()
    }

    // MARK: - Recording lifecycle

    func startRecording() async {
        if case .recording = state { return }
        let now = Date()
        let note = QuickNote(id: UUID().uuidString,
                             title: "Voice Note \(Self.shortTime.string(from: now))",
                             createdAt: now,
                             durationSeconds: 0,
                             snippet: "",
                             wasDictation: false)
        do {
            try store.writeNote(note)
            try recorder.start(outputURL: store.audioURL(for: note))
            pendingNote = note
            state = .recording(startedAt: now)
            refresh()
        } catch {
            log.error("startQuickNote failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "quick-note-start"])
            state = .error(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard case .recording = state, var note = pendingNote else { return }
        let (url, duration) = recorder.stop()
        note.durationSeconds = duration
        pendingNote = nil
        state = .transcribing
        try? store.writeNote(note)
        refresh()

        guard let url else { state = .idle; return }
        await transcribe(note, audioURL: url)
        state = .idle
    }

    func normalizedAudioLevel() -> Float { recorder.normalizedLevel() }

    // MARK: - Import

    @discardableResult
    func importVoiceNote(from url: URL) async -> String? {
        let now = Date()
        let base = url.deletingPathExtension().lastPathComponent
        let note = QuickNote(id: UUID().uuidString,
                             title: base.isEmpty ? "Imported Note \(Self.shortTime.string(from: now))" : base,
                             createdAt: now,
                             durationSeconds: 0,
                             snippet: "",
                             wasDictation: false)
        do {
            try store.writeNote(note)
            let dest = try store.importAudio(from: url, for: note)
            var finalized = note
            finalized.durationSeconds = Self.audioDuration(at: dest)
            try? store.writeNote(finalized)
            refresh()
            AppLog.info("VoiceNote", "Imported audio",
                        ["note": note.id, "source": url.lastPathComponent])
            await transcribe(finalized, audioURL: dest)
            return note.id
        } catch {
            log.error("importVoiceNote failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "quick-note-import", "source": url.path])
            state = .error("Import failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Re-transcribe / re-polish

    func reTranscribe(_ note: QuickNote) {
        guard let url = store.existingAudioURL(for: note) else {
            setError(note.id, "Audio file not found. The recording may not have been written.")
            return
        }
        setError(note.id, nil)
        Task { await transcribe(note, audioURL: url) }
    }

    func rePolish(_ note: QuickNote) {
        let raw = store.readTranscript(for: note)
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setError(note.id, "No raw transcript to polish. Run Transcribe first.")
            return
        }
        setError(note.id, nil)
        Task { await polishInBackground(note, raw: raw) }
    }

    /// Generate (or regenerate) the TCREI-structured AI prompt for a note from
    /// its raw transcript. Optional and on-demand — unlike polish it does NOT
    /// run automatically after transcription.
    func generatePrompt(_ note: QuickNote) {
        let raw = store.readTranscript(for: note)
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setError(note.id, "No raw transcript to rewrite. Run Transcribe first.")
            return
        }
        setError(note.id, nil)
        Task { await rewritePromptInBackground(note, raw: raw) }
    }

    private func rewritePromptInBackground(_ note: QuickNote, raw: String) async {
        structuringPrompt.insert(note.id)
        defer {
            structuringPrompt.remove(note.id)
            refresh()
        }
        do {
            let prompt = try await promptRewriter.rewrite(raw)
            try? store.writePrompt(prompt, for: note)
        } catch {
            log.error("prompt rewrite failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .integration,
                                        context: ["service": "ollama", "phase": "prompt", "note": note.id])
            setError(note.id, "AI-prompt rewrite failed: \(error.localizedDescription). The raw transcript is still saved.")
        }
    }

    private func transcribe(_ note: QuickNote, audioURL: URL) async {
        setError(note.id, nil)
        transcribing.insert(note.id)

        let result: (text: String, error: String?) = await Task.detached(priority: .userInitiated) { [transcriber] in
            do {
                let t = try await transcriber.transcribe(audioURL: audioURL)
                return (t, nil)
            } catch {
                return ("", error.localizedDescription)
            }
        }.value

        var finalized = note
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        finalized.snippet = String(trimmed.prefix(150))
        try? store.writeNote(finalized)
        try? store.writeTranscript(result.text, for: finalized)
        transcribing.remove(note.id)
        refresh()
        if let err = result.error {
            log.error("transcribe failed: \(err, privacy: .public)")
            AppLog.error("VoiceNote", "Transcription failed",
                         ["note": note.id, "audio": audioURL.path, "detail": err])
            setError(note.id, "Transcription failed: \(err)")
            return
        }
        if trimmed.isEmpty {
            AppLog.warn("VoiceNote", "Transcription returned empty text",
                        ["note": note.id, "audio": audioURL.path])
            setError(note.id, "Transcription returned no text. Audio may be silent, or the whisper model is missing.")
            return
        }
        AppLog.info("VoiceNote", "Transcribed",
                    ["note": note.id, "chars": "\(trimmed.count)"])
        await polishInBackground(finalized, raw: result.text)
    }

    private func polishInBackground(_ note: QuickNote, raw: String) async {
        polishing.insert(note.id)
        defer {
            polishing.remove(note.id)
            refresh()
        }
        do {
            let polished = try await polisher.polish(raw)
            try? store.writePolished(polished, for: note)
            await autoExtractActionItems(from: polished, note: note)
        } catch {
            log.error("polish failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .integration,
                                        context: ["service": "ollama", "phase": "polish", "note": note.id])
            setError(note.id, "Polishing failed: \(error.localizedDescription). The raw transcript is still saved.")
        }
    }

    /// 3-D: best-effort auto-extraction of action items from a finished voice
    /// note into the task store (same parser meetings use). Never blocks the
    /// note or surfaces an error to the user — the transcript is already saved.
    private func autoExtractActionItems(from polished: String, note: QuickNote) async {
        guard let store = actionItems else { return }
        do {
            let md = try await ollama.extractActionItems(from: polished)
            var items = ActionItemExtractor.extract(from: md, sourceID: note.id,
                                                     sourceTitle: note.title, sourceDate: note.createdAt)
            guard !items.isEmpty else { return }
            let known = PeopleStore.shared.people
            for i in items.indices {
                items[i].source = "voice_note"
                if items[i].ownerPersonID == nil {
                    items[i].ownerPersonID = PersonResolver.resolveOwner(items[i].owner, in: known)
                }
            }
            store.reconcileExtracted(items, for: note.id)
            AppLog.info("VoiceNote", "Auto-extracted action items",
                        ["note": note.id, "items": "\(items.count)"])
        } catch {
            log.error("voice-note action extraction failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Hook the global dictation pipeline so transcribed dictation notes
    /// flow through the same auto-polish path quick notes use.
    func handleDictationNote(_ note: QuickNote) {
        refresh()
        let raw = store.readTranscript(for: note)
        if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await polishInBackground(note, raw: raw) }
        }
        onDictationNoteFinalized?(note)
    }

    // MARK: - Persisted text reads + edits

    func readTranscript(_ note: QuickNote) -> String { store.readTranscript(for: note) }
    func readPolished(_ note: QuickNote) -> String { store.readPolished(for: note) }
    func readPrompt(_ note: QuickNote) -> String { store.readPrompt(for: note) }

    func saveTranscript(_ text: String, for note: QuickNote) {
        try? store.writeTranscript(text, for: note)
        var updated = note
        updated.snippet = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
        try? store.writeNote(updated)
        refresh()
        // Index into vault FTS so GlobalSearch can find this voice note.
        PeopleStore.shared.indexVoiceNote(id: note.id,
                                          title: note.title,
                                          transcript: text.isEmpty ? nil : text,
                                          createdAt: note.createdAt)
    }

    func savePolished(_ text: String, for note: QuickNote) {
        try? store.writePolished(text, for: note)
    }

    func savePrompt(_ text: String, for note: QuickNote) {
        try? store.writePrompt(text, for: note)
    }

    func delete(_ note: QuickNote) {
        store.deleteNote(note)
        refresh()
    }

    func audioURL(_ note: QuickNote) -> URL {
        store.existingAudioURL(for: note) ?? store.audioURL(for: note)
    }

    // MARK: - Per-note state queries

    func isTranscribing(_ note: QuickNote) -> Bool { transcribing.contains(note.id) }
    func isPolishing(_ note: QuickNote) -> Bool { polishing.contains(note.id) }
    func isStructuringPrompt(_ note: QuickNote) -> Bool { structuringPrompt.contains(note.id) }
    func error(for note: QuickNote) -> String? { errors[note.id] }

    private func setError(_ id: String, _ err: String?) {
        if let err { errors[id] = err }
        else { errors.removeValue(forKey: id) }
    }

    private static func audioDuration(at url: URL) -> Double {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    private static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d h:mm a"
        return f
    }()
}
