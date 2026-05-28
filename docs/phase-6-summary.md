# Phase 6 — Local AI Media Generation

> **Update — scoped to what runs on 16 GB RAM (image-only):** after a RAM-fit
> review for a 16 GB Mac mini, media generation is **Core ML Stable Diffusion
> only** (SD 1.5 / 2.1, CreativeML OpenRAIL-M — free), run **in-process** via the
> linked `apple/ml-stable-diffusion` `StableDiffusionPipeline` with
> `reduceMemory` (peak ~2–4 GB — comfortable on 16 GB, no Python).
>
> **Removed** because they exceed 16 GB of unified memory on this machine:
> FLUX.1 schnell + SDXL-Turbo (MLX) and **all video generation** (Wan2.1 /
> `VideoGeneration*`). The model picker now lists only the Core ML SD variants.
>
> Generated output now lives in a dedicated top-level **Media** page
> (Library + Create). `downloadModel` fetches Core ML weights via the `hf` CLI
> from an app-managed Python venv.

## What was built/changed

Fully on-device image generation (and the architecture for future video), in
keeping with MeetingScribe's local-first, no-cloud, no-API-keys model.

1. **Image generation engine** — an actor that drives a local generator
   out-of-process (MLX Python CLI for SDXL-turbo/FLUX; Apple's Core ML
   `ml-stable-diffusion` for SD 1.5/2.1).
2. **Image generation UI** — full generator, gallery, a per-meeting "AI Visuals"
   tab, and a settings pane.
3. **Meeting-aware prompt builder** — offline keyword extraction → a suggested
   visualization prompt (no Ollama call).
4. **Video generation foundation** — protocol + actor + stub UI ("coming soon").
5. **Package.swift** — added the `apple/ml-stable-diffusion` (`StableDiffusion`)
   dependency.

## Files created / modified

**Created — `Sources/MeetingScribe/MediaGeneration/`:**
- `SDModelVariant.swift` — `.coreML_SD15 / .coreML_SD21 / .mlx_SDXL / .mlx_FLUX` with size/speed/URL/defaults.
- `GenerationRequest.swift` — request value type (model-aware defaults).
- `GeneratedImage.swift` — persisted image metadata.
- `GeneratedMediaStore.swift` — `@MainActor @Observable` JSON-backed store in App Support; writes PNGs.
- `ImageGenerationService.swift` — `actor`; `isAvailable`/`isGenerating`/`progress`, `generate(...) -> CGImage`, `cancelGeneration()`, `downloadModel(_:)`.
- `MeetingPromptBuilder.swift` — `build(meeting:summary:actionItems:) -> (prompt, negativePrompt)`.
- `ImageGeneratorView.swift` — main UI (+ `ImageGenViewModel` to mirror actor progress on the main actor).
- `MediaGalleryView.swift` — grid gallery with Images/Video sections, sort, meeting filter, context menu.
- `MeetingImageSidebarView.swift` — the "AI Visuals" meeting tab.
- `ImageGenerationSettingsView.swift` — default model, storage, retention, downloads, clear cache.

**Created — `Sources/MeetingScribe/MediaGeneration/Video/`:**
- `VideoGenerationModel.swift` — `VideoModelVariant` (Wan2.1 MLX / AnimateDiff Core ML).
- `VideoGenerationService.swift` — `VideoGenerationBackend` protocol + `actor VideoGenerationService` (`isAvailable = false`).
- `VideoGeneratorView.swift` — "coming soon" card + notify-me field.

**Modified:**
- `Package.swift` — added `apple/ml-stable-diffusion` dependency + `StableDiffusion` to the app target; MLX-Python setup noted in a comment.
- `Sources/MeetingScribe/UI/UnifiedMeetingDetail.swift` — new `DetailTab.visuals` + `visualsBody` (the "AI Visuals" tab).
- (plus the Phase 0 foundation build fix so this branch builds standalone off main)

## How to use

1. **Get a model:** Settings → Image Generation → Download Models. FLUX schnell
   (MLX) is the recommended default — fastest on Apple Silicon, ~4 steps, no
   guidance. MLX variants need Python + mlx (`brew install python@3.11 && pip
   install mlx diffusers`); Core ML variants use the bundled Swift package.
2. **Generate standalone:** open the Image Generator, enter a prompt, pick a
   model, Generate. Results auto-save to your media gallery; Copy / Save to
   Desktop / Regenerate from the result.
3. **Generate for a meeting:** open a meeting → **AI Visuals** tab → "Generate
   image for this meeting." The prompt is pre-filled from the meeting's
   title/summary/action items (MeetingPromptBuilder), and the result is linked
   to that meeting.
4. **Browse:** MediaGalleryView shows everything, filterable by meeting; the
   Video tab is a placeholder.

## Important deviations / notes for the next developer

- **`meetingID` is `String?`, not the spec's `UUID?`** — to match the app's
  real `Meeting.id` (a String) so images actually link to meetings.
- **Engine runs out-of-process.** `ImageGenerationService` does NOT
  `import StableDiffusion`; it shells out to a generator CLI (MLX Python, or the
  Core ML `StableDiffusionSample` tool). This keeps the app from hard-linking a
  heavy ML runtime and means the code compiles even if the model/CLI isn't
  installed (it surfaces a clear "not installed / not downloaded" error). A
  future revision can call `StableDiffusionPipeline` from the now-linked
  `StableDiffusion` package directly for the Core ML path.
- **The `apple/ml-stable-diffusion` dependency resolves and builds** (v1.1.1,
  pulls swift-argument-parser). `Package.resolved` is gitignored by this repo,
  so it isn't committed.
- **Progress** is mirrored from the actor to SwiftUI via `ImageGenViewModel` (a
  `@MainActor @Observable`) since SwiftUI can't observe an actor directly.
- **Video is a stub** (`VideoGenerationService.isAvailable == false`). Wire a
  `VideoGenerationBackend` (Wan2.1 MLX) when Apple-Silicon video models mature;
  the protocol seam is ready.
- The new views aren't yet inserted into the main nav / SettingsView — host
  `ImageGeneratorView`, `MediaGalleryView`, and `ImageGenerationSettingsView`
  where appropriate (the per-meeting tab IS wired).
