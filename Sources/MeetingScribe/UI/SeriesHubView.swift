import SwiftUI
import AppKit

/// Series Hub (C1-4) — a focused page for the recurring meeting *itself*, not a
/// single occurrence. Recurring calls share a `seriesID`; this view aggregates
/// the whole standing meeting so the through-line stops dying inside individual
/// occurrences:
///
///   • Header — series title, cadence + occurrence count, and the attendee
///     roster (union across every occurrence).
///   • Occurrence timeline — each recorded occurrence, newest first, tappable to
///     open that meeting.
///   • Rolling open items — every still-open action item across the series, with
///     the occurrence it came from.
///   • Decisions ledger — decisions filtered to this series.
///
/// Presented as a sheet from the "Recurring" chip in the meeting header. Reads
/// only existing public store APIs (`manager.pastMeetings`,
/// `manager.actionItems.items(for:)`, `manager.decisions.decisions`) and the
/// router's `openMeeting` — it owns no model or store changes.
@available(macOS 14.0, *)
struct SeriesHubView: View {
    /// Any one occurrence of the series — used to read `seriesID` + title.
    let meeting: Meeting

    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var router: WorkspaceRouter
    @Environment(\.dismiss) private var dismiss

    // MARK: - Series data (read-only derivations)

    private var seriesID: String? {
        guard let sid = meeting.seriesID, !sid.isEmpty else { return nil }
        return sid
    }

    /// Every recorded occurrence of this series, newest first, including the one
    /// we were opened from (even if it isn't in `pastMeetings` yet).
    private var occurrences: [Meeting] {
        guard let sid = seriesID else { return [meeting] }
        var all = manager.pastMeetings.filter { $0.seriesID == sid }
        if !all.contains(where: { $0.id == meeting.id }) { all.append(meeting) }
        return all.sorted { $0.startDate > $1.startDate }
    }

    /// Union of attendees across the whole series, de-duped, in first-seen
    /// (oldest occurrence first) order so the founding roster reads first.
    private var roster: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for occ in occurrences.sorted(by: { $0.startDate < $1.startDate }) {
            for a in occ.attendees where !seen.contains(a) {
                seen.insert(a); out.append(a)
            }
        }
        return out
    }

    /// Still-open action items across every occurrence, paired with the date of
    /// the occurrence they came from. Highest priority (then most recent) first.
    private var openItems: [(item: ActionItem, date: Date)] {
        occurrences.flatMap { occ in
            manager.actionItems.items(for: occ.id)
                .filter { $0.status != .completed && !$0.isTrashed }
                .map { (item: $0, date: occ.startDate) }
        }
        .sorted { ($0.item.priority.weight, $0.date) > ($1.item.priority.weight, $1.date) }
    }

    /// Decisions made anywhere in the series, newest first.
    private var seriesDecisions: [Decision] {
        let ids = Set(occurrences.map { $0.id })
        return manager.decisions.decisions
            .filter { ids.contains($0.meetingID) }
            .sorted { $0.date > $1.date }
    }

    /// A short one-line outcome for an occurrence row: its first recorded
    /// decision, else the user's own description, else nothing.
    private func outcome(for m: Meeting) -> String? {
        if let d = manager.decisions.decisions.first(where: { $0.meetingID == m.id }) {
            return d.text
        }
        if let desc = m.userDescription, !desc.isEmpty { return desc }
        return nil
    }

    /// A plain-language cadence guess from the median gap between occurrences.
    /// nil when there's too little history to tell.
    private var cadence: String? {
        let dates = occurrences.map(\.startDate).sorted()
        guard dates.count >= 2 else { return nil }
        var gaps: [Double] = []
        for i in 1..<dates.count {
            gaps.append(dates[i].timeIntervalSince(dates[i - 1]) / 86_400)
        }
        let median = gaps.sorted()[gaps.count / 2]
        switch median {
        case ..<2:    return "Daily"
        case ..<11:   return "Weekly"
        case ..<18:   return "Every two weeks"
        case ..<45:   return "Monthly"
        default:      return nil
        }
    }

    private var subtitle: String {
        let count = occurrences.count
        let occ = count == 1 ? "1 occurrence" : "\(count) occurrences"
        if let cadence { return "\(cadence) · \(occ)" }
        return occ
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(NDS.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: NDS.spaceXL) {
                    rosterSection
                    timelineSection
                    openItemsSection
                    decisionsSection
                }
                .padding(NDS.spaceXL)
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 720)
        .background(NDS.bg)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(NDS.lilacSoft).frame(width: 36, height: 36)
                Image(systemName: "repeat")
                    .scaledFont(15, weight: .bold)
                    .foregroundStyle(NDS.lilac)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.displayTitle)
                    .scaledFont(20, weight: .bold)
                    .foregroundStyle(NDS.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .scaledFont(12)
                    .foregroundStyle(NDS.textSecondary)
            }
            Spacer(minLength: 12)
            Button("Done") { dismiss() }
                .buttonStyle(MSSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, NDS.spaceXL)
        .padding(.vertical, NDS.spaceLG)
    }

    // MARK: - Roster

    @ViewBuilder
    private var rosterSection: some View {
        if !roster.isEmpty {
            VStack(alignment: .leading, spacing: NDS.spaceMD) {
                NotionEyebrow(text: "People", count: roster.count)
                FlowLayout(spacing: 8) {
                    ForEach(roster, id: \.self) { a in
                        rosterChip(a)
                    }
                }
            }
        }
    }

    private func rosterChip(_ attendee: String) -> some View {
        let identity = PersonResolver.parse(attendee)
        let name = identity.hasName ? identity.name : PersonResolver.localPart(of: identity.email)
        return HStack(spacing: 6) {
            MSAvatar(name: name, size: 20)
            Text(name)
                .scaledFont(12)
                .foregroundStyle(NDS.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(NDS.fieldBg, in: Capsule())
        .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 1))
    }

    // MARK: - Occurrence timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: NDS.spaceMD) {
            NotionEyebrow(text: "Timeline", count: occurrences.count)
            VStack(spacing: 2) {
                ForEach(occurrences) { occ in
                    occurrenceRow(occ)
                }
            }
        }
    }

    private func occurrenceRow(_ occ: Meeting) -> some View {
        Button {
            router.openMeeting(occ)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .scaledFont(12)
                    .foregroundStyle(NDS.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MeetingManager.entityDateString(occ.startDate))
                        .scaledFont(13, weight: .medium)
                        .foregroundStyle(NDS.textPrimary)
                    if let o = outcome(for: occ) {
                        Text(o)
                            .scaledFont(12)
                            .foregroundStyle(NDS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if occ.id == meeting.id {
                    Text("This one")
                        .scaledFont(10, weight: .bold)
                        .foregroundStyle(NDS.lilac)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(NDS.lilacSoft, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .scaledFont(10)
                    .foregroundStyle(NDS.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
            .ndsHover()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rolling open items

    private var openItemsSection: some View {
        VStack(alignment: .leading, spacing: NDS.spaceMD) {
            NotionEyebrow(text: "Open follow-ups", count: openItems.count)
            if openItems.isEmpty {
                emptyRow(systemImage: "checkmark.circle",
                         text: "Nothing open across the series.")
            } else {
                VStack(spacing: 2) {
                    ForEach(openItems, id: \.item.id) { pair in
                        openItemRow(pair.item, occurrenceDate: pair.date)
                    }
                }
            }
        }
    }

    private func openItemRow(_ item: ActionItem, occurrenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(NDS.priority(item.priority))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .scaledFont(13)
                    .foregroundStyle(NDS.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let owner = item.owner, !owner.isEmpty {
                        Text(owner)
                            .scaledFont(11)
                            .foregroundStyle(NDS.textSecondary)
                        Text("·").scaledFont(11).foregroundStyle(NDS.textTertiary)
                    }
                    Text("from \(shortDate(occurrenceDate))")
                        .scaledFont(11)
                        .foregroundStyle(NDS.textTertiary)
                    if let due = item.dueDate {
                        Text("· due \(shortDate(due))")
                            .scaledFont(11)
                            .foregroundStyle(NDS.due(due, status: item.status))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    // MARK: - Decisions ledger

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: NDS.spaceMD) {
            NotionEyebrow(text: "Decisions", count: seriesDecisions.count)
            if seriesDecisions.isEmpty {
                emptyRow(systemImage: "checkmark.seal",
                         text: "No decisions recorded yet for this series.")
            } else {
                VStack(spacing: 2) {
                    ForEach(seriesDecisions) { decision in
                        decisionRow(decision)
                    }
                }
            }
        }
    }

    private func decisionRow(_ decision: Decision) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .scaledFont(12)
                .foregroundStyle(NDS.mint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(decision.text)
                    .scaledFont(13)
                    .foregroundStyle(NDS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(shortDate(decision.date))
                    .scaledFont(11)
                    .foregroundStyle(NDS.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    // MARK: - Shared bits

    private func emptyRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .scaledFont(12)
                .foregroundStyle(NDS.textTertiary)
            Text(text)
                .scaledFont(12)
                .foregroundStyle(NDS.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius, style: .continuous))
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
