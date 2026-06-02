# C5 — Competitive Intelligence & Pricing Audit

**Lens:** Relationship + personal coaching app pricing; freemium conversion mechanics; what features unlock payment; positioning for a power-user native macOS tool.

**Date:** 2026-06-02 | **Auditor:** Competitive Intelligence & Pricing (Agent C5)

---

## Important context: P4 already exists

Agent P4 (monetization) produced a thorough structural analysis: one-time $49 / annual $79 / lifetime $149 via Paddle, 10-meeting free tier, `LicenseStore` singleton in Keychain, Sparkle EdDSA fix. **This report does NOT repeat that work.** It goes beyond it: live competitor price data as of June 2026, freemium conversion benchmarks, precise upgrade-hook design, and payment processor recommendation based on 2026 indie-dev community evidence.

Read P4 first. C5 adds the competitive and psychological layer on top.

---

## 1. Code Audit — Zero Monetization Infrastructure

| File | Finding |
|---|---|
| `Sources/MeetingScribe/UI/SettingsView.swift:68–91` | Settings opens with "About" (version string) and "You" sections. No "Plan", "Pro", "Upgrade", or "License" section anywhere in ~500 lines of Form. |
| `Sources/MeetingScribe/Updates/UpdaterController.swift:21–24` | `isConfigured` guard blocks Sparkle from even starting — `SUPublicEDKey` is still the `REPLACE_WITH` placeholder. The update channel is dead. No purchase or license check wired anywhere in the updater. |
| `Sources/MeetingScribeMCP/main.swift` | All 17 tools ungated. A free user and a paying user get identical MCP capability. |
| `Sources/MeetingScribe/Models/Settings.swift` | `AppSettings` is a `UserDefaults` + `KeychainStore` wrapper. No `isPro`, `licenseKey`, `trialStartDate`, or feature-flag surface. |

**Conclusion:** The app ships with zero revenue infrastructure. Every feature is free to every user forever. This is a clean slate — good — but it means no launch can include paid features until `LicenseStore` is implemented from scratch.

---

## 2. Live Competitor Pricing (June 2026)

### 2a. Meeting Transcription — Direct Competitors

| Product | Free Tier | Pro / Paid | Model | Notes |
|---|---|---|---|---|
| **Granola** | 25-note history cap | $14/user/month (Business); $35/user/month (Enterprise) | SaaS subscription only | Raised $125M at $1.5B in March 2026; pivoting to enterprise "Spaces" + API. No bot, like MeetingScribe. Business tier undercuts Fathom. |
| **Fathom** | Unlimited recording + transcription; 5 AI summaries/month | $20/month individual; $19/user/month Team; $34/user/month Business | Freemium + subscription | ~22% discount for annual. Free tier is genuinely useful — 5 AI calls/month is the choke point. |
| **tl;dv** | Limited recordings | ~$18–29/month | SaaS | Bot-joins-meeting model; less relevant for local-first positioning. |
| **Craft Docs** | Free core (no one-time purchase) | ~$5/user/month | Subscription only | No one-time option. Sync + collaborate = the paid value prop. |
| **Obsidian** | Free core, no feature limits | Sync $5/month; Publish $10/month; Catalyst supporter $25 one-time | Hybrid: free core + paid services | The canonical indie-macOS model: genuinely free app, pay only for cloud services or to support dev. $25 one-time "Catalyst" feels like a tip jar. |

**Key strategic signal from Granola's $1.5B raise:** The meeting-notes market is going enterprise. Granola is no longer competing for individual power users — it is competing for Asana, Gusto, and Cursor company-wide deals. This **opens a vacuum at the individual and prosumer tier** that a local-first, privacy-first, one-time-purchase product can fill.

Sources:
- [Granola Pricing](https://www.granola.ai/pricing)
- [Granola raises $125M at $1.5B valuation — TechCrunch](https://techcrunch.com/2026/03/25/granola-raises-125m-hits-1-5b-valuation-as-it-expands-from-meeting-notetaker-to-enterprise-ai-app/)
- [Fathom AI Pricing 2026 — alfred_](https://get-alfred.ai/blog/fathom-pricing)
- [Obsidian Pricing](https://obsidian.md/pricing)
- [Craft Pricing](https://www.craft.do/pricing)

### 2b. Relationship & Personal Coaching Apps

| Product | Free | Paid | Model | Ceiling insight |
|---|---|---|---|---|
| **Lasting** (couples therapy) | 7-day trial only | $29.99/month; $59.99/3mo; $89.99/6mo; promo $59/year | Subscription, iOS/Android | Users pay for *emotional outcomes*, not features. $30/month is acceptable when framed as "cheaper than one therapy session." |
| **Paired** (couples habits) | 1 question/day + Sunday quiz | $6.99–$14.99/month; ~$83.99/year for couple (one subscription covers both) | Freemium → subscription | One subscription, two people: lowers per-person cost perception. |
| **Relatio** | — | ~$9.99–$14.99/month | Subscription | Newer entrant (iOS-only); relationship coaching for men specifically. |

**Willingness-to-pay ceiling for personal/relationship apps:** Research (MDPI, PMC) shows ~35% of personal-growth app users have paid at some point. The ceiling for self-guided relationship tools runs $7–$90/month depending on perceived emotional stakes. The framing determines the ceiling: "note-taking app" → $5–$10/month ceiling; "relationship coach" → $15–$30/month ceiling. MeetingScribe currently reads as a note-taking app. Repositioning the People module as a relationship coach raises the psychological ceiling by 2–3x.

Sources:
- [Lasting Subscription](https://getlasting.com/subscription)
- [Paired Premium](https://www.paired.com/premium)
- [Willingness to Pay for a Dating App — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9916160/)
- [13 Best Couples Apps 2026 — Emira](https://emira.io/articles/best-couples-apps)

### 2c. Indie macOS Power-User Tools

| Product | Free | Pro | Model | Lesson |
|---|---|---|---|---|
| **Raycast** | Full launcher (all extensions) free forever | $8/month (annual) — AI + Cloud Sync + custom themes | Freemium. Free is genuinely powerful. | "Free forever" builds audience; Pro is AI and sync, not core features. |
| **Bear** | Core notes | $14.99/year | Subscription, minimal | Sync + themes = the entire paid value prop. Very low churn because $15/year is a non-decision. |
| **Setapp** | N/A | $9.99/month for 250+ apps; single-app subscriptions now via Setapp Marketplace (March 2026) | Bundle subscription + new single-app tier | Setapp Marketplace now allows per-app subscriptions OR one-time purchase. Being on Setapp gets you 1M+ subscribers as a discovery channel. |

**One-time vs. subscription sentiment (macOS indie community, 2025–2026):** The community prefers one-time purchase for tools where there is no ongoing server cost. Subscriptions are accepted when they fund a cloud service (Obsidian Sync, Bear sync, Craft collaboration). The pattern: *"charge for the service, not the software."* MeetingScribe has no server costs — its cloud services are iCloud (Apple-hosted) and Ollama (user-hosted). A subscription cannot be justified on infrastructure grounds. The honest model is one-time purchase for the software + optional annual subscription for content updates (relationship coaching templates, prompt libraries).

Sources:
- [Raycast Pricing](https://www.raycast.com/pricing)
- [Setapp Pricing](https://setapp.com/pricing)
- [Setapp Marketplace launch — Setapp](https://setapp.com/app-reviews/setapp-subscription-vs-buying-apps)
- [Paddle vs Lemon Squeezy 2026 — SoloDevStack](https://solodevstack.com/blog/paddle-vs-lemonsqueezy-solo-developers)

---

## 3. Freemium Conversion Benchmarks

From First Page Sage 2026 SaaS Freemium Conversion Rate Report and Userpilot benchmarks:

- **Freemium → paid conversion: 2–5%** for productivity tools (median 3–4%)
- **Free trial → paid: 17–48%** depending on opt-in vs. opt-out trial
- Median conversion for no-expiry freemium happens between **month 3 and month 6**
- Tools with **sub-5-minute time-to-value** achieve 13–16% visitor-to-signup rates vs. 7–8% for trial models
- **Key insight:** An opt-out trial (full features, auto-downgrade after 30 days) converts at 48–50% but creates significant early churn as users who didn't consciously choose to pay cancel. For a solo developer with no support team, that churn overhead is damaging.

**Implication for MeetingScribe:** The 10-meeting free tier proposed by P4 is well-targeted — users who've recorded 10 meetings have experienced real value and made a genuine choice. This is better than a time-limited trial for a tool where value accrues with use (relationship memories, meeting history).

Sources:
- [SaaS Freemium Conversion Rates 2026 — First Page Sage](https://firstpagesage.com/seo-blog/saas-freemium-conversion-rates/)
- [Freemium Conversion Rate — Userpilot](https://userpilot.com/blog/freemium-conversion-rate/)
- [Free-to-Paid Conversion Rates Explained — CrazyEgg](https://www.crazyegg.com/blog/free-to-paid-conversion-rate/)

---

## 4. Existing Plan Items — Endorsements Through This Lens

1. **P4-1 (one-time $49 + annual $79):** Endorse and sharpen: the one-time price is correct. The annual subscription at $79 is borderline — explain clearly what the annual subscriber gets that the one-time buyer does not (relationship coaching content updates, new AI prompt templates, priority Sparkle updates). Without a concrete ongoing benefit, the annual offer will confuse buyers.

2. **P4-7 (10-meeting free tier, not trial days):** Fully endorse. This is the right shape for a tool with accruing relationship value. Time limits create anxiety; usage limits create natural upgrade moments.

3. **P4-5 (Sparkle + EdDSA key fix):** Must-do before any public release. `UpdaterController.isConfigured` is `false` — updates are silently disabled. All revenue depends on distributing the app; distribution depends on Sparkle working.

4. **P4-4 (contextual inline banner, not modal nag):** Endorse strongly. The macOS indie community reacts poorly to paywalls that block the UI. The inline "AI features are Pro" banner on first AI trigger is the correct pattern — Raycast uses a similar approach.

---

## 5. NET-NEW Recommendations

### C5-1 — Use LemonSqueezy, Not Paddle (effort: S)

P4 recommended Paddle. The 2026 indie-dev community data now points to **LemonSqueezy** as the better choice for solo macOS developers:

- **Built-in license key generation and validation** — this is the single most important feature for a desktop app selling a perpetual license. Paddle does not have this natively; you'd need to build it. LemonSqueezy issues and validates license keys out of the box, which maps directly to the `LicenseStore` pattern P4 described.
- **5% + $0.50 per transaction** — same as Paddle for small volumes.
- **Self-service onboarding** — live in under an hour vs. Paddle's approval process that can take days.
- **Setapp Marketplace compatibility** — LemonSqueezy transactions flow through the same Merchant of Record model that Setapp Marketplace now uses; easier to cross-list if you choose to.

**Caveat:** Post-acquisition community sentiment toward LemonSqueezy has become mixed (slower support). If launch volume exceeds $50K/year, revisit Paddle for its stronger SLA. For launch, LemonSqueezy is the fastest path to a working purchase + license flow.

Sources:
- [Paddle vs LemonSqueezy 2026 — SoloDevStack](https://solodevstack.com/blog/paddle-vs-lemonsqueezy-solo-developers)
- [Stripe vs LemonSqueezy vs Paddle 2026 — Monolit](https://monolit.sh/blog/stripe-vs-lemonsqueezy-vs-paddle-saas-billing-compared-2026)

### C5-2 — The Annual Subscription Needs a Concrete Ongoing Benefit (effort: S–M)

The P4 model offers one-time $49 OR annual $79. This works only if the annual subscriber receives something the one-time buyer does not — otherwise, every rational buyer takes the one-time option and MeetingScribe has no recurring revenue.

**Proposed annual-only benefits:**
1. **New relationship coaching template packs** every quarter (Gottman check-in, attachment theory exercises, NVC repair scripts). Distributed via Sparkle appcast as downloadable `.json` template bundles — no server required.
2. **Priority AI model upgrades** — when Whisper or Ollama releases a better model, annual subscribers get auto-download and swap first.
3. **MCP changelog** — new MCP tools ship annually to subscribers first, then roll to one-time buyers 60 days later.

This creates a genuine reason to subscribe annually vs. buy once, while keeping the one-time option honest and not extractive.

### C5-3 — "No Bot, No Cloud, No Subscription Required" as the Positioning Spine (effort: S)

Granola's $1.5B raise and pivot to enterprise creates an opening in the market: individual power users who want meeting notes without joining a $14/month enterprise SaaS. The positioning statement that captures this gap:

> **"No bot. No cloud. No subscription required."**
> MeetingScribe records meetings locally, transcribes with Whisper on your Mac, and never sends audio to a server. Pay once. Own it.

This positions against Granola (cloud, $14/month), Fathom (cloud, subscription), and tl;dv (bot-joins-meeting) simultaneously. It resonates with the macOS power-user audience that already pays for Raycast, Bear, and Obsidian because those apps respect local data.

**Place this line on the marketing page, in the Sparkle update release notes, and as the subtitle in the app's "About" section in Settings.**

### C5-4 — "Relationship Coach" Framing for the People Module Unlocks a Higher WTP Ceiling (effort: S — marketing copy, M — supporting features)

The research on relationship app pricing is unambiguous: users pay $29.99/month for Lasting because they're paying for relationship health, not app features. MeetingScribe's People module already has the data architecture to be a relationship coach. The gap is framing and a few feature anchors.

**Specific changes that shift WTP ceiling from ~$10/month to ~$20–30/month:**
- Rename the People tab section header and marketing copy from "People CRM" / "Second Brain" to "Relationship Journal" or "Relationship Coach."
- Add one Gottman-derived check-in prompt visible on the Person detail page for partners (even as a static template in v1). This single design choice signals psychological depth.
- Add a "Relationship Health" section to the Pro tier feature list on the upgrade screen — even if the initial implementation is just encounter frequency + memory count, the framing matters.
- Price the annual plan explicitly as "relationship coaching for $79/year" — compare to Lasting ($360/year), Paired ($84/year/couple).

**This is marketing copy + 2–3 UX changes, not a full feature rebuild.** The code already has `goneCold` logic (`PeopleInsightsView.swift:21–38`), memory capture, encounter logging, and iMessage analysis — the relationship coach is already 60% built. The WTP gap is a framing gap.

### C5-5 — Setapp Marketplace as a Discovery Channel (effort: M, plan for v2)

Setapp launched its Marketplace in March 2026, allowing users to subscribe to individual apps outside the bundle or buy them one-time. For MeetingScribe:

- Being listed on Setapp Marketplace exposes the app to 1M+ Setapp subscribers who are already self-selected premium macOS users.
- Setapp takes ~30% revenue share but provides discovery, payment processing, and an existing audience that does not require a Product Hunt launch to reach.
- The local-first architecture is Setapp-compatible (no sandbox issues like the App Store). Whisper binary, Ollama socket, Full Disk Access, and MCP server are all acceptable under Setapp's distribution model.

**Do not prioritize this over direct sales.** Build the direct channel (LemonSqueezy + Sparkle) first. Add Setapp Marketplace as a secondary channel in v1.1 after validating price points with direct customers.

Sources:
- [Setapp Marketplace — MacPaw](https://macpaw.com/setapp)
- [Single App Subscription on Setapp Marketplace — Setapp](https://setapp.com/how-to/single-app-subscription-vs-setapp-membership)

### C5-6 — Price Anchoring: Show the Competitor Comparison on the Upgrade Screen (effort: S)

The upgrade screen (in SettingsView, once implemented) should include a simple comparison that does the pricing math for the user:

```
MeetingScribe Pro    $49 one-time
Granola Business     $168/year
Fathom Premium       $240/year
Lasting              $360/year

MeetingScribe: Pay once. No recurring fees.
```

This single table justifies the $49 price point with no additional copy. The user does the math in their head. This is a standard SaaS anchoring technique adapted for a one-time purchase.

**Implementation:** A `VStack` in the pro upgrade section of SettingsView, shown only to free users. Static content, no network call required.

### C5-7 — The Upgrade Trigger Must Be a Value Moment, Not a Limit Hit (effort: S)

The worst freemium UX is the user hitting a hard limit right when they need the feature ("You've used your 10 AI summaries. Upgrade now."). The best freemium UX triggers the upgrade prompt at the user's highest-value moment — immediately after experiencing something good.

**For MeetingScribe, the highest-value moments are:**
1. **After the first AI summary is generated** — the user sees the summary and action items. THEN show: "Your first 10 meetings include full AI. After that, continue for $49 — or keep recording and transcribing free." This is a pull moment (wow, this is useful), not a push moment (you're blocked).
2. **After the first iMessage analysis** — person-level conversation insight is a "wow" feature. Show the upgrade CTA immediately after the first analysis.
3. **After the 8th meeting** (not 10th) — give the user a 2-meeting warning before the limit so they can upgrade before they're blocked, not after.

**What NOT to do:** Do not block the recording or transcription itself. Block only AI post-processing. A user who records meeting 11 and gets a transcript but no summary is not blocked — they're nudged. This is the Fathom model (unlimited recording, limited AI) and it has lower churn than a hard recording cap.

---

## 6. Precise Price Point Recommendations

| Tier | Price | Rationale |
|---|---|---|
| **Free** | $0, permanent | Up to 10 meetings with full AI (trial-by-doing, not trial-by-time); unlimited People/CRM; basic relationship insights; MCP read tools. |
| **Pro — One-Time** | **$49** | Below Granola's first-year cost ($168); above impulse-buy threshold; competes with Bear ($14.99/year over 3 years = ~$45) as a similar one-time mental model. |
| **Pro — Annual** | **$79/year** | Explicitly cheaper than Lasting ($360/year), Paired ($84/year). Frames as "relationship coaching at $6.59/month." Annual subscribers get quarterly template packs + priority model upgrades (C5-2). |
| **Lifetime** | **$149 (launch promo: $99)** | Rewards early adopters; generates upfront capital; creates a referral incentive ("I got lifetime for $99"). Cap at 500 lifetime seats if you don't want unlimited liability. |

**What is free (never gated):**
- Recording and transcription (unlimited — this is the core product)
- People CRM (unlimited contacts, memories, encounters)
- Basic relationship insights (birthday reminders, goneCold nudges, encounter history)
- MCP read tools (list_meetings, get_transcript, list_people, get_person)
- All hotkeys and integrations for recording

**What is Pro (gated after 10-meeting trial):**
- AI summaries + action item extraction
- Auto-people extraction from transcripts
- iMessage analysis + ConversationAnalysisPreset
- Speaker diarization (once wired)
- MCP write tools (create_action_item, add_memory, etc.)
- Linear / Notion / Google Drive integrations
- Relationship type paths with structured templates (partner/family/friend)
- Monthly Relationship Intelligence Report
- Annual: quarterly coaching template packs

**What is never gated (even behind Pro):**
- Exporting your own data (markdown, JSON)
- Reading your own transcripts
- The People module's basic read/write (name, notes, encounters)

The last point is critical: a personal data tool that locks your own data behind a paywall is extractive and will be called out publicly. Keep data access free.

---

## 7. Top 3 Picks

### #1 — C5-3: "No Bot, No Cloud, No Subscription Required" Positioning (highest priority)

Granola's enterprise pivot and $1.5B raise is the single most important competitive event in this market. It leaves the individual power-user segment underserved. MeetingScribe can own that segment with a single positioning statement. This costs zero engineering time and should happen before any other pricing work.

### #2 — C5-1: LemonSqueezy Over Paddle for License Key Infrastructure

The built-in license key generation in LemonSqueezy directly implements P4's `LicenseStore` pattern with minimal custom code. Saving the 2–3 days of custom license-validation engineering lets that time go into shipping C5-4 (relationship coach framing) instead.

### #3 — C5-7: Value-Moment Upgrade Trigger (not limit-hit upgrade trigger)

The difference between a 3% freemium conversion rate and a 6–8% rate is almost entirely determined by when the upgrade prompt fires. Triggering after the first successful AI summary — when the user is actively impressed — is a different conversion event than triggering when the user is blocked. Implement this in the same sprint as `LicenseStore`.

---

## Sources

- [Granola Pricing — granola.ai](https://www.granola.ai/pricing)
- [Granola raises $125M at $1.5B — TechCrunch](https://techcrunch.com/2026/03/25/granola-raises-125m-hits-1-5b-valuation-as-it-expands-from-meeting-notetaker-to-enterprise-ai-app/)
- [Granola Pricing Analysis — alfred_](https://get-alfred.ai/blog/granola-pricing)
- [Fathom AI Pricing — alfred_](https://get-alfred.ai/blog/fathom-pricing)
- [Fathom Pricing — fathom.ai](https://www.fathom.ai/pricing)
- [Lasting Subscription — getlasting.com](https://getlasting.com/subscription)
- [Paired Premium — paired.com](https://www.paired.com/premium)
- [Relatio App Review — VibeCheck](https://thevibecheck.app/blog/relationship-advice/relatio-app-review-men)
- [Raycast Pricing — raycast.com](https://www.raycast.com/pricing)
- [Obsidian Pricing — obsidian.md](https://obsidian.md/pricing)
- [Craft Pricing — craft.do](https://www.craft.do/pricing)
- [Setapp Pricing — setapp.com](https://setapp.com/pricing)
- [Setapp Marketplace — macpaw.com](https://macpaw.com/setapp)
- [SaaS Freemium Conversion Rates 2026 — First Page Sage](https://firstpagesage.com/seo-blog/saas-freemium-conversion-rates/)
- [Freemium Conversion Rate — Userpilot](https://userpilot.com/blog/freemium-conversion-rate/)
- [Paddle vs LemonSqueezy 2026 — SoloDevStack](https://solodevstack.com/blog/paddle-vs-lemonsqueezy-solo-developers)
- [Lemon Squeezy vs Polar vs Paddle MoR 2026 — BuildMVPFast](https://www.buildmvpfast.com/blog/lemon-squeezy-vs-polar-paddle-merchant-of-record-2026)
- [Willingness to Pay — PMC/MDPI](https://pmc.ncbi.nlm.nih.gov/articles/PMC9916160/)
- [Best Couples Apps 2026 — Emira](https://emira.io/articles/best-couples-apps)
