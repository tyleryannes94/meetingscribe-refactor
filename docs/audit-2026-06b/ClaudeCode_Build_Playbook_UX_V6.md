# Claude Code Build Playbook — UX-V6 (Focused UX Audit, 2026-06-11)

Companion to `docs/audit-2026-06b/MASTER-PLAN-UX.md`. Paste one prompt per Claude Code session, in order. Don't start the next phase until the current PR is merged and `main` is green.

## How to use

1. Make sure `docs/audit-2026-06b/` (briefing, master plan, findings) is committed to `main` first, so every phase branch can read it.
2. Paste **PROMPT 0** once at the start of every session (or append it to `CLAUDE.md` once).
3. Paste the phase prompt. Review the PR. Merge. Repeat.

## Build order

1. Phase 0 — Shipping bugs & trust emergencies (`ux6-phase0-fixes`)
2. Phase 1 — Identity & navigation spine (`ux6-phase1-spine`)
3. Phase 2 — Premium shell (`ux6-phase2-shell`) — may run parallel to Phase 1 (different files)
4. Phase 3 — Component, state & copy system (`ux6-phase3-components`)
5. Phase 4 — Command layer & keyboard (`ux6-phase4-command`)
6. Phase 5 — People in meetings (`ux6-phase5-people-meetings`)
7. Phase 6 — People in tasks (`ux6-phase6-people-tasks`)
8. Phase 7 — Person profile, Today & menu bar (`ux6-phase7-daily-surfaces`)
9. Phase 8 — Cross-surface & trust (`ux6-phase8-surfaces-trust`)

---

## PROMPT 0 — Ground rules (paste once per session)

```text
You are working in MeetingScribe at ~/MeetingScribeRefactor (remote: github.com/tyleryannes94/meetingscribe-refactor, default branch main). Touch no other repo.

We are executing the UX-V6 multi-phase build. Reference docs are in docs/audit-2026-06b/:
- MASTER-PLAN-UX.md (the phased plan; item IDs like P1-1, D2-4, U3-1 are defined there)
- findings/*.md (full per-item detail with file:line evidence; the ID prefix names the file, e.g. P1-* -> findings/P1_people_meetings.md)
- BRIEFING.md (audit context)
Also relevant: docs/audit-2026-06/MASTER-PLAN.md is the PRIOR plan — where a UX-V6 item upgrades a prior-plan item (the master plan notes this), build the merged version once, not twice.
Read the plan section + the cited findings file(s) before implementing any item.

GROUND RULES for every phase:
1. Branch + PR per phase. Start: git checkout main && git pull, then create the branch I name. Commit per item. At phase end, push and open a PR; do not merge — I will.
2. Commit style: imperative, category prefix (feat:/fix:/refactor:/docs:/chore:), lowercase after prefix, subject <72 chars, optional body wrapped at 80 explaining WHY. No Co-Authored-By trailers.
3. Build verification BEFORE every commit of non-trivial Swift: swift build -c release (or make app). Warnings fine; errors block the commit. Run swift test where the area has tests; design-lint must stay clean.
4. Smoke test before opening a PR if the phase touches recording, transcription, finalize, or the vault write path: make app, install, record a short test capture, confirm transcript + summary + vault files appear. Note in the PR that you ran it.
5. Do NOT regress the capture pipeline (RecordingMonitor, MeetingPipelineController, LiveTranscriber, finalize). If an item touches those files, call it out in the PR and add/extend tests.
6. Environment: macOS 26.x Tahoe, Apple Silicon. Use /usr/bin/open in scripts (~/bin/open is a custom shim). Code-signing identity "MeetingScribe Local Signer" — rebuilds must keep the same identity so TCC permissions stick. Bundle id com.tyleryannes.MeetingScribe.
7. Scope discipline: implement ONLY the phase's listed items. Note other findings in the PR under "Found but out of scope".
8. Keep diffs reviewable. Where an item adds a design token or lint rule, the sweep and the rule land in the same PR so lint starts green.
9. STOP and ask on product decisions (copy voice, visual taste calls the findings leave open, anything that changes data on disk irreversibly).

WORKFLOW each phase: read plan + findings -> list the items -> implement item-by-item with build gating -> smoke test if required -> push branch -> open PR (checklist of item IDs, verification notes, out-of-scope findings) -> report branch, PR link, items done, anything blocked.

Confirm you've read docs/audit-2026-06b/MASTER-PLAN-UX.md before starting.
```

---

## PROMPT 1 — Phase 0: Shipping bugs & trust emergencies

```text
Phase: UX-V6 Phase 0 — Shipping bugs & trust emergencies. Branch: ux6-phase0-fixes.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md section "Phase 0" and the cited findings files (U4_nontechnical.md, P1_people_meetings.md, C1_meeting_tools.md, D5_a11y_density.md, C2_personal_crm.md, D2_visual_premium.md) for file:line detail before coding.

Implement these items (all S effort):
- U4-10: Rewrite paywall copy — it currently leaks developer instructions ("set FeatureGate.shared.isPro = true in Xcode") to end users. Replace with honest user-facing copy; no purchase flow exists yet, so say so gracefully.
- P1-6: Bulk "Add to People" (MeetingDetailHeader) must create Person records WITH the meeting link and bump lastInteractionAt, plus an undo toast.
- C1-3: Wire transcript<->audio sync — pass the AudioPlayerController at the MeetingTranscriptTab call site so the existing TranscriptSyncView tap-to-seek works. Verify by playing a recorded meeting.
- D5-2: Fix the textTertiary contrast token to meet WCAG AA at its smallest usage size, and harden the contrast unit test so it fails below 4.5:1.
- C2-12: Unify encounter logging — retire the legacy AddEncounterSheet, wire QuickEncounterSheet into PersonDetailView, and make the default path truly 1-tap (optimistic save + undo toast; fold in D3-6/U1-8 details from the findings).
- U4-4: Failure parity — when a summary fails, post a user notification and surface a retry affordance (pair with the existing ActivityLog summary-failed event).
- D2-8: Fix the nav rail person.2 icon collision between Meetings and People; apply the fill-on-select rule from D2-9's findings if trivial.

Smoke test required (C1-3 and U4-4 touch playback/pipeline-adjacent code). Follow the ground rules. Report back.
```

## PROMPT 2 — Phase 1: Identity & navigation spine

```text
Phase: UX-V6 Phase 1 — Identity & navigation spine. Branch: ux6-phase1-spine.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 1" and findings P1_people_meetings.md, P2_people_tasks.md, D1_ia_navigation.md, U2_busy_ic.md, P3_cross_surface.md.

Implement in this order:
- P1-1 (KEYSTONE): PersonResolver — one email-keyed identity layer that resolves attendee strings AND extracted task owners to Person records. Replace the six divergent parsers the findings enumerate; auto-link calendar attendees with exact-email Person matches at finalize; set ownerPersonID at extraction; add a backfill pass for existing vault data (behind a one-time migration, with tests for the "Dan"/"Daniel" substring bug and the empty follow-up-recipients bug). This merges P2-1 and P2-10 — read all three write-ups first.
- D1-3: PendingRoute mailbox on WorkspaceRouter — deterministic deep-links; delete every NotificationCenter + asyncAfter navigation hack; every notification deep-links somewhere real (folds P3-7).
- D1-1: State-bearing nav rail (correct selection semantics, restores last location per section).
- D1-2: Entity-complete back/forward history (people/notes/tasks, not just meetings).
- D1-4: Collapse the duplicate meeting surface inside the Tasks tab; route through canonical meeting detail.
- U2-1: Live-event snap — all four startRecording(for: nil) call sites attach to the currently-live calendar meeting when one exists.
- P1-4: "Who's this with?" lightweight people picker when recording starts with no calendar match (non-blocking, dismissible).
- U2-9: Auto-title ad-hoc recordings from the first transcript chunk.
- P3-1: Web hash-routes twinned 1:1 with meetingscribe:// (same path grammar both sides).

CAUTION: P1-1 touches finalize and U2-1 touches recording start — smoke test required, and add unit tests for the resolver (exact email match, display-name fallback, no-substring-match regression).

This phase is large: split into two PRs on this branch — PR A = P1-1 + tests + backfill; PR B = the routing/recording items. Follow the ground rules. Report back.
```

## PROMPT 3 — Phase 2: Premium shell

```text
Phase: UX-V6 Phase 2 — Premium shell. Branch: ux6-phase2-shell.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 2" and findings C3_premium_macos.md, D2_visual_premium.md, D3_interaction_motion.md, D5_a11y_density.md.

Implement:
- D2-1: Modular type ramp — named NDS text styles, SF Pro for UI, Bricolage reserved for display moments (merges C3-7, D5-11); sweep the ~435 raw .font(.system...) sites mechanically; add a design-lint rule banning raw system text styles.
- D2-2: Elevation token system (dark = lighter surface, not bigger shadow); replace the 12 ad-hoc shadow recipes.
- D2-3: Radius ramp (4 tokens) + nesting rule; sweep the ~103 hardcoded cornerRadius values; lint rule.
- D3-1: NDS Motion Language — token tiers (instant/quick/standard/expressive springs), reduce-motion-proof including NDS's own button styles (merges D2-11, C3-8 motion parts, D5-8); sweep the ~40 ad-hoc duration literals; lint rule.
- D2-7: Semantic NDS.recording color + designed live recording treatment; kill raw .red.
- C3-3: Native chrome & materials pass — translucent sidebar material, hidden title bar, unified toolbar, glass treatment for floating surfaces (merges D2-4). Follow the Linear/Things recipe in the findings.
- C3-4: Remove the in-rail Light/Dark toggle; follow system appearance (merges D2-10); spot-check the light palette per NotionDesign.swift:73-90.
- C3-1: App icon + brand-mark pipeline — STOP and ask me to approve the mark before wiring it through onboarding/empty states.
- C3-9: Brandize onboarding + the first-run empty states on NDS (visual only; copy voice comes in Phase 3).
- D2-9: Surface-adoption sweep — hand-rolled cards -> msCard, raw paddings -> spacing tokens.
- D2-5: Glow budget — one luminous moment per screen; remove competing glows.
- D4-7: Design-lint v2 — land the radius/semantic-color/primitive-bypass/minTap rules (folds D5-3) AFTER the sweeps so lint starts green.
- D2-12 + C3-10: Naming/identity residue cleanup (retire Notion/Untitled/Stripe naming residue; one wordmark, distinct glyphs).

Each sweep + its lint rule in the same commit. Split into 2–3 PRs by area (type/motion/tokens vs chrome/materials vs brand). Screenshots in every PR description. No smoke test needed unless you touch the record dock. Follow the ground rules. Report back.
```

## PROMPT 4 — Phase 3: Component, state & copy system

```text
Phase: UX-V6 Phase 3 — Component, state & copy system. Branch: ux6-phase3-components.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 3" and findings D4_states_consistency.md, U4_nontechnical.md, D5_a11y_density.md, D3_interaction_motion.md, U3_exec.md.

Implement:
- D4-1: MSErrorState component + ErrorPresenter layer with three plain-language fields (what happened / why / what to do) — merges U4-3. Raw whisper-cli stderr must never reach the transcript tab again.
- D4-2: Empty-state system v2 — one visual signature (uses the Phase-2 brand mark), filtered-empty variants, replace all 9 bespoke empty states (fix MeetingsView using the People icon).
- D4-9: Skeleton standards — shaped placeholders, labeled spinners; replace bare ProgressView()s on primary surfaces.
- D4-5: MSSheet adaptive container (merges D5-4) — one sheet anatomy; migrate the 11+ fixed-frame sheets.
- D4-3: TaskMetaCluster — one task row rendering used by list/board/table/gallery/Today/person surfaces; fix the ActionItemsTableView 80pt/96pt misalignment.
- D4-10: MSFilterChip with counts.
- D3-10: .ndsHover(_:) hover/press standard; replace the 15 bespoke hover implementations.
- D3-12: Toast v2 (stacking, hover-pause, action affordance).
- U3-11: Replace NSAlert.runModal confirmations with NDS toasts/dialogs.
- D4-6: Copy voice guide + entity-name decree — merges U4-1's jargon word-map and P3-12's lexicon. STOP first and ask me to ratify the word-map (vault -> ?, Ollama -> ?, "task" everywhere), then sweep user-facing strings and add the lint jargon rule. This also unblocks held item 1E from the prior plan.
- D4-8: Designed "no selection" panes.
- D5-5: Semantic rows — Button-ify onTapGesture rows, combined a11y elements, heading rotor.
- D5-10: AttendeeChip legible "in People" state + real hit target.

Split into 2–3 PRs (states/components vs sheets/rows vs copy sweep). Screenshots in PRs. Follow the ground rules. Report back.
```

## PROMPT 5 — Phase 4: Command layer & keyboard

```text
Phase: UX-V6 Phase 4 — Command layer & keyboard. Branch: ux6-phase4-command.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 4" and findings C3_premium_macos.md, D3_interaction_motion.md, D1_ia_navigation.md, U2_busy_ic.md, U4_nontechnical.md.

Implement:
- C3-2: Rebuild Cmd-K as a floating, blurred, spring-in command palette with verbs + entities + per-result actions (merges D3-4 — read both specs; this is also the premium realization of prior-plan 2A's quick-switcher, build once).
- D1-8: One query engine — palette, GlobalSearchView, web /api/search, and MCP all call the FTS5 hybrid search; add the search-escalation row ("Search everything for ...").
- U2-3: Matched-context snippets in results (merges U4-5 — also apply to GlobalSearchView and web results).
- U2-2: Query carry-through — opening a result lands in the transcript with the query pre-highlighted and find-bar populated.
- U2-10: Search qualifiers (with:@person, before:/after:, in:transcripts|notes|tasks) — depends on PersonResolver from Phase 1.
- C1-7: In-transcript find with match counter + Enter/Shift-Enter cycling.
- D3-8: Unified keyboard model — j/k + arrows in every list, single-key actions where focused (merges C2-11, C3-11), plus a "?" shortcut overlay.
- U2-4: Keyboard-first action-item triage (complete/defer/assign/delete from the keyboard).
- D3-3: NSUndoManager bridge for the stores — Cmd-Z works for task edits, encounter logs, person edits.
- D3-2: One-click task completion with a celebration micro-beat (motion tokens from Phase 2).
- U2-5: Global Quick Entry window (Things-style), live-meeting aware; include U2-6 (capture line in the record dock) and U2-7 (explicit dictation destination + "note to self" mode).
- D1-10: Directional section transitions.
- D1-5 (LAST, and only if the phase isn't already too big — otherwise note as deferred): universal entity Peek preview on space-bar/hover.

Split into 2–3 PRs (palette+search vs keyboard+undo vs quick entry). Follow the ground rules. Report back.
```

## PROMPT 6 — Phase 5: People in meetings

```text
Phase: UX-V6 Phase 5 — People in meetings. Branch: ux6-phase5-people-meetings.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 5" and findings P1_people_meetings.md, C1_meeting_tools.md, U1_manager.md, U3_exec.md, D1_ia_navigation.md, P2_people_tasks.md.

Prerequisite: Phase 1's PersonResolver is merged.

Implement:
- U1-10: Persist briefs to disk + pre-warm before meetings; add the U3-12 LLM right-of-way policy (user-visible surfaces never wait on a cold Ollama call).
- C1-1: Brief-as-hero — prep greets you on the meeting view before/at start; rename/restructure the "Transcript" tab placement per the findings.
- U3-9: People-first brief content — shared history, open loops "between you and X" (merges U1-7, P2-5).
- P1-2: "Who's here" people rail in meeting detail — health, last-met, open commitments per attendee; include P1-11 "mentioned, not present" chips.
- P1-5: Shared-history strip ("3rd meeting with Jane this quarter").
- P1-7: Face piles on meeting rows (Today, Meetings list, MeetingCard).
- D1-6: Series spine — recurring meetings as a first-class thread with prev/next; bind series <-> person for 1:1s (merges C1-4, U1-2).
- U1-6: Commitment carry-forward on series finalize.
- U1-1: "Your 1:1 Day" person-first rail on Today.
- U1-5: "Discuss next time" talking-points inbox per person, surfaced in the brief (merges P2-4).
- P1-3: Speaker->person mapping ("This is Jane") with per-meeting sidecar; person-attributed talk-time + action items.
- P1-8: Person-aware follow-up composer (merges P2-7).
- P1-9: Recorded meetings emit encounters (one interaction stream).
- P1-10: Inject person context into meeting Ask-AI + brief synthesis.
- C1-2: "Mark moment" in-call highlight -> pinned summary anchors; add C1-10 time-remaining/overrun cue on the dock.
- P1-12: Live per-person quick-capture while recording.
- U3-5: External/internal meeting awareness from attendee domains.

CAUTION: P1-9 and finalize-adjacent items require the smoke test. This is the biggest phase — split into 3 PRs: (A) briefs, (B) people rail + series + 1:1, (C) in-call + speakers. Follow the ground rules. Report back.
```

## PROMPT 7 — Phase 6: People in tasks

```text
Phase: UX-V6 Phase 6 — People in tasks. Branch: ux6-phase6-people-tasks.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 6" and findings P2_people_tasks.md, U2_busy_ic.md, C1_meeting_tools.md, U1_manager.md.

Prerequisites: PersonResolver (Phase 1), TaskMetaCluster (Phase 3), keyboard triage (Phase 4).

Implement:
- P2-2: People facet in the Tasks IA — sidebar People section + person-scoped task views (TaskQuery.Scope.person already exists).
- P2-3: Owner chips navigate everywhere via EntityLink; include P2-11 (person chips in Needs Attention + "owed to people" Today lens), P2-12 (open-commitment counts on people surfaces), U1-9 (attendee chips navigate-first).
- P2-8: @person and >person tokens in TaskQuickAddParser (merges U2-8), resolving through PersonResolver with autocomplete.
- P2-9: Attendee-first assignment in the meeting Actions tab (the people in the room are the likely owners).
- P2-6: Waiting-on lifecycle — flip captureDelegatedTasks default to true, age waiting-on items, one-click person-addressed nudge (draft via the Phase-5 follow-up composer).
- C1-11: Forward-looking person header on meeting detail — "Next with Priya" + open loops.

One PR. Follow the ground rules. Report back.
```

## PROMPT 8 — Phase 7: Person profile, Today & menu bar

```text
Phase: UX-V6 Phase 7 — Person profile, Today & menu bar. Branch: ux6-phase7-daily-surfaces.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 7" and findings C2_personal_crm.md, D5_a11y_density.md, U1_manager.md, U3_exec.md, D2_visual_premium.md, D1_ia_navigation.md, D4_states_consistency.md, C3_premium_macos.md.

NOTE: C2-1 is gated on the prior plan's PersonDetailView decomposition (2,356 LOC). If that hasn't landed yet, do the decomposition first as its own PR per docs/audit-2026-06/MASTER-PLAN.md 2G, then build on it.

Implement:
- C2-1: Unified "Story" timeline as the person profile's default tab (encounters + meetings + notes + decisions, one stream).
- C2-3: Health "why" popover + trend arrow + next-best action.
- C2-4: Reconnect-with-context — last-topic snippet + local Ollama message draft.
- C2-2: Keep-in-touch kanban by health band as a People list mode.
- C2-10: Health-ring avatars across people surfaces; include C2-7 (de-emoji: typed glyph + color chips) and C2-9 ("Known for 3 years" line + first-met).
- C2-6: Mood as a first-class field (kill the [mood:x] string), mood-tinted heat map + trendline.
- D5-7: Identity pane — adaptive width, 3-zone calm layout; include D5-9 (meeting header 8 rows -> 3, hover-reveal edit chrome).
- U1-4: Deterministic per-person evidence compiler (perf-review view); include U1-11 ("My Team" pinned smart group + work-aware types).
- D5-1: Today, calm by default — 15 sections -> 4 modules + a "More" shelf; one section-header + row spec (merges D2-6, D1-7, D4-11); merge the two drifting-people modules into one health-scored module (D4-4).
- U3-3: "Day shape" strip atop Today.
- U3-2: Turnaround card (the 30-seconds-between-meetings bridge).
- U3-4: One-line outcome per meeting on every list surface.
- U3-1: Menu-bar next-meeting intelligence — countdown, prep card, live recording state (merges C3-6, P3-11).
- U3-6: Weekly Ledger with copy-as-update; include U3-10 (attributed quote bank).

Split into 3 PRs: (A) person profile, (B) Today redesign, (C) menu bar + weekly ledger. Screenshots in every PR. Follow the ground rules. Report back.
```

## PROMPT 9 — Phase 8: Cross-surface coherence & trust

```text
Phase: UX-V6 Phase 8 — Cross-surface & trust. Branch: ux6-phase8-surfaces-trust.

Read docs/audit-2026-06b/MASTER-PLAN-UX.md "Phase 8" and findings P3_cross_surface.md, D1_ia_navigation.md, U3_exec.md, U4_nontechnical.md, D5_a11y_density.md, C3_premium_macos.md, C1_meeting_tools.md, D3_interaction_motion.md.

Implement:
- P3-2: One canonical IA — same sections, order, names, glyphs on desktop and web (merges D1-9).
- P3-3: Live Mac recording status + remote stop on the phone.
- P3-4: Phone Today = pocket schedule (next meeting + its humans, merges U3-7); U3-8 read-first person dossier (edit behind a pencil).
- P3-6: Citations that navigate on every surface (web + MCP answers deep-link via the twinned routes).
- P3-8: Phone quick capture into _inbox/ (notes, tasks, encounters — works with the app closed).
- P3-9: "Send to phone" / "Open on Mac" handoff affordances.
- P3-10: MCP parity — projects + the Today aggregate.
- D5-6: Tabbed, plain-language Settings with an Advanced basement (merges C3-5, U4-2).
- U4-6: Trust Center — one "Your data" room including Delete-this-conversation (UI over the prior plan's 2G purge work; if 2G purge hasn't landed, STOP and ask whether to build the purge now or stub it); include U4-7 per-client consent tracking and C1-9 transcript trim/redact.
- U4-9: Capability-aware UI — never advertise what can't work yet; include U4-8 (sidebar identity fixes) and U4-11 (first-summary "here's what just happened" recap).
- C1-5: Saved Views as tabs on Meetings + Tasks; include C1-6 (Copy for Slack / Copy as email split button), C1-8 (meeting-type summary templates), C1-12 (edit-summary-by-asking chips).
- D3-5: Drop-target choreography for board/list drag-drop; include D3-7 (numeric content transitions), D3-9 (FloatingOverlay lifecycle animation), D3-11 (inline mention/slash popover replacing NSMenu).

Split into 3 PRs: (A) web/mobile + MCP, (B) settings + trust center, (C) meetings/tasks long-tail polish. Smoke test for (B) if the purge path is built. Follow the ground rules. Report back.
```

---

## Reusable snippets

**PR description template**

```text
## UX-V6 <Phase name> (<PR letter if split>)
Items completed: [ ] <ID> ... (checklist)
Plan refs: docs/audit-2026-06b/MASTER-PLAN-UX.md + findings/<files>.md
### Verification
- swift build -c release: PASS · swift test: PASS (<n> tests) · design-lint: clean
- Smoke test (record -> transcript -> summary -> vault): PASS / N/A
- Screenshots: <attached for visual changes>
### Found but out of scope
- <...>
### Risk notes
- <feature flags, migrations, pipeline-adjacent files touched>
```

**Smoke-test checklist**

```text
1. make app && make install (or the repo's install path); confirm /Applications/MeetingScribe.app version == HEAD.
2. Launch; confirm no TCC re-prompts (signing identity unchanged).
3. Start a recording from the menu bar; speak ~30s with system audio playing; stop.
4. Confirm: live transcript appeared; final transcript has the last sentence; summary generates; meeting folder + markdown written to the vault; person auto-link fired if a calendar event was live.
5. Open the meeting in the app and on the phone web app; confirm parity.
```

**"You're stuck" rescue prompt**

```text
You seem blocked. (1) Commit what compiles. (2) Summarize the failure (error + file:line) and what you tried. (3) Give 2 options with trade-offs. (4) Recommend one and wait. Don't force a change that breaks the build or the capture pipeline.
```
