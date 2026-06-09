# Whole-App Visual + Accessibility Refresh

**Branch merged to `main`:** `design/whole-app-refresh` (phases 0–5, commits `ef4bbd4` → `b087322`)
**Status:** complete & merged. Local build clean, **134 tests pass** (was 126), design-lint **0 violations** in fail mode.
**Scope decided with the owner:** whole-app pass, *plan-first*, **full program incl. deep a11y**, **with CI lint enforcement**.

---

## Why this happened

The Phase 3/4/6 work shipped the Tasks **features** (calendar/gallery/board, quick-add, undo, CSV, reminders…)
but the **visual design refresh specced alongside them never landed**. Each feature PR styled its own view
ad-hoc, so the app looked piecemeal. The root cause was **adoption + drift, not a missing design system**:

- A mature system already existed — `NotionDesign.swift` (`NDS`: warm light/dark palette, `brand` purple,
  Dynamic-Type type scale, `motion()` reduce-motion gate, `scaledFont()`, button family) and
  `MSComponents.swift` (`msCard()`, `MSEmptyState`, `MSSectionHeader`, `MSSearchField`, `MSSkeleton`).
- But ~50% of files — the densest ones (ActionItems, Chat, Settings, Meetings) — **opted out**: cold
  `Color(NSColor.controlBackgroundColor)` surfaces (a warm/cold seam), priority/status colors redefined raw
  in 7+ files, `Color.accentColor` (system blue) instead of `NDS.brand`, ~245 raw `.font(.system(size:))`
  (Dynamic-Type lockout).

The fix was to **adopt the existing system everywhere, consolidate the drift, and lock it in with CI lint.**

---

## What shipped, by phase

| Phase | What | Result |
|---|---|---|
| **0 — Tokens** | `NDS.priority()/status()/due()` (warm palette + glyph redundancy) replacing 6 duplicated local switches; `Color.accentColor`→`NDS.brand`; spacing scale, motion constants, icon-weight helper; `scripts/design-lint.sh` (warn). | Color-drift class → **0**. Brand renders purple everywhere. |
| **1 — Components** | `MSAvatar`/`MSAvatarStack` (`TaskOwnerAvatar` now wraps it), `DueChip` (relative phrasing), `MSStatusBadge`/`MSPriorityBadge` (color **+ glyph**), `SymbolPicker`, and a hidden `ComponentGallery` QA surface. | Shared layer to build on. |
| **2 — Warm/cold seam** | Replaced every `Color(NSColor.*BackgroundColor)`/`separatorColor` in board, chat, search, Today, quick-notes, project page, markdown editor, follow-ups with `NDS` tokens; added `NDS.columnBg`. | Cold-surface class → **0**. |
| **3 — Reskins** | Board cards: priority accent bar + `MSPriorityBadge` + `DueChip` + avatar. Table priority/due cells use the shared badge/chip. People rows get real `MSAvatar` monograms. MainWindow tab transition → `NDS.springStandard`. | Highest-traffic surfaces visibly upgraded. |
| **4 — Deep a11y** | ~234 fixed fonts → `scaledFont` (Dynamic Type app-wide); contrast-retune of `textSecondary/textTertiary` + WCAG helpers + `DesignContrastTests`; reduce-motion gating on the tab transition; status/priority carry glyphs (color-independent). | Font-drift class → **0**; +4 contrast tests. |
| **5 — Enforcement** | `design-lint.sh` flipped to **fail** and wired into CI (`.github/workflows/ci.yml`) as a ratchet; `DesignSnapshotTests` render the gallery + components in light/dark via `ImageRenderer`. | Drift can't silently return; +4 snapshot tests. |

**Totals:** 60 files changed, +948 / −416. Drift **256 → 0**. Tests **126 → 134**.

---

## How the guard works

`scripts/design-lint.sh [warn|fail]` scans `Sources/MeetingScribe/UI` + `People` for three drift classes:
raw `.font(.system(size:))`, raw priority/status colors, and cold AppKit surface colors. CI runs it in
**fail** mode. Intentional exceptions carry a trailing `// design-lint:allow` (used for the few Canvas-draw
and tabular-`monospacedDigit` sites that genuinely can't use `scaledFont`).

---

## Deliberately deferred (honest follow-on)

The core landed; these audit items are **not** done and are good next PRs:

- **i18n** — no String Catalog / `String(localized:)` wrapping yet (large, ~200+ strings). SwiftUI `Text`
  literals are already localizable-ready, but the catalog + non-`Text` strings remain.
- **VoiceOver** — new components have `accessibilityLabel`s, but full rotor-ready row composition
  (`accessibilityElement(children:.combine)` + custom actions) across every list is not complete.
- **Tasks polish** — sticky group headers, project/initiative progress bar+ring, dashboard Charts band,
  calendar/gallery card polish, and a table Columns menu were scoped out of phase 3.
- **`SymbolPicker`** is built but not yet wired into the project/initiative header (still the hardcoded menu).
- **`MSAvatar` photos** — the component supports an `NSImage`, but People don't pass one through yet.
- **Density toggle** — spacing tokens exist; the comfortable/compact switch isn't wired.

---

## Verification

- `swift build -c release` — clean (warnings only).
- `swift test` — **134 pass, 1 skipped, 0 failures** (incl. 4 contrast + 4 snapshot tests).
- `scripts/design-lint.sh fail` — **0 violations**.
- `make install` — installed; manual QA via `ComponentGallery` in light/dark.
- **CI note:** GitHub Actions is currently **blocked by an account billing issue** (*"recent account
  payments have failed"*) and has been red on `main` since before this work — no job runs, so CI can't
  validate any commit until billing is resolved. All gates above were therefore run locally.
