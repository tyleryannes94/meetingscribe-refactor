# G1 — Visual Hierarchy & Design System

Lens: typography scale, spacing rhythm, color/theming, density, component polish, light/dark parity, modern macOS aesthetic — every fix tied to cold-start/runtime speed and crash-safety, preferring cache-backed/cheap approaches.

## Audit (through my lens)

The design system (`NotionDesign.swift`, "NDS") is genuinely good as a *token definition*: a warm-neutral dynamic palette via `NDS.dyn` (`NotionDesign.swift:60`), brand purple unified (`:37`), a `motion()` reduce-motion gate (`:116`), `scaledFont`/`@ScaledMetric` (`:139`), Untitled + MS button styles (`:253-340`), and reusable `NotionChip`/`NotionEyebrow`/`QuickActionCard`. NDS is referenced 644× across UI+People. But adoption is **partial and competing**, so the live UI does not yet *look* systematized. Concrete drift:

- **Three parallel type systems run at once.** NDS type tokens are used 188× (`NDS.tiny`×63, `small`×60, `body`×32, `sectionLabel`×24, `title`×6, `pageTitle`×3); raw `.font(.system(size:))` survives **288×** (227 in UI, 61 in People — *up* from the 192 the V4 plan cited); and SwiftUI semantic styles add **302×** (`.caption`×126, `.caption2`×97, `.headline`×34, `.callout`×22, `.title*`×13, `.body`×9). There is no single source of truth for the scale — `MeetingCard` alone uses `.headline`/`.callout`/`.caption2` (`MeetingCard.swift:89,73,77`) while neighboring views use NDS tokens. `scaledFont` (the Dynamic-Type-safe path) is used only **3×** total — D5-2 is effectively unshipped.
- **No spacing scale exists.** NDS defines `pagePadding`, `radius`, button paddings — but no `space2/4/8/12/16` rhythm. Padding literals are scattered: `8)`×72, `10)`×54, `6)`×39, `4)`×34, `12)`×31, `14)`×26, `16)`×19… (raw count across UI). Vertical rhythm is eyeballed per-view.
- **Radius tokens exist but aren't enforced** (`NDS.radius`/`rowRadius`/`cardRadius`, `:21-23`). Live code hardcodes `cornerRadius:` literals **98×** across **9 distinct values** (8×37, 6×17, 10×13, 7×7, 14×7, 12×6, 9×4, 4×3, 26×3). `MeetingCard` hardcodes `14` (`:42,46,59`) instead of `NDS.cardRadius`.
- **No shared card/row/surface component.** `grep` for `MSCard`/`MSSurface`/`MSListRow` → none. Every card re-implements `RoundedRectangle().fill().overlay(strokeBorder).shadow()` by hand (`MeetingCard.swift:41-53`, `QuickActionCard` in NDS, ActionItems chrome, People rows). This is exactly why radius/shadow/padding drift — there's nothing to drift *toward*.
- **Accent/color leaks to system blue/purple** despite the V4 "unify accent" item: `.foregroundStyle(.blue)` for the video-call glyph (`MeetingCard.swift:101`), `.purple` for the recurring glyph (`:113`), `.blue` status dots (`ActionItemsProjectPage.swift:343`, `ActionItemsTableView.swift:79`), `.blue` in `VaultMigrationSheet.swift:14`. 37 hardcoded `Color(hex:`/`.gray`/`.secondary` outside NDS.
- **Light/dark parity is mostly handled** by `NDS.dyn` (good), but 7 raw `.black.opacity`/`.white.opacity` shadows/fills bypass it (e.g. `MeetingCard.swift:51` `.black.opacity` shadow is invisible in dark and too heavy in light); shadows aren't tokenized so elevation is inconsistent (5 files use `.shadow` with ad-hoc values).
- **Loading/empty states are unmodern.** **26** bare `ProgressView()` spinners; **0** skeleton/`redacted(reason:)` placeholders; **0** `ContentUnavailableView` (the native macOS 14 empty-state primitive) — empty states are hand-rolled VStacks in 12 files. First-open and transcribe/summarize show spinners, not structure.
- **`.regularMaterial`/blur used only 1×** — the app forgoes the native translucency that makes macOS Tahoe surfaces feel current; everything is flat opaque fills.

Load/runtime context: none of the above is expensive today, and the fixes below are render-only (no new I/O), so they *reduce* cost — fewer view-modifier permutations to compose, cached token reads, and skeletons that let first paint happen before data loads.

## NET-NEW recommendations

**DV-1 — Add a spacing + elevation scale to NDS and lint it.**
What/why: introduce `NDS.space` (`xs2=2, xs=4, sm=8, md=12, lg=16, xl=24, xxl=32`), `NDS.shadowCard`/`shadowHover` (dynamic, dark-aware), and a tiny CI grep that fails on raw `.padding(<int>)`/`.shadow(color: .black`. Gives vertical rhythm one source of truth.
UX impact: consistent breathing room across all 5 tabs; removes the "every view is spaced slightly differently" feel. No click change.
Perf/stability: pure compile-time constants — zero runtime cost; *fewer* distinct modifier closures to memoize. Cache-friendly (static lets).
Effort: S · Impact: Med · Deps: none.

**DV-2 — Extract `MSCard`, `MSListRow`, `MSSurface` and route every card through them.**
What/why: one component owns radius (`NDS.cardRadius`), hairline, hover elevation, and reduce-motion scale; replace the hand-rolled chrome in `MeetingCard.swift:41-53`, `QuickActionCard`, ActionItems/People rows. Kills the 98 hardcoded radii and 9 competing values.
UX impact: instant visual coherence; hover/selection behaves identically everywhere. No click change.
Perf/stability: a single reused `ViewBuilder` is cheaper to diff than N bespoke modifier stacks; centralizes the `scaleEffect`/`animation` so reduce-motion can't be missed (crash/jank-safe). Cache decoded shadow colors once.
Effort: M · Impact: High · Deps: DV-1.

**DV-3 — Collapse the three type systems into NDS-only `Font.TextStyle` tokens, mechanically.**
What/why: map the 288 `.font(.system(size:))` and 302 semantic `.caption/.headline` calls onto the 6 NDS tokens (each already pinned to a `TextStyle`, `NotionDesign.swift:76-81`). Since NDS tokens are `Font.system(.style)`, they already scale — so this *also* finishes Dynamic Type (D5-2) that today has only 3 `scaledFont` call-sites.
UX impact: one legible hierarchy; low-vision users get real text scaling app-wide; titles stop being 2pt-off between adjacent views.
Perf/stability: no runtime cost; removes 288 fixed-size fonts that lock layout. Do it file-by-file behind `swift build` gates so a bad reflow can't ship.
Effort: M · Impact: High · Deps: DV-1.

**DV-4 — Skeleton placeholders via `.redacted(reason: .placeholder)` for first-open + pipeline waits.**
What/why: replace the 26 bare `ProgressView()` (transcribe/summarize/chat/Today first paint) with shimmer skeletons of the eventual layout. Render the skeleton *before* the store finishes loading so first paint is instant.
UX impact: cold-open and "transcribing…" feel 2–3× faster (perceived); structure communicates what's coming. Directly serves the first-open speed mandate.
Perf/stability: **the cheapest first-open win** — paint structure from a cached/empty model, hydrate async; no data dependency to block the frame. Add a reusable `MSSkeleton` so it's one line per site. Zero new I/O.
Effort: S–M · Impact: High · Deps: DV-2 (skeleton shares card chrome).

**DV-5 — Adopt `ContentUnavailableView` for every empty/zero/error state.**
What/why: the 12 hand-rolled empty VStacks (Meetings, Tasks, People graph, Brief, etc.) → native macOS 14 `ContentUnavailableView` with icon + actionable button. Modern, consistent, accessible by default.
UX impact: empty tabs become a clear next-action instead of a void; ties into the "no dead ends" theme. 0→1 click to the obvious action.
Perf/stability: native view is lighter than custom stacks and has built-in a11y; render-only. No caching needed.
Effort: S · Impact: Med · Deps: none.

**DV-6 — Tokenize the last color leaks + introduce semantic status colors.**
What/why: route `.blue`/`.purple`/`.black.opacity` (`MeetingCard.swift:101,113,51`; ActionItems status dots; VaultMigration) through NDS — add `NDS.statusLive/Upcoming/Done/Warn` and `NDS.shadowCard` so dark/light both resolve correctly.
UX impact: accent is purple *everywhere*; status semantics read identically across Today, Meetings, Tasks. Fixes dark-mode invisible / light-mode heavy shadows.
Perf/stability: dynamic `NSColor` resolves per-appearance (already the NDS pattern) — no cost; removes the parity bugs that currently render wrong in one mode.
Effort: S · Impact: Med · Deps: DV-1.

**DV-7 — Native translucency on chrome surfaces (sidebar, right rail, toolbars).**
What/why: the app uses `.regularMaterial` only 1×. Apply `.thinMaterial`/`.regularMaterial` (or `NSVisualEffectView` sidebar material) to the nav rail and chat rail so the window feels native-Tahoe, while content surfaces stay opaque for legibility.
UX impact: immediately more "2026 macOS"; depth without heavy shadows.
Perf/stability: material is GPU-composited and cheap; apply only to static chrome (not scrolling lists) so it never thrashes during scroll. No memory cost.
Effort: S · Impact: Med · Deps: none.

**DV-8 — Density control: a compact/comfortable toggle backed by the spacing scale.**
What/why: power users (manager with 50 people, long task lists) want denser rows; an `@AppStorage("ui.density")` that swaps `NDS.space` row paddings. Only possible once DV-1/DV-2 centralize spacing.
UX impact: more rows per screen without redesign; fewer scrolls (reduces effective clicks to reach lower items).
Perf/stability: denser rows = fewer rendered cells per scroll page = *less* layout work; pure constant swap, no relayout cost beyond the toggle. Persisted, so it's free on next launch.
Effort: M · Impact: Med · Deps: DV-1, DV-2.

**DV-9 — Tokenize shadows/elevation + cache decoded shadow `Color`s.**
What/why: 5 files hand-roll `.shadow`; define 2 elevation tokens and apply via `MSCard`. Resolve the dynamic shadow color once (static let) rather than per-render.
UX impact: consistent, subtle depth; no more "this card floats, that one doesn't."
Perf/stability: shadows are a known scroll-perf cost — one tuned, cached value beats per-view ad-hoc blur radii; keep shadow off list rows during scroll, on cards only.
Effort: S · Impact: Low–Med · Deps: DV-1, DV-2.

## Top 3 picks

- **DV-4 (Skeleton placeholders)** — **Phase 1.** Highest-leverage for the speed/first-open mandate: structure paints from an empty/cached model before stores hydrate, so cold-open *feels* instant with zero new I/O. Cheapest perceived-perf win in the audit.
- **DV-2 (Extract MSCard/MSListRow/MSSurface)** — **Phase 1.** The foundational fix that makes DV-1/DV-3/DV-6/DV-8/DV-9 enforceable and stops future drift; collapses 98 hardcoded radii and bespoke shadows into one cheap reused component.
- **DV-3 (Collapse 3 type systems → NDS tokens)** — **Phase 2.** Resolves the single biggest hierarchy problem (590+ competing font calls) and finishes Dynamic Type for free, since NDS tokens already scale. Sequenced after the component/scale foundation lands.

Single highest-value: **DV-4** — perceived speed at near-zero cost, directly on the hard constraint.
