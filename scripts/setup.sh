#!/usr/bin/env bash
set -euo pipefail

# MeetingScribe one-time setup:
#  1. Ensure Homebrew dependencies (whisper-cpp, ollama, jq) are installed.
#  2. Download a default whisper model if missing.
#  3. Pull the default Ollama model.
#  4. Start the Ollama server (background) if not running.

MODEL="${WHISPER_MODEL:-ggml-base.en.bin}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1:8b}"
NOTES_DIR="${HOME}/Documents/MeetingNotes"
MODEL_DIR="${NOTES_DIR}/models"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }

require_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required: https://brew.sh"
    exit 1
  fi
}

install_brew_pkg() {
  local pkg="$1"
  if brew list --formula --versions "$pkg" >/dev/null 2>&1; then
    bold "✓ $pkg already installed"
  else
    bold "→ brew install $pkg"
    brew install "$pkg"
  fi
}

main() {
  require_brew
  install_brew_pkg whisper-cpp
  install_brew_pkg ollama
  install_brew_pkg jq

  mkdir -p "$MODEL_DIR"
  validate_model() {
    local path="$1"
    # Magic bytes for ggml whisper models: 'lmgg' (little-endian 'ggml').
    local size
    size=$(stat -f%z "$path" 2>/dev/null || echo 0)
    [[ "$size" -lt 1000000 ]] && return 1   # any real whisper model is >1MB
    local head4
    head4=$(head -c 4 "$path" | xxd -p 2>/dev/null)
    [[ "$head4" == "6c6d6767" ]]            # 'lmgg' = 'ggml' little-endian
  }

  if [[ -f "$MODEL_DIR/$MODEL" ]] && validate_model "$MODEL_DIR/$MODEL"; then
    bold "✓ whisper model already present and valid ($MODEL)"
  else
    if [[ -f "$MODEL_DIR/$MODEL" ]]; then
      bold "→ Existing model file is empty or invalid — re-downloading"
      rm -f "$MODEL_DIR/$MODEL"
    fi
    bold "→ Downloading whisper model $MODEL"
    curl -L --fail --progress-bar \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL" \
      -o "$MODEL_DIR/$MODEL"
    if ! validate_model "$MODEL_DIR/$MODEL"; then
      echo "✗ Downloaded model failed validation. Check network / try again." >&2
      exit 1
    fi
    bold "✓ Validated model ($(stat -f%z "$MODEL_DIR/$MODEL") bytes, ggml magic OK)"
  fi

  if ! pgrep -x ollama >/dev/null 2>&1; then
    bold "→ Starting ollama serve in background"
    # Log to the user's notes dir (per-user 700) instead of /tmp (world-readable).
    mkdir -p "$NOTES_DIR/logs"
    nohup ollama serve >>"$NOTES_DIR/logs/ollama.log" 2>&1 &
    sleep 2
  else
    bold "✓ ollama already running"
  fi

  if ! ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$OLLAMA_MODEL"; then
    bold "→ ollama pull $OLLAMA_MODEL"
    ollama pull "$OLLAMA_MODEL"
  else
    bold "✓ ollama model present ($OLLAMA_MODEL)"
  fi

  bold "All set."
  echo "Model:        $MODEL_DIR/$MODEL"
  echo "Ollama model: $OLLAMA_MODEL"
  echo "Notes dir:    $NOTES_DIR"
}

main "$@"
