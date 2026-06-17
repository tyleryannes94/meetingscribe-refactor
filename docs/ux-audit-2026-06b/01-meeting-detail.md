# Audit — Meeting Detail Redesign (de-tab → one canvas)

*Agent: meeting-view. Goal: replace 4 tabs with a single scrolling canvas of collapsible `MSSection`s.*

## Current problems
- 4 mutually-exclusive tabs (`DetailTab`, `MeetingTranscriptTab.swift:172-191`): Meeting/Actions/Transcript/Ask AI — one logical page split apart (`UnifiedMeetingDetail.swift:143-244`).
- Action items render in **three** places: `outcomesStrip` (read-only preview, `MeetingSummaryTab.swift:194-235`), `actionsBody` (full CRUD, `UnifiedMeetingDetail.swift:277-320`), legacy `actionItemsSection` (`MeetingSummaryTab.swift:471-537`).
- `applySmartTabDefault` (`UnifiedMeetingDetail.swift:427-444`) guesses the tab and races a 300ms toggle — the wrong model for a show-everything page.
- Transcript (the record) is a click away; highlights teleport via `tab = .transcript`, losing notes scroll.
- Mode-specific content hides in tab slots (upcoming→brief, live→live transcript).

## Proposed layout — one canvas
Header / reviewBanner / audioBar stay as chrome. Below, a stack of `MSSection`s:

| # | Section | Source | Default past | live | upcoming |
|---|---|---|---|---|---|
| 1 | Outcomes (action items + decisions, full inline CRUD) | merge `outcomesStrip`+`actionsBody` | expand if any | expand if any | hidden |
| 2 | Highlights | `highlightsStrip` | if any | if any | hidden |
| 3 | Summary (recap + edit-by-asking + feedback + copy/follow-up) | `summaryDisclosure`+`pastSummaryBody` | **expanded** (else generating/failed banner) | hidden | hidden |
| 4 | Your notes (`RichMarkdownEditor`) | `currentNotesEditor` | **expanded** | **expanded** | **expanded** |
| 5 | Transcript / Live / Brief (mode-multiplexed) | `transcriptBody` | **collapsed** (mount on expand) | expanded | expanded |
| 6 | Ask AI | `chatBody` | collapsed (lazy) | collapsed | collapsed |
| 7 | Related & linked | `relatedMeetingsStrip`/`backlinksPanel` | if any | — | — |

Defaults encode intent without a "smart tab" guess.

## Constraints & handling
- **A — editor can't nest in a ScrollView.** Outer container is a `VStack` in a `GeometryReader`, NOT a ScrollView. Notes pane = `RichMarkdownEditor` in `.frame(minHeight:240, idealHeight: max(280, geo.height*0.4))` with a drag-resize grabber; it scrolls internally. Short sections size intrinsically. A top-level ScrollView is only safe once every long child has a fixed frame (true after steps below).
- **B — TranscriptSyncView heavy.** Lazy-mount: `if transcriptExpanded { TranscriptSyncView(...).frame(height: transcriptHeight) }` — not instantiated while collapsed (default for past). Repurpose `consumeTranscriptQuery` + highlight buttons to set `transcriptExpanded = true` + scroll-to-anchor instead of `tab = .transcript`.
- **C — mode multiplex.** Keep `transcriptBody`'s `switch mode`; relabel the section (Live transcript / Pre-meeting brief / Transcript); live+upcoming default expanded; other sections hide via `@ViewBuilder` guards so no empty husks.

## Tasks integration
Action Items become **Section 1 (Outcomes)**, expanded by default, full inline CRUD (merge `actionsBody`'s `MeetingActionRow` + "Add all N → Tasks" + "Add action item"; keep decisions from `outcomesStrip`; drop the read-only preview + legacy `actionItemsSection`). Header carries the live triage badge (`unconfirmedActionCount`) + "→ Tasks inbox" bridge. Owner rows get avatar + person jump (see `04-tasks-integration`).

## Build plan (flag-gated migration; each step green)
0. `MSSection` primitive (from `05`).
1. `@AppStorage("meetingCanvasV2")` flag + `canvasBody` scaffold rendering existing `combinedNotesBody`; `body` switches on flag. Off = identical to today.
2. Outcomes section (merged tasks).
3. Notes section with bounded editor + drag-resize (Constraint A).
4. Summary section + generating/failed banners.
5. Transcript section (lazy, mode-multiplexed; Constraints B/C).
6. Ask AI section (lazy, fixed-height).
7. Related/linked + rewire `consumeTranscriptQuery`/highlights/`reviewBanner` to expand+scroll instead of `tab=`.
8. Flip flag default true; soak.
9. Delete `tabPicker`, `switch tab`, `applySmartTabDefault`, `actionsBody`, legacy bodies, `tab`/`hasAppliedTabDefault`/`summaryExpanded` state, `DetailTab` enum.

New file: `MeetingSection.swift` (or reuse shared `MSSection`). Touches `UnifiedMeetingDetail.swift`, `MeetingSummaryTab.swift`, `MeetingTranscriptTab.swift`, `MeetingNotesTab.swift`, `MeetingChatTab.swift`. `MarkdownEditor.swift` is NOT modified — work around it with bounded heights.
