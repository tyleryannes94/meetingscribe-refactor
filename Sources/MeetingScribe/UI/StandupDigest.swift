import SwiftUI
import AppKit

/// Standup / daily digest (U1-4): a 60-second "yesterday / today / open
/// commitments / blockers" compiled from the user's own data. Structured (not
/// LLM-generated) so it's instant and reliable.
@available(macOS 14.0, *)
enum StandupDigest {
    @MainActor
    static func markdown(manager: MeetingManager, calendar: CalendarService) -> String {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let yStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        let yesterday = manager.pastMeetings
            .filter { $0.startDate >= yStart && $0.startDate < todayStart }
            .sorted { $0.startDate < $1.startDate }
        let today = calendar.upcoming
            .filter { cal.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }
        let open = manager.actionItems.items.filter { $0.status != .completed }
        let overdue = open.filter { ($0.dueDate.map { $0 < todayStart }) ?? false }

        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        var lines = ["# Standup — \(now.formatted(date: .abbreviated, time: .omitted))", ""]

        lines.append("## Yesterday")
        lines += yesterday.isEmpty ? ["- _(no recorded meetings)_"]
                                   : yesterday.map { "- \($0.displayTitle)" }
        lines.append("")

        lines.append("## Today")
        lines += today.isEmpty ? ["- _(nothing on the calendar)_"]
                               : today.map { "- \(tf.string(from: $0.startDate)) — \($0.displayTitle)" }
        lines.append("")

        lines.append("## Open commitments")
        lines += open.isEmpty ? ["- _(none)_"]
                              : open.prefix(12).map { item in
                                  let who = (item.owner.map { " — \($0)" }) ?? ""
                                  return "- [ ] \(item.title)\(who)"
                              }

        if !overdue.isEmpty {
            lines.append("")
            lines.append("## Blockers / overdue")
            lines += overdue.map { "- ⚠️ \($0.title)" }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

@available(macOS 14.0, *)
struct StandupDigestSheet: View {
    let markdown: String
    @Binding var isPresented: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily standup").scaledFont(18, weight: .bold)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                MarkdownText(markdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: 520, minHeight: 540)
    }
}
