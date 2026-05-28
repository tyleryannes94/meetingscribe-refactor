import SwiftUI
import AppKit

/// Phase 6 — a small Notion-flavored design system. Centralizes color,
/// spacing, and typography so the Workspace surfaces share one polished look
/// instead of ad-hoc styling. Tuned for dark mode (where the app lives) but
/// uses adaptive system colors so light mode stays legible.
enum NDS {
    // MARK: Layout
    static let pagePadding: CGFloat = 56
    static let contentMaxWidth: CGFloat = 760
    static let radius: CGFloat = 6
    static let rowRadius: CGFloat = 6

    // MARK: Color
    /// Untitled UI brand (primary). Used for the active nav item, primary
    /// buttons, and the app accent tint.
    static let brand = Color(hex: "#7F56D9") ?? .purple
    static let brandHover = Color(hex: "#9E77ED") ?? .purple

    /// Direction A — Refined Current. The dark palette is **blue-tinted** (deep
    /// navy/indigo) rather than neutral gray, so the whole window reads as a
    /// cool, dim workspace. Light mode stays clean and slightly cool to match.
    /// Each token is a single dynamic color that resolves against the view's
    /// effective appearance, so existing call sites pick up the tint for free.
    static let bg          = dyn(dark: (13, 19, 32, 1),    light: (251, 252, 254, 1))   // #0d1320 / #fbfcfe
    static let sidebarBg   = dyn(dark: (18, 26, 44, 1),    light: (241, 244, 250, 1))   // #121a2c / #f1f4fa
    static let rightRailBg = dyn(dark: (15, 22, 38, 1),    light: (246, 248, 252, 1))   // #0f1626 / #f6f8fc
    static let rowHover    = dyn(dark: (140, 175, 240, 0.08), light: (28, 52, 108, 0.05))
    static let rowSelected = brand.opacity(0.14)
    static let divider     = dyn(dark: (140, 175, 240, 0.09), light: (28, 52, 108, 0.07))
    static let hairline    = dyn(dark: (140, 175, 240, 0.13), light: (28, 52, 108, 0.10))
    static let textPrimary   = dyn(dark: (232, 237, 247, 1), light: (29, 29, 31, 1))    // #e8edf7 / #1d1d1f
    static let textSecondary = dyn(dark: (206, 218, 242, 0.62), light: (0, 0, 0, 0.55))
    static let textTertiary  = dyn(dark: (206, 218, 242, 0.40), light: (0, 0, 0, 0.38))
    static let fieldBg       = dyn(dark: (140, 175, 240, 0.06), light: (28, 52, 108, 0.04))
    /// Background of the active segment in the appearance toggle.
    static let segmentActiveBg = dyn(dark: (140, 175, 240, 0.14), light: (255, 255, 255, 1))

    /// Builds a single SwiftUI `Color` backed by a dynamic `NSColor` that
    /// resolves to the `dark` or `light` sRGB tuple (r, g, b in 0–255, a in
    /// 0–1) based on the rendering appearance.
    static func dyn(dark: (CGFloat, CGFloat, CGFloat, CGFloat),
                    light: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        })
    }

    // MARK: Type
    static let title = Font.system(size: 32, weight: .heavy)
    static let pageTitle = Font.system(size: 26, weight: .bold)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let body = Font.system(size: 14)
    static let small = Font.system(size: 12)
    static let tiny = Font.system(size: 11)

    // MARK: Notion-style named colors for select/status chips.
    /// Notion's muted palette — chips use a low-alpha fill with a saturated text.
    static let palette: [(name: String, color: Color)] = [
        ("gray",   Color(hex: "#9B9B9B")!),
        ("brown",  Color(hex: "#A27763")!),
        ("orange", Color(hex: "#D9730D")!),
        ("yellow", Color(hex: "#CB912F")!),
        ("green",  Color(hex: "#448361")!),
        ("blue",   Color(hex: "#337EA9")!),
        ("purple", Color(hex: "#9065B0")!),
        ("pink",   Color(hex: "#C14C8A")!),
        ("red",    Color(hex: "#D44C47")!)
    ]

    /// Deterministic color for an arbitrary tag/select/team string.
    static func selectColor(_ s: String) -> Color {
        let key = s.lowercased()
        // A few semantic overrides so common values look "right".
        switch key {
        case "engineering", "urgent", "high", "overdue": return palette[2].color  // orange/red-ish
        case "product", "completed", "done", "low":       return palette[4].color  // green
        case "design":                                     return palette[6].color // purple
        case "medium", "in progress", "open":              return palette[1].color // brown/blue
        default: break
        }
        var hash = 5381
        for b in key.utf8 { hash = ((hash << 5) &+ hash) &+ Int(b) }
        return palette[abs(hash) % palette.count].color
    }
}

// MARK: - Reusable components

/// A Notion "select" chip: low-alpha tinted pill with saturated text.
struct NotionChip: View {
    let text: String
    var color: Color
    var systemImage: String? = nil
    init(_ text: String, color: Color? = nil, systemImage: String? = nil) {
        self.text = text
        self.color = color ?? NDS.selectColor(text)
        self.systemImage = systemImage
    }
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11.5, weight: .medium))
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.16), in: Capsule())
        .lineLimit(1)
    }
}

/// A property row inside a full page: small gray icon+label on the left, value
/// on the right — Notion's page-properties layout.
struct NotionPropertyRow<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(NDS.body)
            }
            .foregroundStyle(NDS.textSecondary)
            .frame(width: 132, alignment: .leading)
            .padding(.top, 3)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

/// A small section/eyebrow label (uppercase, tracked).
struct NotionEyebrow: View {
    let text: String
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .font(NDS.sectionLabel).tracking(0.6)
                .foregroundStyle(NDS.textTertiary)
            if let count { Text("\(count)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary) }
        }
    }
}

/// A subtle, Notion-like icon button used in toolbars/headers.
struct NotionIconButton: View {
    let systemName: String
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(NDS.textSecondary)
                .frame(width: 28, height: 26)
                .background(hovering ? NDS.rowHover : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Untitled UI-style buttons

/// Solid brand button (primary action).
struct UntitledPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(NDS.brand.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: NDS.brand.opacity(0.25), radius: 6, y: 2)
            .contentShape(Rectangle())
    }
}

/// Subtle surface button with a hairline border (secondary action).
struct UntitledSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(NDS.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(NDS.fieldBg.opacity(configuration.isPressed ? 1.4 : 1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// A homepage quick-action card: icon tile + title, brand-tinted on hover.
@available(macOS 14.0, *)
struct QuickActionCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var tint: Color = NDS.brand
    let action: () -> Void
    var enabled: Bool = true
    @State private var hovering = false

    init(_ title: String, subtitle: String? = nil, systemImage: String,
         tint: Color = NDS.brand, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
        self.tint = tint; self.enabled = enabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NDS.textPrimary).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? NDS.rowHover : NDS.fieldBg,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(hovering ? tint.opacity(0.4) : NDS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    /// Wraps page content in Notion's centered, max-width, generously-padded
    /// column.
    func notionPageColumn() -> some View {
        self
            .frame(maxWidth: NDS.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, NDS.pagePadding)
            .padding(.vertical, 28)
    }
}

// MARK: - Direction A: quick-action pill

/// Compact tinted pill used in the Today quick-actions row. Replaces the old
/// 5-card grid that collapsed to a wall at narrow widths — these flow and wrap.
@available(macOS 14.0, *)
struct QuickPill: View {
    let title: String
    let systemImage: String
    var tint: Color = NDS.brand
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NDS.textPrimary)
            }
            .padding(.leading, 11).padding(.trailing, 14).padding(.vertical, 8)
            .background(tint.opacity(hovering ? 0.20 : 0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(hovering ? 0.45 : 0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Direction A: flow layout

/// A simple left-to-right wrapping layout, so the quick-action pills reflow
/// onto new lines instead of clipping when the content column is narrow.
@available(macOS 14.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Direction A: appearance toggle

/// Two-segment Light / Dark switch that sits in the bottom-left of the nav rail.
/// Writes to the caller's `dark` binding (backed by `@AppStorage`).
@available(macOS 14.0, *)
struct AppearanceToggle: View {
    @Binding var dark: Bool

    var body: some View {
        HStack(spacing: 2) {
            segment(isDark: false, label: "Light", icon: "sun.max.fill")
            segment(isDark: true,  label: "Dark",  icon: "moon.fill")
        }
        .padding(3)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(NDS.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }

    private func segment(isDark: Bool, label: String, icon: String) -> some View {
        let active = (dark == isDark)
        return Button {
            dark = isDark
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 11.5, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? NDS.textPrimary : NDS.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(active ? NDS.segmentActiveBg : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: active && !isDark ? .black.opacity(0.10) : .clear, radius: 1, y: 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
