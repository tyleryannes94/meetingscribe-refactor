# Design — Visual Design System & the "Expensive" Aesthetic
> Lens: does every pixel decision (type, spacing, color, depth, materials, motion, icons) read as deliberate and premium — Things 3 / Craft / Linear / Notion Calendar grade — or as assembled?

## Full-app audit (through my lens)

### What's genuinely strong (rare for an indie app)
- **A real token file exists and is opinionated.** `NDS` carries a dark-first plum/coral/lilac "Bloom" palette with appearance-adaptive `dyn()` colors (`Sources/MeetingScribe/UI/NotionDesign.swift:73-102`), bundled display+body typefaces with exact PostScript weight mapping to avoid CoreText fractional-weight noise (`NotionDesign.swift:124-141`), a spacing scale (`:222-227`), motion constants + a Reduce Motion gate (`:215-237`), WCAG contrast helpers (`:288-307`), and semantic status/priority/due colors with glyph redundancy (`:247-279`). The CI `scripts/design-lint.sh` ratchet is a maturity signal most teams never reach.
- **`MSAvatar`** squircle (34% radius) + deterministic gradient + dark warm monogram (`UI/MSAvatar.swift:15-31`) is a legitimately premium identity primitive — Craft-grade.
- The **coral→lilac ambient corner glow** (`UI/MSComponents.swift:27-38`) and `MSTintedHeaderCard` (`MSComponents.swift:44-78`) are signature moves with real personality.

### What reads as cheap, and exactly why

**1. The typography system is bifurcated — Bloom fonts and SF Pro mix inside single components.** Bloom type only renders where `scaledFont()`/NDS tokens are used. There are **435 raw `.font(.headline/.caption/.callout/...)` system-text-style sites** in `Sources/MeetingScribe` (vs ~6 NDS type tokens), and `design-lint.sh` only catches `.system(size:)` — text styles sail through (`scripts/design-lint.sh:38`). Concretely: `MeetingCard`'s title is `.font(.headline)` = SF Pro (`UI/MeetingCard.swift:113`) while its status pill three lines down is `scaledFont(11, ...)` = Plus Jakarta (`MeetingCard.swift:274`). Two typefaces inside one card is the canonical "assembled, not designed" tell. Nothing in Things 3 or Linear ever mixes families within a surface.

**2. No modular scale — fractional ad-hoc sizes everywhere.** The NDS ramp has only 6 tokens (30/25/14/12/11/11, `NotionDesign.swift:151-156`) with a hole between 14 and 25, so views invent sizes: `scaledFont(15.5)` (`UI/MainWindow.swift:126`), `13.5` (`MainWindow.swift:671`, `TodayView.swift:343`), `11.5` (`NotionDesign.swift:369`), `15` (`TodayView.swift:129`), `16` (`TodayView.swift:448`). Premium type systems have zero fractional point sizes; every size is a named step.

**3. Radius anarchy.** Tokens declare 14/12/20 (`NotionDesign.swift:24-26`), but the live histogram across `Sources/MeetingScribe` is: 27× `cornerRadius: 8`, 22× `6`, 17× `10`, 7× `7`, 5× `9`, plus 4/3/2/1/0/16/26. `MeetingCard` hard-codes 14 against `cardRadius: 20` (`UI/MeetingCard.swift:42`); its own doc comment still cites the *previous* spec ("modeled after Stripe / Cash App", `MeetingCard.swift:10` — three named aesthetics now coexist in-repo: Notion, Untitled UI, Bloom/Stripe). Inconsistent corner geometry is subliminal but powerful: it's why screenshots feel "off" without users knowing why.

**4. Spacing tokens exist but are decorative.** `NDS.space*` has **15 call sites**; literal paddings have **hundreds** (39× `.padding(.horizontal, 10)`, 36× `8`, 25× `12`, 22× `.padding(10)`, 18× `.padding(14)`…). The Today feed uses `28/24` page padding (`UI/TodayView.swift:101`) while `NDS.pagePadding` is 56 and `notionPageColumn()` (`NotionDesign.swift:608-614`) goes unused there — so Today, the first screen, has a different page rhythm than every Notion-column surface.

**5. No elevation system — 12 ad-hoc shadows, 7 different recipes.** `MeetingCard` hover: black 0.06/r8/y3 (`MeetingCard.swift:51`); record dock: 0.32/r16/y8 (`UI/MeetingRecordDock.swift:71`); toast: 0.25/r10/y3 (`UI/ToastCenter.swift:64`); markdown toolbar: 0.25/r6/y3 (`UI/MarkdownEditor.swift:823`); graph node: 0.25/r3/y1. Things 3 and Linear have 2–3 named elevation levels, period. Worse: black drop shadows are nearly invisible on the `#15121a` plum background — dark-mode elevation should come from *lighter surfaces* (`surface2`) + hairline, not shadow, and nobody has made that call.

**6. Materials are almost absent.** Four material uses in the entire app (`UI/MarkdownEditor.swift:821`, `UI/FloatingOverlay.swift:260`, `People/Graph/*`). The nav rail is a flat opaque `sidebarBg` rectangle (`UI/MainWindow.swift:180`) in a hand-rolled `HStack` (`MainWindow.swift:383-410`). The translucent, desktop-tinted sidebar is *the* thing that makes Things 3, Craft, and Notion Calendar feel native-expensive on macOS; its absence is the single largest gap between MeetingScribe and the benchmark set. `NDS.splitPaneTopInset = 60` (`NotionDesign.swift:20`) is a magic-number workaround for not owning the titlebar treatment.

**7. The app's most emotional state — recording — bypasses the palette.** Live cards use raw `.red` (`UI/MeetingCard.swift:92, 129, 189, 317, 325`), `FloatingOverlay` glows `.red.opacity(0.5)` (`UI/FloatingOverlay.swift:477`), and `MeetingDetailHeader:730` has a raw `.red : .yellow : .green` traffic-light ternary. 45 raw system-color sites total. The moment users stare at hardest is the least designed.

**8. Iconography: the nav rail has a metaphor collision.** Meetings = `person.2.fill`, People = `person.2` (`UI/MainWindow.swift:23-26`) — the same symbol distinguished only by fill, for the app's two most important concepts. Fill/outline also mixes arbitrarily across the rail (`sun.max.fill` vs `person.2` vs `checklist`). `NDS.iconWeight()` exists (`NotionDesign.swift:282-284`) but is barely called.

**9. Component adoption is the drift engine.** `msCard()` has **4 call sites** while the hand-rolled `NDS.fieldBg, in: RoundedRectangle` pattern it replaces appears **48 times**. TodayView alone uses three different section-header treatments: inline icon + `scaledFont(15, semibold)` (`TodayView.swift:127-130`), `Label + NDS.sectionLabel` (`:331-333`), and uppercase tracked `sectionLabel()` (`:574-580`) — within one file. Today renders as a 13-section vertical dump (`TodayView.swift:54-100`) where the hero card, a follow-up row, and a voice-note row all get near-identical 8pt-radius gray rows: no editorial hierarchy = no "expensive."

**10. The coral glow is spent everywhere.** Every primary button ships a permanent coral drop-glow (`NotionDesign.swift:457, 493`), the brand mark glows (`MainWindow.swift:124`), the ambient corner glows. When everything glows, nothing does — Linear's restraint (one accent moment per screen) is the benchmark.

**11. Light mode is a liability, and the toggle squats on premium real estate.** Light is self-described as a "tasteful fallback" (`NotionDesign.swift:71-72`), shadows/glows are untuned for it, and the Light/Dark `AppearanceToggle` lives in the nav-rail footer (`MainWindow.swift:151`) — no benchmark app puts appearance switching in primary navigation; it signals "settings demo," not product.

## Existing-plan items I rank highest
1. **1F Button consolidation (retire `Untitled*`, adopt `MS*`)** — two parallel button families in one view is top-three cheapness; pure adoption work.
2. **1F Loading skeleton tri-state** — the "No summary" false-empty flash is a perceived-quality killer on the most-opened surface; `MSSkeleton` already exists (`MSComponents.swift:187-208`).
3. **2A Unify split panes under one `NavigationSplitView` shell** — prerequisite for the native sidebar material story (my D2-4); three pane implementations can never share one chrome.
4. **2B Warm copy + photo hero avatar with `RelationshipType.color` ring** — the highest-emotion visual moment in the coach loop; `MSAvatar` already accepts an `NSImage` that People never pass (per `docs/design/WHOLE_APP_REFRESH.md` deferred list).
5. **2H Dynamic Type round 2 (adaptive sheet frames)** — fixed-frame sheets clipping at large text reads as broken, the opposite of expensive.
6. **1F Gate all motion through `NDS.motion()`** — five different hover animation recipes coexist (0.12 easeOut, 0.15/0.18/0.22/0.3 springs); one motion voice is a cheap coherence win.

## NET-NEW recommendations

### D2-1 — Complete modular type ramp + lint system text styles
- **What/why:** Extend the NDS ramp to a full named scale and make it the *only* legal way to set type. Proposed (Bricolage display / Jakarta body, Dynamic-Type-anchored): `displayXL 30/800`, `display 25/800`, `title 20/700` *(new — fills the 14→25 hole)*, `headline 16/600` *(new)*, `bodyStrong 14/600` *(new)*, `body 14/400`, `label 13/500` *(new — absorbs the 13/13.5 ad-hocs)*, `small 12/500`, `micro 11/700-caps`. Round every fractional size (11.5/13.5/15.5) to a step. Then extend `scripts/design-lint.sh` with two new drift classes: raw `.font(.headline|.caption|.callout|…)` in `UI/`+`People/` (435 current hits — migrate file-by-file with `// design-lint:allow` during the ratchet) and `scaledFont(<literal>)` sizes not in the ramp. This finishes what the whole-app refresh started: it linted `.system(size:)` but left the much larger text-style class open, which is why SF Pro still renders most of the app.
- **User value:** One typeface voice everywhere — the single biggest subconscious "this app is expensive" signal; also fixes hierarchy (titles/headlines stop competing).
- **Effort:** M (token file is S; the 435-site sweep is mechanical, lint prevents regression)
- **Impact:** High
- **Depends on:** none

### D2-2 — Elevation token system (dark-first: surface, not shadow)
- **What/why:** Add `NDS.Elevation` with exactly four levels, each a *bundle* of background + border + shadow per appearance: `.flat` (bg, no border), `.raised` (fieldBg + hairline, **no shadow in dark**; black 0.06/r3/y1 in light), `.overlay` (surface2 + hairline + black 0.25/r10/y3 — popovers, toasts, markdown toolbar), `.floating` (surface2 + hairline + black 0.35/r16/y8 — record dock, drag previews). Implement as `func msElevation(_ level:)` and replace the 12 ad-hoc `.shadow(` sites (`MeetingCard.swift:51`, `MeetingRecordDock.swift:71`, `ToastCenter.swift:64`, `MarkdownEditor.swift:823`, `FloatingOverlay.swift:518`, `PersonNodeView.swift:120`, `TodayView.swift:670`). Codify the rule in the file header: *in dark mode, height = lighter surface; shadow is reserved for true overlays.*
- **User value:** Depth becomes legible and consistent — cards, popovers, and docks read as a physical system the way Things 3's panels do, instead of seven different lighting rigs.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### D2-3 — Radius ramp + nesting rule, linted
- **What/why:** Collapse the 15 observed corner radii to four tokens: `radiusXS 6` (nested chips/inner controls), `radiusSM 10` (small controls, icon-button hovers), `radius 14` (controls/fields — exists), `cardRadius 20` (cards — exists), all `.continuous`. Add the optical nesting rule as a doc'd helper: `childRadius = parentRadius − inset` (so a 20pt card with 14pt padding contains 6pt-radius children — this is why Craft's nested surfaces look "machined"). Fix `MeetingCard.swift:42` (14 → cardRadius 20) and migrate the 27× `8` / 22× `6` / 17× `10` literals to the nearest token. Add a `cornerRadius: [0-9]` drift class to design-lint.
- **User value:** Corner geometry stops fighting itself; screenshots immediately look more deliberate.
- **Effort:** S
- **Impact:** Med-High
- **Depends on:** none

### D2-4 — Native translucent sidebar + unified window chrome (the Things 3 move)
- **What/why:** Replace the flat opaque `navRail` (`MainWindow.swift:114-181`) with an `NSVisualEffectView(.sidebar)`-backed rail (a 10-line `NSViewRepresentable`), tint-washed with `sidebarBg` at ~85% so the plum identity survives over desktop translucency; extend it full-height under a transparent titlebar (`titlebarAppearsTransparent` + `.fullSizeContentView`), and replace the `splitPaneTopInset = 60` magic number with a real `safeAreaInset`. Selection stays `lilacSoft`, but hairline-separate the rail with `NDS.divider` only (no opaque seam). This pairs with — and gives the visual payoff for — the planned 2A `NavigationSplitView` unification, which specs structure but not chrome.
- **User value:** The app instantly reads as a native, first-party-grade macOS citizen; this is the most recognizable shared trait of Things 3 / Craft / Notion Calendar and the largest single gap today.
- **Effort:** M
- **Impact:** High
- **Depends on:** plan item 2A (sequencing, not blocking)

### D2-5 — Glow budget: one luminous moment per screen
- **What/why:** Establish "the record action is the sun": only the screen's single most important CTA keeps the coral glow. Remove the permanent `shadow(color: NDS.accent.opacity(0.32))` from `MSPrimaryButtonStyle`/`UntitledPrimaryButtonStyle` defaults (`NotionDesign.swift:457, 493`) and the brand-mark glow (`MainWindow.swift:124`); add an opt-in `.glow()` modifier applied to exactly: Today's Record button, the live `FloatingOverlay`, and `MeetingRecordDock`. Secondary primaries (Join & Record in cards, sheet CTAs) get flat coral fill.
- **User value:** Restraint is the premium tell — Linear ships one accent moment per view. The record action gains gravity precisely because nothing else glows.
- **Effort:** S
- **Impact:** Med-High
- **Depends on:** none

### D2-6 — Today as an editorial page: 3 section archetypes, 1 header component
- **What/why:** TodayView stacks 13 visually identical sections (`TodayView.swift:54-100`) with three competing header styles (`:127`, `:331`, `:574`). Define exactly three section archetypes and re-pour Today into them: **Hero** (one `MSTintedHeaderCard` — Up Next *or* live recording, never both), **Strip** (horizontal scroll of compact cards — Stay Connected people, On This Day), and **Digest** (collapsed count-first rows — "3 follow-ups to send ›" expanding on click instead of pre-rendering 4 rows each). One `MSSectionHeader` (already built, `MSComponents.swift:119-145`) for all of them, with `NotionEyebrow` styling and a trailing "All ›". Cap the page at 5 visible sections; the rest collapse to Digest rows. This is the visual spec the master plan's Today work (routing, drift strip) never wrote.
- **User value:** The home screen gets a front-page hierarchy — scan in 3 seconds instead of scrolling a 13-block wall; density drops, perceived quality jumps.
- **Effort:** M
- **Impact:** High
- **Depends on:** D2-1 (header type), plan 2A routing

### D2-7 — Designed recording state: semantic `NDS.recording` + live border treatment
- **What/why:** Add `NDS.recording` (a coral-leaning red, e.g. `#ff6b5e`, tuned to sit with the Bloom family — raw `.red` vibrates against plum) + `recordingSoft` fill, and replace every raw `.red` in the live path (`MeetingCard.swift:92, 129, 189, 317, 325`, `FloatingOverlay.swift:477`, `MainWindow.swift:753`, `MeetingDetailHeader.swift:493, 730`). Give the live card a slow animated angular-gradient border (coral→recording, 3s rotation, `NDS.motion`-gated, static ring under Reduce Motion) instead of the flat 1.5pt stroke — the "this moment is alive" treatment the most-stared-at state deserves.
- **User value:** The app's emotional peak looks designed rather than defaulted; recording confidence is also a trust feature.
- **Effort:** S
- **Impact:** High
- **Depends on:** D2-5

### D2-8 — Nav iconography: kill the person.2 collision + fill-on-select rule
- **What/why:** `MainWindow.swift:23-27`: Meetings (`person.2.fill`) vs People (`person.2`) is a metaphor collision on the two core concepts. Re-map: Today `sun.max`, Meetings `waveform` *(owns the brand glyph — it records conversations)* or `calendar.badge.clock`, People `person.2`, Tasks `checklist`, Voice Notes `mic`. Adopt the platform-standard state rule: **outline at rest, `.fill` variant when selected** (use `symbolVariant(.fill)` on selection) — this is how Apple's own apps and Things 3 signal selection without color alone. Route all rail/toolbar icons through `NDS.iconWeight()`.
- **User value:** The rail becomes glanceable and self-evident; icon discipline is disproportionately visible in screenshots and first impressions.
- **Effort:** S
- **Impact:** Med
- **Depends on:** none

### D2-9 — Surface-adoption sweep: 48 hand-rolled cards → `msCard`, paddings → tokens
- **What/why:** `msCard()` has 4 call sites vs 48 hand-rolled `NDS.fieldBg + RoundedRectangle + hairline` clones; `NDS.space*` has 15 uses vs hundreds of literals. Sweep: (a) replace hand-rolled card chrome with `msCard()`/`msElevation` (D2-2); (b) add an `msRow()` primitive (the 8pt-radius list-row pattern repeated ~30× in TodayView/MeetingDetailHeader) so rows are defined once; (c) migrate `.padding(<literal>)` to the nearest `NDS.space*` on touched files; (d) snap Today's `28/24` page padding to a new `pagePaddingCompact = 32` token or `notionPageColumn()`. Add a warn-mode lint for `fieldBg, in: RoundedRectangle` outside MSComponents.
- **User value:** Rhythm consistency — the difference between "tidy" and "machined"; also makes D2-2/D2-3 stick permanently.
- **Effort:** M
- **Impact:** Med-High
- **Depends on:** D2-2, D2-3

### D2-10 — Commit to dark; move appearance switching out of the rail
- **What/why:** Bloom is explicitly dark-first with light as a "fallback" (`NotionDesign.swift:71-72`) — half-supporting light costs double QA on every token (shadows, glows, and `AppearanceToggle`'s light-only shadow at `NotionDesign.swift:724` show the strain). Either (a) declare dark-only for 1.x (delete the toggle, set `.preferredColorScheme(.dark)`), or (b) keep light but move the toggle to Settings ▸ Appearance and add light-mode rows to `DesignSnapshotTests` for every MS* component. In both cases the rail footer (`MainWindow.swift:150-176`) is reclaimed for the planned Recents rail / user identity — appearance toggles in primary nav read as a demo, not a product.
- **User value:** Every design decision gets tested against one canvas; the rail footer becomes useful navigation real estate.
- **Effort:** S
- **Impact:** Med
- **Depends on:** none

### D2-11 — One motion voice: hover/press tokens
- **What/why:** Five hover/press recipes coexist (`easeOut 0.12` in QuickActionCard/QuickPill/NavRailItem, `spring 0.15` ToolbarPillButton, `spring 0.18` MeetingCard, `spring 0.3/0.7` buttons, `springStandard 0.32/0.8` tabs). Define `NDS.hoverMotion` (= easeOut `motionFast`) and `NDS.pressMotion` (= one spring) and route all interactive feedback through them; document the hierarchy (hover = fast fade, press = spring, navigation = springStandard) in NotionDesign.swift. Fold into the planned 1F motion-gating sweep so it's one pass.
- **User value:** The app feels like it has one nervous system — motion coherence is half of what people call "feel."
- **Effort:** S
- **Impact:** Med
- **Depends on:** plan 1F motion gating

### D2-12 — Name the system: retire the Notion/Untitled/Stripe identity residue
- **What/why:** The design system is named "NotionDesign/NDS," ships "Untitled UI-style buttons" (`NotionDesign.swift:444`), cards "modeled after Stripe / Cash App" (`MeetingCard.swift:10`), and a palette called Bloom from `designs/bloom.css`. Rename the namespace to `Bloom` (typealias `NDS = Bloom` for zero-churn migration), delete the `Untitled*` aliases after the 1F consolidation, rewrite stale doc comments, and add a one-page `docs/design/BLOOM.md` north star (palette, ramp from D2-1, elevation from D2-2, radius from D2-3, glow budget from D2-5, motion from D2-11) so future agents/PRs converge on one aesthetic instead of four.
- **User value:** Indirect but compounding — every future surface gets built to one standard; the current four-reference residue is *why* drift keeps re-emerging.
- **Effort:** S
- **Impact:** Med
- **Depends on:** D2-1, D2-2, D2-3, D2-5

## Top 3 picks
1. **D2-1 — Modular type ramp + text-style lint.** 435 SF-Pro leak sites means most of the app isn't rendering the brand typefaces at all; this is the largest single "expensive" lever and it's mostly mechanical.
2. **D2-4 — Native translucent sidebar + unified window chrome.** The one structural move that closes the gap to Things 3 / Craft / Notion Calendar on sight.
3. **D2-2 — Elevation tokens (surface-not-shadow in dark).** Cheap, ends the seven-shadow chaos, and codifies the dark-mode depth rule nobody has made.

**Single highest-priority rec overall: D2-1.** Typography is the medium everything else is read through; until one family renders everywhere at named sizes, no amount of color or card polish will read as premium — and the lint extension makes the fix permanent rather than another drift cycle.
