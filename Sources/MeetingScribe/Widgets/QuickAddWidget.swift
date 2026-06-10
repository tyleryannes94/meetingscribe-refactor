import AppIntents
import Foundation

/// Quick Add (STUB).
///
/// An `AppIntent` so "create a meeting draft" is reachable from Spotlight,
/// Shortcuts, and (eventually) a Control Center / Home Screen widget without
/// opening the app. Today it just validates input and reports back; wiring it
/// to actually create a draft is the TODO below.
@available(macOS 13.0, *)
struct QuickAddMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Meeting"
    static var description = IntentDescription(
        "Create a meeting draft from a title, without opening MeetingScribe."
    )
    /// Don't foreground the app — the whole point is a lightweight capture.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Meeting title")
    var meetingTitle: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Give the meeting a title and try again.")
        }
        // TODO: post to MeetingManager (e.g. via a NotificationCenter draft
        // request, since AppIntents run outside the app's normal lifecycle) to
        // persist a draft Meeting with this title. For now we just acknowledge.
        return .result(dialog: "Drafted “\(trimmed)”.")
    }
}

/// Registers the Quick Add intent as an App Shortcut so it shows up in
/// Shortcuts / Spotlight with a spoken phrase.
@available(macOS 13.0, *)
struct MeetingScribeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddMeetingIntent(),
            phrases: ["Quick add a meeting in \(.applicationName)"],
            shortTitle: "Quick Add Meeting",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: CaptureQuickNoteIntent(),
            phrases: ["Capture a note in \(.applicationName)"],
            shortTitle: "Capture Quick Note",
            systemImageName: "note.text.badge.plus"
        )
        AppShortcut(
            intent: AddActionItemIntent(),
            phrases: ["Add a task in \(.applicationName)"],
            shortTitle: "Add Action Item",
            systemImageName: "checklist"
        )
    }
}
