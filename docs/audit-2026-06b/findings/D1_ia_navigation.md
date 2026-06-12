# Design — Information Architecture & Navigation
> Lens: mental model, findability, nav depth, cross-entity flows (meeting→person→task→note), clicks-to-anything, dead ends.

*(ID note: `D1-n` below are items of THIS audit, `docs/audit-2026-06b`. Source comments like `(D1-1)`, `(D1-5)` in code refer to a prior audit's IDs — collisions are coincidental.)*

## Full-app audit (through my lens)

### Strong — the router rebuild landed and works
- `WorkspaceRouter` is a real single source of truth for section + meeting selection with a coalesced browser-style back/forward stack (`Sources/MeetingScribe/UI/WorkspaceRouter.swift:13–117`). Meetings open in ONE canonical surface (`MeetingsView.swift:20–27`), Today cards route through it (`TodayView.swift:537–543`), and person detail backlinks click through to the canonical meeting detail (`People/PersonDetailView.swift:1235–1237`). The four-incompatible-ways-to-open-a-meeting era is genuinely over.
- The person↔meeting edge is two-directional in places: person detail unions recorded + calendar-only meetings into one badged timeline (`PersonDetailView.swift:1209–1230`), and attendee chips open an inline connect panel without losing meeting context (`MeetingDetailHeader.swift:794–847`).
- ⌘K is more than search — it has typed filter scopes, FTS5+hybrid ranking, and a command mode ("record", "new task", "go to…") (`GlobalSearchView.swift:26–49, 356–410`).

### Weak — the mental model leaks at every seam between sections

**1. The nav rail is semantically broken at the glyph level.** `.meetings` uses `person.2.fill` and `.people` uses `person.2` (`MainWindow.swift:23–27`) — the two most important sections are distinguished only by fill weight of the *same people icon*, and the Meetings icon isn't a meeting metaphor at all. Group labels "WORKSPACE" / "ORGANIZE" (`MainWindow.swift:39–42`) carry no meaning (why is Tasks "organize" but People "workspace"?). The rail is also completely state-free: no overdue-task count, no drifting-people count, no "2 finalizing" — all of that is buried in an overflow ⋯ menu (`MainWindow.swift:258–261`).

**2. The history stack forgets everyone except meetings.** `NavState` is only `(section, meetingID)` (`WorkspaceRouter.swift:44–47`). Navigate Today → Priya's profile → a meeting → Cmd-[ twice and you land on the People *tab*, not Priya. Back/forward silently drops person, task, project, voice-note, and tag positions — a back button that lies is worse than none.

**3. Person/note/tag routing is fire-and-forget NotificationCenter with timing hacks.** `router.openPerson` flips the section then posts a notification (`WorkspaceRouter.swift:130–134`); `PeopleListView` only hears it if it has already been built (`PeopleListView.swift:125–127`) — but tabs are lazily built on first visit (`MainWindow.swift:85–110`). TodayView papers over the race with `asyncAfter(0.05)` (`TodayView.swift:628–634`); `handleEntity` papers over it with a runloop hop (`MainWindow.swift:606–611`). A deep link to a person on a fresh launch where People was never visited can land on an unselected People tab. Voice notes (`WorkspaceRouter.swift:154–157`) and tag filters (`:168–171`) have the same fragility.

**4. Tasks and projects are unroutable — search dead-ends.** `route(kind:)` for `.project, .actionItem` is literally `section = .actions` (`WorkspaceRouter.swift:158–159`). Pick a task in ⌘K and you're dropped at the Tasks tab root to re-find it by hand: 1 click becomes 1 click + a manual re-search. Every "From meeting" task affordance and the Today commitments fallback (`TodayView.swift:190–194`, falls back to bare `section = .actions`) hits this wall.

**5. There is a second, parallel "workspace" inside the Tasks tab.** `ActionItemsView` keeps its own private `selectedMeetingID`, `selectedTaskID`, `selectedProjectID`, `selectedInitiativeID` (`ActionItemsView.swift:25–32`) — a shadow router the global history can't see. Its rail is literally titled "📁 Workspace" (`ActionItemsSidebar.swift:26–28`) inside a nav group also called WORKSPACE, and it contains *its own meetings list* that opens meetings in `MeetingNotesPage` (`ActionItemsView.swift:172–175`) — a **second meeting surface** competing with the canonical `UnifiedMeetingDetail` the router rebuild just consolidated. Same entity, two homes, two layouts: the exact fork the D1-1 router work was supposed to kill.

**6. Today is a 15-section wall with no internal navigation.** The feed stacks header, quick actions, up-next, live, needs-attention, today's meetings, action-items widget, follow-ups, commitments, decisions, on-this-day, recent notes, suggested people, stay-connected, and reconnect (`TodayView.swift:52–105`). Findability inside the app's own home page is scroll-only; section order is fixed; nothing is collapsible. The two people-nudge modules (`StayConnectedSection`, `ReconnectView`, `:96–99`) are near-duplicates a user can't tell apart.

**7. Four search boxes, three ranking models.** ⌘K uses FTS5+BM25+embeddings (`GlobalSearchView.swift:235–246`); the Meetings list search matches *title and attendee substring only* — a transcript phrase finds nothing there (`MeetingsView.swift:227–232`); People has its own debounced store query (`PeopleListView.swift:45–59`); Tasks has another (`ActionItemsView.swift:16`). The same query gives different answers depending on which box you typed it into — a findability fork users experience as "search is flaky".

**8. Desktop and mobile web fork the section taxonomy.** Desktop: 5 sections, Projects buried inside the Tasks rail. Web: 8 top-level tabs with Projects, Search, and Ask AI promoted (`Web/WebAssets.swift:132–139`). The briefing's own principle — "web/MCP must not fork the mental model" — is currently violated on both axes (what exists, and where it lives).

**9. Recurring meetings have no thread.** A `seriesID` exists and is rendered only as a tiny repeat glyph (`MeetingsView.swift:476–480`). For a product whose core loop is the recurring 1:1, there is no prev/next-in-series navigation, no "all 14 occurrences" — getting from this week's 1:1 to last week's is: back to list → scroll/search → click (3+ interactions).

**10. Section switching is a flat opacity crossfade** in a keep-alive ZStack (`MainWindow.swift:94–110`) — functional, but spatially mute; the nav rail implies a vertical order that the canvas never expresses.

## Existing-plan items I rank highest (endorsed, MASTER-PLAN Phase 2A/2C)

1. **`EntityLink` open protocol (2A)** — the single fix for the `.actionItem → section = .actions` dead-end (`WorkspaceRouter.swift:158`); gates backlinks, decision chips, and graph nav.
2. **`selectedPersonID` on the router (2A)** — kills the NotificationCenter/asyncAfter person-routing race (`WorkspaceRouter.swift:130–134`, `TodayView.swift:628–634`).
3. **Resurrect `ActionItemsViewModel` (2A)** — prerequisite to dissolving the Tasks tab's shadow router (`ActionItemsView.swift:25–32`).
4. **Recents rail + ⌘K quick-switcher (2A)** — ⌘K's empty state already shows recent meetings only (`GlobalSearchView.swift:211–222`); cross-entity recents is the cheapest "instant nav" win.
5. **Directed commitments with `personID` (2C)** — the task→person edge simply doesn't exist today (owner is a free string, `TodayView.swift:159–165`); without it the meeting→person→task triangle can't close.
6. **Universal backlink index (2C)** — turns every detail page into a nav hub instead of a leaf.

## NET-NEW recommendations

### D1-1 — State-bearing, semantically correct nav rail
- **What/why:** Fix the icon collision (`MainWindow.swift:23–27`: Meetings = `person.2.fill`?!) with real metaphors (Meetings → `calendar.day.timeline.left` or `waveform`, People → `person.2`); replace WORKSPACE/ORGANIZE with meaningful groups or none; add live badges to rail items — overdue tasks count on Tasks, drifting-people count on People, a subtle pulsing dot + "2 finalizing" on Meetings (data already exists: `manager.transcribingMeetingIDs`, `MainWindow.swift:258`). Benchmark: Things 3's Today count, Linear's inbox badge.
- **User value:** The rail becomes a glanceable status board; users stop opening tabs "to check if anything needs me."
- **Effort:** S · **Impact:** High · **Depends on:** none

### D1-2 — Entity-complete navigation history
- **What/why:** Extend `NavState` from `(section, meetingID)` (`WorkspaceRouter.swift:44–47`) to a typed entity ref: `(section, entity: WorkspaceEntityKind+id?, anchor: scrollPosition?)`. Back/forward then restores the *person*, *task*, *project page*, or *note* you were on — not just the tab. Add per-section last-selection memory (returning to People restores the last open person, like Mail/Linear).
- **User value:** Cmd-[ becomes trustworthy; "where was I?" disappears. This is the difference between a back button and a back *story*.
- **Effort:** M · **Impact:** High · **Depends on:** plan 2A (`selectedPersonID`), D1-3

### D1-3 — `PendingRoute` mailbox: delete all NotificationCenter navigation
- **What/why:** The plan adds `selectedPersonID` but doesn't fix the *pattern*: lazily-built tabs can't hear notifications (`MainWindow.swift:85–110` vs `PeopleListView.swift:125`). Give the router a `pendingDestination: WorkspaceEntity?` mailbox; target views consume it in `.onAppear`/`task` and clear it. Removes `meetingScribeOpenPerson`, `…OpenVoiceNote`, `…FilterByTag`, the `asyncAfter(0.05)` (`TodayView.swift:630`), and the runloop hop in `handleEntity` (`MainWindow.swift:608`). Deep links from notifications, Spotlight, widgets, and MCP become deterministic — they currently inherit every race.
- **User value:** Deep links that always land; the foundation Phase 2D (Spotlight/WidgetKit) silently requires and the plan never specs.
- **Effort:** M · **Impact:** High · **Depends on:** none (enables plan 2A/2D)

### D1-4 — Collapse the second meeting surface in Tasks
- **What/why:** `MeetingNotesPage` inside the Tasks tab (`ActionItemsView.swift:172–175`) and the meetings tree in `ProjectRail` (`ActionItemsSidebar.swift:19–21`) give meetings a second home with a different layout. Either (a) make those rows call `router.openMeeting()` with a "Tasks" tab pre-anchored in `UnifiedMeetingDetail`, or (b) embed `UnifiedMeetingDetail` itself. Rename the rail from "📁 Workspace" to "Projects". One entity, one canonical surface — finish what the router rebuild started.
- **User value:** Edits/notes made on a meeting are always the same page; no "which meeting view am I in?" confusion.
- **Effort:** M · **Impact:** High · **Depends on:** plan 2A (ActionItemsViewModel)

### D1-5 — Universal entity Peek (space-bar / hover preview)
- **What/why:** The plan specs a hover card for *attendee chips only*. Generalize: any entity row or chip anywhere (search results, backlinks, Today widgets, commitments, decisions) supports a Quick-Look-style peek — hover-delay or space-bar opens a floating preview card (person: avatar, health ring, last 3 encounters; meeting: summary head, attendees, 3 tasks; task: status, owner, source meeting) with one "Open ↵" promote action. Benchmark: Notion page peek, Craft hover previews, macOS Quick Look.
- **User value:** Cross-entity *glancing* without navigation — checking "who is this / what was that meeting" goes from 2 clicks + 2 back-clicks to 0 clicks. This is the single most "expensive-feeling" nav interaction available.
- **Effort:** L · **Impact:** High · **Depends on:** D1-3 (promote action routes), plan 2C (backlink data)

### D1-6 — Series spine: prev/next navigation for recurring meetings
- **What/why:** `seriesID` exists but is decoration (`MeetingsView.swift:476–480`). Add to `UnifiedMeetingDetail`'s header: ‹ prev / next › chevrons within the series, "Occurrence 14 of 23", and a dropdown timeline of all occurrences; on person detail, group the meeting timeline by series ("Weekly 1:1 · 14 meetings"). Keyboard: ⌥⌘← / ⌥⌘→.
- **User value:** "What did we discuss last week?" — the highest-frequency recall question for the 1:1 persona — drops from 3+ interactions to 1. No competitor (Granola included) navigates meetings as threads.
- **Effort:** M · **Impact:** High · **Depends on:** none

### D1-7 — Today information diet: jump-rail + collapsible, reorderable sections
- **What/why:** Today renders ~15 fixed sections (`TodayView.swift:52–105`). Add (a) a sticky right-edge mini-index (dots/labels like Craft's page outline) that scroll-jumps to a section; (b) per-section collapse + drag-reorder persisted in `@AppStorage`; (c) every section header becomes a link into its canonical tab *with the filter pre-applied* (e.g. "Commitments →" opens Tasks with owner-scope set — not the bare tab flip at `TodayView.swift:63, 73`); (d) merge StayConnected/Reconnect into one people module.
- **User value:** Today stops being a second app you scroll; it becomes a true index of the app. Findability inside the home surface becomes 1 click.
- **Effort:** M · **Impact:** Med-High · **Depends on:** D1-8 helps (filter deep-links)

### D1-8 — One query engine, many mouths (+ search escalation row)
- **What/why:** Per-tab search fields each use a different matcher — Meetings search can't see transcripts (`MeetingsView.swift:227–232`) while ⌘K can (`GlobalSearchView.swift:235–246`). Route all in-tab search fields through the same FTS5/hybrid engine scoped to that tab's kind, and append a persistent footer row to every in-tab result list: "Search everything for 'q' ⌘K" that opens the palette pre-filled.
- **User value:** Search behaves identically everywhere; a transcript phrase typed in the Meetings box finally finds the meeting. Kills the "search is flaky" perception with one engine.
- **Effort:** M · **Impact:** Med-High · **Depends on:** none

### D1-9 — Unify desktop/web section taxonomy (one mental model)
- **What/why:** Desktop has 5 sections with Projects nested in Tasks; web has 8 top-level tabs (`WebAssets.swift:132–139`). Decide the canonical model once — recommendation: **Today · Meetings · People · Tasks (with Projects rail) · Notes** everywhere; web's Search/Ask AI become a persistent search affordance + chat affordance (mirroring desktop's ⌘K + chat rail), not tabs. Same names, same order, same icons on both surfaces.
- **User value:** Phone and Mac stop being two apps to learn; muscle memory transfers. Directly enforces the briefing's "web must not fork the mental model."
- **Effort:** M · **Impact:** Med · **Depends on:** D1-1 (final icon/name set)

### D1-10 — Directional section transitions (spatial nav model)
- **What/why:** Replace the flat opacity crossfade between kept-alive tabs (`MainWindow.swift:94–110`) with a subtle directional slide (8–12pt offset + fade, 0.18s, `NDS.motion`-gated): moving *down* the rail slides content up, moving *up* slides down. Detail-pane pushes (meeting open from Today) get a left-slide; back gets right. Benchmark: Things 3 list transitions, iOS Settings.
- **User value:** Navigation acquires a physical geography — users *feel* where they are. Cheap, pure-premium texture on every single interaction.
- **Effort:** S · **Impact:** Med · **Depends on:** none

## Top 3 picks

1. **D1-3 PendingRoute mailbox** — every deep-link surface the plan is about to build (Spotlight, widgets, notifications, MCP citations) lands on today's race-prone NotificationCenter routing; fix the foundation first.
2. **D1-4 Collapse the second meeting surface** — the canonical-detail consolidation is the app's best recent IA work, and the Tasks tab quietly undoes it.
3. **D1-6 Series spine** — highest-frequency recall flow for the core persona, 3+ clicks → 1, and a genuine differentiator.

**Single highest-priority rec overall:** D1-3 — it is small, unblocks D1-2/D1-5 and the plan's own 2A/2D items, and converts navigation from "usually works" to deterministic, which is the precondition for everything premium layered on top.
