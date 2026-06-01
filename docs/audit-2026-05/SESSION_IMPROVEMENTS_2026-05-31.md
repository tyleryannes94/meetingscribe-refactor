# MeetingScribe — Session Improvements (2026-05-31)

> Companion to `MASTER_PLAN_V4.md`. Records the People-tab overhaul and the
> V4 Phase 4 + Phase 5 work shipped in this session, then lays out recommended
> next steps **focused on app layout and usability** rather than new features or
> integrations.

All work below was build-gated (`swift build -c release`), test-gated
(`swift test` — 52 passed / 1 skipped throughout), merged to `main` via
self-reviewed PRs, and installed to `/Applications/MeetingScribe.app`.

| PR | Branch | Theme | Merge |
|----|--------|-------|-------|
| #22 | `people-editing` | Tag management, recency, prefill, auto-focus | `33a29cb` |
| #23 | `people-power` | Multi-select bulk actions, sort, AND-filter, Tasks tab, Ask AI | `c3622f5` |
| #24 | `people-redesign` | Single-page profile, embedded chat, AI suggestions, deep message analysis, task links, insights | `f933854` |
| #25 | `phase4-5` | Calendar write-back, Obsidian companion, power governor, perf, hardware-aware AI | `38d314d` |

---

## 1. People tab — what changed

The People tab was the focus of three PRs (#22–#24). It went from a tabbed
master/detail with a thin profile to a single-page relationship workspace.

### 1.1 List & organization (PRs #22, #23)

| ID | Improvement | Where |
|----|-------------|-------|
| FT3-1 | **Tag management UI** — rename/delete people-tags from a slider button on the chip row (the store methods existed but had no UI, so a typo'd tag was permanent). | `People/TagManagementSheet.swift` (new) |
| UX3-2 | **Last-interaction recency** in each row ("2w ago") so you can see who's gone cold without opening anyone. | `People/PeopleListView.swift` (`PersonRow`) |
| UX3-3 | **Prefill the active tag** when adding a person while a tag filter is on, so they stay in view. | `People/AddPersonSheet.swift` |
| UX10-4 | **Auto-focus the Name field** on a new person so you can type immediately. | `People/AddPersonSheet.swift` |
| FT3-2/FT3-3 | **Multi-select + bulk actions** — a "Select" toggle flips the list to a multi-select binding; a bottom bar **tags / merges / deletes** the checked people. Merge collapses the selection into its highest-signal record. | `People/PeopleListView.swift` |
| UX (sort) | **Persisted sort** — Recent activity / Name (A–Z) / Most meetings / Recently added; suppressed while searching to preserve relevance order. | `People/PeopleListView.swift` (`PeopleSort`) |
| UX3-5 | **AND tag-filter** — selecting two chips shows only people carrying both tags. | `People/PeopleListView.swift` |

### 1.2 The profile redesign (PR #24)

- **Single scrollable page, no tabs.** The Notes/Meetings/Tasks/Messages tab bar
  was removed; identity, tags, contact, favorites, AI suggestions, relationships,
  encounters, meetings, tasks, memories, notes, and messages are all visible in
  one column. (`People/PersonDetailView.swift`)
- **Embedded AI chat** as a persistent right column (`ChatPanel` on the shared
  `ChatSession`) replacing the toggled sidebar rail. "Ask AI" posts a person
  briefing straight into it.
- **Inline editing in the main view** — an **Add tag** menu (pick existing or
  create new; chips are removable) and inline **Favorites** add/remove, alongside
  the existing inline identity edit. The full edit sheet stays behind the `⋯`.

### 1.3 AI in the profile (PR #24)

- **AI suggestions card** (`People/PersonAISuggestions.swift` — new) — builds a
  context blob from the person's profile, encounters, meetings, and co-attendees,
  asks Ollama for strict JSON, and parses it tolerantly (the `PersonExtractor`
  pattern). One-tap accept adds a **tag**, links a **relationship** to a matched
  person, or logs an **encounter**. All on-device via the existing egress gate.
- **Deep message analysis** — one thorough pass over the *entire* matched text
  history, cached once as a `deep-all` AttachedNote ("Run" → "Refresh"). The same
  pass mines tags/encounters from real message content into the suggestions card.

### 1.4 People insights dashboard (PR #24)

The empty detail pane is now a relationship dashboard instead of a
"Select a person" placeholder (`People/PeopleInsightsView.swift` — new):
**Reconnect** (gone-cold contacts, 45-day cutoff), **Upcoming birthdays**
(next 30 days, next-occurrence aware), **Most active** (by encounters + meeting
mentions). Each row opens that person.

---

## 2. Cross-tab integration

| ID | Improvement | Where |
|----|-------------|-------|
| — | **Real Person↔task link** — `ActionItem.ownerPersonID` (safe Codable migration; old JSON still decodes). The person Tasks section matches the hard link first (owner-string match stays as a legacy fallback); quick-add links exactly; the task page assignee gains a person-link menu + an open-person button. Navigation works both directions. | `ActionItems/ActionItem.swift`, `ActionItems/ActionItemStore.swift`, `People/PersonDetailView.swift`, `UI/TaskPageView.swift` |

---

## 3. Phase 4 — platform & workflow reach (PR #25)

The locally-buildable, no-external-credential slice of V4 Phase 4.

- **P4-1 Calendar write-back** (`Calendar/CalendarStoreActor.swift`,
  `UI/MeetingDetailHeader.swift`) — **Add recap to event** writes the meeting
  summary + a deep link into the source event's notes (idempotent,
  marker-delimited); **Schedule follow-up** (tomorrow / 3 days / next week)
  creates a new event. In the meeting **Options → Calendar…** menu. Uses the
  full-access calendar permission already granted at onboarding.
- **C3-x Obsidian companion** — **Open in Obsidian** deep-links the canonical
  `<slug>.md` via `obsidian://open`; **EXPORT.md** portability manifest is
  written at the vault root on first canonical-markdown write — the local-first
  "leave anytime" guarantee. (`Export/VaultManifest.swift` — new,
  `Export/ObsidianExporter.swift`, `MeetingManager.swift`)

---

## 4. Phase 5 — AI stack & performance (PR #25)

The self-contained, dependency-free slice of V4 Phase 5.

- **E2-2/E2-3/E2-7 ResourceGovernor** (`AI/ResourceGovernor.swift` — new) — the
  app was power-blind. The governor reads battery (`IOKit.ps`), low-power mode,
  and `thermalState`, and **defers live transcription to a single batch pass on
  stop** when on battery / low-power / thermally critical, eliminating the
  per-chunk Whisper cold-loads. `needsBatchRepair(liveIsEmpty:)` already covers
  the deferred case, so the transcript is never dropped. Two Settings toggles +
  a live status line.
- **E2-5 ThumbnailCache** (`UI/ThumbnailCache.swift` — new) — ImageIO-downsampled,
  `NSCache`-backed people-photo thumbnails replace full-res
  `NSImage(contentsOf:)` decode-per-render.
- **C5-3 HardwareProfile** (`AI/HardwareProfile.swift` — new) — RAM/core-aware
  recommended summarization model with a "Use recommended" button + a "this Mac"
  hint in the Ollama settings.

---

## 5. Explicitly deferred (need external deps / accounts)

Flagged, not built — real work that can't be built-and-verified headlessly:

- **Phase 4:** real Slack delivery (bot token), HubSpot/Attio CRM bridge,
  MCP-registry publish, Raycast/Alfred extension, the local automation
  rules-engine, and the first-class Client/Workspace entity (large).
- **Phase 5:** WhisperKit / Apple SpeechAnalyzer STT swap, FluidAudio
  diarization, MLX summarization backend — each needs a new SPM dependency +
  model downloads best validated interactively on a Mac.

---

## 6. Recommended next steps — layout & usability

> The product now has a strong *feature* surface; the biggest remaining wins are
> in **consistency, hierarchy, and editing ergonomics**, not new capabilities.
> The People redesign set a high bar (single page, inline edit, embedded chat,
> live empty states) — most of the app hasn't caught up to it yet. These phases
> are about closing that gap.

### Phase U1 — Design-system enforcement (foundational)

The People redesign hand-rolled its section cards, chips, and list rows; Meetings,
Tasks, Chat, and Settings each have their own. This drift is the root cause of
most inconsistency.

- **Extract shared primitives** — `MSCard`, `MSListRow`, `MSSurface`,
  `MSSectionHeader`, `MSEmptyState` — and migrate every tab onto them (maps to
  plan items **D2-1 / D2-6**). One definition of a card means one fix when a card
  is wrong.
- **Spacing/radius scale + CI lint.** Codify the `NDS` spacing/radius tokens and
  fail the build on magic numbers, so opted-out surfaces can't drift again.
- **Promote `NDS.splitPaneTopInset` everywhere.** The toolbar-clearance bug recurred
  per-pane this session; make the inset a layout primitive every top-level pane uses,
  not a value each view remembers to add.

### Phase U2 — Bring the People patterns to the rest of the app

The People profile is now the reference layout. Apply its three wins outward:

- **Single-page detail over tabs.** The Meeting detail still mixes a header,
  inline sections, and modal sheets. Audit whether its content can collapse into
  one scroll with progressive disclosure, the way the person profile did.
- **One contextual-chat pattern.** There are now *three* chat surfaces: the People
  embedded column, the per-meeting Chat tab, and the global toggled rail. Unify
  them into a single "chat about what I'm looking at" component with a consistent
  position and grounding contract.
- **Inline editing over modal sheets.** People can now edit tags/favorites/identity
  in place; Meetings (title/description), Tasks (properties), and the full person
  edit still open sheets. Prefer in-place editing with autosave; reserve sheets
  for genuine multi-field creation.

### Phase U3 — Information hierarchy & wayfinding

- **Tame the long person page.** Now that everything is one scroll, very rich
  people produce a very long page. Add a lightweight **section jump-rail / anchors**
  or **collapsible sections**, and collapse low-signal blocks (transcript,
  provenance, full message history) by default — progressive disclosure.
- **Consistent selection & back affordances.** People list is single-select →
  detail, with a separate multi-select mode; Meetings/Tasks use different models.
  Pick one selection metaphor and one "back / breadcrumb" treatment across tabs.
- **Make global search the primary nav.** A reliable `⌘K` palette that jumps to
  any person/meeting/task/note reduces tab-hopping and makes the whole app feel
  smaller. (The FTS index already exists.)
- **Empty states everywhere.** The People insights dashboard proved the value of a
  useful empty pane. Give Meetings, Tasks, and Today the same treatment instead of
  blank space or a bare placeholder.

### Phase U4 — Editing ergonomics & trust

- **Autosave-on-blur + consistent focus management** across every create/edit
  surface (maps to **UX10-2 / UX10-3**). Auto-focus the first field; commit on
  blur; never lose a half-typed field to a navigation.
- **Undo for destructive actions.** Bulk **merge** and **delete** are currently
  irreversible. Add an undo window (or a soft-delete/trash) — merge especially,
  since it auto-picks the keeper.
- **Better in-context AI states.** AI suggestions and deep analysis currently fail
  to a terse "make sure Ollama is running" string. Add a real loading/skeleton
  state, a cancel affordance, and a one-click "start Ollama" / setup hint.
- **Replace heavy feedback with light feedback.** Calendar write-back uses a modal
  `NSAlert`; prefer an inline, auto-dismissing toast so confirmations don't block.

### Phase U5 — Responsiveness & accessibility

- **Narrow-window behavior.** The People `HSplitView` (sections + embedded chat)
  needs a graceful collapse: below a width threshold the chat should become a
  toggle, not squeeze the content. Audit every split pane for small screens.
- **Dynamic Type & VoiceOver.** Many sizes are hard-coded points; adopt scalable
  text and verify VoiceOver labels on the new chips, suggestion rows, and the
  insights dashboard.
- **Reduce-motion / contrast passes** on the new surfaces.

### Smaller, specific usability debt found this session

- **Bulk merge keeper is auto-chosen** (highest-signal). Offer an explicit keeper
  pick for ambiguous merges (the per-pair duplicate sheet already does this).
- **Assignee → person picker caps at 50 recent contacts** with no search. Make it
  a searchable picker (mirror `AddRelationshipSheet`).
- **The embedded chat shares one global `ChatSession`.** Viewing a person while the
  global rail is open mirrors state. Consider per-context sessions, or make the
  shared session's grounding switch unambiguously with the visible context.
- **Task↔person matching falls back to owner *string*.** Two people who share a
  first name can both surface a loosely-owned task until it's hard-linked. A small
  "link these owners to people" cleanup pass would tighten it.

### Sequencing

`U1` (design system) is the enabler — do it first so `U2`–`U5` apply consistent
primitives rather than multiplying bespoke ones. `U2` and `U3` deliver the most
visible "the app feels coherent now" payoff. `U4` and `U5` are continuous polish
that should ride along with every subsequent change rather than being a single
phase.
