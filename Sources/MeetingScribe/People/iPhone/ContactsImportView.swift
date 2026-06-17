import SwiftUI
import Contacts

/// Phase 7-B (Option 2): search macOS Contacts, multi-select, and import with a
/// before-import diff ("N new will be added, M already exist"). Import goes
/// through `PeopleStore.importPeople`, which dedupes/merges against existing
/// people, so re-importing a known contact updates rather than duplicates.
@available(macOS 14.0, *)
struct ContactsImportView: View {
    @EnvironmentObject var people: PeopleStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var candidates: [Candidate] = []
    @State private var selected: Set<UUID> = []
    @State private var loading = false
    @State private var loaded = false
    @State private var resultMessage: String?

    /// A fetched contact plus a stable id and whether it already exists.
    struct Candidate: Identifiable {
        let id = UUID()
        let `import`: PersonImport
        let alreadyExists: Bool
    }

    private var filtered: [Candidate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.import.displayName.lowercased().contains(q)
                || $0.import.company.lowercased().contains(q)
                || $0.import.emails.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private var selectedCandidates: [Candidate] { candidates.filter { selected.contains($0.id) } }
    private var newCount: Int { selectedCandidates.filter { !$0.alreadyExists }.count }
    private var existingCount: Int { selectedCandidates.filter { $0.alreadyExists }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480, minHeight: 560)
        .task { await loadIfNeeded() }
        .alert("Import complete", isPresented: Binding(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") { dismiss() }
        } message: { Text(resultMessage ?? "") }
    }

    private var header: some View {
        HStack {
            Text("Import from Contacts").font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(NDS.textTertiary)
            TextField("Search contacts by name, company, email…", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView("Loading Contacts…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !loaded {
            permissionPrompt
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .scaledFont(36).foregroundStyle(.secondary)
                Text(query.isEmpty ? "No contacts found." : "No matches.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filtered) { candidate in row(candidate) }
            }
            .listStyle(.inset)
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").scaledFont(36).foregroundStyle(.secondary)
            Text("Contacts access needed").font(.headline)
            Text("MeetingScribe reads Contacts read-only to import people.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Allow Contacts Access") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private func row(_ candidate: Candidate) -> some View {
        let isOn = selected.contains(candidate.id)
        return Button {
            if isOn { selected.remove(candidate.id) } else { selected.insert(candidate.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? NDS.brand : NDS.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.import.displayName).scaledFont(13, weight: .semibold)
                    let sub = [candidate.import.role, candidate.import.company]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    let detail = sub.isEmpty ? (candidate.import.emails.first ?? "") : sub
                    if !detail.isEmpty {
                        Text(detail).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if candidate.alreadyExists {
                    Text("exists").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(NDS.fieldBg, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            if selected.isEmpty {
                Text("Select contacts to import.").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            } else {
                Text(diffSummary).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            Button("Select All") { selected = Set(filtered.map { $0.id }) }
                .disabled(filtered.isEmpty)
            Button("Import Selected") { importSelected() }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
        }
        .padding(12)
    }

    private var diffSummary: String {
        var parts: [String] = []
        if newCount > 0 { parts.append("\(newCount) new \(newCount == 1 ? "person" : "people") will be added") }
        if existingCount > 0 { parts.append("\(existingCount) already \(existingCount == 1 ? "exists" : "exist") (will be updated)") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Data

    private func loadIfNeeded() async {
        guard !loaded, ContactsImporter.isAuthorized else { return }
        await load()
    }

    private func load() async {
        loading = true
        let imports = (try? await ContactsImporter.fetchAll()) ?? []
        let existingEmails = Set(people.people.flatMap { $0.emails.map { $0.lowercased() } })
        let existingNames = Set(people.people.map { $0.displayName.lowercased() })
        let existingCIDs = Set(people.people.compactMap { $0.contactIdentifier })
        candidates = imports
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { imp in
                let exists = (imp.contactIdentifier.map { existingCIDs.contains($0) } ?? false)
                    || imp.emails.contains(where: { existingEmails.contains($0.lowercased()) })
                    || existingNames.contains(imp.displayName.lowercased())
                return Candidate(import: imp, alreadyExists: exists)
            }
        loading = false
        loaded = true
    }

    private func importSelected() {
        let toImport = selectedCandidates.map { $0.import }
        let result = people.importPeople(toImport)
        resultMessage = "Added \(result.created), updated \(result.merged)."
    }
}
