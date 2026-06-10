import SwiftUI

/// Living design-system gallery (CV-2). Renders every token and shared component
/// in one place so the whole-app refresh can be eyeballed in light/dark without
/// hunting through real screens. Not wired into the shipping UI; open it from a
/// SwiftUI preview or a debug menu.
@available(macOS 14.0, *)
struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NDS.spaceXL) {
                group("Type scale") {
                    Text("title").font(NDS.title)
                    Text("pageTitle").font(NDS.pageTitle)
                    Text("SECTION LABEL").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    Text("body").font(NDS.body)
                    Text("small").font(NDS.small).foregroundStyle(NDS.textSecondary)
                    Text("tiny").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
                group("Notion palette") {
                    swatchRow(NDS.palette.map { ($0.name, $0.color) })
                }
                group("Priority (color + glyph)") {
                    HStack(spacing: NDS.spaceSM) {
                        ForEach(ActionItem.Priority.allCases) { MSPriorityBadge(priority: $0) }
                    }
                }
                group("Status (color + glyph)") {
                    HStack(spacing: NDS.spaceSM) {
                        ForEach(ActionItem.Status.allCases) { MSStatusBadge(status: $0) }
                    }
                }
                group("Due chips") {
                    HStack(spacing: NDS.spaceSM) {
                        DueChip(date: Date().addingTimeInterval(-86400 * 2))
                        DueChip(date: Date())
                        DueChip(date: Date().addingTimeInterval(86400 * 3))
                        DueChip(date: nil)
                    }
                }
                group("Avatars") {
                    HStack(spacing: NDS.spaceMD) {
                        MSAvatar(name: "Ada Lovelace", size: 28)
                        MSAvatar(name: "Grace Hopper", size: 28)
                        MSAvatarStack(names: ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Edsger Dijkstra"], size: 28)
                    }
                }
                group("Buttons") {
                    HStack(spacing: NDS.spaceSM) {
                        Button("Primary") {}.buttonStyle(MSPrimaryButtonStyle())
                        Button("Secondary") {}.buttonStyle(MSSecondaryButtonStyle())
                        Button("Danger") {}.buttonStyle(MSDangerButtonStyle())
                        Button("Tertiary") {}.buttonStyle(MSTertiaryButtonStyle())
                    }
                }
                group("Card + empty state") {
                    Text("A standard msCard surface.").msCard()
                }
            }
            .padding(NDS.spaceXXL)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NDS.bg)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NDS.spaceSM) {
            Text(title).font(NDS.sectionLabel).foregroundStyle(NDS.textTertiary)
            content()
        }
    }

    private func swatchRow(_ items: [(String, Color)]) -> some View {
        HStack(spacing: NDS.spaceSM) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: NDS.radius, style: .continuous)
                        .fill(color).frame(width: 36, height: 36)
                    Text(name).scaledFont(9).foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }
}
