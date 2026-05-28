#!/usr/bin/env python3
"""Transcribe the two uploaded audio files using faster-whisper."""

import subprocess, sys

# Install faster-whisper if needed
try:
    from faster_whisper import WhisperModel
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "faster-whisper",
                    "--break-system-packages", "-q"], check=True)
    from faster_whisper import WhisperModel

UPLOADS = "/Users/tyleryannes/Library/Application Support/Claude/local-agent-mode-sessions/79e12b51-78a9-4d8c-9bca-941daaf07fdf/8510e996-400f-414f-bdc6-0d1cc5d17c54/local_6573fb04-af85-4ab7-bdb0-7e41d11d9904/uploads"

files = {
    "system-001.m4a": f"{UPLOADS}/system-001.m4a",
    "mic-001.m4a":    f"{UPLOADS}/mic-001.m4a",
}

model = WhisperModel("base", device="cpu", compute_type="int8")

results = {}
for name, path in files.items():
    print(f"Transcribing {name} ...", flush=True)
    segments, info = model.transcribe(path, beam_size=5)
    text = " ".join(seg.text.strip() for seg in segments)
    results[name] = text
    print(f"  [{name}]: {text}\n", flush=True)

# Write output file
out_path = "/Users/tyleryannes/MeetingScribe/transcripts.txt"
with open(out_path, "w") as f:
    for name, text in results.items():
        f.write(f"=== {name} ===\n{text}\n\n")

print(f"Done — saved to {out_path}")
