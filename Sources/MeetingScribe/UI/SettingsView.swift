import SwiftUI
import Carbon.HIToolbox

@available(macOS 14.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var storageDir: String = AppSettings.shared.storageDir.path
    @State private var whisperBinary: String = AppSettings.shared.whisperBinary
    @State private var whisperModel: String = AppSettings.shared.whisperModel
    @State private var ollamaURL: String = AppSettings.shared.ollamaURL.absoluteString
    @State private var ollamaModel: String = AppSettings.shared.ollamaModel
    @State private var autoRecord: Bool = AppSettings.shared.autoRecord
    @State private var captureMic: Bool = AppSettings.shared.captureMic
    @State private var captureSystem: Bool = AppSettings.shared.captureSystem
    @State private var filterToConference: Bool = AppSettings.shared.filterToConferenceLinks
    @State private var notifyAtStart: Bool = AppSettings.shared.notifyAtMeetingStart
    @State private var detectZoom: Bool = AppSettings.shared.detectZoomImpromptu
    @State private var hotkeyKeyCode: UInt32 = AppSettings.shared.dictationHotkeyKeyCode
    @State private var hotkeyMods: UInt32 = AppSettings.shared.dictationHotkeyModifiers
    @State private var meetingRecKeyCode: UInt32 = AppSettings.shared.meetingRecordHotkeyKeyCode
    @State private var meetingRecMods: UInt32 = AppSettings.shared.meetingRecordHotkeyModifiers
    @State private var swapKeyCode: UInt32 = AppSettings.shared.dictationSwapHotkeyKeyCode
    @State private var swapMods: UInt32 = AppSettings.shared.dictationSwapHotkeyModifiers
    @State private var dictationAutoPaste: Bool = AppSettings.shared.dictationAutoPaste
    @State private var dictationUsePolished: Bool = AppSettings.shared.dictationUsePolished
    @State private var whisperUseGPU: Bool = AppSettings.shared.whisperUseGPU
    @State private var whisperFlashAttn: Bool = AppSettings.shared.whisperFlashAttention
    @State private var whisperLanguage: String = AppSettings.shared.whisperLanguage
    @State private var autoExtractPeople: Bool = AppSettings.shared.autoExtractPeople
    @State private var userName: String = AppSettings.shared.userName
    @State private var userNameAliases: String = AppSettings.shared.userNameAliases.joined(separator: ", ")
    @State private var allowRemoteOllama: Bool = AppSettings.shared.allowRemoteOllamaEndpoint
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

    var body: some View {
        VStack(alignment: .leading) {
            Text("Settings").font(.title2).bold()

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
                Section("Storage") {
                    HStack {
                        TextField("Storage folder", text: $storageDir)
                        Button("Choose…") { pickFolder() }
                    }
                }
                Section("Capture") {
                    Toggle("Record microphone", isOn: $captureMic)
                    Toggle("Record system audio", isOn: $captureSystem)
                    Toggle("Auto-start when a calendar meeting begins", isOn: $autoRecord)
                    Text("Auto-start ONLY fires if MeetingScribe detects you've actually joined the call (Zoom app open with a meeting window, or a browser tab on meet.google.com). Time blocks and meetings you skip won't trigger a surprise recording.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Live transcript runs every 5 minutes during a recording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Calendar") {
                    Toggle("Only show meetings with a conference link", isOn: $filterToConference)
                    Toggle("Notify me at meeting start time", isOn: $notifyAtStart)
                    Text("MeetingScribe reads all calendars connected to macOS Calendar.app. To add Google work + personal calendars: System Settings → Internet Accounts → Google → sign in. Below, choose which of those calendars MeetingScribe should pull events from.")
                        .font(.caption).foregroundStyle(.secondary)
                    CalendarPickerSection()
                }
                Section("Impromptu detection") {
                    Toggle("Prompt to record when a Zoom call / Meet tab is detected", isOn: $detectZoom)
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
                    Text("Click a shortcut box, then press ANY key combination to set it. After dictating, press the swap shortcut to replace the inserted text with the other version (raw ↔ polished) in place.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle("Paste transcription at cursor after dictation", isOn: $dictationAutoPaste)
                    Toggle("Use the polished (cleaned-up) version by default", isOn: $dictationUsePolished)
                    Text("Polished output runs the raw transcript through Ollama for grammar/filler cleanup (Whispr-Flow style). It adds a brief delay before pasting; the swap shortcut flips to the raw version instantly.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

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

                Section("Integrations — Task sync") {
                    Text("Pull issues/tasks into the Action Items tab. Both APIs are free — no usage charges, and nothing is sent to an AI. Notion uses the key set in Notion MCP above (plus its database ID).")
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
                        if drive.isWorking { ProgressView().controlSize(.small) }
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
                            .buttonStyle(.borderedProminent)
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
                Section("Ollama") {
                    TextField("Server URL", text: $ollamaURL)
                    TextField("Model", text: $ollamaModel)
                    Text("Recommended: \(AppSettings.recommendedOllamaModel) — strongest small open-weight model for tool calling. Install with `ollama pull \(AppSettings.recommendedOllamaModel)`. Avoid llama3.1:8b: it leaks tool-call JSON as plain text and over-fires safety refusals on benign prompts.")
                        .font(.caption2).foregroundStyle(.secondary)
                    OllamaStatusRow()
                    Toggle("Allow a non-local Ollama endpoint", isOn: $allowRemoteOllama)
                    Text("Off by default. MeetingScribe only sends transcripts to a local LLM (127.0.0.1). Turn this on only if you intentionally run Ollama on another machine — your meeting content will leave this device.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("People (second brain)") {
                    Toggle("Auto-extract people from meetings", isOn: $autoExtractPeople)
                    Text("After a meeting is summarized, a second on-device Ollama pass lists the people mentioned in the transcript. Strong matches link to existing people automatically; uncertain ones appear as suggestions on the Today tab. Nothing leaves your machine.")
                        .font(.caption).foregroundStyle(.secondary)
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

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear { mcp.refreshStatus() }
        .sheet(isPresented: $showHealthCheck) {
            HealthCheckSheet(isPresented: $showHealthCheck)
        }
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
        s.captureMic = captureMic
        s.captureSystem = captureSystem
        s.filterToConferenceLinks = filterToConference
        s.notifyAtMeetingStart = notifyAtStart
        s.detectZoomImpromptu = detectZoom
        s.dictationHotkeyKeyCode = hotkeyKeyCode
        s.dictationHotkeyModifiers = hotkeyMods
        s.meetingRecordHotkeyKeyCode = meetingRecKeyCode
        s.meetingRecordHotkeyModifiers = meetingRecMods
        s.dictationSwapHotkeyKeyCode = swapKeyCode
        s.dictationSwapHotkeyModifiers = swapMods
        s.dictationAutoPaste = dictationAutoPaste
        s.dictationUsePolished = dictationUsePolished
        s.whisperUseGPU = whisperUseGPU
        s.whisperFlashAttention = whisperFlashAttn
        s.whisperLanguage = whisperLanguage
        s.autoExtractPeople = autoExtractPeople
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
                if !allCalendars.isEmpty {
                    Button(enabled.isEmpty || enabled.count == allCalendars.count
                           ? "Select specific…" : "Include all") {
                        if enabled.isEmpty || enabled.count == allCalendars.count {
                            enabled = Set(allCalendars.prefix(1).map { $0.id })
                        } else {
                            enabled.removeAll()
                        }
                        AppSettings.shared.enabledCalendarIDs = enabled
                    }
                    .controlSize(.small)
                }
            }
            if !calendar.authorized {
                Text("Grant Calendar access first.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if allCalendars.isEmpty {
                Text("No calendars yet. Add accounts via System Settings → Internet Accounts.")
                    .font(.caption).foregroundStyle(.secondary)
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
                .controlSize(.small)
                .disabled(starting)

                if !reachable {
                    Button {
                        Task { await start() }
                    } label: {
                        if starting {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("Starting…")
                            }
                        } else {
                            Label(binaryPath == nil ? "Install with brew" : "Start Ollama",
                                  systemImage: binaryPath == nil ? "arrow.down.app" : "play.fill")
                        }
                    }
                    .controlSize(.small)
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
