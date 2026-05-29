import SwiftUI
import AppKit

/// Pre-meeting brief shown when a user taps into an upcoming calendar event.
/// Replaces the "No transcript yet" placeholder with genuinely useful context:
///   • Prior meetings with any of the same attendees (email-matched)
///   • Open action items from those prior meetings
///   • Attendee People-record links (if they exist in PeopleStore)
///
/// Data is all in-memory — no async work needed beyond an initial filter pass.
@available(macOS 14.0, *)
struct PreMeetingBriefView: View {
    let meeting: Meeting

    @EnvironmentObject var manager: MeetingManager

    // Computed once on appear; stored in state so the view doesn't
    // recompute on every re-render triggered by unrelated manager changes.
    @State private var priorMeetings: [Meeting] = []
    @State private var openItems: [ActionItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if !openItems.isEmpty   { openItemsSection }
                if !priorMeetings.isEmpty { priorMeetingsSection }
                if priorMeetings.isEmpty && openItems.isEmpty { emptyState }
            }
            .padding()
        }
        .onAppear { computeBrief() }
        .onChange(of: meeting.id) { _, _ in computeBrief() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Pre-meeting brief", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .foregroundStyle(NDS.brand)
            Text("Context from previous meetings with these attendees.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var openItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Open action items from prior meetings",
                  systemImage: "checklist")
                .font(.callout.weight(.semibold))

            ForEach(openItems.prefix(10)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.callout)
                        if let mtg = manager.pastMeetings.first(where: { $0.id == item.meetingID }) {
                            Text(mtg.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            if openItems.count > 10 {
                Text("+ \(openItems.count - 10) more in Tasks tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(NDS.brand.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var priorMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent meetings with these attendees",
                  systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.callout.weight(.semibold))

            ForEach(priorMeetings.prefix(5)) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.displayTitle)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(m.startDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let items = manager.actionItems.items(for: m.id)
                        .filter { $0.status != .completed }
                    if !items.isEmpty {
                        Text("\(items.count) open action item\(items.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No prior meetings found")
                .font(.callout.weight(.medium))
            Text("This appears to be a first meeting with these attendees, or Calendar access hasn't been granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    // MARK: - Data computation

    private func computeBrief() {
        let emails = attendeeEmails(from: meeting.attendees)
        guard !emails.isEmpty else {
            priorMeetings = []
            openItems = []
            return
        }

        // All past meetings that share at least one attendee email.
        let related = manager.pastMeetings.filter { past in
            let pastEmails = attendeeEmails(from: past.attendees)
            return !pastEmails.isDisjoint(with: emails)
        }
        .sorted { $0.startDate > $1.startDate }

        priorMeetings = Array(related.prefix(10))

        // Collect open action items from those meetings.
        openItems = related.flatMap { m in
            manager.actionItems.items(for: m.id).filter { $0.status != .completed }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Extract the email portion from "Name <email>" attendee strings.
    private func attendeeEmails(from attendees: [String]) -> Set<String> {
        Set(attendees.compactMap { str -> String? in
            guard let open = str.lastIndex(of: "<"),
                  let close = str.lastIndex(of: ">"),
                  open < close else {
                // Plain email with no angle brackets — use as-is.
                return str.contains("@") ? str.lowercased() : nil
            }
            let start = str.index(after: open)
            return String(str[start..<close]).lowercased()
        })
    }
}
