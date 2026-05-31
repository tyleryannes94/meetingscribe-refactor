import Foundation
import OSLog

/// One person the LLM pulled out of a transcript (audit §8.1).
struct ExtractedPerson: Codable, Hashable {
    let name: String
    var aliases: [String]
    /// "speaker" | "attendee" | "third_party"
    var primaryContext: String
    var oneLineSummary: String
    var confidence: Double

    private enum CodingKeys: String, CodingKey {
        case name, aliases
        case primaryContext = "primary_context"
        case oneLineSummary = "one_line_summary"
        case confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
        primaryContext = (try? c.decode(String.self, forKey: .primaryContext)) ?? ""
        oneLineSummary = (try? c.decode(String.self, forKey: .oneLineSummary)) ?? ""
        // The model sometimes emits confidence as a string ("0.9").
        if let d = try? c.decode(Double.self, forKey: .confidence) {
            confidence = d
        } else if let s = try? c.decode(String.self, forKey: .confidence), let d = Double(s) {
            confidence = d
        } else {
            confidence = 0.7
        }
    }
}

/// Runs the post-summary Ollama pass that lists every person mentioned in a
/// transcript. Local-only (Ollama), no network egress — preserves the app's
/// privacy guarantee (audit §9).
enum PersonExtractor {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "PersonExtractor")

    /// Transcripts can be long; keep the prompt within the model's context
    /// window. ~14k chars ≈ comfortably under num_ctx 8192 tokens with the
    /// instruction overhead.
    private static let maxTranscriptChars = 14_000

    static func extract(from transcript: String,
                        meeting: Meeting,
                        using ollama: OllamaService) async -> [ExtractedPerson] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 40 else { return [] }
        let clipped = String(trimmed.prefix(maxTranscriptChars))

        let prompt = buildPrompt(transcript: clipped, meeting: meeting)
        let raw: String
        do {
            raw = try await ollama.generate(prompt: prompt, temperature: 0.1, numCtx: 8192)
        } catch {
            log.error("Person extraction LLM call failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return parse(raw)
    }

    private static func buildPrompt(transcript: String, meeting: Meeting) -> String {
        """
        You are reading a meeting transcript. List every person mentioned by name
        (not by role like "the customer" unless that's the only reference).
        For each, output an object with keys: name (string), aliases (array of
        strings, may be empty), primary_context (one of "speaker", "attendee",
        "third_party"), one_line_summary (string), confidence (number 0-1 that
        this is a real, distinct person).

        Rules:
        - If a person is referred to only as "I" or "me", that's the user — SKIP them.
        - The user's name is Tyler — SKIP Tyler / "Me".
        - Do NOT invent people. Only include names actually present.
        - Do NOT include company names, product names, or places as people.
        - Output ONLY a JSON array. No prose, no markdown fences.

        Example output:
        [{"name":"Jane Smith","aliases":["Jane"],"primary_context":"attendee","one_line_summary":"Raised the pricing concern.","confidence":0.9}]

        TRANSCRIPT (speaker labels: "Me" is the user Tyler, "Them" is everyone else):

        \(transcript)
        """
    }

    /// Tolerant JSON-array parse: strips ``` fences and slices to the outermost
    /// [ … ] so a chatty model that adds a sentence still parses.
    static func parse(_ raw: String) -> [ExtractedPerson] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = s.firstIndex(of: "["),
              let end = s.lastIndex(of: "]"),
              start < end else { return [] }
        let json = String(s[start...end])
        guard let data = json.data(using: .utf8),
              let people = try? JSONDecoder().decode([ExtractedPerson].self, from: data) else {
            log.error("Person extraction produced unparseable JSON")
            return []
        }
        // Drop empties and obvious self-references (profile-driven, U1-2).
        let selfAliases = AppSettings.shared.myNameAliases
        return people.filter { p in
            let n = p.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !n.isEmpty && !selfAliases.contains(n)
        }
    }
}
