# E5 — Testing Strategy, CI Coverage, and People Module Gaps

**Lens:** Swift Testing & CI expert — coverage of the People module and MCP tools; what to test for relationship-type data model changes; CI setup and gaps; testing strategy for audio pipeline and SQLite migrations.

---

## 1. Current test inventory — what exists

Eleven test files in `Tests/MeetingScribeTests/`. Zero test files for `VaultKit` alone, zero for the `MeetingScribeMCP` target, zero for `ScribeCore`.

| File | Tests | What they cover |
|------|-------|-----------------|
| `AudioCountersTests.swift` | 4 | Lock-protected counter accumulation, TSan-targeted concurrent write safety |
| `ActionItemExtractorTests.swift` | 6 | Regex extraction from summary.md, owner matching, date parsing |
| `MeetingManagerTests.swift` | 3 | `MeetingManager.init()` state, independent store instances |
| `MeetingPipelineControllerTests.swift` | 6 | `needsBatchRepair` pure-function gate (ENG-A), `transcribingIDs` race guard |
| `MeetingStoreTests.swift` | 4 | Index round-trip, O(1) directory cache, legacy JSON shape, orphaned chunk cleanup |
| `VaultMigrationManagerTests.swift` | 3 | Full/partial migration, flag correctness, unparseable JSON gate |
| `LiveTranscriberTests.swift` | 4 | Timestamp formatting, stderr summarizer, `flush()` drain under missing binary |
| `TranscriptParserTests.swift` | 5 | Structured `Speaker [ts]:` format, hour timestamps, bold-speaker fallback |
| `WhisperRunnerTests.swift` | 6 | JSON parse (segments + plainText), malformed input, SHA256 checksum (ENG-D) |
| `VaultCacheTests.swift` | 6 | Round-trip, missing key, version mismatch, TTL expiry, corruption, invalidation |
| `PipelineIntegrationTests.swift` | 2 | E2E `finalize()` with live transcript and with empty transcript |
| `GoldenAudioTranscriptionTests.swift` | 1 | Real whisper-cli WER regression (skips when binary absent) |
| `PlaceholderTests.swift` | 3 | `JSONValue` round-trip, `SchemaEnvelope` version gate, legacy raw payload |

**Total: ~53 test methods.** No discovered test failures at time of audit; `swift test` passes on the repo HEAD.

---

## 2. CI configuration

### `ci.yml` (every push/PR to main)
- Runner: `macos-15` (Swift 6.x / Xcode 16). **No `--sanitize=thread` flag.** The `AudioCountersTests.swift` comment says "running under TSan catches the races" but CI never actually passes the sanitizer flag (`swift test --sanitize=thread`). The TSan coverage is developer-only today.
- Steps: (1) cross-tree duplication ratchet (`check-cross-tree-dupes.sh`), (2) `swift build -c release`, (3) `swift test` (no flags).
- **No code coverage measurement** (`--enable-code-coverage` is absent).
- **No `--filter` to skip slow or binary-dependent tests** — `GoldenAudioTranscriptionTests` skips gracefully when whisper is absent, which is correct.
- Missing: the CI runner is `macos-15` but `release.yml`'s test job pins `macos-14`. The two jobs may diverge silently if Apple drops `macos-14` runners.

### `release.yml` (tag pushes)
- Runs `swift test` on `macos-14` before building. No sanitizers. No coverage. The runner version mismatch with CI is low-risk today but worth normalizing.

### `Package.swift` test target
- Single test target `MeetingScribeTests` depends on `["MeetingScribe", "VaultKit"]` (`Package.swift:77–86`). No separate `VaultKitTests` target (a Foundation-only library is the easiest thing to test on Linux too — missed opportunity).
- `MeetingScribeMCP` and `ScribeCore` have **no test targets at all**.
- `exclude: ["Fixtures"]` correctly keeps golden-audio clips out of the build graph.
- `StrictConcurrency=targeted` on all targets — warnings today, errors in Swift 6 strict mode; CI will catch them before that flip.

---

## 3. Critical coverage gaps — what has zero test coverage

### 3.1 People module — complete zero

**`NameSimilarity`** (`Sources/MeetingScribe/People/NameSimilarity.swift`) is a 80-line pure algorithmic module — Jaro-Winkler + token-level scoring — with two public static methods (`score`, `jaroWinkler`) and zero stateful dependencies. It drives the auto-link threshold (`PeopleStore.autoLinkThreshold = 0.85`, line 34) and the possible-match threshold (`0.6`, line 35). Tweaking these thresholds or the algorithm will silently change whether "Jane" auto-links to "Jane Smith" or gets flagged as a suggestion. There is not a single test for this module.

**`PeopleStore`** (`Sources/MeetingScribe/People/PeopleStore.swift`) — 1,359 lines, `@MainActor` singleton. The methods most worth testing are the pure or near-pure ones that don't need AppKit or the filesystem:
- `buildListSnapshot(_:)` (line 120) — pure, sorts and truncates to 200 rows.
- `rebuildPersonIndex()` (line 49) — pure dict-from-array, dedupe behavior matters.
- `rebuildEncounterCounts()` (line 53) — pure accumulation.
- `relevanceScore(encounterCount:)` on `Person` (line 228) — pure math, drives ghost-contact filtering.
- `cadenceSeconds(for:)` in `ReconnectView` (line 95) — the reconnect nudge's median-gap inference is a pure function on `[Date]` with a 7–120 day clamp. It lives in a View struct, not a store, but it is entirely pure.

**`Encounter` round-trip** — `Encounter.swift` has no test. Adding an encounter, serializing to disk, and re-reading it is untested. The `meetingID` and `voiceNoteID` optional cross-references are especially fragile because the app silently drops unrecognized keys on read.

### 3.2 Relationship data model — zero coverage

`Relationship` in `Person.swift:51–64` is a struct with a freeform `label: String`. The audit's primary focus area — `RelationshipType` as a typed enum — **does not exist yet in the codebase** (confirmed by grep; P1 audit finding `P1-relationship-types.md:11–13`). When it is added, round-trip encode/decode tests are mandatory from day one, because `Person.init(from:)` silently swallows decode errors (`try?`) — a misspelled raw value would produce an empty/default and no error.

### 3.3 MCP tools — complete zero

`Sources/MeetingScribeMCP/main.swift` is 1,526 lines with 17 tool implementations. None of them have tests. The testable surface without a real vault on disk is larger than it looks:

- **`resolveInsideVault(_:)`** (line 36) — a security-critical path-containment check. Tests: a path inside the vault returns non-nil; a path with `../` escaping the vault returns nil; a sibling directory like `<vault>-evil` returns nil.
- **`normalizeISO8601(_:)`** (line 238) — date normalization from various input shapes. Pure function; easy to test.
- **`tagNames(forMeetingID:seriesID:tags:)`** (line 173) — pure lookup logic on a `TagFileDTO`.
- **`personSlug(displayName:id:)`** (line 296) — mirrors `Person.slug`; if they diverge, directories stop being found.
- **`scanDiskForMeetings()`** and **`readMeetingJSON(at:)`** (lines 76–108) — can be tested with a temp directory fixture.
- **`tool_listMeetings`**, **`tool_getMeeting`**, etc. — JSON-RPC response shape assertions are the most valuable: does the response include the expected keys? Does it handle a missing meeting id gracefully?

The MCP server lives in a separate executable target. Adding a `MeetingScribeMCPTests` target that links `MeetingScribeMCP` is not straightforward because the executable exports nothing — all functions are file-scope. The right pattern is to extract the pure helpers into a `MeetingScribeMCPCore` library target (or into `VaultKit`), then test that. The JSON-RPC dispatch loop itself can be tested by feeding stdin/stdout-captured calls into a subprocess.

### 3.4 SQLite / FTS5 — zero unit coverage

`SecondBrainDB.swift` drives the FTS5 search and embedding store. The `upsertPerson`, `searchAll`, `upsertVaultContent`, `upsertEmbedding`, `cosine`-based hybrid ranking — none are tested. The DB file is in `Application Support`, which makes test isolation non-trivial but solvable via the same `UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")` pattern already used in `MeetingStoreTests`.

### 3.5 Transcript tail truncation fix (ENG-A)

`MeetingPipelineControllerTests.swift` tests the pure `needsBatchRepair` gate thoroughly (5 cases, lines 62–105). `PipelineIntegrationTests.swift` drives the real `finalize()` path and asserts `transcript.md` lands in the correct folder. The one remaining gap is that neither test asserts that `flush()` is actually called *before* `renderMarkdown()` inside `finalize()` — the sequencing that was the root of the original truncation bug. This cannot be caught by a pure unit test without mocking `LiveTranscriber`; an approach is to inject a spy `LiveTranscriber` and assert `flush()` was called before the file write. As a minimum, the existing integration test (`testFinalizePersistsTranscriptToReferencedFolder`) covers the outcome even if not the call sequence.

---

## 4. Existing plan items — endorsements from a testing lens

The following items from the master plans most directly create or require test work:

1. **ENG-A (transcript tail truncation)** — existing `MeetingPipelineControllerTests` + `LiveTranscriberTests` + `PipelineIntegrationTests` provide good coverage for the gate logic and the outcome. The `flush()`-before-`renderMarkdown` sequence is the one gap noted above. Endorse as well-covered for a solo developer; the integration test is the regression guard.

2. **VaultKit consolidation** (orphaned `SecondBrainCore`/`MeetingScribeShared` dead targets) — once deleted, run `swift test` to confirm the 3 test files that previously imported `MeetingScribeShared` still compile. This is a no-op today because `PlaceholderTests` and others already import `VaultKit`. Still worth a CI check in the PR.

3. **ARCH-1 CaptureKit de-dup** (4 files diverged across app↔daemon) — the existing CI `check-cross-tree-dupes.sh` ratchet is the right mechanism. Endorse it; do not remove it even as de-dup progresses.

4. **God-file decomposition** (PeopleStore 1,359 lines, MCP main.swift 1,526 lines) — extracting pure functions from both into testable units is the prerequisite for the zero-coverage gaps above.

---

## 5. NET-NEW recommendations

### E5-1 — `NameSimilarityTests`: 10 cases, high value, zero effort (S)

`NameSimilarity.swift` is 80 lines of pure deterministic logic used to gate auto-linking decisions. Add a test file with cases that pin the boundary behavior the thresholds depend on:

```
"Jane" vs "Jane Smith"    → score ≥ 0.85 (should auto-link)
"Jane" vs "John Smith"    → score < 0.60 (should not suggest)
"Sara" vs "Sarah"         → score ≥ 0.85 (Winkler prefix boost)
"" vs "Jane"              → score == 0.0 (guard)
"Alex" vs "Alexander"     → some known value (regression pin)
```

If the Jaro-Winkler implementation or the thresholds change, these tests fail immediately instead of silently making "Jane" stop linking to "Jane Smith" in production. File: `Tests/MeetingScribeTests/NameSimilarityTests.swift`. Effort: **S** (hours).

### E5-2 — `PeopleStoreTests`: pure-function coverage for the store's algorithmic core (S-M)

Already cited in `PipelineIntegrationTests.swift:6` as its own label ("E5-2"), but the actual file does not exist. Create `Tests/MeetingScribeTests/PeopleStoreTests.swift` testing:

- `Person.relevanceScore(encounterCount:)` — boundary: zero everything → 0.0; add a memory → score increases by 3; relationships add 5 per entry.
- `Person.isGhost(encounterCount:)` — a contact with no signal is a ghost; one with a memory is not.
- `PeopleStore.buildListSnapshot(_:)` — with 250 people, snapshot is capped at 200 and sorted by `lastInteractionAt`.
- `ReconnectView.cadenceSeconds(for:)` — extract it to a `@testable` free function or an extension on `Person`. With 3 encounters at 7-day gaps → inferred cadence ≈ 10.5 days; with 2 encounters → falls back to 30 days.

The `@MainActor` singleton `PeopleStore.shared` is a testing hazard. Use the same temp-dir isolation pattern already proven in `MeetingStoreTests`. Effort: **S–M** (a day).

### E5-3 — `MCPVaultTests`: security-critical and pure-function MCP helpers (S)

Without restructuring the executable, create `Tests/MeetingScribeTests/MCPVaultTests.swift` that links the **app target** (already in the test target) and tests the helpers that are worth extracting or can be tested at the file level with `@testable import`:

```swift
// resolveInsideVault — path-containment guard
let base = URL(fileURLWithPath: "/tmp/vault")
XCTAssertNotNil(resolveInsideVault(base.appendingPathComponent("meetings/foo")))
XCTAssertNil(resolveInsideVault(base.appendingPathComponent("../../etc/passwd")))

// normalizeISO8601
XCTAssertNotNil(normalizeISO8601("2026-06-01"))
XCTAssertNotNil(normalizeISO8601("2026-06-01T12:00:00Z"))
XCTAssertNil(normalizeISO8601("not-a-date"))

// personSlug — must match Person.slug exactly
let slug = personSlug(displayName: "Jane Smith", id: "abc12345def")
XCTAssertEqual(slug, "Jane Smith-abc12345")
```

The `resolveInsideVault` test is the most important: a bug here means an MCP write tool can path-traverse outside the vault. Effort: **S** (hours).

### E5-4 — `EncounterRoundTripTests`: serialize/deserialize with all optional fields (S)

`Encounter` has `meetingID`, `voiceNoteID`, `eventTagID` as optionals decoded with `try?`. Add a test that:
1. Creates an `Encounter` with all fields populated.
2. Encodes to JSON via `SharedCoders`.
3. Decodes back.
4. Asserts all fields match, including the optional cross-references.

Also test the "older build" path: an `Encounter` JSON without `voiceNoteID` (field absent) must decode without error. This is the pattern `MeetingStoreTests.testReadsLegacyRawMeetingJSON` already uses — apply the same pattern here. Effort: **S** (hours).

### E5-5 — `RelationshipTypeTests`: add from day one when the enum lands (S, gated on P1 work)

`Person.swift:51–64` has a freeform `label: String` on `Relationship`. When a typed `RelationshipType` enum is added (P1's highest-priority recommendation), write these tests before writing any application code:

```swift
// Round-trip all cases via Codable
for type in RelationshipType.allCases {
    let encoded = try JSONEncoder().encode(type)
    let decoded = try JSONDecoder().decode(RelationshipType.self, from: encoded)
    XCTAssertEqual(type, decoded)
}

// Unknown future raw value falls back to .other (not a crash)
let futureJSON = Data("\"something_new_2027\"".utf8)
let decoded = try? JSONDecoder().decode(RelationshipType.self, from: futureJSON)
XCTAssertEqual(decoded, .other)

// Per-type default cadence is sane
XCTAssertLessThanOrEqual(RelationshipType.partner.defaultCadenceDays, 3)
XCTAssertGreaterThanOrEqual(RelationshipType.colleague.defaultCadenceDays, 7)
```

The `Person.init(from:)` tolerant-decoder pattern uses `try?` everywhere — which means a RelationshipType raw-value typo or a missing `.other` fallback would silently strip all relationship records. These tests catch that before the model lands on disk. Effort: **S** (hours, must precede P1 implementation).

### E5-6 — Enable TSan in CI for the audio concurrency tests (S)

`AudioCountersTests.testConcurrentMutationDoesNotCrashOrLoseUpdates` was written specifically for Thread Sanitizer, but CI does not pass `--sanitize=thread`. Add a second `swift test` step:

```yaml
- name: Test (Thread Sanitizer)
  run: swift test --sanitize=thread --filter AudioCountersTests
  env:
    CI: "true"
```

Scoping to `--filter AudioCountersTests` keeps the TSan run fast (it only adds overhead on the concurrency test). This is the intended use of that test and currently represents zero real coverage in CI. Effort: **S** (one line in `ci.yml`).

### E5-7 — Add `--enable-code-coverage` and surface it as a PR comment (M)

Currently there is no code-coverage gate. Add to `ci.yml`:

```yaml
- name: Test with coverage
  run: swift test --enable-code-coverage
  
- name: Generate lcov report
  run: |
    xcrun llvm-cov export \
      .build/debug/MeetingScribePackageTests.xctest/Contents/MacOS/MeetingScribePackageTests \
      -instr-profile .build/debug/codecov/default.profdata \
      -format=lcov > coverage.lcov

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: coverage.lcov
```

For a solo developer, the goal isn't a coverage number gate but a **coverage diff**: "this PR added 200 lines and zero tests." Even a Codecov free-tier badge in the README makes the gap visible. The `People/` module will show near-0% and that alone is motivating. Effort: **M** (half a day to wire up, ongoing).

### E5-8 — `SecondBrainDBTests`: FTS5 search and embedding round-trip (M)

`SecondBrainDB` drives all vault search and the hybrid semantic recall. It is 0% tested. Write tests using an in-memory `:memory:` SQLite path (pass a temp URL and let `SecondBrainDB.init` open it there):

```swift
func testFTSUpsertAndSearch() throws {
    let db = SecondBrainDB(dbURL: tempURL)
    db.upsertPerson(person, encounterCount: 1, tagName: { _ in nil })
    let results = db.searchAll(query: "Jane", limit: 10)
    XCTAssertTrue(results.contains(where: { $0.entityID == person.id }))
}
```

Also test that `deleteVaultContent` actually removes the row (currently untested), and that `cosine` similarity returns 1.0 for identical vectors and 0.0 for orthogonal ones. Effort: **M** (a day; requires making `SecondBrainDB.init` accept an injectable URL).

### E5-9 — `MeetingScribeMCPTests` target: process-level JSON-RPC smoke tests (M-L)

The MCP server is a subprocess — it reads stdin, writes stdout. The cleanest integration test is a shell-level driver that feeds it a JSON-RPC request and asserts the stdout response:

```swift
func testListMeetingsReturnsCount() async throws {
    // Spin up the MCP binary against a fixture vault directory.
    let proc = Process()
    proc.executableURL = mcpBinaryURL
    proc.environment = ["MEETINGSCRIBE_STORAGE": fixtureVaultPath]
    // ... feed: {"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_meetings","arguments":{}},"id":1}
    // assert response["result"]["content"][0]["text"] contains "count"
}
```

This catches: tool name typos in the dispatch table, JSON-RPC envelope errors, tools that panic/crash on empty vaults, and schema changes that break existing callers. The fixture vault can be a committed directory under `Tests/MeetingScribeTests/Fixtures/mcp-vault/` with a handful of `meeting.json` files. Effort: **M–L** (depends on whether the target restructuring happens; can start as a shell script in `scripts/` and graduate to Swift later).

---

## 6. Pragmatic testing strategy for a solo developer

The existing suite is well-targeted: it covers the three places where a solo dev's app destroys user data (`MeetingPipelineControllerTests`, `VaultMigrationManagerTests`, `LiveTranscriberTests`). That is exactly right. The additions ranked by value-per-hour:

| Priority | Test | Why now |
|----------|------|---------|
| 1 | E5-5: `RelationshipTypeTests` | Must precede P1 implementation — zero-cost to add now, catastrophic (silent data loss) to add later |
| 2 | E5-6: TSan in CI | One line; makes existing test deliver on its stated purpose |
| 3 | E5-1: `NameSimilarityTests` | 10 cases, pure function, gates auto-link decisions the relationship coaching feature depends on |
| 4 | E5-3: `MCPVaultTests` | Security-critical path containment; covers `resolveInsideVault` in hours |
| 5 | E5-4: `EncounterRoundTripTests` | Encounter history is the biggest MCP data gap (P5); test before exposing it |
| 6 | E5-2: `PeopleStoreTests` | Algorithmic core of the reconnect nudge and ghost-contact filter |
| 7 | E5-7: Coverage in CI | Visibility, not a gate; makes gaps obvious in PRs |
| 8 | E5-8: `SecondBrainDBTests` | FTS5 is the search engine; high value but more setup work |
| 9 | E5-9: MCP integration tests | Highest confidence, highest effort; worth it once the MCP surface grows |

**Do not** add SwiftUI view tests (`PersonDetailView` is 1,986 lines). Testing pure business logic and data models gives 10× the return per hour for a solo developer — view tests are fragile, slow, and require a display context.

---

## 7. Top 3 picks

**E5-5** (`RelationshipTypeTests`) — write these before writing `RelationshipType`. The `try?`-everywhere tolerant decoder is a minefield when adding enum raw values; a round-trip test and an unknown-raw-value fallback test are the minimum safety net. Zero cost to add preemptively.

**E5-1** (`NameSimilarityTests`) — the Jaro-Winkler scorer is already live and has already been adjusted (the audit implies the thresholds were tuned). There are no tests pinning its behavior. Tweaking for relationship-type-aware matching (a romantic partner's first name should auto-link even with low character overlap) will be dangerous without a regression suite.

**E5-6** (TSan in CI) — one line of YAML; makes `AudioCountersTests.testConcurrentMutationDoesNotCrashOrLoseUpdates` actually run under the sanitizer it was written for. This is the highest-value / lowest-effort change in this entire document.
