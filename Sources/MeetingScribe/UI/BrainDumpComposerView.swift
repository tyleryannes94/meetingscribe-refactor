import SwiftUI
import AppKit
import Combine

/// Composer column of the Brain Dump page.
///
///   - Autosaving multi-line `TextEditor` (350 ms debounce → `store.updateBody`).
///   - URL detection on paste / on enter: pasted URLs are detected by
///     `NSDataDetector(.link)`, removed from the buffer, and attached as URL
///     sources that the `URLFetcher` resolves in the background.
///   - Toolbar with the primary actions: Plan, Search, Attach URL, Pull
///     Linear, Pull Slack (stub).
@available(macOS 14.0, *)
struct BrainDumpComposerView: View {
    @EnvironmentObject var store: BrainDumpStore
    @EnvironmentObject var actionItems: ActionItemStore
    @EnvironmentObject var router: WorkspaceRouter

    let session: BrainDumpSession
    @ObservedObject var planRunner: BrainDumpPlanRunner
    /// Current Tasks page context (e.g. "Project: Analytics") forwarded to the
    /// planner so proposals reflect what the user is looking at.
    var pageContext: String? = nil

    @State private var bufferText: String = ""
    @State private var bufferTitle: String = ""
    @State private var debouncer = PassthroughSubject<String, Never>()
    @State private var titleDebouncer = PassthroughSubject<String, Never>()
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showSourcesSheet = false

    var body: some View {
        VStack(spacing: 0) {
            titleField
            Divider().overlay(NDS.divider)
            editor
            Divider().overlay(NDS.divider)
            toolbar
        }
        .background(NDS.bg)
        .onAppear { hydrateBuffers() }
        .onChange(of: session.id) { _ in hydrateBuffers() }
        .sheet(isPresented: $showSourcesSheet) {
            BrainDumpSourcesSheet(session: session,
                                  onAttachURL: attachURL,
                                  onSearch: runWebSearch,
                                  onPullLinear: pullLinearBrief)
        }
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Session title (optional)", text: $bufferTitle)
            .textFieldStyle(.plain)
            .scaledFont(18, weight: .bold)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .onChange(of: bufferTitle) { titleDebouncer.send($0) }
    }

    // MARK: - Editor

    /// The SAME rich markdown editor used by Meeting Notes, Tasks, Projects, and
    /// Initiatives (`RichMarkdownEditor`) — one component across the app: live
    /// markdown styling, a "/" block menu, and a formatting toolbar. Autosave and
    /// URL auto-attach behavior are unchanged (they hang off `bufferText`).
    private var editor: some View {
        RichMarkdownEditor(
            text: $bufferText,
            placeholder: "Dump everything on your mind — thoughts, links, follow-ups, the messy week. Paste a URL and the planner reads it. Type / for headings, lists, and to-dos.",
            enableSlashMenu: true,
            enableMentions: false
        )
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onChange(of: bufferText) { newValue in
            debouncer.send(newValue)
            detectURLs(in: newValue)
        }
        // Dictation into the brain dump always pastes the polished transcript —
        // it's piped straight to the local planner.
        .dictationPrefersPolished(id: "brainDump.composer", focused: true)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        let canPlan = !planRunner.isRunning && !bufferText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: 8) {
            Button {
                planRunner.run(
                    sessionID: session.id,
                    store: store,
                    actionItems: actionItems,
                    contexts: actionItems.contexts,
                    pageContext: pageContext
                )
            } label: {
                Label(planRunner.isRunning ? "Planning…" : "Plan with AI",
                      systemImage: planRunner.isRunning ? "hourglass" : "wand.and.stars")
            }
            .buttonStyle(MSPrimaryButtonStyle())
            .disabled(!canPlan)
            .help("Run the local planner — it'll fetch any URLs you added, propose tasks, and suggest focus blocks.")

            Spacer()

            // Sources are no longer a whole column — one button opens a modal to
            // add (URL / web search / Linear) and review attached sources.
            Button { showSourcesSheet = true } label: {
                Label(session.sources.isEmpty ? "Sources"
                                              : "Sources (\(session.sources.count))",
                      systemImage: "paperclip")
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .help("Attach URLs, web searches, or a Linear brief — and review what's attached.")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(NDS.fieldBg.opacity(0.4))
    }

    // MARK: - Lifecycle

    private func hydrateBuffers() {
        bufferText = session.body
        bufferTitle = session.title ?? ""
        cancellables.removeAll()
        debouncer
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { newValue in
                store.updateBody(session.id, newValue)
            }
            .store(in: &cancellables)
        titleDebouncer
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { newValue in
                store.setTitle(session.id, newValue)
            }
            .store(in: &cancellables)
    }

    // MARK: - URL detection

    /// Run NSDataDetector over the buffer; if it finds new URLs we haven't yet
    /// attached as sources, attach them and strip them from the buffer.
    private func detectURLs(in text: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return }

        var newURLs: [(Range<String.Index>, URL)] = []
        let existingURLs: Set<URL> = Set(session.sources.compactMap {
            if case let .url(s) = $0 { return s.url } else { return nil }
        })

        for match in matches {
            guard let url = match.url, url.scheme?.lowercased() == "https",
                  let swiftRange = Range(match.range, in: text) else { continue }
            if existingURLs.contains(url) { continue }
            newURLs.append((swiftRange, url))
        }

        guard !newURLs.isEmpty else { return }

        // Walk the matches back-to-front so we can remove without invalidating
        // earlier indices.
        var mutableText = text
        for (range, _) in newURLs.reversed() {
            mutableText.removeSubrange(range)
        }
        let trimmedText = mutableText
            .components(separatedBy: .newlines)
            .map { line in line.trimmingCharacters(in: CharacterSet(charactersIn: " \t,;")) }
            .joined(separator: "\n")
        bufferText = trimmedText

        for (_, url) in newURLs {
            attachURL(url)
        }
    }

    private func attachURL(_ url: URL) {
        Task { @MainActor in
            // Insert a loading placeholder; the URLFetcher result replaces it.
            let placeholder = URLSource(url: url, title: url.host ?? url.absoluteString)
            store.attachSource(session.id, .url(placeholder))

            do {
                let page = try await URLFetcher.fetch(url)
                let article = ReadabilityExtractor.extract(html: page.html, baseURL: page.finalURL)
                var resolved = placeholder
                resolved.url = page.finalURL
                resolved.title = article.title.isEmpty ? (page.finalURL.host ?? url.absoluteString) : article.title
                resolved.extractedMarkdown = article.markdown
                resolved.isLoading = false
                store.attachSource(session.id, .url(resolved))
            } catch {
                var failed = placeholder
                failed.isLoading = false
                failed.error = error.localizedDescription
                store.attachSource(session.id, .url(failed))
            }
        }
    }

    // MARK: - Web search

    private func runWebSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let provider = WebSearchService.current() else { return }

        Task { @MainActor in
            do {
                let results = try await provider.search(trimmed, limit: 5)
                let source = SearchSource(query: trimmed, provider: provider.name, results: results)
                store.attachSource(session.id, .search(source))
            } catch {
                // Surface the failure as a placeholder source so the user
                // sees why nothing came back.
                let empty = SearchSource(query: trimmed, provider: provider.name,
                                         results: [], summary: "Search failed: \(error.localizedDescription)")
                store.attachSource(session.id, .search(empty))
            }
        }
    }

    // MARK: - Linear brief

    private func pullLinearBrief() {
        guard let key = AppSettings.shared.linearAPIKey, !key.isEmpty else { return }
        Task { @MainActor in
            do {
                let issues = try await LinearBriefService.fetchMyAssignedIssuesToday(apiKey: key)
                let brief = LinearBriefSource(issues: issues)
                store.attachSource(session.id, .linearBrief(brief))
            } catch {
                let empty = LinearBriefSource(issues: [])
                store.attachSource(session.id, .linearBrief(empty))
            }
        }
    }
}

// MARK: - Sources sheet

/// Everything about a session's sources in one modal (replaces the old middle
/// "Sources" column): add via URL / web search / Linear, and review + remove
/// what's attached. Opened from the composer's "Sources (N)" button.
@available(macOS 14.0, *)
struct BrainDumpSourcesSheet: View {
    let session: BrainDumpSession
    let onAttachURL: (URL) -> Void
    let onSearch: (String) -> Void
    let onPullLinear: () -> Void

    @EnvironmentObject var store: BrainDumpStore
    @Environment(\.dismiss) private var dismiss
    @State private var showURL = false
    @State private var showSearch = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sources").scaledFont(18, weight: .bold)
                    Text("Pages, searches, and briefs the planner reads alongside your notes.")
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(MSSecondaryButtonStyle())
            }
            .padding(16)
            Divider().overlay(NDS.divider)

            HStack(spacing: 8) {
                Button { showURL = true } label: {
                    Label("Attach URL", systemImage: "link.badge.plus")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                Button { showSearch = true } label: {
                    Label("Search the web", systemImage: "magnifyingglass.circle")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                .disabled(!AppSettings.shared.allowBrainDumpWebAccess)
                Button { onPullLinear() } label: {
                    Label("Pull Linear", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                .disabled(AppSettings.shared.linearAPIKey?.isEmpty ?? true)
                Button {
                    store.attachSource(session.id, .slackBrief(SlackBriefStub()))
                } label: {
                    Label("Slack (soon)", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                .disabled(true)
                .help("Slack daily brief — coming soon")
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(NDS.divider)

            BrainDumpSourcePanel(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 620, height: 640)
        .background(NDS.bg)
        .sheet(isPresented: $showURL) {
            BrainDumpAttachURLSheet { url in showURL = false; onAttachURL(url) }
        }
        .sheet(isPresented: $showSearch) {
            BrainDumpSearchSheet { query in showSearch = false; onSearch(query) }
        }
    }
}

// MARK: - Search sheet

@available(macOS 14.0, *)
struct BrainDumpSearchSheet: View {
    let onSubmit: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search the web").scaledFont(16, weight: .bold)
            Text("The planner will attach the top results as a source.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary)
            TextField("e.g. \"GPT-5 release roadmap\"", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSubmit(query) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Search") { onSubmit(query) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - Attach URL sheet

@available(macOS 14.0, *)
struct BrainDumpAttachURLSheet: View {
    let onSubmit: (URL) -> Void
    @State private var raw = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Attach a URL").scaledFont(16, weight: .bold)
            Text("MeetingScribe will fetch the page and fold its main content into the planner's context.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://…", text: $raw)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            if let error {
                Text(error).font(NDS.tiny).foregroundStyle(NDS.selectColor("red"))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Attach") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(raw.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func commit() {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            error = "Needs to be an https URL."
            return
        }
        onSubmit(url)
    }
}
