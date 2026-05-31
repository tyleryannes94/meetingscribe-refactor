import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Top-level navigation sections. Collapsed from 7 → 5:
/// - Calendar absorbed into Meetings (accessible via the Upcoming tab)
/// - Integrations moved to Settings (⚙️ gear icon at bottom of rail)
/// - Notes kept as Voice Notes (distinct enough from Meetings to warrant its own slot)
enum TopLevelSection: String, CaseIterable, Identifiable, Hashable {
    case today, meetings, people, actions, notes
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today:    return "Today"
        case .meetings: return "Meetings"
        case .people:   return "People"
        case .actions:  return "Tasks"
        case .notes:    return "Voice Notes"
        }
    }
    var systemImage: String {
        switch self {
        case .today:    return "sun.max.fill"
        case .meetings: return "person.2.fill"
        case .people:   return "person.2"
        case .actions:  return "checklist"
        case .notes:    return "waveform.badge.plus"
        }
    }
    /// Which nav group this section belongs to (for section headers in the rail).
    var group: NavGroup {
        switch self {
        case .today, .meetings, .people: return .workspace
        case .actions, .notes:           return .organize
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
    /// The selected top-level section now lives in `WorkspaceRouter` (D1-1) so
    /// search, deep links, and backlinks all drive one navigation surface. This
    /// computed accessor keeps the existing `section` / `section = …` call sites
    /// unchanged.
    private var section: TopLevelSection {
        get { router.section }
        nonmutating set { router.section = newValue }
    }
    @State private var activeSheet: ActiveSheet?
    // Default the assistant rail CLOSED — new users land on a full-width app
    // instead of a chat panel that crowds content (and confuses first-run users
    // with an empty assistant). Existing users keep their stored preference.
    @AppStorage("chatRailVisible") private var chatVisible = false
    /// Follow the system appearance by default (nil = system). Stored as a
    /// Bool for toggle simplicity; false = light, true = dark. We default to
    /// false (light/system) rather than forcing dark on every first-launch user.
    @AppStorage("appearanceDark") private var appearanceDark = false
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
                        .animation(.easeOut(duration: 0.15), value: section)
                        .allowsHitTesting(section == s)
                        .zIndex(section == s ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: section) { _, s in
            visited.insert(s)
        }
    }

    // MARK: - Left navigation rail

    private var navRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App wordmark
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NDS.brand)
                Text("MeetingScribe").font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 14)

            // WORKSPACE group
            navGroupLabel(NavGroup.workspace.rawValue)
            ForEach(TopLevelSection.allCases.filter { $0.group == .workspace }) { s in
                navItem(s)
            }

            Spacer().frame(height: 8)

            // ORGANIZE group
            navGroupLabel(NavGroup.organize.rawValue)
            ForEach(TopLevelSection.allCases.filter { $0.group == .organize }) { s in
                navItem(s)
            }

            Spacer()
            Divider().overlay(NDS.divider).padding(.horizontal, 10).padding(.bottom, 6)

            // Bottom row: appearance toggle + search + settings
            HStack(spacing: 6) {
                AppearanceToggle(dark: $appearanceDark)
                    .frame(width: 124)
                Spacer(minLength: 0)
                Button { activeSheet = .search } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11))
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

                // Settings gear (replaces the old Integrations nav item)
                NotionIconButton(systemName: "gearshape", help: "Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(width: 240)  // increased from 216
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NDS.sidebarBg)
    }

    private func navGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(NDS.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func navItem(_ s: TopLevelSection) -> some View {
        NavRailItem(section: s, selected: section == s) { section = s }
    }

    private func navActionRow(_ title: String, systemImage: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 13)).foregroundStyle(NDS.textSecondary).frame(width: 18)
                Text(title).font(.system(size: 13)).foregroundStyle(NDS.textSecondary)
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
        case search
        case addPerson
        case setup
        var id: String {
            switch self {
            case .search: return "search"
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
                    .clipped()
                if showChat {
                    Divider().overlay(NDS.divider)
                    ChatSidebar()
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 380)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.18), value: showChat)
        }
        .tint(NDS.brand)
        .preferredColorScheme(appearanceDark ? .dark : .light)
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
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(.easeOut(duration: 0.15)) { chatVisible.toggle() } } label: {
                    Label("Assistant", systemImage: chatVisible ? "sidebar.right" : "bubble.left.and.bubble.right")
                }
                .help(chatVisible ? "Hide assistant" : "Show assistant")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .search
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help("Search everything (⌘K)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                PersistentToolbarButtons()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .search:
                GlobalSearchView(isPresented: Binding(
                    get: { if case .search = activeSheet { return true } else { return false } },
                    set: { if !$0 { activeSheet = nil } }
                ), onOpen: handleEntity)
                .environmentObject(manager)
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
            activeSheet = .search
        }
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

// MARK: - Nav rail item with hover state

@available(macOS 14.0, *)
private struct NavRailItem: View {
    let section: TopLevelSection
    let selected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? NDS.brand : NDS.textSecondary)
                    .frame(width: 18)
                Text(section.label)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                selected
                    ? NDS.brand.opacity(0.14)
                    : isHovered ? NDS.brand.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(section.label)
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
                Label("Stop Recording", systemImage: "stop.circle.fill").foregroundStyle(.red)
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

        // Join & Record (always visible when there's a live meeting with a
        // conference URL; clickable even mid-recording — switches recording).
        if let live = calendar.upcoming.first(where: { $0.isLive && $0.conferenceURL != nil }) {
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
