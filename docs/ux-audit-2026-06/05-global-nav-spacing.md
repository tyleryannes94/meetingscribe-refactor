# UX Audit — Global Navigation, Spacing & Layout Correctness

*Agent: global designer. Scope: `MainWindow.swift`, `NotionDesign.swift` (NDS tokens), `MSComponents.swift`, `ToolbarModel.swift`, HSplitView usages.*

## Navigation: SOUND ✅
7 top-level destinations (`TopLevelSection`, `MainWindow.swift:9-44`) in 2 groups (WORKSPACE: Today/Meetings/People · ORGANIZE: Tasks/Voice Notes/Decisions/Integrations). Clear, sensibly grouped; 7 is the upper limit but acceptable. **No nav re-architecture needed.**

## P0 — breaks "never cramped/cut off"
- **Silent title truncation** (`.lineLimit(1)` + no tooltip): `ActionItemsTableView.swift:138,175`, `ActionItemsChrome.swift:46,69,90`, `ActionItemsBoardView.swift:127,150`. Fixed 140-160pt columns crush titles. → add `.help()` (and `.lineLimit(2)`/`.truncationMode(.middle)`).
- **Nav rail can starve the center pane.** Rail `.frame(width: 240)` (`:191`) + center pane `minWidth: 0` (`:451`) → on <620pt windows tabs become unreadable. → auto-collapse rail below ~580pt OR center pane `minWidth: 360`.

## P1 — spacing consistency
- **Magic-number nav-rail padding** (`MainWindow.swift:144,161,173,189` use 14/10/8/12 — no two rows match). → NDS tokens: outer 16, rows 12, search inset 8.
- **Dashboard rows** `ActionItemsChrome.swift:53,74,94` use 10/7 → `spaceMD/spaceSM` (12/8).
- **TodayView feed** `28/24` magic padding (`:176`) → define `pageHalfPadding` or use a token.
- **Rail resize handle is 6pt** (`ActionItemsView.swift:188`) — hard to grab → widen to 10-12 + `.help("Drag to resize")`.

## P2
- **HSplitView detail panes have no maxWidth** (`PeopleListView.swift:113-114`, `QuickNotesView.swift:20-21`) → prose stretches to full width on big displays. → `maxWidth ~1200`, centered.
- **MSPillTabs `showsIndicators: false`** (`MSComponents.swift:91`) → users don't know tabs scroll on narrow panes. → indicators on, or an overflow chevron.
- **Fixed table columns** (`ActionItemsTableView.swift:7-14`, 140-160pt) brittle for long names/Dynamic Type → adaptive `minWidth/maxWidth` or resizable.

## Spacing offenders summary
~10-15 `.padding(10-14)` (should be 12/16) · ~6-8 `.padding(7-9)` (should be 8) · fixed column widths. **~1hr token-standardization refactor** makes the app feel "designed."

## Top 5 ease-of-use wins
1. Remove `.lineLimit(1)` silent truncation (or add tooltips) — #1 pain.
2. Width guards so the nav rail can't starve the app on small windows.
3. Standardize padding to NDS tokens.
4. MSPillTabs scroll indicators.
5. Adaptive table columns.

**Overall:** not broken, but P0/P1 (~3-4 hrs) would noticeably raise polish + usability.
