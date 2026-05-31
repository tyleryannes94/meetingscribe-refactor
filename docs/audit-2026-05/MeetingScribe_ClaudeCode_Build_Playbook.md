# MeetingScribe — Claude Code Build Playbook

Copy-paste prompts to have Claude Code build out everything we scoped: the **UX Quick-Wins** plan and **Master Plan V4** (Phases 0–7).

## How to use this doc
- Run **one prompt per Claude Code session**, in the order below. Don't paste the next prompt until the current phase's PR is open and green.
- **Paste PROMPT 0 first** (once). It sets the ground rules. Optionally append it to `~/MeetingScribeRefactor/CLAUDE.md` so every session inherits it.
- Each numbered prompt is a self-contained block — copy everything between the `===== COPY =====` markers.
- Reference detail for every item ID (e.g. `E3-1`, `UX2-1`) lives in the repo at `docs/audit-2026-05/` (already placed): `MASTER_PLAN_V4.md`, `UX_QUICKWINS_PLAN.md`, and the `findings/` + `ux-findings/` folders with full `file:line` evidence.

## Build order (decided)
1. **PROMPT 1 — V4 Phase 0** (critical data-integrity & trust — pulled first)
2. **PROMPT 2 — Quick-Wins Phase A** (connect + click budget; the 4 anchors)
3. **PROMPT 3 — Quick-Wins Phase B** (polish + small features)
4. **PROMPT 4 — V4 Phase 1** (finish requirements, nav, first-run)
5. **PROMPT 5 — V4 Phase 2** (recall moat)
6. **PROMPT 6 — V4 Phase 3** (proactive / retention)
7. **PROMPT 7 — V4 Phase 4** (integrations & workflow)
8. **PROMPT 8 — V4 Phase 5** (AI stack upgrade)
9. **PROMPT 9 — V4 Phase 6** (architecture hardening)
10. **PROMPT 10 — V4 Phase 7** (positioning / monetization — optional)

Git model: **one branch + one PR per phase.** Commit per item; push and open the PR at phase end.

---

## PROMPT 0 — Ground rules (paste once at the start, or add to CLAUDE.md)

```text
You are working in the MeetingScribe repo at ~/MeetingScribeRefactor (remote: tyleryannes94/meetingscribe-refactor, default branch main). NEVER touch ~/MeetingScribe or the `frost` repo.

We are executing a multi-phase build. Reference docs are in docs/audit-2026-05/:
- MASTER_PLAN_V4.md and UX_QUICKWINS_PLAN.md (the plans)
- findings/*.md and ux-findings/*.md (full per-item detail with file:line evidence)
Read the relevant plan + findings file before implementing any item. Item IDs (e.g. E3-1, UX2-1) map to those files.

GROUND RULES for every phase:
1. Branch + PR per phase. Start each phase by: git checkout main, git pull, then git checkout -b <branch name I give you>. Commit after each item (or tight group of items) with a clear message. At phase end, push and open a PR; do not merge — I will.
2. Commit message style (from CLAUDE.md): subject line imperative, category prefix (feat:/fix:/refactor:/docs:/chore:), under 72 chars. Optional body wrapped at 80 explaining WHY. No Co-Authored-By or trailers.
3. Build verification BEFORE every commit of non-trivial Swift: run `swift build -c release` (or `make app`). Warnings are fine; errors block the commit. If it doesn't compile, fix it before committing.
4. Smoke test before opening the PR (where the phase touches capture/UI): `make app`, launch, record a ~30s meeting, stop, confirm transcript + summary + notification fire and nothing is lost. Note in the PR that you ran it (or that the phase doesn't touch those paths).
5. Do NOT regress the capture→transcribe→summarize→persist pipeline. If an item would touch MeetingManager / MeetingPipelineController / LiveTranscriber / WhisperRunner / VaultMigrationManager, call it out and proceed carefully with tests.
6. Environment: macOS 26 / Apple Silicon. Use /usr/bin/open directly in any script (the user's ~/bin/open has a frost shortcut). Code-signing identity is "MeetingScribe Local Signer"; bundle id com.tyleryannes.MeetingScribe. Rebuilds must not break TCC permissions.
7. Scope discipline: implement ONLY the items listed for the current phase. If you discover an out-of-scope bug, note it in the PR description under "Found but out of scope" — don't fix it now.
8. Keep changes low-risk and reviewable. Prefer small, focused diffs. Add or update tests for any data-integrity or parsing change.
9. After installing locally, verify the installed app matches HEAD:
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/MeetingScribe.app/Contents/Info.plist)" = "$(git -C ~/MeetingScribeRefactor rev-parse --short HEAD)" ] && echo MATCH || echo MISMATCH

WORKFLOW each phase: read plan+findings → make a short task list of the phase's items → implement item-by-item with build gating → smoke test → push branch → open PR with a checklist of items done, test notes, and any "out of scope" findings → report back to me with the branch name, PR link, items completed, and anything you couldn't do.

Confirm you understand and have read docs/audit-2026-05/MASTER_PLAN_V4.md and UX_QUICKWINS_PLAN.md before starting Phase 0.
```

---

## PROMPT 1 — V4 Phase 0: Critical correctness, data integrity & trust

```text
Phase: V4 Phase 0 (do this first). Branch: fix/v4-phase0-data-integrity.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 0" and the cited findings files (findings/G3_eng_reliability.md, G3_eng_security.md, G3_eng_testing.md, G4_user_ic.md, G5_comp_localfirst.md, G4_user_consultant.md) for full file:line detail before coding.

Implement these items (each is small but high-stakes):
- E3-1 (CRITICAL): Gate the ScribeCore daemon recording path behind an OFF-by-default flag so recording cannot silently route to the daemon and lose a meeting. If feasible, also fix the path (write meeting.json, wire live transcription, call finalize()). At minimum: make it impossible to lose a meeting via the daemon by default. Confirm the login-item auto-registration (MeetingScribeApp.swift ~152, Makefile) respects the flag.
- E1-10: Close the recording-state TOCTOU race by adding .starting/.stopping transient states and claiming them synchronously.
- E4-3: Add a network egress allowlist + a guard that refuses/ warns if the configured Ollama endpoint leaves localhost (the user-settable ollamaURL can currently ship transcripts off-device over HTTP).
- E4-1: Add a vault-containment guard on ALL write paths (especially the write-capable MCP tools) so a meeting's relativeFolderPath cannot escape the vault (path traversal).
- U1-2: Fix the hardcoded-"me" ownership filter in ActionItemExtractor.swift (~line 27); make the owner-match profile-driven (AppSettings.userName) + aliasable.
- C3-1: Fix the canonical markdown writer so finalize writes the Obsidian-native file (people, wikilinks, real frontmatter) instead of the lossy writeMarkdownFile; this also fixes the bug where the folder month (e.g. "2026-05") is scraped in as a tag.
- U4-3: Add a redaction/"what's included" confirmation before any meeting share/export (combinedMarkdown currently dumps private notes + full transcript with no guard).
- E3-4: Add a SQLite quick_check on open + auto-rebuild path so a bad shutdown can't silently empty the People graph.
- E5-7: Fix clean-reinstall.sh so it targets ~/MeetingScribeRefactor (it currently rebuilds from the old ~/MeetingScribe at ~line 21) and assert the git remote is meetingscribe-refactor.

Then stand up the test floor that protects all of the above:
- E5-2: An end-to-end pipeline integration harness (record fixture → transcribe → repair gate → vault write) that fails on a truncated/partial transcript.
- E5-1: A golden-audio transcription regression suite with a small committed fixture.

Follow the ground rules. Build + run the new tests + smoke test before the PR. In the PR, explicitly confirm: (a) the daemon can no longer silently lose a meeting by default, and (b) the egress guard blocks a non-localhost Ollama URL. Report back.
```

---

## PROMPT 2 — Quick-Wins Phase A: Connect everything & hit the click budget

```text
Phase: Quick-Wins Phase A. Branch: feat/quickwins-A-connect.

Read docs/audit-2026-05/UX_QUICKWINS_PLAN.md "Phase A" and the cited ux-findings files (UX02_meetings.md, UX03_people.md, UX04_tasks.md, UX08_notifications_followup.md, UX10_editing_quickadd.md) for file:line detail.

This phase delivers the 4 mandatory anchors and the items that realize them. Use the 3-click / 2-click rule as the acceptance test.

The 4 anchors:
- UX-A (3-click/2-click): every page/action in a tab reachable in <=3 clicks; after opening a person or meeting, every necessary action <=2 clicks. Express this by fixing the worst violations: A7, A8, A3, and Settings reachability (handled in Phase B).
- UX-B (Tasks fluidity): initiatives <-> projects <-> pages <-> tasks connected, not siloed. Realize via A3, A4, A5, A6.
- FEAT-A (email+people -> CRM): from a meeting attendee row, one click to open OR create a CRM Person; make contact rows actionable; "Add to People + link" from attendee/owner chips. Realize via A1, A2, FT10-4.
- FEAT-B (People multi-select + front bulk tagging): add a selection model + bulk-action bar to the People list; primary bulk action = apply/create a tag across the selection; add a tag-management mini-UI (rename/recolor/delete/merge — the PeopleTagStore methods already exist but have no UI).

Implement these specific items:
- A1 = UX2-1 / UX2-2: attendee chips become one-click buttons (open/add Person; "Add all attendees to People").
- A2 = UX3-1: contact rows (email/phone/address) actionable — mailto/tel/copy.
- A3 = UX4-1: a task's "From meeting" chip becomes clickable (meetingID already present; dead Text today at TaskPageView.swift ~176).
- A4 = FT4-1: a "Linked items" block on every task/page (meetings, people, related tasks).
- A5 = FT4-3 / FT4-2: one-click "Create task from this meeting" + link existing task to a meeting; link a task owner to a CRM Person.
- A6 = UX4-2 / UX4-3: drag-to-reparent pages in the rail (setProjectParent exists); full breadcrumb trail on every page.
- A7 = UX2-5: lift Reveal-in-Finder / Export / Recover out of the triple-nested overflow into the detail header.
- A8 = UX3-4: bring Encounter + Relationship "Add" onto the identity panel.
- A9 = UX8-5 / D1-5: make cross-entity links clickable everywhere (PersonDetail "In your recordings" rows; "Needs attention" rows deep-link instead of dumping to the tab).
- A10 = FT2-1 / D1-2: "Copy link to this meeting" (meetingscribe://meeting/<id>) and register the URL scheme + onOpenURL so the links resolve.
- FEAT-A/B as described above.

Follow the ground rules. For each surface you touch, verify the relevant 3-click/2-click target is met and note the before->after click count in the PR. Build + smoke test. Report back.
```

---

## PROMPT 3 — Quick-Wins Phase B: Polish pass & small features

```text
Phase: Quick-Wins Phase B. Branch: feat/quickwins-B-polish.

Read docs/audit-2026-05/UX_QUICKWINS_PLAN.md "Phase B" and the cited ux-findings files (UX01, UX05, UX06, UX07, UX09, UX10) for detail. All items are S or small-M. Implement grouped by area:

B1 Navigation & home:
- UX1-2: reset Today's pushed meeting-detail on tab switch / Cmd-1..5 (Today must return home).
- UX1-1: wire the already-built calendarLink (TodayView.swift ~224, never rendered) and fix stale "Calendar tab" empty-state copy.
- FT1-2 / FT5-4: recently-visited + pinned entities as a quick-switch row in the rail / Cmd-K.
- FT1-3: persist last-opened meeting + scroll so Today restores context.

B2 Lists, empty states & keyboard consistency:
- UX9-1: actionable empty states everywhere (use ContentUnavailableView); Meetings & Tasks are dead today.
- UX9-3 / FT9-4: give the Meetings list the same List(selection:) model as the other lists (arrow keys, Enter, delete).
- UX9-2: collapse the two parallel primary-button systems into one.
- UX9-4 / FT9-1: one shared search field (placement, clear-X, Esc-to-clear) + Cmd-F focuses the current tab's search.
- FT9-3: inline Undo toast after destructive list actions.
- FT9-2: loading skeleton/label instead of bare spinners.

B3 Editing & quick-add:
- UX10-2: auto-focus + select the title on every "create" (no @FocusState anywhere today).
- UX10-3: autosave title/name fields on blur, not only on Enter.
- UX10-4: auto-focus the New tag / label / section fields when their UI opens.
- UX10-1: finish PPL-1 — bring phone/email/tag editing inline so AddPersonSheet isn't needed for a one-field fix.
- FT10-1 / FT10-3: quick-add bar (title + Enter, no detail) with smart defaults from context.

B4 Recording in the moment:
- UX6-1: persistent meeting-recording HUD (reuse the existing RecordingPill/FloatingOverlay that voice notes have).
- FT6-3: live audio-level / silence indicator during meeting recording.
- FT6-2 / UX6-5: one global "record meeting" hotkey (parity with F5) + surface hotkeys where used.
- FT6-4: "Add marker/bookmark" during recording.

B5 Notifications & follow-up:
- UX8-1 / UX8-2: make the "Meeting ready" notification actionable (Review / Draft follow-up + a Meeting payload).
- UX8-3 / FT8-4: follow-up "sent/copied" state + a "pending follow-ups" Today widget.
- FT8-2: auto-draft the follow-up the moment a summary completes (reuse the onComplete hook).
- FT8-5 / FT8-1: detection status chip ("You're in a Zoom call · Record") + "Snooze 5 min" on the meeting-start notification.
- FT8-3: make the Slack follow-up channel actually deliver, or label it "copy only".

B6 Settings & search (mostly dead-code activation):
- UX7-4: ship the already-built IntegrationsView in place of the inferior flat-Form connector duplicate (mostly deletion).
- FT7-1: "what's connected/working" health strip at the top of Settings + a rail dot.
- FT7-4 / UX7-1: Settings search / quick-jump over the 13-section flat scroll.
- UX7-2 / UX7-3: "Reopen MeetingScribe" relaunch button + a "re-run setup" path.
- UX5-1 / FT5-2: inline actions on search results + a command-palette slice of Cmd-K.
- UX5-4 / UX5-5: context-aware chat starter prompts + advertise Chat's write actions in its empty state.

Follow the ground rules. Build + smoke test. This phase is large — if it's getting unwieldy, split into PRs by area (B1-B3 and B4-B6) on the same branch. Report back.
```

---

## PROMPT 4 — V4 Phase 1: Finish requirements, navigation & first-run

```text
Phase: V4 Phase 1. Branch: feat/v4-phase1-nav-firstrun.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 1" and cited findings (G1_design_ia_nav.md, G1_design_onboarding.md, G1_design_accessibility.md, G4_user_nontechnical.md, G4_user_ic.md). Note: some Cmd-K / deep-link / clickable-link work may already be done in Quick-Wins A — reconcile, don't duplicate.

Implement:
- Existing-plan closeouts: NAV-1/2/5 (kill remaining expand/collapse in Today + Calendar -> click-into detail; resolve the orphaned Calendar view), LAY-1/2 (remove 720/920 width caps; chat rail closed by default), PPL-1 (inline person editing — if not finished in QW-B), DEF-1/3 (default Meetings scope = upcoming + persist via AppStorage; promote Draft-follow-up), TDY-1/2 (Today "up next" + "needs attention").
- D1-1: one canonical entity router with a per-tab NavigationPath (collapse the 4 ways a meeting opens into one; remove the asyncAfter(0.18) hack).
- D1-2 / D1-5: ensure meetingscribe:// + onOpenURL and bidirectional clickable person<->meeting<->task links are complete (may be partly done in QW-A).
- U5-1: a no-Terminal signed .dmg installer (double-click, drag-to-Applications).
- U5-2 / D3-1: an in-app "Getting things ready" Setup Check that downloads the whisper model + starts Ollama in-GUI with progress (never a shell command; today a non-CLI user hits a raw brew error in OllamaService.swift ~34).
- D3-3: a bundled sample/demo meeting so first value arrives in zero clicks.
- D3-6 / U5-7: Screen-Recording grant auto-detection + a real "Reopen MeetingScribe" relaunch helper.
- U1-1: first-class "Push to Linear" button on every task (createLinearIssue already exists at TaskSyncService.swift ~202).
- D5-1: reduce-motion compliance pass (remove always-on repeatForever / symbolEffect(.pulse)).
- D5-2 / U5-4: Dynamic Type + VoiceOver + larger-text pass (192 fixed font sizes today); do alongside LAY-1 so enlarged text reflows.
- D4-1: single global record toggle + persistent recording HUD (reconcile with QW-B UX6-1).
- D2-3: unify the accent color to brand purple.

Follow the ground rules. The .dmg installer (U5-1) is the largest item — if needed, land it as its own PR on this branch. Build + smoke test. Report back.
```

---

## PROMPT 5 — V4 Phase 2: The recall moat

```text
Phase: V4 Phase 2 (highest strategic value). Branch: feat/v4-phase2-recall.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 2" and cited findings (G5_comp_secondbrain.md, G5_comp_notetakers.md, G5_comp_personalai.md, G2_pm_roadmap.md, G4_user_manager.md, G5_comp_infra.md). Depends on Phase 0 correctness fixes being merged.

Implement in this order (each builds on the last):
- C2-1: re-wire the EXISTING FTS5 engine (SecondBrainDB.swift ~269) into global search instead of the in-memory contains() fallback (WorkspaceIndex.swift ~106); fix the stale-index bug that caused the revert. Add on-device embeddings (C5-10) for hybrid semantic recall.
- C1-1 / C2-2 / C4-1 / P1-7: "Ask your vault" — local RAG over all meetings with citations, built into the existing Ollama Chat. Cross-meeting Q&A with source links.
- P1-1 / C1-11 / C2-8: Decision & Commitment Ledger — extract decisions + commitments ("who owes what, by when") into a structured, queryable cross-meeting layer.
- U2-1: unified person timeline (recorded meetings + UNRECORDED calendar meetings + messages). Today PersonDetailView ~514 only shows recordings, so a manager's 1:1s read empty.
- P2-1: make lastInteractionAt truthful — derive from all signals + add per-person cadence.
- P1-3 / P1-2: synthesized, series-aware pre-meeting brief (seriesID exists but does nothing; carry forward unresolved commitments).
- C2-3: automatic bidirectional entity links (real backlinks, not URL scans).
- C3-2: write per-person People/*.md so wikilinks resolve and the graph renders in Obsidian.
- C2-4 / C3-3: a Daily Note temporal spine; append each meeting into Daily/YYYY-MM-DD.md.
- C2-9 / C2-6: temporal recall ("On this day", topic timelines) + proactive resurfacing.

This is a large phase. Land it as multiple PRs on this branch, one per major item (start with C2-1 as the on-ramp). Add tests for the RAG retrieval and the ledger extraction. Build + smoke test. Report back after each major PR.
```

---

## PROMPT 6 — V4 Phase 3: Proactive intelligence & retention

```text
Phase: V4 Phase 3. Branch: feat/v4-phase3-proactive.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 3" and cited findings (G2_pm_retention.md, G4_user_founder.md, G4_user_ic.md, G4_user_manager.md, G1_design_interaction.md, G2_pm_metrics.md). Depends on Phase 2 (brief + commitments) where noted.

Implement:
- P2-2: push the synthesized pre-meeting brief into the meeting-start notification.
- U3-1 / P1-9: auto-record the in-progress calendar event (consent-aware) by joining the existing Zoom/Meet detector to the calendar.
- P2-5 / P2-3: morning brief notification + generated daily/weekly recap with a real Weekly Review ritual.
- P2-6 / U3-3: follow-up lifecycle — track "sent" state and resurface forgotten ones (reconcile with QW-B UX8-3).
- U3-2 / P2-7: an "Owe / Owed" board (delegation + commitments-to-people; owner field exists).
- U1-4 / U2-2 / U3-4: persona digests — Standup Mode (60s yesterday/today/blockers), per-report 1:1 prep digest, person dossier in the brief.
- U3-5: between-meeting summary push with deep links.
- D4-2: turn Cmd-K into a real command palette (reconcile with QW-B FT5-2 — extend, don't duplicate).
- P5-3: summary thumbs up/down with local "why" capture that steers regeneration (reconcile with QW-A FT2-2).
- P5-1 / P1-4: opt-in, local-only MetricsStore (default off, never uploaded) so the four KPIs become measurable.
- P5-6: one-click self-diagnostics "Run a health check" (whisper/Ollama/permissions/disk).
- D4-3: universal undo (toast + UndoManager) for vault-mutating actions (reconcile with QW-B FT9-3).

Follow the ground rules. Be careful: U3-1 (auto-record) touches capture — gate it behind explicit consent and test that it can't double-record or lose the manual path. Build + smoke test. Report back.
```

---

## PROMPT 7 — V4 Phase 4: Platform, integrations & workflow

```text
Phase: V4 Phase 4. Branch: feat/v4-phase4-integrations.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 4" and cited findings (G2_pm_workflows.md, G5_comp_infra.md, G5_comp_secondbrain.md, G4_user_consultant.md, G5_comp_localfirst.md).

Implement (independent items — land as separate PRs on this branch):
- P4-1: Calendar write-back (schedule next meeting; "notes ready" on the event) via EventKit write.
- P4-3: real Slack delivery + capture (Slack app + bot token), replacing the fake copy-only channel (reconcile with QW-B FT8-3).
- P4-4 / P4-5: a local "when X then Y" automation rules engine + webhook in/out sink.
- P4-9 / P4-7: a public local HTTP API + OpenAPI, and a Raycast/Alfred extension.
- C5-7 / C5-8 / C2-10 / C5-9: publish the MCP server to the official registry as a "personal memory backend"; add a streamable-HTTP transport; expose semantic-search + graph traversal + elicitation for human-in-the-loop writes.
- U4-1: a first-class Client/Workspace entity above tags (tags are flat metadata today; desiredDirectory ignores them).
- U4-4 / U4-5: billable-time capture + per-client invoice-ready timesheet (timestamps already on Meeting).
- C3-4/5/6/7/8: Obsidian companion suite — "Open vault in Obsidian", Bases-ready frontmatter + starter .base, a vault/_plugins/ post-finalize hook, round-trip import of hand-edited markdown, an EXPORT.md portability manifest.
- P4-6 / P4-8: generalize _inbox capture beyond iPhone (email/desktop/clipboard); a CRM bridge for the People graph (HubSpot/Attio).

Follow the ground rules. Each integration should fail gracefully when not configured. Add tests for the rules engine and the HTTP API. Build + smoke test. Report back per PR.
```

---

## PROMPT 8 — V4 Phase 5: AI stack upgrade & best-in-class transcription

```text
Phase: V4 Phase 5. Branch: feat/v4-phase5-ai-stack.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 5" and findings/G5_comp_infra.md + G3_eng_performance.md for the full rationale and benchmarks. This touches the core capture/transcription path — gate everything behind feature flags, keep whisper.cpp as a working fallback, and smoke-test heavily.

Implement (separate PRs on this branch, in this order):
- C5-1 / E2-1: adopt Apple SpeechAnalyzer/WhisperKit (CoreML/ANE) as the default STT with whisper.cpp as fallback; add a persistent whisper warm-pool to kill the per-chunk model cold-load (~36 reloads per 90-min meeting). Keep the ENG-A repair gate intact across the new path.
- C5-2: real diarization via FluidAudio (CoreML/ANE) so the planned speaker-labeled transcript/summary actually works.
- C5-11 / D5-6: live streaming captions during the meeting; surface as a Live Caption Mode accessibility feature.
- C5-4: streaming summarization with live token rendering.
- C5-5 / C5-6 / C5-3: a native MLX summarization backend + optional Apple Foundation Models (zero-dependency) tier + a hardware-aware model picker.
- E2-2 / E2-3 / E2-7: a ResourceGovernor (low-power/thermal adaptive; defer live transcription to batch-on-stop on battery) + a built-in perf/energy profiling harness.
- E2-5 / E2-10: thumbnail downsampling + decoded-image cache for people photos; coalesce live-transcript re-renders.

Follow the ground rules. For C5-1 specifically: run the golden-audio regression suite (from Phase 0) and confirm transcription quality does not regress vs whisper.cpp before defaulting to the new engine. Build + extended smoke test (record a multi-minute meeting on battery). Report back per PR.
```

---

## PROMPT 9 — V4 Phase 6: Architecture hardening & maintainability

```text
Phase: V4 Phase 6. Branch: refactor/v4-phase6-hardening.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 6" and findings/G3_eng_architecture.md, G3_eng_reliability.md, G3_eng_testing.md, G1_design_visual_system.md. Pure internal hardening — behavior should not change; tests must stay green throughout.

Implement (separate PRs on this branch):
- E1-1: a Services domain layer + constructor injection behind protocols (today AppSettings.shared x165, MeetingManager hard-news all deps).
- E1-2: ship a real VaultFileStore and route both the app and the MCP server through it (eliminate the dual write paths).
- E1-7 / E1-4: a typed, versioned ScribeBridge IPC contract; unify logging/error/settings as VaultKit protocols and delete CompatShim + the daemon's forked AppSettings.
- ARCH-1 / ARCH-3: CaptureKit extraction (retire app<->daemon duplication — 12 files have diverged; follow docs/REMAINING_WORK.md section 1); decompose god-files (PeopleStore, PersonDetailView, MCP main.swift); two-binary activation per docs/REMAINING_WORK.md section 2 — keep the ENG-A repair gate working across the XPC/Darwin boundary.
- E4-5 / U3-9: vault encryption at rest + a sensitive-meeting mode.
- E5-3/4/5/6/9: make doctor pre-flight; crash-report capture into the diagnostics bundle; fuzz/property tests for the vault parsers; automated notarization in the release workflow; CI sanitizer + coverage lane.
- D2-1 / D2-6: design-system enforcement — a spacing + radius scale with a CI lint; extract MSCard/MSListRow/MSSurface so opted-out surfaces can't drift.
- E3-3: a pipeline write-ahead journal + finalize resume so a crash during finalize resumes instead of stranding a meeting.

Follow the ground rules. CaptureKit extraction and two-binary activation are the riskiest — do them as their own carefully-tested PRs, each gated by a full record->stop->transcribe smoke test from the daemon-owned path. Report back per PR.
```

---

## PROMPT 10 — V4 Phase 7: Positioning, monetization & strategic bets (optional)

```text
Phase: V4 Phase 7 (optional — only if going past "personal app"). Branch: feat/v4-phase7-positioning.

Read docs/audit-2026-05/MASTER_PLAN_V4.md "Phase 7" and findings/G2_pm_monetization.md, G5_comp_personalai.md, G2_pm_metrics.md, G5_comp_notetakers.md. Several of these are product/strategy decisions, not just code — flag any that need my decision before building.

Implement (separate PRs; build only the ones I confirm):
- P3-1: reposition around "compliance-grade local" (copy/marketing surfaces, in-app framing).
- P3-2 / P3-3: license the runtime + intelligence (never the data) via a signed offline license; hybrid one-time "lifetime local" + optional Intelligence+ subscription. Add the LicenseManager scaffolding (none exists today).
- P3-5 / P3-6 / P3-8: a "programmable vault" developer SKU; serverless team via vault-federation over shared iCloud/Drive; an anti-lock-in guarantee surface.
- C4-2 / C4-3: an on-device Recall Timeline (privacy-first answer to MS Recall) + a Consent-First Always-On Mode (visible indicator, consent-mode, retention/TTL, jurisdiction warnings). Build responsibly; default off.
- C4-5 / C4-7: retention & "Right to Forget" policies (audio-vs-transcript TTL, per-item forget) + consent receipts/provenance per recording.
- P5-7 / C1-2 / C1-9: "Your Year in Meetings" local stats; opt-in conversation intelligence; private on-device meeting coaching.

Follow the ground rules. For anything requiring a product decision (pricing numbers, SKU boundaries, always-on scope), STOP and ask me rather than guessing. Report back.
```

---

## Reusable snippets

### Per-phase PR description template
```text
## <Phase name>
Items completed: <IDs, each as a checklist line>
Plan refs: docs/audit-2026-05/<plan>.md + <findings files>

### Verification
- swift build -c release: PASS/FAIL
- Tests added/updated: <list>
- Smoke test (record 30s -> stop -> transcript+summary+notification): PASS / N/A (no capture/UI change)
- Click-budget checks (Quick-Wins phases): <surface: before->after>

### Found but out of scope
- <anything noticed but not fixed>

### Risk notes
- <pipeline-adjacent changes, feature flags, migration concerns>
```

### Smoke-test checklist (run before any PR that touches capture or UI)
```text
1. make app && /usr/bin/open /Applications/MeetingScribe.app
2. Start an ad-hoc recording; confirm the recording HUD/indicator shows.
3. Talk ~30s; stop.
4. Confirm: transcript.md is complete (no dropped tail), summary.md generated, notification fired.
5. Open the meeting; confirm action items, attendees, tags, follow-up all work.
6. Verify installed app == HEAD:
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/MeetingScribe.app/Contents/Info.plist)" = "$(git -C ~/MeetingScribeRefactor rev-parse --short HEAD)" ] && echo MATCH || echo MISMATCH
```

### If Claude Code gets stuck (paste mid-phase)
```text
You seem blocked. Do this: (1) commit what compiles so we don't lose it; (2) summarize exactly what's failing (error + file:line) and what you've tried; (3) propose 2 options with trade-offs; (4) recommend one and wait for my go-ahead. Do not force a change that breaks the build or the capture pipeline.
```

### Optional: feed Claude Code its own to-do at the start of a phase
```text
Before coding, list the items in this phase as a checklist, identify any that touch MeetingManager/MeetingPipelineController/LiveTranscriber/WhisperRunner/VaultMigrationManager, and tell me your implementation order and where you'll add tests. Then start.
```

---

## Notes
- The reference bundle (`docs/audit-2026-05/`) is currently untracked in your repo. PROMPT 1 will commit it as part of its branch, or you can commit it once on main first if you prefer it on every branch.
- Phases 2, 4, 5, 6 are large; the prompts tell Claude Code to split them into multiple PRs on the phase branch. That keeps reviews sane.
- If you'd rather Claude Code auto-merge each green PR instead of waiting for you, add "merge the PR once CI is green" to PROMPT 0 rule 1.
```
