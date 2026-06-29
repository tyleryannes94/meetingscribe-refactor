import Foundation

/// Deterministic, local auto-tagging for tasks (B). Two jobs:
///   • every meeting-sourced action item carries the `#meeting` tag (and already
///     keeps its `meetingID` backlink to the source call),
///   • any task whose title matches a known theme gets that theme tag.
///
/// Runs with no model and no network, so it's instant and safe to call on a
/// timer, after meeting extraction, and on launch. The theme list is shared with
/// `TaskOrganizer` so its suggestions and this auto-tagger never disagree.
enum TaskAutoTagger {
    /// The tag every meeting-derived task gets.
    static let meetingTag = "meeting"

    struct Theme { let tag: String; let keywords: [String] }
    static let themes: [Theme] = [
        .init(tag: "email", keywords: ["email", "reply", "respond to", "follow up", "follow-up", "inbox"]),
        .init(tag: "docs", keywords: ["document", "documentation", "write up", "write-up", "readme", "spec ", "notes for"]),
        .init(tag: "bug", keywords: ["bug", "fix ", "error", "crash", "broken", "regression", "hotfix"]),
        .init(tag: "meeting", keywords: ["meeting", "schedule a", "sync ", "standup", "stand-up", "1:1", "agenda"]),
        .init(tag: "review", keywords: ["review", "pull request", " pr ", "feedback", "sign off", "sign-off", "approve"]),
        .init(tag: "design", keywords: ["design", "mockup", "wireframe", "figma", "prototype"]),
        .init(tag: "analytics", keywords: ["analytics", "metrics", "dashboard", "benchmark", "tracking", "report on"]),
        .init(tag: "research", keywords: ["research", "investigate", "evaluate", "explore", "spike", "compare"]),
        .init(tag: "outreach", keywords: ["reach out", "outreach", "contact ", "intro to", "ping "]),
        .init(tag: "scoping", keywords: ["scope", "scoping", "planning", "estimate", "roadmap"]),
    ]

    /// The single theme tag a title maps to, or nil. First match wins.
    static func theme(for title: String) -> String? {
        let t = " " + title.lowercased() + " "
        for theme in themes { for k in theme.keywords where t.contains(k) { return theme.tag } }
        return nil
    }

    /// Run a full auto-tag pass over the store. Returns the number of tags added.
    @MainActor
    @discardableResult
    static func run(on store: ActionItemStore) -> Int {
        store.autoTag(meetingTag: meetingTag, theme: { theme(for: $0) })
    }
}
