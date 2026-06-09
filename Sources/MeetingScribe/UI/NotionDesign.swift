import SwiftUI
import AppKit

/// Phase 6 — a small Notion-flavored design system. Centralizes color,
/// spacing, and typography so the Workspace surfaces share one polished look
/// instead of ad-hoc styling. Tuned for dark mode (where the app lives) but
/// uses adaptive system colors so light mode stays legible.
enum NDS {
    // MARK: Layout
    static let pagePadding: CGFloat = 56
    /// Max width for page-column surfaces (Tasks list/board/page chrome). Was a
    /// cramped 720 reading-measure that wasted horizontal space on lists and
    /// boards; relaxed so content breathes (and so enlarged Dynamic Type can
    /// reflow — prereq for D5-2). True prose panes keep their own narrower
    /// measure. (LAY-1)
    static let contentMaxWidth: CGFloat = 1100
    /// Top inset that pushes a split-view pane's content clear of the window's
    /// translucent title-bar / toolbar (macOS Tahoe). Shared by the People list
    /// and detail panes so they line up instead of repeating a magic 60. (req #1)
    static let splitPaneTopInset: CGFloat = 60
    static let radius: CGFloat = 8       // increased from 6
    static let rowRadius: CGFloat = 8
    static let cardRadius: CGFloat = 12  // card-level rounding (was hardcoded 14)

    // MARK: Button dimension tokens
    // Minimum 44pt invisible tap target via .minTap() extension below
    static let buttonPrimaryH:   CGFloat = 34
    static let buttonSecondaryH: CGFloat = 30
    static let buttonTertiaryH:  CGFloat = 28
    static let buttonIconSide:   CGFloat = 30
    static let buttonHPadLg:     CGFloat = 16
    static let buttonHPadMd:     CGFloat = 14
    static let buttonHPadSm:     CGFloat = 12

    // MARK: Color
    /// Brand accent — kept as the familiar purple.
    static let brand = Color(hex: "#7F56D9") ?? .purple
    static let brandHover = Color(hex: "#9E77ED") ?? .purple

    /// Warm neutral palette — replaces the cold blue-navy.
    /// Dark: warm near-black (#1C1B19). Light: warm off-white (#F8F7F5).
    /// All interactive surfaces use warm-tinted grays for a more premium,
    /// less eye-straining feel compared to the previous blue-navy system.
    static let bg          = dyn(dark: (28, 27, 25, 1),     light: (248, 247, 245, 1))   // #1c1b19 / #f8f7f5
    static let sidebarBg   = dyn(dark: (22, 21, 19, 1),     light: (240, 238, 233, 1))   // #161513 / #f0eee9
    static let rightRailBg = dyn(dark: (25, 24, 22, 1),     light: (244, 242, 238, 1))   // #191816 / #f4f2ee
    static let rowHover    = dyn(dark: (255, 245, 225, 0.06), light: (100, 80, 40, 0.06))
    static let rowSelected = brand.opacity(0.13)
    static let divider     = dyn(dark: (255, 245, 225, 0.09), light: (100, 80, 40, 0.10))
    static let hairline    = dyn(dark: (255, 245, 225, 0.13), light: (100, 80, 40, 0.14))
    static let textPrimary   = dyn(dark: (242, 239, 230, 1),  light: (26, 25, 23, 1))    // #f2efe6 / #1a1917
    static let textSecondary = dyn(dark: (210, 204, 190, 0.72), light: (26, 25, 23, 0.58))
    static let textTertiary  = dyn(dark: (210, 204, 190, 0.42), light: (26, 25, 23, 0.38))
    static let fieldBg       = dyn(dark: (255, 245, 225, 0.055), light: (100, 80, 40, 0.045))
    static let segmentActiveBg = dyn(dark: (255, 245, 225, 0.13), light: (255, 255, 255, 1))

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
    //
    // Tokens are mapped to semantic text styles so they scale with Dynamic Type
    // / the system text-size setting (D5-2). Styles were chosen to keep the
    // default-size appearance close to the previous fixed points (within ~2pt):
    //   largeTitle≈34, title≈28, body≈17→callout 16, footnote≈13, caption≈12,
    //   caption2≈11. `.weight()` preserves scaling.
    static let title = Font.system(.largeTitle).weight(.heavy)        // was 32
    static let pageTitle = Font.system(.title).weight(.bold)          // was 26
    static let sectionLabel = Font.system(.caption).weight(.semibold) // was 12
    static let body = Font.system(.callout)                           // was 14
    static let small = Font.system(.footnote)                         // was 12
    static let tiny = Font.system(.caption2)                          // was 11

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

    /// Returns `animation` unless Reduce Motion is on, in which case `nil`
    /// (no animation). Read `@Environment(\.accessibilityReduceMotion)` at the
    /// call site and pass it as `reduce`. Accessibility: D5-1.
    static func motion(_ animation: Animation?, reduce: Bool) -> Animation? {
        reduce ? nil : animation
    }

    // MARK: Spacing scale (DV-1)
    // Use these instead of ad-hoc `.padding(<literal>)` so the app has one
    // vertical rhythm. xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32.
    static let spaceXS:  CGFloat = 4
    static let spaceSM:  CGFloat = 8
    static let spaceMD:  CGFloat = 12
    static let spaceLG:  CGFloat = 16
    static let spaceXL:  CGFloat = 24
    static let spaceXXL: CGFloat = 32

    // MARK: Motion constants (DV-9 / MX-1)
    // Durations + a canonical spring. Always wrap call-site animations in
    // `motion(_:reduce:)` so Reduce Motion still disables them.
    static let motionFast:     Double = 0.15
    static let motionStandard: Double = 0.22
    static let motionSlow:     Double = 0.35
    /// Canonical spring for view/page transitions and hover affordances.
    static let springStandard: Animation = .spring(response: 0.34, dampingFraction: 0.86)

    // MARK: Semantic status / priority / due colors (DV-5 / VD-5 / DV-8)
    //
    // One source of truth, drawn from the muted Notion `palette` so they sit in
    // the warm theme instead of raw system `.red/.orange/.blue`. These replace
    // the duplicate local `priorityColor`/`statusColor`/`dueColor` switches that
    // had drifted across 7 files. Always pair the color with a glyph (status has
    // `systemImage`; priority has `priorityGlyph`) so meaning never rests on
    // color alone — colorblind-safe.
    static func priority(_ p: ActionItem.Priority) -> Color {
        switch p {
        case .low:    return palette[0].color   // gray
        case .medium: return palette[5].color   // blue
        case .high:   return palette[2].color   // orange
        case .urgent: return palette[8].color   // red
        }
    }
    /// Non-color redundancy for priority, shown alongside the color.
    static func priorityGlyph(_ p: ActionItem.Priority) -> String {
        switch p {
        case .low:    return "minus"
        case .medium: return "equal"
        case .high:   return "chevron.up"
        case .urgent: return "exclamationmark"
        }
    }
    static func status(_ s: ActionItem.Status) -> Color {
        switch s {
        case .open:       return palette[5].color  // blue
        case .inProgress: return palette[2].color  // orange
        case .completed:  return palette[4].color  // green
        }
    }
    /// Overdue → red, due today → amber, otherwise neutral. Completed never reads
    /// as overdue. Centralizes the duplicated `dueColor` helpers.
    static func due(_ date: Date?, status: ActionItem.Status) -> Color {
        guard let date, status != .completed else { return textSecondary }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        if date < startOfToday { return palette[8].color }                  // overdue → red
        if Calendar.current.isDateInToday(date) { return palette[2].color } // today  → orange
        return textSecondary
    }

    // MARK: Icon weight (DV-7) — consistent SF Symbol weight per render size.
    static func iconWeight(forSize size: CGFloat) -> Font.Weight {
        size >= 16 ? .semibold : .medium
    }
}

@available(macOS 14.0, *)
extension View {
    /// Applies a repeating SF Symbol pulse only when motion is allowed.
    /// With Reduce Motion on, the symbol renders statically. Accessibility: D5-1.
    @ViewBuilder
    func pulsingSymbol(active: Bool) -> some View {
        if active {
            self.symbolEffect(.pulse, options: .repeating)
        } else {
            self
        }
    }

    /// A fixed-size system font that STILL scales with Dynamic Type / the system
    /// text-size setting (D5-2). Keeps the design's exact point size at the
    /// default setting but grows/shrinks with the user's preference — use this
    /// instead of a bare `.font(.system(size:))` so low-vision users aren't
    /// locked out. `style` anchors the scaling curve.
    func scaledFont(_ size: CGFloat,
                    weight: Font.Weight = .regular,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, relativeTo: style))
    }
}

/// Backing modifier for `View.scaledFont` — `@ScaledMetric` does the scaling.
@available(macOS 14.0, *)
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
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
            Text(text).scaledFont(11.5, weight: .medium, relativeTo: .caption)
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
                .frame(width: NDS.buttonIconSide, height: NDS.buttonIconSide)
                .background(hovering ? NDS.rowHover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(hovering ? NDS.hairline : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        // Icon-only button → give VoiceOver the same text as the tooltip
        // (fall back to a humanized symbol name if no help was supplied).
        .accessibilityLabel(help.isEmpty
            ? systemName.replacingOccurrences(of: ".", with: " ")
            : help)
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

// MARK: - Full button system (replaces ad-hoc controlSize + bordered patterns)

/// Primary filled action button (36pt tall, brand fill).
struct MSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, NDS.buttonHPadLg)
            .frame(height: NDS.buttonPrimaryH)
            .background(NDS.brand.opacity(configuration.isPressed ? 0.80 : 1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Secondary outlined button (32pt tall, border + field bg).
struct MSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(NDS.textPrimary)
            .padding(.horizontal, NDS.buttonHPadMd)
            .frame(height: NDS.buttonSecondaryH)
            .background(configuration.isPressed ? NDS.rowHover : NDS.fieldBg,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Danger/destructive button (36pt tall, red fill).
struct MSDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, NDS.buttonHPadLg)
            .frame(height: NDS.buttonPrimaryH)
            .background(Color.red.opacity(configuration.isPressed ? 0.72 : 0.88),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Ghost/tertiary button (no border, accent label, 28pt tall).
struct MSTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(configuration.isPressed ? NDS.textPrimary : NDS.textSecondary)
            .padding(.horizontal, NDS.buttonHPadSm)
            .frame(height: NDS.buttonTertiaryH)
            .contentShape(Rectangle())
    }
}

/// Invisible tap-target expander: ensures a 44pt hit area without
/// changing the visual size. Apply to any icon-only button.
extension View {
    func minTap() -> some View {
        frame(minWidth: 44, minHeight: 44)
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
                Text(label).scaledFont(11.5, weight: active ? .semibold : .medium, relativeTo: .caption)
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
