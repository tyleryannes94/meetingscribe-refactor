import Foundation
import OSLog
import AppKit

/// Whispr-Flow-style dictation flow:
///   1. User presses the global hotkey → start recording.
///   2. User presses the hotkey again → stop, transcribe, paste at cursor.
///
/// Which version gets pasted (raw whisper output or the cleaned-up "polished"
/// version) is controlled by `AppSettings.dictationUsePolished`. Either way we
/// polish in the background so the *swap* hotkey can instantly toggle the
/// just-inserted text to the other version.
///
/// The recording is also persisted as a QuickNote (transcript + polished +
/// audio) so the user can find what they dictated later.
@MainActor
final class QuickDictation: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "QuickDictation")

    enum State: Equatable {
        case idle
        case recording(startedAt: Date)
        case transcribing
        case error(String)
    }

    enum Version { case raw, polished }

    /// Tracks the most recent dictation so the swap hotkey can replace the
    /// inserted text in place.
    private struct LastDictation {
        let raw: String
        var polished: String?
        var shown: Version
        /// The exact string currently sitting in the target field — used to
        /// compute how many backspaces the swap needs.
        var insertedText: String
        let note: QuickNote
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastInsertedText: String?

    private let recorder = MicOnlyRecorder()
    private let transcriber = QuickTranscribe()
    private let polisher = TranscriptPolisher()
    private let store = QuickNoteStore()
    private var pendingNote: QuickNote?

    private var last: LastDictation?
    /// In-flight polish for the most recent dictation. `await`-ed by both the
    /// polished-paste path and the swap hotkey.
    private var polishTask: Task<String?, Never>?

    /// Owner sets this so the dictated note appears in the QuickNotes list.
    var onNoteCreated: ((QuickNote) -> Void)?

    /// Called on the main queue with the latest normalized mic level while
    /// recording is active. Forwarded to `MicOnlyRecorder.onLevel`. Set by
    /// the owner (MeetingManager) to push levels into RecordingMonitor.
    var onLevelUpdate: ((Float) -> Void)? {
        get { recorder.onLevel }
        set { recorder.onLevel = newValue }
    }

    /// Toggle: start if idle, stop+transcribe+paste if recording.
    func toggle() {
        switch state {
        case .idle, .error: start()
        case .recording: stopAndProcess()
        case .transcribing: break // ignore — wait for current job to finish
        }
    }

    /// Swap the just-dictated text between raw and polished, replacing it in
    /// the active field in place. No-op if there's nothing to swap or auto-
    /// paste was off.
    func swapVersion() {
        guard AppSettings.shared.dictationAutoPaste, var st = last else {
            NSSound.beep(); return
        }
        let target: Version = (st.shown == .raw) ? .polished : .raw
        Task { @MainActor in
            let newText: String
            switch target {
            case .raw:
                newText = st.raw
            case .polished:
                // Prefer the cached polished text; otherwise await the in-flight
                // polish. If it never resolves (Ollama down), beep + bail.
                if let p = st.polished, !p.isEmpty {
                    newText = p
                } else if let p = await polishTask?.value, !p.isEmpty {
                    st.polished = p
                    newText = p
                } else {
                    log.error("Swap to polished failed — no polished text available")
                    AppLog.warn("Dictation", "Swap to polished unavailable (Ollama down?)")
                    NSSound.beep()
                    return
                }
            }
            guard newText != st.insertedText else { return }
            let deleteCount = st.insertedText.count
            st.shown = target
            st.insertedText = newText
            last = st
            lastInsertedText = newText
            TextInserter.replaceLastInserted(deleteCount: deleteCount, with: newText)
        }
    }

    private func start() {
        let now = Date()
        let note = QuickNote(id: UUID().uuidString,
                             title: "Dictation \(Self.timestampFormatter.string(from: now))",
                             createdAt: now,
                             durationSeconds: 0,
                             snippet: "",
                             wasDictation: true)
        do {
            try store.writeNote(note)
            let audio = store.audioURL(for: note)
            try recorder.start(outputURL: audio)
            pendingNote = note
            state = .recording(startedAt: now)
        } catch {
            log.error("Dictation start failed: \(error.localizedDescription, privacy: .public)")
            AppLog.error("Dictation", "Failed to start", error: error)
            state = .error(error.localizedDescription)
        }
    }

    private func stopAndProcess() {
        let (url, duration) = recorder.stop()
        state = .transcribing
        guard let url, var note = pendingNote else {
            state = .idle
            return
        }
        note.durationSeconds = duration
        pendingNote = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var text = ""
            var failureMessage: String?
            do {
                text = try await self.transcriber.transcribe(audioURL: url)
            } catch {
                failureMessage = error.localizedDescription
                AppLog.error("Dictation", "Transcribe failed", error: error)
            }
            await self.finish(note: note, rawText: text, failure: failureMessage)
        }
    }

    /// Runs on the main actor once transcription returns. Persists the note,
    /// kicks off polish, and pastes the configured version.
    private func finish(note: QuickNote, rawText: String, failure: String?) async {
        var finalized = note
        finalized.snippet = String(rawText.prefix(150))
        try? store.writeNote(finalized)
        try? store.writeTranscript(rawText, for: finalized)
        onNoteCreated?(finalized)

        if let failure {
            state = .error(failure)
            return
        }
        lastInsertedText = rawText

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            AppLog.warn("Dictation", "Transcription returned empty text", ["note": finalized.id])
            return
        }

        // Always polish in the background so the swap hotkey is instant. Also
        // persists polished.md to the note for the QuickNotes UI.
        polishTask = Task { [polisher, store, weak self] in
            do {
                let polished = try await polisher.polish(rawText)
                try? store.writePolished(polished, for: finalized)
                await MainActor.run {
                    self?.onNoteCreated?(finalized)
                    if self?.last?.note.id == finalized.id {
                        self?.last?.polished = polished
                    }
                }
                return polished
            } catch {
                AppLog.error("Dictation", "Polish failed", error: error, ["note": finalized.id])
                return nil
            }
        }

        let usePolished = AppSettings.shared.dictationUsePolished
        let autoPaste = AppSettings.shared.dictationAutoPaste

        guard autoPaste else {
            // No paste — still record raw so a later swap could work if the
            // user manually placed the cursor (rare). Mostly a no-op.
            last = LastDictation(raw: rawText, polished: nil, shown: .raw,
                                 insertedText: rawText, note: finalized)
            state = .idle
            return
        }

        if usePolished {
            // Wait for polish, then paste it (fall back to raw if it fails).
            let polished = await polishTask?.value ?? nil
            let toPaste = (polished?.isEmpty == false) ? polished! : rawText
            last = LastDictation(raw: rawText, polished: polished,
                                 shown: (toPaste == polished) ? .polished : .raw,
                                 insertedText: toPaste, note: finalized)
            lastInsertedText = toPaste
            state = .idle
            TextInserter.insertAtCursor(toPaste)
        } else {
            // Paste raw immediately (instant). Swap can fetch polished later.
            last = LastDictation(raw: rawText, polished: nil, shown: .raw,
                                 insertedText: rawText, note: finalized)
            state = .idle
            TextInserter.insertAtCursor(rawText)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()
}
