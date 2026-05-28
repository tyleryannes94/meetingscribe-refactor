import Foundation

/// Generates a follow-up draft (email or Slack) from a meeting's summary and
/// action items by prompting the local Ollama model. Reuses the same
/// `OllamaService` the summarizer uses, so it inherits auto-start + reachability
/// handling.
struct FollowUpGeneratorService {
    private let ollama = OllamaService()

    func generate(channel: FollowUpSuggestion.Channel,
                  meetingTitle: String,
                  summary: String,
                  actionItems: [String]) async throws -> FollowUpSuggestion {
        let prompt = Self.buildPrompt(channel: channel,
                                      meetingTitle: meetingTitle,
                                      summary: summary,
                                      actionItems: actionItems)
        let raw = try await ollama.generate(prompt: prompt, temperature: 0.4)
        return Self.parse(raw, channel: channel)
    }

    // MARK: - Prompt

    private static func buildPrompt(channel: FollowUpSuggestion.Channel,
                                    meetingTitle: String,
                                    summary: String,
                                    actionItems: [String]) -> String {
        let items = actionItems.isEmpty
            ? "(none captured)"
            : actionItems.map { "- \($0)" }.joined(separator: "\n")

        let channelInstructions: String
        switch channel {
        case .email:
            channelInstructions = """
            Write a concise follow-up EMAIL recapping the meeting. Start the very \
            first line with "Subject: " followed by a short subject, then a blank \
            line, then the body. Keep it warm but brief; lead with outcomes, then \
            list next steps with owners if known. Sign off generically.
            """
        case .slack:
            channelInstructions = """
            Write a short follow-up SLACK message recapping the meeting. No subject \
            line. Use a friendly, skimmable tone with a couple of bullet points for \
            next steps. Keep it under ~120 words.
            """
        }

        return """
        You are drafting a post-meeting follow-up.

        Meeting: \(meetingTitle)

        Summary:
        \(summary.isEmpty ? "(no summary available)" : summary)

        Action items:
        \(items)

        \(channelInstructions)

        Output only the message text — no preamble, no markdown code fences.
        """
    }

    // MARK: - Parse

    private static func parse(_ raw: String, channel: FollowUpSuggestion.Channel) -> FollowUpSuggestion {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard channel == .email else {
            return FollowUpSuggestion(channel: channel, subject: nil, body: text)
        }
        // Pull a leading "Subject:" line if the model produced one.
        if let firstNewline = text.firstIndex(of: "\n") {
            let firstLine = text[..<firstNewline]
            if let range = firstLine.range(of: "subject:", options: .caseInsensitive) {
                let subject = firstLine[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let body = text[text.index(after: firstNewline)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return FollowUpSuggestion(channel: .email, subject: subject, body: body)
            }
        }
        return FollowUpSuggestion(channel: .email, subject: nil, body: text)
    }
}
