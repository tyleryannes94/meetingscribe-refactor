# Meeting Detail Redesign — De-tab → One Scrolling Canvas

*Audit: ux-audit-2026-06b · Agent: meeting-view · Status: implementation-ready spec*

> **Goal.** Replace the four mutually-exclusive `DetailTab`s (Meeting / Actions /
> Transcript / Ask AI) with a **single vertically-scrolling canvas** of
> collapsible `MSSection` blocks — everything for one meeting visible (or one
> chevron away) at once. No tab switch loses your scroll position; no mode hides
> content in a slot you have to discover; action items live in exactly one place
> with full inline CRUD.
>
> **Non-goals.** No change to `MeetingManager`, `MeetingPipelineController`,
> `ActionItemStore`, `DecisionStore`, the body cache, or any storage format. No
> change to `MarkdownEditor.swift` / `RichMarkdownEditor` internals — we design
> *around* its hard constraint, never inside it. The trailing inspectors
> (`MeetingPeopleRail`, `MeetingPersonConnectPanel`) and the `header` chrome are
> reused verbatim.

---

## Table of contents

1. [Current architecture catalog](#1-current-architecture-catalog)
2. [Problem inventory](#2-problem-inventory)
3. [Hard constraints](#3-hard-constraints)
4. [Proposed canvas](#4-proposed-canvas)
5. [Tasks integration](#5-tasks-integration)
6. [Exhaustive build plan](#6-exhaustive-build-plan)
7. [Edge cases & testing](#7-edge-cases--testing)

---

## 1. Current architecture catalog

The meeting detail is one SwiftUI `struct UnifiedMeetingDetail`
(`UnifiedMeetingDetail.swift:9`) split across five files via `extension`s:

| File | Role |
|---|---|
| `UnifiedMeetingDetail.swift` | Type decl, all `@State`, `body`, lifecycle, `reload()`, smart-tab default, `actionsBody`, save plumbing |
| `MeetingDetailHeader.swift` | `header` and every header sub-builder; Options menu; series spine; export/calendar helpers; `AttendeeChip`; `RecurringChip` |
| `MeetingSummaryTab.swift` | `combinedNotesBody`, `outcomesStrip`, `highlightsStrip`, `summaryDisclosure`, `summaryBody`/`pastSummaryBody`, copy/follow-up, `InlineActionItemRow`, `SummaryFeedbackRow`, `SummaryEditByAsking` |
| `MeetingTranscriptTab.swift` | `audioBar`, `transcriptBody`, `consumeTranscriptQuery`, `LiveTranscriptScroll`, `DetailTab` enum, `MarkdownText` |
| `MeetingNotesTab.swift` | `notesEditor`, `currentNotesEditor`, recurring-series notes sidebar, `backlinksPanel`, `relatedMeetingsPanel`, push-to-tasks |
| `MeetingChatTab.swift` | `chatBody`, capability sections, `chatContext(for:)`, `attachChatIfNeeded` |

### 1.1 `@State` / stored properties (`UnifiedMeetingDetail.swift`)

| Symbol | Line | Role |
|---|---|---|
| `mode: Mode` | 16 | `.live` / `.upcoming(Meeting)` / `.past(Meeting)` — the master switch |
| `manager` (`@EnvironmentObject`) | 18 | All meeting/action/decision data + commands |
| `tagStore` | 19 | Tag membership + primary tag |
| `recordingMonitor` | 20 | Live audio-level + health |
| `router` | 21 | Cross-view navigation (`openMeeting`, `openPerson`, `openTasks`, `pendingTranscriptQuery`) |
| `pipeline` | 23 | `summaryGeneratingIDs`, `liveSummaryByID` — streaming summary state |
| `drive` (`@ObservedObject`) | 24 | Google Drive connection for export |
| `reduceMotion` | 25 | Accessibility gate for animations |
| `chatSession` | 30 | App-wide assistant (shared instance; persists across navigation) |
| `tab: DetailTab` | 32 | **The thing being deleted.** Which of 4 tabs is shown |
| `summaryExpanded` | 34 | Disclosure state of the summary inside the Notes canvas |
| `hasAppliedTabDefault` | 37 | One-shot guard so `applySmartTabDefault` doesn't re-fire |
| `chatAttached` | 38 | One-shot guard for `chatSession.attach(manager:)` |
| `showAllAttendees` | 41 | Header attendee chip rail expander (>8 collapses) |
| `selectedOccurrenceID` | 45 | Recurring series: which prior occurrence's notes are shown (read-only) |
| `noteDraft` | 46 | Editable notes buffer (bound to `RichMarkdownEditor`) |
| `lastSavedDraft` | 47 | Debounce baseline for autosave |
| `saveTimer` | 48 | 0.6s autosave debounce timer |
| `transcript` | 49 | Loaded transcript text |
| `summary` | 50 | Loaded summary markdown |
| `bodyLoaded` | 54 | Tri-state PP-1 flag: false = cold load in flight (show skeleton, not false-empty) |
| `titleDraft` / `descriptionDraft` / `editingHeader` | 55–57 | Header inline-edit buffers |
| `previousPrimaryTagID` | 58 | Detects primary-tag change → file move |
| `audioURLs` | 59 | Discovered audio files (drives `audioBar` + transcript seek) |
| `audioController` (`@StateObject`) | 63 | Shared `AudioPlayerController`; transport bar + transcript timestamps seek the same player |
| `bodyLoadTask` | 67 | Cancellable in-flight body refresh (cancels on meeting switch) |
| `backlinks` | 68 | `[WorkspaceEntity]` linking to this meeting |
| `relatedMeetings` | 70 | Embedding-similar meetings |
| `showAudioImporter` / `showTranscriptImporter` / `showFollowUp` | 72–74 | Sheet/importer presentation flags |
| `connectingAttendee` | 79 | Non-nil → inline person-connect inspector shown |
| `peopleRailVisible` (`@AppStorage`) | 81 | Persistent "Who's here" rail toggle (⌥⌘P) |
| `transcriptSearchSeed` | 83 | Query carried from a search hit into the transcript find bar |

### 1.2 Computed properties (`UnifiedMeetingDetail.swift`)

| Symbol | Line | Role |
|---|---|---|
| `meeting: Meeting?` | 85 | Resolves the active meeting from `mode` (live → `manager.activeMeeting`) |
| `isRecurring` | 94 | `seriesID` non-empty |
| `priorOccurrences` | 98 | Past occurrences of the series, newest first |
| `allOccurrences` | 107 | Series spine, oldest→newest, incl. current |
| `occurrenceIndex` / `previousOccurrence` / `nextOccurrence` | 115–128 | Series spine navigation |
| `unconfirmedActionCount` | 249 | This meeting's `needsTriage` action items — drives the Actions tab badge |

### 1.3 View-builders by file

**`UnifiedMeetingDetail.swift`**

| Builder | Line | Role |
|---|---|---|
| `reviewBanner` | 132 | 24h post-meeting `PostMeetingReviewBanner` (past only); its `onReviewTasks` does `tab = .actions` |
| `body` | 143 | The whole view: top inset, `header`, `reviewBanner`, `audioBar`, `tabPicker`, `switch tab`, trailing inspectors, lifecycle modifiers, file importers |
| `tabPicker` | 254 | `MSPillTabs` over `DetailTab.allCases`; relabels Transcript→"Brief" for upcoming, Actions→"Actions N" when triage pending |
| `actionsBody` | 277 | **Dedicated Actions tab** — full CRUD `MeetingActionRow`s + "Add all N → Tasks" + "Add action item" |
| `placeholder(...)` | 321 | Generic centered icon/title/message empty state (legacy; `MSEmptyState` is the newer equivalent) |

**`MeetingDetailHeader.swift`**

| Builder | Line | Role |
|---|---|---|
| `header` | 8 | Series spine, title row + meta + chips + action buttons, attendee rail, shared-history strip, conference URL, `TagPicker`, upcoming action row, status banner, divider |
| `titleAndDescription` | 110 | Title (display or inline-edit `TextField`s + Save/Cancel) |
| `metaLine` | 150 | Time range + health badge + "Processing…" |
| `chipRow` | 171 | `RecurringChip` + calendar `NotionChip` |
| `actionButtons` | 188 | `primaryCTA` + `overflowMenu` |
| `primaryCTA` | 200 | Context CTA: Stop / Transcribe Now / Re-transcribe / Record Again / Join & Record / Record |
| `overflowMenu` | 263 | "Options" menu: edit, source, transcribe, join, add recording, copy link, reveal, recover, export, calendar |
| `sourceMenuContent(for:)` | 417 | Meeting-source submenu |
| `upcomingActionRow(_:)` | 441 | Join Call / Record Only |
| `statusBanner` | 478 | Recording level meter + health, or interrupted-recovery banner |
| `seriesSpine` | 578 | Prev/next occurrence + "Occurrence N of M" menu |
| Helpers | 519–796 | `resetDrafts`, `saveHeader`, `timeRange`, export/Obsidian/Drive/calendar, `sharedHistoryLine`, add-all-attendees, `recordingHealthRow`, `healthDot` |
| `AttendeeChip` (private struct) | 801 | One attendee capsule; tap → `connectingAttendee` |
| `RecurringChip` (private struct) | 893 | "Recurring" chip → `SeriesHubView` sheet |

**`MeetingSummaryTab.swift`**

| Builder | Line | Role |
|---|---|---|
| `combinedNotesBody` | 11 | The "Meeting" tab body: `outcomesStrip` + `highlightsStrip` + (VSplitView of `summaryDisclosure` + `notesEditor` / generating banner / failed banner / notes-only) + `relatedMeetingsStrip` |
| `hasRealSummary` | 57 | Non-empty AND not the `_Summary unavailable_` placeholder |
| `isSummaryGenerating` | 63 | `pipeline.summaryGeneratingIDs` contains id, or live tokens streaming |
| `summaryGeneratingBanner` | 70 | Spinner + streaming tokens (capped 240pt) |
| `summaryFailedBanner` | 91 | "No summary yet" + Generate retry |
| `relatedMeetingsStrip` | 123 | Embedding-similar meeting rows (tappable) |
| `highlightsStrip` | 154 | `MeetingMarks` chips; tap → `tab = .transcript` |
| `outcomesStrip` | 195 | **Read-only** preview: first 5 action items (toggle done) + first 3 decisions |
| `summaryDisclosure` | 238 | Collapsible "Summary" + follow-up button + read-only `MarkdownEditor` in a `ScrollView` |
| `summaryBody` / `pastSummaryBody` | 277 / 335 | Legacy stand-alone Summary tab (still compiled; reachable via streaming-token + edit/feedback path) |
| `copyMenu` / `slackFormatted` / `emailFormatted` / `copyToClipboard` | 300–333 | Copy-for-channel menu |
| `emptySummaryView` | 400 | `MSErrorState` failed-summary or generic empty |
| `followUpButton` | 439 | "Draft follow-up…" → `FollowUpView` sheet |
| `actionItemsSection(_:)` | 472 | **Legacy third action-item render** — full inline list w/ triage bridge |
| `addActionItem` / `attendeeEmails(for:)` | 540 / 554 | Helpers |
| `InlineActionItemRow` (private struct) | 569 | Editable action item row (title/owner/due/priority) used by `actionItemsSection` |
| `SummaryFeedbackRow` | 683 | 👍/👎 + why → steers regeneration |
| `SummaryEditByAsking` | 741 | Preset chips + free-text local rewrite of the recap |

**`MeetingTranscriptTab.swift`**

| Builder | Line | Role |
|---|---|---|
| `audioBar` | 9 | `AudioPlayerBar` when `audioURLs` non-empty |
| `transcriptBody` | 19 | `switch mode`: `LiveTranscriptScroll` / `PreMeetingBriefView` / `TranscriptSyncView` (or skeleton/placeholder) |
| `consumeTranscriptQuery` | 55 | Pulls `router.pendingTranscriptQuery` → seeds search + `tab = .transcript` |
| `liveStartedAt` | 64 | Recording-start time for the countdown |
| `LiveTranscriptScroll` (struct) | 73 | Auto-scrolling live chunks + countdown footer; **owns its own `ScrollView`** |
| `DetailTab` (enum) | 172 | **The thing being deleted** — `notes / actions / transcript / chat` |
| `MarkdownText` (struct) | 199 | Read-only `MarkdownEditor` wrapper |

**`MeetingNotesTab.swift`**

| Builder | Line | Role |
|---|---|---|
| `notesEditor` | 7 | Recurring+priors → sidebar split; else `currentNotesEditor` |
| `currentNotesEditor` | 20 | Caption + `RichMarkdownEditor($noteDraft)` + push-to-tasks + `backlinksPanel` + `relatedMeetingsPanel` |
| `pushNoteTodosToTasks(_:)` | 49 | Parse checkbox/TODO lines → `manager.pushToTasks` |
| `notesMainArea` | 73 | Prior-occurrence read-only notes or current editor |
| `previousCallsSidebar` | 103 | 200pt list of this call + priors |
| `occurrenceRow` / `hasNotes` / `occurrenceLabel` | 129–158 | Sidebar row helpers |
| `backlinksPanel` | 161 | "Linked from" entity rows |
| `relatedMeetingsPanel` | 193 | Second copy of related-meetings UI (notes-tab variant) |

**`MeetingChatTab.swift`**

| Builder | Line | Role |
|---|---|---|
| `chatBody` | 7 | `ChatPanel(session: chatSession, density: .compact, capabilitySections:)` scoped to this meeting via `setContext` |
| `meetingCapabilitySections` (static) | 33 | Grouped suggested prompts |
| `chatContext(for:)` | 54 | Builds the per-meeting system context (title/when/attendees/people graph) |
| `attachChatIfNeeded` | 96 | One-shot `chatSession.attach(manager:)` |

### 1.4 `DetailTab` case → render map

| Case (`MeetingTranscriptTab.swift:172`) | `body` arm (`UnifiedMeetingDetail.swift:158`) | Renders |
|---|---|---|
| `.notes` (label "Meeting") | `combinedNotesBody` | Outcomes preview + highlights + (summary ⇅ notes split) + related |
| `.actions` (label "Actions"/"Actions N") | `actionsBody` | Full-CRUD action item list + add-all + add |
| `.transcript` (label "Transcript"/"Brief") | `transcriptBody` | Live scroll / pre-meeting brief / synced transcript |
| `.chat` (label "Ask AI") | `chatBody` | `ChatPanel` scoped to meeting |

### 1.5 Lifecycle (`body` modifiers, `UnifiedMeetingDetail.swift:167-243`)

- `.onAppear`: `reload()` + `attachChatIfNeeded()` + `applySmartTabDefault()` + `consumeTranscriptQuery()`
- `.onChange(meeting?.id)`: `hasAppliedTabDefault = false`; `reload()`; clear `connectingAttendee`
- `.onChange(audioURLs)`: `audioController.reload(urls:)`
- `.onChange(router.pendingTranscriptQuery)`: `consumeTranscriptQuery()`
- `.onChange(noteDraft)`: `scheduleNoteSave()`
- `.onChange(tags)`: `handleTagChange()` (file move on primary-tag change)
- `.onChange(manager.state)`: `reloadIfLiveFinished()`
- `.onChange(manager.transcribingMeetingIDs)`: `reload()` when this id drops out
- `.onDisappear`: `flushNoteSave()`; cancel `bodyLoadTask`; `audioController.release()`

---

## 2. Problem inventory

### P1 — Tab fragmentation: one page cut into four. **Severity: high.**

**Evidence:** `DetailTab` (`MeetingTranscriptTab.swift:172`) drives an exclusive
`switch tab` (`UnifiedMeetingDetail.swift:157-164`) with `MSPillTabs`
(`tabPicker`, line 254). Only one of {Meeting, Actions, Transcript, Ask AI} is
ever on screen.

**User impact:** Reading the recap (`.notes`) while checking what the transcript
actually said (`.transcript`) requires a tab round-trip that throws away both
scroll positions (each arm has its own `ScrollView` / `VSplitView`). The four
artifacts of one meeting — outcomes, recap, notes, record — are conceptually one
document; the UI insists they're four pages.

### P2 — Action items rendered in **three** places, two of them stale. **Severity: high.**

**Evidence:**
1. `outcomesStrip` (`MeetingSummaryTab.swift:195-235`) — read-only preview, first
   5 items, only a done-toggle; lives at the top of `.notes`.
2. `actionsBody` (`UnifiedMeetingDetail.swift:277-320`) — the **real** CRUD
   surface using `MeetingActionRow` + "Add all N → Tasks" + "Add action item";
   lives in `.actions`.
3. `actionItemsSection(_:)` (`MeetingSummaryTab.swift:472-537`) — a *second* full
   list using `InlineActionItemRow`, with its own triage bridge and Add button;
   only reachable through `pastSummaryBody` (`:393`), the legacy stand-alone
   Summary path.

**User impact:** The same task appears in two layouts with different controls
(`MeetingActionRow` vs `InlineActionItemRow`), different owner UI, and different
"→ Tasks" affordances. Toggling done in the preview vs the tab is two different
code paths. Maintenance hazard: a fix to one row type silently misses the other.

### P3 — `applySmartTabDefault` guesses the page and races a timer. **Severity: medium.**

**Evidence:** `applySmartTabDefault()` (`UnifiedMeetingDetail.swift:427-444`) sets
`tab` per mode, then for `.past` fires a **300 ms `Task.sleep`** (line 436) that
flips `summaryExpanded` based on whether `summary` is non-empty *at that instant*.
`reload()` (line 369) fills `summary` asynchronously from disk; whether the 300 ms
guess wins or loses the body-load race is non-deterministic.

**User impact:** On a cold open the summary disclosure sometimes opens, sometimes
not, depending on disk-read timing. The guard `hasAppliedTabDefault`
(`:428`) and its reset on meeting switch (`:173`) exist purely to stop the guess
from re-firing — complexity that vanishes when there is no tab to guess.

### P4 — Cross-tab teleports lose scroll and notes context. **Severity: medium.**

**Evidence:**
- `highlightsStrip` chips do `tab = .transcript` (`MeetingSummaryTab.swift:168`).
- `consumeTranscriptQuery()` sets `tab = .transcript` (`MeetingTranscriptTab.swift:58`).
- `reviewBanner`'s `onReviewTasks` does `tab = .actions` (`UnifiedMeetingDetail.swift:139`).

**User impact:** Each teleport unmounts the current arm (losing its scroll offset
and any in-progress notes-editor caret) and mounts the target arm at the top.
"Jump to the transcript" from a highlight is supposed to land you *near a moment*;
instead it lands at the top of a freshly-mounted `TranscriptSyncView`, and the
seed search is the only thing keeping it useful.

### P5 — Mode-multiplexed content hidden in tab slots. **Severity: medium.**

**Evidence:** `transcriptBody` (`MeetingTranscriptTab.swift:19-51`) overloads the
"Transcript" tab to be three different things by `mode`: `LiveTranscriptScroll`
(live), `PreMeetingBriefView` (upcoming — relabeled "Brief" in `tabPicker:262`),
or `TranscriptSyncView` (past).

**User impact:** For an upcoming meeting the most valuable content (the
pre-meeting brief: prior meetings + open items) is behind a tab labeled "Brief"
that users don't think to open. For a live meeting the running transcript is one
tab away from the notes you're typing — exactly the two things you want
side-by-side.

### P6 — Header density. **Severity: low–medium.**

**Evidence:** `header` (`MeetingDetailHeader.swift:8-106`) stacks, in order:
series spine, title+meta+chips+CTA+overflow, an attendee `ScrollView`, a
shared-history strip, a conference-URL row, a `TagPicker`, an upcoming action
row, and a status banner — then `reviewBanner` and `audioBar` and `tabPicker`
follow it in `body`. On a short window the canvas can start 250–300pt down.

**User impact:** Fixed chrome eats vertical space before any meeting content
appears. The de-tab makes this worse unless the header stays compact, because the
content below now scrolls *as one column* rather than each tab managing its own
height.

### P7 — Generating / failed summary states are duplicated and inconsistent. **Severity: medium.**

**Evidence:** Two parallel implementations:
- New canvas: `summaryGeneratingBanner` (`MeetingSummaryTab.swift:70`) +
  `summaryFailedBanner` (`:91`), gated by `isSummaryGenerating` / `bodyLoaded &&
  !transcript.isEmpty` in `combinedNotesBody` (`:26-41`).
- Legacy: `pastSummaryBody` (`:335`) renders streaming tokens inline (`:339-349`),
  then `emptySummaryView` (`:400`) uses `MSErrorState` for the same failure.

**User impact:** Two visual languages for "summary is generating" and "summary
engine was off." Which one a user sees depends on which path is live. The
streaming-token preview is capped at 240pt in one place (`:82`) and uncapped in
the other (`:347`).

---

## 3. Hard constraints

These are physics, not preferences. Each is stated with the exact mechanism, then
the **exact handling pattern** the canvas must use.

### C-A — `MarkdownEditor` / `RichMarkdownEditor` **cannot** nest inside an outer `ScrollView`.

**Why (NSViewRepresentable internals).** `MarkdownEditor.makeNSView`
(`MarkdownEditor.swift:26-76`) builds its own `NSScrollView` (`:27`) with
`hasVerticalScroller = true` (`:28`) and an `isVerticallyResizable` text view
(`:39`) whose container has `containerSize.height = .greatestFiniteMagnitude`
(`:43`) and `widthTracksTextView = true` (`:44`). The text view's
`autoresizingMask = [.width]` (`:41`) means it sizes its **height to its
content, unbounded**, and relies on the enclosing `NSScrollView` to clip and
scroll.

If this is placed inside a SwiftUI `ScrollView`, SwiftUI proposes an *infinite*
height to the representable (a SwiftUI `ScrollView` gives its content unbounded
main-axis space). The inner `NSScrollView` then lays out at full content height,
the scroller never engages, two scroll systems fight for the wheel/trackpad, and
on long notes/transcripts you get an unbounded view that pushes everything below
it off-screen and makes the outer scroll jump. `RichMarkdownEditor`
(`MarkdownEditor.swift:707`) wraps the same `MarkdownEditor` plus a toolbar, so
it inherits the constraint. `TranscriptSyncView` has the **same shape**: its body
(`TranscriptSyncView.swift:114-123`) ends in `transcriptScroll`, an internal
`ScrollView` over a `LazyVStack`; and `LiveTranscriptScroll`
(`MeetingTranscriptTab.swift:84`) is built around a `ScrollViewReader { ScrollView
{ … } }`. All three are **self-scrolling AppKit/SwiftUI scroll views**.

**Exact handling pattern.** The canvas outer container is **NOT a `ScrollView`**.
It is a `VStack` whose long children each get a **fixed, bounded height** so they
clip-and-scroll internally; only the *short* sections (Outcomes, Highlights,
Related) size intrinsically. A single SwiftUI `ScrollView` wraps *only* the
short, intrinsically-sized sections; the editor and transcript and chat sit at
explicit heights derived from a `GeometryReader`.

```swift
// Canvas root — NOT a ScrollView around the editor.
GeometryReader { geo in
    VStack(spacing: 0) {
        // SHORT sections scroll together in their own ScrollView.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                outcomesSection            // intrinsic height
                highlightsSection          // intrinsic height
                summarySection(geo: geo)   // bounded: see below
                relatedSection             // intrinsic height
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
        }
        // LONG self-scrolling children at explicit heights, OUTSIDE the ScrollView.
        notesSection                       // RichMarkdownEditor at bounded height
        transcriptSection(geo: geo)        // lazy; bounded height when expanded
        chatSection(geo: geo)              // lazy; bounded height when expanded
    }
}
```

The **summary** is read-only `MarkdownEditor` and *also* self-scrolling, so when
expanded it gets a bounded height too:

```swift
ScrollView { MarkdownEditor(text: .constant(summary), isEditable: false) }
    .frame(height: min(420, max(180, geo.size.height * 0.45)))
```

Where a long pane must coexist *inside* the scrolling column (e.g. summary), cap
its height; where it can own the bottom of the window (notes/transcript/chat),
give it the remaining height via `geo`. **Rule:** every descendant that contains
a `MarkdownEditor` / `RichMarkdownEditor` / `TranscriptSyncView` /
`LiveTranscriptScroll` / `ChatPanel` MUST have a finite frame height before it is
mounted. This is verified by the build steps (§6): each section is added with its
frame already bounded, never "TODO height later."

### C-B — `TranscriptSyncView` is heavy; never mount it eagerly.

**Why.** `TranscriptSyncView` parses the raw transcript on appear
(`TranscriptSyncView.swift:124-128` → `parse()`), builds a speaker map, assigns
speaker colors, and renders a `LazyVStack` of potentially hundreds of segments
with per-segment audio-sync state (`activeSegmentID`, `:109`). Re-parsing on
every `rawTranscript` change (`:130`) is cheap-ish but the initial parse + view
graph for a long meeting is the most expensive thing on the page. In the tab
world it only mounted when you opened the Transcript tab; in a single canvas a
naive always-rendered section would parse + lay out every transcript on every
meeting open.

**Exact handling pattern.** Gate mounting on the section's expanded state and a
one-shot "has ever been expanded" latch, so collapsing doesn't tear down the
parsed graph but the first open is deferred:

```swift
@State private var transcriptEverExpanded = false
// inside the transcript section's content, only when expanded:
if transcriptExpanded {
    Color.clear.onAppear { transcriptEverExpanded = true }
    TranscriptSyncView(rawTranscript: transcript,
                       audioController: audioURLs.isEmpty ? nil : audioController,
                       initialSearch: transcriptSearchSeed,
                       meetingID: meeting?.id,
                       attendees: meeting?.attendees ?? [])
        .frame(height: transcriptPaneHeight(geo))   // C-A: bounded
}
```

For `.past`, the Transcript section defaults **collapsed** (the recap is the
default read; the transcript is the receipt). For `.live` and `.upcoming` it
defaults **expanded** (the live transcript / brief is the point of the page).
`transcriptExpanded` is the section's own persisted disclosure state
(`MSSection` persistenceKey), seeded by mode.

### C-C — Mode-multiplexed transcript slot (live / upcoming / past).

**Why.** `transcriptBody` (`MeetingTranscriptTab.swift:19`) renders three
unrelated views by `mode`: live transcript, pre-meeting brief, or synced
transcript. The brief and the live scroll are not "the transcript" — they're the
mode-appropriate content for that one slot.

**Exact handling pattern.** Keep the `switch mode` inside the section body, but
make the **section title and default-collapse mode-aware** so the section reads
correctly in each mode and is never an empty husk:

```swift
private var transcriptSectionTitle: String {
    switch mode {
    case .live:     return "Live transcript"
    case .upcoming: return "Pre-meeting brief"
    case .past:     return "Transcript"
    }
}
// Section guard: for .past with no transcript and not loading, the whole
// section is omitted (no empty "Transcript" husk) — handled by @ViewBuilder
// returning EmptyView, same pattern outcomesStrip uses today (line 199).
```

For `.upcoming` the section default-expands and the body is `PreMeetingBriefView`
(no audio controller, no bounded-internal-scroll concern because the brief is a
normal SwiftUI scroll — but it still gets a bounded height via `geo`). For `.live`
it default-expands to `LiveTranscriptScroll`. For `.past` it's
`TranscriptSyncView` (or skeleton while `!bodyLoaded`, or omitted when truly
empty).

### C-D — One shared `AudioPlayerController`.

**Why.** `audioController` (`UnifiedMeetingDetail.swift:63`) is shared by the
`audioBar` transport and `TranscriptSyncView` so a timestamp tap seeks the same
audio you hear (C1-3 in the code comment). It's reloaded on `audioURLs` change
(`:176`) and released on disappear (`:193`).

**Exact handling pattern.** `audioBar` stays as fixed chrome **above** the
scrolling column (unchanged), exactly where it is today (`body:154`). The
Transcript section continues to pass the same `audioController` instance. Because
the transcript may now be unmounted (collapsed) while audio plays, the controller
must outlive the section — which it already does (it's `@StateObject` on the
parent). No change needed beyond *not* moving `audioController` ownership into the
section.

---

## 4. Proposed canvas

### 4.1 Structure

```
Color.clear (splitPaneTopInset)        ─┐
header                                  │  fixed chrome (unchanged)
audioBar (if audioURLs)                 │
Divider                                ─┘
─────────────────────────────────────────
canvasBody  (GeometryReader → VStack):
  ScrollView {                          ← short sections only (C-A)
     1. Outcomes
     2. Highlights
     3. Summary  (bounded internal scroll)
     7. Related & linked
  }
  4. Notes        (RichMarkdownEditor, bounded)   ← below the ScrollView
  5. Transcript   (lazy, mode-multiplexed, bounded)
  6. Ask AI       (lazy, bounded)
─────────────────────────────────────────
trailing inspector (connect panel / people rail) — unchanged
```

> **`reviewBanner`** (the 24h checklist) moves to sit just under the header,
> above the `ScrollView`, as chrome (it's a transient nudge, not a section). Its
> `onReviewTasks` is rewired to expand+scroll the Outcomes section (§6.8) rather
> than `tab = .actions`.

### 4.2 Section list

Persistence key prefix: `meeting.<key>` → `MSSection(persistenceKey:)` stores
`section.meeting.<key>.expanded` in `UserDefaults` (see `MSComponents.swift:253`).
Mode-seeded defaults are applied via `defaultExpanded:` per render.

| # | Section | Persistence key | Default (past) | Default (live) | Default (upcoming) | Mapped from | Bounded? |
|---|---|---|---|---|---|---|---|
| 1 | **Outcomes** (action items + decisions, full inline CRUD) | `meeting.outcomes` | expanded if any, else hidden | expanded if any | hidden | merge `outcomesStrip` + `actionsBody` + `MeetingActionRow` | intrinsic |
| 2 | **Highlights** | `meeting.highlights` | expanded if any, else hidden | expanded if any | hidden | `highlightsStrip` (`:154`) | intrinsic |
| 3 | **Summary** (recap + edit-by-asking + feedback + copy + follow-up) | `meeting.summary` | **expanded** (or generating/failed banner) | hidden | hidden | `summaryDisclosure` + `pastSummaryBody` extras | internal scroll capped `min(420, max(180, h*0.45))` |
| 4 | **Your notes** (`RichMarkdownEditor`) | `meeting.notes` | **expanded** | **expanded** | **expanded** | `currentNotesEditor` / `notesEditor` | `frame(height:)` via geo + drag grabber |
| 5 | **Transcript / Live / Brief** | `meeting.transcript` | **collapsed** (lazy) | **expanded** | **expanded** | `transcriptBody` (C-B/C-C) | `frame(height:)` via geo |
| 6 | **Ask AI** | `meeting.chat` | collapsed (lazy) | collapsed (lazy) | collapsed (lazy) | `chatBody` | `frame(height:)` via geo |
| 7 | **Related & linked** | `meeting.related` | expanded if any, else hidden | hidden | expanded if any | `relatedMeetingsStrip` + `backlinksPanel` | intrinsic |

**Why these defaults encode intent (replacing `applySmartTabDefault`):**

- *Past:* you open a finished meeting to read the recap → Summary expanded; the
  transcript is the receipt you rarely need → collapsed. Outcomes/Highlights show
  only when they exist. No 300 ms race (§P3): expansion is a deterministic
  function of `mode` + content presence, evaluated at render.
- *Live:* you're recording → Notes (type alongside) + Live transcript both
  expanded; Summary/Outcomes don't exist yet so they're hidden.
- *Upcoming:* prep is the job → Brief expanded; Notes available to jot prep;
  everything past-only is hidden.

### 4.3 `MSSection` usage

Each section is one `MSSection(title:, systemImage:, count:, persistenceKey:,
defaultExpanded:, trailing:, content:)` (`MSComponents.swift:224`). The header
chevron + eyebrow + count come free; the **trailing accessory** carries the
section's primary action *outside the toggle's hit area* (per the component's
contract, `:218`). Examples:

- Outcomes `trailing`: "Add all N → Tasks" (when triage pending) + "+ Add".
- Summary `trailing`: `copyMenu` + "Draft follow-up…".
- Notes `trailing`: "Push to-dos → Tasks" (when notes non-empty).
- Transcript `trailing`: a find-bar affordance for `.past` (seeds search).

`MSSection` owns no horizontal padding (`:222`); the canvas wraps each in
`.padding(.horizontal, 20)` to match the header inset (`MeetingDetailHeader.swift`
uses `20` throughout).

### 4.4 Bounded-height strategy (per the C-A rule)

Computed from the `GeometryReader`'s height (call it `h`):

| Pane | Height |
|---|---|
| Summary internal scroll | `min(420, max(180, h * 0.45))` |
| Notes editor | starts `max(280, h * 0.40)`, user-resizable via grabber (clamped 160…`h*0.7`); persisted to `@AppStorage("meeting.notes.height")` |
| Transcript pane | `max(320, h * 0.55)` when it owns the bottom; `h * 0.45` when notes also expanded |
| Ask AI pane | `max(360, h * 0.55)` |

When multiple bottom sections are expanded simultaneously, the column would
exceed the window — so the **bottom three sections (Notes/Transcript/Chat) are
themselves wrapped in a vertical scroll of fixed-height blocks** only if more than
one is expanded; the common case (one expanded) fills the remaining height. The
simplest robust rule, used by the build steps: give each expanded bottom section
its bounded height and let the *outer* canvas `VStack` overflow into a final thin
`ScrollView` *only over the bottom group*. (The short sections already scroll in
their own `ScrollView`.)

> Implementation note: because both groups can scroll, keep them visually
> separated by a `Divider().overlay(NDS.divider)` so the user perceives "recap
> area" (scrolls) above "work area" (scrolls) — not one confusing nested scroll.

### 4.5 Drag-resize grabber (Notes)

Replaces the `VSplitView` that today balances summary vs notes
(`combinedNotesBody:21`). Since summary now lives in the upper `ScrollView` and
notes lives below, a single horizontal grabber on the **top edge of the Notes
section** resizes the notes pane:

```swift
notesPaneHeight  // @AppStorage("meeting.notes.height"), default max(280, h*0.40)
// grabber:
Rectangle().fill(.clear).frame(height: 6).contentShape(Rectangle())
  .gesture(DragGesture().onChanged { v in
      notesPaneHeight = (notesPaneHeight - v.translation.height)
          .clamped(to: 160 ... (h * 0.7))
  })
  .help("Drag to resize notes")
```

### 4.6 Scroll-to-anchor behavior (replacing cross-tab teleports, §P4)

The outer short-section `ScrollView` gets a `ScrollViewReader`. Each section's
`MSSection` is tagged `.id(SectionAnchor.x)`. Actions that used `tab = …` now:
1. Set the target section's expanded state to `true` (write its persistence key).
2. `withAnimation { proxy.scrollTo(.target, anchor: .top) }`.
3. For transcript, additionally set `transcriptSearchSeed` / a pending segment so
   `TranscriptSyncView` lands near the moment.

| Old teleport | New behavior |
|---|---|
| Highlights chip `tab = .transcript` (`:168`) | expand Transcript + scroll to it + seed search with the mark's timestamp/label |
| `consumeTranscriptQuery` `tab = .transcript` (`:58`) | expand Transcript + scroll + seed search |
| `reviewBanner` `onReviewTasks: tab = .actions` (`:139`) | expand Outcomes + scroll to it |

Because the upper sections share one `ScrollView`, scrolling to Summary/Outcomes
keeps the rest of the page mounted — no lost scroll, no remount (§P4 fixed).

---

## 5. Tasks integration

Action Items become **Section 1 — Outcomes**, the single canonical surface (kills
the triple-render of §P2).

### 5.1 Content (merged)

- **Action items** with full inline CRUD via `MeetingActionRow`
  (`MeetingActionRow.swift:7`), which already has: done-toggle, due chip,
  attendee-first owner menu (`ownerMenu:67`), and the per-row "→ Tasks" / "In
  Tasks" bridge (`:48-57`). This replaces both `outcomesStrip`'s read-only preview
  and `actionItemsSection`'s `InlineActionItemRow`.
- **Decisions** (first N) carried over from `outcomesStrip`
  (`MeetingSummaryTab.swift:220-227`): seal icon + decision text.
- **Add action item** (from `actionsBody:306-313`): creates a task already linked
  to this meeting (`meetingID`/`meetingTitle`/`meetingDate`).

### 5.2 Section header / trailing accessory

- `count:` = action item count (drives the `MSSection` count badge).
- **Triage badge:** when `unconfirmedActionCount > 0` (`UnifiedMeetingDetail.swift:249`),
  show a coral "N to review" pill in the section header trailing slot.
- **"Add all N → Tasks":** `manager.actionItems.confirm(ids:)` over the
  `needsTriage` items (from `actionsBody:288-294`), shown in trailing when triage
  pending.
- **"→ Tasks inbox" bridge:** the `router.openTasks(route:
  ActionItemsView.triageSentinel)` link from `actionItemsSection:491-497`, shown
  when triage items exist; "All in Tasks ✓" otherwise.

### 5.3 Owner avatars / links

`MeetingActionRow.ownerMenu` already renders `MSAvatar(name: owner, size: 16)`
(`MeetingActionRow.swift:84`). Per `04-tasks-integration`, the owner gains a
person jump when `ownerPersonID` is set — wire `router.openPerson(pid)` on the
avatar/name (the pattern exists in `InlineActionItemRow:613-621`, which we are
deleting; lift that one affordance into `MeetingActionRow`).

### 5.4 Empty state

When `.past` and no items + no decisions, render
`MSEmptyState(systemImage: "checklist", title: "No action items", message: "Items
appear here after summarization, or add one below.")` (from `actionsBody:297`),
with an "Add action item" action. For `.upcoming`, the whole section is hidden.

### 5.5 Net deletions for §P2

`outcomesStrip`, `actionsBody`, `actionItemsSection(_:)`, and `InlineActionItemRow`
all collapse into the one Outcomes section built on `MeetingActionRow`. (Listed in
§6.10 cleanup.)

---

## 6. Exhaustive build plan

Strategy: **flag-gated parallel build.** Add an `@AppStorage("meetingCanvasV2")`
flag; build the canvas *beside* the tabs; migrate section by section behind the
flag (each step compiles and the flag-off path is byte-for-byte today's UI); flip
the default; soak; delete the tab machinery. Each step ends with a
build-verification and a rollback note.

> **Build verification (every step):** `swift build -c release` from
> `~/MeetingScribeRefactor` (warnings OK, errors block). For UI-behavioral steps,
> `make install` and click into a past, a live (record 10s + stop), and an
> upcoming meeting with the flag on and off.
> **Rollback (every step unless noted):** the flag-off path is unchanged, so a bad
> step is reverted by leaving `meetingCanvasV2 = false`; git-revert the step's
> commit.

### Step 0 — Confirm `MSSection` + tokens (no code).

`MSSection` (`MSComponents.swift:224`), `MSSectionHeader` (`:124`),
`MSInlineButton` (`:174`), `msMenuButtonChrome` (`:202`), `MSEmptyState` (`:372`),
`MSSkeleton` (`:346`) already exist (Phase F merged). `NDS.sectionLabel` (`:168`),
`NDS.spaceSM` (`:238`), `NDS.cardRadius` (`:29`), `NDS.sidebarBg` (`:86`),
`NDS.splitPaneTopInset` (`:20`) confirmed. No edits.
**Verify:** `swift build -c release` (baseline green).

### Step 1 — Flag + canvas scaffold (flag-off identical).

**Files:** `UnifiedMeetingDetail.swift`.
**Change:** add `@AppStorage("meetingCanvasV2") var canvasV2 = false`. In `body`,
replace the `Group { switch tab … }` block with:

```swift
if canvasV2 { canvasBody } else { tabbedBody }
```

where `tabbedBody` is the exact `Group { switch tab … }.frame(...)` extracted
verbatim, and `canvasBody` initially just renders today's `combinedNotesBody`
inside the new `GeometryReader`/`VStack` shell (no `ScrollView` yet — just proves
the shell compiles and the editor still works at bounded height). Keep
`tabPicker` rendered only when `!canvasV2`.

```swift
@ViewBuilder private var canvasBody: some View {
    GeometryReader { geo in
        VStack(spacing: 0) { combinedNotesBody }   // placeholder; bounded later
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
```

**Verify:** flag-off → identical to today; flag-on → notes canvas renders, editor
typeable (confirms C-A shell). **Risk:** none flag-off. **Rollback:** flag default
false.

### Step 2 — Canvas chrome split: ScrollView (top group) vs bottom group.

**Files:** `UnifiedMeetingDetail.swift`.
**Change:** in `canvasBody`, lay out the two groups per §4.1 (empty `ScrollView`
with a `ScrollViewReader` over a `VStack` for the top group; an empty `VStack` for
the bottom group; a `Divider().overlay(NDS.divider)` between). Define a
`SectionAnchor` enum (`outcomes, summary, transcript`) for `scrollTo`. Define
`contentMaxWidth = 760` (matches `actionsBody:316`). No sections wired yet.
**Verify:** flag-on shows empty scaffold; build green. **Risk:** layout only.

### Step 3 — Outcomes section (the §P2 merge).

**Files:** `UnifiedMeetingDetail.swift` (new `outcomesSection`),
`MeetingActionRow.swift` (add owner person-jump).
**Change:** build `outcomesSection` as an `MSSection("Outcomes", systemImage:
"checklist", count: items.count, persistenceKey: "meeting.outcomes",
defaultExpanded: <mode/content rule>)`:
- content: `ForEach(items) { MeetingActionRow(item:, store: manager.actionItems,
  meeting: m) }` + decisions rows (from `outcomesStrip:220`) + "Add action item"
  (from `actionsBody:306`).
- trailing: triage pill + "Add all N → Tasks" + "→ Tasks inbox" bridge (§5.2).
- empty: `MSEmptyState` (§5.4) for `.past`; section omitted for `.upcoming`.
- Add `router.openPerson` to `MeetingActionRow.ownerMenu` label (lift from
  `InlineActionItemRow:613`).
Tag it `.id(SectionAnchor.outcomes)`. Add to the top `ScrollView`.
**Verify:** create/toggle/assign/due/confirm an item; triage pill + "Add all"
work; matches `actionsBody` behavior. **Risk:** medium — owner-jump edit touches a
shared row. **Rollback:** flag-off unaffected; revert `MeetingActionRow` hunk
separately if needed.

### Step 4 — Highlights section.

**Files:** `UnifiedMeetingDetail.swift`.
**Change:** wrap `highlightsStrip`'s content (`MeetingSummaryTab.swift:154-190`)
in `MSSection("Highlights", systemImage: "flag.fill", persistenceKey:
"meeting.highlights")`. **Do not** wire the chip `tab = .transcript` yet (Step 8).
Section omitted when no marks. Add to top `ScrollView`.
**Verify:** marks render as chips; section hidden when none. **Risk:** low.

### Step 5 — Notes section (bounded editor + grabber, C-A).

**Files:** `UnifiedMeetingDetail.swift`, reuse `MeetingNotesTab.swift`.
**Change:** build `notesSection` in the **bottom group** (outside the top
`ScrollView`). Reuse `currentNotesEditor` / `notesEditor`
(`MeetingNotesTab.swift:7,20`) but place `RichMarkdownEditor` at
`.frame(height: notesPaneHeight)` and add the drag grabber (§4.5).
`@AppStorage("meeting.notes.height")`. Keep "Push to-dos → Tasks"
(`MeetingNotesTab.swift:32`) in the section trailing. For recurring+priors, keep
the `previousCallsSidebar` split inside the bounded frame.
Wrap in `MSSection("Your notes", systemImage: "doc.text", persistenceKey:
"meeting.notes", defaultExpanded: true)`.
**Verify (critical for C-A):** type a long note (50+ lines); editor scrolls
internally, page does **not** grow unbounded; grabber resizes; autosave fires
(`scheduleNoteSave`/`flushNoteSave` still wired via `.onChange(noteDraft)`).
**Risk:** high (the constraint). **Rollback:** flag-off.

### Step 6 — Summary section (+ generating/failed unification, §P7).

**Files:** `UnifiedMeetingDetail.swift`, reuse `MeetingSummaryTab.swift`.
**Change:** build `summarySection` for `.past` in the top `ScrollView`. Body:
- `hasRealSummary` (`:57`) → read-only `MarkdownEditor` at bounded height (§4.4) +
  `SummaryEditByAsking` (`:741`) + `SummaryFeedbackRow` (`:683`).
- else `isSummaryGenerating` (`:63`) → `summaryGeneratingBanner` (`:70`).
- else `bodyLoaded && !transcript.isEmpty` → `summaryFailedBanner` (`:91`).
- else `!bodyLoaded` → `MSSkeleton(lines: 4)`.
- else (loaded, empty) → section omitted.
Trailing: `copyMenu` (`:300`) + `followUpButton` (`:439`). Hidden for
live/upcoming. Tag `.id(SectionAnchor.summary)`. **Pick the canvas banners
(`summaryGeneratingBanner`/`summaryFailedBanner`) as the single source of truth**;
the legacy `pastSummaryBody`/`emptySummaryView` are slated for deletion (Step 10).
`defaultExpanded: true` for `.past`.
**Verify:** past meeting w/ summary expanded by default (no 300 ms race, §P3);
generating shows banner+tokens; engine-off shows Generate retry; edit-by-asking +
👍/👎 work; copy menu works. **Risk:** medium. **Rollback:** flag-off.

### Step 7 — Transcript section (lazy + mode-multiplex, C-B/C-C).

**Files:** `UnifiedMeetingDetail.swift`, reuse `MeetingTranscriptTab.swift`.
**Change:** build `transcriptSection` in the **bottom group**.
- Title via `transcriptSectionTitle` (§C-C); icon `text.alignleft`.
- `defaultExpanded`: `.past` → false; `.live`/`.upcoming` → true.
- Lazy mount with `transcriptEverExpanded` latch (§C-B); body is the existing
  `transcriptBody` switch, but `TranscriptSyncView` / `LiveTranscriptScroll` /
  `PreMeetingBriefView` each given a bounded `.frame(height:)` via geo.
- `.past` empty → section omitted; `!bodyLoaded` → `MSSkeleton(lines: 8)`.
- persistenceKey `meeting.transcript`. Tag `.id(SectionAnchor.transcript)`.
- Pass the shared `audioController` (C-D) unchanged.
**Verify:** past collapsed by default, expands + parses only on first open
(confirm no parse on meeting open via a temporary log, then remove); timestamp
seek still drives `audioBar`; live transcript auto-scrolls; upcoming shows brief.
**Risk:** high (perf + mounting). **Rollback:** flag-off.

### Step 8 — Ask AI section + rewire teleports to scroll-to-anchor (§P4).

**Files:** `UnifiedMeetingDetail.swift`, `MeetingChatTab.swift` (no logic change),
`MeetingSummaryTab.swift` (highlights chip), `MeetingTranscriptTab.swift`
(`consumeTranscriptQuery`).
**Change:**
- `chatSection`: `MSSection("Ask AI", systemImage: "bubble.left.and.sparkles",
  persistenceKey: "meeting.chat", defaultExpanded: false)` wrapping `chatBody` at
  bounded height; lazy-mounted like transcript. Bottom group, last.
- Rewire `highlightsStrip` chip action: instead of `tab = .transcript`, call a new
  `revealTranscript(seedSearch:)` that sets `transcriptExpanded = true`, sets
  `transcriptSearchSeed`, and `proxy.scrollTo(.transcript)`.
- Rewire `consumeTranscriptQuery` (`:55`): same `revealTranscript` instead of `tab
  = .transcript` (keep clearing `router.pendingTranscriptQuery`). Guard the new
  path behind `canvasV2` so flag-off still does `tab = .transcript`.
**Verify:** highlight chip expands+scrolls to transcript with the moment searched;
search-hit deep-link expands+scrolls; Ask AI lazy-mounts. **Risk:** medium
(shared `proxy` must be reachable — hoist `ScrollViewReader`/proxy or use a
`@State` pending-scroll target consumed by `.onChange`). **Rollback:** flag-off
paths retain `tab = …`.

### Step 9 — Related & linked section + reviewBanner rewire; flip the flag.

**Files:** `UnifiedMeetingDetail.swift`, reuse
`relatedMeetingsStrip`/`backlinksPanel`.
**Change:**
- `relatedSection`: `MSSection("Related & linked", systemImage: "link",
  persistenceKey: "meeting.related")` merging `relatedMeetingsStrip`
  (`MeetingSummaryTab.swift:123`) + `backlinksPanel` (`MeetingNotesTab.swift:161`).
  Hidden when both empty. Top `ScrollView`, last.
- Rewire `reviewBanner.onReviewTasks` (`UnifiedMeetingDetail.swift:139`): under
  `canvasV2`, expand Outcomes + `scrollTo(.outcomes)` instead of `tab = .actions`.
- Move `reviewBanner` to render under the header in `canvasBody` (chrome).
- **Flip `@AppStorage("meetingCanvasV2")` default to `true`.**
**Verify:** full soak — past/live/upcoming, recurring, no-transcript, engine-off;
all anchors scroll; everything reachable without tabs. Keep the flag so a regress
can flip back to `false`. **Risk:** this is the cutover. **Rollback:** set default
`false`.

### Step 10 — Cleanup: delete the tab machinery.

**Files:** all five.
**Only after Step 9 has soaked.** Remove the flag and the `tabbedBody`/flag
branch, then delete every now-dead symbol:

| Symbol | File | Reason |
|---|---|---|
| `enum DetailTab` | `MeetingTranscriptTab.swift:172` | no tabs |
| `@State var tab` | `UnifiedMeetingDetail.swift:32` | no tabs |
| `@State var hasAppliedTabDefault` | `:37` | no tab guessing |
| `@State var summaryExpanded` | `:34` | now `MSSection` persistence |
| `func applySmartTabDefault()` | `:427` | §P3 deleted |
| `var tabPicker` | `:254` | no tabs |
| `var actionsBody` | `:277` | merged into Outcomes |
| `func placeholder(...)` | `:321` | replaced by `MSEmptyState` |
| `var combinedNotesBody` | `MeetingSummaryTab.swift:11` | superseded by canvas sections |
| `var outcomesStrip` | `:195` | merged into Outcomes |
| `var summaryBody` / `pastSummaryBody` | `:277` / `:335` | legacy Summary tab |
| `var emptySummaryView` | `:400` | banners are the single source (§P7) |
| `func actionItemsSection(_:)` | `:472` | §P2 third render |
| `struct InlineActionItemRow` | `:569` | replaced by `MeetingActionRow` |
| `@AppStorage var meetingCanvasV2` + branch | `UnifiedMeetingDetail.swift` | cutover complete |

Keep: `summaryDisclosure`'s logic folds into `summarySection`; `highlightsStrip`,
`relatedMeetingsStrip`, `summaryGeneratingBanner`, `summaryFailedBanner`,
`SummaryEditByAsking`, `SummaryFeedbackRow`, `copyMenu`, `followUpButton`,
`currentNotesEditor`, `transcriptBody`, `chatBody`, `MeetingActionRow`,
`backlinksPanel`, the entire header file, `MarkdownEditor.swift` — all reused.
**Verify:** `swift build -c release` green with zero references to deleted
symbols (grep each name to confirm no remaining call sites). Click-test all three
modes once more. **Risk:** dead-code removal; if a delete breaks the build, the
grep missed a caller — restore that one symbol. **Rollback:** revert the cleanup
commit (canvas still works; only dead code returns).

---

## 7. Edge cases & testing

| Case | Expected | Where it's handled |
|---|---|---|
| **Past, no summary, has transcript** (engine was off) | `summaryFailedBanner` with "Generate summary" retry; Summary section expanded showing the banner, not a dead pane | Step 6 branch order |
| **Past, summary generating / streaming** | `summaryGeneratingBanner` with spinner + live tokens (capped height); reloads when `transcribingMeetingIDs` drops the id (`:182`) | Step 6 |
| **Past, no transcript at all** | Transcript section **omitted** (no empty husk); Summary section likewise omitted; Notes fills | C-C guard, Step 7 |
| **Cold open (cache miss)** | `!bodyLoaded` → `MSSkeleton` in Summary (4 lines) + Transcript (8 lines), never a false "No transcript/summary" | `bodyLoaded` (`:54`), Steps 6/7 |
| **Recurring series** | Notes section keeps `previousCallsSidebar` split inside its bounded frame; series spine + `RecurringChip` stay in header; prior-occurrence notes read-only | Step 5, header unchanged |
| **Live recording** | Notes + Live transcript both expanded; Summary/Outcomes hidden; status banner + level meter in header; live transcript auto-scrolls to bottom | C-C, header `statusBanner` |
| **Upcoming** | Brief expanded (no more hidden "Brief" tab, §P5); Notes available; all past-only sections hidden; primary CTA "Join & Record"/"Record" | C-C, header `primaryCTA` |
| **Ollama / summary engine down** | Summary section shows engine-off banner + Generate; `SummaryEditByAsking` gated by `manager.ollamaReachable` (already, `:373`); Ask AI degrades per `ChatPanel` | Step 6 |
| **Reduce Motion** | `MSSection` toggle already gates animation (`MSComponents.swift:263`); `scrollTo` should use `NDS.motion(..., reduce:)`; `MSSkeleton` already drops shimmer (`:362`) | Steps 2/8 |
| **Narrow / short window** | `contentMaxWidth = 760` caps line length; bounded heights are `max(floor, h*frac)` so panes stay usable at small `h`; header stays compact (§P6) | §4.4 |
| **Very long transcript** | Lazy mount (C-B) defers parse to first expand; `TranscriptSyncView`'s own `LazyVStack` virtualizes rows; bounded frame clips | Step 7 |
| **Long notes** | Editor self-scrolls inside its bounded frame; page never grows unbounded (the C-A acceptance test) | Step 5 |
| **Audio present, transcript collapsed, playing** | `audioController` is `@StateObject` on the parent, outlives the collapsed section; transport bar still controls it; re-expanding re-attaches seek | C-D |
| **Highlight chip / search deep-link** | Expands Transcript + scrolls to it + seeds search to land near the moment (no remount, no lost scroll, §P4) | Step 8 |
| **Switch meetings mid-edit** | `flushNoteSave` on disappear + `bodyLoadTask.cancel()` on switch unchanged; section expand states persist per `MSSection` key (global, not per-meeting — acceptable: they encode *kind* preference, not per-meeting state) | lifecycle unchanged |

### 7.1 Acceptance tests (manual, per cutover)

1. **C-A regression:** past meeting, paste 200 lines into notes → notes pane
   scrolls internally; Summary/Outcomes above remain fixed; no runaway height.
2. **C-B regression:** open 10 past meetings in a row → no transcript parse fires
   until you expand Transcript (temporary instrumentation, removed before merge).
3. **§P2:** an action item edited in Outcomes is the *only* place it appears; no
   second stale copy.
4. **§P3:** open the same past meeting 5×; Summary is expanded every time
   (deterministic, no flicker).
5. **§P4:** click a highlight → transcript expands and scrolls to the moment;
   scroll back up → Outcomes/Summary still where you left them.
6. **§P5:** upcoming meeting shows the brief immediately, no tab to discover.
7. **§P7:** kill Ollama, finish a recording → one consistent engine-off banner
   with a working Generate retry.
