import Foundation

/// Placeholder for a future Slack daily-brief integration on the Brain Dump
/// page. The protocol seam is wired up so the UI affordance compiles today;
/// the concrete provider is a stub. A real impl can land later as a
/// `BoltSlackBriefProvider` (Slack Bolt SDK + OAuth) or
/// `WebhookSlackBriefProvider` (cron-pushed JSON) without touching the
/// Brain Dump store or composer.
protocol SlackBriefProvider {
    var displayName: String { get }
    func fetchDailyBrief() async throws -> SlackBriefSnapshot
}

struct SlackBriefSnapshot {
    var fetchedAt: Date
    var mentions: [SlackMention]
    var unreadDMs: Int
    var notes: String?
}

struct SlackMention {
    var channelID: String
    var channelName: String
    var sender: String
    var snippet: String
    var permalink: URL?
    var timestamp: Date
}

enum SlackBriefError: Error, LocalizedError {
    case notConfigured
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Slack integration isn't connected yet."
        }
    }
}

/// No-op provider — keeps the page compiling and lets the "Slack (soon)"
/// affordance live in the composer toolbar.
struct StubSlackBriefProvider: SlackBriefProvider {
    let displayName = "Slack (coming soon)"
    func fetchDailyBrief() async throws -> SlackBriefSnapshot {
        SlackBriefSnapshot(
            fetchedAt: Date(),
            mentions: [],
            unreadDMs: 0,
            notes: "Slack daily brief — connect Slack in a future update."
        )
    }
}

enum SlackBriefService {
    static func current() -> SlackBriefProvider {
        // When a real provider lands, branch on AppSettings here.
        StubSlackBriefProvider()
    }
}
