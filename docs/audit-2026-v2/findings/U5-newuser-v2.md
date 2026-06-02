# U5 — New User Persona: Riley, 25, Product Hunt Downloader

**Lens:** First-time user excited by the "AI relationship coach" marketing angle.
Walk-through of Riley's first 10 minutes in the app, identifying every friction
point and dead end they hit before deriving any value from the coaching pitch.

---

## Full First-10-Minutes Walk-Through

### 1. First launch — what screen appears?

`MeetingScribeApp.swift` launches `MainWindow`, which checks
`@AppStorage("hasCompletedOnboarding")` and presents `OnboardingSheet` once
(`MainWindow.swift:71–72, 326–342`). The onboarding covers:
- Vault location picker
- Microphone, Screen Recording, Calendar, Notifications, Accessibility permissions

**What is absent:** zero mention of "relationship coaching", "People", "check-in
cadences", or the concept that makes MeetingScribe different from Granola/Fathom.
The entire onboarding (`OnboardingSheet.swift`) is a permissions wizard. Riley
finishes it thinking this is a recording tool. The relationship coach angle —
the reason they downloaded it — is invisible.

**Gap U5-G1:** No value onboarding. `OnboardingSheet` covers only permissions;
it does not explain the "Second Brain / Relationship Coach" value proposition
or prompt Riley to add a first person.

### 2. Riley finds "People" tab — empty state?

`PeopleListView.swift` shows an empty state when `people.people.isEmpty` AND
`snapshotRows.isEmpty`:

```swift
private var emptyState: some View {
    MSEmptyState(systemImage: "person.2",
                 title: "No people yet",
                 message: "Use Add Person or Import above to get started…")
}
```
(`PeopleListView.swift`, `emptyState` computed property)

The message is accurate but bland. It says nothing about relationship coaching,
check-in cadences, or what they'd get by adding someone. There is no "Add your
first relationship" hero card. The `actionsRow` with "Add Person" and "Import"
buttons is present above, but they compete visually with a toolbar full of
controls (graph mode, sort, select).

**Gap U5-G2:** Empty state has no coaching hook. It reads like a contacts app,
not a relationship coach.

### 3. Riley taps "+" to add their partner — relationship type picker visible?

`AddPersonSheet.swift` is a standard form:
- First visible field: **Name** (auto-focused, `nameFocused = true`)
- Then: Company, Role, Email, Phone, Address, Favorite things, Birthday, Tags, Notes

The `RelationshipType` picker **does not appear in AddPersonSheet at all.**
The picker exists in `PersonDetailView.swift:551–585` (the identity sidebar),
but `AddPersonSheet` has no `relationshipType` state variable and no picker.

**Gap U5-G3 (critical):** `AddPersonSheet` does not include the RelationshipType
picker despite Phase 1 explicitly planning it (`D2-2 / P1-2` in the master plan:
"Add relationship type picker as first field in AddPersonSheet"). The picker is
only accessible after saving, then going into PersonDetailView. Riley adds their
partner as a contact with no type, so no cadence is set, no coaching prompts
are shown, and StayConnectedSection never surfaces them.

### 4. Riley sets type to `romanticPartner` — what changes?

After manually navigating to PersonDetailView and finding the type picker
(help text: "controls check-in cadence and coaching content"), setting
`romanticPartner` does:
- Changes the emoji badge in the list row (`PeopleListView`, `PersonRow.body`)
- Sets `effectiveCheckInDays` to the default (likely 7d from `RelationshipType.defaultCheckInDays`)

**Notification scheduling:** `RelationshipNotificationManager.syncPersonReminders()`
is called only from `QuickEncounterSheet.swift:218` (after logging an encounter).
It is **not called on app launch** and **not called when a person's relationship
type changes** (`PersonDetailView.swift:557–585` — the picker calls
`people.updatePerson(updated)` but does not call `syncPersonReminders`).

**Gap U5-G4:** Notifications are never scheduled when a person is first created
or their relationship type is set. Riley won't receive a check-in reminder until
after they log at least one encounter — which itself requires finding the
QuickEncounterSheet. The `RelationshipNotificationManager` is orphaned.

### 5. Riley navigates to TodayView — does StayConnectedSection appear?

`StayConnectedSection` (`UI/StayConnectedSection.swift`) filters for:
```swift
people.people
    .filter { $0.relationshipType != .unset }
    .filter { isOverdue($0) }
```
`isOverdue` uses `p.lastInteractionAt ?? p.createdAt`. For a brand-new person
just added, `lastInteractionAt` is nil, so it falls back to `createdAt`. The
person was just created, so `daysSince = 0`, which is less than
`effectiveCheckInDays` (7 for romanticPartner). **Riley's partner will not
appear in StayConnectedSection until 7 days after creation.**

A new user gets zero engagement signal from StayConnectedSection on day one.

### 6. Riley hears about "AI coaching" — where is it in the app?

`RelationshipPromptLibrary.weeklyPrompt(for:)` exists
(`RelationshipPromptLibrary.swift:59`) and produces Gottman-informed prompts for
`romanticPartner`, NVC prompts for `familyMember`, and love-language prompts for
`closeFriend`. But searching `PersonDetailView.swift` for any call to
`weeklyPrompt` or `RelationshipPromptLibrary` returns **zero results**. The
library is completely unconnected to any UI surface.

The relationship-type-aware AI preamble exists in `PersonDetailView.swift:86–178`
(a `ConversationAnalysisPreset`), but it is only invoked when a user runs an
explicit AI analysis on a person's message history. There is no proactive
coaching surface, no "This week's prompt" card, no coaching tab.

**Gap U5-G5 (critical):** `RelationshipPromptLibrary` is dead code. The 28 static
prompts it contains (the only tangible "AI coaching" content in the codebase) are
never shown to any user anywhere in the app. Riley will never discover them.

### 7. Riley considers upgrading to Pro — clearest value moment?

`ProPaywallView.swift` is defined and has a full UI, but searching all
non-Monetization Swift files for `ProPaywallView` returns zero results. The
paywall is never presented from any main view. `FeatureGate.shared.showPaywall(for:)`
is called only inside `StoreKitManager.swift:64`, which itself is only called
when a feature is tapped — but no feature in the People/TodayView/PersonDetailView
flow calls `StoreKitManager` or checks `FeatureGate.isEnabled()`.

In DEBUG, `FeatureGate.overrideAllEnabled = true` means all gates bypass
completely. In production there are no gate checks in the relationship coaching
surfaces. The paywall is an island.

**Gap U5-G6:** Pro upgrade has no moment of truth. There is no screen where
Riley sees a locked premium feature and understands the value of upgrading.
The paywall exists but is unreachable through normal navigation.

### 8. What's missing for Riley to tell 3 friends?

The viral moment for a relationship coach app is: *"It reminded me to check in
on my mom — and gave me something specific to talk about."* That requires:

1. A check-in notification that fires
2. A coaching prompt surfaced in-app that sparks a real action
3. Visible proof that the app is tracking the relationship

None of these three things happen for Riley in the first 10 minutes — or the
first 7 days.

---

## Existing-Plan Items I Rank Highest

1. **D2-2 / P1-2 — RelationshipType picker as first field in AddPersonSheet**
   The single highest-friction gap for new users. Without this, the entire
   coaching stack is inaccessible.

2. **Phase 2 — syncPersonReminders on app launch and on type change**
   Notifications scheduled only on encounter log means the habit loop never
   starts. Bridging this is hours of work and unlocks the core retention driver.

3. **Phase 3 — RelationshipPromptLibrary surfaced in PersonDetailView**
   The 28 prompts exist and are good. Wiring `weeklyPrompt(for:)` into a card
   in PersonDetailView is ~30 lines of code. This is the "AI coaching" moment.

4. **U5-G3/U5-G4 — Notification scheduler wired to person creation/edit**
   Must call `RelationshipNotificationManager.syncPersonReminders()` when
   `AddPersonSheet` saves a new person with a non-unset type and when the picker
   in PersonDetailView changes.

---

## NET-NEW Recommendations

### U5-1 — "Relationship coach" value onboarding step (S, Impact: HIGH)
**What:** Add a final step to `OnboardingSheet` before dismissal: a 1-screen
"Your relationship coach" card explaining the People + check-in + coaching loop.
Include a "Add your first relationship" CTA that deep-links into AddPersonSheet
with `relationshipType` pre-selected. Show 3 icons: `heart.fill`,
`bell.circle`, `sparkles` with one-line descriptions.
**Why:** Riley downloaded this for coaching. The current onboarding never
mentions it. One screen before dismiss converts a confused new user into an
activated one.
**File:** `Sources/MeetingScribe/UI/OnboardingSheet.swift`, add a new case to
the `step` enum after the final permission step.
**Effort:** S | **Impact:** Very High — direct path from marketing promise to
first value action.
**Deps:** None.

### U5-2 — RelationshipType picker as first field in AddPersonSheet (S, Impact: CRITICAL)
**What:** Add `@State private var relationshipType: RelationshipType = .unset`
and a card-style picker (matching the 5-card design in the master plan) as the
**first** field in `AddPersonSheet`, above the Name field. Pre-populate a prompt
"Who is this person to you?" Display the 5 most common types: Partner, Family,
Close Friend, Colleague, Other. When a type is selected, auto-fill
`checkInCadenceDays` from `RelationshipType.defaultCheckInDays`. Call
`syncPersonReminders` in the `save()` function after `people.updatePerson(person)`.
**Why:** Without this, all of Phase 1's relationship type infrastructure is
never set for any new person. The coaching, cadences, and StayConnectedSection
are permanently inaccessible for the typical new-user journey.
**File:** `Sources/MeetingScribe/People/AddPersonSheet.swift:47–113`
**Effort:** S | **Impact:** Critical — unlocks everything downstream.
**Deps:** RelationshipType enum (already in Person.swift:56).

### U5-3 — Wire weeklyPrompt into PersonDetailView coaching card (S, Impact: HIGH)
**What:** In `PersonDetailView.swift`, add a `coachingCard` computed property
that calls `RelationshipPromptLibrary.weeklyPrompt(for: person.relationshipType)`.
Render it as a card near the top of the identity panel (below the relationship
type picker):
```
[sparkles icon] This week's reflection
"Name three things your partner did this week…"
[Dismiss for this week]
```
Suppress for `.unset`, `.colleague`, `.acquaintance`. Dismissed state stored in
`@AppStorage("dismissedCoachWeek_\(personID)")`.
**Why:** The 28 prompts are fully written and correct. Zero users see them today.
This is the app's core differentiator from every meeting tool competitor, and
it's one function call away from being live.
**File:** `Sources/MeetingScribe/People/PersonDetailView.swift` ~line 544.
**Effort:** S | **Impact:** Very High — delivers the "AI coaching" promise
immediately.
**Deps:** RelationshipPromptLibrary.swift (already exists).

### U5-4 — StayConnectedSection day-0 activation (S, Impact: MEDIUM)
**What:** Modify `StayConnectedSection.overdueRelationships` to also include
people where `lastInteractionAt == nil` (newly added) AND `relationshipType !=
.unset`. Show them with copy "Start your check-in habit" instead of "N days
overdue". Cap at 1 such card so it doesn't overwhelm.
**Why:** Currently StayConnectedSection is invisible for 7 days to every new
user. A newly-added partner with no logged encounters should appear
immediately as an onboarding nudge.
**File:** `Sources/MeetingScribe/UI/StayConnectedSection.swift:18–30`
**Effort:** S | **Impact:** Medium — turns TodayView into an active surface on
day one.
**Deps:** U5-2 (needs person to have a type set on creation).

### U5-5 — Sync reminders on person save and type change (S, Impact: HIGH)
**What:** In two places:
1. `AddPersonSheet.save()` — after `people.updatePerson(person)`, call
   `Task { await RelationshipNotificationManager.shared.syncPersonReminders(people: people.people) }`
   when `person.relationshipType != .unset`.
2. `PersonDetailView` relationship type picker onChange — after calling
   `people.updatePerson(updated)`, call the same sync.
3. `MeetingScribeApp.startServices()` — add a background sync call:
   `Task.detached(priority: .utility) { await RelationshipNotificationManager.shared.syncPersonReminders(people: PeopleStore.shared.people) }`
**Why:** `syncPersonReminders` is never called except after a QuickEncounterSheet
save. New users will never receive a check-in notification. The notification
system is complete but disconnected.
**File:** `AddPersonSheet.swift:save()`, `PersonDetailView.swift:~560`,
`MeetingScribeApp.swift:startServices()`
**Effort:** S | **Impact:** High — the entire notification habit loop depends on this.
**Deps:** RelationshipNotificationManager.swift (already exists).

### U5-6 — People tab empty state with coaching pitch (S, Impact: MEDIUM)
**What:** Replace the generic `MSEmptyState` in `PeopleListView.emptyState` with
a purpose-built coaching empty state:
- Headline: "Your relationship coach starts here"
- Sub: "Add someone you want to stay close with. MeetingScribe tracks how
  often you connect and surfaces weekly reflection prompts."
- CTA button: "Add my first person →" that opens `AddPersonSheet`
- Secondary row: three relationship-type icons (💑 📬 👫) as visual affordance
**Why:** The current empty state ("No people yet") reads like an address book.
The coaching framing is what Product Hunt users expect.
**File:** `Sources/MeetingScribe/People/PeopleListView.swift:emptyState`
**Effort:** S | **Impact:** Medium — first impression for every cold-start user.
**Deps:** U5-2 (type picker in AddPersonSheet).

### U5-7 — ProPaywall reachable from PersonDetailView coaching card (S, Impact: HIGH)
**What:** When `weeklyPrompt` returns a value for a person and
`FeatureGate.shared.isEnabled(.coachingPrompts)` is false (i.e., user is
on free tier), show the prompt truncated with a "Unlock coaching — Pro" overlay
instead of hiding it. This is the single most natural paywall moment in the app:
the user can see a relevant, personalized coaching prompt and understands
exactly what they'd get with Pro.
Also: wire `ProPaywallView` as a `.sheet` on `PersonDetailView` driven by
`@ObservedObject var gate = FeatureGate.shared`, so tapping "Unlock coaching"
presents the paywall sheet. Currently `ProPaywallView` is never presented.
**Why:** No user ever sees the paywall today. The coaching card is the highest-
intent moment to introduce it.
**File:** `Sources/MeetingScribe/People/PersonDetailView.swift`, plus
`Sources/MeetingScribe/Monetization/FeatureGate.swift` (add `.coachingPrompts`
to `ManagedFeature` if not already there).
**Effort:** S–M | **Impact:** High — first monetizable touch point.
**Deps:** U5-3 (coaching card must exist first), ProPaywallView.swift (exists).

### U5-8 — "First relationship" guided flow (M, Impact: HIGH)
**What:** A three-step guided modal triggered from the onboarding CTA or the
empty-state button:
1. "Who is this person?" — RelationshipType card picker (full-screen, not a form)
2. "Tell me their name" — name field, pre-focused
3. "How often do you want to check in?" — stepper preset by type default, with
   copy "We'll remind you if you go quiet"
On save: immediately schedule notifications, show a success banner
"[Name] added — your first check-in reminder is set for [date]."
**Why:** The current AddPersonSheet is a contacts-style form that buries the
value proposition. A coach-first flow names the outcomes explicitly.
**File:** New `Sources/MeetingScribe/People/RelationshipOnboardingFlow.swift`
**Effort:** M | **Impact:** High — dramatically improves day-1 activation rate.
**Deps:** U5-5 (notifications must fire after save).

### U5-9 — "Coaching history" encounter journal toggle (S, Impact: MEDIUM)
**What:** Below the `weeklyPrompt` coaching card in PersonDetailView, add a
collapsed "Your reflections" row showing count of `Encounter` records with
`kind == .note` or where the encounter note is non-empty. One-tap expands to
a lightweight journal-style list. This gives Riley visible proof that the app
is accumulating relationship intelligence over time.
**Why:** New users have no social proof that the app is "working." A visible,
growing journal of interactions creates the streak / progress feeling that
drives retention.
**File:** `Sources/MeetingScribe/People/PersonDetailView.swift`
**Effort:** S | **Impact:** Medium — directly addresses "what has this app done for me?"
**Deps:** None (encounters already stored).

### U5-10 — Onboarding re-entry point in Settings (S, Impact: LOW-MEDIUM)
**What:** Add a "Revisit setup" button in SettingsView that re-presents
`OnboardingSheet` from step 0. Also add a "What can MeetingScribe do?" help
card in TodayView's empty state that shows the features overview.
**Why:** Riley may close onboarding quickly the first time and miss the
relationship coach angle entirely. A re-entry path in Settings costs one line.
**File:** `Sources/MeetingScribe/UI/SettingsView.swift`, `TodayView.swift`
**Effort:** S | **Impact:** Low-Medium.
**Deps:** None.

---

## Top 3 Picks

1. **U5-2** — RelationshipType picker in AddPersonSheet. Every other coaching
   feature is predicated on users setting a type at person creation. This is
   the structural unlock.

2. **U5-3** — Wire `weeklyPrompt` into PersonDetailView. The prompts are
   written, correct, and compelling. Connecting them to UI is 30 lines.
   This is the only tangible "AI coaching" moment Riley can experience today.

3. **U5-1** — Value onboarding step. The marketing promise is "AI relationship
   coach." The onboarding teaches nothing about it. One new screen converts
   permission-grant confusion into intentional first action.

---

## Single Highest-Priority Recommendation

**U5-2 — RelationshipType picker as first field in AddPersonSheet.**

Without it: a new user adds their partner as a nameless CRM contact with no
type, no cadence, no coaching prompts, no notifications, and no StayConnected
surfacing — ever. Every Phase 1–3 feature is inaccessible. This is one SwiftUI
section (~40 lines) and a call to `syncPersonReminders` in `save()`. It is the
cheapest, highest-leverage fix in the entire new-user path.
