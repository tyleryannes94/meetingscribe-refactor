import Foundation
import Observation

// MARK: - Managed Features

/// Every feature that can be gated behind a Pro tier.
/// Add new cases freely — old builds ignore unknown cases via `isEnabled`.
enum ManagedFeature: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    // Relationship intelligence (Phase 1–3)
    case relationshipTypes        // RelationshipType enum, type-specific UI
    case checkInNotifications     // Per-person push notification scheduler
    case relationshipContent      // Coaching prompts, frameworks, weekly prompt
    case healthScore              // Connection strength arc in PersonDetailView

    // MCP & AI (Phase 4)
    case mcpPeopleTools           // list_encounters, log_encounter, get_coaching_context, etc.

    // CRM limits
    case unlimitedPeople          // Free tier: 5 people with typed relationships
    case unlimitedCheckIns        // Free tier: 3 people with reminders

    // Reports (Phase 6)
    case monthlyReport            // Monthly Relationship Intelligence Report
}

// MARK: - Feature Gate

/// Central arbiter for Pro-gated features. Consult this before rendering
/// any Pro-only UI or executing Pro-only logic.
///
/// Usage:
///   ```swift
///   if FeatureGate.shared.isEnabled(.relationshipTypes) {
///       // show type picker
///   } else {
///       FeatureGate.shared.showPaywall(for: .relationshipTypes)
///   }
///   ```
///
/// During development `overrideAllEnabled = true` unlocks everything.
/// Shipping: set via `StoreKitManager.shared.isPro` on purchase/restore.
@available(macOS 14.0, *)
@MainActor
@Observable
final class FeatureGate {
    static let shared = FeatureGate()

    /// Master Pro flag. Set by `StoreKitManager` after purchase/restore.
    var isPro: Bool = false {
        didSet { UserDefaults.standard.set(isPro, forKey: "featureGate.isPro") }
    }

    /// Dev override — bypasses all gates. In DEBUG it defaults to `false` so the
    /// paywall is actually exercised during development; pass `--dev-unlock` (or
    /// flip the Settings toggle) to unlock everything. Release builds never unlock.
    #if DEBUG
    var overrideAllEnabled: Bool = ProcessInfo.processInfo.arguments.contains("--dev-unlock")
    /// QA aid: when `true`, gates behave as if the user is on the free tier even
    /// if `isPro`/override would otherwise unlock them. DEBUG-only.
    var simulateFreeTier: Bool = false
    #else
    let overrideAllEnabled: Bool = false
    #endif

    /// Which feature triggered the currently-shown paywall sheet (if any).
    var paywallFeature: ManagedFeature? = nil

    private init() {
        // Restore persisted Pro state (e.g. after app relaunch pre-StoreKit restore).
        isPro = UserDefaults.standard.bool(forKey: "featureGate.isPro")
    }

    /// Returns true when the feature should be accessible.
    func isEnabled(_ feature: ManagedFeature) -> Bool {
        #if DEBUG
        if simulateFreeTier { return freeTierAllows(feature) }
        #endif
        if overrideAllEnabled { return true }
        if isPro { return true }
        return freeTierAllows(feature)
    }

    /// Free-tier allowances, independent of Pro/override state.
    private func freeTierAllows(_ feature: ManagedFeature) -> Bool {
        // Free-tier allowances:
        switch feature {
        case .relationshipTypes:    return true   // free — classification only
        case .checkInNotifications: return false  // pro — push reminders
        case .relationshipContent:  return false  // pro — coaching frameworks
        case .healthScore:          return false  // pro — health arc
        case .mcpPeopleTools:       return false  // pro — MCP encounter tools
        case .unlimitedPeople:      return false  // pro — >5 typed relationships
        case .unlimitedCheckIns:    return false  // pro — >3 reminders
        case .monthlyReport:        return false  // pro — monthly report
        }
    }

    /// Presents the paywall sheet for the given feature.
    func showPaywall(for feature: ManagedFeature) {
        paywallFeature = feature
    }
}
