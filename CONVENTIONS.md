# MeetingScribe — Engineering & Product Conventions

> **READ THIS BEFORE STARTING ANY TASK. UPDATE IT WHEN YOU FINISH ONE.**
>
> This is the single source of truth for *how this app must be built so it stays
> consistent*. It captures hard requirements that are easy to forget and have
> bitten us before (layout cutoffs, missing AI wiring, padding under the title
> bar, design drift).
>
> **The rule:** every contributor (human or AI) **reads this file first**, and
> after shipping a change **appends** any new requirement, decision, or recurring
> request to the relevant section and to the [Requirements change log](#requirements-change-log)
> at the bottom. **Add, never delete** — only remove a line when it is genuinely
> obsolete or proven wrong, and say why in the change log.

---

## 0. How to use this document

1. **Before coding:** skim the relevant sections below (Layout, Design System,
   AI/Chat, Padding, Build/Verify). If your change touches UI, layout, AI, or
   user-facing copy, the matching section is mandatory reading.
2. **While coding:** treat each "Requirement" as a checklist item, not a
   suggestion.
3. **After coding (before you ask to push):**
   - Add any new convention you established to the right section.
   - Append a dated one-liner to the [Requirements change log](#requirements-change-log).
   - Run `scripts/design-lint.sh` and `swift build -c release`.
4. CLAUDE.md (working preferences) and this file are complementary: CLAUDE.md is
   *workflow* (repo, push policy, commit style); this file is *product &
   engineering correctness*.

---

## 1. Responsive layout & sizing (HARD REQUIREMENTS)

The app is a resizable macOS window and must also degrade gracefully toward
small / "mobile-ish" widths. **The user resizes the window constantly. Nothing
may be cut off at any size.** This was broken repeatedly; do not regress it.

### 1.1 Golden rule

> **Every view must lay out correctly inside whatever width its parent gives it —
> at the smallest allowed window size *and* the largest. If a child cannot shrink,
> it is a bug.** Fix it with the SwiftUI equivalents of responsive CSS: flexible
> frames (`minWidth`/`idealWidth`/`maxWidth`), `GeometryReader` breakpoints
> (our "media queries"), horizontal `ScrollView` fallbacks for rigid rows, and
> proportional clamps — **not** hard `.frame(width:)`.

### 1.2 Window & breakpoints (current source of truth)

| Constant | Value | Where | Meaning |
|---|---|---|---|
| Window minimum | `minWidth: 480, minHeight: 480` | `MeetingScribeApp.swift` | App must remain usable down to here. |
| Nav-rail collapse | `width < 880` | `MainWindow.swift` (`railCollapsed`) | Left nav rail collapses **240pt labelled → 56pt icon strip**. Applies to **all tabs at once**. |
| Chat-rail auto-hide | `width < 860` | `MainWindow.swift` (`showChat`) | Assistant rail hides; user's toggle preference is preserved and restored when there's room. |
| Tasks sidebar clamp | `≤ 42%` of pane (floor 168pt) | `ActionItemsView.swift` (`paneSplit`) | The Projects/Tasks rail is a *preference* clamped to a share of available width so it never starves content. |
| Task inspector drawer | `min(geo*0.96, clamp(220…380, geo*0.44))` | `ActionItemsPropertyDrawer.swift` | Inspector is sized to its container and `.clipped()`; can never exceed the pane. |

If you change a breakpoint, update this table in the same commit.

### 1.3 Layout requirements (do these every time)

- **Desktop *and* narrow/mobile:** fix UX for both. A change that only looks right
  maximized is not done. Verify at the window minimum and at a mid (~620–760pt)
  width.
- **No hard widths on content.** Replace `.frame(width: N)` on text fields,
  labels, columns, toolbars with flexible frames. Reserve fixed widths for
  genuinely fixed chrome (icons, dividers).
- **Rigid rows scroll.** A horizontal row of fixed-size controls (e.g. a
  formatting toolbar) must be wrapped in `ScrollView(.horizontal,
  showsIndicators: false)` so it never forces its container wider. (See the
  markdown editor toolbar.)
- **Centered max-width columns left-align when compact.** `notionPageColumn`
  takes an `alignment` parameter; pass `.leading` in compact/narrow hosts so any
  overflow clips only on the trailing edge instead of being centered and cut on
  **both** sides (this is what used to lop the title off the task inspector).
- **Clip at the container, not the content.** Use `.frame(width:…).clipped()` on
  the *pane* so an oversized child collapses behind a sibling rather than spilling
  under the nav rail or off-screen.
- **Collapsible chrome carries its meaning.** When a labelled control collapses
  to an icon (e.g. nav rail), keep its badge/state as a dot and its label as a
  `.help()` tooltip.
- **Multi-column pages stack when narrow.** Two-column layouts (e.g. Today's
  capture + brain-dump) collapse to a vertical `ScrollView` below their
  breakpoint (~680pt). Don't let a second column squeeze the first to unusable.

---

## 2. Padding, safe area & the "navbar header cutoff" rule

Page content sits under a **translucent native window toolbar**. Content that
starts at y=0 gets clipped by it — titles and headers have been cut off here
repeatedly.

- **Never let a page header butt against the title bar.** Top clearance is
  applied centrally via `MainWindow.tabContent`'s
  `.safeAreaInset(edge: .top)` using `NDS.tabTopInset` (currently `14`). New
  top-level tabs inherit this — **do not** remove it, and don't double-pad on
  top of it.
- **Respect the page column gutters.** Use `notionPageColumn(...)` for page
  bodies; in compact hosts pass tighter `horizontalPadding` (e.g. `18`) so the
  full `NDS.pagePadding` (56) doesn't crush narrow content.
- **Spacing scale:** use `NDS.spaceSM (8) / spaceMD (12) / spaceLG (16)` instead
  of magic numbers where a token fits.
- When adding any header/eyebrow/title row, verify it is fully visible at the
  window minimum **and** that its trailing controls (close/expand buttons) don't
  overflow — prefer icon-only controls in narrow chrome.

---

## 3. Design system (NDS) — use it, don't drift

All visuals route through the **`NDS`** design system in
`Sources/MeetingScribe/UI/NotionDesign.swift`. `scripts/design-lint.sh` fails CI
on drift. Run it before pushing.

### 3.1 Tokens (do not hardcode equivalents)

- **Type:** `scaledFont(_:weight:relativeTo:kind:)` (Dynamic-Type aware) or the
  `NDS` type tokens (`NDS.body/small/tiny/…`). **Never** `.font(.system(size:))`.
- **Color (brand):** `NDS.accent` (#ff9173 coral), `NDS.lilac/brand` (#b79cff),
  `NDS.gold` (#ffce6b, warn/due-today/voice), `NDS.danger` (#ff7a8a,
  overdue/high/destructive).
- **Color (surfaces):** `NDS.bg`, `NDS.fieldBg`, `NDS.rowHover`, `NDS.rowSelected`,
  `NDS.divider`, `NDS.hairline`, `NDS.sidebarBg`. **Never** raw
  `Color(NSColor.controlBackgroundColor|separatorColor|windowBackgroundColor|textBackgroundColor)`.
- **Text:** `NDS.textPrimary / textSecondary / textTertiary`.
- **Semantic priority/status:** `NDS.priority(...) / status(...) / due(...)` —
  never a raw `.red/.orange/.green` in a priority/status `switch`.
- **Geometry:** `NDS.rowRadius (12)`, `NDS.cardRadius (20)`,
  `NDS.buttonIconSide (30)`, `NDS.contentMaxWidth (1100)`.
- **Buttons:** use the `MS*ButtonStyle` tokens, not `.bordered` /
  `.borderedProminent`, and don't put `.controlSize` on a `Button` (height comes
  from the style).
- **Motion:** wrap animations in `NDS.motion(_, reduce: reduceMotion)` so Reduce
  Motion is honored.
- **Elevation/hover:** `.ndsElevation(_)` and `.ndsHover()` instead of bespoke
  shadow/hover state.

### 3.2 Escape hatch

If you must deviate, annotate the line with `// design-lint:allow` and explain
why. Settings/Integrations/Diagnostics surfaces are pre-exempt from the jargon
rule only.

### 3.3 Plain-language copy (the word-map)

User-facing `Text("…")` must avoid internal jargon. Ratified map (D4-6):
`vault → library`, `Ollama → summary engine`, `MCP → Claude connection`,
`whisper → speech-to-text`, `ScreenCaptureKit/daemon/FTS5 → plain phrasing`.
Tech names are allowed only on Settings/Advanced/diagnostics surfaces or with an
explicit allow comment.

---

## 4. AI / Chat logic must stay in sync with features

The in-app assistant can *act* on the app through tools. **Whenever you add or
improve an AI-actionable capability, you MUST wire it into the chat tools — an
improvement that the assistant can't reach is half-built.**

### 4.1 Architecture

- Tools live in `Sources/MeetingScribe/Chat/` as domain handlers conforming to
  `ChatToolHandler` (each exposes `tools: [AnthropicClient.Tool]` + `run(name:input:)`):
  - `MeetingChatTools` — meetings + voice notes (read-only)
  - `ActionItemChatTools` — tasks/projects/initiatives + Notion push
  - `BrainDumpChatTools` — brain-dump capture/planning
  - `PeopleChatTools` — People graph + iMessage stats
  - `DecisionChatTools` — decision logs
  - `IntegrationChatTools`, `FileChatTools` — connectors / file access
- They are aggregated in **`ChatTools.swift`** via the `handlers` array and
  attached to the session in `ChatSession.swift` (`self.tools = ChatTools(...)`).

### 4.2 Requirements when adding/changing AI features

1. **Add or extend the matching `*ChatTools` handler** (new tool name + input
   schema + `run` case), and ensure it's in `ChatTools.handlers`.
2. **Update the system prompt context** in `ChatSession` if the model needs to
   know the capability exists.
3. **Keep tool names + schemas stable** across the app/MCP boundary — they're a
   contract (see the note at the top of `ChatTools.swift`). Renames are breaking.
4. **Mirror it for deep links / MCP** if the feature is reachable from outside the
   app (`meetingscribe://` routes, `MeetingScribeMCP`).
5. **Local-first:** AI runs on-device (summary engine / speech-to-text). Don't
   introduce a hard cloud dependency for a core path.
6. Default new AI work to the **latest Claude models** (per environment guidance).

### 4.3 Latency: do the obvious work without the model

Local models are **slow** and flaky at multi-turn tool calling. For any
"analyze and return results" feature:

- **Compute deterministic results in Swift first and show them instantly** (well
  under a second). Reach for the model only for genuinely fuzzy judgement. The
  user should never stare at a spinner with no output.
- **Prefer ONE structured-JSON call** (`OllamaChatClient.oneShotJSON`, Ollama
  `format: "json"`) over a multi-iteration tool loop — one round-trip instead of
  up to N. Send only the data the step needs (small prefill = fast).
- **Run the model phase in the background with a short timeout**, append results
  progressively, and make sure a model failure/timeout **never erases** the
  instant results. Show a slim "still looking…" hint, not a blocking spinner.
- Reference implementation: `TaskOrganizer` ("Organize my Tasks").

---

## 5. Build, verify & ship

(See CLAUDE.md for the authoritative push/commit policy; summarized here.)

- **Build before pushing:** `swift build -c release` (errors block; warnings are
  fine). Run `scripts/design-lint.sh` for UI changes.
- **Install + run the canonical way:** `make install` (release build → sign →
  `/Applications`), then reopen:
  `pkill -x MeetingScribe; sleep 1; /usr/bin/open /Applications/MeetingScribe.app`.
  Use `/usr/bin/open` directly (the user's `~/bin/open` is a custom shim).
- **Visually verify responsive changes** at the window minimum and a mid width
  before claiming done.
- **Commit style:** category prefix (`feat:`/`fix:`/`refactor:`/`docs:`/`perf:`/
  `chore:`), imperative, lowercase first word, < 72 chars. No `Co-Authored-By`
  trailers unless asked.
- **Branch + PR:** work on a feature branch, open a PR, and squash-merge into
  `main` (the user has standing approval for self-merge of feature/fix PRs).
- **Bundle id:** `com.tyleryannes.MeetingScribe`; signing identity "MeetingScribe
  Local Signer". `Resources/Info.plist`'s `CFBundleVersion` auto-bumps on
  build — that diff is expected noise.

---

## 6. Architecture quick-map (where things live)

- `Sources/MeetingScribe/UI/MainWindow.swift` — app shell: nav rail (collapsible),
  keep-alive tab host, toolbar, global safe-area inset.
- `Sources/MeetingScribe/UI/NotionDesign.swift` — the `NDS` design system +
  `notionPageColumn`, `scaledFont`, hover/elevation modifiers.
- `Sources/MeetingScribe/UI/ActionItems*.swift` — the Tasks workspace (rail,
  list/table/board/calendar, Today, property inspector drawer).
- `Sources/MeetingScribe/UI/TaskPageView.swift` — full + compact task page.
- `Sources/MeetingScribe/UI/MarkdownEditor.swift` — rich note editor + scrollable
  toolbar.
- `Sources/MeetingScribe/Chat/` — assistant + tool handlers (see §4).
- `Sources/MeetingScribe/MeetingScribeApp.swift` — scene, window min, deep links.
- `docs/ARCHITECTURE.md` — deeper system design. `docs/audit-2026*/` — roadmaps.

---

## 7. Recurring product principles (remember these)

- **Nothing cut off, ever.** Layout works at all sizes (see §1, §2).
- **Desktop and mobile/narrow are both first-class.** Fix both in the same pass.
- **Headers/titles always clear the title bar** (§2).
- **AI capabilities and chat tools ship together** (§4).
- **Everything routes through NDS** for visual consistency (§3).
- **Local-first, privacy-first.** On-device transcription/summary; iCloud only for
  backup. Keep model files out of iCloud-evictable locations.
- **Performance: keep the main thread free.** Heavy scans off-main, throttle
  refreshes, prewarm caches — don't reintroduce launch/typing/search freezes.

---

## Requirements change log

> Append a dated entry whenever you add a convention or act on a recurring user
> request. Newest at the top. **Add, don't rewrite history.**

- **2026-06-29 — Incremental (every-5-min) transcription on the ScribeCore path.**
  The default recording path is the out-of-process **ScribeCore** daemon, which
  captures audio into rolling 5-minute chunk WAVs but does NO transcription and
  only sends lifecycle Darwin signals. So `LiveTranscriber` sat idle for the whole
  meeting, the live transcript was empty at stop, and the pipeline always ran a
  full-file whisper batch pass — the long "still processing a 30-min file" wait.
  Fix: `ChunkStreamBridge` (new, `Transcription/`) polls `<meetingDir>/chunks/` on
  the main actor and feeds each *closed* chunk (chunk N is final once N+1 exists;
  the trailing partial is swept at stop) into `LiveTranscriber.enqueueChunk` — the
  same per-chunk transcription the direct path gets via callbacks, gated by the
  same `ResourceGovernor.shouldRunLiveTranscription`. `MeetingManager` starts the
  bridge when ScribeCore is the active path, tracks `recordingStartedAt`, and now
  passes the REAL `recordedDuration`/coverage into `finalize` so `needsBatchRepair`
  is skipped when live coverage is complete. `LiveTranscriber.onTranscriptUpdated`
  persists the partial transcript to disk after every chunk (both paths), so a
  meeting is visibly transcribed as it runs and finalize is near-instant.
  **Convention:** transcription is owned by the app and decoupled from the capture
  process — whoever writes the 5-min chunks, the app transcribes them live; never
  let a long recording reach stop with an empty live transcript.
- **2026-06-29 — Duplicate-fix maintenance job (people + meetings).** People are
  merged when they share a contact identifier, a normalized name, a phone (≥7
  digits, via `PersonMatching.normalizePhone`), or an email — grouped
  transitively with union-find (`PeopleStore.duplicateGroupsIndices`), then merged
  field-by-field (richest record wins; talking points / special dates unioned).
  Meetings are merged when they share a normalized title **and** the same start
  minute (`MeetingManager.duplicateMeetingGroups`); the richest copy
  (`meetingRichness`: segments, real end date, user title, notes, imported) is
  kept and the rest are moved to `root/_DuplicateMeetingsTrash` via
  `MeetingStore.archiveDuplicate` (never hard-deleted). Exposed as a manual
  Settings → Privacy & data → **Maintenance** button ("Fix duplicate people &
  meetings"). Convention: dedup is non-destructive — archive, don't delete, and
  always merge into the richest survivor so no field is lost.
- **2026-06-29 — Polish batch: tag colors, From-meetings view, responsive tabs.**
  (1) Auto-tags carry stable semantic colors (`TaskAutoTagger.tagColors`). (2)
  New "From meetings" rail smart view = confirmed meeting-originated tasks in
  list form (companion to Triage). (3) `ResponsiveMasterDetail` wraps the
  People / Recordings / Voice Notes `HSplitView`s so they collapse to one column
  below 640pt instead of breaking once the window can shrink past their combined
  minimums — reuse this for any future two-column tab. (4) Refinements: brain-dump
  accepts go to the workspace (the review panel is the review); theme auto-tags
  apply to AI-derived tasks only, leaving manual tasks clean.
- **2026-06-29 — Projects & Meetings home tabs are master-detail browsers (D).**
  Replaced the horizontal, side-scrolling project board with a left project nav
  (open counts + quick "New project") → right detail showing the selected
  project's tasks + quick-add. Same treatment for the Meetings home tab (list →
  adaptive preview with the meeting's action items + Open). Both use a
  `GeometryReader` breakpoint (<640pt → list-only, tap opens the full page), so
  they never need horizontal scrolling and never break visually — the same
  responsive side-view pattern as the task inspector.
- **2026-06-29 — Auto-tagging (B) + AI-tasks-to-Triage (C3).** New
  `TaskAutoTagger` (shared theme list with the organizer) runs on Tasks-open and
  hourly: every meeting-sourced task gets `#meeting` (its meeting backlink
  already rides on `meetingID`), and any task whose title matches a theme gets
  that tag — idempotent, local, instant (`ActionItemStore.autoTag`). C3: AI-
  proposed tasks (`ActionItem.suggested`) route to the Triage inbox until
  confirmed, never leaking into projects/views; manual tasks are unaffected.
- **2026-06-29 — Projects can belong to multiple initiatives (many-to-many).**
  `Project.initiativeID` (single) gains `initiativeIDs: [String]?` with a computed
  `allInitiativeIDs` fallback — additive optional field, so the migration is
  automatic and lossless (verified: existing single-initiative data + 46 tasks
  intact, no destructive `.bak`). `initiativeID` is kept as the "primary" mirror
  (= `initiativeIDs.first`) so the ~60 legacy read sites keep working; membership
  reads (rail nesting, initiative filter/scope, completion/open counts, standalone
  detection, delete-initiative cleanup) now use `belongs(toInitiative:)`. The
  project header's initiative picker is now multi-select. **Note:** Project IS the
  "page" type already (`Project.swift` header) — "Pages→Projects" is mostly UI
  relabeling, not a data change.
- **2026-06-29 — Organizer cards show a per-task checklist.** Multi-task
  recommendations (tag N tasks / move N tasks to a project) now list every
  affected task with a checkbox so the user can uncheck the ones that don't fit
  before applying; the header count tracks the live selection and Apply acts only
  on the checked subset. Fixes "tag 2 tasks with #bug isn't specific enough — I
  can't tell what it'll touch." (`TaskSuggestion.deselectedTaskIDs` /
  `activeTaskIDs` / `taskList`.)
- **2026-06-29 — "Organize my Tasks" richer + capped at ≤20s.** Added per-task
  individual suggestions to the instant deterministic pass: **split** compound
  tasks into subtasks, **infer a due date** from date words in the title, and
  **theme-based tag/grouping** (single-task tags + grouping tasks that share a
  theme into a matching project or shared tag). The model phase is now **only
  run when ≥4 loose tasks stay unclustered**, hard-capped to **12s** with an
  output-token cap, so a full run finishes in well under 20s. Verified: ~14
  varied suggestions on screen in ~0.6s, grouping pass done by ~12s.
- **2026-06-29 — "Organize my Tasks" made fast + always-output.** The feature
  ran an up-to-10-iteration local-model tool loop (600s timeout each) and showed
  only a blocking spinner — minutes-long, often no visible result. Rebuilt as a
  two-phase engine: an **instant deterministic pass** (overdue→reschedule,
  title-cue→priority, ~0.4s) that always shows value, plus a **single
  structured-JSON model call** for grouping loose tasks that runs in the
  background, appends progressively, and can fail without erasing the instant
  results. Added `OllamaChatClient.oneShotJSON`. Codified as §4.3.
- **2026-06-29 — Global responsive layout (this session).** Quick-view task
  inspector (and Tasks panes) were cut off on the right unless the window was
  large. Fixed app-wide (PR #365): nav rail collapses to a 56pt icon strip below
  880pt; window minimum dropped 860 → 480pt; Tasks sidebar clamped to ≤42% of its
  pane; task inspector left-aligns its page column + sizes to its container;
  markdown toolbar scrolls horizontally; inspector chrome is icon-only. **User
  requirement recorded:** "It needs to work and not be cut off at any size for the
  app and mobile, not just full/fixed view — I change my app size a lot." →
  codified as §1 Golden Rule + breakpoint table.
- **2026-06-29 — This document created.** Established the read-before /
  update-after rule and seeded conventions from prior commits, the NDS design
  system, the chat-tool architecture, design-lint, and the padding/safe-area
  history.
