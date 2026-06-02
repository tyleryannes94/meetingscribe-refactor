# Group 5 — Competitive & Industry Findings Summary
> 5 agents: C1 Direct Competitors · C2 Mental Health Apps · C3 Habit/Coaching · C4 AI/MCP Trends · C5 Pricing
> Date: 2026-06-02

## Convergence (themes 3+ agents independently raised)

| Theme | Agents | Signal |
|---|---|---|
| `RelationshipType` field missing — every competitor has relationship-type gating | C1, C2, C3 | 🔴 Market standard that MeetingScribe lacks entirely |
| One-tap / chip-first encounter logging — Daylio model — is the market standard | C2, C3, C1 | 🔴 Current 5-step form will kill the logging habit |
| Proactive notification cadence (daily prompt, drift alert) is the retention mechanic behind every successful app | C1, C2, C3 | 🔴 MeetingScribe is entirely passive |
| NEW: Sparkle is silently dead — `UpdaterController.isConfigured` returns false | C5 | 🔴 No auto-updates = no ability to ship fixes to users |
| NEW: Granola raised $125M at $1.5B (March 2026), pivoting to enterprise — individual user segment is open | C5 | 🟠 Massive positioning opportunity |
| MeetingScribe MCP server is invisible in the 10,000-server MCP ecosystem (no registry listing) | C4 | 🟠 Free distribution channel, zero code cost |
| Distress signal pre-flight filter needed before Ollama processes personal encounter notes | C2 | 🟠 Safety requirement for public release |

## New Critical Finding (C5)
**Sparkle is silently dead.** `UpdaterController` has `isConfigured = false`. The Sparkle `SUFeedURL` points at the wrong repo AND the update check is not configured to run. Users of any installed build will never receive an update. This must be fixed before any public release or the app becomes permanently stranded at whatever version users downloaded.

## Competitive Landscape Summary

**Direct competitors (C1):** Lasting (~$60/yr, therapy-backed content), Paired ($80/yr, daily questions + couples games), Relish (AI coaching + licensed therapists), Couply (free/freemium, shared journaling). MeetingScribe's moat: local-first (no data leaves device), all relationship types (not just couples), meeting transcription as relationship context, MCP for Claude. Gap: no structured check-in templates, no relationship type paths, no content framework.

**Mental health apps (C2):** Daylio's chip-first micro-journaling, Woebot's CBT delivery, Reflectly's warm conversational prompts. Key lesson: tone is everything. The difference between a journaling app people use and one they abandon is whether the copy feels like a curious friend or a clinical form.

**Habit/coaching apps (C3):** Fabulous's Journey model (content unlocks as streaks grow), Streaks' grace mechanics (amber decay, not reset), Finch's self-compassion framing for missed days. Key lesson: streaks must have grace or they cause abandonment.

**AI/MCP ecosystem (C4):** MCP ecosystem has 10,000+ servers. Granola and Dex are listed. MeetingScribe is invisible. Adding a `resources/list` endpoint (proactive context at session start) would differentiate from every listed server. `get_coaching_context` composite tool would be unique in the ecosystem.

**Pricing (C5):** Recommendation — free tier (5 people, 30 days history, unlimited meetings), Pro at $49/year or $79 lifetime (unlimited People, relationship type paths, check-in reminders, monthly report). Use LemonSqueezy (not Paddle — has built-in license key validation). Upgrade trigger: after first AI summary, not at a limit wall.

## Top Net-New Picks Per Agent

**C1:** C1-1 — RelationshipType field (M, unblocks personalization stack). C1-3 — Per-type structured check-in templates. C1-5 — Daily relationship prompt via macOS notification.

**C2:** C2-1 — Daylio-style chip-first encounter entry (S, replaces 5-step form). C2-3 — `RelationshipCoachPersona` constant in Ollama prompts (S, immediate tone shift). C2-4 — Distress signal pre-flight filter before AI processing encounter notes (S, **safety requirement**).

**C3:** C3-7 — Binary "Did you connect? Yes/Not yet" inline prompt in SuggestedPeopleView (S, one-tap habit formation). C3-2 — Streak grace mechanics (amber decay + `checkInPausedUntil` + re-entry affirmation). C3-1 — Progressive content arcs (4-week partner, 6-week close-friend) unlocking deeper prompts as encounter count grows.

**C4:** C4-1 — MCP `resources/list` endpoint with relationship brief (M, proactive context). C4-5 — `get_coaching_context` composite tool (M, unique in ecosystem). C4-6 — Publish MCP server to mcpservers.org/mcpmarket.com (S, **zero code**, free distribution).

**C5:** C5-3 — "No Bot, No Cloud, No Subscription Required" positioning spine (zero cost). C5-1 — LemonSqueezy for licensing (saves 2-3 days vs Paddle). C5-7 — Upgrade prompt at first AI summary (3% → 6-8% conversion lift).

## Single Highest-Priority Recommendation (Competitive Group)
**Fix Sparkle (C5) + register the MCP server (C4-6) immediately — zero new features, massive impact.** Sparkle being silently dead means no user can receive any bug fix or feature. MCP registry listing is a free acquisition channel in a 10,000-server ecosystem where Granola and Dex are already listed. Do both before any public announcement.

## Detail Files
- `findings/C1-direct-competitors.md`
- `findings/C2-mental-health.md`
- `findings/C3-habit-coaching.md`
- `findings/C4-ai-mcp-trends.md`
- `findings/C5-pricing.md`
