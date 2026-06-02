# E3 — MCP Server: Tool Audit, People Data Gaps, and Decomposition Plan

**Lens:** Concrete Swift implementation of new MCP tools; People/relationship data not exposed to Claude; decomposition of the 1526-line `main.swift` monolith.

---

## 1. Lens statement

`Sources/MeetingScribeMCP/main.swift` is 1526 lines and carries five distinct concerns in one file: storage resolution helpers, iMessage/SQLite analysis (~200 lines), tool schema definitions (~230 lines), tool implementations (~540 lines), and the JSON-RPC loop (~80 lines). It compiles and works, but adding any new tool or extending people data requires editing this monolith. This document maps all 17 current tools with exact signatures, catalogs every People field not yet surfaced to Claude, and proposes both new tools and a decomposition plan with file boundaries.

---

## 2. All 17 current tools — exact signatures

Source: `main.swift`, `toolList` definition at line 652; `runTool` dispatcher at line 1419.

| # | Tool name | Kind | Input params | What it returns |
|---|-----------|------|-------------|----------------|
| 1 | `list_meetings` | read | `limit: Int = 100`, `tag: String?` | Array of meetings: id/title/start/end/duration/attendees/tags/calendar/isImpromptu/hasTranscript/hasNotes/hasSummary/folder |
| 2 | `get_meeting` | read | `id: String` (required) | Full meeting: all metadata + transcript/notes/summary text + health status |
| 3 | `get_transcript` | read | `id: String` (required) | `{text: String}` — raw `transcript.md` |
| 4 | `get_notes` | read | `id: String` (required) | `{text: String}` — raw `notes.md` |
| 5 | `get_summary` | read | `id: String` (required) | `{text: String}` — raw `summary.md` |
| 6 | `list_voice_notes` | read | `limit: Int = 100` | Array: id/title/createdAt/durationSeconds/snippet/wasDictation/folder |
| 7 | `get_voice_note` | read | `id: String` (required) | Full quick note: id/title/createdAt/durationSeconds/wasDictation/transcript/audioPath/folder |
| 8 | `list_people` | read | `query: String?`, `limit: Int = 20` | Array: id/displayName/company/role/primaryEmail/primaryPhone/lastInteractionAt/meetingMentionCount/memoryCount/importSources |
| 9 | `get_person` | read | `id: String` (required; tolerant lookup) | Full profile: contacts + bio + favorites + memories + relationships + birthday + meetingMentionIDs + importSources |
| 10 | `get_person_messages` | read | `id: String` (required), `snippetLimit: Int = 20` | iMessage stats (total/sent/received/first/last/30d/90d) + recent snippets |
| 11 | `list_person_meetings` | read | `id: String` (required), `limit: Int = 50` | Meetings linked by attendee-name match or transcript mention |
| 12 | `list_action_items` | read | `status: String?`, `meeting_id: String?`, `limit: Int = 200` | Action items with full metadata |
| 13 | `create_action_item` | **write** | `title: String` (required), `owner?`, `status?`, `priority?`, `due_date?`, `notes?`, `meeting_id?` | `{ok, id, title, warning?}` |
| 14 | `update_action_item` | **write** | `id: String` (required), `title?`, `status?`, `priority?`, `owner?`, `due_date?`, `notes?` | `{ok, id, updated: [String]}` |
| 15 | `add_person` | **write** | `display_name: String` (required), `company?`, `role?`, `email?`, `phone?`, `bio?` | `{ok, id, displayName, folder}` |
| 16 | `add_memory` | **write** | `id: String` (required), `text: String` (required), `occurred_on?` | `{ok, personId, displayName, memoryCount}` |
| 17 | `create_meeting_note` | **write** | `id: String` (required), `text: String` (required) | `{ok, meetingId, appended, folder}` |

**12 read + 5 write.** The `runTool` dispatcher is a flat `switch` at line 1419.

**Critical divergence from in-app chat:** `PeopleChatTools.swift` exposes `attach_note_to_person` (line 102–126) — not in MCP. `ActionItemChatTools` exposes `get_overview` and `list_projects` — not in MCP. Claude Desktop is a degraded surface compared to in-app chat for relationship work.

---

## 3. People/relationship data NOT exposed via MCP

### 3.1 Encounter records — completely absent from every tool

`Encounter` (`Sources/MeetingScribe/People/Encounter.swift:7`) carries: `personID`, `eventName`, `date`, `location`, `notes`, `meetingID`, `voiceNoteID`, `eventTagID`. Stored at `<storageDir>/encounters/<id>.json`. **Zero MCP tools read this data.** `get_person` returns only `memories` and `relationships` — encounter history is invisible to Claude Desktop.

`VaultKit/SharedModels.swift` has `PersonMemoryDTO` (line 164) and `PersonRelationshipDTO` (line 175) but **no `EncounterDTO`**. This is the prerequisite missing type for any encounter tool.

PeopleStore computes encounter counts per person (`PeopleStore.swift:52–55`, `encounterCountIndex`) and exposes `encounters(for:)` at line 634. The data structure is solid; only the DTO and MCP reader are missing.

### 3.2 `attachedNotes` — written by in-app chat, invisible to MCP

`AttachedNote` (`Person.swift:26`) is the durable coaching-artifact type: `title`, `body`, `kind`, `createdAt`. The in-app `PeopleChatTools.attachNoteToPerson` (line 340) writes them via `PeopleStore.addAttachedNote`. `PersonDTO` (`SharedModels.swift:186–211`) has **no `attachedNotes` field** — they are stripped when the MCP reads `person.json`. Claude Desktop cannot reference prior session analyses.

`tool_addPerson` at line 1308 does write `"attachedNotes": []` into new person records, confirming the field exists on disk but is never read back.

### 3.3 `checkIn` cadence — not modeled anywhere

`ReconnectView` (`SuggestedPeopleView.swift:95–102`) computes an inferred cadence from encounter gap medians. There is no stored `checkIn` field on `Person` or in `person.json` — the cadence is always recomputed. Claude cannot read a user-set reminder schedule, and there is no MCP write path to set one.

### 3.4 `relationshipType` — freeform label only, no semantic category

`Relationship.label` (`Person.swift:57`) is `String` — "spouse", "manager", "kid", etc. There is no structured enum or type field on the `Person` record itself. `get_person` returns `relationships` as `[{label, toPersonID, toDisplayName}]` (line 1086–1093). Claude cannot select a coaching framework (Gottman vs. attachment vs. NVC) without guessing from freeform text.

### 3.5 `birthday` — decoded but silently dropped in tool response

`PersonDTO.birthday` is correctly decoded (`SharedModels.swift:202`). `tool_getPerson` builds its response dict at line 1094–1112. **`birthday` IS included** at line 1106: `"birthday": .string(p.birthday.map(iso) ?? "")`. This is actually correct — the AUDIT_REPORT_2026-05-30 (P5-mcp-ai.md line 154) flags it as missing, but on re-reading `main.swift:1106` it is present. No fix needed here; update the P5 finding.

### 3.6 `tagIDs` — raw UUIDs, no resolved names

`get_person` returns `meetingMentionIDs` (UUID strings) but not resolved tag names. `list_people` and `get_person` do not return human-readable People tag names. The in-app `PeopleChatTools.getPerson` resolves them via `PeopleTagStore.shared.tag(by:)` (line 272). The MCP server has no `PeopleTagStore` equivalent — it would need to read `people-tags.json` (if it exists) or use the meeting `tags.json` infrastructure.

### 3.7 `encounterCount` — implied by `lastInteractionAt` but not explicit

`list_people` returns `memoryCount` and `meetingMentionCount` but not `encounterCount`. An encounter count in `list_people` would let Claude distinguish "has 12 logged encounters" from "imported contact with zero encounters" without a second tool call.

---

## 4. Existing plan items — endorsements

Through the MCP server engineering lens, three items from the existing plans matter most:

- **ARCH-3 god-file decomposition (MASTER_PLAN_V3.md):** `main.swift` at 1526 lines is the right next decomposition target after `PersonDetailView` and `PeopleStore`. Endorsing — and specifying the file split below.
- **Write-capable MCP (already done):** The raw-JSON patch pattern (`loadActionItemsRaw`/`writeActionItemsRaw`, `writePersonEnvelope`) is excellent — zero DTO-roundtrip risk, existing records never touched. This pattern should be used verbatim for all new write tools.
- **"Stay in touch" nudges:** The cadence logic already exists in `ReconnectView`. Porting it server-side (E3-6 below) is a small lift.

---

## 5. NET-NEW recommendations

### E3-1 — `EncounterDTO` in VaultKit and `get_person_encounters` read tool
**S effort.**

Add to `VaultKit/SharedModels.swift`:
```swift
public struct EncounterDTO: Codable, Sendable {
    public let id: String
    public let personID: String
    public let eventName: String
    public let date: Date
    public let location: String?
    public let notes: String
    public let meetingID: String?
    public let voiceNoteID: String?
    public let createdAt: Date
}
```

Add to MCP server (new `MCPPeople.swift` — see E3-10):
```swift
// Tool: get_person_encounters
// args: id (person, tolerant), limit: Int = 50
// reads: <storageDir>/encounters/<uuid>.json filtered by personID
func loadEncountersForPerson(_ personID: String, limit: Int) -> [EncounterDTO]
```

The `encounters/` directory layout (`PeopleStore.swift:270`) is already on disk. Disk scan is one `contentsOfDirectory` + filter by `personID` field in each JSON. No in-memory store needed; MCP is stateless.

**Why:** Encounter history is the primary behavioral signal for relationship health coaching. Without it, Claude is reasoning from `lastInteractionAt` alone — a single timestamp instead of a time series.

---

### E3-2 — `log_encounter` write tool
**S–M effort.**

```
Tool: log_encounter
Params: id (person, required), event_name (required), date (optional, default now),
        location (optional), notes (optional), meeting_id (optional)
Returns: {ok, encounterId, personId, eventName, date}
```

Implementation mirrors `tool_addMemory` but writes to `<storageDir>/encounters/<newUUID>.json` and also patches `person.json`'s `lastInteractionAt` field if the encounter date is more recent. The `writePersonEnvelope` pattern handles the patch. Post `signalVaultChanged()`.

No DTO round-trip: write the encounter JSON directly via `JSONSerialization`. The encounter file shape is flat and simple.

**Why:** Logging a coffee chat, a phone call, a dinner — this is the highest-value people-data input the app can receive. Zero MCP path for it today.

---

### E3-3 — `attach_note_to_person` ported to MCP server
**S effort.** Already fully implemented in `PeopleChatTools.swift:340–369`. Port to `main.swift` (or the new `MCPPeople.swift`):

```
Tool: attach_note_to_person
Params: id (person, required), title (required), body (required), kind (default "custom")
Returns: {ok, personId, noteId, title, kind, createdAt}
```

Implementation: raw-JSON patch on `person.json` — append to `attachedNotes` array (same pattern as `tool_addMemory` appending to `memories`). No `PeopleStore` reference needed; the MCP is stateless.

**Why:** Every coaching session that saves an analysis via the in-app chat is invisible to Claude Desktop on the next open. Porting this one tool makes coaching sessions cumulative across both surfaces.

---

### E3-4 — `update_person` write tool (identity field patch)
**S–M effort.**

```
Tool: update_person
Params: id (person, required), display_name?, company?, role?, bio?, birthday?,
        relationship_type? (partner/family/close_friend/friend/colleague/professional)
Returns: {ok, personId, updated: [String]}
```

Implementation: raw-JSON patch — read `person.json` via `JSONSerialization`, mutate only the specified keys, write back via `writePersonEnvelope`. Same approach as `tool_updateActionItem`. Does NOT touch memories, relationships, encounters, or attachedNotes — those have dedicated tools.

**Critical use case:** Claude discovers from a conversation that someone changed jobs, got engaged, or moved. Today it can `add_memory` ("got engaged to Alex") but cannot correct the `company` or `role` field, and cannot set a `relationship_type` that will drive future coaching framework selection. This tool closes that gap.

---

### E3-5 — `get_people_needing_attention` proactive read tool
**S effort.** Pure computation over existing data.

```
Tool: get_people_needing_attention
Params: limit: Int = 10
Returns: [{personId, displayName, daysSinceContact, personalCadenceDays,
           overdueByDays, lastInteractionAt, encounterCount}]
```

Implementation: port the cadence logic from `ReconnectView.cadenceSeconds(for:)` (`SuggestedPeopleView.swift:95–102`) to the MCP server. For each person with a `lastInteractionAt`, compute inferred cadence from encounter gap median (requires E3-1 to be most accurate; degrades to 30-day default without encounters). Sort by `overdueByDays` descending.

**Why:** This single tool is what makes Claude Desktop proactive rather than reactive. The first thing Claude should do in a new session is call this tool and open with "Two people are overdue: your sister (42 days) and Horst (18 days)." Currently impossible.

---

### E3-6 — `get_relationship_health` composite read tool
**M effort.**

```
Tool: get_relationship_health
Params: id (person, required)
Returns: {
  personId, displayName, relationshipType,
  daysSinceLastInteraction, daysSinceLastEncounter,
  messages: {last30, last90, total},
  encounters: {last30, last90, total},
  overdueByDays, personalCadenceDays,
  birthdayCountdown: Int?,         // days until next birthday, nil if not set
  recentMemories: [{text, occurredOn}],  // last 3
  attachedNoteCount: Int,
  healthSignals: [{signal: String, severity: "ok"|"warn"|"alert"}]
}
```

`healthSignals` is computed server-side: e.g. `{signal: "No contact in 45 days", severity: "alert"}`, `{signal: "Birthday in 8 days", severity: "warn"}`, `{signal: "Encounter cadence healthy", severity: "ok"}`. This lets small local models (qwen2.5:7b, llama) coach effectively without multi-step tool chains — they just read one structured object.

Requires E3-1 (`get_person_encounters`) data to be most useful but gracefully degrades: `daysSinceLastEncounter` returns null if no encounters are stored.

**Why this composite tool is essential:** The current flow to assess relationship health requires: `get_person` → `get_person_messages` → `get_person_encounters` (once built) → date arithmetic → framework selection. Small models reliably fail this chain. A single tool with server-computed signals makes coaching accurate even with weaker models.

---

### E3-7 — `set_checkin_reminder` write tool
**M effort** (schema change required).

```
Tool: set_checkin_reminder
Params: id (person, required), cadence_days (required, 1–365),
        remind_on (optional, ISO8601 or yyyy-MM-dd — defaults to now + cadence_days),
        note (optional)
Returns: {ok, personId, cadenceDays, remindOn}
```

Schema change: add optional `checkIn` object to `person.json`:
```json
"checkIn": {
  "cadenceDays": 30,
  "remindOn": "2026-07-02T00:00:00Z",
  "note": "Monthly check-in — ask about the new role"
}
```

The app reads `checkIn.remindOn` on next open and schedules a local notification via the existing `NotificationManager` (`NotificationManager.swift:159`). The MCP just writes the JSON; the app handles scheduling.

**MCP implementation:** read `person.json` raw, set/replace `checkIn` key, write via `writePersonEnvelope`. No DTO change needed (the MCP uses raw JSON for writes).

**Why:** "Set a monthly reminder to call my sister" is the most requested coaching action in similar apps. Today the user has to do it manually in the app. Claude can compute the right cadence from encounter history and write it in one tool call.

---

### E3-8 — `update_relationship` write tool (add/update/remove a directed relationship)
**S effort.**

```
Tool: update_relationship
Params: id (person A, required), to_person_id (person B, required),
        label (required), action ("add"|"remove", default "add")
Returns: {ok, personId, toPersonId, label, action}
```

Raw-JSON patch on person A's `relationships` array (append or filter out). Bidirectional mirror (also patch person B) is optional for V1 — the app already mirrors on next load.

**Why:** Claude can infer relationships from conversation ("you mentioned your manager Priya"). Currently no MCP path to record that.

---

### E3-9 — `search_vault` unified FTS tool
**M effort.**

```
Tool: search_vault
Params: query (required), kinds: [String]? (meetings/people/voice_notes/action_items),
        limit: Int = 20
Returns: [{entityID, entityKind, title, dateEpoch, snippet}]
```

The FTS5 `searchAll()` method already exists in `SecondBrainDB` (`PeopleStore.swift:192`). The MCP needs direct SQLite access to `secondbrain.db` (at `~/Library/Application Support/MeetingScribe/secondbrain.db`). The MCP already opens `chat.db` read-only via SQLite3 (line 464) — the same pattern applies.

**Why:** Today Claude must call `list_meetings` + `list_people` + `list_action_items` separately and scan all results for relevance. A single FTS5 search call returning ranked results across all entity types is faster, more accurate, and essential for "find everything about the Stripe deal" queries.

---

### E3-10 — Decompose `main.swift` into 5 focused files
**M effort** (mechanical, low risk if done carefully).

Current: 1526-line monolith with five distinct concerns.

Proposed split:

| File | Lines (est.) | Contents |
|------|-------------|----------|
| `main.swift` | ~120 | JSON-RPC loop only: `handle(line:)`, `writeResponse`, `jsonContentResult`, `serverInfo`, main loop |
| `MCPStorage.swift` | ~200 | `storageDir`, `resolveInsideVault`, `loadIndex`, `allMeetings`, `scanDiskForMeetings`, `readMeetingJSON`, `directoryForMeeting`, `meeting(byID:)`, `quickNoteDirectories`, `readQuickNote`, `directoryForQuickNote`, `loadTags`, `tagNames`, `readText`, `iso`, `isoNow`, `normalizeISO8601` |
| `MCPPeople.swift` | ~250 | `peopleRoot`, `loadAllPeople`, `person(byID:)`, `resolvePerson`, `personMatches`, `directoryForPerson`, `personSlug`, `writePersonEnvelope`, `signalVaultChanged`, `loadEncountersForPerson` (E3-1), all people tool implementations |
| `MCPMessages.swift` | ~250 | `MessageStats`, `MessageSnippet`, `MessageAnalysisError`, `chatDBURL`, `normalizePhone`, `normalizeEmail`, `appleDateToSwift`, `analyzeMessages`, `extractTextFromAttributedBody`, `indexOfBytes` |
| `MCPTools.swift` | ~600 | `toolList` definitions, all `tool_*` functions for meetings/action items/write tools, `normalizeStatus`, `normalizePriority`, `loadActionItemsFromDisk`, `loadActionItemsRaw`, `writeActionItemsRaw`, `actionItemsURL`, `runTool` dispatcher |

The JSON-RPC loop and storage resolution are the most stable. Tools change most often. This split means adding a new tool touches only `MCPTools.swift` and `MCPPeople.swift`.

**Implementation path:** Add `Sources/MeetingScribeMCP/` files, move code with no logic changes, update `Package.swift` if needed (SPM picks up all `.swift` files in the target directory automatically — no change needed). Build-verify with `swift build -c release` before pushing.

---

### E3-11 — Add `encounterCount` to `list_people` response
**S effort (one-line addition).**

`list_people` at line 1051 already iterates `PersonDTO` objects. Add `encounterCount` by scanning `<storageDir>/encounters/` once per `list_people` call and building a count index. Or cache it: read a `_encounter-counts.json` sidecar (written by the app's PeopleStore). Simpler interim: add a `encounterCount` field populated by counting encounter files matching the person ID.

For V1: skip the per-call scan and just add `encounterCount` to `get_person` response by counting encounter files for that specific person. O(k) where k = number of encounter files.

---

### E3-12 — `resolve_person` disambiguation tool
**S effort.**

```
Tool: resolve_person
Params: query (required — name, email, phone, or partial name)
Returns: {matched: [{id, displayName, company, role, matchType}], ambiguous: Bool}
```

The `resolvePerson` function at line 364 already handles the resolution logic. Exposing it as a standalone tool lets Claude explicitly resolve ambiguous names before calling other tools. Currently if `resolvePerson` finds 2 people with the name "Mike", it returns nil and the model gets an error. With this tool it can ask the user which Mike they mean.

---

## 6. Top 3 picks

**E3-3 (`attach_note_to_person` → MCP):** Highest impact per line of code — copy ~30 lines from `PeopleChatTools.swift:340–369`, adapt to the raw-JSON patch pattern. This single change makes coaching sessions persistent in Claude Desktop. Ship today.

**E3-1 + E3-2 (`get_person_encounters` + `log_encounter`):** The encounter data model is architecturally complete on disk. The only gaps are a DTO (`EncounterDTO` in `SharedModels.swift`) and two MCP tool functions. Together they unlock the temporal coaching layer — relationship health scoring, cadence inference, "when did we last see each other in person" — none of which is possible from `lastInteractionAt` alone.

**E3-10 (decompose `main.swift`):** The 1526-line monolith is actively resisting addition of new tools. Every new write tool needs to thread through the same file, creating merge conflicts and reviewer fatigue. The split is low-risk (mechanical, compile-verified), and is the prerequisite for the team to safely add E3-1 through E3-9 without stepping on each other.

---

## 7. Implementation notes and constraints

**Raw-JSON patch pattern is the right discipline.** `tool_addMemory` (`main.swift:1339–1387`) demonstrates: read file → `JSONSerialization.jsonObject` → recover payload (envelope or legacy) → mutate only the target key → `writePersonEnvelope`. This pattern must be followed for every new people write tool. Re-encoding through DTOs would silently strip `attachedNotes`, `photoRelativePaths`, `contactIdentifier`, and any future fields the DTO doesn't model.

**`PersonDTO` field gap:** `attachedNotes` and `photoRelativePaths` are in `Person.swift` (lines 123–124) but absent from `PersonDTO` in `SharedModels.swift`. For read tools that need to surface `attachedNotes`, the easiest path is to add `attachedNoteCount: Int` (not the full bodies) to `PersonDTO`, and add a separate `get_attached_notes` tool that reads the raw JSON. This keeps `get_person` response size bounded.

**Encounter directory not yet scanned by MCP:** `main.swift`'s `scanDiskForMeetings` scans `<storageDir>` top-level and two levels deep. `encounters/` is a flat directory of one-file-per-encounter. The reader for E3-1 is: `contentsOfDirectory(at: encountersRoot)` → filter `.json` → decode each as `EncounterDTO` → filter `personID == targetID`. This is O(totalEncounters), which is acceptable for the MCP's stateless per-call model.

**`secondbrain.db` for E3-9:** The SQLite database lives at `~/Library/Application Support/MeetingScribe/secondbrain.db`. The MCP server already opens `~/Library/Messages/chat.db` read-only (line 464). The same `sqlite3_open_v2(..., SQLITE_OPEN_READONLY, ...)` pattern applies. The FTS5 query from `SecondBrainDB.searchAll()` can be replicated with a single prepared statement — no need to import the full `SecondBrainDB` class.
