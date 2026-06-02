import Foundation

/// C2-4 — a minimal, local, keyword-based pre-flight guard.
///
/// When a user is reflecting on an intimate relationship and the text contains
/// signals of crisis or harm, we deliberately do NOT hand that text to the AI
/// for clinical-style "sentiment / pattern" analysis. A person in crisis
/// writing about a difficult relationship should be met with support, not an
/// app verdict on whether their conversation was "warm" or "tense".
///
/// This is a safety guard, not a diagnosis. It is intentionally a *simple*
/// keyword/phrase matcher (per the audit's C2-4 spec) and errs toward showing
/// help — a false positive costs the user one dismissible resource card, while
/// a miss is the failure mode we care about. All matching is local; no text
/// leaves the device as part of this check.
enum DistressFilter {

    enum Category: Equatable {
        case selfHarm
        case abuse
    }

    /// Conservative phrase lists. Multi-word phrases are preferred over bare
    /// words to cut false positives (e.g. we match "kill myself", not "kill").
    private static let selfHarmPhrases: [String] = [
        "kill myself", "killing myself", "want to die", "wanna die",
        "end my life", "ending my life", "end it all",
        "hurt myself", "harm myself", "self-harm", "self harm",
        "cutting myself", "suicidal", "suicide", "better off dead",
        "no reason to live", "don't want to be here anymore",
        "can't go on", "cant go on"
    ]

    private static let abusePhrases: [String] = [
        "he hits me", "she hits me", "they hit me", "hits me", "hit me",
        "he hurts me", "she hurts me", "hurting me",
        "afraid of him", "afraid of her", "scared of him", "scared of her",
        "abusing me", "abuses me", "abused me",
        "threatened to", "threatened me", "threatens me",
        "forced me to", "won't let me leave", "wont let me leave",
        "controls everything", "hurt the kids", "hurts the kids"
    ]

    /// Returns the matched category if the text contains a distress signal,
    /// else nil. Self-harm takes precedence over abuse when both appear, since
    /// the immediate-safety resources differ. Matching is case-insensitive.
    static func scan(_ text: String) -> Category? {
        let lower = text.lowercased()
        if selfHarmPhrases.contains(where: { lower.contains($0) }) { return .selfHarm }
        if abusePhrases.contains(where: { lower.contains($0) }) { return .abuse }
        return nil
    }

    /// A compassionate, non-clinical message with crisis resources, shown in
    /// place of AI output when a signal is detected. US-centric resources; the
    /// 988 line and Crisis Text Line are the broadly recognized entry points.
    static func supportiveMessage(for category: Category) -> String {
        let opening: String
        var resources: [String]
        switch category {
        case .selfHarm:
            opening = "It sounds like things might be really heavy right now. Before reading patterns from an app, please consider reaching out to someone who can help — you don't have to sit with this alone."
            resources = [
                "988 Suicide & Crisis Lifeline — call or text 988 (US, 24/7)",
                "Crisis Text Line — text HOME to 741741"
            ]
        case .abuse:
            opening = "Some of what you wrote sounds like it may not feel safe. Before letting an app analyze it, please consider talking to someone who can help."
            resources = [
                "National Domestic Violence Hotline — call 1-800-799-7233 or text START to 88788",
                "988 Suicide & Crisis Lifeline — call or text 988 (US, 24/7)"
            ]
        }
        let bullets = resources.map { "• \($0)" }.joined(separator: "\n")
        return opening + "\n\n" + bullets +
            "\n\nThis tool isn't a substitute for talking to a person you trust or a professional. Your messages were not sent for AI analysis."
    }
}
