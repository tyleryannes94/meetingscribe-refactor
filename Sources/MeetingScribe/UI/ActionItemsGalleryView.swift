import SwiftUI

/// Gallery view (VD-4): a responsive grid of task cards — the visually richest,
/// most Notion-defining view. Reuses the shared due/priority colors and avatar.
@available(macOS 14.0, *)
extension ActionItemsView {

    var galleryBody: some View {
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 12)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(projectFiltered) { item in
                    galleryCard(item)
                }
            }
            .padding(16)
        }
    }

    private func galleryCard(_ item: ActionItem) -> some View {
        let labels = store.labels(for: item)
        return VStack(alignment: .leading, spacing: 8) {
            if !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels.prefix(5)) { l in
                        Capsule().fill(Color(hex: l.colorHex) ?? .gray).frame(width: 22, height: 4)
                    }
                }
            }
            Text(item.title).font(.callout).lineLimit(3)
                .strikethrough(item.status == .completed)
            if item.subtaskProgress.total > 0 {
                ProgressView(value: Double(item.subtaskProgress.done),
                             total: Double(item.subtaskProgress.total))
                    .controlSize(.small).tint(NDS.brand)
            }
            HStack(spacing: 6) {
                Text(item.priority.label)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(priorityColor(item.priority).opacity(0.16), in: Capsule())
                    .foregroundStyle(priorityColor(item.priority))
                if item.dueDate != nil {
                    Text(dueShort(item)).font(.caption2).foregroundStyle(dueColor(item))
                }
                Spacer()
                if let owner = item.owner, !owner.isEmpty {
                    TaskOwnerAvatar(name: owner, size: 18)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NDS.divider, lineWidth: 0.5))
        .opacity(item.status == .completed ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { selectedTaskID = item.id }
    }
}
