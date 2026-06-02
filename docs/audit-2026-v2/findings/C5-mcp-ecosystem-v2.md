# C5 — MCP Ecosystem & Personal Coaching Standard Analysis v2

**Lens:** Developer ecosystem researcher specializing in MCP. Sub-lens: What new relationship/personal context MCP servers exist in 2026? What is the standard for personal coaching MCPs now?

---

## 1. Full ecosystem audit through this lens

### State of the ecosystem (June 2026)

As of June 2, 2026, Glama's registry lists **29,909 MCP servers** — up from ~10,000 a year ago. The category breakdown is instructive:

- Knowledge & Memory: 1,616 servers (the largest "personal context" category)
- CRM category: 66 servers (search result confirmed)
- Prompts capability: 2,873 servers
- Local-only hosting: 7,410 servers

Sources: https://glama.ai/mcp/servers (registry stats, accessed 2026-06-02), https://glama.ai/mcp/servers?attributes=category%3Aknowledge-and-memory

### What personal CRM / relationship MCP servers currently exist

A targeted search for "personal crm coach relationship contacts" on Glama surfaced the meaningful competitors:

**1. CRM MCP Server (nxt3d/mcp-crm)**  
URL: https://glama.ai/mcp/servers/nxt3d/mcp-crm  
TypeScript + SQLite, 18 tools covering contacts, interaction history (call/email/meeting/note/task), todos, and CSV export. No relationship types, no coaching, no cadence logic, no birthday tracking. Oriented toward professional sales-style CRM. **Maintenance grade: C. Quality: untested.** MeetingScribe is already more sophisticated in every dimension — but this server is indexed while MeetingScribe is not.

**2. Coach AI (94aharris/coach-ai)**  
URL: https://glama.ai/mcp/servers/94aharris/coach-ai  
Python + SQLite. ADHD productivity coaching: task management, goal tracking, user fact storage, a `get_recommendation()` tool that reads from persistent context. No people graph, no relationship types, no encounter history, no cadence system. Roadmap items include habit tracking and weekly review prompts. The `add_user_fact` / `get_user_context` pattern for persistent coaching context is worth noting — it is the closest functional analog to MeetingScribe's `add_memory`. **License: F (missing). Maintenance: C.** Small community presence but directly validates the coaching MCP use case.

**3. Personal Context MCP Server (matipojo/personal-context-mcp)**  
URL: https://glama.ai/mcp/servers/matipojo/personal-context-mcp  
Topic-based personal information manager (tasks, meetings, contacts) with AES-256 encryption and OTP auth. Security-first positioning but no coaching capability. **License: F.**

**4. macOS Contacts MCP (jcontini/macos-contacts-mcp)**  
URL: https://glama.ai/mcp/servers/jcontini/macos-contacts-mcp  
Wraps the macOS Contacts app. Search, view, add, update contacts. No memory, no coaching, no encounter history. Relevant because it establishes that native macOS contact access via MCP is a solved problem — MeetingScribe's `get_person_messages` (iMessage bridge) is a genuine differentiator over this.

**5. studiomeyer-crm**  
URL: https://glama.ai/mcp/servers/studiomeyer-io/studiomeyer-crm  
AI-native CRM, 33 tools, pipeline + leads + health scores + revenue analytics. Business CRM positioning. No personal relationship coaching.

**Key finding:** No MCP server in the 29,909-server ecosystem combines (a) relationship-typed people graph, (b) encounter history with cadence tracking, (c) AI coaching frameworks per relationship type, and (d) local-first privacy. MeetingScribe has a genuine gap to fill — but must be indexed to fill it. Glama shows it is not currently listed.

### MCP `prompts` capability — current usage patterns

The MCP 2025-03-26 spec (and the current 2025-06-18 spec) defines `prompts` as user-controlled slash-command templates that accept arguments and return structured `PromptMessage` arrays. Capabilities declaration:
```json
{ "capabilities": { "prompts": { "listChanged": true } } }
```

Source: https://modelcontextprotocol.io/specification/2025-03-26/server/prompts (also confirmed at https://modelcontextprotocol.io/docs/concepts/prompts)

Of the 29,909 servers, 2,873 declare the `prompts` capability. Source: https://glama.ai/mcp/servers (sidebar facet). Among the coaching/personal-context category, no server currently ships prompts designed around relationship coaching workflows. The `code_review` prompt in the official reference server (`modelcontextprotocol/servers`) is the canonical example format — a prompt takes `code` as an argument and returns a structured user message.

For coaching, the pattern would be:
- Prompt name: `weekly_relationship_brief` with argument `personId`
- Server resolves person, encounters, cadence, coaching framework
- Returns a multi-message prompt: a system preamble (Gottman/NVC/love-language framing) + a user message summarizing the relationship state + an assistant seed

No server in the current ecosystem does this. It is a genuine differentiator.

### Best practices for MCP tool descriptions in 2026

The MCP 2025-06-18 specification adds a `title` field (human-readable display name) separate from `name` (identifier) and `description` (LLM-facing). Source: https://modelcontextprotocol.io/specification/2025-06-18/server/tools.md

The spec also introduces `outputSchema` for typed structured responses. Top-quality servers on Glama (A-grade quality) share these description patterns:
1. **First sentence is actionable:** starts with a verb ("Get," "List," "Log," "Attach"), describes what the LLM should accomplish.
2. **Second sentence gives disambiguation context:** when to use this vs. similar tools.
3. **Parameter descriptions include example values or enumeration of accepted values**, not just type.
4. **No implementation details in descriptions** (the LLM does not need to know about SQLite or JSON files).

MeetingScribe's 6 Phase 4 tool descriptions (`main.swift:883–955`) already follow this pattern well. The weakest point is the `list_overdue_check_ins` description ("List all people with typed relationships (partner, family, friend) who are overdue") — it underspecifies the sort order and does not tell the LLM when to call this proactively.

### Privacy standards for sensitive personal data in MCP tools

No MCP server in the top search results for "personal crm relationship" addresses privacy explicitly at the protocol level. The pattern emerging from better-quality servers:
- Announce local-only data in the server `description` field in `mcp-registry.json` ("All data stays on your Mac — no cloud")
- Use `annotations` metadata in tool responses to mark intimate content with `audience: ["user"]` rather than `audience: ["assistant", "user"]`

The MCP 2025-03-26/2025-06-18 spec's `annotations` system (audience, priority, lastModified) provides a standardized mechanism for this that MeetingScribe does not yet use. Source: https://modelcontextprotocol.io/specification/2025-06-18/server/resources#annotations

---

## 2. Existing-plan items I rank highest (through ecosystem lens)

1. **C4-6 / Phase 4 item: Publish to mcpservers.org and Glama** — Zero code, immediate discoverability. At 29,909 indexed servers, MeetingScribe is invisible. This is a 30-minute task that unlocks organic discovery. The Glama Add Server form is at https://glama.ai/mcp/servers (top right). MeetingScribe has a complete `mcp-registry.json` — the submission artifact already exists.

2. **C4-1 / Phase 4: `resources/list` endpoint with relationship brief** — No server in the ecosystem currently exposes a proactive personal context resource. This is an unoccupied niche.

3. **E3 audit items (mcp-registry.json accuracy):** The existing plan notes that `get_coaching_context` description advertises a "health score" that is never returned (`main.swift:946` vs `main.swift:1718–1729`). The ecosystem standard is that description accuracy is a first-class quality signal (Glama's quality scoring grades on this). Fix description before publishing.

---

## 3. NET-NEW recommendations

### C5-1 — Declare `prompts` capability with 3 relationship coaching slash-commands

**What:** Implement MCP `prompts` capability in `main.swift` with 3 named prompts:
- `weekly_partner_brief(personId)` — Gottman-framed relationship summary
- `reconnect_coaching(personId)` — for people overdue for check-in, returns NVC/love-language framing
- `post_encounter_reflection(personId, encounterId)` — journaling scaffold after logging a difficult encounter

**Why:** 2,873 of 29,909 servers declare `prompts`. Zero declare coaching prompts for personal relationships. This is an unoccupied niche that maps directly to MeetingScribe's positioning. In Claude Desktop, prompts appear as `/` slash-commands — this is the highest-visibility surface in the UI.

**Implementation sketch:**
```json
// capabilities response
{ "capabilities": { "tools": {}, "prompts": { "listChanged": false } } }

// prompts/list response
{ "prompts": [
  { "name": "weekly_partner_brief", "title": "Weekly Partner Check-In",
    "description": "Gottman-framed summary of your relationship with a person",
    "arguments": [{ "name": "personId", "description": "Person UUID, name, or email", "required": true }] }
]}

// prompts/get response builds from live encounter data + RelationshipPromptLibrary
```

The server already has all the data (`loadEncounters`, `loadPerson`, `RelationshipCoachContent` equivalent via `get_coaching_context`). This is assembling existing data into a new protocol surface.

**User value:** "Weekly Partner Brief" appears in the Claude Desktop slash-command palette. User types `/w` → autocompletes to "Weekly Partner Brief" → types partner's name → gets a Gottman-framed briefing. Zero new app opens required.

**Effort:** M | **Impact:** High (differentiator, unoccupied niche) | **Deps:** Phase 3 coaching content (C3-1 / RelationshipCoachContent.swift)

---

### C5-2 — Add `outputSchema` to all 6 Phase 4 tool definitions

**What:** Add `outputSchema` JSON Schema to the 6 new Phase 4 tool definitions in `main.swift`. The 2025-06-18 spec defines `outputSchema` as an optional tool property that enables client-side structured validation.

**Why it matters:** Glama's quality scoring grades on this. Top-rated servers declare output schemas so Claude can parse responses deterministically rather than extracting from a text blob. For `get_coaching_context` specifically, a declared output schema would prevent Claude from hallucinating fields (e.g., `healthScore`) that the server does not return — closing the description-vs-implementation gap at E3-07 without requiring a description rewrite.

**Example for `get_coaching_context`:**
```json
"outputSchema": {
  "type": "object",
  "properties": {
    "relationshipType": { "type": "string" },
    "daysSinceLastContact": { "type": "integer" },
    "cadenceDays": { "type": "integer" },
    "overdueByDays": { "type": "integer" },
    "birthdayCountdown": { "type": ["integer", "null"] },
    "coachingFramework": { "type": "string" },
    "weeklyPrompt": { "type": ["string", "null"] }
  },
  "required": ["relationshipType", "daysSinceLastContact", "cadenceDays", "overdueByDays", "coachingFramework"]
}
```

**User value:** Claude parses responses correctly without prompt engineering; Glama quality grade improves from B to A; server becomes eligible for "A quality" badge which surfaces it higher in search.

**Effort:** S | **Impact:** Medium (quality/discoverability) | **Deps:** None — purely additive to existing schemas

---

### C5-3 — Add `title` field to all tool definitions (MCP 2025-06-18 spec addition)

**What:** The 2025-06-18 MCP specification adds a `title` field (human-readable display name) separate from `name`. In Claude Desktop and other MCP clients, `title` is what users see in the tool picker, not `name`. Currently MeetingScribe tools show machine-readable names like `list_overdue_check_ins` in the UI.

**Example:**
```json
{ "name": "list_overdue_check_ins", "title": "People Overdue for Check-In", "description": "..." }
{ "name": "get_coaching_context", "title": "Relationship Coaching Brief", "description": "..." }
```

**Why:** The spec was updated in June 2025. No review of other local-first personal apps found them adopting `title` yet — MeetingScribe can be an early mover. Effort is trivial; user-facing impact is significant for Claude Desktop users who see tool names in the UI.

**Effort:** S | **Impact:** Medium (UX polish, spec compliance) | **Deps:** None

---

### C5-4 — Use `annotations` to mark intimate encounter notes as `audience: ["user"]`

**What:** Add MCP 2025-03-26+ `annotations` to tool result content for encounter notes and coaching outputs, marking them `audience: ["user"]` rather than the default `audience: ["assistant", "user"]`.

**Why:** The spec's `audience` annotation signals to the client whether content is meant for the user to see vs. the assistant to process. Encounter notes about romantic partners or family conflicts should be presented to the user for reflection — not fed back into the assistant's reasoning as raw data. No personal CRM or coaching server in the ecosystem does this.

```json
// In tool result content for coaching analysis
{
  "type": "text",
  "text": "You and Sarah haven't connected in 18 days...",
  "annotations": { "audience": ["user"], "priority": 0.9 }
}
```

This is also the privacy differentiation story: "MeetingScribe's MCP server marks intimate relationship notes for user eyes only — not for model context injection." This becomes a marketing claim.

**Effort:** S (additive to existing tool result construction) | **Impact:** High (privacy differentiator, no competitor does this) | **Deps:** None

---

### C5-5 — Submit `mcp-registry.json` to Glama and GitHub MCP Registry

**What:** Submit the existing `mcp-registry.json` (already complete) to:
1. Glama Add Server: https://glama.ai/mcp/servers (Add Server button, top right)
2. GitHub MCP Registry (if public listing is available at time of submission)
3. mcp.so (secondary registry)

Also add `"category": "personal-context"` and `"capabilities": ["tools", "prompts"]` (after C5-1 is implemented) to `mcp-registry.json` to qualify for Glama's category facets.

**Why:** The current registry at Glama shows 29,909 servers. MeetingScribe is not among them. The `mcp-registry.json` artifact is complete. Every day without a listing is a distribution miss. The `nxt3d/mcp-crm` server (no coaching, no relationship types, grade C maintenance) is indexed — MeetingScribe is not.

**Effort:** S (30 minutes) | **Impact:** High (distribution unlock) | **Deps:** Fix description accuracy bugs (E3-07 in existing plan) before submitting

---

### C5-6 — Add `resources/list` endpoint returning a live "Relationship Brief" resource

**What:** Implement the MCP `resources` capability with a single resource: `relationship://brief` that returns a markdown-formatted relationship brief: people overdue for check-in, upcoming birthdays (next 7 days), and last 3 encounter entries across all people. The resource is available at session start without any tool call.

**Why:** The official MCP `resources` feature is declared by 3,122 of 29,909 servers, but no personal coaching server uses it for proactive context injection. The pattern: when Claude Desktop connects to MeetingScribe, the resource appears in the context panel and Claude can read it before the user types anything. This enables Claude to open with: "Good morning — three people need attention: your sister (42 days), Marcus (18 days), and Priya (14 days). Priya's birthday is in 6 days."

Source for capability count: https://glama.ai/mcp/servers (Resources: 3,122 facet)

**Implementation:** New `MCPResources.swift` file (~60 lines). The data already exists via `loadAllPeople()` + `loadEncounters`. The resource content is a markdown string formatted for scan-reading.

**Effort:** M | **Impact:** High (unoccupied niche, session-start habit trigger) | **Deps:** Phase 1 (RelationshipPath enum), Phase 4 encounter tools

---

### C5-7 — Add `"personal-coaching"` as a new mcp-registry.json tag and category claim

**What:** Update `mcp-registry.json` tags from `["meetings", "transcription", "productivity", "people", "relationships", "local-first", "second-brain", "contacts", "macos"]` to add `"personal-coaching"`, `"relationship-intelligence"`, and `"second-brain"` (already present).

Also update the `description` field in `mcp-registry.json` from its current text to surface the coaching differentiation more prominently:

Current: "Local-first meeting intelligence with relationship coaching. Exposes 23 tools to Claude: read and write meetings, transcripts, summaries, action items, people/contacts, encounter history, relationship health, and coaching context. All data stays on your Mac — no cloud, no API keys."

Proposed: "The only local-first personal coaching MCP. Read and write meetings, transcripts, summaries, action items, and a full relationship graph — partner, family, friends, colleagues — with check-in cadence, encounter history, Gottman/NVC/love-language coaching prompts, and birthday reminders. All data stays on your Mac. No cloud, no API keys."

**Why:** The current description buries the coaching angle ("relationship coaching" appears once as a subordinate clause). Glama's search is keyword-driven. The word "coaching" appears in the description of the competing Coach AI server — MeetingScribe should own that keyword in its own description.

**Effort:** S (5 minutes) | **Impact:** Medium (discoverability) | **Deps:** C5-5 (submit to registry)

---

### C5-8 — Fix `get_coaching_context` framework coverage to eliminate 43% fallback rate

**What:** Add specific framework text for the three relationship types that currently fall through to the "Active listening and consistent follow-through" fallback: `"friend"`, `"colleague"`, and `"acquaintance"`. This is a gap confirmed at `main.swift:1716–1720` (per E3 audit):

```swift
// friend
"Reciprocal vulnerability and shared experience. Ask what matters to them, share what matters to you. Small gestures of remembrance (their pet's name, their project deadline) compound into felt closeness."

// colleague  
"Professional respect and reliable follow-through. Note commitments and complete them. Acknowledge their work publicly when warranted."

// acquaintance
"Warmth without pressure. Occasional light touch (sharing an article, noting a shared interest) signals regard without demanding reciprocity."
```

**Why this is ecosystem-significant:** The `get_coaching_context` tool is MeetingScribe's strongest differentiator in the ecosystem. No competitor offers per-relationship-type coaching guidance. But 43% of typed relationships return a generic fallback — meaning if a user asks Claude to coach them on a colleague or casual friend, they get worse guidance than they'd get by just asking Claude without any MCP context. This inverts the value proposition for nearly half of use cases.

This bug was identified in E3-07 (existing plan, Critical gaps #8 in BRIEFING-V2). This entry endorses it as a high-priority fix through the ecosystem lens: it must be fixed before the server is submitted to registries.

**Effort:** S (30 lines) | **Impact:** High (quality, no competitor covers this) | **Deps:** None

---

### C5-9 — Create a `CLAUDE.md` guidance file for Claude Desktop users

**What:** Add a `CLAUDE.md` in the MeetingScribe repo root (separate from the developer `CLAUDE.md` used by Claude Code) that is the MCP server's usage guide for Claude Desktop users. This file would:
- List all 23 tools with a one-line description of when to invoke each
- Include example prompts: "Ask me: 'Who do I need to check in with?'" or "Try: 'Give me a weekly brief on my partner'"
- Document the `prompts` slash commands once C5-1 is implemented

**Why:** Coach AI (94aharris/coach-ai) ships a `CLAUDE_DESKTOP_GUIDE.md` and `EXAMPLES.md`. These files are indexed by Glama and increase discoverability. More importantly, they reduce the activation energy for new users — without a guide, a user who installs MeetingScribe's MCP server has no idea which of 23 tools to invoke or when. This is the "onboarding inside the tool" pattern.

**Effort:** S (1-2 hours writing) | **Impact:** Medium (activation, discoverability) | **Deps:** None

---

### C5-10 — Add `announce_capability` resource for privacy disclosure at session start

**What:** A new read-only resource `relationship://privacy-notice` (returned alongside `relationship://brief` in C5-6) that states MeetingScribe's data handling: all data local, no cloud transmission, encounter notes marked `audience: ["user"]` via annotations.

**Why:** Privacy-sensitive personal data in MCP tools has no standard yet. The vacuum is an opportunity. Being the first MCP server to ship a machine-readable privacy notice as a resource positions MeetingScribe as the trust leader in personal-context MCPs — relevant as the category grows. Anthropic's MCP documentation explicitly calls out that clients should help users understand what tools are exposed; this resource makes the promise legible to both users and MCP clients.

**Effort:** S | **Impact:** Medium (trust differentiation, first-mover) | **Deps:** C5-6 (resources capability)

---

## 4. Top 3 picks + single highest-priority recommendation

### Top 3

1. **C5-1** (Declare `prompts` capability with 3 coaching slash-commands) — occupies an uncontested niche in a 29,909-server ecosystem, creates the highest-visibility surface in Claude Desktop (slash commands), and integrates directly with the coaching content work already planned in Phase 3.

2. **C5-5** (Submit to Glama and GitHub MCP Registry) — zero code, 30 minutes of work, unlocks organic discovery from day one. The competing `nxt3d/mcp-crm` (no coaching, C-grade maintenance) is indexed. MeetingScribe is not.

3. **C5-8** (Fix `get_coaching_context` framework fallback from 43% to 0%) — must ship before registry submission. A tool that returns "Active listening and consistent follow-through" for 43% of relationship types is not a coaching tool, it is a data lookup with a coaching label. Fix this before anyone evaluates the server.

### Single highest-priority recommendation

**C5-8** — Fix the `get_coaching_context` framework fallback rate.

This is the highest-priority item because it blocks everything else. Submit the server to Glama with a 43% fallback rate and the first critical review kills the listing's momentum. It costs 30 lines of Swift and can be done in an afternoon. It is also the minimal change that makes the server's central claim ("relationship coaching MCP") true for all seven relationship types rather than four.

The dependency chain is: fix C5-8 → then fix description accuracy (E3-07, `main.swift:946`) → then update `mcp-registry.json` (C5-7) → then submit to registries (C5-5) → then build `prompts` capability (C5-1). The single highest-priority item unblocks the entire distribution sequence.

---

## 5. Evidence citations

| Claim | Source |
|---|---|
| 29,909 MCP servers in Glama registry (June 2, 2026) | https://glama.ai/mcp/servers |
| Knowledge & Memory: 1,616 servers | https://glama.ai/mcp/servers?attributes=category%3Aknowledge-and-memory |
| Prompts capability: 2,873 servers | https://glama.ai/mcp/servers (sidebar facet) |
| Resources capability: 3,122 servers | https://glama.ai/mcp/servers (sidebar facet) |
| nxt3d/mcp-crm: 18 tools, no coaching | https://glama.ai/mcp/servers/nxt3d/mcp-crm |
| Coach AI: ADHD productivity MCP, no people graph | https://glama.ai/mcp/servers/94aharris/coach-ai |
| MCP `prompts` spec (2025-03-26) | https://modelcontextprotocol.io/specification/2025-03-26/server/prompts |
| MCP `tools` spec with `outputSchema` and `title` (2025-06-18) | https://modelcontextprotocol.io/specification/2025-06-18/server/tools.md |
| MCP `prompts` spec (2025-06-18 — adds `title` field) | https://modelcontextprotocol.io/docs/concepts/prompts |
| Annotations (`audience`, `priority`) on resources/prompts | https://modelcontextprotocol.io/specification/2025-06-18/server/resources#annotations |
| `get_coaching_context` 43% fallback rate | `main.swift:1716–1720` (also BRIEFING-V2 §Critical gaps #8) |
| `get_coaching_context` description advertises `healthScore` not returned | `main.swift:946` vs `main.swift:1718–1729` (per E3 audit) |
| `list_encounters` description advertises `mood` not returned | `main.swift:884` vs `main.swift:1533–1540` (per E3 audit) |
| mcp-registry.json current state (23 tools, tags) | `/MeetingScribeRefactor/mcp-registry.json` |
| GitHub MCP Registry (official reference servers) | https://github.com/modelcontextprotocol/servers |
