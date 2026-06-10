# Senior Product Manager — Compiled Group Digest

_MeetingScribe Refactor audit (2026-06) · synthesized from 5 PM agents: strategy-roadmap, monetization, activation, retention, metrics_

## Executive Summary

MeetingScribe has built far more product than it has shipped *operationally*. Across all five PM lenses, the same pattern recurs: **the machinery exists but the wires are unconnected.** A full paywall, feature gates, coaching-content library, relationship-notification scaffolding, FTS5 search engine, diagnostics plumbing, and a 17-tool MCP server are all present in the codebase — yet none are surfaced in a user flow that converts, retains, or measures.

Three decisions and a cluster of one-line fixes dominate the priority stack:

1. **A keystone positioning decision** (meeting tool vs. relationship coach) that currently blocks coherent roadmap, pricing, and messaging. The codebase is ~70% meeting tool / 30% relationship coach and hedges both. Picking one is the difference between a defensible product and a feature-filled mess.
2. **Monetization is inert** — the paywall is never presented (no `.sheet` binding), gates are never enforced, and `overrideAllEnabled = true` means no developer has ever exercised the free tier. These are trivial-effort, transformational-impact fixes.
3. **The app measures nothing about activation or the core funnel** — no instrumentation of record→transcribe→summarize→action, no first-summary "aha," no north-star metric. Retention investment is currently guesswork.

The strongest **net-new** ideas (not in prior plans): activation funnel instrumentation + first-summary celebration, a **north-star "capture rate" metric**, the core meeting funnel waterfall, and a local A/B harness for prompt/model quality. The strongest **carried** ideas: the `RelationshipPath` enum (22-auditor consensus), per-person check-in notifications, "Ask your vault" on-device RAG, and the commitment ledger.

A recurring monetization theme worth surfacing to the master synthesizer: reframe the wedge from "privacy" (a qualifier) to **"compliance-grade local"** (a buyer requirement for legal/healthcare/finance), and **license the intelligence layer, not the data** — the vault stays free and exportable forever, which converts frictionless export from a monetization risk into a trust asset.

## Prioritized Recommendations

Ranked by impact-vs-effort. Phase 1 = pre-launch / unblock; Phase 2 = core differentiation; Phase 3 = depth & expansion.

| # | Title | Type | Area | Impact | Effort | Phase | Prior? |
|---|-------|------|------|--------|--------|-------|--------|
| 1 | Wire ProPaywallView to MainWindow (single `.sheet` binding) | fix | Monetization | transformational | S | 1 | yes |
| 2 | DECISION: choose core wedge — Meeting Tool vs Relationship Coach | new-feature | Strategy | transformational | S | 1 | no |
| 3 | Fix critical P0 bugs (daemon finalize, Sparkle keys, MCP birthday) | fix | Reliability | high | S | 1 | yes |
| 4 | Invert `overrideAllEnabled` + DEBUG paywall override toggle (QA enablement) | fix | Monetization | high | S | 1 | yes |
| 5 | Instrument the core funnel + activation events (record→transcript→summary→action) | new-feature | Metrics | high | M | 1 | no |
| 6 | Define north-star metric: "Capture rate" | improvement | Metrics | high | M | 1 | no |
| 7 | Monetization infra: one-time license + optional Intelligence+ subscription (LicenseManager, Ed25519, StoreKit) | new-feature | Monetization | transformational | M | 1 | yes |
| 8 | Day 0 onboarding: pre-seed 3 relationships + first-summary celebration | new-feature | Activation | high | M | 1 | partial |
| 9 | Reframe positioning: "compliance-grade local" + license intelligence not data | improvement | Monetization | high | S | 1 | yes |
| 10 | RelationshipPath enum in VaultKit (keystone for coach path) | new-feature | Vault | high | S | 1 | yes |
| 11 | Reliability/quality dashboards: cold-launch, RTF, health trends, crash counter | improvement | Metrics | high | S | 1 | yes |
| 12 | Per-person check-in notifications, wired end-to-end (snooze, quick-log, launch sync) + gate at 3-person cap | new-feature | Retention/Monetization | high | M | 2 | yes |
| 13 | Auto-bump `lastInteractionAt` from meetings + messages (truthful drift signal) | fix | Vault | high | M | 1 | yes |
| 14 | Daily recap + Friday weekly-review ritual; morning brief; re-engagement banner | new-feature | Retention | high | M | 2 | yes |
| 15 | Enrich meeting-start notification with pre-meeting brief | improvement | Retention | high | M | 2 | yes |
| 16 | Wire RelationshipPromptLibrary into PersonDetailView (Pro-gated, blurred teaser) | new-feature | Monetization | high | S | 2 | yes |
| 17 | Chip-first inline encounter quick-log on PersonDetailView | new-feature | Vault | high | S | 2 | yes |
| 18 | Surface speaker diarization + attribute action items (meeting-tool diff) | new-feature | Meetings | high | M | 2 | yes |
| 19 | Follow-up lifecycle tracking + "drafted-but-unsent" nudge | improvement | Retention | high | M | 2 | yes |
| 20 | MCP write tools + relationship-health/encounter tools (coach assistant) | new-feature | MCP | high | M | 3 | yes |
| 21 | "Ask your vault" — local on-device RAG over all meetings (FTS5 + Ollama) | new-feature | Recall | transformational | L | 3 | yes |
| 22 | Decision & Commitment Ledger — who owes whom across meetings | new-feature | Recall | high | L | 3 | yes |
| 23 | Free tier (10 meetings/mo, People unlimited) + Plan section w/ price anchors | new-feature | Monetization | medium | S | 1 | yes |
| 24 | Local A/B harness + extended summary feedback (prompt/model quality loop) | new-feature | Metrics | medium | M | 2 | partial |
| 25 | Decompose PersonDetailView god-file (~1,986 LOC) | tech-debt | Code Health | medium | L | 2 | yes |

## Top 5 Bets

> **1. Wire the paywall (1 line) and fix the gate defaults (Items 1, 4).** The entire designed monetization system — `ProPaywallView`, `FeatureGate.showPaywall()` call sites, the coaching/people/notification gates — is one `.sheet(item:)` binding away from working, and `overrideAllEnabled = true` means no one has ever tested it. Transformational impact, S effort. Ship this week.
>
> **2. Make the wedge decision (Item 2).** Meeting tool ($10–15/mo, write-capable MCP + diarization) vs. relationship coach ($20–30/yr, typed cadences + Gottman content). Every prior plan hedged both. The decision unblocks pricing, messaging, and which Phase-2 features to build. Embed it in `MeetingScribeApp.swift` and `CLAUDE.md`.
>
> **3. See the funnel (Items 5, 6).** The app is blind to whether users ever complete record→summarize, and has no north-star. Local-only event instrumentation + a "capture rate" metric turns retention work from guesswork into engineering. Net-new and foundational for everything downstream.
>
> **4. Land the Day-0 aha (Item 8).** TodayView opens blank — the #1 conversion-blocking gap. Pre-seed 3 relationships in 2 minutes, then celebrate the first AI summary with a one-time "you did it" moment. Emotional investment within 2 minutes turns installs into subscribers-in-waiting.
>
> **5. Close the relationship habit loop (Items 12, 13).** Per-person check-in notifications are the only mechanic that pulls a lapsed user *back* on behalf of a real person they care about — but they only fire on manual encounter logging today, and the drift signal cries wolf because `lastInteractionAt` ignores actual meetings/messages. Fixing the signal (Item 13) and wiring notifications end-to-end (Item 12), with the 4th-person paywall as the highest-emotional-intent upgrade moment, is the retention + monetization keystone.

## Notes for the Master-Plan Synthesizer

- **Heavy convergence** on monetization-as-plumbing across strategy and monetization agents; merged into Items 1/4/7/16/23. Pricing specifics diverged (LemonSqueezy/$49 one-time vs. one-time $79–99 + Intelligence+ $89/yr); both framings preserved under Item 7 — resolve once the wedge (Item 2) is decided.
- **`RelationshipPath` enum naming caveat:** prior memory notes the enum already exists as `RelationshipType` in `Person.swift`, not `RelationshipPath`/`VaultKit`. Item 10 should be treated as *verify-and-extend* (defaults, cadence fields, migration), not net-new from scratch.
- **MCP recommendations** appeared in 3 agents (read tools, write tools, encounter/health tools) — merged into Item 20. Gate write tools to Pro per Item 7.
- **Notification recommendations** (per-person check-in, daily/weekly recap, morning brief, re-engagement, follow-up nudge, unified control panel) were split across retention; consolidated into Items 12/14/19 plus a unified Settings Notifications panel folded into Item 14's scope.
