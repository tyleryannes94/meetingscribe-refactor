import SwiftUI
import Combine

/// First-run readiness for the local AI stack (D3-1). A non-technical user who
/// installed the GUI without running the CLI bootstrap used to hit a raw shell
/// command ("run `brew services start ollama`") the first time a summary ran.
/// This object checks the two things recording needs — the whisper model and a
/// reachable Ollama — and drives the in-app `SetupCheckSheet` so remediation is
/// one tap, never a Terminal.
@available(macOS 14.0, *)
@MainActor
final class SetupReadiness: ObservableObject {
    enum Step: String { case checking, downloadingModel, startingOllama }

    @Published var whisperReady = false
    @Published var ollamaInstalled = false
    @Published var ollamaRunning = false
    @Published var busy: Step?
    @Published var lastError: String?

    private let ollama = OllamaService()

    /// Everything recording + summarizing needs is in place.
    var isReady: Bool { whisperReady && ollamaRunning }

    /// Re-probe all components. Cheap; safe to call on appear and after actions.
    func refresh() async {
        whisperReady = WhisperRunner.isModelReady
        ollamaInstalled = OllamaService.binaryPath != nil
        ollamaRunning = await ollama.isReachable(allowCache: false)
    }

    /// Download the whisper model (~140 MB) to the default path, verified by
    /// checksum. Progress is indeterminate (the underlying URLSession download
    /// reports completion, not a running fraction).
    func downloadModel() async {
        guard busy == nil else { return }
        busy = .downloadingModel
        lastError = nil
        let ok = await WhisperRunner.ensureDefaultModelDownloaded()
        whisperReady = WhisperRunner.isModelReady
        if !ok && !whisperReady {
            lastError = "Couldn't download the transcription model. Check your network and try again."
        }
        busy = nil
    }

    /// Start the local Ollama server if it's installed. Surfaces a friendly
    /// message (with the download link handled by the sheet) when it isn't.
    func startOllama() async {
        guard busy == nil else { return }
        busy = .startingOllama
        lastError = nil
        if OllamaService.binaryPath == nil {
            ollamaInstalled = false
            lastError = "Ollama isn't installed yet."
            busy = nil
            return
        }
        let up = await ollama.ensureRunning(timeout: 12)
        ollamaInstalled = true
        ollamaRunning = up
        if !up {
            lastError = "Ollama is installed but didn't start. Try again, or open Ollama from Applications once."
        }
        busy = nil
    }
}
