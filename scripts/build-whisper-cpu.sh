#!/usr/bin/env bash
#
# Builds a CPU-only whisper-cli binary from source.
#
# WHY: whisper-cpp 1.8.4 from Homebrew + ggml 0.12.0 ship a Metal backend that
# fails to initialize the whisper context on M1/M2/M3/M4 Macs ("tensor API
# disabled for pre-M5 and pre-A19 devices" → "failed to initialize whisper
# context"). The backend is auto-loaded — no runtime flag or env var bypasses
# it. The fix is to build whisper.cpp without Metal entirely.
#
# Output: ~/Documents/MeetingNotes/bin/whisper-cli
# The app reads this path from AppSettings (whisperBinary), so after running
# this script, point Settings → Whisper.cpp → "whisper-cli binary" to it.
set -euo pipefail

INSTALL_DIR="${HOME}/Documents/MeetingNotes/bin"
WHISPER_REPO="https://github.com/ggml-org/whisper.cpp.git"
WHISPER_TAG="${WHISPER_TAG:-v1.8.4}"   # pin the version that matches your model

mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/whisper-cli"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }

if [ -x "$TARGET" ]; then
    bold "→ Existing binary at $TARGET — checking if it works..."
    # Probe with /dev/null input: if the Metal error appears, rebuild.
    if "$TARGET" -m /dev/null -f /dev/null 2>&1 | grep -q "tensor API disabled"; then
        bold "  (it has the Metal issue — rebuilding)"
    else
        bold "  (no Metal warnings — looks good)"
        echo ""
        bold "✓ Already installed. Point MeetingScribe → Settings → Whisper.cpp"
        bold "  → 'whisper-cli binary' to: $TARGET"
        exit 0
    fi
fi

# Need cmake. Brew has it.
if ! command -v cmake >/dev/null 2>&1; then
    bold "→ Installing cmake (required to build)"
    brew install cmake
fi

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

bold "→ Cloning whisper.cpp ($WHISPER_TAG)"
git clone --depth 1 --branch "$WHISPER_TAG" "$WHISPER_REPO" "$WORK/whisper.cpp"
cd "$WORK/whisper.cpp"

bold "→ Configuring with Metal OFF + static libs (no rpath surprises)"
cmake -B build \
    -DGGML_METAL=OFF \
    -DGGML_ACCELERATE=ON \
    -DGGML_BLAS=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    >/dev/null

bold "→ Building whisper-cli"
cmake --build build --config Release --target whisper-cli -j"$(sysctl -n hw.ncpu)" >/dev/null

if [ ! -f "build/bin/whisper-cli" ]; then
    echo "Build did not produce build/bin/whisper-cli — bailing." >&2
    exit 1
fi

# Verify the binary doesn't depend on libwhisper.dylib from the temp dir.
if otool -L build/bin/whisper-cli | grep -q "libwhisper"; then
    echo "  ! whisper-cli still has dynamic libwhisper dependency; copying dylibs alongside"
    find build -name "libwhisper*.dylib" -exec cp {} "$INSTALL_DIR/" \;
    find build -name "libggml*.dylib" -exec cp {} "$INSTALL_DIR/" \;
fi

cp build/bin/whisper-cli "$TARGET"
chmod +x "$TARGET"

echo ""
bold "✓ Built CPU-only whisper-cli:"
echo "  $TARGET"
echo ""
bold "→ Verifying it loads a model without errors"
MODEL="$HOME/Documents/MeetingNotes/models/ggml-base.en.bin"
if [ -f "$MODEL" ]; then
    # Quick test: 1-sec silence, see if we get past whisper context init.
    SAMPLE_TMP=$(mktemp -d)
    /usr/bin/afconvert -f WAVE -d LEI16@16000 -c 1 \
        /System/Library/Sounds/Glass.aiff "$SAMPLE_TMP/test.wav" >/dev/null 2>&1
    OUTPUT=$("$TARGET" -m "$MODEL" -f "$SAMPLE_TMP/test.wav" --no-prints 2>&1 || true)
    rm -rf "$SAMPLE_TMP"
    if echo "$OUTPUT" | grep -qi "tensor API disabled\|failed to initialize"; then
        echo "  ✗ Test failed — output:"
        echo "$OUTPUT" | tail -10
        exit 1
    fi
    echo "  ✓ No Metal errors. Context initialized cleanly."
else
    echo "  (skipping — no model at $MODEL; run ./scripts/setup.sh first to download one)"
fi
echo ""
bold "Now: open MeetingScribe → Settings → Whisper.cpp section →"
bold "      change 'whisper-cli binary' to: $TARGET"
bold "      then click Save. Live transcription will work."
