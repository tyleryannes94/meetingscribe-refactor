# Audit 4 — Projects & Tasks: "Replace Notion" Audit

**Date:** 2026-06-06 · **Scope:** the MeetingScribe Projects/Tasks feature
(`Sources/MeetingScribe/ActionItems/*` + `Sources/MeetingScribe/UI/ActionItems*`,
`TaskPageView`, `TaskRowView`).

**Goal of this audit:** decide what it would take for MeetingScribe's
Projects/Tasks feature to become the user's **primary** task & project tracker —
the one that replaces **Notion / Linear / Asana / Things** — and lean into the one
edge none of them have: **tasks born from your own meetings, by AI.**

## How this was produced

Five independent expert agents each audited the feature against the live
codebase through a different lens, then wrote a findings doc. This folder
compiles them.

| # | Lens | Author role | Doc | Item IDs |
|---|------|-------------|-----|----------|
| 1 | Product / feature completeness | Senior PM | [findings/01_product_pm.md](findings/01_product_pm.md) | `PM-1…PM-21` |
| 2 | Notion-parity (docs + database + wiki) | PKM Product Strategist | [findings/02_product_notion_parity.md](findings/02_product_notion_parity.md) | `NP-1…NP-21` |
| 3 | UX / interaction | Senior Interaction Designer | [findings/03_design_ux_interaction.md](findings/03_design_ux_interaction.md) | `UX-1…UX-22` |
| 4 | Views, visual system & IA | Senior Visual/IA Designer | [findings/04_design_views_ia.md](findings/04_design_views_ia.md) | `VD-1…VD-21` |
| 5 | Modular backend / data architecture | Staff Backend Eng | [findings/05_backend_modular_eng.md](findings/05_backend_modular_eng.md) | `BE-1…BE-21` |

**Total: 106 grounded improvements** (each with `file:line` evidence,
recommendation, impact, effort, dependencies).

## Compiled outputs

- **[MASTER_PLAN.md](MASTER_PLAN.md)** — the 106 findings deduped across
  disciplines and sequenced into **7 phases**, with a theme→item cross-reference
  so nothing is lost.
- **[CLAUDE_CODE_BUILD_PLAYBOOK.md](CLAUDE_CODE_BUILD_PLAYBOOK.md)** — copy-paste
  prompts (one per phase) for Claude Code to build it all out, with ground rules,
  branch/PR model, and per-item references back to the findings.

## The one-paragraph takeaway

The feature already has impressively complete **structure**: Initiative › Project
› Task, three views (list/table/board), sections, labels, subtasks, bidirectional
Linear/Notion sync, a Notion-style page model, and AI extraction from meetings.
The gaps are in four places: (1) the **daily-use loop** is missing (reminders,
"My Work", recurring tasks, undo/trash, saved views); (2) **interaction speed**
lags Linear (no keyboard nav, no NL quick-add, partial bulk edit, read-only table
cells); (3) the **data layer** can't scale (a 759-line `@MainActor` god-store that
rewrites the whole JSON file on every keystroke, plus a live app↔MCP write race);
and (4) it's a **styled task list, not a database** (no custom properties, no
saved multi-views, no calendar/timeline, no relations/rollups, no block docs).
Win the daily loop, modernize the data layer, reach Notion's database bar, and
double down on the meeting-AI moat — and this becomes a credible replacement.
</content>
</invoke>
