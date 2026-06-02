import Foundation

/// Static library of per-type relationship coaching prompts.
/// No server, no AI generation required — pure Swift enum.
/// Surfaced as rotating prompts in PersonDetailView's identity panel
/// for partner, family, and close friend relationship types. (Phase 3)
///
/// Prompt selection rotates by week so the same prompt doesn't reappear
/// for ~3 months (10+ partner prompts × 7 days = ~70 days).
struct RelationshipPromptLibrary {

    // MARK: - Partner prompts (Gottman-inspired)

    static let partnerPrompts: [String] = [
        "Name three things your partner did this week that you appreciated — even small ones.",
        "What's a dream or aspiration of theirs you'd like to support more actively?",
        "When did you last turn toward them when they made a bid for connection?",
        "Is there a repair you've been meaning to make after a recent tension?",
        "What makes your partner feel most loved? Did you do that recently?",
        "What shared ritual or routine brings you closest? Are you protecting it?",
        "Describe a recent moment when you felt genuinely understood by them.",
        "Is there something unsaid that's creating low-grade distance right now?",
        "What would a '10/10 week' look like for your relationship?",
        "What's something new you've learned about them in the past month?",
        "How are you growing together versus in parallel right now?"
    ]

    // MARK: - Family prompts (NVC-informed)

    static let familyPrompts: [String] = [
        "What's a need you have in this relationship that hasn't been voiced yet?",
        "When did you last ask how they're really doing — and really listen?",
        "Is there a shared memory you could revisit together to reconnect?",
        "What life stage are they in right now, and how can you better meet them there?",
        "What's something you've been grateful for about them but haven't said?",
        "Is there an old pattern between you two worth consciously changing?",
        "What would a call next week look like if you made it purely about them?",
        "What do you wish they knew about your inner life right now?"
    ]

    // MARK: - Close friend prompts (love language-aware)

    static let closeFriendPrompts: [String] = [
        "When did you last do something specifically in their love language?",
        "What's something you've experienced recently that you haven't shared with them?",
        "Is this friendship as reciprocal as it was a year ago? What shifted?",
        "What shared goal or adventure could you propose together?",
        "Have you told them recently what their friendship means to you?",
        "Is there a way they've shown up for you that you haven't properly acknowledged?",
        "What's one thing about them you've never told them you admire?",
        "When did you last just hang out with no agenda?",
        "Are there any unresolved tensions you've been avoiding?"
    ]

    // MARK: - Access

    /// Returns the prompt for this week for the given relationship type.
    /// Uses the ISO week number so it rotates weekly and is deterministic.
    static func weeklyPrompt(for type: RelationshipType) -> String? {
        let prompts: [String]
        switch type {
        case .romanticPartner:  prompts = partnerPrompts
        case .familyMember:     prompts = familyPrompts
        case .closeFriend:      prompts = closeFriendPrompts
        default:                return nil
        }
        guard !prompts.isEmpty else { return nil }
        let week = Calendar.current.component(.weekOfYear, from: Date())
        return prompts[week % prompts.count]
    }
}
