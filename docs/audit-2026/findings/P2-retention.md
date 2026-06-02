# P2 — Retention & Habit Loops Audit

**Lens:** Retention engineer auditing MeetingScribe for check-in reminders, streaks,
re-engagement flows, drift warnings, and habit formation mechanics around relationship
maintenance. The People module is evolving toward a relationship coach; this audit
asks whether the notification and behavioral-loop infrastructure actually keeps users
coming back on behalf of their relationships — or just passively surfaces data when
they happen to open the app.

---

## 1. What Notifications Currently Exist

`NotificationManager.swift` (186 lines) registers exactly **four notification types**:

| ID | Trigger | Content | User goal served |
|----|---------|---------|-----------------|
| `MEETING_START` | 10s before calendar event | Meeting title + "Join & Record" action | Productivity capture |
| `IMPROMPTU_DETECTED` | Zoom detected | "Record it?" | Productivity capture |
| `transcription-<id>` | Immediately after pipeline finishes | "Meeting ready" | Productivity feedback loop |
| `daily-brief` | 8am repeating (opt-in, default OFF) | "Open MeetingScribe → Standup" | Productivity standup |

**Zero notifications serve relationship maintenance.** There is no notification that
says "You haven't talked to [Name] in N days", "It's been 3 weeks since you logged
anything with Marcus", or "Sarah's birthday is in 5 days." The notification surface
is 100% meeting-capture focused.

`Settings.swift` has `dailyBriefEnabled` (line 223) as the only user-configurable
notification toggle — no per-person reminder cadence setting of any kind. There are
no keys for `checkInRemindersEnabled`, `weeklyReconnectDigest`, `birthdayReminders`,
or anything analogous.

---

## 2. In-App Drift Detection — What Exists

### ReconnectView (SuggestedPeopleView.swift:84–161)

This is the most sophisticated retention surface in the codebase. It:
- Infers per-person cadence from median gap between encounters (needs ≥ 3 encounters;
  `cadenceSeconds(for:)` at line 95)
- Flags overdue contacts at 1.5× that median, clamped to 7–120 days
- Falls back to 30 days for anyone with fewer than 3 encounters
- Shows top 4 overdue contacts in a card on TodayView (line 96 in TodayView.swift)
- Taps through to that person's detail; does not offer inline quick-log

**Critical gaps:**
1. The 30-day fallback ignores relationship type. A romantic partner and a casual
   acquaintance with 0–2 encounters both get the same 30-day default.
2. The 4-person cap means the 5th-most-overdue person is invisible.
3. There is no way for the user to see *why* someone appeared — what the inferred
   cadence is, when the last interaction was, or how overdue they are by percentage.
4. This widget never fires a push notification. A user who opens the app weekly
   sees it; a user who has lapsed for 2 weeks never gets prompted.

### PeopleInsightsView.swift:76–83 (goneCold)

A second drift surface: hardcoded 45-day cutoff, shows up to 8 people, available
only on the People tab default pane (no person selected). Has an inline "Mark
reached out" checkmark button (line 29–35) that calls `bumpLastInteraction()` —
the only zero-click engagement in the entire relationship surface. The cutoff is
not configurable and ignores relationship type.

**Two drift surfaces with different cutoffs (cadence-inferred vs. 45-day hardcoded)
create inconsistency:** a user can appear in ReconnectView (Today) but not goneCold
(People), or vice versa.

---

## 3. Streak and Consistency Mechanics

**There are none.** The codebase has no streak counter, no "N weeks in a row"
tracker, no consistency score, no heat-map visualization of encounter frequency,
and no goal-setting mechanism ("I want to check in with Sarah weekly"). The
`Encounter` model (Encounter.swift) stores date and notes but no derived metrics
are ever computed from the corpus.

The MCP server's `mcp__meetingscribe__list_meetings` / `list_people` tools exist,
but there is no `get_relationship_health` or `get_check_in_streak` tool that would
let Claude surface consistency data.

---

## 4. Re-Engagement Flow When User Has Been Absent

When a user who hasn't opened the app in 2 weeks returns:
- TodayView loads and shows overdue action items (NeedsAttentionWidget), today's
  meetings, and the ReconnectView widget.
- There is **no re-engagement interstitial** — no "Here's what happened while you
  were away" screen, no "You haven't recorded a meeting in 14 days" prompt, no
  catch-up digest.
- The `StandupDigest` (TodayView.swift:372) is available via a toolbar button but
  is not auto-surfaced on re-entry after absence.
- There is no "lapsed user" detection: the app does not track last-open date, does
  not compare it to the notification cadence, and does not escalate nudges after
  silence.

---

## 5. Existing Plan Items — Highest Priority Through This Lens

**Endorse — "Stay in touch" nudges (in plan):** The plan mentions stay-in-touch
nudges as a planned item but the implementation (`ReconnectView`) is notification-
free. Converting it to a `UNCalendarNotificationTrigger` that fires when the widget
would have shown a person is the completion of this item and is the single most
impactful retention mechanic available. Effort S.

**Endorse — TDY-6 end-of-day recap (MASTER_PLAN_V3.md section 3.4):** Rated P2
in the plan, this should be P1. An end-of-day notification ("3 meetings recorded,
2 action items due, 1 follow-up pending, 2 people to reconnect with") that fires
at 6pm is the daily habit anchor for both productivity and relationship maintenance
loops. Effort M.

**Endorse — Relationship type paths (briefing focus #1):** Without a
`relationshipType` field on `Person`, cadence logic must be one-size-fits-all. This
is the model foundation that unlocks differentiated reminder frequencies (partner:
daily, close friend: weekly, colleague: monthly). D4 audit also endorses this; it
is doubly critical for the retention lens.

---

## 6. NET-NEW Recommendations

### P2-1 — Per-person check-in push notification scheduler

**What:** Add `checkInReminderDays: Int?` to `Person` (nil = off, inherits
relationship-type default when set). Extend `NotificationManager` with a new
method `syncPersonReminders(people: [Person])` that schedules one repeating
`UNCalendarNotificationTrigger` per person who has a non-nil cadence and whose
`lastInteractionAt + cadence < now`. Notification body: "Haven't checked in with
[Name] in [N] days — how are they doing?" with a "Quick log" action that opens a
compact encounter sheet directly (deep-linked via `meetingscribe://person/<id>`).
Call `syncPersonReminders` from `MainWindow` on launch and whenever `PeopleStore`
changes.

Settings key: `checkInRemindersEnabled` (default ON for people with an explicit
cadence). NotificationManager already has the authorization flow and category
infrastructure; this adds one new category `PERSON_REMINDER` with "Quick log" and
"Snooze 3 days" actions.

**Why it's the highest-priority retention item:** Every other retention surface
in this app is passive — it only works if the user opens the app. This is the only
mechanism that can pull a lapsed user back into the relationship maintenance loop
on behalf of their actual relationships. A user who forgot to check in with their
partner for 4 days and gets a notification at 7pm is the relationship coach use
case. Nothing else closes that loop.
**Effort:** M. **Effort breakdown:** Person model change S, NotificationManager
extension S, Settings toggle S, deep-link routing S, UI for per-person cadence
picker S.

### P2-2 — Weekly relationship health digest notification

**What:** A Sunday 7pm `UNCalendarNotificationTrigger` (distinct from daily-brief)
that fires a "Relationship health this week" summary: "You checked in with 4 people
this week. Still to reach: [Name1], [Name2]." Uses `ReconnectView.candidates` logic
to pick the names (capped at 2 for readability). Tapping opens Today tab. Opt-in
via Settings → Notifications → "Weekly relationship digest." Default ON.

This is the weekly habit anchor complementing the daily-brief (productivity anchor)
and per-person reminders (individual anchors). The three-layer cadence (daily,
weekly, per-person) covers all user types.
**Effort:** S. One new notification ID, one `UNCalendarNotificationTrigger`, one
Settings toggle.

### P2-3 — Re-engagement interstitial after 7+ day absence

**What:** Track `AppSettings.shared.lastOpenedAt: Date` (write on every cold
launch). If `Date() - lastOpenedAt > 7 days`, show a non-modal banner at the top
of TodayView (dismissible): "Welcome back — here's what's been waiting." Banner
body: count of unprocessed meetings, overdue action items, and (most importantly)
people in the ReconnectView drift list. One-tap CTA to each area. Auto-dismiss
after 10 seconds or on user scroll.

No sheet, no interrupt — a contextual banner that respects the user's intent while
surfacing the highest-urgency relationship and task items from the gap period.
**Effort:** S. `lastOpenedAt` write + banner view + 7-day gate logic.

### P2-4 — Encounter frequency heat map on PersonDetailView

**What:** Above the encounters list in `PersonDetailView`, render a 13-week
contribution-style grid (one cell = one week, color intensity = encounter count
that week, max 3 = full saturation). Show "Current streak: N weeks" and
"Best streak: M weeks" below. If a per-person cadence is set (P2-1), show the
target as a ghost outline of what a consistent cell should look like.

Implementation: a `LazyHGrid` of 91 `RoundedRectangle` cells, tinted with
`NDS.brand.opacity(0.2 * min(count, 3) / 3)`. No third-party library. The
encounter date corpus is already available via `PeopleStore.encounters(for:)`.

Habit visualization is the strongest behavioral reinforcement mechanism after
notifications. Making consistency visible — a green streak vs. a gap — is what
turns a CRM into a habit.
**Effort:** S. Pure view code; data already exists.

### P2-5 — "Relationship health score" on PeopleInsightsView

**What:** Add a simple composite score (0–100) per person on the Insights pane.
Formula: (recency score 0–40) + (frequency score 0–40) + (quality score 0–20
based on `notes` length in recent encounters). Display as a colored arc or simple
bar next to each person in the goneCold card and mostActive card. Color: green
(>70), amber (40–70), red (<40).

This is not Goodhart's Law bait — keep it in the Insights pane only, not on
PersonDetailView, so it's a diagnostic for the user, not a leaderboard. The score
gives the user a quick answer to "how are my closest relationships actually doing?"
without requiring them to read every encounter log.
**Effort:** S. Pure computed property on top of existing data.

### P2-6 — "On this day" relationship flashback notification

**What:** If the encounter corpus contains encounters on this calendar date in a
prior year, fire an 8am notification: "One year ago today: [encounter event name]
with [Name]. Worth reconnecting?" Tapping opens that person's detail. Max 1
notification per day (pick the most recent matching encounter). Similar to the
TodayView "On this day" section (`TodayView.swift:254–315`) but pushed, not
passive.

Emotional anchoring — reminding users of meaningful past interactions — is a
well-documented technique for sustaining relationship investment. It creates a
natural conversation starter ("hey, this day last year…") and generates intrinsic
motivation to check in.
**Effort:** S. Encounter corpus query at launch + one `UNCalendarNotificationTrigger`
per matching encounter (or one immediate notification if launching on the matching date).

### P2-7 — Lapsed-user notification escalation

**What:** If `lastOpenedAt` (P2-3) shows the user hasn't opened the app in >14
days AND `checkInRemindersEnabled` is ON, escalate the next scheduled person
reminder to a higher-prominence notification with sound and a more direct body:
"It's been 2 weeks since you last opened MeetingScribe. [Name] hasn't heard from
you in [N] days." Use `UNNotificationContent.interruptionLevel = .timeSensitive`
(macOS 12+, available here since macOS 14 is the target). Only one escalated
notification per 7-day window to avoid annoyance.

Escalation nudges have high re-engagement rates compared to flat cadence
notifications. A user who hasn't opened in 2 weeks is at high churn risk; a
time-sensitive notification with a specific person's name is more compelling than
a generic reminder.
**Effort:** S. Condition on existing lastOpenedAt + existing person reminder
infrastructure (P2-1 prerequisite).

### P2-8 — Check-in goal setting per relationship type

**What:** In PersonDetailView (or RelationshipType settings), let the user set an
explicit goal: "I want to check in with [Name] [weekly / every 2 weeks / monthly]."
Store as `checkInGoalDays: Int?` on `Person` (separate from the inferred cadence,
which is historical; the goal is aspirational). Use `checkInGoalDays` as the
primary cadence for P2-1 reminders when set, falling back to inferred cadence.

Show goal vs. actual on the heat map (P2-4): the target line makes the gap
between intention and behavior visible without shaming. Users who set goals with
specific people are significantly more likely to follow through than those relying
on inferred cadences alone.
**Effort:** S. Model field + Settings UI row + heat map target line (P2-4 builds
it; this adds the data source).

### P2-9 — Birthday and anniversary push notifications

**What:** Extend `PeopleInsightsView.upcomingBirthdays` (currently in-app only,
line 86) to fire push notifications: 7 days before ("Sarah's birthday is in 7
days — want to plan something?") and morning of ("Happy birthday day! Reach out to
[Name]"). Also support `anniversaryDate` on `Person` for relationship milestones
(partner, close friend). Scheduled via `UNCalendarNotificationTrigger`.

`NotificationManager` already has the infrastructure; `Person.birthday` exists
(line 103 in Person.swift). This is completing an obviously-needed feature that
the data model already supports but the notification layer ignores.
**Effort:** S. Two `UNCalendarNotificationTrigger` per person with birthday, one
new notification category.

### P2-10 — MCP tools for habit loop data

**What:** Add three tools to the 17-tool MCP server:
1. `get_relationship_health(person_id)` — returns last interaction date,
   inferred cadence, days overdue, encounter count by type in last 90 days,
   current streak (in weeks), best streak.
2. `list_drifting_contacts(limit?, relationship_type_filter?)` — returns the
   same data as `ReconnectView.candidates` but accessible to Claude in chat.
3. `get_check_in_history(person_id, days_back?, kind_filter?)` — returns the
   encounter list with dates, kinds, and notes.

These three tools transform Claude from "person information lookup" to "relationship
coach that can answer: who am I neglecting, how is my relationship with X trending,
and what should I prioritize this week?" Without them, Claude can read person
metadata but cannot reason about relationship health or habit consistency.
**Effort:** S. MCP tools are thin wrappers over existing `PeopleStore` methods;
`encounters(for:)` and `cadenceSeconds(for:)` already exist.

### P2-11 — "Commitment to connect" micro-ritual after meeting finalization

**What:** When a meeting is finalized and the People extraction runs (Phase B,
auto-enabled per `Settings.swift:477`), surface a one-step prompt: "You met with
[attendee names]. Log a quick check-in?" with inline encounter logging for each
attendee (kind auto-set to "meeting", date auto-set to meeting date, notes pre-
filled from the meeting summary's attendee-relevant sentences). One-tap confirm
or dismiss per person.

Today the pipeline auto-bumps `lastInteractionAt` for extracted people
(`PeopleStore.swift:1158`), but does not create a formal `Encounter` record — so
there is no encounter to show in the encounter log, no notes, no kind, and no
contribution to the streak heat map. This prompt closes the gap between "system
knows you met" and "user has a logged, annotated check-in."
**Effort:** M. Requires a post-finalization prompt sheet + attendee-matching
logic + inline quick-confirm per person.

### P2-12 — Notification control panel in Settings

**What:** `Settings.swift` currently has only `dailyBriefEnabled` and
`notifyAtMeetingStart` as notification toggles. Add a dedicated "Notifications"
section in `SettingsView` with granular controls:
- Meeting reminders (already exists)
- Daily brief (already exists)
- Weekly relationship digest (P2-2) — toggle + day/time picker
- Per-person check-in reminders (P2-1) — master toggle (individual people
  control their own cadence in PersonDetailView)
- Birthday & anniversary reminders (P2-9) — toggle + days-in-advance picker
- "On this day" flashbacks (P2-6) — toggle
- Lapsed-user escalation (P2-7) — toggle

Without a control panel, users who find any notification annoying must disable
all system notifications for the app. Granular control increases the chance users
keep at least the relationship-maintenance notifications enabled.
**Effort:** S. Pure Settings UI + new `AppSettings` keys; each notification
feature already has the logic in P2-1 through P2-9.

---

## 7. Top 3 Picks

### #1 — P2-1: Per-person check-in push notification scheduler

This is the highest-priority recommendation in this entire audit. Every other
retention surface (ReconnectView, PeopleInsightsView, heat map) is passive — it
only works if the user opens the app. A per-person push notification is the only
mechanism that acts on the user's behalf when they are not in the app. It is what
transforms MeetingScribe from a meeting tool that happens to have CRM features
into a relationship coach that proactively maintains the user's commitments. The
data model already supports it (`lastInteractionAt` exists, `PeopleStore.encounters`
exists, `NotificationManager` has authorization and category infrastructure); the
missing piece is one `syncPersonReminders()` method and one new `Person` field.

### #2 — P2-4 + P2-8 combined: Encounter heat map + goal setting

The heat map is the habit-formation visualization that makes consistency visible
(5 minutes of code on top of `PeopleStore.encounters(for:)`), and goal-setting
gives the user an explicit intention to reinforce. Together they create the
intrinsic motivation loop: set a goal, see your streak, feel the gap when you
miss a week. Without this, the relationship maintenance habit has no feedback
mechanism. With it, users who set goals with their closest people are far more
likely to sustain the behavior. Both are S-effort.

### #3 — P2-9: Birthday and anniversary push notifications

The `Person.birthday` field exists (`Person.swift:103`). `PeopleInsightsView`
already computes upcoming birthdays (line 86). `NotificationManager` already has
the category and scheduling infrastructure. This is the most glaring case of
existing data that the notification layer completely ignores. Birthday notifications
are the highest open-rate, most emotionally salient notification category in any
social or CRM app. They are also the most natural on-ramp for lapsed users: a
birthday reminder for a close friend feels helpful, not nagging. Shipping this
takes the birthday data from "nice to have in a list" to "makes users thank you."

---

## 8. Cross-Audit Dependencies

| This recommendation | Depends on | Synergizes with |
|---------------------|-----------|-----------------|
| P2-1 (person reminders) | D4-7 (relationship type) for defaults | D4-2 (cadence field), D4-9 (global shortcut) |
| P2-2 (weekly digest) | — | P2-12 (settings panel) |
| P2-4 (heat map) | D4-3 (encounter kind) for kind-filtered view | D4-6 (D4 names same feature) |
| P2-9 (birthday push) | Person.birthday already exists | — |
| P2-10 (MCP tools) | D4-10 (encounter MCP) covers log_encounter | — |

Note: D4 (check-in interaction design audit) and P2 (retention) converge on several
recommendations. D4-2 and P2-1 describe the same per-person notification feature
from different angles — implement once. D4-6 and P2-4 both describe the heat map —
implement once. Where both audits endorse an item, treat it as doubly validated.
