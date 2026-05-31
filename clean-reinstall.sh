#!/usr/bin/env bash
#
# MeetingScribe — clean uninstall + fresh reinstall.
#
# Per the choices in this Cowork session:
#   • Meeting library at ~/Documents/MeetingNotes  →  BACK UP THEN DELETE
#   • Keychain credentials                          →  KEEP ALL
#   • macOS TCC permissions                         →  KEEP ALL
#   • Claude Desktop MCP config                     →  KEEP ALL
#   • UserDefaults plist                            →  KEEP (not asked; defensive)
#
# Run with: bash ~/MeetingScribeRefactor/clean-reinstall.sh
#
# Read it before you run it. It's intentionally short so you can audit it.

set -euo pipefail

BUNDLE_ID="com.tyleryannes.MeetingScribe"
APP_PATH="/Applications/MeetingScribe.app"
# Rebuild from the REFACTOR repo, never the deprecated ~/MeetingScribe tree.
# (Rebuilding from the old repo recreates the wrong-repo install bug this
# script exists to cure. See E5-7.)
REPO_DIR="$HOME/MeetingScribeRefactor"

# Resolve the meeting library from the app's actual configured storageDir
# rather than hardcoding the legacy ~/Documents/MeetingNotes location (the
# current default is the iCloud Drive vault). Fall back to the iCloud default,
# then the legacy path.
DEFAULT_STORAGE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"
LEGACY_STORAGE="$HOME/Documents/MeetingNotes"
STORAGE_DIR=$(defaults read "$BUNDLE_ID" storageDir 2>/dev/null || true)
if [ -z "${STORAGE_DIR:-}" ]; then
    if [ -d "$DEFAULT_STORAGE" ]; then STORAGE_DIR="$DEFAULT_STORAGE"; else STORAGE_DIR="$LEGACY_STORAGE"; fi
fi
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${STORAGE_DIR}.backup-$TIMESTAMP"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m  %s\n" "$*"; }
err()  { printf "  \033[31m✗\033[0m %s\n" "$*"; }

# ---------- step 0: pre-flight ---------------------------------------------

bold "→ Pre-flight checks"
if [ ! -d "$REPO_DIR" ]; then
    err "Repo not found at $REPO_DIR. Aborting — nothing to rebuild from."
    exit 1
fi
ok "Repo at $REPO_DIR"

# Refuse to proceed if the working tree has unexpected local changes. The
# Makefile's check-version target rewrites Resources/Info.plist on every
# local `make app` (build-stamp side effect), which we tolerate. Anything
# else dirty is a sign the user has uncommitted work — abort to be safe.
cd "$REPO_DIR"

# Assert origin is the refactor repo before we build anything. Rebuilding from
# the legacy meetingscribe repo silently downgrades the install (E5-7).
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
case "$ORIGIN_URL" in
    *meetingscribe-refactor*) ok "origin is the refactor repo ($ORIGIN_URL)" ;;
    *)
        err "origin is '$ORIGIN_URL' — expected a meetingscribe-refactor remote."
        err "Refusing to rebuild from the wrong repo. Aborting."
        exit 1
        ;;
esac

DIRTY=$(git diff --name-only)
UNTRACKED=$(git ls-files --others --exclude-standard)
EXPECTED_DIRTY="Resources/Info.plist"
UNEXPECTED=$(printf '%s\n' "$DIRTY" | grep -vx "$EXPECTED_DIRTY" || true)

# The script itself is untracked the first time you run it — that's expected.
# Filter it out of the "untracked" abort check.
UNTRACKED=$(printf '%s\n' "$UNTRACKED" | grep -vx "clean-reinstall.sh" || true)

if [ -n "$UNEXPECTED" ] || [ -n "$UNTRACKED" ]; then
    err "Repo has local changes I don't recognize:"
    [ -n "$UNEXPECTED" ] && printf "    modified: %s\n" "$UNEXPECTED"
    [ -n "$UNTRACKED" ]  && printf "    untracked: %s\n" "$UNTRACKED"
    err "Commit, stash, or rm them — then re-run."
    exit 1
fi
ok "Working tree clean (or only build-stamped Info.plist)"

# ---------- step 1: stop running processes ---------------------------------

bold "→ Stopping any running MeetingScribe processes"
osascript -e 'tell application "MeetingScribe" to quit' 2>/dev/null || true
sleep 1
pkill -9 -x MeetingScribe       2>/dev/null && ok "killed MeetingScribe"      || ok "MeetingScribe was not running"
pkill -9 -x MeetingScribeMCP    2>/dev/null && ok "killed MeetingScribeMCP"   || ok "MeetingScribeMCP was not running"
pkill -9 -x NotionMCP           2>/dev/null && ok "killed NotionMCP"          || ok "NotionMCP was not running"

# ---------- step 2: back up the meeting library ----------------------------

bold "→ Backing up meeting library"
if [ -d "$STORAGE_DIR" ]; then
    SIZE=$(du -sh "$STORAGE_DIR" 2>/dev/null | cut -f1)
    printf "  source: %s (%s)\n" "$STORAGE_DIR" "$SIZE"
    printf "  target: %s\n" "$BACKUP_DIR"
    mv "$STORAGE_DIR" "$BACKUP_DIR"
    ok "moved (instant rename — no copy required)"
    printf "    restore with: mv %q %q\n" "$BACKUP_DIR" "$STORAGE_DIR"
else
    warn "no library at $STORAGE_DIR — nothing to back up"
fi

# ---------- step 3: remove the app bundle ----------------------------------

bold "→ Removing app bundle"
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
    ok "removed $APP_PATH"
else
    warn "no app at $APP_PATH"
fi

# ---------- step 4: clear derived caches -----------------------------------

bold "→ Clearing derived caches (these regenerate on next launch)"
for path in \
    "$HOME/Library/Caches/$BUNDLE_ID" \
    "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
    "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
    "$HOME/Library/HTTPStorages/$BUNDLE_ID.binarycookies" \
    "$HOME/Library/WebKit/$BUNDLE_ID"
do
    if [ -e "$path" ]; then
        rm -rf "$path"
        ok "removed $path"
    fi
done

# ---------- step 5: what we KEPT (per your choices) ------------------------

bold "→ Kept (per your choices):"
ok "Keychain ($BUNDLE_ID.secrets) — Notion, Linear, Google, Sparkle, Backup AES, etc."
ok "TCC permissions — Mic, Screen Recording, Calendar, Contacts, Notifications, Full Disk Access"
ok "Claude Desktop MCP config (~/Library/Application Support/Claude/claude_desktop_config.json)"
ok "UserDefaults plist (~/Library/Preferences/$BUNDLE_ID.plist) — Whisper paths, Ollama URL, hotkeys, integrations"

# ---------- step 6: sync repo + rebuild ------------------------------------

bold "→ Pulling latest main"
# If Info.plist is the only dirty file (build stamp), throw it away so
# git pull --ff-only succeeds. `make install` will rewrite it.
if [ -n "$DIRTY" ]; then
    git checkout -- Resources/Info.plist
    ok "discarded local Info.plist build-stamp"
fi
git fetch origin
git pull --ff-only origin main
NEW_HEAD=$(git rev-parse --short HEAD)
ok "now at $NEW_HEAD"

bold "→ Rebuilding + installing"
make install
ok "make install completed"

# ---------- step 7: verify -------------------------------------------------

bold "→ Verifying install"
if [ ! -d "$APP_PATH" ]; then
    err "$APP_PATH does not exist after make install — something failed silently"
    exit 1
fi
ok "$APP_PATH exists"

INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
                    "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
ok "Installed CFBundleVersion: $INSTALLED_VERSION"
ok "Pulled git HEAD:           $NEW_HEAD"
if [ "$NEW_HEAD" = "$INSTALLED_VERSION" ]; then
    ok "Versions match"
else
    warn "Versions don't match. The check-version Makefile target should stamp HEAD into Info.plist; if it didn't, run 'make app' again or check the Makefile."
fi

# Sparkle public key sanity (we KEPT the keychain entry, so the build should
# have a real key in Info.plist now).
PLACEHOLDER="REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
if /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' \
   "$APP_PATH/Contents/Info.plist" 2>/dev/null | grep -q "$PLACEHOLDER"; then
    warn "Installed app's SUPublicEDKey is the placeholder — auto-update verification is OFF."
    warn "Run ./scripts/setup-sparkle-key.sh in the repo to fix."
else
    ok "Sparkle public key present (auto-update verification ON)"
fi

# ---------- step 8: hand off -----------------------------------------------

bold "→ Done."
echo
echo "  Launch:           open $APP_PATH"
echo "  Restore library:  mv $BACKUP_DIR $STORAGE_DIR"
echo "  Trash backup:     rm -rf $BACKUP_DIR    # only after you're sure"
echo
echo "  First launch will show empty Today / People / Meetings tabs."
echo "  Your integrations should reconnect automatically (Keychain creds preserved)."
echo "  TCC permissions stay granted — no re-prompts."
