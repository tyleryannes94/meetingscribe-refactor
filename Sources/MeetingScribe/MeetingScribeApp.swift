import SwiftUI
import AppKit
import Combine
import ServiceManagement

@available(macOS 14.0, *)
@main
struct MeetingScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var calendar = CalendarService()
    @StateObject private var manager = MeetingManager()
    @StateObject private var notifications = NotificationManager()
    @StateObject private var appDetector = AppDetector()
    @StateObject private var overlay = FloatingOverlayController()
    @StateObject private var chatSession = ChatSession()
    @StateObject private var updater = UpdaterController()
    @StateObject private var vaultMigrator = VaultMigrationManager()
    @StateObject private var router = WorkspaceRouter()
    @State private var calendarTimer: Timer?
    @State private var hotkey = GlobalHotkey()
    @State private var swapHotkey = GlobalHotkey()
    @State private var promptHotkey = GlobalHotkey()
    @State private var meetingRecordHotkey = GlobalHotkey()
    @State private var settingsObserver: AnyCancellable?

    var body: some Scene {
        Window("MeetingScribe", id: "main") {
            MainWindow()
                .environmentObject(calendar)
                .environmentObject(manager)
                .environmentObject(manager.recordingMonitor)
                .environmentObject(notifications)
                .environmentObject(appDetector)
                .environmentObject(manager.tagStore)
                .environmentObject(PeopleStore.shared)
                .environmentObject(PeopleTagStore.shared)
                .environmentObject(chatSession)
                // Scoped sub-controllers (audit 6.3 wiring). Views that
                // only care about one concern can `@EnvironmentObject` the
                // narrower object — they then re-render only when THAT
                // controller publishes, not when the manager's unrelated
                // state changes.
                .environmentObject(manager.quickNotesController)
                .environmentObject(manager.pipelineController)
                .environmentObject(manager.actionItemBackfill)
                .environmentObject(manager.personExtraction)
                .environmentObject(manager.actionItems)
                .environmentObject(manager.decisions)
                .environmentObject(router)
                .frame(minWidth: 720, minHeight: 560)
                // Deep links: meetingscribe://<kind>/<id> from MCP, Shortcuts,
                // Spotlight, or another app. The scheme is registered in
                // Resources/Info.plist (CFBundleURLTypes). Routes through the
                // one canonical router. (D1-2)
                .onOpenURL { url in
                    guard let parsed = WorkspaceLink.parse(url) else { return }
                    router.route(kind: parsed.kind, id: parsed.id, manager: manager)
                }
                .task {
                    startServices()
                    await ActivityLog.shared.log(.appLaunch)  // 1C funnel
                }
                // Vault layout migration — shown once when the vault is still
                // in the old tag-grouped layout. VaultMigrationManager sets
                // needsLayoutMigration = false after a successful migration and
                // persists the completed flag to UserDefaults so the sheet never
                // reappears.
                .sheet(isPresented: $vaultMigrator.needsLayoutMigration) {
                    VaultMigrationSheet(
                        migrator: vaultMigrator,
                        vaultURL: AppSettings.shared.storageDir
                    ) {
                        vaultMigrator.needsLayoutMigration = false
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
            CommandGroup(after: .toolbar) {
                Button("Search Everything…") {
                    NotificationCenter.default.post(name: .meetingScribeOpenSearch, object: nil)
                }
                .keyboardShortcut("K", modifiers: [.command])
            }
            // ⌘1–⌘5: jump to each top-level section (5 sections, Calendar+Integrations removed from nav).
            CommandMenu("Navigate") {
                Button("Today")       { NotificationCenter.default.post(name: .meetingScribeNavigate, object: TopLevelSection.today) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Meetings")    { NotificationCenter.default.post(name: .meetingScribeNavigate, object: TopLevelSection.meetings) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("People")      { NotificationCenter.default.post(name: .meetingScribeNavigate, object: TopLevelSection.people) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Tasks")       { NotificationCenter.default.post(name: .meetingScribeNavigate, object: TopLevelSection.actions) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Voice Notes") { NotificationCenter.default.post(name: .meetingScribeNavigate, object: TopLevelSection.notes) }
                    .keyboardShortcut("5", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Start Ad-hoc Meeting Recording") {
                    Task { await manager.startRecording(for: nil) }
                }
                .keyboardShortcut("R", modifiers: [.command])
                Button("Stop Recording") {
                    Task { await manager.stopRecording() }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                Divider()
                Button("New Voice Note") {
                    Task { await manager.startQuickNote() }
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])
                Button("New Person") {
                    NotificationCenter.default.post(name: .meetingScribeAddPerson, object: nil)
                }
                .keyboardShortcut("P", modifiers: [.command, .shift])
                Button("New Task") {
                    // Quick-add a task and jump to Tasks so it's ready to rename.
                    _ = manager.actionItems.createTask(title: "New task")
                    NotificationCenter.default.post(name: .meetingScribeNavigate,
                                                    object: TopLevelSection.actions)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(calendar)
                .environmentObject(manager)
                .environmentObject(manager.tagStore)
        } label: {
            Label("MeetingScribe", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(calendar)
                .environmentObject(manager)
                .environmentObject(manager.tagStore)
                .environmentObject(updater)
                .frame(width: 560, height: 580)
        }
    }

    private var menuBarIcon: String {
        switch manager.state {
        case .recording, .stopping: return "record.circle.fill"
        case .error: return "exclamationmark.triangle"
        case .idle, .starting:
            return manager.transcribingMeetingIDs.isEmpty ? "waveform" : "waveform.circle"
        }
    }

    private func startServices() {
        // FAST PATH (synchronous, must happen before any UI interaction):
        //   - Wire callbacks so they're not nil when the first user event fires
        //   - Register the global hotkey
        //   - One-time settings migrations (cheap; UserDefaults reads)
        // Everything else is async/detached — the window is already on screen
        // and we don't want to block its first paint on Ollama probes or
        // disk walks.
        AppSettings.shared.migrateOllamaModelIfNeeded()
        registerScribeCoreLoginItem()
        wireNotifications()
        wireDetector()
        wirePipelineNotification()
        // Live-event snap (U2-1): let the manager resolve a quick recording onto
        // the single currently-live calendar event when one exists.
        manager.liveCalendarMeetingProvider = { [weak calendar] in
            let live = calendar?.upcoming.filter { $0.isLive } ?? []
            return live.count == 1 ? live.first : nil
        }
        // Ambient mic-based meeting detection (off unless enabled in Settings).
        AmbientMeetingDetector.shared.startIfEnabled()
        registerHotkey()
        overlay.attach(to: manager)
        chatSession.attach(manager: manager)
        observeSettingsChanges()

        // Phone access: wire the embedded web server to the live stores and
        // start it if the user has enabled it. Reads/writes flow through the
        // same @MainActor stores the desktop UI uses, so edits from a phone
        // get persistence, index updates, and dedup for free. (Off by default.)
        WebServerController.shared.configure(manager: manager)
        WebServerController.shared.startIfEnabled()

        // Wire the iCloud inbox watcher — processes files dropped by iPhone
        // Shortcuts into vault/_inbox/. Without this, Shortcut-to-MeetingScribe
        // flows (quick notes, voice notes, action items) are silently ignored.
        wireInboxWatcher()

        // BACKGROUND: prime the meeting index from disk so the first
        // `listPastMeetings()` from a tab is instant. JSON decode of 200+
        // meetings on a detached task is still milliseconds.
        manager.store.preloadIndex()

        // BACKGROUND: keychain migration. Was sync at the top but each
        // SecItem lookup can take a few ms on first-keychain-unlock; we
        // don't want to pay that on the path to first paint.
        Task.detached(priority: .utility) {
            KeychainStore.migrateAllFromUserDefaults()
        }

        // BACKGROUND: notifications + Ollama. Neither blocks the UI.
        Task { await notifications.requestAuthorization() }
        notifications.scheduleDailyBrief()   // morning brief, opt-in (P2-5)
        Task.detached(priority: .utility) { [manager] in
            await manager.ensureOllamaRunning()
        }

        // BACKGROUND: orphaned chunks cleanup. Hourly throttle would be
        // nicer but per-launch is fine — it's a tree walk that aborts
        // quickly when no chunks/ subdirs exist.
        Task.detached(priority: .background) { [store = manager.store] in
            store.cleanupOrphanedChunks()
        }

        // FOREGROUND (but staggered): the 60s calendar timer fires its
        // first refresh after a small delay so we don't compete with the
        // first paint.
        startCalendarTimerDeferred()

        // BACKGROUND: warm the top-N meeting body cache so the first few
        // clicks-into-detail come from RAM. Runs after a brief pause to
        // let the index load first.
        Task.detached(priority: .utility) { [manager] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run { manager.prefetchTopMeetingBodies(limit: 10) }
        }

        // BACKGROUND: one-time attendee backfill (P1-1). Retroactively links
        // every existing meeting's attendees to their Person records via the
        // identity layer, so health/timelines/follow-ups are truthful for
        // history, not just future meetings. Reads a definitive list from the
        // store (not the still-loading published `pastMeetings`); guarded by a
        // UserDefaults flag inside the store helper, so it runs at most once.
        Task.detached(priority: .background) { [manager] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                let meetings = manager.store.listPastMeetings()
                PeopleStore.shared.backfillMeetingLinks(meetings)
            }
        }
    }

    /// Like `startCalendarTimer` but defers the first call so it doesn't
    /// race the first paint.
    private func startCalendarTimerDeferred() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            startCalendarTimer()
        }
    }

    private func startCalendarTimer() {
        guard calendarTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                calendar.refreshUpcoming()
                let briefs = Dictionary(calendar.upcoming.compactMap { m in manager.briefSnippet(for: m).map { (m.id, $0) } }, uniquingKeysWith: { a, _ in a }); await notifications.syncScheduled(for: calendar.upcoming, briefs: briefs)
                await notifications.syncTaskReminders(for: manager.actionItems.items)
                if AppSettings.shared.autoRecord { autoStartIfNeeded() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        calendarTimer = t
        Task { @MainActor in
            let briefs = Dictionary(calendar.upcoming.compactMap { m in manager.briefSnippet(for: m).map { (m.id, $0) } }, uniquingKeysWith: { a, _ in a }); await notifications.syncScheduled(for: calendar.upcoming, briefs: briefs)
            await notifications.syncTaskReminders(for: manager.actionItems.items)
        }
    }

    private func autoStartIfNeeded() {
        // Belt + suspenders: never auto-start while any recording is being
        // set up, running, or being torn down. The .idle check covered the
        // common case, but a running impromptu must never be silently
        // replaced — see "wrong-meeting transcript" bug 2026-06.
        switch manager.state {
        case .idle:
            break
        case .starting, .recording, .stopping, .error:
            return
        }
        if manager.activeMeeting != nil { return }

        // Only auto-start if the user has actually joined a call — i.e.
        // AppDetector sees them in a Zoom meeting window or a browser tab
        // on meet.google.com. This avoids surprise recordings of calendar
        // events that turned out to be just time blocks.
        guard let detected = MeetingSource.from(detectedCallSource: appDetector.currentCallSource) else { return }

        // Match the live calendar event to the call the user is actually in.
        // Previously we just picked `upcoming.first(where: isLive)`, which
        // would happily attach an impromptu recording's transcript to a
        // completely unrelated scheduled meeting at the same time.
        let liveCandidates = calendar.upcoming.filter { $0.isLive }
        let matching = liveCandidates.filter { m in
            guard let source = m.effectiveSource else { return false }
            return source == detected
        }
        // Be conservative when the match is ambiguous (e.g. two Meet calls
        // overlap). Skipping is better than recording the wrong one.
        guard matching.count == 1, let live = matching.first else { return }
        Task { await manager.startRecording(for: live) }
    }

    /// Post a "Meeting ready" banner when transcription + summary finishes.
    private func wirePipelineNotification() {
        manager.pipelineController.onComplete = { [weak notifications, weak manager] meeting, summaryFailed in
            // U4-4: if the summary failed, the capture promise is half-kept —
            // say so instead of staying silent, and point at the in-app retry.
            guard !summaryFailed else {
                notifications?.notifySummaryNeedsRetry(meeting: meeting)
                return
            }
            // Pull a clean prose snippet from the summary for the notification
            // body (skip markdown headings/blank lines). (U3-5)
            let summary = manager?.summaryMarkdown(for: meeting) ?? ""
            let snippet = summary
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(">") }
                ?? ""
            notifications?.notifyTranscriptionComplete(meeting: meeting, summarySnippet: snippet)
        }
    }

    private func wireNotifications() {
        notifications.onJoinAndRecord = { meeting in
            Task { await manager.switchToRecording(meeting) }
        }
        notifications.onRecordMeeting = { meeting in
            Task { await manager.startRecording(for: meeting) }
        }
        notifications.onRecordImpromptu = { source in
            Task { @MainActor in manager.startImpromptu(source: source) }
        }
    }

    private func wireDetector() {
        appDetector.isRecording = {
            if case .recording = manager.state { return true }
            return false
        }
        appDetector.onImpromptuDetected = { source in
            // Skip if there's already a live calendar meeting that covers this.
            if calendar.upcoming.contains(where: { $0.isLive }) { return }
            notifications.notifyImpromptuDetected(source: source)
        }
        appDetector.start()
    }

    private func registerHotkey() {
        let s = AppSettings.shared
        hotkey.onTrigger = { [weak manager] in
            manager?.dictation.toggle()
        }
        hotkey.register(keyCode: s.dictationHotkeyKeyCode,
                        modifiers: s.dictationHotkeyModifiers)
        swapHotkey.onTrigger = { [weak manager] in
            manager?.dictation.swapVersion()
        }
        swapHotkey.register(keyCode: s.dictationSwapHotkeyKeyCode,
                            modifiers: s.dictationSwapHotkeyModifiers)
        // Optional: rewrite the just-dictated text into a TCREI-structured AI
        // prompt, in place. Separate from the raw↔polished swap.
        promptHotkey.onTrigger = { [weak manager] in
            manager?.dictation.rewriteAsPrompt()
        }
        promptHotkey.register(keyCode: s.dictationPromptHotkeyKeyCode,
                              modifiers: s.dictationPromptHotkeyModifiers)
        // Global meeting-record toggle (D4-1): one chord starts an ad-hoc
        // recording when idle and stops it when recording — works system-wide,
        // even when MeetingScribe isn't the focused app.
        meetingRecordHotkey.onTrigger = { [weak manager] in
            guard let manager else { return }
            Task { @MainActor in
                switch manager.state {
                case .recording, .stopping:
                    await manager.stopRecording()
                default:
                    await manager.startRecording(for: nil)
                }
            }
        }
        meetingRecordHotkey.register(keyCode: s.meetingRecordHotkeyKeyCode,
                                     modifiers: s.meetingRecordHotkeyModifiers)
    }

    // MARK: - Login Item registration

    /// Registers ScribeCore as a Login Item so it starts automatically on login.
    /// Must use `loginItem(identifier:)` — `mainApp` registers the calling process
    /// itself (the UI), not the embedded ScribeCore helper.
    /// Safe to call repeatedly — SMAppService is idempotent when already registered.
    ///
    /// GATED OFF by default (E3-1): the daemon recording path does not finalize
    /// a meeting and loses it silently. When the kill-switch is off we also
    /// proactively *unregister* the login item so existing installs that already
    /// registered it stop booting the daemon on next login.
    private func registerScribeCoreLoginItem() {
        if #available(macOS 13.0, *) {
            let item = SMAppService.loginItem(identifier: "com.tyleryannes.ScribeCore")
            guard AppSettings.shared.useScribeCoreDaemon else {
                // Best-effort: tear down a previously-registered daemon login item.
                do { try item.unregister() }
                catch { print("Failed to unregister ScribeCore login item: \(error)") }
                return
            }
            do {
                try item.register()
            } catch {
                print("Failed to register ScribeCore login item: \(error)")
            }
        }
    }

    // MARK: - iCloud inbox (iPhone Shortcuts integration)

    private func wireInboxWatcher() {
        let watcher = iCloudInboxWatcher.shared
        let mgr = manager

        // Quick text notes created from the iPhone Shortcuts shortcut.
        // Save as a QuickNote with transcript only (no audio).
        watcher.onQuickNote = { [weak mgr] envelope in
            Task { @MainActor in
                guard let mgr else { return }
                let now = Date()
                let note = QuickNote(
                    id: envelope.id,
                    title: envelope.title ?? "Quick Note",
                    createdAt: now,
                    durationSeconds: 0,
                    snippet: String((envelope.body ?? "").prefix(150)),
                    wasDictation: false
                )
                mgr.quickNotesController.saveTranscript(envelope.body ?? "", for: note)
            }
        }

        // Action items manually entered via iPhone Shortcuts.
        watcher.onActionItem = { [weak mgr] envelope in
            Task { @MainActor in
                guard let mgr else { return }
                let title = envelope.title ?? envelope.body ?? "Action Item"
                mgr.actionItems.createTask(title: title)
            }
        }

        // Voice notes recorded on iPhone and synced via iCloud Drive.
        watcher.onVoiceNote = { [weak mgr] audioURL, _ in
            Task { @MainActor in
                guard let mgr else { return }
                await mgr.importVoiceNote(from: audioURL)
            }
        }

        watcher.start(vaultURL: AppSettings.shared.storageDir)
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default
            .publisher(for: .meetingScribeSettingsChanged)
            .sink { _ in
                let s = AppSettings.shared
                hotkey.register(keyCode: s.dictationHotkeyKeyCode,
                                modifiers: s.dictationHotkeyModifiers)
                swapHotkey.register(keyCode: s.dictationSwapHotkeyKeyCode,
                                    modifiers: s.dictationSwapHotkeyModifiers)
                promptHotkey.register(keyCode: s.dictationPromptHotkeyKeyCode,
                                      modifiers: s.dictationPromptHotkeyModifiers)
                meetingRecordHotkey.register(keyCode: s.meetingRecordHotkeyKeyCode,
                                             modifiers: s.meetingRecordHotkeyModifiers)
                notifications.scheduleDailyBrief()
                Task { @MainActor in
                    calendar.refreshUpcoming(force: true)
                    let briefs = Dictionary(calendar.upcoming.compactMap { m in manager.briefSnippet(for: m).map { (m.id, $0) } }, uniquingKeysWith: { a, _ in a }); await notifications.syncScheduled(for: calendar.upcoming, briefs: briefs)
                    await notifications.syncTaskReminders(for: manager.actionItems.items)
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.install()   // capture silent crashes into the diag bundle (PS-3)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for window in sender.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
