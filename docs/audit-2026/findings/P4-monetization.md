# P4 — Product Strategy & Monetization Audit

**Lens:** What features justify a Pro tier; free vs. paid split; positioning for power users vs. casual users; competitor pricing benchmarks in meeting tools and relationship apps; right GTM model for a solo native macOS app.

**Date:** 2026-06-02 | **Auditor:** Product Strategy & Monetization (Agent P4)

---

## 1. Monetization Infrastructure Audit — Zero exists today

The codebase has **no paywall, licensing, tier, or entitlement logic anywhere.**

| File | Finding |
|---|---|
| `Sources/MeetingScribe/Models/Settings.swift` | Pure `UserDefaults` + `KeychainStore` for credentials. No `isPro`, `licenseKey`, `trialStartDate`, `featureFlags`, or Paddle/StoreKit import. All settings are universally accessible. |
| `Sources/MeetingScribe/UI/SettingsView.swift` | No Pro badge, no upgrade CTA, no plan indicator anywhere in ~500 lines. |
| `Sources/MeetingScribe/UI/IntegrationsView.swift` | All integrations (Linear, Notion, Google Drive, iMessage analysis, Ollama, MCP) exposed without gating. A fully free connection surface. |
| `Sources/MeetingScribe/Updates/UpdaterController.swift` | Pure Sparkle update flow — verifies EdDSA public key, no license check on update eligibility. Sparkle `SUPublicEDKey` placeholder (`REPLACE_WITH`) means the update channel is not yet live. |
| `Sources/MeetingScribeMCP/main.swift` | All 17 tools (12 read + 5 write) ungated. Full People graph, meetings, voice notes, iMessage analysis, action items — all exposed equally. |
| `Sources/MeetingScribe/AI/OllamaService.swift` | 100% local Ollama — no cloud API calls, no API-key metering, no usage accounting. No cost-per-call to gate on. |

**Conclusion:** The app is currently a zero-revenue, entirely free, local-first tool. There is no monetization infrastructure to preserve or migrate — you are starting from scratch, which is actually an advantage.

---

## 2. Market Context — Competitor Pricing

### Meeting recording tools (same product category)

| Product | Free | Pro/Premium | Notes |
|---|---|---|---|
| **Granola** | Limited history (25-note cap) | $14/user/month (Business); $35 Enterprise | Restructured 2026; was $18/mo individual. Bot-free like MeetingScribe. Cloud-first. |
| **Fathom** | Unlimited recording, 5 AI summaries/month | $19/mo (Premium); $29/mo (Team); $39/mo (Team Pro) | Free plan is genuinely useful but has the 5-summary cap. Cloud-first, SaaS. |
| **tl;dv** | Limited recordings | ~$18–29/mo | SaaS, bot-joins-meeting model. |

**Key insight:** Both Granola and Fathom are SaaS products with cloud infrastructure costs justifying $14–$39/user/month. MeetingScribe is fully local — no server, no API costs, no per-user infrastructure. This dramatically changes the pricing math: a much lower subscription or a one-time purchase can be profitable where SaaS cannot.

### Relationship / coaching apps (parallel product category)

| Product | Free | Paid | Model |
|---|---|---|---|
| **Lasting** (couples therapy) | 7-day trial | $29.99/mo, $59.99/3mo, $89.99/6mo | Subscription-only, iOS/Android. 300+ guided sessions. |
| **Paired** (couples habits) | 1 question/day, Sunday quiz | $6.99–$14.99/mo (one covers both partners) | Freemium; annual plan ~$83.99/couple. |
| **BetterHelp** (therapy) | None | ~$240–$360/month | Out of scope but sets ceiling expectation. |

**Key insight:** Relationship apps command $7–$90/month because users pay for emotional outcomes, not features. The willingness-to-pay is higher than productivity tools when the framing is personal growth and relationships vs. note-taking efficiency.

### Indie macOS benchmark

Premium native macOS apps (Raycast Pro, CleanMyMac X, Proxyman, TextSoap) typically price at **$8–$15/month** or **$30–$99 one-time**. The market strongly prefers one-time purchase for tools; subscription acceptable only when there is an ongoing cloud service or content update stream behind it. "Subscription fatigue" is a documented user complaint against SaaS productivity tools.

---

## 3. The Two-User Thesis — Meeting Tool vs. Relationship Coach

MeetingScribe currently serves two meaningfully different user archetypes who overlap but have different willingness-to-pay:

**Archetype A — The Power Meeting User**
- Professional, 10–30 recorded meetings/week
- Cares about: accurate transcription, action item extraction, Linear/Notion integration, MCP tools for Claude
- Comparable product: Granola, Fathom
- Willingness to pay: $10–$20/month or $79–$99/year if the product saves real work-hours
- Pain point: losing meeting content, manual follow-up, scattered notes

**Archetype B — The Relationship Coach User**
- Personal use, 0–3 meetings recorded/week
- Cares about: People CRM, check-in reminders, memory capture, communication analysis, relationship health
- Comparable product: Lasting, Paired, Notion-as-CRM
- Willingness to pay: $8–$15/month if framed as relationship investment, or $49–$79 one-time
- Pain point: forgetting people, letting friendships drift, poor communication with partner/family

**Current product split estimate:** The codebase depth is 70% meeting tool (transcription pipeline, Whisper, AI summaries, action items, Sparkle updates) and 30% People CRM. The People module (`PersonDetailView` at 1986 lines, `PeopleStore` at 1359 lines, 33 Swift files in `Sources/MeetingScribe/People/`) is already a substantial second brain. But to become a relationship coach that commands Lasting-level pricing, it needs the psychological framework depth that doesn't yet exist in code.

---

## 4. Existing Plan Items Worth Endorsing Through This Lens

**Highest-leverage existing items for monetization:**

1. **Speaker diarization unwiring** (already in MASTER_PLAN_V3 as a planned item) — this turns transcripts from a text dump into a structured conversation. Power users will pay for this specifically. Make it a Pro feature anchor.

2. **iCloud inbox watcher + date-partitioned vault** (AUDIT_REPORT confirms built) — this is a seamless sync story that justifies a premium over local-only competitors. Emphasize in pricing narrative.

3. **Write-capable MCP (5 write tools, AUDIT_REPORT confirms built)** — Claude integration at this depth is a genuine Pro differentiator vs. every competitor. No other meeting tool has this. Name it explicitly in the Pro tier.

4. **Per-tag summary templates** (MASTER_PLAN_V3 item 13) — templates per relationship type (1:1, partner check-in, family call) are the gateway to the relationship-coach Pro tier. Build before launch.

5. **"Stay in touch" nudges** (MASTER_PLAN_V3 item 9) — the `PeopleInsightsView` already surfaces `goneCold` logic (`PeopleInsightsView.swift:21-38`). This is within days of being a genuine retention hook. Shipped = Pro justification.

---

## 5. NET-NEW Monetization Recommendations

### P4-1 — Two-Tier Freemium: "MeetingScribe Free" + "MeetingScribe Pro" (effort: S–M)

**Recommended model: one-time purchase + annual subscription option.** Do NOT do SaaS-only subscription — you have zero server costs and your target audience (indie macOS power users) has documented subscription fatigue. The right model:

- **Free tier** (always free, no time limit): Record and transcribe up to 10 meetings/month. People CRM unlimited (unlimited people, memories, encounters). No AI features — transcription only, no summaries, no action-item extraction, no iMessage analysis. MCP server read-only (list_meetings, get_transcript). Basic relationship insights (PeopleInsightsView without AI analysis presets).
- **Pro** ($49 one-time OR $79/year): Unlimited recording. Full AI (summaries, action items, auto-people extraction). All MCP write tools. iMessage analysis + conversation analysis presets (`ConversationAnalysisPreset` — `PersonDetailView.swift:23–65`). Speaker diarization. All integrations (Linear, Notion, Google Drive). The relationship coach features below.

The one-time option captures the indie-Mac user. The annual option captures the recurring relationship-coach user who values content updates.

**Implementation:** Add a `LicenseStore` singleton backed by Keychain. Check `LicenseStore.shared.isPro` before presenting AI summaries, MCP write tools, and ConversationAnalysisPreset. Use [Paddle](https://paddle.com) for payment (no App Store 30% cut, works with Sparkle, 5% fee). Wire Sparkle's `SUFeedURL` to the correct repo (AUDIT_REPORT issue #5) before launch.

### P4-2 — Relationship Coach "Depth Pack" as Pro Content Layer (effort: M)

Position the pro version's People/relationship features separately from the meeting recording features in marketing. The relationship coach user does not care about Linear integration — they care about:

- Partner check-in templates with Gottman-backed prompts
- Love language tracking field on Person (`Person.swift` has `favorites: [String]` — add `loveLanguage: String?` and `attachmentStyle: String?` as structured fields)
- Monthly relationship health score computed from encounter frequency + memory richness + message activity
- "Relationship depth" nudge: "You haven't logged anything about [partner] in 12 days"

This creates a second marketing hook that reaches Paired/Lasting users who would never search for "meeting recorder."

**Free vs. Pro split for this cohort:** Free = unlimited People with basic memory capture. Pro = AI conversation analysis presets, monthly health score, partner/family type paths with structured templates, check-in cadence reminders per person.

### P4-3 — Pro Anchor Feature: "Relationship Intelligence Report" (effort: M)

Monthly (or on-demand) AI-generated report covering all tracked relationships: who you've drifted from, who's been most present, what recurring themes appear in conversations, upcoming birthdays and anniversaries. Delivered as a single markdown document. Uses existing local Ollama — no API cost.

This is a **Pro-only monthly deliverable** that creates subscription renewal motivation even when the user hasn't actively used the app that month. Comparable to Lasting's "weekly content" model but entirely on-device.

**Implementation anchor:** `OllamaService` can already run multi-step prompts. `PeopleStore` has all the data. The missing piece is a `RelationshipIntelligenceGenerator` that aggregates across all persons and produces the report. Effort: M (days).

### P4-4 — Upgrade Prompt Architecture: Contextual, Not Modal (effort: S)

Do NOT implement a nag modal or a locked feature that shows a paywall sheet. Instead:

- When a free user triggers an AI feature (e.g. "Summarize"), show a single inline banner: "AI features are Pro — one-time $49 or $79/year. [Upgrade] [Not now]". Banner dismisses and does not re-appear for 7 days.
- In Settings, add a "Plan" section at the top showing current status (Free / Pro). If Free, show a single "Upgrade" button with feature list. No aggressive CTAs elsewhere.
- The MCP tools: free-tier callers who invoke a write tool (`create_action_item`, `add_memory`, etc.) get a JSON error response: `{"error": "write_tools_require_pro", "upgrade_url": "https://meetingscribe.app/upgrade"}`. Read tools always work.

This respects the local-first, power-user audience while making the path to upgrade clear.

### P4-5 — Sparkle + License Gating Before Any Public Release (effort: S)

The Sparkle `SUPublicEDKey` is a placeholder (`REPLACE_WITH`) per `UpdaterController.swift:22-24`. The `SUFeedURL` points at the old repo per AUDIT_REPORT issue #5. Both must be fixed before any paid launch:

1. Generate an EdDSA key pair with `generate_keys` from Sparkle CLI.
2. Embed the public key in `Info.plist:SUPublicEDKey`.
3. Fix `SUFeedURL` in `Resources/Info.plist:45` to point at `github.com/tyleryannes94/meetingscribe-refactor`.
4. Wire the license check in `UpdaterController` so only Pro users get auto-updates (or offer updates free, with features gated — simpler to maintain).

Without this, the distribution channel doesn't exist for collecting revenue.

### P4-6 — "Relationship Coach" as a Distinct App Store Listing (effort: L, plan for v2)

Long-term: consider splitting into two apps sharing the same vault.

- **MeetingScribe** (meeting recording, $49 one-time) — targets Granola/Fathom users. Positioning: "No bot, no cloud, no subscription."
- **Second Brain** or **Vault** (relationship coach, $9.99/month) — targets Lasting/Paired users. Positioning: "Your private AI relationship coach. Everything stays on your Mac."

They share the same VaultKit, iCloud vault, MCP server. The user who buys both gets the power combination. This unlocks App Store discovery via two different search intents and allows category-specific pricing.

**This is a v2 play.** Ship as one app first, validate which cohort converts, then split if the data supports it. Effort: L (weeks of SwiftUI + App Store setup).

### P4-7 — "Free Forever" Limit: 10 Meetings, Not Trial Days (effort: S)

Do not use a time-limited trial. Time limits create "use it or lose it" anxiety and churn free users before they've experienced the value. Instead:

- Free = first 10 meetings get full AI features (summary, action items, auto-people extraction). Meeting 11+ records and transcribes but does not auto-summarize — user sees "AI features for this meeting require Pro."
- People module stays unlimited on free — it's the relationship coach hook that brings people back.
- iMessage analysis stays free for first 3 people, then Pro-only.

This mirrors Granola's history-cap approach but is more transparent and less frustrating. Users who hit the limit have already experienced enough value to make an informed upgrade decision.

### P4-8 — MCP Pro Tier Signaling to Claude (effort: S)

When the MCP server responds to tool calls, include the user's tier in the `list_people` and `list_meetings` responses: `"account_tier": "free"` or `"pro"`. Claude can then surface upgrade prompts naturally in conversation: "I see you're on the free tier — to analyze your iMessage history with this person, you'd need Pro." This turns the AI assistant into a passive sales layer without requiring any explicit paywall UI.

---

## 6. Top 3 Picks

### #1 — P4-1: One-time + Annual Freemium Architecture (highest priority)
This is the entire business foundation. Do this before shipping publicly. The model (one-time $49 OR $79/year, free tier with recording-only) fits the indie-macOS audience, avoids subscription fatigue, and has zero server cost justifying the lower price vs. Granola ($14/month = $168/year). Implement `LicenseStore` + Paddle checkout + Sparkle fix in one sprint before any public announcement.

### #2 — P4-3: Monthly Relationship Intelligence Report
This is the single strongest retention mechanic for the relationship coach cohort. A user who gets a useful monthly report stays subscribed even during weeks they don't open the app. It's differentiated from every meeting tool competitor (Granola has nothing like this) and directly competes with Lasting on emotional outcomes at a lower price point. All the raw data exists; the generator is the missing piece.

### #3 — P4-2: Structured Relationship Type Fields + Pro Content Layer
Adding `loveLanguage`, `attachmentStyle`, and `relationshipType` (partner/family/close-friend/colleague) to the `Person` model unlocks the multi-path UX the audit brief requests AND creates a Pro feature surface that no meeting tool competitor has. This is what makes the pitch "not just Granola with a CRM" — it becomes a genuinely different product for a different emotional job-to-be-done.

---

## 7. Free vs. Pro Feature Split Summary

| Feature | Free | Pro |
|---|---|---|
| Recording + transcription | Up to 10 meetings/mo | Unlimited |
| AI summaries + action items | First 10 meetings (trial) | Unlimited |
| People CRM (unlimited contacts) | Yes | Yes |
| Memory capture + encounters | Yes | Yes |
| Basic relationship insights (goneCold, birthdays) | Yes | Yes |
| Auto-people extraction from transcripts | First 10 meetings | Unlimited |
| iMessage analysis + ConversationAnalysisPreset | First 3 people | Unlimited |
| Speaker diarization | No | Yes |
| Linear / Notion / Google Drive integrations | No | Yes |
| MCP write tools (5 tools) | No | Yes |
| Relationship type paths (partner/family/friend) | No | Yes |
| Monthly Relationship Intelligence Report | No | Yes |
| Chat rail (local Ollama AI chat) | No | Yes |

---

## 8. Pricing Summary Recommendation

| Model | Price | Rationale |
|---|---|---|
| One-time purchase | $49 | Below Granola's annual cost ($168/yr), above impulse-buy threshold |
| Annual subscription | $79/year (~$6.60/month) | Below Paired ($83.99/yr/couple), above "too cheap to trust" |
| Lifetime | $149 (launch promo $99) | Rewards early adopters, generates upfront capital |

Sell via Paddle (direct, not App Store) to keep 95% margin. Use Sparkle for updates. Launch on Product Hunt + Hacker News framing: "Local-first meeting recorder + relationship second brain — no bot, no cloud, no subscription required."

Do NOT add App Store distribution initially — the local Ollama + Full Disk Access + MCP server requirements conflict with App Store sandboxing, and the 30% cut is not justified at launch volumes.
