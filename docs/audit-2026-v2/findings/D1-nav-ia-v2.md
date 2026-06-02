# D1 — UI Code Quality Audit: RelationshipType Picker, QuickEncounterSheet, StayConnectedSection

**Lens:** Are Phase 1–6 UI components polished or placeholder-feeling? Do they deliver on their stated design promises?

---

## Audit findings by component

### 1. QuickEncounterSheet — auto-dismiss / "tap to instantly save" promise (BROKEN)

**File:** `Sources/MeetingScribe/People/QuickEncounterSheet.swift`

The doc-comment at line 71 states: `1. Tap a Kind chip (required)  ← auto-saves on tap`. The inline comment at line 110 reinforces this: `// Kind chips (tap any to instantly save a quick encounter)`.

**This promise is not kept.** The `KindChip` action closure (lines 122–124) only executes:
```swift
withAnimation(.easeInOut(duration: 0.15)) {
    selectedKind = (selectedKind == kind) ? nil : kind
}
```
It toggles `selectedKind` — it does NOT call `saveIfValid()` and does NOT call `dismiss()`. Auto-save only occurs when the user explicitly taps the "Save check-in" button or presses Return. The headline value proposition — "under 10 seconds from open to saved encounter" — is undermined because the user must complete a second deliberate action after picking a kind. The comments describe intended future behavior that was never implemented in the closure.

**Additional note:** Tapping a kind chip a second time *deselects* it (toggle logic). This is an unexpected interaction on a "required" field. The Save button copy helpfully reads "Select a type above" when nothing is selected, which is good, but the chip toggle-off behavior contradicts the required-field semantics.

**Verdict:** Placeholder-feeling. The "quick" in QuickEncounterSheet is not delivered — it's a two-tap flow masquerading as a one-tap flow.

---

### 2. StayConnectedSection — TodayView integration and visibility guard

**File:** `Sources/MeetingScribe/UI/StayConnectedSection.swift`  
**Integration point:** `Sources/MeetingScribe/UI/TodayView.swift:96`

`StayConnectedSection` is unconditionally included in `TodayView` at line 96:
```swift
StayConnectedSection { p in openPerson(p) }
```
There is no `FeatureGate`, no Pro check, no guard wrapping it. The section itself self-hides correctly when the computed `overdueRelationships` array is empty (line 35: `if !items.isEmpty`). This is correct behavior — zero-state means zero UI footprint.

**One subtle bug:** The `overdueRelationships` filter at line 17 excludes people with `relationshipType == .unset`. A user whose partner or family member still has `.unset` type (which is the default and persists for anyone not manually updated) will never see that person in the Stay Connected nudge even if they are 90 days overdue. Since `AddPersonSheet` does not include a relationship type picker (confirmed: grep returns no `relationshipType` usage in `AddPersonSheet.swift`), every newly added person has `.unset` and is invisible to this section until the user discovers the picker in `PersonDetailView`. This makes the section invisible for virtually every user on first week of use.

**Hardcoded values in StayConnectedSection:**
- Line 41: `.font(.system(size: 15, weight: .semibold))` — should be `NDS.body.weight(.semibold)` or a new NDS token
- Line 54: `.font(.system(size: 14, weight: .bold))` — should use NDS token
- Line 58: `.font(.system(size: 10))` — no NDS equivalent; badge font
- Line 64: `.font(.system(size: 13, weight: .semibold))` — should be NDS token
- `Color.pink` used raw (lines 30, 69, 72) — NDS has no warmth palette tokens (`warmRose`, `warmAmber`, `warmTeal` were proposed in the master plan at MASTER-PLAN.md §8 item D3-2 but never added to `NotionDesign.swift`). Raw `Color.pink` will look inconsistent in both light and dark mode compared to the NDS warm-tinted surface palette.

---

### 3. RelationshipType filter bar in PeopleListView — clipping risk

**File:** `Sources/MeetingScribe/People/PeopleListView.swift:475–490`

The `relationshipTypeChips` view wraps chips in a `ScrollView(.horizontal, showsIndicators: false)`, which correctly prevents clipping. The guard at line 244 (`if presentTypes.count > 1`) hides the bar entirely when only one or zero types are in use — good. The `FilterChip` component uses NDS tokens (`NDS.tiny`, `NDS.brand`, `NDS.fieldBg`, `NDS.hairline`) consistently.

**Gap:** The condition `presentTypes.count > 1` means the filter bar appears only *after* a user has manually set at least two different relationship types. Given that `AddPersonSheet` has no type picker, a fresh install will never show the filter bar until the user has opened PersonDetailView for at least two different people and set types. This is a discoverability dead-end for the relationship-type system.

**Potential clipping note (small windows):** With 6 possible types all showing emoji + displayName, the combined width at `NDS.tiny` is approximately 6 × 80pt = 480pt minimum. The sidebar `minWidth` is 260pt. The `ScrollView` wrapper handles this correctly — chips will scroll horizontally. No clipping at minimum window width. **Pass.**

---

### 4. ProPaywallView — presentation gap (CRITICAL)

**File:** `Sources/MeetingScribe/Monetization/FeatureGate.swift:61,87`  
**File:** `Sources/MeetingScribe/Monetization/StoreKitManager.swift:64`  
**File:** `Sources/MeetingScribe/Monetization/ProPaywallView.swift`

`FeatureGate.shared.showPaywall(for:)` sets `paywallFeature` (line 87 of `FeatureGate.swift`). `StoreKitManager.triggerUpgradePromptIfNeeded` calls this (line 64 of `StoreKitManager.swift`).

**However: no view in the app observes `FeatureGate.shared.paywallFeature` and presents `ProPaywallView` as a sheet.** A grep across the entire `Sources/` directory for `ProPaywallView`, `paywallFeature`, and `FeatureGate` (excluding the Monetization folder itself) returns zero results. `MainWindow.swift`, `TodayView.swift`, `WorkspaceRouter.swift`, and every other top-level view have no `.sheet(item: $featureGate.paywallFeature)` binding.

This means:
- `FeatureGate.shared.showPaywall(for: .checkInNotifications)` sets the property
- **Nothing reacts to it**
- `ProPaywallView` is never presented to users

The paywall is a complete dead end in production. Confirmed: `FeatureGate` is `@Observable`, but no view has `@Environment` or `@Bindable` on it to observe `paywallFeature`.

**Also confirmed:** `FeatureGate.overrideAllEnabled = true` in DEBUG (line 61 of `FeatureGate.swift`) means the paywall is also never triggered during development — two independent mechanisms ensure no developer ever sees it.

---

### 5. Empty state — first launch with no people

**StayConnectedSection:** Correctly renders nothing when `overdueRelationships.isEmpty` (line 35). No empty-state prompt — just invisible. Good for a section, but misses the Phase 5 recommended nudge ("Add the people who matter — D2-9 / D2-4").

**QuickEncounterSheet:** Only reachable via a `Person` object reference, so it cannot be displayed without a person. Structurally safe.

**RelationshipType filter bar:** Hidden when `presentTypes.count <= 1` (line 244). Safe.

**PeopleListView empty state** (line 283): Shows `MSEmptyState` with copy "No people yet. Use Add Person or Import above to get started — from Contacts, Gmail, your calendar, or a file." The master plan (D2-4, Phase 5) proposed relationship-coach framing: "Your relationship memory starts here. Add the people who matter." This has NOT been updated. The copy is still CRM-framing, not coach-framing.

---

### 6. Hardcoded colors and fonts inventory

| Location | Issue | NDS alternative |
|---|---|---|
| `StayConnectedSection.swift:41` | `.font(.system(size: 15, weight: .semibold))` | `NDS.body.weight(.semibold)` |
| `StayConnectedSection.swift:54` | `.font(.system(size: 14, weight: .bold))` | `NDS.body.weight(.bold)` |
| `StayConnectedSection.swift:58` | `.font(.system(size: 10))` | No NDS token — needs new `NDS.badge` |
| `StayConnectedSection.swift:64` | `.font(.system(size: 13, weight: .semibold))` | `NDS.small.weight(.semibold)` |
| `StayConnectedSection.swift:30` | `Color.accentColor` (avatar fill) | Acceptable — accent is system |
| `StayConnectedSection.swift:69` | `.tint(.pink)` on Log button | Needs `NDS.warmRelationship` token |
| `StayConnectedSection.swift:72` | `Color.pink.opacity(0.06)` on row background | Needs `NDS.warmRelationship` token |
| `ProPaywallView.swift:18` | `.font(.system(size: 52))` | Acceptable for hero icon, no NDS token needed |
| `ProPaywallView.swift:118` | `let color: Color` (ProBullet) — takes raw `Color.orange`, `.pink`, etc. | Caller inconsistency, not a bug |
| `RelationshipType.colorName` | Returns string names (`"RelationshipPartner"`, etc.) | No `.xcassets` file exists — `Color(named:)` would return nil. The property is dead code. |

**Orphaned dead code:** `RelationshipType.colorName` (Person.swift:111–122) references asset catalog colors that do not exist. There is no `.xcassets` file in `Resources/`. The property compiles but is unreferenced anywhere in the codebase. It is dead code that will silently produce `nil` if ever used with `Color(named:)`.

---

## Existing-plan items I rank highest (3–6)

1. **D2-2 / P1-2 — Relationship type picker in AddPersonSheet** (Master Plan Phase 1): The single highest-leverage fix. Every person created through the primary flow gets `.unset`, breaking StayConnectedSection, filter bar visibility, and notification scheduling for all new users.

2. **D3-2 / D1-9 — Type-specific color/icon in PersonRow** (Master Plan Phase 5): The warmth color tokens (`warmRose`, `warmAmber`, `warmTeal`) were proposed but never added to `NotionDesign.swift`. Without them, `StayConnectedSection` and future type-colored components must fall back to raw `Color.pink` / `Color.accentColor` — breaking NDS consistency.

3. **P4-1 / C5-1 — LicenseStore + paywall presentation wiring** (Master Plan Phase 6): Not just StoreKit — the sheet binding from `FeatureGate.paywallFeature` to `ProPaywallView` must be wired in `MainWindow.swift`. The paywall view itself is well-designed; it just needs a host.

4. **D5-2 — Fix 32 hardcoded font sizes in PersonDetailView** (Master Plan Phase 5): StayConnectedSection adds at least 4 more. These accumulate into a WCAG 1.4.4 failure and a maintenance burden.

5. **D2-4 — Rewrite PeopleListView empty-state copy** (Master Plan Phase 5): Still CRM-framing as confirmed above. Low effort, high positioning impact.

---

## NET-NEW recommendations

### D1-N1 — Implement the "auto-save on kind tap" promise in QuickEncounterSheet
**What:** Change `KindChip` action in `QuickEncounterSheet.swift` (line 122) to call `saveIfValid()` instead of only toggling `selectedKind`. Remove the toggle-off behavior (a required field should not be deselectable). Add a 0.2s "saved" micro-animation before `dismiss()`.  
**Why:** The doc-comment at line 71 and inline comment at line 110 both promise this behavior. It is not delivered. The current UX requires two deliberate taps (chip + Save button) plus a button that is disabled until you've tapped — the opposite of "under 10 seconds."  
**User value:** The one-tap encounter log is the habit formation mechanism. The current two-step flow will cause drop-off before the habit forms.  
**Effort:** S (under 2 hours — one closure change + animation)  
**Impact:** High — closes the gap between documented intent and shipped behavior  
**Deps:** None

### D1-N2 — Wire `FeatureGate.paywallFeature` to `ProPaywallView` in MainWindow
**What:** In `MainWindow.swift`, inject `@Environment(FeatureGate.self)` (or observe via `@Bindable`) and add:
```swift
.sheet(item: $featureGate.paywallFeature) { feature in
    ProPaywallView(feature: feature)
}
```
**Why:** `ProPaywallView` is fully designed and compilable but is never presented. `FeatureGate.showPaywall()` is called by `StoreKitManager` but has no effect in production or development. The monetization layer is silently broken.  
**User value:** Zero monetization conversion is possible without a presentation path.  
**Effort:** S (under 1 hour — one modifier on the root view)  
**Impact:** Critical — unblocks all monetization gating  
**Deps:** None (ProPaywallView is already complete)

### D1-N3 — Add `RelationshipType` picker to `AddPersonSheet`
**What:** Add a horizontal 3-card or segmented picker for `RelationshipType` as the first field in `AddPersonSheet` (before the Name field or immediately after it). Pre-fill `checkInCadenceDays` from `relationshipType.defaultCheckInDays`. Save `person.relationshipType` in the `save()` function.  
**Why:** Every person created via the primary Add Person flow gets `.unset` type. This makes `StayConnectedSection` invisible, `relationshipTypeChips` invisible, and notification scheduling broken for all newly added people. The master plan specified this as Phase 1 item D2-2 / P1-2 but it was not implemented in `AddPersonSheet`.  
**User value:** The relationship coach angle is invisible until the user discovers the picker inside `PersonDetailView`. Type-at-creation is the only path to first-time user activation.  
**Effort:** S (2–4 hours)  
**Impact:** High — fixes downstream breakage in StayConnectedSection, filter bar, notifications  
**Deps:** None

### D1-N4 — Add warmth color tokens to NDS and replace raw `Color.pink` in StayConnectedSection
**What:** Add to `NotionDesign.swift`:
```swift
static let warmRelationship = Color(hex: "#E57373") ?? .pink   // adaptive, not semantic pink
static let warmFamily       = Color(hex: "#FFB74D") ?? .orange
static let warmFriend       = Color(hex: "#4DB6AC") ?? .teal
```
Replace `Color.pink.opacity(0.06)` (StayConnectedSection:72) and `.tint(.pink)` (StayConnectedSection:69) with `NDS.warmRelationship` variants.  
**Why:** `Color.pink` is a fixed Apple semantic color that renders identically in light and dark mode regardless of the app's warm-tinted gray surface palette. In dark mode it clashes with `NDS.surface1`/`NDS.fieldBg`. The master plan proposed `warmRose`, `warmAmber`, `warmTeal` (Phase 5 item D3-2) but they were never added.  
**User value:** Visual consistency — the relationship coach section looks like the rest of the app rather than a bolted-on feature.  
**Effort:** S (1–2 hours)  
**Impact:** Medium — polish, not functional  
**Deps:** None

### D1-N5 — Remove or implement `RelationshipType.colorName` dead code
**What:** Either (a) add a `Color.xcassets` file with the 7 named relationship color assets and use `Color(named: rtype.colorName)` in PersonRow/StayConnectedSection, or (b) delete the `colorName` property and replace it with a direct `Color` computed property:
```swift
var accentColor: Color {
    switch self {
    case .romanticPartner: return NDS.warmRelationship
    case .familyMember:    return NDS.warmFamily
    ...
    }
}
```
**Why:** `RelationshipType.colorName` (Person.swift:111–122) returns strings referencing asset catalog colors that do not exist. There is no `.xcassets` bundle in `Resources/`. Any future developer using `Color(named: rtype.colorName)` will get `nil` silently. The property is referenced nowhere.  
**User value:** Removes a latent bug; opens the door to per-type accent colors in PersonRow and StayConnectedSection.  
**Effort:** S (1 hour)  
**Impact:** Low risk removal + medium future payoff  
**Deps:** D1-N4 (if option b)

### D1-N6 — Add a `FeatureGate` check before showing StayConnectedSection or gate by `relationshipContent`
**What:** Wrap `StayConnectedSection` in `TodayView.swift:96` with a gate check:
```swift
if FeatureGate.shared.isEnabled(.checkInNotifications) {
    StayConnectedSection { p in openPerson(p) }
}
```
Or, since the section is already invisible when no overdue people exist, add an inline upgrade nudge *inside* the section when the user is not Pro and has typed relationships that are overdue.  
**Why:** Currently `StayConnectedSection` is ungated — it appears for free users. Per the master plan's free vs. Pro split (Phase 6), per-person check-in reminders are Pro-only (`unlimitedCheckIns`). Showing overdue relationship nudges without the ability to act on notifications creates confusion ("why don't I get reminders?").  
**User value:** Cohesive upsell moment — nudge appears at peak motivation (user sees they're overdue) and the paywall is contextually relevant.  
**Effort:** S (1 hour — conditional + upgrade nudge)  
**Impact:** Medium (monetization cohesion)  
**Deps:** D1-N2 (paywall must be presentable first)

### D1-N7 — Implement `onSave` callback in StayConnectedSection to optimistically update row
**What:** After `QuickEncounterSheet` dismisses, `StayConnectedSection` should remove the logged person's row immediately with animation rather than waiting for `@Published` `PeopleStore.people` to re-diff. Add an `@State private var justLoggedIDs: Set<String>` and filter them out of `overdueRelationships`.  
**Why:** The current flow: user taps Log → sheet appears → user taps kind (+ Save) → sheet dismisses → ... list updates asynchronously when `PeopleStore` publishes. On slower storage (1000+ person vault), there may be a visible lag where the person remains in the "overdue" list after logging. The `onSave` closure is already passed through at TodayView line 96 as `{ _ in }` — it does nothing.  
**User value:** Snappy, confidence-inspiring feedback — the encounter was saved.  
**Effort:** S (1–2 hours)  
**Impact:** Medium (perceived performance + polish)  
**Deps:** D1-N1 (the kind-chip auto-save should land first so dismiss is reliable)

### D1-N8 — Add `accessibilityLabel` to emoji badges in StayConnectedSection and PersonRow
**What:** The relationship type emoji badges in `StayConnectedSection` (line 58: `Text(person.relationshipType.emoji)`) and `PersonRow` (PeopleListView.swift:585) have no `accessibilityLabel`. VoiceOver will read "💑" as "people holding hands" (Apple's system description) rather than "Partner relationship type." Add:
```swift
Text(person.relationshipType.emoji)
    .accessibilityLabel(person.relationshipType.displayName + " relationship")
```
Also: the "Log" button in StayConnectedSection has no `accessibilityHint` — add `.accessibilityHint("Log a check-in with \(person.displayName)")`.  
**Why:** The master plan identified ~40 unlabeled interactive elements (D5-1). These new Phase 2 components add to the count without addressing it.  
**Effort:** S (30 minutes)  
**Impact:** Low effort / baseline AT compliance  
**Deps:** None

---

## Top 3 picks

1. **D1-N2** — Wire `FeatureGate.paywallFeature` to `ProPaywallView` in MainWindow. Zero lines of design work needed — the paywall is fully built. This is a 1-hour fix that unblocks all monetization.

2. **D1-N1** — Implement the auto-save-on-kind-tap promise. The single most user-visible gap between documented intent and delivered behavior. Makes the "quick" in QuickEncounterSheet real.

3. **D1-N3** — Add `RelationshipType` picker to `AddPersonSheet`. Without this, every user who adds a person through the primary flow produces an `.unset`-typed record that is invisible to StayConnectedSection, the filter bar, and the notification scheduler — breaking the entire Phase 2 habit loop for new users.

---

## Single highest-priority recommendation

**D1-N2 — Wire the paywall sheet in MainWindow.**

`FeatureGate.showPaywall()` is called, `ProPaywallView` is designed, `FeatureGate` is `@Observable` — but the binding between them is missing. This is the keystone monetization bug: no code path in the app can currently present the paywall to a user. It is a one-line `.sheet(item:)` modifier in `MainWindow.swift`. Until this lands, `FeatureGate`, `ProPaywallView`, and `StoreKitManager.triggerUpgradePromptIfNeeded()` are all dead code at runtime.

