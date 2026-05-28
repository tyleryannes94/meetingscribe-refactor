import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum TopLevelSection: String, CaseIterable, Identifiable, Hashable {
    case today, meetings, people, actions, calendar, notes, integrations
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today:        return "Today"
        case .meetings:     return "Meetings"
        case .people:       return "People"
        case .actions:      return "Tasks"
        case .calendar:     return "Calendar"
        case .notes:        return "Notes"
        case .integrations: return "Integrations"
        }
    }
    var systemImage: String {
        switch self {
        case .today:        return "sun.max.fill"
        case .meetings:     return "person.2.fill"
        case .people:       return "person.2"
        case .actions:      return "checklist"
        case .calendar:     return "calendar"
        case .notes:        return "waveform.badge.plus"
        case .integrations: return "puzzlepiece.extension.fill"
        }
    }
}

@available(macOS 14.0, *)
struct MainWindow: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var chatSession: ChatSession

    @AppStorage("mainWindow.lastSelectedSection") private var sectionRaw: String = TopLevelSection.today.rawValue
    private var section: TopLevelSection {
        get { TopLevelSection(rawValue: sectionRaw) ?? .today }
        nonmutating set { sectionRaw = newValue.rawValue }
    }
    /// Binding forwarded to child views (e.g. TodayView) so they can
    /// programmatically switch sections. Writes go through sectionRaw and
    /// are therefore automatically persisted to UserDefaults.
    private var sectionBinding: Binding<TopLevelSection> {
        Binding(get: { section }, set: { section = $0 })
    }
    @State private var activeSheet: ActiveSheet?
    @AppStorage("chatRailVisible") private var chatVisible = true
    /// Direction A — dark mode is the default; the nav-rail toggle flips it.
    @AppStorage("appearanceDark") private var appearanceDark = true
    /// First-launch onboarding — pre-explains every macOS permission BEFORE
    /// the system dialog so a "Don't Allow" tap doesn't silently strand the
    /// user (audit 8.3). Shown once and then never again per `hasCompletedOnboarding`.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showOnboarding: Bool = false
    /// Sections built so far. Today is always pre-built; the persisted section
    /// is also included so the keep-alive ZStack renders it on first paint.
    @State private var visited: Set<TopLevelSection> = {
        let raw = UserDefaults.standard.string(forKey: "mainWindow.lastSelectedSection") ?? ""
        let persisted = TopLevelSection(rawValue: raw) ?? .today
        return [.today, persisted]
    }()

    /// Keep-alive tabs: each section is built lazily the first time it's
    /// opened, then kept in the hierarchy and shown/hidden via opacity.
    private var tabContent: some View {
        ZStack {
            ForEach(TopLevelSection.allCases) { s in
                if visited.contains(s) {
                    tabView(for: s)
                        .opacity(section == s ? 1 : 0)
                        .allowsHitTesting(section == s)
                        .zIndex(section == s ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: sectionRaw) { _, raw in
            let s = TopLevelSection(rawValue: raw) ?? .today
            visited.insert(s)
        }
    }

    // MARK: - Left navigation rail

    private var navRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NDS.brand)
                Text("MeetingScribe").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 12)

            ForEach(TopLevelSection.allCases) { s in
                navItem(s)
            }
            Spacer()
            Divider().overlay(NDS.divider).padding(.horizontal, 10).padding(.bottom, 8)
            // Appearance toggle (bottom-left) + a compact ⌘K search affordance.
            HStack(spacing: 8) {
                AppearanceToggle(dark: $appearanceDark)
                    .frame(width: 140)
                Spacer(minLength: 0)
                Button { activeSheet = .search } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11))
                        Text("⌘K").font(NDS.tiny)
                    }
                    .foregroundStyle(NDS.textSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(NDS.hairline, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search everything (⌘K)")
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(width: 216)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NDS.sidebarBg)
    }

    private func navItem(_ s: TopLevelSection) -> some View {
        let selected = section == s
        return Button {
            section = s
        } label: {
            HStack(spacing: 10) {
                Image(systemName: s.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? NDS.brand : NDS.textSecondary)
                    .frame(width: 18)
                Text(s.label)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? NDS.brand.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
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
        case .today:        return "The Today home — today's meetings, quick actions, and open action items."
        case .meetings:     return "The Meetings list — all past and upcoming meetings/calls."
        case .people:       return "People — your second-brain contacts, searchable by name and event tag."
        case .actions:      return "The Tasks workspace — initiatives, projects (pages), and tasks."
        case .calendar:     return "The Calendar — month view of meetings."
        case .notes:        return "Voice Notes — recorded/imported notes with transcripts."
        case .integrations: return "The Integrations settings — Linear, Notion, Google Drive, Ollama, Calendar, MCP."
        }
    }

    @ViewBuilder
    private func tabView(for s: TopLevelSection) -> some View {
        switch s {
        case .today:        TodayView(section: sectionBinding)
        case .meetings:     MeetingsView()
        case .people:       PeopleListView()
        case .actions:      ActionItemsView(store: manager.actionItems)
        case .calendar:     CalendarTabView()
        case .notes:        QuickNotesView()
        case .integrations: IntegrationsView()
        }
    }

    // (Removed in the perf rebuild: `prewarmOtherTabs` was building every
    // non-default tab in the background during the first 3 seconds — which
    // competed for the main thread with the user's first-impression render
    // of the default tab. The new pattern is: tabs build on first selection.
    // Combined with the warm `MeetingStore` index cache + `MeetingBodyCache`,
    // a freshly-selected tab is already instant without prewarming.)

    /// Single sheet slot so search and an opened meeting never collide.
    enum ActiveSheet: Identifiable {
        case search
        case meeting(Meeting)
        case addPerson
        var id: String {
            switch self {
            case .search: return "search"
            case .meeting(let m): return "meeting:\(m.id)"
            case .addPerson: return "addPerson"
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
        .onAppear { chatSession.setContext(contextLabel(section)) }
        .onChange(of: sectionRaw) { _, raw in
            chatSession.setContext(contextLabel(TopLevelSection(rawValue: raw) ?? .today))
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
            case .meeting(let m):
                meetingSheet(m)
            case .addPerson:
                AddPersonSheet()
                    .environmentObject(PeopleStore.shared)
                    .environmentObject(PeopleTagStore.shared)
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
            }
            // These three are all cheap when the cache is warm (which it
            // is by the time this fires — preloadIndex ran during
            // startServices).
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
            manager.refreshQuickNotes()
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
            routeEntity(kind: parsed.kind, id: parsed.id)
        }
    }

    @ViewBuilder
    private func meetingSheet(_ m: Meeting) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(m.displayTitle).font(.headline).lineLimit(1)
                Spacer()
                Button("Done") { activeSheet = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            UnifiedMeetingDetail(mode: .past(m))
                .environmentObject(manager)
                .environmentObject(manager.recordingMonitor)
                .environmentObject(manager.tagStore)
                .environmentObject(calendar)
        }
        .frame(width: 860, height: 680)
    }

    /// From the search palette: dismiss the search sheet, then route.
    private func handleEntity(_ e: WorkspaceEntity) {
        routeEntity(kind: e.kind, id: e.rawID)
    }

    /// Central navigation. A meeting opens in a sheet; everything else flips to
    /// the relevant section. Hops to the next runloop tick if a sheet is up so
    /// the dismiss/present transition doesn't fight itself.
    private func routeEntity(kind: WorkspaceEntityKind, id: String) {
        let present: () -> Void = {
            switch kind {
            case .meeting:
                if let m = manager.meeting(forEntityID: id) {
                    activeSheet = .meeting(m)
                } else {
                    manager.refreshPastMeetings(force: true)
                }
            case .voiceNote:
                section = .notes
                NotificationCenter.default.post(name: .meetingScribeOpenVoiceNote,
                                                object: nil, userInfo: ["id": id])
            case .project, .actionItem:
                section = .actions
            case .person:
                section = .people
                NotificationCenter.default.post(name: .meetingScribeOpenPerson,
                                                object: nil, userInfo: ["id": id])
            case .attachedNote:
                // rawID is "<personId>::<noteId>" — route to the person;
                // the user can then scroll to the Notes section. We don't
                // try to scroll-to-note here (no anchor wiring yet), but
                // opening the right person is the 90 % win.
                let personId = id.split(separator: "::").first.map(String.init) ?? id
                section = .people
                NotificationCenter.default.post(name: .meetingScribeOpenPerson,
                                                object: nil, userInfo: ["id": personId])
            case .chatQuery:
                // Natural-language passthrough: drop the typed query into
                // the chat sidebar and trigger a send. ChatSession owns
                // the actual dispatch.
                if !chatVisible { chatVisible = true }
                NotificationCenter.default.post(name: .meetingScribeRunChat,
                                                object: nil,
                                                userInfo: ["text": id])
            case .tag:
                // Plain tag click — route to the People tab pre-filtered.
                section = .people
                NotificationCenter.default.post(name: .meetingScribeFilterByTag,
                                                object: nil, userInfo: ["name": id])
            }
        }
        if activeSheet != nil {
            activeSheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: present)
        } else {
            present()
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
