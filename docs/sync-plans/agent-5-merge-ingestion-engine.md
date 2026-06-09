# Agent 5 — Hub-Side Ingestion & Merge Engine (`RemoteVaultIngestor`)

**Scope:** the hub-side engine that takes work-MacBook MeetingScribe files which
have already landed in a quarantined staging namespace and *safely merges* them
into the hub's live second brain. Transport (Tailscale+rsync / Syncthing /
in-app HTTP / Git) is out of scope and owned by other engineers — this design
begins the moment bytes exist at
`<vault>/_remote/work-macbook/…`.

This is a **build plan**, not just a sketch. Real Swift, real file paths,
verified against the current repo (`PeopleStore`, `MeetingStore`,
`ActionItemStore`, `TagStore`, `SchemaEnvelope`, `MeetingScribeMCP/main.swift`).

---

## 1. Overview — where ingestion sits

```
 Work MacBook                         Hub (Mac mini = vault / second brain)
 ┌──────────────┐   transport (rsync/  ┌──────────────────────────────────────┐
 │ MeetingScribe│   syncthing/http/git)│  STAGING (quarantine, read-only to    │
 │   vault      │ ───────────────────▶ │  the live app):                       │
 └──────────────┘                      │   <vault>/_remote/work-macbook/        │
                                       │      ├── meetings/…                    │
                                       │      ├── people/…                      │
                                       │      ├── encounters/…                  │
                                       │      ├── action_items.json             │
                                       │      ├── tags.json … etc               │
                                       │      └── _manifest.json (optional)     │
                                       │                                        │
                                       │  ┌──────────────────────────────────┐ │
                                       │  │  RemoteVaultIngestor (THIS WORK)  │ │
                                       │  │  scan → plan → (review?) → apply  │ │
                                       │  └──────────────────────────────────┘ │
                                       │            │ additive-only writes      │
                                       │            ▼                           │
                                       │  LIVE VAULT (authoritative):           │
                                       │   meetings/ people/ encounters/        │
                                       │   action_items.json tags.json …        │
                                       │            │                           │
                                       │            ▼ rebuild                    │
                                       │  DERIVED: .meeting-index.json,          │
                                       │   _people-cache.json, FTS5/SQLite       │
                                       └──────────────────────────────────────┘
```

**Design principle (non-negotiable):**

> **The hub is authoritative. Work data is *additive-only*.** Ingestion may
> CREATE new records and UNION new sub-data into existing records. It may NEVER
> delete, overwrite, or shrink a record that already exists in the live vault. A
> work record that *conflicts* with a personal record of the same identity is
> never applied in place — it is routed to a conflict quarantine for human
> review.

This mirrors how the codebase already treats untrusted/derived inputs:
`PeopleStore.importPeople` / `mergeImport` *only fill empty scalars and union
collections*; `ActionItemStore.reconcileExtracted` *preserves user-edited
fields*; `ActionItemStore.mergeExternal` *dedupes by `(source, externalID)`*.
We extend the same posture across the whole vault and add provenance + a ledger
so re-runs are no-ops.

Ingestion is **not** a transport. It assumes a complete, consistent snapshot has
arrived (see §10 for partial-transfer handling) and runs:

1. On app boot (background phase), if a staging namespace exists and is newer
   than the last ledger entry.
2. On a periodic timer (default every 2h, configurable).
3. On demand from a Settings button ("Import work data now") — which can run in
   **dry-run / review mode** first.

---

## 2. Record identity & provenance

Two devices generate UUIDs independently. We must keep work-origin records
distinguishable from personal ones forever, and we must make re-imports
idempotent. Three mechanisms, layered:

### 2.1 Origin tagging (provenance)

Every record imported from a device carries an origin marker:

- **People** — reuse the existing `Person.importSources: Set<String>`. Imported
  work people get `importSources.insert("work-macbook")` (the `sourceDevice`
  id). This already drives the "provenance" UI and survives merges
  (`mergeFields`/`mergeImport` both `formUnion` `importSources`). Zero schema
  change.
- **Action items** — reuse the existing `source: String?` /
  `externalID: String?` fields. Work items get `source = "remote:work-macbook"`
  and keep their original `externalID = <original ActionItem.id>` so re-imports
  match the *exact same record* via the existing `(source, externalID)` dedup in
  `mergeExternal`. No schema change.
- **Meetings, encounters, tags** — these models have no provenance field today.
  Rather than touch every model (and risk the tolerant-decode contract), the
  ingestor records provenance **out of band** in the import ledger (§6) keyed by
  the *namespaced id* (below). The on-disk record stays byte-faithful to what the
  work device produced, which is what makes idempotency trivial: the same input
  file hashes the same and is skipped.

  Optionally (a clean, backward-compatible add) we can attach a tiny sidecar
  `origin.json` inside each imported meeting folder:
  `{ "schemaVersion": 1, "data": { "sourceDevice": "work-macbook", "importedAt": …, "originalID": … } }`.
  Because `MeetingStore` ignores unknown files in a meeting dir, this is
  non-breaking and gives Finder-level + MCP-level provenance without a `Meeting`
  schema bump.

### 2.2 ID namespacing (collision-proof identity)

UUID collisions between two devices are astronomically unlikely, so by default
**we preserve the original id** (this is what makes re-import idempotent and lets
backlinks like `Person.meetingMentions` / `ActionItem.meetingID` keep
resolving). The dangerous case is not id collision — it's **slug collision**
(two different meetings producing the same `yyyy-MM-dd-HHmm-Title` folder name)
and the pathological **same-id-different-content** case (a personal meeting and a
work meeting that genuinely share an id — only possible via a restore/clone
mistake). Both are handled:

```swift
/// Stable per-device id used to namespace folders + ledger keys.
struct SourceDevice: Hashable, Codable {
    let id: String          // "work-macbook" — stable, set in Settings on the work side
    let displayName: String // "Tyler's Work MacBook"
}

/// A globally-unique key for a record across devices. We keep the original id
/// inside the record, but key the LEDGER and any disambiguated folders by this.
func namespacedKey(device: SourceDevice, originalID: String) -> String {
    "\(device.id)::\(originalID)"   // e.g. "work-macbook::4F3A…"
}
```

- **Folder slug collisions** are resolved with the same suffixing strategy
  `MeetingStore.moveMeeting` already uses (`-2`, `-3`, …). The *id* is unchanged;
  only the human-readable directory name gets a suffix.
- **Same-id, different-content** between a *personal* and a *work* meeting →
  treated as a conflict (§8): the work meeting is **re-keyed** to a namespaced id
  (`work-macbook::<originalID>` becomes the live id) and routed to conflict
  quarantine for review, never overwriting the personal one.

### 2.3 Idempotency anchor

Each staged item is hashed (content hash of its canonical bytes, §6). The ledger
stores `namespacedKey → lastImportedHash`. Re-running with unchanged bytes is a
pure no-op; changed bytes produce a *delta* that goes through the same
additive/merge path again (which is itself idempotent for unions).

---

## 3. Meetings merge

Staged meeting folders look exactly like live ones
(`meeting.json` = `SchemaEnvelope<MeetingDTO>`, `transcript.md`, `notes.md`,
`summary.md`, `audio/manifest.json` + `*.m4a`). Algorithm per staged folder:

```
for each staged meeting dir D:
    m = decode(D/meeting.json)                  // SchemaEnvelope.decode, tolerant
    key = namespacedKey(device, m.id)
    h   = contentHash(D)                         // hash of meeting.json + md files + manifest
    if ledger[key].hash == h: continue           // idempotent skip (unchanged)

    live = liveMeeting(withID: m.id)             // via MeetingStore index, O(1)

    switch classify(live, m):
    case .new:
        // No live meeting with this id → straight ADD.
        targetDir = MeetingStore.desiredDirectory(for: m, primaryTag: primary(m))
        targetDir = disambiguate(targetDir)      // suffix on slug collision
        copyTree(from: D, to: targetDir)         // meeting.json + md + audio/
        store.upsertInIndex(m with relativeFolderPath=targetDir)
        applyTagsFor(m)                          // §5 tags.json union
        ledger[key] = Entry(hash: h, liveID: m.id, dir: rel(targetDir), origin: device)

    case .sameIDSameOrigin(let liveDir):
        // We imported this before; work side edited it. ADDITIVE refresh:
        // copy any md/audio files that are missing or newer ON THE WORK SIDE,
        // but NEVER clobber a file the user edited on the hub.
        additivelyRefresh(liveDir, from: D)      // see rules below
        ledger[key].hash = h

    case .sameIDPersonalOrigin:
        // An id collision with a PERSONAL meeting (origin != this device).
        // One-way + additive ⇒ do NOT overwrite. Re-key + quarantine.
        quarantine(D, reason: .idCollisionWithPersonal, suggestedID: key)

    case .slugCollisionDifferentID(let liveDir):
        // Different meeting, same desired folder name → just disambiguate dir.
        // (handled inside .new via disambiguate(); listed here for completeness)
```

**`additivelyRefresh` file rules (one-way ⇒ work is additive):**

- `meeting.json`: re-decode both. Build a *merged* DTO that takes the **union**
  of attendees, keeps the **hub's** `userTitle`/`userDescription`/`health` if the
  hub set them (personal edits win on hub), fills any field the hub left
  empty/nil from the work copy, and takes `max(endDate)`. Never blank a hub
  field. Write back via `MeetingStore.writeMeeting` (atomic, coordinated).
- `transcript.md` / `summary.md`: machine-generated and immutable in practice →
  copy from work **only if the hub copy is missing or empty**. If both exist and
  differ, keep the hub's and drop a `transcript.work.md` sidecar (no data loss,
  no clobber).
- `notes.md`: **user-authored** → never overwrite. If the hub has no notes and
  work does, copy. If both have notes and they differ, append the work notes
  under a `\n\n---\n_Imported from work-macbook (<date>)_\n` divider. (Append,
  never replace — same spirit as MCP's append-only note writes.)
- `audio/`: audio files are content-addressed by manifest. Copy any `*.m4a`
  segment the hub doesn't already have; merge `audio/manifest.json` by union of
  segment entries (dedupe by filename). Never delete hub audio.

**Index maintenance:** every add/refresh calls `MeetingStore.upsertInIndex(_:)`
so `.meeting-index.json` stays correct without a full rescan. A single
`MeetingStore.rebuildIndexAsync()` is run **once** at the end of a batch as a
safety net (and to rebuild after disambiguated moves). `_recent.json` is updated
automatically by `writeMeeting`.

**Audio note:** audio is the bulk of bytes. The ingestor must treat
already-present segments as no-ops (hash/size+name check) so re-runs don't
re-copy gigabytes. This is the single biggest perf lever and is enforced by the
ledger + per-file existence checks.

---

## 4. People dedup / merge

This is the richest reconciliation and we **reuse the existing engine** rather
than inventing a parallel one. `PeopleStore` already has: exact email/phone match
+ contactIdentifier match (`matchIndex`), fuzzy-name thresholds
(`autoLinkThreshold = 0.85`, `possibleMatchThreshold = 0.6`), union-merge
(`mergeFields`, `mergeImport`, `mergePeople`), `PersonSuggestion`, and
`dismissedSignatures`. The ingestor maps staged `person.json` records onto this.

### 4.1 Match → decide

For each staged `person.json` (decoded via `SchemaEnvelope<Person>`):

1. **Strong identity match** (auto-merge, no review) — in this precedence
   (matches `PeopleStore.matchIndex`):
   - same `contactIdentifier`, else
   - shared normalized email (`PersonMatching.normalizeEmail`), else
   - shared normalized phone (≥7 digits), else
   - exact normalized name (`PersonMatching.normalizeName`).
   → **auto-merge** the staged record into the live person via the union rules
   below, and `importSources.insert("work-macbook")`.

2. **Fuzzy name only** (no shared email/phone/cid), `NameSimilarity.score`:
   - `≥ 0.85` → still auto-merge (consistent with `ingestExtraction`'s
     `autoLinkThreshold`), **but** only if there's no *conflicting* strong field
     (e.g. a different non-empty company AND different emails → demote to
     suggestion to avoid a false merge).
   - `0.6 ≤ score < 0.85` → emit a **`PersonSuggestion`** (a *possible match*,
     `matchedPersonID` set) for the Today tab. The user confirms/dismisses with
     the existing UI — no new surface needed.

3. **No match** (`< 0.6`) → **create a new person** (work-origin). This is safe
   and additive. (We do *not* gate brand-new work colleagues behind review by
   default — they're the whole point of the backup — but the review/dry-run mode
   in §7 lets the user see them first.)

### 4.2 Union merge (no duplication, stable-id keyed)

When merging a staged person into a live person, reuse the exact semantics of
`PeopleStore.mergeFields` (already battle-tested by the dedup path):

- `emails`/`phones`/`addresses`/`favorites` → `dedupeEmails`/`dedupePhones` /
  ordered-set union.
- `tagIDs`, `meetingMentions`, `importSources` → `formUnion`.
- `memories`, `attachedNotes`, `photoRelativePaths` → **union keyed by stable
  `id`** (these are `Identifiable` with UUID ids). *Important refinement:*
  `mergeFields` currently does `k.memories += other.memories` (plain concat),
  which would duplicate on re-import. The ingestor must union by id:

  ```swift
  func unionByID<T: Identifiable & Hashable>(_ a: [T], _ b: [T]) -> [T] {
      var seen = Set(a.map(\.id)); var out = a
      for x in b where seen.insert(x.id).inserted { out.append(x) }
      return out
  }
  // memories / attachedNotes / photoRelativePaths use this.
  ```

  This is also a worthwhile fix to land in `mergeFields` itself so the local
  dedup path stops double-appending across re-runs.

- `relationships` → union by `toPersonID` (as `mergeFields` already does). After
  all people are merged, run a **relationship-repoint pass**: any
  `Relationship.toPersonID` (and `Encounter.personID`, `ActionItem.ownerPersonID`,
  `Person.meetingMentions`) that pointed at a *work id that got merged into a
  live id* must be repointed to the live id. The ingestor keeps a
  `loserWorkID → keeperLiveID` map exactly like `deduplicate()` does and applies
  the same repoint logic.

- Scalars (`company`, `role`, `bio`, `birthday`, `contactIdentifier`) → fill only
  if hub is empty/nil (`if k.company.isEmpty { k.company = other.company }`).
  **Hub never loses a value.**

- Timestamps → `createdAt = min`, `lastInteractionAt = max`,
  `updatedAt = Date()` (same as `mergeFields`).

### 4.3 Encounters

Staged `encounters/<id>.json` are copied by id (§5) and their `personID` is
**repointed** through the `loserWorkID → keeperLiveID` map so encounters land on
the merged live person, not an orphaned work id.

All of the above runs through `PeopleStore` on the `@MainActor` so the in-memory
`[Person]`, the FTS index, and `_people-cache.json` all stay consistent — we do
**not** write `person.json` behind the store's back.

---

## 5. Aggregate-file reconciliation

These files are *combined* — blind copy = catastrophic data loss. Each is
**read live → merged in-memory → atomically written**. Never copy the staged
file over the live one.

### 5.1 `action_items.json` (+ projects / initiatives / labels / sections)

Reuse `ActionItemStore.mergeExternal`-style keying. Concretely:

- **Items:** dedupe by `(source, externalID)` where work items arrive with
  `source = "remote:work-macbook"`, `externalID = <original id>`. On match,
  preserve hub-edited fields (status/priority/dueDate/notes/notionPageID — exactly
  what `reconcileExtracted` and `mergeExternal` already protect); on no match,
  append. This makes re-import idempotent at the item level *independently* of the
  ledger.
- **Projects / Initiatives / Sections / Labels** (separate files:
  `projects.json`, `initiatives.json`, `task_labels.json`,
  `project_sections.json`): union by id; if an id is new, append; if it exists,
  fill-empty-scalars only. Carry `Project.meetingIDs` as a **set union** (so work
  meeting links accumulate). Map any project/initiative/section/label id that the
  ingestor had to re-key into the item references.
- All writes go through the existing `ActionItemStore` mutators
  (`upsert`, `upsertProject`, `mergeExternal`, `createLabel`…) so the
  `@Published` arrays + on-disk envelopes stay in sync. No raw file copy.

### 5.2 `tags.json`

`TagStore.Persisted = { tags, meetingTags, seriesTags }`.

- `tags`: union by `MeetingTag.id`. Preset ids (`preset-skio`, …) are identical
  across devices → they merge to one. User-created tag ids are UUIDs → unioned.
  Keep the hub's name/symbol/color on id-collision (hub authoritative).
- `meetingTags` (`meetingID → [tagID]`): for each work meeting id, **union** the
  hub's assignment list with the work list (dedupe). Use namespaced/re-keyed
  meeting ids where a meeting was re-keyed.
- `seriesTags`: same union semantics keyed by series id.
- Apply via `TagStore.setTags(_:for:propagateToSeries:)` per affected meeting (or
  a single batched persist). Never replace the whole map.

### 5.3 `encounters/<id>.json`

One file per encounter, keyed by id. Copy any encounter whose id isn't already
live; on id-collision, keep hub's (encounters are immutable facts — collision
means already-imported). Repoint `personID` through the people-merge map (§4.3).
Route through `PeopleStore` (which owns `encounters`) so counts/index refresh.

### 5.4 Rebuild derived artifacts (caches — never merged, always rebuilt)

After the merge transaction commits, rebuild the rebuildables in this order:

1. `MeetingStore.rebuildIndexAsync()` → `.meeting-index.json` (+ `_recent.json`).
2. `PeopleStore` writes `_people-cache.json` automatically (debounced) once its
   `@Published` arrays change; for determinism the ingestor calls a forced
   cache write (same path `deduplicate()` uses) so a relaunch immediately after
   ingest reflects the merge.
3. `PeopleStore.rebuildIndex()` → FTS5 `secondbrain.db` (people).
4. For each newly-added/updated meeting, `PeopleStore.indexMeeting(_:summary:tags:)`
   → `vault_fts` so global search finds work meetings. (Embeddings, if enabled,
   backfill lazily via the existing `embedAndStore` path — not blocking.)

These caches are explicitly listed as "rebuildable, don't merge" — the staged
copies of `.meeting-index.json` / `_people-cache.json` are **ignored entirely**.

---

## 6. Idempotency & the import ledger

A single JSON file at the staging root: **`<vault>/_remote/.import-ledger.json`**
(`SchemaEnvelope`-wrapped, version 1). It records what we've imported and the
content hash of each item so re-runs are deltas.

```swift
struct ImportLedger: Codable {
    var schemaVersion: Int = 1
    /// device id → its per-record state
    var devices: [String: DeviceState] = [:]

    struct DeviceState: Codable {
        /// last successful full-ingest run
        var lastRunAt: Date?
        /// last snapshot manifest hash seen (for partial-transfer guarding)
        var lastManifestHash: String?
        /// namespacedKey → record import state
        var records: [String: Record] = [:]
    }

    struct Record: Codable {
        var kind: String          // "meeting" | "person" | "encounter" | "aggregate:action_items" | …
        var originalID: String
        var liveID: String        // may differ if re-keyed on conflict
        var contentHash: String   // SHA-256 of canonical bytes
        var importedAt: Date
        var status: String        // "merged" | "created" | "quarantined" | "skipped"
        var liveRelativePath: String?  // for meetings: where it landed
    }
}
```

**Hashing** (`contentHash`): SHA-256 over the canonical, sorted-key JSON bytes
for record files, and over a stable digest of the file set
(`name + size + sha256`) for a meeting *directory* (so any md/audio change is
detected). Use `CryptoKit.SHA256` (already available on macOS, no new dep).

**Re-run flow:** scan staging → for each item compute `contentHash` → compare to
`ledger.devices[device].records[key].contentHash`:

- equal → **skip** (no-op). This is what makes "run every 1–2 hours" cheap.
- different / missing → run it through the merge path; update the ledger entry.

The ledger is written **atomically at the end of a successful run** (and after
each batch checkpoint for crash-safety — see §10). Because the merge path itself
is union/fill-empty, even a ledger loss only causes redundant *safe* re-merges,
never corruption.

---

## 7. The Swift design

### 7.1 Types & files

New files (all under the app target unless noted):

- `Sources/MeetingScribe/Sync/RemoteVaultIngestor.swift` — the coordinator.
- `Sources/MeetingScribe/Sync/ImportLedger.swift` — ledger model + load/save.
- `Sources/MeetingScribe/Sync/IngestPlan.swift` — the dry-run plan model
  (`IngestAction` enum + `IngestReport`).
- `Sources/MeetingScribe/Sync/IngestHashing.swift` — `CryptoKit` digest helpers
  + atomic-write helper.
- `Sources/MeetingScribe/UI/Settings/RemoteImportSettingsView.swift` — the
  Settings panel ("Import work data now", schedule, review-before-merge toggle,
  conflict list).

The `Sync/` folder already exists (`Sources/MeetingScribe/Sync/` per
ARCHITECTURE.md "Lightweight cross-device sync"), so this slots in cleanly.

### 7.2 Coordinator shape (concurrency boundaries marked)

```swift
import Foundation
import VaultKit
import CryptoKit
import OSLog

@MainActor                              // ← owns store mutations; publishes progress
final class RemoteVaultIngestor: ObservableObject {
    static let shared = RemoteVaultIngestor()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Ingest")

    @Published private(set) var isRunning = false
    @Published private(set) var lastReport: IngestReport?
    @Published private(set) var conflicts: [IngestConflict] = []   // → quarantine review UI

    // Injected so tests can swap a temp vault + fake stores.
    private let meetingStore: MeetingStore
    private let peopleStore: PeopleStore
    private let actionItemStore: ActionItemStore
    private let tagStore: TagStore

    var stagingRoot: URL {              // <vault>/_remote
        AppSettings.shared.storageDir.appendingPathComponent("_remote", isDirectory: true)
    }

    // MARK: Public API

    /// Plan only — no writes. Powers "review before merge". Heavy scan runs
    /// off-main; returns a structured plan the UI renders.
    func plan(device: SourceDevice) async -> IngestPlan { … }

    /// Apply a previously-computed plan (or compute+apply in one shot when
    /// `dryRun == false` and no review is required).
    @discardableResult
    func run(device: SourceDevice, dryRun: Bool = false) async -> IngestReport { … }

    /// Scan all device namespaces under _remote and ingest each. Called from
    /// boot + the periodic timer.
    func runAllPending() async { … }
}
```

### 7.3 The merge entry point (representative)

```swift
extension RemoteVaultIngestor {

    func run(device: SourceDevice, dryRun: Bool = false) async -> IngestReport {
        isRunning = true; defer { isRunning = false }

        let deviceRoot = stagingRoot.appendingPathComponent(device.id, isDirectory: true)

        // 1. SCAN + HASH off-main (pure file work, no actor state). ───────────┐
        let scan: StagingScan = await Task.detached(priority: .utility) {        // boundary
            IngestScanner.scan(deviceRoot: deviceRoot)                          // hashes everything
        }.value                                                                 //                  ┘

        var ledger = ImportLedger.load(at: stagingRoot)                          // @MainActor read
        var report = IngestReport(device: device, dryRun: dryRun)

        // 2. MEETINGS — @MainActor (touches MeetingStore index + writes). ─────
        for staged in scan.meetings {
            let key = namespacedKey(device: device, originalID: staged.meeting.id)
            if ledger.hash(device.id, key) == staged.contentHash {
                report.skipped += 1; continue                                   // idempotent
            }
            switch classifyMeeting(staged) {
            case .new(let dir):
                if !dryRun { try? copyMeetingTree(staged, to: dir, store: meetingStore) }
                report.add(.meetingCreated(staged.meeting.id))
                ledger.record(device.id, key, hash: staged.contentHash,
                              liveID: staged.meeting.id, status: dryRun ? "planned" : "created")
            case .refreshAdditive(let liveDir):
                if !dryRun { additivelyRefresh(liveDir, from: staged) }
                report.add(.meetingRefreshed(staged.meeting.id))
                ledger.bumpHash(device.id, key, staged.contentHash)
            case .conflictPersonal:
                let c = IngestConflict.meetingIDCollision(staged.meeting.id)
                conflicts.append(c)
                if !dryRun { quarantine(staged, reason: c) }
                report.add(.conflict(c))
            }
        }

        // 3. PEOPLE — reuse PeopleStore match/merge; track work→live id map. ──
        let idMap = ingestPeople(scan.people, device: device, dryRun: dryRun, report: &report)

        // 4. ENCOUNTERS (repoint personID via idMap). ────────────────────────
        ingestEncounters(scan.encounters, idMap: idMap, dryRun: dryRun, report: &report)

        // 5. AGGREGATES (action items, projects…, tags). ─────────────────────
        ingestActionItems(scan.actionItems, device: device, idMap: idMap, dryRun: dryRun, report: &report)
        ingestTags(scan.tags, dryRun: dryRun, report: &report)

        // 6. REBUILD derived caches/indexes (skip on dry-run). ───────────────
        if !dryRun {
            await meetingStore.rebuildIndexAsync()
            peopleStore.rebuildIndex()
            forcePeopleCacheWrite()
            ledger.devices[device.id]?.lastRunAt = Date()
            ledger.save(at: stagingRoot)                                        // atomic
        }

        lastReport = report
        return report
    }
}
```

### 7.4 People ingest (reusing the existing engine)

```swift
/// Returns workPersonID → livePersonID for downstream repointing.
private func ingestPeople(_ staged: [StagedPerson],
                          device: SourceDevice,
                          dryRun: Bool,
                          report: inout IngestReport) -> [String: String] {
    var idMap: [String: String] = [:]
    for sp in staged {
        var incoming = sp.person
        incoming.importSources.insert(device.id)

        if let live = peopleStore.bestStrongMatch(for: incoming) {            // new helper, see below
            idMap[incoming.id] = live.id
            if !dryRun { peopleStore.mergeRemote(incoming, into: live.id) }   // new union-by-id merge
            report.add(.personMerged(work: incoming.id, live: live.id))
        } else if let (live, score) = peopleStore.bestFuzzyMatch(for: incoming),
                  score >= PeopleStore.autoLinkThreshold,
                  !conflictingScalars(incoming, live) {
            idMap[incoming.id] = live.id
            if !dryRun { peopleStore.mergeRemote(incoming, into: live.id) }
            report.add(.personMerged(work: incoming.id, live: live.id))
        } else if let (live, score) = peopleStore.bestFuzzyMatch(for: incoming),
                  score >= PeopleStore.possibleMatchThreshold {
            // 0.6–0.85 → suggestion, exactly like ingestExtraction.
            if !dryRun { peopleStore.enqueueRemoteMergeSuggestion(incoming, possible: live, score: score, device: device) }
            report.add(.personSuggested(work: incoming.id, possible: live.id))
        } else {
            idMap[incoming.id] = incoming.id
            if !dryRun { peopleStore.addRemotePerson(incoming) }              // new person, work-origin
            report.add(.personCreated(incoming.id))
        }
    }
    return idMap
}
```

New `PeopleStore` methods to add (thin wrappers over existing internals):

- `bestStrongMatch(for:) -> Person?` — exposes the `matchIndex` precedence
  (cid → email → phone → exact name) for a full `Person` (today `matchIndex`
  takes a `PersonImport`; add an overload).
- `bestFuzzyMatch(for:) -> (Person, Double)?` — the `NameSimilarity` loop from
  `ingestExtraction`.
- `mergeRemote(_ incoming: Person, into liveID: String)` — calls the
  union-by-id `mergeFields` (with the §4.2 memory/attachedNotes/photo fix),
  writes through `writePerson`.
- `addRemotePerson(_:)` — append + `writePerson` (preserves the incoming id so
  backlinks resolve).
- `enqueueRemoteMergeSuggestion(…)` — builds a `PersonSuggestion`
  (`matchedPersonID` = possible live id), reuses `writeSuggestion` + the
  `dismissedSignatures` guard so a dismissed remote merge never re-suggests.

### 7.5 Atomic write helper

All writes reuse the codebase convention (`data.write(to:options:.atomic)`) and,
for files under the vault that iCloud watches, `MeetingStore.coordinatedWrite`.
The ledger:

```swift
extension ImportLedger {
    func save(at stagingRoot: URL) {
        let url = stagingRoot.appendingPathComponent(".import-ledger.json")
        let env = SchemaEnvelope(version: schemaVersion, data: self)
        guard let data = try? SharedCoders.encoder(pretty: true, sorted: true).encode(env) else { return }
        try? FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)        // atomic rename ⇒ crash-safe
    }
    static func load(at stagingRoot: URL) -> ImportLedger {
        let url = stagingRoot.appendingPathComponent(".import-ledger.json")
        guard let d = try? Data(contentsOf: url),
              let l: ImportLedger = try? SchemaEnvelope.decode(ImportLedger.self, from: d,
                    currentVersion: 1, decoder: SharedCoders.decoder()) else { return ImportLedger() }
        return l
    }
}
```

### 7.6 Hooks (boot, timer, Settings)

- **Boot:** in `MeetingScribeApp.startServices()` *background phase*
  (`Task.detached(priority: .utility)`), call
  `await RemoteVaultIngestor.shared.runAllPending()` *after* the meeting index +
  people store have hydrated. Gate behind a Settings flag
  (`AppSettings.shared.remoteImportEnabled`, default off until configured).
- **Timer:** a `Timer.publish(every: interval)` (default 7200s) on the
  `@MainActor`, mirroring the Calendar refresh timer pattern; each tick calls
  `runAllPending()`. Skips if `isRunning`.
- **Settings:** `RemoteImportSettingsView` with: device list (read from
  `_remote/*` subdirs), "Import work data now" (calls `run(dryRun:false)`),
  "Preview import…" (calls `plan` → presents `IngestPlan`), a "Review before
  merge" toggle, an "Import schedule" picker, and a **Conflicts** section listing
  `conflicts` (quarantined items) with Keep-Hub / Import-as-New actions.

### 7.7 Review-before-merge mode

`plan(device:)` produces an `IngestPlan` (list of `IngestAction` with
human-readable descriptions and counts) **without writing anything**. The UI
renders it like a diff ("12 new meetings, 4 people auto-merged, 2 people need
review, 1 conflict"). The user approves → `run(dryRun:false)` re-uses the same
classification (deterministic) and applies. This mirrors `PersonSuggestion`'s
confirm/dismiss model but at batch granularity.

---

## 8. Safety / non-clobber guarantees (invariants)

These are enforced by construction and should each have a test:

1. **Never delete a live record.** The ingestor has *no* delete path. Deletions
   on the work device do **not** propagate (see §10 — one-way additive model).
2. **Never overwrite a non-empty hub field.** Scalar merges are fill-empty-only;
   collection merges are unions; user-authored `notes.md` is append-only.
3. **Conflicts go to quarantine, never in-place.** Same-id-different-origin
   meetings and demoted fuzzy people land in
   `<vault>/_remote/_conflicts/<device>/…` + a `conflicts` entry for review.
4. **Idempotent.** Re-running with unchanged staging is a pure no-op (ledger hash
   match) — and even with a wiped ledger, the union/fill-empty merges converge to
   the same state (no duplication, given the §4.2 union-by-id fix).
5. **Dry-run / report mode.** `plan()` and `run(dryRun:true)` write nothing and
   produce a full `IngestReport`.
6. **Reversible.** Every applied action is logged in the ledger with the live
   path + a pre-merge snapshot of any *modified* live record (store a
   `.before.json` in `_remote/_undo/<runID>/` for merged records). An "Undo last
   import" reverses additive merges and removes purely-created records. (Audio is
   removed only if it was newly copied — tracked in the ledger.)
7. **Staging is read-only to the ingestor's outputs.** The ingestor reads from
   `_remote/<device>/…` and writes only to the live vault + ledger + quarantine.
   It never edits the staged source files (transport owns those), so a re-sync
   can't be corrupted by us.

---

## 9. Step-by-step build instructions for Claude Code

Ordered, copy-pasteable. Each step compiles; commit between steps.

1. **Add the device id setting.**
   `Sources/MeetingScribe/Models/Settings.swift`: add
   `var remoteImportEnabled: Bool`, `var remoteImportIntervalSeconds: Double`
   (default 7200), `var remoteImportReviewFirst: Bool` (UserDefaults-backed like
   the existing keys).

2. **Ledger model.** Create
   `Sources/MeetingScribe/Sync/ImportLedger.swift` with `ImportLedger`,
   `DeviceState`, `Record`, `SourceDevice`, `namespacedKey`, and the
   `load`/`save` from §7.5. `SchemaEnvelope`-wrapped, version 1.

3. **Hashing + plan models.** Create
   `Sources/MeetingScribe/Sync/IngestHashing.swift`
   (`CryptoKit.SHA256` digest over canonical JSON + over a meeting dir's file
   set) and `Sources/MeetingScribe/Sync/IngestPlan.swift`
   (`IngestAction` enum, `IngestReport`, `IngestConflict`, `StagingScan`,
   `StagedPerson` / `StagedMeeting`).

4. **Scanner (off-main).** Create
   `Sources/MeetingScribe/Sync/IngestScanner.swift` — a `nonisolated` enum that
   walks `_remote/<device>/` (reuse the depth-limited walk pattern from
   `MeetingStore.enumerateMeetingDirectories`), decodes each record via
   `SchemaEnvelope.decode`, and returns a `StagingScan` with content hashes.

5. **Extend `PeopleStore`** (`Sources/MeetingScribe/People/PeopleStore.swift`):
   add `bestStrongMatch(for: Person)`, `bestFuzzyMatch(for: Person)`,
   `mergeRemote(_:into:)`, `addRemotePerson(_:)`,
   `enqueueRemoteMergeSuggestion(…)`, and a `forceCacheWrite()` (extract the
   existing immediate-cache-write block from `deduplicate()` into a reusable
   method). **Also fix** `mergeFields` to union `memories` / `attachedNotes` /
   `photoRelativePaths` by id (use the `unionByID` helper) so re-imports + local
   dedup stop duplicating.

6. **The coordinator.** Create
   `Sources/MeetingScribe/Sync/RemoteVaultIngestor.swift` per §7.2–§7.4 with
   `plan`, `run`, `runAllPending`, `classifyMeeting`, `copyMeetingTree`,
   `additivelyRefresh`, `ingestEncounters`, `ingestActionItems`, `ingestTags`,
   `quarantine`, and undo-snapshot writing. Inject the four stores
   (default to `MeetingManager`'s shared instances; allow override for tests).

7. **Action-item ingest** uses `ActionItemStore.mergeExternal`
   (`source: "remote:<device>"`) for items and `upsertProject` / `createLabel` /
   `createSection` / `createInitiative` for the sub-aggregates, keyed by id with
   fill-empty merges. **Tags** ingest unions `TagStore.Persisted` and applies via
   `setTags`.

8. **Wire boot + timer.** In
   `Sources/MeetingScribe/MeetingScribeApp.swift` `startServices()` background
   phase, after stores hydrate, add (gated on `remoteImportEnabled`):
   `Task.detached(priority: .utility) { await RemoteVaultIngestor.shared.runAllPending() }`.
   Add a `@MainActor` timer (mirror the Calendar 60s timer) firing every
   `remoteImportIntervalSeconds`.

9. **Settings UI.** Create
   `Sources/MeetingScribe/UI/Settings/RemoteImportSettingsView.swift`: enable
   toggle, device list, "Preview import…" (→ `plan`), "Import work data now"
   (→ `run`), schedule picker, and a Conflicts list bound to
   `ingestor.conflicts`. Add it to the Settings tab navigation.

10. **Tests** under `Tests/MeetingScribeTests/` (follow `MeetingStoreTests`
    conventions — temp `storageDir` via `UserDefaults.standard.set(tempRoot.path,
    forKey: "storageDir")`, `@testable import MeetingScribe`):
    - `RemoteVaultIngestorTests.swift`:
      - `testNewMeetingIsCopiedAndIndexed`
      - `testReimportUnchangedIsNoOp` (ledger hash skip)
      - `testPersonExactEmailAutoMerges_unionsCollections_fillsEmptyScalars`
      - `testPersonFuzzyMidScoreProducesSuggestion`
      - `testMemoriesAreUnionedByIDOnReimport` (no duplication)
      - `testActionItemsDedupBySourceExternalID`
      - `testTagsAreUnionedNotReplaced`
      - `testPersonalMeetingIDCollisionIsQuarantinedNotOverwritten`
      - `testNotesMdIsAppendedNeverClobbered`
      - `testDryRunWritesNothing`
    - `ImportLedgerTests.swift`: round-trip + schema-envelope tolerance.

11. **Verify.**
    ```
    swift build -c release
    swift test
    ```
    Both must pass (warnings OK per CLAUDE.md; errors block). Then ask the user
    whether to push (per CLAUDE.md workflow).

---

## 10. Edge cases & failure modes

- **Clock skew between devices.** Never trust wall-clock to decide "who wins" —
  the model is *hub-authoritative + additive*, so timestamps only feed
  `min(createdAt)` / `max(lastInteractionAt)` / `max(endDate)` unions. A
  fast/slow work clock can't cause a hub field to be overwritten. `importedAt` in
  the ledger uses the *hub* clock.

- **Partial transfers mid-ingest.** Two guards:
  (a) The transport should write a top-level `_remote/<device>/_manifest.json`
  (`{ complete: true, snapshotHash, fileCount }`) as the *last* file. The
  ingestor refuses to run a device whose manifest is missing/`complete:false`, or
  whose `snapshotHash` matches `ledger.lastManifestHash` (already imported). If
  no manifest is provided by the transport, fall back to a *quiescence check*:
  skip if any file under the device root was modified in the last N seconds
  (still being written). (b) The ingestor processes in checkpointed batches and
  saves the ledger after each batch, so a crash resumes cleanly — already-applied
  records are skipped by hash.

- **Slug collisions** (different meetings, same `yyyy-MM-dd-HHmm-Title`): the
  *id* disambiguates; the *folder* gets a `-2`/`-3` suffix via the same logic
  `MeetingStore.moveMeeting` already uses. No data merged across them.

- **Schema-version drift between devices.** `SchemaEnvelope.decode` already
  handles legacy + versioned shapes and runs a `migrate` closure when
  `decodedVersion < currentVersion`. If the **work device is newer** (higher
  schemaVersion than the hub knows), `decode` returns the payload as-is via
  tolerant Codable (post-v1 fields are optional-with-default everywhere). The
  ingestor additionally records the staged `schemaVersion` in the ledger and, if
  it exceeds the hub's `currentVersion`, **routes the item to quarantine with a
  "hub app is older — update to import" message** rather than risk a lossy
  down-convert. (Concretely: compare against `MeetingStore.meetingSchemaVersion`
  / `PeopleStore.personSchemaVersion`.)

- **Deletion semantics (one-way / additive).** Deletes on the work device are
  intentionally **not** propagated — this is a *backup*, and silently deleting a
  hub record because the work side removed it would violate invariant #1 and
  could lose data the user wanted kept. If true deletion mirroring is ever
  desired, it must be an explicit, separate, opt-in "mirror deletions" mode with
  its own confirmation — out of scope here. (A future "tombstone" file in
  staging could feed a review queue, never an automatic delete.)

- **Re-keyed id fan-out.** When a meeting/person is re-keyed (conflict) or a work
  person is merged into a live person, *every* reference must follow: encounters'
  `personID`, action items' `meetingID` / `ownerPersonID`, projects' `meetingIDs`,
  `tags.json` `meetingTags`, and `Person.meetingMentions`. The ingestor builds
  the full `workID → liveID` map first, then does a single repoint pass before
  the final cache rebuild — mirroring how `deduplicate()` repoints relationships
  and encounters today.

- **Person false-merge risk.** Fuzzy name ≥ 0.85 with *conflicting* strong fields
  (different emails AND different company) is demoted to a `PersonSuggestion`
  instead of auto-merging, so two genuinely-different "John Smith"s on work vs
  personal don't collapse.

- **Concurrent live edits during ingest.** Because all store mutations run on the
  `@MainActor` (serialized with the UI), the ingestor can't race a user edit
  mid-write. The off-main work is strictly *read+hash* (pure file I/O on staging);
  every *live* mutation hops back to the `@MainActor` through the stores.

- **Empty / corrupt staged file.** `SchemaEnvelope.decode` returns `nil`/throws;
  the scanner skips the item, logs via `AppLog`/`ErrorReporter`, and records a
  `status: "skipped"` ledger entry so it's visible in the report (and retried if
  the bytes change on the next sync).
