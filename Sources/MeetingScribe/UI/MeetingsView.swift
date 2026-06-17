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

    // MARK: Filters + saved views (C1-5)
    // Ad-hoc filter chips. Selecting a saved view just populates these (+ scope);
    // any manual change clears `activeSavedViewID` so the saved-view chip de-lights.
    @State private var filterTagID: String?
    @State private var filterSource: MeetingSource?
    @State private var filterRecordingOnly = false
    @State private var activeSavedViewID: String?
    @State private var showSaveSheet = false
    /// The saved-view array, JSON-encoded into a single String pref (matches the
    /// `meetings.scope` lightweight-pref idiom above).
    @AppStorage("meetings.savedViews") private var savedViewsJSON: String = ""

    private var savedViews: [SavedView] { SavedViewStore.decode(savedViewsJSON) }
    private var hasActiveFilters: Bool {
        filterTagID != nil || filterSource != nil || filterRecordingOnly
    }

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
                // Clear the translucent window toolbar (Tahoe) so the "Meetings"
                // title + counts aren't slid under it and clipped. Matches the
                // detail pane's top inset.
                Color.clear.frame(height: NDS.splitPaneTopInset)
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
        VStack(spacing: 6) {
            // Title row + search packed onto two lines instead of three. The
            // upcoming/past counts now sit beside the title as a muted suffix.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Meetings").font(NDS.title)
                Text("\(upcoming.count) upcoming · \(past.count) past")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)

            // Search bar — always visible (not hidden behind ⌘K)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .scaledFont(12)
                    .foregroundStyle(NDS.textTertiary)
                TextField("Search meetings…", text: $search)
                    .scaledFont(13)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(12)
                            .foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NDS.hairline, lineWidth: 1))
            .padding(.horizontal, 12)

            // List / Month view toggle
            Picker("", selection: $listMode) {
                ForEach(ListMode.allCases) { m in
                    Label(m.label, systemImage: m.systemImage).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)

            // Scope + filter chips
            scopeRow
            filterRow
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveViewSheet(
                scopeLabel: scope.label,
                tagName: filterTagID.flatMap { tagStore.tag(by: $0)?.name },
                sourceName: filterSource?.displayName,
                requiresRecording: filterRecordingOnly,
                onSave: { name in addSavedView(named: name); showSaveSheet = false },
                onCancel: { showSaveSheet = false }
            )
        }
    }

    private var scopeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Scope.allCases) { s in
                    MSFilterChip(label: s.label,
                                 active: scope == s && activeSavedViewID == nil) {
                        scope = s; activeSavedViewID = nil
                    }
                }
                if !savedViews.isEmpty {
                    Divider().frame(height: 16).overlay(NDS.divider)
                    ForEach(savedViews) { v in
                        MSFilterChip(label: v.name, active: activeSavedViewID == v.id) {
                            apply(v)
                        }
                        .contextMenu {
                            Button(role: .destructive) { deleteSavedView(v) } label: {
                                Label("Delete view", systemImage: "trash")
                            }
                        }
                    }
                }
                saveViewButton
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    private var saveViewButton: some View {
        Button { showSaveSheet = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").scaledFont(9)
                Text("Save view").font(NDS.tiny)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(NDS.fieldBg, in: Capsule())
            .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 1))
            .foregroundStyle(NDS.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(!hasActiveFilters)
        .opacity(hasActiveFilters ? 1 : 0.45)
        .help("Save the current filters as a one-click tab")
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagFilterMenu
                sourceFilterMenu
                MSFilterChip(label: "Has recording", active: filterRecordingOnly) {
                    filterRecordingOnly.toggle(); activeSavedViewID = nil
                }
                if hasActiveFilters {
                    Button { clearFilters() } label: {
                        Text("Clear").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 6)
    }

    private var tagFilterMenu: some View {
        Menu {
            Button("All tags") { filterTagID = nil; activeSavedViewID = nil }
            Divider()
            ForEach(tagStore.allTags) { t in
                Button {
                    filterTagID = t.id; activeSavedViewID = nil
                } label: {
                    if filterTagID == t.id { Label(t.name, systemImage: "checkmark") }
                    else { Text(t.name) }
                }
            }
        } label: {
            filterChipLabel(tagChipLabel, active: filterTagID != nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sourceFilterMenu: some View {
        Menu {
            Button("All sources") { filterSource = nil; activeSavedViewID = nil }
            Divider()
            ForEach(MeetingSource.allCases, id: \.self) { s in
                Button {
                    filterSource = s; activeSavedViewID = nil
                } label: {
                    if filterSource == s { Label(s.displayName, systemImage: "checkmark") }
                    else { Text(s.displayName) }
                }
            }
        } label: {
            filterChipLabel(sourceChipLabel, active: filterSource != nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var tagChipLabel: String {
        if let id = filterTagID, let t = tagStore.tag(by: id) { return t.name }
        return "Tag"
    }
    private var sourceChipLabel: String { filterSource?.displayName ?? "Source" }

    /// Capsule label that mirrors MSFilterChip's look for the menu-backed chips
    /// (MSFilterChip is a plain Button and can't host a Menu).
    private func filterChipLabel(_ text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).font(NDS.tiny)
            Image(systemName: "chevron.down").scaledFont(8)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(active ? NDS.brand.opacity(0.18) : NDS.fieldBg, in: Capsule())
        .overlay(Capsule().strokeBorder(active ? NDS.brand.opacity(0.5) : NDS.hairline,
                                        lineWidth: 1))
        .foregroundStyle(active ? NDS.brand : NDS.textSecondary)
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
        MSEmptyState(systemImage: "bubble.left.and.bubble.right",   // D4-2: was the People icon
                     title: search.isEmpty ? "No meetings yet" : "No matches",
                     message: "Meetings appear after you record a call, or when your calendar syncs.") {
            // Actionable empty state — don't dead-end the user. (UX9-1)
            if search.isEmpty {
                Button {
                    Task { await manager.startRecording(for: nil) }
                } label: {
                    Label("Record a meeting", systemImage: "record.circle")
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }
        }
    }

    private var meetingEmptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .scaledFont(48)
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
        // Free-text search (title + attendees).
        if !search.isEmpty {
            let q = search.lowercased()
            guard m.displayTitle.lowercased().contains(q)
                || m.attendees.contains(where: { $0.lowercased().contains(q) })
            else { return false }
        }
        // Saved-view / ad-hoc filter chips (C1-5).
        if let tagID = filterTagID, !tagStore.tagIDs(for: m).contains(tagID) {
            return false
        }
        if let source = filterSource, m.effectiveSource != source {
            return false
        }
        // `hasAudio` walks the meeting dir, so only pay that cost when the chip
        // is actually engaged.
        if filterRecordingOnly, !manager.hasAudio(for: m) {
            return false
        }
        return true
    }

    // MARK: - Saved views (C1-5)

    /// Apply a saved view's scope + filters in one click.
    private func apply(_ v: SavedView) {
        if let s = Scope(rawValue: v.scopeRaw) { scope = s }
        filterTagID = v.tagID
        filterSource = v.source
        filterRecordingOnly = v.requiresRecording
        activeSavedViewID = v.id
    }

    /// Snapshot the current scope + filter chips into a new named tab.
    private func addSavedView(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let v = SavedView(name: trimmed,
                          scopeRaw: scope.rawValue,
                          tagID: filterTagID,
                          source: filterSource,
                          requiresRecording: filterRecordingOnly)
        savedViewsJSON = SavedViewStore.encode(savedViews + [v])
        activeSavedViewID = v.id
    }

    private func deleteSavedView(_ v: SavedView) {
        savedViewsJSON = SavedViewStore.encode(savedViews.filter { $0.id != v.id })
        if activeSavedViewID == v.id { activeSavedViewID = nil }
    }

    /// Reset all ad-hoc filters (but not scope) and clear the active saved view.
    private func clearFilters() {
        filterTagID = nil
        filterSource = nil
        filterRecordingOnly = false
        activeSavedViewID = nil
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

    /// The currently-recording meeting's id (so NOW is shown regardless of the
    /// scope filter).
    private var liveMeetingID: String? {
        if case .recording = manager.state { return manager.activeMeeting?.id }
        return nil
    }

    /// Smart-grouped sections via the shared, tested `MeetingGrouping` (§3A):
    /// NOW / TODAY / UPCOMING TODAY / UPCOMING / PAST · RECORDED. The scope pills
    /// (All / Upcoming / Past) choose which meetings feed the grouping; a live
    /// recording is always pinned to NOW.
    private var groups: [(String, [Meeting])] {
        var source: [Meeting]
        switch scope {
        case .upcoming: source = upcoming
        case .past:     source = past
        case .all:      source = calendarMeetings
        }
        if let live = liveMeetingID, let m = manager.activeMeeting,
           !source.contains(where: { $0.id == m.id }) {
            source.insert(m, at: 0)
        }
        return MeetingGrouping.group(source, liveMeetingID: liveMeetingID)
            .map { ($0.section.title, $0.meetings) }
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
            Text(monthTitle).scaledFont(14, weight: .semibold).foregroundStyle(NDS.textPrimary)
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
                Text(s).scaledFont(9, weight: .semibold)
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
                    .font(.system(size: 11).monospacedDigit()) // design-lint:allow
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
            Text(dayTitle).scaledFont(12, weight: .semibold)
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
                .fill(isLive ? NDS.recording : .clear)
                .frame(width: 3)

            HStack(spacing: 10) {
                // Time column
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit()) // design-lint:allow
                        .foregroundStyle(isLive ? NDS.recording : NDS.textSecondary)
                    Text("\(durationMins)m")
                        .font(.system(size: 10).monospacedDigit()) // design-lint:allow
                        .foregroundStyle(NDS.textTertiary)
                }
                .frame(width: 52, alignment: .leading)

                // Title + meta
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if isLive {
                            Image(systemName: "record.circle.fill")
                                .scaledFont(10)
                                .foregroundStyle(.red)
                                .pulsingSymbol(active: !reduceMotion)
                        }
                        Text(meeting.displayTitle)
                            .scaledFont(13, weight: isSelected ? .semibold : .regular)
                            .foregroundStyle(NDS.textPrimary)
                            .lineLimit(1)
                            .help(meeting.displayTitle)
                        if (meeting.userTitle?.isEmpty ?? true),
                           !(meeting.autoTitle?.isEmpty ?? true) {
                            Image(systemName: "sparkles")
                                .scaledFont(9)
                                .foregroundStyle(NDS.textTertiary)
                                .help("Named automatically from the recording")
                        }
                        if meeting.seriesID?.isEmpty == false {
                            Image(systemName: "repeat")
                                .scaledFont(9)
                                .foregroundStyle(NDS.textTertiary)
                        }
                        if meeting.health?.status == .noTranscript {
                            Image(systemName: "xmark.circle")
                                .scaledFont(9)
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: 5) {
                        if !meeting.attendees.isEmpty {
                            Text("\(meeting.attendees.count) attendees")
                                .scaledFont(11)
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
