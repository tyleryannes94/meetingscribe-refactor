import SwiftUI

/// A horizontal row of tag chips + a "+" button that opens a popover with
/// checkboxes for every known tag plus an inline "Create new tag" field.
@available(macOS 14.0, *)
struct TagPicker: View {
    @EnvironmentObject var tagStore: TagStore
    let meeting: Meeting
    /// Set to true to also store this assignment against the meeting's
    /// recurring series (so future occurrences inherit the tag).
    let propagateToSeries: Bool

    @State private var showingPopover = false
    @State private var newTagName = ""
    /// The tag whose per-tag summary instructions are being edited (5-? / per-tag templates).
    @State private var editingTemplateTag: MeetingTag?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tagStore.tags(for: meeting)) { t in
                TagChip(tag: t, removable: true) {
                    tagStore.removeTag(t.id, from: meeting, propagateToSeries: propagateToSeries)
                }
            }
            Button {
                showingPopover = true
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add tag")
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                tagListPopover
                    .frame(width: 260)
            }
        }
        .sheet(item: $editingTemplateTag) { tag in
            TagSummaryTemplateEditor(tag: tag).environmentObject(tagStore)
        }
    }

    private var tagListPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.headline).padding(.horizontal).padding(.top, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let assigned = Set(tagStore.tagIDs(for: meeting))
                    ForEach(tagStore.allTags) { t in
                      HStack(spacing: 2) {
                        Button {
                            if assigned.contains(t.id) {
                                tagStore.removeTag(t.id, from: meeting,
                                                   propagateToSeries: propagateToSeries)
                            } else {
                                tagStore.addTag(t.id, to: meeting,
                                                propagateToSeries: propagateToSeries)
                            }
                        } label: {
                            HStack {
                                Image(systemName: assigned.contains(t.id) ? "checkmark.square.fill" : "square")
                                TagChip(tag: t, removable: false, onRemove: nil)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(assigned.contains(t.id)
                            ? "Remove tag \(t.name)"
                            : "Add tag \(t.name)")
                        .accessibilityValue(assigned.contains(t.id) ? "selected" : "not selected")
                        Button { editingTemplateTag = t } label: {
                            Image(systemName: "text.alignleft").font(.caption2)
                                .foregroundStyle(t.summaryTemplate == nil ? NDS.textTertiary : NDS.brand)
                        }
                        .buttonStyle(.plain)
                        .help("Custom summary instructions for this tag")
                      }
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
                    let t = tagStore.createTag(name: trimmed)
                    tagStore.addTag(t.id, to: meeting, propagateToSeries: propagateToSeries)
                    newTagName = ""
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 8)
        }
    }
}

/// Editor for a tag's per-meeting summary instructions (per-tag templates).
@available(macOS 14.0, *)
private struct TagSummaryTemplateEditor: View {
    @EnvironmentObject var tagStore: TagStore
    @Environment(\.dismiss) private var dismiss
    let tag: MeetingTag
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary instructions — \(tag.name)").font(.headline)
            Text("Extra guidance appended to the AI summary prompt for meetings with this tag. Leave blank for the default summary.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body).frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(NDS.divider))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    tagStore.setSummaryTemplate(id: tag.id, text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 420)
        .onAppear { text = tag.summaryTemplate ?? "" }
    }
}

@available(macOS 14.0, *)
struct TagChip: View {
    let tag: MeetingTag
    let removable: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if let s = tag.symbol {
                Image(systemName: s).font(.caption2)
            }
            Text(tag.name).font(.caption)
            if removable {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(backgroundColor.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(backgroundColor.opacity(0.5), lineWidth: 0.5))
        .foregroundStyle(backgroundColor)
    }

    private var backgroundColor: Color {
        guard let hex = tag.colorHex else { return NDS.brand }
        return Color(hex: hex) ?? NDS.brand
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
