import SwiftUI

/// An inline peek at a task's source meeting (4-4) — title, date, attendees, a
/// summary excerpt, and any extracted decisions — without leaving the Tasks tab.
/// Shown as a popover anchored to the "From meeting" affordance; the user can
/// still jump to the full meeting from here.
@available(macOS 14.0, *)
struct MeetingPeekPanel: View {
    let meetingID: String
    @EnvironmentObject var manager: MeetingManager
    var onOpenFull: () -> Void

    @State private var expanded = false

    private var meeting: Meeting? { manager.meeting(id: meetingID) }
    private var summary: String { manager.summaryText(forMeetingID: meetingID) ?? "" }

    /// Lines that read like a decision ("Decision:", "Decided:", with optional
    /// markdown bullet/bold prefixes).
    private var decisions: [String] {
        summary.components(separatedBy: .newlines).compactMap { raw in
            var t = raw.trimmingCharacters(in: .whitespaces)
            for lead in ["- ", "* ", "**"] where t.hasPrefix(lead) { t.removeFirst(lead.count) }
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            for marker in ["decision:", "decided:"] where t.lowercased().hasPrefix(marker) {
                return t.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meeting?.displayTitle ?? "Meeting")
                .scaledFont(16, weight: .bold).foregroundStyle(NDS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let m = meeting {
                HStack(spacing: 8) {
                    Label(Self.dateString(m.startDate), systemImage: "calendar")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    if !m.attendees.isEmpty {
                        Label("\(m.attendees.count)", systemImage: "person.2")
                            .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    }
                }
                if !m.attendees.isEmpty {
                    Text(m.attendees.prefix(4).joined(separator: ", ") + (m.attendees.count > 4 ? "…" : ""))
                        .font(NDS.tiny).foregroundStyle(NDS.textSecondary).lineLimit(2)
                }
            }

            if !summary.isEmpty {
                Divider().overlay(NDS.divider)
                Text("Summary").font(NDS.tiny.weight(.semibold)).foregroundStyle(NDS.textTertiary)
                Text(excerpt)
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if summary.count > 400 {
                    Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                        .font(NDS.tiny).buttonStyle(.plain).foregroundStyle(NDS.brand)
                }
            }

            if !decisions.isEmpty {
                Divider().overlay(NDS.divider)
                Text("Decisions").font(NDS.tiny.weight(.semibold)).foregroundStyle(NDS.textTertiary)
                ForEach(Array(decisions.prefix(5).enumerated()), id: \.offset) { _, d in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "checkmark.seal.fill").scaledFont(10).foregroundStyle(NDS.selectColor("green"))
                        Text(d).font(NDS.small).foregroundStyle(NDS.textSecondary)
                    }
                }
            }

            Divider().overlay(NDS.divider)
            Button { onOpenFull() } label: {
                Label("Open full meeting", systemImage: "arrow.up.right")
            }
            .buttonStyle(.plain).font(NDS.small).foregroundStyle(NDS.brand)
        }
        .padding(14)
        .frame(width: 380)
    }

    private var excerpt: String {
        if expanded { return String(summary.prefix(2000)) }
        return summary.count > 400 ? String(summary.prefix(400)) + "…" : summary
    }

    private static func dateString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d · h:mm a"; return f.string(from: d)
    }
}
