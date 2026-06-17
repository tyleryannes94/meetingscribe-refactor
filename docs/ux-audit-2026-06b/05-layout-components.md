# Audit — Shared Layout & Component System (the foundation)

*Agent: design-systems. This is the keystone both page redesigns build on — implement FIRST.*

## Button-size diagnosis

The app ships a complete, correct button system (`MSComponents.swift` / `NotionDesign.swift`): `MSPrimaryButtonStyle` 34 (`buttonPrimaryH`), `MSSecondaryButtonStyle` 30 (`buttonSecondaryH`), `MSDangerButtonStyle` 34, `MSTertiaryButtonStyle` 28 (`buttonTertiaryH`, almost unused), `NotionIconButton` 30² + `.minTap()` 44. The "weird sizes" are important actions **bypassing** these for AppKit defaults. Tally: `.plain` ×193, `.borderless` ×128, `.controlSize(.small)` ×76, `.borderedProminent` ×22, `.bordered` ×11.

Worst offenders:
- `MeetingDetailHeader.swift:404-417` — Options menu hand-builds chrome at **radius 8** (vs `NDS.radius` 14 on the adjacent primary CTA) → visibly squarer corner next to the most-hit button.
- `MeetingDetailHeader.swift:36-57` — "View all attendees" (`.plain` capsule) beside "Add N to People" (`.borderless`) → two adjacent CTAs, two mechanisms, two heights.
- `PersonDetailView.swift:884/889/895` — identity-panel quick actions `.borderless`+`.font(NDS.small)` ~18pt, no tap target.
- `PersonDetailView.swift:1006` — `reconnectSection` uses `.borderedProminent.controlSize(.small).tint` → off-theme system blue, ~24pt, an important CTA rendered wrong.
- `PersonDetailView.swift:1073/1134` — bare `Button("Add").font(NDS.small)` (`.automatic`) mid-form.

## Proposed button system (rules)

Keep the 4 existing styles as the only sanctioned ones. **Ban** `.bordered`, `.borderedProminent`, `.controlSize` on `Button`, and bare `.font(NDS.small)`-on-`Button`. Map every action to a role:

| Role | Style | Height | Use |
|---|---|---|---|
| Primary (≤1 per section/form) | `MSPrimaryButtonStyle` | 34 | the one likely next action |
| Secondary | `MSSecondaryButtonStyle` | 30 | supporting actions, button-styled menus |
| Tertiary/ghost | `MSTertiaryButtonStyle` | 28 | inline list/form actions (replaces `.borderless`+small) |
| Icon-only | `NotionIconButton` + `.minTap()` | 30² / 44 tap | glyph actions |
| Destructive | `MSDangerButtonStyle` | 34 | stop/delete |

Rules: inline width by default (`.fixedSize()`); full-width only for a card's single CTA or a form submit row. Header cluster = `[primary] [secondary] [icon-overflow]` in `HStack(spacing: NDS.spaceSM)`. Menus that look like buttons use `MSSecondaryButtonStyle`/`msMenuButtonChrome()`, not hand-built borders. Icon actions always `.minTap()`.

Add two wrappers to `MSComponents.swift`:
- `MSInlineButton(title:systemImage:action:)` — wraps `MSTertiaryButtonStyle`; the sanctioned replacement for `.borderless`+small.
- `View.msMenuButtonChrome()` — surface + `NDS.radius` + hairline + `buttonSecondaryH`, for `Menu` labels.

## Shared collapsible section — `MSSection`

No suitable component exists (only `MSSectionHeader` non-collapsing, `NotionEyebrow` static, a one-off chevron in `MeetingSummaryTab.swift:237-267`). Add `MSSection` to `MSComponents.swift`:

```swift
struct MSSection<Content: View, Trailing: View>: View {
    let title: String
    var systemImage: String? = nil
    var count: Int? = nil
    var persistenceKey: String? = nil   // nil = @State; set = @AppStorage("section.<key>.expanded")
    var defaultExpanded: Bool = true
    @ViewBuilder var trailing: () -> Trailing   // e.g. an Add button, outside the toggle hit area
    @ViewBuilder var content: () -> Content
}
// + convenience init where Trailing == EmptyView
```

Header: `Button { toggle }` → `HStack(NDS.spaceSM)` of `[chevron] [icon?] [NDS.sectionLabel title] [count?] Spacer [trailing()]`; chevron `chevron.down/right` `scaledFont(10,.semibold)` `NDS.textTertiary` (the proven `MeetingSummaryTab` treatment); whole header is the tap target (`.contentShape(Rectangle())`, `.buttonStyle(.plain)`); `trailing()` sits outside the toggle. Animate via `NDS.motion(.easeInOut(NDS.motionFast), reduce: reduceMotion)`. Persistence: `@AppStorage("section.<key>.expanded")` when key set (precedent: `today.moreExpanded`), else `@State`. Component owns no horizontal padding / card — host wraps it.

Migration targets: `MeetingSummaryTab.swift:237-267`; every `…Section` in `PersonDetailView.swift` (628,1058,1110,1158,1414,1449,1595,1664,1762,1875,1936,1988,2073,2222,2291,2336,2365,2563).

## Spacing rules

Only `NDS.space*` (xs4/sm8/md12/lg16/xl24/xxl32). Between canvas sections `spaceXL` (24); within a section `spaceSM` (8); action/chip rows `spaceSM`; canvas column `maxWidth 760` centered, h-pad `spaceLG`, bottom `spaceXL`, top `splitPaneTopInset`. One density.

## Build plan
1. **Button wrappers + rule doc** — add `MSInlineButton`, `msMenuButtonChrome()` to `MSComponents.swift`; header comment with the role table. No call-site changes.
2. **`MSSection`** — add component + `EmptyView` convenience init + gallery preview. Pure addition.
3. **Fix header inconsistency** — `MeetingDetailHeader.swift:404-417` → `msMenuButtonChrome()` (radius 14); attendee-rail buttons (36-57) → `MSInlineButton`.
4. **Migrate `MeetingSummaryTab` summary disclosure** to `MSSection` (validates it on a real section).
5. **Person button cleanup** — `:1006` → `MSPrimaryButtonStyle`; `:884/889/895` → `MSInlineButton`; `:1073/1134` → `MSTertiaryButtonStyle`.
6. **Person canvas → MSSection** (de-tab pt1; 2–3 sub-PRs by pane).
7. **Meeting canvas → MSSection** (de-tab pt2).
8. **Standardize spacing + extend `design-lint.sh`** to fail on `.borderedProminent`/`.bordered`/`.controlSize` on `Button`.
9. **Remove tab scaffolding** (`DetailTab`/`PersonTab`/`MSPillTabs` usage).
