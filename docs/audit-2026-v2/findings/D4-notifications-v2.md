# D4 — Notification Design Audit

**Lens:** Are the Phase 2 push notifications well-worded and useful, or will users disable them within 3 days?

---

## Full Audit

### 1. Notification Copy Quality

**Check-in body strings** (`RelationshipNotificationManager.swift:145–153`)

| Relationship type | Title | Body | Rating |
|---|---|---|---|
| romanticPartner | `💑 Check in with {name}` | "How are things between you two?" | **B** — better than generic, slightly clinical. A partner app wouldn't normally feel like a help-desk ticket. |
| familyMember | `👨‍👩‍👧 Check in with {name}` | "Give them a call or send a message." | **D** — pure instruction; no warmth, no specificity. This is the copy most likely to get the permission disabled. |
| closeFriend | `👯 Check in with {name}` | "It might be time for a proper catch-up." | **C** — "might be time" is hedge-y; "proper" is faintly condescending. |
| friend | `🙂 Check in with {name}` | "Drop them a quick note." | **C+** — functional but forgettable. |
| colleague / acquaintance | `🤝/👋 Check in with {name}` | "Log a quick check-in to keep the relationship warm." | **D** — meta (instructs the user to interact with the *app*, not the person). Never tell a human their relationship needs "warming". |

**Birthday strings** (`RelationshipNotificationManager.swift:167–186`)

| Notification | Copy | Rating |
|---|---|---|
| Day-of | "Today is a great day to reach out." | **C** — benign but zero action specificity. |
| Week-before | "Plan something special." | **C-** — command without ideas; "special" is vague pressure. |

All body strings use generic imperative framing. None acknowledge *why* the reminder fired (e.g., "You haven't connected in 14 days"), which removes the context that makes a notification feel earned rather than nagging.

The meeting-notification side (`NotificationManager.swift:97–102`) is far stronger — it includes a synthesized brief as a preamble, adapts based on whether a conference URL is present, and uses clear action verbs. The relationship notifications have no equivalent personalization.

---

### 2. Permission Request Flow

`requestAuthorization()` is called in `MeetingScribeApp.startServices()` (line 200):

```swift
Task { await notifications.requestAuthorization() }
```

This fires on every launch but macOS silently no-ops it after the user has already decided. The onboarding sheet (`OnboardingSheet.swift:251–254`) does include a "Notifications" step with subtitle: `"Notifies you 10 seconds before a calendar meeting starts and offers to join + record."` The bullet list (line 381) lists only meeting-focused use cases — **relationship check-in and birthday reminders are not mentioned at all**. A user who approved notifications for meeting alerts and later receives a "Check in with Mom" banner at 9am will feel confused and reach for the mute button.

---

### 3. Cadence Logic — No Frequency Cap

`effectiveCheckInDays` for `romanticPartner` is `1` (hardcoded in `Person.swift:80`). `syncPersonReminders` (line 58) schedules the next notification for `max(dueDate, now+60s)`. If the user never logs a check-in:

1. Today 9am: notification fires.
2. `syncPersonReminders` reschedules for tomorrow 9am (`repeats: false`).
3. `syncPersonReminders` is only called from `QuickEncounterSheet.saveIfValid` (line 218) — **not on app launch**.
4. If the user launches the app tomorrow without logging anything, the pending notification still fires.

In practice a `romanticPartner` entry fires **every single day** with no ability to silence it short of disabling all notifications or deleting the person. There is no:
- Delivered-notification check (the manager checks `pendingNotificationRequests` only, not delivered)
- User-configurable quiet period
- Minimum gap between check-in notifications of the same type
- Snooze action

---

### 4. "Log check-in" Action Button — No Handler

`RelationshipNotificationManager.swift:30–35` registers a `UNNotificationAction` with identifier `"LOG_NOW"` and `categoryIdentifier = "PERSON_CHECKIN"`. The payload includes `userInfo["personID"]` (line 131).

`NotificationManager.handleAction` in `Sources/MeetingScribe/Notifications/NotificationManager.swift:207–240` handles only:
- `JOIN_AND_RECORD`
- `RECORD_ONLY`
- `RECORD_IMPROMPTU`
- `UNNotificationDefaultActionIdentifier` (body tap)

**`LOG_NOW` is not handled.** The `default: break` at line 237 silently discards it. Tapping "Log check-in" activates the app (`.foreground` flag) but drops the user at whatever view was last open — it does **not** open the person's detail view, does **not** present `QuickEncounterSheet`, and does **not** use the `personID` in the payload. The deep-link infrastructure (`WorkspaceRouter.openPerson`) and the `meetingscribe://person/<id>` URL scheme exist and work; they are simply never invoked from notification taps.

The `RelationshipNotificationManager` is not a `UNUserNotificationCenterDelegate` — the only delegate is `NotificationManager` (line 199), so it would need to forward `LOG_NOW` responses, or a dedicated delegate extension must be added.

---

### 5. Birthday Week-Before Reminder — Never Re-Scheduled

`scheduleBirthdayReminders` (`RelationshipNotificationManager.swift:145–187`):

- `person-birthday-<id>` uses `repeats: true` — fires correctly every year on the birthday.
- `person-birthday-week-<id>` uses a fully-specified year/month/day trigger with `repeats: false` (lines 178–183). It is only scheduled for the *current* year's birthday.

After it fires (or lapses without firing), the notification ID is absent. The guard `if !birthdayPending.contains(where: { $0.identifier == weekBeforeID })` (line 159) will attempt to re-schedule — but the logic at line 165 checks `if let thisYearBd = ..., thisYearBd > now`. If this year's birthday has passed, `nextBdComponents.year = currentYear` resolves to a past date and the guard `weekBefore > now` at line 171 fails silently. The reminder is permanently lost until `syncPersonReminders` runs after the birthday rolls into a future year.

**Concrete failure:** Add a person with a July 1 birthday. Week-before fires June 24. If no check-in is logged before July 1, `syncPersonReminders` next runs after the birthday, finds `thisYearBd < now`, and silently skips scheduling next year's week-before reminder.

---

### 6. `syncPersonReminders` Call-Site Map

| Location | When called | Present? |
|---|---|---|
| `QuickEncounterSheet.saveIfValid` (line 218) | After logging a check-in | YES |
| `MeetingScribeApp.startServices()` | On app launch | **NO** |
| `PersonDetailView.saveIdentityEdit` (line 410) | After editing name/role/company | **NO** |
| `PersonDetailView` — relationship type change (line 561) | After changing `relationshipType` | **NO** |
| `PersonDetailView` — cadence change | After editing `checkInCadenceDays` | **NO** |
| `AddPersonSheet` dismiss (line 146) | After adding a new person | **NO** |

The doc comment at `RelationshipNotificationManager.swift:53` says "Idempotent — safe to call on launch, after saving an encounter, and after editing a person." The implementation contradicts this: only the encounter-save path calls it. A user who adds 10 people and never triggers `QuickEncounterSheet` will receive **zero** relationship notifications.

---

## Existing-Plan Items I Rank Highest

1. **Critical Gap #5** — `syncPersonReminders` not called on launch — highest urgency; the notification system is effectively inert for new users until they log their first encounter.
2. **Critical Gap — LOG_NOW handler** — every "Log check-in" action tap silently fails; it's a broken affordance visible to 100% of users who engage with the notification.
3. **Critical Gap #6** — Two `Encounter.Kind` enums — affects whether encounters sync correctly, which affects `lastInteractionAt`, which drives cadence calculations underlying all notifications.

---

## Net-New Recommendations

### D4-1 — Contextual copy: include days-since-contact in notification body
**What:** Replace the static body strings with a format naming the gap: `"Last connected 18 days ago — longer than your usual 14."` Pass `lastInteractionAt` and `effectiveCheckInDays` into `scheduleCheckIn` and compute a human-readable gap string at schedule time.
**Why:** Notifications that explain *why they fired* have materially lower dismissal rates. The user's brain responds to a specific number ("18 days") rather than a vague prompt ("a while").
**User value:** Shifts the notification from "app nag" to "personal context". Users stop disabling check-in alerts.
**Effort:** S
**Impact:** High — directly affects 7-day notification-permission retention rate.
**Deps:** None; purely copy + minor data plumbing.

### D4-2 — Wire LOG_NOW → QuickEncounterSheet for the person
**What:** In `NotificationManager.handleAction`, add a `case RelationshipNotificationManager.actionLogNow` branch. Extract `personID` from `userInfo`, call `router.openPerson(personID)`, and post a `.meetingScribeOpenQuickEncounter` notification that `PeopleListView` or `PersonDetailView` observes to auto-present `QuickEncounterSheet`.
**Why:** Currently 100% of "Log check-in" taps land nowhere meaningful. The entire Phase 2 habit loop depends on this working.
**User value:** Tap notification → log check-in in 5 seconds. Without this, the action button is decoration.
**Effort:** S
**Impact:** Critical — enables the primary engagement loop.
**Deps:** `WorkspaceRouter.openPerson` already exists; only the notification routing and sheet-presentation observer are missing.

### D4-3 — Add a per-person notification frequency floor
**What:** Add a minimum gap check before scheduling: use `center.deliveredNotifications()` to detect whether an unactioned check-in notification was delivered in the last N days (where N = `max(1, effectiveCheckInDays)`). If so, skip rescheduling.
**Why:** A `romanticPartner` entry currently fires daily forever with no cap. Daily push notifications from a productivity app reliably trigger the "Mute" response within 3–5 days for most users. A daily partner reminder also carries a patronizing tone — it implies the user can't remember to talk to their own partner.
**User value:** Prevents notification fatigue; keeps the permission alive for when it matters.
**Effort:** S
**Impact:** High — notification permission survival rate.
**Deps:** None.

### D4-4 — Announce relationship notifications explicitly in onboarding
**What:** Extend the `OnboardingSheet` notifications bullet list (`OnboardingSheet.swift:381`) to include: `"Check-in reminders when you haven't connected with someone in a while"` and `"Birthday reminders 7 days in advance"`. Add a contextual inline prompt when the user first assigns any non-`.unset` `RelationshipType`.
**Why:** The permission was granted for meeting alerts. Relationship reminders arriving later with no prior context feel like scope creep — users who are surprised revoke permissions.
**User value:** Informed consent → higher long-term permission retention.
**Effort:** S
**Impact:** Medium
**Deps:** None.

### D4-5 — Fix birthday week-before re-scheduling for next year
**What:** In `scheduleBirthdayReminders`, after computing `nextBdComponents`, try current year first; if `thisYearBd <= now`, increment year by 1 before computing `weekBefore`. Remove the existing `ID already pending` guard and instead compare the scheduled year against the upcoming birthday year so stale single-year triggers get replaced.
**Why:** As audited in §5, the week-before reminder disappears permanently once the birthday passes without a `syncPersonReminders` call.
**User value:** Birthday reminders actually repeat annually. A missed birthday notification is a relationship harm.
**Effort:** S
**Impact:** High for user trust; low engineering cost.
**Deps:** None.

### D4-6 — Call `syncPersonReminders` from all mutation paths
**What:** Add `Task { await RelationshipNotificationManager.shared.syncPersonReminders(people: people.people) }` to: (a) `AddPersonSheet` on dismiss with a saved person, (b) `PersonDetailView.saveIdentityEdit` (line 410), (c) all `people.updatePerson(updated)` call sites in `PersonDetailView` that change `relationshipType` or `checkInCadenceDays` (lines 561, 634, 640, 690, 696), and (d) `MeetingScribeApp.startServices()`.
**Why:** As mapped in §6, notifications only activate after the user's first encounter log. A new user who adds 10 people with relationship types set sees zero notifications.
**User value:** Notifications work from the moment a person is configured.
**Effort:** S
**Impact:** High — correctness fix.
**Deps:** None; the function is idempotent.

### D4-7 — Snooze action on check-in notifications
**What:** Add a second `UNNotificationAction` with identifier `"SNOOZE_3_DAYS"` to the `PERSON_CHECKIN` category. In the action handler, reschedule the notification `3 * 86400` seconds from now.
**Why:** "Dismiss" permanently discards. "Log check-in" (broken) is the only alternative. Users who intend to reach out but not right now have no recourse — so they dismiss, the cadence breaks down, and the relationship coaching feature silently dies.
**User value:** Graceful deferral preserves the habit loop without forcing an immediate log.
**Effort:** S–M
**Impact:** Medium
**Deps:** D4-2 (wire LOG_NOW first so users understand "Log" vs "Snooze").

### D4-8 — Per-relationship-type notification time preferences
**What:** Allow the user to set a preferred delivery time per `RelationshipType` in Settings (e.g., partner reminders at 8pm, colleague reminders at 10am). Currently all notifications fire at 9am regardless of relationship type.
**Why:** A partner check-in at 9am Tuesday is awkward if the person is at work. A colleague reminder at 9pm Saturday is intrusive. Time-of-day is one of the most-cited reasons users disable notifications from relationship/wellness apps.
**User value:** Notifications arrive at contextually appropriate times.
**Effort:** M
**Impact:** Medium-High
**Deps:** None.

### D4-9 — Rich notification subtitle with last-encounter context
**What:** For top-tier relationship types (romanticPartner, familyMember, closeFriend), add a `subtitle` with the most recent encounter kind and date: `"Last: ☕️ Coffee · 3 weeks ago"`. This mirrors the meeting-notification pattern that includes a synthesized brief snippet.
**Why:** Meeting notifications include a brief preamble (`NotificationManager.swift:97–102`). Relationship notifications have no equivalent. A subtitle with concrete context anchors the notification to lived experience rather than abstract obligation.
**User value:** Makes the notification feel personal rather than robotic.
**Effort:** S (requires passing last-encounter data into `scheduleCheckIn`)
**Impact:** Medium
**Deps:** D4-1 (share the data-plumbing work).

### D4-10 — Notification settings screen for relationship reminders
**What:** Add a "Relationship Reminders" section to `SettingsView` with: global on/off toggle, quiet-hours window, and a list of which people currently have pending notifications. Also respect macOS Focus modes by checking `UNUserNotificationCenter.current().notificationSettings()` before scheduling.
**Why:** Currently the only way to silence relationship notifications is to disable all app notifications in System Settings or set every person's type to `.unset`. Neither is acceptable. Power users need fine-grained control or they nuke the permission entirely.
**User value:** Opt-down without full opt-out preserves the feature for engaged users.
**Effort:** M
**Impact:** Medium
**Deps:** D4-3 (frequency floor), D4-8 (time prefs).

---

## Top 3 Picks

1. **D4-2** (Wire LOG_NOW → QuickEncounterSheet) — the core habit loop is broken without it. S effort, critical impact.
2. **D4-1** (Contextual days-since copy) — directly reduces the notification disable rate. S effort.
3. **D4-6** (Call syncPersonReminders from all mutation paths) — correctness fix; the entire notification system is inert for users who haven't yet logged an encounter.

## Single Highest-Priority Recommendation

**D4-2.** Every "Log check-in" action button tap silently fails. The habit loop MeetingScribe is selling — notification → one-tap log → reschedule — has a broken link at the most critical step. This is not a polish issue; it is a product promise that is demonstrably not delivered. Fix the handler first, then improve the copy.
