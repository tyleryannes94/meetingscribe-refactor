import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    @ViewBuilder
var chatBody: some View {
        if let m = meeting {
            ChatPanel(
                session: meetingChat,
                contextPrefix: chatContext(for: m),
                density: .compact,
                examplePrompts: [
                    "Summarize the key decisions from this meeting.",
                    "Pull the action items and who owns each.",
                    "What questions were left unanswered?",
                    "Draft a follow-up email recapping this call."
                ]
            )
        } else {
            placeholder(systemImage: "sparkles",
                        title: "No meeting context",
                        message: "Open a meeting to chat about it.")
        }
    }

    /// Per-meeting context the AI sees alongside every user message.
    /// Keeps the conversation scoped to this call without the user having
    /// to repeat themselves.
func chatContext(for m: Meeting) -> String {
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
        lines.append("If you need the transcript, notes, or summary, call get_transcript / get_notes / get_summary with this meeting_id.")
        return lines.joined(separator: "\n")
    }

func attachChatIfNeeded() {
        guard !chatAttached else { return }
        meetingChat.attach(manager: manager)
        chatAttached = true
    }
}
