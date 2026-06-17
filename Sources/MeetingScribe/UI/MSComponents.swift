import SwiftUI

/// Shared layout primitives (U1 — design-system enforcement). The app had tokens
/// (`NDS`) and button styles but no reusable *surfaces*, so every tab hand-rolled
/// its own `fieldBg + hairline` card, section header, and empty state — the drift
/// the 2026-05 session doc flagged. Migrate surfaces onto these so a card is
/// defined (and fixed) in exactly one place.

extension View {
    /// Standard card surface: `fieldBg` fill, hairline border, card-radius.
    /// `accentBorder` paints the border in a soft coral tint (Bloom hero cards
    /// like "Up Next" use this in place of the neutral hairline).
    func msCard(padding: CGFloat = 14, accentBorder: Bool = false) -> some View {
        self
            .padding(padding)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
                    .strokeBorder(accentBorder ? NDS.accent.opacity(0.45) : NDS.hairline, lineWidth: 1)
            )
    }

    /// Subtle ambient coral corner glow behind the main content area (Bloom
    /// signature). A blurred low-opacity coral radial light offset off the
    /// top-right corner; static, so it's safe under Reduce Motion. Clipped to
    /// the view's bounds so it never bleeds past the pane.
    func bloomAmbientGlow() -> some View {
        background(alignment: .topTrailing) {
            RadialGradient(
                colors: [NDS.accent.opacity(0.10), .clear],
                center: .center, startRadius: 0, endRadius: 210)
                .frame(minWidth: 420, maxWidth: 420, minHeight: 320)
                .offset(x: 80, y: -120)
                .blur(radius: 20)
                .allowsHitTesting(false)
        }
        .clipped()
    }
}

/// Bloom "tinted-header" card (new hero-card variant). A header strip carries a
/// soft coral→lilac gradient tint with a colored dot + eyebrow label; the body
/// sits below on the standard surface. Used for "Up Next" and other hero cards.
@available(macOS 14.0, *)
struct MSTintedHeaderCard<Content: View>: View {
    let label: String
    var dotColor: Color = NDS.accent
    var accentBorder: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(label.uppercased())
                    .scaledFont(11, weight: .bold, relativeTo: .caption).tracking(0.8)
                    .foregroundStyle(NDS.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [NDS.accent.opacity(0.22), NDS.lilac.opacity(0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NDS.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
                .strokeBorder(accentBorder ? NDS.accent.opacity(0.45) : NDS.hairline, lineWidth: 1)
        )
    }
}

/// Bloom pill tab bar (meeting detail, etc.). Active tab = coral gradient fill +
/// dark text; inactive = muted, surface-on-hover. Motion gated for Reduce Motion.
@available(macOS 14.0, *)
struct MSPillTabs<Tab: Hashable>: View {
    let tabs: [(tab: Tab, label: String)]
    @Binding var selection: Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Scroll horizontally so the tabs never cut off in a narrow column
        // (the person-profile work area can be ~260pt wide). P2: show the
        // indicator so users discover there are more tabs off-edge.
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 4) {
                ForEach(tabs, id: \.tab) { item in
                    let active = item.tab == selection
                    Button {
                        withAnimation(NDS.motion(NDS.springStandard, reduce: reduceMotion)) {
                            selection = item.tab
                        }
                    } label: {
                        Text(item.label)
                            .scaledFont(13, weight: active ? .bold : .semibold)
                            .foregroundStyle(active ? NDS.onAccent : NDS.textSecondary)
                            .padding(.horizontal, 15).padding(.vertical, 8)
                            .background {
                                if active {
                                    Capsule().fill(NDS.accentGradient)
                                } else {
                                    Capsule().fill(.clear)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A section label with an optional leading icon and an optional trailing
/// accessory (an Add button, a count, a menu…).
@available(macOS 14.0, *)
struct MSSectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, systemImage: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

@available(macOS 14.0, *)
extension MSSectionHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

// MARK: - Button system (UX-audit round 2)
//
// One sanctioned style per role; never raw .bordered / .borderedProminent /
// .controlSize / bare .borderless for a visible action:
//   Primary    MSPrimaryButtonStyle    34pt   the one likely next action (≤1/section)
//   Secondary  MSSecondaryButtonStyle  30pt   supporting actions; button-styled menus
//   Tertiary   MSInlineButton          28pt   inline list/form actions (was .borderless+small)
//   Icon-only  NotionIconButton+.minTap 30²/44 glyph actions
//   Destructive MSDangerButtonStyle    34pt   stop/delete

/// Inline ghost text-action — the sanctioned replacement for the ad-hoc
/// `.buttonStyle(.borderless).font(NDS.small)` clusters scattered across the
/// person/meeting views. Wraps `MSTertiaryButtonStyle` so every inline action
/// is one consistent 28pt height with the muted-label treatment.
@available(macOS 14.0, *)
struct MSInlineButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(MSTertiaryButtonStyle())
    }
}

extension View {
    /// Chrome for a `Menu` whose label should read as a secondary button —
    /// matches `MSSecondaryButtonStyle` (surface fill, hairline, `NDS.radius`,
    /// `buttonSecondaryH`) so a menu trigger never drifts from a real button
    /// (fixes the hand-built radius-8 Options chrome in the meeting header).
    func msMenuButtonChrome() -> some View {
        self
            .scaledFont(13, weight: .bold)
            .foregroundStyle(NDS.textPrimary)
            .padding(.horizontal, NDS.buttonHPadMd)
            .frame(height: NDS.buttonSecondaryH)
            .background(NDS.fieldBg,
                        in: RoundedRectangle(cornerRadius: NDS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NDS.radius, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// One reusable collapsible section (UX-audit round 2). The de-tabbed Meeting
/// and Person canvases stack these instead of using pill tabs: a chevron + an
/// eyebrow title + optional count, an optional trailing accessory (e.g. an Add
/// button, kept OUTSIDE the toggle's hit area), over a `@ViewBuilder` body.
/// Collapse state persists across navigation/relaunch when `persistenceKey` is
/// set (`@AppStorage("section.<key>.expanded")`), else it's transient `@State`.
/// Owns no horizontal padding or card — the host wraps it.
@available(macOS 14.0, *)
struct MSSection<Content: View, Trailing: View>: View {
    let title: String
    var systemImage: String?
    var count: Int?
    var persistenceKey: String?
    var defaultExpanded: Bool
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @State private var localExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String,
         systemImage: String? = nil,
         count: Int? = nil,
         persistenceKey: String? = nil,
         defaultExpanded: Bool = true,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.persistenceKey = persistenceKey
        self.defaultExpanded = defaultExpanded
        self.trailing = trailing
        self.content = content
        _localExpanded = State(initialValue: defaultExpanded)
    }

    private var storageKey: String? { persistenceKey.map { "section.\($0).expanded" } }

    private var isExpanded: Bool {
        if let storageKey { return UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultExpanded }
        return localExpanded
    }

    private func toggle() {
        let next = !isExpanded
        if let storageKey { UserDefaults.standard.set(next, forKey: storageKey) }
        withAnimation(NDS.motion(.easeInOut(duration: NDS.motionFast), reduce: reduceMotion)) {
            localExpanded = next   // also drives a re-render for the persisted path
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NDS.spaceSM) {
                Button(action: toggle) {
                    HStack(spacing: NDS.spaceSM) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .scaledFont(10, weight: .semibold).foregroundStyle(NDS.textTertiary)
                        if let systemImage {
                            Label(title, systemImage: systemImage)
                                .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                        } else {
                            Text(title).font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                        }
                        if let count {
                            Text("\(count)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
                        }
                        Spacer(minLength: NDS.spaceSM)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                trailing()
            }
            .padding(.vertical, NDS.spaceSM)
            if isExpanded {
                content().padding(.top, NDS.spaceSM)
            }
        }
    }
}

@available(macOS 14.0, *)
extension MSSection where Trailing == EmptyView {
    init(_ title: String,
         systemImage: String? = nil,
         count: Int? = nil,
         persistenceKey: String? = nil,
         defaultExpanded: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title, systemImage: systemImage, count: count,
                  persistenceKey: persistenceKey, defaultExpanded: defaultExpanded,
                  trailing: { EmptyView() }, content: content)
    }
}

/// One search field for the whole app (V5 SC-2). Replaces the divergent inline
/// magnifying-glass + TextField + clear-button stacks. Esc clears; pass
/// `autoFocus` to grab focus on appear.
@available(macOS 14.0, *)
struct MSSearchField: View {
    let placeholder: String
    @Binding var text: String
    var autoFocus: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(NDS.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        .onAppear { if autoFocus { focused = true } }
    }
}

/// A redacted placeholder block for cold-cache loading states — show page
/// structure instead of a blank/false-empty flash on first paint. Reduce-motion
/// aware (no shimmer when the user asked for less motion). (V5 DI-1 / PP-2)
@available(macOS 14.0, *)
struct MSSkeleton: View {
    var lines: Int = 3
    var lineHeight: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<max(1, lines), id: \.self) { i in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(NDS.fieldBg)
                    .frame(height: lineHeight)
                    .frame(maxWidth: i == lines - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .opacity(reduceMotion ? 1 : (shimmer ? 0.55 : 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: shimmer)
        .onAppear { if !reduceMotion { shimmer = true } }
        .accessibilityHidden(true)
    }
}

/// A centered icon + title (+ optional message) for blank panes. Replaces the
/// several bespoke "nothing here yet" stacks across the tabs.
@available(macOS 14.0, *)
struct MSEmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    init(systemImage: String, title: String, message: String? = nil,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .scaledFont(36).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            actions().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

@available(macOS 14.0, *)
extension MSEmptyState where Actions == EmptyView {
    init(systemImage: String, title: String, message: String? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// One filter chip, everywhere (D4-10). Bordered capsule with an optional count
/// badge — used by the Meetings scope pills, People tag/type chips, and search
/// filters so filtering looks and behaves identically wherever the user filters.
@available(macOS 14.0, *)
struct MSFilterChip: View {
    let label: String
    var count: Int? = nil
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(NDS.tiny)
                if let count {
                    Text("\(count)")
                        .font(NDS.tiny.monospacedDigit())
                        .foregroundStyle(active ? NDS.brand : NDS.textTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(active ? NDS.brand.opacity(0.18) : NDS.surface2, in: Capsule())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? NDS.brand.opacity(0.18) : NDS.fieldBg, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? NDS.brand.opacity(0.5) : NDS.hairline, lineWidth: 1))
            .foregroundStyle(active ? NDS.brand : NDS.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
