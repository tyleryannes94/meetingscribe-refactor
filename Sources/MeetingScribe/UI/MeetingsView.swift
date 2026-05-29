import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Meetings tab — 2-column NavigationSplitView.
/// Left: scrollable meeting list with search + scope filter.
/// Right: full-page UnifiedMeetingDetail for the selected meeting.
///
/// Replaces the old inline-expand accordion pattern. Meetings now open
/// as proper full-height pages with breathing room and a dedicated layout —
/// not cramped expansions inside a list.
@available(macOS 14.0, *)
struct MeetingsView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var recordingMonitor: RecordingMonitor

    @State private var selectedMeeting: Meeting?
    @State private var search: String = ""
    // Default to upcoming-first and remember the user's last choice across
    // visits (was a transient `.all` @State that reset every time the tab
    // was rebuilt). Scope is a String-backed enum so @AppStorage can persist it.
    @AppStorage("meetings.scope") private var scope: Scope = .upcoming

    enum Scope: String, CaseIterable, Identifiable {
        case all, upcoming, past
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // MARK: Left pane — meeting list
            VStack(spacing: 0) {
                listHeader
                Divider().overlay(NDS.divider)
                meetingList
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            .background(NDS.sidebarBg)

        } detail: {
            // MARK: Right pane — meeting detail (full page)
            if let m = selectedMeeting {
                let variant = variant(for: m)
                UnifiedMeetingDetail(mode: detailMode(m, variant: variant))
                    .environmentObject(manager)
                    .environmentObject(manager.recordingMonitor)
                    .environmentObject(manager.tagStore)
                    .environmentObject(calendar)
                    .environmentObject(manager.actionItems)
                    .environmentObject(manager.pipelineController)
                    .id(m.id)  // re-create view when selection changes
            } else {
                meetingEmptyDetail
            }
        }
        .background(NDS.bg)
        .onAppear {
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
        }
    }

    // MARK: - List header

    private var listHeader: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meetings").font(NDS.title)
                    Text("\(upcoming.count) upcoming · \(past.count) past")
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 0)

            // Search bar — always visible (not hidden behind ⌘K)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(NDS.textTertiary)
                TextField("Search meetings…", text: $search)
                    .font(.system(size: 13))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NDS.hairline, lineWidth: 1))
            .padding(.horizontal, 12)

            // Scope filter pills
            HStack(spacing: 6) {
                ForEach(Scope.allCases) { s in
                    Button { scope = s } label: {
                        Text(s.label)
                            .font(.system(size: 11.5, weight: scope == s ? .semibold : .regular))
                            .foregroundStyle(scope == s ? NDS.brand : NDS.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(scope == s ? NDS.brand.opacity(0.12) : .clear,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }

    // MARK: - Meeting list

    private var meetingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { title, items in
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            NotionEyebrow(text: title, count: items.count)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            ForEach(items) { m in
                                meetingRow(m)
                            }
                        }
                    }
                }
                if groups.allSatisfy({ $0.1.isEmpty }) { emptyState }
            }
            .padding(.bottom, 20)
        }
    }

    private func meetingRow(_ m: Meeting) -> some View {
        let isSelected = selectedMeeting?.id == m.id
        let isLive = manager.activeMeeting?.id == m.id
        return Button {
            selectedMeeting = m
        } label: {
            MeetingListRow(meeting: m, isSelected: isSelected, isLive: isLive)
                .environmentObject(tagStore)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 32))
                .foregroundStyle(NDS.textTertiary)
            Text(search.isEmpty ? "No meetings yet" : "No matches")
                .font(.headline)
            Text("Meetings appear after you record a call, or when your calendar syncs.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 20)
    }

    private var meetingEmptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48))
                .foregroundStyle(NDS.textTertiary)
            Text("Select a meeting")
                .font(.title2.weight(.semibold))
                .foregroundStyle(NDS.textSecondary)
            Text("Choose a meeting from the list to view its transcript, summary, notes, and action items.")
                .font(NDS.body)
                .foregroundStyle(NDS.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NDS.bg)
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

    private func variant(for m: Meeting) -> MeetingCard.Variant {
        if manager.activeMeeting?.id == m.id { return .live }
        return m.startDate < Date() ? .past : .upcoming
    }
    private func detailMode(_ m: Meeting, variant: MeetingCard.Variant) -> UnifiedMeetingDetail.Mode {
        if variant == .live { return .live }
        return variant == .upcoming ? .upcoming(m) : .past(m)
    }
}

// MARK: - Compact list row (replaces the full MeetingCard in the list pane)

/// A dense, compact list row for the Meetings list pane.
/// Shows just enough: time, title, attendee count, status dot.
/// The full MeetingCard with actions is used in TodayView.
@available(macOS 14.0, *)
private struct MeetingListRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let isLive: Bool

    @EnvironmentObject var tagStore: TagStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Live indicator bar
            Rectangle()
                .fill(isLive ? Color.red : .clear)
                .frame(width: 3)

            HStack(spacing: 10) {
                // Time column
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(isLive ? .red : NDS.textSecondary)
                    Text("\(durationMins)m")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(NDS.textTertiary)
                }
                .frame(width: 52, alignment: .leading)

                // Title + meta
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if isLive {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, options: .repeating)
                        }
                        Text(meeting.displayTitle)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(NDS.textPrimary)
                            .lineLimit(1)
                        if meeting.seriesID?.isEmpty == false {
                            Image(systemName: "repeat")
                                .font(.system(size: 9))
                                .foregroundStyle(NDS.textTertiary)
                        }
                        if meeting.health?.status == .noTranscript {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: 5) {
                        if !meeting.attendees.isEmpty {
                            Text("\(meeting.attendees.count) attendees")
                                .font(.system(size: 11))
                                .foregroundStyle(NDS.textTertiary)
                        }
                        let tags = tagStore.tags(for: meeting).prefix(2)
                        ForEach(Array(tags)) { t in
                            TagChipMini(tag: t)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Status indicator
                statusDot
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(isSelected ? NDS.brand.opacity(0.10)
                    : isHovered ? NDS.rowHover : .clear)
        )
        .overlay(alignment: .bottom) {
            if !isSelected {
                Divider()
                    .overlay(NDS.divider)
                    .padding(.leading, 75)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    @ViewBuilder
    private var statusDot: some View {
        if isLive {
            Circle().fill(Color.red).frame(width: 7, height: 7)
        } else if let h = meeting.health {
            switch h.status {
            case .ok:           Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)
            case .partial:      Circle().fill(Color.orange.opacity(0.7)).frame(width: 7, height: 7)
            case .noTranscript: Circle().fill(Color.red.opacity(0.7)).frame(width: 7, height: 7)
            case .fallbackUsed: Circle().fill(Color.yellow.opacity(0.7)).frame(width: 7, height: 7)
            }
        } else if meeting.startDate > Date() {
            // Upcoming — no status dot
            EmptyView()
        } else {
            Circle().fill(NDS.textTertiary.opacity(0.3)).frame(width: 7, height: 7)
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: meeting.startDate)
    }
    private var durationMins: Int {
        max(0, Int(meeting.endDate.timeIntervalSince(meeting.startDate) / 60))
    }
}
