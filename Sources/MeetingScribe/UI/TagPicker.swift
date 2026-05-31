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
    }

    private var tagListPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.headline).padding(.horizontal).padding(.top, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let assigned = Set(tagStore.tagIDs(for: meeting))
                    ForEach(tagStore.allTags) { t in
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
