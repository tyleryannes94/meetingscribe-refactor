# Held Items — awaiting your review

These are master-plan items I deliberately did **not** auto-merge during the unattended
build, per your "hold it and explain it" rule. Each is genuinely unsafe to land without
a human in the loop — correctness risk that needs runtime verification, a secret/decision
I can't supply, or a high-blast-radius refactor that the plan itself says must wait for
the test harness. Everything *not* listed here that was safe and verifiable has already
been merged to `main` (see `BUILD-LOG.md`).

| # | Item | Phase | Why held | Recommended action |
|---|------|-------|----------|--------------------|
| 1 | **Live-transcript truncation fix** | 1A | Correctness-critical audio. The app's live path is `Sources/MeetingScribe/Transcription/LiveTranscriber.swift` (the *MeetingScribe* copy, not the `ScribeCore` one the plan named). A wrong `flush()`/repair-gate change can silently make transcription *worse*, and that can only be confirmed by recording a real meeting. | Pair-build it, then record a test meeting and diff the transcript tail vs. the batch pass. |
| 2 | **E2E pipeline harness + Services/DI seam + CaptureKit extraction** | 1B | Large, high-blast-radius. The plan's own sequencing says *tests must land before these refactors* — doing them unattended without runtime verification risks reintroducing the data-loss bugs they target. | Build interactively with `make app` + a real recording after each step. |
| 3 | **Sparkle release signing** | release | The release workflow needs the `SPARKLE_PRIVATE_KEY` GitHub secret, which I can't set. Also `Resources/Info.plist :SUFeedURL` points at the **old** `tyleryannes94/meetingscribe` repo, not `…/meetingscribe-refactor` — so a tag here may not reach your work MacBook. | Confirm/repoint `SUFeedURL`; set the secret (`RELEASING.md` → `./scripts/setup-sparkle-key.sh`). Then re-tag. |
| 4 | **LicenseManager (Ed25519 / Keychain)** | 1D | Security-sensitive crypto gating features. Worth designing deliberately and unit-testing rather than improvising unattended. | Spec the signing scheme + test vectors, then build. |
| 5 | **Directory-traversal `resolveInsideVault` hoist into VaultKit + apply to all app write sites** | 1A/2G | Currently MCP-only. Hoisting + calling on every write touches many paths (medium blast radius); a missed/over-eager guard could block legitimate writes. | Focused PR with a malicious-path rejection test. |
| 6 | **Onboarding de-jargon / "Setup Complete" celebration / SetupCheck required-vs-optional split** | 1E | Subjective UX + branding. "Vault" and "Ollama" are used as deliberate concepts across the app; rewriting user-facing copy app-wide is a tone decision I shouldn't make solo. | Tell me the voice you want ("vault" → ? ) and I'll sweep it. |
| 7 | **Phase 3/5 big bets** (Apple Foundation Models backend, always-on ambient capture, full Decision/Commitment Ledger) | 3–5 | Large and dependency-gated on Phase 1–2 primitives (retention/right-to-forget, write-ahead journal, the test harness). | Sequence after Phase 2 lands. |

## Already done in the codebase (audit was pessimistic)

Several Phase-1 "P0s" turned out to be already implemented — flagging so you don't think they were skipped:

- **Daemon orphan recordings** — already gated behind `useScribeCoreDaemon` (defaults `false`).
- **`rebuild()` transactions, WAL, `PRAGMA quick_check`** — already present in `SecondBrainDB`.
- **CI gate** — `.github/workflows/ci.yml` already runs `swift build -c release` + `swift test` + cross-tree-dup guard + design-lint on every PR/push.
- **`NDS.splitPaneTopInset`** — already applied consistently (no `padding(.top, 60)` drift).
- **`.starting`/`.stopping` transient `RecordingState`** — already claimed synchronously in `startRecording`/`stopRecording`.
