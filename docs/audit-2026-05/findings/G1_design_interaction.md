# Design — Interaction Design & Power-User Flows

*Lens: micro-interactions, keyboard-first usability, command palette, recording controls/HUD, list nav, feedback during long ops, drag/drop, inline editing, undo.*

## Full-app audit (through my lens)

The app is further along than the plans imply — several "net-new" ideas in V3 §4 are already shipped or scaffolded. Through the interaction lens, the bones are good but the keyboard story is half-built and feedback during the app's two slowest operations (transcribe, summarize) is thin.

**Keyboard map exists but is shallow and partly broken.** `MeetingScribeApp.swift:64-112` defines a real menu-command keymap: ⌘K search, ⌘1–⌘5 navigate, ⌘R / ⇧⌘R record start/stop, ⌘N new task, ⇧⌘N voice note, ⇧⌘P new person. That's a solid foundation. But:
- ⌘R **start** and ⇧⌘R **stop** are two different chords for one toggle — users will fight muscle memory. Granola/Zoom use one toggle.
- There is **no global (system-wide) record hotkey** — only the in-app menu command. The only system-wide hotkey is F5 dictation (`GlobalHotkey.swift`, registered in `MeetingScribeApp.swift:275`). You can't start a meeting recording without the app frontmost.
- ⌘1–⌘5 post a `NotificationCenter` event (`:76-85`) routed in `MainWindow.swift:386`; fine, but section switching is the *only* thing wired — there's no ⌘[ / ⌘] back/forward, no ⌘F to focus the in-pane search, no Esc-to-deselect.

**The ⌘K palette is search-only, not a command palette.** `GlobalSearchView.swift` is a competent fuzzy entity-finder (people/meetings/tasks/notes, arrow-key nav at `:67-69`, scoped filter tabs, recent-as-default). But it cannot *do* anything — you can't "Start recording", "Draft follow-up", "Toggle assistant", "Open notes folder", or "New task" from it. Every real command lives only in the menu bar or a toolbar button. The nav rail even renders a `⌘K` chip (`MainWindow.swift:144-153`) promising more than search delivers.

**MeetingsView list is mouse-only — the headline keyboard regression.** Despite DEF-2 being in the plan, `MeetingsView.swift:144-175` is still a `ScrollView` + `LazyVStack` of `Button`s, not `List(selection:)`. ↑/↓/Enter do nothing in the app's most-used list. People and Notes are `List`-based; Meetings is the outlier. There's no type-to-select, no Enter-to-open.

**Recording feedback is fragmented across three surfaces with different fidelity.**
- Voice-note / dictation gets a beautiful floating HUD (`FloatingOverlay.swift`): pulsing dot, live `AudioLevelMeter` (`:270`), elapsed mono-digit timer, Stop/Cancel, and a done-pill with Copy/Open. This is the best interaction in the app.
- **Meeting recording gets none of that.** The toolbar (`MainWindow.swift:570-576`) just swaps to a red "Stop Recording" button — no elapsed time, no level meter, no "is audio actually being captured?" reassurance. The Today "Recording now" card (`TodayView.swift:199-209`) and the live `UnifiedMeetingDetail` (mode `.live` → opens the Notes tab, `:250-251`) carry the live transcript, but there is no persistent HUD when the user navigates away or the window is backgrounded. The dictation flow out-polishes the flagship recording flow.
- The menu-bar extra (`MenuBarView.swift:113-125`) shows "Recording / Started <time>" but no running elapsed counter or level.

**Feedback during long ops (transcribe/summarize) is a tiny spinner.** When meetings finalize, the only signal is `MainWindow.swift:594-600`: "N finalizing" with a small ProgressView, plus a menu-bar label. No per-meeting progress, no stage ("transcribing" vs "summarizing"), no ETA, no way to know whisper is making progress vs. hung. The transcribing pill for voice notes at least says "Whisper is running locally · usually a few seconds" (`FloatingOverlay.swift:310`) — meeting finalize says nothing comparable.

**No undo, anywhere.** `grep` for `UndoManager`/`registerUndo` → zero hits. Destructive/lossy actions have no safety net: checking an action item, deleting a person, retagging a meeting (which physically moves vault folders), clearing a transcript, regenerate-summary (overwrites). For a local-first tool that *moves files on disk* in response to taps, the absence of undo is the riskiest interaction gap.

**Drag/drop is confined to one screen.** Only `ActionItemsBoardView.swift:52-70` has `.draggable`/`.dropDestination` (kanban cards between columns). No drag-to-reorder tasks in list mode, no drag an audio file onto the window to import (import is buried behind a toolbar button + `NSOpenPanel`, `MainWindow.swift:519-533`), no drag a person onto a meeting to add an attendee.

**Inline editing is inconsistent.** Meeting title is inline-editable (`MeetingSummaryTab.swift:227` `titleFocused`); notes autosave with a 0.6s debounce (`UnifiedMeetingDetail.swift:275-287`) — good. But People identity fields are still modal-only (`AddPersonSheet`, confirmed by the plan's PPL-1), and there's no consistent "click text → edit in place → blur to save" affordance pattern users can learn once and apply everywhere.

**Empty/loading states are decent; error states are weak.** Empty states exist (`MeetingsView.swift:179-210`, `TodayView.swift:286-301`). But errors mostly degrade to `NSSound.beep()` (e.g. dictation swap with Ollama down, `QuickDictation.swift:99`) or a transient pill — no inline retry, no "Ollama isn't running, [Start it]" actionable recovery.

**Switch-to-record has hidden side effects.** `MenuBarView.swift:160-177` and the toolbar Join & Record silently auto-stop the current recording before starting a new one. The `.help()` tooltip mentions it, but there's no confirmation and no undo if you fat-finger it mid-meeting.

## Existing-plan items I rank highest

1. **DEF-2 — `List(selection:)` for Meetings.** Through my lens this is the single most-felt keyboard gap. The app's primary list is mouse-only while its secondary lists aren't. Cheap (S), high daily payoff. **Endorse, raise priority.**
2. **LAY-2 — chat rail closed by default + keyboard toggle.** Already default-closed (`MainWindow.swift:65`) and there's a toolbar toggle (`:271`), but **no keyboard shortcut** — add ⌘⌥→ / a binding. Power users shouldn't reach for the mouse to reclaim 340pt.
3. **DEF-3 — promote "Draft follow-up."** Burying the highest-intent post-meeting action below a long summary is an interaction-cost bug, not just layout.
4. **NAV-3 — one canonical meeting surface.** The `dismiss + asyncAfter(0.18)` routing hack (`MainWindow.swift:463-468`) is a feedback/jank smell; collapsing to one surface removes a class of transition bugs.
5. **TDY-1 — "Up next" hero.** The glanceable countdown is the daily-driver interaction; today `nextMeeting` exists in code but no live countdown.

## NET-NEW recommendations

**D4-1 — Unify recording on a single global toggle + persistent recording HUD. (M, High, no dep)**
Make ⌘⇧R (or a user-set *global* hotkey, reusing `GlobalHotkey`) one toggle: idle→start, recording→stop. Promote the floating-overlay pattern (`FloatingOverlay.swift`) to *meeting* recording: pulsing dot + live `AudioLevelMeter` + elapsed timer + Stop, persisting even when the main window is backgrounded. *Why:* meeting recording is the flagship flow yet has the weakest feedback; users currently can't confirm audio is captured without opening the detail. *Value:* trust + one-keystroke capture from anywhere.

**D4-2 — Turn ⌘K into a real command palette (actions, not just search). (M, High, dep: none — extends GlobalSearchView)**
Add a command layer above the entity results: "Start recording", "Stop & transcribe", "Draft follow-up", "New task / person / voice note", "Toggle assistant", "Open notes folder", "Refresh", "Re-summarize this meeting". Type-ahead ranks commands + entities together (Raycast/Linear model). *Why:* every action is currently mouse- or menu-bound; the palette already has the arrow-nav scaffolding (`:67-69`). *Value:* discoverability *and* speed in one surface; the ⌘K chip finally tells the truth.

**D4-3 — Universal undo for lossy actions via a toast + UndoManager. (M, High, no dep)**
Wire `UndoManager` (or a lightweight snapshot stack) for: check/uncheck action item, delete person, **retag meeting (which moves folders on disk)**, clear/overwrite transcript, regenerate summary. Show a 5s "Undone? [Undo]" toast. *Why:* zero undo exists today and several actions mutate the filesystem irreversibly. *Value:* makes power users fearless; directly de-risks the vault-move behavior the eng plan worries about.

**D4-4 — Live finalize feedback with stage + per-meeting progress. (S–M, Med, no dep)**
Replace "N finalizing" (`MainWindow.swift:594-600`) with a per-meeting chip showing stage ("Transcribing 3/5 chunks" → "Summarizing") and a determinate bar where whisper chunk counts are known. Add an inline "still working — usually ~Ns" hint like the voice-note pill already has. *Why:* the app's two slowest ops are nearly silent; users can't distinguish progress from hang. *Value:* removes the #1 "did it freeze?" anxiety.

**D4-5 — Drag-to-import audio + drag-person-to-meeting. (S, Med, no dep)**
Add `.dropDestination` on the main window for `.audio` files → route to `importMeeting` (skip the `NSOpenPanel`), and let a person chip drag onto a meeting's attendee row. *Why:* import is a 3-click toolbar+panel flow; drag is the macOS-native expectation. *Value:* faster ingest; teaches the relationship graph by direct manipulation.

**D4-6 — Type-to-select + Enter-to-open across all lists; Esc-to-deselect. (S, High, dep: D4-? none / pairs with DEF-2)**
Once Meetings is `List(selection:)`, add type-ahead jump (start typing a title to select), Enter opens detail, Esc clears selection / closes detail. Apply the same in People/Notes/Tasks for consistency. *Why:* macOS list muscle memory; today even `List`-based panes lack type-ahead-to-open. *Value:* keyboard-only navigation of the whole corpus.

**D4-7 — Discoverable keyboard map ("?" cheat sheet) + visible hotkey hints. (S, Med, no dep)**
Add a `?` overlay (Slack/Linear-style) listing every shortcut, and surface the F5 dictation hotkey somewhere the user will see it (a one-line hint on Today or in the menu bar), since today it's only discoverable in Settings (`SettingsView.swift:77-93`). *Why:* a keymap nobody can find is no keymap. *Value:* converts mouse users into keyboard users; advertises the dictation superpower.

**D4-8 — Quick-switcher for meetings/people (⌘P / ⌥Tab-style recents). (S, Med, dep: extends GlobalSearchView)**
A lightweight "jump to recent meeting/person" that defaults to MRU and closes on selection — distinct from full ⌘K. The recents data already exists (`GlobalSearchView.recentPeopleSuggestions`, `pastMeetings.prefix(8)`). *Why:* power users bounce between a handful of recent entities; full search is overkill. *Value:* near-instant context switching.

**D4-9 — Inline edit everywhere with a single learnable pattern. (M, Med, dep: pairs with PPL-1)**
Adopt one "click text → field appears → blur/Enter saves, Esc cancels" component (the meeting-title pattern at `MeetingSummaryTab.swift:227`) and apply it to person identity fields, task titles, and tags. *Why:* editing affordances are currently a grab-bag (modal here, inline there, debounce elsewhere). *Value:* one mental model; fewer modals.

**D4-10 — Actionable error recovery (no more bare beeps). (S, Med, no dep)**
Replace `NSSound.beep()` / silent failures with inline recovery: "Ollama isn't running — [Start it]" (you already have `ensureOllamaRunning`), "Transcription failed — [Retry]", "Paste target lost — [Copy instead]". *Why:* dictation-swap and polish failures currently beep into the void (`QuickDictation.swift:99`). *Value:* turns dead-ends into one-click fixes.

**D4-11 — Batch actions on multi-select. (M, Med, dep: D4-6 selection)**
With `List(selection:)` supporting multi-select: tag N meetings at once, mark N tasks done, delete N voice notes, "add all attendees to People." *Why:* every list action is currently one-at-a-time. *Value:* the power-user 10x for vault grooming.

**D4-12 — Recording confirmation/guard on destructive switches. (S, Low, no dep)**
When "Join & Record" / Switch would auto-stop an in-progress recording (`MenuBarView.swift:160-177`), show a quick confirm or at least a undoable toast ("Stopped 'X', now recording 'Y' — [Undo]"). *Why:* silent auto-stop of a live recording is a data-loss-adjacent surprise. *Value:* prevents accidental loss of an important call.

## Top 3 picks

- **D4-1 — Single global record toggle + persistent recording HUD.** The flagship flow has the weakest feedback in the app; one keystroke + a trustworthy HUD is the highest-leverage interaction fix.
- **D4-2 — Real ⌘K command palette.** The scaffolding is already there; promoting it from search to commands unlocks keyboard-first operation of the entire app and makes the existing ⌘K chip honest.
- **D4-3 — Universal undo.** A file-moving, summary-overwriting local app with zero undo is the biggest trust gap; a toast + UndoManager makes power users fearless.

**Single highest-priority recommendation overall: D4-2 (real ⌘K command palette).** It's the multiplier — it makes every other action keyboard-reachable and discoverable, builds directly on shipped scaffolding, and is the lowest-risk path to "power users can move fast."
