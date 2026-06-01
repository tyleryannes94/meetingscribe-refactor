# G2 — Secondary Surfaces (Notes / Chat / Search / Settings)
Lens: the four "everywhere" surfaces — voice Notes, the Chat rail, ⌘K global search, and Settings/Integrations — should feel instant, reach every entity, and never block launch or crowd the primary tabs.

## Audit (through my lens)

### Voice Notes (`QuickNotesView.swift`)
- Solid two-pane layout (Polished | Raw) with debounced disk saves and auto-polish (`QuickNotesView.swift:346-381, 513-540`). Scoped `QuickNotesController` observation already avoids over-invalidation (`:8-13`).
- **Gaps:** a voice note is a dead-end entity. It can be exported to MD/Drive (`:270-303`) but cannot be linked to a Person, a Meeting, or a Task, and has no tags. Compare to Meetings/People which are richly cross-linked. It's also not addressable from People/Tasks.
- `manager.refreshQuickNotes()` runs on every `.onAppear` of the sidebar (`:70`) and again on the open-voice-note notification (`:24-27`) — a full reload each time the tab is shown.
- No search *within* a note's transcript; long dictations are unscrollable-to-a-phrase.

### Chat rail (`ChatPanel.swift`, `ChatSidebar.swift`)
- One app-wide `ChatSession` (`MeetingScribeApp.swift:15`), context label updated per tab (`MainWindow.swift:272-282`) — good. Reusable `ChatPanel` with density modes is clean.
- **Session is in-memory only** — `ChatSession` has no load/persist (`ChatSession.swift:17,31`); `reset()` is the only lifecycle. **Every relaunch wipes the conversation**, and there is no history/thread list — `plus.message` just clears (`ChatSidebar.swift:77-85`). Users lose all prior Q&A.
- Rail auto-hides under 860px width and defaults closed (`MainWindow.swift:248,63`) — reasonable, but on a 13" laptop in a 3-pane layout the rail is effectively unreachable without resizing.
- Example prompts are static strings (`ChatSidebar.swift:22-27`) — they don't reflect the user's actual data (no "Summarize *this* meeting" when a meeting is open in the center).
- Messages keyed by `.offset` (`ChatPanel.swift:35`) — fine now, but blocks stable diffing/streaming-edit later.

### Global Search (`GlobalSearchView.swift`)
- Genuinely good: FTS5 BM25+recency for meetings/notes/people, hybrid semantic refine guarded against stale queries (`:235-247`), command palette, filter tabs, keyboard nav. This is the strongest secondary surface.
- **`recompute()` runs synchronously on `query`/`filter` change on the main actor** (`:65-66, 205-247`). FTS is fast, but `manager.search(q)` (the in-memory WorkspaceIndex path for tasks/projects/notes, `WorkspaceIndex.swift:106`) and `PeopleStore.searchVault` run inline on every keystroke — no debounce. On a large vault this stutters the field.
- The People filter is a *workaround* for a WorkspaceIndex bug (`:21-25, 223-228`) — two code paths, divergent ranking. Tech debt that risks "found in People tab, missing in All".
- Empty-query state shows recent meetings/people only; **no recent searches, no "jump to a Tab/Setting"** — settings are completely unreachable from ⌘K.

### Settings / Integrations
- **Two overlapping surfaces.** `SettingsView.swift` is a 900-line monolithic `Form` (single scroll, ~17 sections) presented in a fixed 560×580 window (`MeetingScribeApp.swift:137-142`) — so most content is off-screen and there are **no section tabs or search**. Finding "GPU acceleration" or "Linear key" is a long scroll-hunt.
- `IntegrationsView.swift` is a *better* design (expandable connector cards with inline test + status pills) but is **orphaned — `IntegrationsView()` is referenced nowhere** (`grep` returns zero call sites). The nav comment says Integrations "moved to Settings," but the nicer card UI was left stranded; Linear/Notion/Google config is now duplicated, less clearly, inside the monolith (`SettingsView.swift:315-420`).
- Settings is a separate macOS `Settings` scene (⌘,) — not reachable from ⌘K or the nav rail except the gear (`MainWindow.swift:159-161`). 2-3 clicks + scroll to reach any given setting.
- `MetricsStore.shared.snapshot()` and `OllamaService.isReachable()` run when the relevant sections render (`:491, 887`) — fine since lazy, but the whole Form mounts all `@State` (~40 reads of `AppSettings.shared`) on open.

## NET-NEW recommendations

**TS-1 — Persist & thread the Chat session.**
What/why: Add JSON-backed persistence to `ChatSession` (last N threads under storageDir) + a lightweight thread switcher in the rail header; `plus.message` archives instead of destroying. Load lazily *after* first paint.
UX: conversation survives relaunch; revisit prior answers. Reset before→after: irreversible wipe → archived thread (recoverable).
Perf/stability: load is async off the launch path (no blocking — session already inits empty at `App:15`); cap persisted messages to bound memory; write debounced.
Effort: M · Impact: High · Deps: none.

**TS-2 — Surface Settings + recent searches in ⌘K.**
What/why: Index every Settings section + Integration as searchable palette entries ("Linear key", "GPU", "Storage folder") that deep-link into the right section; add a recent-searches MRU at empty query.
UX: any setting reachable in ≤2 clicks (⌘K → type → Enter) vs today 3 + scroll-hunt. Makes the 900-line Form navigable without restructuring it first.
Perf/stability: static command list (like `allCommands`, `GlobalSearchView.swift:370`) — zero query cost; MRU is a tiny UserDefaults array.
Effort: S · Impact: High · Deps: TS-6 (deep-link target ids) helps but not required.

**TS-3 — Debounce + unify the search recompute.**
What/why: Wrap `recompute()` in a ~120ms debounce and move the in-memory `manager.search` merge off the keystroke critical path; collapse the People dual-path by fixing the WorkspaceIndex match so `.all` and `.people` share one ranker.
UX: field stays buttery while typing; eliminates "in People but not All" inconsistency.
Perf/stability: fewer FTS/embedding calls per query; single code path = fewer crash/empty-result edge cases. Cache the empty-query suggestion list (recent meetings/people) so reopening ⌘K is instant.
Effort: M · Impact: High · Deps: none.

**TS-4 — Adopt the orphaned card UI as Settings → Integrations, and split Settings into sections.**
What/why: Wire `IntegrationsView` back in as one section of a sidebar-tabbed `SettingsView` (TabView/`NavigationSplitView`: You · Capture · Transcription · AI · Integrations · Advanced), retire the duplicated Linear/Notion/Google blocks in the monolith.
UX: section nav makes every setting findable in ≤2 clicks; removes duplicate, conflicting config surfaces; reuses already-built, nicer card components.
Perf/stability: lazy section bodies mean only the visible section reads `AppSettings`/runs status probes (`OllamaStatusRow`, MCP refresh) — lighter open than mounting the full Form.
Effort: M · Impact: High · Deps: none (code already exists).

**TS-5 — Make voice notes a first-class, linkable entity.**
What/why: Add Person / Meeting / Task links + tags to `QuickNote` (mirror Meeting's link affordances), shown in the note header; index the transcript into FTS (already partly there via `voice_note`) so notes appear in cross-entity backlinks.
UX: a note recorded after a 1:1 attaches to that person in ≤2 clicks; the person/meeting then shows the note. Closes the "notes are an island" gap.
Perf/stability: links are tiny metadata appended to the existing per-note save (debounced, `:513-540`); FTS indexing is incremental, not a rescan.
Effort: M · Impact: Med · Deps: shared link picker (likely exists for Tasks/People).

**TS-6 — Context-aware chat prompts + "Ask about this" everywhere.**
What/why: Replace the static example prompts (`ChatSidebar.swift:22-27`) with ones derived from the current center entity (open meeting/person/note → "Summarize this call", "Draft a follow-up to {name}"); add an "Ask Chat about this" action on meeting/person/note headers that opens the rail pre-seeded (reusing `router.openChat`, `MainWindow.swift:275`).
UX: chat becomes contextual instead of a blank box; 1 click from any entity to a relevant question.
Perf/stability: prompt strings computed from already-loaded selection — no extra fetch; reuses existing `.meetingScribeRunChat` passthrough.
Effort: S · Impact: Med · Deps: TS-1 (nice with persistence) but independent.

**TS-7 — In-note find + jump.**
What/why: Add a ⌘F find bar scoped to the active QuickNote's transcript panes (highlight + next/prev).
UX: locate a phrase in a 30-min dictation instantly instead of manual scroll.
Perf/stability: pure in-view string search on already-loaded text; no storage/index cost.
Effort: S · Impact: Low · Deps: none.

**TS-8 — Lazy-load Settings probes; never block on Ollama/Drive at open.**
What/why: Ensure `OllamaStatusRow.checkStatus`, `MCPInstaller.refreshStatus`, and Drive status only fire when their section is visible (post-TS-4 split makes this natural), with skeleton/"checking…" states instead of synchronous probes.
UX: Settings opens instantly even when Ollama is down or network is slow.
Perf/stability: removes a network reachability call from the open path; bounded, cancelable tasks reduce hang/crash risk.
Effort: S · Impact: Med · Deps: TS-4.

## Top 3 picks
1. **TS-4 — Sectioned Settings + revive the orphaned IntegrationsView** → **Phase 1** (foundational: kills duplicate config surfaces, makes everything findable, lazy bodies = faster open; the component already exists so it's near-free leverage).
2. **TS-2 — Settings/recent-searches in ⌘K** → **Phase 2** (turns the existing palette into the universal entry point; ≤2-click reach to any setting; static list = zero perf cost).
3. **TS-1 — Persist & thread the Chat session** → **Phase 3** (biggest felt-quality win for chat; async load keeps launch fast; unlocks TS-6's contextual prompts).
