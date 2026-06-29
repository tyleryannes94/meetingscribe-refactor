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

    @State private var bufferText: String = ""
    @State private var bufferTitle: String = ""
    @State private var debouncer = PassthroughSubject<String, Never>()
    @State private var titleDebouncer = PassthroughSubject<String, Never>()
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showSearchSheet = false
    @State private var showURLSheet = false
    @FocusState private var bodyFocused: Bool

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
        .sheet(isPresented: $showSearchSheet) {
            BrainDumpSearchSheet { query in
                showSearchSheet = false
                runWebSearch(query)
            }
        }
        .sheet(isPresented: $showURLSheet) {
            BrainDumpAttachURLSheet { url in
                showURLSheet = false
                attachURL(url)
            }
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

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $bufferText)
                .font(NDS.body)
                .focused($bodyFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .onChange(of: bufferText) { newValue in
                    debouncer.send(newValue)
                    detectURLs(in: newValue)
                }

            if bufferText.isEmpty {
                Text("Dump everything on your mind — thoughts, links, follow-ups, the messy week. Paste a URL and the planner will read it.\n\nThe planner turns this into tasks and 25-minute focus blocks you can accept.")
                    .font(NDS.body).foregroundStyle(NDS.textTertiary)
                    .padding(.horizontal, 22).padding(.vertical, 20)
                    .allowsHitTesting(false)
                    .frame(maxWidth: 540, alignment: .topLeading)
            }
        }
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
                    contexts: actionItems.contexts
                )
            } label: {
                Label(planRunner.isRunning ? "Planning…" : "Plan with AI",
                      systemImage: planRunner.isRunning ? "hourglass" : "wand.and.stars")
            }
            .buttonStyle(MSPrimaryButtonStyle())
            .disabled(!canPlan)
            .help("Run the local planner — it'll fetch any URLs you pasted, propose tasks, and suggest focus blocks.")

            Button { showURLSheet = true } label: {
                Label("Attach URL", systemImage: "link.badge.plus")
            }
            .buttonStyle(MSSecondaryButtonStyle())

            Button { showSearchSheet = true } label: {
                Label("Search the web", systemImage: "magnifyingglass.circle")
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .disabled(!AppSettings.shared.allowBrainDumpWebAccess)

            Spacer()

            Button { pullLinearBrief() } label: {
                Label("Pull Linear", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .disabled(AppSettings.shared.linearAPIKey?.isEmpty ?? true)

            Button {
                let stub = BrainDumpSource.slackBrief(SlackBriefStub())
                store.attachSource(session.id, stub)
            } label: {
                Label("Slack (soon)", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .disabled(true)
            .help("Slack daily brief — coming soon")
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
