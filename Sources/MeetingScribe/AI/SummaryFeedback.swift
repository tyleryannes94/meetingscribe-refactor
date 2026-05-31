import Foundation

/// Local 👍/👎 + "why" feedback on a meeting summary (P5-3). The local LLM is the
/// product's variable-quality core and had no feedback loop; a 👎 with a reason
/// is fed into the next regeneration prompt to steer it. Stored per-meeting in
/// UserDefaults (thread-safe, nonisolated) so both the @MainActor UI and the
/// summarizer (off-main) can touch it.
enum SummaryFeedback {
    private static func upKey(_ id: String)  -> String { "sfb.up.\(id)" }
    private static func hasKey(_ id: String) -> String { "sfb.has.\(id)" }
    private static func whyKey(_ id: String) -> String { "sfb.why.\(id)" }

    static func set(up: Bool, why: String?, for meetingID: String) {
        let d = UserDefaults.standard
        d.set(true, forKey: hasKey(meetingID))
        d.set(up, forKey: upKey(meetingID))
        let trimmed = (why ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { d.removeObject(forKey: whyKey(meetingID)) }
        else { d.set(trimmed, forKey: whyKey(meetingID)) }
    }

    /// (hasRating, thumbsUp, why)
    static func rating(for meetingID: String) -> (has: Bool, up: Bool, why: String?) {
        let d = UserDefaults.standard
        return (d.bool(forKey: hasKey(meetingID)),
                d.bool(forKey: upKey(meetingID)),
                d.string(forKey: whyKey(meetingID)))
    }

    /// A steering note for the regenerate prompt — only when the last summary was
    /// thumbed-down with a reason.
    static func steeringNote(for meetingID: String) -> String? {
        let r = rating(for: meetingID)
        guard r.has, !r.up, let why = r.why, !why.isEmpty else { return nil }
        return why
    }
}
