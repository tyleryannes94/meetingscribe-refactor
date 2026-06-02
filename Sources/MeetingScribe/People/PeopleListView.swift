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
    /// Debounced mirror of `query` — the filter/FTS pipeline runs off this so it
    /// doesn't re-run on every keystroke. (V5 PR-4)
    @State private var debouncedQuery = ""
    /// AND-filter: a person must carry EVERY selected tag to show. Empty = all.
    @State private var tagFilters: Set<String> = []
    @State private var showTagManager = false
    @State private var selection: String?
    @State private var showAdd = false
    @State private var showGhosts = false
    @State private var showDuplicates = false
    @State private var dedupResult: String?
    /// Phase 7 — toggles the force-directed mindmap in place of the list/detail.
    @State private var graphMode = false

    // Multi-select + bulk actions (FT3-2/FT3-3).
    @State private var selectMode = false
    @State private var multiSelection: Set<String> = []
    @State private var bulkConfirmDelete = false
    @State private var bulkConfirmMerge = false

    /// Frame-0 launch snapshot (PC-1) — loaded synchronously so the list is
    /// populated instantly on cold open while PeopleStore hydrates off-main.
    @State private var snapshotRows: [PeopleStore.ListSnapshot.Row] =
        PeopleStore.loadListSnapshot()?.rows ?? []

    @AppStorage("people.sortOrder") private var sortRaw = PeopleSort.recent.rawValue
    private var sortOrder: PeopleSort { PeopleSort(rawValue: sortRaw) ?? .recent }

    /// Active relationship-type filter; nil = show all types.
    @State private var relationshipTypeFilter: RelationshipType? = nil

    private var filtered: [Person] {
        // The store filters by a single tag; apply the remaining AND-tags and the
        // chosen sort here. Search relevance order is preserved while querying.
        let base = people.filteredPeople(query: debouncedQuery, tagID: tagFilters.first, includeGhosts: showGhosts)
        let tagged = tagFilters.count <= 1 ? base : base.filter { tagFilters.isSubset(of: $0.tagIDs) }
        // Apply relationship-type filter when set.
        let typeFiltered: [Person]
        if let rtype = relationshipTypeFilter {
            typeFiltered = tagged.filter { $0.relationshipType == rtype }
        } else {
            typeFiltered = tagged
        }
        guard debouncedQuery.isEmpty else { return typeFiltered }
        return sorted(typeFiltered)
    }

    /// Which relationship types actually appear in the current people list (for chip visibility).
    private var presentTypes: [RelationshipType] {
        let used = Set(people.people.map(\.relationshipType)).subtracting([.unset])
        return RelationshipType.allCases.filter { used.contains($0) }
    }

    private func sorted(_ list: [Person]) -> [Person] {
        switch sortOrder {
        case .recent:
            return list.sorted { ($0.lastInteractionAt ?? .distantPast) > ($1.lastInteractionAt ?? .distantPast) }
        case .name:
            return list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .meetings:
            return list.sorted { meetingCount($0) > meetingCount($1) }
        case .newest:
            return list.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func meetingCount(_ p: Person) -> Int {
        people.encounterCount(for: p.id) + p.meetingMentions.count
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
        .onChange(of: query) { _, new in
            // Clearing is instant; typing settles for 180ms before the pipeline runs.
            if new.isEmpty { debouncedQuery = ""; return }
            Task {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if query == new { debouncedQuery = new }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPersonSheet(seedTagID: tagFilters.first)
                .environmentObject(people)
                .environmentObject(peopleTags)
        }
        .sheet(isPresented: $showDuplicates) {
            DuplicateReviewSheet().environmentObject(people)
        }
        .sheet(isPresented: $showTagManager) {
            TagManagementSheet().environmentObject(people).environmentObject(peopleTags)
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
                tagFilters = [match.id]
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
            // Sort the list (persisted). Disabled while searching, where results
            // are ordered by relevance.
            Menu {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(PeopleSort.allCases) { s in
                        Label(s.label, systemImage: s.icon).tag(s.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(!query.isEmpty)
            .help("Sort people")
            // Multi-select for bulk tag / merge / delete (FT3-2/FT3-3).
            if !people.people.isEmpty {
                Button {
                    selectMode.toggle()
                    if !selectMode { multiSelection = [] }
                } label: {
                    Text(selectMode ? "Done" : "Select")
                }
                .help("Select multiple people for bulk actions")
            }
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
            .padding(.horizontal).padding(.top, NDS.splitPaneTopInset).padding(.bottom, 6)

            // Always-visible actions — works whether the list is empty or full.
            actionsRow

            if let status = importer.status {
                Text(status)
                    .font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
            }

            MSSearchField(placeholder: "Search name, company, role…", text: $query)
                .padding(.horizontal).padding(.bottom, 8)

            tagChips

            // Relationship-type filter chips (only shown when multiple types are in use).
            if presentTypes.count > 1 {
                relationshipTypeChips
            }

            Divider()

            if people.people.isEmpty {
                if snapshotRows.isEmpty {
                    emptyState
                } else {
                    // Launch snapshot: instantly-populated rows while the store
                    // hydrates; replaced by the live list the moment it loads. (PC-1)
                    List {
                        ForEach(snapshotRows) { row in SnapshotPersonRow(row: row) }
                    }
                    .listStyle(.inset)
                    .allowsHitTesting(false)
                }
            } else if selectMode {
                List(selection: $multiSelection) {
                    ForEach(filtered) { person in
                        PersonRow(person: person)
                            .tag(person.id)
                    }
                }
                .listStyle(.inset)
                bulkBar
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { person in
                        PersonRow(person: person)
                            .tag(person.id)
                            .contextMenu { personRowMenu(person) }   // right-click (SC-7)
                    }
                }
                .listStyle(.inset)
                ghostFooter
            }
        }
    }

    /// Right-click actions on a person row.
    @ViewBuilder
    private func personRowMenu(_ person: Person) -> some View {
        Button { selection = person.id } label: { Label("Open", systemImage: "arrow.forward") }
        let unused = peopleTags.allTags.filter { !person.tagIDs.contains($0.id) }
        if !unused.isEmpty {
            Menu {
                ForEach(unused) { t in
                    Button(t.name) {
                        var u = person; u.tagIDs.insert(t.id); people.updatePerson(u)
                    }
                }
            } label: { Label("Add tag", systemImage: "tag") }
        }
        Divider()
        Button(role: .destructive) { deleteWithUndo(person) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Delete a person but offer an Undo toast that restores them. (V5 DI-3)
    private func deleteWithUndo(_ person: Person) {
        let snapshot = person
        let encounters = people.encounters(for: person.id)
        if selection == person.id { selection = nil }
        people.deletePerson(person)
        ToastCenter.shared.show("Deleted \(person.displayName)", undoTitle: "Undo") {
            people.restore(person: snapshot, encounters: encounters)
        }
    }

    // MARK: - Bulk actions

    /// Bottom bar shown in select mode: tag, merge, or delete the checked people.
    @ViewBuilder
    private var bulkBar: some View {
        let usable = peopleTags.allTags
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Text("\(multiSelection.count) selected")
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
                Spacer(minLength: 0)
                Menu {
                    if usable.isEmpty {
                        Text("No tags yet")
                    } else {
                        ForEach(usable) { t in
                            Button(t.name) { applyTagToSelection(t.id) }
                        }
                    }
                } label: {
                    Label("Tag", systemImage: "tag")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(multiSelection.isEmpty || usable.isEmpty)

                Button {
                    bulkConfirmMerge = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .disabled(multiSelection.count < 2)
                .help("Merge the selected people into one record")

                Button(role: .destructive) {
                    bulkConfirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(multiSelection.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .confirmationDialog(
            "Merge \(multiSelection.count) people into one?",
            isPresented: $bulkConfirmMerge, titleVisibility: .visible) {
            Button("Merge into \(mergeKeeper()?.displayName ?? "the strongest record")") { mergeSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Encounters, tags, notes, and relationships are combined onto the most complete record. This can't be undone.")
        }
        .confirmationDialog(
            "Delete \(multiSelection.count) \(multiSelection.count == 1 ? "person" : "people")?",
            isPresented: $bulkConfirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their records and encounters are permanently removed.")
        }
    }

    private func applyTagToSelection(_ tagID: String) {
        for id in multiSelection {
            guard var p = people.person(by: id), !p.tagIDs.contains(tagID) else { continue }
            p.tagIDs.insert(tagID)
            people.updatePerson(p)
        }
    }

    /// The record bulk-merge collapses into: the highest-signal of the selection.
    private func mergeKeeper() -> Person? {
        multiSelection.compactMap { people.person(by: $0) }.max {
            $0.relevanceScore(encounterCount: people.encounterCount(for: $0.id))
                < $1.relevanceScore(encounterCount: people.encounterCount(for: $1.id))
        }
    }

    private func mergeSelection() {
        guard let keeper = mergeKeeper() else { return }
        for id in multiSelection where id != keeper.id {
            people.mergePeople(keep: keeper.id, remove: id)
        }
        multiSelection = []
        selectMode = false
        selection = keeper.id
    }

    private func deleteSelection() {
        // Snapshot for Undo before the files are removed.
        let snapshots: [(Person, [Encounter])] = multiSelection.compactMap { id in
            guard let p = people.person(by: id) else { return nil }
            return (p, people.encounters(for: id))
        }
        for (p, _) in snapshots { people.deletePerson(p) }
        if let sel = selection, multiSelection.contains(sel) { selection = nil }
        let count = snapshots.count
        multiSelection = []
        selectMode = false
        guard count > 0 else { return }
        ToastCenter.shared.show("Deleted \(count) \(count == 1 ? "person" : "people")", undoTitle: "Undo") {
            for (p, encs) in snapshots { people.restore(person: p, encounters: encs) }
        }
    }

    /// "N low-signal contacts hidden" toggle (§12.4) — only when the unfiltered
    /// list is actually hiding ghosts.
    @ViewBuilder
    private var ghostFooter: some View {
        if debouncedQuery.isEmpty, tagFilters.isEmpty, people.ghostCount > 0 {
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
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterChip(label: "All", active: tagFilters.isEmpty) { tagFilters = [] }
                        ForEach(used) { t in
                            // AND semantics — selecting two tags shows only people
                            // carrying both. (UX3-5)
                            FilterChip(label: t.name, active: tagFilters.contains(t.id)) {
                                if tagFilters.contains(t.id) { tagFilters.remove(t.id) }
                                else { tagFilters.insert(t.id) }
                            }
                        }
                    }
                    .padding(.leading)
                }
                // Manage tags — rename/delete (store methods existed but had no
                // UI, so a typo'd tag was permanent). (FT3-1)
                Button { showTagManager = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                }
                .buttonStyle(.borderless).help("Manage tags").padding(.trailing)
            }
            .padding(.bottom, 8)
        }
    }

    /// Horizontal chip bar for filtering by relationship type.
    @ViewBuilder
    private var relationshipTypeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All", active: relationshipTypeFilter == nil) {
                    relationshipTypeFilter = nil
                }
                ForEach(presentTypes, id: \.self) { rtype in
                    FilterChip(
                        label: "\(rtype.emoji) \(rtype.displayName)",
                        active: relationshipTypeFilter == rtype
                    ) {
                        relationshipTypeFilter = (relationshipTypeFilter == rtype) ? nil : rtype
                    }
                }
            }
            .padding(.leading)
        }
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        MSEmptyState(systemImage: "person.2",
                     title: "No people yet",
                     message: "Use Add Person or Import above to get started — from Contacts, Gmail, your calendar, or a file.")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let person = people.person(by: id) {
            PersonDetailView(person: person, onDeleted: { selection = nil })
                .id(person.id)
        } else {
            // Relationship dashboard instead of dead space (reconnect / birthdays /
            // most-active). Selecting a card row opens that person.
            PeopleInsightsView(onOpen: { selection = $0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// List ordering options (persisted via @AppStorage). Applied when not searching.
enum PeopleSort: String, CaseIterable, Identifiable {
    case recent, name, meetings, newest
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent:   return "Recent activity"
        case .name:     return "Name (A–Z)"
        case .meetings: return "Most meetings"
        case .newest:   return "Recently added"
        }
    }
    var icon: String {
        switch self {
        case .recent:   return "clock"
        case .name:     return "textformat.abc"
        case .meetings: return "calendar"
        case .newest:   return "sparkles"
        }
    }
}

/// Frame-0 snapshot row (PC-1) — same shape as PersonRow but driven by the tiny
/// persisted digest, so the list looks identical before the store hydrates.
@available(macOS 14.0, *)
private struct SnapshotPersonRow: View {
    let row: PeopleStore.ListSnapshot.Row
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 26)).foregroundStyle(NDS.brand.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let e = row.lastEpoch {
                Text(Self.relative.localizedString(for: Date(timeIntervalSince1970: e), relativeTo: Date()))
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.vertical, 3)
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
                HStack(spacing: 4) {
                    Text(person.displayName).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    // Relationship type badge — only shown when type is set.
                    if person.relationshipType != .unset {
                        Text(person.relationshipType.emoji)
                            .font(.system(size: 11))
                            .help(person.relationshipType.displayName)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Last-interaction recency so "who have I gone cold on?" is visible
            // without opening each person. (UX3-2)
            if let last = person.lastInteractionAt {
                Text(Self.relative.localizedString(for: last, relativeTo: Date()))
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
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
