import SwiftUI

/// Shared layout primitives (U1 — design-system enforcement). The app had tokens
/// (`NDS`) and button styles but no reusable *surfaces*, so every tab hand-rolled
/// its own `fieldBg + hairline` card, section header, and empty state — the drift
/// the 2026-05 session doc flagged. Migrate surfaces onto these so a card is
/// defined (and fixed) in exactly one place.

extension View {
    /// Standard card surface: `fieldBg` fill, hairline border, card-radius.
    func msCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
                    .strokeBorder(NDS.hairline, lineWidth: 1)
            )
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
struct MSEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
