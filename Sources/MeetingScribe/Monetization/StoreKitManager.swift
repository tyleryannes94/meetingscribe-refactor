import Foundation
import OSLog

// TODO: StoreKit 2 — add `import StoreKit` once product IDs are configured
// in App Store Connect. The stub below lets the rest of the monetization
// infrastructure compile and be tested before the IAP backend is ready.

/// Product identifiers. Update when App Store Connect is configured.
enum ProProduct: String, CaseIterable {
    case monthly  = "com.tyleryannes.MeetingScribe.pro.monthly"
    case annual   = "com.tyleryannes.MeetingScribe.pro.annual"
    case lifetime = "com.tyleryannes.MeetingScribe.pro.lifetime"
}

/// StoreKit 2 manager for MeetingScribe Pro.
///
/// Current state: **stub** — no real StoreKit calls yet.
/// When the IAP is ready:
///   1. `import StoreKit`
///   2. Replace `purchase()` with `Product.products(for:)` + `product.purchase()`
///   3. Replace `restorePurchases()` with `Transaction.currentEntitlements`
///   4. Wire `FeatureGate.shared.isPro = true` on successful transaction
@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "StoreKit")

    @Published var isLoading = false
    @Published var lastError: String?

    private init() {}

    /// Initiates a purchase flow for the given product.
    /// Stub: logs intent and shows a TODO note.
    func purchase(_ product: ProProduct) async {
        log.info("Purchase requested: \(product.rawValue, privacy: .public)")
        // TODO: StoreKit 2 — Product.purchase()
        await MainActor.run {
            lastError = "StoreKit 2 purchase not yet implemented. Configure App Store Connect first."
        }
    }

    /// Restores prior purchases. Stub.
    func restorePurchases() async {
        log.info("Restore purchases requested")
        isLoading = true
        defer { isLoading = false }
        // TODO: StoreKit 2 — iterate Transaction.currentEntitlements
        // For now, check if the user has manually set isPro (dev override).
        if FeatureGate.shared.overrideAllEnabled {
            log.info("Dev override active — all features unlocked")
        }
    }

    /// Called from the upgrade-prompt trigger (after first AI summary).
    /// Shows the paywall once per install if not already Pro.
    func triggerUpgradePromptIfNeeded(feature: ManagedFeature = .relationshipContent) {
        guard !FeatureGate.shared.isEnabled(feature) else { return }
        // Show at most once per 7 days.
        let key = "storekit.lastUpgradePrompt"
        let lastShown = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastShown) > 7 * 86400 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        FeatureGate.shared.showPaywall(for: feature)
    }
}
