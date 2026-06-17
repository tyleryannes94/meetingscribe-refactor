# Shared Briefing — MeetingScribe Full-App v2 Audit (25 Agents)

You are one of 25 expert agents in a full-app v1→v2 upgrade audit for MeetingScribe. Read this entire file before doing anything else.

---

## The target — what MeetingScribe is

MeetingScribe is a macOS 14+ native app (SwiftUI + AppKit, ~301 Swift files, ~68,600 LOC, no third-party UI frameworks). It is a **second-brain meeting intelligence tool** that:

- Records meetings (system audio + mic) and transcribes them with local Whisper
- Generates AI summaries, extracts action items, and tracks decisions
- Maintains a relational People database (contacts, relationship tracking, iMessage analysis)
- Manages tasks/projects in an Initiative → Project → Task hierarchy
- Provides a local AI chat assistant (Ollama-powered) with tool-use over all app data
- Stores voice notes, weekly recaps, and exports to Notion/Obsidian/Google Drive
- Uses embeddings + SQLite FTS for semantic search across all content

**The owner's stated vision:** This is a **second brain** that leverages local LLM + structured data to ensure the user always has context for meetings, tasks, and relationships. The v2 upgrade should feel like a qualitative leap — more interconnected, more proactive, more AI-powered, while remaining fast and native macOS.

---

## Tech stack

- Swift 5.9+, SwiftUI + AppKit, Apple Silicon (M2 Mac mini)
- Local AI: Ollama (llama3, mistral, etc.) via `OllamaService.swift` + `OllamaChatClient.swift`
- Cloud AI (optional): `AnthropicClient.swift` for cloud-side analysis
- Storage: JSON files in `~/Library/Application Support/…` (schema-versioned via `SchemaEnvelope`)
- Embeddings: `EmbeddingService.swift` — local vectors for semantic search
- FTS: `SecondBrainDB` (SQLite + FTS5) in `PeopleStore.swift`
- Integrations: Notion API, Linear GraphQL, Google Drive, Obsidian vault, macOS Calendar, iMessage (via `MessagesAnalyzer`)
- Design system: `NDS` (all colors/fonts/spacing)
- MCP server: `MCPInstaller.swift` — exposes tools for external Claude usage

---

## Top-level navigation (5 tabs)

1. **Today** (`TodayView.swift`, 954 LOC) — home dashboard: upcoming meetings, overdue tasks widget, 1:1 section, chat rail, standup digest
2. **Meetings** (`MeetingsView.swift`, `UnifiedMeetingDetail.swift`) — full meeting library; transcript, summary, action items, decisions, pre-meeting brief
3. **People** (`PeopleListView.swift`, `PersonDetailView.swift` 2836 LOC, `PeopleStore.swift` 1468 LOC) — relationship CRM: encounters, memories, iMessage analysis, keep-in-touch board, people graph, AI suggestions
4. **Tasks** (`ActionItemsView.swift` + many extensions, `ActionItemStore.swift`) — hierarchy: Initiative → Project → Section → Task; Notion/Linear sync; triage inbox; calendar; insights
5. **Voice Notes** (`QuickNotesView.swift`) — standalone audio notes outside meetings

**Cross-cutting:**
- `ChatSession.swift` + tool-use (`ChatTools.swift`, `MeetingChatTools.swift`, `PeopleChatTools.swift`, `ActionItemChatTools.swift`) — AI assistant wired to all data
- `GlobalSearchView.swift` — ⌘K palette across all entities
- `WorkspaceRouter.swift` — centralized navigation (meetings, people, tasks, voice notes)
- `WorkspaceIndex.swift` — entity catalog for search/links
- `WebAPI.swift` / `HTTPServer.swift` — local HTTP server exposing data
- `WeeklyRecap.swift`, `StandupDigest.swift` — automated intelligence generation
- `PreMeetingBriefView.swift` — context surface before meetings

---

## Key cross-feature relationships that already exist (but are underexploited)

- Every meeting has attendees → People records (via `PersonResolver`)
- Action items have `meetingID` linking back to their source meeting
- Action items have `ownerPersonID` linking to a Person
- Meetings can be linked to Projects (`project.meetingIDs`)
- People have `encounters` (logs of interactions), `memories`, `talkingPoints`, `specialDates`
- People have AI suggestions from meeting extraction
- The AI chat has tool-use over ALL data: meetings, people, tasks, files, integrations
- `PreMeetingBriefView` shows prior meetings with attendees + open tasks before a call
- `WeeklyRecap` generates a markdown review from meetings + decisions + open tasks
- Embeddings exist but are not exposed to users in the UI

---

## REQUIRED READING — what is ALREADY PLANNED or IMPLEMENTED

Before auditing, read these files to understand what's been built/planned:

1. **Prior Tasks audit plan:** `/Users/tyleryannes/MeetingScribeRefactor/audit/master-plan.md`
2. **Prior Tasks build playbook:** `/Users/tyleryannes/MeetingScribeRefactor/audit/build-playbook.md`
3. **CLAUDE.md:** `/Users/tyleryannes/MeetingScribeRefactor/CLAUDE.md`
4. **Key source files for your focus area** (specified in your individual task prompt)

Then grep for in-code plan references:
```
grep -rn "Phase [0-9]\|TODO\|FIXME\|Phase [A-Z]\|audit\|planned\|C1-\|C2-\|C3-\|D1-\|D2-\|D3-\|P[0-9]-\|U[0-9]-\|BE-\|V5\|PR-" /Users/tyleryannes/MeetingScribeRefactor/Sources/MeetingScribe/ --include="*.swift" | grep -v ".build" | head -50
```

## What is ALREADY IMPLEMENTED (don't re-describe — go BEYOND)

- Tasks: full Phase 0–2 from prior audit (ViewModel, typed routes, context spaces, Today view, quick-add improvements, keyboard shortcuts)
- People: iMessage conversation analysis (6 presets), people graph (force-directed), keep-in-touch board, encounter log, memories, AI suggestions from meetings, duplicate detection, multi-import (contacts, calendar, Apple Notes, Gmail, Messages), tags
- Meetings: AI summary (type-aware), transcript, action items extraction, decisions tracking, pre-meeting brief, series recap, saved views, speaker diarization, export to Notion/Obsidian/Google Drive
- AI chat: tool-use over all data (meetings, people, tasks, files, integrations), persistent conversation, page-context awareness
- Second brain: embeddings, SQLite FTS, WorkspaceIndex entity catalog, backlinks, weekly recap, standup digest, global search

**Your job: find what's MISSING, UNDERCONNECTED, CLUNKY, or INVISIBLE. Propose NET-NEW features and connections the codebase doesn't have. Focus on: How does this become a coherent second brain rather than 5 siloed tabs?**

---

## Tyler's explicit goals for v2

1. **Interconnectedness** — features should feel woven together, not siloed tabs. Data should flow automatically between Meetings → People → Tasks → Today.
2. **Second brain quality** — the local LLM + structured data should make Tyler smarter about his relationships, commitments, and upcoming work. Proactive, not reactive.
3. **People feature overhaul** — currently hard to use, doesn't leverage existing data fully. Needs to be a world-class relationship intelligence tool.
4. **v1 → v2 qualitative leap** — not incremental polish. Everything can be redesigned as long as existing functionality is preserved or improved.
5. **Never cut features** — only add or improve.

---

## Guiding principles for this audit

- **Cite file:line** for every claim about current behavior
- **Interconnectedness > features in isolation** — a finding that bridges two tabs is worth 3x a single-tab improvement
- **Second-brain = proactive context delivery** — the app should tell Tyler things he didn't know to ask, not just respond to queries
- **Native macOS excellence** — keyboard-first, fast, no web anti-patterns
- **Local AI is a superpower** — free, private, always-on Ollama means proactive analysis has zero marginal cost
- **People is the graph** — every meeting, task, and note connects to people; People is the connective tissue of the whole second brain
- **Effort:** S (<1 day), M (1–3 days), L (3–7 days), XL (>1 week)

---

## Output format — TWO files per agent, then a short summary

### File 1: Your individual findings
Write to: `/Users/tyleryannes/MeetingScribeRefactor/audit-v2/findings/<YOUR_FILE>.md`

Structure:
```
# [Role/Sub-Lens] Findings — MeetingScribe v2 Audit

## Top friction points / gaps (file:line citations)
[What exists but is broken, clunky, underused, or underconnected]

## Existing items to endorse (from prior plan or codebase)
[Worth keeping / surfacing from existing code]

## NET-NEW recommendations
### [ID]-1: [Title]
- **What:** ...
- **Why (second-brain angle):** ...
- **Cross-feature connections:** [which other tabs/features this links]
- **Effort:** S/M/L/XL | **Impact:** High/Med/Low
- **Deps:** [none / other IDs]

## Top 3 picks
1. [ID-N] — one line why
```

### File 2: Compile into your GROUP doc
After ALL agents in your group have written their individual files, the **last agent in the group** (or any agent the group designates) reads all other agents' files in the group and writes a group compilation:

Write to: `/Users/tyleryannes/MeetingScribeRefactor/audit-v2/group-compilations/<GROUP>_compilation.md`

Structure:
```
# [Group Name] Group Compilation — MeetingScribe v2 Audit

## Convergence within this group (items 2+ agents raised independently)
## All net-new recommendations (deduplicated, with source agent IDs)
## Group's top 10 picks with rationale
## Highest-priority single recommendation from this group
```

### Summary to return
Return a ~120–150 word summary: your role, your top 3 net-new picks, your single highest-priority recommendation.

---

## Findings directory
Individual findings: `/Users/tyleryannes/MeetingScribeRefactor/audit-v2/findings/`
Group compilations: `/Users/tyleryannes/MeetingScribeRefactor/audit-v2/group-compilations/`
(Both directories already created)
