# U2 — User Scenario: Maria, Family-Centric User

**Lens:** A 45-year-old user with 6 family members. Tests the filter bar, StayConnectedSection cap, birthday reminders, quick-log, notification volume, and cadence editing.

---

## Step 1 — Does the "Family" filter chip appear?

**Actual behavior:** Probably not — and definitely not on a fresh install.

`PeopleListView.presentTypes` (`PeopleListView.swift:54–57`) computes which relationship types exist in the people list, excluding `.unset`:

```swift
private var presentTypes: [RelationshipType] {
    let used = Set(people.people.map(\.relationshipType)).subtracting([.unset])
    return RelationshipType.allCases.filter { used.contains($0) }
}
```

The chip bar only renders at all when `presentTypes.count > 1` (`PeopleListView.swift:244`). For the filter bar to show a "Family" chip, Maria must have already opened PersonDetailView for each family member and manually set the type via the relationship-type menu — because `AddPersonSheet` (`AddPersonSheet.swift`) has **no `relationshipType` field**. Every person added via "+ Add Person" defaults to `.unset`.

If Maria has all 6 family members with `relationshipType == .unset`, `presentTypes` is empty, the bar is invisible, and the filter doesn't exist at all. Even if she has diligently tagged all 6, the bar only appears if she also has at least one *other* type present (the `count > 1` guard). Six family members all set to `.familyMember`, with no other types, still gives `presentTypes.count == 1` — **the bar remains hidden**.

**Desired behavior:** The filter bar should appear whenever at least one person has a typed relationship. The guard should be `presentTypes.count >= 1`, not `> 1`. Additionally, `AddPersonSheet` should expose a relationship-type picker so the default is meaningful, not `.unset`.

**Files/lines:** `PeopleListView.swift:54–57` (presentTypes), `PeopleListView.swift:244` (guard), `AddPersonSheet.swift` (no relationshipType field — confirmed by grep).

---

## Step 2 — How does Maria find the other 3 overdue family members?

**Actual behavior:** She can't see them from TodayView. She has to go looking.

`StayConnectedSection.overdueRelationships` (`StayConnectedSection.swift:17–22`) hard-caps at `.prefix(3)`:

```swift
private var overdueRelationships: [Person] {
    people.people
        .filter { $0.relationshipType != .unset }
        .filter { isOverdue($0) }
        .sorted { overdueDays($0) > overdueDays($1) }
        .prefix(3)
        .map { $0 }
}
```

The section shows a heading ("Stay connected") and up to 3 cards — period. There is no "and 3 more" overflow indicator, no "See all" link, no count badge on the section title. The 3 most-overdue people are shown; the other 3 are invisible in TodayView.

To find them Maria must navigate to People → manually inspect each person's detail, or notice the filter chips (if they are even visible — see Step 1). Neither path is obvious.

**Desired behavior:** A footer row like "3 more overdue — see all →" that deep-links to PeopleListView filtered to overdue people. Or raise the cap to 5 with a scroll container. Either way, the section should never silently discard overdue relationships.

**Files/lines:** `StayConnectedSection.swift:17–22` (prefix cap), `StayConnectedSection.swift:35–95` (no overflow indicator).

---

## Step 3 — Does Maria get a birthday reminder for her mom's birthday in 2 weeks?

**Actual behavior:** Almost certainly no — and the path to "yes" has two independent blockers.

**Blocker A — syncPersonReminders is never called on launch.**

`RelationshipNotificationManager.syncPersonReminders()` is only called from one place in the entire codebase: `QuickEncounterSheet.saveIfValid()` (`QuickEncounterSheet.swift:218`). It is **never called on app launch**. This is a known gap (Briefing critical gap #5). If Maria hasn't logged a check-in since installing the new version, `syncPersonReminders` has never run, so zero birthday notifications have been scheduled.

**Blocker B — birthday scheduling is gated behind the 7-day check-in horizon.**

Even if `syncPersonReminders` *does* run, `scheduleBirthdayReminders` is only called *inside the loop body*, and only *after* the check-in horizon guard passes:

```swift
// Only schedule if overdue or due within the next 7 days.
let horizon = Date().addingTimeInterval(7 * 86400)
guard dueDate <= horizon else { continue }
// ...
await scheduleBirthdayReminders(for: person, center: center)
```

(`RelationshipNotificationManager.swift:78–80, 106`)

With `familyMember.defaultCheckInDays = 7`, if Maria's mom was contacted in the past week (i.e., not yet overdue), `dueDate` is in the future beyond the 7-day horizon, the `guard` executes `continue`, and `scheduleBirthdayReminders` is **never reached**. A mom who is up-to-date on check-ins gets her birthday reminder silently dropped. Her birthday is 2 weeks out — the `person-birthday-week-<id>` reminder fires 7 days before the birthday, which is 7 days from now. That is within range to schedule, but the guard prevents reaching the scheduling call unless the check-in is also overdue.

**Desired behavior:** Birthday scheduling should be unconditional — pulled out of the check-in loop entirely, or called outside the `guard dueDate <= horizon` block. The week-before reminder fires 7 days out and represents a different cadence from check-ins.

**Files/lines:** `RelationshipNotificationManager.swift:78–80` (horizon guard), `RelationshipNotificationManager.swift:106` (birthday call inside guard scope), `QuickEncounterSheet.swift:218` (only call site for syncPersonReminders).

---

## Step 4 — Can Maria log a check-in from the overdue card? Does it reschedule?

**Actual behavior:** Logging works. Rescheduling also works — with a caveat about deduplication.

The "Log" button in `StayConnectedSection` (`StayConnectedSection.swift:70–77`) sets `quickLogTarget = person`, which triggers a `.sheet(item:)` presenting `QuickEncounterSheet` (`StayConnectedSection.swift:97–101`).

`QuickEncounterSheet.saveIfValid()` (`QuickEncounterSheet.swift:207–220`):
1. Calls `people.addEncounter(to: person.id, ...)` — this updates `lastInteractionAt`.
2. Calls `RelationshipNotificationManager.shared.syncPersonReminders(people: people.people)` in a `Task { @MainActor in ... }`.

The reschedule does happen. **However:** `scheduleCheckIn` (`RelationshipNotificationManager.swift:119–135`) deduplicates before scheduling — it returns early if a pending notification for that ID already exists:

```swift
let pending = await center.pendingNotificationRequests()
if pending.contains(where: { $0.identifier == id }) { return }
```

This means if there is an *existing* overdue notification for mom already in the pending queue, it will NOT be replaced with a new one reflecting the updated `lastInteractionAt`. The old stale notification sits in the queue. The correct behavior after a check-in is to *remove* the old notification and schedule a fresh one, but `scheduleCheckIn` only skips if already pending; it never cancels-and-replaces.

**Desired behavior:** After `addEncounter`, the specific `person-checkin-<id>` notification should be explicitly removed before rescheduling. Add `center.removePendingNotificationRequests(withIdentifiers: [id])` before the `add` call in `scheduleCheckIn`, or in `syncPersonReminders` before calling it.

**Files/lines:** `StayConnectedSection.swift:97–101` (sheet), `QuickEncounterSheet.swift:207–220` (saveIfValid + reschedule call), `RelationshipNotificationManager.swift:119–122` (dedup guard that prevents re-scheduling).

---

## Step 5 — 6 family members at 7-day cadence: how many notifications per week? Is there a cap?

**Actual behavior:** Up to 6 notifications per week — and there is no frequency cap anywhere in the code.

`familyMember.defaultCheckInDays = 7` (`Person.swift:81`). Six family members, all at a 7-day cadence, each get their own `person-checkin-<id>` notification scheduled independently. `syncPersonReminders` loops over all people without any batching or rate-limiting logic (`RelationshipNotificationManager.swift:65–113`). There is no global cap on how many check-in notifications can fire per day, per week, or per person-type.

Additionally, `FeatureGate.unlimitedCheckIns` is defined in `FeatureGate.swift:19` (comment: "Free tier: 3 people with reminders") and `isEnabled(.unlimitedCheckIns)` returns `false` for non-Pro users, but **`RelationshipNotificationManager.syncPersonReminders` never consults `FeatureGate`**. The gate exists in the enum but is never enforced — in production (non-DEBUG), a free user would get 6 weekly notifications even though the design intent was to cap at 3.

**Desired behavior:** Either enforce the `unlimitedCheckIns` gate in `syncPersonReminders` (limit reminders to 3 people for free users), or add a daily/weekly notification budget. Six notifications per week from one app is aggressive and will trigger macOS Focus filter suppression or prompt the user to revoke notification permission.

**Files/lines:** `Person.swift:81` (defaultCheckInDays = 7), `RelationshipNotificationManager.swift:65–113` (no cap in loop), `FeatureGate.swift:19,75` (unlimitedCheckIns gate defined but not enforced in notification manager).

---

## Step 6 — Does editing checkInCadenceDays to 14 reflect in the next notification?

**Actual behavior:** There is no UI to edit `checkInCadenceDays`. Even if it is set programmatically, the next notification will only update if `syncPersonReminders` is called — and the deduplication bug (Step 4) may prevent it.

`Person.checkInCadenceDays: Int?` exists in the model (`Person.swift:209`) and is used in `effectiveCheckInDays` (`Person.swift:212–213`). But a grep across all Swift sources finds zero UI that exposes a Stepper, TextField, or other control bound to `checkInCadenceDays`. `PersonDetailView.swift` only exposes the relationship-type picker (lines 556–585); the "Edit Person" sheet (`AddPersonSheet`) has no cadence field. The field is invisible to users.

Even if a future UI were added and Maria set `checkInCadenceDays = 14`, the notification update path still has the deduplication bug: if `person-checkin-<id>` is already pending (scheduled at the old 7-day date), `scheduleCheckIn` returns early and the stale 7-day notification remains. The fix requires removing the existing notification before rescheduling.

**Desired behavior:** `PersonDetailView` (or its Edit sheet) should expose a "Check-in every N days" Stepper or picker. On save, `syncPersonReminders` should be called after first removing the person's existing check-in notification.

**Files/lines:** `Person.swift:209` (checkInCadenceDays field), `Person.swift:212–213` (effectiveCheckInDays), `PersonDetailView.swift:556–585` (only relationship type is exposed, no cadence control), `RelationshipNotificationManager.swift:119–122` (dedup prevents cadence update).

---

## Summary of Findings

| ID | Issue | Severity | File:Line |
|---|---|---|---|
| U2-1 | Filter bar hidden when only one type present (`count > 1` guard) | High | `PeopleListView.swift:244` |
| U2-2 | No `relationshipType` picker in AddPersonSheet → everyone defaults to `.unset` | High | `AddPersonSheet.swift` (absent) |
| U2-3 | StayConnectedSection caps at 3 with no overflow indicator | Medium | `StayConnectedSection.swift:18` |
| U2-4 | `syncPersonReminders` never called on launch; birthday reminders never scheduled | Critical | `QuickEncounterSheet.swift:218`; `RelationshipNotificationManager.swift` |
| U2-5 | Birthday scheduling inside 7-day check-in horizon guard — skipped for up-to-date contacts | High | `RelationshipNotificationManager.swift:78–80,106` |
| U2-6 | `scheduleCheckIn` dedup prevents re-scheduling after check-in → stale notifications | High | `RelationshipNotificationManager.swift:119–122` |
| U2-7 | `unlimitedCheckIns` FeatureGate never consulted in notification manager | Medium | `FeatureGate.swift:75`; `RelationshipNotificationManager.swift` |
| U2-8 | No UI for `checkInCadenceDays` — field is write-only from user perspective | High | `PersonDetailView.swift:556–585`; `Person.swift:209` |

