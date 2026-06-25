import Foundation

extension OllamaService {
    /// Summarize a screen recording from its audio transcript plus the
    /// on-screen text recovered by Vision OCR. Returns Markdown in the same
    /// four-section shape meetings use, so `ActionItemExtractor` can parse the
    /// `## Action Items` section unchanged. Fully local (goes through
    /// `generate`, which is EgressPolicy-guarded to 127.0.0.1).
    func analyzeScreenRecording(transcript: String, onScreenText: String) async throws -> String {
        let spokenBlock = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(no spoken narration was captured)"
            : transcript
        let screenBlock = onScreenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(no readable on-screen text was detected)"
            : onScreenText

        let prompt = """
        You are analyzing a SCREEN RECORDING. You are given two sources:
        (1) the spoken narration transcript, and (2) the distinct text that
        appeared ON SCREEN during the recording (recovered via OCR — it may be
        unordered and noisy). Use both to understand what the person was doing.

        Write the summary as Markdown with EXACTLY these four sections and nothing else:

        ## What Happened
        A concise, chronological account of what was shown and done on screen
        (apps, documents, code, websites, steps taken). Ground it in the on-screen
        text and narration; do not invent specifics.

        ## Key Points
        The most important takeaways, findings, or decisions.

        ## Action Items
        - [ ] <owner> — <action> (due: <date or "unspecified">)
        Use "Me" as the owner unless another person is clearly named. Only include
        items that are real follow-ups. If there are none, write: None.

        ## Open Questions
        Anything unresolved or unclear. If none, write: None.

        SPOKEN NARRATION:
        \(spokenBlock)

        ON-SCREEN TEXT:
        \(screenBlock)
        """
        return try await generate(prompt: prompt, temperature: 0.2, numCtx: 8192)
    }
}
