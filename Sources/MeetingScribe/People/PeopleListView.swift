import SwiftUI

/// The People tab: a searchable, tag-filterable list of people on the left and
/// the selected person's detail on the right. This is the Phase A "search for a
/// tag like 'Purple Party 2026' and find everyone there" surface.
@available(macOS 14.0, *)
struct PeopleListView: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var peopleTags: PeopleTagStore
    @EnvironmentObject var manager: MeetingManager
    @StateObject private var importer = PeopleImportController()

    @State private var query = ""
    @State private var tagFilter: String?
    @State private var selection: String?
    @State private var showAdd = false
    @State private var showGhosts = false
    @State private var showDuplicates = false
    @State private var dedupResult: String?
    /// Phase 7 — toggles the force-directed mindmap in place of the list/detail.
    @State private var graphMode = false

    private var filtered: [Person] {
        people.filteredPeople(query: query, tagID: tagFilter, includeGhosts: showGhosts)
    }

    var body: some View {
        Group {
            if graphMode {
                PeopleGraphView(
                    onExit: { graphMode = false },
                    onOpenProfile: { id in graphMode = false; selection = id }
                )
            } else {
                HSplitView {
                    sidebar.frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                    detail.frame(minWidth: 380)
                }
            }
        }
        .task { people.rebuildIndexIfNeeded() }   // builds the FTS5 index for search
        .sheet(isPresented: $showAdd) {
            AddPersonSheet()
                .environmentObject(people)
                .environmentObject(peopleTags)
        }
        .sheet(isPresented: $showDuplicates) {
            DuplicateReviewSheet().environmentObject(people)
        }
        .alert("Merge duplicates", isPresented: Binding(
            get: { dedupResult != nil }, set: { if !$0 { dedupResult = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(dedupResult ?? "") }
        // Search-palette routing: jump to a specific person or apply a
        // tag filter. The notifications are posted by MainWindow's
        // routeEntity when the user picks one of these result types.
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeOpenPerson)) { note in
            if let id = note.userInfo?["id"] as? String { selection = id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeFilterByTag)) { note in
            guard let name = note.userInfo?["name"] as? String else { return }
            // Resolve the typed tag name to a tag id from PeopleTagStore.
            if let match = peopleTags.allTags.first(where: {
                $0.name.lowercased() == name.lowercased()
                    || $0.name.lowercased().contains(name.lowercased())
            }) {
                tagFilter = match.id
            } else {
                query = name
            }
        }
    }

    @ViewBuilder
    private var importMenuItems: some View {
        Button("Apple / iCloud Contacts") { Task { await importer.importAppleContacts() } }
        Button("Gmail / Google Contacts")  { Task { await importer.importGmail() } }
        Button("Calendar attendees")       { importer.importCalendarAttendees(from: manager.pastMeetings) }
        Button("From file (vCard / CSV)…")  { importer.importFromFile() }
        Divider()
        Button("Find duplicates…")          { showDuplicates = true }
        Button("Merge all duplicates")      {
            let r = people.deduplicate()
            dedupResult = r.removed == 0
                ? "No duplicates found — your People list is clean."
                : "Merged \(r.merged) group\(r.merged == 1 ? "" : "s") and removed \(r.removed) duplicate\(r.removed == 1 ? "" : "s")."
        }
    }

    /// Add Person + Import, as clearly-bordered controls. Lives in the sidebar
    /// body (not the title row) so it's reliably visible in every state.
    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button { showAdd = true } label: {
                Label("Add Person", systemImage: "plus")
            }
            .help("Add a person (⇧⌘P)")
            Menu {
                importMenuItems
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .fixedSize()
            .disabled(importer.isWorking)
            .help("Import people from Contacts, Gmail, calendar, or a file")
            Spacer(minLength: 0)
        }
        .padding(.horizontal).padding(.bottom, 8)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("People").font(.title2).bold()
                Spacer()
                if importer.isWorking { ProgressView().controlSize(.small) }
                // Graph view is available but demoted — it's rarely useful
                // with 500+ contacts and is just decorative at large scale.
                // Accessible via a compact icon button, not a primary action.
                if !people.people.isEmpty {
                    NotionIconButton(systemName: "circle.hexagongrid",
                                     help: "Graph view (experimental)") {
                        graphMode = true
                    }
                }
            }
            // Top padding bumped from default (~16pt) so the title and the
            // action row underneath aren't clipped by the window toolbar
            // overlay on macOS Tahoe. Matches the detail pane's 72pt top
            // inset so the two panes line up visually.
            .padding(.horizontal).padding(.top, 60).padding(.bottom, 6)

            // Always-visible actions — works whether the list is empty or full.
            actionsRow

            if let status = importer.status {
                Text(status)
                    .font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(NDS.textTertiary)
                TextField("Search name, company, role…", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            .padding(.horizontal).padding(.bottom, 8)

            tagChips

            Divider()

            if people.people.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { person in
                        PersonRow(person: person)
                            .tag(person.id)
                    }
                }
                .listStyle(.inset)
                ghostFooter
            }
        }
    }

    /// "N low-signal contacts hidden" toggle (§12.4) — only when the unfiltered
    /// list is actually hiding ghosts.
    @ViewBuilder
    private var ghostFooter: some View {
        if query.isEmpty, tagFilter == nil, people.ghostCount > 0 {
            Button {
                withAnimation { showGhosts.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showGhosts ? "eye.slash" : "person.crop.circle.badge.questionmark")
                    Text(showGhosts ? "Hide \(people.ghostCount) low-signal contacts"
                                    : "Show \(people.ghostCount) more contacts")
                    Spacer()
                }
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Imported contacts you haven't interacted with are hidden by default")
        }
    }

    @ViewBuilder
    private var tagChips: some View {
        let used = peopleTags.allTags.filter { people.usedTagIDs().contains($0.id) }
        if !used.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(label: "All", active: tagFilter == nil) { tagFilter = nil }
                    ForEach(used) { t in
                        FilterChip(label: t.name, active: tagFilter == t.id) {
                            tagFilter = (tagFilter == t.id) ? nil : t.id
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No people yet").font(.headline)
            Text("Use Add Person or Import above to get started — from Contacts, Gmail, your calendar, or a file.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let person = people.person(by: id) {
            PersonDetailView(person: person, onDeleted: { selection = nil })
                .id(person.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Select a person").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 14.0, *)
private struct PersonRow: View {
    let person: Person

    private var subtitle: String {
        [person.role, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(NDS.brand.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

@available(macOS 14.0, *)
private struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(NDS.tiny)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? NDS.brand.opacity(0.18) : NDS.fieldBg, in: Capsule())
                .overlay(Capsule().strokeBorder(active ? NDS.brand.opacity(0.5) : NDS.hairline, lineWidth: 1))
                .foregroundStyle(active ? NDS.brand : NDS.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

/// Review surface for likely-duplicate people (§12.3) — merge or keep separate.
@available(macOS 14.0, *)
struct DuplicateReviewSheet: View {
    @EnvironmentObject var people: PeopleStore
    @Environment(\.dismiss) private var dismiss

    @State private var pairs: [(a: Person, b: Person, score: Double)] = []
    @State private var dismissedKeys: Set<String> = []
    @State private var loaded = false

    private func key(_ a: Person, _ b: Person) -> String { [a.id, b.id].sorted().joined(separator: "|") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Possible duplicates").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            let visible = pairs.filter { !dismissedKeys.contains(key($0.a, $0.b)) }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("No likely duplicates found.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, pair in
                            row(pair)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 460, height: 520)
        .onAppear {
            guard !loaded else { return }
            pairs = people.duplicateCandidates()
            loaded = true
        }
    }

    @ViewBuilder
    private func row(_ pair: (a: Person, b: Person, score: Double)) -> some View {
        // Keep the higher-signal record.
        let aScore = pair.a.relevanceScore(encounterCount: people.encounterCount(for: pair.a.id))
        let bScore = pair.b.relevanceScore(encounterCount: people.encounterCount(for: pair.b.id))
        let keeper = aScore >= bScore ? pair.a : pair.b
        let loser = aScore >= bScore ? pair.b : pair.a
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pair.a.displayName).font(.system(size: 13, weight: .semibold))
                Text("·").foregroundStyle(.secondary)
                Text(pair.b.displayName).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(pair.score >= 1 ? "shared email" : "\(Int(pair.score * 100))% name match")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            HStack {
                Button("Merge → \(keeper.displayName)") {
                    people.mergePeople(keep: keeper.id, remove: loser.id)
                    dismissedKeys.insert(key(pair.a, pair.b))
                }
                Button("Not duplicates") { dismissedKeys.insert(key(pair.a, pair.b)) }
                    .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                Spacer()
            }
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
    }
}
