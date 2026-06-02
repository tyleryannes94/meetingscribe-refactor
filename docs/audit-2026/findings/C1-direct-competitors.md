# C1 — Direct Competitor Analysis: Relationship Apps vs. MeetingScribe People Module

**Lens:** Competitive Intelligence — direct relationship app competitors (Lasting, Paired, Relish,
Couply, Gottman Card Decks) mapped against MeetingScribe's People module.

**Date:** 2026-06-02  
**Prefix:** C1-

---

## 1. Lens Statement

MeetingScribe's People module is a CRM second-brain for *all* relationships (colleagues, friends,
family, partners) grounded in local transcripts and iMessage context. The five competitors below
all serve a narrower slice — romantic partners only — but have built deeper psychological
scaffolding, stronger habit loops, and more explicit content frameworks than MeetingScribe
currently offers. The gap is not in data richness (MeetingScribe wins there) but in *structured
emotional depth* and *type-aware UX flows*.

---

## 2. Competitor Profiles

### 2.1 Lasting — https://getlasting.com

**What it does well:**  
Lasting delivers therapist-authored "Series" of sessions covering Communication, Conflict,
Repair, Sexual Connection, Intimacy, Money, Family Culture, and Appreciation — drawn from
Gottman Method and Emotionally Focused Therapy (EFT). Each Series bundles reading material,
audio, and quizzes. Couples work through the same session independently, then compare answers.
Live therapist-led Zoom workshops are gated behind Premium. Sessions are organised by life stage
(Premarital, New Parents, Long-Term Marriage), not just topic. The app also offers free
"Conversation Starters" and "Relationship Reminders."

**Pricing:** $29.99/month · $89.99/6 months · promotional $59/year.  
([Lasting App Review — Choosing Therapy](https://www.choosingtherapy.com/lasting-app-review/))

**What MeetingScribe lacks that Lasting has:**
- Structured, therapist-authored content *series* tied to relationship life stages (premarital,
  new parents, long-term) — MeetingScribe has zero structured curriculum.
- Independent-then-compare question format (each partner answers, results revealed together).
- Audio-guided sessions — no audio content in MeetingScribe's People module today.
- Life-stage content paths (relationship type × stage = content variant).

---

### 2.2 Paired — https://www.paired.com

**What it does well:**  
Paired sends one daily prompt to both partners, each answers independently, then answers are
revealed side-by-side. Prompts are designed by relationship therapists and counselors and cover
emotional needs, conflict resolution styles, and future expectations. The app enforces a *daily
streak* mechanic — missing a day breaks the streak visually. Courses (love languages, conflict
resolution, intimacy) are added as structured deep-dives. There's a memory feature to capture
relationship highlights. 8 million downloads; independently shown to increase relationship
satisfaction.

**Pricing:** Free tier (limited questions); ~$9.99/month per couple.  
([Paired App Review — Panoramic Posts](https://panoramicposts.com/paired-app-review/),
[Paired App Store](https://apps.apple.com/us/app/paired-couples-relationship/id1469609343))

**What MeetingScribe lacks that Paired has:**
- Daily structured prompt — fired by push notification at a consistent time every day.
- Streak mechanics with loss-aversion hook — MeetingScribe's `ReconnectView` is passive
  (it surfaces only on Today, after the cadence threshold passes), not proactive.
- Both-partner-answer-then-compare pattern (requires shared accounts for a dyad).
- Therapist-curated courses on named topics surfaced in a browse UI.

---

### 2.3 Relish — https://hellorelish.com

**What it does well:**  
Relish applies 24 distinct relationship theories (including attachment theory and love languages)
to build a *personalised* micro-learning plan — short, frequent lessons rather than long sessions.
A live relationship coach (human, not AI) is available via in-app messaging at the premium tier
($156/couple above base). Lessons are generated from an initial assessment; topics include
Managing Emotions, Rebuilding Trust, Vulnerability, and Gratitude. The "partner joins free"
model lowers dual-subscription friction.

**Pricing:** $99.99/6 months for 2 users; coach access +$156/couple.  
([Relish App Review — Ryan and Alex](https://www.ryanandalex.com/relish-app-review/),
[Relish — hellorelish.com](https://hellorelish.com/faqs/))

**What MeetingScribe lacks that Relish has:**
- An onboarding *relationship assessment* that classifies the relationship and tailors content.
- Explicit attachment theory and love language profiling stored per person.
- Micro-learning format: very short exercises (2–5 min) completed daily — distinct from a
  long-form conversation analysis session.
- Human coach escalation path — MeetingScribe's AI is always Ollama/Claude, no human.

---

### 2.4 Couply — https://www.couply.io

**What it does well:**  
Couply combines personality profiling (Love Style, Attachment Style, Enneagram, 16-type MBTI
variant), daily conversation prompts, 110+ topic courses, date planning with calendar sync, a
shared private photo album, milestones tracker, long-distance mode, and an AI relationship coach
trained on the couple's personality results and interaction history. The AI coach can surface
*personalised* date ideas and advice based on stored personality data — the closest competitor
analog to MeetingScribe's Ollama-backed per-person chat.

**Pricing:** ~$15/month (freemium; free tier usable).  
([Couply review — OneDateIdea](https://www.onedateidea.com/reviews/couply/),
[Couply.io](https://www.couply.io/))

**What MeetingScribe lacks that Couply has:**
- Structured personality quizzes (Attachment Style, Love Style, Enneagram) stored *on the
  person record* and used to personalise AI responses and prompts.
- Shared photo album with milestones — MeetingScribe has `photoRelativePaths` but it is
  single-person and no milestones concept exists
  (`Sources/MeetingScribe/People/Person.swift:111`).
- Long-distance mode: content variant for relationships where regular in-person encounters are
  rare — directly maps to MeetingScribe's `lastInteractionAt` data but no UX path exists for it.
- Calendar-synced date planning — MeetingScribe reads calendar but does not *write* events
  triggered by relationship content.
- Partner account linking — MeetingScribe is single-user.

---

### 2.5 Gottman Card Decks — https://www.gottman.com/couples/apps/

**What it does well:**  
The app delivers 22 named decks (>1,000 flashcards) covering Love Maps (deep-knowing questions),
Open-Ended Questions, Expressing Needs ("I Feel…"), Give Appreciation, Salsa (intimacy), and
Bringing Baby Home (new-parent decks). The format is simple: one card at a time, tap to next,
star to favourite, shake to shuffle. The entire app is *free*. The content is backed by 40+
years of Gottman Institute research and maps directly to the "Sound Relationship House" model.
There is no check-in mechanic, no streak, no personalisation — it is pure content delivery.

**Pricing:** Free.  
([Gottman Card Decks — App Store](https://apps.apple.com/us/app/gottman-card-decks/id1292398843),
[Gottman Institute Apps](https://www.gottman.com/couples/apps/))

**What MeetingScribe lacks that Gottman Card Decks has:**
- Named exercise decks grounded in a named clinical framework (Sound Relationship House,
  Gottman Method).
- Love Maps cards — open-ended factual discovery questions ("What is your partner's greatest
  dream?") as a structured exercise, not just free-form notes.
- "Give Appreciation" and "I Feel…" card decks for practising NVC-adjacent communication.
- Framework *branding* — Gottman, Attachment, NVC, DBT are credibility anchors competitors
  cite explicitly. MeetingScribe's prompts in `PersonDetailView.swift:1764` (the deep-analysis
  prompt) do not name any framework.

---

## 3. What MeetingScribe Has That Competitors Don't

| Advantage | Detail |
|---|---|
| **Local-first, private** | All data stays on device (iCloud Drive vault); no competitor cloud, no profile mining. |
| **All relationship types** | Supports colleagues, family, close friends, and partners in one graph — none of the five cover non-romantic relationships. |
| **Meeting transcription context** | `meetingMentions` (`Person.swift:99`) links people to verbatim conversation context; competitors have no access to what was actually *said*. |
| **iMessage deep-analysis** | `MessagesAnalyzer` + `ConversationAnalysisPreset` run Ollama over real message history — Relish/Paired have no access to native message data. |
| **MCP / Claude integration** | 17-tool MCP server lets Claude read full person profiles, message stats, and meeting transcripts and write memories + people. Competitors have no LLM tool-calling layer. |
| **Graph view** | Node/edge relationship map across all contacts (`PeopleGraphViewModel`) — no competitor has a social graph surface. |
| **macOS native** | Full-window, keyboard-first, multi-window — all five competitors are mobile-only. |

---

## 4. Existing Plan Items — Top Endorsements (through C1 lens)

The existing plans already cover these items; ranked by competitive urgency:

1. **PPL-1 (inline identity editing)** — competitors surface personality data in the same
   screen as the check-in prompt. A modal round-trip to update a relationship label undermines
   the emotional immediacy these apps depend on.
2. **"Stay in touch" nudges** (partially built in `SuggestedPeopleView.swift:84-161`) —
   extend cadence inference to a *push notification* path so it fires outside the app, matching
   Paired's daily prompt mechanic.
3. **Relationship TYPE PATHS** (audit focus item #1) — endorsed strongly; Lasting, Relish, and
   Couply all bifurcate their content on relationship type; MeetingScribe treats a spouse and a
   work colleague identically in the data model and UI.

---

## 5. NET-NEW Recommendations

### C1-1 — Relationship Type Field + Type-Gated Content Paths (M)
**Gap:** `Person.swift` has `role` (a job title string) and `relationships` (freeform labels like
"spouse") but no first-class `relationshipType` enum. All five competitors gate their content on
relationship type (romantic partner, family, close friend, colleague).  
**Build:** Add `enum RelationshipType: String, Codable { case partner, family, closeFriend,
colleague, acquaintance }` to `Person`. Add a picker in `identityPanel` (one tap). Use the type
to: (a) show/hide sections in `PersonDetailView` (e.g. Encounters has different cadence defaults
for a partner vs. a colleague); (b) seed the per-type check-in templates (C1-3); (c) tint the
avatar ring.  
**Effort:** M. **Why now:** Every other recommendation in this file depends on this primitive.

### C1-2 — Love Language + Attachment Style Fields on Person Record (S)
**Gap:** `Person.swift` has `favorites` (freeform strings) but no structured psychological
profile fields. Relish and Couply both store attachment style and love language per person and
use them to personalise every subsequent prompt. MeetingScribe's Ollama deep-analysis
(`PersonDetailView.swift:1764`) could surface these automatically — but there's nowhere to store
the result except an `AttachedNote`.  
**Build:** Add optional typed fields to `Person`: `loveLanguage: LoveLanguage?` (words of
affirmation, acts of service, receiving gifts, quality time, physical touch) and
`attachmentStyle: AttachmentStyle?` (secure, anxious, avoidant, disorganised). Render as a
2-chip row in `identityPanel` below the role line. Wire to the deep-analysis prompt so Ollama
can populate them automatically when found in iMessage history.  
**Effort:** S. **Why now:** These two fields unlock personalised prompt injection in the chat
column at zero extra UX cost.

### C1-3 — Per-Person Structured Check-In Templates by Relationship Type (M)
**Gap:** `Encounter` (`Encounter.swift:1-46`) is a freeform "I met this person here" record.
None of the five competitors use freeform notes for check-ins — they use *structured prompts*
(Paired's daily question, Relish's micro-lesson, Lasting's session). MeetingScribe has no
templated check-in.  
**Build:** Add a `CheckInTemplate` struct with fields: `prompt: String`, `framework: String`
(e.g. "Gottman Love Maps", "NVC", "Attachment"), `type: RelationshipType`. Ship 3 templates per
type (9 total to start). Add a "Check in" button to the Encounters section header that opens a
half-sheet: show today's template prompt, let the user free-write a response, save as a
special-kind Encounter (`kind: "checkin"`). Separate from encounters tab in nav-rail.  
**Effort:** M.

### C1-4 — Gottman / NVC / Attachment Framework Cards as Named Decks (M)
**Gap:** Gottman Card Decks app delivers >1,000 exercise cards free, grounding them in named
clinical frameworks. MeetingScribe has no exercise content — users arrive to a blank profile.
The deep-analysis prompt (`PersonDetailView.swift:1764`) doesn't reference any named framework.  
**Build:** Add a "Reflection prompts" section to `PersonDetailView` (above Memories), populated
from a local JSON bundle of ~60 curated prompts organised into named decks: "Love Maps" (10),
"Expressing Needs / NVC" (10), "Appreciation" (10), "Conflict Repair" (10), "Intimacy" (10),
"Listening" (10). Filter shown deck by `relationshipType` (C1-1). Tap a card → it opens a note
entry field pre-populated with the prompt. Cards cycle daily (deterministic seed from date +
person ID). No server needed — static bundle.  
**Effort:** M.

### C1-5 — Daily Relationship Prompt via macOS Notification (S)
**Gap:** Paired's single biggest retention mechanic is a push notification delivered at the same
time every day that breaks the streak if ignored. MeetingScribe's `ReconnectView` only appears
when the app is open and the threshold has passed — passive, not proactive.  
**Build:** Add a `RelationshipPromptScheduler` that uses `UNUserNotificationCenter` to fire one
daily notification per "priority person" (marked as partner or close friend via C1-1). The
notification body is the day's check-in prompt (from C1-4's deck, seeded by date). Tapping the
notification deep-links to that person's detail and opens the Check-In half-sheet (C1-3).
Configurable per-person time in the identity panel.  
**Effort:** S.

### C1-6 — Relationship Health Score + Trend Sparkline (M)
**Gap:** Relish and Paired show implicit "relationship health" signals through streak length and
lesson completion. MeetingScribe has `relevanceScore(encounterCount:)` (`Person.swift:228`) but
it is never surfaced in the UI.  
**Build:** Compute a `RelationshipHealthScore` for each person from: encounter cadence vs.
inferred typical cadence, memory density (memories per 30 days), message sentiment trend (from
`ConversationAnalysisPreset.sentimentTrends`), and check-in streak (from C1-3). Display as a
3-dot or 5-bar icon in the People list row and as a small sparkline in `identityPanel` showing
the past 90 days. Feed into `ReconnectView` priority order. Expose via MCP as
`get_relationship_health`.  
**Effort:** M.

### C1-7 — Milestone Tracker (birthdays, anniversaries, relationship events) (S)
**Gap:** Couply tracks anniversaries, birthdays, and important milestones with calendar sync.
`Person.swift:103` already stores `birthday: Date?` but it is never used for proactive
surfacing. No anniversary or "relationship started" date field exists.  
**Build:** Add `milestones: [Milestone]` to `Person`, where `Milestone` has `label: String`,
`date: Date`, `isRecurring: Bool`. Pre-populate from `birthday`. Add "Add milestone" button in
identity panel. Surface upcoming milestones in Today view above the "stay in touch" block (within
14 days). Fire a notification 3 days before each recurring milestone. Use birthday for the
"hasn't been wished happy birthday" nudge pattern.  
**Effort:** S.

### C1-8 — Dyad Mode: Shared Encrypted Vault Folder for Partner Relationships (L)
**Gap:** All five competitors are inherently two-player apps (both partners have accounts). This
is MeetingScribe's hardest structural gap. A solo user journaling *about* their partner is
valuable, but Paired's "reveal answers together" mechanic requires a shared state layer.  
**Build:** For partner-type relationships (C1-1), add an opt-in "Dyad vault" that is a shared
iCloud Drive folder (`vault/dyads/<dyad-id>/`) readable by both partners' MeetingScribe
instances. Shared content: check-in responses (C1-3), milestones (C1-7), and a shared "Love
Maps" note. Each user's private memories remain private. No new server required — iCloud Drive
coordination. Wire `NSFileCoordinator` (already used in `MeetingStore` write methods).  
**Effort:** L. Note: this is a product-differentiating moat none of the five competitors match
(they all require their own cloud); flag for roadmap but do not block other C1 items.

### C1-9 — MCP Tools: add_encounter, add_check_in, get_relationship_health (S)
**Gap:** The MCP server has `add_memory` and `add_person` but no way to log an encounter or
check-in, and no relationship health signal. Claude cannot currently answer "when did I last
check in with my partner?" or "how is my relationship health trending?"  
**Build:** Add three MCP tools to `Sources/MeetingScribeMCP/main.swift`:  
- `add_encounter(personID, eventName, date, notes, location?)` — mirrors `Encounter.swift` struct.
- `add_check_in(personID, promptUsed, response, templateKind?)` — saves as Encounter with kind "checkin".
- `get_relationship_health(personID)` — returns cadence score, sentiment trend label, last check-in, streak.  
**Effort:** S.

### C1-10 — Onboarding Relationship Assessment (Attachment Style, Love Language) (M)
**Gap:** Relish and Couply both run a 5–10 question assessment at onboarding that gates all
subsequent content. MeetingScribe's onboarding (`OnboardingSheet`) focuses on vault location and
permissions — no relationship profiling.  
**Build:** Add an optional step 4 in `OnboardingSheet`: "Tell us about your most important
relationship" (optionally skippable). Two question blocks of 5 questions each: love language
(forced-choice scenarios) and attachment style (brief validated scale). Store results as
`loveLanguage` and `attachmentStyle` on the matched person record (C1-2). Use these values to
personalise the check-in template selection (C1-3) and the Ollama system prompt in the person
chat column (`personChatColumn` in `PersonDetailView.swift:268`).  
**Effort:** M.

### C1-11 — Conversation Debrief: Post-Meeting Relationship Reflection (S)
**Gap:** After a meeting with a person, Lasting would serve a reflection prompt ("How did that
conversation go for your relationship?"). MeetingScribe auto-generates a summary but surfaces no
relationship-focused debrief.  
**Build:** When a meeting is finalized and contains an attendee who is a People-module contact
with `relationshipType == .partner` or `.closeFriend`, add a "Relationship reflection" card to
the meeting detail (below the summary). The card shows 2–3 prompts drawn from the C1-4 deck
category "Conflict Repair" or "Listening" depending on the meeting's sentiment tag. One-tap
creates a Memory on that person, linked to the meeting ID. Takes 30 seconds of user time, no
new data model needed beyond the Memory struct.  
**Effort:** S.

### C1-12 — Framework-Branded Prompt Injection in Person Chat (S)
**Gap:** The Gottman Card Decks app is free and wins on framework credibility. MeetingScribe's
Ollama person-chat system prompt (`PersonDetailView.swift:1764`) currently names no framework.
Users of Lasting or Relish arrive pre-educated in Gottman / attachment / NVC language.  
**Build:** When `loveLanguage` or `attachmentStyle` is set on the person (C1-2), inject those
values into the person chat column's system prompt: "This person's attachment style is
[anxious]. Frame suggestions using Gottman Method Sound Relationship House principles and NVC
(Nonviolent Communication) language." No backend change — prompt string only. Surfaces immediately
in Claude's responses without any UI work.  
**Effort:** S.

---

## 6. Top 3 Picks

| # | ID | Recommendation | Rationale |
|---|---|---|---|
| 1 | **C1-1** | Relationship Type Field + Type-Gated Content Paths | Every other C1 recommendation depends on this primitive; without it, partner vs. colleague content cannot be differentiated. One afternoon of Swift work unlocks the entire content personalization stack. |
| 2 | **C1-3** | Per-Person Structured Check-In Templates | The single mechanic all five competitors share. Paired proved daily structured prompts are the core retention loop; MeetingScribe's existing Encounter model is 80% of the data model already (`Encounter.swift:1-46`) — this is mostly UI. |
| 3 | **C1-5** | Daily Relationship Prompt via macOS Notification | Converts MeetingScribe from a passive archive into an active relationship habit coach — the gap that most directly explains why users open Paired every day and open MeetingScribe only when they remember a meeting. |

---

## 7. Competitive Summary Table

| Feature | Lasting | Paired | Relish | Couply | Gottman | MeetingScribe (today) |
|---|---|---|---|---|---|---|
| Relationship type paths | Partner only | Partner only | Partner only | Partner only | Partner only | All types, no paths |
| Structured check-ins | Sessions | Daily question | Micro-lessons | Daily prompt | Card draw | Encounter (freeform) |
| Streak / cadence mechanic | No | Yes | Nudges | Yes | No | `ReconnectView` (passive) |
| Framework content (Gottman/NVC) | Yes | Partial | Yes | Partial | Yes | None |
| Personality profiling | No | No | Attachment + LL | Attach + LL + MBTI | No | None |
| AI coach | No | No | Human coach | AI (partner-aware) | No | Ollama + Claude (local) |
| iMessage context | No | No | No | No | No | Yes (MessagesAnalyzer) |
| Meeting transcript context | No | No | No | No | No | Yes (meetingMentions) |
| MCP / tool-calling | No | No | No | No | No | 17 tools (5 write) |
| Local-first / private | No | No | No | No | No | Yes |
| All relationship types | No | No | No | No | No | Yes |
| macOS native | No | No | No | No | No | Yes |
| Price | $90/6mo | $10/mo | $100/6mo | $15/mo | Free | (indie, TBD) |
