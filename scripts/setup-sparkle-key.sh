#!/usr/bin/env bash
#
# One-time Sparkle EdDSA keypair setup for MeetingScribe auto-updates.
#
# What this does
# --------------
#   1. Locates Sparkle's `generate_keys` tool (under .build/.../sparkle/Sparkle/bin
#      after `swift build`, or in a Sparkle tarball you point at with
#      SPARKLE_BIN=/path/to/bin).
#   2. Generates an EdDSA keypair. The PRIVATE key goes into your login
#      keychain (Sparkle's default); the PUBLIC key is printed.
#   3. Patches Resources/Info.plist, replacing the placeholder
#      `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY` with the real public key.
#   4. Exports the private key to /tmp/sparkle_private_key.pem and prints it
#      so you can paste it into the GitHub `SPARKLE_PRIVATE_KEY` repo secret.
#   5. Prints a verification checklist.
#
# Safety
# ------
#   • Idempotent: re-running it is safe. If the public key in Info.plist is
#     already non-placeholder, the script refuses to clobber it without
#     `--force`. If the keychain already has a Sparkle key, `generate_keys`
#     will export the existing one rather than creating a new one.
#   • Never commits the private key. /tmp/sparkle_private_key.pem is deleted
#     unless you pass `--keep-private-key-file`.
#   • Self-checks the patched Info.plist with PlistBuddy before exiting.
#
# Usage
# -----
#   ./scripts/setup-sparkle-key.sh                 # standard one-time setup
#   ./scripts/setup-sparkle-key.sh --force         # overwrite a real key (dangerous)
#   ./scripts/setup-sparkle-key.sh --keep-private-key-file
#   SPARKLE_BIN=~/Downloads/Sparkle-2.6.4/bin ./scripts/setup-sparkle-key.sh

set -euo pipefail

# ---------- argument parsing ------------------------------------------------

FORCE=0
KEEP_PRIVATE_FILE=0
for arg in "$@"; do
    case "$arg" in
        --force)                       FORCE=1 ;;
        --keep-private-key-file)       KEEP_PRIVATE_FILE=1 ;;
        -h|--help)
            sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//;/^set -euo pipefail$/d'
            exit 0
            ;;
        *)
            echo "✗ Unknown option: $arg  (use --help)"
            exit 64
            ;;
    esac
done

# ---------- locate repo + Info.plist ----------------------------------------

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
INFO_PLIST="$REPO_ROOT/Resources/Info.plist"
PLACEHOLDER="REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
PRIVATE_FILE="/tmp/sparkle_private_key.pem"

if [ ! -f "$INFO_PLIST" ]; then
    echo "✗ Could not find $INFO_PLIST"
    echo "  Run this script from inside the MeetingScribe repo."
    exit 1
fi

current_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$current_key" ]; then
    echo "✗ Info.plist has no SUPublicEDKey entry. Add one (any value) and re-run."
    exit 1
fi
if [ "$current_key" != "$PLACEHOLDER" ] && [ "$FORCE" != "1" ]; then
    echo "✓ SUPublicEDKey is already set to a non-placeholder value:"
    echo "    $current_key"
    echo
    echo "  Nothing to do. Pass --force to overwrite (only do this if you've"
    echo "  rotated the keypair and updated the GitHub SPARKLE_PRIVATE_KEY"
    echo "  secret to match)."
    exit 0
fi

# ---------- locate generate_keys --------------------------------------------

GEN_KEYS="${SPARKLE_BIN:-}"
if [ -n "$GEN_KEYS" ]; then
    GEN_KEYS="$GEN_KEYS/generate_keys"
fi
if [ -z "${GEN_KEYS}" ] || [ ! -x "$GEN_KEYS" ]; then
    # Search SwiftPM's resolved Sparkle artifact first.
    found=$(find "$REPO_ROOT/.build" -path '*/Sparkle/bin/generate_keys' -type f 2>/dev/null | head -1 || true)
    if [ -n "$found" ]; then
        GEN_KEYS="$found"
    fi
fi
if [ -z "$GEN_KEYS" ] || [ ! -x "$GEN_KEYS" ]; then
    # Fall back to Developer DerivedData (Xcode/SPM caches Sparkle there too).
    found=$(find "$HOME/Library/Developer" -path '*/Sparkle/bin/generate_keys' -type f 2>/dev/null | head -1 || true)
    if [ -n "$found" ]; then
        GEN_KEYS="$found"
    fi
fi
if [ -z "$GEN_KEYS" ] || [ ! -x "$GEN_KEYS" ]; then
    echo "✗ Could not locate Sparkle's generate_keys binary."
    echo
    echo "  Run 'swift build -c release' first (downloads + builds Sparkle),"
    echo "  or download a Sparkle tarball from"
    echo "  https://github.com/sparkle-project/Sparkle/releases and point"
    echo "  this script at its bin/ directory:"
    echo
    echo "    SPARKLE_BIN=~/Downloads/Sparkle-2.6.4/bin ./scripts/setup-sparkle-key.sh"
    exit 2
fi
echo "→ Using Sparkle tools at: $GEN_KEYS"

# ---------- generate or recover the keypair ---------------------------------

# `generate_keys` (no args) either:
#   • finds an existing private key in the login keychain and prints its
#     public counterpart, OR
#   • generates a fresh keypair, stores the private key in the keychain,
#     and prints the public part.
echo "→ Generating/recovering EdDSA keypair (private key lives in your login keychain)..."
GEN_OUT="$("$GEN_KEYS" 2>&1)"

# generate_keys prints a banner + the public key, sometimes on its own line,
# sometimes prefixed with "Public key:". The key is a base64 blob made of
# [A-Za-z0-9+/] with 0-2 '=' of padding, at least 40 chars long (Ed25519
# keys are 32 bytes = 44 base64 chars with padding). grep -oE pulls the
# first such blob regardless of surrounding text.
#
# (Earlier versions used awk here, but awk's /regex/ literal can't contain
# an unescaped '/' even inside a character class, which broke parsing.)
PUBLIC_KEY=$(printf '%s\n' "$GEN_OUT" | grep -oE '[A-Za-z0-9+/]{40,}={0,2}' | head -1)
if [ -z "$PUBLIC_KEY" ]; then
    echo "✗ Could not parse the public key from generate_keys output:"
    echo "------------------------------------------------------------------"
    printf '%s\n' "$GEN_OUT"
    echo "------------------------------------------------------------------"
    echo "  Run '$GEN_KEYS' manually, copy the printed public key, and paste"
    echo "  it into Resources/Info.plist :SUPublicEDKey."
    exit 3
fi
echo "✓ Public key:  $PUBLIC_KEY"

# ---------- patch Info.plist ------------------------------------------------

echo "→ Patching $INFO_PLIST :SUPublicEDKey"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$INFO_PLIST"

# Re-read what's actually on disk now and confirm the bytes match what
# generate_keys printed. Cheap to do; catches a corrupted PlistBuddy run.
read_back="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")"
if [ "$read_back" != "$PUBLIC_KEY" ]; then
    echo "✗ Info.plist read-back didn't match the generated public key."
    echo "  Wanted: $PUBLIC_KEY"
    echo "  Got:    $read_back"
    exit 4
fi
echo "✓ Info.plist patched and verified."

# Confirm the make target's guard is now happy (without invoking the rest
# of the build).
if grep -q "$PLACEHOLDER" "$INFO_PLIST"; then
    echo "✗ Placeholder string still present in Info.plist (unexpected). Aborting."
    exit 5
fi

# ---------- export private key for GitHub Actions ---------------------------

echo "→ Exporting private key to $PRIVATE_FILE for the GitHub Actions secret..."
"$GEN_KEYS" -x "$PRIVATE_FILE" >/dev/null
chmod 600 "$PRIVATE_FILE"

cat <<EOF

================================================================================
NEXT STEP — add the private key as a GitHub Actions secret
================================================================================

1. Open: https://github.com/tyleryannes94/meetingscribe/settings/secrets/actions
2. Click "New repository secret"
3. Name:   SPARKLE_PRIVATE_KEY
4. Value:  paste the contents of $PRIVATE_FILE

Contents (copy exactly, including line breaks):

--------------------------------------------------------------------------------
EOF
cat "$PRIVATE_FILE"
cat <<EOF
--------------------------------------------------------------------------------

EOF

if [ "$KEEP_PRIVATE_FILE" = "1" ]; then
    echo "⚠  --keep-private-key-file set: leaving $PRIVATE_FILE on disk."
    echo "   Delete it once you've pasted it into the GitHub secret."
else
    rm -f "$PRIVATE_FILE"
    echo "✓ Deleted $PRIVATE_FILE (the private key still lives in your login keychain)."
fi

# ---------- post-flight checklist -------------------------------------------

cat <<EOF

================================================================================
VERIFICATION CHECKLIST
================================================================================
  [ ] Resources/Info.plist :SUPublicEDKey set to the real public key
        (currently: $PUBLIC_KEY)
  [ ] GitHub secret SPARKLE_PRIVATE_KEY added (paste from above)
  [ ] Commit Resources/Info.plist on a branch and PR (the public key is
      safe to commit; only the private key is sensitive)
  [ ] Run 'make install' — the placeholder guard should pass and the app
      installs to /Applications cleanly
  [ ] Tag a release (e.g. v0.1.1) to confirm the CI release workflow
      signs the archive with the new private key

If anything in this list is unchecked, auto-updates either won't work or
won't be verifiable. See RELEASING.md for the full release flow.
EOF
