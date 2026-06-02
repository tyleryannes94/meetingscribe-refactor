# P3 — Check-in Habit Loop Audit

**Lens:** Behavioral product design through BJ Fogg's Tiny Habits + Nir Eyal's Hooked model. Sub-lens: will users form a durable daily/weekly check-in habit, or does notification fatigue collapse the loop?

---

## Full Audit — Hooked Model Applied to the Check-in Flow

### 1. Trigger — Notifications Are the Only External Trigger

**External triggers:**
`RelationshipNotificationManager.syncPersonReminders` (`RelationshipNotificationManager.swift:58`) schedules `UNCalendarNotificationTrigger` check-in reminders. This is the **only external trigger** in the system. There is no:
- Widget (macOS menubar extra has no check-in surface)
- Badge count on the app icon
- Weekly digest email / notification
- "Drift alert" for users whose notification permission is off

**The single-point-of-failure problem:** If a user disables notifications (or never grants them), the only remaining triggers are:
- Manually opening the app and scanning `StayConnectedSection` in `TodayView.swift`
- Manually navigating to the People tab

Both are *internal triggers* — they depend on the user already thinking about the app, which is exactly what a habit loop is supposed to avoid needing.

**`syncPersonReminders` is only called from `QuickEncounterSheet.saveIfValid` (line 218).** It is not called on app launch (`MeetingScribeApp.applicationDidFinishLaunching:426`), not on `AddPersonSheet` save, and not when `relationshipType` is set on a person. A new user who adds 10 people sees zero notifications until their first encounter log — the trigger loop never starts.

**`StayConnectedSection` is buried low in the `TodayView` feed** (`TodayView.swift:~line 75`) — after `NeedsAttentionWidget`, `todaySection`, `ActionItemsWidget`, `followUpsSection`, `commitmentsSection`, `decisionsSection`, `onThisDaySection`, `recentNotesSection`, `SuggestedPeopleView`. A user who uses the meeting recording features regularly will never scroll this far.

**`MenuBarView` has no check-in surface.** The menubar popover (`MenuBarView.swift:1–189`) shows recording status, upcoming meetings, and quick actions for recording — zero relationship touchpoints.

### 2. Action — QuickEncounterSheet Access Path

**The sheet is not accessible in <3 taps from the menubar icon.** Current minimum path:

1. Click menubar icon → popover opens
2. Click "Open MeetingScribe Window" (MenuBarView.swift:20)
3. Wait for window to gain focus and render TodayView
4. Scroll to "Stay Connected" section (buried after 8 other sections)
5. Click "Log" button on a person card → `QuickEncounterSheet` opens
6. Select kind chip → save

That is **5–6 steps**, not 3. For a Tiny Habits trigger-action pair, the behavioral cost is lethal.

**`QuickEncounterSheet` itself is well-designed** — chip-first, under 10 seconds once open (comment at file:74 is accurate). The friction is entirely in the *path to the sheet*, not the sheet itself. This is a navigation architecture failure, not a UI failure.

**`AddEncounterSheet` still exists at `PersonDetailView.swift:316`** — the old 5-step form — and the "Add" button in `encountersSection` (PersonDetailView.swift:1184) opens it, not `QuickEncounterSheet`. Two parallel encounter-logging flows exist with different step counts and no handoff logic between them.

### 3. Variable Reward — After Logging, Nothing Happens

`QuickEncounterSheet.saveIfValid` (line 207–220):
1. Calls `people.addEncounter`
2. Calls `onSave?(enc)` — callback returns `_` (TodayView's caller ignores it)
3. Reschedules notifications
4. Calls `dismiss()`

**The sheet disappears. That is the entire feedback loop.**

There is no:
- Celebration animation (confetti, scale, pulse)
- Toast/banner confirming the log ("Saved! 3 check-ins this week")
- Streak update visible anywhere in the UI
- Update to a "last checked in" pill on the person's card in `StayConnectedSection`
- Sound or haptic (macOS does support haptic via `NSHapticFeedbackManager`)
- Any change to the person card that made the user tap in the first place

The person's card in `StayConnectedSection` will disappear from the section (because they're no longer overdue), but only after the next render cycle — not with any animation that signals "you did a good thing." On first log, the card just vanishes, which can read as a bug.

From a Hooked model perspective: **there is zero variable reward.** The system does not acknowledge that the user did something valuable. Fogg's Tiny Habits explicitly requires a "Shine" moment — a moment of self-affirmation or positive signal — immediately after the behavior. The current flow skips this entirely.

### 4. Investment — Data Accumulation Is Invisible

Encounter data accumulates in `PeopleStore` and is rendered as `EncounterRow` entries in `PersonDetailView.encountersSection` (line 1175). There is no visible signal that:

- Logging more encounters improves the usefulness of AI coaching prompts
- The coaching preamble in `PersonDetailView.swift` (`ConversationAnalysisPreset.template`, line 84) adapts based on encounter history
- The `relevanceScore` algorithm (Person.swift:327) weights encounters at `4x` — meaning every log makes that person surface higher in search/suggestions

Users do not know their investment compounds. The investment arm of the Hooked model requires that the user's actions make future product interactions more valuable *and that they perceive this is happening*. Neither the encounter list view nor the AI panel communicates "your data history is making this better."

**The `healthScore` feature gate** (`FeatureGate.swift:13`) is named as a Pro feature but **the arc ring UI does not exist** (confirmed: `PersonDetailView.swift` has zero hits for arc/ring/healthScore rendering). Even if the gate opened, there is nothing to show. Investment feedback is entirely blocked.

### 5. Streak Mechanics — Zero Streak Counter in the Codebase

**Grep confirms: no `streak`, `streakCount`, `currentStreak`, `longestStreak`, or equivalent field exists anywhere in `Sources/`.** The master plan (item D4-6/P2-4, line 124 of MASTER-PLAN.md) proposed a 13-week encounter heat map with "Current streak: N weeks" — this was never built.

`Person.lastInteractionAt` (used at `StayConnectedSection.swift:26`) tracks the last interaction date but no consecutive-cadence logic is derived from it. The only time-based feedback is the `overdueDays` counter shown in orange in `StayConnectedSection` — which is a *guilt signal* (you're late) not a *reward signal* (you're consistent).

From Fogg's model: **there is no behavioral "streak" to protect, no loss-aversion hook to drive return visits.** The only motivational signal is overdue shame.

### 6. Re-engagement — Nothing Pulls a Lapsed User Back

After 2 weeks of no logging:
- `syncPersonReminders` has not been called (only fires after a save)
- If the initial notifications fired and were dismissed without logging, no new notifications are scheduled for people with `effectiveCheckInDays > 7` unless the app was opened and `syncPersonReminders` was called
- There is no `lastOpenedAt` tracking (proposed as P2-3 in MASTER-PLAN.md:149 but not built)
- There is no re-engagement banner on `TodayView`
- There is no weekly digest notification
- The `StayConnectedSection` will show the correct overdue people *if* the user opens the app, but there is nothing nudging the user to open it

**The re-engagement plan (P2-3 in MASTER-PLAN.md) was proposed but not implemented.** The `AppSettings.shared.lastOpenedAt` field does not exist in the codebase.

---

## Existing-Plan Items I Rank Highest

1. **P2-3 (Re-engagement banner after 7+ day absence)** — the most important habit loop item not yet built. Trivial to implement; addresses the complete re-engagement gap.
2. **D4-2 (Wire LOG_NOW action → QuickEncounterSheet)** — already covered thoroughly by D4, but worth endorsing here. The core loop is broken without it.
3. **D4-6/P2-4 (13-week encounter heat map + streak)** — investment visualization; makes accumulated data visible. Proposed, never built.
4. **D4-6 (Call syncPersonReminders from all mutation paths)** — without this, the trigger never starts.

---

## NET-NEW Recommendations

### P3-1 — Menubar quick-log: overdue people surface directly in the popover
**What:** In `MenuBarView.swift`, add a "People" section above "Upcoming" that shows up to 2 overdue check-in people (mirroring `StayConnectedSection` logic) with a single "Log" button each. Tapping "Log" presents `QuickEncounterSheet` as a sheet attached to the `MenuBarExtra` window (not requiring the main window to open).
**Why:** Reduces the encounter-logging path from 5–6 steps to 2 (click menubar icon → click Log). This is the single biggest friction reduction available. Fogg's Tiny Habits rule: the behavior must be "tiny" in activation energy, not just in execution time.
**User value:** Users can maintain relationships without ever opening the main window — the menubar becomes the habit anchor.
**Effort:** S–M (the overdue-people logic exists; `QuickEncounterSheet` is already built; plumbing `PeopleStore` into `MenuBarView` via the existing `EnvironmentObject` chain is the work)
**Impact:** Critical — enables the <3-tap path the current architecture blocks.
**Deps:** Requires `PeopleStore` passed into `MenuBarView` environment.

### P3-2 — Post-save "Shine" moment: animated confirmation with running count
**What:** After `QuickEncounterSheet.saveIfValid` dismisses, the calling view (either `StayConnectedSection` or a `PersonDetailView` toolbar button) shows a 1.5-second overlay: checkmark pulse animation + "Saved · {N} check-ins with {name} this year." Use `NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)` for haptic.
**Why:** BJ Fogg's Shine is non-negotiable for habit formation. The behavior must be followed by a positive feeling — not just absence of friction. "Saved · 12 check-ins with Mom this year" is a variable reward (the count is different each time; the year framing gives progressive context). It also makes the Investment arm visible: the data is accumulating and the user can see it.
**User value:** Transforms logging from a task into a gratifying action. The count creates social proof of the user's own effort.
**Effort:** S
**Impact:** High — directly closes the missing reward loop.
**Deps:** `people.encounterCount(for: person.id)` already exists in `PeopleStore.swift:139`.

### P3-3 — Cadence rhythm card: replace overdue-shame with rhythm-progress framing
**What:** In `StayConnectedSection`, replace the "3 days overdue" orange label with a two-element compound: (a) a 12-week mini-heatmap (one dot per week, filled if any encounter that week, empty if not), rendered as a 12-cell `HStack` of 8×8 circles using `people.encounters(for:)` data, plus (b) a plain-English rhythm label: "Usually every 2 weeks · Last: 3 weeks ago." Only show "overdue" language when the gap exceeds 2x the cadence.
**Why:** "3 days overdue" triggers guilt/avoidance. A heatmap communicates rhythm without verdict — it shows *pattern*, not *failure*. Duolingo's streak works because a missed day feels like breaking a visual chain; the heatmap creates the same loss-aversion without shame framing. D5's audit correctly identifies the guilt-as-driver failure mode; this item operationalizes the fix at the trigger surface.
**User value:** Users can see "I've been consistent with this person" — which is motivating — rather than "I'm failing" — which leads to avoidance.
**Effort:** S (no new data structures; `encounters(for:)` returns a `[Encounter]` with dates)
**Impact:** High — directly addresses the guilt-trigger problem that will cause the highest-empathy users (this product's core audience) to ignore or suppress the section.
**Deps:** None.

### P3-4 — Internal trigger: "who are you thinking about?" entry point in TodayView header
**What:** In `TodayView.quickActions` (TodayView.swift), add a fourth secondary pill: "Log connection" with a person-picker popover (searchable by name, showing relationship emoji). Selecting a person immediately presents `QuickEncounterSheet`. No navigation required.
**Why:** BJ Fogg's Tiny Habits depend on *existing* habits as anchors. "I open my meeting notes every morning" is an existing behavior. Adding "log a connection" to the same quick-action row anchors the new habit to an existing context. The pill is visible before the user scrolls, unlike `StayConnectedSection` which is below the fold.
**User value:** Low-friction logging path that doesn't require a person to already be in the overdue list.
**Effort:** S (person-picker UI exists in `PeopleListView`; can reuse the debounced search)
**Impact:** Medium-High — creates an internal trigger path independent of notifications.
**Deps:** None.

### P3-5 — Weekly relationship digest notification (Sunday 7pm)
**What:** Add a new notification type in `RelationshipNotificationManager`: a weekly Sunday 7pm summary using `UNCalendarNotificationTrigger` with `DateComponents(weekday: 1, hour: 19)` and `repeats: true`. Content: "This week: {N} connections logged · {M} people due soon." Tapping opens `TodayView` with `StayConnectedSection` scrolled into view.
**Why:** The existing per-person notifications are high-frequency and person-specific. A weekly digest serves as a habit anchor ("Sunday evening = relationship maintenance review") independent of whether per-person notifications are enabled. This is the pattern used by Streaks, BeReal, and Superhuman — a predictable weekly cadence builds a ritual, not just a reminder.
**User value:** Users who have silenced per-person notifications can still maintain the weekly rhythm. Also provides a natural re-engagement mechanism for lapsed users.
**Effort:** S
**Impact:** High — creates a habit anchor independent of the broken per-person trigger chain.
**Deps:** None; UNCalendarNotificationTrigger with `repeats: true` on a weekly DateComponents fires weekly automatically.

### P3-6 — Investment signal: "Your relationship memory is building" prompt in PersonDetailView
**What:** In `PersonDetailView.encountersSection` (line 1175), when `mine.count >= 5`, add an inline callout above the encounter list: "You've logged {N} interactions with {name}. AI coaching now has enough context to surface personalized insights." Include a "Try coaching" CTA button that selects the `ConversationAnalysisPreset.checkinCoach` preset and scrolls to the AI panel.
**Why:** The Investment arm of Hooked requires users to *perceive* that their stored data compounds into future value. Currently, encounter logs accumulate silently. Users who don't understand why they're logging will stop after a few entries. A visible inflection-point message at count 5 communicates "the data is working for you."
**User value:** Explains the product's value proposition at the moment of demonstrated commitment, not just at onboarding.
**Effort:** S
**Impact:** Medium — converts the Investment arm from invisible to explicit.
**Deps:** `people.encounterCount(for:)` already available; `ConversationAnalysisPreset` already defined.

### P3-7 — Re-engagement banner: "Welcome back" with relationship context
**What:** Add `AppSettings.shared.lastOpenedAt: Date` (persisted via `@AppStorage`), updated on every `TodayView.onAppear`. If `Date() - lastOpenedAt > 7 days` when `TodayView` loads, show a dismissible banner below the header: "You've been away for {N} days — {M} people are waiting to hear from you." One "See who" CTA scrolls to `StayConnectedSection`.
**Why:** The P2-3 re-engagement banner was proposed in the prior master plan but never implemented. Without it, the only path back for a lapsed user is ambient overdue notifications — which have broken action handlers (D4-2) and no frequency floor (D4-3). The banner is the backstop.
**User value:** Makes MeetingScribe feel aware of absence rather than indifferent. Lapsed users who see "14 days · 3 people waiting" are activating loss-aversion on *human relationships*, not on an app metric — this is appropriate and meaningful.
**Effort:** S
**Impact:** High — the only re-engagement mechanism that operates inside the app.
**Deps:** Orthogonal to D4 fixes; can be implemented independently.

### P3-8 — Anchor habit: post-meeting "who did you see?" prompt
**What:** After a meeting transcript is finalized (`MeetingPipelineController.finalize`), if attendees include any people with non-`.unset` relationshipType, show a non-blocking banner in the meeting summary view: "Was this a check-in with [attendee name]? → Log it." One-tap logs a `videoCall` encounter for that person with the meeting as context.
**Why:** The strongest Tiny Habits anchor is attaching a new behavior to an existing one the user already does. MeetingScribe users already review their meeting summaries. This converts that existing habit into a relationship logging trigger — no new habit formation required, just piggyback behavior.
**User value:** Auto-surfaces the logging opportunity at the highest-context moment (the meeting just happened). Requires near-zero mental effort.
**Effort:** M (requires matching attendee names to People; `Person.findPerson(in: [Person], named:)` style lookup is needed; but the attendee data and People store are already available)
**Impact:** Very high — the strongest habit anchor in the product. Every meeting becomes a potential relationship log.
**Deps:** Phase 1 `RelationshipType` (already built); attendee-to-person matching (partial logic exists in `SuggestedPeopleView`).

### P3-9 — Notification permission recovery: in-app fallback prompt
**What:** In `TodayView`, when `UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied` and `StayConnectedSection` has overdue people, add a non-dismissible callout above the section: "Notifications are off — you won't be reminded about [name] and {N} others. Enable in System Settings →." Use `UNUserNotificationCenter.current().notificationSettings()` asynchronously on `task`.
**Why:** If notifications are disabled, the external trigger is gone forever — the app cannot request permission again after initial denial. This fallback makes the notification-disabled state explicit rather than silently degrading. It also provides a recovery path via a deep-link to `x-apple.systempreferences:` for the app's notification settings.
**User value:** Users who denied notifications during initial setup (common: 40–60% decline first-ask) discover the gap without having to debug "why am I not getting reminders."
**Effort:** S
**Impact:** High for the segment that declined notifications.
**Deps:** D4-4 (onboarding context fix helps prevent this situation).

### P3-10 — Variable reward: celebrate relationship milestones
**What:** When `encounterCount` for a person crosses 10, 25, 50 (configurable thresholds stored in `AppSettings`), show a one-time banner in `PersonDetailView`: "10 interactions logged with {name} — your relationship history is one of the richest in your network." No scores, no percentages — just a milestone acknowledgment phrased as personal significance, not app engagement.
**Why:** Fogg's Tiny Habits and Eyal's Hooked both require variable reward — the reward that fires unpredictably is more reinforcing than the one that fires every time. Milestone celebrations fire rarely and unpredictably from the user's perspective. Phrasing the milestone as "relationship significance" rather than "app achievement" avoids the gamification failure mode D5 identified (users logging phantom encounters).
**User value:** Turns encounter logging into something that feels meaningful, not mechanical.
**Effort:** S
**Impact:** Medium — reinforces the investment behavior without requiring new data structures.
**Deps:** `encounterCount` already tracked at `PeopleStore.encounterCountIndex`.

---

## Top 3 Picks

1. **P3-1** (Menubar quick-log) — eliminates the single biggest friction point in the entire habit loop. The behavior (tap menubar → log) must be shorter than the behavior (open app → scroll → find person → tap). Right now it isn't, and no habit will form at the current activation cost.

2. **P3-8** (Post-meeting "who did you see?" anchor) — the strongest habit anchor in the product because it requires zero new behavior from users who already review meeting summaries. Every meeting becomes a relationship logging opportunity.

3. **P3-2** (Post-save Shine moment) — directly addresses the missing reward step. Without positive feedback at the moment of behavior, Fogg's model predicts the behavior will not become habitual regardless of how frictionless the trigger and action are.

---

## Single Highest-Priority Recommendation

**P3-1 — Add overdue people + quick-log to the MenuBarView.**

The check-in habit loop has five broken links (trigger never starts, action path is 5+ steps, zero variable reward, investment invisible, no re-engagement). P3-1 addresses the most fundamental architectural problem: the app is designed as a window-first experience but users interact with it primarily as a menubar extra. Until "log a connection" is available in 2 taps from the menubar icon, every other habit-loop improvement is optimizing the path that users never take.

