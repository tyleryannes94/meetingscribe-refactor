# G2 — Senior PM, Activation / Retention & Engagement Loops

> Lens: what produces the first "aha," what makes someone open MeetingScribe *tomorrow*, and which loops compound as meeting + CRM history accumulates.

## Framing: the three loops this product needs

1. **Activation moment (aha):** the user records (or imports) one meeting and gets back a *summary + action items they'd otherwise have hand-typed*. Everything before that is setup cost; everything after is retention.
2. **Core habit loop:** calendar event approaches → notification fires → Join & Record → meeting ends → transcript/summary ready notification → review + check off action items → draft follow-up. The trigger (calendar) is external and reliable, which is the product's biggest retention asset.
3. **Compounding-value loop:** every recorded meeting enriches the People CRM (`lastInteractionAt`, encounters, memories) and the action-item backlog. Pre-meeting briefs, stay-in-touch nudges, and "what did we decide last time" all get *better the longer you use it*. This is the moat — and it is under-exploited today.

## Full-app audit (through my lens)

**The trigger side of the loop is strong; the return side is weak.** `NotificationManager.syncScheduled` fires ~10s before each calendar meeting with a Join & Record action (`NotificationManager.swift:78-128`), and `notifyTranscriptionComplete` closes the loop with a "Meeting ready to review" banner (`NotificationManager.swift:133-143`). That's exactly the right pair of hooks. But these are the *only two* scheduled/triggered notifications in the app. There is **no proactive re-engagement when the app is closed and no meeting is imminent** — no morning brief, no "you have 3 follow-ups un-sent," no overdue-task ping. A user with a light meeting day gets zero reason to reopen.

**Activation is gated behind a cold first run with nothing to show.** `TodayView.emptyState` (`TodayView.swift:286-301`) only appears when the calendar is empty and offers "Import meeting recording." A brand-new user with no recordings and no CRM sees empty `NeedsAttentionWidget`, `ActionItemsWidget`, `SuggestedPeopleView`, and `ReconnectView` — all of which `return EmptyView()` when empty (`NeedsAttentionWidget.swift:24`, `SuggestedPeopleView.swift:12`). So Today is a blank slate until the *first meeting finishes processing*. There is no "record a 30-second test meeting" or sample-data path to manufacture the aha before the user's first real call. Time-to-aha is entirely at the mercy of their calendar.

**The compounding surfaces exist but are passive and single-entry-point.** `ReconnectView` (stay-in-touch) and `SuggestedPeopleView` only live inside the Today feed (`TodayView.swift:75-78`); if the user lands on Meetings or Tasks, they never see them. `PreMeetingBriefView` (`PreMeetingBriefView.swift`) is genuinely the best compounding feature in the app — it surfaces prior meetings + open action items with the same attendees — but it only renders when a user *manually taps into an upcoming meeting's detail*. Nothing pushes the brief *to* the user before a call. The notification 10s before a meeting says "Starting now" (`NotificationManager.swift:106`), not "Here's what you owe these people."

**`lastInteractionAt` — the engine of the stay-in-touch loop — is only bumped from explicit encounters.** It's updated in `PeopleStore.swift:449-450` (recordEncounter) and merged on dedupe (`:899-901`). It is **not** bumped when a person is merely an attendee of a recorded meeting, nor from message history (`get_person_messages` exists in MCP). So the "haven't talked to X in 30 days" nudge (`SuggestedPeopleView.swift:89`) will fire false positives for anyone you meet regularly but never manually log an encounter for — eroding trust in the one feature that's supposed to feel magic. The threshold is also a hard-coded 30 days with no per-person cadence.

**No streak, no recap, no sense of accumulated value.** `MASTER_PLAN_V3` lists TDY-6 "end-of-day recap" as P2 and never built it; the only "weekly review" in the codebase is a *static markdown note template* (`NoteTemplate.swift:92-108`) the user has to manually fill in — not a generated ritual. The MenuBarView (`MenuBarView.swift`) shows upcoming meetings but nothing about *what you accomplished* (meetings recorded this week, tasks closed, follow-ups sent). The app never reflects its own value back to the user, which is the cheapest retention mechanic available to a local-first app that can't email them.

**Follow-up is a dead-end without a sent-state.** `FollowUpGeneratorService` drafts an email/Slack recap (`FollowUpGeneratorService.swift:10-20`), and the plan endorses "send in Mail" (done). But there is no record of *whether a follow-up was sent*, so it can never appear in a "needs attention" list or a recap. A drafted-but-unsent follow-up is exactly the kind of forgotten commitment a retention-focused product should resurface.

**Notifications are not authorized proactively in the habit-critical path.** `requestAuthorization` (`NotificationManager.swift:38-45`) is wired but the whole loop depends on the user having granted notification permission during onboarding; if skipped, the trigger half of the core loop silently dies and there's no re-prompt.

## Existing-plan items I rank highest (through my lens)

1. **TDY-1 "Up next" hero** (V3 §3.4, *already built* — `TodayView.swift:159-197`). This is the single most important daily-glance object: it makes "open the app before a meeting" a habit. Endorse keeping it, but it currently only shows when *not* recording and needs the brief attached (see P2-2).
2. **TDY-2 "Needs attention" block** (built — `NeedsAttentionWidget.swift`). Overdue/due-today tasks are the strongest non-calendar reason to reopen. Highest-leverage existing retention surface after Up Next.
3. **"Stay in touch" nudges** (V3 §4, built as `ReconnectView`). The flagship compounding-CRM loop. Endorsed — but it's only as good as `lastInteractionAt` accuracy (see P2-1), and it needs a re-engagement push, not just passive display.
4. **TDY-6 End-of-day recap** (V3 §3.4, *not built*). The cheapest retention mechanic in the plan and the only one that reflects value back. I'm promoting it from P2 and expanding it (P2-3).
5. **Write-capable MCP + send-follow-up in Mail** (done). These turn drafts into completed loops; necessary precondition for tracking follow-up sent-state (P2-6).
6. **Pre-meeting brief** (built — `PreMeetingBriefView.swift`). The best compounding feature; under-surfaced. I want it *pushed*, not pulled (P2-2).

## NET-NEW recommendations

### P2-1 — Make `lastInteractionAt` truthful: derive it from all signals, add per-person cadence
**What/why:** Bump `lastInteractionAt` whenever a person is an attendee of a recorded meeting and from `get_person_messages` lastDate — not only from manual encounters (`PeopleStore.swift:449`). Then replace the global 30-day threshold (`SuggestedPeopleView.swift:89`) with a per-person `reconnectCadenceDays` (default inferred from historical interaction frequency: someone you saw weekly for 3 months and then went quiet should surface at ~3 weeks, not 30 days). **User value:** the stay-in-touch nudge stops crying wolf and starts feeling like a personal chief-of-staff — the core trust requirement for the compounding loop. **Effort:** M. **Impact:** High. **Depends on:** none (pure data-layer + threshold change).

### P2-2 — Push the pre-meeting brief instead of waiting for a tap
**What/why:** When a meeting notification fires (`NotificationManager.syncScheduled`), enrich the body with the brief's headline facts ("3 open items you owe Sarah; last met 12 days ago") and add a "Prep" action that opens `PreMeetingBriefView` directly. Optionally fire a separate, earlier "Prep for your 2pm" notification 15–30 min before meetings that *have* prior context. **User value:** turns the best compounding feature from a thing-you-must-remember-to-open into a proactive habit trigger; you walk into meetings prepared without lifting a finger. **Effort:** M. **Impact:** High. **Depends on:** existing `PreMeetingBriefView` compute logic (reuse `computeBrief`).

### P2-3 — Generated daily/weekly recap with a real "Weekly Review" ritual
**What/why:** Build TDY-6 for real and extend it. A daily end-of-day card on Today (meetings recorded, tasks closed, follow-ups still un-sent) *and* a Friday "Weekly Review" that auto-populates the existing `weekly-review` note template (`NoteTemplate.swift:92`) with generated Highlights / What slipped / Next week's focus from the week's meetings + closed/missed tasks — instead of an empty fill-in form. Offer it via a Friday-afternoon notification. **User value:** reflects accumulated value back (retention), and converts a static template into a weekly habit. **Effort:** M. **Impact:** High. **Depends on:** P2-6 (follow-up sent-state) for the "un-sent" line; otherwise standalone.

### P2-4 — Activation: a guided "record your first meeting" + instant sample brief
**What/why:** On first run with zero recordings, replace the blank Today with a one-tap "Try it: record this 30-second test note" (reuse `startQuickNote`) that runs the full transcribe→summarize pipeline so the user hits the aha in under two minutes — *before* their first real calendar meeting. Pair with a single pre-seeded sample meeting so `PreMeetingBriefView`, action items, and the People graph aren't empty on day one. **User value:** collapses time-to-aha from "whenever your next recorded meeting happens" to immediate; dramatically lifts activation. **Effort:** M. **Impact:** High. **Depends on:** onboarding flow (`OnboardingSheet.swift`).

### P2-5 — Morning brief notification (proactive re-engagement when no meeting is imminent)
**What/why:** A once-daily (user-set time, default 8am) local notification: "Today: 2 meetings, 3 tasks due, 1 person to reconnect with." Tapping opens Today. This is the missing re-engagement hook — the app currently only notifies *reactively* (meeting starting, transcript ready). **User value:** gives a reason to open the app on light-meeting days; anchors the daily habit independent of the calendar. **Effort:** S–M. **Impact:** High. **Depends on:** none (extends `NotificationManager` with a `UNCalendarNotificationTrigger`).

### P2-6 — Follow-up lifecycle: track sent-state and resurface forgotten ones
**What/why:** Add a `followUpSent`/`followUpDraftedAt` field per meeting. Surface "drafted but not sent" follow-ups in `NeedsAttentionWidget` and the recap. After a meeting ends, if no follow-up is sent within ~24h and there were action items, nudge once. **User value:** closes the most common forgotten commitment — the recap email you meant to send — which is precisely the kind of dropped ball this product should catch. **Effort:** M. **Impact:** High. **Depends on:** send-follow-up-in-Mail (done) to set sent-state.

### P2-7 — Surface forgotten *commitments to people* ("you owe X")
**What/why:** Action items already carry an owner. Build a person-scoped view of *open commitments you owe to a specific person* and surface it (a) in `PreMeetingBriefView` (already partially there via open items), and (b) as a Today block "Owed to others: 4 open promises." Distinct from "Needs attention" (due-date-driven) — this is relationship-debt-driven. **User value:** the relationship graph turns task backlog into "don't drop the ball with people who matter," a uniquely sticky compounding signal. **Effort:** M. **Impact:** Med. **Depends on:** action-item owner attribution; benefits from speaker diarization (planned).

### P2-8 — Streak / consistency mechanic, framed as a habit not a game
**What/why:** A subtle "recorded meetings 4 days running" / "reviewed all action items 3 weeks straight" indicator in the recap and MenuBarView. Avoid gamified vanity; tie it to *behaviors that produce value* (reviewing tasks, sending follow-ups), not raw app-opens. **User value:** loss-aversion nudge to maintain the habit; cheap to build on top of the recap. **Effort:** S. **Impact:** Med. **Depends on:** P2-3 (recap) to host it.

### P2-9 — Make MenuBarView a glanceable re-engagement surface
**What/why:** The menu bar (`MenuBarView.swift`) already shows upcoming meetings. Add a "Today" summary line (tasks due, un-sent follow-ups, people to reconnect with) and a one-line "this week: N meetings, M tasks done." It's the always-present surface a closed-window user sees most. **User value:** re-engagement without opening the main window; reinforces the recap habit ambiently. **Effort:** S. **Impact:** Med. **Depends on:** P2-3, P2-6 for the data.

### P2-10 — Re-prompt for notification permission if the trigger loop is broken
**What/why:** If `notifyAtMeetingStart` is on but authorization was denied/skipped, the entire core loop's trigger silently dies. Detect denied authorization and show a gentle in-app banner on Today explaining that meeting reminders won't fire, with a one-tap path to System Settings. **User value:** protects the single most important retention mechanic from being silently disabled at onboarding. **Effort:** S. **Impact:** Med. **Depends on:** none.

### P2-11 — "Resume where you left off" / unfinished-meeting nudge
**What/why:** If a meeting was recorded but never reviewed (transcript opened? action items triaged?), or a recording crashed/recovered (crash recovery exists per V3 §1), surface a "1 meeting waiting for review" prompt on Today and in the menu bar. **User value:** catches the drop-off between record and review — the moment most value leaks out — and creates a return trigger. **Effort:** S–M. **Impact:** Med. **Depends on:** a per-meeting `reviewedAt` flag.

## Top 3 picks

1. **P2-2 — Push the pre-meeting brief into the notification.** It converts the app's best compounding feature from pull to push, riding the already-reliable calendar trigger. Highest impact per unit effort and directly strengthens the core daily loop.
2. **P2-1 — Make `lastInteractionAt` truthful with per-person cadence.** The entire stay-in-touch / compounding-CRM moat rests on this number being right; today it's bumped only from manual encounters and will misfire, killing trust in the flagship loop.
3. **P2-5 — Morning brief notification.** The single missing re-engagement hook; the app currently has no proactive reason to reopen on a light-meeting day. Cheap, and it anchors the daily habit independent of whether a meeting happens to be scheduled.

**Single highest-priority recommendation overall: P2-2 (push the pre-meeting brief).** It compounds with history, reuses code that already exists, rides the strongest existing trigger, and turns "I should have prepped" into "the app prepped me" — the clearest path to a daily-must-open habit.
