import Foundation
import OSLog

/// Rewrites a raw voice-note / dictation transcript into a well-structured
/// AI prompt, following Google's TCREI prompt-engineering framework
/// (Task, Context, References, Evaluate, Iterate — "The Cool Robot Eats
/// Ice Cream"). This is a SEPARATE output from the "polished" transcript:
/// polishing cleans speech into readable prose, whereas this reshapes a
/// spoken request into a structured prompt you can paste into an AI.
///
/// Like the polisher, it runs entirely on-device through the local Ollama
/// instance. The raw transcript is always preserved separately, and the
/// rewrite is OPTIONAL — it only runs when the user asks for it (the prompt
/// hotkey, or the "Generate" button in the voice-note detail).
///
/// The five TCREI pillars the rewrite must hit:
///   1. 🎯 Task        — the specific action, an assigned persona, output format
///   2. 🌐 Context     — background, constraints, target audience
///   3. 📚 References   — examples / style guidelines (few-shot)
///   4. 🔍 Evaluate     — how to check the result against the goal
///   5. 🔁 Iterate      — how to refine after the first pass
final class PromptRewriter {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "PromptRewriter")
    private let ollama = OllamaService()

    /// Returns a TCREI-structured prompt built from the raw transcript.
    /// Throws if Ollama can't be reached after auto-start. Returns empty
    /// string on empty input.
    func rewrite(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let prompt = Self.prompt(raw: trimmed)
        // Slightly higher temperature than polish — we want the model to
        // organize and lightly infer structure, not transcribe verbatim.
        let out = try await ollama.generate(prompt: prompt, temperature: 0.3)
        return Self.stripCodeFences(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prompt(raw: String) -> String {
        return """
        You are a prompt engineer. The user spoke a request out loud and a
        speech-to-text engine produced the RAW TRANSCRIPT below. Rewrite their
        request into a single, well-structured AI prompt using Google's TCREI
        framework (Task, Context, References, Evaluate, Iterate).

        Produce the prompt using EXACTLY these five Markdown headers, in order:

        ## Task
        State the specific action the AI should perform. Assign a relevant
        expert persona ("Act as a …") and name the desired output format
        (length, structure, medium). One or two sentences.

        ## Context
        Capture the background, constraints, and target audience that the user
        actually described — why they want this and who it is for. Do NOT invent
        facts; only use what the transcript implies. If the user gave no
        audience or constraints, write a short bracketed placeholder such as
        "[Add target audience]" instead of guessing.

        ## References
        List any examples, style guidelines, or sources the user mentioned as
        bullet points (few-shot grounding). If none were given, add 1–2
        bracketed placeholders like "[Paste an example of the style you want]".

        ## Evaluate
        Give 2–4 concrete, checkable criteria the output must satisfy, derived
        from the user's request (e.g. honored the format, correct length, right
        tone, no hallucinated facts).

        ## Iterate
        Suggest one or two specific follow-up refinements the user could ask for
        after the first draft, phrased as instructions to the AI.

        RULES:
        - Preserve the user's real intent. Do NOT add requirements they never
          expressed; use bracketed placeholders for anything missing.
        - Strip filler words and verbal hesitations from the spoken request.
        - The output IS the finished prompt — write it so it can be pasted
          directly into an AI assistant.
        - Output ONLY the structured prompt. No preamble like "Here is your
          prompt:", no commentary, no code fences.

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
