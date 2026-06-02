# P2 — Monetization Gate Wiring Audit v2

**Lens:** FeatureGate is built but never called — zero gating exists in any production code path.

---

## Full-App Audit Through the Monetization Lens

### FeatureGate.swift
`Sources/MeetingScribe/Monetization/FeatureGate.swift`

Well-designed: 8-case `ManagedFeature` enum, `isEnabled()` function, `paywallFeature: ManagedFeature?` observable state, `showPaywall(for:)` method. The critical flaw: `overrideAllEnabled = true` in DEBUG (`FeatureGate.swift:55`) means **no gate ever fires during development**. In release builds `isPro = false` by default — but nothing calls `isEnabled()`, so this distinction is moot.

### Call-site map for `FeatureGate` / `isEnabled` / `showPaywall` / `isPro`

A codebase-wide grep finds **exactly four call sites**, all in the monetization module itself:

| File | Line | What it does |
|---|---|---|
| `StoreKitManager.swift:50` | Reads `overrideAllEnabled` for a log statement | No enforcement |
| `StoreKitManager.swift:58` | `guard !FeatureGate.shared.isEnabled(feature)` | Correct pattern — but `triggerUpgradePromptIfNeeded()` is **never called from any view or service** |
| `StoreKitManager.swift:64` | `FeatureGate.shared.showPaywall(for: feature)` | Correct — but unreachable |
| `ProPaywallView.swift:94` | References `isPro` in a "Coming Soon" alert label | Informational only |

**Zero calls to `FeatureGate.shared.isEnabled()` exist outside the Monetization/ folder.**

### Gap: ProPaywallView is never presented

`ProPaywallView` is defined in `Sources/MeetingScribe/Monetization/ProPaywallView.swift:8` but is referenced in exactly **one file** — itself. No `.sheet(item: $FeatureGate.shared.paywallFeature)` binding exists in `MainWindow.swift`, `MeetingScribeApp.swift`, `TodayView.swift`, or anywhere else. Setting `paywallFeature` on `FeatureGate` is a no-op: nothing observes it to present the sheet. The paywall cannot appear for any user.

### Gap: StayConnectedSection — no gate

`Sources/MeetingScribe/UI/StayConnectedSection.swift` displays up to 3 overdue people with a one-tap quick-log button. No call to `FeatureGate.shared.isEnabled(.checkInNotifications)` or `.unlimitedCheckIns`. Free-tier users see the full UI without restriction. `TodayView.swift:96` renders it unconditionally.

### Gap: RelationshipNotificationManager — no gate

`Sources/MeetingScribe/People/RelationshipNotificationManager.swift` contains zero references to `FeatureGate`, `isEnabled`, `checkInNotifications`, or `isPro`. `syncPersonReminders()` schedules check-in push notifications for all people with `relationshipType != .unset` regardless of tier. Called from `QuickEncounterSheet.swift:218` on every encounter save — again with no gate. Free-tier users receive unlimited push reminders.

### Gap: PeopleListView — relationship filter chips are ungated

`Sources/MeetingScribe/People/PeopleListView.swift:43,475–487` — `relationshipTypeFilter` state + relationship-type chips are rendered with no `isEnabled(.relationshipTypes)` check. Per the `isEnabled` logic, `.relationshipTypes` actually returns `true` for free users (it's explicitly marked free), so this is intentional. But the 5-person typed-relationship limit (`unlimitedPeople`) is never enforced anywhere — no count check before `AddPersonSheet` saves a new typed person.

### Gap: PersonDetailView — coaching content and coaching preamble are ungated

`Sources/MeetingScribe/People/PersonDetailView.swift` has zero references to `FeatureGate`, `isEnabled`, `showPaywall`, `isPro`, `healthScore`, or `RelationshipPromptLibrary`. The relationship-type-aware AI preambles (lines 80–178) are rendered for all users. `RelationshipPromptLibrary.weeklyPrompt()` exists but is **never called from any view** — the coaching prompts library is dead code as well as ungated.

### Gap: QuickEncounterSheet — no gate

`Sources/MeetingScribe/People/QuickEncounterSheet.swift` contains no `FeatureGate` calls. The chip-first encounter logging flow and the subsequent notification resync fire for all users regardless of tier.

### Gap: MCP people tools — no license enforcement

`Sources/MeetingScribeMCP/main.swift` implements all 6 Phase 4 people tools (`list_encounters`, `log_encounter`, `get_check_in_status`, `list_overdue_check_ins`, `get_coaching_context`, `attach_note_to_person`) with zero license or tier checks. Any Claude Desktop user with the MCP server configured gets full `mcpPeopleTools` access permanently for free.

### Gap: unlimitedCheckIns limit never enforced

`FeatureGate.ManagedFeature.unlimitedCheckIns` documents a 3-person reminder cap for free users. No code anywhere in `RelationshipNotificationManager.swift` or its callers checks this limit or calls `isEnabled(.unlimitedCheckIns)`.

### Gap: monthlyReport feature — no UI and no gate

`ManagedFeature.monthlyReport` is defined and listed in `ProPaywallView`'s bullets, but there is no `MonthlyReport` view, generator, or trigger anywhere in the codebase. Both the feature and its gate are phantom.

### overrideAllEnabled = true — QA paywall testing

`FeatureGate.swift:55`: In DEBUG builds, `overrideAllEnabled` is a `var` initialised to `true`. This means **no developer can ever QA the paywall during normal development without manually setting it to `false` in a breakpoint or adding a debug UI toggle**. There is no settings panel, test flag, or scheme argument for toggling `overrideAllEnabled`. The ProPaywallView comment (`set FeatureGate.shared.isPro = true in Xcode`) describes unlocking, not paywalling — inverse of what QA needs. A developer who wants to test the blocked-feature UX must either compile a release build or remember to flip this flag in the debugger.

---

## Existing-Plan Items I Rank Highest

1. **Phase 9 — Real StoreKit 2 wiring** — The highest-leverage single item. Until `isPro` can actually be set to `true` by a real transaction, the entire monetization system is inert. The `ProProduct` IDs are already defined.
2. **ProPaywallView presentation binding** — Already flagged in the briefing as "Gap 4." One `.sheet(item: $FeatureGate.shared.paywallFeature)` in `MainWindow.swift` unblocks the entire system.
3. **syncPersonReminders on launch** — Briefing Gap 5. Notifications for pre-existing overdue relationships are never scheduled until the user manually logs an encounter.

---

## Net-New Recommendations

### P2-1 — Attach ProPaywallView sheet to MainWindow (not each feature site)
**What:** Add a single `.sheet(item: $gate.paywallFeature)` binding in `MainWindow.swift` where `gate = FeatureGate.shared`. Pass `paywallFeature` as the `ManagedFeature?` item to `ProPaywallView(feature:)`. Remove the need for every call site to manage its own sheet state.
**Why:** The paywall currently cannot appear at all. This is a one-line fix that activates the entire `showPaywall(for:)` system already built.
**User value:** Users who hit a Pro feature wall will see the upgrade prompt instead of getting the feature for free or seeing nothing.
**Effort:** S (< 1 hour)
**Impact:** Critical — without this, monetization is zero.
**Deps:** None. Works today with `isPro = false` in release builds.

### P2-2 — Add `isEnabled(.checkInNotifications)` guard in RelationshipNotificationManager
**What:** At the top of `syncPersonReminders()` in `RelationshipNotificationManager.swift`, add:
```swift
guard FeatureGate.shared.isEnabled(.checkInNotifications) else {
    // Free tier: schedule for at most 3 people, sorted by most overdue.
    // Cancel the rest.
    ...
}
```
For free users, cap at 3 notifications (honouring `unlimitedCheckIns`), cancel the rest via `center.removePendingNotificationRequests`.
**Why:** Push reminders are a stated Pro feature. Free users currently get unlimited push access permanently.
**User value:** Creates a real conversion trigger: "You have 5 overdue relationships but only 3 reminder slots — upgrade for all."
**Effort:** S
**Impact:** High — the most natural monetization hook in the habit loop.
**Deps:** P2-1 (paywall must be presentable before a gate produces user value).

### P2-3 — Add `isEnabled(.unlimitedPeople)` check in AddPersonSheet save action
**What:** In `AddPersonSheet.swift`, before calling `people.add(person)`, check:
```swift
let typedCount = people.people.filter { $0.relationshipType != .unset }.count
if typedCount >= 5 && !FeatureGate.shared.isEnabled(.unlimitedPeople) {
    FeatureGate.shared.showPaywall(for: .unlimitedPeople)
    return
}
```
**Why:** The 5-person free-tier limit is documented in `FeatureGate.swift:19` and `ProPaywallView.swift:104` but never enforced. Any user can add unlimited typed relationships for free.
**User value:** Creates a natural upgrade moment at peak engagement (when the user is actively building their relationship graph).
**Effort:** S
**Impact:** High — drives upgrades from engaged users who hit the wall organically.
**Deps:** P2-1.

### P2-4 — Add a `#if DEBUG` paywall test toggle to SettingsView
**What:** In `SettingsView.swift`, add a Developer section (already conditionally shown in other apps via `#if DEBUG`) with a toggle: "Simulate free tier" that sets `FeatureGate.shared.overrideAllEnabled = false` and `FeatureGate.shared.isPro = false`. Also add "Simulate Pro" that sets `isPro = true`. Persist via `@AppStorage("devPaywallOverride")`.
**Why:** Currently there is no way to QA the paywall in a DEBUG build without a debugger breakpoint. The `ProPaywallView` comment instructs developers to set `isPro = true` — the opposite of what paywall testing requires. This blocks any UX testing of the freemium tier.
**User value:** Internal — unblocks the entire QA workflow for monetization.
**Effort:** S
**Impact:** High — prerequisite for any meaningful monetization QA before launch.
**Deps:** None.

### P2-5 — Call `RelationshipNotificationManager.syncPersonReminders()` on app launch
**What:** In `MeetingScribeApp.startServices()` (around line 200), add:
```swift
Task { @MainActor in
    await RelationshipNotificationManager.shared.syncPersonReminders(
        people: PeopleStore.shared.people)
}
```
Gate this call: only fire if `FeatureGate.shared.isEnabled(.checkInNotifications)`.
**Why:** Currently notifications for existing overdue relationships are only scheduled when a user logs a new encounter (QuickEncounterSheet:218). A user who installs the app, adds 5 people, then doesn't open it for a week receives no reminders — defeating the entire habit loop.
**User value:** The notification system actually works as intended after this fix.
**Effort:** S
**Impact:** High — without launch sync, check-in notifications are mostly dead.
**Deps:** P2-2 (gate the launch call to respect the free-tier cap).

### P2-6 — Wire RelationshipPromptLibrary.weeklyPrompt() into PersonDetailView
**What:** `RelationshipPromptLibrary.weeklyPrompt(for:)` is built and contains 28 static prompts but is dead code — never called from any view. Add a "This week's prompt" card in `PersonDetailView.swift` for people with `supportsDepthContent` relationship types. Gate it: only visible if `FeatureGate.shared.isEnabled(.relationshipContent)`, otherwise show a teaser with a "Pro" lock badge.
**Why:** The coaching content is fully built. It is not surfaced anywhere. This is the most visible Pro-only differentiator and it currently does not exist in the UI at all.
**User value:** Users see the coaching value proposition in context; free users see exactly what they're missing.
**Effort:** S
**Impact:** Very high — activates built but unused content AND creates a visible in-context upgrade hook.
**Deps:** P2-1 (paywall presentation), P2-4 (QA testing).

### P2-7 — Add `isEnabled(.mcpPeopleTools)` guard at MCP tool dispatch
**What:** In `MeetingScribeMCP/main.swift`, in the `switch toolName` dispatch block for the 6 Phase 4 people tools, read a shared license file from the app's container (e.g. `AppSupport/MeetingScribe/license.json` written by the app when `isPro` is set) and return an MCP error for unlicensed callers:
```swift
guard licenseFile.isPro else {
    return .object(["error": "mcpPeopleTools require MeetingScribe Pro"])
}
```
**Why:** The MCP binary is a separate process — it cannot call `FeatureGate.shared`. But it can read a file the app writes. Currently any Claude Desktop user with the MCP configured gets all 6 relationship tools for free, bypassing the entire gate.
**User value:** Closes the most trivially exploitable bypass in the monetization system.
**Effort:** M (requires IPC file protocol between app and MCP binary)
**Impact:** High — the MCP tools are the primary technical differentiator for Pro users.
**Deps:** Real StoreKit wiring (Phase 9) so `isPro` can be durably set; app must write the license file on `isPro` change.

### P2-8 — Replace `overrideAllEnabled = true` default with `false`; add explicit dev unlock
**What:** Change `FeatureGate.swift:55` from `var overrideAllEnabled: Bool = true` to `var overrideAllEnabled: Bool = false`. Add a one-time launch check: `if CommandLine.arguments.contains("--dev-unlock") { overrideAllEnabled = true }`. Add that argument to the Xcode DEBUG scheme. This means a deliberate choice is needed to enable bypass mode, rather than requiring a deliberate choice to disable it.
**Why:** The current default means every developer is always testing in "all Pro" mode. No gated feature has ever been tested in a gated state. This inversion of defaults is the root cause of why the entire gate system is unvalidated.
**User value:** Internal — ensures every developer run exercises the free-tier code paths unless explicitly unlocked.
**Effort:** S
**Impact:** Very high — the single highest-leverage change for monetization integrity.
**Deps:** P2-4 (complementary Settings toggle for QA without relaunch).

### P2-9 — Implement `triggerUpgradePromptIfNeeded` call after first AI summary
**What:** `StoreKitManager.triggerUpgradePromptIfNeeded()` is fully implemented (rate-limited to once per 7 days, calls `showPaywall`) but never called. Add a call in `PersonDetailView.swift` after a successful AI summary completes, targeting `.relationshipContent`. This is the highest-intent moment — the user just generated AI coaching output and is most likely to upgrade.
**Why:** The upgrade prompt trigger is built and correct but orphaned. No user ever sees it.
**User value:** Converts the highest-intent action (using AI coaching) into an upgrade prompt.
**Effort:** S
**Impact:** High — this is the designed conversion funnel entry point.
**Deps:** P2-1 (paywall must be presentable).

### P2-10 — Persist `isPro` via Keychain, not UserDefaults
**What:** `FeatureGate.swift:50` persists `isPro` to `UserDefaults`. A technically-inclined user can trivially set `featureGate.isPro = 1` in `defaults write` and unlock all Pro features permanently. Move persistence to `KeychainStore` (already used for API keys in the codebase) with the key `featureGate.isPro`.
**Why:** UserDefaults is world-readable and writable from Terminal. This is not a serious attack vector for a $4.99 app but it is a trivially-avoided embarrassment, especially for a local-first app that already has a Keychain store.
**User value:** Basic bypass resistance. The Keychain store is already in the codebase so the marginal effort is small.
**Effort:** S
**Impact:** Medium — necessary hygiene before public launch.
**Deps:** Real StoreKit wiring (phase 9).

---

## Top 3 Picks

1. **P2-1** — Attach `ProPaywallView` to `MainWindow` with a single `.sheet(item:)` binding. The entire monetization system is assembled but the final wire is missing. One line unblocks everything.
2. **P2-8** — Flip `overrideAllEnabled` default to `false` with explicit opt-in. This is the structural root cause of why no gate has ever been tested. All other gate-wiring work is meaningless until developers can actually exercise it.
3. **P2-6** — Wire `RelationshipPromptLibrary.weeklyPrompt()` into `PersonDetailView` with a Pro gate. The coaching content is fully built and sitting idle. This creates the most visible in-product case for upgrading.

## Single Highest-Priority Recommendation

**P2-1** — Add `.sheet(item: $FeatureGate.shared.paywallFeature) { ProPaywallView(feature: $0) }` to `MainWindow.swift`. Every other gate-wiring item — `checkInNotifications`, `unlimitedPeople`, `unlimitedCheckIns`, `relationshipContent`, `mcpPeopleTools` — calls `FeatureGate.shared.showPaywall(for:)` correctly. The only reason none of them produce a visible result is that `paywallFeature` is observed by nothing. This is a one-line fix that activates a fully-built system.
