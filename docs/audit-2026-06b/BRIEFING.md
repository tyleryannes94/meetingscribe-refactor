# Shared Briefing — MeetingScribe 15-Agent Focused UX Audit (2026-06-11)

You are one of 15 expert agents auditing **MeetingScribe**. Read this whole file first.

## The audit's focus (the user's exact mandate)

> "Focused on usability, navigating the app, better integrating people into meetings and tasks, and overhauling the UX so everything looks clean and expensive."

Four pillars. Every recommendation must serve at least one:
1. **Usability** — fewer clicks, less confusion, faster time-to-anything.
2. **Navigation** — moving between meetings ↔ people ↔ tasks ↔ notes should feel instant and obvious.
3. **People integration** — people should be first-class citizens *inside* meetings and tasks, not a separate tab.
4. **Premium visual overhaul** — "clean and expensive." Think Things 3, Craft, Linear, Notion Calendar. Not just consistent — *desirable*.

This is NOT a reliability/security/monetization audit. Skip those unless a finding directly blocks one of the four pillars.

## The target (what it is)

MeetingScribe is a 100%-local macOS (Tahoe) meeting recorder + relationship "second brain": records mic+system audio, transcribes locally (WhisperKit), summarizes via Ollama, stores everything in a markdown vault, and exposes it to Claude via a bundled MCP server. Swift/SwiftUI, ~349 Swift files / ~75K LOC. Also ships a token-gated mobile web app (8 tabs: Today · Meetings · Tasks · Projects · People · Notes · Search · Ask AI) served over Tailscale.

Key surfaces:
- **Desktop app** — `Sources/MeetingScribe/`: `UI/` (~90 view files incl. `MainWindow.swift`, `TodayView`, `MeetingsView`, `MeetingDetail*`, `ActionItems*` ~9 files, `NotionDesign.swift` = the "NDS" design system, `WorkspaceRouter`), `People/` (`PersonDetailView.swift` 2,300+ LOC, `PeopleListView`, `QuickEncounterSheet`, `SecondBrainDB`), `ActionItems/` (model/store layer), `Chat/`, `QuickNotes/`, `Calendar/`, `Followup/`.
- **Mobile web** — `Sources/MeetingScribe/Web/` (`WebAssets.swift` holds the embedded HTML/JS/CSS, `WebAPI.swift`).
- **MCP server** — `Sources/MeetingScribeMCP/main.swift`.
- **Shared kit** — `Sources/VaultKit/` (incl. `RelationshipHealth`).

## Where to read the live source (cite file:line)

Read with the Read/Grep/Glob tools at: `/Users/tyleryannes/MeetingScribeRefactor`
(Shell path if you use bash: `/sessions/upbeat-admiring-heisenberg/mnt/MeetingScribeRefactor`)

## REQUIRED first step — read existing plans so you ADD net-new

Skim these before auditing (they are the "already planned" baseline):
- `docs/audit-2026-06/MASTER-PLAN.md` — the current 5-phase plan from a 25-agent audit (June 10). **Most important.**
- `docs/audit-2026-06/MORNING-REPORT.md` — what already shipped (PRs #89–#99: paywall wiring, relationship health score + badge + Today drift strip, App Intents, MCP search_everything, full mobile-web overhaul with editable everything + Ask AI).
- `docs/audit-2026-06/HELD-ITEMS.md` — items deliberately held (transcript-truncation fix, E2E harness, onboarding copy sweep, etc.).
- Optional, your lens only: `docs/audit-2026-06/GROUP-DESIGN.md` / `GROUP-PM.md` / `GROUP-END-USER.md` / `GROUP-COMPETITIVE.md`; `docs/design/WHOLE_APP_REFRESH.md`.

## What is ALREADY PLANNED (do NOT re-list — go beyond it)

The June-10 master plan already covers, in detail:
- **Navigation backbone (Phase 2A):** routing Today cards to canonical detail, one `NavigationSplitView` shell, an `EntityLink` open-anything protocol, `selectedPersonID` on the router, Recents rail + Cmd-K quick switcher, global forward/back stack (Cmd-[/]) + breadcrumbs, attendee chip hover-card with "Add to People", `ActionItemsViewModel` resurrection, month-view restore.
- **People/habit loop (Phase 2B):** cadence fields, chip-first encounter quick-log, auto-bump lastInteractionAt, calendar-aware drift, check-in notifications + Today drift strip (drift strip SHIPPED), health score + ring (score/badge SHIPPED), inner-circle strip, prompts library wiring, quiet 1:1 capture, growth themes, warm copy + photo avatars.
- **Tasks/commitments (Phase 2C):** directed commitments (iOwe/theyOwe + personID), inline meeting→task creation with bidirectional links, universal backlink index, Decision/Commitment Ledger UI.
- **Native muscle (2D/2E):** Reminders sync, Spotlight, WidgetKit, in-meeting scratchpad, mid-call recap, calendar auto-record, pre-meeting briefs, daily/weekly rituals, recording status feedback, diarization surfacing.
- **Engagement extras (2H):** follow-up lifecycle, 1:1 prep digest, Dynamic-Type round 2, drag-to-reorder affordance, daily-note journal, `[[`/`@person` autocomplete in MarkdownEditor, mobile review layout.
- **Phases 3–5:** full RAG "Ask your vault", knowledge-graph atoms, Apple Foundation Models, ambient capture, Obsidian-vault moat.

**Your job: endorse the 3–6 existing items that matter most through your lens (one line each), then propose NET-NEW improvements the plans miss. Novelty + specificity win. A net-new item may also be a concrete *redesign* of how a planned item should look/feel/behave — if the plan says "add Cmd-K" and you spec the exact premium interaction model it needs, that counts.**

## Guiding principles for this audit

- **Evidence over opinion** — cite `file:line` from the live source for every observation about the current app.
- **"Clean and expensive" is a falsifiable standard** — name the specific typography/spacing/color/motion/material decisions that currently read as cheap, and what the premium replacement is. Reference real benchmark apps.
- **People-first integration** — judge every meeting and task surface by "can I see and act on the humans involved, right here?"
- **Count the clicks** — for usability items, record before→after interaction cost (e.g. "log encounter: 5 clicks → 1").
- **Desktop is primary; web/MCP must not fork the mental model.**
- Distinguish clearly: endorsing-existing vs NET-NEW.
- Don't propose reliability/infra/test work — the prior audit owns that.

## Output — write a markdown file, then return a short summary

1. Write your full analysis to: `/Users/tyleryannes/MeetingScribeRefactor/docs/audit-2026-06b/findings/<YOUR_FILE>.md` (filename given in your task).
2. Structure it exactly as:

```markdown
# <Group> — <Sub-role>
> One-line lens statement.

## Full-app audit (through my lens)
Concrete observations, citing file:line. Strong / weak / missing.

## Existing-plan items I rank highest
3–6 items, one-line "why" each.

## NET-NEW recommendations
6–12 items NOT in the existing plans. Each:

### <PREFIX>-<n> — <Short title>
- **What/why:** ...
- **User value:** ...
- **Effort:** S / M / L
- **Impact:** High / Med / Low
- **Depends on:** <IDs or none>

## Top 3 picks
3 highest-conviction net-new items + the single highest-priority rec overall.
```

3. Then return (final message) a ~120–150 word summary: your role, top 3 net-new picks, single highest-value rec.

Be concrete and opinionated. Cite code. Avoid generic advice. Use the ID prefix assigned in your task.
