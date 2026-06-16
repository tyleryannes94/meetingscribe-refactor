import SwiftUI

/// One tappable segment of a breadcrumb trail.
@available(macOS 14.0, *)
struct BreadcrumbItem {
    let label: String
    var systemImage: String? = nil
    var color: Color? = nil
    /// Where this segment navigates. nil = the current (non-tappable) page.
    var action: (() -> Void)? = nil
}

/// A clickable breadcrumb trail — `Context › Initiative › Project` — so the
/// task page and project pane stop being navigational dead-ends (3-6). Each
/// segment routes back up the hierarchy; the last segment (the current page)
/// is plain text.
@available(macOS 14.0, *)
struct BreadcrumbBar: View {
    let items: [BreadcrumbItem]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(items.indices, id: \.self) { idx in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .scaledFont(8, weight: .semibold)
                        .foregroundStyle(NDS.textTertiary)
                }
                segment(items[idx])
            }
        }
    }

    @ViewBuilder
    private func segment(_ item: BreadcrumbItem) -> some View {
        let content = HStack(spacing: 4) {
            if let icon = item.systemImage {
                Image(systemName: icon).scaledFont(10).foregroundStyle(item.color ?? NDS.textSecondary)
            }
            Text(item.label).font(NDS.small).lineLimit(1)
        }
        if let action = item.action {
            Button(action: action) { content.foregroundStyle(NDS.textSecondary) }
                .buttonStyle(.plain)
        } else {
            content.foregroundStyle(NDS.textPrimary)
        }
    }
}
