import SwiftUI
import AppKit

/// Phase 4 — ⌘K command palette. Searches meetings, voice notes, projects, and
/// action items in one place; selecting a result navigates to it. Empty query
/// shows recent meetings as quick-jump suggestions.
@available(macOS 14.0, *)
struct GlobalSearchView: View {
    @EnvironmentObject var manager: MeetingManager
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
        .frame(width: 620, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
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
            TextField("Search meetings, notes, projects, action items…", text: $query)
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
        if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: query.isEmpty ? "sparkle.magnifyingglass" : "questionmark.folder")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
                Text(query.isEmpty ? "Type to search your workspace" : "No matches for “\(query)”")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, e in
                            row(e, index: idx)
                                .id(idx)
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
                    Text(e.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

    private func recompute() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
                guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
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
        return WorkspaceEntity(kind: kind, rawID: r.entityID,
                               title: r.title ?? "(untitled)",
                               subtitle: subtitle, date: date)
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
        guard results.indices.contains(selection) else { return }
        open(results[selection])
    }

    private func open(_ e: WorkspaceEntity) {
        // Don't dismiss here — the host's router dismisses the search sheet and
        // hops to the next runloop tick before presenting, so the transition
        // doesn't fight itself.
        onOpen(e)
    }
}
