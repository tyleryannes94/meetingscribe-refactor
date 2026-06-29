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

    enum Version { case raw, polished, prompt }

    /// Where the transcript for the *current* capture will land once it's
    /// transcribed. Drives the floating overlay's destination line so a private
    /// mid-meeting thought can't silently paste into a shared chat.
    enum Destination: Equatable {
        /// Auto-paste is on — the transcript types into the named frontmost app.
        case paste(appName: String)
        /// Save-only — the transcript is kept as a note and pasted nowhere.
        case saveOnly
    }

    /// Tracks the most recent dictation so the swap / prompt hotkeys can
    /// replace the inserted text in place.
    private struct LastDictation {
        let raw: String
        var polished: String?
        /// TCREI-structured AI prompt, generated lazily on first use of the
        /// prompt hotkey (it's optional, so we don't compute it eagerly).
        var promptStructured: String?
        var shown: Version
        /// The exact string currently sitting in the target field — used to
        /// compute how many backspaces the swap needs.
        var insertedText: String
        let note: QuickNote
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastInsertedText: String?
    /// Destination for the in-progress capture. Set the moment recording starts
    /// (see `start()`), read by the floating overlay's recording pill.
    @Published private(set) var destination: Destination = .saveOnly

    /// True when the current capture was forced save-only (Shift held at start),
    /// regardless of the persistent `dictationAutoPaste` default. Threaded into
    /// `finish()` so the paste step is skipped for exactly this capture.
    private var forcedSaveOnly = false

    /// True when recording began while an "always-polished" in-app field (the
    /// Brain Dump composer or a Tasks quick-add input) was focused. Captured at
    /// `start()` so the intent is locked even if focus flickers during the async
    /// transcription, and read in `finish()` to force the polished version.
    private var forcePolishedCapture = false

    private let recorder = MicOnlyRecorder()
    private let transcriber = QuickTranscribe()
    private let polisher = TranscriptPolisher()
    private let promptRewriter = PromptRewriter()
    private let store = QuickNoteStore()
    private var pendingNote: QuickNote?

    private var last: LastDictation?
    /// In-flight polish for the most recent dictation. `await`-ed by both the
    /// polished-paste path and the swap hotkey.
    private var polishTask: Task<String?, Never>?
    /// In-flight prompt rewrite for the most recent dictation. Started lazily
    /// the first time the prompt hotkey fires for a given dictation.
    private var promptTask: Task<String?, Never>?

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
            case .raw, .prompt:
                // `target` is only ever .raw or .polished (computed above);
                // .prompt is unreachable here but kept for exhaustiveness.
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

    /// Replace the just-dictated text with a TCREI-structured AI prompt,
    /// generated from the RAW transcript. Optional, on-demand sibling of
    /// `swapVersion()` driven by its own hotkey. The prompt is computed lazily
    /// (and cached) so we don't pay an Ollama round-trip on every dictation.
    /// A later `swapVersion()` flips back to raw/polished. No-op if there's
    /// nothing to rewrite or auto-paste was off.
    func rewriteAsPrompt() {
        guard AppSettings.shared.dictationAutoPaste, let st = last else {
            NSSound.beep(); return
        }
        // Already showing the prompt version — nothing to do.
        if st.shown == .prompt { return }
        Task { @MainActor in
            let newText: String
            if let p = st.promptStructured, !p.isEmpty {
                newText = p
            } else {
                // Kick off (or reuse) the rewrite and await it. If it never
                // resolves (Ollama down / empty), beep + bail without changing
                // the inserted text.
                if promptTask == nil {
                    let raw = st.raw
                    let note = st.note
                    promptTask = Task { [promptRewriter, store] in
                        do {
                            let rewritten = try await promptRewriter.rewrite(raw)
                            try? store.writePrompt(rewritten, for: note)
                            return rewritten
                        } catch {
                            AppLog.error("Dictation", "Prompt rewrite failed", error: error,
                                         ["note": note.id])
                            return nil
                        }
                    }
                }
                if let p = await promptTask?.value, !p.isEmpty {
                    newText = p
                } else {
                    log.error("Prompt rewrite failed — no structured prompt available")
                    AppLog.warn("Dictation", "Prompt rewrite unavailable (Ollama down?)")
                    NSSound.beep()
                    return
                }
            }
            // The dictation may have changed while we awaited; re-read `last`.
            guard var cur = last, cur.note.id == st.note.id else { return }
            cur.promptStructured = newText
            guard newText != cur.insertedText else { last = cur; return }
            let deleteCount = cur.insertedText.count
            cur.shown = .prompt
            cur.insertedText = newText
            last = cur
            lastInsertedText = newText
            TextInserter.replaceLastInserted(deleteCount: deleteCount, with: newText)
        }
    }

    private func start() {
        // Resolve the destination for THIS capture up front so the overlay pill
        // can show it the instant recording begins. Holding Shift forces a
        // save-only capture even when auto-paste is the persistent default.
        forcedSaveOnly = NSEvent.modifierFlags.contains(.shift)
        // Lock in whether the focused field always wants polished text (Brain
        // Dump / Tasks input), captured now while that field is still focused.
        forcePolishedCapture = DictationFieldContext.shared.preferPolished
        if AppSettings.shared.dictationAutoPaste && !forcedSaveOnly {
            let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "the active app"
            destination = .paste(appName: app)
        } else {
            destination = .saveOnly
        }

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

        // New dictation → drop any prompt rewrite cached for the previous one.
        promptTask = nil

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

        // Use the polished version when the global default asks for it OR when
        // this capture targeted an always-polished field (Brain Dump / Tasks
        // input) — those feed the local planner/extractor, which does less work
        // on already-cleaned text.
        let usePolished = AppSettings.shared.dictationUsePolished || forcePolishedCapture
        // The persistent default, overridden to false when this one capture was
        // forced save-only (Shift held at start).
        let autoPaste = AppSettings.shared.dictationAutoPaste && !forcedSaveOnly

        guard autoPaste else {
            if forcedSaveOnly {
                // Per-capture save-only override: nothing was pasted, so a later
                // swap/prompt hotkey must NOT touch the focused app. Clearing
                // `last` makes those hotkeys no-op (beep) for this capture.
                last = nil
            } else {
                // Persistent "don't paste" mode — still record raw so a swap
                // works if the user manually placed the cursor (rare).
                last = LastDictation(raw: rawText, polished: nil, promptStructured: nil,
                                     shown: .raw, insertedText: rawText, note: finalized)
            }
            state = .idle
            return
        }

        if usePolished {
            // Wait for polish, then paste it (fall back to raw if it fails).
            let polished = await polishTask?.value ?? nil
            let toPaste = (polished?.isEmpty == false) ? polished! : rawText
            last = LastDictation(raw: rawText, polished: polished, promptStructured: nil,
                                 shown: (toPaste == polished) ? .polished : .raw,
                                 insertedText: toPaste, note: finalized)
            lastInsertedText = toPaste
            state = .idle
            TextInserter.insertAtCursor(toPaste)
        } else {
            // Paste raw immediately (instant). Swap can fetch polished later.
            last = LastDictation(raw: rawText, polished: nil, promptStructured: nil,
                                 shown: .raw, insertedText: rawText, note: finalized)
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
