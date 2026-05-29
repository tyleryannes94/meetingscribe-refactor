# MeetingScribe — Master Improvements Plan (Post-Rebuild)

> **Repo audited:** `~/MeetingScribeRefactor` → `github.com/tyleryannes94/meetingscribe-refactor` (HEAD `e15c1db`). This is the **new, rebuilt app** — not the older `~/MeetingScribe`.
> **Synthesized from a 20-agent audit:** 5 UX/UI · 5 Product · 5 Engineering · 5 simulated end-users, each reading the live Swift source and citing file:line.
> **Date:** 2026-05-29 · **Status:** Proposed — for Tyler's review before implementation.
> **Companion doc:** `MASTER_PLAN_V2.md` (data-layer / architecture). This doc owns the UX, product, and view-layer work plus the engineering changes that support it.

---

## 1. Executive summary

The rebuild is real and substantial — all four audit teams independently confirmed it in code. The Meetings tab is now a true `NavigationSplitView` (no accordion), People is a two-column layout with a sticky identity panel, meeting detail is summary-first with inline checkable action items, the follow-up generator is wired back in, a pre-meeting brief is live, the Coach tab is gone (7→5 sections), permission onboarding is respectful and skip-friendly, and the backend landed genuine wins (lock-protected `AudioCounters` with a TSan test, one consolidated `WhisperRunner`, bounded-backpressure live transcription, a debounced O(1) `MeetingStore` index, crash recovery).

So this is a refinement plan, not a teardown. But the audit surfaced two categories that matter:

**A. Your seven requirements are mostly *partial*, not done.** The rebuild fixed collapse/expand in Meetings but **left it in Today and Calendar**; made People editable but **only through a modal**; and still **caps content width** so wide displays waste space. None of your seven is fully satisfied yet — but the remaining work is small and high-signal.

**B. Two genuine data-integrity bugs and one dead feature** that the UX-focused brief wouldn't have caught:
- **Live transcripts are silently truncated at stop** — the final 0–5 minutes of *every* recording are dropped from `transcript.md`, and the batch fallback that should recover them is skipped. Summaries and action items are then generated from a truncated transcript. **(P0)**
- **Vault migration is half-wired** — it moves folders but never updates each meeting's stored path, new/retagged meetings still use the old layout, and a partial migration is marked "complete." **(P0)**
- **The entire Calendar month/week view (`CalendarTabView`) is orphaned** — built, ~500 lines, referenced by nothing, unreachable from the nav. Either a feature was lost or it's dead code shipping in the binary. **(P0-decision)**

**The convergent P0 spine** (what multiple teams independently ranked highest):

1. Replace Today's (and Calendar's) inline expand/collapse with click-into-detail + back arrow — finish what Meetings started.
2. Inline, field-level person editing — retire the modal for quick edits.
3. Use the full window width — remove/relax the 720 / 920 caps; default the chat rail closed.
4. Default Meetings scope to upcoming-first and persist it.
5. Fix the live-transcript truncation (data loss).
6. Fix / complete the vault migration (data integrity).
7. Decide the orphaned Calendar view: re-expose as a Meetings view-mode, or delete.

---

## 2. Your seven non-negotiables — verified against the new code

| # | Requirement | Status | Evidence (file:line, MeetingScribeRefactor) |
|---|---|---|---|
| 1 | Clean spacing; People tab not cut off | ⚠️ Partial | Fixed but via magic number: `PeopleListView.swift:133` `.padding(.top, 60)`; the comment claims a matching 72pt detail inset that `PersonDetailView` does **not** apply, so panes don't align. Should be `.safeAreaInset`. |
| 2 | People CRM **easier to edit** | ⚠️ Partial | Full edit works but is **modal-only** (`PersonDetailView.swift:342` → `AddPersonSheet`, 460×540). Memories/encounters/relationships/photos are inline; the most-edited identity fields are the modal-locked ones. Single email/phone/address (`replacingFirst`). |
| 3 | Today = functional central hub | ⚠️ Partial | Good ingredients (record CTA, pills, today's calls, tasks widget, suggested people) but still uses inline expand; no "next meeting" glance; `calendarLink` is defined but never placed in the feed (`TodayView.swift:173`). |
| 4 | **Never collapse/expand** — click in + back arrow | ❌ Violated (Today + Calendar) | `TodayView.swift:23/245/296` (`expandedMeetingID`, "Collapse", `toggle`); `CalendarTabView.swift:20/487/498`. **Meetings tab is compliant** (NavigationSplitView). |
| 5 | **Full screen width**, no wasted space | ❌ Violated | Caps: `TodayView.swift:60` (920), `PersonDetailView.swift:277` (720), `NotionDesign.swift:11` `contentMaxWidth=720`. Plus always-on chat rail → dead gutter on wide displays, crowding on narrow. |
| 6 | **Defaults** upcoming → past → all, sorted | ⚠️ Partial | Sorting correct everywhere; but `MeetingsView.swift:26` defaults `scope = .all` and resets each visit (not `@AppStorage`). |
| 7 | **Restore lost buttons/editing** | ✅ Mostly done | Follow-up, regenerate summary, imports, full Tasks CRUD all present. Remaining gaps: no per-attendee "add to People"; no "+ add action item" on a meeting; orphaned Calendar view. |

**Net: 0 of 7 fully shipped, but most are one small change away.** The cleanest wins Tyler will notice immediately: #4 (Today still expands) and #6 (default scope).

---

## 3. Improvements, by area

Severity: **P0** = breaks a requirement / data loss · **P1** = significant gap · **P2** = polish. Effort: S/M/L.

### 3.1 Navigation — finish the click-into model (req #3, #4)

The rebuild converted Meetings to `NavigationSplitView`, but three navigation models now coexist: the app **shell** is still an opacity-ZStack tab switcher (`MainWindow.swift:83-100`), Meetings is split-view, and **Today + Calendar still inline-expand**. The same meeting opens three ways (split-view page, inline 520pt panel, modal sheet from search).

| Item | What to do | Sev | Effort |
|---|---|---|---|
| NAV-1 | Replace Today's inline expand with navigation into the shared `UnifiedMeetingDetail` (select-into Meetings or a push) with a back arrow. Delete `expandedMeetingID`, `cardWithDetail`, `inlineDetail`, `toggle`, the "Collapse" button, and `MeetingCard.isExpanded`. | P0 | M |
| NAV-2 | Same for `CalendarTabView` (or fold it per NAV-5). | P0 | S |
| NAV-3 | Route `routeEntity(.meeting)` (search/deep-link) into Meetings selection instead of a separate modal sheet, so there's one canonical meeting surface. Removes the `dismiss + asyncAfter(0.18)` hack. | P1 | M |
| NAV-4 | Move the app shell to a real `NavigationSplitView` (sidebar = nav rail); scope keep-alive to the 1–2 heaviest tabs instead of mounting all five forever (see ENG-perf). | P1 | M |
| NAV-5 | Decide the orphaned `CalendarTabView`: re-expose month/week as a List/Month/Week segmented control inside MeetingsView, or delete the ~500 lines. Today's "all calls" link currently goes to Meetings — make it consistent. | P0 (decision) | S–M |

### 3.2 Layout & full-width (req #1, #5)

| Item | What to do | Sev | Effort |
|---|---|---|---|
| LAY-1 | Remove/relax the width caps for lists, tables, cards, and detail panes (`TodayView:60` 920, `PersonDetailView:277` 720, `NDS.contentMaxWidth` 720). Keep a reading measure (~720) **only** for prose (summary/transcript). Consider adaptive `min(width - gutters, cap)`. | P0 | M |
| LAY-2 | Default the chat rail **closed** (especially first-run), remember the choice, and add a keyboard toggle. It currently eats ~340pt by default and auto-hides under 860px with no key binding. | P0 | S |
| LAY-3 | Replace the People `.padding(.top, 60)` magic number with `.safeAreaInset`/toolbar-aware layout applied consistently to both panes; remove the misleading "72pt" comment. | P1 | S |
| LAY-4 | Migrate the cold `NSColor.*` surfaces (ActionItems board, Calendar) to NDS tokens; adopt the `MSPrimary/Secondary/Tertiary` button styles consistently (call sites still use raw `.bordered*`). | P2 | M |

### 3.3 People CRM — inline editing (req #2)

| Item | What to do | Sev | Effort |
|---|---|---|---|
| PPL-1 | Make identity-panel fields click-to-edit in place (name, role, company, email, bio), autosave on blur — mirror the meeting header's `editingHeader` pattern. Reserve `AddPersonSheet` for first-create only. | P0 | M |
| PPL-2 | Multi-value contact fields (emails/phones/addresses with +/− and work/home labels); stop dropping the 2nd value via `replacingFirst`. | P1 | M |
| PPL-3 | Make identity-panel tag chips tappable to filter the list (currently display-only); make encounters/relationships add inline like memories already do (consistency). | P1 | S |
| PPL-4 | On a person's Meetings tab, show **all calendar meetings** with them, not only recorded ones (managers' 1:1s often aren't recorded → tab reads empty). | P1 | M |
| PPL-5 | "Notes" label collision: rename the bio section to "About"; keep "Notes" for attached analyses (`PersonDetailView.swift:537` vs `:816`). | P2 | S |

### 3.4 Today — a glanceable hub (req #3)

| Item | What to do | Sev | Effort |
|---|---|---|---|
| TDY-1 | "Up next" hero strip: next meeting + countdown + attendees + "Open brief" + "Join & Record." The single highest-value daily glance, currently missing. | P0 | M |
| TDY-2 | "Needs attention" block above meetings: overdue + due-today tasks + follow-ups not yet sent (distinct from the generic widget). | P0 | S |
| TDY-3 | After NAV-1, Today cards open the full detail; drop the forced `minHeight: 520`. | P0 | S (with NAV-1) |
| TDY-4 | Make inline action-item rows on the Summary fully editable (title, due, owner), and add a "+ Add action item" button on the meeting detail that auto-links to that meeting. | P1 | M |
| TDY-5 | Auto-open newly created "New task"/"New page" focused for rename instead of dropping an "Untitled" in the Tasks tab. | P1 | S |
| TDY-6 | End-of-day recap (meetings recorded, tasks done, follow-ups pending) — retention hook. | P2 | M |

### 3.5 Meetings & defaults (req #6)

| Item | What to do | Sev | Effort |
|---|---|---|---|
| DEF-1 | Default `MeetingsView` scope to `.upcoming` and persist via `@AppStorage("meetings.scope")`. | P0 | S |
| DEF-2 | Make the Meetings list a focusable `List(selection:)` so ↑/↓/Enter work (People and Notes already do; Meetings is mouse-only `Button`s in a `ScrollView`). | P1 | S |
| DEF-3 | Promote "Draft follow-up" to the top of the Summary tab / detail header — it's buried below long summaries today. | P1 | S |
| DEF-4 | Surface a "Home/Dashboard" entry in the Tasks ProjectRail so the rich dashboard is discoverable (default lands on All Tasks with no hint it exists). | P2 | S |

### 3.6 Engineering — data integrity & reliability (some are P0 data loss)

| Item | What to do | Sev | Effort |
|---|---|---|---|
| ENG-A | **Live-transcript truncation (data loss).** `stopRecording` calls `renderMarkdown()` before the live transcriber's in-flight per-source tasks finish, and the batch fallback only runs if the live transcript is *empty* — so the final 0–5 min of every meeting is silently dropped. Add `LiveTranscriber.flush() async` (await `lastMicTask`/`lastSystemTask`) before render; change the fallback gate from "is live empty?" to "does live cover < (duration − one chunk)?"; always batch when `droppedChunkCount > 0`. Route the ScribeCore stop path through the same finalize entry point. (`MeetingManager.swift:331`, `:135`, `MeetingPipelineController.swift:86`, `LiveTranscriber.swift:98`) | P0 | M |
| ENG-B | **Vault migration half-wired.** `VaultMigrationManager` moves folders but never rewrites each meeting's `relativeFolderPath`; `MeetingStore.desiredDirectory` still emits the old flat tag layout, so new/retagged meetings diverge and every migrated meeting hits the O(N) tree-walk; retagging moves meetings back out; a partial migration is marked complete (errors swallowed). Write back the new path per meeting, update `desiredDirectory` to the date-partitioned layout, make `moveMeeting` layout-aware, and only set the completed flag when moved == discovered. (`VaultMigrationManager.swift:24-95`, `MeetingStore.swift:96-134`, `MeetingManager.swift:604`) | P0 | M |
| ENG-C | **finalize vs Transcribe-Now race.** Claim the meeting id in `transcribingIDs` synchronously inside `stopRecording` (before dispatching finalize) so a concurrent "Transcribe Now" is rejected; make `mergeSegments` write temp + atomic rename. (`MeetingPipelineController.swift:56/154`, `MeetingManager.swift:339`) | P1 | S |
| ENG-D | **Whisper model download integrity.** Pin a SHA-256 for `ggml-base.en.bin`, stream-hash and reject on mismatch; gate the silent ~140 MB fetch behind onboarding consent; add resumable/retry download. (`WhisperRunner.swift:306-369`) | P1 | S |
| ENG-E | **Backup honesty.** `Backup/` is empty, zero CloudKit code — "iCloud" is just on-demand file download + the inbox watcher. Ensure no UI claims "backed up"; either implement a real backup target or state plainly "stored locally; put your vault in iCloud Drive for sync." | P1 | M |
| ENG-F | **`startRecording` publishes the wrong meeting** into `.recording` (uses the `nil` `meeting` param instead of resolved `m` for ad-hoc; ScribeCore path does it right). Fix line 206 and standardize reads on `activeMeeting`. (`MeetingManager.swift:206`) | P1 | S |
| ENG-G | **Replace `try?` on persistence** (transcript/notes/summary/meeting.json writes and folder moves) with real error handling via `ErrorReporter` + a user-visible warning on write failure. | P1 | M |

### 3.7 Engineering — architecture, perf & maintainability

| Item | What to do | Sev | Effort |
|---|---|---|---|
| ARCH-1 | **~25 audio/transcription files are physically duplicated** between `Sources/MeetingScribe/` and `Sources/ScribeCore/` and have **already drifted** (different logging, different `AudioRecorder`/`WhisperRunner`). Every fix must be made twice — and ENG-A/ENG-D each live in both copies. Extract a shared `CaptureKit` library used by both; delete the duplicates; add a CI guard that fails if a path exists under both trees. | P1 | L |
| ARCH-2 | **Keep-alive ZStack runs hidden tabs' timers forever** — notably `TranscriptSyncView` fires a 0.25s timer 4×/sec unconditionally even when hidden/no audio. Gate timers on visibility + playing state; drive transcript-sync off the player time-observer; make the hourly refresh non-forced. (`MainWindow.swift:84`, `TranscriptSyncView.swift:118`) | P1 | M |
| ARCH-3 | Finish the MeetingManager decomposition — migrate views to observe `quickNotesController`/`pipelineController` directly and delete the ~50 forwarding shims. Decompose the remaining god-files: `PeopleStore` (1177), `PersonDetailView` (1208), MCP `main.swift` (1081). | P2 | M |
| ARCH-4 | Memoize `TranscriptSyncView.parse()` (keyed by transcript hash; off-main for large inputs) instead of re-parsing on every change. | P2 | S |

### 3.8 Testing & CI

| Item | What to do | Sev | Effort |
|---|---|---|---|
| TST-1 | Add `.github/workflows/ci.yml` on `pull_request` + `push: main` running `swift build` + `swift test` (ideally `--sanitize=thread`). Today CI runs **only on release tags**, so dev commits are ungated. | P1 | S |
| TST-2 | Add tests for the data-integrity paths that currently have none: `LiveTranscriber.flush` (tail not dropped), `VaultMigrationManager` (paths rewritten, flag stays false on partial), finalize-vs-transcribeNow concurrency, `WhisperRunner.parse` (+ malformed JSON) and the checksum rejection, and the `TranscriptSyncView` regex parser. | P1 | M |

---

## 4. New ideas to make it best-in-class

The local-first + relationship-graph combo is the moat. Highest-leverage additions:

- **Write-capable MCP tools** (`create_action_item`, `update_action_item`, `add_person`, `add_memory`, `create_meeting_note`). The MCP server is still 100% read-only (12 `get_*`/`list_*` tools) — Claude can read everything but change nothing, leaving the agent half of the product on the table. *(P0-for-differentiation, M)*
- **Send the follow-up, don't just copy it** — "Open in Mail" (`mailto:`/`NSSharingService`) with recipients prefilled from attendees; "schedule next meeting" via EventKit write. *(S, after promoting the button)*
- **"Stay in touch" nudges** on Today — "haven't talked to X in N days" from message `lastDate` + meeting history; snooze/done. Self-maintaining CRM. *(M)*
- **Speaker-labeled transcript & summary** — `SpeakerDiarization.swift` exists but isn't surfaced; attribute action items to speakers. *(L)*
- **Unified "find everything about X"** — wire the FTS5 v2 `searchAll()` into `GlobalSearchView` across people + meetings + tasks + messages with recency boost. *(M)*
- **Global ⌘N quick-add task** with natural-language parsing (title + due + owner). *(S)*
- **Per-tag summary templates** (1:1 vs all-hands vs decisions-only). *(M)*
- **Don't hard-code "Tyler"** into local analysis prompts — read the name from the profile. (Found baked into every Ollama analysis preamble.) *(S)*

---

## 5. First-run & onboarding (from the new-user persona)

- De-jargon "vault" → "where should we save your notes and recordings?"
- The Screen-Recording "quit and relaunch" step reads as broken to a non-technical user — explain it warmly and add a "Reopen MeetingScribe" affordance instead of dumping them in System Settings.
- A one-time "how it works" overview after onboarding (record → transcribe → summary → tasks).
- Disambiguate Voice Note vs. Meeting recording vs. Ad-hoc (three entry points, no explanation).
- Default the chat rail closed until the user has content to ask about.

---

## 6. Suggested implementation sequence

**Phase 0 — Data integrity (do first, independent of UI):** ENG-A (transcript truncation), ENG-B (vault migration), ENG-C (pipeline race), ENG-D (model checksum), ENG-F (recording-state bug). These are silent data-loss / correctness issues — the highest-stakes items in this whole plan.

**Phase 1 — Finish the nav model:** NAV-1/2 (kill Today + Calendar expand/collapse → click-into + back arrow), NAV-5 (decide Calendar), LAY-1/2 (full width + chat rail default-off). Directly closes requirements #3, #4, #5.

**Phase 2 — Editing & defaults (fast, high-signal):** PPL-1 (inline person editing, req #2), DEF-1 (upcoming-first default, req #6), DEF-3 (follow-up to top), TDY-1/2 (up-next + needs-attention).

**Phase 3 — Depth:** PPL-2/3/4, TDY-4/5, DEF-2/4, write-capable MCP, send-follow-up, ARCH-2.

**Phase 4 — Hardening & best-in-class:** ARCH-1 (de-duplicate CaptureKit), ARCH-3, TST-1/2, ENG-E/G, the relationship-intelligence and search ideas, first-run polish.

---

## 7. Appendix — source audits

Full per-discipline detail (every file:line) lives alongside this doc:
`audit2_ux.md` · `audit2_pm.md` · `audit2_eng.md` · `audit2_users.md`.

**Confidence note:** four teams worked independently against the same code and converged on the same items — Today still expand/collapse, modal-only person editing, wasted width, default scope, and (from the engineers) the transcript-truncation and vault-migration bugs. That convergence is why this plan leads with them.

*(An earlier version of this audit mistakenly targeted the older `~/MeetingScribe` repo; that output is marked superseded. This plan reflects `~/MeetingScribeRefactor` only.)*
