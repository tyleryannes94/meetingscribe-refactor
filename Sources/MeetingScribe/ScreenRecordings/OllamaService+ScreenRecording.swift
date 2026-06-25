import Foundation

extension OllamaService {
    /// Multimodal pass (optional, Phase 2+): describe what the user was doing
    /// across a handful of sampled frames using the local vision model. Returns
    /// "" if no frames are provided. Caps the frame count — vision tokens are
    /// expensive and small local models handle only a few images well.
    func describeFrames(_ imageURLs: [URL], maxFrames: Int = 6) async throws -> String {
        let chosen = Self.evenlySpaced(imageURLs, max: maxFrames)
        let b64 = chosen.compactMap { try? Data(contentsOf: $0).base64EncodedString() }
        guard !b64.isEmpty else { return "" }
        let prompt = """
        These images are frames sampled in chronological order from a screen \
        recording. Describe what the user is doing on screen across them: the \
        apps and windows visible, the content (documents, code, websites, \
        dashboards), and any actions or workflow you can infer. Be concrete and \
        specific; 4-8 sentences. Do not guess beyond what is visible.
        """
        return try await generateVision(prompt: prompt, imagesBase64: b64)
    }

    private static func evenlySpaced(_ urls: [URL], max: Int) -> [URL] {
        guard urls.count > max, max > 0 else { return urls }
        let stride = Double(urls.count) / Double(max)
        return (0..<max).map { urls[Int(Double($0) * stride)] }
    }

    /// Summarize a screen recording from its audio transcript plus the
    /// on-screen text recovered by Vision OCR. Returns Markdown in the same
    /// four-section shape meetings use, so `ActionItemExtractor` can parse the
    /// `## Action Items` section unchanged. Fully local (goes through
    /// `generate`, which is EgressPolicy-guarded to 127.0.0.1).
    func analyzeScreenRecording(transcript: String,
                                onScreenText: String,
                                visualDescription: String = "") async throws -> String {
        let spokenBlock = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(no spoken narration was captured)"
            : transcript
        let screenBlock = onScreenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(no readable on-screen text was detected)"
            : onScreenText
        let visualBlock = visualDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let visualSection = visualBlock.isEmpty ? "" : """


        VISUAL ANALYSIS (a vision model's description of sampled frames):
        \(visualBlock)
        """

        let prompt = """
        You are analyzing a SCREEN RECORDING. You are given these sources:
        (1) the spoken narration transcript, (2) the distinct text that appeared
        ON SCREEN (recovered via OCR — may be unordered/noisy), and possibly
        (3) a vision model's description of sampled frames. Use all of them to
        understand what the person was doing.

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
        \(screenBlock)\(visualSection)
        """
        return try await generate(prompt: prompt, temperature: 0.2, numCtx: 8192)
    }
}
