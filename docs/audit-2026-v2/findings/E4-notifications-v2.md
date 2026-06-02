# E4 — Notification System Reliability Audit

**Lens:** Will `RelationshipNotificationManager` correctly schedule and fire notifications in production?

---

## Full-App Audit Through This Lens

### Check 1 — Deduplication with no rescheduling path (CRITICAL BUG)

`scheduleCheckIn` (`RelationshipNotificationManager.swift:124–125`):

```swift
let pending = await center.pendingNotificationRequests()
if pending.contains(where: { $0.identifier == id }) { return }
```

This is a hard early-return with **no fire-date comparison**. If a check-in notification was scheduled two weeks ago for a due date that has since been invalidated (e.g., the user just logged an encounter that pushes the cadence 30 days forward), the stale notification **will fire on the original date and is never updated**. The function is documented as "Idempotent — safe to call on launch, after saving an encounter, and after editing a person" but that comment is false: idempotency should mean "calling it twice produces the same correct outcome," not "calling it twice produces the same stale outcome."

**Rescheduling path:** There is none. `syncPersonReminders` (`line 110`) cancels check-in notifications only for people whose `relationshipType` was reset to `.unset`. It does not cancel and re-add for people whose cadence or last-interaction date changed. The correct fix is to remove the pending notification before re-adding whenever the fire date differs by more than a configurable tolerance (e.g., >1 hour), or unconditionally remove-then-add inside `syncPersonReminders` before calling `scheduleCheckIn`.

### Check 2 — `@preconcurrency import UserNotifications`

The annotation is present at `RelationshipNotificationManager.swift:2` and is functionally necessary. The `registerCategories` method (`lines 38–45`) calls `getNotificationCategories(completionHandler:)`, whose callback runs on an **unspecified queue** — not the `@MainActor` the class is isolated to. Inside that callback, `updated.insert(cat)` and `setNotificationCategories(updated)` execute off-main-actor. Without `@preconcurrency`, the compiler would emit `Sendable` conformance warnings for `UNNotificationCategory`. The annotation suppresses these warnings correctly; it does not introduce unsafety here because `UNUserNotificationCenter` methods are themselves thread-safe. This is the right choice under Swift 5.10 before full concurrency checking is enabled — no action required.

### Check 3 — `registerCategories()` thread-safety

The get-then-set pattern (`lines 38–45`):

```swift
UNUserNotificationCenter.current().getNotificationCategories { existing in
    var updated = existing
    updated.insert(cat)
    UNUserNotificationCenter.current().setNotificationCategories(updated)
}
```

**There is a race condition.** If `registerCategories` is called concurrently from both `NotificationManager.init()` and `RelationshipNotificationManager.init()` (or if any code path calls `NotificationManager.registerCategories` a second time), the following interleaving is possible:

1. `NotificationManager.registerCategories` calls `setNotificationCategories([meetingCat, impCat])` — overwrites.
2. `RelationshipNotificationManager.registerCategories` calls `getNotificationCategories` — gets `[meetingCat, impCat]`.
3. `RelationshipNotificationManager.registerCategories` calls `setNotificationCategories([meetingCat, impCat, PERSON_CHECKIN])` — correct state.

So far harmless because `NotificationManager` is a `@StateObject` initialized at launch and `RelationshipNotificationManager.shared` is a lazy static initialized on first access from `QuickEncounterSheet` (always after app startup). **However**, `NotificationManager.registerCategories` (`Notifications/NotificationManager.swift:71`) calls `setNotificationCategories([meetingCat, impCat])` — it does NOT use the get-then-set pattern. If anything calls `registerCategories` on `NotificationManager` a second time after `RelationshipNotificationManager.shared` has been initialized, `PERSON_CHECKIN` will be silently deleted and all "Log check-in" action buttons will stop appearing. Currently no second-call path exists, but the fragility is real: any future "re-register on foreground" logic would trigger it.

**Additional deregistration bug:** When `PeopleStore.deletePerson` is called (`PeopleStore.swift:514`), it correctly cleans up files and database rows but **never cancels `person-birthday-<id>` (which repeats annually) or `person-birthday-week-<id>` or `person-checkin-<id>`**. A deleted person's birthday notification will fire every year indefinitely. The cleanup at `syncPersonReminders:113` only removes `person-checkin-*` IDs for non-`.unset` people; there is no cleanup pass for birthday notifications at all.

### Check 4 — Birthday week-before: never re-scheduled for next year

`scheduleBirthdayReminders` (`lines 181–205`):

The day-of notification uses `repeats: true` with month+day components — this fires annually by the OS and needs no re-scheduling. Correct.

The week-before notification uses a **fully-qualified year/month/day/hour/minute trigger with `repeats: false`** (lines 178–183). It is only ever scheduled for the current calendar year. After it fires (or after the birthday passes without `syncPersonReminders` running), the notification is absent from pending requests. On the next call to `syncPersonReminders`, the outer guard `if !birthdayPending.contains(where: { $0.identifier == weekBeforeID })` returns `true` (not pending), so the code enters the scheduling block — but then:

```swift
nextBdComponents.year = currentYear          // e.g., 2026
if let thisYearBd = cal.date(from: nextBdComponents), thisYearBd > now {
```

If today is July 5 and the birthday is July 1, `thisYearBd` (July 1, 2026) is in the past — the guard fails silently and **no `person-birthday-week-<id>` is ever scheduled for 2027**. The reminder is permanently lost until `syncPersonReminders` happens to run before June 24, 2027, which requires the user to log an encounter between those dates.

**Second structural bug:** `scheduleBirthdayReminders` is called from inside the `guard dueDate <= horizon else { continue }` block (`line 103`). For a person just checked in (cadence = 30 days, due date = 30 days away), the horizon guard fires `continue` and `scheduleBirthdayReminders` is **never called at all**. Birthday reminders are only ever scheduled as a side effect of check-in scheduling, and only when the check-in is due within 7 days. A person with a birthday next month whose cadence puts their check-in 3 months away will never get a birthday reminder scheduled.

### Check 5 — `UNCalendarNotificationTrigger(repeats: true)` for birthday-day

The trigger uses `.month` + `.day` components only (line 166), which is the documented pattern for annual repeats. macOS will correctly fire this every year on the birthday at 9am. The OS handles year rollover. This part is correct.

### Check 6 — `syncPersonReminders` call-site map

| Call site | When | Present? |
|---|---|---|
| `QuickEncounterSheet.saveIfValid` (`line 218`) | After logging an encounter | YES |
| `MeetingScribeApp.startServices()` | App launch | **NO** |
| `AddPersonSheet` on dismiss | After adding a new person with relationship type | **NO** |
| `PersonDetailView.saveIdentityEdit` | After editing name/role | **NO** |
| `PersonDetailView` — `relationshipType` change | After changing relationship type | **NO** |
| `PersonDetailView` — `checkInCadenceDays` change | After changing cadence | **NO** |
| `PeopleStore.deletePerson` | Cleanup on person deletion | **NO** |

The doc-comment says the function is "safe to call on launch, after saving an encounter, and after editing a person" — only the encounter-save path is wired. A brand-new user who adds 10 people and never opens `QuickEncounterSheet` will receive **zero relationship notifications**. This was identified in the briefing as Critical Gap #5 and independently confirmed by D4 with specific line numbers.

---

## Existing-Plan Items I Rank Highest

1. **Critical Gap #5 — `syncPersonReminders` not called on launch.** The entire notification system is inert until the user logs their first encounter. Fix: call `Task { await RelationshipNotificationManager.shared.syncPersonReminders(people: PeopleStore.shared.people) }` from `MeetingScribeApp.startServices()`.

2. **D4-5 (endorsed) — Birthday week-before re-scheduling.** The one-shot trigger is permanently lost after the birthday passes. The fix requires checking `thisYearBd <= now` and incrementing year by 1 when true.

3. **D4-2 (endorsed) — Wire LOG_NOW → QuickEncounterSheet.** The action identifier is registered but never handled; `NotificationManager.handleAction` falls through to `default: break`. This is a broken product promise: the primary CTA on every check-in notification does nothing.

4. **D4-6 (endorsed) — Call `syncPersonReminders` from all mutation paths.** `AddPersonSheet`, `PersonDetailView` (type/cadence changes), and `PeopleStore.deletePerson` are all missing calls. Ranked just below launch-call because the launch call is the highest-leverage single fix.

---

## Net-New Recommendations

### E4-1 — Remove-then-re-add in `scheduleCheckIn` to fix stale fire dates

**What:** In `scheduleCheckIn`, before the early-return guard, compare the pending trigger's next-fire date against the computed `fireDate`. If they differ by more than 30 minutes, call `center.removePendingNotificationRequests(withIdentifiers: [id])` and proceed to schedule. Alternatively, remove unconditionally at the top of `scheduleCheckIn` (the function is only called from within `syncPersonReminders` which already owns the pending-requests array in `wantedIDs`).

**Why:** After a user logs an encounter, the cadence should push the next notification forward. Currently it does not — the pre-existing stale notification fires on the original date. This is the central reliability promise of the check-in system.

**User value:** Notifications reflect reality. Logging an encounter stops the old notification from firing as if no encounter happened.

**Effort:** S

**Impact:** High — correctness; the deduplication comment is currently a lie.

**Deps:** None.

---

### E4-2 — Cancel birthday and check-in notifications on `PeopleStore.deletePerson`

**What:** Add a cleanup call in `PeopleStore.deletePerson` (`PeopleStore.swift:514`) before the existing cleanup code:

```swift
let ids = [
    "person-checkin-\(person.id)",
    "person-birthday-\(person.id)",
    "person-birthday-week-\(person.id)"
]
UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
```

**Why:** Currently, deleting a person leaves `person-birthday-<id>` with `repeats: true` in the OS notification queue. It will fire every year on their birthday indefinitely. On macOS this notification will appear with a stale person name even after the person is gone.

**User value:** Prevents ghost notifications for deleted people — a confusing and embarrassing production defect.

**Effort:** S

**Impact:** Medium-High — correctness and trust.

**Deps:** None.

---

### E4-3 — Decouple `scheduleBirthdayReminders` from check-in horizon guard

**What:** Move the `scheduleBirthdayReminders` call outside and after the `guard dueDate <= horizon else { continue }` block. Birthday scheduling should happen for all people with a non-nil `birthday` and non-`.unset` `relationshipType`, regardless of when their check-in is due.

**Why:** Currently birthday notifications are only ever scheduled as a side effect of a check-in being due within 7 days (`RelationshipNotificationManager.swift:80`). A person checked in recently (cadence = 30 days) will have their birthday notification scheduling skipped entirely until they become due for a check-in.

**User value:** Birthday notifications actually work for all people, not just those who happen to be overdue for a check-in.

**Effort:** S — a three-line restructuring of the loop body.

**Impact:** High — birthday notifications are a flagship feature; this silently disables them for ~80% of people at any given time.

**Deps:** None.

---

### E4-4 — Fix `NotificationManager.registerCategories` to use get-then-set (prevent PERSON_CHECKIN wipeout)

**What:** Change `NotificationManager.registerCategories` (`Notifications/NotificationManager.swift:48–71`) to use the same get-then-set pattern as `RelationshipNotificationManager.registerCategories`: call `getNotificationCategories`, insert the meeting and impromptu categories into the existing set, then call `setNotificationCategories`. This makes both managers mutually safe regardless of initialization order or re-registration.

**Why:** `NotificationManager.registerCategories` currently calls `setNotificationCategories([meetingCat, impCat])` — a hard overwrite. If this is ever called after `RelationshipNotificationManager.shared` has been initialized, `PERSON_CHECKIN` is silently deleted. The action button vanishes for all pending check-in notifications. This is a latent fragility that will be triggered if any future "re-register on app-foreground" logic is added.

**User value:** Defensive hardening; prevents a future regression that would silently kill the check-in action button.

**Effort:** S

**Impact:** Medium — latent bug; not currently triggering in production but will if `registerCategories` is ever called twice.

**Deps:** None.

---

### E4-5 — Use `center.deliveredNotifications()` in deduplication to prevent already-fired re-scheduling

**What:** In `scheduleCheckIn`, also check `center.deliveredNotifications()` for the identifier before re-scheduling. If a check-in was delivered (fired) but the user hasn't logged anything, the current code will re-schedule it correctly (since it's no longer pending). But once re-scheduled with the same date math, it will fire again almost immediately (tomorrow 9am). Add a grace period: if a delivered notification for this ID exists and was delivered within the last `effectiveCheckInDays / 2` days, skip re-scheduling until that window passes.

**Why:** The current code checks only `pendingNotificationRequests`. After a notification fires it moves to `deliveredNotifications`. The next call to `syncPersonReminders` (e.g., on next app launch) sees the notification as absent and re-schedules it for tomorrow 9am. For a `romanticPartner` with cadence=1, this creates a daily re-fire loop even after the user has seen and dismissed the notification.

**User value:** Reduces notification fatigue; prevents the same check-in prompt from firing every day indefinitely.

**Effort:** S

**Impact:** High for `romanticPartner` and other high-cadence relationship types.

**Deps:** None; builds on E4-1 (both address deduplication).

---

### E4-6 — Add `syncPersonReminders` call to `PeopleStore.updatePerson` for relevant field changes

**What:** In `PeopleStore.updatePerson` (or at the call sites in `PersonDetailView` that change `relationshipType` or `checkInCadenceDays`), add:

```swift
if old.relationshipType != new.relationshipType || old.checkInCadenceDays != new.checkInCadenceDays {
    Task { @MainActor in
        await RelationshipNotificationManager.shared.syncPersonReminders(people: self.people)
    }
}
```

**Why:** Changing a person's relationship type (e.g., `colleague` → `closeFriend`) immediately changes `effectiveCheckInDays` from 30 to 7 — but the pending notification won't reflect this until E4-1 (remove-then-re-add) is also implemented. This call is the trigger; E4-1 is the mechanism that makes it effective.

**User value:** Relationship type changes take effect immediately in the notification schedule.

**Effort:** S

**Impact:** Medium — correctness for edit flows.

**Deps:** E4-1 (without the stale-notification fix, this call doesn't help).

---

### E4-7 — Weekly background refresh via `BGAppRefreshTask` to keep week-before birthday current

**What:** Register a `BGAppRefreshTask` (or use macOS's equivalent background execution) that calls `syncPersonReminders` once a week. This ensures the one-shot week-before birthday trigger is rescheduled for the next year even if the user doesn't open the app between birthdays.

**Why:** Even after fixing E4-3 (birthday/horizon decoupling) and E4-4 (year-rollover fix for week-before), `syncPersonReminders` is only called when the user actively uses the app. If no encounters are logged and the app is not opened in the week before a birthday, the week-before notification never fires. macOS's `NSBackgroundActivityScheduler` provides a lightweight path that doesn't require a separate daemon.

**User value:** Birthday reminders are reliable even for infrequent app users — the exact users who need the reminder most.

**Effort:** M

**Impact:** High for user trust; birthday misses are relationship harms.

**Deps:** E4-3 (fix horizon coupling first), Critical Gap #5 (launch call).

---

### E4-8 — Notification delivery receipt via `UNUserNotificationCenterDelegate.didReceive` to trigger reschedule

**What:** In `NotificationManager.handleAction`, for the `UNNotificationDefaultActionIdentifier` case, check if the notification category is `PERSON_CHECKIN`. If so, call `syncPersonReminders` after removing the delivered notification. This closes the loop: notification fires → user taps body → `syncPersonReminders` runs → new notification scheduled for correct future date.

**Why:** Currently `syncPersonReminders` is not called when a notification is tapped (only when an encounter is explicitly logged). If the user taps the notification body (opens the app) but doesn't log an encounter, the notification will re-fire the next time `syncPersonReminders` runs — likely the next time they log an encounter, which could be weeks later. Meanwhile, the user saw a check-in prompt and took no action but the system has no way to reschedule intelligently.

**User value:** Tapping a check-in notification resets the clock without requiring a full encounter log.

**Effort:** S

**Impact:** Medium — improves notification lifecycle management.

**Deps:** Critical Gap #5 (launch call must exist so reschedule has an effect).

---

## Top 3 Picks

1. **E4-1** (Remove-then-re-add to fix stale fire dates) — the deduplication early-return makes `syncPersonReminders` idempotent in the wrong direction; logging an encounter has no effect on a pending notification. S effort, critical correctness.

2. **E4-3** (Decouple `scheduleBirthdayReminders` from check-in horizon) — birthday notifications are silently never scheduled for ~80% of people at any given time. The fix is a three-line restructure.

3. **E4-2** (Cancel birthday notifications on person delete) — a `repeats:true` annual trigger is permanently left in the OS queue when a person is deleted. This will cause ghost notifications years into the future.

## Single Highest-Priority Recommendation

**E4-1.** The deduplication guard at `scheduleCheckIn:124–125` makes the entire sync function a no-op for any person who already has a pending notification. This directly contradicts the doc-comment claim of idempotency and means that logging an encounter — the primary user action in the coaching loop — does not update the next-fire date. Fix this first: compare the existing trigger's nextTriggerDate against the computed fireDate and remove-then-re-add when they differ. Without this fix, every other improvement to call sites and scheduling logic is undermined by notifications that never update.
