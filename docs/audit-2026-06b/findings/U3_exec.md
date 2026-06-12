# End-User Persona — Founder/Exec (back-to-back days)
> 8+ meetings a day, investors/customers/team interleaved; any surface that doesn't pay off inside a 10-second attention budget doesn't exist, and software must look as premium as the hardware it runs on.

## Full-app audit (through my lens)

I ran four concrete days through the app. Citations are from the live source.

### Scenario 1 — 7am coffee scan: "what does my day look like?"

I open the app with coffee in hand. I get a **15-section vertical feed** (`UI/TodayView.swift:52-106`): header, quick actions, up-next, needs-attention, today's meetings, action-items widget, follow-ups, commitments, decisions, on-this-day, recent notes, suggested people, stay-connected, reconnect. Reading order ≠ urgency order, and there is no representation of the day's *shape*. The only "shape" signal is a text subtitle — `"3 upcoming today · 1 earlier today"` (`TodayView.swift:614-623`). I can't see: when my first gap is, which meetings are external (investor/customer) vs internal, whether anything overlaps. Notion Calendar answers all of that in one strip; here I'd have to scroll and mentally assemble it.

What's genuinely good: the **"Up next" hero card** with one-tap Join & Record (`TodayView.swift:441-467`) is exactly the right instinct — title, relative start, two buttons. And `NeedsAttentionWidget` is correctly scoped (overdue + due-today only, renders nothing when empty — `UI/NeedsAttentionWidget.swift:15-25`). The **Standup digest** (`UI/StandupDigest.swift:10-52`) is instant and structured, but it's hidden behind a button → sheet → markdown wall whose main affordance is "Copy" (`StandupDigest.swift:66-72`). That's a clipboard tool, not a morning ritual.

### Scenario 2 — 30 seconds between meetings: "what do I need for the next one?"

This is the moment that decides whether an exec keeps the app. Today the path is: main window → Meetings → select the upcoming event → wait while a spinner says "Synthesizing brief…" (`UI/PreMeetingBriefView.swift:44-47`). The brief is generated **on view-appear** (`PreMeetingBriefView.swift:38`, `:184-190`), not ahead of time, and it's held in `@State` — never persisted, so it regenerates every relaunch. Worse, between back-to-backs is exactly when Ollama is busy summarizing the meeting that just ended, so the brief competes with the pipeline for the same local LLM.

The brief content also omits the humans: the doc comment promises "Attendee People-record links (if they exist in PeopleStore)" (`PreMeetingBriefView.swift:8`) but the body renders only the synthesized text, open items, and prior meetings (`PreMeetingBriefView.swift:27-40`) — no person chips, no role/company, no relationship health, nothing that tells me *who I'm about to sit down with*. For a people-first audit, the single people-first surface forgot the people.

Meanwhile the **menu bar** — the natural 30-second surface — is a bare list: title + time range + a record icon per row (`UI/MenuBarView.swift:30-44`, `:144-182`). No countdown, no "you owe them X", no brief access. Click-cost to prep for the next meeting: ~4 clicks + an LLM wait. It should be 1 click and 0 wait.

### Scenario 3 — Friday: "what did I commit to this week?"

The Commitments section on Today (`TodayView.swift:167-211`) is the right idea, but: (a) ownership is decided by fragile string-matching of the `owner` field against my name and aliases (`TodayView.swift:159-165`) — one "T. Yannes" in a summary and the split lies to me; (b) each column shows `prefix(3)` items (`TodayView.swift:190`) with **no "show all" affordance** — the rest are simply invisible; (c) there's no time scoping at all — it's every open item ever, so "this week" is unanswerable. The Standup digest covers yesterday/today only (`StandupDigest.swift:16-21`). There is literally no surface in the app that answers "what did I commit to this week," even though all the data exists.

### Scenario 4 — phone, walking to a customer meeting: "what did they say last quarter?"

The mobile web Today tab shows drift, due tasks, and *recent* meetings — but **not today's upcoming meetings** (`Web/WebAssets.swift:214-247`; the `/api/today` payload has `drift`/`dueTasks`/`recentMeetings` only). My phone can't even tell me what's next, let alone prep me for it.

Pulling up the customer: the mobile person detail **leads with an edit form** — Name/Company/Role/Email inputs and a Save button before any content (`WebAssets.swift:475-484`). On a phone, while walking, I'm shown form fields when I need a dossier. Their meeting history is reachable, but each meeting's transcript is a raw escaped blob inside a `<details>` element (`WebAssets.swift:292`) and Search results carry kind + subtitle but no matched-text snippet (`WebAssets.swift:566-577`), so "what did they say about pricing in March" is minutes of pinch-zoom archaeology. Ask AI exists and is well-aimed (`WebAssets.swift:582-607`) but typing a question one-thumbed is slower than a glance should be.

### Premium-feel notes (exec expectation: looks like it costs money)

- Calendar write-back confirmations use blocking `NSAlert.runModal()` (`UI/MeetingDetailHeader.swift:659-665`) — "Recap added to the calendar event. [OK]" is 2009-era chrome in an otherwise tokenized app.
- The mobile tab bar uses emoji as icons (`&#127968;`, `&#129302;` — `WebAssets.swift:132-139`); eight emoji tabs on a 380px viewport reads like a hackathon, not hardware-grade.
- `PreMeetingBriefView` bypasses NDS: `Color.secondary.opacity(0.07)` card fills and bare `.orange` text (`PreMeetingBriefView.swift:132,136`).
- Meeting cards on Today show title + attendee *count* + badges but no content (`UI/MeetingCard.swift:108-151`) — scanning 8 past meetings tells me nothing about what happened in any of them. There is no one-line outcome anywhere in the system; the summary exists only as a full markdown document.
- The meeting detail header, conversely, is dense and confident (context-aware single CTA + labeled Options menu, `MeetingDetailHeader.swift:196-256`, `:381-397`) — that's the quality bar the rest should meet.

## Existing-plan items I rank highest

1. **Proactive pre-meeting brief (2D)** — the scheduled-job-N-minutes-before model is the only correct architecture for the 30-second window; everything in my U3-1/2/9 builds on it.
2. **Daily/weekly/morning rituals (2D)** — the Friday review gap is my scenario-3 failure; it must ship (see U3-6 for the spec it needs).
3. **Directed commitments iOwe/theyOwe + personID (2C)** — replaces the string-match `isMine` (`TodayView.swift:159-165`) that makes the Commitments split untrustworthy.
4. **Mid-call "catch me up" (2D)** — joining meeting #6 four minutes late is a weekly exec reality.
5. **WidgetKit + Control Center (2D)** — glanceability off-app is the cheapest way to respect the attention budget.
6. **Recents rail + Cmd-K (2A)** — between-meeting context switching must be keystroke-fast.

## NET-NEW recommendations

### U3-1 — Menu-bar next-meeting intelligence (the Notion Calendar move)
- **What/why:** The menu-bar *label* shows a live countdown when the next meeting is ≤15 min ("Acme sync · 4m"); the panel's top section becomes a prep card: meeting title, external/internal badge, 2–3 "you owe them" chips from open directed items, and a one-line cached brief — replacing the context-free list at `MenuBarView.swift:30-44`. One click = full brief.
- **User value:** The 30-second between-meetings scan happens without opening the main window. Prep: 4 clicks + LLM wait → 0–1 clicks, instant.
- **Effort:** M
- **Impact:** High
- **Depends on:** planned 2D proactive brief; U3-12 (cache)

### U3-2 — Turnaround card: the back-to-back bridge
- **What/why:** When a recording stops and the calendar shows another meeting starting within ~15 min, the floating overlay (`UI/FloatingOverlay.swift` already owns this window layer) shows one combined card: "✅ Acme sync — summary processing · ⏭ Board prep in 6 min — brief ready →" with Join & Record. Nothing in the app today connects "meeting just ended" to "next one is imminent," which is the defining state of an exec's day.
- **User value:** The single highest-frequency exec moment gets a purpose-built, zero-navigation surface.
- **Effort:** M
- **Impact:** High
- **Depends on:** planned 2D brief; U3-12

### U3-3 — "Day shape" strip at the top of Today
- **What/why:** A horizontal timeline of today's blocks (8am–6pm): meeting blocks sized by duration, tinted by external/internal (U3-5), recorded ones check-marked, gaps visible, now-line, click = `router.openMeeting`. Replaces the textual subtitle (`TodayView.swift:614-623`) as the first thing under the date. This is the 10-second answer to "what does my day look like" that the 15-section feed can't give.
- **User value:** 7am scan drops from ~60s of scrolling to one glance; complements (doesn't duplicate) D5-1's section diet.
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### U3-4 — One-line outcome per meeting, everywhere
- **What/why:** At finalize, extract a single ≤120-char outcome sentence ("Agreed to pilot at $40k; legal review by Fri") stored on the meeting record — distinct from the full summary. Surface it on Today's past-meeting cards (`MeetingCard.swift:108-151` currently shows zero content), mobile meeting rows (`WebAssets.swift:254-257`), the Friday review, and Spotlight/widget rows. Cheap prompt addition to the existing summary pass.
- **User value:** Scanning 8 meetings becomes 8 glances; every list surface in the app gains information density without weight.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### U3-5 — External/internal awareness from attendee domains
- **What/why:** Derive meeting audience by comparing attendee email domains (already parsed, `PreMeetingBriefView.swift:242-253`) against the user's own domain(s): badge meetings "External · acme.com", tint them in the day strip, and rank prep/follow-up nudges external-first (an unsent recap to a customer outranks one to a teammate in `pendingFollowUps`, `TodayView.swift:112-120`). No new data entry — it's inference.
- **User value:** The investor/customer/team interleave becomes visible structure; follow-up discipline points at the meetings that cost money to fumble.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### U3-6 — Exec-grade Weekly Ledger (the concrete spec for 2D's "Friday review")
- **What/why:** A "This week" view: top strip = 3 numbers (meetings held, commitments made by me, owed to me); then commitments **grouped by person** with avatar + audience badge and deltas vs last week ("3 cleared, 2 new, 1 slipped"); decisions made; unsent external follow-ups. One "Copy as update" button producing investor/board-ready markdown (reuse the `StandupDigest` pattern, `StandupDigest.swift:10-52`, scoped to the week). Fixes the invisible `prefix(3)` truncation and no-time-scoping of today's Commitments section (`TodayView.swift:190,169`).
- **User value:** "What did I commit to this week" goes from unanswerable to a 10-second read + a pasteable update.
- **Effort:** M
- **Impact:** High
- **Depends on:** 2C directed commitments; U3-5

### U3-7 — Mobile Today = pocket schedule
- **What/why:** Add today's upcoming meetings (time, title, external badge, cached brief one-liner) as the **first** section of `/api/today` and `renderToday` (`WebAssets.swift:214-247`), above drift. The phone surface for a moving exec must lead with "what's next," not "who's drifting."
- **User value:** The walking-to-a-meeting glance works at all; desktop and web stop forking the Today mental model.
- **Effort:** S
- **Impact:** High
- **Depends on:** U3-12 (brief in API); U3-4 (one-liners)

### U3-8 — Mobile person dossier: read first, edit behind a pencil
- **What/why:** Flip `renderPersonDetail` (`WebAssets.swift:469-484`) to lead with a dossier: name/role/company + health pill, "last met" + outcome line, open commitments both directions, recent meetings with one-liners, then a ✎ that reveals the current edit form. Today the first paint is six input fields and a Save button.
- **User value:** The pull-up-a-customer-on-foot scenario: 0 scrolling to the answer; editing (rare on phone) costs one extra tap.
- **Effort:** S
- **Impact:** High
- **Depends on:** U3-4

### U3-9 — Put the humans in the pre-meeting brief
- **What/why:** Make the brief people-first: a row of attendee person-chips (avatar, role @ company, relationship-health dot, tap → person) above the synthesized text, and a "Last time, they said" pulled quote from the most recent shared meeting. The view's own doc comment promises person links it never renders (`PreMeetingBriefView.swift:8` vs body `:27-40`). Also migrate its ad-hoc fills/colors to NDS tokens (`:132,136`).
- **User value:** Prep = remembering who people are and what they care about, not just what's overdue; one tap from brief → person dossier.
- **Effort:** S–M
- **Impact:** High
- **Depends on:** none (richer with 2C)

### U3-10 — Quote bank: attributed key quotes per meeting
- **What/why:** At finalize, extract 2–4 verbatim, speaker-attributed quotes ("We can't sign anything until SOC 2" — Dana, Acme) stored as structured atoms; render a "Quotes" timeline on person detail (desktop + mobile) and feed U3-9's "last time they said." Today the only path to what someone said is reading raw transcript blobs (`WebAssets.swift:292`); search results don't even show matched snippets (`WebAssets.swift:566-577`).
- **User value:** "What did they say last quarter" becomes 2 taps on a phone; quotes are the currency of exec recall (board decks, negotiations, recaps).
- **Effort:** M
- **Impact:** High
- **Depends on:** diarization surfacing (planned 2E) makes attribution better, not required

### U3-11 — Kill `NSAlert.runModal` confirmations → NDS toasts
- **What/why:** `infoAlert()` blocks the app with a modal for non-decisions ("Recap added to the calendar event.") at `MeetingDetailHeader.swift:633-637,650-656,659-665`. Replace success paths with the toast pattern the web app already has (`WebAssets.swift:162`), reserving alerts for genuine failures with a recovery action.
- **User value:** Removes the cheapest-feeling interaction in the desktop app; success feedback stops costing a click.
- **Effort:** S
- **Impact:** Med
- **Depends on:** D3-12 toast component if it lands; otherwise trivial standalone

### U3-12 — Brief cache + LLM right-of-way policy
- **What/why:** Persist the synthesized brief to the meeting folder (regenerate only when inputs change), and give finalize-summarization priority over brief generation on the shared Ollama instance — with the scheduled pre-compute (planned 2D) filling briefs during calendar gaps. Today the brief is `@State`-only, regenerated per appearance (`PreMeetingBriefView.swift:23-25,184-190`), exactly when the LLM is busiest.
- **User value:** Briefs are instant at the moment of need on every surface (menu bar, overlay, phone) instead of a spinner between meetings.
- **Effort:** S–M
- **Impact:** High
- **Depends on:** none; enables U3-1, U3-2, U3-7

## Top 3 picks

1. **U3-1 Menu-bar next-meeting intelligence** — the highest-frequency surface (touched 8+ times/day) currently carries zero intelligence; this is where the 10-second budget is won.
2. **U3-4 One-line outcome per meeting** — S-effort, transforms every list on desktop, mobile, widgets, and the weekly review from labels into information.
3. **U3-6 Exec-grade Weekly Ledger** — the only scenario of my four with *no* answer in the app today, and the one that produces a shareable artifact (board/investor update) every week.

**Single highest-priority rec overall:** ship the planned 2D proactive pre-meeting brief, but to the U3-12 + U3-9 + U3-1 spec — precomputed and cached, people-first in content, and surfaced in the menu bar/overlay rather than four clicks deep. Without those three, the planned brief is a feature; with them, it's the reason a back-to-back exec opens this app between every meeting.
