# 02 — Person Detail View: Exhaustive Redesign Spec

> Target file: `Sources/MeetingScribe/People/PersonDetailView.swift` (3049 lines).
> Supporting: `Sources/MeetingScribe/UI/MSComponents.swift`,
> `Sources/MeetingScribe/UI/NotionDesign.swift`.
> Scope of this document: redesign spec only. **Do not modify `Sources/` from this doc.**
>
> User complaints driving this work, verbatim:
> 1. "super crammed"
> 2. "weird button sizes for important things"
> 3. "a bunch of unnecessary tabs"
>
> User has separately confirmed: **"fit is good now"** — i.e. nothing currently
> clips at the default window width. §5 (Fit-risk analysis) is the contract that
> the redesign must not regress that, and is the single highest-risk constraint
> on every step in §7.

---

## 0. Reading guide & design-system facts

Everything below leans on the Phase F button system and the collapsible
`MSSection` primitive. Pin these facts before reading the rest:

### 0.1 Button system (one sanctioned style per role)

From `NotionDesign.swift:159-167` (the doc comment) and the style definitions:

| Role        | Style                                 | Height                         | File:line                       | When to use |
|-------------|---------------------------------------|--------------------------------|---------------------------------|-------------|
| Primary     | `MSPrimaryButtonStyle`                | `buttonPrimaryH` = **34pt**    | `NotionDesign.swift:532-547`    | The one likely next action, ≤1 per section. Coral gradient + glow, `onAccent` label, `buttonHPadLg`=16, radius 14. |
| Secondary   | `MSSecondaryButtonStyle`              | `buttonSecondaryH` = **30pt**  | `NotionDesign.swift:550-565`    | Supporting actions; surface fill + hairline; `buttonHPadMd`=14, radius 14. |
| Tertiary    | `MSInlineButton` → `MSTertiaryButtonStyle` | `buttonTertiaryH` = **28pt** | `MSComponents.swift:174-195`, `NotionDesign.swift:584-593` | Inline list/form text actions (the sanctioned replacement for `.borderless`+`NDS.small`). Muted label, `buttonHPadSm`=12, **no border**. |
| Icon-only   | `NotionIconButton` + `.minTap()`      | glyph `buttonIconSide` = **30pt**, hit area **44pt** | `NotionDesign.swift:465-491`, `598-601` | Glyph-only actions (⋯, trash, ×). `.minTap()` gives a 44pt invisible hit target without changing visual size. |
| Destructive | `MSDangerButtonStyle`                 | `buttonPrimaryH` = **34pt**    | `NotionDesign.swift:568-581`    | Stop / delete with weight. Danger fill. |
| Menu chrome | `.msMenuButtonChrome()`               | `buttonSecondaryH` = **30pt**  | `MSComponents.swift:202-213`    | A `Menu` whose label should read as a Secondary button. |

The rule (verbatim from `NotionDesign.swift:160-162`): **"never raw `.bordered` /
`.borderedProminent` / `.controlSize` / bare `.borderless` for a visible action."**
Every violation found in the file is catalogued in §3.

### 0.2 `MSSection` (the de-tabbing primitive)

`MSComponents.swift:216-311`. The redesign's load-bearing component.

- Signature: `MSSection(_ title, systemImage:, count:, persistenceKey:, defaultExpanded:, trailing:, content:)`.
- Chevron + eyebrow title (`NDS.sectionLabel`) + optional `count` (monospaced-digit, `NDS.tiny`) + optional `trailing()` accessory kept **outside** the toggle's hit area (`MSComponents.swift:289`).
- Collapse state: persists when `persistenceKey` is set, via `@AppStorage("section.<key>.expanded")` (`MSComponents.swift:253-258`); else transient `@State` (`localExpanded`).
- Toggle animates with `NDS.motion(.easeInOut(duration: NDS.motionFast=0.15), reduce: reduceMotion)` — already Reduce-Motion aware (`MSComponents.swift:260-266`).
- "Owns no horizontal padding or card — the host wraps it" (`MSComponents.swift:222`). The host scroll provides `.padding(20)`.
- An `EmptyView`-trailing convenience init exists (`MSComponents.swift:299-311`), so `MSSection("Title", count: n) { … }` is legal.

### 0.3 Other tokens referenced

- `NDS.splitPaneTopInset` = 60 (`NotionDesign.swift:20`) — top inset that clears the traffic-light/title region.
- `NDS.radius` = 14, `NDS.cardRadius` = 20, `NDS.radiusSmall` = 8 (`NotionDesign.swift:26-29`).
- `NDS.spaceSM` = 8 (`NotionDesign.swift:238`).
- `NDS.sectionLabel` = 11/700 eyebrow font (`NotionDesign.swift:168`).
- `msCard(padding:accentBorder:)` (`MSComponents.swift:13-21`), `MSSectionHeader` (`MSComponents.swift:124-157`), `MSEmptyState` (`MSComponents.swift:372-408`), `FlowLayout` (used throughout PersonDetailView for wrap-don't-clip rows).

---

## 1. Current architecture catalog

### 1.1 Top-level structure

`PersonDetailView` is a `@available(macOS 14.0, *) struct` (`PersonDetailView.swift:222-2922`)
with 8 `@EnvironmentObject`s (`:224-231`): `people`, `peopleTags`, `manager`,
`chatSession`, `router`, `calendar`, `actionItems`, `decisions`.

`body` (`:362-423`) is an **`HSplitView`** with two children:

1. `detailPane` — `.frame(minWidth: 560, idealWidth: 760)`, `.background(NDS.bg)`, `.background(keyboardVerbs)` (`:367-371`).
2. `personChatColumn` — `.frame(minWidth: 320, idealWidth: 380, maxWidth: 480)` (`:373-374`).

So today this is a **three-column page**: identityPane (fixed 300pt) │ workArea (flex) │ chat (320-480pt).

Lifecycle hooks on `body` (`:377-422`):
- `.onAppear { updateChatContext() }`, `.onChange(of: current.id)` re-context.
- `.task(id: current.id)` × 3: `loadCalendarMeetings()`, `computeInCommon()`, `people.refreshIMessageSignal(...)`.
- `.onDisappear` resets chat context to the People-tab blurb.
- Sheets: `showEdit`→`AddPersonSheet`, `showAddEncounter`→`QuickEncounterSheet`, `showAddRelationship`→`AddRelationshipSheet`, `showAddToMeeting`→`addToMeetingSheet`, `showBrief`→`PersonBriefSheet`.
- `.confirmationDialog` for delete (`:408-422`).

### 1.2 `detailPane` → two sub-panes (`:490-499`)

```
HStack(spacing: 0) {
    identityPane.frame(width: 300).background(NDS.sidebarBg)   // FIXED 300pt
    Divider().overlay(NDS.divider)
    workArea.frame(maxWidth: .infinity)                        // FLEX
}
```

### 1.3 `identityPane` contents (the 300pt left column) — `:503-519`

A single `ScrollView` → `VStack(alignment:.leading, spacing:16)` with `.padding(.horizontal,16)`, `.padding(.top, NDS.splitPaneTopInset)`, `.padding(.bottom,24)`. **Seven** stacked sections:

| # | Section | Builder | File:line | Role |
|---|---------|---------|-----------|------|
| 1 | `identityPanel` | var | `:778-909` | Avatar 56 + name/subtitle (inline-editable) + **two FlowLayout button rows** + relationship-type picker + health badge. |
| 2 | `proactiveInsightCard` | `@ViewBuilder` | `:524-536` | Health ring + one-line deterministic insight; self-hides for `.unset`. |
| 3 | `tagsEditSection` | var | `:1058-1078` | Tag chips (`FlowLayout`) + inline add field with bare `Button("Add")`. |
| 4 | `contactRows` | `@ViewBuilder` | `:1543-1557` | `NotionEyebrow("Contact")` + email/phone/address/birthday rows + `addEmailControl`. |
| 5 | `relationshipsSection` | var | `:1885-1917` | Relationship rows + `Button("Add")` (`.borderless`) + `weeklyRelationshipPrompt`. |
| 6 | `encountersSection` | var | `:1664-1681` | `checkInGoalMenu` + `EncounterHeatMap` + `EncounterRow` list. |
| 7 | `photosSection` | var (conditional) | `:1595-1616` | Horizontal photo strip + `Button("Add")` (`.borderless`). Only when `!photoRelativePaths.isEmpty`. |

### 1.4 `workArea` (the flex middle column) — `:570-590`

```
VStack(spacing: 0) {
    Color.clear.frame(height: NDS.splitPaneTopInset)
    HStack { MSPillTabs(tabs: PersonTab.allCases…, selection: $personTab); Spacer() }
        .padding(.horizontal,20).padding(.bottom,10)
    Divider()
    ScrollView { VStack(spacing:18){ workContent }.padding(20).frame(maxWidth:760)
        .animation(.easeOut(0.18), value: personTab) }
}
```

`PersonTab` enum (`:287-299`): `.overview, .meetings, .messages, .notes` — already
trimmed from 6→4 (comment `:288-289`: "Story folds into Overview, Tasks into Meetings").

### 1.5 `PersonTab` → `workContent` mapping (`:665-693`)

| Tab | Sections rendered | Builders (file:line) |
|-----|-------------------|----------------------|
| `.overview` | reconnect, in-common, notes(bio), favorites, AI suggestions, story, provenance | `reconnectSection :2083`, `inCommonSection :1946`, `notes :1655`, `favoritesEditSection :1110`, `aiSuggestionsSection :1158`, `storySection :628`, `provenanceFooter :2644` |
| `.meetings` | "Add to a meeting" CTA, meeting history, mentioned-in, **tasks**, decisions | inline `Button :677-680`, `meetingHistorySection :1449`, `mentionedInSection :1998`, `tasksSection :1762`, `decisionsSection :1414` |
| `.messages` | messages/iMessage analysis | `messagesSection :2375` |
| `.notes` | talking points, evidence, memories, attached notes | `talkingPointsSection :2301`, `evidenceSection :2232`, `memoriesSection :2346`, `attachedNotesSection :2573` |

**Tab siloing problems (evidence for §2):**
- `tasksSection` is buried under **Meetings** (`:683`) — a user looking for "what does this person owe me" must guess it lives behind the Meetings tab.
- The `.meetings` tab leads with a free-floating "Add to a meeting" button styled `MSSecondaryButtonStyle` (`:677-680`) sitting above the section eyebrows — visually orphaned.
- Two "Notes" concepts collide: `notes` (the bio, in Overview, `:1655`) and `attachedNotesSection` (saved analyses, titled "Notes", in the Notes tab, `:2573`).

### 1.6 `personChatColumn` (the right column) — `:1355-1386`

`VStack` → header `HStack` (`sparkles` + "Chat" + a reset `.borderless` button when messages exist, `:1366-1368`) over `ChatPanel(session:, density:.compact, examplePrompts:[…])`. Background `NDS.sidebarBg`. Header top-inset `NDS.splitPaneTopInset`.

### 1.7 Complete `@State` / `@FocusState` inventory (`:237-312`)

| Property | Type | Line | Drives |
|----------|------|------|--------|
| `showEdit` | Bool | 237 | `AddPersonSheet` |
| `showBrief` | Bool | 238 | `PersonBriefSheet` (2-B) |
| `editingIdentity` | Bool | 242 | Inline identity edit mode |
| `draftName/Role/Company/Email/Phone/Address/Bio` | String×7 | 243-249 | Inline edit drafts |
| `showAddEncounter` | Bool | 250 | `QuickEncounterSheet` |
| `showHealthWhy` | Bool | 252 | Health "why" popover |
| `showAddRelationship` | Bool | 253 | `AddRelationshipSheet` |
| `confirmDelete` | Bool | 254 | Delete dialog |
| `newMemory` | String | 255 | Memory add field |
| `memoryFieldFocused` | `@FocusState` Bool | 257 | `N` keyboard verb focuses memory field |
| `newTalkingPoint` | String | 258 | Talking-point add field |
| `showEvidence` | Bool | 259 | Evidence sheet |
| `showReconnectDraft` / `reconnectDraft` / `reconnectDrafting` / `reconnectError` | mixed | 261-264 | Reconnect opener |
| `newTaskTitle` | String | 265 | Task quick-add |
| `newFavorite` | String | 266 | Favorite add field |
| `newTagName` | String | 267 | Tag add field |
| `aiSuggestions` / `aiRunning` / `aiError` / `dismissedSuggestions` | mixed | 268-271 | AI suggestions card |
| `deepRunning` | Bool | 272 | Deep message analysis |
| `calendarMeetings` | `[Meeting]` | 275 | Unrecorded cal meetings |
| `messageStats` / `messageError` / `analyzingMessages` / `messageWindow` | mixed | 276-280 | iMessage scan |
| `analysisOutput` / `analysisRunning` / `customPromptDraft` / `showCustomPrompt` | mixed | 281-284 | Conversation analysis |
| **`personTab`** | `PersonTab` | 286 | **Which work-area tab is showing (removed in redesign)** |
| `showAddEmail` / `newEmailDraft` | mixed | 301-302 | Inline add-email popover |
| `showAddToMeeting` | Bool | 303 | Add-to-meeting sheet |
| `showAnalyzePopover` / `analyzePreset` / `analyzeRange` | mixed | 305-307 | Analyze popover |
| `noteExpansion` | `[String:Bool]` | 308 | Per-attached-note expand |
| `inCommon` | `[InCommonPerson]` | 312 | Co-attendee rows |

### 1.8 Legacy / dead code present

- `header` (`:1511-1534`): an alternate top-bar with `.borderedProminent` "Brief Me" + bare `Button("Edit")` + bare `Button(role:.destructive)`. **Not referenced by `body`** — superseded by `identityPanel`. The redesign's compact header replaces this concept; this dead var can be deleted.
- `tagRow` (`:1536-1540`): unused alternate tag display.
- `sectionNav(_:)` + `sectionNavItems` (`:698-738`): comment marks it "U3, legacy — superseded by the work-area tabs". The scrolling-pills "cram tell." Unreferenced.

---

## 2. Problem inventory

Severity: **P1** blocks the user complaints directly; **P2** is structural debt
amplifying them; **P3** is polish.

**P1-A — Three-column cram on the default width.** `body` (`:366-375`) forces
identityPane(300) + Divider + workArea(min ~260 inside its `maxWidth:760`) + chat(min 320)
all visible simultaneously. With the HSplitView `minWidth: 560` on the detail half
plus a 320 chat min, the *minimum* total is ~880pt before either side can breathe;
at the user's typical width the middle column is squeezed. This is the literal
"super crammed." Severity **P1**.

**P1-B — 300pt identityPane overload (7 stacked sections).** `identityPane`
(`:503-518`) stacks identity + insight + tags + contact + relationships +
encounters + photos into a *fixed* 300pt rail. The `EncounterHeatMap` (`:1677`),
relationship rows, and tag chips all wrap/clip inside 300pt − 32pt padding = 268pt
usable. This is the densest column and the primary "crammed" offender. Severity **P1**.

**P1-C — Two ragged FlowLayout button rows with mixed heights.** `identityPanel`
renders, back-to-back:
- Row 1 (`:852-875`): `Brief Me` (**Primary 34pt**), `Edit` (**Secondary 30pt**), `⋯` ellipsis (**Secondary 30pt**, icon-in-secondary), `trash` (**Secondary 30pt**, icon-in-secondary).
- Row 2 (`:880-897`): `Log encounter`, `Relationship`, `Ask AI` — all `.buttonStyle(.borderless).font(NDS.small)`.

So the user sees a 34pt pill next to 30pt pills next to borderless text links, all
flowing across a 268pt-usable width into a ragged 2-3 line block. This is exactly
"weird button sizes for important things." Severity **P1**.

**P1-D — Sub-44pt taps on important verbs (the un-sized `.borderless` cluster).**
Row 2's `Log encounter` / `Relationship` / `Ask AI` (`:884, :889, :895`) are
`.borderless` with `font(NDS.small)` — no `.minTap()`, no fixed height. These are
*verbs the user reaches for constantly* (logging a check-in is the core CRM loop)
yet they render as ~20pt-tall text links well under the 44pt tap minimum. Severity **P1**.

**P1-E — `.borderedProminent` reconnect/health CTAs (raw style violation).**
`healthWhyPopover` "Log a check-in" uses `.buttonStyle(.borderedProminent).controlSize(.small).tint(NDS.brand)` (`:1003-1006`); the dead `header` uses `.borderedProminent` for "Brief Me" (`:1525-1528`). Both violate the §0.1 rule and render at a system size that doesn't match the 34pt Primary. Severity **P1** (live popover) / **P2** (dead `header`, deleted anyway).

**P1-F — Bare `Button("Add")` / `Button("Run")` everywhere.** Unstyled
`Button("Add")` at `:1073` (tags), `:1134` (favorites), `:1782` (tasks), `:1890`
(relationships, `.borderless`), `:2308` (talking points), `:2354` (memories); bare
`Button("Run")` at `:2827` (deep), `Button(actionLabel…)` at `:1269` (suggestions),
`Button("Add", systemImage…)` at `:1600` (photos). These inherit the default macOS
push-button look — inconsistent with every styled button on the page. Severity **P1**.

**P1-G — "A bunch of unnecessary tabs."** `MSPillTabs` (`:574`) with 4 tabs in a
column so narrow that `MSPillTabs` itself had to be made horizontally scrolling
(`MSComponents.swift:88-92`, comment: "the person-profile work area can be ~260pt
wide"). A tab bar that *scrolls because it doesn't fit* is the structural cram tell.
The tabs also hide content (Tasks under Meetings — §1.5). Severity **P1**.

**P2-H — The scrolling section-nav pills (cram tell, dead).** `sectionNav` /
`sectionNavItems` (`:698-738`) is a horizontally-scrolling pill rail of 9 section
jump-chips, left in the file though superseded. Its very existence documents that
the page once had so many sections it needed a scrolling jump-rail. Severity **P2** (remove).

**P2-I — Duplicate "Brief Me" + duplicate "Notes."** "Brief Me" exists in both the
live `identityPanel` (`:856`) and the dead `header` (`:1525`). "Notes" is both the
bio (`:1655`) and attached notes (`:2576`). Confusing labels. Severity **P2**.

**P2-J — Inline-text-action `.borderless` clusters.** `analysisPresetMenu` Analyze
(`:2431`), `addEmailControl` (`:1564`), `aiSuggestionsSection` Suggest (`:1172`),
photos Add (`:1601`), Save-to-notes (`:2524`), etc. all use
`.buttonStyle(.borderless).font(NDS.small/.tiny)`. Sanctioned replacement is
`MSInlineButton` (28pt tertiary). Severity **P2**.

**P3-K — `checkInGoalMenu` / `relationshipTypePicker` / `messagesSection` Scan menu**
use `.menuStyle(.borderlessButton)` with no chrome (`:1048, :1708, :2394`). The
sanctioned chrome is `.msMenuButtonChrome()`. Visual, not functional. Severity **P3**.

---

## 3. Button-size audit — every button in the file

Legend for target: **P** = `MSPrimaryButtonStyle`, **S** = `MSSecondaryButtonStyle`,
**T** = `MSInlineButton`/`MSTertiaryButtonStyle`, **D** = `MSDangerButtonStyle`,
**I** = `NotionIconButton` + `.minTap()`, **M** = `.msMenuButtonChrome()`, **plain** = row-button (whole-row tap, keep `.plain`).

| # | Button | File:line | Current style | Target | Notes |
|---|--------|-----------|---------------|--------|-------|
| 1 | Brief Me (identityPanel) | 856-859 | `MSPrimaryButtonStyle` ✓ | **P** | Keep. This is the one Primary. Moves to header. |
| 2 | Edit (identityPanel) | 860-863 | `MSSecondaryButtonStyle` | **→ overflow ⋯ menu item** | Folds into header overflow. |
| 3 | ⋯ ellipsis (full edit sheet) | 864-869 | `MSSecondaryButtonStyle` (icon) | **I** (header overflow trigger) | Becomes the header overflow `Menu` icon. |
| 4 | trash (delete) | 870-874 | `MSSecondaryButtonStyle` (icon) | **→ overflow ⋯ menu item** (destructive) | Out of the always-visible row. |
| 5 | Save (identity edit) | 841-844 | `MSPrimaryButtonStyle` ✓ | **P** | Keep (edit mode). |
| 6 | Cancel (identity edit) | 845-846 | `MSSecondaryButtonStyle` ✓ | **S** | Keep. |
| 7 | Log encounter | 881-885 | `.borderless`+`NDS.small` | **S** | Promote: core verb, deserves 30pt + min-tap. Moves into Encounters section header `trailing`. |
| 8 | Relationship | 886-889 | `.borderless`+`NDS.small` | **T** (Relationships section `trailing`) | 28pt inline add. |
| 9 | Ask AI | 892-895 | `.borderless`+`NDS.small` | **T** or drop | Chat is always visible in redesign → demote to `MSInlineButton`, or drop (redundant with the persistent chat). |
| 10 | Log a check-in (health popover) | 1003-1006 | `.borderedProminent`+`controlSize(.small)`+tint | **P** | Fix raw violation. |
| 11 | Add tag | 1073 | bare `Button` + `NDS.small` | **T** | `MSInlineButton("Add")`. |
| 12 | remove-favorite × | 1118-1121 | `.borderless` (icon) | **I** + `.minTap()` | Chip remove glyph. |
| 13 | Add favorite | 1134 | bare `Button` + `NDS.small` | **T** | |
| 14 | Suggest / Refresh (AI) | 1167-1172 | `.borderless`+`NDS.small` | **T** (section `trailing`) | |
| 15 | suggestionChip accept | 1242-1254 | `.plain` (chip) | **plain** | Keep — it's a chip, not a button. |
| 16 | suggestionRow accept | 1269 | bare `Button`+`NDS.small` | **T** | |
| 17 | reset chat | 1366-1368 | `.borderless` (icon) | **I** + `.minTap()` | |
| 18 | decisions row | 1423-1443 | `.plain` (row) | **plain** | Whole-row navigation. |
| 19 | Add to a meeting (Meetings tab) | 677-680 | `MSSecondaryButtonStyle` | **S** (Meetings section `trailing`) | Moves into section header. |
| 20 | timelineRow (recorded) | 1476 | `.plain` (row) | **plain** | |
| 21 | header Brief Me (dead) | 1525-1528 | `.borderedProminent` | **delete** | Dead `header`. |
| 22 | header Edit (dead) | 1529 | bare `Button` | **delete** | |
| 23 | header Delete (dead) | 1530-1532 | bare `Button(role:.destructive)` | **delete** | |
| 24 | addEmailControl trigger | 1561-1564 | `.borderless`+`NDS.tiny` | **T** | Inline "Add email". |
| 25 | addEmail Cancel | 1573 | bare `Button` | **S** | Popover footer. |
| 26 | addEmail Add | 1574-1576 | `MSPrimaryButtonStyle` ✓ | **P** | Keep. |
| 27 | photos Add | 1600-1601 | `.borderless`+`NDS.small` | **T** (section `trailing`) | |
| 28 | contactRow mailto/tel | 1643-1646 | `.plain` (link) | **plain** | Keep — inline link. |
| 29 | task complete toggle | 1835-1842 | `.borderless` (icon) | **plain** + `.minTap()` | Checkbox; needs 44pt tap AND its done/open tint is meaningful → keep `.plain` + `.minTap()`, not NotionIconButton (which forces a muted tint). |
| 30 | task open (row) | 1844-1878 | `.plain` (row) | **plain** | |
| 31 | task → meeting jump | 1863-1867 | `.plain` (nested) | **plain** | |
| 32 | relationships Add | 1890-1892 | `.borderless`+`NDS.small` | **T** (section `trailing`) | |
| 33 | remove-relationship × | 1906-1909 | `.borderless` (icon) | **I** + `.minTap()` | |
| 34 | inCommon row | 1955-1973 | `.plain` (row) | **plain** | |
| 35 | mentioned-in row | 2010-2029 | `.plain` (row) | **plain** | |
| 36 | log-meeting-as-encounter + | 2032-2038 | `.borderless` (icon) | **I** + `.minTap()` | |
| 37 | Draft an opener (reconnect) | 2119-2122 | `MSSecondaryButtonStyle` ✓ | **S** | Keep. |
| 38 | reconnect Copy (sheet) | 2162-2167 | bare `Button` | **S** | |
| 39 | reconnect Done | 2168 | bare `Button` | **S** | |
| 40 | Compile evidence | 2236-2238 | bare `Button` | **S** | |
| 41 | evidence Copy | 2253-2257 | bare `Button` | **S** | |
| 42 | evidence Done | 2258 | bare `Button` | **S** | |
| 43 | talking-point Add | 2308-2309 | bare `Button` | **T** | |
| 44 | talking-point done × | 2316-2320 | `.borderless` (icon, mint tint) | **plain** + `.minTap()` | Mint tint is meaningful → keep `.plain`. |
| 45 | memory Add | 2354-2355 | bare `Button` | **T** | |
| 46 | memory delete × | 2362-2365 | `.borderless` (icon) | **I** + `.minTap()` | |
| 47 | Scan menu (messages) | 2387-2394 | `.menuStyle(.borderlessButton)` | **M** | `.msMenuButtonChrome()`. |
| 48 | Analyze… | 2428-2431 | `.borderless`+`NDS.small` | **T** | |
| 49 | Run analysis (popover) | 2492-2503 | `MSPrimaryButtonStyle` ✓ | **P** | Keep. |
| 50 | analysis Save to notes | 2521-2524 | `.borderless`+`NDS.tiny` | **T** | |
| 51 | analysis dismiss × | 2525-2529 | `.borderless`+`NDS.tiny` (icon) | **I** + `.minTap()` | |
| 52 | customPrompt Cancel/Run | 2558-2564 | bare `Button` | **S** / **P** | |
| 53 | deep analysis Run/Refresh | 2827 | bare `Button`+`NDS.small` | **T** | |
| 54 | attachedNote expand chevron | 2606-2611 | `.borderless`+`NDS.tiny` (icon) | **I** + `.minTap()` | |
| 55 | attachedNote delete | 2612-2618 | `.borderless`+`NDS.tiny` (icon) | **I** + `.minTap()` | |
| 56 | addToMeeting Done | 438 | bare `Button` | **S** | |
| 57 | addToMeeting row | 451-465 | `.plain` (row) | **plain** | |
| 58 | encounter delete × | 2976-2977 | `.borderless` (icon) | **I** + `.minTap()` | In `EncounterRow`. |
| 59 | checkInGoalMenu | 1704-1710 | `.menuStyle(.borderlessButton)` | **M** | |
| 60 | relationshipTypePicker | 1041-1049 | `.menuStyle(.borderlessButton)` | **M** | Becomes header metadata-row control. |
| 61 | AddRelationshipSheet Cancel/Save | 3006-3008 | bare `Button` | **S** / **P** | In `AddRelationshipSheet`. |

**Consistent role→style→height rules (the contract):**

1. **One Primary per visible surface.** The header gets exactly one: `Brief Me`. Sheets/popovers get exactly one (their confirm). Nowhere else.
2. **Supporting actions = Secondary (30pt).** Sheet Cancel/Copy/Done, "Draft an opener", "Compile evidence", "Add to a meeting", "Log encounter".
3. **Inline add/text actions = `MSInlineButton` (28pt).** Every "Add" in a section header, "Suggest", "Analyze…", "Save to notes", "Run" (deep).
4. **Glyph-only actions = `NotionIconButton` + `.minTap()`** — EXCEPT where the glyph's tint carries meaning (task checkbox done/open, mint talking-point done): those stay `.plain` + `.minTap()` because `NotionIconButton` forces `NDS.textSecondary`.
5. **Menu triggers that should read as buttons = `.msMenuButtonChrome()`** (30pt). Type picker, Scan, goal menu.
6. **Destructive-with-weight = Danger (34pt).** Only the confirm-delete path; everything else is an overflow menu item with `role: .destructive`.
7. **Whole-row navigation = `.plain`** (unchanged): timeline rows, in-common, decisions, mentioned-in, task-open.

---

## 4. Proposed layout

### 4.0 The shape

Two columns, not three:

```
HSplitView {
    personCanvas   // ScrollView of: compactHeader + stacked MSSections   (minWidth 480, ideal 720)
    personChatColumn   // unchanged, always present                       (minWidth 300, ideal 360, max 460)
}
```

- **Delete** `detailPane`, `identityPane`, `workArea`, `workContent`, `MSPillTabs` usage, `PersonTab`, and `personTab` state.
- The left column becomes one `ScrollView` (`personCanvas`) that wraps a `compactHeader` followed by a vertical stack of `MSSection`s. No inner left/right split.

### 4.1 `compactHeader` — full width, one Primary, one overflow

Replaces the avatar+name+button-pile that lived in `identityPanel` (`:778-909`).
Goal: kill P1-C/D/E/G by moving all the action clutter off the narrow rail onto the
full canvas width, and reducing to **one** visible CTA + **one** overflow trigger.

```
VStack(alignment:.leading, spacing: 12) {
    // Row 1 — identity + the single CTA + overflow
    HStack(alignment:.center, spacing: 12) {
        MSAvatar(name: current.displayName, size: 48)
        VStack(alignment:.leading, spacing: 2) {
            Text(current.displayName)               // 22/heavy; tap → beginIdentityEdit() (keep :810 gesture)
                .lineLimit(1).truncationMode(.tail)  // R1 guard
            if !subtitle.isEmpty { Text(subtitle) … 12/secondary .lineLimit(1) }
        }
        Spacer(minLength: 8)
        Button { showBrief = true } label: { Label("Brief Me", systemImage:"sparkles") }
            .buttonStyle(MSPrimaryButtonStyle())                       // the ONE Primary
        Menu {                                                          // overflow ⋯
            Button { beginIdentityEdit() }     { Label("Edit name & role", systemImage:"pencil") }
            Button { showEdit = true }         { Label("Edit all fields…", systemImage:"square.and.pencil") }
            Button { showAddEncounter = true } { Label("Log encounter", systemImage:"calendar.badge.plus") }
            Button { showAddRelationship = true } { Label("Add relationship", systemImage:"person.2.badge.plus") }
            Button { showAddToMeeting = true } { Label("Add to a meeting", systemImage:"calendar.badge.plus") }
            Divider()
            Button(role:.destructive) { confirmDelete = true } { Label("Delete \(firstName)", systemImage:"trash") }
        } label: { Image(systemName:"ellipsis") }
            .menuStyle(.borderlessButton)                              // chrome → 30pt glyph + .minTap()
    }
    // Row 2 — metadata, the FIT GUARDRAIL (FlowLayout so it wraps, never clips)
    FlowLayout(spacing: 8) {
        relationshipTypePicker                                         // .msMenuButtonChrome()
        if let health = relationshipHealth { healthBadge(health) }     // existing capsule, :941
        if let since = knownSinceLine { Text(since) … tiny/tertiary }  // "Known for 3 years…"
    }
}
.padding(.horizontal, 20).padding(.top, NDS.splitPaneTopInset).padding(.bottom, 8)
```

Exact secondary actions in the overflow `Menu` (so they leave the always-visible
surface but stay one tap away): **Edit name & role**, **Edit all fields…**, **Log
encounter**, **Add relationship**, **Add to a meeting**, **Delete** (destructive,
below a Divider). Note: "Log encounter" / "Add relationship" / "Add to a meeting"
*also* live as section `trailing` accessories (Encounters / Relationships /
Meetings) — the overflow is the redundant always-reachable path; the section
header is the contextual path.

Edit mode (`editingIdentity == true`) keeps the existing inline form
(`:817-847`) but renders it *inside the header block*, full-width — the
name/role/company/email/phone/address/bio fields now have the whole canvas width
instead of 268pt, so the form stops feeling cramped too. Save = **P**, Cancel = **S** (unchanged).

### 4.2 The `MSSection` stack (order, mapping, collapse, persistence keys)

Below the header, one stack of `MSSection`s. Each maps from existing builders.
`persistenceKey` values are namespaced `person.<key>` → stored as
`section.person.<key>.expanded` (`MSComponents.swift:253`).

| Order | `MSSection` title | systemImage | count | persistenceKey | defaultExpanded | Body = (existing builder, file:line) | Notes |
|------:|-------------------|-------------|-------|----------------|-----------------|--------------------------------------|-------|
| 1 | **Reconnect** | `hand.wave.fill` | — | `person.reconnect` | true (whole section self-hides unless overdue/drifting) | `reconnectSection` body `:2083-2141` | Keep the self-hide guard around the `MSSection`; when present, expanded. |
| 2 | **Insight** | — | — | (none — transient) | true | `proactiveInsightCard` `:524-536` | Tiny; render directly under the header rather than as a chevron section (one line). Self-hides for `.unset`. |
| 3 | **Tasks** ⭐ | `checklist` | open-count | `person.tasks` | **true** | `tasksSection` body `:1762-1795` (quick-add + `commitmentLedger`) | **Promoted to top-level, expanded** (§6). Header count = open items. |
| 4 | **Tags** | `tag` | tags.count | `person.tags` | true | `tagsEditSection` `:1058-1078` | Inline add via `MSInlineButton`. |
| 5 | **Contact** | `person.crop.circle` | — | `person.contact` | true | `contactRows` `:1543-1557` | "Add email" → `MSInlineButton`. |
| 6 | **Relationships** | `person.2` | rels.count | `person.relationships` | true | `relationshipsSection` `:1885-1917` + `weeklyRelationshipPrompt` | "Add" → section `trailing` `MSInlineButton`. |
| 7 | **In common** | `person.2.fill` | inCommon.count | `person.incommon` | false | `inCommonSection` `:1946-1977` | Self-hides if empty (keep guard around the section). |
| 8 | **Meetings** | `calendar` | rows.count | `person.meetings` | true | `meetingHistorySection` `:1449-1469` + `mentionedInSection` `:1998-2044` | "Add to a meeting" → `trailing` Secondary. |
| 9 | **Decisions** | `checkmark.seal` | mine.count | `person.decisions` | false | `decisionsSection` `:1414-1447` | Self-hides if empty (keep guard). |
| 10 | **Encounters** | `mappin.and.ellipse` | mine.count | `person.encounters` | true | `encountersSection` `:1664-1681` | `checkInGoalMenu` → `trailing` (`.msMenuButtonChrome()`); "Log encounter" → `trailing` Secondary. |
| 11 | **Messages** | `message` | — | `person.messages` | **false** | `messagesSection` `:2375-2417` | Heavy/async; default collapsed so it doesn't auto-scan. Scan → `trailing` `.msMenuButtonChrome()`. |
| 12 | **Discuss next time** | `bubble.left` | points.count | `person.talkingpoints` | false | `talkingPointsSection` `:2301-2326` | |
| 13 | **Memories** | `sparkles` | memories.count | `person.memories` | false | `memoriesSection` `:2346-2371` | `N` keyboard verb still focuses this field (see §8.4). |
| 14 | **About** | `text.alignleft` | — | `person.bio` | false | `notes` (bio) `:1655-1662` | Renamed from "Notes" → "About" to kill the P2-I collision. Only shows if bio non-empty or editing. |
| 15 | **Saved analyses** | `doc.text` | notes.count | `person.attachednotes` | false | `attachedNotesSection` `:2573-2592` | Renamed from "Notes" → "Saved analyses." |
| 16 | **AI suggestions** | `wand.and.stars` | — | `person.aisuggestions` | false | `aiSuggestionsSection` `:1158-1228` | Already a `msCard`; render inside section body. |
| 17 | **Perf-review evidence** | `doc.text.magnifyingglass` | — | `person.evidence` | false | `evidenceSection` `:2232-2245` | |
| 18 | **Photos** | `photo` | photos.count | `person.photos` | false | `photosSection` `:1595-1616` | Only if `!photoRelativePaths.isEmpty`. |
| — | provenanceFooter | — | — | — | — | `provenanceFooter` `:2644-2649` | Stays a plain footer line (not a section). |

Notes on collapse defaults: the **everyday-glance** sections default expanded
(Reconnect, Insight, Tasks, Tags, Contact, Relationships, Meetings, Encounters);
the **on-demand / heavy** sections default collapsed (Messages, Discuss, Memories,
About, Saved analyses, AI suggestions, Evidence, Photos, In common, Decisions).
Because state persists per-key, a user who opens Messages once keeps it open.

The "Story" timeline (`storySection :628`) is *intentionally dropped from the
default stack* — it duplicates Meetings + Encounters + Memories + Decisions, which
are now all first-class sections. Optionally keep it behind a collapsed section
`person.story` defaultExpanded:false if the chronological union is still wanted;
recommend dropping to reduce count. (`StoryItem`/`storyItems` at `:595-625` would
become dead code if dropped — delete them too.)

### 4.3 Why this fixes the three complaints

- "Crammed" → the 300pt rail is gone; every section uses the full ~720pt canvas, and 10 of 18 sections start collapsed so the first screen is short.
- "Weird button sizes" → §3 normalizes every button to the role table; the header has exactly one Primary and one icon overflow.
- "Unnecessary tabs" → `MSPillTabs` + `PersonTab` deleted entirely; collapsible sections replace tab siloing, and the user controls what's open.

---

## 5. Fit-risk analysis

The user confirmed **"fit is good now."** That is true today for two reasons we
must preserve:

1. **Multi-control rows already use `FlowLayout`**, which wraps instead of clipping. The identity action rows (`:852, :880`), tag chips (`:1062`), favorites (`:1114`), AI tag suggestions (`:1189`), and the Analyze time-range pills (`:2477`) all wrap to a second line rather than overflow. Nothing in those rows is fixed-width.
2. **The narrowest container is the 300pt identityPane**, and everything in it was sized/wrapped to survive 268pt usable. The work-area `MSPillTabs` was made horizontally-scrolling precisely so it can't clip (`MSComponents.swift:88-92`).

The redesign **widens** the constraint, which is inherently safer: moving all
actions from the 268pt rail to the ~720pt canvas means every row that fit at 268pt
now has 2.7× the room. But three new fit risks appear and must be guarded:

- **R1 — compactHeader Row 1 overflow.** Avatar + long name + "Brief Me" (Primary, ~120pt) + ⋯ on one `HStack`. A very long `displayName` could push the CTA off-edge at the new `minWidth: 480`. **Guard:** `Text(name).lineLimit(1).truncationMode(.tail)` + `Spacer(minLength: 8)` before the CTA; the CTA + ⋯ are fixed-width and right-anchored. The name truncates, the buttons never clip.
- **R2 — compactHeader Row 2 (metadata).** Type picker + health badge + "Known since" line. **Guard:** this row is a `FlowLayout` (the explicit fit guardrail in §4.1) — it wraps to 2 lines on a narrow canvas exactly like today's identity rows do. This is the single most important fit decision in the redesign: *keep multi-control rows in `FlowLayout`.*
- **R3 — `HSplitView` minimums.** Lowering the detail `minWidth` 560→480 and the chat `minWidth` 320→300 reduces the floor from ~880 to ~780, giving the canvas more slack at typical widths. **Guard:** keep `idealWidth` generous (canvas 720, chat 360) so the default open width is comfortable.

**Per-step fit risk** is called out inline in §7. The overarching rule: **never
introduce a fixed-width `HStack` of two-or-more text controls; if a row has ≥2
controls that could grow, it goes in a `FlowLayout`.**

---

## 6. Tasks integration (promotion)

Today `tasksSection` (`:1762`) + `commitmentLedger` (`:1801`) are buried under the
Meetings tab (`:683`). The redesign promotes them to **Section #3, top-level,
`defaultExpanded: true`**, directly under the header/insight.

- **Open-count in the `MSSection` header.** `MSSection`'s `count:` parameter
  (`MSComponents.swift:281-283`) shows a monospaced-digit badge. Feed it
  `personTasks.filter { $0.status != .completed }.count` — the same count
  `tasksSection` computes inline today (`:1768`). So the section header reads
  e.g. "Tasks 3" without expanding.
- **`commitmentLedger` stays** (`:1801-1817`): the "Waiting on {first}" / "{first}'s
  open items" / "Completed" grouping (via `ledgerGroup` `:1819-1829` and `taskRow`
  `:1831-1883`) is the owe/owed picture. Render it as the section body when
  `!personTasks.isEmpty`, else the existing empty-state line (`:1788`).
- **Quick-add** (`:1775-1786`) stays as the first child of the section body — a
  field with `MSInlineButton("Add")` (was bare `Button("Add")`, §3 #45-analog at
  `:1782`). `addTaskForPerson()` (`:1754-1760`) is unchanged.
- **Owner/meeting links preserved.** `taskRow` (`:1832-1883`) already links the
  checkbox (`setStatus`), the row (`router.route(kind:.actionItem)`), and the
  meeting jump (`router.openMeeting`, `:1863`). Only the checkbox button changes:
  `.borderless` icon → `.plain` + `.minTap()` (§3 #29) for a 44pt tap while keeping
  the meaningful done/open tint. The matching logic (`ownerMatchesPerson` `:1731`,
  `ownerTokens` `:1717`, `personTasks` `:1744`) is untouched.

---

## 7. Exhaustive build plan (small increments)

Each step: **title · files · change + sketch · build-verification · risk.** Build
after every non-trivial step (`swift build -c release` per CLAUDE.md). Sequence is
ordered so the app compiles and runs at every step (button cleanup is purely
additive/cosmetic before any structural change).

### Phase A — Button cleanup (no structural change; app stays tabbed)

**A1 · Delete dead code.**
- File: `PersonDetailView.swift`.
- Remove `header` (`:1511-1534`), `tagRow` (`:1536-1540`), `sectionNav(_:)` + `sectionNavItems` (`:698-738`). All unreferenced.
- Verify: build succeeds; `grep -n "sectionNav\|tagRow\|var header\b\| header\b"` shows no remaining call sites.
- Risk: **low** — confirm zero references first.

**A2 · Fix the live raw-style violation.**
- `healthWhyPopover` "Log a check-in" (`:1003-1006`): `.borderedProminent`+`controlSize`+tint → `.buttonStyle(MSPrimaryButtonStyle())`.
- Verify: popover button renders coral 34pt; build clean.
- Risk: **low**.

**A3 · Convert bare/`.borderless` text actions → `MSInlineButton`.**
- §3 #11,13,14,16,24,27,43,45,48,50,53 (tag/favorite/talking-point/memory/photos/suggest/analyze/save/deep/suggestionRow "Add"/"Run"/"Refresh").
- Sketch: `if !newTagName.isEmpty { MSInlineButton("Add") { commitTagEntry() } }`.
- Verify: each renders 28pt muted; build clean; visually scan each section.
- Risk: **low**. Rewrite the short-form `Button("Add", action:)` at talking points (`:2308`) and memories (`:2354`) as `MSInlineButton("Add") { addTalkingPoint() }` / `{ addMemory() }`, preserving the existing `.disabled(...)` by wrapping/guarding inside the action or moving the guard to the field's `onSubmit` (the actions already no-op on empty).

**A4 · Convert glyph buttons → `NotionIconButton` + `.minTap()` (tint-neutral) or `.plain` + `.minTap()` (tint-meaningful).**
- `.minTap()` only: §3 #29 (task checkbox, keep done/open tint), #44 (talking-point done, keep mint).
- `NotionIconButton`+`.minTap()`: §3 #12,17,33,36,46,51,54,55,58 (chip ×, reset chat, remove-rel, log-meeting +, memory delete, analysis dismiss, note expand/delete, encounter delete).
- Sketch (encounter delete, `EncounterRow` `:2976`): `NotionIconButton(systemName:"xmark.circle.fill", help:"Delete encounter") { onDelete() }.minTap()`.
- Verify: each glyph has a 44pt hit area (click near the edge); colored glyphs keep their color; build clean.
- Risk: **medium** — `NotionIconButton` forces `foregroundStyle(NDS.textSecondary)`; that's why #29/#44 stay `.plain`. Double-check VoiceOver labels survive (NotionIconButton derives one from `help`).

**A5 · Menu chrome.**
- `relationshipTypePicker` (`:1041-1049`), `checkInGoalMenu` (`:1704-1710`), Scan menu (`:2387-2394`): apply `.msMenuButtonChrome()` to the `Menu` label. Keep `.fixedSize()` on Scan; drop `.menuStyle(.borderlessButton)` if the chrome supplies the look (test for double-chrome — keep both if the menu still needs `.borderlessButton` to suppress the system bezel).
- Verify: triggers read as 30pt secondary buttons; build clean.
- Risk: **low/medium**.

**A6 · Sheet/popover footers → Secondary; sheet confirms → Primary.**
- §3 #25,38,39,40,41,42,52,56,61 (addEmail Cancel, reconnect Copy/Done, evidence Compile/Copy/Done, customPrompt Cancel, addToMeeting Done, AddRelationshipSheet Cancel → S; customPrompt Run, AddRelationshipSheet Save → P).
- Verify: build clean; sheets render consistent 30/34pt footers.
- Risk: **low**.

> After Phase A, the page is still tabbed but every button obeys §3. Commit point.

### Phase B — Compact header

**B1 · Add `compactHeader` var.**
- File: `PersonDetailView.swift`.
- Build the §4.1 view: Row 1 `HStack` (avatar 48, name/subtitle, Spacer, Brief Me Primary, ⋯ overflow Menu) + Row 2 `FlowLayout` (type picker, health badge, known-since). Keep the existing `beginIdentityEdit()` tap gesture on the name (`:810`) and the existing `editingIdentity` inline form (`:817-847`), full-width.
- Move `Edit`/`⋯ full sheet`/`Delete`/`Log encounter`/`Add relationship`/`Add to a meeting` into the overflow `Menu` items.
- Verify: build clean; header renders; overflow menu lists all six items + destructive Delete.
- Risk: **medium** — **R1** (name overflow): apply `.lineLimit(1).truncationMode(.tail)` + `Spacer(minLength:8)`. **R2** (metadata wrap): Row 2 must be `FlowLayout`.

**B2 · Swap `identityPanel`'s button rows for `compactHeader` (still inside identityPane for now).**
- Temporarily render `compactHeader` at the top of `identityPane` and delete the two FlowLayout button rows (`:852-897`) + the standalone `relationshipTypePicker`/`healthBadge` block (`:899-907`) from `identityPanel`.
- Verify: build + run; the 300pt rail now leads with the compact header; no orphaned buttons.
- Risk: **medium** — header at 300pt is the *tightest* it'll ever be (it widens in Phase C); a good early fit test. If it survives 300pt it survives the canvas.

### Phase C — Collapse two panes into one scroll

**C1 · Introduce `personCanvas`.**
- New `ScrollView` whose content is `compactHeader` + a `VStack(spacing:18)` placeholder that *temporarily re-renders the existing identityPane sections + workContent inline* (no tabs), to prove the single-column layout before converting to `MSSection`.
- Verify: build + run at narrow and wide widths; everything visible in one scroll.
- Risk: **medium** — content ordering will be ugly mid-migration; acceptable transient state.

**C2 · Repoint `body` to the two-column split.**
- Replace the `detailPane` child of the `HSplitView` with `personCanvas`; lower mins per §5/R3 (`personCanvas.frame(minWidth:480, idealWidth:720)`, `personChatColumn.frame(minWidth:300, idealWidth:360, maxWidth:460)`). Move `.background(NDS.bg)` and `.background(keyboardVerbs)` onto `personCanvas`.
- Delete `detailPane`, `identityPane`, `workArea`, `workContent`.
- Verify: build + run; chat still present; one scroll on the left.
- Risk: **high** — biggest structural change. Keep `personChatColumn` untouched.

### Phase D — Convert sections to `MSSection` + delete tabs

**D1 · Wrap each builder in `MSSection`** per §4.2 table, in order, inside `personCanvas`'s `VStack(spacing:18)`. Use the exact `title`/`systemImage`/`count`/`persistenceKey`/`defaultExpanded` from the table. Move per-section add actions into `trailing:` closures. Add `.padding(.horizontal,20)` once on the canvas `VStack` (MSSection owns no horizontal padding — `MSComponents.swift:222`).
- Sketch (Tasks): `MSSection("Tasks", systemImage:"checklist", count: personTasks.filter{ $0.status != .completed }.count, persistenceKey:"person.tasks", defaultExpanded:true) { tasksBody }` where `tasksBody` = quick-add + ledger (today's `tasksSection` body minus its own eyebrow `HStack` `:1765-1772`).
- Verify: build + run; each section collapses/expands; counts correct; collapse state persists across relaunch (inspect `UserDefaults` key e.g. `section.person.messages.expanded`).
- Risk: **high** — many sections; do them a handful at a time, building between. **Strip each builder's own `Text(title).font(NDS.sectionLabel)` header** (now provided by `MSSection`) to avoid double titles — affects `tagsEditSection :1060`, `favoritesEditSection :1112`, `relationshipsSection :1888`, `encountersSection :1668`, `tasksSection :1766`, `memoriesSection :2348`, `talkingPointsSection :2303`, `attachedNotesSection :2576`, `messagesSection :2378`, `decisionsSection :1421`, `mentionedInSection :2003`, `inCommonSection :1952`, `notes :1657`, `evidenceSection :2234`, `aiSuggestionsSection :1161`, `photosSection :1598`. Rename "Notes"→"About" (bio) and "Notes"→"Saved analyses" (attached) per P2-I.

**D2 · Delete `MSPillTabs` usage + `PersonTab` + `personTab`.**
- Remove the enum (`:287-299`), the `@State personTab` (`:286`), the `.animation(.easeOut(0.18), value: personTab)` (gone with `workArea`), and any remaining references.
- Verify: build clean; `grep -n "PersonTab\|personTab"` → zero.
- Risk: **medium** — `keyboardVerbs` references `personTab` (next step blocks the build until fixed; do D2 and E1 together).

### Phase E — `keyboardVerbs` repoint

**E1 · Rewrite `keyboardVerbs`** (`:344-360`).
- `N` (add memory): keep `memoryFieldFocused = true`; remove `personTab = .overview`. Expand the Memories section first (set `UserDefaults section.person.memories.expanded = true`) so the field is rendered before focusing (§8.4). Optionally scroll to it with a `ScrollViewReader`.
- `L` (log encounter): keep `showAddEncounter = true`.
- `T` (new task): add a `@FocusState taskFieldFocused`; ensure Tasks is expanded (it defaults expanded) and focus the quick-add field instead of `personTab = .meetings`.
- Drop the `⌘1–5` tab shortcuts entirely (no tabs). Optionally repurpose later as expand-all / collapse-all.
- Verify: build + run; N/L/T work without tabs; no `personTab` reference remains.
- Risk: **medium** — a `ScrollViewReader` around the canvas is needed to honor scroll-to; if skipped, N/T just focus fields (acceptable). The expand-before-focus for `N` is the real gotcha (§8.4).

### Phase F — Final sweep

**F1 · Empty-states + consistency pass.**
- Ensure every section that can be empty either self-hides (In common, Decisions, Reconnect, Photos — guard the whole `MSSection` with the existing `if`) or shows its existing empty-state line inside the expanded body (Tags, Relationships, Tasks, Encounters, Memories, etc.).
- Confirm `provenanceFooter` renders once at the bottom of the canvas, not inside a section.
- Verify: build + run with (a) a brand-new contact (mostly empty) and (b) a rich contact. No double headers, no orphaned buttons, no clipped rows at `minWidth:480`.
- Risk: **low**.

**F2 · Reduce-motion + accessibility.**
- `MSSection` toggles are already reduce-motion gated (`MSComponents.swift:263`); confirm no other added `.animation` ignores it (the old `value: personTab` animation is gone with `workArea`).
- Verify every icon-only button has an `.accessibilityLabel` (NotionIconButton supplies one from `help`; the `.plain`+`.minTap()` checkbox/done glyphs need an explicit one).
- Risk: **low**.

**F3 · Build verification + ask to push.**
- `swift build -c release` (CLAUDE.md). Then ask the user to commit/push per the repo workflow rule.

---

## 8. Edge cases & testing

1. **Editing identity inline.** `beginIdentityEdit()` (`:743-752`) populates 7 drafts; `saveIdentityEdit()` (`:754-767`) uses `setPrimary` (`:770-774`) to preserve `emails[1...]`. In the redesign the form renders full-width in the header. Test: edit name only → role/company/email preserved; the "Editing the first value — use ⋯ for all" hint (`:831-834`) still shows when arrays have >1 value. Save = Enter (`onSubmit`), Cancel = button.
2. **Inline tag add.** `commitTagEntry()` (`:1094-1106`) matches an existing tag case-insensitively else creates one. Test: typing an existing tag name attaches it (no dupe); the `MSInlineButton("Add")` appears only when `!newTagName.isEmpty` (`:1073`).
3. **Inline favorite add / remove.** `addFavorite()`/`removeFavorite()` (`:1141-1154`). Test: dedupe on add (`!u.favorites.contains`); chip `×` is now a 44pt-tap `NotionIconButton`.
4. **Inline memory add + `N` verb (the focus-into-collapsed-section gotcha).** `memoryFieldFocused` (`:257`) — pressing `N` (not in a field) focuses the memory field. Memories defaults **collapsed** (§4.2 #13). If the section is collapsed, the `TextField` isn't in the view tree and `memoryFieldFocused = true` silently no-ops. **Decision/required behavior:** the `N` verb must set `section.person.memories.expanded = true` (then `DispatchQueue.main.async { memoryFieldFocused = true }`) so the field exists before focus. Same pattern for `T`/Tasks (Tasks defaults expanded, so less risky).
5. **Message analysis (heavy/async).** Messages section defaults **collapsed** (#11) so opening a profile never auto-runs a scan. Test: Scan menu loads stats (`analyzeMessages` `:2674`); `Analyze…` popover (`analyzePopover :2444`) runs a preset; `analysisOutput` (`:2513`) renders inline with `MSInlineButton("Save to notes")` + a 44pt dismiss ×; Deep analysis (`runDeepMessageAnalysis :2833`) caches to Saved analyses (kind `deep-all`). Distress pre-flight guard (`:2761-2771`) still fires for intimate types.
6. **Narrow widths.** At `HSplitView` `minWidth:480` (canvas) the compactHeader Row 1 must keep Brief Me + ⋯ visible (name truncates, R1) and Row 2 must wrap (FlowLayout, R2). Test by dragging the split divider to the floor. The chat min is 300; total floor ~780.
7. **Reduce Motion.** `MSSection` expand/collapse honors `accessibilityReduceMotion` (`MSComponents.swift:263`). Test: with Reduce Motion on, sections snap (no animation); `MSSkeleton` shimmer off; the deleted `value: personTab` animation is gone.
8. **Collapse-state persistence.** `persistenceKey` writes `section.person.<key>.expanded` (`MSComponents.swift:262`). Test: collapse Tasks, relaunch → Tasks stays collapsed. Two different people share the *same* keys (intended — layout preference is global, not per-person), matching meeting-detail behavior.
9. **Self-hiding sections + counts.** Reconnect self-hides unless overdue/drifting (`:2084`); In common hides if empty (`:1947`); Decisions hides if empty (`:1419`); Photos only with photos (`:512`). Test that a hidden section contributes no empty `MSSection` shell (guard the `MSSection` itself with the same `if`, not just its body).
10. **Keyboard verbs while a field is focused.** Existing behavior (`:342-343`): keystrokes go to the focused field, not the hidden shortcut layer. Confirm typing "n"/"l"/"t" into the tag/task/memory fields inserts text rather than triggering verbs.
11. **AddRelationshipSheet disabled-state.** Save is `.disabled(selectedID == nil || label.isEmpty)` (`:3008`) — when restyled to `MSPrimaryButtonStyle`, confirm the disabled appearance still reads (dim). The relationships "Add" trigger is also `.disabled(people.people.count < 2)` (`:1892`) — preserve.
12. **`MSAvatar` size change (56 → 48).** `identityPanel` uses `MSAvatar(name:size:56)` (`:782`); the compact header uses 48 to keep Row 1 single-line. Test that initials still render legibly at 48 and that the avatar vertically centers against the 34pt Brief Me pill.
13. **Chat context lifecycle unchanged.** `updateChatContext()` (`:2700`) / `.onChange(of: current.id)` / `.onDisappear` (`:384`) are on `body`, not on the deleted panes — confirm they still fire after the canvas swap. The example prompts (`:1377-1382`) and `askAIAboutPerson()` (`:2715`) are unaffected; if "Ask AI" (§3 #9) is dropped, remove `askAIAboutPerson()` too (dead-code check).
14. **`.task` ordering.** The three `.task(id: current.id)` modifiers (`loadCalendarMeetings`, `computeInCommon`, `refreshIMessageSignal`, `:379-383`) feed the Meetings / In-common / Reconnect sections. They run regardless of collapse state, so a collapsed Meetings section still has fresh `count`. Test switching between two people rapidly — `inCommon` (`:312`) and `calendarMeetings` (`:275`) must re-resolve per id.

### 8.5 `@State` disposition through the migration

Every state property from §1.7, and what happens to it:

| Property | Disposition | Where it lives after redesign |
|----------|-------------|-------------------------------|
| `showEdit` | keep | Header overflow "Edit all fields…" → `AddPersonSheet`. |
| `showBrief` | keep | Header Primary "Brief Me". |
| `editingIdentity` + 7 drafts | keep | Header inline edit form (full-width). |
| `showAddEncounter` | keep | Overflow + Encounters `trailing` + `L` verb + health popover. |
| `showHealthWhy` | keep | `healthBadge` capsule in header Row 2. |
| `showAddRelationship` | keep | Overflow + Relationships `trailing`. |
| `confirmDelete` | keep | Overflow "Delete" (destructive). |
| `newMemory` / `memoryFieldFocused` | keep | Memories section; `N` verb expands-then-focuses (§8.4). |
| `newTalkingPoint` | keep | Discuss-next-time section. |
| `showEvidence` | keep | Perf-review-evidence section. |
| reconnect quartet | keep | Reconnect section. |
| `newTaskTitle` (+ new `taskFieldFocused`) | keep / **add** | Tasks section; `T` verb focuses. |
| `newFavorite` | keep | (Favorites — see note) Favorites section. |
| `newTagName` | keep | Tags section. |
| AI-suggestions quartet | keep | AI-suggestions section. |
| `deepRunning` | keep | Messages → deep analysis. |
| `calendarMeetings` | keep | Meetings section. |
| message quartet | keep | Messages section. |
| analysis quartet | keep | Messages → Analyze popover. |
| **`personTab`** | **DELETE** | Tabs removed (D2). |
| `showAddEmail` / `newEmailDraft` | keep | Contact section add-email popover. |
| `showAddToMeeting` | keep | Overflow + Meetings `trailing`. |
| `showAnalyzePopover` / `analyzePreset` / `analyzeRange` | keep | Messages → Analyze popover. |
| `noteExpansion` | keep | Saved-analyses section. |
| `inCommon` | keep | In-common section. |

> **Favorites note:** today `favoritesEditSection` (`:1110`) lives in the
> Overview tab but is **absent from the §4.2 table**. Decision: add it as a
> collapsed section between Tags(#4) and Contact(#5) — `persistenceKey:"person.favorites"`,
> `count: current.favorites.count`, `defaultExpanded:false`. It's a natural pair
> with Tags. (Catalogued here so the migration doesn't silently drop it.)

---

## 9. Code-sketch appendix (non-binding, illustrative)

These sketches show the *shape* of the converted code; exact tokens come from the
tables above. They are not literal diffs.

### 9.1 `body` after Phase C/D

```swift
var body: some View {
    HSplitView {
        personCanvas
            .frame(minWidth: 480, idealWidth: 720)
            .background(NDS.bg)
            .background(keyboardVerbs)          // N / L / T (⌘1–5 dropped)
        personChatColumn
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { updateChatContext() }
    .onChange(of: current.id) { _, _ in updateChatContext() }
    .task(id: current.id) { await loadCalendarMeetings() }
    .task(id: current.id) { computeInCommon() }
    .task(id: current.id) { people.refreshIMessageSignal(forPersonID: current.id) }
    .onDisappear { chatSession.setContext("The People tab — the user's second-brain contacts.") }
    // …all existing .sheet / .confirmationDialog modifiers unchanged…
}
```

### 9.2 `personCanvas`

```swift
private var personCanvas: some View {
    ScrollViewReader { proxy in            // for N/T scroll-to (optional)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                compactHeader
                if relationshipInsight != nil { proactiveInsightCard }   // Insight (#2)

                MSSection("Tasks", systemImage: "checklist",
                          count: personTasks.filter { $0.status != .completed }.count,
                          persistenceKey: "person.tasks", defaultExpanded: true) {
                    tasksBody                                            // quick-add + commitmentLedger
                }
                .id("person.tasks")

                MSSection("Tags", systemImage: "tag",
                          count: tags.count, persistenceKey: "person.tags") {
                    tagsBody
                }
                // … sections #4–#18 per §4.2, in order …

                provenanceFooter
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}
```

### 9.3 A section with a `trailing` add accessory (Relationships)

```swift
MSSection("Relationships", systemImage: "person.2",
          count: current.relationships.count,
          persistenceKey: "person.relationships",
          trailing: {
              MSInlineButton("Add", systemImage: "plus") { showAddRelationship = true }
                  .disabled(people.people.count < 2)        // preserve :1892 guard
          }) {
    relationshipsBody                                       // rows + weeklyRelationshipPrompt
}
```

### 9.4 A self-hiding section (Decisions)

```swift
@ViewBuilder private var decisionsSectionWrapped: some View {
    let mine = decisions.decisions
        .filter { current.meetingMentions.contains($0.meetingID) }
        .sorted { $0.date > $1.date }.prefix(8)
    if !mine.isEmpty {
        MSSection("Decisions", systemImage: "checkmark.seal",
                  count: mine.count, persistenceKey: "person.decisions",
                  defaultExpanded: false) {
            ForEach(Array(mine)) { d in decisionRow(d) }
        }
    }
}
```

### 9.5 `keyboardVerbs` after Phase E

```swift
@ViewBuilder private var keyboardVerbs: some View {
    Group {
        Button("") {
            UserDefaults.standard.set(true, forKey: "section.person.memories.expanded")
            DispatchQueue.main.async { memoryFieldFocused = true }
        }.keyboardShortcut("n", modifiers: [])
        Button("") { showAddEncounter = true }.keyboardShortcut("l", modifiers: [])
        Button("") {
            // Tasks defaults expanded; just focus the quick-add field.
            DispatchQueue.main.async { taskFieldFocused = true }
        }.keyboardShortcut("t", modifiers: [])
        // ⌘1–5 tab shortcuts removed — no tabs.
    }
    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
}
```

### 9.6 Compact-header overflow trigger chrome

The ⋯ `Menu` label should read as a 30pt icon button with a 44pt tap. Since
`NotionIconButton` is a `Button` (not a `Menu` label), use its visual treatment
inline on the menu label:

```swift
Menu { /* items per §4.1 */ } label: {
    Image(systemName: "ellipsis")
        .scaledFont(13).foregroundStyle(NDS.textSecondary)
        .frame(width: NDS.buttonIconSide, height: NDS.buttonIconSide)   // 30pt
}
.menuStyle(.borderlessButton)
.minTap()                                                                // 44pt hit area
.help("More actions")
.accessibilityLabel("More actions")
```

---

## 10. Net effect summary

- **Columns: 3 → 2** (canvas + chat). Kills P1-A.
- **Identity rail (300pt, 7 sections): deleted.** Content redistributed onto the full-width canvas as collapsible sections. Kills P1-B.
- **Header buttons: 7 controls (mixed 34/30/borderless) → 1 Primary + 1 overflow ⋯ + a FlowLayout metadata row.** Kills P1-C/D/E.
- **Tabs: `MSPillTabs`(4) + `PersonTab` + `personTab` deleted.** Replaced by 18 user-controlled `MSSection`s (10 expanded by default). Kills P1-G.
- **Tasks: promoted from "buried under Meetings" to top-level expanded with an open-count badge.** Fixes the §1.5 siloing.
- **Every button: normalized to the §3 role table** (Primary 34 / Secondary 30 / Tertiary 28 / Icon 30+44 / Danger 34 / Menu-chrome 30). Kills P1-F, P2-J, P3-K.
- **Fit preserved** by widening the constraint and keeping all multi-control rows in `FlowLayout` (§5).
