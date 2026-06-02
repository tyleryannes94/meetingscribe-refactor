# C2 — Mental Health & Therapy App Competitive Intelligence
**Lens:** Adjacent mental health and therapeutic journaling apps (Woebot, Wysa, Reflectly,
Daylio, BetterHelp, Connected/Gottman) — how they deliver content, run emotional check-ins,
handle sensitive topics safely, and distinguish warm from clinical. Lessons for MeetingScribe's
relationship coach layer.

**Auditor role:** Competitive intelligence specialist, mental health/therapy app sub-lens.
**Audit date:** 2026-06-02

---

## 1. Lens Statement

MeetingScribe is building a relationship coach layer on top of a meeting-capture app. The
parallel industry that has solved every core UX problem it faces — low-friction emotional
logging, habit-forming check-in loops, safe AI content delivery, warm-not-clinical tone,
framework-backed prompts — is mental health and journaling apps. This audit reads those apps'
design choices as a direct pattern library for MeetingScribe, then maps each pattern to
specific source code gaps.

The prior audits (P1, P3, D4, P2) have correctly identified *what* is missing: no
`RelationshipType` field, no encounter quality fields, no framework-aware AI prompts, no
check-in notifications. This audit answers a different question: **exactly how should that
content be delivered, timed, worded, and guarded** — the craft details that separate a
relationship coach users return to daily from one they abandon after three sessions.

---

## 2. What the Mental Health App World Has Solved

### 2.1 Woebot — CBT in two-line turns, not paragraphs

Woebot (now B2B only after June 2025 DTC shutdown) pioneered the pattern that defines the
space: deliver evidence-based therapeutic content in short, conversational micro-turns with
pre-scripted button responses, never demanding open-ended writing.

Key lessons:
- **Turn length discipline.** Every AI response was ≤ 3 sentences. The bot never "lectured."
  A Gottman check-in in MeetingScribe should ask one question per message — not present a
  five-field form.
- **Button-scaffolded responses.** Woebot offered 3–4 tap-to-reply options alongside a free-
  text field. This lowers anxiety about "saying the right thing" and gets 10× more responses
  than blank open fields. MeetingScribe's encounter logging (currently one freeform text
  field) should offer 3–5 tappable emotion chips ("felt warm / draining / unresolved /
  grateful / complicated") before the free-text box.
- **Daily check-in, single question.** Push notification → open app → one question ("How's
  your energy today?") → logged in 15 seconds. This is the habit loop. MeetingScribe's
  daily brief notification (8am, currently off by default) should offer a parallel
  relationship check-in question per close contact — one per day, not a batch prompt.
- **Why Woebot died:** pre-scripted chatbots became obsolete when LLMs arrived. MeetingScribe
  runs a local LLM (Ollama, `OllamaService.swift:7`) — it can deliver Woebot's warm delivery
  pattern with genuine generativity. This is a structural advantage over Woebot's legacy
  approach.

Sources: [AI Mental Health Apps 2026: Woebot, Wysa, Earkick Reviewed](https://sunlithapiness.com/blog/ai-mental-health-apps-2026/);
[Woebot CBT Features & Facts](https://aicw.io/ai-chat-bot/woebot/);
[Anatomy of Woebot — Postpartum Depression CBT Study](https://www.tandfonline.com/doi/full/10.1080/17434440.2023.2280686)

---

### 2.2 Wysa — Safety Guardrails as Architecture, Not Afterthought

Wysa (still active, B2B-focused) is the gold standard for emotional safety in AI systems:
every LLM-generated response is screened by a proprietary safety layer before delivery.
This is structural, not prompt-engineered.

Key lessons:
- **Pre-flight content review.** Wysa's "clinician-approved rule engine" checks every response
  for distress signals before it reaches the user. MeetingScribe's `PersonSuggestionEngine`
  (`PersonAISuggestions.swift:26–72`) and the `buildPrompt` method in `OllamaService.swift:264`
  have no such gate. For a relationship coach handling content about romantic partners, family
  conflict, and attachment anxiety, a lightweight content screen is required.
- **Escalation as a first-class flow.** Wysa maintains a persistent crisis button accessible
  from any screen. MeetingScribe doesn't need crisis escalation at full clinical scale, but
  it needs a "this feels heavy — want to talk to someone?" detection: if a user's free-text
  encounter note contains distress signals (self-harm adjacent language, extreme hopelessness),
  Ollama's response should acknowledge the weight and offer a resource link, not a journaling
  prompt. This is one additional prompt filter.
- **Scope discipline.** Wysa documents clearly what it is NOT for (crisis, trauma, severe
  depression). MeetingScribe needs the same in its AI-generated coach content: "I'm a
  reflection tool, not a therapist" framing in the first check-in a new user receives. This
  prevents scope creep expectations.

Sources: [Wysa Transforming Mental Health — EMHIC](https://emhicglobal.com/artificial-intelligence-2/wysa-transforming-mental-health-through-ai-driven-support/);
[Evaluating Therapeutic Alliance with Wysa — PMC](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9035685/);
[Is Wysa Worth It? 2026 Review](https://aigearbase.com/tool/wysa)

---

### 2.3 Reflectly — Guided Structure, Not Blank Page

Reflectly is the closest template for MeetingScribe's encounter logging UX. Its core
insight: structured prompts with a visible completion path dramatically increase journaling
follow-through vs. a blank text field.

Key lessons:
- **Mood slider as entry, not form field.** Reflectly's first screen is a large emoji-backed
  mood slider. The interaction takes 2 seconds and immediately provides data. MeetingScribe's
  encounter quick-log (currently a freeform `eventName` field in `AddEncounterSheet`) should
  lead with a tap-to-select emotional quality row — 5 states, icon-driven, no typing required.
- **Three-question daily prompt structure.** Reflectly asks: what happened / how did you feel
  / what do you want to do differently. This maps directly onto MeetingScribe's encounter
  reflection: "What happened with [Name] / How did it feel / What do I want to do differently
  next time." The three-question format has the psychological property of feeling complete
  rather than arbitrary.
- **AI follow-up question (not AI answer).** After a user entry, Reflectly's AI asks one
  follow-up question ("You mentioned feeling drained — was that about the topic or the
  dynamic?"). This is more powerful than AI-generated summaries because it externalizes
  the user's own thinking rather than replacing it. MeetingScribe's Ollama pipeline should
  offer this after an encounter is saved: one AI-generated follow-up question, dismissable,
  that surfaces something worth noticing.
- **Voice note → transcription → reflection prompt.** Reflectly 2025 added voice journaling
  with auto-transcription. MeetingScribe already has voice notes for people
  (`mcp__meetingscribe__get_voice_note` in the MCP surface) but doesn't route voice note
  content through the relationship coach layer. A voice note about a conversation with a
  partner should auto-trigger a reflection prompt.

Sources: [Reflectly App Review 2025](https://ikanabusinessreview.com/2025/10/reflectly-app-review-2025-guided-journaling-for-wellbeing/);
[Reflectly AI Journal — Trending AI Tools](https://www.trendingaitools.com/ai-tools/reflectly/);
[Reflectly App Store](https://apps.apple.com/us/app/reflectly-journal-ai-diary/id1241229134)

---

### 2.4 Daylio — Tap-First Logging, Writing Optional

Daylio is the definitive case study in micro-journaling friction reduction. Its design
principle: **a logged entry with minimal data is infinitely more valuable than a perfect
entry that never happens.**

Key lessons:
- **Emoji-first, text-optional.** Daylio logs a complete entry with 2 taps (mood +
  activity icon). Text is offered but never required. MeetingScribe's encounter logging
  requires a typed `eventName` before Save is enabled. This is a friction wall. The minimum
  viable encounter log should be: person (pre-selected) + date (today, pre-filled) + one
  tap on an emotional quality icon. That's it. Notes are optional.
- **Retroactive logging without guilt.** Daylio allows past-day entries and explicitly does
  not break "streaks" for missed days. MeetingScribe's `ReconnectView`
  (`SuggestedPeopleView.swift:84–161`) currently flags drift after 1.5× inferred cadence —
  this can feel punishing. Allow logging past encounters (the `Encounter.date` field already
  supports this) and show a neutral historical view, not just an overdue alert.
- **Activity tags as emotional vocabulary.** Daylio uses tappable activity icons ("family,"
  "work," "good sleep," "exercise") as structured context on top of the mood score. For
  MeetingScribe: tappable interaction-type chips per encounter ("quality time," "conflict,"
  "repair," "deep talk," "logistics only," "fun"). These map directly to Gottman framework
  tags and require zero typing. The `Encounter.frameworkTag` field proposed in P3 is the
  right data slot; the delivery should be icon chips, not a text field.
- **Insights that require no manual work.** Daylio's statistics section surfaces correlations
  ("walking correlates with 'good' mood") from structured logs automatically. MeetingScribe's
  `PeopleInsightsView` (`PeopleInsightsView.swift:7–155`) currently has only three cards
  driven by raw date math. Structured encounter quality tags (even just the icon chips) unlock
  pattern detection: "Your highest-rated encounters with [partner] were 'deep talk' type —
  you've had none in 3 weeks."

Sources: [Daylio Review 2026 — Calmevo](https://calmevo.com/daylio-review/);
[Daylio Journal — Mood Tr... 2026 Intel](https://marlvel.ai/intel-report/lifestyle/daylio-journal-mood-tracker-1);
[Daylio App Showcase — ScreensDesign](https://screensdesign.com/showcase/daylio-journal-daily-diary)

---

### 2.5 Connected (Gottman Method App) — Weekly Structured Reflection as Product Core

Connected is the closest direct competitor to MeetingScribe's relationship coach ambition.
It wraps Gottman Method, attachment theory, and EFT into a weekly check-in habit with
assessments, AI coaching, and conflict tools.

Key lessons:
- **5-part weekly reflection as anchor habit.** Connected's weekly check-in format: highlights
  / what felt off / gratitude / intention / repair. "Fifteen minutes that does more than an
  hour-long talk." MeetingScribe's per-person check-in templates (P3-3 in the prior audit)
  should adopt this exact five-part structure as the default for romantic partner type, not
  a custom format. It is research-validated and user-tested.
- **Assessment + AI coaching, not just logging.** Connected measures attachment style,
  communication pattern, conflict style, and satisfaction score. MeetingScribe's `Person`
  model has none of these structured fields (confirmed at `Person.swift:77–185`). The
  assessment data is what unlocks meaningful AI coaching vs. generic prompts.
- **Daily question cadence.** One research-backed question per day, not a weekly dump.
  MeetingScribe's daily brief (8am push, `NotificationManager.swift:159–171`) should carry
  one daily relationship question per primary-type person. The Gottman Card Decks app
  (1,000+ flashcards across 22 decks on Love Maps, intimacy, and date ideas) is the content
  library MeetingScribe should draw from for free-tier prompts.

Sources: [Connected Relationship App 2026](https://www.connectedcouples.app/relationship-app);
[Best AI Relationship Apps 2026 — Couplework](https://couplework.ai/ai-relationship-apps-in-2026-how-couplework-compares-to-the-rest/);
[Gottman Card Decks App Store](https://apps.apple.com/us/app/gottman-card-decks/id1292398843)

---

### 2.6 Tone and Safety Design — Clinical vs. Warm

Research and UX literature on mental health app design converge on a clear split:

**Clinical signals (avoid):**
- Numbered lists of symptoms or techniques
- Medical / DSM terminology surfaced without explanation
- "Your relationship shows signs of…" framing (diagnostic voice)
- Long AI responses that read like a report
- Progress metrics framed as scores to optimize

**Warm signals (use):**
- First-person invitation language: "Want to take a moment to notice what's working?"
- Curiosity over evaluation: "What do you think is underneath that for you?"
- Normalizing language: "It's common for partners to have different needs here…"
- Short turns — never more than 3 sentences in a single AI message
- Specific, non-generic affirmation: "That's a meaningful thing to notice" (not "Great job!")
- Soft tone on hard data: when surfacing "you haven't logged quality time in 18 days," the
  framing should be an invitation, not an alert ("It's been a while since you logged a deep
  conversation with [Name] — want to add one?")

Color and visual design: de-saturated teals, sage greens, and warm earth tones reduce cortisol
associations. MeetingScribe's current `NotionDesign.swift` color tokens should be audited for
any relationship coach views — avoid high-contrast alert red for relationship health signals.

Sources: [Mental Health UX — NumberAnalytics](https://www.numberanalytics.com/blog/mental-health-ux-in-healthcare);
[Mental Health App Design Guide — Gapsy Studio](https://gapsystudio.com/blog/mental-health-app-design/);
[Designing for Emotional Resilience — Medium/Bootcamp](https://medium.com/design-bootcamp/designing-for-emotional-resilience-ux-ui-strategies-for-mental-health-apps-9dba4cb5e533)

---

## 3. Existing Plan Items I Rank Highest (from This Lens)

| ID | Item | Ranking | Mental-health-app rationale |
|---|---|---|---|
| P3-10 | Encounter Quick-Log from Today View | **Highest** | Daylio proves: if the entry point isn't on the home screen with ≤2 taps, logging frequency collapses. Without this, every other framework addition is dead on arrival. |
| P3-2 | Relationship-type-specific AI analysis presets | **High** | Woebot and Wysa: framework-grounded content is what separates a therapeutic tool from a generic note-taker. This is already half-built (prompts exist in `PersonAISuggestions.swift` and `OllamaService.swift:264`). |
| P3-3 | Relationship check-in templates | **High** | Connected's 5-part weekly reflection is the model. The template slot exists in `NoteTemplate`; the content is missing. |
| P3-5 | Per-person check-in cadence + notifications | **Medium** | Woebot's retention data showed daily push → app open → 15-second log drives 3× more entries than in-app-only prompts. MeetingScribe's notification surface (`NotificationManager.swift:159`) is 100% productivity-focused; zero relationship nudges. |

---

## 4. NET-NEW Recommendations

### C2-1: Adopt Daylio-Style Icon-First Encounter Entry
**Effort: S**

The single highest-ROI UI change for relationship logging adoption. Replace the current
`AddEncounterSheet` required-text-first pattern with an icon-chip-first pattern:

1. Row of 5–6 tappable emotional quality chips with icons: "Warm," "Deep," "Tense,"
   "Draining," "Repair," "Fun/Playful" — no typing required.
2. Pre-selected date (today) and pre-selected person (whoever's detail view you're on).
3. Optional notes field below. Optional framework tag (Quality Time / Acts of Service / etc.)
4. Minimum complete entry: tap one chip → Save. 8 seconds total.

The chip selections write to the `qualityRating` and `frameworkTag` fields (already proposed
in P3-4). This is purely a UI change to the existing `AddEncounterSheet` — no model changes.
The current forced `eventName` field becomes optional placeholder "What happened?" rather than
a required string.

File targets: `Sources/MeetingScribe/People/PersonDetailView.swift` (AddEncounterSheet at
line ~1918) and `Sources/VaultKit/Encounter.swift` (add quality/tag fields if P3-4 lands
first, or land them here together).

---

### C2-2: Ollama Follow-Up Question After Encounter Save
**Effort: S**

After any encounter is saved for a person with `primaryRelationshipType` set to partner,
close friend, or family type, trigger a single Ollama-generated follow-up question in a
dismissable inline card (not a sheet, not a notification — stays in context). Format:

```
[Name card]  "Want to go a little deeper?"
             "You mentioned this felt tense — was that about what was said, or how?"
             [Expand] [Not now]
```

The Ollama prompt: `"The user just logged an encounter with [Name] ([relationship type]) 
rated as [quality chip]. Based on this note: '[user text]', ask one short, genuinely curious 
follow-up question (≤ 15 words) that helps them understand themselves better in this 
relationship. Never make it feel like therapy homework. Never diagnose."` Temperature 0.5
for warmth/variety (not 0.2 like the existing CRM prompts in `PersonSuggestionEngine`).

This is Reflectly's highest-retention feature ported to the relationship context. The user
wrote two sentences; the AI asks one question; the user either ignores it (no friction) or
writes more (high value). The question should feel like a curious friend, not a therapist.

File target: new method in `OllamaService.swift` alongside `generate()` / `summarize()`.
Triggered from the save handler in `PersonDetailView.swift`.

---

### C2-3: Relationship Coach Tone Guide Injected into Every AI Prompt
**Effort: S**

The existing `PersonSuggestionEngine.generate()` prompt (`PersonAISuggestions.swift:31`) and
`OllamaService.buildPrompt()` (`OllamaService.swift:264`) both use the same clinical framing:
"You are organizing a personal CRM" and "You are an assistant that writes concise,
action-oriented meeting summaries." For relationship coach content, this framing produces
clinical output.

Add a shared `RelationshipCoachPersona` string constant injected when the person has a
close relationship type:

```swift
static let coachPersona = """
You are a warm, curious relationship companion — not a therapist, not a life coach, \
not a CRM assistant. You notice patterns without labeling people. You ask questions \
rather than give advice. You never diagnose, score, or evaluate the relationship. \
Your tone is like a thoughtful friend who also happens to know a lot about \
attachment theory and Gottman research — but you never use jargon unless the user \
introduces it. Keep all responses under 3 sentences.
"""
```

This is a one-file change that immediately changes the tone of every AI-generated output in
the People module for close relationships. The clinical "organize a personal CRM" persona
is retained for colleague/acquaintance types where professional framing is correct.

File target: new constant in `PersonAISuggestions.swift` or a shared `AIPersonas.swift`;
injected into `PersonSuggestionEngine.generate()` and any new coach prompts.

---

### C2-4: Distress Signal Filter on Encounter Notes
**Effort: S**

MeetingScribe handles real emotional content — users will write about conflict with a partner,
estrangement from a parent, grief about a friendship fading. The existing Ollama pipeline has
no guardrail for distress signals in this content (unlike Wysa's proprietary pre-flight
checker).

Add a lightweight client-side check before passing encounter notes to Ollama:

```swift
static let distressTerms = ["hopeless", "can't go on", "don't want to be here",
                             "hurting myself", "self-harm", "ending it", "no point"]

func containsDistressSignal(_ text: String) -> Bool {
    let lower = text.lowercased()
    return distressTerms.contains { lower.contains($0) }
}
```

When triggered: (1) do NOT pass the note text to Ollama; (2) show an inline card: "It sounds
like things are really hard right now. If you're going through something serious, the Crisis
Text Line (text HOME to 741741) is always available." (3) Offer "Continue journaling" to
proceed without AI processing. This is not clinical crisis intervention — it is responsible
scope management, the same pattern Wysa uses to flag its non-crisis scope. Effort is S; legal
and moral risk of omitting it is significantly higher than the effort to add it.

File target: new utility function in a new `Sources/MeetingScribe/People/SafetyFilter.swift`.
Called from `PersonDetailView.swift` save handler before any Ollama call on encounter notes.

---

### C2-5: "Not Now" / "Coming Back To This" Defer Mechanism on All Prompts
**Effort: S**

Every mental health app that achieves sustained engagement (Reflectly, Headspace, Wysa) has
a core UX principle: **no prompt should feel mandatory.** The user must be able to defer
without friction and return without shame. MeetingScribe's current encounter and AI
suggestion surfaces have dismiss/cancel but no defer.

Add a "Remind me later today" or "Save this for my next check-in" option to:
1. The post-encounter Ollama follow-up question (C2-2)
2. The AI suggestions card in `PersonDetailView` (aiSuggestionsSection)
3. The relationship health card (if P3-7 lands)

Mechanically: a deferred item stores as a `PendingReflection` in UserDefaults (not a meeting
or encounter — it never should show up in a CRM list). The daily brief notification (8am)
includes deferred items in its payload ("You set aside a question about your conversation with
[Name] yesterday — want to come back to it?"). Max 3 deferred items before new deferral is
blocked ("Let's clear one first").

File target: new `PendingReflection` model + `PendingReflectionStore` in the People module.
Connected to `NotificationManager.swift` for the daily brief injection.

---

### C2-6: Warm Framing for "Gone Cold" / Overdue Nudges
**Effort: S**

The existing `ReconnectView` (`SuggestedPeopleView.swift:81–161`) and whatever notification
is added for check-in cadence (P3-5) will be the first relationship nudge most users see.
The wording of these nudges determines whether users experience MeetingScribe as a caring
companion or a manager.

Current implied wording pattern (inferred from code): "[Name] — overdue" / "Haven't logged
in N days." This is a report, not an invitation.

Define a set of warm nudge templates by relationship type:
- **Partner**: "You haven't logged time with [Name] in [N] days. How have things been
  between you?" (never "overdue," never a count ≥ 30 for partners — use "a few weeks")
- **Close friend**: "It's been a while since [Name] showed up in your notes. How are they
  doing?" (not "you haven't logged" — shift to curiosity about them, not a logging task)
- **Family**: "Your last note about [Name] was [N] days ago — anything from that visit still
  on your mind?" (retrospective, not a reminder to log)
- **Colleague**: Keep neutral/functional: "Haven't connected with [Name] recently."

These string templates should live in a `NudgeTemplates.swift` file, selectable by
`RelationshipType`. The `PeopleInsightsView` (currently `goneColdDays: 45` hardcoded at
`PeopleInsightsView.swift:76–83`) should pull from these templates. Zero new infrastructure;
this is copy + relationship-type branching on existing nudge cards.

---

### C2-7: Relationship Coach Scope Disclosure (First-Use Card)
**Effort: S**

Woebot's DTC shutdown was partly driven by user expectation mismatch — people brought
clinical-level needs to a wellness chatbot. MeetingScribe faces the same risk at smaller
scale: a user in genuine relationship crisis receiving a Gottman check-in prompt is a
product failure.

Add a one-time dismissable card shown the first time a user sets up a close relationship
type OR the first time the AI coach surface is used:

> "MeetingScribe's relationship reflection tools are for self-insight, not therapy. They're
> here to help you notice patterns and appreciate what matters. For serious relationship
> challenges, a licensed therapist or couples counselor is the right resource."

This card (1) sets correct scope; (2) reduces user frustration when the AI gives curious
questions rather than advice; (3) is the responsible product posture. Store show-state in
`UserDefaults` with key `hasSeenCoachScopeDisclosure`. One view, one UserDefaults bool.

---

### C2-8: Framework Content Sourcing — Curated Prompt Library, Not Ad-Hoc Generation
**Effort: M**

Woebot, Wysa, and Connected share one practice: their therapeutic content is **authored by
clinicians**, not generated ad-hoc by LLMs. The LLM delivers the content; it doesn't author
the framework content. MeetingScribe currently has the AI generating open-ended prompts
(`PersonSuggestionEngine.generate()`), which produces variable quality and no consistency.

Build a local `RelationshipPromptLibrary` — a JSON or Swift constant file containing:
- 20 Gottman-grounded daily questions (Love Maps: "What's something [Name] is looking
  forward to that I may not know about?")
- 10 attachment-theory reflection prompts (per attachment style: secure / anxious / avoidant)
- 10 love-language activation prompts (per language: quality time / words / acts / gifts /
  touch)
- 8 NVC check-in prompts ("What need of mine was showing up in that interaction?")
- 5 repair-conversation starters ("What do I wish I had said differently?")

The LLM is then used to *personalize* a selected prompt ("insert [Name] and the relevant
context from their recent messages") rather than to generate the framework content from
scratch. This guarantees content quality, allows vetting by a therapist consultant if
desired, and makes the content auditable and tweakable without model changes.

File target: `Sources/MeetingScribe/People/RelationshipPromptLibrary.swift` — a static
struct of categorized string arrays with metadata (framework type, relationship type scope,
last-shown tracking). Selection logic: pick a prompt the user hasn't seen in ≥ 7 days,
matching the person's `primaryRelationshipType` and any set love language / attachment style.

---

## 5. Top 3 Picks

### Pick 1 (Highest Priority): C2-1 — Daylio-Style Icon-First Encounter Entry

This is the single change most likely to determine whether the relationship coach layer
ever gets used. Daylio's entire market position is built on one insight: **the fastest
log wins**. The current `AddEncounterSheet` (text field required, sheet modal, 5 taps to
reach) guarantees users will not develop a daily logging habit. Every other investment —
frameworks, prompts, AI analysis, health dashboard — depends on encounter data that simply
won't exist if logging is friction-heavy. Effort: S. Unblocked now. Immediate impact on
every single user who encounters the People module.

### Pick 2: C2-3 — Relationship Coach Tone Guide (Persona Injection)

The existing Ollama prompts produce clinical, CRM-register output ("organizing a personal
CRM," "adult professionals"). This is a one-file constant addition that rewires every AI
output in the People module for close relationships from report-register to curious-companion
register. It's the difference between a user feeling they're filling out a database and
feeling they're working through something real. Effort: S. No infrastructure, no schema
changes. Can ship in hours. The warm/clinical distinction is what makes users share the
product with friends ("this actually helped me think") vs. quietly uninstall it.

### Pick 3: C2-4 — Distress Signal Filter

This is the responsible floor. MeetingScribe is moving into emotional territory that will
attract users in genuine distress. A simple keyword pre-flight check before Ollama is called
on personal notes is the minimum viable safety layer Wysa has demonstrated is necessary.
The downside of a false positive (someone writes "no point going to that party") is one
skipped AI response and a gentle resource card — low cost. The downside of missing a real
signal and returning a journaling prompt is significant. Effort: S. This should land before
any coach features ship publicly.

---

## 6. Delivery Principles Synthesis (Cross-Cutting)

Drawn from the full mental health app review — these should be stated as product rules for
the relationship coach layer, not just individual features:

| Principle | Source | How it applies to MeetingScribe |
|---|---|---|
| **Turn length ≤ 3 sentences** | Woebot | All AI-generated coach output; enforce in persona constant (C2-3) |
| **One question at a time** | Woebot, Connected | Daily check-in = one question per relationship; never a form |
| **Tap-first, text-optional** | Daylio | Encounter entry (C2-1); mood/quality chips before free text |
| **Curious over evaluative** | Wysa, Reflectly | Prompt framing: "What did you notice?" not "Rate your relationship" |
| **Warm nudge language** | All | "How have things been?" not "Overdue: 18 days" (C2-6) |
| **Never mandatory** | Reflectly | Every prompt has a "Not now" path (C2-5) |
| **Scope discipline** | Wysa | First-use disclosure; not a therapist (C2-7) |
| **Authored content + LLM delivery** | Woebot, Connected | Prompt library (C2-8); LLM personalizes, doesn't generate frameworks |
| **Safety pre-flight** | Wysa | Distress filter (C2-4) before Ollama on all personal note content |
| **Retroactive logging** | Daylio | Allow past-date encounters without streak/overdue penalty |
