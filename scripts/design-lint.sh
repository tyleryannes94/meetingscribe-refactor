#!/usr/bin/env bash
#
# design-lint.sh — guards the design-system migration (whole-app refresh).
#
# Flags the three drift classes the refresh is consolidating:
#   1. raw `.font(.system(size:))`            → use NDS type tokens / scaledFont()
#   2. raw priority/status colors             → use NDS.priority()/NDS.status()
#   3. cold AppKit surface colors in UI/      → use NDS.fieldBg/rowHover/hairline
#
# Modes:
#   warn  (default) — print violations, always exit 0. Used during migration.
#   fail            — print violations, exit 1 if any remain. Flipped on in Phase 5.
#
# Usage: scripts/design-lint.sh [warn|fail]

set -uo pipefail
MODE="${1:-warn}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIRS=("$ROOT/Sources/MeetingScribe/UI" "$ROOT/Sources/MeetingScribe/People")

total=0

scan() {
    local label="$1" pattern="$2"; shift 2
    local hits
    hits="$(grep -rnE --include='*.swift' "$pattern" "${UI_DIRS[@]}" 2>/dev/null \
            | grep -vE '// *design-lint:allow' || true)"
    if [[ -n "$hits" ]]; then
        local n; n="$(printf '%s\n' "$hits" | grep -c .)"
        total=$((total + n))
        echo "── $label ($n) ────────────────────────────────"
        printf '%s\n' "$hits" | sed "s#$ROOT/##"
        echo
    fi
}

# 1. Raw fixed-point fonts (Dynamic Type lockout). NDS tokens + scaledFont() are exempt.
scan "raw .font(.system(size:))" '\.system\(size: *[0-9]'

# 2. Raw priority/status colors — should route through NDS.priority()/status()/due().
#    Heuristic: a `case .(low|medium|high|urgent|open|inProgress|completed):` line that
#    returns a raw system color.
scan "raw priority/status color" 'case \.(low|medium|high|urgent|open|inProgress|completed):.*return \.(red|orange|yellow|green|blue|gray)'

# 3. Cold AppKit surface colors — should be NDS.fieldBg/rowHover/hairline/columnBg.
scan "cold AppKit surface color" 'Color\(NSColor\.(controlBackgroundColor|separatorColor|windowBackgroundColor|textBackgroundColor)\)'

echo "design-lint: $total violation(s) in tracked drift classes."

if [[ "$MODE" == "fail" && "$total" -gt 0 ]]; then
    echo "design-lint: FAIL (mode=fail). Route these through NDS, or annotate an"
    echo "intentional exception with a trailing  // design-lint:allow  comment."
    exit 1
fi
exit 0
