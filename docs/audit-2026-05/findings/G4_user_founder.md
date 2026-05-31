# G4 — Simulated End User: Startup Founder / Executive

> Lens: 8–12 back-to-back meetings a day (investors, customers, candidates, team). I have no hands free to take notes, I delegate constantly, I can't drop a ball, and I must remember every face. Recording has to be one tap, summaries have to be ready before the next call, and follow-ups have to go out in seconds. Privacy is load-bearing — half my calls are investor, legal, or HR.

## Full-app audit (through my lens)

I walked my real day against the live source.

**8:55am — "just start recording, I'm already late."** Today's primary CTA is a full-width `Record Meeting` button (`TodayView.swift:122-134`) and the `UP NEXT` hero gives me `Join & record` when the next event has a conference URL (`TodayView.swift:159-188`, `nextMeeting` at `:191-197`). This is genuinely good — one tap, no scope-hunting. **But** `Join & record` only renders `if m.conferenceURL != nil` (`:173`). Half my day is in-person (coffee with a candidate, a partner who walked into my office). For those, the hero shows only `Open`, and I'm back to the generic Record button which creates an **ad-hoc** meeting *unlinked from the calendar event I'm literally in*. So the recording loses the attendees, the title, and the brief — exactly the metadata that makes the follow-up fast later.

**The bigger friction: I have to remember to press record at all.** `AmbientMeetingDetector` exists and is good engineering — it watches `kAudioDevicePropertyDeviceIsRunningSomewhere` and fires `meetingScribeAmbientMeetingDetected` after sustained mic use (`AmbientMeetingDetector.swift:73-86`). But (a) it ships **off by default** (`isEnabled` reads a `UserDefaults` bool, `:39-41`), and (b) all it does is *post a notification* — it never offers to start recording the **calendar event that's happening right now**. On a back-to-back day the one thing I will reliably fail at is pressing a button between calls. The detector knows I'm in a meeting and the calendar knows *which* meeting — nothing joins them.

**9:30am — call ends, I have 4 minutes before the next.** This is the make-or-break window. The summary pipeline is local (Ollama) and runs on stop, which is right. But there is **no push of the finished summary to me**. I have to manually navigate back into Meetings → find the meeting → Summary tab to see it. Between two calls I won't do that. The `NeedsAttentionWidget` is a real win for the "don't drop a ball" anxiety (`NeedsAttentionWidget.swift:14-21` — overdue + due-today, soonest first) — but it's **date-driven only**. It does not surface "follow-up not yet sent" the way the plan's TDY-2 promised; there is no follow-up-sent state in the model anywhere (grep for `followupSent`/`markSent` → nothing). So my single most common dropped ball — *I recapped the call in my head but never sent the email* — is invisible to the app.

**9:32am — send the follow-up.** `FollowUpView` is the best-executed founder feature in the app. `Draft follow-up` generates a recap and `Open in Mail` builds a `mailto:` with **recipients prefilled from attendees** (`FollowUpView.swift:88-92`, `:138-150`). That's the 30-second follow-up I want. Three problems at speed: (1) it's buried — I have to open the meeting and find the Summary/Followup tab; the plan's DEF-3 ("promote Draft follow-up to the top") isn't done. (2) After I send, the app has **no idea I sent it** — it can't stop nagging me and it can't show "owed vs done." (3) `recipients` defaults to `[]` (`:16`) and is only populated if the caller passes attendee emails; for an ad-hoc recording (see 8:55am) there are no attendees, so the To: line is empty and my 30-second flow becomes a 3-minute one.

**Throughout the day — delegate the action items.** Action items carry an `owner` string (`ActionItem.swift:23`; settable via `setOwner`, `ActionItemStore.swift:502`) and the write-MCP exposes it (`create_action_item`/`update_action_item` with `owner`, `main.swift:787-820`). Good bones. But there is **no per-owner view** — no "everything I assigned to Sarah," no board grouped by owner (`ActionItemsView.swift` has no group-by-owner). As a founder I don't track tasks, I track *people I'm waiting on*. The data is there; the lens isn't.

**3pm — investor call I've taken twice before.** The `PreMeetingBriefView` pulls prior meetings with the same attendees and their open action items (`PreMeetingBriefView.swift:135-157`). Useful. But it is **email-matched meetings only** — it does **not** pull the Person record's memories, relationships, role/company, or "last thing I promised them." I have a rich CRM (`PeopleStore`, memories, encounters) and the one moment I need it — the 60 seconds before I greet someone — it's not surfaced. "Never forget a name/face" lives in People, but the brief doesn't open the dossier.

**Privacy.** Half my calls are investor/legal/HR. The app is local-first, which is the entire reason I'd trust it — but there is **no per-meeting privacy control**: no "don't transcribe this one," no auto-redaction, no exclude-from-summary. Every grep for `confidential`/`doNotRecord`/`ephemeral` returns only Swift access modifiers. A founder will eventually record a board comp discussion and want it handled differently.

## Existing-plan items I rank highest

1. **TDY-1 / TDY-2 (up-next hero + needs-attention)** — already largely shipped (`TodayView.swift:159`, `NeedsAttentionWidget.swift`). This *is* my command center between calls. Highest endorsement; just finish the gaps (in-person events, follow-up-owed surfacing).
2. **DEF-3 (promote "Draft follow-up" to the top)** — still not done. The 30-second follow-up only works if the button is the first thing I see on a finished meeting, not buried under a long summary.
3. **Send-the-follow-up-in-Mail (V3 §4, done)** — `mailto:` with prefilled recipients is exactly right. Endorse keeping and extending it.
4. **Write-capable MCP (done)** — lets me say "Claude, mark all of Sarah's items done and add a memory that we closed the round." For a delegating founder this is the highest-leverage surface in the app.
5. **NAV-1 click-into-detail (done in Today)** — between calls I cannot afford the old inline-expand reflow. Confirmed compliant (`TodayView.swift:33-38`, `selectedMeeting` push).

## NET-NEW recommendations

### U3-1 — Auto-record the calendar event in progress (not just notify)
**What/why:** When `AmbientMeetingDetector` fires (`AmbientMeetingDetector.swift:84`) *or* a calendar event's start time passes while a conference app is frontmost, match it to the calendar event that's happening **right now** and offer a single "Recording — keep / stop" banner that starts capture **linked to that event** (attendees, title, brief intact). Ship it on by default with a respectful first-run consent. Today the detector posts a notification into the void and the manual path makes an unlinked ad-hoc meeting.
**User value:** Eliminates the one thing I reliably fail at — pressing record — and preserves the metadata that makes every downstream step (follow-up recipients, brief, person links) fast.
**Effort:** M · **Impact:** High · **Depends on:** ENG-F (correct active-meeting publish); reuses `AmbientMeetingDetector`, `CalendarService`, `switchToRecording`.

### U3-2 — "Owe / Owed" board (delegation + follow-up tracking)
**What/why:** Add a follow-up `sent` timestamp to the meeting model and a view with two columns: **I owe** (follow-ups not sent + items where `owner == me`) and **They owe me** (action items where `owner != me`, grouped by owner). The `owner` field already exists (`ActionItem.swift:23`); there is no owner-grouped view today.
**User value:** Founders track people they're waiting on, not tasks. This is the literal "who do I owe / who owes me" board, and it makes a dropped follow-up impossible to hide.
**Effort:** M · **Impact:** High · **Depends on:** U3-3 (sent state) for the follow-up half.

### U3-3 — Follow-up "sent" state + Today nudge
**What/why:** Record when a follow-up was generated and when "Open in Mail" was invoked (`FollowUpView.swift:138`), persist a `followUpSentAt`, and add a "Follow-ups to send" row to `NeedsAttentionWidget` (`:15-21` currently date-only). Clear it once sent.
**User value:** Closes the most common founder failure — recapped in my head, never emailed. Turns "needs attention" into a true zero-inbox for relationships.
**Effort:** S · **Impact:** High · **Depends on:** none (small model addition).

### U3-4 — Person dossier in the pre-meeting brief
**What/why:** Extend `PreMeetingBriefView.computeBrief()` (`:135-157`) to also load each attendee's Person record: role/company, top memories, relationships, and "last thing I committed to them" (their open items where `owner == me`). Show face/photo if present. Today the brief is meeting-history only and never touches the CRM.
**User value:** The 60 seconds before I greet someone is when "never forget a name/face" actually pays off. Walk in knowing who they are and what I promised.
**Effort:** M · **Impact:** High · **Depends on:** PeopleStore lookup by attendee email (exists).

### U3-5 — Between-meeting summary push
**What/why:** When finalize completes, fire a local notification ("Summary ready: Acme investor sync — 2 action items, draft follow-up") with deep-link buttons straight to the summary and the follow-up draft. `NotificationManager` already exists.
**User value:** I get the recap pushed to me in the 4-minute gap instead of having to remember to navigate back. This is the difference between the app working on a busy day and not.
**Effort:** S–M · **Impact:** High · **Depends on:** finalize completion hook (`MeetingPipelineController`).

### U3-6 — One-tap delegate from a summary action item
**What/why:** On each inline action item in the Summary tab, add a "Delegate" affordance that sets `owner` and opens a prefilled email/Slack handoff ("Sarah — can you own this from today's call? Context: …"). Today `setOwner` exists (`ActionItemStore.swift:502`) but there's no UI gesture that combines assign + notify.
**User value:** I delegate live, in the gap, without typing. Assign and notify in one tap.
**Effort:** M · **Impact:** Med · **Depends on:** U3-2 (owner board) for the tracking half.

### U3-7 — Pipeline view (investor / customer / candidate stages)
**What/why:** A board that groups People (and their meetings) by a `pipeline`/`stage` tag — Investors (intro → pitch → DD → committed), Customers (lead → demo → trial → closed), Candidates (screen → onsite → offer). Tags already exist on people; meetings already link to people. This is a CRM-pipeline overlay on data I already have.
**User value:** Founders live in pipelines. Seeing "3 investor calls stalled at DD, last contact 12 days ago" is the report I'd open every morning.
**Effort:** L · **Impact:** Med-High · **Depends on:** stay-in-touch/last-contact data (partly present via `ReconnectView`).

### U3-8 — Fast voice memo between meetings ("Voice note" → auto-route)
**What/why:** Voice notes exist and transcribe+polish well (`QuickNotesController.swift:57-92`). Net-new: let a voice memo *create action items / a person memory* via NL parsing ("remind me to send the deck to Acme, and note that their CTO used to be at Stripe"). Route the parsed output to the right store automatically.
**User value:** In the hallway between calls I just talk; the app files it. No typing, no tab-switching.
**Effort:** M · **Impact:** Med · **Depends on:** action-item NL parser (overlaps planned ⌘N parsing).

### U3-9 — Private / sensitive meeting mode
**What/why:** A per-meeting "Sensitive" toggle (set from the calendar event or live banner) that keeps audio + transcript local-only, excludes the meeting from any export/Drive sync, optionally skips the summary, and marks it so it never appears in shared boards. Nothing like this exists today.
**User value:** Investor comp talk, legal, HR, term-sheet calls. The local-first promise is *why* I'd record those — but I need an explicit, visible guarantee per meeting.
**Effort:** M · **Impact:** Med-High · **Depends on:** export/sync gating (`MeetingExporter`, `GoogleDriveService`).

### U3-10 — "End of day" relationship recap
**What/why:** Extend the planned end-of-day recap (V3 TDY-6) with a founder cut: who I met today (with faces), follow-ups still owed, action items I assigned and to whom, and "new people to add to the CRM." One screen to close the loop before I leave.
**User value:** The 6pm "did I drop anything?" check in 20 seconds.
**Effort:** M · **Impact:** Med · **Depends on:** U3-3 (sent state), U3-2 (owner board).

## Top 3 picks

1. **U3-1 — Auto-record the calendar event in progress.** The single highest-leverage change for this persona. The detection and calendar pieces already exist; joining them removes the only step a busy founder reliably fails. Everything downstream (linked attendees → fast follow-up → person links) depends on the recording being attached to the right event.
2. **U3-5 — Between-meeting summary push.** A finished summary I have to go find is a summary I won't read on a back-to-back day. Pushing it (with deep links to the follow-up) is what makes the 4-minute gap actually usable. Small effort, huge perceived value.
3. **U3-2 + U3-3 — Owe/Owed board with follow-up "sent" state.** Founders track people, not tasks. The `owner` field is already there; adding a sent-state and an owner-grouped view turns the app from a note-taker into a "you will never drop a ball" system — the core promise for this user.

**Single highest-priority recommendation overall:** U3-1 — auto-record the in-progress calendar event (detector + calendar join), on by default with consent. It's the difference between the app capturing my day and capturing the half of it I remembered to press record on.
