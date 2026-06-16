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
    // Bloom is chunkier/rounder — radii bumped to match `designs/bloom.css`
    // (--r-ctl 14, --r-card 20). Chips/badges/nav/tabs go fully rounded
    // (Capsule) at their call sites.
    // Radius ramp (D2-3): four tokens. Everything maps to one of these; chips/
    // badges/nav/tabs go fully rounded (Capsule) at the call site.
    static let radiusSmall: CGFloat = 8  // chips, inline controls, small pills
    static let rowRadius: CGFloat = 12   // list rows
    static let radius: CGFloat = 14      // controls/fields (--r-ctl)
    static let cardRadius: CGFloat = 20  // cards, sheets, panels (--r-card)

    /// Permanent top breathing room reserved for every tab/page, applied once at
    /// the tab host (`MainWindow.tabContent`) so content never sits flush against
    /// — and gets clipped by — the translucent window toolbar on macOS Tahoe.
    static let tabTopInset: CGFloat = 14

    // MARK: Button dimension tokens
    // Minimum 44pt invisible tap target via .minTap() extension below
    static let buttonPrimaryH:   CGFloat = 34
    static let buttonSecondaryH: CGFloat = 30
    static let buttonTertiaryH:  CGFloat = 28
    static let buttonIconSide:   CGFloat = 30
    static let buttonHPadLg:     CGFloat = 16
    static let buttonHPadMd:     CGFloat = 14
    static let buttonHPadSm:     CGFloat = 12

    // MARK: Color — "Bloom" (dark-mode-first). Values from designs/bloom.css.
    //
    // The heart of Bloom is a plum-ink base with coral (primary CTA), lilac
    // (brand/nav), mint/sky/gold accents. `brand` is now LILAC — it drives nav
    // selection, focus rings, and `.tint`. Primary CTAs use the CORAL gradient
    // (see `accent`/`accentGradient` + MSPrimaryButtonStyle), NOT `brand`.
    static let brand = lilac
    static let brandHover = Color(hex: "#cbb8ff") ?? lilac

    // --- Accents (signature Bloom hues; identical across appearances) ---
    /// Coral — primary CTAs, active tab, brand mark, ambient glow.
    static let accent      = Color(hex: "#ff9173") ?? .orange
    static let accentEnd   = Color(hex: "#f06a4c") ?? .orange   // coral gradient end (--accent-2)
    static let accentSoft  = (Color(hex: "#ff9173") ?? .orange).opacity(0.16)
    /// Lilac — brand / nav accent (active nav icon, selection, "New page").
    static let lilac       = Color(hex: "#b79cff") ?? .purple
    static let lilacSoft   = (Color(hex: "#b79cff") ?? .purple).opacity(0.16)
    static let mint        = Color(hex: "#74e0bc") ?? .green   // success / done
    static let sky         = Color(hex: "#8ab4ff") ?? .blue    // info / in progress
    static let gold        = Color(hex: "#ffce6b") ?? .yellow  // warning / due today / voice
    static let danger      = Color(hex: "#ff7a8a") ?? .red     // overdue / high / destructive
    /// Live-capture red (D2-7). Distinct from `danger`: this means "recording in
    /// progress", not "error/overdue". Use everywhere a recording dot/border/Stop
    /// affordance appears instead of raw `.red`.
    static let recording   = Color(hex: "#ff5a5f") ?? .red

    /// Coral primary-CTA gradient (135° #ff9173 → #f06a4c).
    static let accentGradient = LinearGradient(
        colors: [accent, accentEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Near-black warm label that sits on the coral fill (`#2a1208`).
    static let onAccent = Color(hex: "#2a1208") ?? .black
    /// Brand-mark gradient (coral → lilac).
    static let brandMarkGradient = LinearGradient(
        colors: [accent, lilac],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Plum-ink surfaces & text. Dark is the design target; light values are a
    /// tasteful fallback so the app stays legible if the user picks Light.
    static let bg          = dyn(dark: (21, 18, 26, 1),       light: (248, 246, 250, 1))   // #15121a
    static let sidebarBg   = dyn(dark: (16, 13, 21, 1),       light: (240, 237, 244, 1))   // #100d15
    static let rightRailBg = dyn(dark: (30, 25, 37, 1),       light: (244, 241, 247, 1))   // #1e1925
    // Hover/selected rows pick up a lilac-soft wash (Bloom "rows get lilac-soft bg").
    static let rowHover    = dyn(dark: (183, 156, 255, 0.12), light: (120, 90, 220, 0.08))
    static let rowSelected = lilac.opacity(0.16)
    static let divider     = dyn(dark: (245, 238, 250, 0.09), light: (40, 25, 60, 0.10))   // --line
    static let hairline    = dyn(dark: (245, 238, 250, 0.16), light: (40, 25, 60, 0.16))   // --line-2
    static let textPrimary   = dyn(dark: (243, 238, 246, 1),   light: (28, 22, 38, 1))     // #f3eef6
    static let textSecondary = dyn(dark: (243, 238, 246, 0.68), light: (28, 22, 38, 0.66)) // --txt-2
    // D5-2: raised from 0.44/0.50 — the old token sat at ~3.9:1 on the dark
    // surface, an AA failure at its 11pt (NDS.tiny) usage. These alphas clear
    // 4.5:1 normal-text AA while staying below textSecondary so the hierarchy holds.
    static let textTertiary  = dyn(dark: (243, 238, 246, 0.54), light: (28, 22, 38, 0.62)) // --txt-3
    // Card / field fill — the opaque `--surface` plum (#1e1925).
    static let fieldBg       = dyn(dark: (30, 25, 37, 1),      light: (255, 255, 255, 1))
    // Elevated / segment-thumb / gray-chip fill — `--surface-2` (#271f31).
    static let segmentActiveBg = dyn(dark: (39, 31, 49, 1),    light: (236, 232, 242, 1))
    static let surface2        = dyn(dark: (39, 31, 49, 1),    light: (236, 232, 242, 1))
    /// Subtle lane fill for kanban columns / grouped bands (DV-19).
    static let columnBg = dyn(dark: (245, 238, 250, 0.035),   light: (40, 25, 60, 0.03))

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

    // MARK: Type — Bloom fonts
    //
    // Display (page titles, brand wordmark, big numbers) → Bricolage Grotesque.
    // Everything else → Plus Jakarta Sans. Both are bundled under
    // Resources/Fonts and auto-registered via ATSApplicationFontsPath in
    // Info.plist. The `relativeTo:` form keeps Dynamic-Type scaling (D5-2); if a
    // font fails to load (e.g. in unit tests) SwiftUI falls back to the system
    // font, so nothing crashes.
    static let displayFamily = "Bricolage Grotesque"
    static let bodyFamily    = "Plus Jakarta Sans"

    /// Which Bloom family a token/text uses.
    enum FontKind { case body, display }

    /// The exact bundled PostScript instance for a (family, weight). We select
    /// the discrete static weight directly instead of applying SwiftUI's
    /// `.weight()` to a single family name — that produces fractional weight
    /// traits CoreText can't map (noisy "Unable to update Font Descriptor's
    /// weight" logs) and risks picking the wrong member. Bricolage only ships
    /// SemiBold/Bold/ExtraBold, so lighter display weights round up to SemiBold.
    static func psName(_ kind: FontKind, _ weight: Font.Weight) -> String {
        switch kind {
        case .display:
            switch weight {
            case .bold:            return "BricolageGrotesque-Bold"
            case .heavy, .black:   return "BricolageGrotesque-ExtraBold"
            default:               return "BricolageGrotesque-SemiBold"
            }
        case .body:
            switch weight {
            case .medium:          return "PlusJakartaSans-Medium"
            case .semibold:        return "PlusJakartaSans-SemiBold"
            case .bold:            return "PlusJakartaSans-Bold"
            case .heavy, .black:   return "PlusJakartaSans-ExtraBold"
            default:               return "PlusJakartaSans-Regular"
            }
        }
    }

    /// Scaled custom font. `display` → Bricolage Grotesque, `body` → Plus
    /// Jakarta Sans. Dynamic-Type-aware via `relativeTo`.
    static func font(_ kind: FontKind = .body, _ size: CGFloat,
                     weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(psName(kind, weight), size: size, relativeTo: style)
    }

    static let title = font(.display, 30, weight: .heavy, relativeTo: .largeTitle)   // h1 30/800
    static let pageTitle = font(.display, 25, weight: .heavy, relativeTo: .title)    // detail 25/800
    static let sectionLabel = font(.body, 11, weight: .bold, relativeTo: .caption)   // eyebrow 11/700
    static let body = font(.body, 14, relativeTo: .callout)
    static let small = font(.body, 12, weight: .medium, relativeTo: .footnote)
    static let tiny = font(.body, 11, weight: .medium, relativeTo: .caption2)

    // MARK: Notion-style named colors for select/status chips.
    /// Notion's muted palette — chips use a low-alpha fill with a saturated text.
    /// Retuned to the Bloom accent family so tag chips read as part of the
    /// dark, saturated palette (lilac/mint/sky/gold/coral/danger) instead of the
    /// old muted Notion hues.
    static let palette: [(name: String, color: Color)] = [
        ("gray",   Color(hex: "#9b93a8")!),
        ("brown",  Color(hex: "#8ab4ff")!),   // → sky (medium / in-progress / open)
        ("orange", Color(hex: "#ff9173")!),   // → coral (engineering / urgent / high)
        ("yellow", Color(hex: "#ffce6b")!),   // → gold
        ("green",  Color(hex: "#74e0bc")!),   // → mint (product / done / low)
        ("blue",   Color(hex: "#8ab4ff")!),   // → sky
        ("purple", Color(hex: "#b79cff")!),   // → lilac (design)
        ("pink",   Color(hex: "#e58fd0")!),
        ("red",    Color(hex: "#ff7a8a")!)    // → danger
    ]

    /// The five Bloom avatar gradient pairs (coral / mint / lilac / sky / gold),
    /// from `designs/bloom.css`. Monograms sit on these in dark warm text.
    static let avatarGradients: [(Color, Color)] = [
        (Color(hex: "#ff9173")!, Color(hex: "#f06a4c")!),  // coral
        (Color(hex: "#74e0bc")!, Color(hex: "#46c79f")!),  // mint
        (Color(hex: "#b79cff")!, Color(hex: "#9a7af0")!),  // lilac
        (Color(hex: "#8ab4ff")!, Color(hex: "#6b96ec")!),  // sky
        (Color(hex: "#ffce6b")!, Color(hex: "#f0b43f")!)   // gold
    ]
    /// Dark warm monogram color that sits on every avatar gradient (#241636).
    static let avatarText = Color(hex: "#241636") ?? .black

    /// Deterministic avatar gradient for a name (stable across launches).
    static func avatarGradient(_ name: String) -> LinearGradient {
        var hash = 5381
        for b in name.lowercased().utf8 { hash = ((hash << 5) &+ hash) &+ Int(b) }
        let pair = avatarGradients[abs(hash) % avatarGradients.count]
        return LinearGradient(colors: [pair.0, pair.1],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

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
    /// Bloom personality: a touch livelier/bouncier than the old 0.34/0.86.
    static let springStandard: Animation = .spring(response: 0.32, dampingFraction: 0.80)

    // MARK: Elevation (D2-2)
    //
    // Dark-first elevation: lift comes mostly from a *lighter surface*, with a
    // restrained shadow for the floating tiers — not the 12 ad-hoc `.shadow`
    // recipes (radius 1…20, random opacities) the app accumulated. Apply with
    // `.ndsElevation(_:)`; use the surface color via `Elevation.surface`.
    enum Elevation {
        case flat       // inline with the page — no shadow
        case raised     // cards, rows pulled off the page
        case floating   // popovers, menus, toasts
        case modal      // sheets, the command palette

        /// The surface fill for this tier (lighter as it rises, dark-first).
        var surface: Color {
            switch self {
            case .flat:     return NDS.fieldBg
            case .raised:   return NDS.surface2
            case .floating: return NDS.surface2
            case .modal:    return NDS.rightRailBg
            }
        }

        /// A restrained shadow. Dark UIs read depth from contrast, so these stay
        /// soft; the heavy lifting is the surface color above.
        var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
            switch self {
            case .flat:     return (.clear, 0, 0)
            case .raised:   return (.black.opacity(0.18), 6, 2)
            case .floating: return (.black.opacity(0.28), 14, 6)
            case .modal:    return (.black.opacity(0.40), 28, 14)
            }
        }
    }

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
        case .low:    return textTertiary   // none/hidden — bar suppressed at call site
        case .medium: return gold           // --warn
        case .high:   return danger         // --danger
        case .urgent: return danger         // --danger (glyph distinguishes from high)
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
        case .open:       return sky    // --info
        case .inProgress: return gold   // --warn
        case .completed:  return mint   // --ok
        }
    }
    /// Overdue → danger, due today → gold, otherwise neutral. Completed never
    /// reads as overdue. Centralizes the duplicated `dueColor` helpers.
    static func due(_ date: Date?, status: ActionItem.Status) -> Color {
        guard let date, status != .completed else { return textSecondary }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        if date < startOfToday { return danger }                  // overdue → danger
        if Calendar.current.isDateInToday(date) { return gold }   // today  → gold
        return textSecondary
    }

    // MARK: Icon weight (DV-7) — consistent SF Symbol weight per render size.
    static func iconWeight(forSize size: CGFloat) -> Font.Weight {
        size >= 16 ? .semibold : .medium
    }

    // MARK: Contrast (AV-3) — pure WCAG helpers, used by the contrast test and
    // available for audits. Inputs are sRGB components in 0–255.
    private static func linearize(_ c: Double) -> Double {
        let s = c / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    static func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
        0.2126 * linearize(rgb.0) + 0.7152 * linearize(rgb.1) + 0.0722 * linearize(rgb.2)
    }
    /// WCAG contrast ratio (1…21) between two opaque sRGB colors.
    static func contrastRatio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    /// Composite a translucent foreground (r,g,b,a) over an opaque background.
    static func composite(_ fg: (Double, Double, Double, Double),
                          over bg: (Double, Double, Double)) -> (Double, Double, Double) {
        let a = fg.3
        return (fg.0 * a + bg.0 * (1 - a),
                fg.1 * a + bg.1 * (1 - a),
                fg.2 * a + bg.2 * (1 - a))
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

    /// A fixed-size Bloom font that STILL scales with Dynamic Type / the system
    /// text-size setting (D5-2). Keeps the design's exact point size at the
    /// default setting but grows/shrinks with the user's preference — use this
    /// instead of a bare `.font(.system(size:))` so low-vision users aren't
    /// locked out. `style` anchors the scaling curve; `kind` picks the Bloom
    /// family (`.body` = Plus Jakarta Sans, `.display` = Bricolage Grotesque).
    func scaledFont(_ size: CGFloat,
                    weight: Font.Weight = .regular,
                    relativeTo style: Font.TextStyle = .body,
                    kind: NDS.FontKind = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, relativeTo: style, kind: kind))
    }
}

/// Backing modifier for `View.scaledFont` — `@ScaledMetric` does the scaling,
/// then a Bloom custom font is applied at the scaled size.
@available(macOS 14.0, *)
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let kind: NDS.FontKind
    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle, kind: NDS.FontKind) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.kind = kind
    }
    func body(content: Content) -> some View {
        content.font(.custom(NDS.psName(kind, weight), fixedSize: size))
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
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).scaledFont(10, weight: .bold) }
            Text(text).scaledFont(11.5, weight: .bold, relativeTo: .caption)
        }
        .padding(.horizontal, 11).padding(.vertical, 4)
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
                Image(systemName: icon).scaledFont(12)
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
                .scaledFont(13)
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

/// Solid primary button (coral gradient + glow) — legacy alias kept for older
/// call sites; matches `MSPrimaryButtonStyle`.
struct UntitledPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(13, weight: .bold)
            .foregroundStyle(NDS.onAccent)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(NDS.accentGradient,
                        in: RoundedRectangle(cornerRadius: NDS.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .shadow(color: NDS.accent.opacity(0.32), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Subtle surface button with a hairline border (secondary action).
struct UntitledSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(13, weight: .bold)
            .foregroundStyle(NDS.textPrimary)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(configuration.isPressed ? NDS.surface2 : NDS.fieldBg,
                        in: RoundedRectangle(cornerRadius: NDS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NDS.radius, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

// MARK: - Full button system (replaces ad-hoc controlSize + bordered patterns)

/// Primary filled action button — Bloom coral gradient + coral drop-glow,
/// near-black warm label, radius 14. Press: gentle spring scale + dim.
struct MSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(13, weight: .bold)
            .foregroundStyle(NDS.onAccent)
            .padding(.horizontal, NDS.buttonHPadLg)
            .frame(height: NDS.buttonPrimaryH)
            .background(NDS.accentGradient,
                        in: RoundedRectangle(cornerRadius: NDS.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .shadow(color: NDS.accent.opacity(0.32), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary outlined button — `--surface` fill, `--line-2` border, radius 14.
struct MSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(13, weight: .bold)
            .foregroundStyle(NDS.textPrimary)
            .padding(.horizontal, NDS.buttonHPadMd)
            .frame(height: NDS.buttonSecondaryH)
            .background(configuration.isPressed ? NDS.surface2 : NDS.fieldBg,
                        in: RoundedRectangle(cornerRadius: NDS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NDS.radius, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Danger/destructive button — `--danger` fill, dark warm text, radius 14.
struct MSDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(13, weight: .bold)
            .foregroundStyle(Color(hex: "#2a0e12") ?? .black)
            .padding(.horizontal, NDS.buttonHPadLg)
            .frame(height: NDS.buttonPrimaryH)
            .background(NDS.danger.opacity(configuration.isPressed ? 0.82 : 1),
                        in: RoundedRectangle(cornerRadius: NDS.radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Ghost/tertiary button (no border, muted label, 28pt tall).
struct MSTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(12, weight: .medium)
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
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).scaledFont(13, weight: .semibold)
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

    /// Apply one elevation tier's shadow (D2-2). Pair with a surface fill of
    /// `tier.surface` for the dark-first "lighter as it rises" treatment.
    func ndsElevation(_ tier: NDS.Elevation) -> some View {
        let s = tier.shadow
        return self.shadow(color: s.color, radius: s.radius, y: s.y)
    }

    /// Standard hover affordance (D3-10): a subtle row-wash background on hover,
    /// reduce-motion-proof. Replaces the app's many bespoke `@State isHovered`
    /// implementations with one consistent treatment.
    func ndsHover(cornerRadius: CGFloat = NDS.rowRadius) -> some View {
        modifier(NDSHoverModifier(cornerRadius: cornerRadius))
    }
}

@available(macOS 14.0, *)
private struct NDSHoverModifier: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(hovering ? NDS.rowHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(NDS.motion(.easeOut(duration: 0.12), reduce: reduceMotion), value: hovering)
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
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(tint)
                Text(title)
                    .scaledFont(13, weight: .medium)
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

// AppearanceToggle was removed (C3-4): the app follows the system appearance
// like a native Mac app rather than carrying a web-style in-rail Light/Dark
// switch. The light palette remains as the system-light fallback.
