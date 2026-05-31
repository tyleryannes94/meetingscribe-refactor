# UX08 — Notifications, Follow-up & Action Surfacing

Senior-PM lens on the proactive edge of MeetingScribe: meeting-start notifications, Zoom/Meet auto-detect prompts, the follow-up generator/send flow, "Needs attention", and action-item surfacing on Today. The capture loop is solid; the *closing* loop (prompt → record → review → follow-up → done) leaks at every notification and never tracks whether the user actually sent anything.

## Lift from V4 (already in plan — relevant to this surface)

- **P2-2** — Push the synthesized pre-meeting brief into the meeting-start notification. Today `syncScheduled` (`NotificationManager.swift:104-110`) only sets a generic body ("Tap Join & Record…"). Rides the strongest existing trigger.
- **P2-6 / U3-3** — Follow-up lifecycle: track "sent" state and resurface forgotten ones. Confirmed *no* sent state exists anywhere (grep for `followUpSent`/`sentAt` returns nothing). This is the single biggest gap on my surface.
- **U3-1 / P1-9** — Auto-record the in-progress calendar event. Detector (`AppDetector`) + calendar already exist and are already joined for `autoStartIfNeeded` (`MeetingScribeApp.swift:232-241`); the notification path is the consent-aware fallback.
- **U3-5** — Between-meeting summary push with deep links. `notifyTranscriptionComplete` (`NotificationManager.swift:133`) fires but has no deep link or action button — tapping just activates the app at whatever screen was last open.

---

## UX improvements (5)

### UX8-1 — Make "Meeting ready" notification actionable (Review / Draft follow-up)
**Friction today:** `notifyTranscriptionComplete` (`NotificationManager.swift:133-143`) posts a banner with *zero* actions and `categoryIdentifier` unset, so it falls through to `UNNotificationDefaultActionIdentifier` — which, for a transcription notification, carries no `meetingJSON` payload (`handleAction:201-204`), so tapping just calls `NSApp.activate` and lands the user wherever they last were. They then navigate Meetings → find the meeting → open it → scroll to summary.
**Fix:** Add a `TRANSCRIPTION_READY` category with two foreground actions — "Review" and "Draft follow-up" — and attach the encoded `Meeting` payload (same pattern as `syncScheduled:111-114`). Route "Review" to open the meeting detail; "Draft follow-up" straight into `FollowUpView`.
**Clicks:** 4 (activate → Meetings → row → summary scroll) → **1** (tap action). 
**Effort:** S.

### UX8-2 — Follow-up not reachable from the "ready" notification or Today
**Friction today:** The follow-up generator only exists inside `MeetingSummaryTab.followUpButton` (`MeetingSummaryTab.swift:97-126`). To reach it from a fresh "Meeting ready" banner: activate app → Meetings tab → click meeting → Summary tab → "Draft follow-up…" = **4-5 clicks**, violating the 2-click-after-entering-a-meeting rule for the #1 post-meeting action.
**Fix:** Combine with UX8-1's "Draft follow-up" notification action, *and* add a "Draft follow-up" affordance to the past-meeting `MeetingCard` row on Today (the card already has a `switchToRecording` button at `MeetingCard.swift:211` — add a sibling). 
**Clicks:** 4-5 → **1-2**. 
**Effort:** S (button) + shares UX8-1's category work.

### UX8-3 — No "sent / copied" persistence cue on follow-ups
**Friction today:** `FollowUpView` tracks `copied` only as transient `@State` (`FollowUpView.swift:21,87,133`) — it resets the moment the sheet closes. There is no record that a follow-up was ever generated or sent for a meeting, so the user re-opens, can't remember if they sent it, and re-drafts. "Open in Mail" (`openInMail:138`) and `ShareLink` leave no trace at all.
**Fix:** Persist a lightweight `followUpSentAt: Date?` (or `lastFollowUpChannel`) on the meeting when the user hits Copy / Open in Mail / Share. Show a green "Sent · Apr 3" pill on the meeting card and at the top of `FollowUpView`. This is the minimum viable half of V4's P2-6.
**Clicks:** unchanged; removes a re-draft round-trip. 
**Effort:** small-M (needs one persisted field).

### UX8-4 — Impromptu prompt can't be silenced for the current call
**Friction today:** When the Zoom/Meet detector fires (`AppDetector.poll:63-65` → `notifyImpromptuDetected`), the notification offers only "Record Impromptu" and "Dismiss" (`NotificationManager.swift:62-68`). Dismiss clears *this* banner, but the detector only re-arms `lastDetectedSource` on session change — so a user who dismisses still gets re-prompted next time they rejoin. There's no "not this kind of call" / "snooze for this app" escape, which is the classic reason users disable detection entirely in Settings.
**Fix:** Add a third action "Don't ask for Zoom today" that sets a per-source suppression date `AppDetector` checks before calling `onImpromptuDetected`. Keeps the feature on instead of users nuking it.
**Clicks:** opening Settings to toggle off (3+) → **1** in-context. 
**Effort:** S.

### UX8-5 — "Needs attention" rows aren't deep-linkable; whole-row tap dumps to the Tasks tab
**Friction today:** Every interaction in `NeedsAttentionWidget` — the row tap (`NeedsAttentionWidget.swift:87 onTapGesture { onOpenFull() }`), the "Open" button, and "+N more" — does the same thing: `section = .actions`, dropping the user into the full Tasks board where they must re-find the item. The item already knows its `meetingTitle`/meeting; tapping it should open *that* item or its source meeting, not the whole board.
**Fix:** Make the row tap open the specific action item (or its source meeting detail) rather than the generic board; keep the header "Open" for the full board. Reuses the same router the rest of Today uses.
**Clicks:** board → scan/scroll → find item (3+) → **1** (row opens it). 
**Effort:** S (wire row to an `onOpenItem(item)` callback).

---

## Feature improvements (5)

### FT8-1 — "Snooze 5 min" on the meeting-start notification
**What/why:** Meeting-start fires 10s before start (`syncScheduled:101`). On a back-to-back day the user is still wrapping the prior call and can't act, so they swipe it away and forget. Add a "Remind me in 5 min" action that re-schedules the same payload.
**Value:** Recovers the most common miss — "I meant to record that." 
**Effort:** S. **Dep:** none (re-use existing payload + `UNTimeIntervalNotificationTrigger`).

### FT8-2 — Auto-draft follow-up the moment a summary completes
**What/why:** `pipelineController.onComplete` (`MeetingScribeApp.swift:245`) already fires when summary+transcript finish. Kick off a background `FollowUpGeneratorService.generate` for the email channel and cache the draft, so when the user taps "Draft follow-up" it's *already written* instead of a cold "Drafting…" spinner (`FollowUpView.swift:53`).
**Value:** Turns a 10-20s wait into instant; makes "the app prepped me" real. 
**Effort:** small-M. **Dep:** Ollama running (already gracefully handled by `OllamaService`).

### FT8-3 — Slack channel actually delivers (or labels itself "copy only")
**What/why:** The Slack channel in `FollowUpView` (`FollowUpSuggestion.Channel.slack`) generates a message but the only outputs are Copy and Share — there's no "Open in Slack." Per V4 P4-3 the Slack path is fake/draft-only today. Minimum lift: add an "Open in Slack" via `slack://` deep link to a chosen channel, or relabel the button so users don't expect a send.
**Value:** Removes the "where did it go?" dead-end; sets honest expectations. 
**Effort:** S (deep link) — full bot delivery is the larger P4-3.

### FT8-4 — "Pending follow-ups" surface on Today
**What/why:** Pair with UX8-3's `followUpSentAt`. Add a small Today widget (sibling of `NeedsAttentionWidget`) listing recent meetings with a summary but no follow-up sent — "3 meetings awaiting follow-up." Surfaces the forgotten-follow-up resurfacing half of V4 P2-6 where the user already looks.
**Value:** Closes the loop the app currently drops entirely; high retention value. 
**Effort:** small-M. **Dep:** FT8-3/UX8-3 sent-state field.

### FT8-5 — Detection status chip ("You're in a Zoom call · Record")
**What/why:** `AppDetector` already publishes `currentCallSource` and fires `onStatusUpdate` every 15s (`AppDetector.swift:19,56`) but nothing renders it. Surface a live chip in the Today header / menu bar when a call is detected, with an inline Record button — so users who keep notifications off still get a one-click capture path, and the prompt isn't the *only* entry point.
**Value:** Always-visible, non-interrupting alternative to the modal-ish notification; great for notification-averse users. 
**Effort:** S (data already published; just a view + existing `startImpromptu`).

---

## Top 3 picks

1. **UX8-1 + UX8-2 (actionable "Meeting ready" → Review / Draft follow-up)** — one new notification category with a payload turns a dead 4-5-click banner into a 1-tap path to the #1 post-meeting action. Pure S, highest leverage.
2. **UX8-3 / FT8-4 (follow-up sent-state + "pending follow-ups" on Today)** — the app currently has *zero* memory of whether you followed up; a single persisted field plus a Today widget closes the biggest open loop on this surface.
3. **FT8-2 (auto-draft follow-up on summary completion)** — reuses an existing completion hook to make the follow-up instant instead of a cold spinner; "the app prepped me."

**Single highest-value low-lift win:** **UX8-1** — adding a category + `Meeting` payload to `notifyTranscriptionComplete` so the "Meeting ready" notification carries "Review" and "Draft follow-up" buttons. Hours of work, removes a 4-5-click detour on the most-fired, highest-intent notification in the app.
