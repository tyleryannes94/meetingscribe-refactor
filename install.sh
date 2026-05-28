#!/usr/bin/env bash
#
# MeetingScribe — one-shot installer.
#
# What this does (idempotent — safe to re-run):
#   1. Verifies macOS 14+ and Xcode CLT.
#   2. Installs Homebrew if missing.
#   3. Installs whisper-cpp + ollama + jq (via brew).
#   4. Downloads the default whisper model and verifies its magic bytes.
#   5. Pulls the default Ollama model (llama3.1:8b) and starts ollama serve.
#   6. Creates a self-signed code-signing certificate ("MeetingScribe Local
#      Signer") in your login keychain so TCC permissions survive rebuilds.
#   7. Builds the app + MCP server and signs them with that identity.
#   8. Installs MeetingScribe.app to /Applications and launches it.
#
# What you still need to do manually (macOS won't let scripts do these):
#   • Click "Always Allow" on the keychain dialog the first time codesign
#     uses the new cert (it appears during step 7).
#   • Grant Microphone, Screen Recording, and Calendar (Full Access) permissions
#     the first time the app asks for them (during normal use).
#   • Re-launch the app once after granting Screen Recording (macOS quirk).
#
# Usage:
#   ./install.sh
set -euo pipefail

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }
step()  { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

# -- 1. OS check ---------------------------------------------------------------
step "1/8 Verifying macOS"
if [[ "$(uname)" != "Darwin" ]]; then
    red "MeetingScribe is macOS-only. Aborting."
    exit 1
fi
OS_VER=$(sw_vers -productVersion)
OS_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
if [[ "$OS_MAJOR" -lt 14 ]]; then
    red "macOS 14 (Sonoma) or newer required. You have $OS_VER."
    exit 1
fi
green "✓ macOS $OS_VER"

# -- 2. Xcode CLT --------------------------------------------------------------
step "2/8 Verifying Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
    bold "→ Installing Xcode Command Line Tools (a system dialog will appear)…"
    xcode-select --install || true
    echo "Wait for the install to finish in the dialog, then re-run ./install.sh"
    exit 1
fi
green "✓ Xcode CLT at $(xcode-select -p)"

# -- 3. Homebrew ---------------------------------------------------------------
step "3/8 Verifying Homebrew"
if ! command -v brew >/dev/null 2>&1; then
    red "✗ Homebrew is not installed."
    cat <<'EOF'

    MeetingScribe needs Homebrew to install whisper-cpp, ollama, and jq.
    Rather than silently piping curl into bash from here (which would make
    this script vouch for whoever happens to control brew.sh today), please
    install Homebrew yourself first by following the instructions at:

        https://brew.sh

    Then re-run ./install.sh

EOF
    exit 1
fi
green "✓ Homebrew at $(brew --prefix)"

# -- 4. Dependencies + whisper model -------------------------------------------
step "4/8 Installing whisper-cpp + ollama + jq, downloading default model"
./scripts/setup.sh

# -- 5. Code-signing certificate -----------------------------------------------
step "5/8 Setting up self-signed code-signing identity"
./scripts/create-signing-cert.sh

# -- 6. Build the app ----------------------------------------------------------
step "6/8 Building MeetingScribe + MeetingScribeMCP"
echo "If macOS shows a 'codesign wants to use your keychain' dialog,"
echo "click 'Always Allow' so future builds don't prompt."
make install

# -- 7. Launch -----------------------------------------------------------------
step "7/8 Launching MeetingScribe"
/usr/bin/open /Applications/MeetingScribe.app
sleep 2

# -- 8. Permission reminders ---------------------------------------------------
step "8/8 First-run reminders"
cat <<'EOF'

  As you use the app, macOS will prompt for:

    • Microphone        — first time you record
    • Screen Recording  — required for system-audio capture
                          (after granting, QUIT + RELAUNCH the app)
    • Calendar          — when the main window opens
    • Notifications     — for "meeting starting" prompts
    • Accessibility     — only if you use the F5 dictation hotkey
                          (so it can paste at the cursor)

  Optional MCP setup for Claude Desktop / Claude Code:
    Open the app → Settings → MCP Server → "Install in Claude Desktop"
    Then restart Claude Desktop and ask it to list your meetings.

EOF

green "✓ Install complete. Look for the waveform icon in the menu bar (top-right)."
