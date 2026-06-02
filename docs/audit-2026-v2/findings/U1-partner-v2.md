# U1 — Partner Persona Walkthrough (Alex, 32, relationship-focused user)

**Lens:** Full step-by-step audit of Alex's experience using MeetingScribe to track and deepen their 4-year romantic partnership, from first setup through coaching content.

---

## Step-by-Step Walkthrough

### Step 1: Alex opens AddPersonSheet to set partner as `romanticPartner`

**What ACTUALLY happens:** The relationship type picker is **NOT** in `AddPersonSheet`. The sheet (`Sources/MeetingScribe/People/AddPersonSheet.swift`, lines 1–186) has no `relationshipType` field, no state variable, no picker UI, and does not set `person.relationshipType` anywhere in its `save()` function (lines 123–147). The BRIEFING states the type picker is in `AddPersonSheet`, but the code contradicts this entirely.

**What SHOULD happen:** Alex fills in Name, sets type to "Romantic Partner" in the same form, saves. One flow, one screen.

**Actual path:** Alex must first save the person with no type, then navigate to PersonDetailView, find the `relationshipTypePicker` menu (lines 551–587 of PersonDetailView.swift) and select there. That is 3+ extra steps after creation.

**Severity:** High friction. The person is saved as `.unset` by default; no notification is ever scheduled for a partner created this way unless Alex manually finds and changes the type in PersonDetailView.

---

### Step 2: Alex sets the type — do notifications get scheduled?

**What ACTUALLY happens:** Setting the type via `relationshipTypePicker` in PersonDetailView (line 558–561) calls `people.updatePerson(updated)` — but does NOT call `RelationshipNotificationManager.shared.syncPersonReminders()`. The only place `syncPersonReminders` is called is inside `QuickEncounterSheet.saveIfValid()` (line 218 of QuickEncounterSheet.swift). It is never called on app launch (confirmed: `MeetingScribeApp.startServices()` has no call to it) and never called when `updatePerson` runs.

**What SHOULD happen:** Updating a person's relationship type should immediately schedule (or reschedule) their check-in reminder.

**Gap:** A user who sets `romanticPartner` but has not yet logged any encounter will never receive a check-in notification. The `syncPersonReminders` call is missing from three critical paths: (1) app launch, (2) `updatePerson` when `relationshipType` changes, and (3) `AddPersonSheet.save()`.

---

### Step 3: 3 days later — notification arrives, Alex taps "Log check-in"

**What ACTUALLY happens:**

The notification content is correctly built in `RelationshipNotificationManager.scheduleCheckIn()` (lines 103–119): title `"💑 Check in with [Partner]"`, body `"How are things between you two?"`, category `PERSON_CHECKIN`, with a `LOG_NOW` action registered (lines 31–34).

When Alex taps "Log check-in" (`LOG_NOW`), the action is sent to `NotificationManager.handleAction()` (Notifications/NotificationManager.swift, lines 205–243). The `handleAction` switch handles `actionJoinAndRecord`, `actionRecordOnly`, `actionRecordImpromptu`, and `UNNotificationDefaultActionIdentifier`. The `LOG_NOW` case (`RelationshipNotificationManager.actionLogNow = "LOG_NOW"`) falls through to `default: break` — **the action is silently dropped**.

**What SHOULD happen:** Tapping "Log check-in" should open the app and present `QuickEncounterSheet` for the partner, with `personID` extracted from `notification.request.content.userInfo["personID"]`.

**Severity:** Critical UX failure. The `PERSON_CHECKIN` category and `LOG_NOW` action are registered and visible in the notification, but tapping "Log check-in" does nothing except bring the app to the foreground. Alex is left with an open app and no sheet.

---

### Step 4: Alex tries to use QuickEncounterSheet — is it reachable in <3 taps?

**What ACTUALLY happens (TodayView path):**

1. Tap 1: Alex is already on Today tab. `StayConnectedSection` (TodayView.swift line 96) shows the partner if overdue. Alex taps the pink "Log" button on the partner row.
2. `StayConnectedSection.quickLogTarget` is set → `QuickEncounterSheet` sheet presents (StayConnectedSection.swift lines 58–65).

**Result: 1 tap from TodayView if the partner is already shown as overdue. This path works correctly.**

**What ACTUALLY happens (PersonDetailView path):**

1. Tap 1: Navigate to People section (or use sidebar).
2. Tap 2: Tap the partner's name in the list → PersonDetailView opens.
3. Tap 3: Tap "Encounter" button (line 522) → `showAddEncounter = true`.

But `showAddEncounter` opens `AddEncounterSheet` (line 316), the old heavyweight form requiring a typed event name — not `QuickEncounterSheet`. There is no route from PersonDetailView to `QuickEncounterSheet`.

**Severity:** Medium. The quick path exists in TodayView but PersonDetailView uses the old form, not the chip-first QuickEncounterSheet. Alex gets very different UX depending on entry point.

---

### Step 5: Alex logs "Coffee / Meal" with mood "great" — any reward signal?

**What ACTUALLY happens:** `QuickEncounterSheet.saveIfValid()` (lines 196–221): selects kind `coffee`, appends `[mood:great]` tag to notes, calls `people.addEncounter()`, calls `syncPersonReminders()` as a Task, then calls `dismiss()`. The sheet closes.

**No celebration, no reward signal, no sound, no animation, no toast, no haptic.** The sheet just closes silently. There are zero references to `NSSound`, haptics, confetti, toast/banner, or any celebratory UI anywhere in the codebase.

**What SHOULD happen:** macOS has `NSHapticFeedbackManager` (not available) but a brief success animation, a green checkmark flash, or a subtle sound would reinforce the habit. The briefing notes "design goal: under 10 seconds from open to saved encounter" — but there is zero acknowledgment that anything was saved.

---

### Step 6: Alex opens PersonDetailView — does Alex see the weekly Gottman prompt?

**What ACTUALLY happens:** `RelationshipPromptLibrary.weeklyPrompt(for:)` is defined at line 59 of RelationshipPromptLibrary.swift and returns the correct Gottman prompt for `.romanticPartner`. However, **it is never called anywhere in the app**. A codebase-wide search for `weeklyPrompt` and `RelationshipPromptLibrary` returns only the definition file itself — no call site exists in PersonDetailView, TodayView, StayConnectedSection, or anywhere else.

**What SHOULD happen:** PersonDetailView should display the weekly Gottman prompt in a visible card when `person.relationshipType == .romanticPartner`.

**Severity:** High. Phase 3's centerpiece coaching feature — the rotating Gottman prompts — is entirely dead code. 11 partner prompts exist but none are surfaced to Alex.

---

### Step 7: Alex tries to upgrade to Pro for coaching frameworks

**What ACTUALLY happens:**

- `FeatureGate.isEnabled(.relationshipContent)` returns `false` for free users (FeatureGate.swift line 73). However, in DEBUG builds `overrideAllEnabled = true` (line 55), so **all gates bypass during development**.
- In a production build, `isEnabled(.relationshipContent)` returns `false`, and `FeatureGate.showPaywall(for: .relationshipContent)` sets `paywallFeature` (line 87). But `paywallFeature` is an `@Observable` property on `FeatureGate.shared` — and `ProPaywallView` is **never presented as a `.sheet`** from any main view. A global search for `paywallFeature` outside of FeatureGate.swift and StoreKitManager.swift returns zero results.
- Even if the paywall were presented: tapping "Start 7-Day Free Trial" shows a "Coming Soon" alert (ProPaywallView.swift line 87). `StoreKitManager.purchase()` has no StoreKit 2 implementation.

**What SHOULD happen:** Alex hits a gate, sees `ProPaywallView`, taps the CTA, and StoreKit presents a purchase sheet.

**Severity:** Critical. The paywall is fully designed and built but has no presentation binding. No user can ever see it from a natural in-app flow. `StoreKitManager` contains no real IAP calls.

---

## Summary of Findings

| # | Step | Status | Severity |
|---|------|--------|----------|
| 1 | Relationship type in AddPersonSheet | MISSING — type picker absent from AddPersonSheet entirely | High |
| 2 | Notifications scheduled on type change | BROKEN — syncPersonReminders not called on type change or app launch | High |
| 3 | Tapping "Log check-in" in notification | BROKEN — LOG_NOW falls to `default: break` in NotificationManager | Critical |
| 4 | QuickEncounterSheet in <3 taps | PARTIAL — works from TodayView/StayConnectedSection; PersonDetailView opens old heavy form | Medium |
| 5 | Celebration on "Coffee/Meal, great" | MISSING — no reward signal at all; sheet silently dismisses | Medium |
| 6 | Weekly Gottman prompt in PersonDetailView | DEAD CODE — weeklyPrompt() never called anywhere | High |
| 7 | Pro paywall for coaching frameworks | BROKEN — ProPaywallView never presented; StoreKit not wired | Critical |

---

## Existing Plan Items I Rank Highest (from prior plan)

1. **Known gap #5** — `syncPersonReminders` not called on launch. The entire check-in notification system is silent at startup; Alex's reminders exist only if she happened to log an encounter in the same session she set the type.
2. **Known gap #4** — `ProPaywallView` has no sheet binding. No user can be converted to Pro from any natural flow.
3. **Known gap #6** — Dual `Encounter.Kind` enums. The QuickEncounterSheet enum (call/coffee/videoCall/message/metUp/milestone) is distinct from VaultKit's (meeting/call/email/message/note). If MCP tools read `eventName` to classify encounters, they will misparse QuickEncounterSheet entries.

---

## NET-NEW Recommendations

### U1-N1 — Add relationship type picker to AddPersonSheet (S)
**What:** Add `@State private var relationshipType: RelationshipType = .unset` + a `Picker` row to `AddPersonSheet`. Wire `save()` to set `person.relationshipType = relationshipType`. Also call `syncPersonReminders` after `people.updatePerson()`.
**Why:** The current flow requires 5+ steps to create a typed partner. First impressions are set during onboarding.
**User value:** Alex sets their partner in one shot during first-time setup.
**Effort:** S. **Impact:** High. **Deps:** none.

### U1-N2 — Handle LOG_NOW action in NotificationManager (S)
**What:** In `NotificationManager.handleAction()`, add `case RelationshipNotificationManager.actionLogNow:` that extracts `personID` from `userInfo`, calls `router.route(kind: .person, id: personID, ...)`, and posts a notification to open `QuickEncounterSheet` for that person. A `NotificationCenter` post (`meetingScribeOpenQuickLog`) consumed in `PeopleListView` or `PersonDetailView` would work.
**Why:** The LOG_NOW action is the entire value prop of the check-in notification. It is silently dropped.
**User value:** Alex taps the notification, QuickEncounterSheet opens pre-populated for their partner.
**Effort:** S. **Impact:** Critical. **Deps:** U1-N1, WorkspaceRouter.

### U1-N3 — Surface weeklyPrompt in PersonDetailView coaching card (S)
**What:** In PersonDetailView's identity panel (after `relationshipTypePicker`, around line 587), add a `if let prompt = RelationshipPromptLibrary.weeklyPrompt(for: current.relationshipType)` card. Show the prompt text with a "This week's reflection" label and a light pink/purple background. Gate behind `FeatureGate.isEnabled(.relationshipContent)` — show a teaser + paywall CTA for free users.
**Why:** `RelationshipPromptLibrary` is 100% dead code. The Gottman prompts exist but Alex never sees them.
**User value:** Alex opens her partner's profile and gets a concrete question: "Name three things your partner did this week that you appreciated."
**Effort:** S. **Impact:** High. **Deps:** paywall presentation fix (U1-N4).

### U1-N4 — Wire ProPaywallView presentation globally (S)
**What:** In `MainWindow.swift` or `MeetingScribeApp`, observe `FeatureGate.shared.paywallFeature` (it's already `@Observable`) and present a `.sheet` when it becomes non-nil: `if gate.paywallFeature != nil { ProPaywallView(feature: gate.paywallFeature).sheet(...) }`. This is a single binding change.
**Why:** `FeatureGate.showPaywall()` is called from `StoreKitManager` but no view ever listens to `paywallFeature`. The paywall is built; it just has no presentation path.
**User value:** Alex hits any gated feature and sees the paywall.
**Effort:** S. **Impact:** Critical (revenue). **Deps:** none.

### U1-N5 — Sync notifications on app launch and on `updatePerson` (S)
**What:** (1) In `MeetingScribeApp.startServices()`, after `PeopleStore.shared` is ready, add `Task { await RelationshipNotificationManager.shared.syncPersonReminders(people: PeopleStore.shared.people) }`. (2) In `PeopleStore.updatePerson()`, after saving, if the person's `relationshipType` changed, fire `syncPersonReminders`. An `@Observable` / Combine observation on `PeopleStore` would be cleaner, but a direct call in `updatePerson` is the minimal fix.
**Why:** This is known gap #5, but the downstream effect for Alex is that her partner never gets a notification even after she correctly sets the type.
**Effort:** S. **Impact:** High. **Deps:** none.

### U1-N6 — Route QuickEncounterSheet from PersonDetailView's "Encounter" button (S)
**What:** Replace the `showAddEncounter` binding in PersonDetailView (line 315) that opens `AddEncounterSheet` with `QuickEncounterSheet`. The old `AddEncounterSheet` (the heavyweight form) can be kept for the "detailed encounter" use case, but the primary "Encounter" button should use the chip-first sheet.
**Why:** Alex gets a different experience depending on whether she enters from TodayView vs PersonDetailView. Consistency matters for habit formation.
**Effort:** S. **Impact:** Medium. **Deps:** none.

### U1-N7 — Save confirmation signal in QuickEncounterSheet (S)
**What:** After `dismiss()` in `saveIfValid()`, play `NSSound(named: .init("Tink"))?.play()` and briefly animate a green checkmark (1-second overlay). On macOS 14+, `NSHapticFeedbackManager` is available for trackpad users. At minimum, update the StayConnectedSection row to show "Logged ✓" instead of "Log" for 2 seconds after a save.
**Why:** No reward signal = no habit loop. The 10-second goal is met but Alex has no idea if it worked.
**Effort:** S. **Impact:** Medium. **Deps:** none.

### U1-N8 — Partner streak / milestone micro-celebration (M)
**What:** When `people.addEncounter()` writes a coffee/meal encounter and the new total for the person reaches a milestone (3, 7, 14, 30 encounters), show a brief overlay card: "3 check-ins with [Name] 🎉 Keep going." Store milestone-seen flags in `UserDefaults` keyed on `personID + milestone`.
**Why:** Gottman research (cited in the preamble on line 92) emphasizes positive sentiment override. A streak signal creates emotional ownership of the relationship. No competitor in the "second brain for relationships" space (Monica, Clay) offers this on-device.
**Effort:** M. **Impact:** High. **Deps:** U1-N7.

### U1-N9 — "Last Gottman prompt" stamped on encounter note (S)
**What:** When Alex saves a QuickEncounterSheet entry while PersonDetailView's current weekly prompt is displayed (U1-N3), auto-append the prompt text as a note prefix: `[Reflection: "Name three things..."]`. This links coaching to logging.
**Why:** The prompt is disconnected from logging. Connecting them creates a journaling thread.
**Effort:** S. **Impact:** Medium. **Deps:** U1-N3.

### U1-N10 — Relationship type persisted through AddPersonSheet save (S)
**What:** After U1-N1, also ensure `PersonDTO.memberwise init` (SharedModels.swift — known gap #7) carries `relationshipType` so that round-tripped persons from the MCP don't lose their type.
**Why:** If Alex's MCP tools read her partner via `get_coaching_context`, a DTO with `.unset` would return the fallback coaching string instead of Gottman content.
**Effort:** S. **Impact:** Medium. **Deps:** U1-N1.

---

## Top 3 Picks

1. **U1-N2 (Handle LOG_NOW)** — The notification is the top-of-funnel habit trigger. If tapping it does nothing, Alex will disable notifications and the entire relationship coaching loop collapses.
2. **U1-N4 (Wire ProPaywallView)** — Revenue-blocking. The paywall is 100% built but unreachable. One binding in MainWindow fixes it.
3. **U1-N3 (Surface weeklyPrompt)** — The Gottman prompts are Phase 3's centrepiece and are 100% dead code. Surfacing them transforms PersonDetailView from a data form into a coaching surface.

## Single Highest-Priority Recommendation

**U1-N2 — Handle `LOG_NOW` notification action in NotificationManager.**
This is the moment MeetingScribe catches Alex's attention and asks for one behavior. Dropping the action silently is a trust-destroying bug: Alex tapped "Log check-in" and nothing happened. Fixing it takes one `case` in a `switch` statement and a `NotificationCenter` post. It unblocks the entire habit loop.
