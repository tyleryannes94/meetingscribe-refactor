#!/bin/bash
#
# install-sync.sh — set up the one-way MeetingScribe vault backup on the
# WORK MacBook (work -> personal Mac mini HUB over Tailscale).
#
# Run this ON THE WORK MACBOOK. It will:
#   1. Check prerequisites (Tailscale, rsync, the vault).
#   2. Ask for the hub's Tailscale name/IP + login user.
#   3. Create a dedicated SSH key and authorize it on the hub.
#   4. Verify connectivity and create the quarantine folder on the hub.
#   5. Install the sync script + a launchd job that runs every couple of hours.
#   6. Do a dry run, then optionally a first real sync.
#
# Idempotent: safe to re-run to change settings.
# See docs/CROSS_DEVICE_SYNC.md for the full walkthrough.
#
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; }
hdr()  { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
ask()  { # ask "Prompt" "default" -> echoes the answer
  local prompt="$1" def="${2:-}" ans
  if [ -n "$def" ]; then read -r -p "$prompt [$def]: " ans; else read -r -p "$prompt: " ans; fi
  printf '%s' "${ans:-$def}"
}

LABEL="com.tyleryannes.meetingscribe.sync"
BUNDLE_ID="com.tyleryannes.MeetingScribe"
CONFIG_DIR="$HOME/.config/meetingscribe-sync"
CONFIG_FILE="$CONFIG_DIR/config.env"
BIN_DIR="$HOME/.local/bin"
INSTALLED_SCRIPT="$BIN_DIR/meetingscribe-sync.sh"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/MeetingScribe"
SSH_KEY="$HOME/.ssh/meetingscribe_sync"

hdr "MeetingScribe one-way sync — setup (run this on your WORK MacBook)"

# --------------------------------------------------------------------------
# 0. Sanity: this should be macOS.
# --------------------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
  err "This installer is for macOS (your work MacBook). Aborting."
  exit 1
fi

# --------------------------------------------------------------------------
# 1. Prerequisites
# --------------------------------------------------------------------------
hdr "1. Checking prerequisites"

# Tailscale CLI (standalone app or brew cask). Probe a couple of known paths.
TS=""
for cand in tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale /usr/local/bin/tailscale /opt/homebrew/bin/tailscale; do
  if command -v "$cand" >/dev/null 2>&1; then TS="$cand"; break; fi
  [ -x "$cand" ] && { TS="$cand"; break; }
done
if [ -n "$TS" ]; then
  if "$TS" status >/dev/null 2>&1; then ok "Tailscale is running."
  else warn "Tailscale is installed but not connected. Open the Tailscale app and sign in (same account as your Mac mini) before syncing."; fi
else
  warn "Tailscale CLI not found. Install it on THIS Mac and sign in to the SAME tailnet as your Mac mini:"
  say  "    brew install --cask tailscale   # then open it and sign in"
  say  "  (You said it's already on your Mac mini + iPhone — the work MacBook needs it too.)"
fi

# rsync — prefer Homebrew's 3.x over macOS 15's openrsync.
RSYNC=""
for cand in /opt/homebrew/bin/rsync /usr/local/bin/rsync /usr/bin/rsync; do
  [ -x "$cand" ] && { RSYNC="$cand"; break; }
done
if [ -z "$RSYNC" ]; then
  err "No rsync found. Install one:  brew install rsync"; exit 1
fi
RSYNC_VER="$("$RSYNC" --version 2>/dev/null | head -1)"
if printf '%s' "$RSYNC_VER" | grep -qi openrsync; then
  warn "Found openrsync ($RSYNC). It works but Homebrew rsync is more capable. Recommended:  brew install rsync"
else
  ok "rsync: $RSYNC ($RSYNC_VER)"
fi

# Vault path: app's configured storageDir, else the iCloud default.
VAULT_LOCAL="$(defaults read "$BUNDLE_ID" storageDir 2>/dev/null || true)"
[ -n "$VAULT_LOCAL" ] || VAULT_LOCAL="$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"
if [ -d "$VAULT_LOCAL" ]; then ok "Vault: $VAULT_LOCAL"
else warn "Vault folder doesn't exist yet: $VAULT_LOCAL  (it'll be created once MeetingScribe records its first meeting here)"; fi

# --------------------------------------------------------------------------
# 2. Hub connection details
# --------------------------------------------------------------------------
hdr "2. Where is the hub (your personal Mac mini)?"
say "${DIM}On the Mac mini, find these with:  tailscale ip -4   (the 100.x address) or its MagicDNS name, and  whoami${RESET}"

# Pre-fill from existing config if re-running.
[ -f "$CONFIG_FILE" ] && { # shellcheck disable=SC1090
  source "$CONFIG_FILE"; }
HUB_HOST="$(ask "Hub Tailscale name or 100.x IP" "${HUB_HOST:-}")"
HUB_USER="$(ask "Hub login user (whoami on the mini)" "${HUB_USER:-$USER}")"
DEVICE_NAME="$(ask "A short name for THIS Mac (folder on the hub)" "${DEVICE_NAME:-work-macbook}")"
# HUB_VAULT is resolved AFTER the SSH key works (section 3b) by reading the hub
# app's real storageDir — not hardcoded here, which is what silently broke sync
# when the hub stored its vault outside the iCloud default.
INTERVAL_HOURS="$(ask "Sync every how many hours?" "${INTERVAL_HOURS:-2}")"

if [ -z "$HUB_HOST" ]; then err "Hub host is required."; exit 1; fi
case "$INTERVAL_HOURS" in (*[!0-9]*|'') err "Interval must be a whole number of hours."; exit 1;; esac
INTERVAL_SECONDS=$(( INTERVAL_HOURS * 3600 ))

# --------------------------------------------------------------------------
# 3. SSH key + authorize on the hub
# --------------------------------------------------------------------------
hdr "3. SSH key"
if [ -f "$SSH_KEY" ]; then
  ok "Reusing existing key: $SSH_KEY"
else
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "meetingscribe-sync $DEVICE_NAME->hub" >/dev/null
  ok "Created $SSH_KEY"
fi

say "Authorizing this key on the hub (you'll be asked for the hub user's password once)…"
if ssh-copy-id -i "${SSH_KEY}.pub" "$HUB_USER@$HUB_HOST" 2>/dev/null; then
  ok "Key authorized on the hub."
else
  warn "ssh-copy-id didn't complete automatically. Run this once, then re-run the installer:"
  say  "    ssh-copy-id -i ${SSH_KEY}.pub $HUB_USER@$HUB_HOST"
  say  "  (If the hub refuses connections at all: on the mini, enable System Settings -> General -> Sharing -> Remote Login.)"
fi

# Verify non-interactive auth + reachability.
say "Verifying passwordless SSH over the tailnet…"
if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=20 "$HUB_USER@$HUB_HOST" 'echo ok' 2>/dev/null | grep -q ok; then
  ok "SSH to $HUB_USER@$HUB_HOST works without a password."
else
  err "Could not SSH to $HUB_USER@$HUB_HOST with the key."
  say "  Checklist: Tailscale connected on BOTH Macs? Remote Login ON on the mini? Key authorized (step above)?"
  say "  Fix that, then re-run this installer. (Config will be saved so prompts pre-fill.)"
fi

# --------------------------------------------------------------------------
# 3b. Resolve the hub vault — auto-detect the app's configured storageDir on
#     the hub so work files land in the SAME folder the hub app reads. The hub
#     can store its vault anywhere (e.g. ~/Documents/MeetingNotes); hardcoding
#     the iCloud default here is exactly what made files sync but never show up.
# --------------------------------------------------------------------------
hdr "3b. Hub vault location"
HUB_VAULT_FALLBACK='$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault'
HUB_VAULT_DETECTED="$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=20 "$HUB_USER@$HUB_HOST" \
  "defaults read $BUNDLE_ID storageDir 2>/dev/null" 2>/dev/null | tr -d '\r' | head -1)"
if [ -n "$HUB_VAULT_DETECTED" ]; then
  ok "Hub app stores its vault at: $HUB_VAULT_DETECTED"
  HUB_VAULT_DEFAULT="$HUB_VAULT_DETECTED"
else
  warn "Couldn't read the hub app's storageDir over SSH — using the iCloud default."
  say  "  (If the hub keeps its vault elsewhere, override the value below.)"
  HUB_VAULT_DEFAULT="${HUB_VAULT:-$HUB_VAULT_FALLBACK}"
fi
HUB_VAULT="$(ask "Hub vault path (auto-detected — change only if you're sure)" "$HUB_VAULT_DEFAULT")"

# --------------------------------------------------------------------------
# 4. Write config
# --------------------------------------------------------------------------
hdr "4. Writing config"
mkdir -p "$CONFIG_DIR"
# NOTE: HUB_VAULT is written SINGLE-QUOTED so a literal `$HOME` survives `source`
# and is expanded on the HUB (remote) rather than this work Mac. The other values
# are concrete local strings and are double-quoted normally.
cat > "$CONFIG_FILE" <<EOF
# MeetingScribe sync config — written by install-sync.sh on $(date '+%Y-%m-%d %H:%M:%S%z').
# Edit values here; no need to touch the script.
HUB_USER="$HUB_USER"
HUB_HOST="$HUB_HOST"
DEVICE_NAME="$DEVICE_NAME"
HUB_VAULT='$HUB_VAULT'
SSH_KEY="$SSH_KEY"
VAULT_LOCAL="$VAULT_LOCAL"
LOG_DIR="$LOG_DIR"
EOF
chmod 600 "$CONFIG_FILE"
ok "Wrote $CONFIG_FILE"

# Create the quarantine folder on the hub (idempotent).
REMOTE_BASE="$HUB_VAULT/_remote/$DEVICE_NAME"
if ssh -i "$SSH_KEY" -o BatchMode=yes "$HUB_USER@$HUB_HOST" "mkdir -p \"$REMOTE_BASE\"" 2>/dev/null; then
  ok "Hub quarantine ready: _remote/$DEVICE_NAME/"
else
  warn "Couldn't create the hub quarantine folder yet (SSH not working). It'll be created on the first successful sync."
fi

# --------------------------------------------------------------------------
# 5. Install the sync script + launchd job
# --------------------------------------------------------------------------
hdr "5. Installing the sync script + schedule"
mkdir -p "$BIN_DIR" "$LOG_DIR"
install -m 0755 "$SCRIPT_DIR/meetingscribe-sync.sh" "$INSTALLED_SCRIPT"
ok "Installed $INSTALLED_SCRIPT"

# Render the plist from the template.
sed -e "s#@SCRIPT_PATH@#$INSTALLED_SCRIPT#g" \
    -e "s#@INTERVAL_SECONDS@#$INTERVAL_SECONDS#g" \
    -e "s#@LOG_DIR@#$LOG_DIR#g" \
    "$SCRIPT_DIR/com.tyleryannes.meetingscribe.sync.plist.template" > "$PLIST_DEST"
ok "Wrote $PLIST_DEST (every ${INTERVAL_HOURS}h + at login)"

# (Re)load it.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST" 2>/dev/null; then
  ok "Loaded launchd job $LABEL"
else
  # Older macOS fallback.
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  launchctl load "$PLIST_DEST" 2>/dev/null && ok "Loaded launchd job $LABEL (legacy)" || warn "launchctl load reported an issue; check 'launchctl list | grep meetingscribe'."
fi

# --------------------------------------------------------------------------
# 6. Dry run + optional first sync
# --------------------------------------------------------------------------
hdr "6. Test"
say "Running a DRY RUN (no files written)…"
if MEETINGSCRIBE_SYNC_CONFIG="$CONFIG_FILE" bash "$INSTALLED_SCRIPT" --dry-run; then
  ok "Dry run completed. See $LOG_DIR/sync.log for the file list."
else
  warn "Dry run hit an error — check $LOG_DIR/sync.log and the SSH checklist above."
fi

ans="$(ask "Do a real first sync now? (y/N)" "N")"
case "$ans" in
  [yY]*)
    say "Syncing… (first run copies everything; later runs are deltas)"
    if MEETINGSCRIBE_SYNC_CONFIG="$CONFIG_FILE" bash "$INSTALLED_SCRIPT"; then
      ok "First sync done. On the hub, your work data is under  _remote/$DEVICE_NAME/"
    else
      warn "Sync reported an error — check $LOG_DIR/sync.log."
    fi
    ;;
  *) say "Skipped. It'll run automatically every ${INTERVAL_HOURS}h (and at login). Run it now anytime with:"
     say "    bash $INSTALLED_SCRIPT" ;;
esac

hdr "Done."
say "Manage it:"
say "    Run now:     bash $INSTALLED_SCRIPT"
say "    Dry run:     bash $INSTALLED_SCRIPT --dry-run"
say "    Logs:        tail -f $LOG_DIR/sync.log"
say "    Status:      launchctl list | grep meetingscribe"
say "    Change opts: edit $CONFIG_FILE  (or re-run this installer)"
say "    Uninstall:   bash $SCRIPT_DIR/uninstall-sync.sh"
