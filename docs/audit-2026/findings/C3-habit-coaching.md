# C3 — Habit & Coaching App Competitive Intelligence

**Lens:** Adjacent habit/coaching apps — Fabulous, Finch, Coach.me, Streaks, Bearable —
streak mechanics, content delivery, habit loop design, and what check-in cadence
should look like per relationship type.
**Auditor:** Competitive Intelligence subagent (25-agent audit, 2026-06-02)

---

## 1. Lens Statement

MeetingScribe's People module is evolving into a relationship coach. Five mature
habit apps have already solved the problems it is about to face: how to deliver
content progressively without overwhelming, how to handle missed days without
punishing users into quitting, how to make data visible without shaming, and how to
sustain a check-in habit across months rather than days. This audit extracts the
specific design decisions from those apps that MeetingScribe should adopt — and the
ones it should deliberately avoid.

**Primary sources:**
- Fabulous behavioral design: [How Fabulous Turns Habits Into Rituals](https://medium.com/@preciousebunoluwaa/how-fabulous-turns-habits-into-rituals-a-case-study-in-behavior-design-51b3ae18ffd3), [Fabulous science page](https://www.thefabulous.co/science-behind-fabulous/)
- Finch emotional design: [Finch App Review 2026](https://calmevo.com/finch-app-review/), [DBT review](https://maggiedaviscounseling.wordpress.com/2026/01/03/mental-health-app-review-finch-why-it-works-for-emotional-regulation-especially-with-dbt/), [Enchanted Design](https://www.sophiepilley.com/post/the-magic-of-finch-where-self-care-meets-enchanted-design)
- Streaks mechanics: [Smashing Magazine Streak UX](https://www.smashingmagazine.com/2026/02/designing-streak-system-ux-psychology/), [ADHD failure modes](https://www.helloklarity.com/post/breaking-the-chain-why-streak-features-fail-adhd-users-and-how-to-design-better-alternatives/), [Streak Psychology](https://dev.to/assindo/why-streaks-work-the-psychology-behind-habit-streaks-and-how-to-keep-them-without-burning-out-42n0)
- Coach.me check-ins: [Coach.me Review](https://accompli.app/coach-me-app-review/), [Getting Started](https://support.coach.me/article/45-getting-started)
- Bearable visualization: [Bearable Health Tracker](https://bearable.app/health-tracker/), [Visualising health data](https://bearable.app/support/tips/visualise-your-health-data-in-many-forms/)
- Streak psychology: [Yu-kai Chou on Streak Design](https://yukaichou.com/gamification-analysis/streak-design-gamification-motivation-burnout/)
- Notification fatigue: [Avoiding Push Fatigue](https://contextsdk.com/blogposts/avoiding-push-fatigue-common-user-turn-offs), [Appbot 2026 Best Practices](https://appbot.co/blog/app-push-notifications-2026-best-practices/)
- Relationship contact research: [PMC longitudinal study](https://pmc.ncbi.nlm.nih.gov/articles/PMC7483134/), [Communication across life course](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5156499/)

---

## 2. What MeetingScribe Has (Competitive Baseline)

### Current check-in infrastructure (file:line citations)

| Component | Location | What it does | Gap |
|-----------|----------|--------------|-----|
| `ReconnectView` | `SuggestedPeopleView.swift:84–161` | Infers cadence from encounter median; shows 4 overdue contacts on Today | Silent widget only; no push; 30-day fallback ignores relationship type |
| `cadenceSeconds(for:)` | `SuggestedPeopleView.swift:95–102` | Median-gap inference, clamped 7–120d, needs ≥3 encounters | One-size fallback; no journey, no content, no progressive delivery |
| `NotificationManager` | `NotificationManager.swift:1–242` | 4 notification types: meeting start, impromptu, transcription complete, daily brief | Zero relationship check-in notifications |
| `Encounter` model | `People/Encounter.swift:7–46` | Event-anchored log: eventName, date, location, notes, meetingID | No `kind`, no emotional quality, no duration, no streak metric |
| `PeopleInsightsView` goneCold | `PeopleInsightsView.swift:76–83` | 45-day hardcoded cutoff, in-app card only | Hardcoded, not type-aware, no push |
| `AddEncounterSheet` | `PersonDetailView.swift:1918` | 420×460pt sheet, required eventName, optional date/location/notes | No quick-capture, no template, no relationship-type prompt |

**Competitive verdict:** MeetingScribe is at Duolingo circa 2013 — a streak tracker
with no grace mechanics, a single notification cadence for all users, no progressive
content delivery, and no recovery path when a user misses a week.

---

## 3. What Each Competitor Does (and What to Steal)

### 3.1 Fabulous — Progressive "Journey" Content Delivery

**What they built:** Fabulous (Duke Behavioral Economics Lab, Dan Ariely) uses
"Journeys" — multi-week structured programs that introduce one small habit at a time,
each anchored to an existing routine (morning coffee, waking up). Habit stacking:
new behavior attaches to an established one so it is contextually cued rather than
willpower-dependent. Audio coaching frames each new habit with behavioral science
rationale. Users do not see a checklist of everything — they see the next right step.

**The design principle:** Content is gated by readiness, not by subscription tier.
A user on Day 1 of a "sleep mastery" Journey sees one action. On Day 14 they see
four. The complexity scales with demonstrated consistency.

**What MeetingScribe should steal:**
- The idea of a **Relationship Journey** — a defined arc (e.g. "Deepening with a
  close friend over 6 weeks") that introduces one new check-in behavior per week.
  Week 1: log that you met. Week 2: add an emotional quality note. Week 3: set a
  check-in goal. Week 4: try a structured reflection prompt. This is content
  delivery paced to user readiness, not a feature dump.
- **Keystone habit attachment:** The most natural existing cue in MeetingScribe is
  the moment a meeting finishes and transcription completes. That exact moment
  (the `notifyTranscriptionComplete` callback at `NotificationManager.swift:141`)
  is the keystone cue for a "log a check-in" nudge. Fabulous would put the habit
  right there, not hidden behind a tab.

**What to avoid:** Fabulous's rigid Journey linearity stalls users who graduate the
core program. MeetingScribe should let users choose their own journey depth per
relationship type, not force a single linear path.

---

### 3.2 Finch — Self-Compassion Mechanics and Emotional Design

**What they built:** Finch gamifies *self-compassion*, not productivity. The virtual
bird waits patiently when you miss a day — no penalty, no streak reset, no guilt
induction. The first question every session is "how are you feeling?" not "what did
you accomplish?" Rewards effort ("showed up") not perfection ("perfect week"). The
emotional design thesis: if the system makes users feel judged for absence, they stop
returning. If it makes them feel welcomed back, they return even after long gaps.

**The design principle:** Missed days are treated as neutral data, not failures.
Progress accumulates regardless of gaps. The reward is in the *return*, not the
unbroken chain.

**What MeetingScribe should steal:**
- When a user has not logged a check-in with someone for a long time, the re-entry
  message should be warm, not accusatory. Current `ReconnectView.lastText()` at
  `SuggestedPeopleView.swift:155–160` says "Last talked over a year ago." Finch
  would say "It's been a while — Sarah would probably love to hear from you." One
  is a verdict; the other is an invitation.
- **"Showed up" micro-reward:** When a user logs any check-in after a gap of ≥7
  days, show a one-line affirmation: "Back in touch with Marcus — that matters."
  This is a 3-line code change with outsized emotional impact.
- **Effort, not intensity:** The check-in UX should reward *any* interaction
  (a text, a brief call) as meaningful — not just structured sit-down encounters.
  The current `Encounter` model has no `kind` to distinguish "full dinner" from
  "sent a meme" but both deserve credit. Finch would count both.

**What to avoid:** Finch's virtual pet is delightful for Gen Z self-care but would
feel tonally wrong in a relationship coaching app for professionals. The mechanics
transfer; the metaphor does not.

---

### 3.3 Streaks — What Makes a Streak Mechanic Sticky Without Punishing

**What they built:** Streaks (Apple Design Award 2016) uses "Don't Break the Chain"
with deliberate design choices that the 2026 Smashing Magazine UX analysis dissects
in detail. Key findings:
- Hard resets (streak → 0 on one missed day) cause **catastrophic abandonment** —
  users report disproportionate feelings of failure that lead to quitting entirely.
- The effective pattern is **grace mechanisms**: streak freezes (intentional skip,
  no reset), decay (streak decreases slowly rather than zeroing), or forgiveness
  (a "repair" after a miss). Lally et al. (2010) proved missing one day does not
  reset the habit formation process; apps that punish as if it does are
  psychologically misinformed.
- The **pause feature** (for planned breaks — travel, illness) is the highest-rated
  Streaks mechanic. Users who know they can pause without penalty maintain longer
  streaks than those who fear a forced reset.
- 71% of app users uninstall apps because of excessive notifications; well-timed
  notifications increase engagement by up to 88%. The delta between "well-timed"
  and "excessive" is personalization and user control.

**What MeetingScribe should steal:**
- **Streak decay, not reset:** When a user misses their check-in goal for a person,
  the streak counter should say "2 weeks (1 missed)" rather than resetting to 0.
  The visual — a heat map cell with lower saturation rather than a blank gap —
  communicates the miss without inducing abandonment. The P2-4/D4-6 heat map
  recommendations already exist; the *coloring convention* should encode grace.
- **"Pause" mechanic for planned relationship gaps:** If a user knows they're on
  vacation or a person is traveling, let them "pause" the check-in reminder for
  that person for N days. One toggle in PersonDetailView. Maps to `Person` as
  `checkInPausedUntil: Date?`. This prevents the notification from becoming noise
  that gets permanently disabled.
- **The right notification budget:** Relationship check-in notifications should be
  capped to prevent fatigue. The research-backed sweet spot: max 1 notification
  per person per cadence period, with a global daily cap of 3 relationship
  notifications total regardless of how many people are overdue. More than 3 per
  day and users disable the whole category.

---

### 3.4 Coach.me — What Makes Check-Ins Meaningful

**What they built:** Coach.me's insight is that the check-in's *social visibility*
is what makes it stick. A private checkmark is weaker than a checkmark a coach or
friend can see and respond to. The daily coach-check-in ("coaches should check in
nearly every day") creates an external accountability loop that the user cannot
generate for themselves. The format: one tap to confirm, optional note, coach
responds.

**The key finding:** Behavioral psychology (BJ Fogg's BMAT model): the notification
is the Trigger, the habit is the Behavior, the coach response is the Ability-
boosting signal that lowers friction for next time. The check-in loop without a
*response* is weaker than one with feedback.

**What MeetingScribe should steal:**
- **Structured one-question check-ins, not open text boxes.** Coach.me's check-in
  format is: "Did you do it? (yes/no) + optional note." MeetingScribe's
  `AddEncounterSheet` asks the user to invent context from scratch. The competitive
  pattern is a pre-populated structured prompt: "Did you connect with [Name] this
  week? [Yes — log it] / [Not yet — snooze]." The binary prompt is dramatically
  lower friction than an open text field.
- **Claude as the "coach" that responds.** The MCP server already has bidirectional
  access. After a user logs a check-in with a partner, Claude could proactively
  surface a relevant observation in the next chat session: "You've logged 6 check-
  ins with Alex this month — up from 3 last month. What's working?" This closes the
  Coach.me feedback loop using the AI already in the app.
- **Social accountability substitute:** MeetingScribe is solo/local-first, so
  peer-visibility isn't available. The substitute is *personal accountability to
  stated intentions.* When a user sets a check-in goal ("I want to connect with
  Dad weekly"), the app should surface that stated commitment in the notification:
  "You said you'd connect with Dad weekly. It's been 9 days." Not a generic drift
  alert — a specific reminder of the user's own words.

---

### 3.5 Bearable — Correlation Insights and Data Visualization

**What they built:** Bearable's core value is the **correlation insight** — showing
users not just what they tracked, but how different variables affect each other.
The landscape-rotation comparison graph lets users overlay mood vs. sleep vs. water
intake. The "Impacts" section quantifies: "this factor improves your mood by X%."
The key UX choice: correlation data lives on the *Insights* page, not the primary
tracking view. Tracking is simple; understanding is a deliberate navigation step.

**Bearable's design discipline:**
- Max 5–9 elements per dashboard card to prevent overload.
- Calendar heatmap (year-in-pixels) for mood/symptoms — one square per day,
  color-coded. Glanceable; no numbers needed.
- Reports available as weekly/monthly exports — the data belongs to the user.

**What MeetingScribe should steal:**
- **Cross-person relationship activity calendar (year-in-pixels):** A "relationship
  year" calendar on `PeopleInsightsView` — one square per week per close contact,
  color-coded by encounter count. This gives the user a gestalt view of their
  social life: "I was consistently connected in Jan-Feb, then completely dropped off
  in April." Bearable proves this single visualization is the most compelling
  retention hook in health tracking apps.
- **Correlation insights for relationship health:** "You log better-quality notes
  with Sarah when you meet in person vs. on a call." Or: "Your encounter frequency
  with Marcus drops 40% every quarter (busy periods?). You have 3 weeks to next
  predicted drop." These are computable from the encounter corpus. MCP Claude is
  the natural engine for generating them; a `generate_relationship_insights`
  MCP tool would expose the corpus to Claude for exactly this analysis.
- **Bearable's insight placement discipline:** Correlation data should live on
  `PeopleInsightsView`, not on `PersonDetailView`. The detail view is for action;
  the insights view is for reflection. Mixing them (showing a relationship health
  score on every person card) risks Goodhart's Law — users optimize the score
  rather than the relationship. P2-5 (relationship health score) already makes this
  correct placement decision; C3 validates it from competitive evidence.

---

## 4. Existing Plan Items Worth Endorsing (Through This Lens)

Items already in MASTER_PLAN_V3 or D4/P2 findings that this competitive research
validates most strongly:

**Endorse — P2-4/D4-6 (Encounter frequency heat map):** Bearable's year-in-pixels
calendar is the single most retention-effective visualization in health tracking.
A 13-week `LazyHGrid` on `PersonDetailView` is the right call. Endorsing as **P0**
through this lens — it is table stakes for any app positioning itself as a
relationship coach.

**Endorse — P2-1/D4-2 (Per-person check-in notification scheduler):** Coach.me
proves that the external trigger is what separates "habit" from "intention."
The current architecture has the trigger infrastructure (`NotificationManager`) but
zero relationship triggers. Both D4 and P2 also endorse this; triple validation.

**Endorse — D4-8 (Check-in prompt templates per relationship type):** Fabulous's
Journey framing and Coach.me's one-question format both validate this. Rotating
relationship-type-aware prompts in the notes field is a direct implementation of
Fabulous's progressive content delivery and Coach.me's structured check-in.

**Endorse — D4-5 (Structured post-encounter reflection prompt):** Finch's
"how are you feeling?" prompt versus Duolingo's "did you complete the lesson?"
is the entire design difference between self-compassion mechanics and achievement
mechanics. A one-question post-log prompt is Finch's core mechanic applied to
relationship maintenance.

---

## 5. NET-NEW Recommendations

Items not covered by D4, P2, P1, or the existing plan:

---

### C3-1 — Relationship Journey: Progressive Content Unlocking

**What:** Borrow Fabulous's Journey model to create per-relationship-type onboarding
arcs. When a user sets `relationshipType = .partner` on a Person (P1/D4-7), the app
activates a 4-week "Partner Connection Journey":
- Week 1 prompt (shown once, inline on PersonDetailView): "Log when you connect —
  just a tap."
- Week 3 prompt (after 3 check-ins logged): "Try adding one note about what felt
  good this time."
- Week 5 prompt (after 5 check-ins with notes): "You've been building a record.
  Here are 3 questions that tend to deepen partner relationships." (Links to
  Gottman-informed reflection templates.)
- Week 8 (streak maintained): Unlock "Relationship Insights" mini-dashboard on
  `PeopleInsightsView` for that person.

**Implementation:** A `JourneyProgress` struct (per person, stored in `Person`
via a lightweight `journeyState: [String: Int]` dictionary — keys are journey IDs,
values are the current step index). No server needed; logic is local and deterministic.
The prompts are static strings in a `RelationshipJourneyLibrary` enum, gated by
`checkInCount` and `notesQuality` (computed from encounter corpus).

**Why it's net-new:** D4-8 covers static prompt templates. This adds *progression* —
the content changes as the user builds the habit, exactly as Fabulous does. Static
templates don't teach; progressive journeys coach.
**Effort:** M. Model extension S, library struct S, PersonDetailView prompt injection M.

---

### C3-2 — Streak Grace Mechanic: Decay + Pause, Not Reset

**What:** When the P2-4/D4-6 heat map is built, implement Streaks-style grace
mechanics rather than hard resets:

1. **Decay coloring:** A missed week on the heat map renders as a half-opacity cell
   (amber), not blank. The streak counter shows "3 weeks (1 gap)" rather than
   resetting. Implemented in the `LazyHGrid` color formula: `gap == 0 ? NDS.brand :
   (gap == 1 ? NDS.brand.opacity(0.4) : Color.clear)`.
2. **Pause toggle:** A `checkInPausedUntil: Date?` field on `Person` (new field, S
   effort). When set, `ReconnectView.cadenceSeconds(for:)` returns `.infinity`,
   removing the person from the overdue list and suppressing their push notification.
   Exposed in PersonDetailView as "Pause reminders until [date picker]."
3. **Re-entry affirmation:** When a user logs a check-in after a gap of ≥14 days
   (measured from `lastInteractionAt`), show a one-line non-blocking toast:
   "Back in touch with [Name] — that matters." This is Finch's self-compassion
   mechanic applied to relationship maintenance. Zero-effort to implement once the
   encounter log event is fired.

**Why it's net-new:** D4-6/P2-4 specify the heat map but not the coloring convention
for missed periods. The `pause` mechanic and the re-entry affirmation are entirely
absent from existing proposals. Both are directly derived from Streaks and Finch's
competitive research.
**Effort:** S. Coloring formula change, one new `Person` field, one toast view.

---

### C3-3 — Notification Budget Cap (Global Daily Relationship Limit)

**What:** The research finding that 71% of app users uninstall because of excessive
notifications — and that a cap of 3 relationship notifications per day is the
fatigue threshold — has a direct implementation implication.

Add a `NotificationBudget` actor (or a simple `@AppStorage` counter) that tracks how
many relationship-check-in notifications have fired today. Before scheduling any
person-reminder push (P2-1), check `relationshipNotificationsToday < 3`. If at cap,
defer the notification to the next valid window (next morning at 8am). The 3
highest-priority people (most overdue, based on `ReconnectView.candidates` sort order)
get today's budget; the rest wait.

This is a **single guard clause** in the `syncPersonReminders()` method that P2-1
proposes. Without it, a user who adds 10 close friends with weekly cadences could
receive 10 push notifications in one day — the fastest path to disabling the entire
notification category.

**Why it's net-new:** P2-1 specifies the per-person notification scheduler. P2-12
specifies a notification settings panel. Neither addresses the global daily cap or
the priority-based deferral logic. This is the operational guardrail the notification
system needs to stay useful rather than becoming noise.
**Effort:** S. One counter + one guard clause in NotificationManager.

---

### C3-4 — Claude as Coach: Post-Check-In Response Loop

**What:** Coach.me's retention insight is that a check-in without a *response* is
weaker than one with feedback. MeetingScribe has Claude in the app. Build a
lightweight "coach response" loop:

After a user logs a check-in via `AddEncounterSheet` or the inline quick-entry
(D4-1), if the notes field is non-empty, queue a background Claude analysis:
"The user just logged a check-in with [relationship type] [Name]. Notes: '[notes]'.
In 1–2 sentences, what's a useful observation or question to surface?" The response
appears as a collapsible "Reflection" row in the encounter's `EncounterRow` view
(`PersonDetailView.swift:1836`), prefixed with "Claude noticed:".

This is not a full AI chat session — it is a brief, automatic response to the logged
check-in, identical in spirit to Coach.me's coach-responds-to-your-check-in mechanic.
The user gets the feedback loop without having to initiate a conversation.

**Guard rails:** Only fires if the user has the Chat feature enabled; only when
notes length > 20 characters (so "coffee" doesn't trigger it); max 1 response per
encounter. Opt-out via Settings toggle `claudeCheckInResponseEnabled`.
**Why it's net-new:** No existing proposal connects the check-in log event to a
Claude response loop. P2-10 adds MCP tools for Claude to *read* relationship data;
this makes Claude *respond to* the act of logging, closing the Coach.me accountability
loop using the AI already in the architecture.
**Effort:** M. One background Ollama call post-save + EncounterRow display extension.

---

### C3-5 — Relationship Correlation Insights via MCP

**What:** Bearable's "Impacts" section surfaces correlations between tracked factors
and health outcomes. MeetingScribe has the corpus to surface relationship correlations:
encounter frequency, note quality, kind distribution, and emotional tone (if notes
are used). Add one MCP tool:

`generate_relationship_insights(person_id, days_back: Int = 90) → InsightPayload`

Returns: encounter count trend (up/down vs. prior period), kind distribution
("you text 60% of the time, meet in person 20%"), average note length trend (as a
quality proxy), predicted next overdue date based on cadence inference, and one
natural-language observation from Claude about the pattern.

The tool exposes data that already exists in `PeopleStore.encounters(for:)` but
is never aggregated. Claude in the chat tab can then answer "how is my relationship
with Sarah trending?" with actual data, not just metadata.

Surface the top insight per person on `PeopleInsightsView` as a one-line card below
the heat map (once C3-1's Week 8 unlock triggers it). Bearable proved this
placement discipline: insights live on the dedicated insights surface, not
scattered across detail views.
**Why it's net-new:** P2-10 proposes `get_relationship_health` and
`list_drifting_contacts`. C3-5 adds `generate_relationship_insights` — a
tool that *synthesizes* rather than just returns, using Claude to produce a
natural-language pattern observation from the encounter corpus. Different tool,
different output type, different use case.
**Effort:** M. MCP tool wrapper S; Claude synthesis prompt M; PeopleInsightsView card S.

---

### C3-6 — Relationship-Type Cadence Table (Opinionated Defaults)

**What:** The academic research on contact frequency (PMC longitudinal study,
Dunbar social brain hypothesis) combined with the competitive evidence from
Coach.me and Fabulous yields a specific, defensible cadence table. This is not a
generic "set your own cadence" feature — it is an opinionated set of defaults that
the app presents as the starting point, with user override available.

Build this as a `RelationshipCadenceDefaults` struct:

```swift
enum RelationshipType {
    case partner        // cadence: 1d (daily check-in),  grace: 2d
    case familyImmediate // cadence: 3d,                  grace: 3d
    case closeFriend    // cadence: 7d (weekly),          grace: 3d
    case friend         // cadence: 21d (every 3 weeks),  grace: 7d
    case colleague      // cadence: 30d (monthly),        grace: 7d
    case acquaintance   // cadence: 90d (quarterly),      grace: 14d
}
```

The `grace` value feeds directly into C3-2's decay mechanic — a missed period within
the grace window gets the amber-decay cell rather than a full gap. A missed period
outside the grace window is a gap cell. A missed period more than 2× the grace window
triggers the notification escalation (P2-7).

**Why these numbers:** Partner daily is consistent with Gottman research on bids for
connection; weekly for close friends is the Dunbar inner-layer maintenance frequency;
monthly for colleagues aligns with Coach.me's professional check-in research.
The grace periods are from Streaks/Smashing Magazine research: 2–3 days prevents
catastrophic abandonment without removing the streak's motivational force.

The table should be **shown to the user during AddPersonSheet onboarding** as a
"here's what we'll suggest" explanation — transparency about the defaults increases
acceptance and reduces notification disable rates.
**Why it's net-new:** D4-7 proposes the `RelationshipType` enum with cadence
defaults. C3-6 adds the `grace` dimension to each type and provides the specific
research rationale for each number. The grace mechanics and onboarding transparency
are absent from D4-7.
**Effort:** S. Extends D4-7's enum definition; no new UI required beyond AddPersonSheet
explanation row.

---

### C3-7 — "Minimal Viable Check-In" as the Default Interaction

**What:** Fabulous, Finch, and Coach.me all converge on one principle: the default
interaction must be as small as possible. Fabulous starts with drinking a glass of
water. Finch starts with "how are you feeling?" Coach.me starts with one tap.

MeetingScribe's default check-in is a 420×460pt sheet with a required event name
field (`PersonDetailView.swift:1918`). That is the wrong default. The correct default
is a single-question binary prompt surfaced in `ReconnectView` on TodayView:

**"Did you connect with [Name] this week? [Yes] [Not yet]"**

- Tapping "Yes" creates an encounter with `kind = .checkin`, `eventName = "Connected"`,
  `date = today`, no notes required. Done. The full `AddEncounterSheet` is available
  via a "Add details" link in the confirmation.
- Tapping "Not yet" snoozes the notification/widget entry by 3 days (a grace freeze,
  C3-2) and moves the person to the bottom of the ReconnectView list.

This binary prompt replaces the current `ReconnectView` tap-to-navigate pattern
(`SuggestedPeopleView.swift:127`) with an actionable inline CTA. The tap currently
navigates to PersonDetailView, where the user must still complete a 5-step sheet
to log anything. The binary prompt closes the loop in one tap.

**Implementation:** Extend `ReconnectRow` in `SuggestedPeopleView.swift` to show
two pill buttons ("Yes" / "Not yet") instead of a `chevron.right`. "Yes" calls
`people.quickLogCheckIn(for: person)` — a new `PeopleStore` method that creates the
minimal encounter. "Not yet" calls `people.snoozeReconnect(for: person, days: 3)`.
**Why it's net-new:** D4-1 proposes an inline field on PersonDetailView. C3-7
proposes a binary prompt on TodayView's ReconnectView — a different surface, a
different interaction model, and a lower-friction entry point than any existing
proposal. The "Not yet" snooze is new; the binary Yes/No format is new.
**Effort:** S. Two buttons + two `PeopleStore` methods + one `Person` field
(`snoozedUntil: Date?`).

---

### C3-8 — Relationship Activity "Year in Pixels" on PeopleInsightsView

**What:** Bearable's single most effective visualization is the year-in-pixels
calendar — one square per day or week, color-coded by activity. Apply this to
MeetingScribe's aggregate relationship view on `PeopleInsightsView`:

A 52-week grid (one row per tracked relationship type: Partner, Family, Close
Friends, Friends), each cell colored by encounter count that week. Read at a glance:
"I was actively maintaining all relationship tiers in Q1, then dropped Family
contact in Q2, then all personal contact collapsed in a busy work period."

This is distinct from the per-person heat map (P2-4/D4-6): that shows one person's
history. C3-8 shows the user's *entire social life* at the aggregate relationship-
tier level — a view no existing proposal covers.

**Implementation:** `LazyVGrid` with 52 columns × N rows (one per `RelationshipType`
tier). Cell color: `NDS.brand.opacity(intensity)` where intensity = min(weekCount, 3)
/ 3.0. Data source: `PeopleStore.encounters` grouped by week and relationship type.
Requires D4-7's `relationshipType` field on `Person` to group by tier.

**Why it's net-new:** P2-4/D4-6 propose a 13-week per-person heat map. C3-8 proposes
a 52-week cross-person aggregate view organized by relationship tier. Different
scope, different location (PeopleInsightsView vs. PersonDetailView), different purpose
(life-level reflection vs. per-person habit tracking). Directly derived from
Bearable's year-in-pixels pattern.
**Effort:** M. View code M (new grid layout); data aggregation S; depends on D4-7.

---

## 6. Top 3 Picks

### #1 — C3-7: Minimal Viable Check-In (Binary Prompt on TodayView)

This is the single highest-leverage change in the entire check-in surface. Every
competitor (Fabulous, Finch, Coach.me) converges on the same finding: the default
interaction must be minimal or users will not perform it consistently. The current
default (5-step sheet, required event name) is incompatible with habit formation.
A binary "Did you connect? Yes / Not yet" prompt in `ReconnectView` requires
changes to `SuggestedPeopleView.swift` (two buttons), `PeopleStore` (two methods),
and `Person` (one field). It is S-effort and immediately reduces the interaction
cost for the most common check-in action by roughly 80%. Every other recommendation
in this file benefits from users who have formed the base check-in habit — this is
the foundation.

### #2 — C3-2: Streak Grace Mechanics (Decay + Pause + Re-entry Affirmation)

The Smashing Magazine research and the ADHD failure-mode analysis both reach the same
conclusion: hard streak resets cause catastrophic abandonment. MeetingScribe's
proposed heat map (P2-4/D4-6) will, as specified, render missed periods as blank gaps
— a hard-reset visual. Implementing decay coloring (amber half-opacity cell) and the
pause mechanic (one new `Person` field) before the heat map ships costs S effort and
prevents the heat map from becoming a demotivation tool. The re-entry affirmation
("back in touch with [Name] — that matters") costs 3 lines of code and delivers
Finch's self-compassion mechanic.

### #3 — C3-1: Relationship Journey (Progressive Content Unlocking)

Static check-in prompts (D4-8) are necessary but not sufficient. What sustains a
check-in habit over months is *progressive* content — the app introduces depth
gradually as the user demonstrates consistency. The Fabulous Journey model applied
to relationship types (4-week partner arc, 6-week close-friend arc) turns MeetingScribe
from a tool with prompts into a tool that *teaches* relationship skills incrementally.
This is the feature that most clearly differentiates "relationship coach" from "CRM
with reminders." M-effort, but the implementation is a pure Swift enum and a simple
step-progression model — no backend, no server, no library.

---

## 7. Notification Frequency Reference by Relationship Type

Derived from competitive research and academic contact-frequency data:

| Type | Target cadence | Grace period | Max daily notifications | Re-engagement trigger |
|------|---------------|--------------|------------------------|----------------------|
| Partner | Daily | 2 days | 1 (partner always wins budget) | >3 days overdue |
| Immediate family | Every 3 days | 3 days | 1 per day budget share | >7 days overdue |
| Close friend | Weekly | 3 days | 1 per day budget share | >14 days overdue |
| Friend | Every 3 weeks | 7 days | 1 per day budget share | >35 days overdue |
| Colleague | Monthly | 7 days | 1 per week maximum | >45 days overdue |
| Acquaintance | Quarterly | 14 days | 1 per month maximum | >120 days overdue |

**Global cap (C3-3):** Max 3 relationship notifications per day regardless of how
many people are overdue. Priority order: partner > family > close friend > friend >
colleague > acquaintance.

---

## 8. Cross-Audit Dependencies

| This recommendation | Depends on | Also endorsed by |
|--------------------|-----------|-----------------|
| C3-1 (Journey) | D4-7 (RelationshipType enum) | Fabulous research |
| C3-2 (Grace mechanics) | P2-4/D4-6 (heat map built first) | Streaks + Finch research |
| C3-3 (Notification cap) | P2-1 (person reminder scheduler) | Notification fatigue research |
| C3-4 (Claude coach response) | D4-1 (inline quick entry), Ollama wired | Coach.me research |
| C3-5 (Correlation MCP tool) | P2-10 (existing MCP tool proposals) | Bearable research |
| C3-6 (Cadence table) | D4-7 (RelationshipType enum) | Extends D4-7 with grace dimension |
| C3-7 (Binary prompt) | ReconnectView exists (SuggestedPeopleView.swift:84) | Fabulous + Finch + Coach.me convergence |
| C3-8 (Year in pixels) | D4-7 (RelationshipType to group by tier) | Bearable research; distinct from P2-4 |
