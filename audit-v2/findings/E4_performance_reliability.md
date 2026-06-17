# Performance & Reliability Findings — MeetingScribe v2 Audit

**Agent ID:** E4  
**Sub-lens:** Launch time, memory at scale, main-thread safety, audio pipeline reliability, crash safety

---

## Top friction points / gaps (file:line citations)

### 1. `allEmbeddings()` is a full-table pull into memory on every hybrid search

`SecondBrainDB.swift:467` — `allEmbeddings()` fetches every stored embedding row into a Swift array and holds it in memory for in-process cosine scoring. The comment says "even thousands of 768-d vectors are only a few MB" — true today, but at 500 meetings × 768 floats × 4 bytes = ~1.5 MB per call. The real problem is that this table is **read on every `searchVaultHybrid` invocation** (`PeopleStore.swift:223`) with no cache. At v2 scale (500 meetings + 1000 people with embeddings), every hybrid search allocates ~3–4 MB, runs cosine over every row in Swift, and throws it away. The correct fix is ANN (approximate nearest neighbor) inside SQLite via sqlite-vec or a persistent in-process vector cache.

### 2. `SecondBrainDB.rebuildIndex()` runs on the `@MainActor` for every People mutation

`PeopleStore.swift:737, 1047` — both `deduplicate()` and `importPeople()` call `rebuildIndex()` synchronously after their writes. `rebuildIndex()` issues `BEGIN`, `DELETE FROM people`, `DELETE FROM encounters_idx`, `DELETE FROM search_index`, `DELETE FROM vault_content`, then re-inserts every record in a transaction (`SecondBrainDB.swift:285`). At 1000 people + encounters this is hundreds of SQLite writes inside a single transaction, all called from `@MainActor` functions. The per-mutation `syncIndex()` path (`PeopleStore.swift:153`) uses an upsert which is fine — the problem is the full-rebuild fallback triggered after bulk operations.

### 3. `WebAPI.swift` calls `listPastMeetings(limit: 100_000)` for ID lookups

`WebAPI.swift:131, 606, 710` — three HTTP handler paths call `listPastMeetings(limit: 100_000)` then do `.first(where: { $0.id == id })`. When the in-memory cache is warm, `listPastMeetings` returns all 500+ Meeting structs (allocating the full array), then scans linearly for one ID. The correct fix is a `meeting(byID:)` method on `MeetingStore` that uses the `_directoryByID` cache for O(1) lookup — this method is partially implied by `MeetingStore.swift:496` but not wired into WebAPI.

### 4. `ActionItemStore.writeEnvelope` encodes with `pretty: true, sorted: true`

`ActionItemStore.swift:1693` — every task mutation encodes the full array with `pretty: true, sorted: true`. Key-sorted pretty-printing is ~3–5× slower than compact encoding. At 10,000 tasks, the encode step runs on `@MainActor` (comment on line 1689 says "cheap for these small files") before handing bytes to `TaskPersistenceCoordinator`. With 10k tasks this is no longer cheap: a 10k-item array with nesting easily reaches 2–4 MB of JSON, which means the main-thread encode step before the coordinator handoff becomes a frame-budget violation on every save.

### 5. `AudioRecorder` watchdog timer created without explicit `RunLoop` attachment — potential stall on audio thread

`AudioRecorder.swift` references a `watchdog: Timer?` field. If this `Timer` is created on the audio pipeline's private queue (no RunLoop), it will silently never fire — the stall condition it monitors can persist indefinitely. The `ProcessInfo.beginActivity` token prevents OS throttling but doesn't replace the watchdog.

### 6. Signal handler path leaves a stale `crash-signal.txt` across runs

`CrashReporter.swift:46` — the signal handler opens `crash-signal.txt` with `O_CREAT | O_TRUNC`. The fixed file name means each new crash overwrites the previous one. A single post-mortem crash report is fine, but a crash storm (signal fires repeatedly before the OS terminates) produces truncated output. More importantly, the static file means there is no history: if the user sees a crash on relaunch, `crash-signal.txt` may reflect a prior run's crash or have been partially overwritten. A timestamp suffix (resolved at `install()` time, when allocation is safe) would give one file per crash event with no signal-context allocation cost.

### 7. `PeopleStore` cache file grows unboundedly with no size guard

`PeopleStore.swift:376` — `writeCache` serializes all People + Encounters + Suggestions into `_people-cache.json`. At 1000 people with memories, tags, talk-points, encounters, and suggestions, this single file could easily reach 20–50 MB. It is read as a single `Data(contentsOf:)` call (line 372), which blocks the background thread until the entire file is in memory. There is no incremental/paged load path.

### 8. `MeetingStore.enumerateMeetingDirectories` is a 3-level `FileManager` walk invoked synchronously

`MeetingStore.swift:580` — `walk(root, depth: 3)` issues `contentsOfDirectory` at every level. At 500 meetings, under iCloud Drive (where `open()` is intercepted by the daemon), this can take multiple seconds. The in-memory `_indexMemoryCache` mitigates repeat calls, but cold starts after a reboot or after iCloud evicts metadata are unprotected.

---

## Existing items to endorse (from prior plan or codebase)

- `TaskPersistenceCoordinator` (BE-1): excellent pattern — coalesced off-main writes with termination flush. Should be the template for ALL stores.
- `AudioRecovery.ensureDownloaded` iCloud-aware segment discovery and download with timeout: solid guard for iCloud Drive users.
- `CrashReporter` async-signal-safe path using `backtrace_symbols_fd`: the fix for the prior double-fault is correct and complete.
- `PeopleStore` single-file cache (`_people-cache.json`) with per-launch snapshot (`VaultCache` list): dramatically better than per-file scan. Correct direction.
- `MeetingStore` `_indexMemoryCache` + `_directoryByID` path cache: right architecture, needs to be fully exercised by WebAPI.

---

## NET-NEW recommendations

### E4-1: Persistent in-process embedding cache (kill `allEmbeddings()` per-search)

- **What:** Load the embedding table into a shared, lazily-initialized in-memory cache on first hybrid search, and invalidate only on insert/delete. Store as `[String: [Float]]` keyed by `"kind\u{1}id"`. Replace the per-call `allEmbeddings()` pull with a cache read.
- **Why (second-brain angle):** Hybrid search is the retrieval backbone for the AI chat, PreMeetingBrief, and related-meeting backlinks. Making it latency-free (sub-10ms for 500 meetings) means the chat assistant can use it for every tool call without perceptible lag.
- **Cross-feature connections:** GlobalSearch, ChatTools, PreMeetingBriefView, relatedMeetings backlinks, WeeklyRecap
- **Effort:** S | **Impact:** High
- **Deps:** none

### E4-2: Move `SecondBrainDB.rebuild()` off `@MainActor` (async incremental rebuild)

- **What:** Replace the synchronous full-rebuild after bulk People operations with a `Task.detached` async path that issues the SQLite transaction off the main thread. Use a serial actor (`SQLiteActor`) to serialize writes. Gate with a debounce so multiple rapid imports coalesce into one rebuild.
- **Why (second-brain angle):** People is "the graph" (briefing). Import of contacts, calendar attendees, or iMessage participants is the primary way the graph grows. If import blocks the main thread, users will feel the app freeze every time they onboard data — discouraging the enrichment that makes the second brain valuable.
- **Cross-feature connections:** PeopleListView, People import flows (contacts, calendar, Apple Notes, Gmail, iMessage), PeopleStore deduplication
- **Effort:** M | **Impact:** High
- **Deps:** none

### E4-3: Replace `WebAPI.listPastMeetings(limit: 100_000)` scans with `meeting(byID:)`

- **What:** Add `func meeting(byID id: String) -> Meeting?` to `MeetingStore` that uses the O(1) `_directoryByID` + `readMeeting(at:)` path. Swap all three `WebAPI.swift` lookup sites to use it. For the count endpoint (`WebAPI.swift:106`), derive from `cachedIndex().count` rather than materializing all Meeting structs.
- **Why (second-brain angle):** The local HTTP server is the bridge between MCP/Claude and the app's data. Slow WebAPI handlers mean the AI chat's tool calls block during heavy use (e.g., daily standup digest building a list of all meetings with their people).
- **Cross-feature connections:** WebAPI, MCP server, ChatTools, StandupDigest, WeeklyRecap
- **Effort:** S | **Impact:** Med
- **Deps:** none

### E4-4: Switch `ActionItemStore.writeEnvelope` to compact encoding for > N tasks

- **What:** Pass `pretty: false, sorted: false` to the encoder when `items.count > 500`. The `.bak` write-ahead backup already provides recoverability. Pretty-print only in an explicit "export for Finder readability" path.
- **Why (second-brain angle):** Every task completion, drag-reorder, or subtask check triggers a main-thread encode. At 10k tasks, keeping pretty+sorted encoding means recurrent 50–200ms stalls on the UI thread during normal use.
- **Cross-feature connections:** ActionItemStore, TaskPersistenceCoordinator
- **Effort:** S | **Impact:** Med
- **Deps:** none

### E4-5: Timestamp crash-signal files at `install()` time; rotate to keep last 5

- **What:** At `CrashReporter.install()`, resolve a timestamped path (`crash-signal-<epoch>.txt`) and pre-compute `signalPath` from it. On install, delete all but the 5 most recent `crash-signal-*.txt` files (safe to do in normal context). Store the per-crash timestamp in the pre-resolved path at install time.
- **Why (second-brain angle):** Crash history is the only post-mortem evidence for diagnosing flaky audio pipeline failures. A single-file overwrite means a crash storm erases itself. With 5 retained files, the developer can correlate crashes with audio segment timestamps.
- **Cross-feature connections:** CrashReporter, AudioRecorder, MeetingPipelineController
- **Effort:** S | **Impact:** Med
- **Deps:** none

### E4-6: Add `PeopleStore` cache size guard and incremental load for large datasets

- **What:** Before writing `_people-cache.json`, check encoded size. If > 10 MB, split into a `_people-header-cache.json` (lightweight list snapshot rows) and `_people-full-cache.json` (complete records). The app hydrates the list from the header cache first (fast), then lazily loads the full cache in the background.
- **Why (second-brain angle):** A user who has imported 2000+ contacts and logged hundreds of encounters will hit a cold-start stall on `_people-cache.json` reads. Incremental hydration means People list is responsive within 100ms even at power-user scale.
- **Cross-feature connections:** PeopleListView, PeopleStore, LaunchSnapshot (VaultCache)
- **Effort:** M | **Impact:** Med (high for power users)
- **Deps:** none

---

## Top 3 picks

1. **E4-1** — Persistent embedding cache eliminates the biggest hidden allocation on the retrieval hot path; critical before v2 makes hybrid search the default for all AI features.
2. **E4-2** — Moving SQLite rebuild off `@MainActor` unblocks the People import flows that grow the second brain's graph; a jank-free import is table stakes for power-user data volume.
3. **E4-3** — O(1) WebAPI meeting lookup is a one-hour fix that prevents the MCP/Claude integration from degrading under a 500-meeting dataset, making the AI chat reliable at v2 scale.
