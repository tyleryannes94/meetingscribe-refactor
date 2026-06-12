# Design — Component Consistency & State Polish
> Premium apps design every state — empty, loading, error, and "nothing selected" — and render the same concept identically everywhere; MeetingScribe has the primitives (MSEmptyState, MSSkeleton, NDS tokens) but adoption is ~40%, so the app reads as five apps stitched together.

## Full-app audit (through my lens)

### Strong (genuinely premium foundations — protect these)
- **The primitives exist and are good.** `MSEmptyState` (`Sources/MeetingScribe/UI/MSComponents.swift:213`), `MSSkeleton` with reduce-motion-aware shimmer (`MSComponents.swift:187`), `MSSearchField` (`:158`), `MSAvatar`/`MSAvatarStack` (`UI/MSAvatar.swift:9,49`), `msCard()` (`MSComponents.swift:13`). `TaskOwnerAvatar` is already correctly a thin wrapper over `MSAvatar` (`UI/TaskOwnerAvatar.swift:11`) — proof the codebase knows how to consolidate.
- **PeopleListView's frame-0 snapshot is the best loading state in the app** — `SnapshotPersonRow` renders a real-looking list synchronously while the store hydrates (`People/PeopleListView.swift:36,250-261,541-565`). This is Linear-grade cold-start polish. Nothing else in the app does it.
- **People's "no selection" pane is content, not dead space** — `PeopleInsightsView` dashboard when nobody is selected (`PeopleListView.swift:509-513`). The premium pattern, implemented once.
- **`MeetingSummaryTab`/`MeetingTranscriptTab` correctly distinguish loading from empty** (`UI/MeetingSummaryTab.swift:100,131`, `UI/MeetingTranscriptTab.swift:37` — "loading, not empty (PP-1)").

### Weak: empty states — one component, eight bespoke clones
`MSEmptyState` is used in ~8 places, but at least 9 panes still hand-roll their own stack with drifting specs:
- `TodayView.swift:545-560` — bespoke (icon 36, spacing 10, `UntitledSecondaryButtonStyle` CTA).
- `ActionItemsChrome.swift:520-544` — bespoke (icon 40, spacing 12, raw `.borderedProminent` CTA — system blue inside a coral-accent app).
- `MeetingsView.swift:207-223` (`meetingEmptyDetail`) — bespoke (icon 48, `.title2`), and it dead-ends ("Select a meeting") while People shows a dashboard.
- Also bespoke: `PreMeetingBriefView.swift:142-148`, `TaskTrashView.swift:47`, `ChatSidebar.swift:129`, `TranscriptSyncView.swift:239`, `DuplicateReviewSheet` (`PeopleListView.swift:651-656`), `GlobalSearchView.swift:123-127`, plus bare-text empties like `TagManagementSheet.swift:26` ("No tags yet." floating in a void) and `ActionItemsSidebar.swift:94,115,458`.
- **Copy-paste icon bug:** the Meetings list empty state uses `person.2` (`MeetingsView.swift:192`) — the *People* glyph — for "No meetings yet". Same glyph as `PeopleListView.swift:496`. An empty Meetings tab literally shows the People icon.
- No empty state distinguishes "truly empty" from "filtered to empty" except Meetings (`search.isEmpty ? "No meetings yet" : "No matches"`, `MeetingsView.swift:193`); People, Tasks, and the sidebar show the same copy whether you have zero items or an over-narrow filter.

### Weak: loading — skeleton standard exists, spinners everywhere
~35 `ProgressView()` call sites; `MSSkeleton` is adopted in exactly 2 files (summary/transcript tabs). Centered bare spinners with no label: `DuplicateReviewSheet` (`PeopleListView.swift:650`), `People/iPhone/ContactsImportView.swift:80`, `PersonDetailView.swift:924,1718,1768,2158`. The premium pattern (structure-shaped placeholder) ships in the design system and then isn't used where lists load.

### Missing entirely: a designed error state
There is no `MSErrorState`. Failures render as empty states with apologetic prose: "Ollama wasn't running when this meeting finished, or summarization failed" (`MeetingSummaryTab.swift:175`) — engine jargon, no diagnosis, no one-click fix (HealthCheckSheet exists one menu away and isn't linked). "No Linear projects found. Check your key in Settings → Integrations" (`ActionItemsProjectPage.swift:265`) is a body-text error. Grep for `Text("Failed`/`Couldn't`/`Error` in UI: zero matches — the app literally has no error vocabulary.

### Weak: the same task renders 4 different ways in one tab
- **Board card** (`ActionItemsBoardView.swift:112-174`): `MSPriorityBadge` + `DueChip` + priority accent bar, `NDS.rowRadius`(12), `NDS.hairline` border, title `.caption`.
- **Gallery card** (`ActionItemsGalleryView.swift:20-59`): hand-rolled priority capsule (`:38-42`) and due text (`:43-45`) instead of `MSPriorityBadge`/`DueChip`, hardcoded radius 10 (`:54`), `NDS.divider` border (`:55`), title `.callout`, avatar 18 vs board's 16, no context menu, no meeting attribution.
- **Table row** (`ActionItemsTableView.swift:72-127`): raw `.green/.orange/.blue` status colors (`:78-79`) while the board uses `NDS.status()` (`ActionItemsBoardView.swift:35`); **header/cell misalignment bug** — Priority/Due headers framed 80pt (`:46-47`) but cells framed 96pt (`:107,:120`), so every column after Priority is shifted 32pt off its header.
- **List row** delegates to the full `ActionItemRow` (`ActionItemsListView.swift:402-451`). Meanwhile Today has two *more* mini task-row renderings (`NeedsAttentionWidget.swift:60-88`, `ActionItemsWidget.swift:98+`) with their own checkbox/color/typography choices.

### Weak: duplicated near-identical components
- **Two "drifting people" sections on the same Today page**: `StayConnectedSection` (health-formula-ordered, band-colored cards, 36pt `MSAvatar`, `MSPrimaryButtonStyle` "Log" → QuickEncounterSheet; `UI/StayConnectedSection.swift:62-119`) and `ReconnectView` (median-gap heuristic, generic `person.circle` glyph at `People/SuggestedPeopleView.swift:135`, tiny borderless "Yes / Not yet" that bumps `lastInteractionAt` without logging an encounter; `SuggestedPeopleView.swift:84-181`). Same person can appear in both, with different "overdue" math and different copy ("3 days overdue" vs "Last talked 12 days ago"). This is the single most visible "two teams built this" artifact.
- **Three filter-chip systems**: Meetings scope pills (borderless, brand 0.12 fill; `MeetingsView.swift:136-147`), People `FilterChip` (hairline border, fieldBg, brand 0.18; `PeopleListView.swift:608-625`), GlobalSearch filter bar (`GlobalSearchView.swift:72+`), plus `MSPillTabs` for detail tabs.
- **Two search fields**: `MSSearchField` in People (`PeopleListView.swift:238`) vs a hand-rolled clone in Meetings (`MeetingsView.swift:105-123`) — different clear-button behavior (MSSearchField has Esc-to-clear; Meetings doesn't).
- **Three button systems live simultaneously**: `MS*` (coral gradient, the standard), legacy `Untitled*` (still live: `TodayView.swift:556`, `ActionItemsChrome.swift:372`), and ~25 raw `.borderedProminent` sites (system accent blue): `MeetingCard.swift:188,238,251`, `MeetingSummaryTab.swift:197,213`, `QuickEncounterSheet.swift:194`, `OnboardingSheet.swift:114,182,191`, `HealthCheckSheet.swift:49`, `MeetingsView.swift:202`, etc. The *first-run* onboarding and the *empty-state CTAs* — the highest-stakes impression surfaces — are mostly the off-brand system style.

### Weak: density, alignment & token drift
- 103 hardcoded `RoundedRectangle(cornerRadius: N)` across 40 files against a 3-token system (`NDS.radius`=14, `rowRadius`=12, `cardRadius`=20; `NotionDesign.swift:24-26`). Today widgets sit at 14 (`NeedsAttentionWidget.swift:54`, `ActionItemsWidget.swift:46`), Today row chips at 8 (`TodayView.swift:151,204,243,299`), gallery at 10, Suggested people at 10 — four radii on one scroll page.
- Pane-title drift: Meetings uses `NDS.title` (`MeetingsView.swift:96`); People uses `.title2.bold()` (`PeopleListView.swift:209`).
- Today section-header drift on a single page: `scaledFont(15,.bold)` ("Stay connected"), `scaledFont(15,.semibold)` ("Follow-ups to send", `TodayView.swift:129`), `.headline` ("Needs attention", "Action items"), `NDS.sectionLabel` ("Suggested people", "Stay in touch"), uppercase tracked `sectionLabel()` ("TODAY", `TodayView.swift:574-579`).
- Raw semantic colors bypassing tokens: `MeetingListRow` status dots `.green/.orange/.red/.yellow` (`MeetingsView.swift:532-535`), `NeedsAttentionWidget` orange/red (`:54-56,80`), `HealthCheckSheet.swift:35`.
- `QuickEncounterSheet` chips: raw `.white` text, `Color.secondary.opacity(0.12)` fills, radii 10/8, raw `withAnimation(.easeInOut...)` not gated through `NDS.motion()` (`QuickEncounterSheet.swift:124,238-249,262-277`).

### Weak: sheet anatomy — five sheets, four header patterns
- `NewMeetingSheet`: display title 20 heavy, actions bottom-trailing, `MSPrimaryButtonStyle` (`NewMeetingSheet.swift:22,63-70`).
- `AddPersonSheet`: `.headline` title, Cancel/Save top-right (`AddPersonSheet.swift:50-60`).
- `TagManagementSheet`: 18 bold, lone "Done" top-right (`TagManagementSheet.swift:18-23`).
- `QuickEncounterSheet`: `.headline` + `xmark.circle.fill` icon close, `.borderedProminent` save (`QuickEncounterSheet.swift:93-107,194`).
- `HealthCheckSheet`: 20 bold, Re-run/Done bottom row, `.borderedProminent` (`HealthCheckSheet.swift:25,45-50`).
Widths/heights are five unrelated fixed frames (440 / 460×540 / 440×480 / 470 / 360–480).

### Weak: copy voice
- **The app can't decide what a task is called.** Tab/empty states say "action items" (`ActionItemsChrome.swift:524`, `ActionItemsWidget.swift:60`); every creation affordance says "New task" (`ActionItemsChrome.swift:514,531`, board `:44`); the sidebar says "pages" and "projects" (`ActionItemsSidebar.swift:94,458`). Three nouns, one entity.
- Capitalization drift: "Add Person" (`PeopleListView.swift:163`) vs "Add tag" / "Add a task"; "New Person" (`AddPersonSheet.swift:52`) vs "New meeting" (`NewMeetingSheet.swift:22`).
- Tone lurches from warm ("No tags yet. Use Add tag to group this person (clients, family, an event…)", `PersonDetailView.swift:830`) to plumbing-speak ("Re-extract from meetings", `ActionItemsChrome.swift:537`; "Ollama wasn't running…", `MeetingSummaryTab.swift:175`) — sometimes within one pane.

## Existing-plan items I rank highest
1. **1F Loading skeleton tri-state (`LoadState` + `.redacted`)** — the only plan item squarely in my lens; partially shipped (summary/transcript tabs), must be generalized to every async pane.
2. **1F Button consolidation (retire `Untitled*`, adopt `MS*` + 44pt)** — verified still unfinished (`TodayView.swift:556`, `ActionItemsChrome.swift:372`, ~25 `.borderedProminent` leaks); single cheapest "expensive-feeling" win.
3. **1E honest empty/status copy + de-jargon (held per HELD-ITEMS #6)** — my D4-8 voice guide is the missing decision artifact that unblocks this hold.
4. **2A `ActionItemsViewModel` resurrection** — consolidating the 12 `@State`s is the prerequisite for one task-row component rendering consistently across the four view modes.
5. **2H Dynamic Type round 2 (adaptive frames on fixed-size sheets)** — all five audited sheets are hard-framed; pairs with my D4-5 sheet scaffold.
6. **2B warm copy + photo hero avatars** — extends the already-shared `MSAvatar` instead of forking it; keep it that way.

## NET-NEW recommendations

### D4-1 — `MSErrorState` + error vocabulary (the missing fourth state)
- **What/why:** The app has empty and (partial) loading states but zero designed error states — failures masquerade as empties with jargon prose (`MeetingSummaryTab.swift:168-204`, `ActionItemsProjectPage.swift:265`). Ship `MSErrorState(icon:title:diagnosis:fixAction:)` in MSComponents: amber/danger-tinted card, plain-language diagnosis, and a *fix-it* button that deep-links to the cure (Ollama down → "Start local AI" / open HealthCheckSheet; Linear key bad → open Integrations). Adopt at the ~6 known failure surfaces. The plan's tri-state covers loading-vs-empty; nobody owns *failed*.
- **User value:** Failures become 1-click recoverable instead of dead ends; "expensive" apps never shrug.
- **Effort:** M · **Impact:** High · **Depends on:** none

### D4-2 — Empty-state system v2: one visual signature + filtered-empty everywhere
- **What/why:** Migrate the 9 bespoke empties onto `MSEmptyState`, then upgrade the component itself with a signature look: layered SF Symbol in a soft `NDS.accentGradient`-tinted squircle (matching `bloomAmbientGlow`'s identity) instead of a bare grey glyph, a per-tab canonical icon map (fix `person.2` on Meetings, `MeetingsView.swift:192`), and a required `filteredVariant` so every searchable/filterable surface distinguishes "nothing exists" (verb-first CTA) from "nothing matches" (one-tap "Clear filters"). CTA slot standardized to `MSPrimaryButtonStyle` (kills the blue `.borderedProminent` empties).
- **User value:** First-run and every drill-in feels intentionally designed; filtered-empty stops sending users to re-create data they already have.
- **Effort:** M · **Impact:** High · **Depends on:** none (1F button consolidation lands the CTA style)

### D4-3 — `TaskMetaCluster`: one task rendering across all 6 surfaces
- **What/why:** Extract the status-toggle + `MSPriorityBadge` + `DueChip` + project chip + `MSAvatar` + meeting-attribution cluster into one component with `.row/.card/.mini` densities; adopt in list, board, table, gallery, NeedsAttentionWidget, ActionItemsWidget. Kills the gallery's hand-rolled chips (`ActionItemsGalleryView.swift:38-45`), the table's raw status colors (`ActionItemsTableView.swift:78-79`), and fixes the 80pt-header/96pt-cell column misalignment (`:46-47` vs `:107,:120`) as part of the rewrite. Gallery cards also gain the context menu and meeting line they currently lack.
- **User value:** A task is recognizably *the same object* whether seen on Today, a board, or a table — the core of "clean and expensive"; switching view modes stops feeling like switching apps.
- **Effort:** M · **Impact:** High · **Depends on:** 2A ViewModel resurrection (sequencing, not blocking)

### D4-4 — Merge "Stay connected" + "Stay in touch" into one Today people module
- **What/why:** Two sections, two overdue formulas, two visual languages, possible double-listing of the same person (`UI/StayConnectedSection.swift` vs `ReconnectView` in `People/SuggestedPeopleView.swift:84-181`). Merge into one `StayConnectedSection` powered solely by the shipped `RelationshipHealth` score; keep typed-cadence people first, heuristic (median-gap) people as a second tier in the same card list; one action set (Log → QuickEncounterSheet, Snooze) — delete ReconnectView's `bumpLastInteraction` "Yes" path, which fakes health without recording an encounter.
- **User value:** One trustworthy answer to "who am I drifting from", one place, one math; removes the most visible duplicated-component artifact in the app.
- **Effort:** S · **Impact:** High · **Depends on:** none

### D4-5 — `MSSheet` scaffold: one sheet anatomy
- **What/why:** A standard sheet container: title row (`scaledFont(18,.bold)`), optional subtitle, Esc-bound Cancel top-right, primary action bottom-trailing in `MSPrimaryButtonStyle`, content slot, two width presets (compact 420 / regular 480) with min-height-not-fixed-height. Migrate NewMeetingSheet, AddPersonSheet, QuickEncounterSheet, TagManagementSheet, HealthCheckSheet (4 header patterns today — citations above). Also retokenize QuickEncounterSheet chips (raw `.white`, radii 10/8, ungated animations; `QuickEncounterSheet.swift:124,238-277`).
- **User value:** Muscle memory — Save/Cancel/Esc always live in the same place; sheets stop clipping under Dynamic Type (pairs with 2H).
- **Effort:** M · **Impact:** Med · **Depends on:** none

### D4-6 — Copy voice guide + entity-name decree ("task" everywhere)
- **What/why:** A one-page `docs/design/VOICE.md` enforced by extending the existing design-lint: (1) the entity is a **task** — retitle "Action items" headers/empties, keep "extracted from meetings" as a description not a name; (2) sentence case for all buttons/labels ("Add person", not "Add Person"); (3) empty/loading/error copy formula: *what this is → why it's empty → verb-first next step*, no engine names (Ollama/FTS/vault) outside Settings; (4) warm register for People surfaces, neutral for work surfaces (matches plan 2B). This is also the decision artifact HELD-ITEMS #6 is explicitly waiting on.
- **User value:** The app sounds like one confident product; "what's the difference between tasks and action items?" stops being a question.
- **Effort:** S · **Impact:** High · **Depends on:** none

### D4-7 — Design-lint v2: radius, semantic-color, and primitive-bypass rules
- **What/why:** The repo already runs design-lint in CI (`scaledFont` allowlisting proves it). Add three rules: (a) flag `RoundedRectangle(cornerRadius: <literal>)` (103 occurrences/40 files) → must use `NDS.radius/rowRadius/cardRadius`; (b) flag raw `.green/.orange/.red/.blue/.yellow` in foreground/fill (status dots `MeetingsView.swift:532-535`, table `ActionItemsTableView.swift:78-79`, `NeedsAttentionWidget.swift:54-80`) → `NDS.status()/NDS.due()/band colors`; (c) flag new `VStack{Image;Text;Text}` empty-state shapes and `.borderedProminent` outside Settings → `MSEmptyState`/`MS*` styles. Drift is regression-proofed, not just cleaned once.
- **User value:** Consistency stops decaying the week after the sweep.
- **Effort:** S · **Impact:** High (compounding) · **Depends on:** D4-2/D4-3 sweeps land first so lint starts green

### D4-8 — "No selection" panes that earn their pixels
- **What/why:** People already solved this (`PeopleInsightsView` dashboard, `PeopleListView.swift:509-513`); Meetings shows a dead "Select a meeting" placard (`MeetingsView.swift:207-223`) and Tasks shows nothing curated. Standardize: every split-view detail pane with no selection renders a lightweight insights/recents card stack (Meetings: this week's recordings + capture-health; Tasks: due-soon + per-project counts) with the tab's primary verb as CTA. One `MSNoSelectionPane(sections:cta:)` component.
- **User value:** The most-seen pixel area in a split-view app (the right pane before any click) sells the product instead of apologizing.
- **Effort:** M · **Impact:** Med-High · **Depends on:** D4-2 (shared visual signature)

### D4-9 — Skeleton standards: shaped placeholders, labeled spinners
- **What/why:** Extend `MSSkeleton` with `.rows(count:avatar:)` and `.cards(count:)` variants so lists/grids load as ghost-shaped structure, not text lines or void; adopt at `DuplicateReviewSheet` (`PeopleListView.swift:650`), `ContactsImportView.swift:80`, the four bare spinners in `PersonDetailView` (`:924,1718,1768,2158`), and ActionItems project pages (`ActionItemsProjectPage.swift:263`). Rule (lintable, D4-7): a bare unlabeled `ProgressView()` may only appear inline next to a verb ("Drafting…", "Checking…") — never centered in a pane. Generalize PeopleListView's frame-0 snapshot trick to the Meetings list (it has the same cold-open).
- **User value:** Loading reads as "fast app arranging content," never "frozen app."
- **Effort:** S-M · **Impact:** Med · **Depends on:** 1F tri-state (endorsed)

### D4-10 — `MSFilterChip`: one chip, with counts
- **What/why:** Unify Meetings scope pills (`MeetingsView.swift:136-147`), People `FilterChip` (`PeopleListView.swift:608-625`), and GlobalSearch's filter bar into one `MSFilterChip(label:count:active:)` — FilterChip's bordered look as the standard, plus an optional count badge (Meetings already computes counts in its header; surfacing them in chips beats the "3 upcoming · 12 past" subtitle). Relationship-type chips reuse it for free.
- **User value:** Filtering looks and behaves identically in all three places users filter; counts answer "is it worth clicking?" before the click.
- **Effort:** S · **Impact:** Med · **Depends on:** none

### D4-11 — Today page rhythm: one section-header + one row spec
- **What/why:** Today stacks 13 sections with ≥4 header styles and ≥3 row treatments (citations in audit). Define `MSTodaySection(icon:title:count:trailing:)` using one header spec (`MSSectionHeader` already exists — `MSComponents.swift:119` — and Today doesn't use it) and route all mini-rows (follow-ups, decisions, on-this-day, commitments — `TodayView.swift:126-306`) through one row style at `NDS.rowRadius`. Pure adoption, no new design.
- **User value:** Today — the landing page — gets the calm, even rhythm of Things 3's Today list instead of a widget junk drawer.
- **Effort:** S · **Impact:** High (it's the first screen) · **Depends on:** D4-3 (task rows), D4-4 (people module)

## Top 3 picks
1. **D4-3 `TaskMetaCluster`** — one task rendering across 6 surfaces, and it fixes a real alignment bug; nothing says "expensive" like the same object looking identical everywhere.
2. **D4-2 Empty-state system v2** — empties are the app's most frequent first impressions; one signature style + filtered-empty handling is the highest polish-per-hour.
3. **D4-4 Merge the two drift sections** — small effort, deletes the most user-visible duplication and a trust-eroding double-math problem on the landing page.

**Single highest-priority rec overall:** D4-3 — paired with the endorsed 1F button consolidation, it converts the Tasks tab (the app's most state-rich surface) from four divergent renderings into one designed system, and D4-7's lint then locks the whole category of drift out of the codebase permanently.
