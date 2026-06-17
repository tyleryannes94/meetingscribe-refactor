import SwiftUI
import AppKit

/// One place to set up, edit, and test every connector the app uses, with a
/// short explanation of what each unlocks — and an assistant on the right that
/// works across your connected workspace.
@available(macOS 14.0, *)
struct IntegrationsView: View {
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var calendar: CalendarService
    @ObservedObject private var drive = GoogleDriveService.shared
    @ObservedObject private var gmail = GmailContactsService.shared
    @StateObject private var mcp = MCPInstaller()
    @StateObject private var peopleImport = PeopleImportController()

    // Drafts
    @State private var linearKey = AppSettings.shared.linearAPIKey ?? ""
    @State private var notionKey = AppSettings.shared.notionAPIKey ?? ""
    @State private var notionDB = AppSettings.shared.notionActionItemsDatabaseID ?? ""
    @State private var googleID = AppSettings.shared.googleClientID ?? ""
    @State private var googleSecret = AppSettings.shared.googleClientSecret ?? ""
    @State private var googleFolder = AppSettings.shared.googleDriveFolderName

    // Test results
    @State private var linearStatus: String?
    @State private var notionStatus: String?
    @State private var ollamaStatus: String?
    @State private var calendarStatus: String?
    @State private var mcpStatus: String?
    @State private var testing: Set<String> = []

    var body: some View {
        list
            .background(NDS.bg)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    Text("🧩").scaledFont(26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Integrations").font(NDS.title)
                        Text("Connect your tools. Everything runs locally or against each service's free API.")
                            .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    }
                    Spacer()
                }
                linearCard
                notionCard
                googleCard
                peopleConnectorsCard
                iMessageCard
                ollamaCard
                calendarCard
                mcpCard
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Cards

    private var linearCard: some View {
        IntegrationCard(
            icon: "l.square.fill", tint: NDS.selectColor("purple"), title: "Linear",
            explanation: "Pull your Linear projects and issues into Tasks. Link a project to keep its issues in sync — assignees, priorities, and status carry over.",
            connected: !(AppSettings.shared.linearAPIKey ?? "").isEmpty,
            status: linearStatus, testing: testing.contains("linear")
        ) {
            SecureField("Personal API key (lin_api_…)", text: $linearKey).textFieldStyle(.roundedBorder)
            Text("Linear → Settings → Security & access → Personal API keys. Read access is enough.")
                .font(.caption2).foregroundStyle(.tertiary)
            HStack {
                Button("Save") { AppSettings.shared.linearAPIKey = trimmedOrNil(linearKey) }
                Button("Test connection") { Task { await testLinear() } }
                    .disabled(trimmedOrNil(linearKey) == nil)
                Spacer()
            }
        }
    }

    private var notionCard: some View {
        IntegrationCard(
            icon: "n.square.fill", tint: NDS.textPrimary, title: "Notion",
            explanation: "Push action items into a Notion database, and pull database items back into Tasks. Create an internal integration and share the database with it.",
            connected: !(AppSettings.shared.notionAPIKey ?? "").isEmpty && !(AppSettings.shared.notionActionItemsDatabaseID ?? "").isEmpty,
            status: notionStatus, testing: testing.contains("notion")
        ) {
            SecureField("Internal integration secret", text: $notionKey).textFieldStyle(.roundedBorder)
            TextField("Action-items database ID", text: $notionDB).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") {
                    AppSettings.shared.notionAPIKey = trimmedOrNil(notionKey)
                    AppSettings.shared.notionActionItemsDatabaseID = trimmedOrNil(notionDB)
                }
                Button("Test connection") { Task { await testNotion() } }
                    .disabled(trimmedOrNil(notionKey) == nil || trimmedOrNil(notionDB) == nil)
                Spacer()
            }
        }
    }

    private var googleCard: some View {
        IntegrationCard(
            icon: "externaldrive.fill.badge.icloud", tint: NDS.selectColor("blue"), title: "Google Drive",
            explanation: "Export voice notes and meeting notes to a folder in your Drive. One-time OAuth setup with a Desktop-app client; then exports are one click.",
            connected: drive.isConnected, status: drive.lastStatus, testing: drive.isWorking
        ) {
            SecureField("OAuth Client ID", text: $googleID).textFieldStyle(.roundedBorder)
            SecureField("OAuth Client secret", text: $googleSecret).textFieldStyle(.roundedBorder)
            TextField("Drive folder name", text: $googleFolder).textFieldStyle(.roundedBorder)
            HStack {
                if drive.isConnected {
                    Button("Disconnect", role: .destructive) { drive.disconnect() }
                } else {
                    Button("Connect") {
                        AppSettings.shared.googleClientID = trimmedOrNil(googleID)
                        AppSettings.shared.googleClientSecret = trimmedOrNil(googleSecret)
                        AppSettings.shared.googleDriveFolderName = googleFolder.trimmingCharacters(in: .whitespaces)
                        Task { await drive.connect() }
                    }
                    .disabled(trimmedOrNil(googleID) == nil || trimmedOrNil(googleSecret) == nil)
                }
                Spacer()
            }
        }
    }

    private var peopleConnectorsCard: some View {
        IntegrationCard(
            icon: "person.crop.circle.badge.plus", tint: NDS.selectColor("orange"),
            title: "People — Google Contacts",
            explanation: "Import names + emails from one or more Google accounts (personal + work) into your People graph. Reuses the Drive OAuth client — enable the People API in your Google Cloud project and add the contacts read-only scopes to the consent screen.",
            connected: !gmail.accounts.isEmpty, status: gmail.lastStatus ?? peopleImport.status,
            testing: gmail.isWorking || peopleImport.isWorking
        ) {
            ForEach(gmail.accounts) { acct in
                HStack {
                    Image(systemName: "envelope").foregroundStyle(NDS.textTertiary)
                    Text(acct.email).font(NDS.small)
                    Spacer()
                    Button("Remove", role: .destructive) { gmail.removeAccount(acct.email) }
                        .buttonStyle(.borderless).font(NDS.tiny)
                }
            }
            HStack {
                Button("Connect account…") { Task { await gmail.connectAccount() } }
                    .disabled(!gmail.hasCredentials || gmail.isWorking)
                Button("Import now") { Task { await peopleImport.importGmail() } }
                    .disabled(gmail.accounts.isEmpty || peopleImport.isWorking)
                Spacer()
            }
            Text("Also available from the People tab → Import: Apple/iCloud Contacts, calendar attendees, and vCard/CSV files.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var iMessageCard: some View {
        IntegrationCard(
            icon: "message.fill", tint: NDS.selectColor("green"), title: "iMessage analysis",
            explanation: "Per-person message stats (counts, recency, conversation summary) computed locally from your Messages history. Requires Full Disk Access so the app can read chat.db — nothing is uploaded. Run analysis from a person's detail view.",
            connected: MessagesAnalyzer.hasAccess(), status: nil, testing: false
        ) {
            if MessagesAnalyzer.hasAccess() {
                Text("Full Disk Access granted — open any person and tap “Analyze” under Messages.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("Grant Full Disk Access, then relaunch MeetingScribe.")
                    .font(.caption2).foregroundStyle(.tertiary)
                Button("Open Full Disk Access settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private var ollamaCard: some View {
        IntegrationCard(
            icon: "cpu.fill", tint: NDS.selectColor("green"), title: "Ollama (local AI)",
            explanation: "Local AI that writes meeting summaries, polishes voice notes, extracts action items, and powers the assistant — runs on your machine, nothing leaves it.",
            connected: manager.ollamaReachable, status: ollamaStatus, testing: testing.contains("ollama")
        ) {
            Text("Model: \(AppSettings.shared.ollamaModel) · \(AppSettings.shared.ollamaURL.absoluteString)")
                .font(.caption2).foregroundStyle(.tertiary)
            if AppSettings.shared.ollamaModel != AppSettings.recommendedOllamaModel {
                Text("Recommended: \(AppSettings.recommendedOllamaModel). Better tool-calling and fewer spurious refusals than llama3.1:8b. Install with `ollama pull \(AppSettings.recommendedOllamaModel)`, then set it in Settings → Ollama.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            HStack {
                Button("Test / start Ollama") { Task { await testOllama() } }
                Button("Pull \(AppSettings.recommendedOllamaModel)") {
                    Task { await pullRecommendedModel() }
                }
                .help("Runs `ollama pull \(AppSettings.recommendedOllamaModel)` in the background — ~5 GB download.")
                Spacer()
            }
        }
    }

    private var calendarCard: some View {
        IntegrationCard(
            icon: "calendar", tint: NDS.selectColor("orange"), title: "Calendar",
            explanation: "Reads your calendar so meetings show up with titles, attendees, and join links — and so recordings get labeled automatically.",
            connected: calendar.authorized, status: calendarStatus, testing: false
        ) {
            HStack {
                Button(calendar.authorized ? "Refresh" : "Grant access") {
                    Task {
                        if !calendar.authorized { await calendar.requestAccess() }
                        calendar.refreshUpcoming(force: true)
                        calendarStatus = calendar.authorized ? "✓ Access granted — \(calendar.upcoming.count) upcoming." : "✗ Access denied. Enable in System Settings → Privacy → Calendars."
                    }
                }
                Spacer()
            }
        }
    }

    private var mcpCard: some View {
        IntegrationCard(
            icon: "terminal.fill", tint: NDS.textSecondary, title: "Claude Desktop (MCP)",
            explanation: "Exposes your meetings, notes, and action items to Claude Desktop / Claude Code as an MCP server, so you can ask about them there too.",
            connected: mcp.installedInClaudeDesktop, status: mcpStatus, testing: testing.contains("mcp")
        ) {
            HStack {
                Button(mcp.installedInClaudeDesktop ? "Reinstall in Claude Desktop" : "Install in Claude Desktop") {
                    do { _ = try mcp.installInClaudeDesktop(); mcpStatus = "✓ Registered — restart Claude Desktop." }
                    catch { mcpStatus = "✗ " + error.localizedDescription }
                }
                .disabled(!mcp.binaryExists)
                Button("Self-test") {
                    testing.insert("mcp")
                    Task {
                        switch await mcp.selfTest() {
                        case .ok(let s): mcpStatus = "✓ " + s
                        case .failure(let e): mcpStatus = "✗ " + e
                        }
                        testing.remove("mcp")
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Tests

    private func testLinear() async {
        testing.insert("linear"); defer { testing.remove("linear") }
        AppSettings.shared.linearAPIKey = trimmedOrNil(linearKey)
        let projects = await manager.fetchLinearProjectList()
        if let err = manager.lastTaskSyncError { linearStatus = "✗ " + err }
        else { linearStatus = "✓ Connected — \(projects.count) project\(projects.count == 1 ? "" : "s") visible." }
    }

    private func testNotion() async {
        testing.insert("notion"); defer { testing.remove("notion") }
        AppSettings.shared.notionAPIKey = trimmedOrNil(notionKey)
        AppSettings.shared.notionActionItemsDatabaseID = trimmedOrNil(notionDB)
        guard let key = AppSettings.shared.notionAPIKey, let db = AppSettings.shared.notionActionItemsDatabaseID else { return }
        do {
            let items = try await TaskSyncService.fetchNotion(apiKey: key, databaseID: db)
            notionStatus = "✓ Connected — \(items.count) item\(items.count == 1 ? "" : "s") in database."
        } catch {
            notionStatus = "✗ " + ((error as? TaskSyncService.SyncError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func testOllama() async {
        testing.insert("ollama"); defer { testing.remove("ollama") }
        let ok = await manager.ensureOllamaRunning()
        ollamaStatus = ok ? "✓ Reachable (\(AppSettings.shared.ollamaModel))."
                          : "✗ Not reachable. Install ollama and run `ollama serve`, then pull the model."
    }

    /// Run `ollama pull <recommended model>` as a background process so the
    /// user gets one-click upgrade from the bad-default 8B model. Streams
    /// status into `ollamaStatus` so the card shows live progress instead
    /// of looking frozen during the ~5 GB download.
    private func pullRecommendedModel() async {
        testing.insert("ollama"); defer { testing.remove("ollama") }
        guard let binary = OllamaService.binaryPath else {
            ollamaStatus = "✗ Ollama not installed. `brew install ollama` first."
            return
        }
        let model = AppSettings.recommendedOllamaModel
        ollamaStatus = "Pulling \(model)… this can take a few minutes."
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["pull", model]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            ollamaStatus = "✗ Failed to launch ollama pull: \(error.localizedDescription)"
            return
        }
        // Don't block the UI thread — wait on a background task.
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                proc.waitUntilExit()
                cont.resume()
            }
        }
        if proc.terminationStatus == 0 {
            AppSettings.shared.ollamaModel = model
            ollamaStatus = "✓ Pulled \(model) and set as active model."
            NotificationCenter.default.post(name: .meetingScribeSettingsChanged, object: nil)
        } else {
            ollamaStatus = "✗ `ollama pull \(model)` exited \(proc.terminationStatus). Try running it in Terminal."
        }
    }

    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Reusable integration card

@available(macOS 14.0, *)
private struct IntegrationCard<Content: View>: View {
    let icon: String
    var tint: Color = NDS.brand
    let title: String
    let explanation: String
    let connected: Bool
    var status: String? = nil
    var testing: Bool = false
    @ViewBuilder var content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon).scaledFont(15)
                        .foregroundStyle(tint).frame(width: 30, height: 30)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title).scaledFont(13.5, weight: .semibold).foregroundStyle(NDS.textPrimary)
                            statusPill
                            if testing { ProgressView().controlSize(.small) }
                        }
                        Text(explanation).font(NDS.small).foregroundStyle(NDS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .scaledFont(11).foregroundStyle(NDS.textTertiary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(NDS.divider)
                    content()
                    if let status {
                        Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .padding(.top, 2)
                    }
                }
                .padding(12)
            } else if let status {
                Text(status).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NDS.hairline, lineWidth: 0.5))
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle().fill(connected ? NDS.selectColor("green") : NDS.textTertiary).frame(width: 6, height: 6)
            Text(connected ? "Connected" : "Not connected")
                .scaledFont(10, weight: .medium)
                .foregroundStyle(connected ? NDS.selectColor("green") : NDS.textTertiary)
        }
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background((connected ? NDS.selectColor("green") : NDS.textTertiary).opacity(0.12), in: Capsule())
    }
}
