# G4 End-User — Busy IC (Software Engineer)

> Lens: a heads-down individual contributor. Daily standup, sprint planning, design reviews, frequent 1:1s, lots of context-switching. I want **near-zero overhead**, fast capture of *my* action items, and a clean path from "meeting ended" to "ticket in Linear." I don't care about the relationship graph; I care about not dropping a commitment I made out loud in a meeting.

## Full-app audit (through my lens)

I walked my real day: join standup → record → get my action items → push to Linear → prep for my next 1:1.

### 1. Recording / joining is genuinely low-friction (good)
Today has a one-tap **Record Meeting** (`TodayView.swift:124`, `manager.startRecording(for: nil)`), a **Join & record** affordance on upcoming calls (`TodayView.swift:175`), a **New Note** voice capture (`startQuickNote()`, `TodayView.swift:140`), and a global F5 dictation hotkey (`Hotkey/QuickDictation.swift`). For someone bouncing between Zoom standup and a design review, that's the right amount of "start in one click." This is the part of my day the app nails.

### 2. "Just my action items" is *half* built — and silently hardcoded to "Tyler"
The single best thing this app does for an IC is in `ActionItemExtractor.swift`: it **only keeps action items that are mine** (`isMine`, lines 65–82) — owner is "me"/"I"/"myself"/"Tyler", or the action text addresses me by name. That is exactly the IC dream: I record a 30-person all-hands and only the 2 things *I* committed to land in my tasks.

But two problems:
- **It's hardcoded to one human.** `myOwnerAliases = ["me","i","myself","my","tyler","tyler yannes"]` (`ActionItemExtractor.swift:27-28`). The plan claims "de-hardcode user name (done)" — but that only landed in `OllamaService.swift:261` (`AppSettings.shared.userName`). The *ownership filter that decides which action items are mine* still hardcodes "tyler." Same in `PersonExtractor.swift:116` and `CalendarAttendeeImporter.swift:8`. If my name isn't Tyler, the app silently extracts **zero** of my action items, or worse, the wrong ones. For a generic IC this is a P0 correctness bug masquerading as a "done" item.
- **No transparency / override.** When the extractor drops an item because it parsed the owner as someone else, I can't see what it dropped or reclaim it. If the LLM wrote "Eng to fix the flaky test" and that was me, it's gone.

### 3. There is no "My action items across all meetings" view
The Tasks tab filters are status/priority/date only (`ActionItemsViewModel.swift:19-35`: all, thisWeek, open, inProgress, completed, upcoming, overdue). There's **no owner/"assigned to me" lens**. That's *fine* for meeting-extracted items (already filtered to me) but breaks the moment I **import my Linear backlog** — `syncExternalTasks()` pulls in issues with every assignee (`TaskSyncService.fetchLinear`), and now my clean "my stuff" list is polluted with the whole team's tickets and there's no way to filter back to mine. The Today widget filters to "today & yesterday" by `createdAt` (`ActionItemsWidget.swift:61`), not by *due date* or *me* — so a thing due tomorrow that I created last week doesn't surface, and an imported teammate task created today does.

### 4. Push to Linear is a second-class citizen — the asymmetry hurts
This is my biggest day-to-day pain. As an engineer my tickets live in **Linear**, not Notion. But:
- `TaskRowView.swift` only renders a **"Push to Notion"** button (`:324`, `:385`). There is **no per-item "Push to Linear"** anywhere in the UI.
- Linear is **import-only** in the normal flow (`fetchLinear`, `importLinearProject` — `TaskSyncService.swift:37,396`).
- `createLinearIssue` exists (`TaskSyncService.swift:202`) but is reachable **only through the AI chat tool** (`IntegrationChatTools.swift:120`) — i.e. I have to open the chat rail and type "create a Linear issue titled… in team…" and supply a team_id. That's not a workflow; that's a party trick.

So my real loop today is: meeting ends → I read my extracted items → I **manually retype each one into Linear** by hand. The exact toil this app should kill.

### 5. Pre-meeting prep exists but is buried and not "what I owe"
`PreMeetingBriefView` is solid in concept: prior meetings with the same attendees + their open action items (`computeBrief()`, `:135-157`). But:
- It's only rendered inside **`MeetingTranscriptTab.swift:28`** — buried in a sub-tab of a meeting detail. There is **no proactive surfacing**: no meeting-start notification links to it (`grep` of `Notifications/` for "brief" → nothing), and Today's "up next" doesn't open it.
- It shows open items for *all* attendees, not **"things I committed to last time with this person."** Before my weekly 1:1 with my manager, what I want in one glance is: "last 1:1 you said you'd land the migration PR — status?" The data is all there; it's just not framed as *my outstanding promises to this person*.

### 6. Context-switching tax: nothing connects "what I said" to "what I shipped"
I commit to things verbally; I complete them in git/Linear. The app has no notion that an action item ("send the RFC", "fix the flaky test") might already be **done** because I merged the PR. Every standup I manually reconcile my MeetingScribe task list against reality. The `externalID`/`externalURL` fields on `ActionItem` (`ActionItem.swift:50-52`) are the hook, but nothing closes the loop.

## Existing-plan items I rank highest (through my lens)

1. **ENG-A — live-transcript truncation fix** (MASTER_PLAN_V3 §3.6 / AUDIT #1). The last 0–5 min of every recording is where standups and 1:1s put the *wrap-up action items* ("okay so you'll take X"). If those get dropped, the app fails at its one job for me. Highest stakes.
2. **TDY-2 — "Needs attention" block** (overdue + due-today + unsent follow-ups). This is the closest existing item to my morning ritual, *if* it's scoped to me and keyed on due date (today it's createdAt — see #3 above).
3. **TDY-1 — "Up next" hero with Open brief + Join & Record.** My day is back-to-back; one glance at "next meeting + countdown + one tap to join+record" removes the scramble.
4. **"Send the follow-up, don't just copy it" + DEF-3 (promote Draft follow-up).** After a design review I want to fire the recap without leaving the app.
5. **Speaker-labeled transcript & action-item attribution** (V3 §4). This is the *correct* long-term fix for the hardcoded-"tyler" owner guess: attribute "you'll take X" to the actual speaker via diarization rather than string-matching a name.

## NET-NEW recommendations

### U1-1 — First-class "Push to Linear" on every task (parity with Notion)  · S · **High** · depends on nothing (`createLinearIssue` already exists)
Add a **Push to Linear** button + "Open in Linear" / "Re-sync" to `TaskRowView` mirroring the Notion button (`TaskRowView.swift:300-360`). Store `externalID`/`externalURL`/`source="linear"` on push (fields already on the model, `ActionItem.swift:50-52`). One-time pick a default team in Integrations so I don't supply `team_id` every time. **Why:** today the only push button is Notion and Linear-create is hidden in chat; an engineer's tickets live in Linear. This deletes the single biggest piece of manual toil in my loop.

### U1-2 — Fix the hardcoded-"me" ownership filter; make it profile-driven + aliasable  · S · **High** · depends on AppSettings.userName (exists)
Replace the literal `["...","tyler","tyler yannes"]` sets in `ActionItemExtractor.swift:27`, `PersonExtractor.swift:116`, `CalendarAttendeeImporter.swift:8` with `AppSettings.shared.userName` + a user-editable **"names people call me"** alias list (nickname, first name, "the eng lead"). **Why:** the "just my action items" magic is the app's best IC feature and it's silently broken for anyone not named Tyler. The plan marks de-hardcode "done" but only the prompt was fixed, not the ownership filter.

### U1-3 — "My commitments" smart list + an "assigned to me" filter  · S · **High** · depends on U1-2
Add an `assignedToMe` `Filter` case (`ActionItemsViewModel.swift:19`) and a pinned **"My commitments"** smart list at the top of the Tasks sidebar that shows open items owned by me across *all* meetings + imported tickets where assignee == me. **Why:** the instant I sync my Linear backlog, "just my stuff" is lost in the team's tickets. I need a one-click "what do *I* owe, everywhere."

### U1-4 — Standup Mode: a 60-second pre-standup digest  · M · **High** · depends on U1-2/U1-3
A dedicated view (and optional 8:55am notification before my recurring standup) that auto-assembles **Yesterday** (items I completed / meetings recorded), **Today** (my open items due ≤ today), **Blockers** (items flagged blocked / overdue), formatted as copy-pasteable standup bullets. Reuse the `engineering:standup` shape but sourced from my action items + recordings. **Why:** I write this by hand every single morning; the app already holds every input.

### U1-5 — "What I owe you" relationship brief, surfaced before the meeting  · M · **High** · depends on PreMeetingBrief (exists)
Reframe `PreMeetingBriefView` around **my outstanding commitments to these attendees** (open items I own from prior meetings with them, oldest first), promote it out of `MeetingTranscriptTab` onto the meeting detail header and the Today "up next" card, and fire it in the meeting-start notification. **Why:** before my 1:1 I want "last time you promised X, still open" — not a generic attendee dump three tabs deep.

### U1-6 — Auto-detect what I already shipped (close the commitment loop)  · L · **Med** · depends on U1-1, GitHub/Linear sync
On Linear/GitHub sync, fuzzy-match my open action-item titles against my recently-closed Linear issues / merged PRs and propose **"Looks done — mark complete?"** Use the `externalID` hook (`ActionItem.swift:50`). **Why:** I complete work in git, not in MeetingScribe; reconciling two lists every standup is pure tax.

### U1-7 — Distraction-free / silent recording mode  · S · **Med** · depends on nothing
A toggle that, while recording, suppresses the floating overlay, mutes all MeetingScribe notifications, and shows only a tiny menu-bar dot (`FloatingOverlay.swift` is fairly heavy today). Auto-engage during calendar events titled "interview"/"1:1"/"focus." **Why:** in a design review I'm screen-sharing my IDE; a floating recorder overlay and notification toasts are both distracting and a privacy risk on shared screens.

### U1-8 — Inline action-item *capture* during recording ("flag this as mine")  · M · **Med** · depends on live transcript (exists)
A hotkey / overlay button during recording that timestamps "⭑ this is an action item for me," so when I hear "Tyler, can you take the migration?" I tap once. At finalize, flagged moments are pre-seeded as my action items (and shown verbatim from transcript) instead of relying solely on the LLM extractor. **Why:** the extractor misses or mis-owns items; let me cheaply ground-truth the ones that matter mid-meeting without breaking focus.

### U1-9 — Per-meeting-type summary template: "1:1" and "standup"  · M · **Med** · overlaps planned per-tag templates but IC-specific
Ship two opinionated templates: **Standup** (just decisions + my action items, skip prose) and **1:1** (my commitments, manager's asks, topics to raise next time). Auto-select by calendar title/recurrence. **Why:** a generic narrative summary of a 10-min standup is noise; I want the 2 bullets and out.

### U1-10 — Mark-done from the keyboard + bulk-complete in the widget  · S · **Med** · depends on DEF-2
Make the Tasks list and the Today `ActionItemsWidget` fully keyboard-drivable (↑/↓ + space-to-complete) and allow multi-select complete. **Why:** Friday afternoon I clear out the week's done items; clicking 12 checkboxes one-by-one is the kind of friction that makes me stop using the tool.

## Top 3 picks

1. **U1-1 — First-class "Push to Linear" button.** The highest-leverage, lowest-effort fix: the backend (`createLinearIssue`) already exists; it's just not wired to a button. It removes my single biggest daily toil (retyping action items into Linear by hand).
2. **U1-2 — Fix the hardcoded-"me" ownership filter.** The app's standout IC feature ("only my action items") is silently broken for any user not named Tyler. Small change, correctness-critical, and the plan falsely believes it's done.
3. **U1-4 — Standup Mode digest.** Turns the app's existing data into the one artifact I produce by hand every morning. High retention hook for the IC persona.
