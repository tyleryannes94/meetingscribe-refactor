# E3 — MCP Tool Implementation Audit (Phase 4 People Tools)

**Lens:** Are the 6 new Phase 4 MCP tools correctly typed, handling errors, reading from the right data sources?

---

## 1. Full audit through this lens

### E3-01 · `tool_listEncounters` — `loadEncounters` exists; flat-directory scan

`loadEncounters(forPersonID:)` is at `main.swift:1498`. It scans the flat `<storageDir>/encounters/` directory, reads every `.json` file, unwraps the envelope via `obj["data"]` if present, then filters by `personID`. This is correct for MCP-written and app-written files alike. However:

- **N+1 performance (minor for one person, critical in aggregate).** Every call to `loadEncounters` performs a full `contentsOfDirectory` scan plus a `Data(contentsOf:)` read for every encounter file in the vault. For `tool_listOverdueCheckIns` this is called once per person: with 100 people and 50 encounters each, that is 100 directory listings × 5,000 file reads. No caching, no index.
- **Return shape drops `mood`.** The description at `main.swift:884` says "mood" is returned. The row map at `main.swift:1533–1540` emits only `id`, `date`, `kind`, `notes`, `location`. No `mood` key. Encounters written by `QuickEncounterSheet` embed mood in `eventName` as a suffix (`" [mood:great]"`) rather than a separate key, but the MCP description still misleads callers.

### E3-02 · `tool_logEncounter` — Envelope key mismatch (data corruption)

**Critical bug.** `tool_logEncounter` at `main.swift:1570` writes:
```json
{ "version": 1, "data": { ... } }
```
`SchemaEnvelope` (defined in `VaultKit/SchemaEnvelope.swift:19`) uses `schemaVersion` as its Codable key:
```swift
public let schemaVersion: Int
```
`PeopleStore.loadEncounters()` at `PeopleStore.swift:415–417` calls `SchemaEnvelope.decode(Encounter.self, from: data, ...)`. The envelope decode attempt fails (no `schemaVersion` key), and the fallback tries to decode the top-level dict as a raw `Encounter` — which also fails because the top-level dict has `version` and `data` keys rather than `id`, `eventName`, `date`, etc.

**Result:** Any encounter written by the MCP via `log_encounter` is silently discarded when the app next loads its `encounters/` directory. The encounter appears correctly to the MCP (because `loadEncounters` in `main.swift:1508` uses a loose `obj["data"]` unwrap that handles `"version"` and `"schemaVersion"` interchangeably), so the round-trip looks correct in Claude but the encounter is invisible to the app.

**Fix:** Change `main.swift:1570` from:
```swift
let envelope: [String: Any] = ["version": 1, "data": enc]
```
to:
```swift
let envelope: [String: Any] = ["schemaVersion": 1, "data": enc]
```

This single-character fix aligns with the `SchemaEnvelope` contract used everywhere else in the MCP (`main.swift:309`, `main.swift:267`).

Additionally, `tool_logEncounter` does not write `createdAt` in a format the app's `SharedCoders.decoder()` can parse (the decoder uses `.iso8601` strategy), but since the `Encounter` struct decodes `createdAt` via Codable's synthesized path this should be fine as long as `iso()` produces ISO 8601 strings — verify `func iso()` produces the right format.

### E3-03 · `tool_getCheckInStatus` — `p.lastInteractionAt` and `p.checkInCadenceDays` accessible

`PersonDTO` at `SharedModels.swift:201–209` declares both `lastInteractionAt: Date?` and `checkInCadenceDays: Int?`. The Codable `init(from:)` at line 252 decodes them tolerantly. Both fields are accessible. No issue.

One subtle bug: `tool_getCheckInStatus` at `main.swift:1619–1621` uses:
```swift
let lastDate = lastEncDate ?? p.lastInteractionAt ?? p.createdAt
```
If a person has no encounters and `lastInteractionAt` is nil, `p.createdAt` defaults to `Date(timeIntervalSince1970: 0)` (epoch) for people loaded from older builds (SharedModels.swift:246). This produces `daysSince = ~56 years`, flagging every legacy person as massively overdue. The `createdAt` fallback should instead be `Date()` (now) so a brand-new person starts with `daysSince = 0`.

### E3-04 · `tool_listOverdueCheckIns` — N+1 file I/O, all people scanned

`tool_listOverdueCheckIns` at `main.swift:1647`:
1. Calls `loadAllPeople()` — reads all `person.json` files in `people/` directory (O(n) person reads).
2. For each person with a typed relationship, calls `loadEncounters(forPersonID:)` — which performs a full `contentsOfDirectory` scan + reads every encounter file.

At 100 people × 50 encounters = 100 directory scans + up to 5,000 `Data(contentsOf:)` calls, all synchronous, on the main queue. On a spinning disk or a cold iCloud-synced vault this will timeout Claude's tool call (default MCP timeout is 30 s).

**Fix:** Load all encounters once, group into a `[String: [[String: Any]]]` by `personID`, then process each person against the pre-built map. This changes the complexity from O(n × m) to O(m) for the encounter phase.

### E3-05 · `tool_getCoachingContext` — `p.birthday` accessible; framework fallback confirmed

`PersonDTO.birthday: Date?` at `SharedModels.swift:200` is decoded tolerantly. The `p.birthday` access at `main.swift:1701` is valid.

The framework switch at `main.swift:1716–1720` confirms the known gap (also in BRIEFING-V2 §Critical gaps #8): `"friend"`, `"colleague"`, and `"acquaintance"` all fall through to `"Active listening and consistent follow-through"`. With 3 of 7 relationship types returning a meaningful framework and 3 returning a generic fallback, 43% of typed relationships receive no type-specific coaching guidance.

Additionally, the birthday countdown calculation at `main.swift:1704–1710` divides `timeIntervalSince` by `86400` (integer truncation) rather than using `Calendar.current.dateComponents`. On DST boundaries this can be off by ±1 day.

### E3-06 · `tool_attachNoteToPerson` — O(n) directory scan with a known faster path

`tool_attachNoteToPerson` at `main.swift:1726–1769` already has the person's `id` (and `displayName`) from the `resolvePerson()` result. Despite this, it iterates all subdirectories under `people/`, reads and parses every `person.json`, and looks for `stored["id"] == p.id`.

The person's directory name is deterministic: `personSlug(displayName:id:)` at `main.swift:296`. Since the function already has `p.displayName` and `p.id`, it can construct the path directly:

```swift
let slug = personSlug(displayName: p.displayName, id: p.id)
let personDir = storageDir.appendingPathComponent("people/\(slug)", isDirectory: true)
let jsonURL = personDir.appendingPathComponent("person.json")
```

This turns an O(n) scan into O(1). The current approach also has a correctness risk: if `displayName` changed since the `resolvePerson` call (concurrent edit from the app), the slug lookup would miss the file and silently succeed (returning `ok: true`) without actually writing the note.

### E3-07 · Schema consistency — `list_encounters` description vs return shape

The `list_encounters` tool description at `main.swift:884` advertises "mood" in the response. The implementation at `main.swift:1533–1540` does not emit a `mood` field. Callers that rely on the schema description to parse mood will always get nothing. Either:
- Add a `mood` field (parsed from the `[mood:xxx]` suffix in `eventName`), or  
- Remove "mood" from the description.

The `get_coaching_context` schema description (`main.swift:946`) mentions "health score" as a returned field, but the implementation never computes or returns one (`result` dict at `main.swift:1718–1729` has no `healthScore` key). The `healthScore` feature is behind `FeatureGate.ManagedFeature.healthScore` and the arc ring UI is unimplemented (per BRIEFING-V2 §Critical gaps #3).

### E3-08 · `PersonDTO` memberwise `init` missing Phase D fields

The manually-written memberwise `init` at `SharedModels.swift:267–285` does not include `relationshipType` or `checkInCadenceDays`. These two fields have no default on the struct — they are `let` properties. This means any call site that uses the memberwise init (e.g., tests, mocks, migration shims) will hard-fail to compile if it tries to create a `PersonDTO` and the initializer is the only available path. In practice today this compiles because the synthesized init is NOT generated (the explicit `init(from:)` is present), but any new test fixture calling `PersonDTO(id:displayName:...)` will silently produce a person with `relationshipType = nil` and `checkInCadenceDays = nil` — making test coverage of the Phase 4 tools unreliable.

---

## 2. Existing-plan items I rank highest

1. **E3-02 envelope key mismatch** — highest priority: every `log_encounter` call silently corrupts the vault from the app's perspective. One word fix.
2. **E3-04 N+1 in `list_overdue_check_ins`** — impacts real-world performance at 50+ people; already noted as a known perf risk.
3. **Known gap #8 (framework fallback)** — friend/colleague/acquaintance get generic coaching; 3 of 7 types covered.
4. **PersonDTO memberwise init gap** (BRIEFING-V2 §Critical gaps #7) — blocks reliable unit testing of all Phase 4 tools.

---

## 3. Net-new recommendations

### E3-N1 · Fix `log_encounter` envelope key: `"version"` → `"schemaVersion"` *(S · Critical)*
**What:** Change `main.swift:1570` to write `"schemaVersion": 1` instead of `"version": 1`.  
**Why:** Without this fix, every MCP-logged encounter is silently dropped by the app on next load. The MCP appears to work (it reads its own files fine) while the app state diverges.  
**User value:** MCP-created encounters actually appear in PersonDetailView and update `lastInteractionAt`.  
**Effort:** S (one word).  
**Impact:** Critical — data integrity.  
**Deps:** None.

### E3-N2 · Pre-build encounters index in `list_overdue_check_ins` to eliminate N+1 *(S · High)*
**What:** In `tool_listOverdueCheckIns`, call `loadAllEncounters()` once (scan `encounters/` once, group by `personID` into a dict), then replace each `loadEncounters(forPersonID:)` call with a dict lookup.  
**Why:** Current O(n × m) I/O blocks for >50 people. A single scan is O(m).  
**User value:** Tool returns in <1 s even with 500 encounters; no Claude tool timeout.  
**Effort:** S (add one helper function, thread dict through loop).  
**Impact:** High — reliability at scale.  
**Deps:** None.

### E3-N3 · Direct slug-path lookup in `tool_attachNoteToPerson` *(S · Medium)*
**What:** Replace the O(n) directory scan with `personSlug(displayName: p.displayName, id: p.id)` to construct the target path directly.  
**Why:** Current approach reads every person file even though the path is computable. Also avoids the silent-success-on-miss bug.  
**User value:** Faster note attachment; eliminates data loss on concurrent rename.  
**Effort:** S (3 lines).  
**Impact:** Medium.  
**Deps:** None.

### E3-N4 · Add `mood` field to `log_encounter` / `list_encounters` *(S · Medium)*
**What:** Accept `mood` as an optional string in `log_encounter` inputSchema, write it as a top-level key in the encounter dict, and emit it in `list_encounters` row output. Parse `[mood:xxx]` suffix from legacy encounters for backward compatibility.  
**Why:** Mood is central to relationship health coaching. The description promises it; the implementation doesn't deliver it.  
**User value:** Claude can query "when did Tyler last have a tense conversation with Alex" — enabling proactive sentiment-based coaching.  
**Effort:** S.  
**Impact:** Medium — enables coaching features that already exist in Phase 3 content.  
**Deps:** E3-N1 (same encounter write path).

### E3-N5 · Fix `createdAt` fallback in `getCheckInStatus` / `listOverdueCheckIns` *(S · Medium)*
**What:** Replace `?? p.createdAt` fallback with `?? Date()` (or better: `?? p.updatedAt ?? Date()`). Document why `createdAt` epoch-zero is wrong.  
**Why:** Legacy persons have `createdAt = epoch` → `daysSince ≈ 20,000` → every legacy person shows as massively overdue.  
**User value:** Correct overdue status for all existing users' contacts.  
**Effort:** S.  
**Impact:** Medium — correctness.  
**Deps:** None.

### E3-N6 · Extend framework switch to cover `friend`, `colleague`, `acquaintance` *(S · Medium)*
**What:** In `tool_getCoachingContext`, add cases for the three uncovered relationship types:
- `"friend"` → "Love Languages — prioritize quality time and proactive outreach"
- `"colleague"` → "Radical Candor — care personally, challenge directly; keep feedback timely"
- `"acquaintance"` → "Weak Ties theory — low-frequency but memorable touchpoints; lead with their interests"  
**Why:** 43% of typed relationships get a generic fallback. This is already flagged in BRIEFING-V2 critical gaps #8 but no concrete replacement strings were proposed.  
**User value:** Meaningful per-type coaching for every relationship category.  
**Effort:** S (6 lines).  
**Impact:** Medium.  
**Deps:** None.

### E3-N7 · Remove `healthScore` from `get_coaching_context` description until implemented *(S · Low)*
**What:** Strip "health score" from the `get_coaching_context` tool description at `main.swift:946` until `FeatureGate.ManagedFeature.healthScore` and the arc ring UI exist.  
**Why:** Claude will try to surface a field that doesn't exist, producing confusing nil-like output or hallucinated values.  
**User value:** Honest tool contract.  
**Effort:** S.  
**Impact:** Low (cosmetic but correctness).  
**Deps:** None.

### E3-N8 · Add `PersonDTO` memberwise init params for `relationshipType` and `checkInCadenceDays` *(S · Medium)*
**What:** Extend the `init(id:displayName:...)` at `SharedModels.swift:267` to accept `relationshipType: String? = nil, checkInCadenceDays: Int? = nil` and assign them in the body.  
**Why:** Current memberwise init silently zeroes out Phase D fields, making test fixtures unreliable.  
**User value:** Enables unit tests for all Phase 4 MCP tools with typed-relationship fixtures.  
**Effort:** S.  
**Impact:** Medium — test coverage quality.  
**Deps:** None.

### E3-N9 · Encounters sub-directory per person (long-term) *(M · High)*
**What:** Store encounters at `<storageDir>/encounters/<personID>/<encID>.json` rather than a flat directory. `loadEncounters(forPersonID:)` becomes a targeted directory read with no filtering needed.  
**Why:** The flat layout works at <500 encounters but at 1,000+ (a power user's 3-year vault), every encounter tool call scans the whole directory.  
**User value:** Sub-millisecond encounter reads for any person regardless of vault size.  
**Effort:** M (requires migration for existing vaults, update both PeopleStore and MCP).  
**Impact:** High — scales the people graph to power users.  
**Deps:** E3-N1 should land first so the correct envelope format is baked in.

### E3-N10 · Add `DarwinNotifier.post(vaultChanged)` after `tool_logEncounter` succeeds *(S · Medium)*
**What:** Call `signalVaultChanged()` (already defined at `main.swift:319`) at the end of `tool_logEncounter` after the file is written.  
**Why:** The comment at `main.swift:1578` says "The running app will detect the new encounter file via its vault watcher" — but without a Darwin notification the watcher may not fire immediately on some macOS versions.  
**User value:** PersonDetailView refreshes immediately after MCP logs an encounter, avoiding stale state.  
**Effort:** S (one line).  
**Impact:** Medium.  
**Deps:** E3-N1.

---

## 4. Top 3 picks + single highest priority

**Top 3:**
1. **E3-N1** — `"version"` → `"schemaVersion"` one-word fix that restores data integrity for every `log_encounter` call.
2. **E3-N2** — Pre-build encounters index eliminates O(n×m) I/O blocking in `list_overdue_check_ins`.
3. **E3-N5** — Fix `createdAt` epoch-zero fallback so existing users don't see every legacy contact as massively overdue.

**Single highest priority: E3-N1.** The envelope key mismatch is a silent data corruption bug — the MCP appears to succeed, the app silently drops the file, and no error is ever surfaced. It takes one word to fix and blocks every other encounter feature from being useful.
