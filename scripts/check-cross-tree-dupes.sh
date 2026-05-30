#!/usr/bin/env bash
#
# ARCH-1 guard: stop the cross-tree duplication between Sources/MeetingScribe
# and Sources/ScribeCore from getting worse, and ratchet it down over time.
#
# ~28 audio/transcription files are physically duplicated across the two trees
# and have drifted (see MASTER_PLAN_V3 ARCH-1). The real fix is to extract a
# shared CaptureKit library and delete the copies — but that reconciles
# behavior-bearing recording/transcription code across the GUI app and the
# headless ScribeCore login-item and must be done in a runtime-tested PR.
#
# Until then this guard enforces a baseline allowlist (scripts/capturekit-dup-
# baseline.txt) of the *known* duplicated basenames and:
#   1. FAILS if a NEW cross-tree duplicate appears that isn't in the baseline
#      (don't make the problem bigger).
#   2. FAILS if a baseline entry is no longer duplicated (a file got de-duped or
#      renamed) — you must remove it from the baseline, so the allowlist can
#      only shrink. This is the ratchet.
#
# Exit 0 = clean. Non-zero = action required (printed below).
set -euo pipefail

cd "$(dirname "$0")/.."

baseline="scripts/capturekit-dup-baseline.txt"
[ -f "$baseline" ] || { echo "✗ missing $baseline"; exit 2; }

actual="$(mktemp)"; sorted_baseline="$(mktemp)"
trap 'rm -f "$actual" "$sorted_baseline"' EXIT

comm -12 \
  <(find Sources/MeetingScribe -name '*.swift' -exec basename {} \; | sort -u) \
  <(find Sources/ScribeCore     -name '*.swift' -exec basename {} \; | sort -u) > "$actual"

# Normalize the baseline (ignore blank lines / comments, sort) so hand-edits are forgiving.
grep -vE '^\s*(#|$)' "$baseline" | sort -u > "$sorted_baseline"

new_dups="$(comm -23 "$actual" "$sorted_baseline" || true)"
stale="$(comm -13 "$actual" "$sorted_baseline" || true)"

status=0
if [ -n "$new_dups" ]; then
  status=1
  echo "✗ New cross-tree duplication introduced (file exists under BOTH Sources/MeetingScribe and Sources/ScribeCore):"
  echo "$new_dups" | sed 's/^/    /'
  echo "  → Put shared code in a library both targets depend on, not a second copy."
fi
if [ -n "$stale" ]; then
  status=1
  echo "✗ Baseline lists files that are no longer duplicated — remove them from $baseline (ratchet down):"
  echo "$stale" | sed 's/^/    /'
fi

if [ "$status" -eq 0 ]; then
  echo "✓ No new cross-tree duplication. Baseline: $(wc -l < "$sorted_baseline" | tr -d ' ') known duplicate file(s) pending CaptureKit extraction."
fi
exit "$status"
