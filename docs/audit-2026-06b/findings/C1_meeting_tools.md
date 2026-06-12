# Competitive — AI Meeting-Notes Category UX (Granola · Fathom · Otter · Fireflies · Notion AI · Circleback)
> Lens: what the category leaders' meeting-lifecycle UX (prep → capture → review → share → recall) does that MeetingScribe's surfaces don't — June 2026 state, verified against live changelogs.

## Market snapshot (live research, June 2026)

- **Granola** shipped **Briefs** (May 20, 2026): open a meeting note and a short, *cited*, 2–3-bullet brief appears — who you're meeting, what you discussed last time, what matters now — prepared overnight, no prompting, and it "hides itself once you've read it." ([granola.ai/blog/briefs…](https://www.granola.ai/blog/briefs-prepare-you-for-your-next-meeting-as-you-join)) Earlier: agentic Chat with Recipes (Apr 2026), @Mentions with attendee cards (Jan 2026), **delete parts of a transcript** (Jan 28, 2026), "time remaining in meetings" (Dec 2025), edit-notes-just-by-asking (Jul 2025), 29 auto-selectable templates, Team Folders/Spaces. ([granola.ai/updates](https://www.granola.ai/updates)) $1.5B valuation, Mar 2026. ([TechCrunch](https://techcrunch.com/2026/03/25/granola-raises-125m-hits-1-5b-valuation-as-it-expands-from-meeting-notetaker-to-enterprise-ai-app/))
- **Circleback** (changelog, all 2026): **always-visible draggable record panel** that expands on hover (May 29); notes capture **what's shared on screen** (May 28); **search transcripts in context** — every hit highlighted *with surrounding conversation*, Enter/Shift-Enter navigation, result counter, search-by-speaker (May 25); **People & Companies spaces** showing pending action items, recent meetings/emails, *upcoming calendar events* (Apr 30); multi-select action items + ⌘K command menu (Apr 3); **saved Views as tabs** over meetings and action items (Mar 19). ([circleback.ai/releases](https://circleback.ai/releases))
- **Fathom**: click **"highlight" during any call** → auto-built clips per highlight, share in seconds; Ask Fathom across all conversations; instant follow-ups. ([fathom.ai](https://www.fathom.ai/), [fathom.ai/overview](https://www.fathom.ai/overview))
- **Otter**: live **Takeaways panel** — highlight, comment, and **assign action items during the meeting**; **AI Channels** grouping a meeting series/project's recordings, summaries, action items and chat into one shared space. ([otter.ai](https://otter.ai/), [Otter help center](https://help.otter.ai/hc/en-us/articles/9156381229079-Meeting-Summary-Overview))
- **Notion AI Meeting Notes**: `/meet` on any page, "gentle reminder" when it auto-detects a meeting, notes auto-linked to the calendar event, and **a pre-written agenda on the page is used as context to sharpen the summary**. ([notion.com/product/ai-meeting-notes](https://www.notion.com/product/ai-meeting-notes), [help](https://www.notion.com/help/ai-meeting-notes))

The pattern: leaders are converging on (a) zero-effort prep that appears *in* the note, (b) one-keystroke in-call capture gestures, (c) review surfaces where transcript/audio/summary are one synced object, (d) one-click channel-formatted sharing, and (e) recall organized around people and recurring series, not a flat list.

## Full-app audit (through my lens)

**Strong (genuinely at or past category parity):**
- The Notes canvas (summary disclosure + editable notes in one scroll) matches Granola's read-recap-while-writing model — `UI/MeetingSummaryTab.swift:11–24`.
- Inline attendee→person connect panel without leaving the meeting (`UI/MeetingDetailHeader.swift:744–848`, `UnifiedMeetingDetail.swift:153–163`) is *ahead* of most competitors' attendee chips.
- Follow-up lifecycle on Today (`UI/TodayView.swift:108–155`) + draft-follow-up at top of summary (`MeetingSummaryTab.swift:137–141`) — Fathom-grade follow-up posture.
- Calendar write-back (recap-to-event, schedule follow-up — `MeetingDetailHeader.swift:362–378, 624–657`) is something none of the cloud tools do natively against the user's own calendar.
- Summary 👍/👎 with reason-steered regeneration (`MeetingSummaryTab.swift:414–467`) — nobody else closes this loop.

**Weak / missing (the gaps this report is about):**
1. **Prep is hidden inside a tab labeled "Transcript."** For an upcoming meeting the smart-tab default selects `.transcript` (`UI/UnifiedMeetingDetail.swift:357–358`) and `PreMeetingBriefView` renders *inside the Transcript tab* (`UI/MeetingTranscriptTab.swift:24–29`). A user who never clicks "Transcript" on a future meeting never sees prep. Granola's whole Briefs launch is about the brief greeting you at the top of the note. Today's `upNextCard` (`TodayView.swift:442–459`) offers "Join & record" but no prep affordance at all.
2. **The transcript↔audio sync feature is built and dead.** `TranscriptSyncView` supports tap-timestamp-to-seek, active-line follow-along, and a Sync toggle — all gated on `audioController != nil` (`UI/TranscriptSyncView.swift:96, 178, 214–219`) — but the only call site passes nothing: `TranscriptSyncView(rawTranscript: transcript)` (`UI/MeetingTranscriptTab.swift:42`). The audio bar (`MeetingTranscriptTab.swift:9–16`) and transcript are two unconnected widgets. This is the single cheapest premium-feel win in the app.
3. **No in-call capture gesture.** `MeetingRecordDock` offers exactly: level meter, "Open & add notes," stop (`UI/MeetingRecordDock.swift:48–62`). No "mark this moment" (Fathom's highlight), no live action-item flag (Otter's Takeaways). The dock also shows **elapsed time only** (`MeetingRecordDock.swift:33–37, 81–86`) — Granola shows time *remaining* in the meeting.
4. **Transcript search destroys context.** Search *filters out* non-matching segments (`TranscriptSyncView.swift:249–257`), so a hit appears as an orphaned line with no surrounding conversation, no match counter, no next/prev. Circleback's May 2026 release is precisely the opposite pattern.
5. **Recurring meetings have no home.** A series is a "Recurring" chip + "N previous" caption (`MeetingDetailHeader.swift:166–173`) and a per-occurrence notes picker (`UnifiedMeetingDetail.swift:81–86`). There is no series-level page: rolling open actions, decisions across occurrences, trend. Otter Channels and Granola Folders both monetize exactly this aggregation.
6. **The meetings list has fixed scopes, no saved views.** `Scope` is hardcoded `all/upcoming/past` (`UI/MeetingsView.swift:46–50`, pills at 136–150); search matches title/attendee only (`MeetingsView.swift:227–232`). No filter by tag, person, or source, and no way to save one (Circleback Views).
7. **Sharing is file-export-shaped, not message-shaped.** The header overflow exports Markdown/PDF/Drive/Obsidian via modal pickers (`MeetingDetailHeader.swift:335–359`); the only ShareLink in the app is buried in `Followup/FollowUpView.swift:97`. There is no one-click "copy recap formatted for Slack/email" — the thing Granola explicitly tuned in Jan 2026.
8. **Transcript is immutable.** No trim/redact ("delete parts of a transcript", Granola Jan 2026) — ironic for the privacy-first product; the transcript renders read-only (`MeetingTranscriptTab.swift:42`, `TranscriptSyncView` has no edit path).
9. **Person pages look backward, not forward.** `PersonDetailView` shows history and offers an "add to an upcoming meeting" *sheet* (`People/PersonDetailView.swift:372–393`), but never surfaces "your next meeting with this person" + open commitments as a forward-looking header — Circleback's People spaces' core promise.

## Existing-plan items I rank highest

1. **In-meeting hybrid scratchpad (2D)** — the single most-copied Granola mechanic; without it, capture UX is a generation behind. (Circleback even bolts a note window onto its record panel, May 29 2026.)
2. **Calendar-driven auto-record + pre-roll (2D)** — Notion auto-detects and nudges; this is now table-stakes and directly moves the "capture rate" north star.
3. **Proactive pre-meeting brief (2D)** — Granola's Briefs launch proves the demand; must land *with* the C1-1 placement redesign below or it stays invisible.
4. **Mid-call "catch me up" recap (2D)** — Granola has had in-meeting "what did I miss?" since Jan 2025.
5. **Recents rail + Cmd-K quick switcher (2A)** — Circleback runs bulk actions through ⌘K; command-palette fluency is part of "expensive."
6. **Attendee chip hover card (2A)** — Granola shipped attendee cards on @mentions (Jan 2026); pairs with the already-strong connect panel.

## NET-NEW recommendations

### C1-1 — Brief-as-hero: move prep out of the "Transcript" tab
- **What/why:** The pre-meeting brief renders inside a tab labeled "Transcript" (`MeetingTranscriptTab.swift:24–29`; default at `UnifiedMeetingDetail.swift:357–358`). Redesign per Granola Briefs: a compact, *cited* 2–3-bullet brief card at the top of the Notes canvas for upcoming meetings and on Today's `upNextCard` (`TodayView.swift:442`), auto-collapsing once read, with a "how this was built" footer (sources: prior meetings, open items, person records). Rename the upcoming-mode tab "Prep." The planned 2D proactive job generates it; this spec is *where it lives and how it behaves*.
- **User value:** Prep stops being a hidden feature; you never open a call cold. (Granola: "designed to be short, unobtrusive, and to hide themselves once you've read it.")
- **Effort:** M · **Impact:** High · **Depends on:** none (improves planned 2D brief)

### C1-2 — "Mark moment" in-call highlight → pinned summary anchors
- **What/why:** Fathom's defining gesture: click highlight during a call, get clips after. Local version: a flag button on `MeetingRecordDock` (`MeetingRecordDock.swift:48–62`) + global hotkey writes a timestamped marker (optional 4-word label); markers render as pins in `TranscriptSyncView`, seed "Highlights" atop the summary, and seek audio on click.
- **User value:** One keystroke turns "that was important" into a navigable artifact; the summary gets human priority signals the LLM can weight (same philosophy as the planned scratchpad merge, at 1-keystroke cost).
- **Effort:** M · **Impact:** High · **Depends on:** none (synergy with 2D scratchpad)

### C1-3 — Wire the dead transcript↔audio sync (pass the AudioPlayerController)
- **What/why:** Tap-to-seek, follow-along highlighting, and the Sync toggle already exist but are permanently disabled because the call site passes no controller (`MeetingTranscriptTab.swift:42` vs `TranscriptSyncView.swift:96,178,214–219`). Lift the `AudioPlayerController` out of `AudioPlayerView` into `UnifiedMeetingDetail` state and pass it through.
- **User value:** Review becomes "click any sentence, hear it" — the canonical premium notetaker interaction (Fathom/Otter/Fireflies all have it). Cheapest high-end feel in the backlog.
- **Effort:** S · **Impact:** High · **Depends on:** none

### C1-4 — Series Hub: a page for the recurring meeting itself
- **What/why:** Otter's AI Channels and Granola's Folders aggregate a series; MeetingScribe has the data (`seriesID`, `priorOccurrences` at `UnifiedMeetingDetail.swift:81–86`) but only a caption chip (`MeetingDetailHeader.swift:169–173`). Make the "Recurring" chip navigate to a series page: occurrence timeline, rolling open action items across occurrences, decisions ledger filtered to the series, attendee roster, and "ask AI across this series" scope.
- **User value:** The weekly 1:1 / standup — the highest-frequency meeting type — finally accumulates instead of fragmenting; recall scoped to "this standing meeting" with one click.
- **Effort:** M · **Impact:** High · **Depends on:** 2A EntityLink (planned)

### C1-5 — Saved Views as tabs on Meetings (and Tasks)
- **What/why:** Circleback Views (Mar 2026): save any filter combination as a named tab. MeetingScribe's list has hardcoded All/Upcoming/Past pills (`MeetingsView.swift:46–50,136–150`) and title/attendee-only search (`:227–232`). Add filter chips (tag, person, source, has-recording) and a "+ Save view" affordance persisting to `@AppStorage`/router.
- **User value:** "Customer calls," "1:1s," "this project" become one-click — the flat chronological list stops being the only recall path.
- **Effort:** M · **Impact:** Med-High · **Depends on:** none

### C1-6 — Message-shaped sharing: "Copy for Slack / Copy as email" split button
- **What/why:** Every competitor optimizes recap-into-chat (Granola tuned Slack copy-paste Jan 2026; Fathom "share in seconds"). MeetingScribe only has modal file exports (`MeetingDetailHeader.swift:335–359`) and one buried ShareLink (`Followup/FollowUpView.swift:97`). Add a header-level Share split button: Copy summary (rich text), Copy for Slack (mrkdwn), Copy as email (greeting + recap + action items), reusing the existing private-notes-excluded `confirmedExportDocument` gate (`MeetingDetailHeader.swift:700–713`).
- **User value:** Share drops from 4+ clicks-plus-file-dialog to 1 click; the recap actually leaves the app, which is the whole point of notes.
- **Effort:** S · **Impact:** High · **Depends on:** none

### C1-7 — Search-in-context for transcripts (counter + Enter/Shift-Enter)
- **What/why:** Current search *removes* non-matching segments (`TranscriptSyncView.swift:249–257`), orphaning hits from their conversation. Adopt Circleback's May 2026 pattern: keep the full transcript, highlight all matches, show "3 of 14," navigate with Enter/Shift-Enter, keep speaker filter as a dim-not-remove treatment.
- **User value:** "Find where we discussed pricing" returns the *conversation*, not a stripped quote — review trust goes way up.
- **Effort:** S · **Impact:** Med-High · **Depends on:** none

### C1-8 — Meeting-type summary templates, auto-selected from calendar
- **What/why:** Granola ships 29 templates auto-applied per meeting type; `NoteTemplate.swift` exists but only feeds scratch notes, and the Ollama summary prompt is one-size-fits-all (the group digest carried this below its cut line; it never reached the master plan). Bind a template (1:1, standup, sales call, interview) to a tag/series or detect from title+invitee-count (cf. Circleback's invitee-count automation condition), and feed it into the summary pass + per-section regeneration.
- **User value:** A 1:1 recap and a sales-call recap stop looking identical; summaries become predictable, scannable documents people trust.
- **Effort:** M · **Impact:** High · **Depends on:** none

### C1-9 — Transcript trim & redact ("delete parts of a transcript")
- **What/why:** Granola shipped this Jan 28, 2026 — and MeetingScribe, the privacy product, can't do it: transcripts are read-only (`MeetingTranscriptTab.swift:42`). Add per-segment "Remove from transcript" (with optional `[redacted]` placeholder) that rewrites the canonical markdown, re-indexes FTS/embeddings, and optionally re-summarizes.
- **User value:** The off-the-record aside or the kid walking in stops being permanently embedded in the vault — a privacy promise competitors *invented first* despite being cloud products.
- **Effort:** M · **Impact:** Med · **Depends on:** none (complements planned right-to-forget, which is whole-meeting only)

### C1-10 — Time-remaining + overrun cue on the record dock
- **What/why:** The dock shows elapsed only (`MeetingRecordDock.swift:33–37,81–86`). For calendar-linked meetings, show "12 min left" from `endDate`, going amber at 5 min and "+8 over" past the end (Granola added time-remaining Dec 2025). Also show it in the live status banner (`MeetingDetailHeader.swift:489–507`).
- **User value:** The recorder becomes a meeting *companion* — keeps you on time, and quietly justifies always-visible presence the way Circleback's panel does.
- **Effort:** S · **Impact:** Med · **Depends on:** none

### C1-11 — Forward-looking person header: "Next with Priya" + open loops
- **What/why:** Circleback's People spaces (Apr 30, 2026) show *upcoming calendar events* + pending action items per person. `PersonDetailView` is history-only; its calendar tie-in is a buried add-attendee sheet (`PersonDetailView.swift:372–393`). Add a compact header rail: next scheduled meeting (with Prep link → C1-1 brief), open commitments both directions, days since last encounter.
- **User value:** "Catching up on someone used to mean bouncing between calendar, inbox, and meetings" (Circleback's own pitch) — the person page becomes the complete picture, which is MeetingScribe's stated identity.
- **Effort:** M · **Impact:** High · **Depends on:** 2B health fields (shipped), 2C directed commitments (planned)

### C1-12 — Edit the summary by asking (quick-instruction chips)
- **What/why:** Granola's "edit your meeting notes just by asking" (Jul 2025). MeetingScribe has 👍/👎-steered full regeneration only (`MeetingSummaryTab.swift:414–467`). Add an instruction field + chips on the summary disclosure ("shorter," "more detail on decisions," "turn into an email") running a targeted local-LLM rewrite of the summary block, with one-step revert.
- **User value:** Fixing a summary becomes a 5-second tweak instead of a full re-run gamble; pairs naturally with C1-6's email copy.
- **Effort:** M · **Impact:** Med · **Depends on:** none

## Top 3 picks

1. **C1-3 — Wire the dead transcript↔audio sync.** S-effort, already built, instantly category-parity premium feel. Embarrassing to leave dark.
2. **C1-1 — Brief-as-hero prep redesign.** Granola just made "the note preps you as you walk in" the category's defining 2026 move; MeetingScribe's equivalent is hidden behind a tab named "Transcript."
3. **C1-2 — "Mark moment" in-call highlight.** Fathom's signature gesture, trivially achievable bot-free and on-device, and it feeds better summaries.

**Single highest-priority rec overall:** the already-planned **in-meeting scratchpad (2D)** — every leader's capture UX now centers on "you type a little, AI does the rest"; land it together with C1-2 and C1-10 so the live dock becomes one coherent, premium in-call companion.

## Sources

- https://www.granola.ai/updates · https://www.granola.ai/blog/briefs-prepare-you-for-your-next-meeting-as-you-join
- https://techcrunch.com/2026/03/25/granola-raises-125m-hits-1-5b-valuation-as-it-expands-from-meeting-notetaker-to-enterprise-ai-app/
- https://circleback.ai/releases (always-visible record panel · search-in-context · People & Companies · Views · multi-select + ⌘K)
- https://www.fathom.ai/ · https://www.fathom.ai/overview (highlights→clips, Ask Fathom)
- https://otter.ai/ · https://help.otter.ai/hc/en-us/articles/9156381229079-Meeting-Summary-Overview (Takeaways, assign action items, AI Channels)
- https://www.notion.com/product/ai-meeting-notes · https://www.notion.com/help/ai-meeting-notes (auto-detect reminder, agenda-as-context, calendar linking)
