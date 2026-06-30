import SwiftUI
import Carbon.HIToolbox

@available(macOS 14.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var actionItems: ActionItemStore
    @EnvironmentObject private var manager: MeetingManager
    // "Fix duplicates" maintenance job state.
    @State private var fixingDuplicates = false
    @State private var dedupeResult: String?

    @State private var storageDir: String = AppSettings.shared.storageDir.path
    @State private var whisperBinary: String = AppSettings.shared.whisperBinary
    @State private var whisperModel: String = AppSettings.shared.whisperModel
    @State private var ollamaURL: String = AppSettings.shared.ollamaURL.absoluteString
    @State private var ollamaModel: String = AppSettings.shared.ollamaModel
    @State private var autoRecord: Bool = AppSettings.shared.autoRecord
    @State private var useScreenVisionModel: Bool = AppSettings.shared.useScreenVisionModel
    @State private var screenVisionModel: String = AppSettings.shared.screenVisionModel
    @State private var captureMic: Bool = AppSettings.shared.captureMic
    @State private var captureSystem: Bool = AppSettings.shared.captureSystem
    @State private var liveTranscriptionEnabled: Bool = AppSettings.shared.liveTranscriptionEnabled
    @State private var deferLiveOnBattery: Bool = AppSettings.shared.deferLiveTranscriptionOnBattery
    @State private var filterToConference: Bool = AppSettings.shared.filterToConferenceLinks
    @State private var notifyAtStart: Bool = AppSettings.shared.notifyAtMeetingStart
    @State private var dailyBrief: Bool = AppSettings.shared.dailyBriefEnabled
    @State private var detectZoom: Bool = AppSettings.shared.detectZoomImpromptu
    @State private var hotkeyKeyCode: UInt32 = AppSettings.shared.dictationHotkeyKeyCode
    @State private var hotkeyMods: UInt32 = AppSettings.shared.dictationHotkeyModifiers
    @State private var meetingRecKeyCode: UInt32 = AppSettings.shared.meetingRecordHotkeyKeyCode
    @State private var meetingRecMods: UInt32 = AppSettings.shared.meetingRecordHotkeyModifiers
    @State private var quickEntryKeyCode: UInt32 = AppSettings.shared.quickEntryHotkeyKeyCode
    @State private var quickEntryMods: UInt32 = AppSettings.shared.quickEntryHotkeyModifiers
    @State private var swapKeyCode: UInt32 = AppSettings.shared.dictationSwapHotkeyKeyCode
    @State private var swapMods: UInt32 = AppSettings.shared.dictationSwapHotkeyModifiers
    @State private var promptKeyCode: UInt32 = AppSettings.shared.dictationPromptHotkeyKeyCode
    @State private var promptMods: UInt32 = AppSettings.shared.dictationPromptHotkeyModifiers
    @State private var dictationAutoPaste: Bool = AppSettings.shared.dictationAutoPaste
    @State private var dictationUsePolished: Bool = AppSettings.shared.dictationUsePolished
    @State private var whisperUseGPU: Bool = AppSettings.shared.whisperUseGPU
    @State private var whisperFlashAttn: Bool = AppSettings.shared.whisperFlashAttention
    @State private var whisperLanguage: String = AppSettings.shared.whisperLanguage
    @State private var autoExtractPeople: Bool = AppSettings.shared.autoExtractPeople
    @State private var captureDelegated: Bool = AppSettings.shared.captureDelegatedTasks
    @State private var defaultSmartViewID: String = AppSettings.shared.defaultSmartViewID ?? ""
    @State private var defaultTaskAssignToMe: Bool = AppSettings.shared.defaultTaskAssignToMe
    @State private var defaultTaskDueDate: String = AppSettings.shared.defaultTaskDueDate
    @State private var defaultTaskPriority: String = AppSettings.shared.defaultTaskPriority
    @State private var userName: String = AppSettings.shared.userName
    @State private var userNameAliases: String = AppSettings.shared.userNameAliases.joined(separator: ", ")
    // Mic / transcription / backup
    @State private var preferBluetoothMic: Bool = AppSettings.shared.preferBluetoothMic
    @State private var whisperVADEnabled: Bool = AppSettings.shared.whisperVADEnabled
    @State private var backupEnabled: Bool = AppSettings.shared.backupEnabled
    @State private var backupDir: String = AppSettings.shared.backupDir.path
    @State private var backupIncludeAudio: Bool = AppSettings.shared.backupIncludeAudio
    @State private var storageBusy = false
    @State private var storageStatus: String = ""
    @State private var allowRemoteOllama: Bool = AppSettings.shared.allowRemoteOllamaEndpoint
    @State private var collectMetrics: Bool = AppSettings.shared.collectMetrics
    @State private var obsidianVaultPath: String = ExportSettings().vaultPath
    @State private var obsidianTemplate: String = ExportSettings().filenameTemplate

    @StateObject private var mcp = MCPInstaller()
    @State private var mcpStatus: String = ""
    @State private var configCopied: Bool = false
    @State private var notionAPIKeyDraft: String = AppSettings.shared.notionAPIKey ?? ""
    @State private var notionDatabaseDraft: String = AppSettings.shared.notionActionItemsDatabaseID ?? ""
    @State private var showingNotionKeyEditor: Bool = false
    @State private var linearKeyDraft: String = AppSettings.shared.linearAPIKey ?? ""
    @State private var linearSaved: Bool = false
    @State private var showHealthCheck = false
    @State private var linearTeams: [TaskSyncService.LinearTeamRef] = []
    @State private var linearTeamID: String = AppSettings.shared.linearDefaultTeamID ?? ""
    @State private var linearTeamsLoading: Bool = false
    @State private var linearTeamsError: String?
    @ObservedObject private var drive = GoogleDriveService.shared
    @State private var googleClientIDDraft: String = AppSettings.shared.googleClientID ?? ""
    @State private var googleSecretDraft: String = AppSettings.shared.googleClientSecret ?? ""
    @State private var googleFolderDraft: String = AppSettings.shared.googleDriveFolderName

    /// Marketing version + build id (the build id is the git commit, stamped by
    /// `make`). Lets the user confirm the installed app is the latest build.
    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Settings categories (comp: a left category rail rather than top tabs).
    /// Same content as before — the technical bits stay in an Advanced basement.
    enum SettingsCategory: String, CaseIterable, Identifiable {
        case general, recording, notifications, privacy, connections, automation, advanced
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: return "General"
            case .recording: return "Recording"
            case .notifications: return "Notifications"
            case .privacy: return "Privacy & data"
            case .connections: return "Connections"
            case .automation: return "Automation"
            case .advanced: return "Advanced"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .recording: return "mic"
            case .notifications: return "bell"
            case .privacy: return "lock.shield"
            case .connections: return "link"
            case .automation: return "bolt.horizontal"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }
    @State private var category: SettingsCategory = .general

    var body: some View {
        HStack(spacing: 0) {
            // Left category rail (comp).
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .scaledFont(17, weight: .heavy, kind: .display)
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 12)
                ForEach(SettingsCategory.allCases) { c in
                    categoryRow(c)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(MSSecondaryButtonStyle())
                    Button("Done") { save(); dismiss() }
                        .buttonStyle(MSPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(12)
            .frame(width: 220)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(NDS.sidebarBg)

            Divider().overlay(NDS.divider)

            // Content pane — each category is a self-scrolling Form.
            categoryContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { mcp.refreshStatus() }
        .sheet(isPresented: $showHealthCheck) {
            HealthCheckSheet(isPresented: $showHealthCheck)
        }
    }

    private func categoryRow(_ c: SettingsCategory) -> some View {
        let active = category == c
        return Button { category = c } label: {
            HStack(spacing: 10) {
                Image(systemName: c.icon)
                    .scaledFont(13, weight: active ? .semibold : .regular)
                    .foregroundStyle(active ? NDS.lilac : NDS.textSecondary)
                    .frame(width: 18)
                Text(c.label)
                    .scaledFont(13, weight: active ? .bold : .medium)
                    .foregroundStyle(active ? NDS.textPrimary : NDS.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(active ? NDS.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var categoryContent: some View {
        switch category {
        case .general:       generalTab
        case .recording:     recordingTab
        case .notifications: notificationsTab
        case .privacy:       privacyTab
        case .connections:   connectionsTab
        case .automation:    WebhookSettingsView()   // 6-F / 6-E
        case .advanced:      advancedTab
        }
    }

    // MARK: - General

    @ViewBuilder private var generalTab: some View {
        Form {
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersionString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Use this to confirm the installed app matches the latest build (the build id is the git commit).")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    showHealthCheck = true
                } label: {
                    Label("Run a health check", systemImage: "stethoscope")
                }
                Text("Checks the transcription model, Ollama, disk space, and macOS permissions.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("You") {
                TextField("Your name", text: $userName)
                TextField("Also called (comma-separated)", text: $userNameAliases)
                Text("Used to recognize which action items are yours and to avoid adding yourself as a contact. Add any nicknames or names people call you (e.g. \"Ty, the eng lead\").")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Calendar") {
                Toggle("Only show meetings with a conference link", isOn: $filterToConference)
                Text("MeetingScribe reads every calendar connected to macOS Calendar.app — your Apple/iCloud calendars plus any Google or Outlook accounts you add. Connect as many Google accounts as you like (work + personal); each one's calendars appear below to switch on or off.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        CalendarAccountsHelper.openInternetAccounts()
                    } label: {
                        Label("Add Google account…", systemImage: "person.crop.circle.badge.plus")
                    }
                    Button {
                        CalendarAccountsHelper.importAppleCalendars(into: calendar)
                    } label: {
                        Label("Import Apple calendars", systemImage: "calendar.badge.plus")
                    }
                }
                Text("“Add Google account…” opens System Settings → Internet Accounts — sign in to each Google account you want and its calendars sync into macOS. “Import Apple calendars” grants Calendar access and pulls in your Apple/iCloud calendars. Everything you connect shows up in the list below.")
                    .font(.caption2).foregroundStyle(.secondary)
                CalendarPickerSection()
            }
            Section("Task defaults") {
                Picker("Default smart view", selection: $defaultSmartViewID) {
                    Text("All tasks (no preference)").tag("")
                    ForEach(actionItems.savedTaskViews) { v in
                        Text(v.name).tag(v.id)
                    }
                }
                Text("Which Tasks view opens by default when you switch to the Tasks tab.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Assign new tasks to me", isOn: $defaultTaskAssignToMe)
                Picker("Default due date", selection: $defaultTaskDueDate) {
                    Text("None").tag("none")
                    Text("Today").tag("today")
                    Text("Tomorrow").tag("tomorrow")
                    Text("Next week").tag("nextWeek")
                }
                Picker("Default priority", selection: $defaultTaskPriority) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                    Text("Urgent").tag("urgent")
                }
                Text("Used by the inline “+ Add task” field. You can still override per-task by typing !high, @sarah, +project, or a date.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Recording

    @ViewBuilder private var recordingTab: some View {
        Form {
            Section("Capture") {
                Toggle("Record microphone", isOn: $captureMic)
                Toggle("Record system audio", isOn: $captureSystem)
                Toggle("Auto-start when a calendar meeting begins", isOn: $autoRecord)
                Text("Auto-start ONLY fires if MeetingScribe detects you've actually joined the call (Zoom app open with a meeting window, or a browser tab on meet.google.com). Time blocks and meetings you skip won't trigger a surprise recording.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Live transcript runs every 5 minutes during a recording.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Transcribe live during the meeting", isOn: $liveTranscriptionEnabled)
                Toggle("Defer to batch on battery / low-power", isOn: $deferLiveOnBattery)
                    .disabled(!liveTranscriptionEnabled)
                Text("Deferring skips the per-chunk Whisper cold-loads while unplugged; the full transcript is produced in one pass when you stop. Currently: \(ResourceGovernor.shared.statusDescription).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Screen recordings") {
                Toggle("Analyze frames with a local vision model", isOn: $useScreenVisionModel)
                TextField("Vision model", text: $screenVisionModel)
                    .disabled(!useScreenVisionModel)
                Text("When analyzing a screen recording, also \"watch\" sampled frames with a local multimodal model (auto-pulled on first use, a few GB). Off = OCR + transcript only, no download. Either way, nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Meeting recording") {
                HStack {
                    Text("Global start / stop recording")
                    Spacer()
                    HotkeyRecorder(keyCode: $meetingRecKeyCode, modifiers: $meetingRecMods)
                    Menu("Presets") {
                        ForEach(quickPresets, id: \.label) { preset in
                            Button(preset.label) {
                                meetingRecKeyCode = preset.key
                                meetingRecMods = preset.mods
                            }
                        }
                    }
                    .frame(width: 90)
                }
                Text("A system-wide shortcut that starts an ad-hoc recording when idle and stops it when recording — works even when MeetingScribe isn't focused. Default: ⌥⌘R.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text("Quick entry (task / note)")
                    Spacer()
                    HotkeyRecorder(keyCode: $quickEntryKeyCode, modifiers: $quickEntryMods)
                    Menu("Presets") {
                        ForEach(quickPresets, id: \.label) { preset in
                            Button(preset.label) {
                                quickEntryKeyCode = preset.key
                                quickEntryMods = preset.mods
                            }
                        }
                    }
                    .frame(width: 90)
                }
                Text("Pops a small capture bar over any app to add a task or note without switching windows — type, press Return, and you're back. If a recording is live, the entry links to it. Default: ⌥⌘Space.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Dictation (Whispr Flow)") {
                HStack {
                    Text("Start / stop dictation")
                    Spacer()
                    HotkeyRecorder(keyCode: $hotkeyKeyCode, modifiers: $hotkeyMods)
                    Menu("Presets") {
                        ForEach(quickPresets, id: \.label) { preset in
                            Button(preset.label) {
                                hotkeyKeyCode = preset.key
                                hotkeyMods = preset.mods
                            }
                        }
                    }
                    .frame(width: 90)
                }
                HStack {
                    Text("Swap raw ↔ polished")
                    Spacer()
                    HotkeyRecorder(keyCode: $swapKeyCode, modifiers: $swapMods)
                    Menu("Presets") {
                        ForEach(quickPresets, id: \.label) { preset in
                            Button(preset.label) {
                                swapKeyCode = preset.key
                                swapMods = preset.mods
                            }
                        }
                    }
                    .frame(width: 90)
                }
                HStack {
                    Text("Rewrite as AI prompt")
                    Spacer()
                    HotkeyRecorder(keyCode: $promptKeyCode, modifiers: $promptMods)
                    Menu("Presets") {
                        ForEach(quickPresets, id: \.label) { preset in
                            Button(preset.label) {
                                promptKeyCode = preset.key
                                promptMods = preset.mods
                            }
                        }
                    }
                    .frame(width: 90)
                }
                Text("Click a shortcut box, then press ANY key combination to set it. After dictating, press the swap shortcut to replace the inserted text with the other version (raw ↔ polished) in place.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("The AI-prompt shortcut is optional. It rewrites your dictation into a structured prompt using the TCREI framework (Task, Context, References, Evaluate, Iterate) — ideal when you're dictating a request to paste into an AI. Default: F7. Press the swap shortcut to flip back to raw/polished.")
                    .font(.caption2).foregroundStyle(.secondary)
                Toggle("Paste transcription at cursor after dictation", isOn: $dictationAutoPaste)
                Toggle("Use the polished (cleaned-up) version by default", isOn: $dictationUsePolished)
                Text("Polished output runs the raw transcript through Ollama for grammar/filler cleanup (Whispr-Flow style). It adds a brief delay before pasting; the swap shortcut flips to the raw version instantly.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Notifications

    @ViewBuilder private var notificationsTab: some View {
        Form {
            Section("Notifications") {
                Toggle("Notify me at meeting start time", isOn: $notifyAtStart)
                Toggle("Daily morning brief (8am)", isOn: $dailyBrief)
                    .onChange(of: dailyBrief) { _, v in
                        AppSettings.shared.dailyBriefEnabled = v
                        NotificationCenter.default.post(name: .meetingScribeSettingsChanged, object: nil)
                    }
            }
            Section("Impromptu detection") {
                Toggle("Prompt to record when a Zoom call / Meet tab is detected", isOn: $detectZoom)
                MeetingDetectionSettingsView()
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Privacy & data

    @ViewBuilder private var privacyTab: some View {
        Form {
            Section("Storage") {
                HStack {
                    TextField("Storage folder", text: $storageDir)
                    Button("Choose…") { pickFolder() }
                }
                if VaultStorageManager.isInICloud(URL(fileURLWithPath: (storageDir as NSString).expandingTildeInPath)) {
                    Text("Your vault is in an iCloud-synced folder. iCloud can evict files to the cloud, so they aren't always downloaded — which can break recording/transcription. Move it to fast local storage and back up to iCloud instead.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        migrateToLocalStorage()
                    } label: {
                        Label("Move vault to local storage", systemImage: "internaldrive")
                    }
                    .disabled(storageBusy)
                }
                if !storageStatus.isEmpty {
                    HStack(spacing: 6) {
                        if storageBusy { ProgressView().controlSize(.small) } // design-lint:allow
                        Text(storageStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Backup") {
                Toggle("Back up vault to iCloud", isOn: $backupEnabled)
                    .onChange(of: backupEnabled) { _, v in AppSettings.shared.backupEnabled = v }
                Text("Additive backup — files are only ever copied to iCloud, never deleted there. Runs automatically about once a day.")
                    .font(.caption2).foregroundStyle(.secondary)
                if backupEnabled {
                    HStack {
                        TextField("Backup folder", text: $backupDir)
                        Button("Choose…") { pickBackupFolder() }
                    }
                    Toggle("Include audio files in backup", isOn: $backupIncludeAudio)
                        .onChange(of: backupIncludeAudio) { _, v in AppSettings.shared.backupIncludeAudio = v }
                    Text(backupIncludeAudio
                         ? "Backs up everything (audio + transcripts + notes). Safest, uses the most iCloud space."
                         : "Backs up transcripts, notes, and data only — large audio stays local.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button { backUpNow() } label: { Label("Back up now", systemImage: "arrow.up.doc") }
                            .disabled(storageBusy)
                        Spacer()
                        if AppSettings.shared.lastBackupAt > 0 {
                            Text("Last: \(Self.relativeDate(AppSettings.shared.lastBackupAt))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section("Microphone & transcription") {
                Toggle("Prefer AirPods / Bluetooth mic", isOn: $preferBluetoothMic)
                    .onChange(of: preferBluetoothMic) { _, v in AppSettings.shared.preferBluetoothMic = v }
                Text("When AirPods or another Bluetooth mic is connected, record from it and never fall back to the Mac's built-in mic.")
                    .font(.caption2).foregroundStyle(.secondary)
                Toggle("Speech detection (VAD) before transcription", isOn: $whisperVADEnabled)
                    .onChange(of: whisperVADEnabled) { _, v in AppSettings.shared.whisperVADEnabled = v }
                Text("Only transcribes speech, so silent/non-speech stretches can't be hallucinated into repeated nonsense. Downloads a small model the first time.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Maintenance") {
                HStack {
                    Button {
                        runDuplicateFix()
                    } label: {
                        Label(fixingDuplicates ? "Fixing…" : "Fix duplicate people & meetings",
                              systemImage: "person.2.slash")
                    }
                    .disabled(fixingDuplicates)
                    if fixingDuplicates { ProgressView().controlSize(.small) }
                }
                if let dedupeResult {
                    Text(dedupeResult).font(.caption).foregroundStyle(.secondary)
                }
                Text("Merges people who share a phone number or name into one record (combining their info), and collapses meetings with the same name and start time into a single copy. Removed meeting copies are moved to a recoverable “_DuplicateMeetingsTrash” folder — nothing is hard-deleted.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("People (second brain)") {
                Toggle("Auto-extract people from meetings", isOn: $autoExtractPeople)
                Text("After a meeting is summarized, a second on-device Ollama pass lists the people mentioned in the transcript. Strong matches link to existing people automatically; uncertain ones appear as suggestions on the Today tab. Nothing leaves your machine.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Capture others' action items as “delegated / waiting-on”", isOn: $captureDelegated)
                Text("By default, meeting extraction keeps only action items that are yours. Enable this to also capture items owned by other participants, tagged so a “Delegated” view can track what you're waiting on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Usage metrics") {
                Toggle("Collect local usage metrics", isOn: $collectMetrics)
                    .onChange(of: collectMetrics) { _, v in AppSettings.shared.collectMetrics = v }
                Text("Off by default. Counts stay on this Mac (UserDefaults) and are NEVER uploaded — there's no network code for them. Lets you see how much you use MeetingScribe.")
                    .font(.caption2).foregroundStyle(.secondary)
                if collectMetrics {
                    ForEach(MetricsStore.shared.snapshot(), id: \.0) { event, count in
                        HStack { Text(event.label); Spacer(); Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
                            .font(.caption)
                    }
                }
            }
            Section("Diagnostics") {
                HStack {
                    Button {
                        NSWorkspace.shared.open(AppLog.fileURL)
                    } label: {
                        Label("Open app error log", systemImage: "ladybug")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }
                Text("App-wide errors (recording, transcription, summary, polish, Notion) are logged at \(AppLog.fileURL.path). Send this file if you hit a bug.")
                    .font(.caption2).foregroundStyle(.secondary)
                DiagnosticsExportRow()
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Connections

    @ViewBuilder private var connectionsTab: some View {
        Form {
            PhoneAccessSection()
            TailscaleSyncSection()
            Section("Integrations — Task sync") {
                Text("Pull issues/tasks into the Action Items tab. Both APIs are free — no usage charges, and nothing is sent to an AI. Notion uses the key set under Advanced → Notion MCP (plus its database ID).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField("Linear personal API key (lin_api_…)", text: $linearKeyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button(linearSaved ? "Saved" : "Save") {
                        let t = linearKeyDraft.trimmingCharacters(in: .whitespaces)
                        AppSettings.shared.linearAPIKey = t.isEmpty ? nil : t
                        linearSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { linearSaved = false }
                    }
                }
                Text("Linear → Settings → Security & access → Personal API keys → New key. Read access is enough; write access is needed for Push to Linear.")
                    .font(.caption2).foregroundStyle(.tertiary)

                // Default team for "Push to Linear" — issues are created
                // under this team. Loaded on demand from the saved key.
                HStack {
                    if linearTeams.isEmpty {
                        Button(linearTeamsLoading ? "Loading…" : "Choose default team") {
                            Task { await loadLinearTeams() }
                        }
                        .disabled(linearTeamsLoading
                                  || (AppSettings.shared.linearAPIKey ?? "").isEmpty)
                        if let name = AppSettings.shared.linearDefaultTeamName, !name.isEmpty {
                            Text("Current: \(name)").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Default team", selection: $linearTeamID) {
                            Text("None").tag("")
                            ForEach(linearTeams) { t in
                                Text("\(t.name) (\(t.key))").tag(t.id)
                            }
                        }
                        .onChange(of: linearTeamID) { _, new in
                            let team = linearTeams.first { $0.id == new }
                            AppSettings.shared.linearDefaultTeamID = new.isEmpty ? nil : new
                            AppSettings.shared.linearDefaultTeamName = team?.name
                        }
                    }
                }
                if let err = linearTeamsError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                } else {
                    Text("Push to Linear creates issues under this team.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                if let last = AppSettings.shared.lastTaskSync {
                    Text("Last sync: \(last.formatted(date: .abbreviated, time: .shortened)) — sync from the Action Items tab.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Section("Google Drive export") {
                HStack(spacing: 6) {
                    Image(systemName: drive.isConnected ? "checkmark.seal.fill" : "circle.dashed")
                        .foregroundStyle(drive.isConnected ? .green : .secondary)
                    Text(drive.isConnected ? "Connected" : "Not connected").font(.callout.weight(.medium))
                    if drive.isWorking { ProgressView().controlSize(.small) } // design-lint:allow
                }
                Text("Export voice notes and meeting notes to a folder in your Google Drive. One-time setup: create an OAuth client so the app can talk to your Drive (Google requires this — it's tied to your account).")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("How to get a client ID & secret") {
                    Text("""
                    1. Go to console.cloud.google.com → create (or pick) a project.
                    2. APIs & Services → Library → enable **Google Drive API**.
                    3. APIs & Services → OAuth consent screen → External → add yourself as a Test user.
                    4. Credentials → Create credentials → OAuth client ID → **Desktop app**.
                    5. Copy the Client ID and Client secret below.
                    """)
                    .font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                }
                SecureField("OAuth Client ID", text: $googleClientIDDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("OAuth Client secret", text: $googleSecretDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Drive folder name", text: $googleFolderDraft)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                    Spacer()
                    if drive.isConnected {
                        Button("Disconnect", role: .destructive) { drive.disconnect() }
                    } else {
                        Button("Connect Google Drive") {
                            AppSettings.shared.googleClientID = googleClientIDDraft.trimmingCharacters(in: .whitespaces)
                            AppSettings.shared.googleClientSecret = googleSecretDraft.trimmingCharacters(in: .whitespaces)
                            AppSettings.shared.googleDriveFolderName = googleFolderDraft.trimmingCharacters(in: .whitespaces)
                            Task { await drive.connect() }
                        }
                        .buttonStyle(MSPrimaryButtonStyle())
                        .disabled(googleClientIDDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                  || googleSecretDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                  || drive.isWorking)
                    }
                }
                .onChange(of: googleFolderDraft) { _, v in
                    AppSettings.shared.googleDriveFolderName = v.trimmingCharacters(in: .whitespaces)
                }
                if let status = drive.lastStatus {
                    Text(status).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            Section("Export to Obsidian") {
                HStack {
                    TextField("Obsidian vault path (leave blank to ask)", text: $obsidianVaultPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            obsidianVaultPath = url.path
                        }
                    }
                }
                HStack {
                    Text("Filename template")
                    Spacer()
                    TextField("{date}-{slug}", text: $obsidianTemplate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                Text("Tokens: {date} (YYYY-MM-DD), {title}, {slug}. Each meeting's Summary tab has an 'Export to Obsidian' button that writes a Markdown note to this vault.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced (technical basement)

    @ViewBuilder private var advancedTab: some View {
        Form {
            Section("Software Update") {
                HStack {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.down.circle")
                    }
                    .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let last = updater.lastChecked {
                        Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if updater.isUpdaterConfigured {
                    Toggle("Check for updates automatically", isOn: $updater.automaticChecks)
                    Text("Pulls the latest release from this repo and installs it. Each update is downloaded from the project's GitHub Releases and verified against the app's built-in signing key before it's applied — no reinstall by hand.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 4) {
                        Text("Feed:").font(.caption2).foregroundStyle(.secondary)
                        Text(updater.feedURLString)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Label("In-app updates aren't available in this build (no signing key).",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Reinstall from source with install.sh to get the latest. Signed auto-updates require a release built through the GitHub Actions release workflow (see RELEASING.md).")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            CrossDeviceSyncSection()

            Section("MCP Server (for Claude Desktop / Claude Code)") {
                HStack(spacing: 6) {
                    Image(systemName: mcp.binaryExists ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(mcp.binaryExists ? .green : .orange)
                    Text(mcp.binaryExists ? "Bundled" : "MCP binary not found in app bundle")
                        .font(.caption)
                }
                HStack {
                    Text("Binary path").font(.caption)
                    Spacer()
                    Text(mcp.binaryURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
                HStack {
                    Button {
                        mcp.copyConfigSnippetToPasteboard()
                        configCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { configCopied = false }
                    } label: {
                        Label(configCopied ? "Copied!" : "Copy config snippet",
                              systemImage: configCopied ? "checkmark" : "doc.on.doc")
                    }

                    Button {
                        installInClaudeDesktop()
                    } label: {
                        Label(mcp.installedInClaudeDesktop ? "Reinstall in Claude Desktop" : "Install in Claude Desktop",
                              systemImage: "tray.and.arrow.down")
                    }
                    .disabled(!mcp.binaryExists)

                    if mcp.installedInClaudeDesktop {
                        Button {
                            try? mcp.uninstallFromClaudeDesktop()
                        } label: {
                            Label("Uninstall", systemImage: "tray.and.arrow.up")
                        }
                    }
                }
                HStack {
                    Button {
                        Task { await runSelfTest() }
                    } label: {
                        Label("Test connection", systemImage: "play.circle")
                    }
                    .disabled(!mcp.binaryExists)
                    Button {
                        mcp.revealBinaryInFinder()
                    } label: {
                        Label("Reveal binary", systemImage: "folder")
                    }
                    .disabled(!mcp.binaryExists)
                }
                if !mcpStatus.isEmpty {
                    Text(mcpStatus)
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(mcp.installedInClaudeDesktop
                     ? "Registered in Claude Desktop. Quit and reopen Claude Desktop, then ask Claude to list your meetings."
                     : "Not registered. Click 'Install in Claude Desktop' or copy the snippet and paste it into your MCP client.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Show config snippet") {
                    ScrollView {
                        Text(mcp.configSnippet())
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 110)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            Section("Notion MCP") {
                HStack(spacing: 6) {
                    Image(systemName: mcp.notionBinaryExists ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(mcp.notionBinaryExists ? .green : .orange)
                    Text(mcp.notionBinaryExists ? "Bundled" : "NotionMCP binary not found")
                        .font(.caption)
                }
                Text("Lets the in-app Chat (and Claude Desktop, if you install Notion there) query your Notion workspace, and lets you push action items into a Notion database. Create an integration at notion.so → Settings → Integrations, copy the Internal Integration Secret, and paste it below. Then share the pages/databases you want with that integration.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        showingNotionKeyEditor = true
                    } label: {
                        Label("Set Notion API key", systemImage: "key")
                    }
                    Button {
                        installNotion()
                    } label: {
                        Label(mcp.notionInstalledInClaudeDesktop ? "Reinstall Notion in Claude Desktop"
                                                                  : "Install Notion in Claude Desktop",
                              systemImage: "tray.and.arrow.down")
                    }
                    .disabled(!mcp.notionBinaryExists)
                    if mcp.notionInstalledInClaudeDesktop {
                        Button {
                            try? mcp.uninstallNotionFromClaudeDesktop()
                        } label: {
                            Label("Uninstall", systemImage: "tray.and.arrow.up")
                        }
                    }
                }
                Text(mcp.notionInstalledInClaudeDesktop
                     ? "Registered with Claude Desktop. Quit + reopen Claude Desktop to load it."
                     : "Not registered yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showingNotionKeyEditor) {
                NotionKeyEditor(initialKey: notionAPIKeyDraft) { newKey in
                    notionAPIKeyDraft = newKey ?? ""
                    // Persist into the Claude Desktop config too if Notion
                    // is already registered (otherwise just hold for the
                    // next install).
                    if mcp.notionInstalledInClaudeDesktop {
                        installNotion()
                    }
                }
            }

            Section("Whisper.cpp") {
                TextField("whisper-cli binary", text: $whisperBinary)
                TextField("GGML model path", text: $whisperModel)
                HStack {
                    Text("Language")
                    Spacer()
                    Picker("", selection: $whisperLanguage) {
                        Text("Auto-detect").tag("auto")
                        Text("English (en)").tag("en")
                        Text("Spanish (es)").tag("es")
                        Text("French (fr)").tag("fr")
                        Text("German (de)").tag("de")
                        Text("Italian (it)").tag("it")
                        Text("Portuguese (pt)").tag("pt")
                        Text("Japanese (ja)").tag("ja")
                        Text("Chinese (zh)").tag("zh")
                        Text("Korean (ko)").tag("ko")
                        Text("Dutch (nl)").tag("nl")
                        Text("Russian (ru)").tag("ru")
                        Text("Hindi (hi)").tag("hi")
                    }
                    .frame(width: 200)
                }
                Text("Auto-detect works well for most languages. Force a specific language only if detection is wrong.")
                    .font(.caption2).foregroundStyle(.secondary)
                Toggle("Use GPU (Metal) acceleration", isOn: $whisperUseGPU)
                Text("Disable if transcription returns empty output. Some Apple Silicon hardware + recent ggml builds misbehave; CPU mode is slower but always works.")
                    .font(.caption2).foregroundStyle(.secondary)
                Toggle("Enable flash-attention", isOn: $whisperFlashAttn)
                Text("Default OFF on macOS. flash-attn produces empty transcripts on pre-M5 Apple Silicon (M1–M4) with the current homebrew whisper.cpp. Only re-enable if a newer whisper-cpp build fixes this.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([TranscriptionLog.fileURL])
                    } label: {
                        Label("Reveal transcription log", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        NSWorkspace.shared.open(TranscriptionLog.fileURL)
                    } label: {
                        Label("Open log", systemImage: "doc.text")
                    }
                }
                Text("Every whisper invocation is logged with its full command, exit code, and stderr at \(TranscriptionLog.fileURL.path). Auto-rotated at ~2 MB.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Ollama") {
                TextField("Server URL", text: $ollamaURL)
                TextField("Model", text: $ollamaModel)
                Text("Recommended: \(AppSettings.recommendedOllamaModel) — strongest small open-weight model for tool calling. Install with `ollama pull \(AppSettings.recommendedOllamaModel)`. Avoid llama3.1:8b: it leaks tool-call JSON as plain text and over-fires safety refusals on benign prompts.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text("This Mac: \(HardwareProfile.summary)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Use recommended") { ollamaModel = HardwareProfile.recommendedSummaryModel }
                        .font(.caption)
                }
                OllamaStatusRow()
                Toggle("Allow a non-local Ollama endpoint", isOn: $allowRemoteOllama)
                Text("Off by default. MeetingScribe only sends transcripts to a local LLM (127.0.0.1). Turn this on only if you intentionally run Ollama on another machine — your meeting content will leave this device.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private struct HotkeyPreset {
        let label: String; let key: UInt32; let mods: UInt32
    }

    private let quickPresets: [HotkeyPreset] = [
        .init(label: "F5",                       key: UInt32(kVK_F5),  mods: 0),
        .init(label: "⌥Space",                   key: UInt32(kVK_Space), mods: UInt32(optionKey)),
        .init(label: "⌘⇧D",                      key: UInt32(kVK_ANSI_D), mods: UInt32(cmdKey | shiftKey)),
        .init(label: "⌥` (option backtick)",     key: 50,              mods: UInt32(optionKey)),
        .init(label: "⌃⌥V",                      key: UInt32(kVK_ANSI_V), mods: UInt32(controlKey | optionKey))
    ]

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { storageDir = url.path }
    }

    private func pickBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            backupDir = url.path
            AppSettings.shared.backupDir = url
        }
    }

    /// Copies the vault from its current (iCloud) location to fast local storage,
    /// then points the app at the local copy. Non-destructive — the original is
    /// left in place; the user can delete it once they've confirmed the move.
    /// Run both dedup jobs (people + meetings) and report what changed.
    private func runDuplicateFix() {
        guard !fixingDuplicates else { return }
        fixingDuplicates = true
        dedupeResult = nil
        let mgr = manager
        Task { @MainActor in
            let people = PeopleStore.shared.deduplicate()   // (merged groups, removed records)
            let meetingsRemoved = mgr.deduplicateMeetings()
            var parts: [String] = []
            if people.removed > 0 {
                parts.append("merged \(people.removed) duplicate \(people.removed == 1 ? "person" : "people") into \(people.merged) record\(people.merged == 1 ? "" : "s")")
            }
            if meetingsRemoved > 0 {
                parts.append("collapsed \(meetingsRemoved) duplicate meeting\(meetingsRemoved == 1 ? "" : "s")")
            }
            dedupeResult = parts.isEmpty ? "No duplicates found — everything's already clean."
                                         : "Done — " + parts.joined(separator: " · ") + "."
            fixingDuplicates = false
        }
    }

    private func migrateToLocalStorage() {
        let src = AppSettings.shared.storageDir
        let dst = VaultStorageManager.localDefaultURL
        storageBusy = true
        storageStatus = "Copying vault to local storage…"
        Task.detached(priority: .utility) {
            do {
                let p = try VaultStorageManager.copyVault(from: src, to: dst) { prog in
                    let mb = Double(prog.bytes) / 1_000_000
                    Task { @MainActor in storageStatus = "Copying… \(prog.files) files (\(Int(mb)) MB)" }
                }
                await MainActor.run {
                    AppSettings.shared.storageDir = dst
                    storageDir = dst.path
                    storageBusy = false
                    let mb = Double(p.bytes) / 1_000_000
                    storageStatus = "Moved to \(dst.path). Copied \(p.files) files (\(Int(mb)) MB). Your original folder was left untouched — delete it once you've confirmed everything's here."
                }
            } catch {
                await MainActor.run {
                    storageBusy = false
                    storageStatus = "Move failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func backUpNow() {
        let vault = AppSettings.shared.storageDir
        let dst = AppSettings.shared.backupDir
        let includeAudio = AppSettings.shared.backupIncludeAudio
        storageBusy = true
        storageStatus = "Backing up…"
        Task.detached(priority: .utility) {
            do {
                let p = try VaultStorageManager.backup(vault: vault, to: dst, includeAudio: includeAudio) { prog in
                    Task { @MainActor in storageStatus = "Backing up… \(prog.files) files" }
                }
                await MainActor.run {
                    AppSettings.shared.lastBackupAt = Date().timeIntervalSince1970
                    storageBusy = false
                    let mb = Double(p.bytes) / 1_000_000
                    storageStatus = "Backup complete: \(p.files) files (\(Int(mb)) MB) → \(dst.lastPathComponent)."
                }
            } catch {
                await MainActor.run {
                    storageBusy = false
                    storageStatus = "Backup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    static func relativeDate(_ epoch: Double) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: Date(timeIntervalSince1970: epoch), relativeTo: Date())
    }

    private func installInClaudeDesktop() {
        do {
            let url = try mcp.installInClaudeDesktop()
            mcpStatus = "Installed. Updated: \(url.path). Restart Claude Desktop."
        } catch {
            mcpStatus = "Install failed: \(error.localizedDescription)"
        }
    }

    /// Fetches the Linear teams for the saved API key so the user can pick a
    /// default. Pre-selects the previously-chosen team if still present.
    private func loadLinearTeams() async {
        guard let key = AppSettings.shared.linearAPIKey, !key.isEmpty else {
            linearTeamsError = "Save your Linear API key first."
            return
        }
        linearTeamsLoading = true
        linearTeamsError = nil
        defer { linearTeamsLoading = false }
        do {
            let teams = try await TaskSyncService.fetchLinearTeams(apiKey: key)
            linearTeams = teams
            if teams.first(where: { $0.id == linearTeamID }) == nil {
                linearTeamID = AppSettings.shared.linearDefaultTeamID ?? ""
            }
        } catch {
            linearTeamsError = "Couldn't load teams: \(error.localizedDescription)"
        }
    }

    private func installNotion() {
        do {
            let trimmed = notionAPIKeyDraft.trimmingCharacters(in: .whitespaces)
            let url = try mcp.installNotionInClaudeDesktop(notionAPIKey: trimmed.isEmpty ? nil : trimmed)
            mcpStatus = "Notion MCP registered in \(url.lastPathComponent). Restart Claude Desktop."
        } catch {
            mcpStatus = "Notion install failed: \(error.localizedDescription)"
        }
    }

    private func runSelfTest() async {
        mcpStatus = "Testing…"
        switch await mcp.selfTest() {
        case .ok(let s):      mcpStatus = s
        case .failure(let e): mcpStatus = e
        }
    }

    private func save() {
        let s = AppSettings.shared
        // Only update the storage dir from a real, non-empty path. An empty or
        // whitespace field would resolve against the app's cwd ("/") and
        // corrupt the setting (which previously broke recording).
        let rawDir = storageDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawDir.isEmpty {
            let expanded = (rawDir as NSString).expandingTildeInPath
            if expanded != "/" { s.storageDir = URL(fileURLWithPath: expanded) }
        }
        s.whisperBinary = whisperBinary
        s.whisperModel = whisperModel
        if let u = URL(string: ollamaURL) { s.ollamaURL = u }
        s.allowRemoteOllamaEndpoint = allowRemoteOllama
        s.ollamaModel = ollamaModel
        s.autoRecord = autoRecord
        s.useScreenVisionModel = useScreenVisionModel
        s.screenVisionModel = screenVisionModel.trimmingCharacters(in: .whitespaces).isEmpty
            ? "qwen2.5vl" : screenVisionModel.trimmingCharacters(in: .whitespaces)
        s.captureMic = captureMic
        s.captureSystem = captureSystem
        s.liveTranscriptionEnabled = liveTranscriptionEnabled
        s.deferLiveTranscriptionOnBattery = deferLiveOnBattery
        s.filterToConferenceLinks = filterToConference
        s.notifyAtMeetingStart = notifyAtStart
        s.detectZoomImpromptu = detectZoom
        s.dictationHotkeyKeyCode = hotkeyKeyCode
        s.dictationHotkeyModifiers = hotkeyMods
        s.meetingRecordHotkeyKeyCode = meetingRecKeyCode
        s.meetingRecordHotkeyModifiers = meetingRecMods
        s.quickEntryHotkeyKeyCode = quickEntryKeyCode
        s.quickEntryHotkeyModifiers = quickEntryMods
        s.dictationSwapHotkeyKeyCode = swapKeyCode
        s.dictationSwapHotkeyModifiers = swapMods
        s.dictationPromptHotkeyKeyCode = promptKeyCode
        s.dictationPromptHotkeyModifiers = promptMods
        s.dictationAutoPaste = dictationAutoPaste
        s.dictationUsePolished = dictationUsePolished
        s.whisperUseGPU = whisperUseGPU
        s.whisperFlashAttention = whisperFlashAttn
        s.whisperLanguage = whisperLanguage
        s.autoExtractPeople = autoExtractPeople
        s.captureDelegatedTasks = captureDelegated
        s.defaultSmartViewID = defaultSmartViewID.isEmpty ? nil : defaultSmartViewID
        s.defaultTaskAssignToMe = defaultTaskAssignToMe
        s.defaultTaskDueDate = defaultTaskDueDate
        s.defaultTaskPriority = defaultTaskPriority
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { s.userName = trimmedName }
        s.userNameAliases = userNameAliases
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let es = ExportSettings()
        es.vaultPath = obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        es.filenameTemplate = obsidianTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        NotificationCenter.default.post(name: .meetingScribeSettingsChanged, object: nil)
        dismiss()
    }
}

extension Notification.Name {
    static let meetingScribeSettingsChanged = Notification.Name("MeetingScribeSettingsChanged")
}

@available(macOS 14.0, *)
struct NotionKeyEditor: View {
    let initialKey: String
    let onSave: (String?) -> Void
    @State private var keyDraft: String
    @State private var dbDraft: String = AppSettings.shared.notionActionItemsDatabaseID ?? ""
    @Environment(\.dismiss) private var dismiss

    init(initialKey: String, onSave: @escaping (String?) -> Void) {
        self.initialKey = initialKey
        self.onSave = onSave
        _keyDraft = State(initialValue: initialKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Notion integration").font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Integration token").font(.caption.weight(.semibold))
                SecureField("secret_…", text: $keyDraft).textFieldStyle(.roundedBorder)
                Text("From notion.so → Settings → Integrations → your integration → Internal Integration Secret. Don't forget to share the pages/databases you want accessible with this integration (click the integration name in any page's ⋯ menu).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Action Items database ID (optional)").font(.caption.weight(.semibold))
                TextField("32-char Notion database ID", text: $dbDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                Text("Action items pushed from MeetingScribe land in this database. The DB must have at least: Name (title), Status (status), Priority (select), Due (date), Meeting (rich_text). Find the ID in the page URL — the 32 hex chars before the `?`. Leave blank to create pages in the integration's default location instead.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    let trimmed = keyDraft.trimmingCharacters(in: .whitespaces)
                    AppSettings.shared.notionAPIKey = trimmed.isEmpty ? nil : trimmed
                    let dbTrimmed = dbDraft.trimmingCharacters(in: .whitespaces)
                    AppSettings.shared.notionActionItemsDatabaseID =
                        dbTrimmed.isEmpty ? nil : dbTrimmed
                    onSave(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// Helpers for connecting calendar accounts. We deliberately route Google (and
/// Outlook/Exchange) sign-in through macOS Internet Accounts rather than an
/// in-app OAuth flow: once an account is added there, macOS syncs its calendars
/// into EventKit, which MeetingScribe already reads — so any number of Google
/// accounts works, with no API keys to manage.
@available(macOS 14.0, *)
enum CalendarAccountsHelper {
    /// Opens System Settings → Internet Accounts so the user can add a Google
    /// (or Outlook/iCloud) account.
    static func openInternetAccounts() {
        // The pane's URL scheme has changed across macOS versions; try the
        // modern Settings extension id first, then older ids, then the root.
        let candidates = [
            "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.internetaccounts",
            "x-apple.systempreferences:"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Grants Calendar access (if not already granted) and re-pulls the
    /// Apple/iCloud + connected calendars into the app.
    @MainActor
    static func importAppleCalendars(into calendar: CalendarService) {
        Task {
            await calendar.requestAccess()
            calendar.refreshUpcoming(force: true)
        }
    }
}

/// Lists every calendar EventKit knows about (across all accounts the user
/// has connected to macOS Calendar.app) with a checkbox per calendar.
/// Empty set = include all (sensible default for first-run users).
@available(macOS 14.0, *)
struct CalendarPickerSection: View {
    @EnvironmentObject var calendar: CalendarService
    @State private var enabled: Set<String> = AppSettings.shared.enabledCalendarIDs
    @State private var allCalendars: [CalendarService.CalendarOption] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Calendars to include").font(.caption.weight(.semibold))
                Spacer()
                if calendar.authorized {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small) // design-lint:allow
                    .help("Re-scan connected calendars")
                }
                if !allCalendars.isEmpty {
                    Button(enabled.isEmpty || enabled.count == allCalendars.count
                           ? "Select specific…" : "Include all") {
                        if enabled.isEmpty || enabled.count == allCalendars.count {
                            enabled = Set(allCalendars.prefix(1).map { $0.id })
                        } else {
                            enabled.removeAll()
                        }
                        AppSettings.shared.enabledCalendarIDs = enabled
                        NotificationCenter.default.post(name: .meetingScribeSettingsChanged, object: nil)
                    }
                    .controlSize(.small) // design-lint:allow
                }
            }
            if !calendar.authorized {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar access hasn't been granted yet.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task { await calendar.requestAccess(); await refresh() }
                    } label: {
                        Label("Grant Calendar access", systemImage: "checkmark.shield")
                    }
                    .controlSize(.small) // design-lint:allow
                }
            } else if allCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No calendars found yet. Add accounts via System Settings → Internet Accounts, then refresh.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Refresh calendars", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small) // design-lint:allow
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allCalendars) { cal in
                        Toggle(isOn: bindingFor(cal.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: cal.color) ?? NDS.brand)
                                    .frame(width: 10, height: 10)
                                Text(cal.title).font(.callout)
                                if !cal.source.isEmpty {
                                    Text("· \(cal.source)").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                Text(enabled.isEmpty
                     ? "(All calendars currently included — no filtering.)"
                     : "Showing events from \(enabled.count) of \(allCalendars.count) calendars.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        if !calendar.authorized { await calendar.requestAccess() }
        allCalendars = await calendar.availableCalendars()
        // Re-read the persisted set (it may have been healed elsewhere) and
        // drop any saved IDs that no longer map to a live calendar — EventKit
        // churns identifiers for Google/CalDAV accounts. If every saved ID is
        // stale the set collapses to empty, which means "include all", so the
        // user's meetings keep showing instead of silently vanishing.
        enabled = AppSettings.shared.enabledCalendarIDs
        if !enabled.isEmpty {
            let live = Set(allCalendars.map { $0.id })
            let healed = enabled.intersection(live)
            if healed != enabled {
                enabled = healed
                AppSettings.shared.enabledCalendarIDs = healed
                NotificationCenter.default.post(name: .meetingScribeSettingsChanged, object: nil)
            }
        }
    }

    private func bindingFor(_ id: String) -> Binding<Bool> {
        Binding(
            get: { enabled.isEmpty || enabled.contains(id) },
            set: { newValue in
                // If we're currently in "all" mode and the user starts checking
                // individuals, switch to explicit-select mode seeded with the
                // remaining calendars.
                if enabled.isEmpty {
                    enabled = Set(allCalendars.map { $0.id })
                }
                if newValue { enabled.insert(id) } else { enabled.remove(id) }
                AppSettings.shared.enabledCalendarIDs = enabled
                NotificationCenter.default.post(name: .meetingScribeSettingsChanged, object: nil)
            }
        )
    }
}

@available(macOS 14.0, *)
struct OllamaStatusRow: View {
    @State private var reachable: Bool = false
    @State private var binaryPath: String? = nil
    @State private var starting: Bool = false
    @State private var statusText: String = ""
    private let service = OllamaService()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: indicatorSymbol).foregroundStyle(indicatorColor)
                Text(statusLine).font(.caption)
                Spacer()
                Button {
                    Task { await checkStatus() }
                } label: {
                    Label("Check", systemImage: "arrow.clockwise")
                }
                .controlSize(.small) // design-lint:allow
                .disabled(starting)

                if !reachable {
                    Button {
                        Task { await start() }
                    } label: {
                        if starting {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small) // design-lint:allow
                                Text("Starting…")
                            }
                        } else {
                            Label(binaryPath == nil ? "Install with brew" : "Start Ollama",
                                  systemImage: binaryPath == nil ? "arrow.down.app" : "play.fill")
                        }
                    }
                    .controlSize(.small) // design-lint:allow
                    .disabled(starting || binaryPath == nil)
                }
            }
            if !statusText.isEmpty {
                Text(statusText)
                    .font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .task { await checkStatus() }
    }

    private var indicatorSymbol: String {
        if reachable { return "checkmark.circle.fill" }
        return binaryPath == nil ? "exclamationmark.triangle.fill" : "circle"
    }
    private var indicatorColor: Color {
        if reachable { return .green }
        return binaryPath == nil ? .orange : .secondary
    }
    private var statusLine: String {
        if reachable { return "Ollama is running" }
        if binaryPath == nil { return "Ollama not installed (brew install ollama)" }
        return "Ollama installed but not running"
    }

    private func checkStatus() async {
        binaryPath = OllamaService.binaryPath
        reachable = await service.isReachable()
        statusText = ""
    }

    private func start() async {
        starting = true
        defer { starting = false }
        let ok = await service.ensureRunning()
        await checkStatus()
        statusText = ok
            ? "Started ollama serve. Logs: /tmp/meetingscribe-ollama.log"
            : "Auto-start failed. Try `brew services start ollama` in Terminal."
    }
}

// MARK: - Phone access (embedded web server)

/// Settings card for the embedded web server that lets an iPhone browser
/// read/edit the vault over the LAN or Tailscale. Talks to the shared
/// `WebServerController` singleton, so toggling here drives the same server
/// the app starts at launch.
@available(macOS 14.0, *)
struct PhoneAccessSection: View {
    @ObservedObject private var web = WebServerController.shared
    @State private var enabled = AppSettings.shared.webServerEnabled
    @State private var port = String(AppSettings.shared.webServerPort)
    @State private var endpoints: [WebServerController.Endpoint] = []
    @State private var qr: NSImage?
    @State private var copied = false

    var body: some View {
        Section("Phone access (web)") {
            Toggle("Serve my vault to phone browsers", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    web.setEnabled(on)
                    refresh()
                }

            Text("Browse and edit your meetings, people, projects, and tasks from your phone — all served straight off this Mac. Nothing is uploaded to a cloud database. Works on the same Wi-Fi; pair with Tailscale (free) to reach it from anywhere. See docs/PHONE_ACCESS.md.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Port")
                TextField("8765", text: $port)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Button("Apply") {
                    if let p = Int(port), (1024...65535).contains(p) {
                        web.setPort(p)
                        refresh()
                    }
                }
            }

            if web.isRunning {
                Label("Running", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            } else if let err = web.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.caption)
            }

            if web.isRunning {
                if let qr {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(nsImage: qr)
                                .resizable().interpolation(.none)
                                .frame(width: 168, height: 168)
                                .background(Color.white)
                                .cornerRadius(8)
                            Text("Scan with your phone camera")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                ForEach(endpoints) { endpoint in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(endpoint.label).font(.caption).foregroundStyle(.secondary)
                            Text(endpoint.url).font(.system(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(endpoint.url, forType: .string)
                            copied = true
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                    }
                }
                if copied {
                    Text("Link copied").font(.caption2).foregroundStyle(.green)
                }

                Button(role: .destructive) {
                    web.regenerateToken()
                    refresh()
                } label: {
                    Label("Regenerate access token", systemImage: "arrow.triangle.2.circlepath")
                }
                Text("Regenerating signs every paired phone out. Re-scan the new QR code to reconnect.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { refresh() }

        // Multi-user accounts — replaces (or supplements) the shared-token QR
        // path so people can sign in from any device with email + password.
        WebAccountsSection()
    }

    private func refresh() {
        enabled = AppSettings.shared.webServerEnabled
        port = String(AppSettings.shared.webServerPort)
        endpoints = web.isRunning ? web.endpoints() : []
        // QR encodes the first endpoint (Tailscale preferred, else LAN).
        if web.isRunning, let first = endpoints.first {
            qr = web.qrImage(for: first.url)
        } else {
            qr = nil
        }
        copied = false
    }
}

/// Accounts subsection for the phone web UI. Lists local user records with a
/// "Create account" form and a delete affordance. Lives next to the QR token
/// so users can see both paths in one place.
@available(macOS 14.0, *)
struct WebAccountsSection: View {
    @ObservedObject private var store = AccountStore.shared
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var newDisplayName = ""
    @State private var error: String?
    /// Per-account expand state for the admin row (change-password +
    /// sign-out-everywhere). Keyed by account id.
    @State private var expanded: Set<String> = []
    @State private var newPasswordDraft: [String: String] = [:]
    @State private var rowError: [String: String] = [:]

    var body: some View {
        Section("Accounts") {
            Text("Users you've added here can sign into the phone web UI with their email and password — from any device, over the same Tailscale link. The shared QR token above keeps working alongside this.")
                .font(.caption).foregroundStyle(.secondary)

            if store.accounts.isEmpty {
                Text("No accounts yet — add one below to enable email + password sign-in.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.accounts) { account in
                    accountRow(account)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Add account").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Name (optional)", text: $newDisplayName)
            TextField("Email", text: $newEmail)
                .textContentType(.emailAddress)
                .disableAutocorrection(true)
            SecureField("Password (8+ characters)", text: $newPassword)
            if let error {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Create account") {
                    let nameInput = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let result = store.createAccount(
                        email: newEmail,
                        password: newPassword,
                        displayName: nameInput.isEmpty ? nil : nameInput)
                    if result == nil {
                        error = "Couldn't create account. Check the email isn't already in use, that it looks like an email, and that the password is at least 8 characters."
                    } else {
                        error = nil
                        newEmail = ""
                        newPassword = ""
                        newDisplayName = ""
                    }
                }
                .disabled(newEmail.isEmpty || newPassword.count < 8)
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ account: WebAccount) -> some View {
        let isExpanded = expanded.contains(account.id)
        let sessionCount = store.sessionCount(forAccountID: account.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.displayName).font(.callout)
                    Text(account.email).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(sessionCount == 1 ? "1 device" : "\(sessionCount) devices")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    if isExpanded { expanded.remove(account.id) }
                    else { expanded.insert(account.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Hide admin options" : "Change password or sign out devices")
                Button(role: .destructive) {
                    store.deleteAccount(id: account.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this account and sign out every device using it")
            }

            if isExpanded {
                Divider().padding(.vertical, 2)
                let sessions = store.sessions(forAccountID: account.id)
                if !sessions.isEmpty {
                    Text("Signed-in devices")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(sessions) { session in
                        deviceRow(session)
                    }
                    Divider().padding(.vertical, 2)
                }
                let draft = Binding<String>(
                    get: { newPasswordDraft[account.id] ?? "" },
                    set: { newPasswordDraft[account.id] = $0 })
                SecureField("New password (8+ characters)", text: draft)
                if let err = rowError[account.id] {
                    Text(err).font(.caption2).foregroundStyle(.orange)
                }
                HStack {
                    Button("Change password") {
                        let pw = newPasswordDraft[account.id] ?? ""
                        if store.updatePassword(id: account.id, newPassword: pw) {
                            newPasswordDraft[account.id] = ""
                            rowError[account.id] = nil
                        } else {
                            rowError[account.id] = "Password must be at least 8 characters."
                        }
                    }
                    .disabled((newPasswordDraft[account.id]?.count ?? 0) < 8)
                    Spacer()
                    Button("Sign out all devices") {
                        store.revokeAllSessions(forAccountID: account.id)
                    }
                    .disabled(sessionCount == 0)
                    .help("Revoke every active session for this account. They'll need to sign in again.")
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func deviceRow(_ session: WebSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone").foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.deviceLabel?.isEmpty == false ? session.deviceLabel! : "Unnamed device")
                    .font(.caption)
                Text("Last used \(session.lastUsedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sign out") {
                store.revokeSession(id: session.id)
            }
            .buttonStyle(.borderless).font(.caption)
            .help("Revoke just this device's session — others stay signed in.")
        }
        .padding(.vertical, 1)
    }
}

/// Settings card for 2-way Tailscale sync. Lists each configured peer, the
/// last sync timestamp + any error, a manual "Sync now" button, and a form
/// to add a new peer.
///
/// Lives next to the Phone access card because they both stand on the same
/// Tailscale plumbing — the QR token grants per-user UI access, this grants
/// per-peer file sync.
@available(macOS 14.0, *)
struct TailscaleSyncSection: View {
    @ObservedObject private var peerStore = SyncPeerStore.shared
    @ObservedObject private var engine = SyncEngine.shared

    @State private var newLabel = ""
    @State private var newBaseURL = ""
    @State private var newSecret = ""
    @State private var revealSecrets: Set<String> = []

    var body: some View {
        Section("2-way Tailscale sync") {
            Text("Configure another Mac running MeetingScribe as a peer. The engine pulls files newer than the last sync, then pushes any local changes since the last push. Last-write-wins per file by modification time — same model as `docs/CROSS_DEVICE_SYNC_MASTER_PLAN.md`. Both Macs need the same shared secret in their peer entry; copy it from the side that generated it.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Sync automatically", isOn: $engine.autoSyncEnabled)
                .help("Run every configured peer on a timer in the background.")
            if engine.autoSyncEnabled {
                HStack {
                    Text("Every")
                    Picker("", selection: $engine.autoSyncInterval) {
                        Text("1 minute").tag(TimeInterval(60))
                        Text("5 minutes").tag(TimeInterval(300))
                        Text("15 minutes").tag(TimeInterval(900))
                        Text("1 hour").tag(TimeInterval(3600))
                        Text("6 hours").tag(TimeInterval(21_600))
                    }
                    .labelsHidden().fixedSize()
                    Spacer()
                }
            }

            if peerStore.peers.isEmpty {
                Text("No peers yet — add one below to start syncing.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(peerStore.peers) { peer in
                    peerRow(peer)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Add peer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Label (e.g. \"Work MacBook\")", text: $newLabel)
            TextField("Base URL (http://100.x.y.z:8765)", text: $newBaseURL)
                .disableAutocorrection(true)
            HStack {
                TextField("Shared secret", text: $newSecret)
                    .disableAutocorrection(true)
                Button("Generate") { newSecret = SyncPeer.newSecret() }
                    .help("Generate a new random secret — copy it onto the other Mac's peer entry.")
            }
            Text("Both Macs must use the same shared secret. Generate once, paste on both ends. It's the only credential needed for sync — separate from any user-account passwords above.")
                .font(.caption2).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Add peer") {
                    let secret = newSecret.isEmpty ? SyncPeer.newSecret() : newSecret
                    if peerStore.addPeer(label: newLabel, baseURL: newBaseURL,
                                          sharedSecret: secret) != nil {
                        newLabel = ""
                        newBaseURL = ""
                        newSecret = ""
                    }
                }
                .disabled(newLabel.isEmpty || newBaseURL.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func peerRow(_ peer: SyncPeer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(peer.label).font(.callout)
                    Text(peer.baseURL).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if engine.runningPeerIDs.contains(peer.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Sync now") {
                        Task { await engine.syncNow(peerID: peer.id) }
                    }
                }
                Button(role: .destructive) {
                    peerStore.deletePeer(id: peer.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            statusLine(peer)

            HStack(spacing: 8) {
                Button(revealSecrets.contains(peer.id) ? "Hide secret" : "Show secret") {
                    if revealSecrets.contains(peer.id) {
                        revealSecrets.remove(peer.id)
                    } else {
                        revealSecrets.insert(peer.id)
                    }
                }
                .buttonStyle(.borderless).font(.caption)
                if revealSecrets.contains(peer.id) {
                    Text(peer.sharedSecret)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Copy secret") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(peer.sharedSecret, forType: .string)
                }
                .buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusLine(_ peer: SyncPeer) -> some View {
        if let err = peer.lastError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.orange).lineLimit(2)
        } else if let when = peer.lastSyncAt {
            Text("Synced \(when.formatted(.relative(presentation: .named)))")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("Never synced.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
