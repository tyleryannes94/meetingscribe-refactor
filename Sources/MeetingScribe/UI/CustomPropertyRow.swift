import SwiftUI

/// Editable row for one user-defined property on a task (NP-1 UI). Inline-rename
/// the property, edit its typed value, or delete the column. Self-contained
/// (owns its draft state) so it can drop into the task page property block.
@available(macOS 14.0, *)
struct CustomPropertyRow: View {
    @ObservedObject var store: ActionItemStore
    let projectID: String
    let itemID: String
    let def: PropertyDefinition
    let value: PropertyValue?

    @State private var nameDraft = ""
    @State private var textDraft = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: def.type.systemImage)
                .font(.system(size: 12)).foregroundStyle(NDS.textTertiary).frame(width: 16)
            TextField("Property", text: $nameDraft)
                .textFieldStyle(.plain).font(NDS.small).foregroundStyle(NDS.textSecondary)
                .frame(width: 120, alignment: .leading)
                .onSubmit { store.renameProperty(def.id, inProject: projectID, name: nameDraft) }
            Spacer()
            valueEditor
            Menu {
                Button(role: .destructive) {
                    store.deleteProperty(def.id, fromProject: projectID)
                } label: { Label("Delete property", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(NDS.textTertiary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .onAppear { nameDraft = def.name; loadValue() }
        .onChange(of: def.id) { _, _ in nameDraft = def.name; loadValue() }
        .onChange(of: def.name) { _, n in nameDraft = n }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch def.type {
        case .text, .url, .select:
            TextField("Empty", text: $textDraft)
                .textFieldStyle(.plain).font(NDS.body).frame(width: 170)
                .multilineTextAlignment(.trailing)
                .onSubmit(commitText)
        case .number:
            TextField("0", text: $textDraft)
                .textFieldStyle(.plain).font(NDS.body).frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onSubmit(commitText)
        case .checkbox:
            Toggle("", isOn: Binding(
                get: { if case .checkbox(let b)? = value { return b } else { return false } },
                set: { store.setPropertyValue(itemID, propID: def.id, .checkbox($0)) }
            )).labelsHidden()
        case .date:
            DatePicker("", selection: Binding(
                get: { if case .date(let d)? = value { return d } else { return Date() } },
                set: { store.setPropertyValue(itemID, propID: def.id, .date($0)) }
            ), displayedComponents: .date).labelsHidden()
        }
    }

    private func loadValue() {
        switch def.type {
        case .text, .url, .select, .number: textDraft = value?.displayString() ?? ""
        case .checkbox, .date: break
        }
    }

    private func commitText() {
        let s = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let v: PropertyValue?
        switch def.type {
        case .number: v = s.isEmpty ? nil : Double(s).map(PropertyValue.number)
        case .url: v = s.isEmpty ? nil : .url(s)
        case .select: v = s.isEmpty ? nil : .select(s)
        default: v = s.isEmpty ? nil : .text(s)
        }
        store.setPropertyValue(itemID, propID: def.id, v)
    }
}
