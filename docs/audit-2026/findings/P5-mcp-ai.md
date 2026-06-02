# P5 — MCP Expansion & AI Coaching
**Lens:** What People/relationship data Claude should read AND write via MCP; new tools beyond the current 17; proactive coaching patterns.

---

## 1. Lens statement

MeetingScribe's MCP server is currently a meeting-and-task retrieval tool with a thin people layer grafted on. The relationship coaching ambition — Gottman, attachment theory, NVC, love languages embedded as habits — requires Claude to have full encounter history, per-person relationship type context, check-in cadences, and durable write paths for coaching artifacts. None of those exist in the current 17 tools. This document maps the gap and proposes the net-new tools and patterns to close it.

---

## 2. The current 17 tools — exact inventory

Source: `Sources/MeetingScribeMCP/main.swift`, `toolList` definition at line 652.

| # | Name | Kind | What it exposes |
|---|------|------|-----------------|
| 1 | `list_meetings` | read | Meeting list with id/title/time/tags/artifact flags |
| 2 | `get_meeting` | read | Full meeting: metadata + transcript + notes + summary |
| 3 | `get_transcript` | read | `transcript.md` for one meeting |
| 4 | `get_notes` | read | `notes.md` for one meeting |
| 5 | `get_summary` | read | `summary.md` for one meeting |
| 6 | `list_voice_notes` | read | Voice note list with snippets |
| 7 | `get_voice_note` | read | Full transcript + metadata for one voice note |
| 8 | `list_people` | read | People index: name/company/role/email/phone/lastInteraction/counts |
| 9 | `get_person` | read | Full profile: contact + bio + favorites + memories + relationships + meetingMentionIDs |
| 10 | `get_person_messages` | read | iMessage stats + snippets from `chat.db` |
| 11 | `list_person_meetings` | read | Meetings linked to a person (attendee or transcript mention) |
| 12 | `list_action_items` | read | Action items filtered by status/meeting |
| 13 | `create_action_item` | **write** | New action item, optionally linked to a meeting |
| 14 | `update_action_item` | **write** | Patch status/priority/owner/due/notes on an existing item |
| 15 | `add_person` | **write** | Create a new Person record |
| 16 | `add_memory` | **write** | Append a Memory to a person's record |
| 17 | `create_meeting_note` | **write** | Append text to a meeting's `notes.md` |

The in-app `ChatTools` adds three more that only exist in the embedded chat surface (not in Claude Desktop via MCP): `get_overview`, `attach_note_to_person`, `list_projects`. These are invisible to Claude Desktop — a meaningful gap.

---

## 3. What Person/Encounter data is NOT yet exposed via MCP

### 3.1 Encounter records — completely invisible

`Encounter` (`Sources/MeetingScribe/People/Encounter.swift`) is a first-class model with: `personID`, `eventName`, `date`, `location`, `notes`, `meetingID`, `voiceNoteID`, `eventTagID`. **None of these fields appear in any MCP tool.** `get_person` returns only `memories` and `relationships` — encounters are never surfaced. Claude Desktop cannot answer "when was the last time Tyler physically met with Horst?" because encounter history does not exist in any MCP response.

Disk layout: `<storageDir>/encounters/<id>.json` — easily readable by the MCP server. No DTO exists in `VaultKit/SharedModels.swift` for `Encounter`. This is the most significant gap.

### 3.2 AttachedNotes — invisible to MCP

`AttachedNote` (`Sources/MeetingScribe/People/Person.swift:26`) stores long-form AI analyses (sentiment trends, relationship summaries, communication style). The in-app `attach_note_to_person` chat tool writes them (`PeopleChatTools.swift:341`), and the app displays them. But `PersonDTO` in `VaultKit/SharedModels.swift:186–211` does NOT include `attachedNotes` — they're stripped before Claude Desktop can read them. Claude cannot reference prior analyses.

### 3.3 Encounter cadence / "stay in touch" signal — invisible

`ReconnectView` (`SuggestedPeopleView.swift:84`) computes per-person reconnect cadences from encounter gaps (median × 1.5, clamped 7–120 days). `PeopleInsightsView` uses a 45-day flat threshold. Neither cadence nor the "overdue by N days" signal is exposed via MCP. Claude cannot independently calculate who is overdue.

### 3.4 Relationship type / path — not modeled at all

`Relationship.label` (`Person.swift:57`) is freeform: "spouse", "manager", "kid", "friend". There is no structured `relationshipType` enum — no concept of Partner, FamilyMember, CloseFriend, Colleague as distinct behavioral categories. `get_person` returns `relationships` as raw `[{label, toPersonID, toDisplayName}]` with no semantic category that Claude could use to select the right coaching framework.

### 3.5 Birthday data — in PersonDTO but not in MCP response

`PersonDTO.birthday` is decoded (`SharedModels.swift:202`) but `tool_getPerson` (`main.swift:1073`) does NOT include birthday in the returned JSON — the field is decoded but silently dropped in the response object construction at line 1094. Claude cannot use birthdays for proactive coaching.

### 3.6 Tag names — IDs only, not names

`get_person` returns `meetingMentionIDs` (an array of UUIDs) and `importSources`. It does not return resolved tag names, only raw `tagIDs`. Claude cannot filter people by tag ("show me all family members") without a tags lookup tool that doesn't exist.

### 3.7 Favorites — exposed but passive

`favorites` (`Person.swift:109`) is surfaced in `get_person` but never used by any coaching prompt. "Loves single-origin coffee" is a gold-mine for gift suggestions and re-engagement openers, but no tool gives Claude a cue to proactively surface it.

### 3.8 `attachedNotes` write path exists in app but not in MCP

`PeopleStore.addAttachedNote` exists and the in-app chat uses it via `attach_note_to_person`. But this tool is only in `PeopleChatTools.swift`, not in `main.swift`. Claude Desktop cannot persist analyses.

---

## 4. Existing plan items most relevant to this lens (endorsements)

The briefing's "already planned" list is broad. Through the MCP/coaching lens, three items matter most and I explicitly endorse them:

- **"Stay in touch" nudges (item 9)** — already partially built (`ReconnectView`, `PeopleInsightsView`). Endorsing the plan item; the MCP gap is that Claude Desktop sees none of this signal.
- **Write-capable MCP already done (item 12)** — the 5 write tools are live and the raw-JSON patch approach is solid. The right pattern to extend.
- **Per-tag summary templates (item 13)** — endorsing this as a foundation for relationship-type coaching paths.

I do NOT endorse god-file decomposition (item 14) as a priority through this lens — it's engineering hygiene, not relationship coaching value.

---

## 5. NET-NEW recommendations

### P5-1 — `get_person_encounters` read tool  
**What:** New MCP tool that returns the full encounter list for a person: `eventName`, `date`, `location`, `notes`, `meetingID`. Requires adding `EncounterDTO` to `VaultKit/SharedModels.swift` and reading `<storageDir>/encounters/` filtering by `personID`.  
**Why this matters:** Without encounter history, Claude cannot answer "when did I last see X in person?", "how often do we actually meet?", or coach on relationship health using real behavioral data instead of meeting-attendance inference.  
**How Claude uses it:** "Tyler, you've met Jordan 6 times in the last 3 months, all at work events. No personal hangouts. Based on Jordan's 'close friend' label, you may want to invite them somewhere non-work." This is impossible today.  
**Effort:** S (hours — the data is on disk, just needs a DTO and reader function mirroring `loadActionItemsFromDisk`).

### P5-2 — `log_encounter` write tool  
**What:** Claude can write a new encounter record for a person: `person_id`, `event_name`, `date`, `location` (optional), `notes` (optional), `meeting_id` (optional). Writes a new `<uuid>.json` to `<storageDir>/encounters/` using the same raw-JSON pattern as `tool_addMemory`. Updates `lastInteractionAt` on the person record via a field patch.  
**Why this matters:** The most important habit MeetingScribe can build is "log that you connected." Currently the only write affordances for People are memories (facts) and person creation. Logging an encounter — "just grabbed coffee with Jordan" — is the highest-value relationship data point and has no MCP path.  
**Coaching use:** After logging, Claude proactively computes next suggested check-in and adds it as an action item if the user confirms.  
**Effort:** S–M. The encounter file format is simple. The `lastInteractionAt` patch on `person.json` uses the existing `writePersonEnvelope` pattern.

### P5-3 — `set_checkin_reminder` write tool  
**What:** Write a structured check-in reminder onto a person record: `person_id`, `remind_on` (date), `cadence_days` (how often to repeat), `note` (optional context). Stored as a new `checkIn` field in `person.json`. The app's `NotificationManager` already schedules notifications (`NotificationManager.swift:159`) — this tool would write the data; the app reads it on next open to schedule the notification.  
**Why this matters:** Claude can say "you haven't talked to your sister in 6 weeks. Want me to set a monthly reminder?" — but today it has no write path to make that happen. The user has to manually go into the app.  
**Schema change required:** Add `checkIn: {remindOn: Date, cadenceDays: Int, note: String?}` as optional to `person.json`. Tolerant decoder means old records work. One new raw-JSON key in the patch.  
**Effort:** M (schema + app reader + MCP write tool + notification scheduling hookup).

### P5-4 — `get_relationship_health` composite read tool  
**What:** A single tool that, given a person ID, returns a health summary: days since last interaction, days since last encounter, message frequency (30/90 day — from existing `get_person_messages` data), encounter count (last 90 days), overdue vs. personal cadence (computed from encounter gaps), and birthday countdown. Claude uses this to generate a relationship health score without calling 4 tools in sequence.  
**Why this matters:** The current flow requires `get_person` + `get_person_messages` + `get_person_encounters` (once built) + manual date math. Small local models can't chain that reliably. A composite read tool with a single JSON object gives Claude everything to coach in one call.  
**Effort:** M (pure aggregation — no new data, just a new tool that calls existing readers and computes derived fields server-side).

### P5-5 — `add AttachedNote to PersonDTO` + `get_attached_notes` MCP read tool  
**What:** (a) Add `attachedNotes: [AttachedNoteDTO]` to `PersonDTO` in `VaultKit/SharedModels.swift` so `get_person` returns saved analyses. (b) Add a standalone `get_attached_notes` tool if the payload size is a concern. (c) Add `attach_note_to_person` to `main.swift` — it already exists in `PeopleChatTools.swift:102` but was never ported to the MCP server.  
**Why this matters:** If a user asks Claude Desktop to analyze their relationship with someone and save the analysis, the next time they ask Claude won't have the prior analysis in context. Every session starts cold. This is the primary reason coaching sessions feel disposable instead of cumulative.  
**Effort:** S for (c) (copy the existing logic from `PeopleChatTools.swift`). S for (a) (add field to DTO). Together these are a single PR.

### P5-6 — `get_people_needing_attention` proactive read tool  
**What:** A tool that returns the top N people who are overdue for contact, sorted by "most overdue relative to their personal cadence," with the cadence computation the `ReconnectView` already implements (`SuggestedPeopleView.swift:95–102`). Returns: `personId`, `displayName`, `daysSinceContact`, `personalCadenceDays`, `overdueByDays`, `lastInteractionAt`.  
**Why this matters:** Right now the "stay in touch" card on Today only appears in-app. Claude Desktop has no way to proactively surface "you should reach out to someone." This tool unlocks the key coaching behavior: Claude can open a session saying "Two people need attention: your brother (42 days overdue) and Sarah (18 days overdue)."  
**Effort:** S (pure computation over existing data, mirrors `ReconnectView.candidates`).

### P5-7 — Structured `relationshipType` field on Person  
**What:** Add `relationshipType: String?` to `Person` and `person.json` — values: `"partner"`, `"family"`, `"close_friend"`, `"friend"`, `"colleague"`, `"professional"`. Optional, defaults to nil (meaning "unclassified"). Expose it in `get_person` and `list_people`. Claude uses it to select the correct coaching framework: Gottman for partner, attachment-style for family, love languages for close friends, professional norms for colleagues.  
**Why this matters:** The current `relationship.label` is directional (A→B) and freeform. It describes how two people relate to EACH OTHER, not what TYPE of relationship the user has with them. A structured type on the Person itself is what enables relationship-path branching.  
**MCP implication:** `add_person` and a new `update_person` tool (P5-8) should accept `relationship_type`.  
**Effort:** S (add optional field, tolerant decoder, pass through DTOs and MCP responses).

### P5-8 — `update_person` write tool (patch identity fields)  
**What:** Claude can patch identity fields on an existing person: `display_name`, `company`, `role`, `bio`, `birthday`, `relationship_type` (P5-7). Uses the same raw-JSON patch pattern as `tool_addMemory`. Does NOT touch memories, encounters, or relationships — those have dedicated tools.  
**Why this matters:** Currently Claude can only CREATE a person or ADD a memory. It cannot correct a name spelling, update a job title after a promotion, or set a relationship type it discovers from a conversation. `PeopleChatTools` has no equivalent either. This is a missing write path.  
**Effort:** S–M (patch specific keys on `person.json` without re-encoding through DTO — same pattern as `tool_addMemory`).

### P5-9 — `get_relationship_coaching_prompt` generative tool  
**What:** A read tool that, given a person ID and optional context string, returns a structured coaching prompt Claude should deliver to the user: a recommended topic, a question to ask the person, and a reflection question for the user. Driven by relationship type (P5-7), last interaction distance, encounter history, and any attached notes. Built server-side as a template engine (no Ollama call — pure logic), so it works when Ollama is offline.  
**Why this matters:** This is the tool that transforms MeetingScribe from a CRM into a relationship coach. Instead of Claude having to synthesize all the context itself, the server does the template selection and Claude just delivers a pre-structured prompt. Faster, more consistent, works on smaller local models.  
**Example output:** `{"type": "check_in_prompt", "opener": "Ask about their new role at Stripe — you logged that they started 3 months ago", "reflection": "How do you feel about how frequently you two connect?", "framework": "Gottman: turning toward"}`  
**Effort:** M (template library for each relationship type, wired to existing data).

### P5-10 — `sync_chat_tools_to_mcp` — port missing in-app tools to MCP server  
**What:** Three tools exist in `PeopleChatTools.swift` / `ActionItemChatTools.swift` that are NOT in `main.swift`: `get_overview`, `attach_note_to_person`, `list_projects`. Port them directly — no new logic needed, just the MCP shell.  
**Why this matters:** This is the most embarrassing gap. A user asking Claude Desktop "give me an overview of my week" gets a worse answer than the same question in the app's in-app chat, because `get_overview` (the key diagnostic tool) is missing from MCP. `attach_note_to_person` means saved analyses don't work in Claude Desktop.  
**Effort:** S — copy the existing logic verbatim.

### P5-11 — Proactive coaching: `schedule_relationship_review` scheduled-context pattern  
**What:** Document (and wire) a pattern where the MCP server's `get_people_needing_attention` (P5-6) result is injected into Claude's system prompt or context block when opening a new Claude Desktop session. This turns passive tools into proactive coaching: Claude greets the user with "Good morning. Three people are overdue for a check-in. Want to work through them?" This requires a `claude_instructions.md` snippet in the MCP config or a resources endpoint, not a new tool per se.  
**Why this matters:** Every other coaching app (Replika, BetterUp, therapist apps) starts the session with the user's situation. MeetingScribe's Claude integration starts blank. This pattern is what separates a tool from a coach.  
**Effort:** S (config + MCP `resources/list` endpoint exposing a relationship-brief resource).

### P5-12 — `birthday` field fix in `tool_getPerson`  
**What:** `PersonDTO.birthday` is decoded correctly in `SharedModels.swift:202` but `tool_getPerson` in `main.swift:1094` never writes it into the response dict. The fix is a one-line addition: `"birthday": .string(p.birthday.map(iso) ?? "")`. Currently Claude Desktop cannot see any person's birthday even when it's stored.  
**Why this matters for coaching:** Birthday coaching ("Jordan's birthday is in 11 days — last year you texted late. What do you want to do differently?") is the highest-recall, highest-emotion moment in a relationship. It's blocked by a trivial oversight.  
**Effort:** S (one line — `main.swift` around line 1112).

---

## 6. Top 3 picks

**P5-1 + P5-2 together (get_person_encounters + log_encounter):** These two are inseparable. You cannot coach on encounter frequency without reading it, and you cannot build the logging habit without a write path. Combined effort: S–M for a full weekend sprint. These unlock every temporal coaching insight.

**P5-6 (get_people_needing_attention):** The single tool most likely to produce a "wow" moment in the first 5 minutes of a Claude Desktop session. Computes and surfaces the most emotionally relevant signal in the whole app — people you've been neglecting — in one call. Reuses entirely existing data and logic.

**P5-12 (birthday field fix):** Highest effort-to-impact ratio of any item in this document. One line of Swift. Unlocks birthday coaching permanently. Ship this today.

---

## 7. Architecture note: EncounterDTO gap in VaultKit

`VaultKit/SharedModels.swift` defines `PersonMemoryDTO` and `PersonRelationshipDTO` but has no `EncounterDTO`. The `Encounter` model in `Sources/MeetingScribe/People/Encounter.swift` has a richer shape than the VaultKit `Encounter` stub (adds `eventTagID`, `eventName`, `location`, `meetingID`, `voiceNoteID`). Adding `EncounterDTO` to `SharedModels.swift` is the prerequisite for P5-1 and P5-2, and it should model the app-side `Encounter`, not the VaultKit stub.
