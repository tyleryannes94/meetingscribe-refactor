#!/bin/bash
#
# hub-ingest.sh — run the hub-side ingestion engine on the personal Mac mini.
#
# Folds work-device backups from <vault>/_remote/<device>/ into the live second
# brain (deduped, additive, never clobbering your own data). This is the Phase-2
# complement to the rsync transport: rsync DELIVERS work files into _remote/,
# this PROMOTES them into your real Meetings / People / Tasks.
#
# DEFAULT IS A DRY RUN. Pass --apply to actually perform the merge. All arguments
# pass through to the MeetingScribeSync binary, e.g.:
#     bash hub-ingest.sh                 # dry-run report
#     bash hub-ingest.sh --apply         # perform the merge
#     bash hub-ingest.sh --apply -v      # verbose
#     bash hub-ingest.sh --self-test     # verify the merge logic
#
set -u -o pipefail

BUNDLE_ID="com.tyleryannes.MeetingScribe"
LOG="$HOME/Library/Logs/MeetingScribe/ingest.log"
mkdir -p "$(dirname "$LOG")"

# Resolve the storage location the app uses, so the binary targets the same vault.
STORAGE="$(defaults read "$BUNDLE_ID" storageDir 2>/dev/null || true)"
[ -n "$STORAGE" ] && export MEETINGSCRIBE_STORAGE="$STORAGE"

# Find the bundled binary (installed app), else fall back to building from the repo.
BIN=""
for cand in \
  "/Applications/MeetingScribe.app/Contents/MacOS/MeetingScribeSync" \
  "$HOME/Applications/MeetingScribe.app/Contents/MacOS/MeetingScribeSync"; do
  [ -x "$cand" ] && { BIN="$cand"; break; }
done

ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
{
  echo "── $(ts) hub-ingest $* ──"
  if [ -n "$BIN" ]; then
    "$BIN" "$@"
  elif command -v swift >/dev/null 2>&1 && [ -f "Package.swift" ]; then
    swift run -c release MeetingScribeSync "$@"
  else
    echo "✗ MeetingScribeSync not found. Build the app (make app) or run this from the repo root with a Swift toolchain installed." >&2
    exit 1
  fi
} 2>&1 | tee -a "$LOG"

exit "${PIPESTATUS[0]}"
