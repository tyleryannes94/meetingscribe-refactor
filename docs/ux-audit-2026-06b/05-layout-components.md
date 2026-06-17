# 05 — Layout & Component System

*Agent: design-systems. This is the keystone both page redesigns build on — implement FIRST.*

**Scope.** The shared layout and component substrate the Meetings-detail and
People-detail redesigns build on. This is the contract: every page in the
audit-2026-06b work stacks onto these tokens, these button styles, and the
`MSSection` collapsible. It documents what exists in source today (with
`file:line`), catalogues the drift that the redesign must erase, and lays out an
increment-by-increment migration plan plus a CI guard to keep it erased.

**Source of truth.**
- Tokens + button styles + icon button: `Sources/MeetingScribe/UI/NotionDesign.swift`
- Surfaces, section header, collapsible, F-phase wrappers:
  `Sources/MeetingScribe/UI/MSComponents.swift`
- The two canvases this spec governs:
  `Sources/MeetingScribe/UI/UnifiedMeetingDetail.swift` (+
  `MeetingDetailHeader.swift`, `MeetingSummaryTab.swift`) and
  `Sources/MeetingScribe/People/PersonDetailView.swift` (+ `PeopleListView.swift`).
- CI guard: `scripts/design-lint.sh`.

**Non-negotiable.** Do not edit `Sources/` to produce this doc. This is a spec;
the migration section tells the build agent what to change later.

---

## 1. Token reference

Every layout-relevant `NDS` token, its literal value, the source line in
`NotionDesign.swift`, and its intended use. **Rule: never hard-code any of these
literals at a call site — reference the token.** A raw `.padding(16)` is a bug
the moment `spaceLG` changes.

### 1.1 Spacing scale (`NotionDesign.swift:234-242`)

The app has ONE vertical rhythm. `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`.

| Token | Value | Line | Intended use |
|---|---|---|---|
| `NDS.spaceXS` | `4` | :237 | Hairline gaps: label↔value, icon↔text inside a chip, fine-tune nudges. |
| `NDS.spaceSM` | `8` | :238 | Default control gap. Gap inside an action row (`HStack(spacing:)`), header→count, chevron→title in `MSSection`. |
| `NDS.spaceMD` | `12` | :239 | Within-section spacing: rows in a card, the `VStack` spacing inside a tab body (meeting `actionsBody` uses `12`). |
| `NDS.spaceLG` | `16` | :240 | Card internal padding region; gap between tightly-related sub-blocks. |
| `NDS.spaceXL` | `24` | :241 | **Between top-level sections** on a canvas. The primary inter-section rhythm. |
| `NDS.spaceXXL` | `32` | :242 | Major canvas bands / above a footer / between unrelated regions. |

### 1.2 Radius ramp (`NotionDesign.swift:26-29`)

Four radii. Everything maps to one of these; pills/chips/nav/tabs go fully
rounded (`Capsule`) at the call site, NOT via these tokens.

| Token | Value | Line | Intended use |
|---|---|---|---|
| `NDS.radiusSmall` | `8` | :26 | Chips, inline controls, small pills, inline edit fields (title-edit field uses a raw `6` today — should be this). |
| `NDS.rowRadius` | `12` | :27 | List rows; the default corner for `ndsHover()`. |
| `NDS.radius` | `14` | :28 | **Controls/fields** — the canonical button radius. All four `MS*ButtonStyle` and `msMenuButtonChrome` use this. (`--r-ctl`) |
| `NDS.cardRadius` | `20` | :29 | Cards, sheets, panels. `msCard`, `MSTintedHeaderCard`. (`--r-card`) |

### 1.3 Button dimension tokens (`NotionDesign.swift:36-44`)

The 44pt minimum tap target is delivered separately via `.minTap()`
(:597-602), never by inflating the visual height.

| Token | Value | Line | Intended use |
|---|---|---|---|
| `NDS.buttonPrimaryH` | `34` | :38 | Height of Primary + Destructive buttons. |
| `NDS.buttonSecondaryH` | `30` | :39 | Height of Secondary buttons AND `msMenuButtonChrome` menu triggers. |
| `NDS.buttonTertiaryH` | `28` | :40 | Height of Tertiary / `MSInlineButton`. |
| `NDS.buttonIconSide` | `30` | :41 | Visible side of a square icon button (`NotionIconButton` frame). |
| `NDS.buttonHPadLg` | `16` | :42 | Horizontal padding for Primary + Destructive. |
| `NDS.buttonHPadMd` | `14` | :43 | Horizontal padding for Secondary + `msMenuButtonChrome`. |
| `NDS.buttonHPadSm` | `12` | :44 | Horizontal padding for Tertiary / `MSInlineButton`. |

### 1.4 Page / pane layout (`NotionDesign.swift:9-34`)

| Token | Value | Line | Intended use |
|---|---|---|---|
| `NDS.pagePadding` | `56` | :10 | Horizontal padding inside `notionPageColumn()` (wide list/board chrome). |
| `NDS.contentMaxWidth` | `1100` | :16 | Max width for wide page-column surfaces (lists/boards) via `notionPageColumn()`. **Not** the detail-canvas measure — see §5. |
| `NDS.splitPaneTopInset` | `60` | :20 | Top inset that clears the translucent Tahoe title bar in a split pane. Used by People list + detail panes so they line up. |
| `NDS.tabTopInset` | `14` | :34 | Permanent top breathing room applied once at the tab host (`MainWindow.tabContent`). |

### 1.5 Motion (`NotionDesign.swift:244-252`)

Always pass call-site animations through `NDS.motion(_:reduce:)`
(:230-232) so Reduce Motion disables them. Read
`@Environment(\.accessibilityReduceMotion)` and pass it as `reduce`.

| Token | Value | Line | Intended use |
|---|---|---|---|
| `NDS.motionFast` | `0.15` | :247 | Hover washes, chevron flips, `MSSection` expand/collapse (`easeInOut(duration: motionFast)`). |
| `NDS.motionStandard` | `0.22` | :248 | Standard content transitions. |
| `NDS.motionSlow` | `0.35` | :249 | Large / page-level transitions. |
| `NDS.springStandard` | `.spring(response: 0.32, dampingFraction: 0.80)` | :252 | Canonical spring for view/page transitions, pill-tab selection, hover affordances. |

> **Inconsistency to fix during migration.** The four `MS*ButtonStyle` press
> animations hard-code `.spring(response: 0.3, dampingFraction: 0.7)`
> (`NotionDesign.swift:509, 545, 563, 579`) instead of `NDS.springStandard`.
> Not user-visible enough to block, but the redesign must not introduce *new*
> hard-coded springs — use `NDS.springStandard`.

### 1.6 The section-label / eyebrow font (`NotionDesign.swift:166-171`)

The redesigns lean hard on the eyebrow label because the de-tabbed canvases use
`MSSection` headers everywhere. The exact tokens:

| Token | Definition | Line | Intended use |
|---|---|---|---|
| `NDS.title` | `font(.display, 30, .heavy, relativeTo: .largeTitle)` | :166 | h1 page titles (list headers). |
| `NDS.pageTitle` | `font(.display, 25, .heavy, relativeTo: .title)` | :167 | Detail-view title (person/meeting name). |
| `NDS.sectionLabel` | `font(.body, 11, .bold, relativeTo: .caption)` | :168 | **The eyebrow.** Section headers (`MSSection`, `MSSectionHeader`, `NotionEyebrow`). Always uppercased + `.tracking(0.6–0.8)` at the call site. |
| `NDS.body` | `font(.body, 14, relativeTo: .callout)` | :169 | Body text, property labels. |
| `NDS.small` | `font(.body, 12, .medium, relativeTo: .footnote)` | :170 | Secondary text, inline-button labels. |
| `NDS.tiny` | `font(.body, 11, .medium, relativeTo: .caption2)` | :171 | Counts, metadata, captions. Counts use `.monospacedDigit()`. |

**Eyebrow tracking is inconsistent in source today and must be standardized:**
`NotionEyebrow` (:458) applies `.tracking(0.6)` while `MSTintedHeaderCard`
(`MSComponents.swift:56`) applies `.tracking(0.8)`; `MSSectionHeader`/`MSSection`
apply none. **Redesign convention: eyebrow = `NDS.sectionLabel` +
`.textCase(.uppercase)` (or `.uppercased()`) + `.tracking(0.6)`.**

---

## 2. Button-style catalogue

### 2.1 The four sanctioned `MS*ButtonStyle` (decomposed)

All four live in `NotionDesign.swift` in the "Full button system" block
(:528-593). Each is a `ButtonStyle`, applied with
`.buttonStyle(MS…ButtonStyle())` on a `Button { } label: { }`.

#### `MSPrimaryButtonStyle` — `NotionDesign.swift:532-547`
The one likely next action. **Max one per section.**
- Font: `scaledFont(13, weight: .bold)` (:534)
- Foreground: `NDS.onAccent` (near-black warm `#2a1208`) (:535)
- Padding: `.horizontal, NDS.buttonHPadLg` (16) (:537)
- Height: `NDS.buttonPrimaryH` (34) (:538)
- Background: `NDS.accentGradient` (coral 135°) in `RoundedRectangle(NDS.radius)` (:539-540)
- Shadow: coral drop-glow `NDS.accent.opacity(0.32)`, r8, y4 (:542)
- Pressed: opacity `0.88`, scale `0.97`, spring `0.3/0.7` (:541, 543, 545)

#### `MSSecondaryButtonStyle` — `NotionDesign.swift:550-565`
Supporting actions; the chrome that button-styled `Menu`s should match.
- Font: `scaledFont(13, weight: .bold)` (:553)
- Foreground: `NDS.textPrimary` (:554)
- Padding: `.horizontal, NDS.buttonHPadMd` (14) (:555)
- Height: `NDS.buttonSecondaryH` (30) (:556)
- Background: `NDS.fieldBg` (→ `NDS.surface2` when pressed) in `RoundedRectangle(NDS.radius)` (:557-558)
- Border: `NDS.hairline`, 1pt (:559-560)
- Pressed: scale `0.98`, spring `0.3/0.7` (:561, 563)

#### `MSDangerButtonStyle` — `NotionDesign.swift:568-581`
Stop / delete / destructive confirm.
- Font: `scaledFont(13, weight: .bold)` (:570)
- Foreground: dark warm `#2a0e12` (:572)
- Padding: `.horizontal, NDS.buttonHPadLg` (16) (:573)
- Height: `NDS.buttonPrimaryH` (34) (:574)
- Background: `NDS.danger` (→ `0.82` opacity when pressed) in `RoundedRectangle(NDS.radius)` (:575-576)
- Pressed: scale `0.97`, spring `0.3/0.7` (:577, 579)

#### `MSTertiaryButtonStyle` — `NotionDesign.swift:584-593`
Ghost text-action. Usually consumed through the `MSInlineButton` wrapper rather
than applied directly.
- Font: `scaledFont(12, weight: .medium)` (:587)
- Foreground: `NDS.textSecondary` (→ `NDS.textPrimary` when pressed) (:588)
- Padding: `.horizontal, NDS.buttonHPadSm` (12) (:589)
- Height: `NDS.buttonTertiaryH` (28) (:590)
- Background: none (ghost); `.contentShape(Rectangle())` only (:591)

> **Legacy aliases — do not use in new code.** `UntitledPrimaryButtonStyle`
> (`NotionDesign.swift:497-511`) and `UntitledSecondaryButtonStyle` (:514-526)
> predate the token system: they hard-code `.padding(.horizontal, 15)
> .padding(.vertical, 9)` instead of the height/padding tokens. They are
> visually close to the MS styles but drift (no fixed `frame(height:)`, so they
> grow with Dynamic Type differently). The migration treats any surviving
> `Untitled*` usage as a swap target.

### 2.2 Repo-wide tally of ad-hoc variants

Counts from a `grep` across `Sources/` (2026-06-17):

| Pattern | Count | Status |
|---|---|---|
| `.buttonStyle(.borderedProminent)` | **29** | BAN — native blue push button, off-theme. |
| `.buttonStyle(.bordered)` (excl. prominent) | **11** | BAN — native bordered, off-theme. |
| `.controlSize(...)` | **88** | Mostly on `ProgressView` (allowed). On a `Button` → BAN. |
| `.buttonStyle(.borderless)` | **75** | Mixed: fine for an icon clear in a text field; BAN for a visible text action → `MSInlineButton`. |
| `.buttonStyle(.plain)` | **200** | Allowed (it's the base for every custom-chrome control). Not a lint target. |
| `.buttonStyle(MSPrimaryButtonStyle())` | 22 | Sanctioned. |
| `.buttonStyle(MSSecondaryButtonStyle())` | 25 | Sanctioned. |

The headline problem: **`.controlSize` on a `Button`, and `.bordered`/
`.borderedProminent`, are native AppKit chrome.** They render a system blue/gray
push button that ignores the Bloom palette, the 30/34pt height tokens, the coral
gradient, and the press spring. Next to an `MSPrimaryButtonStyle` they read as a
different app.

### 2.3 Worst offenders (concrete, with the "why it looks weird")

Ranked by how jarring the mismatch is, all within this spec's five files.

1. **`PersonDetailView.swift:1525-1532`** — a secondary identity header has a
   `Button("Brief Me")` with `.buttonStyle(.borderedProminent)` (:1528), then
   `Edit` and `Delete` with **no style at all** (:1529-1531 → native default
   push buttons). This is the SAME action cluster that the primary identity
   panel renders correctly with `MSPrimaryButtonStyle`/`MSSecondaryButtonStyle`
   at `PersonDetailView.swift:856-874`. Two "Brief Me / Edit / Delete" clusters,
   two completely different looks. **Worst single offender — fix first.**
   - Why weird: coral-vs-blue "Brief Me", and bare gray system Edit/Delete that
     don't even sit at the 30pt token height.

2. **`MeetingSummaryTab.swift:446-447`** — the `followUpButton` ("Draft
   follow-up…") uses `.buttonStyle(.borderedProminent).controlSize(.regular)`.
   A hero action on the summary tab rendered as a native blue button, next to
   coral `MSPrimary` CTAs in the same view. The label even sets its own
   `.font(.callout)` (:444), which the style would otherwise own.
   - Why weird: a blue macOS button is the most prominent thing on a coral page.

3. **`MeetingSummaryTab.swift:714, 720`** — "Save & regenerate" / "Just save" are
   bare `Button("…").controlSize(.small)` with no `buttonStyle`. They render as
   default push buttons (one tinted blue as the default action, one gray).
   - Why weird: a paired confirm/cancel that looks nothing like the
     `MSPrimary + MSSecondary` pair used everywhere else (e.g. the header
     Save/Cancel at `MeetingDetailHeader.swift:127-131`).

4. **`PersonDetailView.swift:1006`** — "Log a check-in" in the health popover:
   `.buttonStyle(.borderedProminent).controlSize(.small).tint(NDS.brand)`. The
   `.tint(NDS.brand)` paints it lilac, so it's a lilac native push button — a
   third button color in the app (coral primary / surface secondary / **lilac
   native**).
   - Why weird: invents a lilac CTA that exists nowhere in the design system.

5. **`PersonDetailView.swift:884, 889, 895, 1172, 1601, 2431, 2524, 2528,
   2611, 2618`** — a recurring cluster of
   `.buttonStyle(.borderless).font(NDS.small)` (and `.font(NDS.tiny)`) inline
   text actions ("Log encounter", "Relationship", "Ask AI", etc.). These are
   exactly the pattern `MSInlineButton` was built to replace (see its doc
   comment, `MSComponents.swift:169-172`).
   - Why weird: `.borderless` gives macOS link-blue text on hover/press and no
     consistent 28pt height; the same label drifts in size between sites
     (`NDS.small` 12pt vs `NDS.tiny` 11pt).

6. **`PersonDetailView.swift:2036, 2122` region** — `.buttonStyle(.borderless)`
   talking-points/reconnect actions sitting in/next to a row that also uses
   `MSSecondaryButtonStyle` (:2122). Mixed bordered/borderless in one cluster.

**Already-correct references** (use these as the pattern):
`MeetingDetailHeader.swift:128/131` (Save/Cancel = Primary/Secondary pair),
`:35/44` (`MSInlineButton`), `:405` (`msMenuButtonChrome`),
`:210` (`MSDangerButtonStyle` for Stop Recording),
`PersonDetailView.swift:856-874` (the canonical identity action cluster),
`UnifiedMeetingDetail.swift:293/313` (Primary + Secondary in the Actions body).

---

## 3. The button system rules

### 3.1 Role → style → height → width

| Role | Use | Height | Width | When |
|---|---|---|---|---|
| **Primary** | `MSPrimaryButtonStyle` | 34 | hug content; never full-width unless it's a sheet's sole CTA | The single most-likely next action. **≤ 1 per section / per header.** |
| **Secondary** | `MSSecondaryButtonStyle` | 30 | hug content | Supporting actions; the second/third button in a cluster. |
| **Secondary menu** | `Menu { … } label: { … }.msMenuButtonChrome()` | 30 | hug content | A `Menu` trigger that must read as a secondary button (the "Options" overflow). |
| **Tertiary / inline** | `MSInlineButton` | 28 | hug content | Inline list/form text actions ("Add 3 to People", "Log encounter", "Ask AI"). |
| **Destructive** | `MSDangerButtonStyle` | 34 | hug content | Stop recording, delete, destructive confirm. |
| **Icon-only** | `NotionIconButton` + `.minTap()` | 30 visible / 44 hit | square | Glyph toolbar/header actions with no label. |
| **Tab** | `MSPillTabs` | — | scrollable row | Tab switching only (being retired on detail canvases → `MSSection`). |
| **Chip / filter** | `MSFilterChip` / `NotionChip` | — | capsule | Filtering and tags, not actions. |

### 3.2 Bans (enforced by lint — see §6.3)

On a `Button` (or a `Menu` styled as a button), the following are **banned**:
- `.buttonStyle(.borderedProminent)` — never. Use Primary.
- `.buttonStyle(.bordered)` — never. Use Secondary.
- `.controlSize(...)` on a `Button` — never. Height comes from the style token.
  (`.controlSize` on `ProgressView`/`TextField` is fine and not linted.)
- `.tint(...)` to recolor a native button — never. Color comes from the style.
- `.buttonStyle(.borderless)` on a *visible text action* — use `MSInlineButton`.
  (Borderless is tolerated only for an icon-glyph clear inside a text field,
  e.g. `MSSearchField`'s clear at `MSComponents.swift:331-332`.)
- Hand-built button chrome (`RoundedRectangle` + `strokeBorder` + manual
  padding) duplicating a style — use the style or `msMenuButtonChrome`.

### 3.3 The F-phase wrappers — exactly when to use each

**`MSInlineButton`** (`MSComponents.swift:173-195`)
```swift
MSInlineButton("Add 3 to People", systemImage: "person.crop.circle.badge.plus") {
    addAllAttendeesToPeople(m)
}
```
- API: `init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void)`.
- Wraps `MSTertiaryButtonStyle` (28pt, muted label, ghost background).
- **Use for:** every inline ghost text-action previously written as
  `.buttonStyle(.borderless).font(NDS.small)`. This is the #1 most-needed swap
  in `PersonDetailView`.
- **Don't use for:** the primary CTA of a section (use Primary), or an
  icon-only action (use `NotionIconButton`).
- Reference good usage: `MeetingDetailHeader.swift:35, 44`.

**`msMenuButtonChrome()`** (`MSComponents.swift:197-214`)
```swift
Menu { … } label: {
    HStack(spacing: 5) {
        Image(systemName: "slider.horizontal.3").scaledFont(12, weight: .medium)
        Text("Options").scaledFont(12, weight: .medium)
    }
    .msMenuButtonChrome()
}
.menuStyle(.borderlessButton)
.fixedSize()
```
- A `View` modifier (NOT a `ButtonStyle` — a `Menu`'s label can't take a
  `ButtonStyle` the way a `Button` can). Paints `MSSecondaryButtonStyle` chrome:
  `scaledFont(13, .bold)`, `textPrimary`, `buttonHPadMd` (14), `buttonSecondaryH`
  (30), `fieldBg`, `hairline`, `NDS.radius`.
- **Use for:** any `Menu` whose label should read as a secondary button — the
  meeting "Options" overflow, future "Export…" / "More" menus.
- **Don't use for:** a real `Button` (use `MSSecondaryButtonStyle`); or a
  borderless inline text menu intentionally NOT styled as a button (e.g. the
  series-spine occurrence menu at `MeetingDetailHeader.swift:590-601`).
- Always pair with `.menuStyle(.borderlessButton).fixedSize()` so the system
  doesn't stack its own chrome on top.
- Reference good usage: `MeetingDetailHeader.swift:401-408`.

### 3.4 Icon-button + `.minTap` rule

- An icon-only action MUST be `NotionIconButton` (`NotionDesign.swift:465-491`),
  which gives the 30pt visible square, hover wash, hairline-on-hover, and a
  VoiceOver label derived from `help` (falling back to a humanized symbol name).
- It MUST carry a 44pt hit target. `NotionIconButton` renders at 30pt; wrap the
  call site (or any other bare icon-only `Button`) in `.minTap()`
  (`NotionDesign.swift:597-602`) to expand the hit area to 44×44 **without**
  changing the visual size.
- A glyph used as a *label inside* a styled button (e.g. the `ellipsis` Image
  inside an `MSSecondaryButtonStyle` button at `PersonDetailView.swift:864-869`)
  is fine and does NOT need `.minTap` — the button's own height + padding
  already exceeds the target. The rule is specifically for bare icon buttons.

---

## 4. `MSSection` spec

`MSSection` (`MSComponents.swift:216-311`) is the spine of both redesigns. The
de-tabbed Meeting and Person canvases stack `MSSection`s in one scroll column
instead of switching `MSPillTabs`. **It is defined and merged but adopted in
zero call sites today** (greenfield — the redesign is its first consumer; a
grep for `MSSection(` across `Sources/` returns nothing).

### 4.1 API

```swift
MSSection<Content: View, Trailing: View>(
    _ title: String,
    systemImage: String? = nil,
    count: Int? = nil,
    persistenceKey: String? = nil,
    defaultExpanded: Bool = true,
    trailing: () -> Trailing,   // optional via the EmptyView overload
    content: () -> Content
)
```

| Param | Type | Default | Meaning |
|---|---|---|---|
| `title` | `String` | — | Eyebrow label, rendered via `NDS.sectionLabel`. |
| `systemImage` | `String?` | `nil` | Optional leading SF Symbol (rendered as a `Label`). |
| `count` | `Int?` | `nil` | Optional trailing count badge (`NDS.tiny.monospacedDigit()`). |
| `persistenceKey` | `String?` | `nil` | If set, expand/collapse persists under `@AppStorage("section.<key>.expanded")`. If `nil`, state is transient `@State`. |
| `defaultExpanded` | `Bool` | `true` | Initial expanded state (and the fallback when no persisted value exists). |
| `trailing` | `() -> Trailing` | `EmptyView` | A trailing accessory (Add button, menu) kept OUTSIDE the toggle's hit area. |
| `content` | `() -> Content` | — | The section body, shown only when expanded. |

Overload (`MSComponents.swift:299-311`): when no trailing is needed,
`Trailing == EmptyView`, so the `trailing:` closure may be omitted entirely.

### 4.2 Header anatomy (`MSComponents.swift:268-291`)

The header is an `HStack(spacing: NDS.spaceSM)`:
- A `Button(action: toggle)` (`.buttonStyle(.plain)`) containing, left→right:
  - chevron `chevron.down` / `chevron.right`, `scaledFont(10, .semibold)`, `textTertiary`
  - title — `Label(title, systemImage:)` or `Text(title)` in `NDS.sectionLabel`/`textSecondary`
  - optional `count` in `NDS.tiny.monospacedDigit()`/`textTertiary`
  - `Spacer(minLength: NDS.spaceSM)` so the whole title row is tappable.
- `trailing()` — **outside** the toggle button, so tapping an Add button never
  collapses the section.
- Header row vertical padding: `.padding(.vertical, NDS.spaceSM)` (:291).
- Body, when expanded: `content().padding(.top, NDS.spaceSM)` (:293).

### 4.3 Trailing slot

The trailing accessory is the section's local action — most often an
`MSInlineButton` ("Add") or a `NotionIconButton`. Because it sits outside the
toggle, it is hit-test-independent of expand/collapse. Keep it to ONE accessory;
multiple actions belong in the section body or an overflow menu.

### 4.4 Animation & persistence

- Toggle animates with `NDS.motion(.easeInOut(duration: NDS.motionFast), reduce: reduceMotion)`
  (:263) — reduce-motion-safe.
- Persistence: `storageKey = "section.\(persistenceKey).expanded"` (:253);
  read/written via `UserDefaults.standard` (:256, :262). The `localExpanded`
  `@State` is also flipped on the persisted path (:264) purely to force a
  re-render — so the *animation* always runs through `localExpanded`.
- **Owns no horizontal padding and no card.** The host wraps it (in the canvas
  column padding, or in an `msCard` if the section should be carded).

### 4.5 Usage — Meeting canvas

```swift
ScrollView {
    VStack(alignment: .leading, spacing: NDS.spaceXL) {
        MSSection("Summary", systemImage: "doc.text",
                  persistenceKey: "meeting.summary") {
            MeetingSummaryTab(…)
        }
        MSSection("Action items", systemImage: "checklist",
                  count: items.count,
                  persistenceKey: "meeting.actions",
                  trailing: {
                      MSInlineButton("Add", systemImage: "plus") { addItem() }
                  }) {
            ForEach(items) { MeetingActionRow(item: $0, …) }
        }
        MSSection("Transcript", systemImage: "text.bubble",
                  persistenceKey: "meeting.transcript",
                  defaultExpanded: false) {
            TranscriptBody(…)
        }
    }
    .padding(NDS.spaceXL)
    .frame(maxWidth: 760)
    .frame(maxWidth: .infinity, alignment: .center)   // see §5
}
```

### 4.6 Usage — Person canvas

```swift
ScrollView {
    VStack(alignment: .leading, spacing: NDS.spaceXL) {
        MSSection("Story", systemImage: "clock.arrow.circlepath",
                  persistenceKey: "person.story") { StoryStream(…) }
        MSSection("Open items", systemImage: "checklist",
                  count: openCount, persistenceKey: "person.openItems",
                  trailing: { MSInlineButton("Log", systemImage: "plus") { showAddEncounter = true } }) {
            …
        }
        MSSection("Relationships", systemImage: "person.2",
                  persistenceKey: "person.relationships", defaultExpanded: false) { … }
    }
    .padding(NDS.spaceXL)
    .frame(maxWidth: 760)
    .frame(maxWidth: .infinity, alignment: .center)
}
```

### 4.7 Persistence-key naming convention

Namespace by canvas so a Meeting section and a Person section never collide on
the same `section.<key>.expanded` default. Lowercase, dot-separated,
singular-canvas prefix.

| Canvas | Prefix | `persistenceKey` values (proposed) | Resolved `@AppStorage` key |
|---|---|---|---|
| Meeting detail | `meeting.` | `meeting.summary`, `meeting.actions`, `meeting.transcript`, `meeting.notes`, `meeting.decisions`, `meeting.attendees` | `section.meeting.<x>.expanded` |
| Person detail | `person.` | `person.story`, `person.openItems`, `person.relationships`, `person.meetings`, `person.notes`, `person.talkingPoints` | `section.person.<x>.expanded` |

Rule: the `persistenceKey` value is `meeting.<x>` / `person.<x>` (the component
prepends `section.` and appends `.expanded`). Do not invent keys outside these
two prefixes for these two canvases.

---

## 5. Spacing & density rules

### 5.1 The canvas column

Both detail canvases use the **same** column recipe today, but **left-aligned,
at 760, with hard-coded padding 20**:

- Meeting `actionsBody`: `.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)` (`UnifiedMeetingDetail.swift:315-317`).
- Person `workArea`: identical at `PersonDetailView.swift:583-585`.

**Redesign rule — the canvas column:**
- Max content width **760** (the detail reading measure; it is NOT
  `NDS.contentMaxWidth` = 1100, which is for wide lists/boards).
- **Center it:** `.frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .center)`.
  The current code centers the *clamp* but then re-pins `.leading`, so on a wide
  window the column hugs the left edge. The redesign centers the column.
- Horizontal padding inside the column: `NDS.spaceXL` (24) — replace the
  hard-coded `20`. (`notionPageColumn()`'s 56 is for the wide list chrome, not
  this measure.)
- Vertical padding top/bottom: `NDS.spaceXL` (24).
- The pane already gets `NDS.splitPaneTopInset` (60) / `NDS.tabTopInset` (14)
  from its host (e.g. `PersonDetailView.swift:572`); don't re-add it.

### 5.2 Spacing between vs within

| Context | Token | Notes |
|---|---|---|
| Between top-level `MSSection`s | `NDS.spaceXL` (24) | The canvas `VStack(spacing:)`. |
| Inside a section, between rows/cards | `NDS.spaceMD` (12) | Matches meeting `actionsBody` VStack (`UnifiedMeetingDetail.swift:282`). |
| Within a card (`msCard` padding) | `NDS.spaceLG` (16) default; `12` for dense cards (`msCard(padding: 12)`) | One density per card type, not per instance. |
| Action row (`HStack` of buttons) | `NDS.spaceSM` (8) | Matches every existing action row: header `actionButtons` (:192), upcoming row (:442), summary feedback row (`MeetingSummaryTab.swift:708`). |
| Label↔value / icon↔text | `NDS.spaceXS` (4) – `NDS.spaceSM` (8) | Fine detail. |

### 5.3 One-density rule

A given surface picks ONE density and holds it. The card default padding is `14`
(`msCard` default, `MSComponents.swift:13`); dense cards use `msCard(padding: 12)`
(already used at `PersonDetailView.swift:1227`). Do not mix `12` and `16`
padding on sibling cards in the same column. Within a single canvas, every
`MSSection` body uses the same inter-row spacing (`NDS.spaceMD`). Inline action
labels are uniformly `MSInlineButton` (so they are uniformly `scaledFont(12,
.medium)` at 28pt) — no per-site `NDS.small`-vs-`NDS.tiny` drift.

---

## 6. Migration plan

Ordered, increment-by-increment. Each increment is independently shippable
(compiles, can be eyeballed) and ends with `swift build -c release`. Group A is
button-style swaps (the visible-drift fixes), Group B is `MSSection` adoption,
Group C is the CI guard.

### Group A — button-style swaps

Every swap removes a banned native variant and substitutes the sanctioned style.
Target style chosen by role (§3.1). Verification for all of A: `swift build -c
release` succeeds **and** `scripts/design-lint.sh` no longer reports the line.

**A1 — PersonDetailView secondary identity header (the worst offender).**
- Files/lines: `PersonDetailView.swift:1525-1532`.
- Change: `Brief Me` `.borderedProminent` → `MSPrimaryButtonStyle`; bare
  `Edit` → `MSSecondaryButtonStyle`; `Delete(role: .destructive)` → keep
  `role: .destructive` and apply `MSSecondaryButtonStyle` (a destructive-tinted
  secondary, matching the canonical cluster at :870-873). Ideally delete this
  duplicate header and reuse the :856-874 cluster outright.
- Verification: the two "Brief Me/Edit/Delete" clusters render identically.
- Risk: **low.** If the two headers serve genuinely different layouts, keep both
  but unify the styles.

**A2 — PersonDetailView health-popover CTA.**
- Line: `PersonDetailView.swift:1006`.
- Change: `.borderedProminent.controlSize(.small).tint(NDS.brand)` →
  `.buttonStyle(MSPrimaryButtonStyle())` (drop `.tint`; coral is the primary).
- Risk: low.

**A3 — MeetingSummaryTab `followUpButton`.**
- Lines: `MeetingSummaryTab.swift:446-447`.
- Change: `.borderedProminent.controlSize(.regular)` →
  `.buttonStyle(MSPrimaryButtonStyle())`. Remove the label's `.font(.callout)`
  (:444) — the style sets the font.
- Risk: low.

**A4 — MeetingSummaryTab feedback pair.**
- Lines: `MeetingSummaryTab.swift:714, 720`.
- Change: "Save & regenerate" → `MSPrimaryButtonStyle`; "Just save" →
  `MSSecondaryButtonStyle`. Remove both `.controlSize(.small)`. Keep the
  `.disabled(...)` on the primary (:715).
- Risk: low.

**A5 — PersonDetailView inline `.borderless` text actions → `MSInlineButton`.**
- Lines (the cluster): `884, 889, 895, 1172, 1601, 2431, 2524, 2528, 2611, 2618`
  (all `.buttonStyle(.borderless).font(NDS.small|tiny)`).
- Change: each `Button { } label: { Label(...) }.buttonStyle(.borderless).font(...)`
  → `MSInlineButton("Title", systemImage: "…") { action }`.
- Verification: every inline action is now 28pt, muted-label, uniform.
- Risk: **medium** — these are scattered and several carry
  `.help(...)`/`.accessibilityLabel(...)`; preserve those by attaching them to
  the `MSInlineButton` (it's a `View`, so the modifiers still apply). The
  *colored* inline actions (`.foregroundStyle(NDS.accent/mint/textTertiary)` at
  `:1564, 2319, 2365, 2977`, etc.) need per-case judgement: a semantic colored
  link can stay a tertiary with the color override; otherwise normalize.

**A6 — PeopleListView `.borderless` actions.**
- Lines: `PeopleListView.swift:514` ("Manage tags"), `:737`
  (`.foregroundStyle(NDS.textTertiary)`).
- Change: text actions → `MSInlineButton`; icon clears → `NotionIconButton +
  .minTap`.
- Risk: low.

**A7 — PersonDetailView remaining bordered/borderless near MS buttons.**
- Lines: `2036, 2122` region (mixed in a cluster with `MSSecondaryButtonStyle`
  at :2122); `1121, 1367, 1909` (`.borderless` icon-ish).
- Change: text actions → `MSInlineButton`; icon clears → `NotionIconButton +
  .minTap`.
- Risk: medium (verify each is text vs icon).

**A8 — Untitled* alias sweep (repo-wide, low priority).**
- Any surviving `UntitledPrimaryButtonStyle` / `UntitledSecondaryButtonStyle`
  → `MSPrimaryButtonStyle` / `MSSecondaryButtonStyle`. (None in the five files
  here; sweep the wider repo when convenient.)
- Risk: low.

### Group B — MSSection adoption

Adopt the collapsible canvas. Do this AFTER Group A so the buttons inside each
section are already correct.

**B1 — Meeting canvas: replace `MSPillTabs` with stacked `MSSection`s.**
- Files: `UnifiedMeetingDetail.swift` (`tabPicker` :254-273, the tab-body
  switch, `actionsBody` :277-319) + the tab bodies (`MeetingSummaryTab`,
  transcript, notes).
- Change: drop `MSPillTabs` + the `tab` `@State`; render one `ScrollView` with
  `MSSection("Summary"…) / ("Action items"…) / ("Transcript"…) / ("Notes"…)`
  using the `meeting.*` persistence keys (§4.7). Apply the §5.1 column recipe.
- Verification: sections expand/collapse, state persists across relaunch, build
  green. Eyeball that the header CTA is still the single primary.
- Risk: **medium-high** — the biggest structural change. Keep the tab bodies as
  the section `content` (don't rewrite them); only swap the container.

**B2 — Person canvas: replace `MSPillTabs` with stacked `MSSection`s.**
- Files: `PersonDetailView.swift` `workArea` (:570-590) + `workContent`
  (the `MSPillTabs` is at :574).
- Change: same as B1 with `person.*` keys.
- Risk: medium-high.

**B3 — Section-header accessory normalization.**
- Anywhere a section currently hand-rolls `NotionEyebrow + Spacer + Button`
  (e.g. meeting `actionsBody` :283-295), move the title into the `MSSection`
  header and the Add action into the section `trailing:` slot.
- Risk: low (mechanical once B1/B2 land).

### Group C — the CI guard

**C1 — extend `scripts/design-lint.sh` with a button-chrome scan.**
- File: `scripts/design-lint.sh` (add new `scan` calls alongside the existing
  four drift classes at :39-49; the `scan` helper already supports the
  `// design-lint:allow` escape hatch).
- Add patterns (UI dirs only):
  ```bash
  # 5. Native AppKit button chrome — use MS*ButtonStyle.
  scan "native .borderedProminent button" '\.buttonStyle\(\.borderedProminent\)'
  scan "native .bordered button"          '\.buttonStyle\(\.bordered\)'
  # 6. .controlSize on a Button (ProgressView / TextField are legitimate).
  #    A line-local grep can't see the enclosing Button, so flag every
  #    .controlSize that is NOT on a ProgressView/TextField line and triage.
  CS="$(grep -rnE --include='*.swift' '\.controlSize\(' "${UI_DIRS[@]}" 2>/dev/null \
        | grep -vE 'ProgressView|TextField' \
        | grep -vE '// *design-lint:allow' || true)"
  # …fold $CS into total the same way the jargon scan does.
  ```
- Flip to `fail` mode in CI only **after** Groups A+B drive the count to zero
  (annotate any deliberate survivor with `// design-lint:allow` + a reason).
- Verification: `scripts/design-lint.sh warn` → 0 across UI+People after A+B;
  `scripts/design-lint.sh fail` exits 0.
- Risk: low (lint-only; the `.controlSize` heuristic may need a small allow-list
  pass for the ~88 legitimate `ProgressView` uses, already excluded above).

### Migration order summary

1. A1 → A2 → A3 → A4 (the four loud `.borderedProminent`/`.controlSize` CTAs).
2. A5 → A6 → A7 (the inline `.borderless` cluster → `MSInlineButton`).
3. A8 (alias sweep).
4. B1 → B2 → B3 (`MSSection` adoption).
5. C1 (lint guard, then flip CI to `fail`).

---

## 7. Consistency checklist

Every page in the audit-2026-06b redesign must pass this before it's considered
done. (Reusable — copy into each page's PR description.)

**Tokens**
- [ ] No raw spacing literals — all gaps/paddings reference `NDS.space*`
      (the canvas `20`→`NDS.spaceXL` migration included).
- [ ] No raw radius literals — `radiusSmall/rowRadius/radius/cardRadius` only;
      pills use `Capsule()`.
- [ ] No raw `.font(.system(size:))` — `NDS` type tokens or `scaledFont(...)`
      (lint class 1).
- [ ] Eyebrows use `NDS.sectionLabel` + uppercase + `.tracking(0.6)`.
- [ ] Any animation is wrapped in `NDS.motion(_:reduce:)` with
      `@Environment(\.accessibilityReduceMotion)`.

**Buttons**
- [ ] Zero `.buttonStyle(.borderedProminent)` / `.bordered`.
- [ ] Zero `.controlSize(...)` on a `Button`; zero `.tint(...)` recoloring a
      native button.
- [ ] No `.buttonStyle(.borderless)` on a visible text action (an icon clear in
      a field is the only exception).
- [ ] Exactly one `MSPrimaryButtonStyle` per section/header.
- [ ] Inline text actions are `MSInlineButton` (28pt, uniform).
- [ ] Menu triggers that should read as buttons use `msMenuButtonChrome()` +
      `.menuStyle(.borderlessButton).fixedSize()`.
- [ ] Icon-only buttons are `NotionIconButton` + `.minTap()` (30 visible / 44
      hit) with a `help`/accessibility label.
- [ ] No hand-built `RoundedRectangle + strokeBorder` button chrome.

**Layout / sections**
- [ ] Canvas column = `maxWidth 760`, **centered**, `NDS.spaceXL` h-padding,
      `NDS.spaceXL` v-padding.
- [ ] Top-level sections are `MSSection` with a `meeting.*` / `person.*`
      `persistenceKey`.
- [ ] Section trailing accessory (if any) is a single action, outside the toggle.
- [ ] Between-section spacing `NDS.spaceXL`; within-section `NDS.spaceMD`;
      action-row `NDS.spaceSM`.
- [ ] One density per card type (`msCard` default 14 / dense 12 — not mixed on
      siblings).
- [ ] Cards use `msCard` / `MSTintedHeaderCard`; empty states use
      `MSEmptyState`; filters use `MSFilterChip`; search uses `MSSearchField`.

**CI**
- [ ] `swift build -c release` green.
- [ ] `scripts/design-lint.sh` reports 0 violations across `UI/` + `People/`
      (or every survivor carries `// design-lint:allow` with a reason).
