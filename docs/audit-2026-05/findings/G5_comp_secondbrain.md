# Competitive Analysis (G5) — AI Second-Brain / PKM

**Lens:** MeetingScribe captures meetings beautifully. But a second brain is judged on *recall and connection over time* — does last quarter's decision resurface when it's relevant? Can you ask your whole vault a question and get a cited answer? Does the graph connect meetings → people → topics → tasks, not just people → people? Measured against Mem.ai, Reflect, Tana, Notion AI, Capacities, Saga, and Amie, MeetingScribe is a best-in-class *capture* tool with a *retrieval* layer that's half-built and unwired.

## Full-app audit (through my lens)

**1. The unified FTS5 recall engine exists in code but nothing uses it.** `SecondBrainDB.swift:118-273` already defines exactly the V2 plan's `vault_content` + `vault_fts` external-content table across all five entity kinds, with the recency-boosted BM25 query (`SecondBrainDB.swift:269-273`, `bm25(vault_fts, 10,1,0.5) * (1 + 0.5*recency_decay/180d)`). This is the moat the V2 plan calls "the product." But the app's actual global search — `WorkspaceIndex.search()` (`WorkspaceIndex.swift:106-284`) — is a hand-rolled in-memory `contains()` scorer that walks `pastMeetings`, `quickNotes`, `actionItems`, and `PeopleStore.people` on every keystroke. `GlobalSearchView.recompute()` (`GlobalSearchView.swift:172-203`) calls `manager.search(q)`, never `vault_fts`. So the recency-ranked, tokenized, diacritic-folded FTS index ships in the binary, gets written by triggers, and is queried by *nobody*. Worse, the code comments (`WorkspaceIndex.swift:197-208`) record that the team *tried* routing People search through FTS5, hit a stale/mis-tokenized `search_index`, and **reverted to in-memory matching** — meaning the FTS path is not just unwired, it's distrusted.

**2. Search is lexical only — there is no semantic recall.** Grep for `embed|vector|cosine` across `Sources` returns zero hits. Every competitor's headline 2026 feature is the opposite: Mem's Deep Search surfaces "projected income" when you type "revenue forecasting" because it maps intent, not strings [Mem]; Reflect ships "similar notes"; Capacities is adding "semantic retrieval" and graph traversal to its AI [Capacities]. MeetingScribe can't find a meeting about pricing unless the literal token "pricing" appears. For a meeting vault — where the transcript says "we should bump the tier to $30" and the user later searches "price increase" — lexical-only recall fails exactly when it matters most.

**3. Backlinks are one-directional and link-only.** `WorkspaceIndex.backlinks(toMeetingID:)` (`:61-94`) does a detached scan of `notes.md`/`summary.md`/project bodies for a literal `meetingscribe://` URL. So backlinks exist *only* where the user manually pasted a deep-link — there is no automatic linking, no `[[wiki-link]]` autocomplete, no "this meeting mentions Acme → show on Acme's page." Reflect lets you select text and auto-add backlinks (cmd+J); Capacities and Tana treat bidirectional links as the substrate. MeetingScribe's "links" are inert unless hand-authored, which almost never happens.

**4. The knowledge graph is people-only.** `PeopleGraphViewModel.buildGraph` (`:38-75`) is genuinely good — force layout, BFS "find path between two people" (`:168-203`), edges weighted by shared meetings/tags. But nodes are *exclusively* `Person`. Meetings, projects, topics, and tags are not nodes. Capacities renders "your entire knowledge network as a living graph" of objects (people, projects, ideas) [Capacities]; Tana's supertag graph connects #meeting, #person, #project as first-class queryable nodes [Tana]. MeetingScribe has the rendering engine but feeds it one entity type.

**5. There is no daily note / temporal spine.** Grep for `daily.?note|on this day|year ago|resurfac|throwback` finds only `dismissSuggestion` ("won't resurface a dismissed person"). Daily notes are table-stakes for this category: Reflect auto-opens a dated note every morning ("after a month you see patterns"), Tana's #DailyNote builds a structured dashboard, Capacities makes one-note-per-day "the simplest way to build a knowledge habit" [Reflect, Tana, Capacities]. MeetingScribe's Today tab is a transient dashboard, not a *persisted, linkable, searchable* daily journal. Nothing in the vault ties "what happened on 2026-05-30" together as a durable object.

**6. Chat is agentic tool-use, not vault RAG.** `ChatSession` (`ChatSession.swift`) drives a local Ollama tool-loop over `get_overview`/`list_people`/`get_transcript` etc. This is good for *structured* lookups ("what's due", "texts with Horst") but it is **not** retrieval over note *content* — there's no step that retrieves the top-k relevant transcript/note passages by similarity and grounds the answer with citations. Ask "what did we decide about the migration across all my Q1 calls?" and the model must guess which meeting IDs to fetch; it has no semantic index to retrieve from. Notion's Q&A answers "what did we decide about the pricing change last month?" *with citations* by searching across all content [Notion]. MeetingScribe's chat can't reliably do cross-meeting synthesis because there's no retrieval layer under it.

**7. No proactive resurfacing.** Mem's "Heads Up" panel proactively flags a six-month-old client note when it becomes relevant again [Mem]; Mem's Daily Digest resurfaces aging-relevant notes. MeetingScribe surfaces "suggested people" (`SuggestedPeopleView`) and the planned "stay-in-touch nudges," but never resurfaces *knowledge* — "you discussed this same topic 3 weeks ago," "before your 2pm with Acme, here's the last 2 meetings + open items." The pre-meeting brief is the closest hook and is the right place to graft this on.

**Net:** capture is ahead of the field (100% local transcription + a real CRM graph is a genuine moat the PM audit correctly identified). Recall is behind. The good news: the FTS5 spine is *already written* — the gap is wiring + a semantic layer, not green-field.

## Existing-plan items I rank highest

1. **Unified "find everything about X" → wire `searchAll()`/`vault_fts` into `GlobalSearchView`** (V3 §4, REMAINING_WORK §4). Highest-priority existing item through my lens: the FTS5 engine is built (`SecondBrainDB.swift:269`) and the app ignores it. This is the recall moat going to waste.
2. **FTS5 schema upgrade to v2 / WorkspaceIndex → FTS5 migration** (V2 Phase 1 + Phase 3). Endorse — but note v2 schema already landed; the remaining work is *trusting and using* it, plus fixing the stale-index bug the team hit (`WorkspaceIndex.swift:197`).
3. **Speaker-labeled transcript & summary** (V3 §4). Through a recall lens this matters because attributed text ("Alice committed to X") is far more retrievable and graphable than anonymous transcript.
4. **Stay-in-touch nudges** (V3 §4) — the only proactive-resurfacing primitive currently planned; the right scaffold to extend toward knowledge resurfacing (C2-6 below).
5. **Per-tag summary templates** (V3 §4) — structured summaries (decisions / commitments / questions) are the raw material for smart collections and graph topic-nodes.

## NET-NEW recommendations

### C2-1 — Wire FTS5 + add semantic recall (hybrid search) **[the moat]**
**What:** Replace `WorkspaceIndex.search()`'s in-memory pass with the existing `vault_fts` recency-BM25 query (`SecondBrainDB.swift:269`), then add a local embedding index (e.g. a small on-device model via Ollama `nomic-embed-text`, stored in a `vault_embeddings` table) and fuse lexical+semantic with reciprocal-rank fusion. Fixes the stale-`search_index` bug (`WorkspaceIndex.swift:197`) along the way.
**Why:** Every leader's headline feature is intent-based recall (Mem Deep Search, Reflect similar-notes, Capacities semantic retrieval). MeetingScribe is lexical-only and the lexical index isn't even used.
**User value:** "price increase" finds the meeting that said "$30 tier"; recall stops depending on remembering exact words.
**Effort:** L · **Impact:** High · **Depends on:** FTS wiring (already-built schema); embeddings are additive.

### C2-2 — Ask-your-vault RAG mode in Chat
**What:** Add a retrieval step to `ChatSession.run()` (`ChatSession.swift:152`): before/within the tool loop, embed the user's question, retrieve top-k transcript/note/summary chunks (from C2-1's index), inject them as grounded context, and require inline citations linking back via `meetingscribe://`. Add a `search_vault(query)` chat tool that returns ranked passages, not just entity stubs.
**Why:** Today's chat does structured lookups but cannot synthesize across meeting *content* ("what did we decide about the migration across Q1?"). Notion's cited Q&A is the bar [Notion].
**User value:** Cross-meeting answers with sources — the single feature that turns a transcript archive into a queryable brain.
**Effort:** M · **Impact:** High · **Depends on:** C2-1 (needs the retrieval index).

### C2-3 — Automatic bidirectional links (entity backlinks, not URL backlinks)
**What:** During the post-meeting pipeline, detect entity mentions (people via PeopleStore, projects, prior meetings, tags) in transcript/summary and write *typed* backlinks into the index. On every Person/Project/Meeting detail, render a "Mentioned in" / "Linked from" section computed from the index (replace the literal-URL scan in `WorkspaceIndex.backlinks` `:61`). Add `[[` autocomplete in the notes editor (`MarkdownEditor.swift`) that inserts a real link.
**Why:** Reflect/Capacities/Tana are built on automatic bidirectional links; MeetingScribe's links are inert unless hand-pasted. Auto-linking is what makes the graph self-assemble.
**User value:** Open Acme's page → see every meeting that discussed Acme, with zero manual tagging.
**Effort:** M · **Impact:** High · **Depends on:** C2-1 index; speaker/entity extraction.

### C2-4 — Daily Note: a persisted, linkable temporal spine
**What:** Add a first-class `DailyNote` entity (one per date) auto-created each morning, pre-populated with that day's meetings (linked), open action items, and a free-write journal area; indexed in `vault_content` like everything else. Make Today's hero a *view* of today's DailyNote rather than a transient dashboard.
**Why:** Daily notes are table-stakes across Reflect, Tana, Capacities — the habit loop and the temporal anchor for "what happened when" [Reflect, Tana, Capacities].
**User value:** A durable, searchable journal of each day that links meetings, tasks, and thoughts into one object.
**Effort:** M · **Impact:** Med-High · **Depends on:** entity/index plumbing.

### C2-5 — Knowledge-graph view: promote meetings, projects & topics to nodes
**What:** Extend `PeopleGraphViewModel` (`:38`) to a heterogeneous graph: node kinds person/meeting/project/topic-tag; edges from attendance, mention (C2-3), shared-tag, and action-item-ownership. Reuse the existing force layout + BFS find-path. Add a node-kind filter to `GraphFilterBar`.
**Why:** The rendering engine is already excellent but fed one entity type. Capacities ("entire knowledge network as a living graph") and Tana set the bar [Capacities, Tana].
**User value:** "Show me the cluster around the Migration project — who, which meetings, what's open" in one canvas.
**Effort:** M · **Impact:** Med · **Depends on:** C2-3 (typed links supply the edges).

### C2-6 — Proactive resurfacing ("Heads Up" for meetings)
**What:** Two surfaces: (a) in the pre-meeting brief, auto-attach the last N meetings with overlapping attendees/topics + their open action items + relevant past decisions (semantic-similar via C2-1); (b) a Today "Resurfaced" card — "3 weeks ago you discussed X; it's relevant to today's Y." Reuse the stay-in-touch nudge scaffold but for *knowledge*, not just contact cadence.
**Why:** Mem's Heads Up / Daily Digest proactively resurface aging-relevant notes — the defining "compounding knowledge" behavior [Mem]. MeetingScribe resurfaces people but never knowledge.
**User value:** Walk into every meeting with the relevant history already pulled, unprompted.
**Effort:** M · **Impact:** High · **Depends on:** C2-1 (similarity), C2-3 (links).

### C2-7 — Smart Collections (saved semantic + structured queries)
**What:** Saved, live-updating queries combining FTS/semantic terms + filters (entity kind, tag, date, person). E.g. "Decisions, last 90 days, #pricing." Materialize as a pinnable view in the sidebar; back it with the `vault_fts`/embedding index. Tana's "Live searches" and Mem's Collections are the model [Tana, Mem].
**Why:** Turns recall from one-off search into standing, self-maintaining views of a topic.
**User value:** A always-current "Pricing decisions" or "Open commitments to me" page that needs no maintenance.
**Effort:** M · **Impact:** Med · **Depends on:** C2-1.

### C2-8 — Decision & commitment extraction (structured recall layer)
**What:** Extend the Ollama summary pipeline (and per-tag templates) to extract typed atoms: Decisions, Commitments (who→what→when), Open Questions. Store as first-class indexed entities (so they're searchable, collectible per C2-7, and graphable per C2-5).
**Why:** "What did we *decide*?" is the highest-value recall query and the hardest for raw transcript search. Notion's Q&A leans on this framing [Notion]; Tana auto-extracts decisions/follow-ups from pasted transcripts [Tana].
**User value:** A queryable ledger of every decision and commitment across all meetings.
**Effort:** M · **Impact:** High · **Depends on:** per-tag templates (planned); index.

### C2-9 — Temporal recall: "On this day" + topic timelines
**What:** A lightweight surface (Today card or sidebar) showing meetings/notes from this date in prior weeks/months/years, plus a per-topic/per-person timeline view ("everything with Acme, chronologically"). Cheap given the recency-ranked index already keys on `date_epoch` (`SecondBrainDB.swift:120`).
**Why:** Temporal resurfacing ("after a month you see patterns" — Reflect) is a core compounding-knowledge behavior absent here.
**User value:** Rediscover relevant past context by time, not just keyword.
**Effort:** S · **Impact:** Med · **Depends on:** index (date already stored).

### C2-10 — MCP: expose semantic search + graph traversal to Claude
**What:** Add `search_vault_semantic(query, k)`, `get_backlinks(entity)`, and `find_path(personA, personB)` to the MCP server (`MeetingScribeMCP/main.swift`), surfacing C2-1/C2-3/C2-5 to external agents.
**Why:** The write-capable MCP is a differentiator; extending it with *recall* primitives lets Claude do cross-vault synthesis the in-app chat does, without rebuilding it.
**User value:** "Claude, what's the through-line across my last five Acme calls?" works from any MCP client.
**Effort:** S · **Impact:** Med · **Depends on:** C2-1, C2-3, C2-5.

## Top 3 picks

1. **C2-1 — Wire FTS5 + add hybrid semantic recall.** The single highest-leverage move: the BM25/recency engine is *already in the binary* (`SecondBrainDB.swift:269`) and unused; the app falls back to in-memory `contains()`. Wiring it (and fixing the stale-index distrust at `WorkspaceIndex.swift:197`), then layering local embeddings, closes the one gap that separates MeetingScribe from every leader.
2. **C2-2 — Ask-your-vault RAG in Chat.** Turns the existing local-Ollama chat from structured-lookup tool into a cited, cross-meeting question-answering brain — the feature users mean when they say "second brain."
3. **C2-3 — Automatic bidirectional entity links.** Makes the graph self-assemble from capture instead of requiring manual `[[links]]`, unlocking C2-5 (full graph) and C2-6 (resurfacing) for nearly free.

---
**Sources:**
- [Mem.ai Review 2026 (productivitystack)](https://productivitystack.io/guides/mem-ai-guide/), [Mem.ai Review (aicloudbase)](https://aicloudbase.com/tool/memai), [Mem AI (Lovable)](https://lovable.dev/guides/what-is-mem-ai)
- [Reflect Notes](https://reflect.app/), [Reflect AI Review 2026 (aichief)](https://aichief.com/ai-productivity-tools/reflect-ai/)
- [Tana Supertags Guide](https://aiproductivity.ai/guides/tana-supertags-guide/), [Tana Review 2026 (toolchase)](https://toolchase.com/tool/tana/)
- [Notion AI product](https://www.notion.com/product/ai), [Notion Enterprise Search](https://www.notion.com/help/enterprise-search), [Notion AI Review 2026 (eesel)](https://www.eesel.ai/blog/notion-ai-review)
- [Capacities Product](https://capacities.io/product/), [Capacities AI](https://capacities.io/product/ai)
- [Amie](https://amie.so/), [Amie Review 2026 (work-management.org)](https://work-management.org/productivity-tools/amie-review/)
- [Saga](https://saga.so/), [Saga AI](https://saga.so/ai)
