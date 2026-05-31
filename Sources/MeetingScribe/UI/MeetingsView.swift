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
    @EnvironmentObject var router: WorkspaceRouter

    /// The selected meeting is owned by `WorkspaceRouter` (D1-1) so opening a
    /// meeting from Today, search, a deep link, or a backlink all land in this
    /// one detail pane. Resolved from the unfiltered sources so an active search
    /// filter can't blank the open detail.
    private var selectedMeeting: Meeting? {
        guard let id = router.selectedMeetingID else { return nil }
        return (calendar.upcoming + manager.pastMeetings).first { $0.id == id }
    }
    @State private var search: String = ""
    // Default to upcoming-first and remember the user's last choice across
    // visits (was a transient `.all` @State that reset every time the tab
    // was rebuilt). Scope is a String-backed enum so @AppStorage can persist it.
    @AppStorage("meetings.scope") private var scope: Scope = .upcoming
    // List vs Month view inside the Meetings tab — re-exposes the month grid
    // (option B). Month mode is wired to `selectedMeeting`, not inline expand.
    @State private var listMode: ListMode = .list
    @State private var monthCursor = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    enum ListMode: String, CaseIterable, Identifiable {
        case list, month
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String { self == .list ? "list.bullet" : "calendar" }
    }

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
                if listMode == .list { meetingList } else { monthView }
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

            // List / Month view toggle — re-exposes the month grid (option B).
            Picker("", selection: $listMode) {
                ForEach(ListMode.allCases) { m in
                    Label(m.label, systemImage: m.systemImage).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12).padding(.bottom, 2)

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
            router.selectedMeetingID = m.id
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

    // MARK: - Month view (option B — re-exposed calendar)

    /// All meetings (past + upcoming, deduped), honoring the search box. Month
    /// mode ignores the scope pills — it always shows the whole calendar.
    private var calendarMeetings: [Meeting] {
        var seen = Set<String>()
        var out: [Meeting] = []
        for m in calendar.upcoming + manager.pastMeetings where seen.insert(m.id).inserted {
            if matches(m) { out.append(m) }
        }
        return out
    }

    private var monthView: some View {
        ScrollView {
            VStack(spacing: 0) {
                monthHeader
                weekdayRow
                monthGrid
                Divider().overlay(NDS.divider).padding(.vertical, 10)
                selectedDayList
            }
            .padding(.bottom, 16)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                .accessibilityLabel("Previous month")
            Spacer()
            Text(monthTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(NDS.textPrimary)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                .accessibilityLabel("Next month")
            Button {
                let t = Calendar.current.startOfDay(for: Date()); monthCursor = t; selectedDay = t
            } label: { Text("Today").font(.caption) }
                .buttonStyle(.plain).foregroundStyle(NDS.brand)
        }
        .foregroundStyle(NDS.textSecondary)
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NDS.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
    }
    private var weekdaySymbols: [String] {
        DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    }

    private var monthGrid: some View {
        let days = daysGrid(for: monthCursor)
        let cal = Calendar.current
        return VStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        if idx < days.count {
                            dayCell(days[idx],
                                    inMonth: cal.isDate(days[idx], equalTo: monthCursor, toGranularity: .month))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 4)
    }

    private func dayCell(_ day: Date, inMonth: Bool) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let hasMeetings = calendarMeetings.contains { cal.isDate($0.startDate, inSameDayAs: day) }
        return Button {
            selectedDay = cal.startOfDay(for: day)
            if !cal.isDate(day, equalTo: monthCursor, toGranularity: .month) { monthCursor = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(inMonth ? (isToday ? NDS.brand : NDS.textPrimary)
                                             : NDS.textTertiary.opacity(0.6))
                Circle().fill(hasMeetings ? NDS.brand : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? NDS.brand.opacity(0.18)
                                 : (isToday ? NDS.brand.opacity(0.06) : .clear)))
        }
        .buttonStyle(.plain)
    }

    private var selectedDayList: some View {
        let cal = Calendar.current
        let items = calendarMeetings
            .filter { cal.isDate($0.startDate, inSameDayAs: selectedDay) }
            .sorted { $0.startDate < $1.startDate }
        return VStack(alignment: .leading, spacing: 2) {
            Text(dayTitle).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NDS.textSecondary)
                .padding(.horizontal, 14).padding(.bottom, 4)
            if items.isEmpty {
                Text("No meetings this day").font(.caption)
                    .foregroundStyle(NDS.textTertiary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            } else {
                ForEach(items) { m in
                    Button { router.selectedMeetingID = m.id } label: {
                        MeetingListRow(meeting: m,
                                       isSelected: selectedMeeting?.id == m.id,
                                       isLive: manager.activeMeeting?.id == m.id)
                            .environmentObject(tagStore)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let n = Calendar.current.date(byAdding: .month, value: delta, to: monthCursor) { monthCursor = n }
    }
    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: monthCursor)
    }
    private var dayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return "Today" }
        if cal.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        if cal.isDateInYesterday(selectedDay) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: selectedDay)
    }
    private func daysGrid(for month: Date) -> [Date] {
        let cal = Calendar.current
        guard let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let leadDays = cal.component(.weekday, from: firstOfMonth) - 1
        guard let gridStart = cal.date(byAdding: .day, value: -leadDays, to: firstOfMonth) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                .pulsingSymbol(active: !reduceMotion)
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
