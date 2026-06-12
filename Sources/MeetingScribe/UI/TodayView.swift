import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The home view. Single column on the left:
///   1. Header (date + quick actions).
///   2. Action items from today + yesterday (compact widget).
///   3. NOW — the active recording, if any.
///   4. TODAY — today's calls only (past + upcoming).
///   5. Quick link to the Calendar tab for past/future calls.
///
/// A narrow Chat sidebar lives on the right. Sidebar is intentionally
/// secondary — action items and meeting cards are the primary focus.
@available(macOS 14.0, *)
struct TodayView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var decisions: DecisionStore
    @EnvironmentObject var actionItems: ActionItemStore
    @State private var showStandup = false

    /// Navigation is owned by `WorkspaceRouter` (D1-1): meeting cards route to
    /// the canonical Meetings-tab detail, and the widgets flip sections through
    /// it. Today no longer keeps its own pushed meeting detail.
    @EnvironmentObject var router: WorkspaceRouter

    var body: some View {
        feed
            .background(NDS.bg)
            .onAppear {
                calendar.refreshUpcoming()
                manager.refreshPastMeetings()
            }
            .task {
                // Defer the one-shot backfills (action items, people, search index,
                // embeddings, decisions) off the first-paint frame so Today renders
                // immediately. They're single-shot-per-session + off-main internally,
                // so a short delay is harmless. (V5 TT-2)
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                manager.backfillActionItemsIfNeeded()
                manager.backfillPeopleIfNeeded()
                manager.backfillSearchIndexIfNeeded()
                manager.backfillEmbeddingsIfNeeded()
                manager.backfillDecisionsIfNeeded()
            }
    }

    // MARK: - Feed (left column)

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                dayShapeStrip   // U3-3: the 7am coffee scan, answered in 10s
                quickActions
                upNextCard

                if isRecording { liveSection }

                // Overdue + due-today work, surfaced above meetings (TDY-2).
                NeedsAttentionWidget(store: manager.actionItems) {
                    router.section = .actions
                }

                if !todayUpcoming.isEmpty || !todayPast.isEmpty {
                    todaySection
                } else if !isRecording {
                    emptyState
                }

                ActionItemsWidget(store: manager.actionItems) {
                    router.section = .actions
                }

                // Forgotten follow-ups to send. (P2-6/U3-3)
                followUpsSection

                // Owe / Owed commitments split by direction. (U3-2/P2-7)
                commitmentsSection

                // Decision ledger — recent decisions across all meetings. (P1-1)
                decisionsSection

                // "On this day" — resurface meetings from prior weeks/months/
                // years on today's date. (C2-9/C2-6)
                onThisDaySection

                // Recent voice notes — the one surface Today never referenced. (TT-6)
                recentNotesSection

                // People suggestions below meetings — they're context, not actions
                SuggestedPeopleView()

                // "Stay connected" — overdue relationship check-ins with quick-log (Phase 2)
                StayConnectedSection { p in openPerson(p) }

                // "Stay in touch" — people you're drifting from (by last interaction).
                ReconnectView { p in openPerson(p) }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            // Full window width (req #5) — the feed is cards/lists, not prose,
            // so no reading-measure cap. (Prose panes keep their own measure.)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Follow-ups to send (P2-6/U3-3)

    @State private var followUpRefresh = 0   // bump to re-evaluate after marking sent

    private var pendingFollowUps: [Meeting] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        _ = followUpRefresh   // dependency so marking sent refreshes the list
        return manager.pastMeetings
            .filter { $0.startDate >= cutoff && !cal.isDateInToday($0.startDate) }
            .filter { !FollowUpStatus.isSent($0.id) }
            .sorted { $0.startDate > $1.startDate }
    }

    @ViewBuilder
    private var followUpsSection: some View {
        let items = pendingFollowUps
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane").foregroundStyle(NDS.brand)
                    Text("Follow-ups to send").scaledFont(15, weight: .semibold)
                }
                ForEach(items.prefix(4)) { m in
                    HStack(spacing: 8) {
                        Button { router.openMeeting(m) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayTitle).scaledFont(13, weight: .medium)
                                    .foregroundStyle(NDS.textPrimary).lineLimit(1)
                                Text(m.startDate, style: .date).scaledFont(11)
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("Mark sent") {
                            FollowUpStatus.setSent(m.id, true)
                            followUpRefresh += 1
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Commitments / Owe-Owed (U3-2/P2-7)

    private func isMine(_ owner: String) -> Bool {
        let o = owner.lowercased().trimmingCharacters(in: .whitespaces)
        if o == "me" || o == "i" { return true }
        let name = AppSettings.shared.userName.lowercased()
        if !name.isEmpty && o.contains(name) { return true }
        return AppSettings.shared.userNameAliases.contains { !$0.isEmpty && o.contains($0.lowercased()) }
    }

    @ViewBuilder
    private var commitmentsSection: some View {
        let open = actionItems.items.filter { $0.status != .completed && !($0.owner ?? "").isEmpty }
        let iOwe = open.filter { isMine($0.owner ?? "") }
        let owed = open.filter { !isMine($0.owner ?? "") }
        if !iOwe.isEmpty || !owed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(NDS.brand)
                    Text("Commitments").scaledFont(15, weight: .semibold)
                }
                commitmentColumn("You owe", items: iOwe)
                commitmentColumn("Owed to you", items: owed)
            }
        }
    }

    @ViewBuilder
    private func commitmentColumn(_ title: String, items: [ActionItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) (\(items.count))")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(items.prefix(3)) { item in
                    Button {
                        if let m = manager.meeting(forEntityID: item.meetingID) { router.openMeeting(m) }
                        else { router.section = .actions }
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.title).scaledFont(12)
                                .foregroundStyle(NDS.textPrimary).lineLimit(1)
                            Spacer()
                            if let owner = item.owner, !owner.isEmpty {
                                Text(owner).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Decision ledger (P1-1)

    @ViewBuilder
    private var decisionsSection: some View {
        let items = decisions.decisions
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal").foregroundStyle(NDS.brand)
                    Text("Recent decisions").scaledFont(15, weight: .semibold)
                }
                ForEach(items.prefix(5)) { d in
                    Button {
                        if let m = manager.meeting(forEntityID: d.meetingID) { router.openMeeting(m) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill").scaledFont(5)
                                .foregroundStyle(NDS.brand).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.text)
                                    .scaledFont(13)
                                    .foregroundStyle(NDS.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text("\(d.meetingTitle) · \(d.date.formatted(date: .abbreviated, time: .omitted))")
                                    .scaledFont(11)
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - On this day (C2-9/C2-6)

    /// Past meetings that fall on today's calendar date in a prior year (true
    /// anniversaries), or on a round "ago" milestone (~1 week / 1 month /
    /// 1 quarter / 1 year ago, ±1 day). Newest first.
    private var onThisDay: [Meeting] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.dateComponents([.month, .day], from: now)
        let startToday = cal.startOfDay(for: now)
        return manager.pastMeetings.filter { m in
            guard !cal.isDateInToday(m.startDate) else { return false }
            let c = cal.dateComponents([.month, .day], from: m.startDate)
            if c.month == today.month && c.day == today.day { return true }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: m.startDate),
                                          to: startToday).day ?? 0
            return [7, 30, 90, 365].contains { abs(days - $0) <= 1 }
        }
        .sorted { $0.startDate > $1.startDate }
    }

    @ViewBuilder
    private var onThisDaySection: some View {
        let items = onThisDay
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(NDS.brand)
                    Text("On this day").scaledFont(15, weight: .semibold)
                }
                ForEach(items.prefix(4)) { m in
                    Button { router.openMeeting(m) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayTitle)
                                    .scaledFont(13, weight: .medium)
                                    .foregroundStyle(NDS.textPrimary)
                                Text(agoString(m.startDate))
                                    .scaledFont(11)
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(10, weight: .semibold)
                                .foregroundStyle(NDS.textTertiary)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Human "N days/weeks/months/years ago" label.
    private func agoString(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        switch days {
        case 365...:  return "\(days / 365) year\(days / 365 == 1 ? "" : "s") ago"
        case 28...:   return "\(days / 30) month\(days / 30 == 1 ? "" : "s") ago"
        case 7...:    return "\(days / 7) week\(days / 7 == 1 ? "" : "s") ago"
        default:      return "\(days) days ago"
        }
    }

    // MARK: - Recent notes (TT-6)

    private var recentNotes: [QuickNote] {
        manager.quickNotes.sorted { $0.createdAt > $1.createdAt }.prefix(3).map { $0 }
    }

    @ViewBuilder
    private var recentNotesSection: some View {
        let notes = recentNotes
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Recent notes", systemImage: "waveform")
                        .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    Spacer()
                    Button("All") { router.select(.notes) }
                        .font(NDS.small).buttonStyle(.borderless)
                }
                ForEach(notes) { n in
                    Button { router.select(.notes) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform").foregroundStyle(NDS.brand.opacity(0.7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.title).scaledFont(13.5, weight: .medium).lineLimit(1)
                                if !n.snippet.isEmpty {
                                    Text(n.snippet).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayLong())
                    .scaledFont(30, weight: .heavy, relativeTo: .largeTitle, kind: .display)
                    .tracking(-0.8)
                    .foregroundStyle(.primary)
                Text(subtitleString())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showStandup = true } label: {
                Label("Standup", systemImage: "list.bullet.rectangle")
            }
            .help("Generate a daily standup: yesterday, today, open commitments")
        }
        .sheet(isPresented: $showStandup) {
            StandupDigestSheet(
                markdown: StandupDigest.markdown(manager: manager, calendar: calendar),
                isPresented: $showStandup)
        }
    }

    // MARK: - Quick actions

    /// Direction A — a tight, wrapping pill row instead of the old adaptive
    /// 5-card grid (which collapsed to a single-column wall at narrow widths).
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Primary action — full-width filled button (most common intent)
            if isRecording {
                Button {
                    Task { await manager.stopRecording() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill").scaledFont(16)
                        Text("Stop recording")
                            .scaledFont(14, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(MSDangerButtonStyle())
            } else {
                Button {
                    Task { await manager.startRecording(for: nil) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill").scaledFont(16)
                        Text("Record Meeting")
                            .scaledFont(14, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }

            // Secondary actions — compact pills
            FlowLayout(spacing: 8) {
                QuickPill(title: "Voice note", systemImage: "mic.fill",
                          tint: NDS.gold) {
                    Task { await manager.startQuickNote() }
                }
                QuickPill(title: "New task", systemImage: "checklist",
                          tint: NDS.mint) {
                    manager.actionItems.createTask(title: "New task")
                    router.section = .actions
                }
                QuickPill(title: "New page", systemImage: "doc.badge.plus",
                          tint: NDS.lilac) {
                    _ = manager.actionItems.createProject(name: "Untitled")
                    router.section = .actions
                }
            }
        }
    }

    /// "Up next" hero — the soonest upcoming meeting as a prominent glance with
    /// a one-tap Join & Record (req #3: make Today a better central hub).
    @ViewBuilder
    private var upNextCard: some View {
        if !isRecording, let m = nextMeeting {
            MSTintedHeaderCard(label: "Up next") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.displayTitle)
                            .scaledFont(16, weight: .bold, relativeTo: .headline, kind: .display)
                            .foregroundStyle(NDS.textPrimary).lineLimit(1)
                        Text(relativeStart(m))
                            .scaledFont(12).foregroundStyle(NDS.textSecondary)
                    }
                    Spacer()
                    if m.conferenceURL != nil {
                        Button { Task { await manager.switchToRecording(m) } } label: {
                            Label("Join & record", systemImage: "video.fill")
                        }
                        .buttonStyle(MSPrimaryButtonStyle())
                    }
                    Button { router.openMeeting(m) } label: {
                        Label("Open", systemImage: "chevron.right")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                }
            }
        }
    }

    /// The soonest upcoming meeting (prefers one with a conference link).
    private var nextMeeting: Meeting? {
        let future = calendar.upcoming
            .filter { $0.startDate > Date().addingTimeInterval(-5 * 60) }
            .sorted { $0.startDate < $1.startDate }
        return future.first { $0.conferenceURL != nil } ?? future.first
    }

    /// "Day shape" strip (U3-3): the whole day in one glanceable line —
    /// meetings remaining, overdue tasks, and when the next call is.
    @ViewBuilder
    private var dayShapeStrip: some View {
        let meetingsLeft = todayUpcoming.count
        let overdue = manager.actionItems.overdueTasks.count
        HStack(spacing: 14) {
            dayShapeItem(icon: "calendar",
                         value: "\(meetingsLeft)",
                         label: meetingsLeft == 1 ? "meeting left" : "meetings left",
                         color: NDS.brand)
            if overdue > 0 {
                dayShapeItem(icon: "exclamationmark.circle.fill",
                             value: "\(overdue)", label: "overdue", color: NDS.danger)
            }
            if let m = nextMeeting {
                let f = DateFormatter(); let _ = (f.dateFormat = "h:mm a")
                dayShapeItem(icon: "clock", value: f.string(from: m.startDate),
                             label: "next", color: NDS.gold)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
    }

    private func dayShapeItem(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).scaledFont(13).foregroundStyle(color)
            Text(value).scaledFont(15, weight: .bold).foregroundStyle(NDS.textPrimary)
            Text(label).scaledFont(12).foregroundStyle(NDS.textSecondary)
        }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Recording now")
            if let m = manager.activeMeeting {
                meetingCard(m, variant: .live)
            } else {
                MeetingCard(meeting: adhocPlaceholder(), variant: .live, onOpen: {})
                    .environmentObject(manager)
                    .environmentObject(tagStore)
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Today")
            ForEach(todayUpcoming) { m in
                meetingCard(m, variant: .upcoming)
            }
            ForEach(todayPast) { m in
                meetingCard(m, variant: .past)
            }
        }
    }

    private var calendarLink: some View {
        Button {
            router.section = .meetings  // Calendar absorbed into Meetings tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(NDS.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All past + upcoming calls")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NDS.textPrimary)
                    Text("Open the Calendar tab for the full list + month view")
                        .font(.caption).foregroundStyle(NDS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NDS.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NDS.fieldBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NDS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// A tappable meeting card. Clicking it pushes the full meeting detail onto
    /// the navigation stack (with a back arrow) instead of expanding inline.
    private func meetingCard(_ meeting: Meeting, variant: MeetingCard.Variant) -> some View {
        MeetingCard(meeting: meeting,
                    variant: variant,
                    onOpen: { router.openMeeting(meeting) })
            .environmentObject(manager)
            .environmentObject(tagStore)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .scaledFont(36).foregroundStyle(.secondary)
            Text("Nothing on today's calendar").font(.headline)
            Text("Use a quick action above, or import an existing recording.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                importMeeting()
            } label: { Label("Import meeting recording", systemImage: "square.and.arrow.down") }
            .buttonStyle(UntitledSecondaryButtonStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private func importMeeting() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a meeting audio file to import, transcribe, and summarize"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await manager.importMeeting(from: url) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    // MARK: - Data

    private var isRecording: Bool {
        if case .recording = manager.state { return true }
        return false
    }

    private var todayUpcoming: [Meeting] {
        let cal = Calendar.current
        return calendar.upcoming
            .filter { cal.isDateInToday($0.startDate) && $0.startDate > Date().addingTimeInterval(-60) }
            .sorted { $0.startDate < $1.startDate }
    }

    private var todayPast: [Meeting] {
        let cal = Calendar.current
        return manager.pastMeetings
            .filter { cal.isDateInToday($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    private func relativeStart(_ m: Meeting) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Starts " + f.localizedString(for: m.startDate, relativeTo: Date())
    }

    private func todayLong() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private func subtitleString() -> String {
        let parts = [
            todayUpcoming.count > 0 ? "\(todayUpcoming.count) upcoming today" : nil,
            todayPast.count > 0 ? "\(todayPast.count) earlier today" : nil
        ].compactMap { $0 }
        if parts.isEmpty {
            return "Nothing on the calendar today"
        }
        return parts.joined(separator: " · ")
    }

    /// Jump to the People tab and open a specific person (used by the "Stay in
    /// touch" nudges). Deterministic via the router (D1-3) — no asyncAfter race
    /// against the People tab mounting.
    private func openPerson(_ p: Person) {
        router.openPerson(p.id)
    }

    private func adhocPlaceholder() -> Meeting {
        Meeting(id: UUID().uuidString,
                title: "Ad-hoc Recording",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                attendees: [], notes: nil, location: nil,
                conferenceURL: nil, calendarName: nil, seriesID: nil,
                userDescription: nil, userTitle: nil,
                isImpromptu: true, segmentCount: 0)
    }
}

// MARK: - Pill button used in the header

@available(macOS 14.0, *)
struct ToolbarPillButton: View {
    enum Prominence { case primary, secondary }
    let label: String
    let systemImage: String
    let prominence: Prominence
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.callout.weight(.semibold))
                Text(label).font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 0.5))
            .foregroundStyle(foreground)
            .shadow(color: shadow, radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.15, dampingFraction: 0.85), value: hovering)
        .onHover { hovering = $0 }
    }

    private var background: AnyShapeStyle {
        switch prominence {
        case .primary:   return AnyShapeStyle(NDS.accentGradient)
        case .secondary: return AnyShapeStyle(NDS.fieldBg)
        }
    }
    private var foreground: Color {
        prominence == .primary ? NDS.onAccent : .primary
    }
    private var borderColor: Color {
        prominence == .primary ? .clear : NDS.hairline
    }
    private var shadow: Color {
        prominence == .primary ? NDS.accent.opacity(0.32) : .clear
    }
}
