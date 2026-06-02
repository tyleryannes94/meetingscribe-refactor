# P4 — MCP Coaching Quality (Phase 4 Tools)

**Lens:** Are the 6 new Phase 4 MCP tools genuinely useful for Claude to coach with, or are they data dumps Claude doesn't know how to use?

---

## Tool-by-Tool Evaluation

### 1. `list_encounters` (main.swift:883–894, 1524–1545)

**Schema clarity:** The description says "understand the relationship's health over time" — passive and vague. There is no guidance on when to call this vs `get_person` (which already returns linked meeting IDs) or `get_coaching_context` (which returns `encounterCount` and `medianGapDays`). Claude has no signal distinguishing "I need raw encounter rows" from "I need a health summary."

**Output quality:** Returns `id`, `date`, `kind`, `notes`, `location`. The `kind` field maps to `enc["eventName"]`, which is a raw freeform string (e.g. `"📞 Call"`, `"☕️ Coffee / Meal"`) — not a normalized enum. Claude cannot reliably categorize or count encounter types.

**Missing:** No `mood` field in the output, even though `QuickEncounterSheet` appends mood as a `#tag` in `notes`. Claude would have to parse free text to detect sentiment trends. No date-range filter parameter — fetching 20 rows for a 5-year relationship buries useful patterns.

**Verdict:** Usable for raw listing but not for coaching. Claude gets a list with no instructions and no filter options.

---

### 2. `log_encounter` (main.swift:896–910, 1547–1586)

**Kind values:** The description says `"Type: Call, Coffee / Meal, Video Call, Message, Met Up, or Milestone."` — this is inline prose, not a JSON Schema `enum`. Claude has to parse a sentence to know the valid values. If Claude hallucinates `"phone call"` or `"zoom"`, the implementation accepts it silently (`kind` is stored verbatim as `eventName`). There is no validation, no normalization, no error on invalid kind values.

**Critical mismatch:** `VaultKit/Encounter.swift:7` defines a *different* Kind enum: `meeting, call, email, message, note`. The app-side Swift model and the MCP input/output use completely different vocabularies. An encounter logged via MCP as `"Coffee / Meal"` would not match any `VaultKit.Encounter.Kind` case, breaking any app-side aggregation that reads the stored file.

**Missing:** No `mood` parameter. The QuickEncounterSheet supports mood chips (great/good/neutral/tense/hard) but log_encounter has no way to capture this, creating a data asymmetry between app-logged and MCP-logged encounters.

**Verdict:** Will silently accept garbage input and write bad data. Kind must be an `enum` in the schema.

---

### 3. `get_check_in_status` (main.swift:921–930, 1588–1625)

**Output format:** Returns `overdueDays`, `isOverdue`, `cadenceDays`, `daysSinceLast`, `encounterCount`. The data is clean and structured.

**Claude-friendliness problem:** Claude receives `overdueDays: 14` with no guidance on what to *do* with it. There is no interpretation layer — no severity classification (mild overdue vs. critical), no suggested action, no coaching message template. Claude must independently decide that 14 days overdue on a `close_friend` cadence (default 14 days) means the relationship is 2x beyond target, and improvise a response.

**Missing interpretation fields:** No `overdueLevel` (e.g., `"mild"/"moderate"/"critical"`), no `suggestedAction` (e.g., `"Send a quick text today"`), no `lastEncounterKind` (so Claude can say "you haven't called Sarah since your coffee in March").

**Ambiguous edge case:** When a person has zero encounters, `lastDate` falls back to `p.lastInteractionAt ?? p.createdAt` (line 1611). Claude cannot tell whether "14 days since last contact" means 14 days since a real conversation or 14 days since the person was added to the app. The output field is `lastEncounterDate` in all cases — misleading.

**Verdict:** Data is correct but semantically thin. Claude has to build its own coaching logic from raw integers with no scaffolding.

---

### 4. `list_overdue_check_ins` (main.swift:932–940, 1627–1651)

**Context returned per person:** `personID`, `personName`, `relationshipType`, `overdueDays`. That is all.

**The coaching problem:** To write a meaningful outreach message, Claude needs to know *why* the relationship exists, what they last talked about, and what the other person cares about. This tool returns none of it. A typical Claude response to this list would be "You're overdue with Sarah (34 days), Mike (21 days), and Jake (18 days)" — which adds zero value over the app's own StayConnectedSection.

**Missing fields:** No `lastEncounterKind`, no `lastEncounterDate`, no `lastEncounterNotes`, no `cadenceDays`. Claude cannot say "You last messaged Mike 21 days ago" — it only knows he is 21 days overdue. No `birthdayDaysUntil` — the birthday countdown exists in `get_coaching_context` but is absent here, so Claude misses the urgency signal "Sarah's birthday is in 3 days and you're 14 days overdue."

**Verdict:** A name-and-number dump. Claude needs at minimum last-encounter-kind + cadence to write anything non-trivial.

---

### 5. `get_coaching_context` (main.swift:943–952, 1653–1718)

**Framework output analysis:** The `recommendedFramework` string for the three typed relationships is reasonable:
- `romantic_partner` → "Gottman Method — focus on bids for connection, love languages, and repair"
- `family_member` → "NVC (Non-Violent Communication) — needs, feelings, and empathic listening"
- `close_friend` → "Love Languages + intentional time — quality time and acts of appreciation"

But `friend`, `colleague`, and `acquaintance` all fall through to the default: `"Active listening and consistent follow-through"` (main.swift:1712). That is a generic business phrase, not a coaching framework. It does not tell Claude *how* to coach — there are no specific techniques, no example prompts, no action suggestions. Even the three specific frameworks are just labels: Claude receives "Gottman Method" but has no attached playbook, question bank, or prompt templates.

**Structural problem:** `recommendedFramework` is a single string. Claude cannot extract the framework name separately from its description. A `{ name: "gottman", description: "...", suggestedQuestions: [...] }` structure would be actionable.

**Also missing from output:** No `memories` field — the person likely has stored memories (things they care about, past conversation topics) that are the single highest-value input for personalized coaching. `get_person` returns memories; `get_coaching_context` ignores them entirely.

**Verdict:** The best of the 6 tools, but the framework field is a label, not a playbook. Three of six relationship types get a useless fallback.

---

### 6. `attach_note_to_person` (main.swift:953–961, 1720–1770)

**Trigger clarity:** The description says "typically an analysis output (relationship summary, coaching insight, sentiment analysis)." This is the clearest usage trigger of all 6 tools, but it is still backward-looking — it positions the tool as a save-after-analysis action.

**The gap:** Claude has no natural cue to call this tool unprompted. In a typical conversation ("How should I reconnect with Sarah?"), Claude would generate coaching advice, deliver it in chat, and stop. Nothing in the tool list tells Claude "if you generate coaching advice for a person, always persist it with attach_note_to_person." Without that instruction, the tool is only used if the user explicitly says "save this."

**`kind` field:** Valid values are `summary, sentiment, coaching, custom` — listed in the description as prose, not a JSON Schema `enum`. Same problem as `log_encounter`.

**Return value:** Returns `ok: true, noteId, personName, title, kind` but not the note `body` — Claude cannot confirm what was saved without calling `get_person` again.

**Verdict:** Tool exists but lacks a conversational trigger. The "auto-persist coaching outputs" pattern is missing from both the tool description and any system-level instructions.

---

## System Prompt / Coaching Orchestration Analysis

There is **no system prompt** and **no coaching workflow guidance** anywhere in the MCP server. The `initialize` response (main.swift:1843–1848) returns only `protocolVersion`, `capabilities: {tools: {}}`, and `serverInfo: {name, version}`. There are no:

- `prompts` capability (MCP 2024-11-05 supports `prompts/list`)
- `resources` capability
- Server-level instructions telling Claude when to call these tools together
- A workflow description like: "When a user asks about their relationship with someone, call `get_coaching_context` first, then `list_encounters` for recent history, then formulate advice, then `attach_note_to_person` to persist it."

Claude is expected to infer multi-tool workflows from individual tool descriptions alone. Given the overlap between `list_encounters`, `get_check_in_status`, `get_coaching_context`, and `get_person`, Claude will make inconsistent choices about which tools to call and when.

---

## Existing Plan Items I Rank Highest

1. **P4-existing-1 — Two conflicting `Encounter.Kind` enums** (BRIEFING-V2.md critical gap #6): The `VaultKit/Encounter.swift` Kind (`meeting/call/email/message/note`) and `QuickEncounterSheet` Kind (`call/coffee/videoCall/message/metUp/milestone`) are irreconcilable. MCP-logged encounters use the QuickEncounterSheet vocabulary but land in a flat JSON file that the app reads without validation. This is a data corruption risk, not just a code smell. Must be resolved before any encounter-based health score algorithm is meaningful.

2. **P4-existing-2 — `get_coaching_context` fallback for friend/colleague/acquaintance** (BRIEFING-V2.md critical gap #8): Three of six relationship types get `"Active listening and consistent follow-through"`. These are likely the *majority* of a user's contacts. The fallback framework gives Claude nothing to work with.

3. **P4-existing-3 — `PersonDTO` memberwise init missing Phase D fields** (BRIEFING-V2.md critical gap #7): If `relationshipType` and `checkInCadenceDays` are stripped during round-trip serialization, every cadence calculation in all 6 tools falls back to hardcoded defaults. The tools appear to work but silently use wrong data.

---

## NET-NEW Recommendations

### P4-N1 — Add `enum` constraints to all freeform `kind` parameters
**What:** Change `log_encounter.kind` and `attach_note_to_person.kind` from prose descriptions to JSON Schema `enum` arrays. For `log_encounter`: `["Call", "Coffee / Meal", "Video Call", "Message", "Met Up", "Milestone"]`. For `attach_note_to_person`: `["summary", "sentiment", "coaching", "custom"]`.
**Why:** Without `enum`, Claude hallucinates values that pass silently, corrupt data, and break app-side aggregation. JSON Schema `enum` is natively understood by Claude — it constrains output without additional prompting.
**User value:** Encounter history becomes reliable and filterable. App and MCP use the same vocabulary.
**Effort:** S (hours — schema change + add input validation with error return)
**Impact:** High — data integrity for all encounter-dependent features
**Deps:** Resolve the dual-Kind enum conflict first (P4-existing-1)

---

### P4-N2 — Add `mood` parameter to `log_encounter` and `mood` field to `list_encounters` output
**What:** Add `mood: string (enum: ["great","good","neutral","tense","hard"])` as an optional parameter to `log_encounter`. Store it as a top-level field in the encounter JSON (not buried in notes as a tag). Return it in `list_encounters` output.
**Why:** `QuickEncounterSheet` already captures mood, but MCP-logged encounters never can. Mood is the richest signal for relationship health over time — a string of "tense" encounters is a coaching trigger that `get_coaching_context` currently cannot detect. Claude explicitly coaching from mood trends ("your last 3 calls with your dad were marked 'tense' — have you tried…") is a differentiated capability no competitor offers.
**User value:** Claude can say "your last 3 interactions with Mike were 'tense' — here's what Gottman says about repair attempts" instead of "you haven't talked to Mike in 21 days."
**Effort:** S (add field to schema + implementation + loadEncounters return)
**Impact:** High — unlocks sentiment-aware coaching
**Deps:** P4-N1

---

### P4-N3 — Add `lastEncounterKind`, `lastEncounterDate`, `cadenceDays` to `list_overdue_check_ins` output
**What:** For each person in the overdue list, include `lastEncounterKind: string`, `lastEncounterDate: string`, `cadenceDays: int`, and `birthdayDaysUntil: int?`.
**Why:** Currently the tool returns 4 fields per person. Claude cannot write a meaningful coaching message from a name and an integer. "You haven't called Sarah since your coffee last month, and her birthday is in 4 days" requires all of these fields — and they are already computed in nearby functions.
**User value:** Claude's daily check-in coaching becomes genuinely personalized instead of generic.
**Effort:** S (fetch last encounter in existing loop, add 3 fields)
**Impact:** High — transforms the tool from a list into an actionable brief
**Deps:** None

---

### P4-N4 — Expose `memories` in `get_coaching_context` output
**What:** Add a `memories: [{ content: string, createdAt: string }]` array (capped at 5 most recent) to `get_coaching_context` output, drawn from the person's stored memories.
**Why:** Memories (things the person cares about, past conversation topics, shared experiences) are the single highest-value input for personalized coaching. `get_coaching_context` is the tool Claude calls before coaching, yet it omits the entire memories store that `get_person` exposes. Claude having "Sarah loves hiking, is going through a job transition, and has a daughter named Lily" produces fundamentally different coaching than having only a cadence integer and a framework label.
**User value:** Coaching messages feel like they come from someone who knows the person, not a CRM reminder.
**Effort:** S (load memories array from person.json, append to response)
**Impact:** High — single highest-leverage coaching quality improvement
**Deps:** None

---

### P4-N5 — Add structured coaching frameworks instead of strings
**What:** Replace `recommendedFramework: string` in `get_coaching_context` with a structured object:
```json
{
  "recommendedFramework": {
    "name": "Gottman Method",
    "keyPrinciple": "Bids for connection — small moments of turning toward your partner",
    "suggestedQuestions": [
      "What's been on your mind most this week?",
      "Is there anything you've been wanting to talk about?"
    ],
    "repairPhrase": "I need a moment, but I'm not going anywhere."
  }
}
```
Add frameworks for `friend` (Dunbar reciprocity), `colleague` (psychological safety / Edmondson), and `acquaintance` (weak-ties theory / Granovetter). Remove the generic fallback.
**Why:** A framework label tells Claude nothing it doesn't already know. A structured object with key principle + 2 suggested questions gives Claude a scaffolded coaching output that is consistent, evidence-based, and differentiable from what GPT-4 would say freehand.
**User value:** Coaching advice references real techniques with specific language, not generic wellness phrases.
**Effort:** M (write frameworks for all 6 types, restructure output schema)
**Impact:** High — directly addresses the core MCP quality gap
**Deps:** None

---

### P4-N6 — Add MCP `prompts` capability with coaching workflow templates
**What:** Implement the `prompts/list` and `prompts/get` MCP methods (supported in MCP protocol version 2024-11-05). Expose 3 prompt templates:
- `coaching_check_in`: "The user wants coaching on their relationship with {{personName}}. Call get_coaching_context, then list_encounters (limit 5), then formulate advice using the recommended framework. End by calling attach_note_to_person with kind=coaching."
- `daily_relationship_brief`: "Call list_overdue_check_ins, then for each person call get_coaching_context. Generate a prioritized action plan for today."
- `log_and_reflect`: "The user just had an interaction with {{personName}}. Call log_encounter, then get_check_in_status, then offer one coaching observation."
**Why:** Without workflow prompts, Claude must infer multi-tool sequences from individual descriptions. It will call tools inconsistently and almost never auto-persist outputs via attach_note_to_person. Prompts are the MCP-native mechanism for encoding "here is how these tools work together." Claude Desktop surfaces them as slash commands.
**User value:** "Coach me on Sarah" becomes a reliable, consistent, multi-step workflow rather than an improvised single-tool call.
**Effort:** M (add prompts/list + prompts/get handler to JSON-RPC loop, write 3 prompt templates)
**Impact:** Critical — addresses the root cause of all MCP quality gaps (no workflow orchestration)
**Deps:** P4-N4, P4-N5

---

### P4-N7 — Fix the `lastDate` fallback ambiguity in `get_check_in_status`
**What:** Add a `lastContactSource: string` field to `get_check_in_status` output with values `"encounter"`, `"lastInteractionAt"`, or `"createdAt"`. When `lastContactSource != "encounter"`, also return a `warning: "No encounters logged — cadence calculated from record creation date"`.
**Why:** Claude currently cannot distinguish "Sarah is 14 days overdue on a 14-day cadence" (genuinely lapsed) from "Sarah was added to the app 14 days ago and has never been logged" (brand new contact). The coaching implication is completely different. Claude will generate false urgency for new contacts.
**User value:** Prevents embarrassing coaching messages like "You haven't called your new colleague in 14 days!" on day 1.
**Effort:** S (add 2 fields to existing implementation — source is already determinable from the existing conditional)
**Impact:** Medium — prevents false positives that erode user trust
**Deps:** None

---

### P4-N8 — Add `overdueSeverity` classification to check-in tools
**What:** Add a computed `overdueSeverity: "on_track" | "mild" | "moderate" | "critical"` field to both `get_check_in_status` and `list_overdue_check_ins`. Thresholds relative to cadence: mild = 1–1.5x, moderate = 1.5–2x, critical = >2x overdue.
**Why:** Claude receiving `overdueDays: 14` on a `cadenceDays: 7` relationship (moderate) vs `overdueDays: 14` on a `cadenceDays: 60` relationship (on track) should produce completely different responses. Without a severity classification, Claude has to do the arithmetic itself — and often won't, defaulting to treating all overdue as equally urgent.
**User value:** Claude's coaching urgency is calibrated. "Sarah is critically overdue" vs "Mike is slightly past his usual cadence" produces meaningfully different advice.
**Effort:** S (computed field in existing functions — overdueDays / cadenceDays ratio)
**Impact:** Medium — improves coaching calibration across all relationship types
**Deps:** None

---

### P4-N9 — Silent failure in `attach_note_to_person` when person directory not found
**What:** `tool_attachNoteToPerson` iterates person directories and breaks on first match. If no match is found (person.json has an unexpected structure, or the directory scan returns no results), the function returns `ok: true` with a valid-looking response but the note was never saved (main.swift:1755–1770). Add a `saved: false` + `error: "person directory not found"` path.
**Why:** Claude receives `{ok: true}` and tells the user "I've saved that coaching note to Sarah's profile" — but the file was never written. Silent success on write failure is a data integrity bug.
**User value:** Claude can say "I couldn't save the note — try again" instead of falsely confirming.
**Effort:** S (add a boolean written flag before the loop, check after the break)
**Impact:** Medium — prevents trust-eroding false confirmations
**Deps:** None

---

### P4-N10 — Add `get_coaching_context` result to `list_overdue_check_ins` via a `detailed` flag
**What:** Add an optional `detailed: bool` parameter to `list_overdue_check_ins`. When `true`, inline `get_coaching_context` data for each person (framework, memories snippet, last encounter kind) instead of requiring N+1 tool calls.
**Why:** Claude handling a "who should I reach out to today?" request currently needs: 1 call to `list_overdue_check_ins`, then N calls to `get_coaching_context` for each person. For a user with 5 overdue contacts, this is 6 tool calls. Claude often stops after the list, never fetching context. A `detailed: true` flag enables a one-shot daily brief.
**User value:** "Give me my daily relationship brief" becomes a single tool call that produces actionable, personalized output.
**Effort:** M (loop calling getCoachingContext logic for each row, add to response)
**Impact:** High — reduces tool-call friction for the most common coaching use case
**Deps:** P4-N4, P4-N5

---

### P4-N11 — Add `encounter_frequency_trend` to `get_coaching_context`
**What:** Add `encounterFrequencyTrend: "increasing" | "stable" | "declining" | "dormant"` to `get_coaching_context`, computed by comparing the median gap from the last 90 days vs the prior 90 days.
**Why:** `medianGapDays` is a static snapshot. A relationship where the median gap has gone from 7 to 21 days over the past 6 months is in decline even if the current overdue count is low. "Your relationship with Sarah has been declining in frequency — you were talking every week in January and now it's monthly" is a qualitatively different coaching trigger than "you're 3 days overdue."
**User value:** Proactive trend coaching, not just reactive overdue alerts — catches drift before it becomes a critical gap.
**Effort:** M (compute 90-day windowed medians, add enum field)
**Impact:** High — enables proactive coaching, differentiating from any CRM-style tool
**Deps:** None

---

## Top 3 Picks

1. **P4-N6 — MCP `prompts` capability with coaching workflow templates** — The root cause of all quality gaps is that Claude has no workflow guidance. Individual tool descriptions cannot encode multi-tool sequences. Prompts are the MCP-native fix and require no changes to any tool schema or implementation.

2. **P4-N5 — Structured coaching frameworks** — Replacing `recommendedFramework: string` with a structured object (key principle + suggested questions) is the single highest-leverage change to actual coaching output quality. Three of six relationship types currently get a string that means nothing.

3. **P4-N4 — Expose `memories` in `get_coaching_context`** — Memories are already stored and already returned by `get_person`. Adding them to the coaching context tool takes hours and transforms every coaching output from generic to personal.

---

## Single Highest-Priority Recommendation

**P4-N6: Add MCP `prompts` capability** is the most important fix.

All other gaps (thin output, missing fields, no severity classification) can be partially compensated by a smart Claude that calls multiple tools and reasons carefully. But without workflow prompts, Claude cannot reliably orchestrate the 6 tools together, will rarely call `attach_note_to_person` unprompted, and will make different choices on every invocation. The `prompts` capability is the correct MCP-native mechanism for encoding "call these tools in this order for this use case" — it produces consistent behavior across Claude versions and does not require the user to engineer their prompts manually. Implementing 3 prompt templates (coaching_check_in, daily_brief, log_and_reflect) costs ~1 day and fixes the orchestration gap that all other improvements depend on.

