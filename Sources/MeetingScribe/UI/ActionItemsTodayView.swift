import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Today scratchpad (1-3)
    //
    // Today is the home view you land on when opening Tasks. It's a daily
    // scratchpad built for momentum: a left "quick capture" column for ripping
    // off tasks in rapid succession (anything you add is pinned to today so it
    // doesn't vanish), and a right "brain dump" column where the local AI turns
    // free-text into tasks — suggesting a project, priority, and due date — or
    // sketches a focus plan for the day.

    /// Narrows a task list to the active workspace context (1-2). nil context
    /// ("All") passes everything through.
    func contextFiltered(_ list: [ActionItem]) -> [ActionItem] {
        guard let cid = env.activeContextID else { return list }
        return list.filter { store.effectiveContextID(for: $0) == cid }
    }

    /// Count that drives the sidebar "Today" badge: overdue + due-today.
    var todayCount: Int {
        contextFiltered(store.overdueTasks).count + contextFiltered(store.myDayTasks).count
    }

    @ViewBuilder
    var todayPane: some View {
        VStack(spacing: 0) {
            todayScratchHeader
            todayUpNextStrip
            Divider().overlay(NDS.divider)
            HStack(spacing: 0) {
                todayCaptureColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(NDS.divider)
                todayBrainDumpColumn
                    .frame(width: 420)
            }
            .frame(maxHeight: .infinity)
            Divider().overlay(NDS.divider)
            todayBoardSection
        }
    }

    // MARK: Header

    private var todayScratchHeader: some View {
        let open = todayOpenTasks.count
        let overdue = contextFiltered(store.overdueTasks).count
        let meetingsToday = todayUpcomingMeetings.count
        let dueToday = contextFiltered(store.myDayTasks).count
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                // Comp greeting: big Bricolage display title that changes by time
                // of day, with a meta line summarizing the day.
                Text(Self.greeting()).scaledFont(31, weight: .heavy, kind: .display)
                Text(Self.todaySubtitle(meetings: meetingsToday, due: dueToday))
                    .font(NDS.body).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if overdue > 0 { stat(label: "Overdue", value: overdue, color: NDS.selectColor("red")) }
                stat(label: "Open", value: open, color: NDS.brand)
            }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
    }

    /// Today's upcoming calendar meetings (the comp's "Up next").
    var todayUpcomingMeetings: [Meeting] {
        let cal = Calendar.current
        return calendar.upcoming
            .filter { cal.isDateInToday($0.startDate) && $0.endDate >= Date() }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Horizontal "Up next" strip of today's meetings above the scratchpad.
    @ViewBuilder
    private var todayUpNextStrip: some View {
        let meetings = todayUpcomingMeetings
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Up next").font(NDS.sectionLabel).tracking(0.6)
                    .foregroundStyle(NDS.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(meetings.prefix(6)) { m in todayMeetingCard(m) }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
        }
    }

    private func todayMeetingCard(_ m: Meeting) -> some View {
        Button { router.openMeeting(m) } label: {
            HStack(spacing: 11) {
                Text(Self.meetingTime(m.startDate))
                    .scaledFont(12, weight: .bold).monospacedDigit()
                    .foregroundStyle(NDS.textSecondary)
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.displayTitle).font(NDS.body).fontWeight(.semibold).lineLimit(1)
                        .foregroundStyle(NDS.textPrimary)
                    Text("\(Self.durationLabel(m)) · \(m.attendees.count) attendees")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(width: 300, alignment: .leading)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            .overlay(RoundedRectangle(cornerRadius: NDS.radius).strokeBorder(NDS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func greeting(now: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: now)
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Still up?"
        }
    }

    static func todaySubtitle(meetings: Int, due: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        var parts = [f.string(from: Date())]
        parts.append("\(meetings) meeting\(meetings == 1 ? "" : "s") today")
        parts.append("\(due) task\(due == 1 ? "" : "s") due")
        return parts.joined(separator: " · ")
    }

    static func meetingTime(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }

    static func durationLabel(_ m: Meeting) -> String {
        let mins = max(0, Int(m.endDate.timeIntervalSince(m.startDate) / 60))
        if mins >= 60 { let h = mins / 60, r = mins % 60; return r == 0 ? "\(h)h" : "\(h)h \(r)m" }
        return "\(mins)m"
    }

    /// Everything you could be working on: open + in-progress, non-triage,
    /// scoped to the active context, smart-sorted (overdue floats to the top).
    var todayOpenTasks: [ActionItem] {
        contextFiltered(store.items.filter { !$0.needsTriage && $0.status != .completed })
            .sorted { sort($0, $1) }
    }

    // MARK: Left — quick capture

    private var todayCaptureColumn: some View {
        let items = todayOpenTasks
        return VStack(spacing: 0) {
            todayQuickAddRow
            if items.isEmpty {
                todayCaptureEmpty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("All tasks")
                                .scaledFont(13, weight: .semibold).foregroundStyle(.secondary)
                                .textCase(.uppercase).tracking(0.6)
                            Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.bottom, 2)
                        // Right-click any row to set priority / due / labels / project
                        // without opening it; a single click opens the editor drawer.
                        ForEach(items) { item in
                            row(for: item)
                                .draggable(item.id)
                                .taskQuickActions(item: item, store: store) { env.selectedTaskID = item.id }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var todayQuickAddRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").scaledFont(15).foregroundStyle(NDS.brand)
            TextField("Add a task — try “Email Sarah friday !high +Marketing”", text: $todayQuickAddText)
                .textFieldStyle(.plain).font(NDS.body)
                .focused($todayQuickAddFocused)
                .onSubmit { commitTodayQuickAdd() }
                .dictationPrefersPolished(id: "tasks.today.quickAdd", focused: todayQuickAddFocused)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        .overlay(RoundedRectangle(cornerRadius: NDS.radius).strokeBorder(NDS.hairline, lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var todayCaptureEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").scaledFont(34).foregroundStyle(NDS.selectColor("green"))
            Text("Nothing on deck yet").scaledFont(15, weight: .semibold)
            Text("Jot tasks above as they come to mind, or brain-dump on the right and let AI sort them.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: Bottom — status board

    /// The set the Today board shows: open + in-progress, plus tasks completed
    /// today (so the Done column reflects today's wins instead of vanishing).
    var todayBoardTasks: [ActionItem] {
        contextFiltered(store.items.filter { item in
            guard !item.needsTriage else { return false }
            if item.status != .completed { return true }
            if let c = item.completedAt, Calendar.current.isDateInToday(c) { return true }
            return false
        })
    }

    func todayBoardColumnItems(_ status: ActionItem.Status) -> [ActionItem] {
        todayBoardTasks.filter { $0.status == status }
            .sorted { a, b in
                let sa = a.sortIndex ?? .greatestFiniteMagnitude
                let sb = b.sortIndex ?? .greatestFiniteMagnitude
                if sa != sb { return sa < sb }
                return sort(a, b)
            }
    }

    /// Drag-to-status reorder for the Today board (mirrors `dropCard`, scoped to
    /// the Today set so neighbors come from the right column).
    func dropTodayCard(_ id: String, toStatus status: ActionItem.Status, beforeID: String?) {
        guard id != beforeID, store.items.contains(where: { $0.id == id }) else { return }
        let col = todayBoardColumnItems(status).filter { $0.id != id }
        let targetIndex: Int = {
            if let beforeID, let idx = col.firstIndex(where: { $0.id == beforeID }) { return idx }
            return col.count
        }()
        let prev = targetIndex > 0 ? col[targetIndex - 1].sortIndex : nil
        let next = targetIndex < col.count ? col[targetIndex].sortIndex : nil
        let newIndex: Double = {
            switch (prev, next) {
            case let (p?, n?): return (p + n) / 2
            case let (p?, nil): return p + 1
            case let (nil, n?): return n - 1
            case (nil, nil): return 0
            }
        }()
        if store.items.first(where: { $0.id == id })?.status != status { store.setStatus(id, status: status) }
        store.setSortIndex(id, sortIndex: newIndex)
    }

    private var todayBoardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.split.3x1").scaledFont(13).foregroundStyle(NDS.brand)
                Text("Board").scaledFont(14, weight: .bold)
                Text("Drag to organize").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(ActionItem.Status.allCases) { status in
                        StatusBoardColumn(parent: self, store: store, status: status,
                                          items: todayBoardColumnItems(status),
                                          onDrop: { id, beforeID in
                                              dropTodayCard(id, toStatus: status, beforeID: beforeID)
                                          },
                                          onAdd: {
                                              let t = store.createTask(title: "New task", projectID: nil, status: status)
                                              PinnedToday.toggle(t.id, in: &pinnedTodayCSV)
                                              env.selectedTaskID = t.id
                                          })
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .frame(height: 320)
    }

    // MARK: Right — Brain Dump callout
    //
    // The free-text brain-dump that used to live here has been promoted to a
    // first-class page (TopLevelSection.brainDump, ⌘6) with URL ingestion, web
    // search, calendar suggestions, and session persistence. This narrow
    // column is now a CTA that opens the page; the rest of the AI surface
    // lives on the BrainDumpView.

    private var todayBrainDumpColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "brain.head.profile.fill")
                    .scaledFont(14).foregroundStyle(NDS.brand)
                Text("Brain Dump").scaledFont(15, weight: .bold)
            }
            Text("Dump everything on your mind — thoughts, links, daily briefs — and the planner turns it into tasks and calendar focus blocks.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NotificationCenter.default.post(name: .meetingScribeOpenBrainDump, object: nil)
            } label: {
                Label("Open Brain Dump", systemImage: "arrow.up.forward.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MSPrimaryButtonStyle())

            Text("Tip: Press ⌘6 anywhere to jump there.")
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)

            Divider().overlay(NDS.divider).padding(.vertical, 4)

            HStack(spacing: 7) {
                Image(systemName: "wand.and.stars").scaledFont(14).foregroundStyle(NDS.brand)
                Text("Organize my Tasks").scaledFont(15, weight: .bold)
            }
            Text("Let AI review your current tasks and suggest fixes — reschedule overdue, fix priorities, group loose tasks into projects — applied only on your sign-off.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                taskOrganizer.reset()
                showOrganizer = true
            } label: {
                Label("Organize my Tasks", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MSSecondaryButtonStyle())

            Spacer()
        }
        .padding(16)
        .sheet(isPresented: $showOrganizer) {
            TaskOrganizerView(organizer: taskOrganizer, store: store,
                              onClose: { showOrganizer = false })
        }
    }

    // MARK: Actions

    func commitTodayQuickAdd() {
        let raw = todayQuickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let t = store.createTask(parsing: raw, projectID: nil)
        // Anything captured here belongs to today until it's done.
        PinnedToday.toggle(t.id, in: &pinnedTodayCSV)
        todayQuickAddText = ""
        Task { @MainActor in todayQuickAddFocused = true }
    }

    static func todayDateString() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

