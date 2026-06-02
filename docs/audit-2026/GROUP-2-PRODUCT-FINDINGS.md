# Group 2 — Product Strategy Findings Summary
> 5 agents: P1 Relationship Types · P2 Retention · P3 Content · P4 Monetization · P5 MCP Expansion
> Date: 2026-06-02

## Convergence (themes 3+ agents independently raised)

| Theme | Agents | Signal |
|---|---|---|
| `RelationshipPath/PersonCategory` enum — missing at every layer (model, VaultKit DTO, MCP, UI) | P1, P2, P3, P4 | 🔴 CRITICAL keystone — blocks all type-path features |
| Zero relationship push notifications (birthday, drift, check-in reminders all absent) | P1, P2, P3 | 🔴 The only habit driver that works when user is not in app |
| Encounter data completely invisible to MCP — no `get_person_encounters` or `log_encounter` | P5, P1 | 🔴 Core coaching loop blocked |
| No monetization infrastructure anywhere in codebase | P4 | 🟠 Must ship before public release |
| Content frameworks (Gottman, love languages, attachment, NVC) entirely absent | P3, P1, P2 | 🟠 The "relationship coach" premise has no content |

## Top Picks Per Agent

**P1 (Relationship Types):** P1-1 — `RelationshipPath` enum on `Person` (keystone, hours, backward-compatible). P1-3 — Per-type check-in cadence overrides (daily partner / weekly family / biweekly closeFriend). P1-7 — Static per-type coaching prompt library (no AI required, immediate depth).

**P2 (Retention):** P2-1 — Per-person push notification scheduler with `checkInReminderDays` on `Person`. P2-4/P2-8 — Encounter heat map + goal-setting (habit visibility). P2-9 — Birthday/anniversary push notifications (`Person.birthday` exists, never pushed — 1 bug away).

**P3 (Content):** P3-2 — Relationship-type-aware AI analysis presets (Gottman/NVC/love-language lens per type, prompt rewrite only — no schema changes). P3-1+P3-5 — `RelationshipType` enum + per-person cadence notifications (structural foundation). P3-10 — One-tap "Log a moment" from Today's suggested-people strip.

**P4 (Monetization):** P4-1 — One-time $49 OR $79/year via Paddle + Sparkle (implement `LicenseStore` before public release). P4-3 — Monthly on-device Relationship Intelligence Report (Pro-only retention hook). P4-2 — `loveLanguage`, `attachmentStyle`, `relationshipType` as structured Pro fields.

**P5 (MCP):** P5-1+P5-2 — `get_person_encounters` + `log_encounter` (encounter history is completely invisible to MCP despite living on disk). P5-6 — `get_people_needing_attention` (port cadence logic from `SuggestedPeopleView.swift:95–102` to MCP). P5-12 — Birthday field bug: `PersonDTO.birthday` decoded but never written into `tool_getPerson` response (`main.swift:1094`) — **one line fix**.

## Critical Bug Found (P5)
**`Person.birthday` is silently dropped in every MCP `get_person` response.** `PersonDTO.birthday` is decoded correctly in `SharedModels.swift:202` but `tool_getPerson` in `main.swift:1094` never includes it in the returned dict. Birthday coaching is the highest-recall relationship moment and is currently blocked by a one-line omission.

## Single Highest-Priority Recommendation (Product Group)
**P1-1 / RelationshipPath enum on `Person` model** — the keystone schema change that every product, content, notification, and MCP feature depends on. Backward-compatible `decodeIfPresent`, ships in hours, unlocks the entire relationship-coach product surface. Do this before any other People investment.

## Detail Files
- `findings/P1-relationship-types.md`
- `findings/P2-retention.md`
- `findings/P3-content.md`
- `findings/P4-monetization.md`
- `findings/P5-mcp-ai.md`
