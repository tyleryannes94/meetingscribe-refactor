# MeetingScribe — Improvements Shipped 2026-05-31

> Companion to `MASTER_PLAN_V4.md`. A complete record of everything merged to
> `main` on 2026-05-31 — V4 Phases 0–5, the quick-wins sweep, and the full
> People-tab overhaul — followed by recommendations for future work **focused on
> app layout and usability** rather than new features or integrations.

Every change was build-gated (`swift build -c release`) and test-gated
(`swift test` — 52 tests, 1 expected skip), merged via self-reviewed PRs, and
the app reinstalled to `/Applications/MeetingScribe.app`.

## Merges today (PRs #13–#26)

| PR | Merge | Theme |
|----|-------|-------|
| #13 | `9be4de0` | **Phase 0** — critical correctness, data integrity & trust |
| #14 | `5591c23` | **Phase 1** — finish shipped requirements, navigation & first-run |
| #16 | `2b9b721` | **D5-2** — Dynamic Type foundation (scalable type) |
| #17 | `b4b6f2c` | **Phase 2.1** — recall moat: hybrid search, person timeline, truthful recency, briefs |
| #18 | `ceb8515` | **Phase 2.2** — cited RAG chat, related-meeting links, On this day |
| #19 | `035e768` | **Phase 2.3** — Obsidian person notes, Daily Note, Decision Ledger |
| #20 | `116e908` | **Phase 3** — proactive intelligence & retention loops |
| #21 | `ebf26e6` | **Quick-wins sweep** — connect remaining dead-ends |
| #22 | `33a29cb` | **People** — tag management, recency, prefill, auto-focus |
| #23 | `c3622f5` | **People** — multi-select bulk actions, sort, AND-filter, Tasks tab, Ask AI |
| #24 | `f933854` | **People** — single-page profile, embedded chat, AI suggestions, deep message analysis, task links, insights |
| #25 | `38d314d` | **Phase 4 + 5** — calendar write-back, Obsidian companion, power governor, perf, hardware-aware AI |
| #26 | `70fdfeb` | **Docs** — this document |

Several stand-alone fixes also landed between phases (visible re-transcribe + app
version in Settings, the "you" short-recording transcription bug, mic+system
playback mixing, Re-transcribe/options discoverability, the Meetings-tab toolbar
inset, and a whisper watchdog so re-transcribe can't hang).

---

## Phase 0 — Critical correctness, data integrity & trust (PR #13)

Shipping bugs that lost data, broke the privacy promise, or blocked install.

| ID | Improvement |
|----|-------------|
| **E3-1** | Gate the ScribeCore daemon recording path behind an off-by-default flag (and proactively unregister the login item) — kills a silent total-meeting-loss landmine where the daemon recorded into an orphan folder and never called `finalize()`. |
| **E4-3** | Network-egress allowlist + non-local Ollama guard (`EgressPolicy`): the three transcript-bearing Ollama POST sites refuse a non-local endpoint unless the user opts in. |
| **E4-1** | Vault-containment guard on MCP writes (`resolveInsideVault()` rejects `..`/escaping paths) so add_person/add_memory/create_meeting_note can't write outside the vault. |
| **U1-2** | Profile-driven "my action items": a single `myNameAliases` source of truth on `AppSettings` (+ a "You" Settings section), replacing hardcoded `["tyler",…]` sets. |
| **C3-1** | Obsidian-native canonical markdown — auto-written `{slug}.md` routes through the rich builder (attendees frontmatter, `[[wikilinks]]`, inline `#tags`, `## People`); fixes the `2026-05`-as-a-tag bug. |
| **U4-3** | Don't leak private notes on share — a "what's included" confirm (private notes default OFF) before Markdown/PDF/Drive export. |
| **E3-4** | SQLite `quick_check` on open + auto-rebuild from canonical JSON on corruption; `rebuild()` rolls back on a failed step instead of committing a half-index. |
| **E5-7** | Fixed `clean-reinstall.sh` to target the right repo + resolve the library from the configured `storageDir`. |
| **E5-2 / E5-1** | E2E pipeline harness (drives real `finalize` against a temp vault) + golden-audio regression suite (real `whisper-cli` over reference clips, WER threshold). |
| **E1-10** | Verified already-correct (`.starting`/`.stopping` transient states existed) — no change. |

---

## Phase 1 — Finish shipped requirements, navigation & first-run (PR #14)

| ID | Improvement |
|----|-------------|
| **D1-1** | `WorkspaceRouter` — one source of truth for the selected section + meeting; collapses four meeting-open flows into the single Meetings-tab detail (removes the modal sheet + the `asyncAfter` hack). |
| **D1-2** | Register `meetingscribe://` + `onOpenURL` → router — unlocks deep links from MCP / Shortcuts / Spotlight. |
| **D1-5** | Clickable bidirectional links — PersonDetail recording rows open the meeting; attendee chips open/create a Person (green dot = already in People). |
| **D3-1** | In-app "Getting things ready" Setup Check (whisper model + Ollama) with one-tap remediation. |
| **D3-3** | A bundled sample meeting seeded on a brand-new vault so Today is never empty. |
| **D3-6** | Real Screen-Recording grant detection + a one-tap "Reopen MeetingScribe", replacing the quit-and-relaunch cliff. |
| **U1-1** | First-class "Push to Linear" button on every task (+ default-team picker). |
| **D2-3** | Unify accent color to brand purple (stray `accentColor` fills were resolving to system blue). |
| **D5-1** | Honor Reduce Motion on all perpetual animations. |
| **D4-1** | Global record-toggle hotkey (⌥⌘R) + a persistent recording HUD (pulsing dot, timer, audio meter, Stop). |
| **LAY-1** | Relax the page-column cap 720 → 1100 so Tasks breathe (also unblocks Dynamic-Type reflow). |
| **U5-1** | `make dmg` — a no-Terminal, drag-to-Applications installer. |

---

## D5-2 — Dynamic Type foundation (PR #16)

- **NDS font tokens now scale** — `title/pageTitle/sectionLabel/body/small/tiny`
  map to semantic text styles, so every design-system-token screen responds to
  Dynamic Type (within ~2pt of the prior fixed sizes at default).
- **`View.scaledFont(_:weight:relativeTo:)`** — a `@ScaledMetric`-backed modifier
  to bring inline sites onto Dynamic Type with no default-size shift.
- The worst low-vision offenders (11.5pt chip/eyebrow/tab text) converted.
- *Deliberately not* a blind sweep of ~192 inline `.font(.system(size:))` sites —
  left as a safe incremental follow-up (see U5 below).

---

## Phase 2 — The recall moat (PRs #17, #18, #19)

Turns capture into compounding, searchable memory.

### 2.1 (PR #17)
| ID | Improvement |
|----|-------------|
| **C2-1a** | Wire FTS5 global search onto the real `SecondBrainDB` BM25/recency engine (meetings, voice notes, people) + a once-per-session backfill that fixed the staleness behind the original revert. |
| **C2-1b / C5-10** | On-device embeddings (`EmbeddingService`, local `nomic-embed-text`, egress-guarded) + `vault_embeddings` store + reciprocal-rank fusion of lexical + semantic. Instant lexical results, then a hybrid refine. |
| **P2-1** | Truthful `lastInteractionAt` — bumped on auto-link/confirm, not just manual encounters; per-person reconnect cadence (median gap) instead of a flat 30 days. |
| **U2-1** | Unified person timeline — recorded meetings unioned with the person's unrecorded calendar meetings (matched by attendee email), deduped + badged. |
| **P1-3 / P1-2** | Synthesized, series-aware pre-meeting brief carrying context forward from the last occurrence of a recurring series. |

### 2.2 (PR #18)
| ID | Improvement |
|----|-------------|
| **C2-2** | Ask-your-vault cited RAG chat — retrieve-then-ground: each turn injects the top hybrid-search meetings (summaries + `meetingscribe://` links) and the model cites them. |
| **C2-3** | Auto-discovered "Related meetings" panel via embedding cosine (meeting↔meeting backlinks). |
| **C2-9 / C2-6** | "On this day" — Today resurfaces past meetings from prior weeks/months/years. |

### 2.3 (PR #19)
| ID | Improvement |
|----|-------------|
| **C3-2** | Obsidian-resolvable person notes — `person.md` leads with YAML frontmatter (`aliases`, role/company/email, `tags: [person]`) so `[[wikilinks]]` resolve and the graph renders. |
| **C2-4 / C3-3** | Daily Note — each finalized meeting appended to `Daily/YYYY-MM-DD.md` as a wikilink in an edit-guarded block (idempotent). |
| **P1-1 / C1-11 / C2-8** | Decision & Commitment Ledger — "Key Decisions" lifted into a queryable cross-meeting `DecisionStore`, surfaced on Today. |

---

## Phase 3 — Proactive intelligence & retention loops (PR #20)

| ID | Improvement |
|----|-------------|
| **P2-2** | Meeting-start notification leads with a structured brief (open items + prior-meeting context). |
| **U3-5** | "Meeting ready" push gets a summary snippet + a deep link. |
| **P2-5 / P2-3** | Opt-in 8am morning brief + a `Generate weekly review` writing `Weekly/<YYYY-Www>.md`. |
| **U3-2 / P2-7** | Owe/Owed commitments split (You owe / Owed to you). |
| **P2-6 / U3-3** | Follow-up sent-state + a "Follow-ups to send" resurfacing section (+ Mark-as-sent). |
| **U1-4** | Daily Standup digest (yesterday / today / open / blockers). |
| **D4-2** | ⌘K is now a real command palette (record, new task/voice note/person, navigate, weekly review, refresh). |
| **D4-3** | Undo toast for destructive vault moves (e.g. tag rename → Undo). |
| **P5-3** | Summary 👍/👎 with a reason that steers the next regeneration. |
| **P5-6** | One-click health check (model, Ollama, disk, permissions). |
| **P5-1** | Opt-in, local-only usage metrics (default off, never uploaded). |

---

## Quick-wins sweep — connect remaining dead-ends (PR #21)

| ID | Improvement |
|----|-------------|
| **A3 / UX4-1** | Task "From meeting" chip is clickable → opens the meeting (was dead text). |
| **A2 / UX3-1** | PersonDetail email/phone rows are actionable (`mailto:` / `tel:`). |
| **A10 / FT2-1** | "Copy link to meeting" in the meeting Options menu. |
| **UX9-1** | Meetings empty state gets a "Record a meeting" CTA. |

---

## People tab overhaul (PRs #22, #23, #24)

The session's largest body of work — from a thin tabbed profile to a single-page
relationship workspace.

### List & organization (#22, #23)
| ID | Improvement | Where |
|----|-------------|-------|
| **FT3-1** | Tag-management UI — rename/delete people-tags (methods existed, no UI). | `People/TagManagementSheet.swift` (new) |
| **UX3-2** | Last-interaction recency in each row ("2w ago"). | `People/PeopleListView.swift` |
| **UX3-3** | Prefill the active tag when adding a person while filtered. | `People/AddPersonSheet.swift` |
| **UX10-4** | Auto-focus the Name field on a new person. | `People/AddPersonSheet.swift` |
| **FT3-2 / FT3-3** | Multi-select + bulk **tag / merge / delete** (merge collapses into the highest-signal record). | `People/PeopleListView.swift` |
| sort | Persisted sort — Recent / Name / Most meetings / Recently added (off while searching). | `People/PeopleListView.swift` |
| **UX3-5** | AND tag-filter — two chips show only people carrying both. | `People/PeopleListView.swift` |

### Profile redesign + in-profile AI (#24)
| Improvement | Where |
|-------------|-------|
| **Single scrollable page, no tabs** — identity, tags, contact, favorites, AI suggestions, relationships, encounters, meetings, tasks, memories, notes, messages all visible at once. | `People/PersonDetailView.swift` |
| **Embedded AI chat** as a persistent right column (`ChatPanel` on the shared session), replacing the toggled rail; "Ask AI" posts a briefing into it. | `People/PersonDetailView.swift` |
| **Inline editing** — Add-tag menu (pick/create, removable chips) + Favorites add/remove, alongside inline identity edit. | `People/PersonDetailView.swift` |
| **AI suggestions card** — on-device Ollama proposes tags / relationships / encounters from profile + meetings + co-attendees; one-tap accept. | `People/PersonAISuggestions.swift` (new) |
| **Deep message analysis** — one thorough pass over all matched texts, cached once (`deep-all` note); also mines tags/encounters from message content into the suggestions card. | `People/PersonDetailView.swift` |
| **People insights dashboard** — the empty detail pane becomes Reconnect / Upcoming birthdays / Most active. | `People/PeopleInsightsView.swift` (new) |

### Cross-tab
| Improvement | Where |
|-------------|-------|
| **Real Person↔task link** — `ActionItem.ownerPersonID` (safe Codable migration); person Tasks match the hard link first (owner-string as legacy fallback); quick-add links exactly; the task page assignee gains a person-link menu + open-person button. Bidirectional. | `ActionItems/ActionItem.swift`, `ActionItems/ActionItemStore.swift`, `People/PersonDetailView.swift`, `UI/TaskPageView.swift` |

---

## Phase 4 — Platform & workflow reach (PR #25)

| ID | Improvement | Where |
|----|-------------|-------|
| **P4-1** | Calendar write-back — **Add recap to event** writes the summary + deep link into the source event's notes (idempotent); **Schedule follow-up** (tomorrow / 3 days / next week) creates an event. In Options → Calendar…. | `Calendar/CalendarStoreActor.swift`, `UI/MeetingDetailHeader.swift` |
| **C3-x** | Obsidian companion — **Open in Obsidian** (`obsidian://open`) + an **EXPORT.md** portability manifest at the vault root ("leave anytime"). | `Export/VaultManifest.swift` (new), `Export/ObsidianExporter.swift` |

---

## Phase 5 — AI stack & performance (PR #25)

| ID | Improvement | Where |
|----|-------------|-------|
| **E2-2 / E2-3 / E2-7** | `ResourceGovernor` — the app was power-blind. Reads battery (`IOKit.ps`), low-power, `thermalState`; **defers live transcription to a single batch pass on stop** when constrained (finalize already covers the empty-live case, so no transcript is dropped). Two Settings toggles + live status. | `AI/ResourceGovernor.swift` (new), `MeetingManager.swift` |
| **E2-5** | `ThumbnailCache` — ImageIO-downsampled, `NSCache`-backed people-photo thumbnails replace full-res decode-per-render. | `UI/ThumbnailCache.swift` (new) |
| **C5-3** | `HardwareProfile` — RAM/core-aware recommended summarization model with a "Use recommended" button + a "this Mac" hint. | `AI/HardwareProfile.swift` (new) |

---

## Explicitly deferred (need external deps / accounts)

Flagged, not built — real work that can't be built-and-verified headlessly:

- **Phase 4:** real Slack delivery (bot token), HubSpot/Attio CRM bridge,
  MCP-registry publish, Raycast/Alfred extension, the local automation
  rules-engine, the first-class Client/Workspace entity, billable-time/timesheets.
- **Phase 5:** WhisperKit / Apple SpeechAnalyzer STT swap, FluidAudio diarization,
  MLX summarization backend — each needs a new SPM dependency + model downloads
  best validated interactively on a Mac.
- **Carried from earlier audits** (`REMAINING_WORK.md`): CaptureKit extraction,
  two-binary activation, iPhone Shortcuts authoring.

---

## Future recommendations — layout & usability

> After today, the product's **feature** surface is strong. The biggest remaining
> wins are in **consistency, hierarchy, and editing ergonomics**, not new
> capabilities. The People redesign set a high bar (single page, inline edit,
> embedded chat, live empty states) that the rest of the app hasn't reached yet.
> Phase 6 (architecture hardening) is intentionally out of scope here; these are
> the *user-facing* layout/usability phases worth doing alongside it.

### U1 — Design-system enforcement (the enabler; do first)

Today's work hand-rolled section cards, chips, and rows in several places
(People, the new insights/suggestion cards), while Meetings, Tasks, Chat, and
Settings each keep their own. That drift is the root of most inconsistency.

- **Extract shared primitives** — `MSCard`, `MSListRow`, `MSSurface`,
  `MSSectionHeader`, `MSEmptyState` — and migrate every tab onto them (plan items
  **D2-1 / D2-6**). One card definition → one fix when a card is wrong.
- **Spacing/radius scale + CI lint** on the `NDS` tokens so surfaces can't drift
  back to magic numbers.
- **Promote `NDS.splitPaneTopInset` to a layout primitive** every top-level pane
  uses. The toolbar-clearance bug recurred per-pane today (Meetings header,
  People panes); make it structural rather than remembered.

### U2 — Bring the People patterns to the rest of the app

The People profile is now the reference layout; apply its three wins outward.

- **Single-page detail over tabs.** Audit the Meeting detail (still a header +
  inline sections + modal sheets) for the same one-scroll + progressive-disclosure
  treatment.
- **One contextual-chat pattern.** There are now three chat surfaces — the People
  embedded column, the per-meeting Chat tab, and the global toggled rail. Unify
  them into a single "chat about what I'm looking at" component with a consistent
  position and grounding contract.
- **Inline editing over modal sheets.** People edit tags/favorites/identity in
  place; Meetings (title/description), Tasks (properties), and full person-edit
  still open sheets. Prefer in-place + autosave; reserve sheets for genuine
  multi-field creation.

### U3 — Information hierarchy & wayfinding

- **Tame the long person page.** One scroll for a rich person gets very long. Add
  a lightweight **section jump-rail / anchors** or **collapsible sections**, and
  collapse low-signal blocks (transcript, provenance, full message history) by
  default.
- **Consistent selection & back affordances.** People list is single-select →
  detail with a separate multi-select mode; Meetings/Tasks differ. Pick one
  selection metaphor and one back/breadcrumb treatment across tabs.
- **Make global search the primary nav.** The ⌘K palette (Phase 3) + the hybrid
  FTS index (Phase 2) are already built — lean on them so the app feels smaller
  and tab-hopping drops.
- **Empty states everywhere.** The insights dashboard and the Meetings CTA proved
  the value; give every blank pane (Today, Tasks, search-no-results) the same.

### U4 — Editing ergonomics & trust

- **Autosave-on-blur + consistent focus management** across every create/edit
  surface (**UX10-2 / UX10-3**): auto-focus the first field, commit on blur, never
  lose a half-typed field to navigation.
- **Undo for destructive actions.** The vault-move undo toast (D4-3) exists, but
  bulk **merge** and **delete** in People are irreversible — extend the undo
  window (or soft-delete) to them, merge especially (it auto-picks the keeper).
- **Better in-context AI states.** AI suggestions and deep analysis fail to a terse
  "make sure Ollama is running" string — add a loading/skeleton state, a cancel
  affordance, and a one-click setup hint (the Setup Check from D3-1 can host it).
- **Light feedback over modal.** Calendar write-back uses a modal `NSAlert`; prefer
  an inline, auto-dismissing toast so confirmations don't block.

### U5 — Responsiveness & accessibility

- **Finish Dynamic Type.** D5-2 laid the foundation + the `scaledFont` helper;
  sweep the remaining ~192 inline `.font(.system(size:))` text sites
  incrementally, and add VoiceOver `accessibilityLabel`s to icon buttons and the
  new chips/suggestion rows/insights dashboard.
- **Narrow-window behavior.** The People `HSplitView` (sections + embedded chat)
  needs a graceful collapse below a width threshold — the chat should become a
  toggle, not squeeze the content. Audit every split pane for small screens.
- **Reduce-motion / contrast passes** on the new surfaces (D5-1 covers animation;
  verify the new cards/chips for contrast).

### Smaller, specific usability debt found this session

- **Bulk merge keeper is auto-chosen.** Offer an explicit keeper pick for
  ambiguous merges (the per-pair duplicate sheet already does this).
- **Assignee → person picker caps at 50 recent contacts** with no search — make it
  a searchable picker (mirror `AddRelationshipSheet`).
- **The embedded chat shares one global `ChatSession`** — viewing a person while
  the global rail is open mirrors state. Consider per-context sessions, or make the
  shared session's grounding switch unambiguously with the visible context.
- **Task↔person matching falls back to an owner *string*** — two people sharing a
  first name can both surface a loosely-owned task until it's hard-linked; a
  "link owners to people" cleanup pass would tighten it.

### Sequencing

`U1` (design system) is the enabler — do it first so `U2`–`U5` apply consistent
primitives instead of multiplying bespoke ones. `U2` and `U3` deliver the most
visible "the app feels coherent now" payoff. `U4` and `U5` are continuous polish
that should ride along with every subsequent change rather than being one phase.
