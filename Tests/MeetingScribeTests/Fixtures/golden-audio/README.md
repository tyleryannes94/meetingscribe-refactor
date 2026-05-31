# Golden-audio transcription fixtures (E5-1)

These drive `GoldenAudioTranscriptionTests`, which runs the **real** bundled
`whisper-cli` against reference audio and asserts the transcript hasn't
regressed (normalized word-error-rate under a threshold). The whisper
subprocess is the product's core value and is otherwise untested — a model
bump or a whisper.cpp upgrade can silently degrade quality with zero signal.

## How to add a fixture

For each reference clip, drop **two files in this directory** with the same base name:

```
my-clip.wav            # 16-bit PCM WAV, mono preferred, ~20–40s of speech
my-clip.expected.txt   # the expected transcript (plain text, lowercase ok)
```

Suggested set (commit short, freely-licensed or synthetic TTS audio only — do
NOT commit real meeting recordings):

- `clean-speech.wav` — one speaker, clear speech.
- `with-silence.wav` — speech with a few seconds of leading/trailing silence.
- `two-overlap.wav` — two voices with a brief overlap.

## How the test scores it

The test normalizes case/punctuation/whitespace on both the expected and the
produced transcript, computes word-level edit distance (WER), and fails if WER
exceeds `GoldenAudioTranscriptionTests.maxWER`. Tune that constant if the
pinned model legitimately changes.

## Running

macOS only, and requires whisper-cli + the pinned `ggml-base.en.bin` model:

```bash
swift test --filter GoldenAudioTranscriptionTests
```

The test **skips** (does not fail) when the whisper binary, the model, or these
fixtures are absent — so CI on a runner without whisper stays green while a
developer Mac with whisper installed gets real coverage.
