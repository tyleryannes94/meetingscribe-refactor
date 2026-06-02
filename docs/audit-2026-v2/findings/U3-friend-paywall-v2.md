# U3 — Jordan's Free-Tier Journey: Friend Paywall Walkthrough

**Lens:** Walk every step a real free-tier user (8 friends, wants reminders + coaching) hits — and find every place the paywall should fire but doesn't.

---

## Persona

Jordan, 28. Uses MeetingScribe to stay close to 8 friends after relocating. Wants check-in reminders and coaching prompts. Free tier. Power user.

---

## Step-by-Step Walkthrough

### 1. Adding a 9th friend with a relationship type — does `unlimitedPeople` fire?

**Answer: No. Zero enforcement.**

`FeatureGate.ManagedFeature.unlimitedPeople` (`FeatureGate.swift:19`) documents a free-tier cap of 5 typed relationships. `isEnabled(.unlimitedPeople)` returns `false` for free users (`FeatureGate.swift:79`). But `AddPersonSheet.save()` (`AddPersonSheet.swift:130–157`) calls `people.updatePerson(person)` directly with no count check and no call to `FeatureGate.shared.isEnabled(.unlimitedPeople)`. Jordan adds person 9 (and 99) without friction.

There is also no relationship-type count cap. `AddPersonSheet` doesn't even include a `RelationshipType` picker in the current UI — the sheet was not updated when Phase 1 added the type system (the picker lives only in `PersonDetailView`'s `relationshipTypePicker` subview at line 551). So Jordan sets the type from the detail view post-save, again with zero gate.

**Net result:** `unlimitedPeople` is an enum case wired to nothing.

---

### 2. Coaching frameworks in PersonDetailView — gated?

**Answer: No gate, but the feature is dead code.**

`FeatureGate.ManagedFeature.relationshipContent` (`FeatureGate.swift:13`) is defined as Pro-only (`isEnabled` returns `false` at line 76). `ProPaywallView` lists "Relationship coaching frameworks (Gottman, NVC, love languages)" as a Pro bullet.

`RelationshipPromptLibrary.swift` contains 28 static prompts and a `weeklyPrompt(for:)` function (`RelationshipPromptLibrary.swift:59`). However, **`weeklyPrompt` is never called from `PersonDetailView` or any other view** — confirmed by codebase-wide grep returning zero hits outside `RelationshipPromptLibrary.swift` itself. The coaching content Jordan would look for on a person's detail page simply does not exist in the UI. There is no section, no card, no button that renders a coaching prompt. Even if Jordan upgraded to Pro, they would see no coaching frameworks anywhere in the app.

The relationship-type-aware AI preamble (lines 80–178 in `PersonDetailView.swift`) is visible to all users and does apply Gottman/NVC framing to Ollama queries — but this is contextual glue code inside the analysis engine, not a user-facing coaching surface, and it is ungated.

---

### 3. Setting up check-in reminders — does `checkInNotifications` gate fire?

**Answer: No gate on either the display surface or the notification scheduler.**

`StayConnectedSection` (`UI/StayConnectedSection.swift`) renders overdue friends with a one-tap log button and is mounted unconditionally in `TodayView.swift:96`. There is no `FeatureGate.shared.isEnabled(.checkInNotifications)` check before the section renders.

`RelationshipNotificationManager.syncPersonReminders()` (`RelationshipNotificationManager.swift:58`) contains zero references to `FeatureGate`, `isEnabled`, or `isPro`. It schedules push reminders for every person with `relationshipType != .unset`, regardless of tier or the `unlimitedCheckIns` limit (which caps free users at 3 reminders per `FeatureGate.swift:20` — also never enforced). Jordan gets all 8 friends' reminders for free.

There is a second problem: `syncPersonReminders()` is only called from `QuickEncounterSheet.swift:218` (on encounter save). It is **never called on app launch** (`MeetingScribeApp.swift` and `MainWindow.swift` have zero calls to it). Jordan's 8 friends accumulate overdue status silently until the first encounter log, which may never come for a new-city user who hasn't yet established the log habit.

---

### 4. Tapping "Start 7-Day Free Trial" — what happens?

**Answer: A "Coming Soon" alert. Dead end.**

`ProPaywallView.swift` — the "Start 7-Day Free Trial" button's action (`ProPaywallView.swift:66–68`) sets `showPurchaseAlert = true`. The alert (`ProPaywallView.swift:89–95`) reads:

> "StoreKit 2 purchase is not yet wired. To unlock Pro during development, set FeatureGate.shared.isPro = true in Xcode."

`StoreKitManager.purchase()` (`StoreKitManager.swift:37–41`) logs intent and sets `lastError` — no StoreKit call is made. The free trial cannot be started.

Compounding this: `ProPaywallView` itself is unreachable. A codebase-wide grep finds **zero `.sheet(item:)` or `.sheet(isPresented:)` bindings that present `ProPaywallView`** outside the Monetization/ folder. `FeatureGate.shared.paywallFeature` is an `@Observable` property that gets set by `showPaywall(for:)`, but nothing observes it to present the sheet — confirmed by grep returning only `FeatureGate.swift:61,87` and `ProPaywallView.swift:94` as all references to `paywallFeature`. Jordan cannot reach the paywall from any normal app flow.

---

### 5. Claude Desktop using `get_coaching_context` — gated?

**Answer: No. The MCP server has zero license checks.**

`MeetingScribeMCP/main.swift:1804` dispatches `get_coaching_context` to `tool_getCoachingContext()` with no license, tier, or `isPro` check anywhere in the dispatch loop or the tool implementation. The MCP binary runs as a separate process and has no runtime access to `FeatureGate.shared` (which lives in the main app's memory). There is no inter-process license handshake. All 6 Phase 4 people tools — `list_encounters`, `log_encounter`, `get_check_in_status`, `list_overdue_check_ins`, `get_coaching_context`, `attach_note_to_person` — are permanently free for every Claude Desktop user regardless of subscription status.

Note: `get_coaching_context` also returns "Active listening and consistent follow-through" as the coaching framework for Jordan's `friend`-typed contacts (briefing Gap 8), since only `romanticPartner`, `familyMember`, and `closeFriend` have non-fallback framework strings.

---

### 6. Credit card expires 3 months in — what happens to data? Graceful degradation?

**Answer: Data is safe. Degradation is moot because nothing was ever gated.**

`FeatureGate.isPro` is persisted to `UserDefaults` (`FeatureGate.swift:50`). When the subscription lapses, `isPro` would need to be set back to `false` by a StoreKit entitlement listener — but `StoreKitManager` has no `Transaction.updates` listener or `currentEntitlements` check. `restorePurchases()` is a stub that does nothing. So in practice: `isPro` stays `true` in `UserDefaults` forever once set, meaning a lapsed subscriber would retain "Pro" status indefinitely — accidental grace, not designed.

Because no feature is actually gated, there is nothing for Jordan to lose. All 8 friend profiles, encounters, memories, and notification schedules persist in local SQLite regardless. The app is local-first: no cloud sync means no server-side entitlement enforcement. Data is never at risk.

The absence of a `Transaction.updates` async sequence (the StoreKit 2 pattern for subscription renewal/lapse detection) means the app cannot distinguish an active subscriber from a lapsed one at runtime.

---

## What Is the Actual Upgrade Trigger?

**There is no upgrade trigger for Jordan.**

Mapping every path Jordan takes:
- Adding the 9th friend: no gate fires
- Viewing coaching content: no coaching content exists in UI to gate
- Setting up reminders: no gate, reminders work in full
- Tapping the trial CTA: the paywall is unreachable from normal flow
- Using MCP tools: no license check in the MCP server

`StoreKitManager.triggerUpgradePromptIfNeeded()` (`StoreKitManager.swift:57–65`) is the only function that calls `showPaywall()` with a rate limit — but it is **never called from any view**. A grep for `triggerUpgradePromptIfNeeded` outside `StoreKitManager.swift` returns zero results.

The only way Jordan sees the paywall is if `FeatureGate.shared.showPaywall(for:)` is called, which requires `paywallFeature` to be set, which requires a `.sheet(item:)` binding that does not exist. The upgrade funnel has no entry point.

**Is the paywall value proposition compelling?** The bullets in `ProPaywallView` are strong for Jordan's use case: per-person reminders and coaching frameworks are exactly what a relationship-focused user wants. $4.99/month is reasonable. The "local-first, no lock-in" reassurance is a real differentiator. The problem is entirely mechanical — the CTA is broken and the features it sells are either ungated or non-existent in the UI. There is nothing to convert.

---

## Key Findings Summary

| ID | Finding | Severity | File:Line |
|---|---|---|---|
| U3-1 | `unlimitedPeople` gate never called in `AddPersonSheet.save()` | Critical | `AddPersonSheet.swift:130–157` |
| U3-2 | `RelationshipPromptLibrary.weeklyPrompt()` has zero callers — coaching is dead code | Critical | `RelationshipPromptLibrary.swift:59` |
| U3-3 | `checkInNotifications` gate never checked in `StayConnectedSection` or `RelationshipNotificationManager` | Critical | `StayConnectedSection.swift:7`, `RelationshipNotificationManager.swift:58` |
| U3-4 | `ProPaywallView` has no `.sheet(item:)` binding anywhere — unreachable | Critical | All of `Sources/MeetingScribe/` |
| U3-5 | `StoreKitManager.purchase()` shows "Coming Soon" alert — 0% functional | Critical | `StoreKitManager.swift:37–41` |
| U3-6 | MCP server has no license checks — `get_coaching_context` and all Phase 4 tools free permanently | High | `MeetingScribeMCP/main.swift:1804` |
| U3-7 | No `Transaction.updates` listener — lapsed subscription never detected, `isPro` stays `true` in UserDefaults forever | High | `StoreKitManager.swift` (entire file) |
| U3-8 | `syncPersonReminders()` never called on app launch — notifications never fire until first manual encounter log | High | `MeetingScribeApp.swift`, `MainWindow.swift` |
| U3-9 | `triggerUpgradePromptIfNeeded()` is never called from any view or service | Critical | `StoreKitManager.swift:57` |
| U3-10 | `friend` relationship type gets fallback coaching framework in `get_coaching_context` — Jordan's primary use case is underserved | Medium | `MeetingScribeMCP/main.swift` |

---

## Net-New Recommendations

### U3-A — Add `RelationshipType` picker to `AddPersonSheet` and enforce `unlimitedPeople` at save
**What:** Insert a `RelationshipTypePicker` row in `AddPersonSheet` (mirrors the one in `PersonDetailView:551`). In `save()`, count people with `relationshipType != .unset`; if ≥ 5 and `!FeatureGate.shared.isEnabled(.unlimitedPeople)`, call `showPaywall(for: .unlimitedPeople)` instead of saving. This moves the gate to the natural moment of first real value: adding a *typed* friend.
**Why:** Jordan is adding relationship-typed friends. The friction point must be at the moment of intent (adding friend #6 with a type), not a passive background limit.
**User value:** First real upgrade moment Jordan would encounter naturally.
**Effort:** S (hours — picker already exists, count check is trivial)
**Impact:** High — creates the first working upgrade trigger in the entire codebase
**Deps:** Requires U3-B (paywall presentation) to actually show the paywall

### U3-B — Wire `ProPaywallView` sheet presentation in `MainWindow.swift`
**What:** In `MainWindow.swift`, inject `@State private var gate = FeatureGate.shared` and add `.sheet(item: $gate.paywallFeature) { feature in ProPaywallView(feature: feature) }` to the root `WindowGroup`. This is a single modifier that activates the entire monetization system.
**Why:** `paywallFeature` is observable and already set correctly by `showPaywall(for:)` — the only missing piece is a SwiftUI sheet binding that observes it.
**User value:** Prerequisite for any paywall to appear.
**Effort:** S (< 30 minutes)
**Impact:** Critical — unblocks the entire monetization funnel
**Deps:** None

### U3-C — Surface a "Weekly Coaching Prompt" card in `PersonDetailView` behind `relationshipContent` gate
**What:** Add a `CoachingPromptCard` section in `PersonDetailView` (near the identity panel, after `relationshipTypePicker`). For Pro users, call `RelationshipPromptLibrary.weeklyPrompt(for: current.relationshipType)` and render the prompt in a tappable card. For free users, render a locked ghost card with "Upgrade for weekly coaching prompts →" that calls `FeatureGate.shared.showPaywall(for: .relationshipContent)`.
**Why:** Jordan opened the app for coaching. Currently there is no coaching UI anywhere. `RelationshipPromptLibrary` is dead code. This gives both a visible Pro feature AND the second natural upgrade trigger.
**User value:** The single most compelling Pro feature for Jordan's use case — and currently completely absent from the UI.
**Effort:** S–M (the prompt library and gate exist; only the view card is new)
**Impact:** High — gives Jordan a reason to upgrade and activates Phase 3's primary deliverable
**Deps:** U3-B (paywall presentation)

### U3-D — Add `friend` and `colleague` coaching frameworks to `get_coaching_context` MCP tool
**What:** In `tool_getCoachingContext` in `MeetingScribeMCP/main.swift`, replace the fallback string "Active listening and consistent follow-through" with type-specific frameworks: `friend` → Dunbar number awareness + "invest in shared experiences" playbook, `colleague` → psychological safety (Edmondson) + trust-building questions, `acquaintance` → "weak ties" social capital framework. Add a `coaching_questions: [String]` array alongside the `recommended_framework` string.
**Why:** Jordan's 8 contacts are all typed as `friend`. The MCP tool currently returns the fallback for all of them, making the coaching context useless for Jordan's primary relationship type.
**User value:** Turns `get_coaching_context` from a data dump into actionable coaching for Jordan's actual contacts.
**Effort:** S (text additions + schema extension in main.swift)
**Impact:** Medium-High — directly improves the feature Jordan would use most in Claude Desktop
**Deps:** None

### U3-E — MCP license handshake via `.pro_status` file in app storage directory
**What:** When `FeatureGate.isPro` changes, write a signed `.pro_status` JSON file to the app's group container (same directory the MCP reads `people/` from). The MCP server reads this file at tool call time and returns an `{"error": "pro_required", "upgrade_url": "meetingscribe://upgrade"}` for `mcpPeopleTools` features when the file is absent or invalid. The file is signed with a HMAC using the app's bundle ID + install UUID as the key.
**Why:** The MCP process cannot access `FeatureGate.shared` (in-process singleton). Without a file-based handshake, the MCP will never enforce the `mcpPeopleTools` gate regardless of how much the in-app gate is improved.
**User value:** Creates a functional upgrade path from Claude Desktop ("I want to use coaching tools" → MCP returns upgrade_url → Jordan upgrades).
**Effort:** M (1–2 days: file write in app + read in MCP + HMAC signing)
**Impact:** High — closes the MCP license gap and creates a Claude Desktop → upgrade funnel
**Deps:** U3-B (paywall presentation must work before the MCP can meaningfully redirect users)

### U3-F — Add `syncPersonReminders()` call to app launch sequence in `MeetingScribeApp.swift`
**What:** In `MeetingScribeApp.swift` (or `MainWindow.swift`'s `.task`), call `await RelationshipNotificationManager.shared.syncPersonReminders(people: people.people)` after `PeopleStore` hydrates. Add a check: if `!FeatureGate.shared.isEnabled(.checkInNotifications)`, schedule zero notifications (free users) or cap at 3 (`unlimitedCheckIns`).
**Why:** Jordan has 8 friends with relationship types but no encounter logs yet in a new city. Without launch sync, no reminders fire until the first manual log — the notification loop never starts for new users. Also adds the missing gate check so reminders become a real Pro differentiator.
**User value:** Reminders actually work from day one; free users hit the 3-person cap and see a natural upgrade prompt.
**Effort:** S (one `.task` modifier + gate check)
**Impact:** High — fixes the broken notification loop and creates the third upgrade trigger (hitting the 3-reminder cap)
**Deps:** U3-B (paywall presentation)

---

## Top 3 Picks

1. **U3-B** — Wire `ProPaywallView` sheet in `MainWindow.swift`. Every other recommendation depends on the paywall actually appearing. One `.sheet(item:)` modifier. Hours of work.
2. **U3-C** — `CoachingPromptCard` in `PersonDetailView` behind the `relationshipContent` gate. This is the feature Jordan came for; it doesn't exist yet; `RelationshipPromptLibrary` has 28 prompts waiting to be used. Creates the most compelling Pro differentiator visible in the daily app flow.
3. **U3-A** — Enforce `unlimitedPeople` in `AddPersonSheet.save()` with a `RelationshipType` picker. Jordan has 8 friends and wants to add more. This is the first natural conversion moment in the entire user journey.

**Single highest-priority recommendation: U3-B.** The paywall is fully designed, the gate logic is correct, and `paywallFeature` is observable — but without a `.sheet(item:)` binding, none of it fires. One modifier in `MainWindow.swift` unblocks all other monetization work. No Jordan scenario can convert until this is wired.
