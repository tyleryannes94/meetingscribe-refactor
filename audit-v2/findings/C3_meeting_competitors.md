# AI Meeting Competitor Intelligence Findings — MeetingScribe v2 Audit

**Agent:** C3 — AI Meeting Assistant Tools Sub-Lens  
**Competitors analyzed:** Granola, Otter.ai, Fireflies.ai  
**Date:** 2026-06-16

---

## Top friction points / gaps (file:line citations)

### What competitors do that MeetingScribe lacks

**Granola's hybrid note canvas (biggest UX gap)**
- Granola's killer pattern: the user types sparse jottings during the meeting; Granola fuses those jottings with the full transcript post-meeting to produce a personalized, enhanced set of notes. The user's own words seed the structure, so the result feels personal, not boilerplate.
- MeetingScribe's `UnifiedMeetingDetail.swift` has separate `noteDraft` (My Notes tab) and `transcript` / `summary` (different tabs) — these are three siloed tabs, never fused. `UnifiedMeetingDetail.swift:27–30` shows `tab: DetailTab = .notes` driving a tab-switching paradigm rather than a unified canvas.
- The Granola model would be: a single canvas where user notes become H2-level anchors that the AI auto-expands with transcript context.

**Fireflies' Soundbites / shareable audio clips**
- Fireflies lets users create short, named audio clips from any moment in a recording and share them as standalone snippets.
- MeetingScribe has `audioController` (`UnifiedMeetingDetail.swift:55`) and timestamp-linked transcript (`UnifiedMeetingDetail.swift:54`), but no concept of a named clip, soundbite, or shareable highlight that a user can bookmark, label, and export.

**Fireflies' speaker analytics / talk-time metrics**
- Fireflies surfaces per-speaker talk time, sentiment trends, and team-level conversation metrics.
- MeetingScribe has speaker diarization (mentioned in briefing.md:89) but nothing in `UnifiedMeetingDetail.swift:1–100` or `OllamaService.swift:1–80` shows speaker-level analytics being computed or displayed. The meeting detail has no talk-ratio chart, no per-speaker sentiment, no "you talked 70% of this call" flag.

**Fireflies' personalized topic feed across all meetings**
- Fireflies builds a "Personalized Feed With Key Topics & Discussions" — a dynamic cross-meeting feed that highlights recent conversations and recurring topics, so users see what themes are trending across their week.
- MeetingScribe has `WeeklyRecap` and `StandupDigest`, but these are narrative outputs, not an interactive cross-meeting topic feed with drill-down. The embeddings and FTS5 backend exist (`briefing.md:29–31`) but are not exposed as a live topic-trend surface.

**Otter.ai's live captions + real-time transcript visible during meeting**
- Otter surfaces a live caption rail visible during the call itself — you can glance at what was just said.
- MeetingScribe's `UnifiedMeetingDetail.swift:12–14` differentiates `.live` vs `.past` modes, and transcript state is loaded (`transcript: String` at line 43), but no evidence of a live, scrolling caption panel visible to the user while the meeting is in progress.

**Granola's pre-meeting Brief with email-context awareness**
- Granola's Brief surface pulls in email context ("Alex emailed this morning noting push-back is team-driven") alongside prior meeting history.
- MeetingScribe's `PreMeetingBriefView.swift:1–80` already does prior meetings, open tasks, and talking points — but email/iMessage context from `MessagesAnalyzer` is not plumbed into the Pre-Meeting Brief despite being available in the codebase.

**Otter's inline highlight + bookmark system**
- Otter lets users highlight any transcript segment, add a comment, and bookmark it for later retrieval.
- MeetingScribe's transcript is displayed but has no highlight/bookmark affordance in the detail view. `transcriptSearchSeed` (`UnifiedMeetingDetail.swift:76`) is the closest mechanism but is for search seeding, not annotation.

**Fireflies' cross-meeting semantic search ("Meeting Search" / "AskFred")**
- Fireflies' AskFred lets you query across ALL your meetings in natural language from within the call or library.
- MeetingScribe has AI chat with tool-use over meetings (`ChatTools.swift`, `MeetingChatTools.swift`) and FTS + embeddings, but this is not surfaced as an always-visible, instant-answer search bar in the Meetings tab — you have to open a chat rail.

---

## Existing items to endorse (from prior plan or codebase)

- **Timestamp-synced transcript + audio player** (`UnifiedMeetingDetail.swift:54–55`, comment "C1-3"): already built, should be surfaced prominently. This is a core differentiator that Granola (notes-focused) lacks.
- **Type-aware summary prompts** (`OllamaService.swift:26–80`, comment "C1-8"): inferring meeting type (1:1, standup, sales, interview) and adjusting the summary is exactly right and better than all three competitors' generic templates.
- **Pre-meeting talking points from People records** (`PreMeetingBriefView.swift:52–79`, comment "U1-5"): already implemented and highly differentiated — no competitor does this with a local People CRM.
- **Series spine / recurring meeting history** (`UnifiedMeetingDetail.swift:95–100`, comment "D1-6"): threading recurring occurrences is a strong second-brain pattern competitors ignore.

---

## NET-NEW recommendations

### C3-1: Hybrid Fusion Notes Canvas
- **What:** Replace the three-tab (Transcript / My Notes / Summary) paradigm in `UnifiedMeetingDetail` with a single post-meeting canvas. The user's jottings during the meeting become H2 section headers; Ollama expands each with relevant transcript context. Final output is one coherent, personal document — not a generic AI summary alongside unrelated user notes.
- **Why (second-brain angle):** The user's own words carry intent signals the AI can't infer. Fusing them produces notes that feel owned, not generated. This is Granola's #1 differentiator; MeetingScribe can do it 100% locally with zero privacy cost.
- **Cross-feature connections:** Feeds richer content into People memories (auto-suggested from the fused canvas); action items extracted from the unified canvas are more accurate because they include user-flagged items; Notion/Obsidian export quality improves dramatically.
- **Effort:** L | **Impact:** High
- **Deps:** None — builds on existing `noteDraft`, `transcript`, `summary` state and `OllamaService`

### C3-2: Live Caption Rail During Recording
- **What:** In `.live` mode, show a floating, auto-scrolling caption strip at the bottom of `UnifiedMeetingDetail` (or as a menu bar popover) that displays the last 3–5 transcript lines as they arrive from Whisper. User can glance without leaving the meeting app window.
- **Why (second-brain angle):** Lets the user catch a name or number they missed without rewinding audio. Otter's biggest "wow" moment for first-time users.
- **Cross-feature connections:** Live captions can trigger real-time action-item detection (flash a "capture this?" prompt when Whisper detects "I'll… / you should… / by Friday").
- **Effort:** M | **Impact:** High
- **Deps:** Whisper streaming pipeline — verify real-time output cadence from `RecordingMonitor`

### C3-3: Speaker Talk-Time + Sentiment Panel
- **What:** On any past meeting with diarized transcript, show a collapsible analytics panel: per-speaker talk-time bars, rough sentiment trajectory (positive/neutral/negative segments via Ollama), and a flag if the user talked >65% of the call. Store these as meeting metadata.
- **Why (second-brain angle):** Fireflies' #1 enterprise upsell. For a single-user "second brain," the self-coaching angle is powerful: "You dominated 3 of your last 5 1:1s — consider asking more questions." Ollama makes this free to run.
- **Cross-feature connections:** Speaker stats feed People records (Person's typical communication style); Weekly Recap can include "your most balanced conversation this week was…"; Today view can surface a coaching nudge.
- **Effort:** M | **Impact:** Med
- **Deps:** Speaker diarization metadata must be persisted per-segment (verify current diarization storage schema)

### C3-4: Transcript Highlights + Bookmarks
- **What:** Let users select any transcript segment, press ⌘B to bookmark it with an optional label, and optionally create a named audio clip (like Fireflies Soundbites) that exports as a shareable `.m4a` + transcript snippet. Bookmarks appear in a sidebar within the meeting and are searchable via FTS.
- **Why (second-brain angle):** Converts transcript from read-only artifact into an annotated knowledge store. Bookmarks become retrievable facts tied to People and Projects — "find every time Alex mentioned the Q3 deadline."
- **Cross-feature connections:** Bookmarks link to People (tag a person when bookmarking); link to Projects/Tasks (bookmark → create task); searchable via `GlobalSearchView`; exportable to Notion/Obsidian as annotated callouts.
- **Effort:** M | **Impact:** High
- **Deps:** `audioController` (C1-3 already built); FTS5 schema extension for bookmark entity type

### C3-5: Cross-Meeting Topic Feed
- **What:** A "Topics" section on the Meetings tab (or Today view) that uses existing embeddings + FTS5 to surface the top 5 recurring themes across the last 30 days of meetings, each linking to the specific meetings where they appeared. Updated nightly by a background Ollama pass.
- **Why (second-brain angle):** Fireflies' personalized feed in a fully private, local form. Surfaces what's consuming the user's meeting time that they may not consciously track. "You've discussed 'API pricing' in 7 meetings this month."
- **Cross-feature connections:** Topics link to Projects (if a topic matches a project name, auto-surface it); feed into Weekly Recap as a "themes this week" section; topics can be pinned to People (this person keeps raising X).
- **Effort:** M | **Impact:** Med
- **Deps:** `EmbeddingService`, `SecondBrainDB` FTS5 — both exist; needs a background job scheduler

### C3-6: iMessage/Email Context in Pre-Meeting Brief
- **What:** Extend `PreMeetingBriefView` to pull the last 3 iMessage/email threads with each attendee (via existing `MessagesAnalyzer`) and display a 1-line AI-synthesized summary of each ("Alex's last message: pushing back on pricing, sent 8 hours ago").
- **Why (second-brain angle):** Granola's Brief does this with email; MeetingScribe has iMessage already analyzed but it's siloed in the People tab. Bringing it to the pre-meeting surface is a major differentiator — no competitor does this with local iMessage.
- **Cross-feature connections:** `PeopleStore` → `MessagesAnalyzer` → `PreMeetingBriefView`. Also surfaces talking points from People records (already done in U1-5).
- **Effort:** S | **Impact:** High
- **Deps:** `MessagesAnalyzer` must expose per-person recent thread summary; `PersonResolver` already resolves attendees to People records

---

## Top 3 picks

1. **C3-1 (Hybrid Fusion Notes Canvas)** — Granola's most-praised feature, achievable locally, transforms the meeting artifact from "AI output beside user jottings" into one coherent owned document. Highest UX leap for lowest risk.
2. **C3-6 (iMessage/Email Context in Pre-Meeting Brief)** — Small effort (S), very high impact. MeetingScribe already has `MessagesAnalyzer` and `PersonResolver`; wiring them into `PreMeetingBriefView` creates a genuinely unique "brief" no cloud competitor can replicate without local device access.
3. **C3-4 (Transcript Highlights + Bookmarks)** — Turns the transcript from a read-only artifact into an annotated knowledge store. Cross-links to People, Projects, and global search. Foundation for future "meeting memory" features.
