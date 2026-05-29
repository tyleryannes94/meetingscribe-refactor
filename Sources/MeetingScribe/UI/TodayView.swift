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

    /// Hosted (the MainWindow owns the selected top-level section) so the
    /// "open all action items" button can flip to that tab.
    @Binding var section: TopLevelSection
    /// The meeting the user clicked into — drives a NavigationStack push to the
    /// full meeting detail (with a system back arrow). Replaces inline expand/collapse.
    @State private var selectedMeeting: Meeting?

    var body: some View {
        NavigationStack {
            feed
                .background(NDS.bg)
                // Click a card → push the full detail page with a back arrow.
                // No more inline 520pt expansion that shoved the feed around.
                .navigationDestination(isPresented: Binding(
                    get: { selectedMeeting != nil },
                    set: { if !$0 { selectedMeeting = nil } }
                )) {
                    if let m = selectedMeeting { meetingDetail(for: m) }
                }
        }
        .onAppear {
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
            manager.backfillActionItemsIfNeeded()
            manager.backfillPeopleIfNeeded()
        }
    }

    // MARK: - Feed (left column)

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickActions
                upNextCard

                if isRecording { liveSection }

                if !todayUpcoming.isEmpty || !todayPast.isEmpty {
                    todaySection
                } else if !isRecording {
                    emptyState
                }

                ActionItemsWidget(store: manager.actionItems) {
                    section = .actions
                }

                // People suggestions below meetings — they're context, not actions
                SuggestedPeopleView()

                // "Stay in touch" — people you're drifting from (by last interaction).
                ReconnectView { p in openPerson(p) }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            // Was 920 — left wide empty gutters on large displays (req #5).
            // Widened so Today fills more of the window without going full-bleed.
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayLong())
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                Text(subtitleString())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
                        Image(systemName: "stop.circle.fill").font(.system(size: 16))
                        Text("Stop recording")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(MSDangerButtonStyle())
            } else {
                Button {
                    Task { await manager.startRecording(for: nil) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill").font(.system(size: 16))
                        Text("Record Meeting")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }

            // Secondary actions — compact pills
            FlowLayout(spacing: 8) {
                QuickPill(title: "Voice note", systemImage: "mic.fill",
                          tint: NDS.selectColor("orange")) {
                    Task { await manager.startQuickNote() }
                }
                QuickPill(title: "New task", systemImage: "checklist",
                          tint: NDS.selectColor("green")) {
                    manager.actionItems.createTask(title: "New task")
                    section = .actions
                }
                QuickPill(title: "New page", systemImage: "doc.badge.plus",
                          tint: NDS.brand) {
                    _ = manager.actionItems.createProject(name: "Untitled")
                    section = .actions
                }
            }
        }
    }

    /// "Up next" hero — the soonest upcoming meeting as a prominent glance with
    /// a one-tap Join & Record (req #3: make Today a better central hub).
    @ViewBuilder
    private var upNextCard: some View {
        if !isRecording, let m = nextMeeting {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UP NEXT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NDS.brand).tracking(0.6)
                    Text(m.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NDS.textPrimary).lineLimit(1)
                    Text(relativeStart(m))
                        .font(.system(size: 12)).foregroundStyle(NDS.textSecondary)
                }
                Spacer()
                if m.conferenceURL != nil {
                    Button { Task { await manager.switchToRecording(m) } } label: {
                        Label("Join & record", systemImage: "video.fill")
                    }
                    .buttonStyle(MSPrimaryButtonStyle())
                }
                Button { selectedMeeting = m } label: {
                    Label("Open", systemImage: "chevron.right")
                }
                .buttonStyle(MSSecondaryButtonStyle())
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NDS.fieldBg))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(NDS.brand.opacity(0.3), lineWidth: 1))
        }
    }

    /// The soonest upcoming meeting (prefers one with a conference link).
    private var nextMeeting: Meeting? {
        let future = calendar.upcoming
            .filter { $0.startDate > Date().addingTimeInterval(-5 * 60) }
            .sorted { $0.startDate < $1.startDate }
        return future.first { $0.conferenceURL != nil } ?? future.first
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
            section = .meetings  // Calendar absorbed into Meetings tab
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
                    onOpen: { selectedMeeting = meeting })
            .environmentObject(manager)
            .environmentObject(tagStore)
    }

    /// Full-page meeting detail pushed onto the Today navigation stack. Matches
    /// the environment objects the Meetings tab injects so the detail behaves
    /// identically from either entry point.
    @ViewBuilder
    private func meetingDetail(for meeting: Meeting) -> some View {
        UnifiedMeetingDetail(mode: detailMode(for: meeting))
            .environmentObject(manager)
            .environmentObject(manager.recordingMonitor)
            .environmentObject(tagStore)
            .environmentObject(calendar)
            .environmentObject(manager.actionItems)
            .environmentObject(manager.pipelineController)
    }

    private func detailMode(for m: Meeting) -> UnifiedMeetingDetail.Mode {
        if manager.activeMeeting?.id == m.id { return .live }
        return m.startDate > Date() ? .upcoming(m) : .past(m)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 36)).foregroundStyle(.secondary)
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
            .font(.system(size: 13, weight: .semibold))
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

    /// Jump to the People tab and open a specific person (used by the
    /// "Stay in touch" nudges). Small delay lets the People tab mount and
    /// register its notification listener before we post.
    private func openPerson(_ p: Person) {
        section = .people
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .meetingScribeOpenPerson,
                                            object: nil, userInfo: ["id": p.id])
        }
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
        case .primary:   return AnyShapeStyle(Color.accentColor)
        case .secondary: return AnyShapeStyle(Color(NSColor.controlBackgroundColor))
        }
    }
    private var foreground: Color {
        prominence == .primary ? .white : .primary
    }
    private var borderColor: Color {
        prominence == .primary ? .clear : Color(NSColor.separatorColor)
    }
    private var shadow: Color {
        prominence == .primary ? Color.accentColor.opacity(0.2) : .clear
    }
}
