import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    @ViewBuilder
var chatBody: some View {
        if let m = meeting {
            ChatPanel(
                session: chatSession,
                density: .compact,
                capabilitySections: Self.meetingCapabilitySections
            )
            // P0-2: scope the shared assistant to this meeting on the session's
            // pageContext (same mechanism Today/People use) instead of a
            // per-message contextPrefix on a throwaway session. Messages persist.
            .onAppear {
                attachChatIfNeeded()
                chatSession.setContext(chatContext(for: m), label: m.displayTitle)
            }
            .onChange(of: m.id) { _, _ in
                chatSession.setContext(chatContext(for: m), label: m.displayTitle)
            }
        } else {
            placeholder(systemImage: "sparkles",
                        title: "No meeting context",
                        message: "Open a meeting to chat about it.")
        }
    }

    /// Meeting-scoped capability groups so discovery matches the Today sidebar's
    /// categorized "What can I ask?" instead of a flat prompt list (P0-2).
    static var meetingCapabilitySections: [ChatPanel.CapabilitySection] {
        [
            .init(label: "This meeting", prompts: [
                "Summarize the key decisions from this meeting.",
                "Pull the action items and who owns each.",
                "What questions were left unanswered?"
            ]),
            .init(label: "Follow-up", prompts: [
                "Draft a follow-up email recapping this call.",
                "What should I send each attendee afterward?"
            ]),
            .init(label: "Analysis", prompts: [
                "What did the attendees seem to disagree on?",
                "How does this connect to our earlier meetings?"
            ])
        ]
    }

    /// Per-meeting context the AI sees alongside every user message.
    /// Keeps the conversation scoped to this call without the user having
    /// to repeat themselves.
func chatContext(for m: Meeting) -> String {
        // Make this meeting resolvable by the chat tools even if it isn't a
        // finalized past meeting yet (calendar/today meeting). Fixes Ask AI's
        // "meeting not found". Plain (non-published) var — no view invalidation.
        manager.chatContextMeeting = m
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d 'at' h:mm a"
        var lines: [String] = []
        lines.append("Context: This conversation is about a specific meeting.")
        lines.append("- Title: \(m.displayTitle)")
        lines.append("- When: \(f.string(from: m.startDate))")
        lines.append("- Meeting ID: \(m.id)")
        if let cal = m.calendarName { lines.append("- Calendar: \(cal)") }
        if !m.attendees.isEmpty {
            lines.append("- Attendees: \(m.attendees.joined(separator: ", "))")
        }
        // P1-10: inject what the vault already knows about the resolved
        // attendees so "what should I ask Jane?" answers from the relationship
        // graph, not just this transcript. All local — no privacy cost.
        let people = PeopleStore.shared.people
        var blocks: [String] = []
        for raw in m.attendees {
            guard let id = PersonResolver.resolve(raw, in: people),
                  let p = people.first(where: { $0.id == id }) else { continue }
            var b = "  • \(p.displayName)"
            let rc = [p.role, p.company].filter { !$0.isEmpty }.joined(separator: " at ")
            if !rc.isEmpty { b += " (\(rc))" }
            if p.relationshipType != .unset { b += " — \(p.relationshipType.displayName)" }
            let mems = p.memories.prefix(3).map(\.text)
            if !mems.isEmpty { b += "; you've noted: " + mems.joined(separator: "; ") }
            if !p.talkingPoints.isEmpty { b += "; to discuss next: " + p.talkingPoints.joined(separator: "; ") }
            blocks.append(b)
        }
        if !blocks.isEmpty {
            lines.append("What you know about the people here (from your private notes):")
            lines.append(contentsOf: blocks)
        }
        lines.append("If you need the transcript, notes, or summary, call get_transcript / get_notes / get_summary with the \"id\" \(m.id).")
        lines.append("Answer from this meeting's transcript / notes / summary and the people data above. Do NOT use the file or Chat-folder tools (list_files, search_files, etc.) unless the user explicitly asks about files on disk — a meeting is not a folder.")
        return lines.joined(separator: "\n")
    }

func attachChatIfNeeded() {
        guard !chatAttached else { return }
        chatSession.attach(manager: manager)
        chatAttached = true
    }
}
