# Competitive Analysis — AI Meeting Notetakers (Granola, Fathom, Otter, Fireflies, tl;dv, Zoom AI Companion, MS Copilot/Teams, Read.ai)

> Lens: feature-parity gap analysis against the 2026 commercial field. What competitors do that MeetingScribe doesn't, what MeetingScribe's local-first model does better, and the net-new bets that close real gaps. All competitor claims cited to live product/press sources (May 2026).

---

## The 2026 market shift (why this matters now)

The field has bifurcated. The dominant cloud players (Otter, Fireflies, Read.ai, Zoom, MS Teams, tl;dv) all run **recording bots that join the call as a participant** and ship audio to cloud servers. In 2026 this is now a liability, not a feature: enterprise IT/legal are banning bots over all-party-consent and wiretap exposure, the NYC Bar issued Formal Opinion 2025-6 warning that AI notetakers without strict consent risk confidentiality/privilege violations, and "bot fatigue" is a named market force ([Granola privacy](https://www.granola.ai/blog/ai-notetaker-participant-privacy-consent), [tl;dv on privacy](https://tldv.io/blog/ai-and-privacy/), [Fellow bot-free list](https://fellow.ai/blog/bot-free-ai-note-takers/)). The two bot-free leaders are **Granola** (system-audio capture, transcribe-then-delete) and MeetingScribe. **MeetingScribe is more private than Granola** — Granola still transcribes in the cloud and stores notes on Granola's servers; MeetingScribe transcribes (whisper.cpp) and summarizes (Ollama) 100% on-device with an Obsidian vault you own. That is a genuine, defensible moat the cloud field structurally cannot match.

But on **product surface area**, the field has moved well past single-meeting notes into three areas MeetingScribe largely lacks: (1) **cross-meeting / library-wide AI Q&A**, (2) **conversation intelligence** (talk-time, sentiment, topic trackers, coaching), and (3) **agentic post-meeting actions** (auto-CRM, auto-task, auto-email). The gap analysis below maps these.

---

## Full-app audit (through my competitive lens)

I read `MASTER_PLAN_V3.md`, `MASTER_PLAN_V2.md`, `AUDIT_REPORT_2026-05-30.md`, `docs/REMAINING_WORK.md`, and skimmed the live source. Current capability map vs the field:

**Where MeetingScribe is already at or ahead of parity:**
- **Bot-free local capture** — `ScreenCaptureKit` system audio + `AVAudioEngine` mic, on-device. Matches Granola's headline and beats every bot-based competitor on privacy/consent. This is the strongest single asset.
- **On-device transcription + summarization** — `WhisperRunner.swift` + `OllamaService.swift`. No cloud round-trip. Unique in the field; even Granola transcribes server-side.
- **MCP server (17 tools, 5 write)** — `Sources/MeetingScribeMCP`, `MCP/MCPInstaller.swift`. Granola, Zoom, and now several others ship MCP, but MeetingScribe's is *write-capable against a local vault* — it can mutate notes/people/tasks, not just read. That's ahead of most.
- **Relationship CRM / people graph** — `People/`, message history, memories, encounters. No mainstream notetaker has a real personal CRM; this is a differentiator the plans already recognize.
- **In-app chat over content** — `Chat/` (`MeetingChatTools`, `PeopleChatTools`, `FileChatTools`). This is the local analog of "Ask Fathom" / "Otter AI Chat" — but see gap C1-1 on cross-meeting scope.
- **Custom summary templates** — per-tag templates are *planned* (V3 §4). Granola ships 29+ templates plus shareable "Recipes" ([Granola recipes](https://www.granola.ai/blog/meeting-recipes-repeatable-formats)) — so MeetingScribe is behind here today but the plan points the right direction.

**Table-stakes / near-table-stakes the app LACKS (competitor-proven):**
- **Cross-meeting / vault-wide AI Q&A.** Otter "Cross-Meeting Intelligence" answers "what was the consensus on Q3 budget across all marketing meetings in December" ([Otter](https://otter.ai/blog/otter-ai-evolves-from-ai-notetaker-to-create-100b-enterprise-conversational-knowledge-engine-market)); Fathom expanded Ask Fathom from single-meeting to whole-library ([Fathom press](https://www.businesswire.com/news/home/20260415965820/en/)); Granola does folder-level chat across a collection with per-answer citations. MeetingScribe's chat appears scoped to one meeting/person at a time. The FTS5 `searchAll()` + Ollama exist — the wiring to "ask my whole vault" does not (this is the single biggest table-stakes gap).
- **Conversation intelligence** — talk-time/talk-to-listen ratio, sentiment, topic trackers. Fireflies ([conversation intelligence](https://fireflies.ai/conversation-intelligence)), Read.ai (engagement scores, sentiment trends, [metrics](https://www.read.ai/benchmarks)), tl;dv (speaker insights) all ship this. MeetingScribe has `SpeakerDiarization.swift` built but **not surfaced** — the raw material for talk-time exists, unused.
- **Agentic post-meeting actions** — auto-push to CRM, auto-create tasks, auto-draft+send follow-up. Zoom AI Companion 3.0 auto-converts action items to Zoom Tasks with owners/deadlines ([Zoom 3.0](https://news.zoom.com/zoom-launches-ai-companion-3-0/)); Fathom auto-logs to HubSpot/Salesforce; Read.ai Search Copilot Actions update CRMs and send emails. MeetingScribe has Linear/Notion sync and "open in Mail" but no *automatic* post-meeting fan-out.
- **In-meeting / live assistance** — Fireflies "Live Assist" coaching, Fathom live summaries, MS Teams Facilitator agent (live notes + agenda + task assignment [MS Facilitator](https://support.microsoft.com/en-US/teams/copilot/facilitator-in-microsoft-teams-meetings)). MeetingScribe does live 5-min-chunk transcription but no live *insight* surface.
- **Slide/visual capture** — OtterPilot 3.0 captures slides/whiteboards into the transcript at the right timestamp ([Otter](https://otter.ai/)). MeetingScribe is audio-only; it already holds Screen Recording permission via ScreenCaptureKit, so the capability is one frame-grab away.
- **Mobile / phone-call capture** — Granola records on-the-go and transcribes phone calls via iOS ([Granola App Store](https://apps.apple.com/us/app/granola-ai-meeting-notes/id6739429409)); Fathom/Otter/Fireflies all have iOS apps. MeetingScribe has the iCloud inbox + planned Shortcuts but no real mobile capture.

---

## Existing-plan items I rank highest (through my lens)

1. **Unified "find everything about X" — wire FTS5 `searchAll()` into `GlobalSearchView`** (V3 §4, REMAINING_WORK §4). This is the foundation for the #1 competitive gap (cross-meeting Q&A). I'd reframe it from "search" to "ask," but it's the right substrate. **Highest-leverage planned item.**
2. **Speaker-labeled transcript & surface `SpeakerDiarization.swift`** (V3 §4). Already-built code that unlocks the entire conversation-intelligence category (talk-time, per-speaker action items). Cheap unlock of a feature 4 competitors charge for.
3. **Per-tag summary templates** (V3 §4 / §3.4). Directly answers Granola's Templates+Recipes, which is its most-cited stickiness feature. Endorse — but expand to shareable/library form (see C1-7).
4. **Write-capable MCP (done) + "stay in touch" nudges** (V3 §4). The MCP writes are the local agentic substrate; nudges are the relationship-graph payoff no competitor has. Double down here.
5. **Send-the-follow-up (done) + schedule-next-meeting via EventKit** (V3 §4). The first step of the agentic-actions category the whole field is racing toward.

---

## NET-NEW recommendations

Each item is genuinely absent from V2/V3/REMAINING_WORK. Tagged with the competitor that proves demand.

### C1-1 — "Ask your vault" cross-meeting RAG chat (local)
**What/why:** Promote chat from single-meeting to vault-wide. Retrieve over the FTS5 v2 index + transcripts/notes, feed top-k chunks to Ollama, and answer with **inline citations to the source meeting/date** (Granola's folder-chat does exactly this with citations). Add scope chips: this meeting · this person · this tag · everything.
**User value:** Replaces "where did we decide X?" archaeology. The defining 2026 feature — and uniquely, MeetingScribe can do it without sending a byte to the cloud.
**Proven by:** Otter Cross-Meeting Intelligence, Fathom whole-library Ask Fathom, Granola folder chat.
**Effort:** M (retrieval glue over existing FTS5 + Ollama). **Impact:** High. **Depends on:** the planned `searchAll()` → GlobalSearchView wiring (build retrieval there, reuse in chat).

### C1-2 — Conversation-intelligence panel (talk-time, topics, sentiment) — fully local
**What/why:** Surface a per-meeting analytics tab driven by the existing `SpeakerDiarization.swift`: talk-to-listen ratio per speaker, a topic timeline (cluster transcript segments via local embeddings), and an optional on-device sentiment pass. No cloud — a privacy-respecting version of what Read.ai/Fireflies sell.
**User value:** "Did I dominate that 1:1?" / "How long did we spend on pricing?" — insight competitors gate behind paid tiers.
**Proven by:** Read.ai (engagement/sentiment), Fireflies (topic tracker, talk-to-listen), tl;dv (speaker insights).
**Effort:** L. **Impact:** High. **Depends on:** surfacing diarization (the planned item) first.

### C1-3 — Post-meeting "agentic action fan-out" (review-then-execute)
**What/why:** After finalize, generate a single **action card**: action items (push to Linear/Notion), a follow-up email draft (open in Mail), a "schedule next" EventKit event, and people-graph updates (new attendees → add to People). User reviews and one-click executes — local LLM proposes, user approves. This is the agentic loop, but consent-safe and local.
**User value:** Collapses 15 min of post-meeting busywork into one approval. Matches Zoom 3.0 / Fathom auto-CRM without the auto-without-consent risk.
**Proven by:** Zoom AI Companion 3.0 (auto-tasks w/ owners), Fathom (auto-HubSpot/Salesforce), Read.ai Search Copilot Actions.
**Effort:** M (orchestrates existing follow-up, Linear/Notion, EventKit, People writes). **Impact:** High. **Depends on:** existing send-follow-up + write-MCP work.

### C1-4 — Slide / screen-frame capture into the transcript
**What/why:** MeetingScribe already holds Screen Recording permission for audio. Periodically (or on slide-change detection) grab a frame, OCR locally (Vision), and pin the image + text into the meeting note at its timestamp. Optionally run on `AmbientMeetingDetector` triggers.
**User value:** "What was on slide 4?" — screen-share decks and whiteboards become searchable. Audio-only notetakers lose this entirely.
**Proven by:** OtterPilot 3.0 Visual Context (slides/whiteboards into notes at timestamp).
**Effort:** M. **Impact:** Med-High. **Depends on:** none (ScreenCaptureKit + Vision already on-platform).

### C1-5 — "Privacy posture" as a first-class, provable feature
**What/why:** Build a visible **Privacy panel**: "0 bytes left this Mac · transcribed on-device · audio retained N days · vault at <path>." Add a one-click "what gets recorded / consent script" helper and an in-app, copy-pasteable consent line. Make the moat legible, since the whole market is now fighting on exactly this axis.
**User value:** Turns the invisible local-first advantage into the explicit reason to choose MeetingScribe over Granola (which still uses the cloud). Directly answers the 2026 bot-backlash / NYC Bar concerns.
**Proven by:** Granola markets "transcribe then delete, nothing stored"; the entire bot-free-privacy category ([Fellow](https://fellow.ai/blog/bot-free-ai-note-takers/), [Granola privacy](https://www.granola.ai/blog/ai-notetaker-participant-privacy-consent)).
**Effort:** S-M. **Impact:** High (positioning). **Depends on:** ENG-E backup-honesty work (don't claim what isn't true).

### C1-6 — Trend / digest reports across recurring meetings & people
**What/why:** A recurring "report" surface: per recurring-meeting-series rollup (open action items, decisions, recurring topics) and a weekly digest ("here's what moved this week, who you didn't talk to"). Generated locally on a schedule.
**User value:** Turns a pile of notes into a narrative; the retention hook the field leans on.
**Proven by:** tl;dv Multi-Meeting AI Insights + recurring AI reports, Fathom account-wide insights, Zoom daily reflection workflows.
**Effort:** M. **Impact:** Med. **Depends on:** C1-1 retrieval; complements the planned end-of-day recap (TDY-6).

### C1-7 — Shareable / importable templates + a local "Recipes" library
**What/why:** Extend the planned per-tag templates into a file-based, shareable format (drop a `.template`/`.recipe` md into the vault; export/import; a few built-ins for 1:1 / sales / interview / standup). "Recipes" = saved post-hoc prompts ("draft exec summary," "extract feature requests") runnable from chat.
**User value:** Repeatable, standardized outputs — Granola users cite this as the stickiest feature; and a vault-native format keeps it local and version-controllable.
**Proven by:** Granola Templates (29+) + Recipes ([Granola](https://www.granola.ai/blog/meeting-recipes-repeatable-formats)).
**Effort:** M. **Impact:** Med. **Depends on:** the planned per-tag template item (this is its productized form).

### C1-8 — Auto-detected meeting purpose → template + brief selection
**What/why:** Use calendar metadata (title, attendees, recurrence) + `AmbientMeetingDetector` to auto-classify a meeting (1:1 / sales / interview / standup) and auto-apply the right template (C1-7) and pre-meeting brief. No manual tagging.
**User value:** Right format with zero setup; removes the friction Granola still requires (manual template pick).
**Proven by:** Granola's per-meeting-type templates (manual today) + Fathom's customizable per-team summaries — auto-selection is the unmet step.
**Effort:** S-M. **Impact:** Med. **Depends on:** C1-7, existing Calendar/Detection modules.

### C1-9 — On-device meeting coaching (private, opt-in)
**What/why:** After a meeting, an optional local-LLM coaching pass: filler-word count, monologue detection, question ratio, "you talked 78% of your 1:1." Entirely on-device — the privacy-safe version of cloud coaching tools.
**User value:** Self-improvement insight that users currently can't get without uploading their voice to a vendor.
**Proven by:** Fireflies Live Assist/coaching, tl;dv AI Coaching Hub + scorecards, Read.ai meeting coach.
**Effort:** M. **Impact:** Med. **Depends on:** C1-2 (diarization/talk-time).
**Note:** the old repo had a Coaching module that was deleted as unwired — this is a *focused, local, opt-in* revival, not the old orphan.

### C1-10 — Real mobile capture path (phone-call / on-the-go voice)
**What/why:** Beyond the planned Shortcuts, define a path to capture a phone call or in-person conversation on iPhone (record → drop audio into the iCloud `_inbox/` → Mac daemon transcribes locally). The inbox watcher already exists; this is the missing capture client.
**User value:** Coverage for the meetings that don't happen at the desk — a major Granola 2026 push.
**Proven by:** Granola iOS phone-call transcription, Otter/Fathom/Fireflies mobile apps.
**Effort:** L (iOS client). **Impact:** Med. **Depends on:** iCloudInboxWatcher (built); larger than the planned Shortcuts.

### C1-11 — Decision & commitment ledger (cross-meeting)
**What/why:** A dedicated extraction pass that pulls **decisions** and **commitments** (distinct from action items) into a vault-wide, searchable ledger with source citations. "Show me every decision about pricing this quarter."
**User value:** The institutional-memory layer; answers the exact query Otter advertises, but as a persistent structured artifact, not just a chat answer.
**Proven by:** Otter CMI ("consensus on Q3 budget"), Fathom "locate past decisions instantly."
**Effort:** M. **Impact:** Med-High. **Depends on:** C1-1 retrieval + a decisions extraction prompt.

---

## Top 3 picks

1. **C1-1 — "Ask your vault" cross-meeting RAG chat.** The defining table-stakes feature of 2026 (Otter CMI, Fathom library-wide Ask Fathom, Granola folder chat) and the one MeetingScribe most conspicuously lacks. It can be built on the already-planned `searchAll()` wiring + existing Ollama, and it's the rare feature MeetingScribe can offer *better* than the field — fully local, with citations, no cloud.
2. **C1-3 — Post-meeting agentic action fan-out (review-then-execute).** The whole market is converging on agentic actions (Zoom 3.0, Read.ai Search Copilot Actions, Fathom auto-CRM). MeetingScribe already has the write primitives (Linear/Notion, Mail, EventKit, write-MCP, People) — they just need to be orchestrated into one reviewable card. Consent-safe agency is a category MeetingScribe can own.
3. **C1-5 — Privacy posture as a provable, marketed feature.** The market has reorganized around bot-free/local-first privacy, and MeetingScribe is *more* private than Granola yet says so nowhere. Making the moat legible (and consent-helper tooling) is low effort and high positioning leverage — it's why a privacy-conscious buyer would pick this over the entire cloud field.

**Single highest-priority recommendation overall:** C1-1. Cross-meeting local Q&A is both the biggest parity gap and the clearest place to convert the local-first moat into a feature competitors structurally can't match.
