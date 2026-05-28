import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A focused, friendly list of every meeting — upcoming and past — grouped
/// into Upcoming / Today / Earlier. Cleaner and more navigable than the
/// Calendar tab's list mode. Cards expand inline to the full detail.
@available(macOS 14.0, *)
struct MeetingsView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var tagStore: TagStore

    @State private var expandedID: String?
    @State private var search: String = ""
    @State private var scope: Scope = .all

    enum Scope: String, CaseIterable, Identifiable {
        case all, upcoming, past
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NDS.divider)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.0) { title, items in
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                NotionEyebrow(text: title, count: items.count)
                                ForEach(items) { m in cardWithDetail(m) }
                            }
                        }
                    }
                    if groups.allSatisfy({ $0.1.isEmpty }) { emptyState }
                }
                .padding(.horizontal, 28).padding(.vertical, 18)
                .frame(maxWidth: 940, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(NDS.bg)
        .onAppear {
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Meetings").font(NDS.title).lineLimit(1)
                Text("\(upcoming.count) upcoming · \(past.count) past")
                    .font(NDS.small).foregroundStyle(NDS.textSecondary).lineLimit(1)
            }
            .layoutPriority(0)
            Spacer(minLength: 12)
            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 180)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder).frame(minWidth: 90, maxWidth: 220)
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2").font(.system(size: 34)).foregroundStyle(NDS.textTertiary)
            Text(search.isEmpty ? "No meetings yet" : "No matches")
                .font(.headline)
            Text("Recorded and upcoming calendar meetings show up here.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: - Data

    private func matches(_ m: Meeting) -> Bool {
        guard !search.isEmpty else { return true }
        let q = search.lowercased()
        return m.displayTitle.lowercased().contains(q)
            || m.attendees.contains { $0.lowercased().contains(q) }
    }

    private var upcoming: [Meeting] {
        let now = Date().addingTimeInterval(-60)
        return calendar.upcoming
            .filter { $0.startDate > now && matches($0) }
            .sorted { $0.startDate < $1.startDate }
    }
    private var past: [Meeting] {
        manager.pastMeetings.filter(matches).sorted { $0.startDate > $1.startDate }
    }

    private var groups: [(String, [Meeting])] {
        let cal = Calendar.current
        let todayUpcoming = upcoming.filter { cal.isDateInToday($0.startDate) }
        let laterUpcoming = upcoming.filter { !cal.isDateInToday($0.startDate) }
        let todayPast = past.filter { cal.isDateInToday($0.startDate) }
        let earlierPast = past.filter { !cal.isDateInToday($0.startDate) }
        switch scope {
        case .upcoming:
            return [("Today", todayUpcoming), ("Upcoming", laterUpcoming)]
        case .past:
            return [("Today", todayPast), ("Earlier", earlierPast)]
        case .all:
            return [("Upcoming", laterUpcoming),
                    ("Today", todayUpcoming + todayPast),
                    ("Earlier", earlierPast)]
        }
    }

    // MARK: - Card + inline detail (shared pattern)

    @ViewBuilder
    private func cardWithDetail(_ meeting: Meeting) -> some View {
        let variant = variant(for: meeting)
        let expanded = expandedID == meeting.id
        VStack(spacing: 0) {
            MeetingCard(meeting: meeting, variant: variant, isExpanded: expanded,
                        onOpen: { expandedID = expanded ? nil : meeting.id })
                .environmentObject(manager)
                .environmentObject(tagStore)
            if expanded {
                VStack(spacing: 0) {
                    UnifiedMeetingDetail(mode: detailMode(meeting, variant: variant))
                        .environmentObject(manager)
                        .environmentObject(tagStore)
                        .environmentObject(calendar)
                    HStack {
                        Spacer()
                        Button { expandedID = nil } label: {
                            Label("Collapse", systemImage: "chevron.up").font(.caption)
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .padding(.vertical, 6).padding(.trailing, 10)
                    }
                }
                .frame(minHeight: 520)
                .padding(.top, 8).padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: expanded)
    }

    private func variant(for m: Meeting) -> MeetingCard.Variant {
        if manager.activeMeeting?.id == m.id { return .live }
        return m.startDate < Date() ? .past : .upcoming
    }
    private func detailMode(_ m: Meeting, variant: MeetingCard.Variant) -> UnifiedMeetingDetail.Mode {
        if variant == .live { return .live }
        return variant == .upcoming ? .upcoming(m) : .past(m)
    }
}
