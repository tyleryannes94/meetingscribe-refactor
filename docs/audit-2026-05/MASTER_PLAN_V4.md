# MeetingScribe — Master Plan V4 (25-Agent Audit Synthesis)

> **Repo audited:** `~/MeetingScribeRefactor` → `github.com/tyleryannes94/meetingscribe-refactor` (HEAD `c25a41e`). The new, rebuilt app — not legacy `~/MeetingScribe`.
> **Method:** 25 independent expert agents in 5 groups of 5 — Senior Product Designer · Senior Product Manager · Staff Engineer · End-User Personas · Industry/Competitive Experts (with live 2026 web research). Each agent read MASTER_PLAN V1–V3, AUDIT_REPORT_2026-05-30, and REMAINING_WORK first, then audited the live Swift source citing `file:line`, then proposed **net-new** work beyond the existing plans. 153 net-new items were produced; this doc dedupes, ranks, and sequences them into build phases for Claude Code.
> **Date:** 2026-05-30 · **Status:** Proposed — for Tyler's review.
> **Per-agent detail:** `audit/findings/*.md` (25 files). Item IDs below (e.g. `C2-1`, `E3-1`) map to those files.

---

## 1. Executive summary

The rebuild is in genuinely good shape — capture, the data layer, the people graph, and a 17-tool read+write MCP server are real and largely match the prior plans. The single most important finding from this round is a reframing: **MeetingScribe has solved *capture* and barely started on *recall*.** Five different agents, working from completely different lenses (notetakers, second-brain, personal-AI, PM-roadmap, manager-persona), independently converged on the same conclusion — the corpus the app already collects is not yet queryable, connected, or proactive. That gap is simultaneously the biggest competitive hole *and* the most defensible moat, because the recall feature the whole market is racing to ship (Otter, Fathom, Granola, Limitless) can only be done **100% on-device here**.

Before any of that, though, the engineering agents surfaced **one critical, shipping data-loss bug and a small cluster of trust/correctness breaks** that must be fixed first. Those make up Phase 0.

### The convergence map — where independent agents agreed (highest signal)

| Theme | Agents who independently raised it | Phase |
|---|---|---|
| **"Ask your vault / memory" — local RAG Q&A across all meetings with citations** | C1-1, C2-2, C4-1, P1-7 (notetakers, 2nd-brain, personal-AI, PM) | 2 |
| **The FTS5 search engine already ships but is unused; wire it + add semantic recall** | C2-1, C5-10 (2nd-brain, infra) | 2 |
| **Decision & Commitment Ledger — cross-meeting "what was decided / who owes whom"** | P1-1, C1-11, C2-8, U2-3, U3-2, P2-7 (PM, notetakers, 2nd-brain, manager, founder) | 2 |
| **Per-person page is broken: it ignores unrecorded calendar meetings; `lastInteractionAt` is wrong** | U2-1, P2-1 (manager, retention-PM) | 2 |
| **Synthesized, series-aware pre-meeting brief, pushed (not pull)** | P1-3, P2-2, U1-5, U2-2, U3-4 (PM ×2, IC, manager, founder) | 2/3 |
| **GUI install silently assumes the CLI installer ran → ship a no-Terminal DMG + in-app setup** | U5-1, U5-2, D3-1 (non-tech user, designer) | 0/1 |
| **Accessibility floor: Dynamic Type + VoiceOver + reduce-motion (192 fixed font sizes today)** | D5-1, D5-2, U5-4 (a11y designer, non-tech user) | 1 |
| **Auto-record the in-progress calendar event (detector + calendar already exist)** | U3-1, P1-9 (founder, PM) | 3 |
| **Apple SpeechAnalyzer/WhisperKit default STT + whisper warm-pool** | C5-1, E2-1 (infra, perf) | 5 |
| **Make the canonical on-disk markdown Obsidian-native (+ fixes a live tag bug)** | C3-1, C3-2 (local-first) | 0/4 |
| **One canonical navigation router + deep links + command palette** | D1-1, D1-2, D4-2 (IA, interaction designers) | 1/3 |

---

## 2. Phase 0 — Critical correctness, data integrity & trust (do first)

These are shipping bugs that lose data, break the privacy promise, or block install. None are large; all are high-stakes. Build and verify on the Mac (record→stop→transcribe smoke test) before anything else.

| ID | Item | Why it's P0 | Source | Effort |
|---|---|---|---|---|
| **E3-1** | **Gate/fix the ScribeCore daemon recording path.** The daemon is shipped and auto-registered as a login item (`MeetingScribeApp.swift:152`, `Makefile`). If it boots first, recording routes to it, captures into an orphan `meetings/scribecore-<date>/` with no `meeting.json`, never wires live transcription, and never calls `finalize()` → **total silent loss of a meeting** while audio is stranded. Gate behind an off-by-default flag immediately; fix or finish the path before re-enabling. | Eng/Reliability | M |
| **E1-10** | **Close the recording-state TOCTOU race** — add the `.starting`/`.stopping` transient states (V2 Bug 6 was never actually fixed). | Eng/Arch | S |
| **E4-3** | **Network egress allowlist + "endpoint left localhost" guard.** A user-settable `ollamaURL` with no allowlist can silently ship transcripts off-device over HTTP — directly violates "everything stays local." Make the promise an enforced invariant. | Eng/Security | M |
| **E4-1** | **Vault containment guard on all writes.** A meeting's stored `relativeFolderPath` flows unchecked into now-write-capable MCP tools → path traversal escaping the vault. Validate every write path. | Eng/Security | S |
| **U1-2** | **Fix the hardcoded-"me" ownership filter.** `ActionItemExtractor.swift:27` hardcodes `["tyler","tyler yannes"]`; the "only my action items" feature is silently broken for any other user (the plan marked name de-hardcoding "done" but only the Ollama prompt was fixed). Make it profile-driven + aliasable. | IC user | S |
| **C3-1** | **Fix the canonical markdown writer.** Finalize auto-writes the lossy `writeMarkdownFile` (no people, no wikilinks, tags scraped from folder name → ships `2026-05` as a "tag"); the rich Obsidian-native writer is reachable only via manual export. Merge them so the on-disk file is the good one. Fixes a live tag bug too. | Local-first | M |
| **U4-3** | **Stop leaking private notes on share.** `MeetingExporter.combinedMarkdown` dumps the user's private notes + full transcript with no redaction/recipient awareness. Add a redaction guard / explicit "what's included" confirm before any share. | Consultant user | M |
| **E3-4** | **SQLite `quick_check` + auto-rebuild** so a bad shutdown can't silently empty the People graph the whole product is built on. | Eng/Reliability | S |
| **E5-7** | **Fix `clean-reinstall.sh`** — the official recovery script (line 21) still rebuilds from the *old* `~/MeetingScribe` repo, recreating the wrong-repo install bug. Target the refactor repo + assert the remote. | Eng/Testing | S |
| **E5-2 / E5-1** | **Stand up the test floor that would have caught all of the above:** an end-to-end record→transcribe→repair→vault pipeline harness (E5-2) and a golden-audio transcription regression suite (E5-1). The whisper subprocess is the product's core and is explicitly untested. | Eng/Testing | M |

---

## 3. Phase 1 — Finish the shipped requirements, navigation & first-run

Closes the remaining gaps in the V3 "seven non-negotiables" and makes the GUI-only path actually work. Several items here are reaffirmations of existing-plan work the agents ranked highest; the net-new items are marked ★.

| ID | Item | Source | Effort |
|---|---|---|---|
| NAV-1/2/5, LAY-1/2 (existing) | Kill remaining expand/collapse in Today + Calendar → click-into detail; full-width (remove 720/920 caps); chat rail closed by default; resolve orphaned Calendar view. | V3 (endorsed by D1, U-personas) | M |
| PPL-1, DEF-1/3, TDY-1/2 (existing) | Inline person editing; default Meetings scope = upcoming + persist; promote Draft-follow-up; Today "up next" + "needs attention". | V3 (endorsed) | M |
| **D1-1 ★** | **One canonical entity router with a per-tab `NavigationPath`.** A meeting opens four different ways today (split pane, pushed page, two modal-sheet routes + an `asyncAfter(0.18)` hack). Collapse to one surface — the keystone the back/forward, breadcrumb, deep-link and recents work all depend on. | IA designer | M |
| **D1-2 ★** | **Register `meetingscribe://` with the OS + add `onOpenURL`.** The scheme is referenced but registered nowhere, so MCP/Shortcuts/Spotlight can't deep-link. Tiny effort, unlocks the agent/automation surface. | IA designer | S |
| **D1-5 ★** | **Bidirectional, clickable person↔meeting↔task links everywhere** (PersonDetail "In your recordings" rows are dead `HStack`s; attendee chips only respond to right-click). Makes the moat navigable. | IA designer | M |
| **U5-1 ★** | **No-Terminal `.dmg` installer** (double-click, drag-to-Applications, signed). The only install path today is `git clone && ./install.sh` — a hard wall for non-technical users. | Non-tech user | M |
| **U5-2 / D3-1 ★** | **In-app "Getting things ready" Setup Check** before first recording — download the whisper model + start Ollama in-GUI with progress, never a shell command (today a non-CLI user eventually hits a raw `brew services start ollama` error, `OllamaService.swift:34`). | Non-tech user / designer | M |
| **D3-3 ★** | **Bundled sample/demo meeting** so first value (a real summary) arrives in zero clicks and Today is never empty. | Onboarding designer | S |
| **D3-6 / U5-7 ★** | **Screen-Recording grant auto-detection + a real "Reopen MeetingScribe" relaunch helper**, replacing the "quit and relaunch" cliff that reads as broken. | Designer / non-tech user | S |
| **U1-1 ★** | **First-class "Push to Linear" button on every task** (parity with the existing "Push to Notion"). `createLinearIssue` already exists (`TaskSyncService.swift:202`) — it just needs a button. Lowest-effort/highest-leverage IC win. | IC user | S |
| **D5-1 ★** | **Reduce-motion compliance pass** — remove always-on `repeatForever`/`symbolEffect(.pulse)` vestibular triggers on the primary screen. | A11y designer | S |
| **D5-2 / U5-4 ★** | **Dynamic Type + VoiceOver + larger-text pass.** 192 fixed `.font(.system(size:))` calls lock out low-vision users; do it alongside LAY-1 so enlarged text can reflow. | A11y designer / non-tech user | M |
| **D4-1 ★** | **Single global record toggle + persistent recording HUD** (meeting recording lacks the polished HUD voice-note dictation already has; no *global* record hotkey today). | Interaction designer | M |
| **D2-3 ★** | **Unify the accent color to brand purple** (it currently flips to system blue on opted-out surfaces) — smallest effort, highest-visible polish. | Visual designer | S |

---

## 4. Phase 2 — The recall moat (turn capture into compounding memory)

The highest-value phase and the strongest cross-agent convergence. This is what makes MeetingScribe defensible.

| ID | Item | Source | Effort |
|---|---|---|---|
| **C2-1** | **Wire the existing FTS5 engine + add hybrid semantic recall.** The BM25/recency-boosted `vault_content`/`vault_fts` engine already ships (`SecondBrainDB.swift:269`) but global search falls back to in-memory `contains()` (`WorkspaceIndex.swift:106`) after a stale-index revert. Re-wire it, fix the index, add on-device embeddings (C5-10) for semantic search. | 2nd-brain / infra | M |
| **C1-1 / C2-2 / C4-1 / P1-7** | **"Ask your vault" — local RAG chat across all meetings, with citations.** The defining 2026 table-stakes feature (Otter CMI, Fathom, Granola, Limitless) — and MeetingScribe can ship the *only* fully-on-device version. Turn the existing Ollama chat from structured lookups into cited cross-meeting Q&A. | notetakers / 2nd-brain / personal-AI / PM (4-way) | L |
| **P1-1 / C1-11 / C2-8** | **Decision & Commitment Ledger.** A structured, queryable cross-meeting layer extracting decisions and commitments ("who owes what, by when") from transcripts. The clearest net-new differentiator; converts the captured corpus into durable memory. | PM / notetakers / 2nd-brain | L |
| **U2-1** | **Unified person timeline** (recorded meetings + unrecorded calendar meetings + messages). Today the per-person page (`PersonDetailView.swift:514`) only shows recordings, so a manager's weekly 1:1s read empty and the brief says "first meeting" with someone met for a year. The keystone for every people-centric feature. | Manager user | M |
| **P2-1** | **Make `lastInteractionAt` truthful** — derive from all signals (meetings, calendar, messages), add per-person cadence. The entire stay-in-touch/compounding-CRM moat rests on this number being right. | Retention PM | S |
| **P1-3 / P1-2** | **Synthesized, series-aware pre-meeting brief.** Today the brief is a static list with no LLM synthesis; `seriesID` exists but does nothing. Make it auto-carry unresolved commitments and last-time context. Engine + IDs already exist. | PM | M |
| **C2-3** | **Automatic bidirectional entity links** (real backlinks, not literal-URL scans) so the graph self-assembles from capture. | 2nd-brain | M |
| **C3-2** | **Write per-person `People/*.md` notes** so wikilinks resolve and the relationship graph renders *in Obsidian*, not just in SQLite. | Local-first | M |
| **C2-4 / C3-3** | **Daily Note** — a persisted, linkable temporal spine; append each meeting into `Daily/YYYY-MM-DD.md`. The stickiest, lowest-cost way to slot into the PKM habit. | 2nd-brain / local-first | S |
| **C2-9 / C2-6** | **Temporal recall ("On this day", topic timelines) + proactive resurfacing ("Heads up, last time with X…").** | 2nd-brain | M |

---

## 5. Phase 3 — Proactive intelligence & retention loops

Convert the recall layer (Phase 2) from pull to push and build the habit loop. The app currently has almost no proactive reason to reopen on a light-meeting day.

| ID | Item | Source | Effort |
|---|---|---|---|
| **P2-2** | **Push the synthesized pre-meeting brief into the meeting-start notification** (rides the strongest existing trigger; turns "I should've prepped" into "the app prepped me"). | Retention PM | S |
| **U3-1 / P1-9** | **Auto-record the in-progress calendar event** (consent-aware), not just notify. The Zoom/Meet detector + calendar already exist; join them so recording happens without remembering to press a button. | Founder / PM | M |
| **P2-5 / P2-3** | **Morning brief notification + generated daily/weekly recap with a real "Weekly Review" ritual** (today the "Weekly review" is a blank note template). | Retention PM | M |
| **P2-6 / U3-3** | **Follow-up lifecycle: track "sent" state and resurface forgotten ones** (no sent-state exists today). | Retention PM / founder | S |
| **U3-2 / P2-7** | **"Owe / Owed" board** — delegation + commitments-to-people tracking (the `owner` field exists; add direction + a board). | Founder / PM | M |
| **U1-4 / U2-2 / U3-4** | **Persona digests: Standup Mode (60-sec yesterday/today/blockers), per-report 1:1 prep digest, person dossier in the brief.** | IC / manager / founder | M |
| **U3-5** | **Between-meeting summary push** with deep links — a finished summary you have to go find won't get read on a back-to-back day. | Founder | S |
| **D4-2** | **Turn ⌘K into a real command palette** (today it's search-only despite the rail's ⌘K chip) — makes every action keyboard-reachable. | Interaction designer | M |
| **P5-3** | **Summary 👍/👎 with local "why" capture that steers regeneration** — the local LLM is the product's variable-quality core and has zero feedback loop today. | Metrics PM | S |
| **P5-1 / P1-4** | **Opt-in, local-only `MetricsStore`** (default off, never uploaded) so the project's own four KPIs become measurable and the roadmap can be prioritized on data. | Metrics / roadmap PM | M |
| **P5-6** | **One-click self-diagnostics "Run a health check"** (whisper/Ollama/permissions/disk) — for a local app the user is their own ops team. | Metrics PM | S |
| **D4-3** | **Universal undo** (toast + `UndoManager`) — the app physically moves vault folders on retag with zero undo today. | Interaction designer | M |

---

## 6. Phase 4 — Platform, integrations & workflow reach

The app reads the calendar flawlessly but writes nothing back, "Slack" only copies text, and there's no programmatic surface beyond Claude. Make it a hub.

| ID | Item | Source | Effort |
|---|---|---|---|
| **P4-1** | **Calendar write-back** ("schedule next meeting", "notes ready" on the event) — table stakes every competitor has. | Workflow PM | M |
| **P4-3** | **Real Slack delivery + capture** (replace the fake draft-only channel with a Slack app + bot token). | Workflow PM | M |
| **P4-4 / P4-5** | **Local "when X then Y" automation rules engine + webhook in/out sink** — composes every export button into workflows. | Workflow PM | M |
| **P4-9 / P4-7** | **Public local HTTP API + OpenAPI, and a Raycast/Alfred extension** for frictionless desktop capture & search. | Workflow PM | M |
| **C5-7 / C5-8 / C2-10 / C5-9** | **Publish the MCP server to the official registry as a "personal memory backend"; add a streamable-HTTP transport; expose semantic-search + graph traversal + elicitation for human-in-the-loop writes.** MeetingScribe already *is* the hot 2026 category — claim it. | Infra / 2nd-brain | M |
| **U4-1** | **First-class Client/Workspace entity above tags** (tags are flat metadata today; `desiredDirectory` ignores them). Foundation for client siloing, safe export, and billing. | Consultant user | L |
| **U4-4 / U4-5** | **Billable-time capture + per-client invoice-ready timesheet** (timestamps already exist on `Meeting`). | Consultant user | M |
| **C3-4/5/6/7/8** | **Obsidian companion suite:** "Open vault in Obsidian", Bases-ready frontmatter + starter `.base`, a `vault/_plugins/` post-finalize hook, round-trip import of hand-edited markdown, and an `EXPORT.md` portability manifest ("leave anytime"). | Local-first | M–L |
| **P4-6 / P4-8** | **Generalize `_inbox` capture beyond iPhone (email/desktop/clipboard); CRM bridge for the People graph (HubSpot/Attio).** | Workflow PM | M |

---

## 7. Phase 5 — AI stack upgrade & best-in-class transcription

Every layer of the local-AI stack now has a materially better Apple-Silicon option (validated against 2026 web research). These improve the core loop's accuracy, speed, and energy on the user's macOS 26 / M2 hardware.

| ID | Item | Source | Effort |
|---|---|---|---|
| **C5-1 / E2-1** | **Adopt Apple SpeechAnalyzer/WhisperKit (CoreML/ANE) as the default STT, whisper.cpp as fallback; add a persistent whisper warm-pool.** ~55% faster, zero 140 MB download (kills brew/model friction), and ends the per-chunk model cold-load (~36 reloads per 90-min meeting) that is the single largest avoidable energy cost. | Infra / Perf | L |
| **C5-2** | **Real diarization via FluidAudio (CoreML/ANE)** so the *planned* speaker-labeled transcript/summary feature actually works (today `SpeakerDiarization` is a no-op marker). | Infra | M |
| **C5-11 / D5-6** | **Live streaming captions during the meeting** (not just 5-min chunks) → doubles as a flagship **Live Caption Mode** accessibility feature for deaf/HoH users. | Infra / a11y | M |
| **C5-4** | **Streaming summarization with live token rendering** (no more staring at a spinner). | Infra | S |
| **C5-5 / C5-6 / C5-3** | **Native MLX summarization backend + optional Apple Foundation Models (zero-dependency) tier + hardware-aware model picker.** | Infra | M |
| **E2-2 / E2-3 / E2-7** | **`ResourceGovernor`: low-power/thermal adaptive mode; defer live transcription to batch-on-stop on battery; a built-in perf/energy profiling harness.** The app is power-blind today. | Perf | M |
| **E2-5 / E2-10** | **Thumbnail downsampling + decoded-image cache for people photos; coalesce live-transcript re-renders.** | Perf | S |

---

## 8. Phase 6 — Architecture hardening & maintainability

Pays down the structural debt so the two-binary split and CaptureKit work become safe rather than risky. Mostly internal; sequence after or alongside feature phases.

| ID | Item | Source | Effort |
|---|---|---|---|
| **E1-1** | **Services domain layer + constructor injection behind protocols** (today `AppSettings.shared` ×165, `MeetingManager` hard-news all deps). The prerequisite that makes CaptureKit de-dup and two-binary activation safe. | Eng/Arch | L |
| **E1-2** | **Ship a real `VaultFileStore` and route both the app and the MCP server through it** (turns VaultKit from a DTO bag into a shared domain layer; eliminates the dual write paths). | Eng/Arch | M |
| **E1-7 / E1-4** | **Typed, versioned `ScribeBridge` IPC contract; unify logging/error/settings as VaultKit protocols and delete `CompatShim` + the daemon's forked `AppSettings`.** Makes the two-binary split finishable without re-drift and stops ENG-A silently regressing across the boundary. | Eng/Arch | M |
| ARCH-1 / ARCH-3 (existing) | **CaptureKit extraction (retire app↔daemon duplication — 12 files have already diverged); decompose god-files (PeopleStore, PersonDetailView, MCP main.swift); two-binary activation.** | V3 / Eng | L |
| **E4-5 / U3-9** | **Vault encryption at rest + a sensitive-meeting mode** — the durable answer to "years of meetings sit in plaintext in iCloud Drive." | Security / founder | M |
| **E5-3/4/5/6/9** | **Testing & release hardening:** `make doctor` pre-flight, crash-report capture into the diagnostics bundle, fuzz/property tests for the vault parsers, automated notarization in the release workflow, CI sanitizer + coverage lane. | Eng/Testing | M |
| **D2-1 / D2-6** | **Design-system enforcement:** spacing + radius scale with a CI lint; extract `MSCard/MSListRow/MSSurface` so opted-out surfaces (ActionItems, Chat, Settings) can't drift. | Visual designer | M |
| **E3-3** | **Pipeline write-ahead journal + finalize resume** so a crash during the multi-minute finalize resumes instead of stranding a meeting. | Eng/Reliability | M |

---

## 9. Phase 7 — Positioning, monetization & strategic bets (future / optional)

Not required to ship; captured because the PM and competitive agents made a strong, coherent case. Pursue only if MeetingScribe is headed past "personal app."

| ID | Item | Source | Effort |
|---|---|---|---|
| **P3-1** | **Lead with "compliance-grade local" as the wedge, not generic "privacy"** — target legal/health/finance who *can't* use cloud tools. Near-free repositioning; the COGS asymmetry (no per-minute cloud cost) is the commercial thesis. | Monetization PM | S |
| **P3-2 / P3-3** | **License the runtime + intelligence (never the data) via a signed offline license; hybrid one-time "lifetime local" + optional Intelligence+ subscription.** The missing monetization scaffolding, done the only way consistent with own-your-data. | Monetization PM | M |
| **P3-5 / P3-6 / P3-8** | **"Programmable vault" developer SKU; serverless team via vault-federation over shared iCloud/Drive; anti-lock-in as a marketed guarantee.** | Monetization PM | M–L |
| **C4-2 / C4-3** | **On-device Recall Timeline (the privacy-first answer to Microsoft Recall) + Consent-First Always-On Mode** (visible indicator, consent-mode, retention/TTL, jurisdiction warnings). The category is growing from meeting-bounded to life-bounded and got punished on *trust* — exactly MeetingScribe's ground. Build responsibly. | Personal-AI | L |
| **C4-5 / C4-7** | **Retention & "Right to Forget" policies (audio-vs-transcript TTL, per-item forget) + consent receipts/provenance per recording.** | Personal-AI | M |
| **P5-7 / C1-2 / C1-9** | **"Your Year in Meetings" local stats; opt-in conversation intelligence (talk-time, topics, sentiment); private on-device meeting coaching.** | Metrics PM / notetakers | M |

---

## 10. How to use this plan with Claude Code

- **Phases are dependency-ordered.** Phase 0 is non-negotiable and independent of UI. Phase 2 (recall) is the strategic core and depends on Phase 0's correctness fixes + the FTS5 re-wire. Phases 4–7 can be reordered by appetite.
- **Each item ID resolves to a full write-up** (problem, `file:line` evidence, user value, effort, dependencies) in `audit/findings/<group>.md`. Hand Claude Code an item ID and that file for full context before implementation.
- **Per the project workflow**, build + `swift build -c release` / `make app` + a record→stop→transcribe smoke test must gate each change before commit; data-integrity items (Phase 0) especially can only be verified on the Mac.
- **Suggested first sprint:** E3-1, E1-10, E4-3/E4-1, U1-2, E5-7 (correctness/trust) → then E5-2 harness → then C2-1 (wire FTS5) as the on-ramp to the recall moat.

---

## Appendix — full item catalog (153 net-new items)

Grouped by source agent; see `audit/findings/*.md` for full detail on each ID.

**G1 Product Designer** — IA/Nav (D1-1…D1-12), Visual System (D2-1…D2-7), Onboarding (D3-1…D3-6+), Interaction (D4-1…D4-x), Accessibility (D5-1…D5-6).
**G2 Product Manager** — Roadmap (P1-1…P1-10), Retention (P2-1…P2-11), Monetization (P3-1…P3-10), Workflows (P4-1…P4-12), Metrics (P5-1…P5-11).
**G3 Staff Engineer** — Architecture (E1-1…E1-10), Performance (E2-1…E2-10), Reliability (E3-1…E3-10), Security (E4-1…E4-x), Testing (E5-1…E5-11).
**G4 End-User Personas** — IC (U1-1…U1-10), Manager (U2-1…U2-x), Founder (U3-1…U3-10), Consultant (U4-1…U4-5), Non-technical/a11y (U5-1…U5-12).
**G5 Competitive Experts** — Notetakers (C1-1…C1-11), Second-brain (C2-1…C2-10), Local-first PKM (C3-1…C3-10), Personal-AI (C4-1…C4-8), Infra/MCP (C5-1…C5-12).
