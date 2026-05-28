import Foundation
import OSLog

/// Polishes a raw whisper transcript into a "natural" version, matching
/// Whispr-Flow-style editing rules. Runs entirely on the user's machine
/// via the local Ollama instance. The raw transcript is preserved
/// separately so the user always has the unedited source.
///
/// Polish rules (all applied by the LLM in one pass):
///   • Strip filler words (um, uh, like, you know, I mean, sort of, kinda)
///   • Honor spoken retractions ("scratch that", "actually, no", "I mean…")
///     by REMOVING the retracted span, not annotating it
///   • Apply voice commands inline:
///       "new line"          → \n
///       "new paragraph"     → blank line
///       "comma"/"period"    → punctuation
///       "open quote"/"close quote", "question mark", "exclamation point"
///   • Detect list intent and format:
///       "first… second… third…" → ordered list
///       "next… also… and…"      → bullet list
///       explicit "bullet point" / "make a list" → bullets
///   • Add normal punctuation + capitalization
///   • Preserve meaning — no hallucinated content
final class TranscriptPolisher {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Polisher")
    private let ollama = OllamaService()

    /// Returns a polished version of the raw transcript. Throws if Ollama
    /// can't be reached after auto-start. Returns empty string on empty input.
    func polish(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let prompt = Self.prompt(raw: trimmed)
        let out = try await ollama.generate(prompt: prompt, temperature: 0.15)
        return Self.stripCodeFences(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prompt(raw: String) -> String {
        return """
        You are a transcript polisher. The user spoke into a microphone and a
        speech-to-text engine produced the RAW transcript below. Rewrite it so
        it reads as natural written English, applying the rules below.

        RULES — apply them all, in order:

        1. Remove filler words and verbal hesitations: "um", "uh", "er",
           "hmm", "uhh", "you know" (when filler), "like" (when filler),
           "I mean" (when filler), "sort of", "kinda" (when filler), "right?"
           (when trailing tag), "okay" (when trailing tag).

        2. Honor spoken retractions by DELETING what was retracted, not
           annotating it. Common cues:
             - "scratch that" / "ignore that" → delete the most recent sentence
             - "actually, no…" / "wait, no…" → reconsider the preceding clause
             - "I mean…" → replace the previous phrase with what follows
             - "delete that" → remove the preceding phrase
           The polished output must read as if the retracted part was never said.

        3. Apply voice-dictation commands inline:
             - "new line" → line break
             - "new paragraph" → blank line + new paragraph
             - "comma" → ", "
             - "period" / "full stop" → ". "
             - "question mark" → "? "
             - "exclamation point" → "! "
             - "open quote" / "close quote" → " or "
             - "colon" → ": "
             - "dash" / "hyphen" → "-"

        4. Detect list intent and format as a real list:
             - Speaker says "first… second… third…" → numbered list
             - Speaker says explicitly "bullet point X" or "make a list" →
               bullet list (use "- ")
             - Speaker enumerates with "next", "and also", "another thing" →
               bullet list

        5. Add normal punctuation and capitalize sentence starts and proper
           nouns. Break run-on sentences when meaning shifts.

        6. Preserve meaning. Do NOT add new information. Do NOT explain
           your edits. Do NOT include any preamble like "Here is the
           polished version:".

        7. If the speech is clearly a draft email or message, preserve a
           greeting / sign-off shape if one is present, but otherwise don't
           invent structure.

        Output ONLY the polished text. No commentary, no code fences.

        RAW TRANSCRIPT:
        \(raw)
        """
    }

    private static func stripCodeFences(_ s: String) -> String {
        var text = s
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
