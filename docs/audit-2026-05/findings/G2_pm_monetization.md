# Group G2 (Product) — Monetization, Pricing & Positioning

> Lens: treat MeetingScribe as a commercial product. Where is the wedge, what's the durable moat vs Granola/Otter/Fathom, how do you package and license a *local-first, server-less* app, and what features actually justify payment?

## Full-app audit (through my lens)

**There is zero monetization machinery in the codebase today.** A full-tree grep for `license|paywall|subscription|trial|StoreKit|entitlement|purchase|activation` returns no product code — only a license header, a Notion settings string, and "free API" copy in `IntegrationsView.swift:44`. The app is 100% ungated. That's correct for a personal tool, but it means *everything* in the monetization plan is greenfield: there is no `LicenseManager`, no feature-flag gate, no receipt validation, no offline activation. This is the single biggest gap between "personal app" and "sellable product," and the existing plans (V3, REMAINING_WORK) **do not mention it at all** — only the older `docs/MeetingScribe_Subscription_Audit.docx` does, and even there it's a §6.7 footnote ("add licensing/entitlement gating").

**The moat is real and load-bearing, but it's also the COGS story, not just a privacy story.** `OllamaService.swift:5` runs entirely against `127.0.0.1:11434`; transcription is local whisper.cpp. The prior audit's best single insight (docx §4 TIP): *competitors all carry a per-minute cloud-inference COGS line they bury in pricing; MeetingScribe has none.* This is the commercial crux. Otter/Fathom/Granola **cannot** offer truly unlimited transcription without margin erosion — MeetingScribe can give it away free forever. That asymmetry should be the headline of the positioning, not a tip buried on page 9.

**The wedge is mispriced as "privacy."** Privacy is the *qualifier*, not the wedge. Plenty of buyers say they want privacy and don't pay for it (see: the entire "privacy-respecting" graveyard). The actual wedge is narrower and sharper: **"the meeting tool that works where cloud tools are banned."** Legal, healthcare, finance, defense contractors, M&A, therapists, and anyone under NDA literally *cannot* paste a client call into Otter. For them local-first isn't a preference, it's a compliance requirement — and they have the highest willingness-to-pay. The docx gestures at this ("Compliance Mode... HIPAA/FINRA/attorney-client... niche but high willingness-to-pay") but files it as a low-impact Pro feature rather than recognizing it as **the beachhead segment**.

**The onboarding tax is currently a monetization-killer.** `OllamaService.swift:34-37` surfaces `brew install ollama` / `brew services start ollama` error strings to the user. A paying non-technical buyer who hits "Install it with `brew install ollama`" has already churned. The whisper model is a separate ~140MB silent fetch (`WhisperRunner.swift`, flagged ENG-D). **You cannot charge money for a product whose first-run requires Homebrew.** Bundling the inference runtime is a prerequisite to *any* paid SKU, not a polish item.

**The MCP server is an under-exploited monetization surface.** 17 tools (12 read + 5 write) let Claude Desktop/Cursor read and mutate the vault. No competitor exposes anything like this. The plans treat it as a feature; through a monetization lens it's a *developer/power-user wedge and a defensible category* ("the meeting vault you can program against"). It's also the only feature here that's genuinely uncopyable by Otter/Fathom without re-architecting around local files.

**Distribution surfaces that already exist and matter for packaging:** `Export/` has Obsidian, Google Drive, and a generic `MeetingExporter`; Notion + Linear sync exist. The vault is plain markdown + SQLite in iCloud Drive. This "own-your-data, no lock-in" posture is a *selling point* but also a *monetization risk* — if everything exports cleanly and the data is just files, what stops a user from churning the moment a subscription lapses? (Answer below: license the *intelligence layer and the runtime*, never the data.)

**Sync/team are stubs.** `Sources/MeetingScribe/Sync/` contains only `iCloudInboxWatcher.swift`; the docx confirms CloudKit/Team are STUBs scoring 1/5. The prior audit's pricing ladder leans heavily on these (Pro = sync, Team = shared workspace) — i.e. it monetizes the two things that **don't exist and that contradict the local-first/no-server identity.** That's the central tension this audit must resolve.

## Existing-plan items I rank highest (through my lens)

1. **Write-capable MCP (V3 §4, shipped).** The single most defensible, uncopyable feature. It's the foundation of a "programmable meeting vault" positioning and a developer/prosumer price tier. Endorsed as the *anchor* of differentiation.
2. **Send-the-follow-up in Mail + schedule-next-meeting via EventKit (V3 §4, partly shipped).** Closing the loop from transcript → sent email is the moment a user feels daily ROI — the emotional trigger for upgrading. High monetization leverage per unit effort.
3. **Cross-meeting intelligence / unified `searchAll()` → GlobalSearchView (V3 §4, REMAINING_WORK §4).** This is the textbook *retention-driven paywall*: it's worthless on day 1 and invaluable after a month of history. It pulls users into paying *after* they're locked in by their own accumulated data — the healthiest possible conversion mechanic for a local app.
4. **ENG-D: bundle/consent the model download + warm Whisper.** Reframed through my lens: this is not just integrity, it's the **paid-launch gate** — no friction-free first run, no sellable product.
5. **Stay-in-touch nudges (V3 §4).** The relationship-graph CRM is the feature set Otter/Fathom/Granola structurally lack (they're transcript tools, not relationship tools). Endorsed as the basis for a *non-meeting* positioning angle ("personal CRM that happens to record meetings").

## NET-NEW recommendations

### P3-1 — Lead with "compliance-grade local" as the wedge, not "privacy" (positioning)
**What/why:** Re-anchor the entire go-to-market on the segment that *cannot legally use cloud tools* — legal, healthcare, finance, therapy, M&A, defense. Build one artifact: a one-page "Why your security team will approve MeetingScribe" (no data egress, on-device inference, auditable local vault, no vendor DPA needed). Position copy: *"Record the calls Otter won't let you."*
**User value:** Gives the highest-WTP buyers a reason to pay that no competitor can match.
**Effort:** S (positioning + one doc; the technical truth already exists). **Impact:** High. **Depends on:** nothing.

### P3-2 — License the *runtime + intelligence*, never the data (licensing model for a server-less app)
**What/why:** The correct license boundary for a local-first app with exportable plain-markdown data is: **the vault is always free and yours; the on-device intelligence and conveniences are licensed.** Concretely, build a `LicenseManager` that gates *features* (cross-meeting intelligence, follow-up generation, advanced templates, the warm-model fast path), validated by a signed offline license file (Ed25519 public key embedded in the app, license blob checked locally — no server, works on a plane). If the license lapses, the user keeps every recording, transcript, and the read-only MCP; they lose the *new* AI conveniences. This makes churn non-catastrophic (good for trust, good for word-of-mouth) while still creating recurring value.
**User value:** "You can never lose access to your own meetings" is itself a marketing line competitors can't say.
**Effort:** M. **Impact:** High. **Depends on:** nothing (this IS the missing scaffolding).

### P3-3 — One-time "lifetime local" license + optional intelligence subscription (pricing structure)
**What/why:** The prior audit copied the SaaS playbook ($12-15/mo Pro, $20-25/seat Team) — wrong shape for a local app with no COGS and no server to amortize. Local-first buyers (the Obsidian/Things/Bear crowd) *prefer one-time purchase* and distrust subscriptions for offline software. Propose a **hybrid**: (a) **MeetingScribe One** — one-time ~$79-99, perpetual license to the app + all local recording/transcription/CRM forever; (b) **Intelligence+** — optional ~$8-10/mo *only* for the features with ongoing model/maintenance cost (cross-meeting Q&A, auto follow-ups, prep briefs, new template packs). Frame the subscription as "the smart layer," not "the app." This matches buyer psychology for the segment and de-risks the "why pay monthly for software that runs on my machine?" objection.
**User value:** Aligns price model with how local-first buyers actually want to pay.
**Effort:** S (decision) + depends on P3-2 for enforcement. **Impact:** High. **Depends on:** P3-2.

### P3-4 — BYO-model as a *paid power-user tier*, not a default (BYO vs bundled)
**What/why:** Bundle a default model for everyone (P3 gate for launch). But expose, behind Intelligence+, a "bring your own model" panel: point summarization at any local Ollama model, an MLX model, OR (explicit opt-in, clearly labeled "leaves your device") a user-supplied Anthropic/OpenAI key for users who *want* frontier quality and accept the tradeoff. Today `OllamaService` hard-targets `llama3.1:8b` locally with no abstraction. Adding a provider-agnostic `SummarizationProvider` protocol turns "which brain runs your meetings" into a differentiating, monetizable choice — and lets the *same product* serve both the compliance buyer (local only) and the quality-maximalist (BYO key).
**User value:** One app spans "never leaves my Mac" to "use the best model" without forking the product.
**Effort:** M. **Impact:** Med-High. **Depends on:** P3-2 (gating).

### P3-5 — "Programmable vault" as a standalone prosumer/developer SKU (net-new tier the plans miss)
**What/why:** The 17-tool MCP server is a category no competitor has. Package it: a **Developer/Power tier** whose value prop is "your meetings are an API." Ship example recipes (auto-file action items to Linear, weekly digest via cron + MCP, "what did we decide about X" from the terminal). This reaches the Cursor/Claude-power-user audience — exactly the people who evangelize tools — and is essentially free to deliver since the code exists.
**User value:** Turns the meeting vault into automatable infrastructure.
**Effort:** S (packaging + docs/recipes). **Impact:** Med. **Depends on:** write-capable MCP (shipped).

### P3-6 — Team without a server: vault-federation over shared iCloud/Drive folder (team model for local-first)
**What/why:** The docx's "Team tier = shared workspace via CloudKit" contradicts the no-server identity AND doesn't exist. Net-new alternative: **team = a shared vault folder** (iCloud shared folder / Google Drive / a Dropbox the org already trusts) that multiple MeetingScribe installs read/write, with last-writer-wins + conflict files (the Obsidian Sync / git-style model). No MeetingScribe server, no DPA, data stays in *the customer's* storage. Sell it per-seat (~$15/seat) as "team meeting memory that never leaves your company's drive." This is the only team story consistent with the moat.
**User value:** Teams in regulated industries get shared memory without a third-party processor.
**Effort:** L. **Impact:** High (unlocks per-seat revenue). **Depends on:** P3-2.

### P3-7 — Time-to-first-value as the free-tier design constraint (packaging the free tier)
**What/why:** The free tier's job is *word-of-mouth*, and the moment that earns it is the first auto-generated summary + sent follow-up. Make Free unmistakably generous on *local* capability (unlimited recording/transcription/CRM/export — it costs you nothing, per the COGS asymmetry) and put the paywall only at the *post-history* intelligence. Explicitly do NOT gate transcription minutes or recording count — that's competing on Otter's turf where you have no advantage. The differentiation copy writes itself: "Unlimited, because we don't pay per minute."
**User value:** Free tier is genuinely useful forever; converts on depth, not on artificial limits.
**Effort:** S (a packaging decision). **Impact:** High. **Depends on:** P3-2, P3-3.

### P3-8 — Anti-lock-in as an explicit, marketed guarantee (positioning + trust)
**What/why:** Turn the "it's just markdown + SQLite you own" property into a stated promise: a "Data Bill of Rights" — your recordings/transcripts/notes are plain files in your iCloud Drive, exportable any time, readable without the app, and you keep them if you stop paying. Competitors lock data in their cloud. This converts the *monetization risk* of frictionless export into a *trust asset* that drives purchase ("safe to try — you can never get trapped").
**User value:** Removes the #1 objection to paying for any subscription software.
**Effort:** S. **Impact:** Med. **Depends on:** nothing.

### P3-9 — Per-tag/persona template packs as paid micro-content (recurring value, low cost)
**What/why:** V3 already proposes per-tag summary templates (1:1 vs all-hands). Monetize the *library*: ship curated, profession-specific packs (sales-discovery, 1:1-coaching, legal-intake, user-interview-synthesis, standup) as part of Intelligence+, refreshed periodically. This gives a subscription *ongoing* delivered value (the hardest thing for local software to justify) without per-use COGS.
**User value:** Better summaries tuned to the user's actual job, improving over time.
**Effort:** S-M. **Impact:** Med. **Depends on:** per-tag templates (planned).

### P3-10 — A trust/quality landing surface before any paid launch (positioning prerequisite)
**What/why:** Before charging, the product needs a credible public face that states the moat plainly: on-device, no cloud, COGS-free unlimited, programmable, own-your-data. None exists today. Even a single static page + the "security team" one-pager (P3-1) is a launch gate — buyers in the compliance segment will not purchase software they can't vet. This is positioning infrastructure, not marketing fluff.
**User value:** Lets the highest-WTP buyers evaluate and approve the purchase.
**Effort:** S-M. **Impact:** Med-High. **Depends on:** P3-1.

## Top 3 picks

1. **P3-1 — Re-anchor the wedge on "compliance-grade local," not "privacy."** The single highest-leverage, lowest-effort move: it aims the whole product at the buyers who *must* use a local tool and pay the most. The technical truth already exists in the code; only the framing is missing.
2. **P3-2 — License the runtime + intelligence, never the data.** This is the missing scaffolding that turns a personal app into a sellable one, done in the *only* way consistent with a server-less, own-your-data product. Everything else (P3-3, P3-4, P3-6, P3-7) depends on it.
3. **P3-3 — Hybrid one-time license + optional Intelligence+ subscription.** Replaces the prior audit's mis-shaped SaaS ladder with a pricing structure that matches how local-first buyers actually want to pay, neutralizing the "why subscribe to offline software?" objection while still creating recurring revenue on the only features that carry ongoing cost.
