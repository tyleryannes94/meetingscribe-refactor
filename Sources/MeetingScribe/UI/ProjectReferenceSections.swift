import SwiftUI

/// Project-page knowledge sections: the **Decision log** (and, added in a later
/// phase, **Reference materials**). These turn a project/feature page into the
/// place a PM logs the calls made while building and pins the docs that back
/// them. Inserted under `ProjectPageHeader` in `ActionItemsChrome.projectPane`.
///
/// Decisions here are the same `Decision` records the rest of the app uses:
/// some are auto-extracted from meetings (and assigned to this project), others
/// are logged by hand via `DecisionStore.addManual(..., projectID:)`.
struct ProjectDecisionsSection: View {
    @EnvironmentObject private var decisions: DecisionStore
    let projectID: String

    @State private var expanded = true
    @State private var draft = ""
    @State private var draftWhy = ""
    @State private var addingWhy = false

    private var all: [Decision] {
        decisions.decisions(forProject: projectID).sorted { $0.date > $1.date }
    }
    private var toMake: [Decision] { all.filter { $0.status == .open } }
    private var made: [Decision] { all.filter { $0.status == .resolved } }
    private var superseded: [Decision] { all.filter { $0.status == .superseded } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded {
                addRow
                if all.isEmpty {
                    Text("No decisions yet. Log the calls you make building this — they’ll also collect here automatically from linked meetings.")
                        .scaledFont(12).foregroundStyle(NDS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    group("To make", toMake, tint: NDS.gold)
                    group("Made", made, tint: NDS.mint)
                    group("Superseded", superseded, tint: NDS.textTertiary)
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 12)
    }

    private var header: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").scaledFont(12).foregroundStyle(NDS.brand)
                Text("Decisions").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                if !all.isEmpty {
                    Text("\(all.count)").scaledFont(11).foregroundStyle(NDS.textTertiary)
                }
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .scaledFont(10).foregroundStyle(NDS.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle").scaledFont(13).foregroundStyle(NDS.textTertiary)
                TextField("Add a decision to make…", text: $draft)
                    .textFieldStyle(.plain).scaledFont(13)
                    .onSubmit(commit)
                Button { addingWhy.toggle() } label: {
                    Image(systemName: addingWhy ? "text.bubble.fill" : "text.bubble")
                        .scaledFont(12).foregroundStyle(addingWhy ? NDS.brand : NDS.textTertiary)
                }
                .buttonStyle(.plain).help("Add the why (rationale)")
                Button("Add", action: commit)
                    .buttonStyle(.plain).scaledFont(12).foregroundStyle(NDS.brand)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if addingWhy {
                TextField("Why — the reason behind it (optional)", text: $draftWhy)
                    .textFieldStyle(.plain).scaledFont(12).foregroundStyle(NDS.textSecondary)
                    .padding(.leading, 21)
            }
        }
        .padding(10)
        .background(NDS.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [Decision], tint: Color) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased()).font(NDS.tiny).tracking(0.6)
                    .foregroundStyle(NDS.textTertiary)
                ForEach(rows) { d in row(d, tint: tint) }
            }
            .padding(.top, 2)
        }
    }

    private func row(_ d: Decision, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: d.status == .resolved ? "checkmark.circle.fill" : "circle")
                .scaledFont(12).foregroundStyle(tint).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.text).scaledFont(13).foregroundStyle(NDS.textPrimary)
                    .multilineTextAlignment(.leading)
                if let r = d.rationale, !r.isEmpty {
                    Text(r).scaledFont(11).foregroundStyle(NDS.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                if d.origin == .meeting, let src = d.meetingTitle {
                    Text("from \(src)").font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            statusMenu(d)
        }
        .padding(.vertical, 2)
    }

    private func statusMenu(_ d: Decision) -> some View {
        Menu {
            ForEach(DecisionStatus.allCases, id: \.self) { s in
                Button {
                    decisions.setStatus(d.id, s)
                } label: {
                    if d.status == s {
                        Label(s.label, systemImage: "checkmark")
                    } else {
                        Text(s.label)
                    }
                }
            }
            if d.origin == .manual {
                Divider()
                Button(role: .destructive) { decisions.delete(d.id) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Text(d.status.label)
                .font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(NDS.surface2, in: Capsule())
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let why = draftWhy.trimmingCharacters(in: .whitespaces)
        decisions.addManual(text: text, rationale: why.isEmpty ? nil : why, projectID: projectID)
        draft = ""; draftWhy = ""; addingWhy = false
    }
}

/// Reference materials pinned to a feature/project: scoping docs, design files,
/// competitor analyses — as web links or local files. The thing a PM "grabs and
/// pulls from" while building. Inserted under the decisions section.
struct ProjectReferenceMaterialsSection: View {
    @ObservedObject var store: ActionItemStore
    let projectID: String

    @State private var expanded = true
    @State private var draftTitle = ""
    @State private var draftURL = ""
    @State private var draftKind: DocumentReference.DocKind = .scopingDoc

    private var docs: [DocumentReference] { store.documents(forProject: projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded {
                if !docs.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(docs) { chip($0) }
                    }
                }
                addRow
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 12)
    }

    private var header: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperclip").scaledFont(12).foregroundStyle(NDS.brand)
                Text("Reference materials").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                if !docs.isEmpty { Text("\(docs.count)").scaledFont(11).foregroundStyle(NDS.textTertiary) }
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .scaledFont(10).foregroundStyle(NDS.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ d: DocumentReference) -> some View {
        Button { open(d) } label: {
            HStack(spacing: 6) {
                Image(systemName: d.kind.systemImage).scaledFont(11).foregroundStyle(NDS.brand)
                Text(d.title).scaledFont(12).foregroundStyle(NDS.textPrimary).lineLimit(1)
                Text(d.kind.label).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(NDS.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(d.locationLabel)
        .contextMenu {
            Button { open(d) } label: { Label("Open", systemImage: "arrow.up.right.square") }
            Button(role: .destructive) {
                store.removeDocument(d.id, fromProject: projectID)
            } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(DocumentReference.DocKind.allCases) { k in
                    Button { draftKind = k } label: {
                        if draftKind == k { Label(k.label, systemImage: "checkmark") } else { Text(k.label) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: draftKind.systemImage).scaledFont(11)
                    Text(draftKind.label).scaledFont(12)
                    Image(systemName: "chevron.down").scaledFont(8)
                }
                .foregroundStyle(NDS.textSecondary)
            }
            .menuStyle(.borderlessButton).fixedSize()

            TextField("Title (optional)", text: $draftTitle)
                .textFieldStyle(.plain).scaledFont(12).frame(maxWidth: 160)
            TextField("Paste a link…", text: $draftURL)
                .textFieldStyle(.plain).scaledFont(12)
                .onSubmit(addLink)
            Button("Add link", action: addLink)
                .buttonStyle(.plain).scaledFont(12).foregroundStyle(NDS.brand)
                .disabled(draftURL.trimmingCharacters(in: .whitespaces).isEmpty)
            Divider().frame(height: 16)
            Button(action: addFile) {
                Label("File…", systemImage: "folder").scaledFont(12).foregroundStyle(NDS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(NDS.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func addLink() {
        var url = draftURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        if !url.contains("://") { url = "https://" + url }
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        store.addDocument(.init(title: title.isEmpty ? url : title, kind: draftKind, payload: .url(url)),
                          toProject: projectID)
        draftTitle = ""; draftURL = ""
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        for url in panel.urls {
            guard let bm = FileBookmark.make(for: url) else { continue }
            let name = title.isEmpty || panel.urls.count > 1 ? url.lastPathComponent : title
            store.addDocument(.init(title: name, kind: draftKind,
                                    payload: .localFile(bookmark: bm, displayPath: url.path)),
                              toProject: projectID)
        }
        draftTitle = ""
    }

    private func open(_ d: DocumentReference) {
        switch d.payload {
        case .url(let s):
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .localFile(let bookmark, _):
            FileBookmark.open(bookmark)
        }
    }
}
