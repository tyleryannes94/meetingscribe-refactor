# Second Brain / Knowledge Graph Tools Findings — MeetingScribe v2 Audit

**Agent:** C4 — Second Brain / Knowledge Graph (Roam Research, Obsidian, Logseq)

---

## Top friction points / gaps (file:line citations)

### 1. Backlinks are meeting-only and scan-based, not a living graph
`WorkspaceIndex.swift:61–93` — `backlinks(toMeetingID:)` detects backlinks by grepping markdown files on disk for `meetingscribe://` URLs. This is correct but severely limited: only meetings and projects are scanned; people, action items, and voice notes cannot be backlink sources or targets. A knowledge graph tool (Roam, Obsidian, Logseq) treats every entity — people, blocks, dates — as fully bidirectional link participants. MeetingScribe treats backlinks as an afterthought visible only in `UnifiedMeetingDetail.swift:367–376`.

### 2. No block-level references — only document-level links
Roam's fundamental unit is the *block* (a single bullet), not a page. Every block has a UUID and can be embedded or referenced anywhere. MeetingScribe's markdown export (`ObsidianExporter.swift:85–139`) writes meeting notes as flat markdown sections — there is no way to reference a single decision, action item, or transcript line from another meeting. Decisions and insights can't be "transcluded."

### 3. ObsidianExporter produces output-only, one-directional files
`ObsidianExporter.swift:12–188` writes Obsidian-flavored markdown with `[[wikilinks]]` for attendees, but there is zero round-trip awareness. If a user edits the vault file, those edits never come back into MeetingScribe. More critically, `[[wikilinks]]` resolve to attendee names but those names are not linked to MeetingScribe's own Person records — the People tab and the Obsidian export are entirely disconnected.

### 4. No daily-note rhythm — Today view is a dashboard, not a journal
Roam Research and Logseq are **journal-first**: every day gets an auto-created page, and all captures default to today's entry, with date backlinks making "what happened on June 16" trivially answerable. MeetingScribe's Today view (`TodayView.swift`, 954 LOC) is a dashboard of upcoming meetings and tasks. It has no journal/note capture mode. Voice notes exist but are a separate tab with no date-graph connection.

### 5. Embeddings exist but are invisible and uncrossed
`EmbeddingService.swift` generates vectors for content. `PeopleStore.shared.relatedMeetingIDs(toID:)` (`UnifiedMeetingDetail.swift:373`) exposes semantically similar meetings — but only in meeting detail, only for meetings, and only as a small "Related" row. There is no graph-view visualization, no cross-entity similarity (e.g., "voice notes related to this meeting"), and no query surface for users to navigate by semantic proximity.

### 6. No query language / saved views over structured fields
Obsidian's Dataview plugin and Logseq's query blocks allow users to write `WHERE status = "open" AND tags INCLUDE "client-x"` queries that render as live tables. MeetingScribe has saved meeting views (`SavedViews`) but these are filter presets, not a composable query language. The structured data (attendees, decisions, meeting type, action-item owners, due dates) is never queryable in an ad-hoc way.

### 7. No visual graph/canvas — People graph is people-only
The People graph is a force-directed visualization of person-to-person relationships. It has no meetings, tasks, or voice notes as nodes, and it is not navigable as a knowledge map. Obsidian Canvas allows spatial arrangement of any entity type with freeform connectors. MeetingScribe has no equivalent multi-entity visual surface.

---

## Existing items to endorse (from prior plan or codebase)

- **WorkspaceIndex entity catalog** (`WorkspaceIndex.swift:11–49`) is the right architectural foundation for a knowledge graph — it already includes meetings, voice notes, projects, action items, and people as linkable entities. This is more structured than anything Roam or Obsidian has natively.
- **`#tag` search in `WorkspaceIndex.swift:111`** is a solid start at a query syntax. Extend it rather than replace it.
- **Embedding-based `relatedMeetingIDs`** (`UnifiedMeetingDetail.swift:373`) is the right idea — similarity-based discovery should be promoted to a first-class navigation pattern.
- **ObsidianExporter YAML frontmatter** (`ObsidianExporter.swift:100–112`) is well-structured and Obsidian-compatible. The foundation for richer metadata queries already exists.
- **C2-3** (referenced in `UnifiedMeetingDetail.swift:373`) is already planned — related meetings via embedding. This should be expanded to cross-entity similarity.

---

## NET-NEW recommendations

### C4-1: Block-Level References for Decisions and Action Items
- **What:** Assign every decision and every action item a stable `block://` URI (like `meetingscribe://block/<itemID>`). Allow `[[` mention of a specific decision or action item from any note, meeting notes section, or project body. When clicked, deep-link to the exact item in context. Show a backlinks panel per-decision ("this decision was referenced in 3 other meetings").
- **Why (second-brain angle):** Roam's superpower is that granular insights — not just documents — become linkable. A decision made in Q1 should be referenceable in Q3 review without copying text. MeetingScribe's structured data (typed decisions, typed action items) gives it a precision advantage: the "block" already has structured fields, not just freeform text.
- **Cross-feature connections:** Meetings ↔ Projects (link a decision to a project body); People (link a decision to its owner/accountable person); Tasks (link an action item block to a Project task).
- **Effort:** M | **Impact:** High
- **Deps:** None — builds on existing `WorkspaceLink` URL scheme

### C4-2: Daily Journal Layer in Today View
- **What:** Add a "Today's Journal" capture zone at the top of Today view — a persistent, auto-dated freeform text block (like Roam's daily page) that supports `[[entity]]` mentions. Each journal entry is saved as a `DailyNote` struct with a date key. The Today view shows journal entries for the last 7 days in collapsed sections. The journal automatically receives backlinks from all meetings, voice notes, and tasks that occurred that day (so "June 16" becomes a hub showing everything that happened). Weekly Recap reads from daily notes as additional signal.
- **Why (second-brain angle):** Logseq and Roam users capture everything into the day's page — the date becomes the universal organizing principle. MeetingScribe already knows what meetings happened each day; adding a freeform journal makes Today view the connective tissue of the whole brain, not just a task dashboard.
- **Cross-feature connections:** Today ↔ Meetings (meetings auto-link to their day's journal); Today ↔ People (mentions in journal create encounter logs); Today ↔ Tasks (tasks mentioned in journal are quick-captured); Today ↔ WeeklyRecap (journal text feeds the recap LLM context).
- **Effort:** M | **Impact:** High
- **Deps:** C4-1 (entity mention support helps but is not required for v1 of this)

### C4-3: Structured Query Views — Dataview for MeetingScribe
- **What:** Expose a composable query syntax (extending the existing `#tag` prefix in `WorkspaceIndex.swift:111`) to build saved views like: `@person:Alex type:1-on-1 has:open-actions` or `tag:client-acme date:last-30d`. These queries render as live tables/lists anywhere in the app (Today sidebar widget, Project body, PreMeetingBrief). Queries are saveable and nameable. The query engine runs over the in-memory WorkspaceIndex (already has all entities) plus structured fields on Meeting (attendees, type, tags, date), ActionItem (owner, due date, status), and Person (company, tags).
- **Why (second-brain angle):** Obsidian Dataview is one of its most-used plugins because unstructured notes can't be queried — but MeetingScribe has *structured* data (meeting type, attendee list, action-item status, person tags). A query like "show me all open commitments to Acme Corp from the last quarter" is trivially answerable with existing fields. This is the killer advantage over text-based PKM tools.
- **Cross-feature connections:** All five tabs — queries can surface cross-tab results; PreMeetingBrief (show query results for "past meetings with these attendees"); Tasks (query for overdue items by person); People (query for all meetings with a company).
- **Effort:** L | **Impact:** High
- **Deps:** None (WorkspaceIndex already provides entity catalog)

### C4-4: Multi-Entity Graph Canvas View
- **What:** A zoomable, force-directed graph canvas (like Obsidian Graph View but richer) showing all entity types as typed nodes: meetings (circles), people (hexagons), projects (squares), action items (diamonds), voice notes (triangles). Edges are typed: attended, owns, links-to, related-to (semantic similarity). User can filter by entity type, date range, tag, or person. Clicking a node opens a detail popover. Spatial layout is persistent (user can pin/arrange nodes). This replaces the people-only graph and becomes the true "second brain map."
- **Why (second-brain angle):** Obsidian's graph view is one of its most-loved features because it makes the knowledge structure visible. MeetingScribe already has richer semantic relationships than Obsidian (attendee lists, ownership, project membership) — the graph would show patterns like "Sarah is the hub connecting 4 projects and 12 meetings" that are invisible in list views.
- **Cross-feature connections:** People (replace people-only graph); Meetings (nodes in graph); Tasks/Projects (nodes in graph); embeddings (semantic similarity edges via C2-3).
- **Effort:** XL | **Impact:** High
- **Deps:** C4-3 (queries can drive graph filters); C2-3 (similarity edges)

### C4-5: Two-Way Obsidian Vault Sync (Read + Write)
- **What:** Instead of one-way export, implement a true vault watcher: when a meeting markdown file in the Obsidian vault is modified (FSEvents), parse the changes and sync them back into MeetingScribe notes. When a user creates a `[[PersonName]]` note in the vault, offer to create a Person record. When the vault's `action-items.md` section changes, sync completion status back to ActionItemStore. Use the existing `{slug}.md` path convention already established by `ObsidianExporter.writeMarkdownFile`.
- **Why (second-brain angle):** Obsidian users live in their vault. If MeetingScribe writes to the vault but can't read back, it becomes a one-way data sink rather than a true integration. True bidirectional sync makes MeetingScribe the "structured backend" to Obsidian's "freeform frontend."
- **Cross-feature connections:** Meetings (notes sync); Tasks (action item completion sync); People (person note creation).
- **Effort:** L | **Impact:** Med
- **Deps:** None

### C4-6: Semantic Backlinks Panel — Cross-Entity, Embedding-Powered
- **What:** Extend the current `backlinks(toMeetingID:)` (which only scans meeting and project markdown files) to a full cross-entity backlink engine: (a) explicit links (`meetingscribe://` URLs in any text field), (b) semantic neighbors via embeddings (top-5 similar entities across all types), (c) shared-attendee co-occurrence (meetings with overlapping people), (d) shared-decision co-occurrence (decisions that echo earlier ones via LLM diff). Show this as a unified "Connections" panel in Meeting detail, replacing the current separate "Backlinks" and "Related" rows.
- **Why (second-brain angle):** Roam's killer feature is that you discover connections you didn't manually make. The embedding + structured-data combination gives MeetingScribe an edge: it can surface "this decision echoes a commitment from 3 months ago" — something no text PKM can do without AI.
- **Cross-feature connections:** Meetings ↔ People ↔ Tasks ↔ Voice Notes (all entity types as connection sources); EmbeddingService (similarity); LLM (decision echo detection).
- **Effort:** M | **Impact:** High
- **Deps:** Embedding service (already exists); C4-1 (block URIs improve precision)

---

## Top 3 picks

1. **C4-3 — Structured Query Views** — MeetingScribe's typed, structured data is its decisive advantage over text PKM tools. A query language turns five siloed tabs into a single queryable knowledge base and requires no new data collection.
2. **C4-2 — Daily Journal Layer** — Adds Roam/Logseq's proven journal-first rhythm with zero disruption to existing features. Makes Today view the connective tissue of the whole brain and feeds WeeklyRecap with richer context.
3. **C4-6 — Semantic Backlinks Panel** — The existing embedding infrastructure is unused in the UI. Promoting it to a first-class "Connections" panel (cross-entity, AI-powered) is a high-leverage use of already-built infrastructure and creates the "surprise discovery" moment that makes second-brain tools feel magical.
