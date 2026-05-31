# G4 — End-user: People Manager / Engineering Manager

> Lens: I manage 7 direct reports. Weekly 1:1s, monthly skip-levels, quarterly growth/perf cycles. My core need is **continuity of relationship over months** — "what did we discuss last time, what did I commit to, what did they commit to, what's their growth arc" — across people, where **many 1:1s are talked, not recorded.** The People CRM + relationship graph is the product to me; the recorder is a feeder.

## Full-app audit (through my lens)

I walked my real workflows against the live source.

### Workflow 1 — Prep for Tuesday's 1:1 with a report
I tap into the upcoming calendar event. `PreMeetingBriefView` (`UI/PreMeetingBriefView.swift:135`) does the right *shape*: it shows prior meetings sharing an attendee email and their open action items. But for a manager it has three holes:
- It only searches `manager.pastMeetings` (`:144`) — **recorded** meetings. My last three 1:1s with this person were talked, not recorded, so the brief reads "No prior meetings found" (`:122`) and tells me this is "a first meeting" with someone I've met weekly for a year.
- It pulls **nothing from the PeopleStore** — not their memories, not their `bio`/About, not relationships, not the attached sentiment/topic notes. The richest per-person context the app holds is invisible at the exact moment I need it.
- It surfaces open action items but with **no sense of direction** — I can't tell "things I owe them" from "things they owe me" (see Workflow 3).

### Workflow 2 — During/after the 1:1: recall "last time"
On the person's detail page, the Meetings tab (`People/PersonDetailView.swift:511` `meetingHistorySection`) filters `manager.pastMeetings` by attendee email/name match (`:514-521`) and is literally titled **"In your recordings"** (`:527`). So a report's Meetings tab is **empty or sparse for everyone whose 1:1s I don't record** — which is most of them. The chat-tool path has the identical limitation: `ChatToolHelpers.allMeetings` (`Chat/ChatToolHelpers.swift:62-66`) returns `pastMeetings` and *never* touches `CalendarService`, so `list_person_meetings` (`Chat/PeopleChatTools.swift:372`) also can't see an unrecorded weekly 1:1. The "Mentioned in" section (`PersonDetailView.swift:716`) is transcript-derived, so it's empty for the same reason. **Net: the app silently assumes every meaningful meeting was recorded. For a manager, that assumption is false ~70% of the time, and it hollows out the one tab I'd live in.** MASTER_PLAN_V3 PPL-4 names this but scopes it as "show all calendar meetings" — it under-counts how load-bearing it is for this persona.

### Workflow 3 — Track commitments in both directions
`ActionItem` (`ActionItems/ActionItem.swift`) has `owner: String?` (`:23`) as free text and `meetingID` (`:16`), but **no link to a Person record and no me-vs-them axis.** I can't ask "what has Priya committed to over the last quarter" or "what have I promised each report and not delivered." Owner is an unstructured name string that doesn't reconcile with `Person.id`. The pre-meeting brief lumps all open items together regardless of who owns them.

### Workflow 4 — Track growth themes per person over time
There is no growth/theme primitive. `Memory` (`People/Person.swift:6`) is freeform dated facts; `AttachedNote` (`:26`) is a one-off long-form analysis with a free-text `kind` ("sentiment", "topics"…) but **no time series and no tag taxonomy.** The `NoteTemplate` "1:1" (`Models/NoteTemplate.swift:36`) is a *blank* markdown stub I paste manually — not data-driven, not per-report, not threaded across sessions. So "how has this person's growth on system-design progressed across six 1:1s" is something I'd have to reconstruct by hand. The `relevanceScore` (`Person.swift:228`) even counts `attachedNotes.count * 4` — the data model *wants* to track this, but nothing structures it.

### Workflow 5 — Notice someone I haven't met with recently
`Person.lastInteractionAt` (`:94`) exists and drives recency sort, and `MessagesAnalyzer` computes `last30/last90` (`PeopleChatTools.swift:326-327`). But the actual "stay in touch" nudge is **vaporware** — the only trace is a *comment* in `TodayView.swift:367` ("Stay in touch nudges"); there is no view, no threshold, no snooze. For a manager this is the difference between "I notice I've ghosted a report for 3 weeks" and not. Worse, because unrecorded 1:1s don't update much (no encounter is auto-created from a calendar-only meeting), staleness signals will misfire — `lastInteractionAt` won't move for a report I met yesterday but didn't record.

### Other observations
- **No private vs shareable boundary.** `AttachedNote` and `bio` have no visibility flag. As a manager I keep two registers: candid private assessments ("not yet ready for staff") and shareable summaries I'd paste into a growth doc. Today everything is one bucket, and the write-capable MCP (`add_memory`, `create_meeting_note`) can read/emit all of it indiscriminately — a real leak risk if I ever let an agent draft a shareable summary.
- **Relationship graph is org-blind.** `Relationship` (`Person.swift:51`) is freeform ("manager", "kid"), bidirectional-mirrored. There's no notion of *my* reporting line, so the app can't say "these 7 are your directs" or render a team view. Skip-levels have no place to live.
- **Encounters** (`People/Encounter.swift`) are perfect for "met at Purple Party" but are not auto-created from calendar 1:1s, so they don't backfill the empty Meetings tab either.

## Existing-plan items I rank highest

1. **PPL-4 — show all calendar meetings per person, not just recorded** (V3 §3.3). For this persona it's not a polish item; it's the fix that makes the per-person page usable at all. I'd upgrade it from P1 to P0-for-managers.
2. **"Stay-in-touch" nudges** (V3 §4 / REMAINING_WORK §4). Directly serves Workflow 5 — but only if it counts calendar 1:1s, not just recordings/messages (see U2-1 dependency).
3. **PPL-1 — inline field-level person editing** (V3 §3.3). I edit role/notes on reports constantly between cycles; the modal (`PersonDetailView.swift` → `AddPersonSheet`) is friction I hit weekly.
4. **Per-tag summary templates** (V3 §4). A real 1:1 template that auto-fills last-time context is the backbone of U2-2 below.
5. **Write-capable MCP** (already shipped). Lets me say "log that Priya wants to lead the migration" without leaving chat — high value, but needs the privacy axis (U2-5) before I trust it with candid notes.

## NET-NEW recommendations

**U2-1 — Unified person timeline that merges recorded + calendar + messages + encounters.** *What/why:* Make the person Meetings tab (and the brief, and `list_person_meetings`) draw from `CalendarService` events matched by attendee email **unioned** with `pastMeetings`, deduped by `seriesID`/time, each row badged recorded / calendar-only / message-thread. Fixes the "empty tab for unrecorded reports" bug at the source (`PersonDetailView.swift:514`, `ChatToolHelpers.swift:62`). *Value:* the per-person page finally reflects reality for a manager. *Effort:* M. *Impact:* High. *Depends on:* none (prerequisite for U2-2/U2-7).

**U2-2 — 1:1 prep digest per report.** *What/why:* When I open an upcoming 1:1, generate (locally, Ollama) a one-screen digest: last 1:1 date + key points, open commitments both directions, unresolved growth themes, recent memories, "you said you'd follow up on X." Extends `PreMeetingBriefView` to read PeopleStore, not just `pastMeetings`. *Value:* I walk in prepared in 30 seconds instead of scrolling six markdown files. *Effort:* M. *Impact:* High. *Depends on:* U2-1, U2-3.

**U2-3 — Bidirectional commitment tracking tied to people.** *What/why:* Add `personID: String?` and `direction: enum {iOwe, theyOwe, mutual}` to `ActionItem` (`ActionItem.swift`), with a per-person "Commitments" panel split into "I owe them / they owe me" and a "carried over N weeks" age. *Value:* the core accountability loop of management; nothing in the app does this today (owner is free text). *Effort:* M. *Impact:* High. *Depends on:* none.

**U2-4 — Growth-theme threads (typed, time-series memories).** *What/why:* A `GrowthTheme` per person (title like "system design", "delegation") with dated entries and a trend marker (improving/stuck/regressed). Promote the existing freeform `Memory`/`AttachedNote` into themed threads instead of an undifferentiated list. *Value:* I can see a report's arc across two quarters at a glance and write a defensible review. *Effort:* M. *Impact:* High. *Depends on:* none (but pairs with U2-8).

**U2-5 — Private vs shareable note visibility flag.** *What/why:* Add `visibility: enum {private, shareable}` to `AttachedNote`/`Memory`; gate MCP/chat read+write tools so an agent drafting a "summary to share" can only see shareable content unless I explicitly opt in. *Value:* lets me keep candid manager notes and report-facing notes in one place without leak risk. *Effort:* S–M. *Impact:* High. *Depends on:* touches MCP tool layer (`PeopleChatTools.swift`).

**U2-6 — Performance-review compilation.** *What/why:* A "Compile review" action on a person that pulls a date-range of 1:1 points, completed commitments, growth-theme deltas, and shareable notes into a structured draft (markdown, locally generated). *Value:* turns six months of scattered notes into a review draft in one click — the single most painful recurring task I have. *Effort:* M. *Impact:* High. *Depends on:* U2-3, U2-4, U2-5.

**U2-7 — Calendar-aware "stay-in-touch" cadence per report.** *What/why:* Per-person target cadence (e.g. weekly for directs, monthly for skips); Today surfaces "you haven't had a 1:1 with X in N weeks" computed from **calendar history**, not just recordings/messages, with snooze/done. Make a calendar-only 1:1 bump `lastInteractionAt` (or a new `lastMetAt`) so the signal is honest. *Value:* I never silently drop a report. *Effort:* M. *Impact:* High. *Depends on:* U2-1.

**U2-8 — Sentiment/morale trend per report over time.** *What/why:* Extend the existing per-person sentiment `AttachedNote` "kind" into a dated scalar (e.g. -2…+2) I can log each 1:1 (or have Ollama estimate from a recorded 1:1), rendered as a sparkline on the person header. *Value:* early warning for a disengaging report before it becomes attrition. *Effort:* M. *Impact:* Med. *Depends on:* U2-4 (shares the time-series substrate).

**U2-9 — Team / org-line view in the relationship graph.** *What/why:* A typed `directReport` / `manager` relationship plus a "My team" filter and a simple org rollup, so my 7 directs and their skips are a first-class group. *Value:* one surface for "how's my team doing" instead of 7 separate pages. *Effort:* M. *Impact:* Med. *Depends on:* U2-3/U2-7 to populate it with signal.

**U2-10 — "Quiet 1:1" capture without recording.** *What/why:* A fast post-meeting capture (template-driven, the existing 1:1 `NoteTemplate`) that creates a lightweight non-recorded meeting/encounter linked to the person and date, so unrecorded 1:1s still populate the timeline, commitments, and themes. *Value:* matches how managers actually work (most 1:1s aren't recorded) without forcing recording. *Effort:* S–M. *Impact:* High. *Depends on:* U2-1 (so the captured note shows in the unified timeline).

**U2-11 — Cross-report theme rollup ("what's bubbling up across my team").** *What/why:* Aggregate growth themes + commitments across all directs to surface patterns ("4 of 7 reports raised on-call load this month"). *Value:* turns 1:1 notes into management signal I can act on org-wide. *Effort:* M. *Impact:* Med. *Depends on:* U2-3, U2-4.

## Top 3 picks

1. **U2-1 — Unified person timeline (recorded + calendar + messages).** Without it, the per-person page lies to a manager every week. It's the keystone the rest depend on.
2. **U2-3 — Bidirectional commitment tracking tied to people.** The accountability loop is the literal job of managing; the app currently can't answer "what do I owe each report."
3. **U2-2 — 1:1 prep digest per report.** The highest-frequency, highest-relief moment — walking into a 1:1 already knowing last time, open commitments, and the growth thread.
