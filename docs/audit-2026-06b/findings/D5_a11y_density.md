# Design — Accessibility, Readability & Density as Premium Quality
> Premium apps are legible at any text size, operable by any input, and confident enough to show less — MeetingScribe's design system has the right bones but its surfaces are dense, its helpers unadopted, and one contrast failure is codified in a test.

## Full-app audit (through my lens)

### Strong (real foundations, better than most indie macOS apps)
- **WCAG math lives in the design system** — `NDS.relativeLuminance/contrastRatio/composite` (`Sources/MeetingScribe/UI/NotionDesign.swift:288-307`) and a CI-run contrast test (`Tests/MeetingScribeTests/DesignContrastTests.swift`). Almost nobody ships this.
- **Dynamic-Type-aware custom fonts** — `scaledFont()` backed by `@ScaledMetric` (`NotionDesign.swift:329-352`) and `NDS.font(relativeTo:)` (`:145-149`). Widely adopted (~hundreds of call sites).
- **`NotionIconButton` auto-derives its VoiceOver label from `.help`** (`NotionDesign.swift:436-441`) — the correct template.
- **Semantic status/priority colors paired with glyphs** (`NDS.priority/priorityGlyph/status`, `NotionDesign.swift:247-270`) — colorblind-safe by construction *where used*.
- **Health badge a11y done right** — `accessibilityElement(children: .ignore)` + a sentence-form label (`People/PersonDetailView.swift:761-762`).
- **Zero `minimumScaleFactor` in the codebase** — good instinct; text is never silently shrunk to fit.

### Weak / failing

**1. The 44pt tap-target helper has ZERO adopters.** `.minTap()` is defined (`NotionDesign.swift:548-553`) and advertised in a comment (`:29`) but a repo-wide grep finds **no call sites**. Meanwhile: task status menu is a 22pt-wide hit area (`UI/TaskRowView.swift:193-199`), the row overflow menu 28pt (`:172-176`), Stay-connected's "open person" arrow is a bare caption-size glyph (`UI/StayConnectedSection.swift:105-113`), the relationship-type chevron is 9pt (`PersonDetailView.swift:794`), and the source-picker menu target is the text itself (`UI/MeetingDetailHeader.swift:427-443`).

**2. Reduce Motion gating is ~20% complete and the design system itself violates it.** 51 `withAnimation`/`.animation(` sites across 26 files; `NDS.motion()` is called from only 5 files (11 sites). Worse, the NDS components hard-code ungated animation: `QuickActionCard` (`NotionDesign.swift:601`), `QuickPill` (`:649`), and all four `MS*ButtonStyle` springs (`:460,496,514,530`). Gating call sites while the kit itself animates is unwinnable.

**3. A contrast failure is locked in by the test.** `textTertiary` dark = 0.44 alpha (`NotionDesign.swift:83`) ≈ **3.9:1** composited over `bg` — and `DesignContrastTests.swift:44-49` only asserts **3:1**, justified as "used for larger captions." In reality `textTertiary` is overwhelmingly applied at **11pt** (`NDS.tiny`, `font(.caption2)`): meeting meta on Today rows (`UI/TodayView.swift:236-238, 289-291`), note snippets (`:345`), chip counts (`NotionDesign.swift:410`). 11pt regular is not WCAG large text; the floor should be 4.5:1. The regression guard guards the regression.

**4. Fixed-size sheets: the plan says 5; I count 11+.** `OnboardingSheet` 480×480 (`UI/OnboardingSheet.swift:48`), `GlobalSearchView` 620×480 (`UI/GlobalSearchView.swift:59`), `TaskInsightsView` 520×560 (`:34`), `TaskTrashView` 460×440, `TagManagementSheet` 440×480, `AddPersonSheet` 460×540, `ContactsImportView` 480×560, `PeopleListView` sheet 460×520 (`:668`), three PersonDetailView sheets 420×460/420×420/480w (`PersonDetailView.swift:414, 2340, 2399, 1902`), and the Settings *window* itself 560×580 (`MeetingScribeApp.swift:145`). At one Dynamic Type step up, footers clip (OnboardingSheet's `Spacer` + `.bar` footer at `:105-117` eats body text first).

**5. VoiceOver coverage is a patchwork, and rows aren't keyboard-operable.** 43 `accessibilityLabel`s across 21 files — against ~90 view files and 230+ icon buttons. Zero `.accessibilityHeading` anywhere (VoiceOver users cannot skim section structure). Composite rows activate via `onTapGesture` (12 sites, e.g. `TaskRowView.swift:180`) — no focus, no Space/Return activation, no combined element. The task status button (`TaskRowView.swift:193`) exposes neither label nor current value.

**6. Color-only meaning survives in the highest-traffic spots.** The 5×5pt green dot meaning "already in People" on `AttendeeChip` (`MeetingDetailHeader.swift:813-815`); meeting-health dots in the list, five colors × 7pt, no glyph or label (`UI/MeetingsView.swift:529-541`); recording `healthDot` green/yellow/red circles (`MeetingDetailHeader.swift:729-739`).

**7. Density: the app is afraid of whitespace.** This is the "expensive" gap:
- **Today is a 15-section wall** (`UI/TodayView.swift:52-100`): header, quick actions, up-next, live, needs-attention, today, action items, follow-ups, commitments, decisions, on-this-day, recent notes, suggested people, stay connected, reconnect — all stacked, all using the identical `fieldBg`/radius-8 row treatment, every day, regardless of relevance. Things 3 shows *one* list; Notion Calendar shows *today*. Nothing here is allowed to matter.
- **Meeting detail header stacks up to 8 rows before content** (`UI/MeetingDetailHeader.swift:8-98`): title/meta/chips + attendees + conference URL + source picker + tags + action row + banner. The source picker and tags are persistent edit-chrome for things users set once.
- **PersonDetailView identity pane is a fixed 300pt column** (`PersonDetailView.swift:436`) holding ~8 stacked control rows (name block, edit/⋯/trash row, Encounter/Relationship/Ask-AI row, type picker, health badge, tags, contact, relationships, encounters, photos) — `.frame(width: 300)` cannot reflow for Dynamic Type, and `minWidth: 560` + chat `minWidth: 320` (`:324-328`) makes ~1180pt the real minimum window.
- **Settings is 24 `Section`s in one unsectioned Form** inside a fixed 560×580 window (`UI/SettingsView.swift:76-580`, `MeetingScribeApp.swift:145`) — MCP config JSON, Whisper flags, and "You" name fields share one infinite scroll. This single screen reads cheaper than anything else in the app.

**8. Token drift undermines the token system.** Raw `.secondary/.tertiary/.quaternary` and system fonts coexist with NDS tokens on the same screens (`TodayView.swift:200, 371`, all of `OnboardingSheet.swift`), and fractional ad-hoc sizes (11.5, 13.5) leak around the 6-token type scale (`NotionDesign.swift:369`, `PersonDetailView.swift:1192, 1651`).

## Existing-plan items I rank highest
1. **Dynamic Type round 2 (2H)** — right idea, undersized: it names 5 fixed sheets; there are 11+ (see D5-4 for the systemic fix).
2. **Icon-button `accessibilityLabel` + `.help` sweep (GROUP-DESIGN rec 2)** — `NotionIconButton` already proves the pattern; this is mechanical and WCAG-blocking.
3. **Color-dot glyph+label pairing (rec 3)** — `MeetingsView:529-541` is verified-current; `NDS.priorityGlyph` shows the house style.
4. **Gate all motion through `NDS.motion()` (1F)** — endorse, but it must include the design-system components themselves (D5-8).
5. **`PersonDetailView` decomposition (2G)** — prerequisite for any identity-pane density redesign (D5-7); don't restyle a 2,300-LOC file.
6. **Loading skeleton tri-state (1F)** — honest loading states are a readability feature; keep it reduce-motion aware.

## NET-NEW recommendations

### D5-1 — Today, calm by default: 15 sections → 4 modules + a "More" shelf
- **What/why:** `TodayView.feed` (`TodayView.swift:52-100`) stacks 15 sections with identical visual weight. Redesign to a fixed editorial hierarchy: (1) **Now/Next** (live recording or up-next card), (2) **Today's meetings**, (3) **Needs attention** (merge needs-attention + commitments + follow-ups into ONE triage module with at most 5 rows and per-row kind glyphs), (4) **People** (merge stay-connected + reconnect + suggested-people into one strip). Decisions, on-this-day, and recent notes move to a collapsed "From your vault" shelf that remembers its disclosure state per-section (`@AppStorage`). Empty modules render nothing — most days Today should be ~half whitespace.
- **User value:** The home screen stops being a backlog and becomes a judgment. This is the single biggest "expensive vs. cheap" lever in the app — Things 3 and Notion Calendar win on what they *don't* show.
- **Effort:** M
- **Impact:** High
- **Depends on:** none (pure recomposition of existing section views)

### D5-2 — Fix the tertiary-text contrast token and harden the test that protects it
- **What/why:** Raise `textTertiary` dark alpha 0.44 → 0.56 (≈5.0:1 over `bg`; still clearly de-emphasized next to 0.68 secondary) and light 0.50 → 0.58. Then fix `DesignContrastTests.testTertiaryTextClearsLargeTextAA` (`DesignContrastTests.swift:44-49`) to assert **4.5:1**, because tertiary is used at 11pt (not WCAG large text) throughout (`TodayView.swift:236-238`, `NotionDesign.swift:410`). Add one more test: tertiary composited over `fieldBg` (#1e1925, `NotionDesign.swift:85`) ≥ 4.5:1 — most tertiary text actually sits on card fills, which are lighter than `bg`.
- **User value:** Every timestamp, snippet, and meta line in the app becomes readable for low-vision users and everyone on a dim/glossy display; the regression guard becomes a real guard.
- **Effort:** S
- **Impact:** High
- **Depends on:** none

### D5-3 — Adopt `.minTap()` everywhere + a design-lint rule so it can't drift to zero again
- **What/why:** The 44pt helper (`NotionDesign.swift:548-553`) has zero call sites. Sweep it onto every icon-only control: `TaskRowView` status (22pt, `:199`) and overflow (28pt, `:176`), `StayConnectedSection` arrow (`:105-113`), relationship-type and source-picker menus, MarkdownEditor toolbar (26×22, `MarkdownEditor.swift:830`). The repo already runs a design-lint in CI (per HELD-ITEMS) — add a rule: any `Button`/`Menu` whose label is a bare `Image(systemName:)` with a frame < 28pt must carry `.minTap()` or be a `NotionIconButton`.
- **User value:** Misses and mis-taps disappear for trackpad, motor-impaired, and large-cursor users; the fix is self-enforcing.
- **Effort:** M (sweep) + S (lint)
- **Impact:** High
- **Depends on:** none

### D5-4 — `MSSheet`: one adaptive sheet container replacing 11+ hard-coded frames
- **What/why:** Go beyond the planned "5 fixed sheets" item: build a single `MSSheet { header; content; footer }` component that supplies `frame(minWidth:idealWidth:maxWidth:)` + `maxHeight` from the screen, wraps content in a `ScrollView` so footers never clip at large text, applies NDS background/typography (killing OnboardingSheet's raw-system-font drift), pins the footer, sets initial `@FocusState`, and adds `.accessibilityAddTraits(.isHeader)` on the title. Migrate all 11+ sheets (list in audit §4) onto it.
- **User value:** One component makes every modal Dynamic-Type-safe, visually consistent, and keyboard-predictable — instead of 11 hand-tuned rectangles re-clipping after every copy change.
- **Effort:** M
- **Impact:** High
- **Depends on:** none (supersedes/implements 2H's sheet item)

### D5-5 — Semantic rows: Button-ify `onTapGesture` rows, combined a11y elements, heading rotor
- **What/why:** (a) Replace the 12 `onTapGesture` row activations (e.g. `TaskRowView.swift:180`) with real `Button`s so rows get focus, Space/Return, and the button trait. (b) On task rows add `.accessibilityElement(children: .combine)` + `accessibilityValue("\(status), \(priority), due \(date)")` + `accessibilityAction`s for Complete / Change due — one swipe reads the row, one action completes it. (c) Add `.accessibilityHeading(.h2)` inside `NotionEyebrow` (`NotionDesign.swift:402-413`) and the section-header HStacks in TodayView — a single-component change that gives VoiceOver users a heading rotor over the entire app.
- **User value:** VoiceOver navigation goes from "tab through 60 fragments" to "skim 6 headings, act on rows" — the difference between technically-labeled and actually usable.
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### D5-6 — Settings: 24-section scroll → tabbed, resizable, plain-language
- **What/why:** `SettingsView` is one Form with 24 `Section`s (About → Sparkle → You → Storage → Capture → Calendar → MCP JSON → Notion → Linear → Drive → Whisper.cpp → Diagnostics → Ollama → Obsidian…) in a fixed 560×580 window (`SettingsView.swift:76-580`, `MeetingScribeApp.swift:145`). Restructure into native `TabView` settings — **General · Capture · AI Models · Integrations · People · Privacy & Data** — make the window resizable, and put one plain-language sentence under each tab title. Whisper/Ollama flags and MCP JSON live under disclosure groups inside AI Models/Integrations.
- **User value:** Settings is where "local-first, you're in control" must feel credible; today it reads like a dotfile. Premium benchmark: Things 3 / CleanShot X settings.
- **Effort:** M
- **Impact:** Med-High
- **Depends on:** pairs well with planned provable-privacy panel (1D) as the Privacy tab

### D5-7 — Identity pane: adaptive width + 3-zone calm layout
- **What/why:** Replace `identityPane.frame(width: 300)` (`PersonDetailView.swift:436`) with `minWidth: 280, idealWidth: 320, maxWidth: 380` scaled via `@ScaledMetric` so Dynamic Type reflows instead of wrapping into a 300pt chute. Restructure the panel's ~8 stacked control rows (`:595-714`) into three zones: **Hero** (avatar, name, type emoji-chip, health badge — one visual unit), **One action row** (Log encounter primary + ⋯ menu absorbing Edit/Relationship/Ask-AI/Delete), **Facts** (tags/contact/relationships, each behind quiet disclosure). Edit and Delete demote to hover-reveal/menu — destructive chrome should not be permanently visible on a profile.
- **User value:** The person page reads as a profile, not a form; the most important relationship signal (health) stops competing with a trash can.
- **Effort:** M
- **Impact:** High
- **Depends on:** sequenced with planned PersonDetailView decomposition (2G)

### D5-8 — Reduce-motion-proof the design system itself + motion lint
- **What/why:** The planned motion sweep gates *call sites*; it misses that `QuickActionCard` (`NotionDesign.swift:601`), `QuickPill` (`:649`), and all `MS*ButtonStyle` springs (`:460,496,514,530`) animate unconditionally. Give NDS components an internal `@Environment(\.accessibilityReduceMotion)` read, and extend the CI design-lint to flag any bare `withAnimation(`/`.animation(` outside `NotionDesign.swift` that doesn't pass through `NDS.motion(` — same self-enforcing pattern as D5-3.
- **User value:** Reduce Motion actually means it, app-wide, permanently — including every future button press.
- **Effort:** S
- **Impact:** Med
- **Depends on:** extends planned 1F motion item

### D5-9 — Meeting header: 8 rows → 3 (hover-reveal the edit chrome)
- **What/why:** `UnifiedMeetingDetail.header` stacks title/meta/chips + attendees + conference URL + source picker + tags + action row + banner (`MeetingDetailHeader.swift:8-98`). Collapse to: (1) title + one meta line (time · health · recurring · calendar chips inline), (2) attendees row, (3) context row where source, tags, and the conference link render as quiet inline text-chips that become editable on hover/click — Linear's issue-header pattern. The source picker (`:401-446`) is a set-once control and must not cost a permanent row.
- **User value:** The summary — the actual product — moves one full screen-row group higher; the header reads composed instead of accreted.
- **Effort:** M
- **Impact:** Med-High
- **Depends on:** none

### D5-10 — AttendeeChip: legible "in People" state + real target
- **What/why:** Replace the color-only 5×5pt green dot (`MeetingDetailHeader.swift:813-815`) with a small `checkmark.circle.fill` badge on the avatar circle, add `accessibilityLabel("\(fullName), in your People")` / `("\(fullName), not yet in People — click to connect")` on the chip button, and `.minTap()` the chip. The chip is the single most important people-integration affordance in the app; its state is currently invisible to colorblind users, VoiceOver, and anyone over 40.
- **User value:** The meeting↔people bridge (pillar 3) becomes perceivable by everyone.
- **Effort:** S
- **Impact:** Med-High
- **Depends on:** complements planned attendee hover-card (2A)

### D5-11 — Type-scale discipline: kill fractional ad-hoc sizes
- **What/why:** The 6-token scale (30/25/14/12/11) is undermined by scattered `scaledFont(13.5…)`, `(11.5…)`, `(13…)` literals (`PersonDetailView.swift:1192,1651`, `NotionChip` 11.5 at `NotionDesign.swift:369`, dozens more). Add two tokens (`bodyStrong` 13.5→13, `chip` 11.5→11.5 *as a token*), sweep literals to tokens, and lint `scaledFont(` calls with numeric literals outside NotionDesign.swift.
- **User value:** Optical consistency is most of what "expensive" means in typography; it also makes any future scale retune a one-file change.
- **Effort:** S
- **Impact:** Med
- **Depends on:** none

## Top 3 picks
1. **D5-1 — Today, calm by default** (15 sections → 4 modules): the largest single premium-feel and usability win in the app.
2. **D5-2 — Tertiary contrast token + test hardening**: a real WCAG failure currently *enforced* by the test suite; smallest fix, app-wide reach.
3. **D5-4 — `MSSheet` adaptive container**: one component retires 11+ Dynamic-Type cliffs and unifies modal quality forever.

**Single highest-priority recommendation overall: D5-1.** Today is the first screen every day; until it stops shouting fifteen things at once, no amount of token polish will make MeetingScribe feel expensive.
