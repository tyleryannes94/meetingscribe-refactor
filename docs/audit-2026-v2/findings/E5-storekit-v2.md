# E5 — StoreKit 2 / FeatureGate Integration Audit

**Lens:** FeatureGate + StoreKit 2 completeness — exact delta from stub to shipping purchase flow.

---

## Full-App Audit Through This Lens

### 1. Purchase Flow Completeness

**Current state:** `StoreKitManager.purchase(_:)` (StoreKitManager.swift:35–42) logs a message and sets `lastError` to a "not yet implemented" string. Zero StoreKit calls exist. `import StoreKit` is not even present in the file (StoreKitManager.swift:4 comment).

**Delta to working purchase:**

```
Product.products(for: ProProduct.allCases.map(\.rawValue))   // fetch
  → store result as @Published var products: [Product]
product.purchase(options: [])                                  // transact
  → returns Purchase.Result: .success(VerificationResult<Transaction>)
  → .verified(let txn) → await txn.finish()
  → FeatureGate.shared.isPro = true
  → .unverified → log + show error
  → .pending → show "payment pending" UI
  → .userCancelled → no-op
```

Missing pieces:
- `import StoreKit` (line 4)
- `@Published var products: [Product] = []` on `StoreKitManager`
- `fetchProducts()` async method called from `init` or on-demand before paywall appears
- Full `purchase(_ product: Product)` replacing the stub (StoreKitManager.swift:35)
- `VerificationResult` unwrapping and `Transaction.finish()` call
- Error surface back to `ProPaywallView` (currently reads `lastError` but `purchase()` never sets it to anything meaningful)

### 2. Transaction Listener — The Critical Omission

**There is no `Transaction.updates` listener anywhere in the codebase.** Search across all Sources confirms zero `Transaction.updates` references (only Sparkle uses "EnableTransactions" in Obj-C, unrelated).

**Impact:** If a purchase completes while the app is backgrounded, suspended, or if the App Store processes a renewal in the background, `isPro` never flips to `true`. The user paid but has no Pro access until they manually tap "Restore Purchases." This is the single most impactful gap.

**Fix:** Add a `Task { for await result in Transaction.updates { ... } }` task in `StoreKitManager.init` (or better, from the `@main` `startServices()` method in `MeetingScribeApp.swift`) that runs for the app's lifetime. The handler should call `handle(verificationResult:)` which calls `Transaction.finish()` and sets `FeatureGate.shared.isPro = true` on `.verified` transactions whose `productType` is `.autoRenewable`.

### 3. Receipt Validation / Security Hole

**`FeatureGate.isPro` reads from and writes to `UserDefaults.standard` (FeatureGate.swift:50, 65).**

```swift
// FeatureGate.swift:49–51
var isPro: Bool = false {
    didSet { UserDefaults.standard.set(isPro, forKey: "featureGate.isPro") }
}
// FeatureGate.swift:65
isPro = UserDefaults.standard.bool(forKey: "featureGate.isPro")
```

**This is a security hole.** Any user can open `defaults write com.tyleryannes.MeetingScribe "featureGate.isPro" -bool YES` in Terminal and unlock Pro permanently. MeetingScribe is a local-first app so server-side validation isn't available, but StoreKit 2 provides `Transaction.currentEntitlements` which cryptographically verifies the purchase against Apple's signed transaction. The source of truth for `isPro` must be `Transaction.currentEntitlements`, not UserDefaults.

**Correct pattern:**
```swift
// On launch: verify entitlements, don't blindly read UserDefaults
for await result in Transaction.currentEntitlements {
    if case .verified(let txn) = result,
       ProProduct(rawValue: txn.productID) != nil,
       txn.revocationDate == nil {
        FeatureGate.shared.isPro = true
    }
}
```

UserDefaults caching is acceptable as a fast-path *after* the entitlement check has confirmed the transaction, not as the primary gate.

**Partial mitigation already present:** In DEBUG, `overrideAllEnabled = true` (FeatureGate.swift:56) means this hole only matters in RELEASE builds — but that's precisely where it must be locked down.

### 4. Family Sharing / Restore

`restorePurchases()` (StoreKitManager.swift:43–52) contains only a TODO comment and a dev-override check. It does not call `Transaction.currentEntitlements`. As a result:

- Restore Purchases button in `ProPaywallView` (line 78) calls `await StoreKitManager.shared.restorePurchases()` but nothing actually happens.
- Family Sharing (where a family member's entitlement comes through `Transaction.currentEntitlements` without the user having directly purchased) is completely unsupported.
- Re-installs, Mac migrations, and reinstalls after deletion will never restore Pro.

**Fix:** `restorePurchases()` should iterate `Transaction.currentEntitlements`, call `finish()` on each, and set `isPro = true` if any matching entitlement is found. Apple guidance for StoreKit 2: there is no separate `SKPaymentQueue.restoreCompletedTransactions()` — `currentEntitlements` is the restore mechanism.

### 5. Free Trial / Intro Offer Handling

`ProPaywallView` displays "Start 7-Day Free Trial" (line 70) as a hardcoded string. There is no code that:
- Checks whether the user is eligible for an intro offer (`product.subscription?.introductoryOffer != nil`)
- Checks whether they have already used the trial (`product.subscription?.isEligibleForIntroOffer` — available iOS 15.4+ / macOS 12.3+)

**How StoreKit 2 handles trial state:**
1. The intro offer is configured in App Store Connect (7-day free trial on the monthly product).
2. `Product.SubscriptionInfo.isEligibleForIntroOffer` returns `true` if the user has never subscribed. If `false`, the CTA copy must change to "Subscribe" not "Start Free Trial."
3. During the trial, `Transaction.offerType == .introductoryOffer`. The app can surface "Trial active — N days remaining" by computing `transaction.expirationDate - Date()`.

**Immediate risk:** If ProPaywallView always shows "Start 7-Day Free Trial" even for users who already used it, Apple will reject the app in review (guideline 3.1.1 misleading in-app purchase).

### 6. Dynamic Pricing

`ProPaywallView` hardcodes `"$4.99 / month  ·  or $49 / year"` (line 58). This is problematic for:
- **Pricing Localization:** App Store automatically adjusts prices per storefront (€4.99, ¥680, etc.). Hardcoded `$4.99` is wrong in every non-US territory.
- **Price Changes:** Any ASC price change requires a new app binary submission.
- **Review Compliance:** Apple reviewers in non-US territories see the wrong currency.

**Fix:** After `Product.products(for:)` resolves, use `product.displayPrice` (a pre-formatted locale-aware string from StoreKit) to populate the paywall. `ProPaywallView` should accept `@Binding var products: [Product]` or observe `StoreKitManager.shared.products`.

```swift
// In ProPaywallView, replace the hardcoded string:
if let monthly = storeKit.products.first(where: { $0.id == ProProduct.monthly.rawValue }),
   let annual  = storeKit.products.first(where: { $0.id == ProProduct.annual.rawValue  }) {
    Text("\(monthly.displayPrice) / month  ·  or \(annual.displayPrice) / year")
}
```

### 7. Paywall Presentation Gap

`FeatureGate.showPaywall(for:)` (FeatureGate.swift:86–87) sets `paywallFeature` but **no view in the entire codebase observes this property and presents `ProPaywallView` as a sheet.** The grep for `paywallFeature` outside `Monetization/` returns zero results. `ProPaywallView` is defined but never instantiated anywhere in `MainWindow.swift`, `MeetingScribeApp.swift`, or any view.

**Impact:** Even if a feature correctly calls `FeatureGate.shared.showPaywall(for:)`, the paywall never appears. No user ever sees it.

**Fix:** Add a `.sheet` modifier rooted at `MainWindow.swift` or `MeetingScribeApp.swift`:
```swift
.sheet(item: $featureGate.paywallFeature) { feature in
    ProPaywallView(feature: feature)
}
```
where `featureGate` is `@Environment(FeatureGate.self)` or `@State private var featureGate = FeatureGate.shared`.

### 8. StoreKit Configuration File (Testing)

No `.storekit` configuration file exists in the repo. Without `StoreKitTestConfiguration.storekit`, Xcode Simulator purchases cannot be tested without a real sandbox account. This blocks any testing of the purchase flow during development on this machine.

---

## Existing-Plan Items I Rank Highest

1. **Phase 9 (Monetization wiring)** — confirmed correct priority; must happen before any public release or the entire FeatureGate infrastructure is theater.
2. **Known gap #4 (ProPaywallView not presented)** — zero users see the paywall; fixes the entire monetization funnel in one `.sheet` modifier.
3. **Known gap #2 (`overrideAllEnabled = true` in DEBUG)** — means all gate logic is unexercised in development; easy to address with a per-feature `#if DEBUG` override toggle in Settings.

---

## NET-NEW Recommendations

### E5-1 — Wire `Transaction.updates` Persistent Listener on App Launch
**What:** In `MeetingScribeApp.startServices()`, start a long-lived `Task` that consumes `Transaction.updates` for the app's lifetime. Handle `.verified` transactions by calling `txn.finish()` and setting `FeatureGate.shared.isPro = true`. Handle `.unverified` by logging and ignoring.
**Why:** Without this, background renewals, billing recoveries, and purchases made on another device (with the same Apple ID) never unlock Pro. StoreKit 2 explicitly requires this listener.
**User value:** Pro users who renew on another device, or whose subscription auto-renews overnight, get access without ever tapping "Restore Purchases."
**Effort:** S (30–40 lines)
**Impact:** Critical — without it, Pro access is permanently unreliable.
**Deps:** `import StoreKit` added.

### E5-2 — Replace UserDefaults Gate with `Transaction.currentEntitlements` Source of Truth
**What:** Rewrite `FeatureGate.init` to iterate `Transaction.currentEntitlements` instead of reading `UserDefaults`. Keep a UserDefaults cache for startup speed (read it optimistically, then verify asynchronously). Add a `verifyEntitlements()` async method called from `startServices()`.
**Why:** UserDefaults is the only source of truth today — trivially exploitable.
**User value:** Prevents piracy; ensures refunded users lose access correctly (revoked transactions have `revocationDate != nil`).
**Effort:** S
**Impact:** High — security and correctness.
**Deps:** E5-1 (transaction listener).

### E5-3 — Add `.storekit` StoreKit Configuration File for Sandbox Testing
**What:** Create `MeetingScribeStoreKit.storekit` at the repo root with the three product IDs (`com.tyleryannes.MeetingScribe.pro.monthly`, `.annual`, `.lifetime`), their prices, and a 7-day intro offer on monthly. Configure Xcode scheme to use this file in StoreKit testing.
**Why:** Currently no way to test the purchase flow in Simulator without a live App Store Connect sandbox account. Every developer working on monetization hits this wall immediately.
**User value:** Indirect — faster iteration means fewer purchase-flow bugs reach users.
**Effort:** S (no code — Xcode GUI config + one JSON file)
**Impact:** High development velocity unlock; prerequisite for testing E5-1 and E5-2.
**Deps:** None.

### E5-4 — Intro Offer Eligibility Guard in ProPaywallView
**What:** Before rendering the "Start 7-Day Free Trial" CTA, call `product.subscription?.isEligibleForIntroOffer`. If `false`, change the button label to "Subscribe Now" and hide the trial copy. Add a `@discardableResult` helper `StoreKitManager.introOfferEligible(for: ProProduct) async -> Bool`.
**Why:** Apple App Store Review Guideline 3.1.1 requires accurate pricing and offer representation. Showing "Start Free Trial" to ineligible users is a review rejection risk.
**User value:** Accurate pricing copy; no broken expectations for returning subscribers.
**Effort:** S
**Impact:** Required for App Store approval.
**Deps:** E5-3 (need products fetched), `import StoreKit`.

### E5-5 — Dynamic Pricing in ProPaywallView
**What:** Remove the hardcoded `"$4.99 / month  ·  or $49 / year"` string (ProPaywallView.swift:58). Replace with `product.displayPrice` from the fetched `[Product]` array on `StoreKitManager`. Add a loading state (`.redacted(reason: .placeholder)`) while products fetch.
**Why:** Hardcoded USD prices are wrong in every non-US App Store territory. Apple reviewers in the EU will see wrong prices.
**User value:** Correct localized pricing in 170+ storefronts.
**Effort:** S
**Impact:** Medium-high; required for international launch.
**Deps:** Products fetched — requires `import StoreKit` + `Product.products(for:)` call.

### E5-6 — Subscription Status Banner for Active Trial Users
**What:** When `Transaction.currentEntitlements` contains an active intro offer transaction (`transaction.offerType == .introductoryOffer`), surface a dismissible banner in `TodayView` or `SettingsView`: "Your 7-day free trial ends [date]. [Manage subscription]". Use `transaction.expirationDate` to compute the date.
**Why:** Users don't know their trial end date. Surprise charges drive App Store refund requests and 1-star reviews. Proactive transparency reduces churn and support volume.
**User value:** No surprise billing; informed upgrade decisions.
**Effort:** S
**Impact:** High for retention/reviews.
**Deps:** E5-1 (transaction listener), E5-2 (entitlement verification).

### E5-7 — Subscription Management Deeplink
**What:** Add a "Manage Subscription" button in `SettingsView` that calls `Product.SubscriptionInfo.showManageSubscriptionsPage()` (or opens `https://apps.apple.com/account/subscriptions`). Currently, a Pro user has no in-app path to cancel or upgrade without knowing to go to System Settings → Apple ID.
**Why:** Apple requires a direct path to subscription management in-app (guideline 3.1.2). Without it, the app will be rejected.
**User value:** Easy cancellation path (paradoxically increases trust and subscription longevity by reducing trapped-feeling churn).
**Effort:** S (5 lines)
**Impact:** Required for App Store approval.
**Deps:** None — works with or without the full purchase flow implemented.

### E5-8 — Paywall Feature-Specific Upgrade Prompts at Gate Points
**What:** Every `FeatureGate.shared.isEnabled()` guard in the codebase (e.g., before showing a coaching framework, before creating a 6th typed person) should call `FeatureGate.shared.showPaywall(for: .relevantFeature)`. Currently no view actually enforces the gate — `FeatureGate.isEnabled()` is defined but never called from any non-Monetization/ file (confirmed by grep). Add contextual paywall triggers at: (a) attempt to add 6th typed person in `AddPersonSheet`, (b) attempt to view a coaching framework in `PersonDetailView`, (c) attempt to view the monthly report.
**Why:** Without gate enforcement, all Pro features are free forever. The entire monetization model is inert.
**User value:** Creates the actual conversion funnel; without this there is nothing to convert.
**Effort:** M
**Impact:** Critical — no enforcement = no revenue.
**Deps:** E5-paywall-sheet-fix (the `.sheet` binding must exist first).

### E5-9 — Lifetime Product Pricing Validation
**What:** `ProProduct.lifetime` (StoreKitManager.swift:13) exists as a product ID but is not shown in `ProPaywallView` and has no price listed. Add lifetime pricing ($149 one-time) to the paywall as a tertiary option. Validate that `Transaction.productType == .nonConsumable` (not `.autoRenewable`) for the lifetime product — different entitlement verification logic required since `currentEntitlements` handles non-consumables differently (no expiration check, no `revocationDate` unless refunded).
**Why:** Lifetime is a common ask for local-first privacy-focused apps (see comparable tools: Tot, Reeder, Pockity). It also attracts users who are subscription-averse — a meaningful segment of MeetingScribe's privacy-forward demographic.
**User value:** One-time payment option; no recurring billing anxiety.
**Effort:** S
**Impact:** Medium — incremental conversion; differentiated from cloud subscription tools.
**Deps:** E5-5 (dynamic pricing), full StoreKit wiring.

### E5-10 — `overrideAllEnabled` Per-Feature Debug Toggle in Settings (DEBUG-only)
**What:** In `SettingsView`, add a `#if DEBUG` section "Feature Gate (Debug)" with individual toggles for each `ManagedFeature` case. Replace the current blunt `overrideAllEnabled = true` with a `Set<ManagedFeature>` of enabled overrides. This lets the team test paywalled flows in DEBUG without disabling all gates.
**Why:** `overrideAllEnabled = true` (FeatureGate.swift:56) means the paywall is *never* exercised during development. The paywall sheet presentation bug (#7 in this audit) would have been caught in one minute of testing if the gate had ever fired.
**User value:** Indirect — better-tested paywall = fewer broken purchase flows reaching users.
**Effort:** S
**Impact:** Development quality; prevents regressions in gate logic.
**Deps:** None.

### E5-11 — Subscription Analytics: Log Purchase Events to Local Diagnostics
**What:** On `Transaction.updates`, log purchase, renewal, cancellation, and billing-retry events to the existing `CrashReporter` / diagnostics bundle (referenced in `MeetingScribeApp.swift:AppDelegate`). Events: `purchase_completed`, `subscription_renewed`, `subscription_cancelled`, `billing_retry`, `trial_started`, `trial_converted`. No external server — local log only, exported with the diagnostics bundle.
**Why:** No visibility into conversion funnel means no ability to diagnose "why aren't users upgrading." Even local logs are better than nothing. Essential for debugging payment issues reported by users.
**User value:** Indirect — faster diagnosis of payment problems; better support responses.
**Effort:** S
**Impact:** Medium — operational necessity for any paid app.
**Deps:** E5-1 (transaction listener provides the events).

---

## Top 3 Picks

1. **E5-1** (Transaction listener) — functional Pro access after background renewal; currently impossible.
2. **E5-8** (Gate enforcement at feature touch points) — without this, no code in the app ever calls `FeatureGate.shared.isEnabled()` in a user-facing context, making the entire monetization model a no-op.
3. **E5-2** (Replace UserDefaults with `currentEntitlements`) — closes the `defaults write` exploit and ensures refunded users lose access.

## Single Highest-Priority Recommendation

**Wire the paywall `.sheet` binding in `MainWindow.swift` + wire `Transaction.updates` listener in `startServices()`.** These are the two lines that turn the existing infrastructure from 100% non-functional to minimally functional. Everything else in this audit is refinement. Currently: `FeatureGate.showPaywall(for:)` sets `paywallFeature` and nothing observes it (paywall never appears); `isPro` can never flip to `true` from a real purchase (no StoreKit calls exist). Both fixes are under 50 lines total and unblock all downstream monetization work.

---

## 10-Step Checklist to Ship a Real Purchase

| # | Step | File | Effort |
|---|------|------|--------|
| 1 | `import StoreKit` in StoreKitManager.swift | StoreKitManager.swift:4 | S |
| 2 | Create `MeetingScribeStoreKit.storekit` config file + configure Xcode scheme | Repo root | S |
| 3 | Add `@Published var products: [Product] = []` + `fetchProducts()` called from `init` | StoreKitManager.swift | S |
| 4 | Wire `Transaction.updates` persistent listener in `startServices()` | MeetingScribeApp.swift | S |
| 5 | Replace `purchase()` stub with real `Product.purchase()` + `VerificationResult` handling | StoreKitManager.swift:35 | S |
| 6 | Replace `restorePurchases()` stub with `Transaction.currentEntitlements` iteration | StoreKitManager.swift:43 | S |
| 7 | Replace UserDefaults source-of-truth with `currentEntitlements` in `FeatureGate.init` | FeatureGate.swift:65 | S |
| 8 | Wire `.sheet(item: $featureGate.paywallFeature)` in `MainWindow.swift` | MainWindow.swift | S (1 line) |
| 9 | Replace hardcoded `"$4.99 / month"` with `product.displayPrice`; add intro offer eligibility guard | ProPaywallView.swift:58, 70 | S |
| 10 | Add gate enforcement calls (`FeatureGate.shared.isEnabled()` + `showPaywall`) at actual feature touch points | AddPersonSheet, PersonDetailView | M |
