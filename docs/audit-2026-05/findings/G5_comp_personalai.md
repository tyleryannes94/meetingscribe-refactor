# Competitive Analysis — Always-On Personal AI / Lifelogging / Recall

> **Lens:** Where is the "personal AI / total recall" puck going — Limitless (ex-Rewind), Microsoft Recall, Granola's second-brain pivot, wearable recorders (Plaud, Bee/Omi) — and how MeetingScribe's local-first, consent-bounded posture is a *strength* exactly where these products are bleeding trust.

---

## The 2026 landscape (live research)

The personal-AI / recall category went through a brutal year, and the throughline is **the privacy model, not the AI, decided who lived**:

- **Rewind → Limitless → Meta.** Rewind's original pitch was 24/7 local screen+audio capture, "your data stays on your device." In April 2024 it rebranded to **Limitless**, pivoted to a $99 always-on pendant, and moved the Mac app to a **cloud-connected** architecture. In **December 2025 Meta acquired Limitless**, halted new pendant sales, and **shut the Rewind Mac app down on Dec 19, 2025** (screen/audio capture disabled). A privacy-first local product became a Meta-owned cloud one — "a hardware pivot, cloud dependency, and a Meta acquisition that contradicted every privacy promise." [9to5Mac](https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/), [WinBuzzer](https://winbuzzer.com/2025/12/05/meta-acquires-ai-wearables-startup-limitless-kills-pendant-sales-and-sunsets-rewind-app-xcxwbn/)
- **Bee → Amazon.** Bee's $49.99 always-on bracelet "records everything it hears unless the user manually mutes it." **Amazon acquired Bee in July 2025.** Another always-on recorder absorbed by a hyperscaler. [TechCrunch](https://techcrunch.com/2025/07/22/amazon-acquires-bee-the-ai-wearable-that-records-everything-you-say/), [CNBC](https://www.cnbc.com/2025/07/22/amazon-ai-bee-wearable.html)
- **Microsoft Recall.** Postponed in 2024 after researchers found snapshots stored in **plaintext**; the loudest public sentiments were "Hell no" and "Why would anybody want this?" Relaunched April 2025 **opt-in by default**, encrypted, gated behind Windows Hello + a VBS enclave, with app/site filters. Yet **one year on (2026) it still raises red flags** — researchers keep extracting data, and **UPenn told admins to disable it** ("substantial and unacceptable security, legality, and privacy challenges"). [GeekWire](https://www.geekwire.com/2026/one-year-after-its-rocky-launch-microsofts-windows-recall-still-raises-security-red-flags/), [Computing](https://www.computing.co.uk/news/2025/microsoft-roll-out-recall-tool-copilot-plus-pc-amidst-continued-privacy-concerns), [DoublePulsar](https://doublepulsar.com/microsoft-recall-on-copilot-pc-testing-the-security-and-privacy-implications-ddb296093b6c)
- **Granola** is the one *adjacent* winner, and it's moving toward exactly the second-brain space — **"chat with detailed transcripts from any meeting… super-human memory,"** cross-meeting queries ("What did we decide about pricing last quarter?"), citations, and a **$125M raise in 2026** pivoting from prosumer notetaker to **"enterprise AI context layer"** with Spaces + MCP. But Granola is cloud, team-data-centric, and meeting-bounded. [Granola 2.0](https://www.granola.ai/blog/two-dot-zero), [Over the Anthill](https://overtheanthill.substack.com/p/granola)
- **Wearables that survived sell on privacy/control.** Plaud (NotePin/Note Pro) leans hard on **GDPR, ISO 27001/27701, SOC II, HIPAA** compliance and "data stays under your control." Omi went open-source. The market explicitly competes on trust now. [Plaud NotePin](https://www.plaud.ai/products/plaud-notepin), [UMEVO wars 2026](https://www.umevo.ai/blogs/ume-all-posts/wearable-ai-wars-2026-limitless-pendant-vs-bee-pioneer-vs-plaud-notepin)
- **The legal floor is rising.** 12 US states require **all-party consent**; leaving an always-on device capturing absent third parties is **federal wiretapping (up to 5 yrs / $250K)**; voiceprints trigger **Illinois BIPA**; *Brewer v. Otter.ai* alleges unlawful interception; **California SB 1130** would fine wearable recording in private business areas. Bee's design — **LED red only when *muted*** — is called out as a consent anti-pattern. [Recording Law](https://www.recordinglaw.com/wearable-recording-devices-at-work/), [Workplace Privacy Report](https://www.workplaceprivacyreport.com/2025/12/articles/artificial-intelligence/the-hidden-legal-minefield-compliance-concerns-with-ai-smart-glasses-part-2-two-party-consent-and-ai-note-taking/), [SF Standard](https://sfstandard.com/2025/08/05/ai-wearables-recording-devices/)

**Where the puck is going:** every competitor is racing to *life-bounded total recall + a personal AI over your whole life*, and every one is paying for it in distrust, acquisitions that break privacy promises, and live litigation. The market has been *taught*, hard, that **on-device + you-own-the-vault is the only durable trust position.** MeetingScribe already sits on that exact ground (whisper.cpp local, Ollama local, Obsidian markdown + SQLite vault you own). Its weakness is the inverse: it's **meeting-bounded** and only recalls what it explicitly recorded.

---

## Full-app audit (through my lens)

- **Capture is event-bounded, not ambient.** `AmbientMeetingDetector.swift:16` only watches `kAudioDevicePropertyDeviceIsRunningSomewhere` to *prompt* a meeting recording; `AppDetector.swift` watches for Zoom/Meet. There is no continuous-capture mode and no "day" as a first-class object. That is the right *default* — but it means the personal-AI / recall surface is entirely missing.
- **Recall today = per-meeting only.** Vault is per-meeting folders (`QuickNote.swift` shows `QuickNotes/<slug>/` with `note.json/audio.m4a/transcript.md`; meetings are date-partitioned). FTS5 exists (`People/SecondBrainDB.swift`, `WorkspaceIndex.swift`) but the plans only wire `searchAll()` into `GlobalSearchView` (V3 §4) — that's *search*, not *ask-my-life*. There is no timeline, no day-rollup, no "ask everything I've ever recorded."
- **The "ask" surface is meeting-scoped.** `Chat/` tools (`MeetingChatTools`, `PeopleChatTools`, `ActionItemChatTools`) and the MCP server (17 tools) let Claude query the vault per-entity. This is *already* a privacy-first version of what Limitless/Granola are building — but it's not framed or surfaced as "your personal AI over your whole memory."
- **Dictation/QuickNotes is the seed of a journal.** F5 `QuickDictation.swift` + `wasDictation` flag in `QuickNote.swift` already produce freestanding transcribed voice notes outside meetings. That's one short hop from a voluntary daily journal / lifelog stream — without any always-on recording.
- **Consent UX is meeting-implicit, not capture-explicit.** Recording is user-initiated, so consent is currently "the human chose to record this call." There is no recording indicator surfaced to *others*, no consent-mode, no retention policy — fine for bounded recording, but a gap the moment any ambient/continuous mode ships. Limitless's **Consent Mode** (voice-ID; only records the wearer until a new speaker verbally opts in) is the bar.
- **No retention/forgetting model.** The vault grows forever. Competitors now ship **custom audio-retention windows** (Limitless). MeetingScribe has no "auto-delete audio after N days, keep transcript" or "forget this meeting" primitive — both a privacy feature and a storage-hygiene one.

---

## Existing-plan items I rank highest (through this lens)

1. **Unified "find everything about X" → `GlobalSearchView` over FTS5 `searchAll()`** (V3 §4, REMAINING_WORK §4). This is the literal foundation of personal-AI recall. Endorse strongly — but it must evolve from keyword search into *grounded Q&A* (see C4-1).
2. **Write-capable MCP (done) + the MCP-as-personal-AI surface.** The 17-tool MCP is already the privacy-first answer to "a personal AI trained on your life," because the model runs against a vault *the user owns locally*. Endorse and lean into it as a positioning pillar, not a dev feature.
3. **Whisper model SHA-256 pin + onboarding consent (ENG-D).** Consent-and-integrity discipline is the brand. Generalize the consent pattern to *all* capture, not just model download.
4. **Speaker-labeled transcript & diarization surfacing** (V3 §4). Diarization is the technical prerequisite for *consent-mode* and for attributing recall answers to who said them — it's load-bearing for the personal-AI direction, not just polish.
5. **Two-binary always-on ScribeCore daemon** (REMAINING_WORK §2). An always-running daemon is the enabling architecture for any responsibly-scoped ambient/journal mode — but it raises the stakes on consent, which the plan doesn't address.

---

## NET-NEW recommendations

### C4-1 — "Ask My Memory": grounded Q&A over the whole vault (RAG, fully local)
**What/why:** A top-level "Ask" surface where the user queries their *entire* recorded history in natural language — "What did Sarah and I decide about the Q3 roadmap?", "Summarize everything about Project Frost across all meetings" — answered by the local Ollama model grounded in FTS5-retrieved chunks, **with citations back to specific meetings/lines.** This is exactly Granola's "super-human memory" and Limitless's "ask your past," but **100% on-device over a vault you own** — the privacy-first version nobody else can credibly ship. Builds on `searchAll()` + `OllamaChatClient` + the existing chat-tools plumbing; the retrieval layer is the new part.
**User value:** Turns a pile of transcripts into an actual second brain — the single biggest capability gap vs. the category leaders.
**Effort:** M (retrieval + prompt + citation rendering; infra mostly exists). **Impact:** High. **Depends on:** GlobalSearch/`searchAll()` wiring; diarization helps but isn't required.

### C4-2 — On-device Recall Timeline (the privacy-first answer to Microsoft Recall)
**What/why:** A scrollable, day-partitioned **timeline** of everything captured — meetings, voice notes, dictations, action items — as the primary "memory" navigation surface, with day/week/month zoom. This reframes the app from "a list of meetings" to "your recorded life, on a timeline you own." Crucially, it is **the anti-Recall**: no screenshots, no ambient screen capture, no plaintext snapshot store, no cloud — only things the user *chose* to record, encrypted/local. Reuse the orphaned `CalendarTabView` (~500 lines, flagged dead in V3 NAV-5) as the timeline scaffold instead of deleting it.
**User value:** The recall/lifelog UX people *wanted* from Rewind/Recall, minus the surveillance.
**Effort:** M (repurpose existing view + aggregate the vault). **Impact:** High. **Depends on:** NAV-5 decision (turn "delete CalendarTabView" into "repurpose as Timeline").

### C4-3 — Consent-First Always-On Mode (opt-in, indicator + consent-mode + retention)
**What/why:** A *responsibly scoped* continuous-capture mode that is **off by default, explicitly opt-in, and consent-correct by construction.** Concretely: (a) a persistent, visible **recording indicator** (menu-bar + on-screen) whenever continuous capture is live — never the Bee anti-pattern of "indicator only when muted"; (b) a **Consent Mode** modeled on Limitless: using `SpeakerDiarization`, only retain the *owner's* speech until a new speaker is detected, then **pause + require explicit confirmation** before persisting others; (c) a **jurisdiction-aware warning** at enable-time (12 all-party-consent states; wiretapping/BIPA risk) sourced from the legal reality above. This is the feature that lets MeetingScribe step toward life-bounded capture *without* inheriting the category's legal/trust liabilities.
**User value:** The only always-on recall a privacy-conscious user (or a lawyer) could actually say yes to.
**Effort:** L (capture mode + diarization gating + consent UX). **Impact:** High. **Depends on:** ScribeCore daemon (REMAINING_WORK §2), diarization surfacing.

### C4-4 — Daily Auto-Journal / End-of-Day Memory Digest
**What/why:** A once-a-day, locally-generated **journal entry** that rolls up the day from already-captured material — meetings attended, decisions made, action items created/closed, people talked to, voice notes — written as prose by Ollama and saved as a dated markdown note in the vault. This is V3's "end-of-day recap" (TDY-6) **promoted into a durable lifelog artifact** rather than an ephemeral UI panel: it becomes a searchable, queryable day-object that C4-1/C4-2 traverse.
**User value:** A self-writing journal/work-log with zero extra effort — the "personal AI narrates your life" promise, delivered from data you already chose to capture.
**Effort:** M. **Impact:** High. **Depends on:** TDY-6 (supersedes it); feeds C4-1/C4-2.

### C4-5 — Retention & "Right to Forget" policies (audio-vs-transcript TTL + per-item forget)
**What/why:** Per-vault retention controls — e.g. "delete raw audio after N days, keep transcript," "auto-purge meetings older than 1 year," plus a one-click **"Forget this meeting/person"** that hard-deletes across vault + FTS5 index + people graph. Limitless already ships custom audio-retention windows; MeetingScribe's vault grows unbounded forever. A *forgetting* primitive is both a privacy differentiator and a prerequisite for any always-on mode (C4-3).
**User value:** Storage hygiene + a genuine privacy guarantee competitors mostly fake.
**Effort:** M. **Impact:** Med-High. **Depends on:** none (touches Storage + index).

### C4-6 — Local "Personal AI" persona/profile that improves recall over time
**What/why:** A user-owned profile object (built from the People graph + recurring topics + the de-hardcoded user name) that the local model uses as standing context for every "Ask My Memory" query — preferred terminology, key people/projects, role — so answers are personalized the way Personal.ai promises, **without** sending anything off-device or "training on your life" in a cloud. Surfaced and *editable* by the user (transparency), and queryable ("who is my personal AI built from?").
**User value:** Personalized recall that's legible and owned, vs. an opaque cloud model "trained on you."
**Effort:** S-M (mostly prompt-context assembly over existing graph). **Impact:** Med. **Depends on:** C4-1.

### C4-7 — Consent receipts / capture provenance per recording
**What/why:** Stamp each meeting's `meeting.json` with a small **provenance/consent record**: capture method (manual / ambient-detected / continuous), detected speakers, whether consent-mode confirmation occurred, jurisdiction at time of recording. Surface a tiny "how this was captured" line in the detail view. Directly answers the *Brewer v. Otter.ai* class of risk — the user can prove *how* and *under what consent* something was recorded.
**User value:** Auditability and legal defensibility; reinforces the trust brand.
**Effort:** S. **Impact:** Med. **Depends on:** C4-3 for the richer fields (basic version stands alone).

### C4-8 — "Memory health" & coverage honesty
**What/why:** A small surface that tells the truth about what the vault does and doesn't remember: which meetings have transcripts vs. audio-only, gaps where capture failed, total recall coverage. Pairs with ENG-A (transcript-truncation) and ENG-E (backup honesty) — the personal-AI promise collapses the moment recall silently has holes. "You have 142 meetings, 9 missing transcripts — repair?"
**User value:** Trust through honesty; turns the ENG-A/ENG-E integrity work into a user-visible feature.
**Effort:** S. **Impact:** Med. **Depends on:** ENG-A.

---

## Top 3 picks

1. **C4-1 — "Ask My Memory" (local RAG over the whole vault).** The defining capability of this entire category, and MeetingScribe can ship the *only* version that's 100% on-device over a user-owned vault. This is the puck.
2. **C4-3 — Consent-First Always-On Mode.** The responsible, legally-aware way to extend from meeting-bounded toward life-bounded — the move that grows the moat instead of inheriting the category's distrust.
3. **C4-2 — On-device Recall Timeline (anti-Recall).** Reframes the product around *memory*, repurposes dead code, and plants a flag directly opposite Microsoft Recall's surveillance posture.
