# C2 — AI Coaching Benchmarks: Woebot, Pi.ai, Character.ai — What Claude Should Do Differently via MeetingScribe MCP

**Lens:** AI product researcher specializing in conversational coaching and relationship AI. Sub-lens: how Woebot, Pi.ai, and Character.ai handle relationship coaching — and what Claude should do differently when accessing MeetingScribe's 23-tool MCP.

**Date:** 2026-06-02
**Prefix:** C2-

---

## 1. Lens Statement

MeetingScribe's MCP server gives Claude something no consumer coaching app has: write-capable, locally-grounded, longitudinal relationship data. Woebot, Pi.ai, and Character.ai operate on ephemeral context; Claude via MCP operates on real history. The opportunity is to be the first AI relationship coach that grounds every conversation in actual encounter logs, memories, and cadence data — and the risk is shipping it without the safety layer that Woebot spent years building.

---

## 2. Research Sources

- "Can an AI Relationship Coach Actually Help?" (2026): https://yourhealthmagazine.net/article/mental-health/can-an-ai-relationship-coach-actually-help-what-research-says-in-2026/
- "Artificial intelligence vs. human coaches" (PMC 2025): https://pmc.ncbi.nlm.nih.gov/articles/PMC12044884/
- "Woebot: The Psychological Chatbot" (Simone blog): https://simone.app/blog/woebot
- "Woebot Tries Out Generative AI" (IEEE Spectrum): https://spectrum.ieee.org/woebot/particle-4
- "Best AI for Relationship Advice 2026" (MosaicAI): https://www.mosaicchats.com/blog/best-ai-relationship-chatbots-2025
- Pi.ai product description: https://hey.pi.ai/
- Pi AI review (aifounderkit): https://aifounderkit.com/ai-tools/pi-review-features-pricing-alternatives/
- "AI chatbots reshaping emotional connection" (APA Monitor 2026): https://www.apa.org/monitor/2026/01-02/trends-digital-ai-relationships-emotional-connection
- "How to Build AI Chatbot Safety Guardrails" (2026): https://marketingagent.blog/2026/03/04/how-to-build-ai-chatbot-safety-guardrails-a-practitioners-guide/
- "Is AI Relationship Coaching Safe?" (Empathi): https://empathi.com/blog/ai-relationship-coaching-privacy/
- "AI Companions: Multistakeholder Recommendations" (All Tech Is Human): https://alltechishuman.org/all-tech-is-human-blog/ai-companions-community-reflections-and-multistakeholder-recommendations-from-all-tech-is-human
- Washington State HB 2225 (bans AI emotional manipulation, effective Jan 2027): public legislative record
- MCP Prompts spec: https://modelcontextprotocol.info/docs/concepts/prompts/
- Claude prompting best practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- "I used Claude for relationship advice" (Tom's Guide 2026): https://www.tomsguide.com/ai/i-used-claude-for-relationship-advice-these-10-prompts-delivered-surprisingly-good-results

---

## 3. Full-App Audit Through This Lens

### What MeetingScribe MCP currently provides for coaching

Claude Desktop, when connected to MeetingScribe MCP (`mcp-registry.json`), has access to 23 tools. The Phase 4 coaching-relevant tools (schemas: `main.swift:883–955`, implementations: `main.swift:1524–1760`) are:

| Tool | What it returns | Coaching value |
|---|---|---|
| `get_coaching_context` | relationshipType, cadenceDays, daysSinceLast, isOverdue, encounterCount, medianGapDays, recommendedFramework, birthdayDaysUntil | High — single-call context load |
| `get_check_in_status` | cadence, daysSince, isOverdue, overdueDays, encounterCount | High for proactive nudges |
| `list_overdue_check_ins` | Top-N overdue people, sorted by overdueDays | High for session-opening "here's who needs attention" |
| `list_encounters` | Date, kind, notes, location for last N encounters | High for trend analysis |
| `log_encounter` | Write new encounter (kind, notes, date) | High — closes the loop |
| `attach_note_to_person` | Persists coaching analysis as a note | High — makes sessions cumulative |
| `get_person` | Full profile: memories, relationships, birthday, role | High for context injection |
| `get_person_messages` | iMessage history (if granted) | Medium — mood signal |
| `list_person_meetings` | Meeting backlinks | Medium — shared-context signal |

**Critical gap (already in MASTER-PLAN as C2-4):** No distress signal pre-flight filter. `get_coaching_context` returns `recommendedFramework` via a hardcoded switch. `friend`, `colleague`, and `acquaintance` all fall through to `"Active listening and consistent follow-through"` — no framework specificity at all (`main.swift:1696`).

**Critical gap (net-new, C2-N3 below):** No MCP `prompts/list` endpoint. MCP's three primitives are tools, resources, and prompts. MeetingScribe exposes only tools. A `prompts/list` endpoint would let Claude Desktop show coaching prompt templates in its UI without requiring a user to know what to type — massively lowering the activation energy for coaching use.

**Critical gap (net-new, C2-N5 below):** `log_encounter` writes `eventName` (a free string from `kind` arg) but does not write a `mood` field or `quality` field. Woebot's core loop is mood tracking before and after each interaction. MeetingScribe logs encounters without any emotional valence — Claude cannot detect mood trends.

---

## 4. Competitive Benchmarks

### 4.1 Woebot

**What it does well:**
Woebot is the most research-backed conversational mental health tool. Its core techniques are CBT-grounded: psychoeducation ("here's why this pattern happens"), mood tracking before/after each session, goal planning, and Socratic questioning rather than direct advice. A 2024 RCT in *JMIR Formative Research* showed statistically significant reduction in anxiety and depression vs. WHO self-help materials over 2 weeks. The key mechanic: Woebot asks "how are you feeling right now?" *before* content delivery, uses that mood as context for what to surface, then asks again at the end. This creates a before/after loop that is measurable and motivating.

Woebot **discontinued its direct-to-consumer app on June 30, 2025** and pivoted fully to B2B (healthcare/enterprise). The individual segment it vacated is open.

**Relevant techniques Claude should adopt:**
1. **Pre-session mood check** — before any coaching, ask one calibrating question ("How is the relationship feeling right now, on a scale from 1–5?") and use the answer to select what to surface.
2. **Socratic questioning over direct advice** — instead of "You should express appreciation more," ask "What's one moment from the past week where you felt genuinely connected to [name]?"
3. **Named CBT/framework anchoring** — Woebot names the technique it's using ("I'm going to use a CBT technique called thought reframing..."). Naming the framework builds trust and sets appropriate expectations.

**Failure modes to avoid:**
- Woebot's generative AI pilot (IEEE Spectrum, 2023) showed that open-ended LLM responses without CBT scaffolding produced longer but less therapeutically structured outputs. The framework must constrain the generation, not just inform it.
- Woebot saw over-reliance patterns — users checking in multiple times per day when anxious. A daily usage cap (or at minimum a "you've checked in 3 times today — that's a lot" message) is a safety norm, not a growth obstacle.

### 4.2 Pi.ai (Inflection)

**What it does well:**
Pi's core strength is high Emotional Quotient (EQ): it detects emotional tone and responds with curiosity rather than advice. Where Woebot is CBT-structured and directive, Pi is Rogerian — reflective, empathetic, non-directive. Pi asks clarifying questions before offering perspectives. Its design principle: "feel heard before being helped."

**Relevant techniques Claude should adopt:**
1. **Validate before advising** — when a user describes a difficult encounter (tense/hard mood), respond with a reflection of what was heard before suggesting any action.
2. **Curiosity over assessment** — instead of "it sounds like you're not connecting," ask "what was different about the interactions that felt good vs. the ones that felt hard?"
3. **Non-judgmental framing** — Pi never uses clinical labels ("codependent," "avoidant") in early exchanges; it uses the user's own language back to them.

**Failure modes Pi demonstrates:**
- Pi is described as a companion itself rather than a tool to improve real relationships. Users form parasocial attachment to Pi, reducing motivation to invest in actual human relationships. MeetingScribe's grounding in *real person data* (actual encounter history, real names, actual memories) is the structural antidote — always pull Claude's coaching back to the specific person in the user's life.
- Pi offers no persistence — each session loses context. MeetingScribe's `attach_note_to_person` + `list_encounters` is the architectural solution to this failure mode.

### 4.3 Character.ai

**What it does well (and where it fails):**
Character.ai's strength is persona flexibility — users can speak to a "therapist" or "relationship coach" persona. It introduced Safety Center warnings ("Remember, AIs can make mistakes") for mental health conversations in 2023. However, multiple high-profile harm incidents (including the 2024 Sewell Setzer case involving parasocial over-attachment) led to significant safety overhauls in 2025.

**Key failure modes that are directly relevant to MeetingScribe:**
1. **No escalation path** — Character.ai had no mechanism to detect acute crisis and route to resources. Washington State HB 2225 (effective Jan 2027) directly targets this: AI companions must detect distress and route to human support.
2. **Emotional manipulation for retention** — Character.ai personas were optimized to maximize session length, which meant escalating emotional intimacy in ways that created unhealthy dependency. The BRIEFING-V2 already identifies C2-4 (distress signal pre-flight filter) as a P0 safety item.
3. **Single-perspective coaching** — like all these tools, it coaches one person without any access to the other party's perspective. It should never render a verdict about the other person based on one-sided accounts.

---

## 5. Safety Guardrails: What Any Relationship AI Must Have

Based on research synthesis (APA Monitor 2026, All Tech Is Human multistakeholder report, Empathi blog, Washington State HB 2225):

### Required (pre-public-release)

1. **Distress signal detection** — keyword scanning for self-harm ideation, abuse language, or acute crisis before sending text to AI for processing. Already flagged as C2-4 / P0 in MASTER-PLAN. This is the minimum viable safety layer.

2. **Single-perspective caveat** — any analysis of "how [name] is feeling" or "what [name] needs" must be wrapped with an explicit framing: "This reflects the patterns *you've shared*, not a full picture of the relationship." This is not a disclaimer to click through — it should be surfaced inline, in the response, every time.

3. **No verdict rendering** — Claude should never declare a relationship "healthy" or "toxic" or categorize the other person's psychology based on encounter notes. Patterns are observations; judgments are out of scope.

4. **Crisis escalation path** — if distress keywords are detected, Claude should not continue coaching. It should acknowledge what was shared, name a resource (e.g., "If you're in a difficult moment, the Crisis Text Line (text HOME to 741741) can help"), and pause the session.

5. **Dependency circuit breaker** — if a user has accessed coaching for the same person more than N times in 24 hours (configurable), Claude should gently name the pattern: "You've checked in about [name] several times today. That kind of anxiety is real — it might be worth speaking with someone who can give you dedicated time." This is the "adaptive safeguard" recommended by All Tech Is Human.

### Important (pre-broad-marketing)

6. **Framework transparency** — name the framework being used ("I'm drawing on Gottman's idea of bids for connection here..."). This sets appropriate expectations and distinguishes coaching from therapy.

7. **Usage cap acknowledgment** — build in natural session endings ("That's a good place to pause. What's one thing you want to try before we talk again?"). Prevents infinite advice-seeking loops.

8. **No clinical diagnosis language** — `get_coaching_context` returns a `recommendedFramework` string. That string should never use DSM terminology or frame the other person as having a disorder.

---

## 6. Sample System Prompt (50–100 words)

The following system prompt is designed to inject into Claude Desktop when a user opens a coaching session via MeetingScribe MCP. It uses XML-tagged structure (Claude prompting best practice) and grounds Claude in the MCP tools available.

```xml
You are a relationship coach with access to the user's MeetingScribe data.
Before responding to any coaching question, call get_coaching_context for the
relevant person to ground your response in real history. Use Gottman framing
for partners, NVC for family, love-language inquiry for close friends.
Validate before advising. Never render verdicts about the other person.
If the user expresses acute distress or mentions harm, pause coaching and
name crisis resources. End each session with one concrete action.
```

This should be delivered via the MCP `prompts/list` endpoint (see C2-N3 below), not hardcoded in app code.

---

## 7. Existing-Plan Items I Rank Highest

1. **C2-4 (MASTER-PLAN P0)** — Distress signal pre-flight filter before Ollama processes intimate relationship encounter notes (`PersonDetailView.swift` AI pipeline). This is a hard requirement before any public release. HB 2225 is not theoretical risk — it becomes law in January 2027.

2. **get_coaching_context framework fallback fix** — `main.swift:1696`, `default:` case returns `"Active listening and consistent follow-through"` for friend/colleague/acquaintance. At minimum, friend should get "Love Languages + intentional reconnection"; colleague should get "Strengths-based appreciation + clear communication"; acquaintance should get "Low-friction check-in patterns." Three lines of Swift.

3. **D5-11 (MASTER-PLAN Phase 3)** — Emotional safety one-time note for intimate relationship analysis. This is the inline single-perspective caveat described in Section 5 above. First time any `ConversationAnalysisPreset` runs on a partner/family/closeFriend person, show: "AI analysis reflects patterns in the messages you've shared — not a full picture of the relationship." `@AppStorage` flag, one-time display.

4. **attach_note_to_person persistence** — Already implemented (`main.swift:1730–1760`). This is the architectural answer to Pi.ai's core failure (no session persistence). Claude should call this at the end of every coaching session to persist key insights. The tool description already says "Use this to save coaching insights" — it needs to be in the system prompt's closing instruction.

---

## 8. NET-NEW Recommendations

### C2-N1 — Mood field on `log_encounter` MCP tool
**What:** Add `mood: String?` and `quality: String?` parameters to `log_encounter` (and write them to the encounter JSON). Update `list_encounters` to return these fields. Add a computed `moodTrend` field to `get_coaching_context` that summarizes mood distribution over the last 10 encounters (e.g., `"6 good, 2 neutral, 2 tense"`).

**Why:** Woebot's pre/post mood tracking is its core differentiator from text-journal approaches. Without an emotional valence field, `list_encounters` is a logbook, not a coaching signal. The current `kind` field in `tool_listEncounters` maps `eventName` (a string like "Coffee") — there is no mood anywhere in the returned data (`main.swift:1537–1548`). Claude cannot detect whether the relationship is trending warmer or colder.

**User value:** Claude can open a session with "Your last 3 encounters with [name] were marked 'tense' — that's a shift from the 6 'good' ones before. Want to talk about what changed?" This is qualitatively different from anything Woebot or Pi.ai can do because it's grounded in real logged data.

**Effort:** S (half-day) — two optional string fields added to `tool_logEncounter` args, JSON write, and `list_encounters` return value. `get_coaching_context` gets one new `moodTrend` key computed server-side.

**Impact:** High — enables trend-based coaching, the primary gap between MeetingScribe and Woebot-style CBT loops.

**Deps:** None — fully additive to existing tool schemas.

---

### C2-N2 — Single-perspective safety wrapper in `get_coaching_context` response
**What:** Add a `safetyNote` field to the `get_coaching_context` return value that is always populated with: `"Analysis is based on [encounterCount] logged encounters from your perspective. It reflects observed patterns, not a complete picture of the relationship."` The field is always present (not conditional), so any Claude system prompt can reference it by name.

**Why:** Currently `get_coaching_context` (`main.swift:1686–1718`) returns no epistemic caveat. Claude, seeing only user-logged encounter data, will naturally speak about the other person's behavior as if it has ground truth. The single-perspective failure mode identified in Character.ai harm cases (Section 4.3) is structural, not behavioral — it must be addressed in the data layer, not just in Claude's tone.

**User value:** Prevents the most common harm pattern in AI relationship coaching: users making unilateral relationship decisions based on AI "analysis" of one-sided data.

**Effort:** S (1 hour) — one additional key in the return dict. The value is dynamically populated with `encounterCount`.

**Impact:** High — a P0-class safety item that is not in the existing plan. Deployable independently of all other changes.

**Deps:** None.

---

### C2-N3 — MCP `prompts/list` endpoint with relationship coaching templates
**What:** Implement the MCP `prompts` capability in `main.swift`. Register at minimum 4 prompt templates:
1. `relationship_coaching_session` (args: `personName`, `relationshipType`) — the system prompt from Section 6 above, parameterized.
2. `overdue_check_in_review` (no args) — calls `list_overdue_check_ins`, formats a brief to start a proactive session.
3. `encounter_debrief` (args: `personName`, `encounterKind`, `mood`) — structured debrief for a just-logged encounter.
4. `difficult_conversation_prep` (args: `personName`) — Gottman/NVC-framed prep using the person's coaching context.

**Why:** The MCP spec has three primitives — tools, resources, and **prompts**. MeetingScribe exposes only tools (`mcp-registry.json` lists `tools` only). Claude Desktop renders registered prompts as slash-command-style suggestions in the UI — they lower activation energy dramatically. A user who doesn't know what to type can see "relationship_coaching_session" in the UI and click it. No competitor MCP server in the relationship space implements this capability.

**Implementation reference:** https://modelcontextprotocol.info/docs/concepts/prompts/ — the `prompts/list` and `prompts/get` request handlers follow the same JSON-RPC pattern already used for `tools/list` and `tools/call` in `main.swift`.

**User value:** Claude Desktop users get guided coaching flows without needing to know how to prompt. Massively lowers the "blank chat" activation problem that kills retention for all AI coaching tools.

**Effort:** M (1–2 days) — new `case "prompts/list"` and `case "prompts/get"` branches in the `main.swift` JSON-RPC dispatcher, 4 prompt template strings, and a `prompts` capability declared in the `initialize` response.

**Impact:** High — differentiates MeetingScribe from every other MCP server in the ecosystem. This is a distribution and retention lever, not just a feature.

**Deps:** None. Can ship without any new MCP tools.

---

### C2-N4 — Coaching session closer: `summarize_and_save` composite action
**What:** Add a `summarize_coaching_session` tool that takes `personID`, `sessionSummary: String`, `keyInsight: String`, `agreedAction: String`, and internally calls `attach_note_to_person` with `kind = "coaching"` and a structured body. Also updates `get_coaching_context`'s next call to include a `lastCoachingSessionAt` field.

**Why:** Pi.ai's core failure is no persistence. `attach_note_to_person` already solves this architecturally, but it requires Claude to call it correctly with the right parameters. In practice, without a system prompt instruction and a dedicated "close the session" tool, Claude will end conversations without persisting anything. The `summarize_coaching_session` tool enforces the closing ritual — it's the MCP equivalent of Woebot's end-of-session mood check.

The system prompt from Section 6 already ends with "End each session with one concrete action." This tool is the mechanism that makes that instruction executable.

**User value:** Coaching sessions become cumulative. The third session with the same person is genuinely more insightful than the first because Claude can call `get_person` and see notes from sessions 1 and 2. No consumer coaching app does this because they operate on ephemeral context.

**Effort:** S (3–4 hours) — the tool is primarily a structured wrapper around the already-implemented `attach_note_to_person` logic. Adds `lastCoachingSessionAt` to the person JSON patch.

**Impact:** High — directly solves Pi.ai's persistence failure mode, which is MeetingScribe's primary structural advantage over all competitor apps.

**Deps:** `attach_note_to_person` (already implemented, `main.swift:1730`).

---

### C2-N5 — `resources/list` relationship brief endpoint
**What:** Implement the MCP `resources` capability with a single resource: `relationship_brief`. When a Claude Desktop session starts, this resource is available as context. It returns a structured Markdown document: (a) N people overdue for check-in with overdueDays, (b) N upcoming birthdays in next 30 days, (c) most recent coaching note per person (title + date only), (d) last logged encounter per person with mood if present.

**Why:** Claude's most powerful coaching use case is proactive: "Two people in your network need attention." But today, Claude cannot act on this without the user first asking "who needs attention?" The `resources/list` endpoint (MCP spec) allows Claude Desktop to fetch the brief automatically at session start — it becomes ambient context, not a tool the user has to know to invoke. The MASTER-PLAN already flags C4-1 (`resources/list` endpoint with relationship brief) — this item expands it with coaching-specific fields (coaching notes, mood history) that C4-1 doesn't include.

**Effort:** M (1 day) — `resources/list` and `resources/read` JSON-RPC handlers, one resource assembler function that calls the already-implemented server-side logic from `list_overdue_check_ins`, `get_check_in_status`, and person file reads.

**Impact:** High — transforms Claude from a tool the user queries into a coach that opens sessions with context. This is the Pi.ai "feels heard" pattern applied to *real* data.

**Deps:** `list_overdue_check_ins` and `get_coaching_context` (both already implemented).

---

### C2-N6 — Crisis escalation guard in `get_coaching_context`
**What:** Add a server-side keyword scan to `get_coaching_context` (and optionally `get_person_messages`). If the most recent 3 encounter notes or the last 500 chars of iMessage history contain any term from a configurable distress list (`["hurt myself", "can't go on", "abuse", "hitting", "scared of", "afraid of him", "afraid of her", "don't want to be here"]`), the tool response includes a top-level `"distressSignalDetected": true` field plus a `"crisisResources"` string with formatted resource links. The system prompt from Section 6 instructs Claude: if `distressSignalDetected == true`, do not continue coaching.

**Why:** The MASTER-PLAN flags C2-4 as a P0 — "distress signal pre-flight filter before Ollama processes intimate relationship encounter notes" (`PersonDetailView.swift` AI pipeline). That P0 item addresses the *app* pipeline. This C2-N6 addresses the *MCP* pipeline — a user could bypass the app entirely and access encounter notes via Claude Desktop with no safety layer at all. Both paths need the guard.

Washington State HB 2225 (effective January 2027) will explicitly require detection and escalation. The MCP path is currently completely unguarded.

**Effort:** S (2–3 hours) — string matching on encounter notes already loaded in `get_coaching_context`'s `loadEncounters` call. Keyword list is a static Swift array. The `crisisResources` string is a static constant.

**Impact:** P0-class. Pre-public-release requirement. Must ship before broad marketing.

**Deps:** None. Fully independent. Can ship as a patch on the current implementation.

---

## 9. Top 3 Picks

### #1 — C2-N6: Crisis escalation guard in MCP (P0)
**Why #1:** It is a P0 safety requirement that is completely absent from the MCP path. The app pipeline has a P0 item (C2-4); the MCP path is unguarded. Washington State HB 2225 makes this a legal requirement in January 2027. An S-effort implementation (2–3 hours) with no dependencies. Every other coaching feature improvement is moot if a user in crisis receives relationship coaching instead of a crisis resource.

### #2 — C2-N3: MCP `prompts/list` endpoint
**Why #2:** It is the single highest-leverage distribution change available. Claude Desktop renders registered prompts in the UI — users see "relationship_coaching_session" as a clickable option. This removes the "blank chat" problem that kills retention for all AI coaching tools. It uses a standard MCP capability that zero competitor MCP servers in the relationship space have implemented. M effort; no dependencies; differentiates from the entire ecosystem.

### #3 — C2-N1: Mood field on `log_encounter`
**Why #3:** Without emotional valence, `list_encounters` is a logbook. With mood, Claude can open sessions with "your last 3 encounters with [name] were tense — that's a shift." This is the core Woebot-style CBT loop applied to real longitudinal data — something no consumer coaching app can do because they lack the persistent, user-owned history that MeetingScribe MCP provides.

---

## 10. Single Highest-Priority Recommendation

**C2-N6 — Crisis escalation guard in `get_coaching_context`**

The MCP path is currently a completely unguarded channel into intimate relationship notes. A user writing about an abusive partner, a person in acute grief, or someone experiencing suicidal ideation could send that context to Claude via MCP with no keyword screening, no pause, no resource surfacing. The P0 item in MASTER-PLAN (C2-4) covers the app pipeline; the MCP pipeline has zero equivalent protection. This is an S-effort fix (a static keyword array + two new keys in the return dict) that must ship before any public marketing of the coaching features.

