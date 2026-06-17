# UX Audit — Today / Tasks / Decisions / Voice Notes / Meetings list

*Agent: pages designer. 23 findings; spacing/density/truncation focused.*

## P0
- **TodayView overwhelming** — the feed stacks 14+ sections at 22pt spacing (`TodayView.swift:131-175`). → Bigger spacing between section *groups* (28-32), hairline dividers, group follow-ups+decisions+1:1s under an "Attention" block.
- **ActionItemsListView cramped section headers** (`:35-39,60`) — HStack spacing 6 + vertical padding 2 feels pinched. → spacing 8-10, vertical padding 6.
- **Waiting-On rows dense** (`ActionItemsSidebar.swift:647-676`) — 0pt VStack + 5pt padding; Nudge replaces age with no room. → spacing 2, vertical padding 8.
- **MeetingsView list rows overflow at 300pt** (`MeetingsView.swift:644-713,694`) — title+meta truncate silently. → min pane 380, meta spacing 8, allow attendee line to wrap.
- **DecisionLedger cards dense** (`DecisionLedgerView.swift:118-146`) — 12pt padding, no line spacing. → 14-16pt padding, `.lineSpacing(2)`, 4pt gap before metadata.

## P1
- Today follow-up rows: 6pt vertical padding → 10; "Mark sent" should be regular size (`TodayView.swift:432-453`).
- ActionItems keyboard popovers: fixed 220pt → `minWidth 240, maxWidth 340` (`ActionItemsListView.swift:170-211`).
- QuickNotes 3-pane has no min widths → `minWidth: 300` per pane; wrap pane-header buttons on narrow (`QuickNotesView.swift:359-516`).
- Initiative tree indentation 13pt too tight → 16-18; node header spacing 3 → 6 (`ActionItemsSidebar.swift:820-965`).
- MeetingCard title `lineLimit(1)` no tooltip → add `.help(displayTitle)` (`MeetingCard.swift:126-128`).

## P2
- Today header badge clustering; Tasks bulk toolbar (7+ menus) squished → vertical padding 12, wrap on narrow; Meetings filter chips need vertical padding; decision metadata row spacing 8 → 10; section-header chevron alignment.

## General (cross-page)
- **Inconsistent padding** — define/use a single spacing scale (`xs4/sm8/md12/lg16/xl20/xxl24`) and replace literals.
- **Min click-target heights** — add `.frame(minHeight: 40)` to clickable sidebar rows.
- **Truncation without tooltips** — `TodayView:261`, `ActionItemsSidebar:241,652`, `MeetingsView:674` → add `.help()`.

**Summary:** 23 issues — 7 P0, 7 P1, 9 P2. Not broken, but the density + silent truncation + inconsistent spacing read as "cramped / unpolished."
