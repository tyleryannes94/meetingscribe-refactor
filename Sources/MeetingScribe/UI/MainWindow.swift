import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Top-level navigation sections. Collapsed from 7 → 5:
/// - Calendar absorbed into Meetings (accessible via the Upcoming tab)
/// - Integrations moved to Settings (⚙️ gear icon at bottom of rail)
/// - Notes kept as Voice Notes (distinct enough from Meetings to warrant its own slot)
enum TopLevelSection: String, CaseIterable, Identifiable, Hashable {
    case today, meetings, people, actions, notes, decisions, integrations
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today:    return "Today"
        case .meetings: return "Meetings"
        case .people:   return "People"
        case .actions:  return "Tasks"
        case .notes:    return "Voice Notes"
        case .decisions: return "Decisions"
        case .integrations: return "Integrations"
        }
    }
    var systemImage: String {
        switch self {
        case .today:    return "sun.max.fill"
        // D2-8: Meetings carried People's glyph (person.2.fill vs person.2),
        // making the two most-used tabs visual twins. Meetings = recorded
        // conversations, so it wears a conversation glyph; People keeps person.2.
        case .meetings: return "bubble.left.and.bubble.right.fill"
        case .people:   return "person.2.fill"
        case .actions:  return "checklist"
        case .notes:    return "waveform.badge.plus"
        case .decisions: return "checkmark.seal.fill"
        case .integrations: return "puzzlepiece.extension.fill"
        }
    }
    /// Which nav group this section belongs to (for section headers in the rail).
    var group: NavGroup {
        switch self {
        case .today, .meetings, .people: return .workspace
        case .actions, .notes, .decisions, .integrations: return .organize
        }
    }
}

enum NavGroup: String {
    case workspace = "WORKSPACE"
    case organize  = "ORGANIZE"
}

@available(macOS 14.0, *)
struct MainWindow: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var chatSession: ChatSession

    @EnvironmentObject var router: WorkspaceRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The selected top-level section now lives in `WorkspaceRouter` (D1-1) so
    /// search, deep links, and backlinks all drive one navigation surface. This
    /// computed accessor keeps the existing `section` / `section = …` call sites
    /// unchanged.
    private var section: TopLevelSection {
        get { router.section }
        nonmutating set { router.section = newValue }
    }
    @State private var activeSheet: ActiveSheet?
    /// The ⌘K command palette presents as a floating, blurred, spring-in surface
    /// (C3-2) — a Raycast-grade overlay, not a system sheet.
    @State private var showSearch = false
    @State private var showWeeklyReview = false   // 3-F
    /// "New meeting" quick sheet (§1) + in-flight audio import flag.
    @State private var showNewMeeting = false
    @State private var importingMeeting = false
    // Default the assistant rail CLOSED — new users land on a full-width app
    // instead of a chat panel that crowds content (and confuses first-run users
    // with an empty assistant). Existing users keep their stored preference.
    @AppStorage("chatRailVisible") private var chatVisible = false
    /// First-launch onboarding — pre-explains every macOS permission BEFORE
    /// the system dialog so a "Don't Allow" tap doesn't silently strand the
    /// user (audit 8.3). Shown once and then never again per `hasCompletedOnboarding`.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showOnboarding: Bool = false
    /// First-run AI-stack readiness (D3-1). Presented automatically when the
    /// whisper model or Ollama isn't ready, so a non-technical user never hits a
    /// raw shell command before their first recording.
    @StateObject private var setup = SetupReadiness()
    /// Offer the Setup Check at most once per launch so it never nags.
    @State private var setupCheckOffered = false
    /// Sections built so far. Today is always pre-built; the persisted section
    /// is also included so the keep-alive ZStack renders it on first paint.
    @State private var visited: Set<TopLevelSection> = {
        let raw = UserDefaults.standard.string(forKey: "mainWindow.lastSelectedSection") ?? ""
        let persisted = TopLevelSection(rawValue: raw) ?? .today
        return [.today, persisted]
    }()

    /// Keep-alive tabs: each section is built lazily the first time it's
    /// opened, then kept in the hierarchy and shown/hidden via opacity.
    /// A short cross-fade (0.15 s) smooths the transition.
    private var tabContent: some View {
        ZStack {
            ForEach(TopLevelSection.allCases) { s in
                if visited.contains(s) {
                    tabView(for: s)
                        .opacity(section == s ? 1 : 0)
                        .animation(NDS.motion(NDS.springStandard, reduce: reduceMotion), value: section)
                        .allowsHitTesting(section == s)
                        .zIndex(section == s ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Permanent top clearance for EVERY tab/page so content can never sit
        // flush against (and be clipped by) the translucent window toolbar — no
        // matter what layout a tab uses internally. One source of truth here
        // means no tab has to remember to pad its own top.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: NDS.tabTopInset)
        }
        .onChange(of: section) { _, s in
            visited.insert(s)
        }
    }

    // MARK: - Left navigation rail

    private var navRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand: coral→lilac gradient mark tile + Bricolage wordmark
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .scaledFont(14, weight: .bold)
                    .foregroundStyle(NDS.avatarText)
                    .frame(width: 26, height: 26)
                    .background(NDS.brandMarkGradient,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: NDS.accent.opacity(0.30), radius: 7, y: 4)
                Text("MeetingScribe")
                    .scaledFont(15.5, weight: .bold, relativeTo: .headline, kind: .display)
                    .tracking(-0.3)
                Spacer()
            }
            .padding(.horizontal, NDS.spaceLG).padding(.top, NDS.spaceLG).padding(.bottom, NDS.spaceSM)

            navGroupLabel(NavGroup.workspace.rawValue)
            ForEach(TopLevelSection.allCases.filter { $0.group == .workspace }) { s in
                navItem(s)
            }

            Spacer().frame(height: 4)

            navGroupLabel(NavGroup.organize.rawValue)
            ForEach(TopLevelSection.allCases.filter { $0.group == .organize }) { s in
                navItem(s)
            }

            Spacer()
            Divider().overlay(NDS.divider).padding(.horizontal, NDS.spaceLG).padding(.bottom, NDS.spaceSM)

            // Bottom row: search + settings. The Light/Dark toggle was removed
            // (C3-4) — the app follows the system appearance like a native Mac app.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button { showSearch = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").scaledFont(11)
                        Text("⌘K").font(NDS.tiny)
                    }
                    .foregroundStyle(NDS.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(NDS.hairline, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search everything (⌘K)")

                // Settings gear (replaces the old Integrations nav item).
                // Uses SwiftUI's SettingsLink — the supported way to open the
                // Settings scene. The previous `NSApp.sendAction(Selector(
                // ("showSettingsWindow:")))` hack silently no-ops on some macOS
                // versions / when the app isn't frontmost, which is why this
                // button "didn't trigger".
                SettingsGearButton()
            }
            .padding(.horizontal, NDS.spaceLG).padding(.bottom, NDS.spaceMD)
        }
        .frame(width: 240)  // increased from 216
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NDS.sidebarBg)
    }

    /// When a meeting is actively recording, the time it started (drives the
    /// in-app recording dock). nil = not recording a meeting.
    private var meetingRecordingStartedAt: Date? {
        if case .recording(_, let startedAt) = manager.state { return startedAt }
        return nil
    }

    /// The page-tailored primary toolbar action for the current section (§1).
    private var primaryToolbarButton: ToolbarModel.Button? {
        ToolbarModel.items(for: section).compactMap {
            if case .button(let b) = $0, b.style == .primary { return b } else { return nil }
        }.first
    }

    /// Wire each toolbar action to app behavior.
    private func runToolbarAction(_ action: ToolbarModel.Action) {
        switch action {
        case .search:       showSearch = true
        case .addPerson:    activeSheet = .addPerson
        case .voiceNote, .newVoiceNote:
            // Toggle: start, or stop if a voice note is already recording.
            if case .recording = manager.quickRecordState {
                Task { await manager.stopQuickNote() }
            } else {
                Task { await manager.startQuickNote() }
            }
        case .record:
            Task { await manager.startRecording(for: nil) }
        case .newMeeting:
            showNewMeeting = true
        case .stopRecording:
            Task { await manager.stopRecording() }
        case .newTask:
            section = .actions
            _ = manager.actionItems.createTask(title: "New task")
        case .importCalendar:
            Task { await calendar.requestAccess() }
            calendar.refreshUpcoming(force: true)
        case .importPeople:
            importPeopleFromFile()
        case .filter:
            section = .actions   // the Tasks tab owns the filter UI
        }
    }

    @ViewBuilder
    private func toolbarItemView(_ item: ToolbarModel.Item) -> some View {
        switch item {
        case .divider:
            Divider()
        case .button(let b):
            Button { runToolbarAction(b.action) } label: {
                Label(b.label, systemImage: b.systemImage).labelStyle(.titleAndIcon)
            }
            .tint(b.style == .primary ? NDS.accent : (b.style == .recording ? NDS.danger : nil))
            .help(b.label)
        }
    }

    /// Overflow ⋯ menu: the less-common controls that left the main bar.
    private var overflowMenu: some View {
        Menu {
            if importingMeeting {
                Label("Importing…", systemImage: "clock")
            } else {
                Button { importMeeting() } label: {
                    Label("Import meeting…", systemImage: "square.and.arrow.down")
                }
            }
            if let live = calendar.upcoming.first(where: { $0.isJoinableWindow && $0.conferenceURL != nil }) {
                Button { Task { await manager.switchToRecording(live) } } label: {
                    Label("Join & record “\(live.displayTitle)”", systemImage: "video.fill")
                }
            }
            Button { refreshAll() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            if !manager.transcribingMeetingIDs.isEmpty {
                Divider()
                Label("\(manager.transcribingMeetingIDs.count) finalizing", systemImage: "clock")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More actions")
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
        importingMeeting = true
        Task { await manager.importMeeting(from: url); importingMeeting = false }
    }

    private func refreshAll() {
        calendar.refreshUpcoming(force: true)
        manager.refreshPastMeetings(force: true)
        manager.refreshQuickNotes()
    }

    private func importPeopleFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Import contacts from a .vcf (vCard) or .csv file"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let candidates = FileContactImporter.candidates(fromFileAt: url)
        guard !candidates.isEmpty else {
            ToastCenter.shared.show("No contacts found in that file")
            return
        }
        let r = PeopleStore.shared.importPeople(candidates)
        ToastCenter.shared.show("Imported \(r.created) new · \(r.merged) merged")
    }

    private func navGroupLabel(_ text: String) -> some View {
        Text(text)
            .scaledFont(9, weight: .semibold)
            .tracking(0.6)
            .foregroundStyle(NDS.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }

    private func navItem(_ s: TopLevelSection) -> some View {
        NavRailItem(section: s, selected: section == s,
                    badge: railBadge(for: s)) { section = s }
    }

    /// State-bearing rail (D1-1): a glanceable count/pulse per section so users
    /// stop opening tabs "to check if anything needs me".
    private func railBadge(for s: TopLevelSection) -> NavRailItem.Badge {
        switch s {
        case .meetings:
            let finalizing = manager.transcribingMeetingIDs.count
            return finalizing > 0 ? .pulse(finalizing) : .none
        case .actions:
            let overdue = manager.actionItems.overdueTasks.count
            return overdue > 0 ? .count(overdue, NDS.danger) : .none
        case .people:
            let drifting = PeopleStore.shared.overdueCheckInCount
            return drifting > 0 ? .count(drifting, NDS.gold) : .none
        case .today, .notes, .decisions, .integrations:
            return .none
        }
    }

    private func navActionRow(_ title: String, systemImage: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).scaledFont(13).foregroundStyle(NDS.textSecondary).frame(width: 18)
                Text(title).scaledFont(13).foregroundStyle(NDS.textSecondary)
                Spacer(minLength: 0)
                Text("⌘K").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.bottom, 8)
    }

    private func contextLabel(_ s: TopLevelSection) -> String {
        switch s {
        case .today:    return "The Today home — today's meetings, quick actions, and open action items."
        case .meetings: return "The Meetings list — all past and upcoming meetings/calls."
        case .people:   return "People — your second-brain contacts, searchable by name and event tag."
        case .actions:  return "The Tasks workspace — initiatives, projects (pages), and tasks."
        case .notes:    return "Voice Notes — recorded/imported notes with transcripts."
        case .decisions: return "Decisions — the searchable decision ledger with rationale and people."
        case .integrations: return "Integrations — set up, edit, and test every connector the app uses."
        }
    }

    /// The floating, blurred, spring-in command palette (C3-2). A Raycast-grade
    /// overlay: dimmed backdrop, glass card pinned near the top, click-out /
    /// Escape to dismiss.
    @ViewBuilder
    private var searchPalette: some View {
        if showSearch {
            ZStack(alignment: .top) {
                // Dimmed backdrop — click to dismiss.
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { showSearch = false }
                    .transition(.opacity)

                GlobalSearchView(isPresented: $showSearch, onOpen: handleEntity)
                    .environmentObject(manager)
                    .frame(maxWidth: 600)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
                        .strokeBorder(NDS.hairline, lineWidth: 1))
                    .ndsElevation(.modal)
                    .padding(.top, 96)
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -8)))
            }
            .animation(NDS.motion(.spring(response: 0.30, dampingFraction: 0.82), reduce: reduceMotion), value: showSearch)
        }
    }

    @ViewBuilder
    private func tabView(for s: TopLevelSection) -> some View {
        switch s {
        case .today:    TodayView()
        case .meetings: MeetingsView()
        case .people:   PeopleListView()
        case .actions:  ActionItemsView(store: manager.actionItems)
        case .notes:    QuickNotesView()
        case .decisions: DecisionLedgerView()
        case .integrations: IntegrationsView()
        }
    }

    // (Removed in the perf rebuild: `prewarmOtherTabs` was building every
    // non-default tab in the background during the first 3 seconds — which
    // competed for the main thread with the user's first-impression render
    // of the default tab. The new pattern is: tabs build on first selection.
    // Combined with the warm `MeetingStore` index cache + `MeetingBodyCache`,
    // a freshly-selected tab is already instant without prewarming.)

    /// Sheet slot for the global search palette and the add-person sheet.
    /// Meetings no longer open in a sheet (D1-1) — they route to the Meetings
    /// tab detail via `WorkspaceRouter`.
    enum ActiveSheet: Identifiable {
        case addPerson
        case setup
        var id: String {
            switch self {
            case .addPerson: return "addPerson"
            case .setup: return "setup"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Auto-collapse the chat rail when the window is too narrow to fit
            // all three panes comfortably. The user's toggle preference is
            // preserved — the rail returns when there's room again.
            let showChat = chatVisible && geo.size.width >= 860
            HStack(spacing: 0) {
                navRail
                Divider().overlay(NDS.divider)
                // Clip + minWidth:0 so the widest kept-alive tab can't inflate
                // the middle pane's minimum and push the nav rail off-screen.
                tabContent
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .bloomAmbientGlow()   // subtle coral corner light (Bloom)
                    // In-app meeting recording dock (§2A) — never a hover overlay.
                    .overlay(alignment: .bottomTrailing) {
                        if let startedAt = meetingRecordingStartedAt,
                           RecordingPresentation.showsMeetingDock(isRecordingMeeting: true, section: section) {
                            MeetingRecordDock(startedAt: startedAt) {
                                section = .meetings
                                if let m = manager.activeMeeting { router.openMeeting(m) }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(NDS.motion(NDS.springStandard, reduce: reduceMotion),
                               value: meetingRecordingStartedAt != nil)
                if showChat {
                    Divider().overlay(NDS.divider)
                    ChatSidebar()
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 380)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.18), value: showChat)
            .overlay(ToastOverlay())   // undo toasts (D4-3)
            .overlay(searchPalette)    // floating ⌘K command palette (C3-2)
        }
        .tint(NDS.brand)
        // No forced color scheme (C3-4): follow the system appearance.
        .navigationTitle("MeetingScribe")
        .onAppear {
            chatSession.setContext(contextLabel(section))
            // The router doesn't own the chat rail's visibility, so it calls
            // back here for a .chatQuery entity: reveal the rail, then dispatch.
            router.openChat = { query in
                if !chatVisible { chatVisible = true }
                NotificationCenter.default.post(name: .meetingScribeRunChat,
                                                object: nil, userInfo: ["text": query])
            }
        }
        .onChange(of: section) { _, s in
            chatSession.setContext(contextLabel(s))
        }
        .toolbar {
            // Title-bar "Stop · MM:SS" pill (from the design comp): a live,
            // always-visible recording control while a meeting is recording.
            ToolbarItem(placement: .principal) {
                if let started = meetingRecordingStartedAt {
                    RecordingStopPill(startedAt: started) {
                        Task { await manager.stopRecording() }
                    }
                }
            }
            // Global back / forward — browser-style history across sections and
            // meeting selections, driven by WorkspaceRouter.
            ToolbarItemGroup(placement: .navigation) {
                Button { router.goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!router.canGoBack)
                .help("Back")
                Button { router.goForward() } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(!router.canGoForward)
                .help("Forward")
            }
            // Page-tailored, named toolbar (§1). Per-page button sets come from
            // ToolbarModel; the less-common controls (import audio, join & record,
            // refresh, finalizing status) live in the overflow ⋯ menu so the bar
            // stays clean. The chat toggle stays unlabelled at the far right.
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(ToolbarModel.items(for: section,
                                           isRecordingMeeting: meetingRecordingStartedAt != nil)) { item in
                    toolbarItemView(item)
                }
                overflowMenu
                Button { withAnimation(.easeOut(duration: 0.15)) { chatVisible.toggle() } } label: {
                    Label("Assistant", systemImage: chatVisible ? "sidebar.right" : "bubble.left.and.bubble.right")
                }
                .help(chatVisible ? "Hide assistant" : "Show assistant")
            }
        }
        .sheet(isPresented: $showNewMeeting) {
            NewMeetingSheet { meeting in
                Task { await manager.startRecording(for: meeting) }
            }
            .environmentObject(calendar)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addPerson:
                AddPersonSheet()
                    .environmentObject(PeopleStore.shared)
                    .environmentObject(PeopleTagStore.shared)
            case .setup:
                SetupCheckSheet(setup: setup, isPresented: Binding(
                    get: { if case .setup = activeSheet { return true } else { return false } },
                    set: { if !$0 { activeSheet = nil } }
                ))
            }
        }
        // First-launch onboarding (audit 8.3). Pre-explains every macOS
        // permission before the system dialog appears — users who tap
        // "Don't Allow" once never see the system dialog again, so this
        // materially improves grant rate. Self-dismisses when complete.
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet(isPresented: $showOnboarding)
        }
        // Phase 1 (1D) — one binding activates every `FeatureGate.showPaywall(for:)`
        // call site across the app. Reading `paywallFeature` here registers the
        // @Observable dependency so the sheet presents the moment a gated action
        // calls `showPaywall`.
        .sheet(item: Binding(
            get: { FeatureGate.shared.paywallFeature },
            set: { FeatureGate.shared.paywallFeature = $0 }
        )) { feature in
            ProPaywallView(feature: feature)
        }
        // Initial data population — non-blocking. Calendar permission is
        // requested in parallel; the window paints with whatever cached
        // data is already in memory (warm-cache index, .upcoming-cache.json)
        // and the fresh reads slot in when they arrive.
        .task {
            // Show the first-launch onboarding instead of immediately
            // hitting the user with five system permission dialogs. The
            // sheet explains each permission before requesting it.
            if !hasCompletedOnboarding {
                // Tiny delay so the main window paints under the sheet
                // before it appears — a sheet over an empty window feels
                // off.
                try? await Task.sleep(nanoseconds: 200_000_000)
                showOnboarding = true
            } else {
                // Returning users: fire calendar permission asynchronously
                // so it never blocks the first paint. If already granted,
                // this is a no-op.
                if !calendar.authorized {
                    Task { await calendar.requestAccess() }
                }
                // Onboarding already done — check the AI stack now and, if it
                // isn't ready, surface the in-app Setup Check before the user
                // hits a first recording. (D3-1)
                await maybeShowSetupCheck()
            }
            // These three are all cheap when the cache is warm (which it
            // is by the time this fires — preloadIndex ran during
            // startServices).
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
            manager.refreshQuickNotes()
            // First-run only: seed a bundled sample meeting so Today is never
            // empty and first value (a real summary) arrives in zero clicks.
            // No-ops when the vault already has meetings. (D3-3)
            SampleMeetingSeeder.seedIfNeeded(manager: manager)
        }
        // New users: once onboarding closes, run the same readiness check so
        // the Setup Check rides right behind the permission flow.
        .onChange(of: showOnboarding) { _, showing in
            if !showing {
                Task { await maybeShowSetupCheck() }
            }
        }
        // Background: keep all tabs' data fresh on an hourly cadence.
        // The previous `prewarmOtherTabs` pattern that pre-rendered every
        // tab during the first 3 seconds of launch actually competed with
        // the first paint and was killed (perf rebuild). Tabs are built
        // lazily on first selection now — with the warm index cache and
        // body cache, that's already instant.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000) // ~1 hour
                guard !Task.isCancelled else { break }
                manager.refreshPastMeetings(force: true)
                manager.refreshQuickNotes()
                calendar.refreshUpcoming(force: true)
            }
        }
        // The Today view auto-stays on .today during recording — the live
        // recording card surfaces there. After stop, the Past section in
        // Today picks up the just-finished meeting.
        .onChange(of: manager.lastStoppedMeetingID) { _, id in
            manager.refreshPastMeetings()
            // Prefetch the just-stopped meeting's body so the user can
            // click into it without waiting for the disk read.
            if let id, let m = manager.pastMeetings.first(where: { $0.id == id }) {
                Task { _ = await manager.body(for: m) }
            }
        }
        // FloatingOverlay's "Go to Recording" posts this — switch to Notes.
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeOpenVoiceNote)) { _ in
            section = .notes
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeOpenSearch)) { _ in
            showSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeOpenWeeklyReview)) { _ in
            showWeeklyReview = true   // 3-F
        }
        .sheet(isPresented: $showWeeklyReview) { WeeklyReviewView() }
        // ⇧⌘P — jump to People and open the add-person sheet. Owned here (not
        // in PeopleListView) so it works even before the People tab is built.
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeAddPerson)) { _ in
            section = .people
            activeSheet = .addPerson
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeOpenEntity)) { note in
            guard let urlString = note.userInfo?["url"] as? String,
                  let url = URL(string: urlString),
                  let parsed = WorkspaceLink.parse(url) else { return }
            router.route(kind: parsed.kind, id: parsed.id, manager: manager)
        }
        // ⌘1–⌘7 keyboard shortcuts posted by CommandMenu("Navigate")
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeNavigate)) { note in
            guard let target = note.object as? TopLevelSection else { return }
            section = target
        }
    }

    /// From the search palette: dismiss the search sheet, then route through the
    /// canonical router. The old dismiss-then-present-SHEET hack is gone — a
    /// meeting now switches to its tab instead of opening a sheet. We still hop
    /// one runloop tick so the search sheet finishes dismissing before the
    /// underlying tab switches (and so a not-yet-built target tab can mount and
    /// register its open-entity listener before the route fires). (D1-1)
    private func handleEntity(_ e: WorkspaceEntity) {
        activeSheet = nil
        DispatchQueue.main.async {
            router.open(e, manager: manager)
        }
    }

    /// Probe the local AI stack and, if it isn't ready, present the in-app
    /// Setup Check — but at most once per launch and never stacked over another
    /// sheet or the onboarding flow. (D3-1)
    @MainActor
    private func maybeShowSetupCheck() async {
        guard !setupCheckOffered, !showOnboarding, activeSheet == nil else { return }
        await setup.refresh()
        guard !setup.isReady else { return }
        setupCheckOffered = true
        activeSheet = .setup
    }
}

// MARK: - Settings gear (SettingsLink-backed)

/// Opens the Settings scene reliably via SwiftUI's `SettingsLink` (macOS 14+),
/// styled to match `NotionIconButton`. Replaces the unreliable private-selector
/// `showSettingsWindow:` send-action the gear used before.
@available(macOS 14.0, *)
private struct SettingsGearButton: View {
    @State private var hovering = false
    var body: some View {
        SettingsLink {
            Image(systemName: "gearshape")
                .scaledFont(13)
                .foregroundStyle(NDS.textSecondary)
                .frame(width: NDS.buttonIconSide, height: NDS.buttonIconSide)
                .background(hovering ? NDS.rowHover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(hovering ? NDS.hairline : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

// MARK: - Nav rail item with hover state

@available(macOS 14.0, *)
private struct NavRailItem: View {
    let section: TopLevelSection
    let selected: Bool
    var badge: Badge = .none
    let action: () -> Void

    /// A glanceable rail indicator (D1-1).
    enum Badge: Equatable {
        case none
        /// A colored count pill (overdue tasks, drifting people).
        case count(Int, Color)
        /// An animated dot + count for in-flight work (meetings finalizing).
        case pulse(Int)
    }

    @State private var isHovered = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .scaledFont(13, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? NDS.lilac : NDS.textSecondary)
                    .frame(width: 16)
                Text(section.label)
                    .scaledFont(13, weight: selected ? .semibold : .medium)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                Spacer(minLength: 0)
                badgeView
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                selected || isHovered ? NDS.lilacSoft : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 9)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(section.label)
        .accessibilityValue(badgeAccessibility)
    }

    @ViewBuilder
    private var badgeView: some View {
        switch badge {
        case .none:
            EmptyView()
        case .count(let n, let color):
            Text("\(n)")
                .scaledFont(10, weight: .bold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(color, in: Capsule())
        case .pulse(let n):
            HStack(spacing: 4) {
                Circle()
                    .fill(NDS.brand)
                    .frame(width: 6, height: 6)
                    .opacity(pulsing && !reduceMotion ? 0.35 : 1)
                    .animation(reduceMotion ? nil :
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulsing)
                Text("\(n)")
                    .scaledFont(10, weight: .bold).monospacedDigit()
                    .foregroundStyle(NDS.textSecondary)
            }
            .onAppear { pulsing = true }
        }
    }

    private var badgeAccessibility: String {
        switch badge {
        case .none: return ""
        case .count(let n, _): return "\(n) need attention"
        case .pulse(let n): return "\(n) finalizing"
        }
    }
}

// MARK: - Persistent toolbar buttons

@available(macOS 14.0, *)
struct PersistentToolbarButtons: View {
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var calendar: CalendarService
    @State private var importingMeeting = false

    private func importMeeting() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a meeting audio file to import, transcribe, and summarize"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importingMeeting = true
        Task {
            await manager.importMeeting(from: url)
            importingMeeting = false
        }
    }

    var body: some View {
        // Voice Note (always visible)
        switch manager.quickRecordState {
        case .idle, .error:
            Button {
                Task { await manager.startQuickNote() }
            } label: {
                Label("Voice Note", systemImage: "mic.circle.fill")
            }
            .help("Record a voice note (transcribed locally)")
        case .recording:
            Button(role: .destructive) {
                Task { await manager.stopQuickNote() }
            } label: {
                Label("Stop Voice Note", systemImage: "stop.circle.fill")
            }
        case .transcribing:
            HStack(spacing: 3) {
                ProgressView().controlSize(.small)
                Text("Transcribing").font(.caption)
            }
        }

        // Meeting Recording (always visible).
        // Post-processing (transcription/summary) for prior meetings runs in
        // the background and no longer blocks new recordings — so the only
        // toolbar states are "start" and "stop".
        switch manager.state {
        case .idle, .error, .starting:
            Button {
                Task { await manager.startRecording(for: nil) }
            } label: {
                Label("Ad-hoc Recording", systemImage: "record.circle")
            }
            .help("Start an ad-hoc meeting recording")
        case .recording, .stopping:
            Button(role: .destructive) {
                Task { await manager.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill").foregroundStyle(NDS.recording)
            }
        }

        // Import an existing meeting recording → transcribe + summarize.
        if importingMeeting {
            HStack(spacing: 3) {
                ProgressView().controlSize(.small)
                Text("Importing").font(.caption)
            }
        } else {
            Button {
                importMeeting()
            } label: {
                Label("Import Meeting", systemImage: "square.and.arrow.down")
            }
            .help("Import an audio file as a meeting — it'll be transcribed and summarized.")
        }

        // Subtle indicator if there are background post-processing jobs.
        if !manager.transcribingMeetingIDs.isEmpty {
            HStack(spacing: 3) {
                ProgressView().controlSize(.small)
                Text("\(manager.transcribingMeetingIDs.count) finalizing").font(.caption)
            }
            .help("Transcription / summary still running for stopped meeting(s).")
        }

        // Join & Record (visible from just before a meeting through 45 min
        // after it ends, with a conference URL; clickable even mid-recording —
        // switches recording).
        if let live = calendar.upcoming.first(where: { $0.isJoinableWindow && $0.conferenceURL != nil }) {
            Button {
                Task { await manager.switchToRecording(live) }
            } label: {
                Label("Join & Record", systemImage: "video.fill")
            }
            .help("Join \(live.displayTitle) and start recording (stops any current recording first)")
        }

        Button {
            calendar.refreshUpcoming(force: true)
            manager.refreshPastMeetings(force: true)
            manager.refreshQuickNotes()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }
}
