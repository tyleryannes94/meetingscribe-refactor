import SwiftUI

/// Add or edit a person. Presented from the People list ("+ Add") and from the
/// global ⇧⌘P shortcut (new person), or from a person's detail view (edit).
@available(macOS 14.0, *)
struct AddPersonSheet: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var peopleTags: PeopleTagStore
    @Environment(\.dismiss) private var dismiss

    /// The person being edited, or nil for a brand-new person.
    let editing: Person?

    @FocusState private var nameFocused: Bool
    @State private var displayName: String
    @State private var company: String
    @State private var role: String
    @State private var emails: [String]
    @State private var phones: [String]
    @State private var bio: String
    @State private var tagIDs: Set<String>
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var addresses: [String]
    @State private var favorites: String

    init(editing: Person? = nil, seedTagID: String? = nil) {
        self.editing = editing
        _displayName = State(initialValue: editing?.displayName ?? "")
        _company = State(initialValue: editing?.company ?? "")
        _role = State(initialValue: editing?.role ?? "")
        _emails = State(initialValue: (editing?.emails.isEmpty == false) ? editing!.emails : [""])
        _phones = State(initialValue: (editing?.phones.isEmpty == false) ? editing!.phones : [""])
        _bio = State(initialValue: editing?.bio ?? "")
        // Prefill the active tag when adding while a tag filter is on. (UX3-3)
        _tagIDs = State(initialValue: editing?.tagIDs ?? (seedTagID.map { [$0] } ?? []))
        _hasBirthday = State(initialValue: editing?.birthday != nil)
        _birthday = State(initialValue: editing?.birthday ?? Date())
        _addresses = State(initialValue: (editing?.addresses.isEmpty == false) ? editing!.addresses : [""])
        _favorites = State(initialValue: (editing?.favorites ?? []).joined(separator: ", "))
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "New Person" : "Edit Person")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Inlined (not the `field` helper) so `.focused` lands on the
                    // TextField itself — UX10-4 auto-focus on a new person.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                        TextField("Jane Smith", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                    }
                    HStack(spacing: 12) {
                        field("Company", text: $company, prompt: "Acme")
                        field("Role", text: $role, prompt: "Engineer")
                    }
                    multiField("Email", $emails, prompt: "jane@acme.com")
                    multiField("Phone", $phones, prompt: "(555) 123-4567")
                    multiField("Address", $addresses, prompt: "123 Main St, City")
                    field("Favorite things", text: $favorites, prompt: "coffee, hiking, sci-fi (comma-separated)")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Birthday").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                        HStack {
                            Toggle("", isOn: $hasBirthday).labelsHidden()
                            DatePicker("", selection: $birthday, displayedComponents: .date)
                                .labelsHidden().disabled(!hasBirthday)
                            Spacer()
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                        EventTagSelector(selected: $tagIDs)
                            .environmentObject(peopleTags)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                        TextEditor(text: $bio)
                            .font(NDS.body)
                            .frame(minHeight: 100)
                            .padding(6)
                            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                            .overlay(RoundedRectangle(cornerRadius: NDS.radius)
                                .strokeBorder(NDS.hairline, lineWidth: 1))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 540)
        .onAppear { if editing == nil { nameFocused = true } }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let cleanEmails = emails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let cleanPhones = phones.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let cleanAddresses = addresses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let favs = favorites.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        // Start from the edited person (preserving imported extra values), or a
        // fresh one. `updatePerson` upserts, so this handles both create + edit.
        var person = editing ?? Person(displayName: trimmedName)
        person.displayName = trimmedName
        person.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        person.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        person.emails = cleanEmails
        person.phones = cleanPhones
        person.addresses = cleanAddresses
        person.favorites = favs
        person.bio = bio
        person.tagIDs = tagIDs
        person.birthday = hasBirthday ? birthday : nil
        person.importSources.insert("manual")
        people.updatePerson(person)
        dismiss()
    }

    /// Repeatable list of text rows (email/phone/address) with add + remove, so
    /// a person can hold multiple values. The model already stores arrays; the
    /// sheet previously edited only the first via `replacingFirst` (PPL-2).
    @ViewBuilder
    private func multiField(_ label: String, _ values: Binding<[String]>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            ForEach(values.wrappedValue.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    TextField(prompt, text: Binding(
                        get: { i < values.wrappedValue.count ? values.wrappedValue[i] : "" },
                        set: { newValue in
                            var arr = values.wrappedValue
                            if i < arr.count { arr[i] = newValue; values.wrappedValue = arr }
                        }))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        var arr = values.wrappedValue
                        if i < arr.count { arr.remove(at: i) }
                        if arr.isEmpty { arr = [""] }
                        values.wrappedValue = arr
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(NDS.textTertiary)
                    .help("Remove")
                }
            }
            Button {
                values.wrappedValue.append("")
            } label: {
                Label("Add \(label.lowercased())", systemImage: "plus.circle").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// A chip row + popover for choosing people tags (e.g. "Purple Party 2026")
/// from the dedicated `PeopleTagStore` — separate from meeting tags — with an
/// inline "create new tag" field. Binds to a `Set<String>` of people-tag ids.
@available(macOS 14.0, *)
struct EventTagSelector: View {
    @EnvironmentObject var peopleTags: PeopleTagStore
    @Binding var selected: Set<String>

    @State private var showingPopover = false
    @State private var newTagName = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(peopleTags.allTags.filter { selected.contains($0.id) }) { t in
                TagChip(tag: t, removable: true) { selected.remove(t.id) }
            }
            Button { showingPopover = true } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                popover.frame(width: 260)
            }
            Spacer(minLength: 0)
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.headline).padding(.horizontal).padding(.top, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(peopleTags.allTags) { t in
                        Button {
                            if selected.contains(t.id) { selected.remove(t.id) }
                            else { selected.insert(t.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(t.id) ? "checkmark.square.fill" : "square")
                                TagChip(tag: t, removable: false, onRemove: nil)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 220)
            Divider()
            HStack {
                TextField("New tag…", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let t = peopleTags.createTag(name: trimmed)
                    selected.insert(t.id)
                    newTagName = ""
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 8)
        }
    }
}
