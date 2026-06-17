import SwiftUI

/// Rename / delete people-tags (FT3-1). The `PeopleTagStore` rename/delete
/// methods already existed but had no UI, so a typo'd tag ("Purpl Party") was
/// permanent and cluttered the chip row forever.
@available(macOS 14.0, *)
struct TagManagementSheet: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var peopleTags: PeopleTagStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingID: String?
    @State private var draftName = ""
    @State private var confirmDeleteID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Manage tags").scaledFont(18, weight: .bold)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            if peopleTags.allTags.isEmpty {
                Text("No tags yet.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(peopleTags.allTags) { tag in row(tag) }
                    }
                    .padding(10)
                }
            }
        }
        .frame(minWidth: 440, maxWidth: 440, minHeight: 480)
    }

    private func row(_ tag: MeetingTag) -> some View {
        let count = people.people.filter { $0.tagIDs.contains(tag.id) }.count
        return HStack(spacing: 10) {
            if editingID == tag.id {
                TextField("Tag name", text: $draftName, onCommit: { commitRename(tag) })
                    .textFieldStyle(.roundedBorder)
                Button("Save") { commitRename(tag) }.controlSize(.small)
                Button("Cancel") { editingID = nil }.controlSize(.small)
            } else {
                Text(tag.name).font(.body)
                Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
                Button { editingID = tag.id; draftName = tag.name } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless).help("Rename")
                Button(role: .destructive) { confirmDeleteID = tag.id } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).help("Delete")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog("Delete tag “\(tag.name)”?",
                            isPresented: Binding(get: { confirmDeleteID == tag.id },
                                                 set: { if !$0 { confirmDeleteID = nil } }),
                            titleVisibility: .visible) {
            Button("Delete tag", role: .destructive) { peopleTags.deleteTag(id: tag.id) }
        } message: {
            Text("Removes the tag from \(count) \(count == 1 ? "person" : "people"). Their records are kept.")
        }
    }

    private func commitRename(_ tag: MeetingTag) {
        let n = draftName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { peopleTags.renameTag(id: tag.id, to: n) }
        editingID = nil
    }
}
