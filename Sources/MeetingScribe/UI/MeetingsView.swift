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
        return (manager.pastMeetings + calendar.upcoming + calendar.rangeEvents).first { $0.id == id }
    }
    @State private var search: String = ""
    // Default to "All" so the user immediately sees today's calls (upcoming +
    // recorded) without first tapping a pill. The user's last choice still
    // persists across visits. Scope is a String-backed enum so @AppStorage can
    // store it; the `.v2` key resets everyone to the new All default once.
    @AppStorage("meetings.scope.v2") private var scope: Scope = .all
    // List vs Week view inside the Meetings tab. Week mode is wired to
    // `selectedMeeting`, not inline expand.
    @State private var listMode: ListMode = .list
    @State private var weekOffset: Int = 0

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
        case list, week
        var id: String { rawValue }
        var label: String {
            switch self {
            case .list: return "List"
            case .week: return "Week"
            }
        }
        var systemImage: String { self == .list ? "list.bullet" : "calendar" }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case all, upcoming, past
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        // Prototype model (MeetingScribe.dc.html): a single centred column that
        // shows the time-grouped list, and swaps to the full-page meeting detail
        // when one is selected (mList vs mDetail) — not a persistent split view.
        Group {
            if let m = selectedMeeting {
                detailFullPage(m)
            } else {
                protoListPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NDS.bg)
        .onAppear {
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            calendar.fetchRange(from: today, to: tomorrow)
        }
    }

    // MARK: - Prototype list pane (centred single column)

    private var protoListPane: some View {
        VStack(spacing: 0) {
            // Fixed header so search, the List/Calendar toggle, and the scope
            // tabs stay put while the list scrolls underneath.
            protoHeader
            Divider().overlay(NDS.divider)
            if listMode == .week {
                weekView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(sortedGroups, id: \.0) { title, items in
                            if !items.isEmpty {
                                protoGroup(title: title, items: items)
                            }
                        }
                        if sortedGroups.allSatisfy({ $0.1.isEmpty }) { emptyState }
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 1000, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    /// Fixed top section of the Meetings list: big title + counts, a
    /// List/Calendar view toggle, an always-visible search bar, and the large
    /// All / Upcoming / Past scope tabs.
    private var protoHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: NDS.splitPaneTopInset)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Meetings")
                        .scaledFont(30, weight: .heavy, relativeTo: .largeTitle, kind: .display)
                        .tracking(-0.8)
                        .foregroundStyle(NDS.textPrimary)
                    Text("\(todayCount) today · \(past.count) recorded")
                        .scaledFont(13.5).foregroundStyle(NDS.textSecondary)
                }
                Spacer(minLength: 0)
                // List ↔ Calendar (week) view toggle.
                Picker("", selection: $listMode) {
                    ForEach(ListMode.allCases) { m in
                        Label(m.label, systemImage: m.systemImage).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            protoSearchBar
            protoScopeTabs
        }
        .padding(.horizontal, 36)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Always-visible search field (filters title + attendees via `matches`).
    private var protoSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .scaledFont(13).foregroundStyle(NDS.textTertiary)
            TextField("Search meetings…", text: $search)
                .textFieldStyle(.plain)
                .scaledFont(14)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(13).foregroundStyle(NDS.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(NDS.hairline, lineWidth: 1))
    }

    /// Large, full-width All / Upcoming / Past tabs (replaces the tiny chips).
    private var protoScopeTabs: some View {
        HStack(spacing: 8) {
            ForEach(Scope.allCases) { s in
                Button { scope = s } label: {
                    Text(s.label)
                        .scaledFont(15, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(scope == s ? NDS.accent : NDS.fieldBg,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .foregroundStyle(scope == s ? NDS.onAccent : NDS.textSecondary)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(scope == s ? Color.clear : NDS.hairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func protoGroup(title: String, items: [Meeting]) -> some View {
        let clean = title.replacingOccurrences(of: "● ", with: "").uppercased()
        let isNow = clean.hasPrefix("NOW")
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                if isNow {
                    Circle().fill(NDS.danger).frame(width: 9, height: 9)
                }
                Text(clean)
                    .scaledFont(10, weight: .bold).tracking(1)
                    .foregroundStyle(isNow ? NDS.danger : NDS.textTertiary)
            }
            .padding(.horizontal, 6).padding(.bottom, 11)
            VStack(spacing: 0) {
                ForEach(items) { m in
                    Button { router.selectedMeetingID = m.id } label: {
                        MeetingProtoRow(meeting: m,
                                        isLive: manager.activeMeeting?.id == m.id,
                                        variant: variant(for: m))
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(NDS.divider)
                }
            }
        }
    }

    // MARK: - Full-page detail (with back-to-list breadcrumb)

    @ViewBuilder
    private func detailFullPage(_ m: Meeting) -> some View {
        let variant = variant(for: m)
        VStack(spacing: 0) {
            Color.clear.frame(height: NDS.splitPaneTopInset)
            // Breadcrumb back row (prototype: "← Meetings / <title>").
            HStack(spacing: 10) {
                Button { router.selectedMeetingID = nil } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left").scaledFont(11, weight: .semibold)
                        Text("Meetings").scaledFont(12.5, weight: .semibold)
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .foregroundStyle(NDS.textSecondary)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(NDS.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text("/").scaledFont(12.5).foregroundStyle(NDS.textTertiary)
                Text(m.displayTitle).scaledFont(12.5, weight: .semibold)
                    .foregroundStyle(NDS.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26).padding(.vertical, 11)
            Divider().overlay(NDS.divider)
            UnifiedMeetingDetail(mode: detailMode(m, variant: variant))
                .environmentObject(manager)
                .environmentObject(manager.recordingMonitor)
                .environmentObject(manager.tagStore)
                .environmentObject(calendar)
                .environmentObject(manager.actionItems)
                .environmentObject(manager.pipelineController)
                .id(m.id)
        }
    }

    @available(*, deprecated, message: "Replaced by the prototype single-column pane")
    private var legacyBody: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            VStack(spacing: 0) {
                Color.clear.frame(height: NDS.splitPaneTopInset)
                listHeader
                Divider().overlay(NDS.divider)
                if listMode == .list { meetingList } else { weekView }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            .background(NDS.sidebarBg)

        } detail: {
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
            // Also pull today's earlier calls (refreshUpcoming now starts from
            // startOfDay, but rangeEvents warms the list view too).
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            calendar.fetchRange(from: today, to: tomorrow)
        }
    }

    // MARK: - List header

    private var listHeader: some View {
        VStack(spacing: 6) {
            // Title row + search packed onto two lines instead of three. The
            // upcoming/past counts now sit beside the title as a muted suffix.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Meetings").scaledFont(22, weight: .bold, kind: .display)
                Text("\(todayCount) today · \(past.count) recorded")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)

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
                                 active: scope == s && activeSavedViewID == nil,
                                 tint: NDS.accent) {
                        scope = s; activeSavedViewID = nil
                    }
                }
                if !savedViews.isEmpty {
                    Divider().frame(height: 16).overlay(NDS.divider)
                    ForEach(savedViews) { v in
                        MSFilterChip(label: v.name, active: activeSavedViewID == v.id,
                                     tint: NDS.accent) {
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

    /// Sort groups so "Today" and "NOW" sections always appear first, then the rest
    /// in original MeetingGrouping order.
    private var sortedGroups: [(String, [Meeting])] {
        let todayFirst = groups.sorted { a, b in
            let aFirst = a.0 == "NOW" || a.0 == "TODAY" || a.0 == "UPCOMING TODAY"
            let bFirst = b.0 == "NOW" || b.0 == "TODAY" || b.0 == "UPCOMING TODAY"
            if aFirst != bFirst { return aFirst }
            return false  // preserve original relative order otherwise
        }
        return todayFirst
    }

    private var meetingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(sortedGroups, id: \.0) { title, items in
                    if !items.isEmpty {
                        let clean = title.replacingOccurrences(of: "● ", with: "")
                        let isNow = clean.uppercased().hasPrefix("NOW")
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if isNow {
                                    Circle().fill(NDS.recording).frame(width: 7, height: 7)
                                }
                                Text(clean.uppercased())
                                    .font(NDS.sectionLabel).tracking(0.8)
                                    .foregroundStyle(isNow ? NDS.recording : NDS.textTertiary)
                                Text("\(items.count)")
                                    .font(NDS.tiny.monospacedDigit())
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            ForEach(items) { m in
                                meetingRow(m)
                            }
                        }
                    }
                }
                if sortedGroups.allSatisfy({ $0.1.isEmpty }) { emptyState }
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

    /// Meetings happening today (calendar upcoming + recorded), for the comp
    /// header subline "N today · N recorded".
    private var todayCount: Int {
        let cal = Calendar.current
        let up = calendar.upcoming.filter { cal.isDateInToday($0.startDate) }.count
        let recorded = manager.pastMeetings.filter { cal.isDateInToday($0.startDate) }.count
        return up + recorded
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

    // MARK: - Week view

    /// All meetings from all sources (upcoming, past recorded, and any
    /// on-demand range fetches), deduped by ID. calendar.upcoming is
    /// preferred over rangeEvents when IDs collide (upcoming has fresher
    /// metadata like title overrides). pastMeetings wins over both for
    /// meetings that have been recorded (has the on-disk data).
    private var calendarMeetings: [Meeting] {
        var seen = Set<String>()
        var out: [Meeting] = []
        // pastMeetings first so recorded meetings keep their on-disk metadata
        for m in manager.pastMeetings + calendar.upcoming + calendar.rangeEvents
            where seen.insert(m.id).inserted {
            if matches(m) { out.append(m) }
        }
        return out
    }

    var weekStart: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        // Start from Monday (weekday=2 in Gregorian; weekday=1 is Sunday)
        let daysFromMonday = (weekday + 5) % 7  // days since last Monday
        return cal.date(byAdding: .day, value: -daysFromMonday + (weekOffset * 7), to: today) ?? today
    }

    var weekDays: [Date] {
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var weekRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let startStr = fmt.string(from: weekStart)
        let startMonth = Calendar.current.component(.month, from: weekStart)
        let endMonth = Calendar.current.component(.month, from: endDate)
        fmt.dateFormat = startMonth == endMonth ? "d, yyyy" : "MMM d, yyyy"
        let endStr = fmt.string(from: endDate)
        return "\(startStr) – \(endStr)"
    }

    func meetingsOnDay(_ day: Date) -> [Meeting] {
        let cal = Calendar.current
        return calendarMeetings.filter { cal.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Trigger an EventKit fetch for the currently-displayed week so that
    /// unrecorded calendar events (no folder on disk) appear in the week view.
    private func fetchCurrentWeek() {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        calendar.fetchRange(from: weekStart, to: end)
    }

    var weekView: some View {
        VStack(spacing: 0) {
            // Header: prev / week range / next / Today
            HStack(spacing: 12) {
                Button { weekOffset -= 1 } label: {
                    Image(systemName: "chevron.left").scaledFont(13, weight: .semibold)
                }
                .buttonStyle(.borderless)
                Text(weekRangeLabel)
                    .font(.callout.weight(.semibold))
                    .frame(minWidth: 180, alignment: .center)
                Button { weekOffset += 1 } label: {
                    Image(systemName: "chevron.right").scaledFont(13, weight: .semibold)
                }
                .buttonStyle(.borderless)
                if weekOffset != 0 {
                    Button("Today") { weekOffset = 0 }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            // Day columns
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(weekDays, id: \.self) { day in
                        weekDayColumn(day)
                        if day != weekDays.last { Divider() }
                    }
                }
                .frame(minWidth: 560)
            }
        }
        .onAppear { fetchCurrentWeek() }
        .onChange(of: weekOffset) { _, _ in fetchCurrentWeek() }
    }

    private static let weekDayNameFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let weekDayNumberFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let weekMeetingTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    @ViewBuilder func weekDayColumn(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let meetings = meetingsOnDay(day)
        VStack(alignment: .leading, spacing: 0) {
            // Day header
            VStack(spacing: 2) {
                Text(MeetingsView.weekDayNameFormatter.string(from: day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                Text(MeetingsView.weekDayNumberFormatter.string(from: day))
                    .font(.title3.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isToday ? Color.accentColor.opacity(0.12) : Color.clear)
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            Divider()
            // Meeting pills
            if meetings.isEmpty {
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(meetings) { m in
                            Button { router.openMeeting(m) } label: {
                                weekMeetingPill(m)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(minWidth: 80, maxWidth: .infinity)
    }

    @ViewBuilder func weekMeetingPill(_ m: Meeting) -> some View {
        let isPast = m.startDate < Date()
        VStack(alignment: .leading, spacing: 2) {
            Text(MeetingsView.weekMeetingTimeFormatter.string(from: m.startDate))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isPast ? Color.secondary : Color.accentColor)
            Text(m.displayTitle)
                .font(.caption)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPast ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
            isPast ? Color.secondary.opacity(0.2) : Color.accentColor.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Compact list row (replaces the full MeetingCard in the list pane)

/// A dense, compact list row for the Meetings list pane.
/// Shows just enough: time, title, attendee count, status dot.
/// The full MeetingCard with actions is used in TodayView.
@available(macOS 14.0, *)
/// Full-width meeting row matching `MeetingScribe.dc.html` (Meetings list):
/// live dot · tabular time (74pt) · title + "dur · source" · attendee stack ·
/// status badge · chevron. Used by the prototype single-column list.
@available(macOS 14.0, *)
private struct MeetingProtoRow: View {
    let meeting: Meeting
    let isLive: Bool
    let variant: MeetingCard.Variant

    var body: some View {
        HStack(spacing: 14) {
            if isLive {
                Circle().fill(NDS.danger).frame(width: 9, height: 9)
            }
            Text(timeString)
                .scaledFont(13, weight: .bold).monospacedDigit()
                .foregroundStyle(NDS.textSecondary)
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                    .scaledFont(15, weight: .semibold).foregroundStyle(NDS.textPrimary)
                    .lineLimit(1)
                Text(metaLine)
                    .scaledFont(12).foregroundStyle(NDS.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !meeting.attendees.isEmpty {
                MSAvatarStack(names: attendeeNames, size: 24, max: 3)
            }
            statusBadge
            Image(systemName: "chevron.right")
                .scaledFont(13).foregroundStyle(NDS.textTertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch variant {
        case .live:
            HStack(spacing: 5) {
                Circle().fill(NDS.danger).frame(width: 8, height: 8)
                Text("Live").scaledFont(11, weight: .heavy)
            }
            .foregroundStyle(NDS.danger)
        case .upcoming:
            Text("Scheduled")
                .scaledFont(10.5, weight: .bold).foregroundStyle(NDS.sky)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(NDS.sky.opacity(0.16), in: Capsule())
        case .past:
            HStack(spacing: 4) {
                Image(systemName: "sparkles").scaledFont(10)
                Text("Summary").scaledFont(10.5, weight: .bold)
            }
            .foregroundStyle(NDS.mint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(NDS.mint.opacity(0.16), in: Capsule())
        }
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: meeting.startDate)
    }
    private var metaLine: String {
        let mins = max(0, Int(meeting.endDate.timeIntervalSince(meeting.startDate) / 60))
        let src = meeting.effectiveSource?.displayName
        return [mins > 0 ? "\(mins)m" : nil, src].compactMap { $0 }.joined(separator: " · ")
    }
    private var attendeeNames: [String] {
        meeting.attendees.map { raw in
            let id = PersonResolver.parse(raw)
            return id.hasName ? id.name : PersonResolver.localPart(of: id.email)
        }
    }
}

private struct MeetingListRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let isLive: Bool

    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var actionItems: ActionItemStore
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

                    HStack(spacing: 6) {
                        if !meeting.attendees.isEmpty {
                            // P1-7: face pile instead of "3 attendees" — scan who
                            // the meeting is with at a glance, matching MeetingCard.
                            MSAvatarStack(names: attendeeNames, size: 16, max: 3)
                        }
                        // T8: a past meeting with open follow-ups doesn't read
                        // as "done" — same badge MeetingCard already shows in
                        // the upcoming rail.
                        if openTaskCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "checklist").scaledFont(9)
                                Text("\(openTaskCount)").scaledFont(10)
                            }
                            .foregroundStyle(NDS.brand)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(NDS.brand.opacity(0.10), in: Capsule())
                            .help("\(openTaskCount) unfinished follow-up\(openTaskCount == 1 ? "" : "s")")
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

    private var openTaskCount: Int {
        // Match MeetingCard's "past meeting with open tasks" cue. Cheap O(n)
        // on the in-memory store; the list pane never holds enough rows for
        // this to register on a profile.
        guard meeting.startDate < Date() else { return 0 }
        return actionItems.items(for: meeting.id).filter { $0.status != .completed }.count
    }

    private var attendeeNames: [String] {
        meeting.attendees.map { raw in
            let id = PersonResolver.parse(raw)
            return id.hasName ? id.name : PersonResolver.localPart(of: id.email)
        }
    }
}
