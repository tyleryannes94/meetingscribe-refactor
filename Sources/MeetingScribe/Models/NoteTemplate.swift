import Foundation

/// Phase 4 — reusable note/page templates. Inserted from the editor's "/"
/// slash menu or the Templates toolbar button. Plain markdown so the result is
/// just text in notes.md.
struct NoteTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let body: String

    static let all: [NoteTemplate] = [
        NoteTemplate(
            id: "meeting-notes",
            name: "Meeting notes",
            systemImage: "doc.text",
            body: """
            # Meeting notes

            **Date:** \(NoteTemplate.today)
            **Attendees:**

            ## Agenda
            -

            ## Discussion
            -

            ## Decisions
            -

            ## Action items
            - [ ]

            """),
        NoteTemplate(
            id: "one-on-one",
            name: "1:1",
            systemImage: "person.2",
            body: """
            # 1:1 — \(NoteTemplate.today)

            ## Wins since last time
            -

            ## Challenges / blockers
            -

            ## Feedback
            -

            ## Action items
            - [ ]

            """),
        NoteTemplate(
            id: "standup",
            name: "Standup",
            systemImage: "sun.max",
            body: """
            # Standup — \(NoteTemplate.today)

            **Yesterday:**
            -

            **Today:**
            -

            **Blockers:**
            -

            """),
        NoteTemplate(
            id: "decision-log",
            name: "Decision log",
            systemImage: "checkmark.seal",
            body: """
            # Decision

            **Context:**

            **Options considered:**
            1.
            2.

            **Decision:**

            **Owner:**
            **Date:** \(NoteTemplate.today)

            """),
        NoteTemplate(
            id: "weekly-review",
            name: "Weekly review",
            systemImage: "calendar.badge.clock",
            body: """
            # Weekly review — \(NoteTemplate.today)

            ## Highlights
            -

            ## What slipped
            -

            ## Next week's focus
            - [ ]

            """)
    ]

    private static var today: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: Date())
    }
}
