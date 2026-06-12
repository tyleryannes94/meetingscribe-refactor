import SwiftUI
import AppKit

/// Phase 4 — ⌘K command palette. Searches meetings, voice notes, projects, and
/// action items in one place; selecting a result navigates to it. Empty query
/// shows recent meetings as quick-jump suggestions.
@available(macOS 14.0, *)
struct GlobalSearchView: View {
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var router: WorkspaceRouter
    @Binding var isPresented: Bool
    /// Called with the chosen entity. The host handles navigation.
    var onOpen: (WorkspaceEntity) -> Void

    @State private var query = ""
    @State private var results: [WorkspaceEntity] = []
    @State private var selection = 0
    @State private var filter: SearchFilter = .all
    @FocusState private var fieldFocused: Bool

    /// Tabs above the result list — scopes the search to one entity
    /// type. `.all` is the default and renders every kind. The People
    /// tab in particular sidesteps the WorkspaceIndex bug where the
    /// in-memory match was dropping certain contacts: when selected, it
    /// delegates straight to PeopleStore.filteredPeople which is the
    /// same path the People tab uses and is known to work.
    enum SearchFilter: String, CaseIterable, Identifiable {
        case all, people, meetings, tasks, notes, voiceNotes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:        return "All"
            case .people:     return "People"
            case .meetings:   return "Meetings"
            case .tasks:      return "Tasks"
            case .notes:      return "Notes"
            case .voiceNotes: return "Voice"
            }
        }
        var systemImage: String {
            switch self {
            case .all:        return "sparkle.magnifyingglass"
            case .people:     return "person.2"
            case .meetings:   return "calendar"
            case .tasks:      return "checklist"
            case .notes:      return "doc.text"
            case .voiceNotes: return "waveform"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            filterBar
            Divider().opacity(0.6)
            content
        }
        // Floating-palette sizing (C3-2): flexible width, capped height; the
        // host supplies the glass material + rounded corners, so no opaque bg here.
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: 520)
        .onAppear {
            recompute()
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: query) { _, _ in recompute() }
        .onChange(of: filter) { _, _ in recompute() }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SearchFilter.allCases) { f in
                    let active = filter == f
                    Button {
                        filter = f
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.systemImage).font(.caption)
                            Text(f.label).font(.callout)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(active ? NDS.brand.opacity(0.22) : Color.clear,
                                    in: Capsule())
                        .foregroundStyle(active ? NDS.brand : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show only \(f.label.lowercased())")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find anything that was said — people, conversations, tasks…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .onSubmit(openSelected)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Text("esc").font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        let commands = commandMatches
        return Group {
            if results.isEmpty && commands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: query.isEmpty ? "sparkle.magnifyingglass" : "questionmark.folder")
                        .scaledFont(30).foregroundStyle(.secondary)
                    Text(query.isEmpty ? "Type to search, or run a command (e.g. \"record\", \"new task\")"
                                       : "No matches for “\(query)”")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            if !commands.isEmpty {
                                sectionLabel("Commands")
                                ForEach(commands) { c in commandRow(c) }
                                if !results.isEmpty { sectionLabel("Results") }
                            }
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, e in
                                row(e, index: idx).id(idx)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selection) { _, new in
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .scaledFont(10, weight: .semibold).tracking(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
    }

    private func commandRow(_ c: PaletteCommand) -> some View {
        Button { runCommand(c) } label: {
            HStack(spacing: 10) {
                Image(systemName: c.icon).frame(width: 20).foregroundStyle(NDS.brand)
                Text(c.title).font(.body)
                Spacer()
                Text("Command").font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NDS.brand.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ e: WorkspaceEntity, index: Int) -> some View {
        Button {
            open(e)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: e.kind.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title).font(.body).lineLimit(1)
                    if let snip = e.snippet {
                        // U2-3: the matched sentence, query terms bolded — proof
                        // the result is relevant without opening it.
                        snippetText(snip).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(e.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Text(e.kind.label).font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(index == selection ? NDS.brand.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Render an FTS5 snippet, bolding the spans the matcher wrapped in the
    /// U+0001 / U+0002 sentinels (U2-3).
    private func snippetText(_ raw: String) -> Text {
        var result = Text("")
        var rest = Substring(raw)
        while let start = rest.firstIndex(of: "\u{1}") {
            result = result + Text(rest[..<start])
            let afterStart = rest.index(after: start)
            if let end = rest[afterStart...].firstIndex(of: "\u{2}") {
                result = result + Text(rest[afterStart..<end]).bold().foregroundColor(NDS.textPrimary)
                rest = rest[rest.index(after: end)...]
            } else {
                rest = rest[afterStart...]
            }
        }
        return result + Text(rest)
    }

    /// Parse `in:<kind>` qualifiers (U2-10): `in:meetings pricing` scopes the
    /// search and searches "pricing". Returns the cleaned query + an optional scope.
    private func parseQualifiers(_ raw: String) -> (query: String, scope: SearchFilter?) {
        var scope: SearchFilter?
        var words: [Substring] = []
        for word in raw.split(separator: " ") {
            if word.lowercased().hasPrefix("in:") {
                switch String(word.dropFirst(3)).lowercased() {
                case "meeting", "meetings":     scope = .meetings
                case "person", "people":        scope = .people
                case "task", "tasks":           scope = .tasks
                case "note", "notes":           scope = .notes
                case "voice", "voicenote", "voicenotes": scope = .voiceNotes
                default: words.append(word)
                }
            } else { words.append(word) }
        }
        return (words.joined(separator: " "), scope)
    }

    private func recompute() {
        let parsed = parseQualifiers(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if let scope = parsed.scope, filter != scope { filter = scope }   // re-fires recompute
        let q = parsed.query
        if q.isEmpty {
            // Empty-query suggestions, scoped to the current tab. For
            // .all and .meetings: recent meetings. For .people: recent
            // contacts. Others: nothing (typing required to scope).
            switch filter {
            case .all, .meetings:
                results = Array(manager.pastMeetings.prefix(8)).map {
                    WorkspaceEntity(kind: .meeting, rawID: $0.id, title: $0.displayTitle,
                                    subtitle: MeetingManager.entityDateString($0.startDate),
                                    date: $0.startDate)
                }
            case .people:
                results = recentPeopleSuggestions()
            default:
                results = []
            }
        } else if filter == .people {
            // Dedicated People path: routes directly through
            // PeopleStore.filteredPeople (same call the People tab uses)
            // so we get the proven-working ranking even when the
            // workspace-index in-memory match drops contacts.
            results = peopleSearch(query: q)
        } else {
            // FTS5-backed recall (BM25 + recency) for the indexed kinds —
            // meetings, voice notes, people — merged with the in-memory index
            // for the kinds FTS doesn't cover (tasks, projects, attached notes,
            // tags) plus the chatQuery "Ask Chat" passthrough. (C2-1: global
            // search used to fall back to an in-memory contains() scan.)
            let ftsKinds: Set<WorkspaceEntityKind> = [.meeting, .voiceNote, .person]
            let other = manager.search(q).filter { !ftsKinds.contains($0.kind) }
            // Instant lexical results first…
            results = filteredResults(PeopleStore.shared.searchVault(q).compactMap(ftsEntity) + other)
            // …then refine with hybrid semantic ranking once the query embedding
            // returns (no-op if the embedding model isn't available). Guarded
            // against a stale query so fast typing isn't clobbered. (C2-1b)
            Task { @MainActor in
                let hybrid = await PeopleStore.shared.searchVaultHybrid(q)
                guard q == parseQualifiers(query.trimmingCharacters(in: .whitespacesAndNewlines)).query else { return }
                results = filteredResults(hybrid.compactMap(ftsEntity) + other)
            }
        }
        selection = 0
    }

    /// Maps an FTS row to a workspace entity for display/opening. Returns nil
    /// for kinds we don't render directly here.
    private func ftsEntity(_ r: VaultSearchResult) -> WorkspaceEntity? {
        let kind: WorkspaceEntityKind
        switch r.entityKind {
        case "meeting":    kind = .meeting
        case "voice_note": kind = .voiceNote
        case "person":     kind = .person
        default:           return nil
        }
        let date = r.dateEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let subtitle = date.map { MeetingManager.entityDateString($0) } ?? ""
        // Only show a snippet when it actually contains a highlighted match
        // (U2-3) — otherwise FTS returns the document head, which is noise.
        let snip = (r.snippet?.contains("\u{1}") == true) ? r.snippet : nil
        return WorkspaceEntity(kind: kind, rawID: r.entityID,
                               title: r.title ?? "(untitled)",
                               subtitle: subtitle, date: date, snippet: snip)
    }

    /// Reduce the full result set to the kinds the active filter wants.
    /// `.all` lets everything through (with the chatQuery passthrough
    /// kept at the bottom). Other tabs strip out everything but their
    /// own kind PLUS the chatQuery row so the user can still Ask Chat.
    private func filteredResults(_ all: [WorkspaceEntity]) -> [WorkspaceEntity] {
        switch filter {
        case .all:
            return all
        case .people:
            // Handled separately in recompute()
            return all.filter { $0.kind == .person || $0.kind == .attachedNote || $0.kind == .chatQuery }
        case .meetings:
            return all.filter { $0.kind == .meeting || $0.kind == .chatQuery }
        case .tasks:
            return all.filter { $0.kind == .project || $0.kind == .actionItem || $0.kind == .chatQuery }
        case .notes:
            return all.filter { $0.kind == .attachedNote || $0.kind == .chatQuery }
        case .voiceNotes:
            return all.filter { $0.kind == .voiceNote || $0.kind == .chatQuery }
        }
    }

    /// People-tab-style query — delegates to PeopleStore.filteredPeople
    /// so it inherits whatever ranking the People tab uses (which works
    /// for Horst). Includes a chatQuery passthrough for long queries
    /// just like the main search.
    private func peopleSearch(query q: String) -> [WorkspaceEntity] {
        let people = PeopleStore.shared.filteredPeople(query: q, tagID: nil, includeGhosts: true)
        var rows: [WorkspaceEntity] = people.prefix(40).map { p in
            let subtitle = [p.role, p.company]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return WorkspaceEntity(
                kind: .person, rawID: p.id,
                title: p.displayName,
                subtitle: subtitle.isEmpty ? (p.primaryEmail.isEmpty ? "Person" : p.primaryEmail) : subtitle,
                date: p.lastInteractionAt ?? p.updatedAt)
        }
        if q.split(whereSeparator: { $0.isWhitespace }).count >= 3 {
            rows.append(WorkspaceEntity(
                kind: .chatQuery, rawID: q,
                title: "Ask Chat: \(q)",
                subtitle: "Run this in the assistant",
                date: nil))
        }
        return rows
    }

    /// Empty-query suggestions for the People tab — most-recently-interacted
    /// contacts so the user can quick-jump without typing.
    private func recentPeopleSuggestions() -> [WorkspaceEntity] {
        PeopleStore.shared.people
            .sorted {
                ($0.lastInteractionAt ?? .distantPast)
                    > ($1.lastInteractionAt ?? .distantPast)
            }
            .prefix(8)
            .map { p in
                let subtitle = [p.role, p.company]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                return WorkspaceEntity(
                    kind: .person, rawID: p.id,
                    title: p.displayName,
                    subtitle: subtitle.isEmpty ? (p.primaryEmail.isEmpty ? "Person" : p.primaryEmail) : subtitle,
                    date: p.lastInteractionAt ?? p.updatedAt)
            }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(0, selection + delta), results.count - 1)
    }

    private func openSelected() {
        if results.indices.contains(selection) {
            open(results[selection])
        } else if let cmd = commandMatches.first {
            // No result rows but a command matches — Enter runs it. (D4-2)
            runCommand(cmd)
        }
    }

    private func open(_ e: WorkspaceEntity) {
        // U2-2: carry the query into the opened meeting's transcript so it lands
        // pre-highlighted — no retyping.
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.kind == .meeting, !q.isEmpty { router.pendingTranscriptQuery = q }
        // Don't dismiss here — the host's router dismisses the search sheet and
        // hops to the next runloop tick before presenting, so the transition
        // doesn't fight itself.
        onOpen(e)
    }

    // MARK: - Command palette (D4-2)

    struct PaletteCommand: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let keywords: [String]
        let run: () -> Void
    }

    private func nav(_ s: TopLevelSection) {
        NotificationCenter.default.post(name: .meetingScribeNavigate, object: s)
    }

    private var allCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "Start recording", icon: "record.circle", keywords: ["record", "start", "meeting"]) {
                Task { await manager.startRecording(for: nil) }
            },
            PaletteCommand(title: "Stop recording", icon: "stop.circle", keywords: ["stop", "record"]) {
                Task { await manager.stopRecording() }
            },
            PaletteCommand(title: "New voice note", icon: "mic.circle", keywords: ["voice", "note", "dictate"]) {
                Task { await manager.startQuickNote() }
            },
            PaletteCommand(title: "New task", icon: "checklist", keywords: ["task", "todo", "new"]) {
                _ = manager.actionItems.createTask(title: "New task")
                nav(.actions)
            },
            PaletteCommand(title: "Add person", icon: "person.crop.circle.badge.plus", keywords: ["person", "contact", "add"]) {
                NotificationCenter.default.post(name: .meetingScribeAddPerson, object: nil)
            },
            PaletteCommand(title: "Go to Today", icon: "sun.max", keywords: ["today", "home"]) { nav(.today) },
            PaletteCommand(title: "Go to Meetings", icon: "person.2.fill", keywords: ["meetings"]) { nav(.meetings) },
            PaletteCommand(title: "Go to People", icon: "person.2", keywords: ["people", "contacts"]) { nav(.people) },
            PaletteCommand(title: "Go to Tasks", icon: "checklist", keywords: ["tasks", "todos"]) { nav(.actions) },
            PaletteCommand(title: "Go to Voice Notes", icon: "waveform", keywords: ["voice", "notes"]) { nav(.notes) },
            PaletteCommand(title: "Generate weekly review", icon: "calendar.badge.clock", keywords: ["weekly", "review", "recap"]) {
                if let url = WeeklyRecap.generate(manager: manager) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            PaletteCommand(title: "Refresh", icon: "arrow.clockwise", keywords: ["refresh", "reload"]) {
                manager.refreshPastMeetings(force: true); manager.refreshQuickNotes()
            },
        ]
    }

    var commandMatches: [PaletteCommand] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return allCommands.filter { c in
            c.title.lowercased().contains(q) || c.keywords.contains { $0.contains(q) }
        }
    }

    func runCommand(_ c: PaletteCommand) {
        isPresented = false
        c.run()
    }
}
