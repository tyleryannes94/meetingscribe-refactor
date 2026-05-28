import Foundation

/// A generated follow-up draft for one channel (email or Slack), produced from
/// a meeting's summary + action items.
struct FollowUpSuggestion: Identifiable, Hashable, Sendable {
    enum Channel: String, CaseIterable, Identifiable, Sendable {
        case email, slack
        var id: String { rawValue }
        var label: String {
            switch self {
            case .email: return "Email"
            case .slack: return "Slack"
            }
        }
        var systemImage: String {
            switch self {
            case .email: return "envelope"
            case .slack: return "message"
            }
        }
    }

    let id = UUID()
    let channel: Channel
    /// Only meaningful for `.email`; nil/empty for Slack.
    var subject: String?
    var body: String

    /// Subject + body joined, suitable for copying to the clipboard.
    var plainText: String {
        if let s = subject, !s.isEmpty {
            return "Subject: \(s)\n\n\(body)"
        }
        return body
    }
}
