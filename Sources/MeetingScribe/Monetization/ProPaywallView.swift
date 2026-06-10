import SwiftUI

/// Paywall sheet shown when a user tries to access a Pro-gated feature.
/// No StoreKit wired yet — the "Start Free Trial" CTA shows a
/// `// TODO: StoreKit 2` alert. This shell lets the UI + gate be
/// tested before the IAP is configured. (Phase 6)
@available(macOS 14.0, *)
struct ProPaywallView: View {
    let feature: ManagedFeature?
    @Environment(\.dismiss) private var dismiss
    @State private var showPurchaseAlert = false

    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(NDS.brandMarkGradient)
                Text("MeetingScribe Pro")
                    .font(.title.bold())
                if let feature {
                    Text(featureLabel(feature))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Feature bullets
            VStack(alignment: .leading, spacing: 12) {
                ProBullet(icon: "bell.badge.fill",
                          text: "Per-person check-in reminders — never let a relationship drift",
                          color: NDS.gold)
                ProBullet(icon: "heart.text.square.fill",
                          text: "Relationship coaching frameworks (Gottman, NVC, love languages)",
                          color: NDS.accent)
                ProBullet(icon: "chart.xyaxis.line",
                          text: "Connection strength score + encounter heat map",
                          color: NDS.lilac)
                ProBullet(icon: "sparkles",
                          text: "Full MCP relationship tools for Claude (log encounters, get coaching context)",
                          color: NDS.sky)
                ProBullet(icon: "doc.text.fill",
                          text: "Monthly Relationship Intelligence Report",
                          color: NDS.mint)
                ProBullet(icon: "person.3.fill",
                          text: "Unlimited people with relationship types (free: 5)",
                          color: NDS.mint)
            }
            .padding(.horizontal)

            // Pricing
            VStack(spacing: 4) {
                Text("$4.99 / month  ·  or $49 / year")
                    .font(.headline)
                Text("No cloud. No subscription lock-in on your data. Local-first forever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // CTAs
            VStack(spacing: 10) {
                Button {
                    showPurchaseAlert = true
                } label: {
                    Label("Start 7-Day Free Trial", systemImage: "arrow.forward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(NDS.accent)

                Button("Restore Purchases") {
                    Task { await StoreKitManager.shared.restorePurchases() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button("Maybe Later") { dismiss() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(minWidth: 400, idealWidth: 480, maxWidth: 520)
        .alert("Coming Soon", isPresented: $showPurchaseAlert) {
            Button("OK") {}
        } message: {
            Text("StoreKit 2 purchase is not yet wired. To unlock Pro during development, set FeatureGate.shared.isPro = true in Xcode.")
        }
    }

    private func featureLabel(_ feature: ManagedFeature) -> String {
        switch feature {
        case .checkInNotifications:  return "Check-in reminders require Pro"
        case .relationshipContent:   return "Coaching frameworks require Pro"
        case .healthScore:           return "Connection strength score requires Pro"
        case .mcpPeopleTools:        return "MCP relationship tools require Pro"
        case .unlimitedPeople:       return "Unlimited typed relationships require Pro"
        case .unlimitedCheckIns:     return "Unlimited reminders require Pro"
        case .monthlyReport:         return "Monthly Relationship Intelligence Report requires Pro"
        default:                     return "This feature requires MeetingScribe Pro"
        }
    }
}

// MARK: - Bullet row

@available(macOS 14.0, *)
private struct ProBullet: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
