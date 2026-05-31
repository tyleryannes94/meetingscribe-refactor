# Engineering — Architecture & Modularity

*Lens: module boundaries, coupling/cohesion, dependency direction, state-management consistency, the two-binary design, and long-term maintainability.*

---

## Full-app audit (through my lens)

### Target graph: VaultKit consolidation landed, but it's a thin model layer, not a domain layer
`Package.swift` is clean for a 5-target graph: `VaultKit` (Foundation-only) is depended on by the app, `ScribeCore`, and both MCP servers (`Package.swift:37-83`). The `MeetingScribeShared` + `SecondBrainCore` orphan targets were correctly deleted and repointed to `VaultKit` (confirmed; `REMAINING_WORK.md:23`). Good.

But VaultKit is **only DTOs + path helpers + DarwinNotifier** (`Sources/VaultKit/`: `SharedModels`, `Person`, `Encounter`, `JSONValue`, `SchemaEnvelope`, `VaultPaths`, `DarwinNotifier`, `SecondBrainStore`). It is a *data-transfer* layer, not a *domain* layer. All actual behavior — store logic, file I/O coordination, the iMessage parser, summary-prompt construction, action-item extraction — lives in the app target and is re-implemented in the MCP server. The "single source of truth" claim in the Package comment (`Package.swift:32-36`) is true for *types* and false for *logic*.

### The two-binary split is scaffolding, not a split — and the duplication is worse than the plan states
25 files are physically duplicated between `Sources/MeetingScribe/{Audio,Transcription,Detection,Calendar,AI,Notifications}` and `Sources/ScribeCore/` (verified by `comm`). `REMAINING_WORK.md:34-48` asserts "**22 are byte-identical**… only 2 differ." **That is now false.** A `diff` across the 25 pairs shows **12 files have diverged**, several substantially:
- `MeetingPipelineController.swift` — 122 diff lines
- `Notifications/NotificationManager.swift` — 83
- `Transcription/WhisperRunner.swift` — 59
- `Transcription/LiveTranscriber.swift` — 37
- `AI/OllamaService.swift` — 25
- plus `AudioRecorder` (11), `CalendarService` (8), `QuickTranscribe`/`WhisperTranscriber` (4 each), `CalendarStoreActor`/`AppDetector`/`TranscriptionLog` (2 each).

This is exactly the failure mode the original audit warned about: **every fix to the capture/transcription pipeline must be made twice, and the two copies are already drifting.** The ENG-A live-transcript repair gate is the canonical example — `REMAINING_WORK.md:108-115` admits the gate lives in the *app's* `MeetingPipelineController.finalize` and must be re-threaded across the daemon boundary, and the 122-line `MeetingPipelineController` diff is where that divergence already sits. The WhisperRunner SHA-pin / GPU-retry logic similarly has to be maintained in two places.

The daemon also carries its own **stub re-implementations of cross-cutting infrastructure**: `Sources/ScribeCore/CompatShim.swift` provides OSLog-only stand-ins for `AppLog` and `ErrorReporter`, and `Sources/ScribeCore/AppSettings.swift` is a hand-copied 86-line subset of the app's `Settings.swift`. So logging, error reporting, and settings reads **silently behave differently** depending on which binary runs the code. That is a correctness hazard, not just a DRY smell.

IPC is still the file-command bridge: `ScribeCore/IPC/VaultCommandWatcher.swift` polls `vault/_commands/*.json`; the real `NSXPCConnection` is unimplemented (`MeetingScribe/IPC/ScribeCoreXPCClient.swift:7` "Phase 2: will switch to NSXPCConnection"; `ScribeCore/IPC/ScribeCoreXPC.swift:4` "Phase 2: replace file-command IPC"). The daemon does not yet own capture — `MeetingManager` still hard-instantiates `private let audio = AudioRecorder()` (`MeetingManager.swift:86`). So today there is **one process doing the work and a second copy of that process's code that nothing runs in production** — all the duplication cost, none of the isolation benefit.

### Dependency direction: inverted via singletons; no injection seam
`AppSettings.shared` is referenced **165 times**, `PeopleStore.shared` **30 times**, `ErrorReporter.shared` **41 times** across the app target. Modules reach *up* into global singletons instead of receiving collaborators. `MeetingManager` hard-news every dependency in its property initializers — `MeetingStore()`, `TagStore()`, `OllamaService()`, `WhisperTranscriber()`, `AudioRecorder()` (`MeetingManager.swift:40-87`) — so it cannot be constructed with fakes; there is no unit-testable seam around the recording controller at all.

Tellingly, the one DI abstraction that *does* exist — `VaultKit/SecondBrainStore.swift`'s `SecondBrainStore` protocol — has **exactly one conformer, `InMemorySecondBrainStore` (`SecondBrainStore.swift:31`), and no `VaultFileStore`.** It is referenced only by its own file and `SecondBrainCoreExports.swift`. The production stores (`PeopleStore`, `MeetingStore`) do not conform to it. The protocol the plan promised as the persistence seam is **orphaned scaffolding** — the intent exists in the type system but nothing is wired through it.

### State management: ObservableObject monolith with high fan-out; @Observable barely adopted
`MeetingManager` is observed via `@EnvironmentObject` by **17 distinct views** (vs. 7 for `CalendarService`, 1 for `ChatSession`). It is a 900-line `ObservableObject` with 12 `@Published` properties plus ~7 forwarding shims that re-expose sub-controller state (`var transcribingMeetingIDs: Set<String> { pipelineController.transcribingIDs }`, `MeetingManager.swift:449`; `lastCompletedMeetingDir`, `:478`). The V2 "Bug 2" (`@Published` wrapping child `ObservableObject`s) **was fixed** — `liveTranscriber`/`tagStore` are now `let` (`MeetingManager.swift:37,42`) — good. But the decomposition is half-done: sub-controllers exist (`pipelineController`, `quickNotesController`, `personExtraction`) yet views still funnel through the god-object's shims rather than observing the sub-controllers directly, so any `MeetingManager.objectWillChange` still re-renders all 17 view trees.

Adoption of the modern `@Observable` macro is **4 occurrences vs. 28 `ObservableObject` classes** — the codebase is overwhelmingly on the legacy Combine-based model, which is precisely what produces the broad invalidation cascades.

### God-files persist (and the worst one grew)
`MeetingMCP main.swift` is **1,502 lines** (the plan cited 1,081 — it *grew*), and it is ~50 free functions in one file with no type structure (`tool_listMeetings`, `analyzeMessages`, `extractTextFromAttributedBody`, …; `main.swift:40-1300`). `PersonDetailView.swift` is 1,328, `PeopleStore.swift` 1,177, `MeetingManager.swift` 900. The MCP file re-implements the **iMessage `attributedBody` typedstream byte-parser** (`extractTextFromAttributedBody`, `main.swift:583`) that also lives in `People/MessagesAnalyzer.swift` — the single most fragile, hand-rolled piece of code in the whole product, duplicated across a target boundary with no shared owner.

### TOCTOU recording-state race never fixed
V2 Bug 6 specified adding `.starting`/`.stopping` transient cases to gate concurrent start/stop. The live enum is still `case idle, recording(startedAt:), transcribing, error(String)` (`MeetingManager.swift:752`) — **no transient states**. The race the plan flagged is still open.

---

## Existing-plan items I rank highest (through my lens)

1. **ARCH-1 — Extract `CaptureKit`, retire app↔daemon duplication** (V3 §3.7; `REMAINING_WORK.md` §1). This is *the* architectural debt. My audit shows the divergence is already real (12/25 files differ, up to 122 diff lines), which makes it more urgent than `REMAINING_WORK.md` claims. Endorse — but the doc's "22 byte-identical" premise must be re-baselined first.
2. **Phase 2 — activate the two-binary split** (V2; `REMAINING_WORK.md` §2). Worth finishing *because* the duplication only pays off once the daemon actually owns capture and the UI process can't crash with it. Until then it is pure cost. Sequence it immediately after CaptureKit.
3. **ARCH-3 — Finish MeetingManager decomposition + delete forwarding shims; decompose `PeopleStore`/`PersonDetailView`/MCP `main.swift`** (V3 §3.7). Endorse, and raise MCP `main.swift` to top priority since it grew and carries the duplicated iMessage parser.
4. **VaultKit as the single shared library** (V2). Endorse the *direction* but note it stopped at DTOs — the high-value move is pushing *logic* (iMessage parser, path/store coordination) down into it, not just types.

---

## NET-NEW recommendations

### E1-1 — Introduce a `Services` domain layer + constructor injection, behind protocols
**What/why:** Today `MeetingManager` hard-news every collaborator and 165 call-sites read `AppSettings.shared`. Define protocol-fronted services (`SettingsReading`, `TranscriptionService`, `SummarizationService`, `PeopleReading`, `MeetingStoring`) in VaultKit, have the concrete types conform, and inject them through initializers (default args can keep call-sites terse). Make `MeetingManager` accept its sub-controllers as parameters.
**User value:** Indirect but large — unblocks fast, deterministic unit tests for the recording/finalize/extraction logic that currently has none, and lets the daemon and app share one implementation injected with target-specific settings/logging (kills `CompatShim`).
**Effort:** L · **Impact:** High · **Depends on:** nothing; strongly enables E1-2, E1-5, ARCH-1.

### E1-2 — Make `SecondBrainStore` real: ship `VaultFileStore` and route both stores + MCP through it
**What/why:** The persistence protocol exists with only an in-memory conformer. Implement `VaultFileStore: SecondBrainStore` (NSFileCoordinator-backed) in VaultKit, conform `PeopleStore`/`MeetingStore` to read/write through it, and have the **MCP server use the same store** instead of its own free-function disk readers (`main.swift:40-310`). One file-format owner, one coordinator policy, one place to fix a path bug.
**User value:** Eliminates the class of bug where the app and MCP server disagree about what's on disk (the plan already notes "the two surfaces report identical numbers" is maintained *by hand*).
**Effort:** L · **Impact:** High · **Depends on:** E1-1 (protocol seam).

### E1-3 — Extract the iMessage `attributedBody` parser into VaultKit as `MessageBodyDecoder`
**What/why:** The hand-rolled typedstream byte-scanner is duplicated in `People/MessagesAnalyzer.swift` and MCP `main.swift:583` (`extractTextFromAttributedBody`). It is the most brittle code in the product (depends on `0x2b` marker positions). Move it to one `public` Sendable function in VaultKit with a golden-fixture test suite; both call-sites import it.
**User value:** A future macOS change to the typedstream format gets fixed once, with a test, instead of silently diverging across two binaries.
**Effort:** S · **Impact:** Med · **Depends on:** nothing.

### E1-4 — Unify logging/error/settings as VaultKit protocols; delete `CompatShim` and the daemon's `AppSettings` copy
**What/why:** `ScribeCore/CompatShim.swift` and `ScribeCore/AppSettings.swift` are silent behavioral forks of `AppLog`/`ErrorReporter`/settings. Define `Logging`/`ErrorReporting`/`SettingsReading` protocols in VaultKit, provide an OSLog default impl there, and let the app inject its file-backed `ErrorReporter`. Both binaries then log/report through the same surface.
**User value:** Daemon-side errors actually reach the user's `app.log` instead of vanishing into OSLog; one consistent settings read path.
**Effort:** M · **Impact:** Med · **Depends on:** E1-1.

### E1-5 — Migrate the recording/pipeline state to `@Observable` (incrementally) and split observation by concern
**What/why:** 28 `ObservableObject`s vs 4 `@Observable`; `MeetingManager` is observed by 17 views and re-publishes sub-controllers via shims. Migrate the hottest objects (`MeetingManager`, `MeetingPipelineController`, `LiveTranscriber`) to `@Observable` so SwiftUI tracks per-property dependencies, then delete the forwarding shims (`MeetingManager.swift:449,478`) and have views observe the sub-controller they actually use.
**User value:** Fewer view invalidations during recording → lower main-thread CPU and smoother live transcript (directly complements the V2 timer-storm fix).
**Effort:** M · **Impact:** High · **Depends on:** ARCH-3 (decomposition) ideally first.

### E1-6 — Define an explicit module dependency policy + CI import-direction guard
**What/why:** There is a CI dupe guard (`scripts/check-cross-tree-dupes.sh`) but nothing enforces *dependency direction*. Document the intended layering (VaultKit ← CaptureKit ← {App, Daemon, MCP}; UI never imported by services) and add a CI check (grep-based or a SwiftPM plugin) that fails if `Sources/VaultKit` imports AppKit/SwiftUI or if a services file imports a view.
**User value:** Prevents the architecture from silently re-coupling as features land (the orphan-target and duplication problems both grew because nothing guarded direction).
**Effort:** S · **Impact:** Med · **Depends on:** ARCH-1 (defines the layers to enforce).

### E1-7 — A typed, versioned `ScribeBridge` IPC contract (one envelope for file-command *and* XPC)
**What/why:** Today the file-command path (`VaultCommandWatcher`, `VaultCommand` struct) and the future XPC path (`ScribeCoreXPC` protocol) are two unrelated definitions that will drift like the capture files did. Define one `Codable`, versioned command/response envelope in VaultKit; the file bridge serializes it to JSON and the XPC layer passes it as `Data`. ENG-A's `liveDroppedChunks`/`liveCoverageSeconds` fields (which `REMAINING_WORK.md:108-115` warns must be threaded across the boundary) become typed fields on that envelope instead of ad-hoc plumbing.
**User value:** The Phase-2 XPC cutover becomes a transport swap, not a re-implementation; ENG-A can't silently regress in the daemon path.
**Effort:** M · **Impact:** High · **Depends on:** ARCH-1; gates Phase-2.

### E1-8 — Collapse the dual people-search architecture behind one `PeopleSearch` service
**What/why:** `ARCHITECTURE.md` documents two separate, intentionally-divergent people-search paths (FTS5 via `PeopleStore.filteredPeople` for the list; plain in-memory contains in `WorkspaceIndex.search` for ⌘K, because FTS "reproducibly dropped contacts"). That's two correctness models for the same question. Wrap both behind a `PeopleSearching` protocol with one implementation that uses FTS5 *with* the in-memory fallback as a single documented policy, used by both surfaces.
**User value:** "Search finds the person" behaves identically everywhere; the known FTS staleness bug gets one owner instead of being worked around in two places.
**Effort:** M · **Impact:** Med · **Depends on:** E1-2 (store seam).

### E1-9 — A `ChatToolHandler`-style plugin registry for both chat *and* MCP tools
**What/why:** The in-app chat already has a clean handler protocol (`ChatTools.swift:82`, five domain handlers). The MCP server does *not* — it's 50 free functions in one 1,502-line file, and the doc's "adding a tool" path requires editing MCP `main.swift` separately (`ARCHITECTURE.md` "Adding a new feature"). Define a shared `VaultTool` protocol (name, JSON schema, `run(args) async -> JSONValue`) in VaultKit; register the same handler structs in both the chat dispatcher and the MCP server's `tools/list`/`tools/call`.
**User value:** New agent capability is written once and appears in both the in-app assistant and Claude Desktop — closes the "mirror into main.swift" gap and shrinks the worst god-file structurally.
**Effort:** L · **Impact:** Med · **Depends on:** E1-2 (tools need the store seam to read/write).

### E1-10 — Add the `.starting`/`.stopping` transient recording states (close the open TOCTOU)
**What/why:** V2 Bug 6 was specified but never landed — `RecordingState` is still `idle/recording/transcribing/error` (`MeetingManager.swift:752`). Add the two transient cases and guard `startRecording`/`stopRecording` synchronously before the first `await`. This is an architectural-correctness item (state-machine integrity under the menu-bar + main-window dual-command topology), not just a bug.
**User value:** No more illegal half-started state from a fast double-tap or simultaneous commands from two windows — a real risk once the daemon adds a third command source.
**Effort:** S · **Impact:** Med · **Depends on:** nothing (but compounds with Phase-2's extra command source).

---

## Top 3 picks

1. **E1-1 — Services domain layer + constructor injection.** Everything else (testability, killing `CompatShim`, sharing logic between binaries, real `SecondBrainStore`) is gated on having an injection seam. Highest leverage net-new item.
2. **E1-7 — Typed, versioned `ScribeBridge` IPC contract.** Makes the two-binary split finishable without re-drift and prevents ENG-A from silently regressing across the daemon boundary — the specific failure the existing plan is most exposed to.
3. **E1-2 — Ship `VaultFileStore` and route the app *and* MCP through it.** Turns VaultKit from a DTO bag into a real shared domain layer and eliminates the hand-maintained "app and MCP agree by coincidence" contract.

**Single highest-priority recommendation overall:** **E1-1** — without dependency injection there is no seam to test the recording pipeline, no way to unify the app/daemon logic, and no way to retire the duplicated infrastructure; it is the prerequisite that makes the endorsed CaptureKit/two-binary work safe rather than risky.
