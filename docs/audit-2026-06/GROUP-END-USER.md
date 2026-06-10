# End-User Persona — Compiled Audit Digest

_MeetingScribe Refactor · Audit 2026-06 · Group: End-User Persona (power-pkm, new-nontechnical, manager-consultant, relationship-personal, cross-device-mobile)_

## Executive Summary

Five persona agents stress-tested MeetingScribe from the seats of the people who actually live in it: the PKM power user who wants the vault to be a queryable graph, the brand-new non-technical user who is intimidated by "vault" and Ollama, the manager running 6+ calls a day who needs directed commitments and growth arcs, the relationship/second-brain user who needs frictionless logging and proactive nudges, and the cross-device user who wants trustworthy capture and review from their phone.

The app has strong, real foundations — local-first vault, MCP servers, calendar-aware briefs, one-way sync, a web UI, a `Decision`/`DecisionStore` scaffold, and a `RelationshipType` enum. But the personas converge on a consistent story: **the data model and capture surfaces are richer than the navigation, surfacing, and proactive layers that turn them into daily habits.** The vault holds the relationships but doesn't traverse them; meetings produce decisions and commitments but doesn't track direction or follow-through; the People CRM models partners and reports but doesn't nudge, score, or log them frictionlessly; and a new user is left guessing what to do after onboarding.

Three cross-persona themes dominate the merged recommendations:

1. **A directed/queryable graph layer** — backlinks everywhere, decision + commitment ledgers, transitive MCP queries, and forward/back navigation. (power-pkm + manager-consultant converge on Decisions/Commitments.)
2. **Frictionless capture + proactive surfacing** — quick-log encounters, check-in notifications, health scores, inline meeting→task creation, and mobile/Siri capture. (relationship-personal + manager + cross-device converge.)
3. **First-run clarity** — de-jargon, disambiguate the three record buttons, a "how it works" tour, and honest empty/status states. (new-nontechnical owns this, and it is the cheapest high-impact bucket.)

Several net-new ideas stand out as strategic: a **Decision & Commitment Ledger** (independently surfaced by both power-pkm and manager-consultant — strong signal), **directed commitment tracking (iOwe/theyOwe)**, **relationship health scores + check-in notifications**, and **iPhone Shortcuts capture** that reuses the existing `_inbox` infrastructure.

## Prioritized Recommendations

| # | Title | Type | Area | Impact | Effort | Phase | Prior? | Description |
|---|-------|------|------|--------|--------|-------|--------|-------------|
| 1 | De-jargon + disambiguate + "how it works" first-run bundle | improvement | Onboarding | high | S–M | 1 | yes | Replace "vault"/"Ollama" with plain copy; one-line descriptions for the 3 record buttons; a one-time 3-step how-it-works tour; honest empty-state + post-recording status copy. |
| 2 | Decision & Commitment Ledger | new-feature | Tasks | high | M–L | 2 | yes | First-class, searchable, linked Decisions entity with 1-click capture; wire the existing `Decision`/`DecisionStore` scaffold into extraction + UI + MCP. (Surfaced independently by 2 agents.) |
| 3 | Directed commitment tracking (iOwe/theyOwe + personID) | improvement | Tasks | high | M | 2 | yes | Add `direction` + `personID` to ActionItem; split per-person "I owe / they owe me" on Today + person detail. The core management accountability loop. |
| 4 | Encounter quick-log widget (kind picker + mood) | new-feature | People/Vault | high | M | 2 | yes | One-tap encounter logging (call/coffee/dinner/quality-time) wiring VaultKit's `Kind` into the UI; the #1 daily-habit blocker. |
| 5 | Relationship check-in notifications + drift surfacing | new-feature | Notifications | high | M | 2 | yes | New `RELATIONSHIP_CHECKIN` category + scheduler for partner/family/close-friend cadence; deep-links to quick-log; dismissible Today banner. Closes the habit loop. |
| 6 | Backlinks & bidirectional query panel (universal, indexed) | new-feature | Tasks | high | M | 2 | no | A `BacklinkIndex` actor built at write-time + a backlinks panel on every entity detail. Makes any task/person/note a context hub. |
| 7 | Inline meeting→task creation + bidirectional link | improvement | Tasks | high | M | 2 | yes | "+ Add action item" on Summary that auto-links to the meeting; "Tasks sourced from this meeting" section; persistent inverse link for later queries. |
| 8 | Relationship health score (surfaced on profile + Today) | new-feature | People/Vault | high | M | 2 | yes | On-the-fly recency+depth+streak score with colored ring; the visible reward that makes logging a habit. |
| 9 | iPhone Shortcuts vault capture (Note/Task/Person/Voice) | new-feature | Cross-device | high | M | 1 | yes | Four Siri-driven Shortcuts writing JSON envelopes to `_inbox/`, reusing iCloudInboxWatcher. Frictionless mobile/hands-free capture. |
| 10 | Per-report 1:1 prep digest (themes + commitments + last meeting) | improvement | People/Meetings | high | M | 2 | yes | Extend PreMeetingBriefView to read bio, growth themes, and directed open commitments into the synthesized brief. |
| 11 | Growth-theme threads (time-series 1:1 arc per report) | new-feature | People/Vault | high | M | 2 | yes | Dated, trended themes (delegation, public speaking) rendered as mini-timelines; foundation for review compilation + sentiment. |
| 12 | Quiet 1:1 / encounter capture for unrecorded meetings | new-feature | People/Meetings | high | M | 2 | yes | "Log a 1:1" lightweight sheet that creates a non-recorded meeting stub + memory; backfills timelines so cadence/drift are truthful. |
| 13 | Calendar-aware stay-in-touch cadence (fix silent ghosting) | improvement | People/Tasks | high | M | 2 | yes | Derive last-interaction from calendar + recordings + messages, not recordings only; stop calling people overdue you saw yesterday. |
| 14 | Private vs shareable note visibility (gate MCP reads) | improvement | People/Vault | high | M | 2 | yes | `visibility` on notes/memories; MCP/agents read shareable-only by default; lock icon in UI. Table-stakes for candid people data. |
| 15 | Inner-Circle Today strip (glanceable partner/family status) | new-feature | Today/Vault | high | M | 2 | yes | Horizontal strip of partner/close-family with status rings ordered overdue-first; the daily ritual surface. |
| 16 | Mobile meeting-review + "What's new" sync glance | improvement | Cross-device | high | M | 2 | no | Phone web UI: sticky summary-first layout with inline action items, plus a `/whatsnew` dashboard + time-since-last-sync badge. |
| 17 | Global forward/back navigation stack (⌘[ / ⌘]) | improvement | Design System | high | M | 2 | yes | Browser-style history in WorkspaceRouter + breadcrumb spine; enables fast cross-entity exploration. (V5 DN-1/CP-5.) |
| 18 | Performance-review compilation (one-click draft) | new-feature | People/Vault | high | M | 3 | yes | Compile 6 months of memories, completed commitments, theme deltas, and shareable notes into a Markdown review draft. |
| 19 | Live recording + post-recording status feedback | improvement | Recording | high | M | 2 | yes | Reuse the voice-note audio meter on meeting recordings + a "transcribing on your Mac" toast/card; kills the "did it capture?" fear. |
| 20 | Transitive graph MCP queries (meeting↔task↔person) | new-feature | Chat | high | M | 3 | yes | Edge-following MCP tools (related people, decisions by person, task stakeholders) on top of EntityGraphIndex. |
| 21 | Smart @-mention completions in notes & tasks | improvement | Tasks | medium | M | 3 | no | Type `@` to insert markdown entity links; makes the existing link infra user-facing, Obsidian-style. |
| 22 | Vault Query API: read-only CLI + JSON schema export | new-feature | Onboarding | high | L | 4 | no | `meetingscribe query --tag … --format=json` + per-tab "export filtered list"; the no-lock-in / scriptable promise. |
| 23 | Team view + org rollup + cross-report patterns | new-feature | People/Vault | medium | M | 3 | yes | Typed manager/directReport relationships, "My Team" filter, and pattern aggregation ("4 of 7 raised on-call load"). |
| 24 | Relationship-type-aware AI presets + fix hard-coded "Tyler" | improvement | People/Vault | medium | S | 1 | yes | Type-aware analysis presets (conflict patterns, date ideas) and pass real `userName`/type into the LLM preamble instead of a baked-in name (safety + correctness). |
| 25 | Bulk link creation/editing (multi-select batch actions) | new-feature | Tasks | medium | M | 3 | no | Multi-select + batch "Link to / Tag as / Assign to" in the shared list; fast bulk PKM operations. |

_Also captured for the master plan (lower priority): vault audit/append log, queryable people-tag hierarchy, sentiment sparkline, "On this day" memory resurface, structured reflection templates, encounter direction/mode fields, `get_relationship_health` MCP tool, nav-rail guided tour, first-recording success card, Chat-sidebar privacy explainer, weekly relationship digest notification, system-wide quick actions, mobile voice task capture, sync trust dashboard, bidirectional sync opt-in, cross-device notification relay, iPad/dark-mode/offline web polish, Focus-mode notification silencing, fuzzy person dedup on merge._

## Top 5 Bets

> **1. First-run clarity bundle (#1).** The cheapest high-impact work in the entire audit. De-jargon, disambiguate the three record buttons, add a how-it-works tour, and fix empty/status copy. Mostly S-effort copy + one small sheet, and it directly determines whether a new user ever reaches their first win.
>
> **2. Decision & Commitment Ledger (#2 + #3).** Two independent agents (power-pkm and manager) converged on this — the strongest cross-persona signal. Turning scattered summary prose into a queryable ledger of who-decided/owes-what, with directed iOwe/theyOwe commitments, unlocks both leadership follow-through and org memory. The `Decision`/`DecisionStore` scaffold already exists.
>
> **3. Frictionless encounter logging + check-in notifications + health score (#4 + #5 + #8).** This trio is the relationship-tracking habit loop: one-tap log → visible score → proactive nudge. The model layer is ready; without these three the entire drift-detection system stays passive and the People tab stays 40% built out.
>
> **4. Universal indexed backlinks + forward/back navigation (#6 + #17).** Together these turn the vault from a set of siloed lists into a navigable graph. Every entity becomes a context hub, and users can trace and retrace ideas across meetings/tasks/people in one or two keystrokes.
>
> **5. iPhone Shortcuts capture (#9).** The highest-leverage cross-device bet: native Siri/Shortcuts capture into the existing `_inbox` pipeline means "Hey Siri, note that…" lands in the vault with zero app-switching. Mostly client-side authoring on top of infrastructure that already exists.
