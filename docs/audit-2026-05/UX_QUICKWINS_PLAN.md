# MeetingScribe — UX & Small-Feature Quick-Wins Plan (Pre-V4)

> **Repo:** `~/MeetingScribeRefactor`. **Method:** 10 senior-PM/UX agents, each anchored on the 3-click/2-click rule, each reading MASTER_PLAN_V4 and the live source, each finding 5 UX + 5 small-feature low-lift wins (100 items total). This plan dedupes them into **2 low-lift phases Claude Code can knock out BEFORE the V4 program starts.**
> **Scope rule:** every item here is **S (hours)** or **small-M (≈1 day)**. No architecture, no moats — that's V4. **Per-agent detail:** `audit/ux-findings/UX01…UX10.md` (item IDs map there).
> **Date:** 2026-05-30 · **Status:** Proposed.

---

## How this relates to V4
This is a deliberate "polish & connect" pass that ships first. Many items are **dead-code activations** (functionality already built, just not wired) or **light slices** of larger V4 items (e.g. a command-palette slice of D4-2, a recording-HUD slice of D4-1). Where an item fully delivers a V4 item at low lift, it's marked `↳ closes <V4 ID>`.

The **4 mandatory anchors** you specified lead Phase A. The remaining items are the highest-conviction, lowest-lift wins from the 10 agents, deduped.

---

## Phase A — Connect everything & hit the click budget

The theme: nothing should be a dead end, and the things that belong together (meetings ↔ people ↔ tasks ↔ initiatives ↔ emails) should be one click apart. The 4 anchors plus the specific items that realize them.

### A0 — The 4 mandatory anchors (spec'd)

| ID | Improvement | What it means concretely | Effort |
|---|---|---|---|
| **UX-A** | **3-click / 2-click budget.** Every page/action in a tab is reachable in ≤3 clicks from entering the tab; after opening a person or meeting, every necessary action is ≤2 clicks. | Treat as an acceptance test applied to A1–A9 below. The worst current violations the agents cited: Export/Recover buried 3-deep in a meeting's overflow (`UX2-5`); first Encounter/Relationship on a person needs a modal (`UX3-4`); a task's source meeting is a dead label (`UX4-1`); Settings is the only door to a 13-section flat scroll (`UX7-1`). Fix these as the concrete expression of the rule. | small-M |
| **UX-B** | **Make Tasks fluid: initiatives ↔ projects ↔ pages ↔ tasks connected, not siloed.** | Realized by A6 (clickable "From meeting", linked-items block, create-and-link, drag-to-reparent, owner→Person, full breadcrumb). The store already has `setProjectParent` and every task carries `meetingID` — the connections exist in data, just not in the UI. | small-M |
| **FEAT-A** | **Connect emails & people (from a meeting) into the CRM vault.** | From a meeting's attendee row: one click to open or **create** a CRM Person from an attendee (`UX2-1`/`UX2-2`); make contact rows (email/phone) actionable so a person links to real comms (`UX3-1`); "Add to People + link" from any attendee/owner chip (`FT10-4`). Lay the data link between an email address and a Person record. | small-M |
| **FEAT-B** | **People multi-select + front-and-center bulk tagging.** | Add a selection model to the People list with a **bulk-action bar** (`FT3-2`); primary bulk action = apply/create a tag across the selection; plus a **tag-management mini-UI** (rename/recolor/delete/merge — `FT3-1`; the `PeopleTagStore` methods already exist but are unreachable). Bring tagging to the front so "select everyone who should get tag X" is fast. | small-M |

### A1–A9 — Items that realize the anchors + the highest-value connective wins

| ID | Improvement | Click impact | Serves | Effort | Source |
|---|---|---|---|---|---|
| **A1 = UX2-1 / UX2-2** | Attendee chips become one-click buttons (open/add Person; "Add all attendees to People"). Today it's a hidden right-click menu. | 2-click + discoverable | FEAT-A | S | Meetings |
| **A2 = UX3-1** | Contact rows (email/phone/address) actionable — mailto/tel/copy, not dead text (~15 lines). | kills 5-step copy/switch | FEAT-A | S | People |
| **A3 = UX4-1** | A task's "From meeting" chip becomes clickable (`meetingID` already on every task; renders as dead `Text` today, `TaskPageView.swift:176`). | 4→1 | UX-B | S | Tasks |
| **A4 = FT4-1** | "Linked items" block on every task/page (meetings · people · related tasks) — one consistent connective section. | — | UX-B | small-M | Tasks |
| **A5 = FT4-3 / FT4-2** | One-click "Create task from this meeting" / link existing task to a meeting; link a task **owner to a CRM Person** (owner is free-text today). | new connections | UX-B/FEAT-A | small-M | Tasks |
| **A6 = UX4-2 / UX4-3** | Drag-to-reparent pages in the rail (`setProjectParent` exists, no drag today); full breadcrumb trail on every page (not just one hop). | reparent 0→1 | UX-B | small-M | Tasks |
| **A7 = UX2-5** | Lift "Reveal in Finder / Export / Recover" out of the triple-nested overflow into the detail header. | 3→1 | UX-A | S | Meetings |
| **A8 = UX3-4** | Bring Encounter + Relationship "Add" onto the identity panel (the Relationships section doesn't even render until one exists). | fixes dead end | UX-A | S | People |
| **A9 = UX8-5 / D1-5** | Make cross-entity links clickable everywhere (PersonDetail "In your recordings" rows, "Needs attention" rows that currently dump to the tab root). | deep-link, not dump | UX-A | small-M | Notif/V4 |
| **A10 = FT2-1 / D1-2** | "Copy link to this meeting" (`meetingscribe://meeting/<id>`) — also registers the URL scheme. | enables deep links | UX-A | S | Meetings ↳ closes D1-2 |

---

## Phase B — Polish pass & small features

Cheap, high-visibility wins that make the app feel finished. Independent of Phase A; can run in parallel.

### B1 — Navigation & home

| ID | Improvement | Effort | Source |
|---|---|---|---|
| **UX1-2** | Reset Today's pushed meeting-detail when switching tabs / pressing ⌘1–5 — today "Today" can land you inside a meeting, not home (~3 lines). | S | Today/nav |
| **UX1-1** | Wire the already-built `calendarLink` (`TodayView.swift:224`, never rendered) so Today links to the full Meetings list; fix stale "Calendar tab" empty-state copy. | S | Today/nav |
| **FT1-2 / FT5-4** | Recently-visited entities + pinned/favorites as a quick-switch row in the rail / ⌘K (reopening a meeting is the most-repeated action; 3→1). | small-M | Today / Chat |
| **FT1-3** | Persist last-opened meeting + scroll so Today restores context on return. | S | Today/nav |

### B2 — Lists, empty states & keyboard consistency

| ID | Improvement | Effort | Source |
|---|---|---|---|
| **UX9-1** | Make every list empty state actionable (Meetings & Tasks are dead today; People/QuickNotes already have a CTA). Adopt `ContentUnavailableView`. | S | Consistency |
| **UX9-3 / FT9-4** | Give the Meetings list the same `List(selection:)` model as every other list — arrow-key nav, Enter to open, ⌫ to delete. It's the busiest tab and the only mouse-only one. | small-M | Consistency |
| **UX9-2** | Collapse the two parallel primary-button systems (`Untitled*` vs `MS*`) into one — TodayView currently mixes both in one view. | S | Consistency ↳ aids D2-3/D2-6 |
| **UX9-4 / FT9-1** | One shared search field (placement, clear-X, Esc-to-clear) + `⌘F` focuses the current tab's search. | S | Consistency |
| **FT9-3** | Inline "Undo" toast after destructive list actions. | small-M | Consistency ↳ light slice of D4-3 |
| **FT9-2** | Loading skeleton/label instead of bare spinners during transcribe/summarize. | S | Consistency |

### B3 — Editing & quick-add (kills create-then-rename friction app-wide)

| ID | Improvement | Effort | Source |
|---|---|---|---|
| **UX10-2** | Auto-focus + select the title on every "create" (no `@FocusState` anywhere today, so new items are literally named "New task" until you hunt-click-clear-type). One pattern, whole-app fix. | S | Editing |
| **UX10-3** | Autosave title/name fields on blur, not only on Enter — page/initiative/task names silently discard on click-away today. | S | Editing |
| **UX10-4** | Auto-focus the "New tag / New label / New section" fields when their UI opens (also fixes tag creation friction in `UX2-3`). | S | Editing |
| **UX10-1** | Finish PPL-1: bring phone/email/tag editing inline so the 460×540 AddPersonSheet modal is never needed for a one-field fix. | small-M | Editing ↳ closes PPL-1 |
| **FT10-1 / FT10-3** | Quick-add bar (type title + Enter, no detail open) with smart defaults from context (project/section/status/due). | small-M | Editing |

### B4 — Recording in the moment

| ID | Improvement | Effort | Source |
|---|---|---|---|
| **UX6-1** | Persistent meeting-recording HUD (reuse the existing `RecordingPill`/`FloatingOverlay` that voice notes already have; meeting recording has none, so stopping behind a Zoom call is 3 clicks). | small-M | Recording ↳ light slice of D4-1 |
| **FT6-3** | Live audio-level / silence indicator during meeting recording (meter exists for voice notes) — catches "recorded nothing" while it's still fixable. | S | Recording |
| **FT6-2 / UX6-5** | One global "record meeting" hotkey (parity with F5 dictation) + surface the hotkeys where they're used. | S | Recording |
| **FT6-4** | "Add marker/bookmark" during recording for fast jump-back later. | small-M | Recording |

### B5 — Notifications & follow-up

| ID | Improvement | Effort | Source |
|---|---|---|---|
| **UX8-1 / UX8-2** | Make the "Meeting ready" notification actionable (Review / Draft follow-up buttons + a `Meeting` payload) — the most-fired, highest-intent notification has zero actions today and lands you 4–5 clicks from the summary. | S | Notif |
| **UX8-3 / FT8-4** | Follow-up "sent/copied" state (none exists today) + a "pending follow-ups" widget on Today. | small-M | Notif ↳ light slice of P2-6 |
| **FT8-2** | Auto-draft the follow-up the moment a summary completes (reuse the existing `onComplete` hook) — instant instead of a cold spinner. | S | Notif |
| **FT8-5 / FT8-1** | Detection status chip ("You're in a Zoom call · Record") + "Snooze 5 min" on the meeting-start notification. | S | Notif |
| **FT8-3** | Make the Slack follow-up channel actually deliver, or honestly label it "copy only" (it silently only copies today). | small-M | Notif |

### B6 — Settings & search (mostly dead-code activation)

| ID | Improvement | Effort | Source |
|---|---|---|---|
| **UX7-4** | Ship the already-built `IntegrationsView` (status pills, inline test, "pull recommended model" nudge) in place of the inferior flat-Form connector duplicate that currently ships. **Mostly deletion.** | S | Settings |
| **FT7-1** | "What's connected / working" health strip at the top of Settings + a rail dot (every underlying probe already exists). | S | Settings |
| **FT7-4 / UX7-1** | Settings search / quick-jump field over the 13-section flat scroll. | S | Settings |
| **UX7-2 / UX7-3** | Add a "Reopen MeetingScribe" relaunch button and a "re-run setup" path (onboarding asks for manual OS chores with no button and no recovery). | S | Settings ↳ light slice of D3-6 |
| **UX5-1 / FT5-2** | Inline actions on search results (act in 1 click, not navigate-then-act) + a command-palette slice of ⌘K (every primary action already has a command). | small-M | Chat/search ↳ light slice of D4-2 |
| **UX5-4 / UX5-5** | Context-aware chat starter prompts + advertise what Chat can *do* (create task, push to Linear, edit file) in its empty state instead of a generic "Ask anything". | S | Chat/search |

---

## Suggested sequencing for Claude Code

**Phase A first (the connect + click-budget pass):** A1→A10, with the 4 anchors (A0) as the acceptance criteria. This is where the "feels connected" leap happens.

**Phase B in parallel/after (the polish pass):** B1–B6. B3 (auto-focus + autosave) and B2 (empty states + Meetings keyboard model) are the cheapest, most-visible; do them first within B.

Per the project workflow, build + `swift build -c release` / `make app` + a record→stop→transcribe smoke test gate each change before commit. None of these items touch the capture/finalize pipeline, so they're low-risk relative to the V4 Phase 0 data-integrity work — but the V4 Phase 0 fixes (e.g. the ScribeCore daemon data-loss bug `E3-1`) should still land before heavy daily use.

---

## Appendix — full 100-item catalog
Every item (UX1-1…UX10-5, FT1-1…FT10-5) with friction, file:line, click-counts, and effort lives in `audit/ux-findings/UX01_today_nav.md` … `UX10_editing_quickadd.md`.
