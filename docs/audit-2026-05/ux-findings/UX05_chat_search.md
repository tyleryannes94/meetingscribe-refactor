# Chat Rail + Global Search + Command/Quick-Switch — Low-Lift UX & Feature Wins

Senior PM lens on *recall speed*: how fast a user finds a meeting/person/task in search and acts on it, and how discoverable/useful the Chat rail is. Surfaces audited live: `GlobalSearchView.swift`, `ChatPanel.swift`, `ChatSidebar.swift`, `MainWindow.swift` (rail toggle + `routeEntity`), `MeetingScribeApp.swift` (⌘K / ⌘1–5 commands).

## Lift from V4 (relevant, already planned — don't re-propose)

- **D4-2** — Turn ⌘K into a *real* command palette (it's search-only today despite the ⌘K chip). Directly on my surface; my FT5 items extend it rather than duplicate it.
- **D1-2** — Register `meetingscribe://` + `onOpenURL`. Enables deep-linking search/chat results from Spotlight/Shortcuts.
- **C2-1** — Wire the shipped FTS5 engine; global search currently falls back to in-memory `contains()` (`WorkspaceIndex.swift:106`). My UX items assume results stay relevance-ranked once this lands.
- **C1-1 / C2-2** — "Ask your vault" RAG. My chat-discoverability items are the cheap on-ramp to it.

---

## UX improvements (5)

### UX5-1 — Inline result actions in search (result → action in 1 click, not 2+)
**Friction today:** every search row is a single `Button { open(e) }` (`GlobalSearchView.swift:147-170`). The *only* thing a result can do is navigate. To act on a found task (mark done), found person (add tag), or found meeting (open notes), the user must open it, then hunt the action inside the detail — 2–4 clicks, and it breaks the 2-click rule. The row already renders a trailing kind badge (`:160`) — there's free horizontal space.
**Fix:** add 1–2 hover/right-side quick-action buttons per kind: task → ✓ complete; person → tag/open; meeting → open notes / open transcript; voiceNote → play. Reuse existing store mutators (`actionItems.setStatus`, `PeopleTagStore`).
**Clicks:** find→act 2–4 → **1**. **Effort:** small-M.

### UX5-2 — Show the "↵ to open" / nav affordance + Enter-to-act on results
**Friction today:** arrow-key nav and `onSubmit(openSelected)` exist (`:67-68, :105, :277`) but nothing on screen tells the user Enter opens the highlighted row, and only "esc" is hinted (`:112`). Keyboard users don't discover the fastest path.
**Fix:** add a tiny "↑↓ navigate · ↵ open" footer hint (mirror the existing `esc` chip styling), and show "↵" on the selected row.
**Clicks:** discoverability only — converts mouse users to 0-click keyboard flow. **Effort:** S.

### UX5-3 — Recent searches + recent results as empty-state suggestions
**Friction today:** empty query only seeds recent *meetings* (`.all`/`.meetings`) or recent *people*; `.tasks/.notes/.voiceNotes` show literally nothing (`recompute()` `:186-189` → `default: results = []` + the empty placeholder `:121-128`). A user opening ⌘K on the Tasks scope sees a dead screen until they type.
**Fix:** (a) persist the last ~6 queries (`@AppStorage`) and show them as tappable chips; (b) for every empty scope, seed the most-recent entities of that kind (recent tasks, recent voice notes), mirroring the meetings path. Re-running a search becomes a tap.
**Clicks:** re-find 3+ → **1**. **Effort:** S.

### UX5-4 — Context-aware chat starter prompts (kill the generic sidebar list)
**Friction today:** the sidebar's example prompts are a hardcoded array of 4 generic strings (`ChatSidebar.swift:21-27`) that never change, while `ChatPanel` already supports per-host `examplePrompts` (`ChatPanel.swift:19`) and the session already gets a per-section context string (`MainWindow.swift:265-268`, `setContext`). The per-meeting and per-person chats pass *no* prompts, so their empty state is bare.
**Fix:** generate 3 starters from the active section/entity — People → "Draft a follow-up to {name}", "When did I last talk to {name}?"; Meeting → "Summarize this call", "What did I commit to?"; Tasks → "What's overdue?". Pure string templating off context already in hand.
**Clicks:** typing a question → **1 tap**, and teaches capability. **Effort:** S.

### UX5-5 — Surface what Chat can *do* (write actions) in the empty state
**Friction today:** the empty state says only "Ask anything" + a privacy note (`ChatPanel.swift:63-99`). But the chat can *create tasks, set status/priority/due dates, push to Notion & Linear, attach notes to people, edit files* (`ActionItemChatTools`, `IntegrationChatTools`, `FileChatTools`, `PeopleChatTools`). None of this is discoverable, so users treat chat as a read-only Q&A box and the most valuable surface goes unused.
**Fix:** add a one-line "Chat can also: create tasks · push to Linear/Notion · edit your files" capability strip (or fold into the starter chips above). Zero new logic — just advertising existing tools.
**Clicks:** discoverability. **Effort:** S.

---

## Feature improvements (5)

### FT5-1 — "Ask Chat about this" on every search result
**What/why:** results can navigate but can't pivot to reasoning. Add a small "Ask Chat" action on each row that pre-fills the chat with a scoped prompt (e.g. result is meeting "Acme sync" → "Tell me about the Acme sync meeting") via the existing `.meetingScribeRunChat` passthrough (`MainWindow.swift:448-455`, `ChatSidebar.swift:44`). The `chatQuery` plumbing already exists for long queries — this just exposes it per-result.
**Value:** bridges search ↔ chat; turns "found it" into "reason about it" in 1 click. **Effort:** S. **Dep:** none (passthrough already wired).

### FT5-2 — Promote ⌘K to a command palette (actions, not just entities)
**What/why:** ⌘K is wired globally (`MeetingScribeApp.swift:69-72`) but only opens entity search. Add a top band of *commands* (Start recording, New voice note, New person, New task, Open settings, Toggle assistant) that match the typed query — every one already has a command/notification (`MeetingScribeApp.swift:87-111`). Filter them in alongside entities when the query matches a verb.
**Value:** every primary action becomes keyboard-reachable from one surface; the ⌘K chip stops over-promising. **Effort:** small-M. **Dep:** overlaps V4 D4-2 — ship as the low-lift first slice.

### FT5-3 — `chatQuery` passthrough at lower threshold + always-available "Ask Chat"
**What/why:** the "Ask Chat: …" escape hatch only appears when the query is ≥3 words (`GlobalSearchView.swift:242`, `peopleSearch`), and isn't added at all in the main `filteredResults` path for `.all`. So a 2-word natural question ("pricing objections") never offers chat. Lower to ≥2 words / when result count is low, and always append one "Ask Chat: {query}" row when there are no strong matches.
**Value:** no query ever dead-ends; search degrades gracefully into chat. **Effort:** S. **Dep:** none.

### FT5-4 — Pinned / favorite entities as a quick-switch row
**What/why:** there's no fast path back to the meeting/person/project a user lives in daily — they re-search every time. Add a "Pinned" row at the top of the empty ⌘K state, backed by a tiny `@AppStorage` id list, with a pin affordance on result rows (reuses UX5-1's action slot).
**Value:** turns ⌘K into a true quick-switcher for the 3–5 entities a user touches constantly; recall in 1 tap. **Effort:** small-M. **Dep:** UX5-1 action slot.

### FT5-5 — Scope chat to the result you came from ("Chatting about X" chip)
**What/why:** `ChatPanel` already accepts a `contextPrefix` (`:14-16`) used by the per-meeting tab, but the sidebar chat has no way to bind to a specific entity on demand. When a user picks "Ask Chat about this" (FT5-1) on a person/meeting, set a removable context chip in the input bar so follow-ups stay scoped without re-naming the entity each turn.
**Value:** multi-turn recall about one entity without repetition; makes the local model far more useful with cheap UI. **Effort:** small-M. **Dep:** FT5-1; `contextPrefix` plumbing already exists.

---

## Top 3 picks (highest conviction, lowest lift)

1. **UX5-1 — Inline result actions** (small-M): the single biggest 3-click/2-click win on this surface; search becomes a *do* surface, not just a *go* surface. All mutators already exist.
2. **UX5-5 + UX5-4 — Discoverable, context-aware chat (S each):** the most valuable surface in the app is currently advertised as a generic Q&A box; a few templated strings unlock the existing write-tools and the future RAG moat at near-zero cost.
3. **FT5-2 — Command-palette slice of ⌘K (small-M):** every primary action already has a command; matching them into the existing search field makes the ⌘K chip honest and the whole app keyboard-driveable.

**Single highest-value low-lift win:** **UX5-1** — adding 1-click actions to search rows. It directly satisfies the result→action-in-≤2-clicks principle, reuses existing store methods (zero new backend), and converts the most-used recall surface into an action surface.
