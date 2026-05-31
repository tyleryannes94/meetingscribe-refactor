# Engineering — Testing, CI/CD, Observability & Release Pipeline

_Lens: what's untested in the data-integrity and pipeline paths, how regressions would actually be caught, and whether a release/install is reproducible and self-verifying._

## Full-app audit (through my lens)

### Test suite — good unit hygiene, zero integration coverage
48 test functions across 10 files (`Tests/MeetingScribeTests/`). The coverage is **deliberately narrow and pure-logic**: parsers, counters, and race-fix invariants. What exists is genuinely good:

- `WhisperRunnerTests.swift` — covers `parse()` JSON shapes + the **SHA-256 model-checksum rejection** (ENG-D). Explicitly notes (`:7`) "the subprocess/argv plumbing needs a real binary so it isn't unit tested here."
- `MeetingPipelineControllerTests.swift` — guards the ENG-C "transcribe-now vs finalize" race via `transcribingIDs` claim.
- `VaultMigrationManagerTests.swift` — locks the ENG-B partial-migration bug (only mark complete when *every* meeting moved).
- `LiveTranscriberTests.swift` — `flush()` drains in-flight work (ENG-A).
- `AudioCountersTests.swift` — concurrency, with a TSan note (`swift test --sanitize=thread`).
- `TranscriptParserTests`, `ActionItemExtractorTests`, `MeetingStoreTests` — drift/regex regressions.

**The gap:** every test is a leaf-node unit test. There is **no test that exercises the actual pipeline** record → segment → whisper → merge → summary → vault write. The two most failure-prone, data-loss-prone subsystems — the **whisper subprocess** and the **Ollama summarization** — are completely untested by design (`WhisperRunnerTests.swift:7`, no Ollama tests at all). The ENG-A repair *gate* (`MeetingPipelineController.needsBatchRepair`, `:65-72`) is unit-tested as a pure function, but nothing verifies that a *real* dropped-chunk recording actually triggers and produces a correct repaired transcript. `Tests/` has **no fixtures dir, no `Bundle.module` resources, no golden files** — confirmed by find. There is a `PlaceholderTests.swift` whose own docstring (`:5-6`) admits "Real high-leverage tests … are added in Batch 8" — Batch 8 partly landed but the integration layer never did.

### CI — already on PR/push (existing-plan item is DONE)
`ci.yml:18-22` triggers on `push: [main]`, `pull_request`, and `workflow_dispatch`. The briefing and AUDIT list "CI on PR/push" as planned-but-pending; **it's actually shipped.** CI runs the dup-guard → `swift build -c release` → `swift test` on `macos-15`/Swift 6.x, with a thoughtful comment (`:8-17`) explaining why an older Xcode pin was abandoned. `release.yml` re-runs `swift test` as a gate before cutting a release (`:26-37`). This is solid. The remaining weakness is **what** CI runs: build + 48 unit tests. No sanitizers in CI (TSan is documented but not wired), no integration smoke, no lint, no coverage threshold/report, and no caching of SwiftPM/Sparkle artifacts (every run re-resolves + recompiles release).

### Release pipeline — well-built, with a verification gate the audit pre-dated
`release.yml` is genuinely good and **already fixes audit finding #5**: it has a `Verify SUFeedURL slug matches this repo` step (`:65-79`) that fails the release if the feed prefix doesn't match `${GITHUB_REPOSITORY}`, plus a placeholder-key guard (`:54-59`). And `Resources/Info.plist:45` now points at `…/meetingscribe-refactor/…` with a real `SUPublicEDKey` (`:47`) — so the wrong-repo Sparkle bug flagged in the audit is **resolved in the app binary.** The pipeline EdDSA-signs the zip + generates the appcast (`:107-122`). Effective and reproducible for the happy path.

**But the release is ad-hoc-signed and unnotarized.** `NOTARIZATION.md:94-99` is honest that CI does an ad-hoc/local-signer build; friends must `xattr -dr com.apple.quarantine` (`RELEASING.md:75`). Notarization is fully documented but **not automated** — it's a manual per-release ritual that will be skipped under pressure.

### The wrong-repo foot-gun is baked into the official reinstall script (HIGH)
This is the most concrete release-integrity bug I found. `clean-reinstall.sh` — the script the audit itself tells users to run to recover from a stale install — **rebuilds from the OLD repo**:
- `clean-reinstall.sh:21` → `REPO_DIR="$HOME/MeetingScribe"` (the legacy `meetingscribe` remote, **not** `~/MeetingScribeRefactor`)
- `:20` → `STORAGE_DIR="$HOME/Documents/MeetingNotes"`
- `:129` → `git pull --ff-only origin main` then `:134` `make install` — **from the legacy repo.**

So the canonical "fix your install" script reinstalls the *deprecated* app and overwrites `/Applications/MeetingScribe.app` from the wrong tree. This directly recreates audit issue #2 instead of curing it. (The copy living in the refactor repo has the same legacy paths.)

### Stale repo references in release/diagnostics docs (LOW but real)
The feed URL is fixed, but several supporting artifacts still hardcode the legacy repo:
- `RELEASING.md:7-8` describes `SUFeedURL` as pointing at `…/meetingscribe/…` (stale prose), and `:28` points the `SPARKLE_PRIVATE_KEY` secret at the **old repo's** settings page.
- `DiagnosticsExporter.swift:127` writes a README telling users to file issues at `github.com/tyleryannes94/meetingscribe/issues` (old repo).
A user filing a diagnostics bundle lands on the wrong issue tracker.

### Reproducibility gap: model pinned in code, only magic-byte-checked in installer
`WhisperRunner.swift:267` pins `baseEnModelSHA256` and `fileMatchesSHA256` rejects a mismatched model at runtime (great, ENG-D). But `install.sh` (step 4, `:9`) only "verifies its magic bytes" on download — **not** the SHA. So an installer can place a corrupt/wrong-revision model that passes the magic-byte check, and the failure surfaces only later at first transcription. The two checks aren't sharing the pinned constant.

### Observability — solid local diagnostics, no telemetry/crash ingestion
`DiagnosticsExporter.swift` is well-designed: user-initiated zip with `app.log`, `transcription-log.json`, `ollama.log`, `recent-errors.json` (last 100 via `ErrorReporter`), redacted settings (allowlist, default-deny, no Keychain). For a local-first app this is the right privacy posture. But there is **no crash capture** (grep found no `NSSetUncaughtExceptionHandler` / signal handler / backtrace ingestion). A crash on a friend's Mac produces nothing actionable; the diagnostics bundle only exists if the app is alive enough to press a button. There's also no structured record of *update* outcomes (did Sparkle apply? roll back?).

### Dup-guard ratchet is healthy but blind to model-layer dupes
`check-cross-tree-dupes.sh` is a clean ratchet (28 baselined, fails on new dupes AND stale entries). But as the audit noted (#3-adjacent), it only diffs `Sources/MeetingScribe` ↔ `Sources/ScribeCore` by **basename** — it can't catch *content* divergence within an allowlisted pair (e.g. the diverged `WhisperRunner`/`NotificationManager` copies), nor dupes in VaultKit. It's a structural guard, not a behavioral one.

## Existing-plan items I rank highest

1. **Data-integrity tests (REMAINING_WORK "needs a Mac" items).** The ENG-A/B/C/D unit tests exist, but the plan's own framing — "must be verified by actually recording → transcribing on a Mac … can't be runtime-tested in the sandbox" — *is the gap*. The highest-value testing work is exactly the Mac-only integration layer that's currently a manual smoke test. Endorsed and escalated below (E5-1).
2. **CI on PR/push** — already shipped (`ci.yml:21`). I endorse keeping it and note the plan should mark it done; the next increment is sanitizers + coverage in that same workflow.
3. **ARCH-1 CaptureKit extraction** (REMAINING_WORK §1) — through my lens this matters because **ENG-A/D fixes currently live in two diverging copies**; a regression fixed in the app copy silently persists in the daemon copy. De-duping is a test-surface reduction, not just cleanup. REMAINING_WORK §2.1 already flags the ENG-A-across-XPC regression risk — that's exactly the kind of thing only an integration test catches.
4. **Two-binary activation ENG-A threading** (REMAINING_WORK §2.1) — endorse the explicit callout that `liveDroppedChunks/liveCoverageSeconds/recordedDuration` must cross the XPC/Darwin boundary or the repair gate silently regresses. This needs a test that asserts the daemon-owned path still triggers repair.

## NET-NEW recommendations

### E5-1 — Golden-audio transcription regression suite **(Top pick)**
**What:** Commit 3–5 short (~20–40s) reference WAVs (synthetic TTS or CC-licensed speech, including one with deliberate silence/overlap) plus their expected transcript JSON, as test fixtures. A Mac-only test target runs the **real** bundled `whisper-cli` against them and asserts a fuzzy match (normalized WER under a threshold, exact for timestamps within ±200ms). Pin against `baseEnModelSHA256`.
**Why:** The whisper subprocess — the app's core value and most likely silent-failure point — is explicitly *not* tested (`WhisperRunnerTests.swift:7`). A model bump, arg change, or whisper.cpp upgrade can degrade quality with zero signal today.
**User value:** "transcripts got worse after an update" becomes a red CI run, not a user complaint.
**Effort:** M · **Impact:** High · **Depends on:** a self-hosted/Mac CI runner OR a `make test-integration` target gated locally (current GitHub runners can run it; whisper-cli must be built — reuse `scripts/build-whisper-cpu.sh`).

### E5-2 — End-to-end pipeline integration harness **(Top pick)**
**What:** One XCTest that drives the real pipeline headlessly: feed a fixture WAV through `MeetingPipelineController.finalize` (with a stubbed or live Ollama) → assert `transcript.md`, `summary.md`, `meeting.json`, and the FTS5 index row all land correctly in a temp vault, and that injecting `liveDroppedChunks > 0` actually triggers the batch repair and recovers the tail. Add a daemon-path variant for the Phase-2 XPC boundary (per REMAINING_WORK §2.1).
**Why:** Every current test stops at a single leaf. The interactions that cause real data loss (race + repair + vault write) are exactly what's untested end-to-end.
**User value:** Guards the "I recorded an hour and got half a transcript" class of bug — the worst possible failure for this app.
**Effort:** L · **Impact:** High · **Depends on:** E5-1 fixtures; an Ollama stub.

### E5-3 — `make doctor` pre-flight self-test
**What:** A bundled diagnostic command (and a UI "Run self-test" button) that verifies the live environment: whisper binary present + model SHA matches the pinned constant, Ollama reachable + model pulled, TCC perms (mic/screen/calendar) granted, signing identity valid, storageDir writable, Sparkle feed reachable (HTTP 200). Emits pass/fail to `app.log` and the diagnostics bundle.
**Why:** Most "it's broken" reports are environment drift (model moved, Ollama down, perms revoked). `install.sh` checks these once; nothing re-checks at runtime. Reuses the pinned SHA so install and runtime agree.
**User value:** Self-service triage; turns a vague failure into a named missing dependency.
**Effort:** M · **Impact:** High · **Depends on:** none (composes existing checks).

### E5-4 — Crash-report capture into the diagnostics bundle
**What:** Install an uncaught-exception handler + signal handler (or integrate a lightweight `MetricKit`/`PLCrashReporter`) that writes a `crash-<ts>.log` next to `app.log`; on next launch, surface "MeetingScribe quit unexpectedly last time — attach report?" and fold the crash into `DiagnosticsExporter`.
**Why:** Today a crash leaves no trace; the diagnostics bundle requires a *running* app to export (`DiagnosticsExporter.swift`). Crashes are invisible to the maintainer.
**User value:** The one class of bug users can't describe becomes reproducible.
**Effort:** M · **Impact:** Med · **Depends on:** none.

### E5-5 — Fuzz + property tests for the vault/markdown parsers
**What:** Property-based tests (SwiftCheck or hand-rolled randomized inputs) for `TranscriptParser.parse`, the `meeting.json` decoder (`MeetingStore` legacy-payload tolerance), and the action-item extractor — feed malformed/truncated/adversarial markdown and assert "never crash, never silently blank a non-empty transcript." Seed the corpus with real vault files.
**Why:** These parsers feed UI directly; `TranscriptParserTests.swift:5` notes a regression "would silently blank the transcript pane even when transcript.md is fine on disk." The vault is user-editable Obsidian markdown synced via iCloud — partial/conflicted files are inevitable.
**User value:** A half-synced or hand-edited note never crashes the app or hides content.
**Effort:** S–M · **Impact:** Med · **Depends on:** none.

### E5-6 — Automated notarization in the release workflow
**What:** Add Developer-ID cert + `notarytool` credentials as encrypted CI secrets and insert `notarytool submit --wait` + `stapler staple` before the GitHub-Release publish (the steps already spelled out in `NOTARIZATION.md:94-99`). Fall back to ad-hoc only when secrets are absent.
**Why:** The manual ritual will be skipped; an unnotarized release means every friend hits Gatekeeper + a `xattr` incantation, and Sparkle delta updates of an unnotarized app are fragile.
**User value:** Updates "just work" with no quarantine dance.
**Effort:** M · **Impact:** Med · **Depends on:** Apple Developer Program enrollment (external).

### E5-7 — Fix `clean-reinstall.sh` to target the refactor repo + assert remote
**What:** Change `REPO_DIR` to `$HOME/MeetingScribeRefactor`, and add a guard that `git remote get-url origin` matches `…/meetingscribe-refactor` before building — abort loudly otherwise. Also stop hardcoding `STORAGE_DIR=~/Documents/MeetingNotes`; read it from the app's `storageDir` default.
**Why:** The official recovery script currently rebuilds the **deprecated** app (`clean-reinstall.sh:21`), recreating audit issue #2. This is a release-integrity bug in the one tool meant to fix release integrity.
**User value:** "Reinstall" can't silently downgrade you to the old app.
**Effort:** S · **Impact:** High · **Depends on:** none.

### E5-8 — Release-artifact post-publish verification job
**What:** After `softprops/action-gh-release`, add a job that downloads the published `appcast.xml` + zip from the release URL, verifies the EdDSA signature with the **public** key from `Info.plist`, confirms the `sparkle:version` matches the tag, and HEAD-checks that `SUFeedURL` resolves 200. Fail the workflow if any check fails.
**Why:** `release.yml` verifies inputs (feed slug, key placeholder) but never confirms the *published* artifact is actually update-able. A signing/upload glitch ships a release no installed copy can apply.
**User value:** A broken release is caught in CI, not by users stuck on an old version forever.
**Effort:** S–M · **Impact:** Med · **Depends on:** release.yml.

### E5-9 — CI sanitizer + coverage lane
**What:** Add a parallel CI job running `swift test --sanitize=thread` (the TSan run `AudioCountersTests.swift:6` documents but CI doesn't execute) and `swift test --enable-code-coverage`, publishing an `llvm-cov` summary as a PR comment with a floor on the data-integrity files (`MeetingPipelineController`, `WhisperRunner`, `MeetingStore`, `VaultMigrationManager`).
**Why:** The races these fixes address (ENG-C, AudioCounters) only reliably surface under TSan, which never runs automatically. Coverage on the integrity files makes regressions in *those* files visible.
**Effort:** S · **Impact:** Med · **Depends on:** none.

### E5-10 — Content-aware dup-guard (not just basename)
**What:** Extend `check-cross-tree-dupes.sh` to also emit a per-pair content-hash diff for baselined files and fail if a file that was byte-identical *diverges* without an explicit `# diverged:` annotation in the baseline. Surface the diverged set (currently `WhisperRunner` ~59 lines, `NotificationManager` ~83) as a tracked debt list.
**Why:** The guard prevents *new* dupes but is blind to the *diverging* ones — which is precisely where an ENG-A/D fix can land in one copy and not the other.
**Effort:** S · **Impact:** Med · **Depends on:** none (pairs well with ARCH-1).

### E5-11 — Snapshot tests for the canonical meeting/People surfaces
**What:** Add `swift-snapshot-testing` for the few high-traffic SwiftUI views being consolidated in V3 (canonical meeting detail, PersonDetailView, Today hub) — render to image at fixed sizes incl. empty/loading/error states.
**Why:** V3 is a heavy UI refactor (kill expand/collapse, full-width, NavigationSplitView). Snapshot tests catch layout regressions (e.g. the `padding(.top, 60)` magic-number alignment bug) that no unit test sees. Lower priority than the data-integrity work but the only automated guard for the UI churn underway.
**Effort:** M · **Impact:** Low–Med · **Depends on:** V3 view consolidation landing first.

## Top 3 picks
1. **E5-2 — End-to-end pipeline integration harness.** The single biggest blind spot: every test is a leaf, and the record→transcribe→repair→vault path (where catastrophic data loss lives) has no automated coverage. This is the test that would have caught ENG-A in the first place.
2. **E5-1 — Golden-audio transcription regression suite.** The whisper subprocess is the product's core and is explicitly untested; a model or whisper.cpp bump can silently degrade quality with zero signal.
3. **E5-7 — Fix `clean-reinstall.sh` to target the refactor repo.** Tiny effort, but the official recovery script currently rebuilds the *deprecated* app — actively recreating the exact wrong-repo bug the audit told users to run it to fix.

**Single highest-priority recommendation overall:** E5-2 (end-to-end pipeline integration harness). For a local-first transcription app, a silent partial transcript is the worst outcome, and nothing in the current suite would catch one before a user does.
