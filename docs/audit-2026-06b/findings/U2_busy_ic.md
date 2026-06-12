# End-User — Busy Senior IC (4–6 meetings/day, zero-overhead capture)
> If a flow costs me more than 5 seconds or one alt-tab, I stop doing it — and the product silently dies for me.

## Full-app audit (through my lens)

I walked the live source as four concrete moments of my day. Click/second counts are from the actual code paths.

### Scenario 1 — "Meeting starts NOW, I need recording in <2s"

**Strong.** There are genuinely fast paths:
- Global record toggle **⌥⌘R works system-wide** — `meetingRecordHotkey.onTrigger` starts when idle / stops when recording (`MeetingScribeApp.swift:353-365`; default R+⌥⌘ in `Models/Settings.swift:388-405`). **0 clicks, ~1s.**
- Meeting-start notifications carry **Join & Record / Record only** actions (`Notifications/NotificationManager.swift:16-18,49-63`). **1 click.**
- Menu bar: "Record Ad-hoc Meeting" + per-meeting record buttons that auto-stop a current recording before joining the next (`MenuBarView.swift:73-95,152-179`). **2 clicks.** Back-to-back meetings are handled — `switchToRecording` is exactly what a 4-meetings-in-a-row day needs.
- Today's full-width "Record Meeting" primary button (`TodayView.swift:405-417`) and Up-Next "Join & record" hero (`TodayView.swift:441-467`). **1 click if the app is frontmost.**

**Weak — the fast paths all record the WRONG meeting.** Every <2s path calls `startRecording(for: nil)`: the hotkey (`MeetingScribeApp.swift:360`), the menu-bar quick action (`MenuBarView.swift:74`), Cmd-R (`MeetingScribeApp.swift:102-105`), Today's primary button (`TodayView.swift:407`). So my 10:00 "Product Sync" — which is sitting right there in `calendar.upcoming` with title, attendees, conference URL — gets captured as **"Ad-hoc Recording", zero attendees**. That breaks the title in the Meetings list, attendee→People linking, pre-meeting briefs, and the 3-weeks-later search. The only metadata-correct fast paths are the notification action and the per-row menu-bar button. Speed and correctness are currently a trade-off; for this persona they must not be.

**Weak.** `NewMeetingSheet` is well built (upcoming list + title field, Enter submits — `NewMeetingSheet.swift:27-29,63-70`) but it's the *slow* path I'd never use mid-scramble, and ad-hoc recordings keep the placeholder title forever unless I hand-rename.

### Scenario 2 — "Capture a thought mid-meeting without alt-tabbing"

This is the persona's most-repeated job (10–20×/day) and it's the weakest area.

- **Typed capture requires a full context switch.** The in-app `MeetingRecordDock` is deliberately in-app only (`MeetingRecordDock.swift:3-6`) and only renders when the app is visible and not on the Meetings tab (`MainWindow.swift:393-398`). Mid-Zoom it's invisible. The capture path is: alt-tab → dock "Open & add notes" → land in detail → type → alt-tab back. **~15–20s + total context loss.** Its only actions are Open and Stop (`MeetingRecordDock.swift:53-61`) — no inline capture.
- **F5 dictation is a foot-gun for "note to self."** `dictationAutoPaste` defaults **true** (`Models/Settings.swift:409-412`), so F5 → speak → F5 *pastes the transcript at the cursor of the frontmost app* (`Hotkey/QuickDictation.swift:289-295`). Mid-Zoom, my private "remind me to push back on Sarah's timeline" lands in the Zoom chat box. And the overlay can't warn me: dictation and voice-note flows collapse into the same `.recording` pill (`FloatingOverlay.swift:92-117`), labelled "VOICE NOTE · OVER ANY APP" (`FloatingOverlay.swift:286`) — identical UI for "saves quietly" vs "will type into the focused app."
- **The menu-bar voice note forcibly activates the main window** — `openWindow(id:"main"); NSApp.activate(...)` *before* `startQuickNote()` (`MenuBarView.swift:80-87`) — the exact alt-tab the floating overlay (which already follows me across Spaces, `FloatingOverlay.swift:211-215`) was built to avoid.
- **The NL quick-add is trapped inside the Tasks tab.** `TaskQuickAddParser` is excellent (priority/#label/natural-language dates, `ActionItems/TaskQuickAddParser.swift:24-70`) but only reachable via the Tasks-toolbar popover whose ⌥⌘N is an in-app SwiftUI shortcut (`ActionItemsChrome.swift:371-375`). There is no global quick-entry.

### Scenario 3 — "Triage action items in 60 seconds at end of day"

**Strong.** The right architecture exists: extracted items land in a triage inbox before polluting Tasks (`TriageInboxView.swift:3-7`), with bulk "Add all N → Tasks" (`TriageInboxView.swift:52-59`), undo-able discard via toast (`TriageInboxView.swift:124-129`), and a source-meeting chip (`TriageInboxView.swift:94-100`). Quick-add keeps the popover open for rapid multi-entry (`ActionItemsChrome.swift:475`). `NeedsAttentionWidget` puts overdue work on Today (`TodayView.swift:62-64`).

**Weak.** Triage is **mouse-only**: no ↑/↓ row focus, no Return=add / X=discard, no due-date or owner assignment at triage time (only an optional project menu, `TriageInboxView.swift:107-119`). A 12-item day costs ~25–35 precise clicks — 2–3 minutes, not 60 seconds. And the Today "Commitments" split identifies *me* by fragile owner-string matching against my name/aliases (`TodayView.swift:159-165`) — "Tyler to send deck" vs "TY" silently mis-buckets.

### Scenario 4 — "That thing Sarah said about the migration, 3 weeks later"

**Strong engine, broken last mile.** Cmd-K is global (`MeetingScribeApp.swift:82-87`), FTS5+BM25 with hybrid embedding re-rank (`GlobalSearchView.swift:230-247`), plus a command palette and "Ask Chat" passthrough. The transcript view already has inline search with highlight and player-synced scroll (`TranscriptSyncView.swift:89-143,355-358`).

But the journey: ⌘K → "migration" → result rows show **title + date only** — `VaultSearchResult` has no snippet field at all (`People/SecondBrainDB.swift:8-14`), so FTS5's `snippet()` is unused and I can't tell *which* of five "Infra Sync" meetings matched → open one → land on the **Notes** tab (`UnifiedMeetingDetail.swift:26`) because `WorkspaceRouter.route` drops everything except the entity ID (`WorkspaceRouter.swift:144-153`) → click Transcript → **retype "migration"** → scan. ~6 interactions, 30–60s, and "Sarah" can't be combined with "migration" as a person filter at all. Opening a `.actionItem`/`.project` result is worse — it just flips the section with no row selection (`WorkspaceRouter.swift:158-159`).

## Existing-plan items I rank highest

1. **In-meeting hybrid scratchpad (2D)** — the single biggest fix for my most-frequent job; the Granola merge mechanic is exactly right.
2. **Calendar-driven auto-record, armed mode (2D)** — dissolves Scenario 1 entirely; zero seconds beats two.
3. **Directed commitments with `personID` (2C)** — kills the `isMine()` owner-string guessing (`TodayView.swift:159-165`) that makes the Commitments widget untrustworthy.
4. **Recents rail + Cmd-K quick-switcher (2A)** — with 4–6 meetings/day, "the meeting I had open 10 minutes ago" is my #1 navigation, and the router already tracks history (`WorkspaceRouter.swift:49-117`).
5. **Mid-call "catch me up" (2D)** — I join late twice a week; pairs with the 5-minute-chunk live transcript (`MeetingTranscriptTab.swift:63-80`).
6. **Live + post-recording status feedback (2E)** — trust that capture is happening is what lets me stop thinking about the tool.

## NET-NEW recommendations

### U2-1 — Live-event snap: fast record paths attach to the calendar meeting happening now
- **What/why:** Every <2s start path calls `startRecording(for: nil)` (`MeetingScribeApp.swift:360`, `MenuBarView.swift:74`, `TodayView.swift:407`) even when `calendar.upcoming` has a live event. Resolve `for: nil` → the live (or starting-within-10-min) calendar event automatically; show a 5s toast "Recording 'Product Sync' — Not this meeting?" with one-click detach to ad-hoc.
- **User value:** The 0-click hotkey stops producing title-less, attendee-less orphans; search, briefs, and People linking work without me paying any setup tax.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### U2-2 — Carry the query through the router: search result → transcript, pre-highlighted
- **What/why:** Add `pendingTranscriptQuery` to `WorkspaceRouter` (set in `GlobalSearchView.open`); when a meeting result was matched on transcript content, land on the Transcript tab (not `.notes`, `UnifiedMeetingDetail.swift:26`) with `TranscriptSyncView.searchText` pre-filled and scrolled to first hit — all the rendering already exists (`TranscriptSyncView.swift:89-143`).
- **User value:** "Find what Sarah said" drops from ~6 interactions + retyping to ⌘K → type → Enter. <10 seconds.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### U2-3 — Matched-context snippets in ⌘K results
- **What/why:** `VaultSearchResult` carries no snippet (`People/SecondBrainDB.swift:8-14`); use FTS5 `snippet(fts, …)` to return a 2-line excerpt with the term bolded (and speaker prefix when the source is a transcript line), rendered under the title in `GlobalSearchView.row` (`GlobalSearchView.swift:188-191`).
- **User value:** Disambiguates five identically-named recurring meetings before I open the wrong one; this is the Spotlight/Linear/Notion search table-stakes that makes results scannable.
- **Effort:** M
- **Impact:** High
- **Depends on:** pairs with U2-2

### U2-4 — Keyboard-first triage: inbox-zero in 60 seconds
- **What/why:** `TriageInboxView` is mouse-only (`TriageInboxView.swift:104-134`). Add a focused-row model: ↑/↓ or j/k move, **Return**=add, **X**=discard (undo toast already exists), **T**=due today, **M**=tomorrow, **W**=next week, **P**=project picker, **A**=add-all. Show the key hints inline on the focused row.
- **User value:** 12 items: ~30 clicks → ~15 keystrokes, hands never leave the keyboard. The actual 60-second end-of-day ritual the view's name promises.
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### U2-5 — Global Quick Entry window (Things-style), live-meeting aware
- **What/why:** A 4th global hotkey opens a small floating NSPanel (same window recipe as `FloatingOverlayController.ensureWindow`, `FloatingOverlay.swift:196-219`) containing one text field wired to `store.createTask(parsing:)` — without activating the main app. If a recording is live, default-link the entry to that meeting with an elapsed-time stamp.
- **User value:** Mid-Zoom typed capture: hotkey → type → Enter → back, **~3 seconds, zero alt-tab**. Replaces the menu-bar voice-note path that force-activates the main window (`MenuBarView.swift:80-87`).
- **Effort:** M
- **Impact:** High
- **Depends on:** U2-8 makes it people-aware

### U2-6 — Inline capture line in the MeetingRecordDock
- **What/why:** The dock's only actions are Open and Stop (`MeetingRecordDock.swift:53-61`). Add a one-line "Note or todo…" field: Enter appends a timestamped bullet to the meeting's notes; a leading `!` or `todo ` files it through the quick-add parser as a meeting-linked task.
- **User value:** When I *am* in the app between calls, capture is 1 field instead of Open → detail → Notes tab; it also becomes the natural seed UI for the planned 2D scratchpad.
- **Effort:** S
- **Impact:** Med
- **Depends on:** complements 2D scratchpad

### U2-7 — Make dictation's destination explicit (and add a no-paste "note to self" mode)
- **What/why:** `dictationAutoPaste` defaults true (`Models/Settings.swift:409-412`) so F5 capture pastes into whatever app has focus (`QuickDictation.swift:289-295`), and the overlay pill renders identically for paste-dictation and save-only voice notes (`FloatingOverlay.swift:92-117`). Show the destination in the pill ("→ types into Zoom" vs "→ saves to Notes"), and add a modifier (⇧+hotkey) that forces save-only for the current capture.
- **User value:** Removes the one failure mode that would make me delete the app: leaking a private mid-meeting thought into a shared Zoom chat.
- **Effort:** S
- **Impact:** High (trust)
- **Depends on:** none

### U2-8 — `@person` token in the quick-add grammar
- **What/why:** `TaskQuickAddParser` parses `!priority` `#label` and dates but not people (`TaskQuickAddParser.swift:24-70`). Add `@name` → fuzzy-resolve against `PeopleStore`, set `owner` + (once 2C lands) `personID`; surface an inline completion chip in the popover (`ActionItemsChrome.swift:450-461`).
- **User value:** "Email @sarah friday !high" is a fully-attributed directed commitment in one line — people become first-class in tasks at capture time, not via later editing. Feeds the Today owe/owed split with real IDs instead of string matching.
- **Effort:** S
- **Impact:** High
- **Depends on:** amplifies planned 2C

### U2-9 — Auto-title ad-hoc recordings from the first transcript chunk
- **What/why:** Ad-hoc meetings are born "Ad-hoc Recording" (`MeetingManager.adhocMeeting()` via `NewMeetingSheet.swift:78`) and stay that way. After the first 5-minute live chunk (or at finalize), have Ollama emit a 4–6-word title; store as auto-title, never overwrite `userTitle`, badge it subtly as AI-named.
- **User value:** A Meetings list of "Ad-hoc Recording (7)" is unsearchable three weeks later; this fixes recall for exactly the recordings started by the zero-friction paths.
- **Effort:** S
- **Impact:** Med
- **Depends on:** U2-1 reduces (not eliminates) the need

### U2-10 — Search qualifiers: `with:@sarah before:may in:transcripts`
- **What/why:** Pre-parse ⌘K queries for `with:@person` (filter meetings by attendee/linked person via the people graph), `in:` (entity kind, mirroring the existing filter chips `GlobalSearchView.swift:26-49`), and `before:/after:` (NSDataDetector, same as quick-add). Strip qualifiers, run the remainder through the existing FTS path.
- **User value:** "What Sarah said about the migration" becomes literally typeable: `migration with:@sarah`. This is the people-pillar version of search — person × keyword × time in one query box.
- **Effort:** M
- **Impact:** High
- **Depends on:** U2-3 (snippets make the filtered results verifiable)

## Top 3 picks

1. **U2-1 Live-event snap** — makes the already-great 0-click capture paths produce correctly-attributed meetings; every other recall/people feature compounds on it.
2. **U2-2 Query-carrying search deep-land** (with U2-3 snippets) — turns a 60-second, retype-the-query hunt into a sub-10-second jump using highlight code that already exists.
3. **U2-5 Global Quick Entry** — the only true zero-alt-tab typed capture; the persona's most frequent unmet job.

**Single highest-priority rec overall:** **U2-1**. It's S-effort, touches four call sites, and converts the app's best existing speed asset (⌥⌘R) from a metadata liability into the product's signature move: *press one chord anywhere, and the right meeting — title, attendees, people links — is being captured.*
