# PM Group — Cross-Surface Coherence & Workflow Fit
> One product, four surfaces (desktop, mobile web, MCP/Claude, notifications/menu bar): the user should carry a single mental model across all of them, each surface should do what it's uniquely good at, and every handoff (phone → Mac, notification → app, Claude → app) should land somewhere real.

## Full-app audit (through my lens)

### Strong
- **Writes converge on one store layer.** `WebAPI` deliberately routes phone edits through the same main-actor stores as desktop (`Sources/MeetingScribe/Web/WebAPI.swift:5-14`), and the relationship-health score is one shared `VaultKit.RelationshipHealth` formula computed identically on desktop badge, web (`WebAPI.swift:329-345`), and MCP. This is the right backbone — no data forking.
- **`meetingscribe://` is real and routed.** Eight entity kinds (`Models/WorkspaceLinks.swift:16-17`), registered scheme, `onOpenURL` → canonical router (`MeetingScribeApp.swift:55-58`), and notifications already attach deep links for tasks and finished meetings (`Notifications/NotificationManager.swift:171,208`). The desktop side of deep-link infrastructure is done.
- **Capture-from-anywhere has one channel.** App Intents drop JSON envelopes into `_inbox/` that the watcher ingests (`Widgets/CaptureIntents.swift:6-25`) — a clean, surface-agnostic capture mental model worth extending (see P3-8).

### Weak / incoherent
- **The IA forks between desktop and web.** Desktop: 5 sections, People 3rd, grouped WORKSPACE/ORGANIZE, Projects *nested inside* Tasks ("initiatives, projects (pages), and tasks" — `UI/MainWindow.swift:338`). Web: 8 flat tabs in a different order with **Projects promoted to top-level** and People demoted to 5th (`Web/WebAssets.swift:131-140`). A user who learns "Projects live inside Tasks" on the Mac meets a different taxonomy on the phone.
- **Vocabulary and iconography drift.** Web tab says "Notes" but its screen title is "Voice notes" (`WebAssets.swift:137` vs `:183`); desktop calls the section "Voice Notes". Desktop chat is "Assistant" (`MainWindow.swift:457`), web is "Ask AI", MCP is Claude. The desktop **Meetings icon is `person.2.fill`** — a *people* glyph — while People is `person.2` (`MainWindow.swift:23-25`); web uses a 📅 calendar emoji for Meetings. Web nav icons are emoji (`&#127968;`, `&#129302;` etc., `WebAssets.swift:132-139`) versus SF Symbols on desktop — directly fails the "clean and expensive" pillar on the surface most often shown to other people (your phone in a meeting).
- **Three forked retrieval brains.** Desktop ⌘K runs hybrid FTS5+embeddings (`searchVaultHybrid`, `UI/GlobalSearchView.swift:243`). Web `/api/search` is naive title-substring matching that never touches transcripts or summaries (`WebAPI.swift:796-817`). Web Ask AI has its *own* hand-rolled keyword scorer (`WebAPI.swift:397-424`) instead of `ChatSession`'s grounding, and MCP `search_everything` is a fourth path. Identical queries return different results per surface — the deepest mental-model fork in the app.
- **Web has zero URL state.** The phone app is a JS in-memory stack (`WebAssets.swift:146,164-174`); `HTTPServer` serves only `/` and `/api/*`. Refresh loses your place, nothing is shareable/bookmarkable, and no external trigger can land the phone on an entity. `meetingscribe://` has no web twin.
- **Citations stop at the Mac's edge.** Desktop chat injects `meetingscribe://meeting/<id>` citations (`Chat/ChatSession.swift:262,277`); web Ask AI returns a plain string with a bare `sources` *count* (`WebAPI.swift:436`) the UI never renders — answers on the phone are dead ends. MCP tool output contains **no `meetingscribe://` links at all** (zero matches in `MeetingScribeMCP/main.swift`), so a Claude coaching session can never hand the user back into the app.
- **Notification landings are uneven.** Meeting-ready and task-due notifications deep-link correctly, but the daily brief literally says *"Open MeetingScribe → Standup"* as body text (`NotificationManager.swift:223`) — a written instruction to a destination that isn't even a nav section (Standup is a button inside TodayView, `UI/TodayView.swift:374`). `WorkspaceLink` has no route for sections/sheets, so it *couldn't* deep-link there today.
- **The phone is blind to the Mac's live state.** `/api/health` returns counts only (`WebAPI.swift:101-111`); the web UI has no recording indicator, no stop control, no "meeting being transcribed" status, and no *upcoming* meetings (every list is `listPastMeetings`). The two highest-value phone moments — "is my Mac still recording?" and "what's my next meeting and what do I owe these people?" — are both unsupported.
- **MCP parity holes.** 27 tools (`main.swift:1922-1947`) cover meetings/people/tasks/encounters well, but there is no `list_projects`/`get_project` (projects are first-class on both UIs) and no `get_today`/standup-style aggregate, so Claude can't answer "what's in flight on Project X" or assemble the same morning picture the other surfaces show.

### Where each surface should specialize (current code mostly agrees, accidentally)
- **Desktop:** capture + deep work (recording, editing, nav backbone). Correct today.
- **Phone:** glanceable prep, quick capture, quick logging, review on the go. Today it's a *mirror* (good) but misses prep/capture/live-status (the specialization).
- **MCP/Claude:** synthesis + coaching over the vault. Right shape, but it's a read-mostly silo that can't point back into the app.
- **Notifications/menu bar:** the *trigger* surface. Menu bar (`UI/MenuBarView.swift`) is meetings-only — no relationship/drift presence despite the coach loop being the Phase-2 centerpiece.

## Existing-plan items I rank highest
1. **2A `EntityLink` open protocol + router unification** — the desktop half of every cross-surface handoff; nothing below works without one canonical `open(kind,id)`.
2. **2F MCP `search_everything` deep-link citations** (planned, shipped *without* the links in PR #94) — finish the citation half; it's the MCP→app bridge.
3. **2D Spotlight indexing with `meetingscribe://` deep links** — makes the scheme the system-wide spine, not an internal trick.
4. **2D Proactive pre-meeting brief + `get_meeting_prep` MCP tool** — the single feature that should exist on *all four* surfaces from day one (see P3-4).
5. **2H Mobile review layout / `/whatsnew` sync-glance** — right instinct that the phone is a review surface; fold into P3-3/P3-4 rather than building separately.
6. **1G App Intents suite completion** — `_inbox/` envelopes are the cross-surface capture primitive; finishing the verb set strengthens every surface at once.

## NET-NEW recommendations

### P3-1 — Web URL routing twinned 1:1 with `meetingscribe://`
- **What/why:** Give the phone app hash routes (`#/meeting/<id>`, `#/person/<id>`, `#/tab/tasks`…) whose `<kind>/<id>` grammar is byte-identical to `WorkspaceLink` (`Models/WorkspaceLinks.swift:68-87`). Replace the in-memory `stack` (`WebAssets.swift:146`) with history-API state so refresh, back-swipe, and bookmarks work. One tiny shared mapping means any link can be rendered for either surface by swapping the prefix (`meetingscribe://` ↔ `https://<tailscale-host>/#/`).
- **User value:** Refresh no longer dumps you to Today; links become shareable, notifiable, and hand-off-able. This is the enabler for P3-5, P3-6, and P3-7.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### P3-2 — One canonical IA: same sections, same order, same words, same glyphs
- **What/why:** Decide the canonical top-level once (recommend: Today · Meetings · People · Tasks · Notes, People 3rd everywhere — people-first pillar) and conform the web tab bar (`WebAssets.swift:131-140`) to it: demote Projects into the Tasks tab as a segment (matching desktop's "Tasks workspace" model, `MainWindow.swift:338`), rename "Notes"→"Voice Notes", fold Search behind a persistent search field instead of a tab. Fix desktop's Meetings glyph (`person.2.fill` → `calendar`, `MainWindow.swift:23`), and replace web emoji icons with inline SVG strokes matching the SF Symbols set.
- **User value:** One taxonomy to learn; muscle memory transfers between Mac and phone; emoji-free nav reads premium (Linear's mobile web, Things 3 parity of iPad/Mac IA are the benchmark).
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### P3-3 — Mac presence on the phone: live recording status + remote stop
- **What/why:** Extend `/api/health` (`WebAPI.swift:101-111`) with `recordingState` (title, startedAt, elapsed) and `finalizingCount`, and render a persistent header strip in the web app: red dot + "Recording: Weekly Sync · 42:10 · [Stop]" (POST `/api/recording/stop` → `manager.stopRecording()`), or "Transcribing 1 meeting…". Today the phone literally cannot tell whether the Mac is capturing.
- **User value:** The #1 anxiety moment — you leave your desk mid-meeting or forget to stop — becomes a one-glance, one-tap fix from anywhere on the tailnet. This is the "start on Mac → finish on phone" handoff.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### P3-4 — Phone Today = "next meeting + the humans in it" (upcoming on web)
- **What/why:** The web app has no calendar data at all — every endpoint reads `listPastMeetings`. Add `/api/upcoming` (CalendarService already holds it) and lead the web Today with a *next-meeting card*: time, conference link (tap to join from the phone!), attendee chips with health pills, last meeting's summary snippet, and open commitments involving those attendees. This is the surface-appropriate specialization of the planned 2D pre-meeting brief.
- **User value:** "Walking to the meeting, phone in hand" is the canonical mobile moment; today that user sees stale past meetings. Closes the loop with desktop's Today instead of mirroring a subset of it.
- **Effort:** M
- **Impact:** High
- **Depends on:** none (synergy with planned 2D brief)

### P3-5 — One retrieval brain across all four surfaces
- **What/why:** Route web `/api/search` (`WebAPI.swift:796-817`) and web chat grounding (`WebAPI.swift:397-424`) through the same `searchVaultHybrid` pipeline desktop ⌘K uses (`GlobalSearchView.swift:243`) and MCP `search_everything` wraps. Delete the two ad-hoc keyword scorers. Result objects share one shape: `{kind, id, title, subtitle, snippet}` — the same grammar as P3-1 routes.
- **User value:** A search that found something on the Mac finds it on the phone and via Claude; transcript/summary content becomes findable from the phone for the first time. Kills the most user-visible mental-model fork ("phone search is worse, I'll wait till I'm at my desk").
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### P3-6 — Citations that navigate, on every surface
- **What/why:** (a) Web Ask AI: have `/api/chat` return `sources: [{kind,id,title}]` (it already computes them, then throws them away — `WebAPI.swift:436`) and render tappable source chips under each answer that route via P3-1. (b) MCP: append `meetingscribe://<kind>/<id>` links to `get_meeting`, `get_person`, `search_everything`, `list_action_items` output (zero links exist in `MeetingScribeMCP/main.swift` today) so Claude's coaching answers can say "open it" and the registered scheme lands the user on the entity.
- **User value:** Every AI answer — phone, desktop, Claude — terminates in the canonical record instead of a dead-end paragraph. Trust ("show me where that came from") plus one fewer manual search per answer.
- **Effort:** S
- **Impact:** High
- **Depends on:** P3-1 (web half)

### P3-7 — Notification landing contract: every notification deep-links, no instructions
- **What/why:** Extend `WorkspaceLink` with section/feature routes (`meetingscribe://section/today`, `meetingscribe://standup`) so the daily brief stops printing *"Open MeetingScribe → Standup"* as prose (`NotificationManager.swift:223`) and instead opens the Standup sheet directly (`TodayView.swift:374-382` shows it's currently a button-only destination). Add a "View brief" action on the meeting-start category and adopt a one-line team rule: *a notification may not ship without a `deepLink` userInfo key* (enforce with a unit test over `NotificationManager`).
- **User value:** Tap → exactly the promised screen, every time. Notification quality is the difference between a habit engine and a nag.
- **Effort:** S
- **Impact:** Med
- **Depends on:** none

### P3-8 — Phone quick capture into `_inbox/` (notes + tasks + encounter, app closed or not)
- **What/why:** The phone cannot create a voice/quick note at all (web Notes is read-only list + edit), and task/person/encounter creation uses `window.prompt()` (`WebAssets.swift:327,458,499`) — the cheapest control on the platform. Add a persistent "+" capture button (bottom-right, above the tab bar) opening a single sheet: note / task / encounter-for-person, POSTing to a new `/api/inbox` that writes the *same* `_inbox/` envelopes App Intents use (`Widgets/CaptureIntents.swift:18-25`). One capture mental model everywhere: "anything captured anywhere lands in the inbox."
- **User value:** The phone becomes the capture device it should be (thought on the train → vault), and prompt() dialogs — the single cheapest-feeling thing in the product — die.
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### P3-9 — Bidirectional handoff affordances ("Send to phone" / "Open on Mac")
- **What/why:** Desktop: a share-menu item on any entity detail that shows a QR of the web URL for that entity (token + P3-1 route). Web: an "Open on Mac" row in each detail view that POSTs `/api/open {kind,id}`; the server posts `.meetingScribeOpenEntity` (`WorkspaceLinks.swift:103`) so the Mac window jumps there. Both are <30 LOC once P3-1 exists.
- **User value:** The classic moment — reviewing a transcript on the phone, sitting down at the Mac, and continuing *without re-finding anything* (and vice versa when running out the door). No competitor's local-only tool has cross-device continuity; this is a cheap wow.
- **Effort:** S
- **Impact:** Med
- **Depends on:** P3-1

### P3-10 — MCP parity: projects + the Today aggregate
- **What/why:** Add `list_projects` / `get_project` (tasks grouped by section, linked meetings — same payload `WebAPI.projectDetail` already assembles, `WebAPI.swift:587-618`) and `get_today` (drift + due tasks + recent + upcoming — mirror of `/api/today`, `WebAPI.swift:351-383`). Today MCP exposes tasks but not the project layer both UIs treat as first-class, and Claude must make 4+ calls to assemble the morning picture every surface else gets in one.
- **User value:** "Claude, what's the state of Project X?" and "brief me on today" work in one tool call; the coach sees the same world the user sees.
- **Effort:** S
- **Impact:** Med
- **Depends on:** none

### P3-11 — Menu bar joins the relationship product
- **What/why:** `MenuBarView` is 100% meetings (status, upcoming, record buttons — `UI/MenuBarView.swift:10-95`) while the product's habit loop is relationships. Add one compact "Stay connected" line (top 2 overdue people from the shared health sort with a one-click "Log" that fires the encounter quick-log) and a "Phone access" item surfacing the QR (currently buried in Settings, per `WebAssets.swift:41`).
- **User value:** The 2-second daily relationship habit becomes reachable without opening the main window — the menu bar is the highest-frequency surface the coach loop never touches.
- **Effort:** S
- **Impact:** Med
- **Depends on:** none

### P3-12 — Surface lexicon: one name per concept, lint-enforced
- **What/why:** A single `Lexicon` constants table (Tasks ≠ "action items" in user-facing copy; "Voice Notes" everywhere; pick ONE assistant name for desktop rail + web tab; "Check-in" phrasing) consumed by desktop strings and the embedded web HTML, plus a design-lint grep over `WebAssets.swift` and MCP tool *descriptions* for banned legacy terms. MCP internal tool IDs stay stable; only human-readable `title`/description text conforms.
- **User value:** Naming drift is how an indie app feels indie. One vocabulary across Mac, phone, Claude, and notifications is a precondition for "expensive."
- **Effort:** S
- **Impact:** Med
- **Depends on:** P3-2 (decides the canonical names)

## Top 3 picks
1. **P3-1 Web URL routing twinned with `meetingscribe://`** — small, foundational, unlocks citations, handoff, and notification landings on the phone.
2. **P3-3 Live recording status + remote stop on the phone** — the single most valuable phone feature missing, and it's an S.
3. **P3-5 One retrieval brain** — kills the worst cross-surface inconsistency (four search/grounding implementations) and instantly upgrades phone search and Ask AI quality.

**Single highest-priority rec overall:** **P3-1.** It's the cheapest item with the longest dependency tail — web citations (P3-6), handoff (P3-9), and any future phone-facing notification all require routable web URLs, and it converts the just-shipped mobile overhaul from a mirror into a true second surface.
