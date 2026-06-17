import Foundation

/// Canonical assembled context for one person (1-D / audit E5-3).
///
/// Before this, every AI surface — the pre-meeting brief, weekly recap, standup
/// digest, chat tools, global search — re-assembled "what do I know about this
/// person" with slightly different rules. `PersonContext` is the single shape;
/// `PersonContextBuilder` is the single assembler. The "Brief Me" synthesis
/// (Phase 2-B) and the relational context strips (Phase 5) consume it.
struct PersonContext {
    let person: Person
    /// Most recent meeting this person attended (by `meetingMentions`).
    let lastMeeting: Meeting?
    /// Open tasks this person owns — what we're waiting on / their commitments.
    let openTasksForPerson: [ActionItem]
    /// Subset explicitly delegated — "waiting on them".
    let waitingOnThem: [ActionItem]
    let talkingPoints: [String]
    /// Recent iMessage themes — nil until the Phase 2 iMessage wiring lands.
    let recentIMessageThemes: [String]?
    let strengthScore: Double?
    /// Next upcoming calendar meeting that includes this person.
    let nextSharedEvent: Meeting?
    let meetingCount: Int
    /// Excerpt of the cached "summary-all" relationship note, if present.
    let relationshipSummaryExcerpt: String?

    /// A compact, prompt-ready block so every AI surface grounds on the *same*
    /// facts. Empty lines are omitted so the prompt stays tight.
    func aiContextBlock() -> String {
        var lines: [String] = []
        lines.append("Person: \(person.displayName)" +
                     ([person.role, person.company].filter { !$0.isEmpty }.isEmpty
                        ? "" : " (\([person.role, person.company].filter { !$0.isEmpty }.joined(separator: ", ")))"))
        if person.relationshipType != .unset {
            lines.append("Relationship: \(person.relationshipType.displayName)")
        }
        if let s = strengthScore { lines.append("Relationship strength: \(Int(s * 100))/100") }
        if let m = lastMeeting {
            lines.append("Last meeting: \(m.displayTitle) on \(Self.dateString(m.startDate))")
        }
        lines.append("Meetings together: \(meetingCount)")
        if !openTasksForPerson.isEmpty {
            lines.append("Open items they own: " + openTasksForPerson.prefix(5).map(\.title).joined(separator: "; "))
        }
        if !waitingOnThem.isEmpty {
            lines.append("Waiting on them: " + waitingOnThem.prefix(5).map(\.title).joined(separator: "; "))
        }
        if !talkingPoints.isEmpty {
            lines.append("Talking points to raise: " + talkingPoints.joined(separator: "; "))
        }
        if let themes = recentIMessageThemes, !themes.isEmpty {
            lines.append("Recent message themes: " + themes.joined(separator: ", "))
        }
        if let e = nextSharedEvent {
            lines.append("Next meeting together: \(e.displayTitle) on \(Self.dateString(e.startDate))")
        }
        if let excerpt = relationshipSummaryExcerpt, !excerpt.isEmpty {
            lines.append("Summary so far: \(excerpt)")
        }
        return lines.joined(separator: "\n")
    }

    private static func dateString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
    }
}

/// The single place person context is assembled. The non-singleton stores are
/// injected (only `PeopleStore` is a process-wide singleton) so the builder stays
/// pure and unit-testable.
@MainActor
enum PersonContextBuilder {
    static func build(personID: String,
                      actionItems: ActionItemStore,
                      pastMeetings: [Meeting],
                      calendarUpcoming: [Meeting] = [],
                      people: PeopleStore = .shared) -> PersonContext? {
        guard let person = people.person(by: personID) else { return nil }

        // Meetings this person attended — `meetingMentions` is kept current by
        // PeopleStore.linkAttendees. Newest first.
        let byID = Dictionary(pastMeetings.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let meetings = person.meetingMentions.compactMap { byID[$0] }
            .sorted { $0.startDate > $1.startDate }

        let openForPerson = actionItems.items.filter {
            $0.ownerPersonID == personID && $0.status != .completed
        }
        let waitingOnThem = openForPerson.filter { $0.delegated == true }

        let now = Date()
        let allPeople = people.people
        let nextEvent = calendarUpcoming
            .filter { $0.startDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .first { m in
                PersonResolver.resolvedAttendees(m.attendees, in: allPeople)
                    .contains { $0.personID == personID }
            }

        let summaryNote = person.attachedNotes.first { $0.kind == "summary-all" }?.body
        let summaryExcerpt = summaryNote.map { String($0.prefix(300)) }

        return PersonContext(
            person: person,
            lastMeeting: meetings.first,
            openTasksForPerson: openForPerson,
            waitingOnThem: waitingOnThem,
            talkingPoints: person.talkingPoints,
            recentIMessageThemes: nil,
            strengthScore: person.relationshipStrengthScore,
            nextSharedEvent: nextEvent,
            meetingCount: meetings.count,
            relationshipSummaryExcerpt: summaryExcerpt)
    }
}
