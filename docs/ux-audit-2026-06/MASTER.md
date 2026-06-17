# MeetingScribe — UX Audit & Redesign Master Plan (2026-06)

*Synthesized from a 5-agent PM/designer audit (meeting view, person view, AI chat, Today/Tasks/Decisions, global nav/spacing). Per-area detail in `01`–`05`. Build prompts in [`BUILD-PROMPTS.md`](BUILD-PROMPTS.md). Goal: make the app easier to use — less cramped, fewer tabs, one consistent assistant, correct engagement signals.*

## The 6 headline problems (user-reported + audit-confirmed)

1. **Meeting view is cramped & over-tabbed.** 4 tabs (Notes/Actions/Transcript/Ask AI); Notes+Transcript are one logical canvas split apart; the summary is locked in a `maxHeight: 320` box that crushes long recaps. → **Merge into one scrolling "Meeting" canvas; 4 tabs → 3.**
2. **Post-meeting summary isn't reliably auto-generated** (fails silently if Ollama was down; user must manually tap "Generate"). Pre-meeting brief *does* auto-gen but has no retry. → **Make summary auto-gen mandatory + retry + visible "generating" state.**
3. **Person view is overwhelming** (7 stacked identity-pane sections + 6 tabs) and **hard to use** — adding a tag is 4 clicks behind a hidden menu; two confusing "add encounter" buttons. → **Simplify hierarchy; inline tag + encounter add; fewer tabs.**
4. **Engagement signal is wrong:** `lastInteractionAt` (and the "overdue by N days" insight) only counts meetings/encounters — **iMessage/SMS recency is ignored** (it only feeds the strength score). A person you text daily reads as "90 days overdue." → **Fold iMessage recency into `lastInteractionAt` and the overdue/insight logic.**
5. **The AI chat is inconsistent & fragmented.** Three surfaces (Today sidebar, per-meeting, per-person); the **per-meeting chat is ephemeral and loses messages**; capability discovery differs per surface; the empty-state "What can I ask?" panel (4 groups + 12 prompts) is the "overwhelming navbar." → **One persistent, context-aware assistant everywhere; collapse the panel.**
6. **Components get cramped / cut off.** `.lineLimit(1)` silently truncates task/meeting titles in tables/boards with no tooltips; magic-number paddings (not NDS tokens); nav rail can starve the center pane on narrow windows; detail panes have no max reading width. → **Truncation tooltips, NDS spacing pass, min/max width guards.**

## Prioritized build roadmap

### P0 — do first (the redesigns the user explicitly called out)
| # | Redesign | Area | Files |
|---|---|---|---|
| P0-1 | **Merge Notes + Transcript into one "Meeting" canvas**; remove `maxHeight: 320` + nested ScrollView | Meeting | `UnifiedMeetingDetail.swift`, `MeetingSummaryTab.swift`, `MeetingTranscriptTab.swift` |
| P0-2 | **One app-wide AI assistant**: kill the ephemeral per-meeting `ChatSession`; meeting/person set context on the shared session; unify capability discovery; collapse the empty-state panel | Chat | `UnifiedMeetingDetail.swift:96`, `MeetingChatTab.swift`, `PersonDetailView.swift` (personChatColumn), `ChatPanel.swift` |
| P0-3 | **Reliable auto post-meeting summary**: track a `summaryGenerating` state, auto-retry on Ollama failure, show "Generating summary…" instead of "No summary yet" | Meeting | `MeetingPipelineController.swift`, `MeetingSummaryTab.swift`, `UnifiedMeetingDetail.swift` |
| P0-4 | **Fix engagement signal**: fold iMessage recency into `lastInteractionAt` + the "overdue"/insight logic (not just the strength score) | Person | `PeopleStore.swift` (`recomputeStrength`/`refreshIMessageSignals`), `PersonDetailView.swift` (`relationshipInsight`) |
| P0-5 | **Inline tag + encounter add** on the person view (TextField like Favorites, not a hidden Menu/popover); de-dupe the two "add encounter" buttons | Person | `PersonDetailView.swift` (tagsEditSection ~1057, identityPanel ~881, encountersSection ~1674) |
| P0-6 | **Truncation pass**: add `.help(fullText)` (or `.lineLimit(2)`) wherever `.lineLimit(1)` hides important titles in tables/boards/cards | Global | `ActionItemsTableView.swift`, `ActionItemsChrome.swift`, `ActionItemsBoardView.swift`, `MeetingCard.swift`, `MeetingsView.swift`, `ActionItemsSidebar.swift` |

### P1 — high-impact polish
- **Person view hierarchy:** collapse identity pane to a sticky header (avatar + name + 1 primary CTA + ⋯ menu); move Edit/Delete/Ask AI into the menu; consider 6 tabs → 3 (Overview / Meetings / Notes, with Story folded into Overview).
- **Today calm pass:** bigger spacing between section groups, hairline dividers, group follow-ups/decisions/1:1s under one "Attention" block.
- **Spacing standardization:** replace magic-number paddings with `NDS.spaceSM/MD/LG`; unify chip paddings.
- **Width guards:** nav rail auto-collapse (or center-pane `minWidth: 360`) on narrow windows; detail panes `maxWidth: ~1200` for reading measure.
- **Pre-meeting brief "Regenerate" button** + pre-warm 24h before start.
- **Meeting header de-clutter:** move source picker into the Options menu; collapse attendees >8 behind "View all"; bigger series-spine font.

### P2 — refinement
Per-page density tweaks (Tasks toolbar, sidebar rows, decision cards), MSPillTabs scroll indicators, adaptive table columns, message-analysis consolidation on person view, context breadcrumb above the chat input, visible People sort menu. (Full list in `01`–`05`.)

## Notes
- Navigation structure is **sound** (7 destinations, sensibly grouped) — no nav re-architecture needed.
- This plan supersedes continued work on the older build phases (per the user's direction); the prior backlog remains in `APP-STATUS-2026-06.md`.
