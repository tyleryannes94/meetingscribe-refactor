# D2 — Onboarding & First-Run UX Audit (Phase 1–6 Relationship Coaching)

**Lens:** When a user first opens MeetingScribe after the Phase 1–6 update, what do they actually see? Is the new relationship coaching value proposition clear from cold start?

---

## Full-App Audit Through This Lens

### What the existing OnboardingSheet covers (and does not cover)

`OnboardingSheet.swift` is a 5-step permissions wizard (vault location + Microphone, Screen Recording, Calendar, Notifications, Accessibility). It is shown once on first launch via `hasCompletedOnboarding` AppStorage flag (`MainWindow.swift:71,337`). The flow is well-executed for permission grant-rate improvement (cited in its own doc comment as "audit 8.3"). However:

- **No mention of relationship coaching, relationship types, or check-in reminders anywhere in the 5 steps** — not in titles, subtitles, bullet lists, or any screen. The word "relationship" does not appear in `OnboardingSheet.swift`.
- The Notifications permission step (`OnboardingSheet.swift` – `PermissionKind.notifications` subtitle and bullets) describes "10s before a meeting starts" and "Pipeline-finished confirmations". It does NOT mention that notifications are also the delivery channel for relationship check-in reminders — arguably the more compelling, recurring value prop for a daily habit.
- There is no "here's what's new / here's why People matters" screen at any point.

### AddPersonSheet — relationship type field placement

`AddPersonSheet.swift` shows these fields **in order**:
1. Name (auto-focused, `AddPersonSheet.swift:79`)
2. Company + Role (side-by-side)
3. Email (multi-field)
4. Phone (multi-field)
5. Address (multi-field)
6. Favorite things
7. Birthday (toggle + DatePicker)
8. Tags
9. Notes (TextEditor)

**`relationshipType` is entirely absent from `AddPersonSheet.swift`** — it is not a field at all. Despite Phase 1 adding `Person.relationshipType` (`Person.swift`) and the plan specifying a "relationship type picker as the FIRST field," the picker was never integrated into `AddPersonSheet`. Users who add a person manually have no way to set the relationship type from the Add sheet; they must find it elsewhere (presumably `PersonDetailView`, which was not checked here but is likely the only surface that exposes it).

This means the fast path from "install → type set → reminder active" requires at least 3 navigations: Add Person (no type) → navigate to person detail → find and set relationship type → check-in reminder eventually fires.

### TodayView cold start (0 people, 0 meetings)

`TodayView.swift` cold-start path (empty state) shows:
- `emptyState` VStack (`TodayView.swift`, `emptyState` computed property): an icon, "Nothing on today's calendar", "Use a quick action above, or import an existing recording.", and an "Import meeting recording" button.
- `StayConnectedSection` (`TodayView.swift`, inside the `feed` VStack) **only renders if `overdueRelationships` is non-empty** (`StayConnectedSection.swift:21`). On day zero, this section is invisible.
- `SuggestedPeopleView` renders unconditionally (placement: after "On this day" and before `StayConnectedSection`), but its content depends on a running `PeopleStore`.
- **No prompt to add relationships on cold start.** The empty-state copy is entirely meeting-centric. A new user sees zero indication that the People tab exists, let alone that it powers a coaching layer.

### Relationship-coach value prop on cold start

- No banner, tooltip, or callout in `TodayView`, `MainWindow`, or `OnboardingSheet` explains the relationship coaching concept.
- The `StayConnectedSection` and `ReconnectView` are the only coaching surfaces on Today, but both are conditionally rendered (require people with typed relationships and overdue cadences). They are invisible until the user has already completed the very onboarding loop they are supposed to motivate.
- `PeopleListView`'s `emptyState` (`PeopleListView.swift`, `emptyState` computed property) reads "No people yet — Use Add Person or Import above to get started." This is neutral/mechanical, not value-forward.
- The relationship-type filter chips in `PeopleListView` (`relationshipTypeChips`) are **only shown when `presentTypes.count > 1`** — they are invisible to new users.

### Upgrade path for existing users (pre-Phase-1 builds)

- `MeetingScribeApp.swift` and `MainWindow.swift` show no "what's new" sheet or upgrade-aware modal. `hasCompletedOnboarding` is set to `true` for any user who has completed the old onboarding, so they bypass `OnboardingSheet` entirely on upgrade.
- Existing users with pre-Phase-1 person records will have `relationshipType == .unset` on all contacts. Nothing prompts them to classify their existing people.
- The only passive signal is the emoji badge on `PersonRow` (`PeopleListView.swift`, inside `PersonRow.body`) — but it only appears when type is already set, so it creates no discovery pressure for `.unset` people.
- No migration note, banner, or tooltip is shown to help existing users understand the new coaching layer.

### Fast path audit: install → type set → first check-in reminder

Current minimum path (new user, manual):
1. Install + launch → OnboardingSheet (5 steps, no mention of coaching)
2. Close onboarding → TodayView (meeting-centric, no prompt toward People)
3. Navigate to People tab (⌘3 or left-rail click)
4. Click "Add Person" → `AddPersonSheet` (no `relationshipType` field)
5. Save person (type = `.unset`)
6. Re-open person in `PersonDetailView` → locate relationship type picker (location not confirmed)
7. Set type → notifications scheduled by `RelationshipNotificationManager` **only if `syncPersonReminders()` is called** — but per the known gap (briefing item 5), it is only called from `QuickEncounterSheet`, not on app launch
8. Wait for `UNCalendarNotificationTrigger` to fire

Even step 7 is broken if the user never logs a `QuickEncounter` first. There is no guaranteed path from "type set" to "reminder active" without an intermediate encounter log.

---

## Existing-Plan Items I Rank Highest

From the prior master plan (Phases 7–10) and the known gaps list, these matter most through the onboarding lens:

1. **`RelationshipNotificationManager.syncPersonReminders()` not called on app launch (known gap #5)** — this is the single highest-friction gap in the coaching loop. Users who set a type and never log an encounter never get a reminder.
2. **`AddPersonSheet` missing `relationshipType` picker (Phase 1 regression)** — the plan specified first-field placement; it was never built. Every manually-added person defaults to `.unset`.
3. **Phase 10 habit loop improvements** — the prior plan's vague "habit loop" item deserves specificity: the cold-start empty state is purely meeting-oriented and should be relationship-aware.
4. **Phase 8 relationship coach depth** — deeper coaching content only matters if users reach the coached state; fixing discovery is prerequisite.

---

## NET-NEW Recommendations

### D2-1 — Relationship Coaching Step in OnboardingSheet
**What:** Add a new step (step index 1, before permissions) that introduces the "People + coaching" value prop with a 3-bullet pitch: "Remember everyone you care about", "Never miss a check-in — get reminders tuned to each relationship type", "Meeting notes automatically linked to contacts." Include a one-tap "Set up a person now" button that opens `AddPersonSheet` inline (or after dismissal).
**Why:** The onboarding is the highest-leverage moment to set user expectation. Currently it says nothing about the app's most differentiated feature. A single explanatory screen costs ~30 seconds and seeds the "add people" habit at the moment of highest motivation.
**User value:** New user understands the relationship coaching concept on day 1; sets at least one person + type during setup; activates the habit loop immediately.
**Effort:** S (one new `OnboardingSheet` step, one new `PermissionKind`-like screen struct — no new backend).
**Impact:** High. This is a cold-start conversion problem; fixing it has a direct effect on the fraction of users who ever activate the coaching feature.
**Deps:** None; purely additive to `OnboardingSheet.swift`.

### D2-2 — RelationshipType Picker as First Field in AddPersonSheet
**What:** Add a `Picker` or segmented chip row for `RelationshipType` as the **first field** below the name in `AddPersonSheet`, with `.unset` pre-selected and a subtle label like "Relationship type (sets check-in cadence)". The 7-case picker should show emoji + display name. Pre-select `.colleague` when the sheet is opened from a meeting-attendee context (future).
**Why:** Phase 1 built the type model but never surfaced it at person-creation time. Every manually-added person inherits `.unset` indefinitely. The coaching loop is permanently broken for all manual additions until this is fixed.
**User value:** Setting a type at creation time is the natural moment — user is in "who is this person?" mode. The cadence note ("sets check-in cadence") makes the downstream value visible immediately.
**Effort:** S (add `@State private var relationshipType: RelationshipType` to `AddPersonSheet` and wire it to `person.relationshipType` in `save()`; add the picker view).
**Impact:** High. Unblocks the core habit loop for manually-added people.
**Deps:** None.

### D2-3 — Cold-Start Empty State: Relationship-First Prompt on TodayView
**What:** When `people.people.isEmpty` (or `people.people.filter { $0.relationshipType != .unset }.isEmpty`), replace or augment the `emptyState` in `TodayView` with a two-CTA empty state: primary = "Record Meeting" (existing), secondary = "Add a person to stay in touch" (routes to People tab). Include a one-liner: "MeetingScribe tracks your meetings AND your relationships."
**Why:** The current empty state copy ("Nothing on today's calendar") is 100% meeting-oriented. A new user with no calendar integration and no people sees nothing that hints at the relationship coaching capability. The empty state is a discovered every single first launch — it is the highest-impression surface in the cold-start funnel.
**User value:** Dual-track value prop visible on first open; routes user toward People setup without requiring navigation discovery.
**Effort:** S (modify `emptyState` computed var in `TodayView.swift`; add a conditional around existing and new copy).
**Impact:** High.
**Deps:** None.

### D2-4 — Upgrade Banner for Existing Users: "New: Relationship Coaching"
**What:** Add an `AppStorage`-gated "What's New" banner that shows once to users whose `hasCompletedOnboarding == true` and who have `people.people.filter { $0.relationshipType != .unset }.isEmpty`. Banner text: "New in this update: relationship check-in reminders. Tap any person → set a relationship type to activate." Dismissible with a "Got it" button and a "Set up now" button that navigates to People.
**Why:** Existing users who upgrade from pre-Phase-1 will see zero indication that anything changed. None of their people have types set. The coaching loop is permanently dormant unless they happen to open every person and notice a new field.
**User value:** Existing users are informed of the new value prop at the earliest opportunity. Activation rate for the coaching loop in the existing-user cohort increases.
**Effort:** S (new `AppStorage` key `hasSeenRelationshipCoachingIntro`; conditional banner rendered in `TodayView` or `MainWindow`).
**Impact:** High — affects every upgrading user.
**Deps:** None. Can co-exist with D2-1 (D2-1 covers new users; D2-4 covers upgraders).

### D2-5 — CallOnce: syncPersonReminders() on App Launch
**What:** In `MeetingScribeApp.startServices()` (or in `PeopleStore`'s init), call `RelationshipNotificationManager.shared.syncAllReminders()` once per launch, after `PeopleStore` has hydrated. This ensures that any person with a type set — even if they've never logged an encounter — gets their scheduled notification.
**Why:** Known gap #5 from the briefing. Without this, users who: (a) set a type on a person, then (b) never open `QuickEncounterSheet`, will never receive a check-in reminder. The entire cadence system is silently inactive for them.
**User value:** Notification-based habit loop activates reliably after first type-set, not only after first encounter-log.
**Effort:** S (one additional call in `startServices()` with a nil-guard for store readiness).
**Impact:** Very High — this is a correctness bug, not a UX suggestion. It silently breaks the core value prop for the majority of initial users.
**Deps:** `PeopleStore.shared` must be initialized before the call. Already satisfied by the existing store initialization order in `MeetingScribeApp`.

### D2-6 — "Unset" People Classifier: Batch-Set Types for Imported Contacts
**What:** When a user imports contacts (Contacts, Gmail, Calendar attendees), present a post-import screen or a persistent banner in `PeopleListView` that shows the count of `.unset` people and offers a quick-classify flow: show 3–5 imported people at a time with a type picker per row and "Skip" / "Done" controls. This is the mobile-app "relationship onboarding" pattern (e.g., Gem, Clay).
**Why:** Bulk imports — which are the primary path for getting >10 people into the app — result in 100% `.unset` contacts. The coaching loop is dead for all of them until the user manually opens each person. With 200 imported contacts, that is never going to happen organically.
**User value:** After an import, users immediately activate the coaching loop for their most important contacts in 2 minutes instead of 2 months.
**Effort:** M (new `PostImportClassifierSheet` view; triggered from `PeopleImportController` completion callback; stores "has been shown for this import batch" flag).
**Impact:** High. Unblocks coaching for the import-driven use case, which is likely the majority of new users with existing contact lists.
**Deps:** D2-2 (type picker component can be reused).

### D2-7 — PersonRow: Inline "Set type" CTA for Unset People
**What:** In `PersonRow` inside `PeopleListView`, when `person.relationshipType == .unset`, show a faint tertiary chip — "Set type →" — after the name. Tapping it opens a popover with the 7-type picker inline (no full sheet required). On selection, updates `person.relationshipType` in `PeopleStore` and calls `syncPersonReminders()`.
**Why:** Even if D2-2 and D2-6 are shipped, a large pool of `.unset` people will exist from historical imports. This gives the user a zero-friction path to classify people while browsing the list — the discoverability cost is near-zero (they're already in `PeopleListView`).
**User value:** Progressive type-classification as the user naturally browses their people list; no dedicated session required.
**Effort:** S-M (modify `PersonRow`; add a `Popover` with a `Picker`; call `PeopleStore.updatePerson()` + `syncPersonReminders()`).
**Impact:** Medium (incremental improvement over D2-2 and D2-6, but meaningful for reducing the `.unset` backlog).
**Deps:** D2-5 (to ensure reminders are scheduled immediately after type is set inline).

### D2-8 — TodayView: "Stay Connected" Teaser When 0 Overdue but People Exist
**What:** In `StayConnectedSection`, when `overdueRelationships.isEmpty` but there are people with types set (i.e., the user has done the work), show a lightweight "You're all caught up — no check-ins overdue" state instead of rendering nothing. Include the count of typed relationships and a "Log a quick check-in" link.
**Why:** Currently the section disappears entirely when the user is up-to-date. This makes the feature feel broken or absent ("did the reminders break?") rather than celebrating compliance. It also removes the only visible signal that the coaching layer is actively working.
**User value:** Positive reinforcement for users who are maintaining their relationships; reduces confusion about whether the feature is active.
**Effort:** S (add an `else` branch to `StayConnectedSection.body` when `overdueRelationships.isEmpty && typedCount > 0`).
**Impact:** Medium. Retention/habit reinforcement.
**Deps:** None.

### D2-9 — Notifications Permission Step: Mention Relationship Check-Ins
**What:** Update `PermissionKind.notifications.bullets` in `OnboardingSheet.swift` to add: "Relationship check-in reminders — never let a friendship drift." This is a one-line change that makes the notifications step relevant to the coaching use case, not just the meeting use case.
**Why:** Users who deny notifications are opting out of both meeting alerts AND relationship reminders. The current bullets don't mention the relationship dimension at all, so the user has no reason to grant notifications if they don't care about meeting alerts.
**User value:** Higher notification grant rate for users who care about relationship maintenance but are neutral about meeting alerts.
**Effort:** XS (one line change in `OnboardingSheet.swift`).
**Impact:** Medium (multiplied by the fraction of users who read the bullet list before tapping Allow).
**Deps:** None.

### D2-10 — PeopleListView Empty State: Relationship-Forward Copy
**What:** Replace the neutral "No people yet — Use Add Person or Import above to get started" copy in `PeopleListView.emptyState` with value-forward copy: "Your relationship second brain starts here. Add people and set a relationship type to get personalized check-in reminders." Include a prominent "Add Person" button (already available in `actionsRow` but not in `emptyState` itself).
**Why:** The empty state is shown every time a new user navigates to the People tab. The current copy is a mechanical instruction ("use the button above") rather than a value prop. It does nothing to explain WHY adding people is worth doing.
**User value:** Users landing on the People tab for the first time understand the coaching value prop and are more likely to add and classify a person.
**Effort:** XS (modify `emptyState` computed var in `PeopleListView.swift`; add a `Button("Add Person") { showAdd = true }` to the empty state).
**Impact:** Medium.
**Deps:** None.

---

## Top 3 Picks

1. **D2-5 (syncPersonReminders on app launch)** — This is a correctness bug. The coaching loop is silently broken for users who set a type but don't log a QuickEncounter. Fix is trivially small and unblocks everything downstream.
2. **D2-2 (RelationshipType picker in AddPersonSheet)** — Phase 1 intended this and it was never built. Every manually-added person defaults to `.unset`; the coaching loop is permanently dead for manual additions.
3. **D2-1 (Onboarding step for relationship coaching)** — New users have zero exposure to the coaching concept during setup. A single screen at the highest-motivation moment (fresh install) converts the most users into coaching-loop participants.

## Single Highest-Priority Recommendation

**D2-5 — Call `syncPersonReminders()` on app launch.**

It is a one-line fix in `MeetingScribeApp.startServices()` that corrects a silent correctness bug: every user who has set a relationship type but never opened `QuickEncounterSheet` currently receives zero notifications from the coaching system. All other onboarding improvements are moot if the feature doesn't activate after the user completes the setup steps.

