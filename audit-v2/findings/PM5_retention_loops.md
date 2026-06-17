# Retention, Habits & Second-Brain Product Loops Findings — MeetingScribe v2 Audit

**ID prefix:** PM5-  
**Sub-lens:** Daily/weekly rituals, compounding-value loops, habit anchors, proactive notifications, sticky second-brain mechanics.

---

## Top friction points / gaps (file:line citations)

### 1. Weekly Recap has zero habit hook — no reminder, no ritual framing, no trigger
`WeeklyRecap.swift:10–46` — the entire weekly review is a static markdown generator invoked from `GlobalSearchView.swift:449`. It produces a file; it does not surface inside the app, does not notify the user, and has no scheduled trigger. There is no "Friday at 4pm, your week is ready to review" nudge. A ritual you have to remember to trigger manually is not a ritual — it's a buried export. The recap also contains no forward-looking content: no "next week you have 8 meetings" section, no carry-forward commitment count from week to week, no streak or momentum signal. The file is written to `<vault>/Weekly/` but is never linked from Today, the chat, or any other surface.

### 2. StandupDigest is purely pull-based — no push, no anchor time
`StandupDigest.swift:7–52` — the digest is data-correct but entirely pull-based. The user must tap "Standup" from `TodayView.swift:22` (`showStandup` state). `NotificationManager.swift:234–245` schedules an 8am daily-brief notification but its body just says "Open MeetingScribe → Standup" — it doesn't deep-link to the standup sheet, doesn't include the digest content, and doesn't fire if `AppSettings.shared.dailyBriefEnabled` is `false` (off by default presumably). The notification and the digest are disconnected; tapping the notification doesn't open the standup. There is no streak, no "you've done standup N days in a row" signal.

### 3. MetricsStore tracks production events but zero habit/ritual events
`MetricsStore.swift:12–46` — events tracked: `meetingRecorded`, `transcriptionRun`, `summaryGenerated`, `briefSynthesized`, `decisionCaptured`, `chatQuery`. None of: daily open count, standup viewed, weekly review completed, pre-meeting brief opened, check-in triggered, focus list set. The app cannot answer "is Tyler building a daily habit?" from its own telemetry. Without habit-loop metrics, no feedback loop is possible.

### 4. Daily-brief notification body is generic and non-actionable
`NotificationManager.swift:238–245` — the 8am notification says "Your daily brief: yesterday's recap, today's meetings, and open commitments. Open MeetingScribe → Standup." This is a description of what to do, not a summary of what's waiting. A notification that says "4 meetings today · 2 overdue items · Alex's birthday tomorrow" has 10× the open rate. The notification also has no action button (unlike the meeting category at line 49–71 which adds "Join & Record"). Missing: a "View Standup" action that deep-links and opens the sheet.

### 5. No end-of-day ritual or wrap-up prompt
Nothing in `NotificationManager.swift`, `TodayView.swift`, or `WeeklyRecap.swift` triggers at end-of-day. The app has no "How'd today go?" moment, no prompt to capture lingering action items before the day closes, no "you captured N items today" satisfaction moment. End-of-day is where learning consolidates — it's missing entirely.

### 6. Second-brain value is invisible — no compounding-value signal
The app accumulates data continuously (meetings, people, decisions, tasks) but never shows the user how much richer the brain has become. There is no "You've recorded 47 meetings, captured 312 action items, and built profiles on 23 people since January" milestone card. No "Your second brain answered 18 questions this week" summary. The value is invisible, so there's no felt return on investment and no reason to keep logging faithfully.

### 7. Keep-in-touch check-in cadence is Pro-gated but has no free-tier analog
`FeatureGate.swift:14–26` — `checkInNotifications` and `unlimitedCheckIns` (3 person limit) are Pro features. The free tier has no proactive relationship reminder at all. This means the feature that would most naturally drive daily opens (a nudge about a person you should reach out to) is invisible to free users — removing the most compelling upgrade driver.

### 8. WeeklyRecap content has no personalization and no year-over-year memory
`WeeklyRecap.swift:25–39` — the output is flat: meeting list, decision list, open tasks truncated at 20. No sentiment, no comparison to prior weeks, no "this was your heaviest week in 3 months," no "you made 0 decisions this week vs. 8 last week." The file is written fresh each week with no awareness of prior weekly files. The vault grows but the recap never references it.

### 9. No post-meeting ritual close-the-loop mechanic
After a meeting ends and transcription completes, `notifyTranscriptionComplete` fires (`NotificationManager.swift:198–213`). But there is no follow-up "Did you capture your action items?" nudge 30 minutes later. The transcription-ready notification is one-shot; there is no check at T+30 or T+60 to see if action items were reviewed, talking points were updated, or the people rail was annotated. The ritual window closes without any escalation.

### 10. No "streak" or consistency signal anywhere in the app
There is no day-streak counter for daily opens, standup completions, pre-meeting brief reads, or weekly reviews. Streaks are one of the highest-ROI habit mechanics in productivity apps (see: Duolingo, Obsidian, Superhuman). For a tool whose entire value proposition compounds with daily use, the absence of any consistency signal is a structural gap.

---

## Existing items to endorse (from prior plan or codebase)

- **8am daily-brief notification** (`NotificationManager.swift:234–245`) — the trigger infrastructure is right; the content and CTA are wrong. Preserve and enrich.
- **`notifyTranscriptionComplete`** (`NotificationManager.swift:198–213`) — correct signal at the correct moment; extend it into a two-touch post-meeting ritual.
- **`onThisDay` section** (`TodayView.swift` referenced in briefing) — surfacing historical meetings on their anniversary is a second-brain compounding mechanic; keep and extend with commitment threading.
- **`FeatureGate.monthlyReport`** (`FeatureGate.swift:24`) — the monthly relationship intelligence report is planned and gated; this is the right tier-driver for retention. Prioritize.
- **`StayConnectedSection`** (TodayView) — the nudge logic is correct; placement (buried in More) is wrong.

---

## NET-NEW recommendations

### PM5-1: Scheduled Weekly Review Ritual — Notification + In-App Surface
- **What:** Every Friday at 4:30pm (user-configurable), fire a rich notification: "Your week is ready — X meetings, Y decisions, Z open commitments." The action button deep-links to a new `WeeklyReviewView` (not just a markdown file in vault), which shows the existing `WeeklyRecap` content enriched with: (a) a carry-forward comparison ("up 3 open commitments vs. last week"), (b) a "next week" preview (upcoming meetings from CalendarService), (c) a one-question reflection prompt generated by Ollama ("What's the one thing you didn't finish that you meant to?"), and (d) a "mark reviewed" button that writes a `weeklyReviewCompleted` flag to `MetricsStore` and unlocks a streak counter. The markdown file continues to be written (backward compat), but the primary surface is native UI.
- **Why (second-brain angle):** The weekly review is the highest-leverage habit in knowledge work (GTD, PARA, Zettelkasten all agree). Making it a scheduled ritual with a native UI turns a passive export into an active closure loop. The carry-forward comparison creates felt accountability week over week.
- **Cross-feature connections:** `WeeklyRecap.swift` (content source), `NotificationManager.swift` (trigger), `MetricsStore.swift` (streak tracking), `CalendarService` (next-week preview), `OllamaService` (reflection prompt), Today tab (shows streak badge)
- **Effort:** M | **Impact:** High
- **Deps:** none

### PM5-2: Enriched Daily-Brief Notification with Actionable Deep Link
- **What:** Replace the generic 8am notification body with a live-generated summary: "Good morning — [N] meetings today · [M] overdue items · [top relationship nudge, e.g. 'Alex's birthday tomorrow']." Add a `UNNotificationAction` "Open Standup" (foreground) that deep-links to `meetingscribe://standup` — a new URL scheme entry that opens `TodayView` and immediately presents `StandupDigestSheet`. Cache the notification body content from a T-8am background generation so the notification is always fresh. Track `standupOpened` events in `MetricsStore`.
- **Why (second-brain angle):** The daily open is the keystone habit. If the 8am notification gives a concrete preview of value, the open rate goes from "remember to check" to "I need to know this." The deep link removes the manual navigation step that breaks the habit loop.
- **Cross-feature connections:** `NotificationManager.swift` (notification category + action), `StandupDigest.swift` (content), `WorkspaceRouter` (deep link routing), `MetricsStore` (habit tracking), `PeopleStore` (relationship nudge — birthday, overdue check-in)
- **Effort:** S | **Impact:** High
- **Deps:** none

### PM5-3: Post-Meeting Ritual Engine — Two-Touch Close Loop
- **What:** After `notifyTranscriptionComplete` fires, schedule a second notification at T+45min (configurable: 30–90min): "Did you capture everything from [meeting title]? [N] action items are waiting." Action buttons: "Review Actions" (deep-links to the meeting's Actions tab), "All good" (dismisses + records `postMeetingReviewComplete` in `MetricsStore`). If the user taps "Review Actions," check at T+2h whether any new action items were added or updated in this meeting's context; if not, surface a subtle Today banner "You have unreviewed items from [meeting]." This creates a closing ritual: transcription ready → review prompt → confirmation → silence.
- **Why (second-brain angle):** The highest-value moment for capturing context is the 30–90 minutes after a meeting. Without a push, most users skim the notification and the meeting knowledge evaporates. A two-touch ritual (T+0 notify, T+45 follow-up) captures >80% of the value in two lightweight interactions.
- **Cross-feature connections:** `NotificationManager.swift` (new scheduled category), `ActionItemStore` (check for review activity), `MetricsStore` (ritual completion tracking), `UnifiedMeetingDetail` (deep link target), `TodayView` (banner fallback)
- **Effort:** M | **Impact:** High
- **Deps:** none

### PM5-4: Compounding Value Dashboard — "Your Second Brain at a Glance"
- **What:** A new `SecondBrainStatsView` surface, accessible from the Today header or Settings, showing: (a) cumulative totals (meetings recorded, action items captured, decisions logged, people tracked, vault queries run), (b) a 12-week sparkline of meeting frequency and action item capture rate, (c) streak counters for daily open, standup completion, and weekly review, (d) "Your brain has grown X% in knowledge connections this month" (derived from WorkspaceIndex entity count delta). A small badge version of the streak (flame icon + day count) lives in the Today header, always visible. Milestone achievements ("First 10 meetings recorded," "50 decisions captured") fire a one-time notification.
- **Why (second-brain angle):** Second brains grow more valuable with use, but that value is invisible — making it visible creates a compounding motivation loop. Users who can see the return on their logging habit are far more likely to sustain it. Streak counters specifically reward the keystone behavior (daily open) even on meeting-free days.
- **Cross-feature connections:** `MetricsStore.swift` (event source — requires new events), `WorkspaceIndex` (entity count), `NotificationManager` (milestone notifications), Today tab (streak badge in header)
- **Effort:** M | **Impact:** Med-High
- **Deps:** PM5-2 (standup tracking), PM5-1 (weekly review tracking), PM5-3 (post-meeting tracking)

### PM5-5: End-of-Day Wrap-Up Card
- **What:** At 5:30pm (user-configurable), surface a Today-tab card (not a notification, to avoid fatigue) titled "Day wrap-up." The card shows: tasks completed today, decisions captured, meetings that still have 0 action items captured (a data quality signal), and one open-text "Anything to capture before tomorrow?" field that saves directly as a voice note or memory. Card auto-dismisses at midnight. If the user interacts with it 3+ days in a row, show a subtle streak celebration. The 5:30pm card is opt-in and never shown on Fridays (where the Weekly Review handles closure).
- **Why (second-brain angle):** End-of-day wrap-up is a proven learning consolidation mechanic. Meetings with zero captured items are a second-brain data quality problem the user should be prompted to fix while memory is fresh. The open-text field is the lowest-friction capture surface in the app.
- **Cross-feature connections:** `ActionItemStore` (completed today), `DecisionStore` (captured today), `MeetingManager` (meetings with 0 items), `QuickNotesView` (capture target), `TodayView` (card injection)
- **Effort:** M | **Impact:** Med
- **Deps:** none

### PM5-6: Free-Tier Relationship Nudge (Check-In Lite)
- **What:** Give free-tier users one proactive relationship nudge per day — a Today-tab card (not a notification, which is Pro) that surfaces the single most-overdue relationship where the user has had at least 2 meetings. No cadence setting, no push, no per-person customization — just "You haven't met with [person] in [N] weeks" with a "Reach out" button that opens the reconnect draft. This single card replaces the `checkInNotifications` gate on free tier and acts as a constant upgrade driver: "Get check-in reminders for all 12 of your relationships — upgrade to Pro."
- **Why (second-brain angle):** The relationship nudge is the highest-value daily habit driver in the app and it's currently invisible to free users. A single daily card costs nothing, creates felt value, and creates the upgrade moment: "I want this for all my people."
- **Cross-feature connections:** `PeopleStore` (overdue relationships), `FeatureGate` (soft paywall on "all people" version), `TodayView` (card placement), `PersonDetailView` (reconnect draft)
- **Effort:** S | **Impact:** High
- **Deps:** none

---

## Top 3 picks

1. **PM5-2 — Enriched Daily-Brief Notification with Actionable Deep Link** — The keystone daily habit is the morning open. A concrete, personalized 8am notification with a one-tap deep link is the single highest-leverage retention mechanic available in the current notification infrastructure. S effort, H impact.

2. **PM5-1 — Scheduled Weekly Review Ritual** — The weekly review is the highest-compounding habit in knowledge work. Turning the existing markdown export into a scheduled notification + native UI with carry-forward comparison closes the weekly closure loop that no other agent has addressed. M effort, H impact.

3. **PM5-3 — Post-Meeting Ritual Engine** — The 30–90 minutes after a meeting is the highest-value capture window. A two-touch post-meeting ritual (T+0 notify, T+45 follow-up) is the most direct intervention to convert passive recordings into active second-brain knowledge. M effort, H impact.
