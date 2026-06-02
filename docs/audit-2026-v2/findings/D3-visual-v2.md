# D3 — Visual Design Consistency Audit (Phase 1–6 Components)

**Lens:** Do new Phase 1–6 UI components feel visually consistent with the existing NDS design system?

---

## Full Audit

### 1. KindChip / MoodChip vs. existing FilterChip and NotionChip

**Finding: Inconsistent chip shape, corner radius, and token usage.**

`KindChip` (`QuickEncounterSheet.swift:207`) uses a **rectangular** `RoundedRectangle(cornerRadius: 10)` with a 1.5pt stroke. `MoodChip` (`QuickEncounterSheet.swift:230`) uses `cornerRadius: 8` with no stroke. Meanwhile, the existing `FilterChip` (`PeopleListView.swift:611`) and `NotionChip` (`NotionDesign.swift:156`) are **Capsule** pills — the canonical chip shape throughout the app.

The corner-radius values in the new chips (8 and 10) are also neither `NDS.radius` (8) nor `NDS.cardRadius` (12); they are hardcoded literals that partially overlap but diverge from the spec. The NDS token `NDS.radius = 8` exists but is not used in either chip.

Neither chip references `NDS.fieldBg`, `NDS.hairline`, or `NDS.brand` — the color tokens every other chip uses. Instead they use `Color.accentColor` (semi-intentional — `accentColor` tracks the system accent) and `Color.secondary.opacity(0.12)`. `FilterChip` uses `NDS.fieldBg` for the inactive state and `NDS.brand` for active. The inconsistency means chip hover/selection feedback looks different depending on which surface the user is on.

**Animation discrepancy:** `KindChip` fires a `.easeInOut(duration: 0.12)` animation via `.animation(_:value:)` AND an explicit `withAnimation(.easeInOut(duration: 0.15))` at the call site — duplicated and slightly different durations. `FilterChip` is entirely unanimated.

**Missing hover state:** `KindChip` and `MoodChip` have no `.onHover` handler; `QuickActionCard` and `NotionIconButton` do. On macOS this is a noticeable gap.

**File:line refs:** `QuickEncounterSheet.swift:207–228` (`KindChip`), `QuickEncounterSheet.swift:231–248` (`MoodChip`), `PeopleListView.swift:611–626` (`FilterChip`), `NotionDesign.swift:156–171` (`NotionChip`).

---

### 2. StayConnectedSection card style vs. TodayView sections

**Finding: StayConnectedSection uses a bespoke pink card, not the NDS card surface.**

Every other TodayView card uses `NDS.fieldBg` with `RoundedRectangle(cornerRadius: 8)` or `cornerRadius: 12` and a `NDS.hairline` stroke — either via the `msCard()` modifier (`MSComponents.swift:14`) or an inline equivalent (`TodayView.swift:151, 204, 243, 299, 467–468`).

`StayConnectedSection` uses `Color.pink.opacity(0.06)` with `RoundedRectangle(cornerRadius: 10)` and **no stroke** (`StayConnectedSection.swift:94`). This row-card is a distinct shade of pink that clashes with the warm neutral `NDS.fieldBg` used everywhere else. The section header icon `.foregroundStyle(.pink)` (`line 39`) and the "Log" button tint `.tint(.pink)` (`line 81`) pile on, making the entire section feel like an embedded marketing card rather than a native piece of the TodayView feed.

The "days overdue" label uses raw `.orange` (`line 67`) instead of `NDS.selectColor("orange")` or `NDS.palette[2].color`, which is the correct semantic orange elsewhere in the app (e.g. `MeetingCard.swift:271–277`).

The section header `Text("Stay connected").font(.system(size: 15, weight: .semibold))` (`line 40`) uses a hardcoded point size; adjacent TodayView section headers use `NDS.sectionLabel` (a Dynamic Type–aware token).

**File:line refs:** `StayConnectedSection.swift:39, 67, 81, 94`; `TodayView.swift:151, 204, 467–468`; `MSComponents.swift:14–19`.

---

### 3. RelationshipType emoji and color system

**Finding: `colorName` property exists but is a dead stub — no asset catalog, no runtime resolution.**

`RelationshipType.colorName` (`Person.swift:111–120`) returns strings like `"RelationshipPartner"`, `"RelationshipFamily"`, etc. These are described in comments as "rose", "amber", "teal", "sky", "slate". However:

- No `.xcassets` file exists anywhere in `Sources/` (only in the Sparkle checkout).
- `colorName` is never read by any view in the codebase — zero callsites.
- In the views that actually render relationship types, the color system is bypassed entirely. `StayConnectedSection` hardcodes `.pink`. `ProPaywallView`'s `ProBullet` rows use `.orange`, `.pink`, `.purple`, `.blue`, `.green`, `.teal` as raw literals (`ProPaywallView.swift:37–52`). No view ever calls `Color(named: rtype.colorName)`.

This means `RelationshipType` has a *designed* color system documented in code but producing zero visual output — every consumer improvises its own color. The result is ad-hoc and inconsistent.

The emoji selection is functional but unmaintained: `closeFriend` maps to 🤝 (a handshake), which reads as a business greeting rather than a close friendship. `friend` maps to 😊 (a smiley face), which is abstract. The overall set lacks visual hierarchy — 💑 (partner), 👨‍👩‍👧 (family), and 🤝 (close friend) are stylistically incoherent.

**File:line refs:** `Person.swift:111–120` (`colorName`), `StayConnectedSection.swift:39, 81, 94`, `ProPaywallView.swift:37–52`.

---

### 4. ProPaywallView gradient header vs. app accent usage

**Finding: The pink→purple gradient and hardcoded `.purple` CTA tint both deviate from NDS.brand.**

The app's canonical accent is `NDS.brand = Color(hex: "#7F56D9")` — a single purple hex. The CTA button (`ProPaywallView.swift:76`) uses `.tint(.purple)`, which is the SwiftUI system purple (approx #AF52DE on macOS), noticeably different from `NDS.brand` (#7F56D9). Side by side these will not match.

The header gradient `LinearGradient(colors: [.pink, .purple], ...)` (`line 20`) imports `.pink` into a component that otherwise lives in the purple-brand world. The design intent (warmth + aspiration) is understandable, but `.pink` is the raw UIKit/SwiftUI pink (approx #FF2D55), not a semantically defined token. `NDS.palette` contains a muted `"pink"` (#C14C8A) that would be less garish and consistent with the design language. `NDS.palette` also contains a `"purple"` (#9065B0) that is closer to `NDS.brand` than the system purple.

The ProBullet icon colors (`.orange`, `.pink`, `.purple`, `.blue`, `.green`, `.teal`) — six different literal colors in six consecutive lines — look accidental. `NDS.palette` has equivalents for all of these: using `NDS.selectColor("orange")` etc. would pull the same semantic palette used in action-item status chips, meeting cards, and tag chips.

**File:line refs:** `ProPaywallView.swift:20–21, 37–52, 76`; `NotionDesign.swift:38–39` (NDS.brand definition).

---

### 5. Hardcoded colors throughout new components (summary table)

| Location | Hardcoded value | Correct token |
|---|---|---|
| `StayConnectedSection.swift:39` | `.pink` (icon) | `NDS.palette[7].color` or `NDS.selectColor("pink")` |
| `StayConnectedSection.swift:67` | `.orange` (overdue text) | `NDS.selectColor("orange")` |
| `StayConnectedSection.swift:81` | `.tint(.pink)` (button) | `.tint(NDS.selectColor("pink"))` or a semantic token |
| `StayConnectedSection.swift:94` | `Color.pink.opacity(0.06)` (row bg) | `NDS.fieldBg` + `NDS.hairline` stroke |
| `ProPaywallView.swift:20` | `.pink` in gradient | `NDS.palette[7].color` |
| `ProPaywallView.swift:21` | `.purple` in gradient | `NDS.brand` |
| `ProPaywallView.swift:37–52` | `.orange/.pink/.purple/.blue/.green/.teal` | `NDS.selectColor("orange")` etc. |
| `ProPaywallView.swift:76` | `.tint(.purple)` | `.tint(NDS.brand)` |
| `StayConnectedSection.swift:40` | `.system(size: 15, weight: .semibold)` | `NDS.sectionLabel` (or NDS-based token) |
| `QuickEncounterSheet.swift:207` | `cornerRadius: 10` hardcoded | `NDS.radius` (8) or `NDS.cardRadius` (12) |
| `QuickEncounterSheet.swift:230` | `cornerRadius: 8` hardcoded | `NDS.radius` |

---

### 6. Design system gaps exposed by new components

These gaps did not exist (or were not visible) before Phase 1–6:

**Gap A — No semantic color for relationship types at runtime.**
`RelationshipType.colorName` returns a string referencing named colors that don't exist in an asset catalog and are never resolved. The design system needs either: (a) a `RelationshipType.color: Color` computed property backed by `NDS.selectColor` or `NDS.palette` lookups, or (b) named color assets actually created in an xcassets bundle.

**Gap B — No "emphasis card" surface in NDS.**
The TodayView needs a card variant with a colored left-border or tinted background for urgent/relational items (overdue check-ins, follow-ups, distress signals). Currently every piece of code that needs this invents its own pink/orange one-off. `NDS` / `MSComponents` should define `msEmphasisCard(tint:)` that takes a `Color` parameter and applies a tinted hairline + faint fill, keeping the warm-neutral base.

**Gap C — No inter-section spacing token.**
`StayConnectedSection` uses `spacing: 10` internally; the TodayView parent uses `spacing: 20`. Adjacent sections have inconsistent internal padding. NDS defines `pagePadding` and `splitPaneTopInset` but nothing for item-to-item rhythm within a feed.

**Gap D — No chip variant for large-format selection (KindChip use case).**
The Capsule pill (FilterChip/NotionChip) works for compact single-line filtering. The 3×2 grid card that KindChip uses is a genuinely different pattern — a "selection tile" — that appears nowhere else. NDS needs a `SelectionTile` component so future uses of the same pattern (coaching framework picker, onboarding, etc.) are consistent. Defining it now costs S effort and avoids four future divergences.

**Gap E — No PaywallHeader component.**
The pink→purple gradient icon is the only gradient in the entire app. If monetization surfaces multiply (upgrade prompts, locked feature banners), each will invent its own gradient. A `ProFeatureHeader` component in NDS with a canonical brand gradient (using NDS token colors) solves this once.

---

## Existing-Plan Items I Rank Highest (Through This Lens)

1. **D2 (Phase 1 color system for RelationshipType)** — the `colorName` stub is already there; completing it is S effort and unblocks three downstream components at once.
2. **E1-1 / E2-1 (VaultKit RelationshipPath)** — the canonical Phase 1 structural work that will force consistent property access and expose the color resolution gap in a compile-time way.
3. **Phase 7 code review** — the visual inconsistencies above are exactly the category that a structured review would catch before they multiply.

---

## NET-NEW Recommendations

### D3-1 — `RelationshipType.color: Color` computed property (backed by NDS)
**What:** Add a `color: Color` property to `RelationshipType` that returns values from `NDS.palette` directly (no asset catalog needed). Example: `.romanticPartner → NDS.palette[7].color` (pink), `.familyMember → NDS.palette[3].color` (yellow/amber), `.closeFriend → NDS.palette[4].color` (green), `.friend → NDS.palette[5].color` (blue), `.colleague → NDS.palette[1].color` (brown/slate), `.acquaintance → NDS.palette[0].color` (gray).
**Why:** `colorName` is a dead stub. Every view is improvising. One 10-line property eliminates all hardcoded relationship colors.
**User value:** Visual hierarchy in the people list — a glance identifies relationship category without reading text.
**Effort:** S | **Impact:** High | **Deps:** None

### D3-2 — `msEmphasisCard(tint:)` NDS modifier
**What:** Add a `msEmphasisCard(tint: Color)` view modifier to `MSComponents.swift` that applies `NDS.fieldBg` base fill + a 2pt left accent border in `tint` + a `tint.opacity(0.07)` fill overlay. `StayConnectedSection`, future distress-signal banners, and "overdue" rows all use this instead of bespoke pink backgrounds.
**Why:** Kills the `Color.pink.opacity(0.06)` one-off and establishes a reusable "this needs attention" visual language.
**User value:** Consistent visual scanning — colored left borders signal urgency level at a glance (UX convention from Notion, Linear, GitHub).
**Effort:** S | **Impact:** Medium-High | **Deps:** D3-1 (so the tint comes from `rtype.color`)

### D3-3 — `SelectionTile` NDS component (replaces KindChip/MoodChip ad-hoc pattern)
**What:** Add `SelectionTile` to `MSComponents.swift` or `NotionDesign.swift`: a rectangular tile with an emoji/icon + short label, using `NDS.fieldBg` inactive / `NDS.brand.opacity(0.14)` active, `NDS.cardRadius` corners, `NDS.hairline` border (active: `NDS.brand.opacity(0.5)`), and a `.spring(response: 0.18, dampingFraction: 0.85)` selection animation. Refactor `KindChip` and `MoodChip` onto it.
**Why:** The 3×2 selection grid is a reusable pattern — it will appear in coaching framework picker (Phase 3), onboarding relationship-type setup, and mood check-ins. Building it once in NDS prevents four future divergences.
**User value:** Consistent tap feedback across all selection surfaces; reduce-motion aware via `NDS.motion`.
**Effort:** S-M | **Impact:** Medium | **Deps:** None

### D3-4 — `ProFeatureHeader` NDS component with canonical brand gradient
**What:** A small `ProFeatureHeader` view in `MSComponents.swift` that renders an SF Symbol icon with a gradient built from NDS-tokenized colors: `NDS.palette[7].color` (muted pink) → `NDS.brand` (purple). Replaces the raw `.pink/.purple` gradient in `ProPaywallView`.
**Why:** When upgrade prompts are added to feature gates (Phase 9), every gated view needs a consistent header. Building it once prevents multiple gradient one-offs.
**User value:** Polished paywall that matches the app's warm-neutral palette instead of looking like a generic iOS upsell.
**Effort:** S | **Impact:** Medium | **Deps:** None

### D3-5 — Replace `StayConnectedSection` header with `MSSectionHeader` and standardize tint
**What:** Replace the hand-rolled HStack header in `StayConnectedSection.swift:38–44` with `MSSectionHeader("Stay connected", systemImage: "heart.circle")`. Replace `.tint(.pink)` on the Log button with `.tint(rtype.color)` (from D3-1) so the button color matches the person's relationship type. Replace the pink card bg with `msEmphasisCard(tint: person.relationshipType.color)` (from D3-2).
**Why:** Three inconsistencies in 60 lines, all fixable with existing components.
**User value:** TodayView reads as a unified feed, not a patchwork of cards.
**Effort:** S | **Impact:** Medium | **Deps:** D3-1, D3-2

### D3-6 — Standardize `ProPaywallView` to NDS brand tokens
**What:** Replace `LinearGradient(colors: [.pink, .purple], ...)` with `[NDS.palette[7].color, NDS.brand]`. Replace `.tint(.purple)` CTA with `.tint(NDS.brand)`. Replace six literal `ProBullet` colors with `NDS.selectColor("orange")`, `NDS.selectColor("pink")`, `NDS.selectColor("purple")`, `NDS.selectColor("blue")`, `NDS.selectColor("green")`, `NDS.selectColor("teal")`.
**Why:** The paywall is the first monetization-critical screen. It should look polished, not like a rainbow test card.
**User value:** A paywall that matches the app's design language increases conversion — a jarring color palette erodes trust.
**Effort:** S | **Impact:** High | **Deps:** None

### D3-7 — Add `onHover` feedback to `KindChip` and `MoodChip`
**What:** Add `@State private var hovering = false` + `.onHover { hovering = $0 }` to both chips. Apply `.scaleEffect(hovering ? 1.03 : 1.0)` (or `NDS.rowHover` background shift) guarded by `NDS.motion(_, reduce: reduceMotion)`. Match the pattern in `QuickActionCard` and `NotionIconButton`.
**Why:** macOS apps are pointer-driven. Chips with no hover state feel unfinished on the platform.
**User value:** Native macOS feel; clear affordance for interactive chips.
**Effort:** S | **Impact:** Low-Medium | **Deps:** None

### D3-8 — `NDS.feedSpacing` token for TodayView section rhythm
**What:** Add `static let feedSpacing: CGFloat = 16` and `static let feedSectionSpacing: CGFloat = 24` to `NDS`. Apply to `TodayView`'s outer `VStack` spacing and to `StayConnectedSection`'s internal item spacing. Currently `StayConnectedSection` uses `spacing: 10` vs the parent's `spacing: 20` — the visual density is inconsistent.
**Why:** Tokens prevent magic-number drift as new sections are added to the feed.
**User value:** A feed with consistent vertical rhythm feels considered and calming rather than jumbled.
**Effort:** S | **Impact:** Low | **Deps:** None

### D3-9 — Audit and migrate remaining `FilterChip`-shaped surfaces to `NotionChip` or unify
**What:** `FilterChip` (PeopleListView) and `NotionChip` (NotionDesign) serve the same purpose but differ in shape details (padding, font size token, capsule vs. explicit Capsule). Consolidate into one component, probably by making `FilterChip` a thin wrapper around `NotionChip` with an `active:` state parameter. Add `active` parameter to `NotionChip`.
**Why:** Two chip implementations for the same visual element means the next developer creates a third.
**User value:** No direct UX impact, but prevents future divergence.
**Effort:** S | **Impact:** Low | **Deps:** None

### D3-10 — `RelationshipType.emoji` set redesign: use consistent style
**What:** Replace the current mixed emoji set with one from a coherent style family. Suggested: use a heart-language set — ❤️ (romanticPartner), 🏠 (familyMember), 🌟 (closeFriend), 😄 (friend), 🤝 (colleague), 👋 (acquaintance), 👤 (unset). Alternatively adopt a consistent shape-based set using SF Symbols rendered in `rtype.color` so the design is fully system-consistent and light/dark aware.
**Why:** 💑👨‍👩‍👧🤝😊💼👋👤 reads as six different emoji packs from different apps. A consistent visual vocabulary makes the relationship type system feel designed.
**User value:** Users build mental models faster with a coherent icon set.
**Effort:** S | **Impact:** Medium | **Deps:** D3-1 (if switching to SF Symbols)

---

## Top 3 Picks

1. **D3-1 (RelationshipType.color backed by NDS)** — highest leverage. One 10-line property eliminates every hardcoded relationship color in the codebase and makes D3-2, D3-5, D3-10 trivial follow-ons.
2. **D3-6 (Standardize ProPaywallView to NDS tokens)** — the paywall is a monetization-critical first impression. Fixing it costs ~15 minutes and removes six hardcoded color literals.
3. **D3-3 (SelectionTile NDS component)** — the KindChip/MoodChip pattern will repeat across coaching, onboarding, and settings. Defining the tile once in NDS prevents four future inconsistencies.

## Single Highest-Priority Recommendation

**D3-1 — add `RelationshipType.color: Color`**, backed by `NDS.palette` lookups, to `Person.swift`. This single property is the prerequisite for every downstream fix: it corrects `StayConnectedSection`, enables typed tinting in the LogButton, could replace the dead `colorName` stub, and gives `ProPaywallView`'s bullets a designed palette. It requires no migration, no asset catalog, and no other PR dependency. Effort: S.
