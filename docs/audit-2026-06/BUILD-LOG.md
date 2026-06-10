# Phase Build Log — audit-2026-06

Autonomous overnight build of the unified master plan. One line per merged increment.

| When | Phase | PR | Release | What shipped |
|------|-------|----|---------|--------------|
| 2026-06-10 | 1 · monetization+integrity | #89 ✅merged | v1.4 | Paywall sheet wired in MainWindow; `ManagedFeature: Identifiable`; DEBUG override flipped to false + `--dev-unlock` + `simulateFreeTier` QA toggle; `RelationshipType.color` (NDS-backed); ProPaywallView migrated to NDS tokens; `insertPerson` now persists v3 columns; v2/v3 SQLite migrations wrapped in transactions. |
| 2026-06-10 | 1 · MCP | #90 ✅merged | v1.4 | MeetingScribeMCP bumped to 2025-06-18 spec + `tools.listChanged` capability; `get_coaching_context` now covers friend/colleague/acquaintance (was generic default). |
| 2026-06-10 | 1 · observability | #91 ✅merged | v1.4 | Local-only `ActivityLog` funnel (appLaunch/recordStart/recordStop/summaryReady/failed); `captureRate` north-star proxy; privacy-safe append-only JSONL in App Support. |
| 2026-06-10 | — | — | v1.4 ⚠️ | `make install` ✅ updated `/Applications/MeetingScribe.app`. `v1.4` tag pushed but Release workflow **fails fast** (same as v1.2/v1.3 — CI billing block / missing `SPARKLE_PRIVATE_KEY` / `SUFeedURL` points at old repo). Local app current; work-MacBook auto-update blocked until pipeline fixed — see HELD-ITEMS #3. |
| 2026-06-10 | 2 · health score | #92 ✅merged | v1.5 | `VaultKit.RelationshipHealth` — shared, pure 0–100 score + band (thriving/steady/drifting/overdue), zero migration; `get_relationship_health` MCP tool; 5 unit tests (all green). |
| 2026-06-10 | 2 · health badge | #93 ✅merged | v1.5 | Connection-health capsule on PersonDetailView identity panel (band color + score + a11y), same formula as the MCP coach tool. design-lint clean. |
| 2026-06-10 | 2 · MCP search | #94 ✅merged | v1.6 | `search_everything` MCP tool — vault-wide keyword recall across meetings + people. |
| 2026-06-10 | 2 · App Intents | #95 ✅merged | v1.6 | Capture Quick Note + Add Action Item Siri/Shortcuts intents (drop to `_inbox/`, work app-closed). |
| 2026-06-10 | 2 · Today drift | #96 ✅merged | v1.6 | Today "Stay connected" ordered by health, band-colored. design-lint clean. |
| 2026-06-10 | web · mobile app | #97 ✅merged | v1.6 | Phone web app: Today home dashboard, relationship health everywhere, quick-log encounters, `/api/today`. **`make install` + relaunch done — live over Tailscale.** |
