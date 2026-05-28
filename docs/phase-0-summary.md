# Phase 0 — Foundation

## What was built/changed

Foundational cleanup so the codebase builds from a fresh clone and the big UI
files are navigable.

1. **Fixed a build-breaking `.gitignore` trap.** `**/QuickNotes/` was
   case-insensitively matching the **source** directory
   `Sources/MeetingScribe/QuickNotes/` on APFS — the exact trap the file's own
   comments warn about for `**/audio/`. This silently kept
   `QuickNotesController.swift` out of git, so fresh clones and CI failed to
   compile (`cannot find 'QuickNotesController' in scope`). Tightened the rule
   and committed the previously-untracked file.
2. **Split two "god object" view files** by semantic domain, leaving each
   original as a slim coordinator.
3. **Wired CI tests** — added a `test` job (`swift test`) that `release` now
   depends on.

> **Note:** `ChatTools.swift` (0-B1 in the plan) was already split in a prior
> commit (it's 89 lines now), and Sparkle's `SUPublicEDKey` is already a real
> key with `SUFeedURL` pointing at this repo's `releases/` feed (which the
> release CI requires). So 0-A and 0-B1 needed no work.

## Files created / modified

**Created (ActionItemsView split — 2,518 → 160-line coordinator):**
- `Sources/MeetingScribe/UI/ActionItemsListView.swift`
- `Sources/MeetingScribe/UI/ActionItemsTableView.swift`
- `Sources/MeetingScribe/UI/ActionItemsBoardView.swift`
- `Sources/MeetingScribe/UI/ActionItemsChrome.swift` (header/toolbar/dashboard/project-page)
- `Sources/MeetingScribe/UI/ActionItemsSidebar.swift` (ProjectRail + tree nodes)
- `Sources/MeetingScribe/UI/ActionItemsProjectPage.swift`
- `Sources/MeetingScribe/UI/TaskRowView.swift` (ActionItemRow)

**Created (UnifiedMeetingDetail split — 983 → 238-line container):**
- `Sources/MeetingScribe/UI/MeetingDetailHeader.swift`
- `Sources/MeetingScribe/UI/MeetingTranscriptTab.swift` (+ LiveTranscriptScroll, DetailTab, MarkdownText)
- `Sources/MeetingScribe/UI/MeetingNotesTab.swift`
- `Sources/MeetingScribe/UI/MeetingSummaryTab.swift`
- `Sources/MeetingScribe/UI/MeetingChatTab.swift`

**Modified:**
- `.gitignore` — removed the source-colliding `**/QuickNotes/`, added `**/polished.md`
- `Sources/MeetingScribe/QuickNotes/QuickNotesController.swift` — now tracked
- `Sources/MeetingScribe/UI/ActionItemsView.swift` — now a 160-line coordinator
- `Sources/MeetingScribe/UI/UnifiedMeetingDetail.swift` — now a 238-line container
- `.github/workflows/release.yml` — added `test` job, `release` `needs: [test]`

## How to use

No user-facing features here — this is developer-facing structure. The split
files use Swift `extension`s so the type surface is unchanged; to find code,
follow the `// MARK:` sections, now one-per-file.

## Notes for the next developer

- The split moved `private` members to internal (Swift `private` is file-scoped,
  so cross-file extensions can't see it). This is intentional and safe within
  the single module.
- Two extra files beyond the plan's named list (`ActionItemsChrome.swift`,
  `ActionItemsProjectPage.swift`, `MeetingChatTab.swift`) house the
  header/toolbar/dashboard/project-page/chat content that didn't fit the
  table/board/list/row/sidebar buckets.
- `swift test` can't run on machines with only Command Line Tools (no XCTest);
  it runs on the `macos-14` CI runner. Use `swift build` locally.
