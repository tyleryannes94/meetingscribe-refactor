# Competitive Analysis — On-Device AI Infrastructure & the MCP/Agent Ecosystem

> Lens: is MeetingScribe on the *best* local-AI stack for 2026 Apple Silicon, and is its
> MCP server positioned to ride the agent wave — or is it leaving accuracy/speed/efficiency
> and ecosystem reach on the table?

## The current stack (verified in source)

- **STT:** `whisper.cpp` invoked as a subprocess (`whisper-cli`), model `ggml-base.en.bin`, GPU(Metal)-then-CPU empty-output retry path (`Transcription/WhisperRunner.swift:5-26, :108-116, :201-218`). Model integrity is pinned with a SHA-256 checksum — ENG-D is **done** (`WhisperRunner.swift:260-267`).
- **Diarization:** "fake" — relies on whisper.cpp's `--diarize`/tinydiarize inline `[SPEAKER_NN]` markers, then regex-parses them (`Transcription/SpeakerDiarization.swift:37-60`). Standard ggml models ignore the flag, so `hasMultipleSpeakers` is usually false (`SpeakerDiarization.swift:34-35`). There is no real speaker-embedding/clustering model.
- **LLM:** Ollama `llama3.1:8b` over `/api/generate` with **streaming disabled** "for simplicity" (`AI/OllamaService.swift:5-13`), auto-started from a Homebrew binary (`OllamaService.swift:43-53`). Connection state machine added to avoid redundant probes (`:55-90`).
- **MCP:** 17-tool server (12 read + 5 write), bundled binary registered into `claude_desktop_config.json` via MCPInstaller; NotionMCP is a second 6-tool server. Servers are **stdio-only and local-only**; not published to any registry (audit report §5).

This is a competent 2024-era stack. Through the infra lens, **every layer now has a materially better 2026 option on Apple Silicon**, and the MCP server is sitting on an unexploited distribution + "agent memory" opportunity.

## Full-app audit (through my lens)

### 1. Subprocess whisper.cpp is now the slow, low-accuracy choice
Apple's own **SpeechAnalyzer / SpeechTranscriber** (macOS 26 Tahoe) transcribes a 34-min file in ~45s — **~55% faster than Whisper Large-v3-Turbo** — as a built-in, zero-download, fully on-device API. ([MacRumors](https://www.macrumors.com/2025/06/18/apple-transcription-api-faster-than-whisper/), [Daring Fireball](https://daringfireball.net/linked/2025/06/19/apples-new-foundation-model-speech-apis-outpace-whisper-for-transcription/)) Separately, **WhisperKit** (Argmax, CoreML/ANE) hits **2.2% WER at 0.46s latency** on Large-v3-Turbo, ~5x faster than subprocess whisper.cpp, with native streaming. ([WhisperKit benchmarks](https://github.com/argmaxinc/WhisperKit/blob/main/BENCHMARKS.md), [Argmax paper](https://arxiv.org/html/2507.10860v1)) And **Parakeet** (NVIDIA TDT, run via the Swift **FluidAudio** SDK on the ANE) is **~10x faster than Whisper Large-v3-Turbo, more accurate, at 0.017 RTF / 60x real-time on an M1**. ([Whisper Notes](https://whispernotes.app/blog/parakeet-v3-default-mac-model), [FluidAudio](https://github.com/FluidInference/FluidAudio)) MeetingScribe's `base.en` subprocess path is the slowest and least accurate option in the field, and it forces a `brew install whisper-cpp` dependency the others don't.

### 2. Diarization is the weakest link, and there's now a drop-in Swift fix
The whole "speaker-labeled transcript" feature (V3 §4 / REMAINING_WORK §4) is built on tinydiarize markers that the default model **doesn't emit** (`SpeakerDiarization.swift:34-35`). Meanwhile **FluidAudio** ships real CoreML speaker diarization + VAD as an MIT/Apache Swift Package, powering 20+ production apps (VoiceInk, Spokenly), and **Parakeet.cpp** has built-in Sortformer diarization for up to 4 speakers. ([FluidAudio](https://swiftpackageindex.com/FluidInference/FluidAudio), [Hugging Face](https://huggingface.co/FluidInference/speaker-diarization-coreml), [modelslab](https://modelslab.com/blog/audio-generation/parakeet-cpp-vs-whisper-self-hosted-asr-comparison-2026)) The planned diarization feature will under-deliver on the current engine no matter how the UI surfaces it.

### 3. Ollama is fine but no longer the throughput leader — and it's left unstreamed
As of **Ollama 0.19 (March 2026) Ollama runs on an MLX backend** on 32GB+ Apple Silicon, reaching ~85% of pure-MLX throughput (+57% prefill / +93% decode on an M5 Max). Standalone MLX still wins outright (~130 tok/s vs 43 tok/s Ollama-llama.cpp on an M4 Pro for Qwen3-Coder-30B). ([Ollama MLX](https://ollama.com/blog/mlx), [willitrunai](https://willitrunai.com/blog/mlx-vs-ollama-apple-silicon-benchmarks), [Contra Collective](https://contracollective.com/blog/llama-cpp-vs-mlx-ollama-vllm-apple-silicon-2026)) Two gaps: (a) MeetingScribe explicitly **disables streaming** (`OllamaService.swift:12-13`), so summaries appear as a single late blob instead of streaming token-by-token; (b) it never tells the user to upgrade Ollama / use the MLX backend, leaving free speed on the floor.

### 4. The MCP server is local-only and invisible to the ecosystem
The **official MCP Registry launched Sept 2025 and grew to ~2,000 servers within months**; the **2026-07-28 spec** adds a stateless core + **streamable HTTP transport** so servers run behind ordinary load balancers, plus **elicitation/sampling** for server-initiated prompts. ([MCP Registry](https://registry.modelcontextprotocol.io/), [MCP 2026 RC](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/)) MeetingScribe's server is stdio-only, hand-registered into one client (Claude Desktop), and unpublished — so it can't be discovered, can't serve a remote agent, and rides none of the discovery wave. Separately, **"AI agent memory" is the hot 2026 MCP category** (mem0, Hindsight, mcp-memory-service, memory-graph), all reimplementing a knowledge graph that MeetingScribe **already has** (people graph + memories + FTS5). ([mem0 State of Agent Memory 2026](https://mem0.ai/blog/state-of-ai-agent-memory-2026), [Hindsight](https://hindsight.vectorize.io/blog/2026/03/04/mcp-agent-memory)) MeetingScribe is one HTTP transport + registry listing away from being the *de facto local memory backend for any agent*, not just a meeting tool.

### 5. App↔daemon duplication taxes every infra change twice
`WhisperRunner`/`LiveTranscriber`/`OllamaService` are duplicated and drifting across `Sources/MeetingScribe/` and `Sources/ScribeCore/` (audit report §4, ARCH-1). Any STT/LLM swap below must be done twice until CaptureKit extraction lands — so ARCH-1 is a prerequisite multiplier for everything here.

## Existing-plan items I rank highest (through my lens)

1. **ENG-D — model checksum (done).** Endorsed and verified (`WhisperRunner.swift:260-267`). The right pattern; it must be **extended to every new model** a marketplace/picker introduces (C5-3), with a published manifest of hashes.
2. **Write-capable MCP (done, 5 tools).** The single most important strategic move already made — it turns the read-only vault into an agent-writable surface and is the foundation for the "memory backend" play (C5-7).
3. **ARCH-1 — CaptureKit extraction.** Not just hygiene: it's the **enabling refactor** for swapping the STT engine once instead of twice. Bump its priority because every C5 STT item depends on it.
4. **V3 §4 speaker-labeled transcript + diarization surfacing.** Right feature, wrong engine — endorse the *goal*, but it should be re-pointed at a real diarization model (C5-2) before UI work.
5. **ENG-A — transcript-truncation/coverage gate.** A streaming-STT migration (C5-1) changes the finalize semantics; the coverage gate must be preserved/re-derived, so keep these two coupled.

## NET-NEW recommendations

### C5-1 — Adopt Apple SpeechAnalyzer/SpeechTranscriber as the default STT, whisper.cpp as fallback
**What/why:** On macOS 26 (the user's OS — Tahoe per CLAUDE.md), make Apple's built-in `SpeechAnalyzer`/`SpeechTranscriber` the primary engine: ~55% faster than Whisper-Turbo, zero model download, native streaming, no `brew` dependency. Keep whisper.cpp as the fallback for pre-Tahoe or when a user wants a specific Whisper model. ([MacRumors](https://www.macrumors.com/2025/06/18/apple-transcription-api-faster-than-whisper/))
**User value:** Faster transcripts, instant first-run (no 140MB fetch), one less external dependency, true live streaming captions.
**Effort:** M · **Impact:** High · **Depends on:** ARCH-1 (do the swap once).

### C5-2 — Replace tinydiarize with FluidAudio (or Parakeet Sortformer) real diarization
**What/why:** Drop the regex-on-`--diarize`-markers approach (`SpeakerDiarization.swift:37`) for **FluidAudio**'s CoreML speaker-diarization + VAD Swift Package (MIT/Apache, ANE-native, 60x RT). This makes "who said what" actually work and unblocks speaker-attributed action items. ([FluidAudio](https://github.com/FluidInference/FluidAudio))
**User value:** Reliable speaker labels in 1:1s and multi-party calls; action items attributed to the right person.
**Effort:** M · **Impact:** High · **Depends on:** none (additive SPM dep); pairs with V3 §4.

### C5-3 — Hardware-aware model marketplace / picker
**What/why:** A Settings pane that detects chip + unified-memory (M-series, GB) and recommends a transcription + summarization profile: e.g. "M2 16GB → SpeechAnalyzer + llama3.1:8b"; "M-Max 64GB → WhisperKit Large-v3-Turbo + Qwen3-30B via MLX." Each downloadable model ships a **published SHA-256 manifest** (generalizing ENG-D) and a one-tap install. ([MLX vs Ollama benchmarks](https://willitrunai.com/blog/mlx-vs-ollama-apple-silicon-benchmarks))
**User value:** Users stop running `base.en` on a 64GB machine; the app self-tunes for accuracy vs. battery.
**Effort:** M · **Impact:** Med · **Depends on:** C5-1, C5-5.

### C5-4 — Streaming summarization with live token rendering
**What/why:** Flip Ollama to `stream: true` (`OllamaService.swift:12-13`) and render the summary token-by-token in `MeetingSummaryTab`. Perceived latency drops to near-zero and the user can read while it writes.
**User value:** Summary feels instant; long all-hands summaries become bearable.
**Effort:** S · **Impact:** Med · **Depends on:** none.

### C5-5 — Add a native MLX summarization backend + Ollama-MLX detection
**What/why:** Offer **MLX** (via mlx-swift) as a first-class summarization backend on 32GB+ Macs (up to 3x Ollama-llama.cpp throughput), and detect/recommend **Ollama ≥0.19's MLX backend** when the user stays on Ollama. ([Ollama MLX](https://ollama.com/blog/mlx), [Contra Collective](https://contracollective.com/blog/llama-cpp-vs-mlx-ollama-vllm-apple-silicon-2026))
**User value:** Faster summaries/action-item extraction, lower battery cost, no external server process for users who pick MLX.
**Effort:** L · **Impact:** Med · **Depends on:** ARCH-1, C5-3.

### C5-6 — Optional Apple Foundation Models summarization (zero-dependency tier)
**What/why:** On macOS 26, expose Apple's built-in **Foundation Models** ~3B on-device LLM (`@Generable` guided generation) as a no-install summarization tier — great for users who never want to install Ollama at all. ([Apple FoundationModels](https://developer.apple.com/documentation/FoundationModels), [Apple newsroom](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/))
**User value:** Summaries with literally zero setup; lowest battery footprint; fully Apple-private.
**Effort:** M · **Impact:** Med · **Depends on:** none (gate on OS availability). *Note: 3B is weaker than llama3.1:8b for long transcripts — position as the "no-setup" tier, with `@Generable` structs for reliable action-item extraction.*

### C5-7 — Publish the MCP server to the official registry as a "personal memory backend"
**What/why:** Publish via `mcp-publisher` under `io.github.tyleryannes94/meetingscribe` so any MCP client (not just Claude Desktop) can discover and install it. Reposition the 17 tools as a **local memory backend** — the hot 2026 MCP category — since the people-graph + memories + FTS5 already implement what mem0/Hindsight reinvent. ([MCP publishing](https://modelcontextprotocol.info/tools/registry/publishing/), [mem0 2026](https://mem0.ai/blog/state-of-ai-agent-memory-2026))
**User value:** "Add my meeting memory to any agent." Distribution + a category-defining position.
**Effort:** S (publish) / M (positioning + a `recall/retain/reflect`-style tool facade) · **Impact:** High · **Depends on:** write-MCP (done).

### C5-8 — Add a streamable-HTTP MCP transport (remote/multi-client)
**What/why:** Implement the 2026-07-28 spec's **stateless streamable HTTP transport** so ScribeCore can serve MCP over `localhost:PORT` (and, opt-in, to other devices), beyond stdio-to-one-client. Lets a phone agent or a second Mac query the vault, and future-proofs against the stdio-only ceiling. ([MCP 2026 RC](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/))
**User value:** Use MeetingScribe memory from any agent/device, not just the local Claude Desktop.
**Effort:** M · **Impact:** Med · **Depends on:** ScribeCore daemon (in progress); C5-7.

### C5-9 — MCP elicitation/sampling for human-in-the-loop writes
**What/why:** Adopt the spec's **elicitation** so write tools (`add_person`, `create_action_item`) can ask the user to confirm/disambiguate mid-call ("Is 'Alex' Alex Chen or Alex Rivera?"), and **sampling** so the server can ask the *client's* LLM to draft text without bundling its own. ([MCP 2026 RC](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/), [memory servers](https://deepwiki.com/modelcontextprotocol/servers/2.5-memory-time-and-sequential-thinking-servers))
**User value:** Safer agent writes (no silent wrong-person merges); the server stays model-agnostic.
**Effort:** M · **Impact:** Med · **Depends on:** MCP spec upgrade in the Swift SDK.

### C5-10 — On-device embeddings + semantic recall over the vault
**What/why:** FTS5 is keyword-only; add a local embedding model (MLX/CoreML, e.g. a small Qwen/BGE) and a vector index so `searchAll()` and an MCP `recall` tool do **semantic** retrieval ("the meeting where we argued about pricing"). Pairs with C5-7's memory-backend framing — every competitor memory server ships hybrid BM25+vector. ([Hindsight](https://hindsight.vectorize.io/blog/2026/03/04/mcp-agent-memory))
**User value:** Find meetings/people/decisions by meaning, not exact words.
**Effort:** L · **Impact:** Med · **Depends on:** C5-5 (embedding runtime).

### C5-11 — Live streaming captions during the meeting (not just 5-min chunks)
**What/why:** Today live transcription is 5-min batch chunks. WhisperKit and SpeechAnalyzer both expose true streaming ASR with end-of-utterance detection (Parakeet EOU 120m); surface a live rolling caption pane during recording. ([WhisperKit paper](https://arxiv.org/html/2507.10860v1), [FluidAudio](https://github.com/FluidInference/FluidAudio))
**User value:** Read the conversation as it happens; catch misheard names live.
**Effort:** M · **Impact:** Med · **Depends on:** C5-1 or C5-2 (a streaming engine).

### C5-12 — Per-model benchmark + battery telemetry surfaced to the user
**What/why:** After each transcribe/summary, record RTF, wall-clock, and energy impact per engine/model, and show a tiny "this took 12s at 30x RT on ANE" badge + a Settings comparison. Makes C5-3's picker data-driven and builds user trust that the local stack is fast.
**User value:** Transparency; informed engine choice; proof the app isn't wasting battery.
**Effort:** S · **Impact:** Low · **Depends on:** C5-1/C5-5 (multiple engines to compare).

## Top 3 picks

1. **C5-1 — Apple SpeechAnalyzer as the default STT (whisper.cpp fallback).** Biggest single accuracy+speed+setup win, on the exact OS the user runs, and it kills the `brew install whisper-cpp` + 140MB-download friction. Highest leverage of anything here.
2. **C5-7 — Publish the MCP server to the registry as a "personal memory backend."** Tiny effort, category-defining payoff: MeetingScribe already *is* the agent-memory product everyone else is building from scratch — it just isn't discoverable or framed that way. This is the strategic move to ride the agent wave.
3. **C5-2 — Real diarization via FluidAudio.** Makes the entire planned speaker-labeled-transcript feature actually function instead of silently no-op'ing on the default model.

**Single highest-priority recommendation overall: C5-1** — swapping to Apple's native SpeechAnalyzer/WhisperKit-class engine is the change that most improves the product's core loop (accuracy, speed, first-run friction) for the most users, and it's squarely on the 2026 Apple-Silicon best-practice path.
