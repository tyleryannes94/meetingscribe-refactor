# UX Redesign — Claude Code Build Prompts (2026-06)

*Paste-and-build prompts, one per improvement, ordered by priority. Each is self-contained: scope, files, the change, and a verification step. Pairs with [`MASTER.md`](MASTER.md) and the per-area docs `01`–`05`. House rules for every prompt: build with `swift build -c release` and confirm **`Build complete!` / exit 0 before merging**; keep edits minimal and match surrounding style; after a green build, `make install`.*

---

## P0-1 — Merge the meeting Notes + Transcript tabs into one "Meeting" canvas

> In `UnifiedMeetingDetail.swift`, `MeetingSummaryTab.swift`, and `MeetingTranscriptTab.swift`, reduce the meeting-detail tabs from 4 (Notes/Actions/Transcript/Ask AI) to 3 by merging Notes + Transcript into a single scrolling **"Meeting"** tab: outcomes strip → highlights → AI summary (full height) → your notes editor → transcript → related-meetings strip. **Remove the hard-coded `maxHeight: 320` on the summary** (`MeetingSummaryTab.swift` ~line 170) and the nested `ScrollView` around the summary editor so the whole canvas scrolls as one (fixes choppy scrolling). Keep **Actions** and **Ask AI** as separate tabs. Update the `MeetingTab` enum + its label/switch sites. Verify build green; `make install`.

## P0-2 — One persistent, context-aware AI assistant (kill the ephemeral per-meeting chat)

> Consolidate the three chat surfaces onto the single app-wide `chatSession`. (1) In `UnifiedMeetingDetail.swift` delete `@StateObject var meetingChat = ChatSession()` (~line 96) and add `@EnvironmentObject var chatSession: ChatSession`; in `MeetingChatTab.swift` change the `ChatPanel(session: meetingChat …)` to `session: chatSession` and call `chatSession.setContext(chatContext(for: m))` on appear so the shared assistant is meeting-aware (messages no longer vanish on navigation). (2) In `PersonDetailView.swift` personChatColumn, change the header title "Ask AI about <Name>" to just "Chat" (context is already set via `updateChatContext()`). (3) Unify capability discovery: have the meeting + person chats use categorized `capabilitySections` (reuse `ChatSidebar.capabilitySections()` or a meeting-specific variant) instead of flat `examplePrompts`. (4) In `ChatPanel.swift` make the "What can I ask?" `DisclosureGroup`s collapsed by default (only first expanded) to de-clutter the empty state. Verify build green; `make install`.

## P0-3 — Reliable auto post-meeting summary (retry + visible state)

> Today the post-meeting summary only generates when `transcribeNow(regenerateSummary:true)` runs and fails silently if Ollama was down. In `MeetingPipelineController.swift` add a published `summaryGeneratingIDs: Set<String>` and ensure summary generation is triggered automatically when transcription completes; on Ollama failure, auto-retry with backoff (max 3). In `MeetingSummaryTab.swift` / `UnifiedMeetingDetail.swift`, show "Generating summary…" (gated on the new state) instead of the "No summary yet" empty state, and on genuine failure show a clear "The summary engine wasn't running — Generate now" button. Verify build green; `make install`.

## P0-4 — Fix the engagement signal (count texts/SMS, not just meetings)

> The "overdue by N days" insight + `lastInteractionAt` ignore iMessage/SMS recency (it only feeds the strength score), so a person you text daily reads as months overdue. In `PeopleStore.swift` `refreshIMessageSignals`/`recomputeStrength`: when the cached iMessage `lastDate` is more recent than `lastInteractionAt`, bump `lastInteractionAt` to it and persist. In `PersonDetailView.swift` `relationshipInsight` (~lines 553–565), use the more-recent of last-encounter vs last-text as the "last connected" date, and trigger `refreshIMessageSignals()` on profile `onAppear`. Verify the overdue badge + insight now reflect recent texts. Build green; `make install`.

## P0-5 — Inline tag + encounter add on the person view

> Adding a tag currently needs a hidden Menu → popover → alert (4 clicks); copy the **Favorites** pattern instead. In `PersonDetailView.swift` `tagsEditSection` (~1057), replace the Menu with an inline `TextField("Add a tag…")` that creates+adds on Enter (match an existing tag if the name matches, else create). De-duplicate the two "add encounter" affordances (identityPanel ~line 881 "Encounter" + encountersSection header ~1674 "Add") into one clear "Log encounter" button. Build green; `make install`.

## P0-6 — Truncation pass (never silently cut off)

> Across the app, important titles use `.lineLimit(1)` with no tooltip and get silently truncated. Add `.help(<full text>)` (and where space allows, `.lineLimit(2)` / `.truncationMode(.middle)`) at: `ActionItemsTableView.swift:138,175`, `ActionItemsChrome.swift:46,69,90`, `ActionItemsBoardView.swift:127,150`, `MeetingCard.swift:127`, `MeetingsView.swift:674`, `ActionItemsSidebar.swift:241,652`, `TodayView.swift:261`, `DecisionLedgerView.swift:131`. Build green; `make install`.

---

## P1 prompts

### P1-1 — Person-view hierarchy simplification
> In `PersonDetailView.swift`, collapse the identity pane to a compact sticky header (avatar + name/role + one primary CTA + a ⋯ menu holding Edit/Delete/Ask AI); fold low-frequency content below a disclosure. Consider reducing the 6 `PersonTab` cases to 3 (Overview / Meetings / Notes) with the Story timeline folded into Overview. Preserve the recently-fixed button wrapping + tab scrolling. Build green; install.

### P1-2 — Today "calm" pass
> In `TodayView.swift`, increase spacing between major section groups (22 → ~28–32), add hairline dividers between category groups, and group follow-ups + decisions + 1:1s under one "Attention" block to reduce the 14-section scroll. Build green; install.

### P1-3 — NDS spacing standardization
> Replace magic-number paddings with NDS tokens (`spaceSM=8`, `spaceMD=12`, `spaceLG=16`) across `MainWindow.swift` (nav rail), `ActionItemsChrome.swift`, `TodayView.swift`, and unify chip paddings (`NotionChip` vs `MSFilterChip`). No behavior change, spacing rhythm only. Build green; install.

### P1-4 — Window width guards
> Prevent the nav rail from starving the center pane: in `MainWindow.swift` either auto-collapse the 240pt rail below ~580pt window width or set the center pane `minWidth: 360`. Add `maxWidth: ~1200` to over-wide HSplitView detail panes (`PeopleListView`, `QuickNotesView`) for readable measure. Build green; install.

### P1-5 — Pre-meeting brief regenerate + pre-warm
> In `PreMeetingBriefView.swift` add a "Regenerate brief…" button below a synthesized brief, and pre-warm the brief into `BriefCache` ~24h before the meeting start. Build green; install.

### P1-6 — Meeting header de-clutter
> In `MeetingDetailHeader.swift` move the meeting-source picker into the Options menu, collapse attendees >8 behind a "View all attendees (N)" expander, and bump the series-spine font to ~12pt. Build green; install.

---

## P2 prompts (batch as convenient)
> MSPillTabs scroll indicators (`MSComponents.swift` — `showsIndicators: true`); adaptive table columns (`ActionItemsTableView.swift` — `minWidth/maxWidth` instead of fixed); consolidate person message-analysis into one "Analyze" card (`PersonDetailView.swift`); add a context breadcrumb pill above the chat input (`ChatPanel.swift`); visible People sort menu (`PeopleListView.swift`); per-page density tweaks from docs `04`/`05`.
