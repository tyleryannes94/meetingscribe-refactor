import Foundation

/// AI-proposed enrichments for a person — tags to apply, relationships to other
/// known people, and encounters worth logging. Produced on-device by Ollama from
/// the person's profile + meeting/message context, parsed tolerantly from JSON
/// (the small local models don't support strict JSON mode), mirroring the
/// PersonExtractor pattern used for transcript people-extraction.
struct PersonAISuggestions: Codable, Equatable {
    var tags: [String] = []
    var relationships: [RelSuggestion] = []
    var encounters: [EncSuggestion] = []

    struct RelSuggestion: Codable, Equatable, Hashable {
        var name: String
        var label: String
    }
    struct EncSuggestion: Codable, Equatable, Hashable {
        var title: String
        var note: String
    }

    var isEmpty: Bool { tags.isEmpty && relationships.isEmpty && encounters.isEmpty }
}

enum PersonSuggestionEngine {
    /// Build the suggestions for a person from a pre-assembled context blob.
    /// Returns nil on model/parse failure so the UI can show a soft error.
    static func generate(personName: String,
                         context: String,
                         using ollama: OllamaService) async -> PersonAISuggestions? {
        let prompt = """
        You are organizing a personal CRM. Using ONLY the context below about \
        \(personName), propose enrichments. Be conservative — only suggest things \
        clearly supported by the context, and never invent people or events.

        Return STRICT JSON with exactly this shape and NOTHING else (no prose, no \
        code fences):
        {
          "tags": ["short label", ...],                 // up to 4; groups like "client", "family", an event, a city
          "relationships": [{"name": "Other Person", "label": "manager"}, ...],  // up to 3; only people NAMED in the context
          "encounters": [{"title": "what happened", "note": "one line"}, ...]    // up to 3; meetings/moments worth logging
        }
        Use [] for any category you have nothing for.

        CONTEXT:
        \(context)
        """
        guard let raw = try? await ollama.generate(prompt: prompt, temperature: 0.2) else { return nil }
        return parse(raw)
    }

    /// Tolerant JSON extraction: strip ``` fences, isolate the outermost {…}.
    static func parse(_ raw: String) -> PersonAISuggestions? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // drop a leading ```json / ``` fence and the trailing ```
            if let firstNewline = s.firstIndex(of: "\n") { s = String(s[s.index(after: firstNewline)...]) }
            if let fence = s.range(of: "```", options: .backwards) { s = String(s[..<fence.lowerBound]) }
        }
        guard let start = s.firstIndex(of: "{"),
              let end = s.lastIndex(of: "}"), start < end else { return nil }
        let json = String(s[start...end])
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(PersonAISuggestions.self, from: data) else { return nil }
        // Drop blanks the model sometimes emits.
        var out = parsed
        out.tags = out.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        out.relationships = out.relationships.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        out.encounters = out.encounters.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        return out
    }
}
