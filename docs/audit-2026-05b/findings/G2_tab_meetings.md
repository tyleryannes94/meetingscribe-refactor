# G2 — Meetings Tab + Meeting Detail (Senior PM/UX)

Lens: treat the Meetings list + `UnifiedMeetingDetail` as a single fast list/detail surface; every post-open action ≤2 clicks; integrate attendees↔People, action items↔Tasks, decisions↔ledger; keep long transcripts cheap via `MeetingBodyCache`.

## Audit (through my lens)

**What's already built (verified, do NOT re-propose):**
- 2-column `NavigationSplitView` replacing the old accordion (`MeetingsView.swift:53`). Selection owned by `WorkspaceRouter.selectedMeetingID` so Today/search/deep-links/backlinks all land in one detail pane (`MeetingsView.swift:20-27`).
- List/Month toggle, persisted scope pills (`@AppStorage "meetings.scope"`), always-visible search (`MeetingsView.swift:32, 88-148`).
- Cache-backed reload: synchronous cache snapshot for instant first paint + cancellable async disk refresh that won't clobber a newer selection (`UnifiedMeetingDetail.swift:166-226`). `MeetingBodyCache` is a real LRU(64) with mtime freshness, coalesced inflight loads, hot-write patches, and a `prefetch(top 10)` fired at launch (`MeetingScribeApp.swift:216`, `MeetingBodyCache.swift`).
- Attendee chips left-click → open/create Person via router; green dot = already in People (`MeetingDetailHeader.swift:688-738`). Inline action items in Summary with status/title/due/priority editing (`MeetingSummaryTab.swift:137-303`). Backlinks + semantic "Related meetings" panels in Notes (`MeetingNotesTab.swift:126-185`). Smart tab default, follow-up drafting, summary 👍/👎 feedback, Options menu (export/recover/calendar write-back).
- `MarkdownEditor` read-only is already used for transcript/summary (faster than AttributedString) (`MeetingTranscriptTab.swift:180-192`).

**Gaps / friction (the net-new opportunity):**
1. **List rows read disk on every render.** `MeetingListRow` shows only time/title/attendee-count/dot; status dot uses `meeting.health` (cheap), but `MeetingCard.hasFile()` does a synchronous `String(contentsOf:)` per render (`MeetingCard.swift:316-322`) — used in Today, and the pattern invites the same in the list. List rows never call `cachedSummaryPreview` even though the cache exposes it (`MeetingBodyCache.swift:83`). No summary preview line, so users must open a meeting to know what it was about.
2. **`calendarMeetings` recomputed per day-cell.** `dayCell` calls `calendarMeetings.contains{…}` (`MeetingsView.swift:357`) — that dedupe loop over `upcoming+pastMeetings` runs ~42×/month render. O(days×meetings) on every grid paint.
3. **Tab content fully torn down on switch.** The detail uses `.id(m.id)` (`MeetingsView.swift:74`) and a `switch tab` that builds only the active tab (`UnifiedMeetingDetail.swift:89-96`). Switching tabs re-instantiates `TranscriptSyncView`/`MarkdownEditor`; for a long transcript that's a re-parse hitch every time you bounce Summary↔Transcript.
4. **No transcript virtualization.** `TranscriptSyncView(rawTranscript:)` gets the whole string; a 1–2 hr call (hundreds of KB) renders as one block. No lazy/paged rendering.
5. **Decisions ledger is invisible in meeting detail.** A decisions/commitments ledger exists app-wide, but the detail surfaces only action items — no "Decisions from this meeting" section, no capture affordance. Decisions↔ledger integration is missing here.
6. **Action items shown only in Summary tab.** If a meeting has no summary, the inline action-items section never renders (`MeetingSummaryTab.swift:59-61` is inside `pastSummaryBody` after the summary-exists branch). Action items can exist without a summary.
7. **Click counts.** Open meeting = 1 click (good). But: see action items = open → already on Summary (0–1); see *decisions* = not reachable; re-transcribe = Options menu → item (2); jump to a person = attendee chip (1, good). Reaching the *full* Tasks view filtered to this meeting = not offered (must leave tab, re-filter). Export = Options → Export → format (3).
8. **Header is dense and non-collapsing.** Title + meta + chips + attendees scroll-row + conference URL + TagPicker + action bar + banner all stack (`MeetingDetailHeader.swift:8-80`) — eats vertical space above the fold before any content; no way to collapse it for reading a long transcript.

## NET-NEW recommendations

**TM-1 — Persist `MeetingBodyCache` summaries to a disk-backed preview index (cold-start first-open).**
What/why: Today the cache is in-memory only; first open of any meeting after launch (beyond the prefetched 10) pays a disk read, and list rows have no preview. Add a tiny on-disk `meeting-previews.json` (id → {summaryFirstLine, hasTranscript, attendeeCount, mtime}) written when bodies load/patch, loaded synchronously at launch into the cache. List rows render a one-line summary preview immediately.
UX impact: list becomes scannable without opening (saves the "open to remember what this was" click on most rows); first-open feels instant.
Perf/stability: replaces per-render disk reads with one small JSON read at launch; bounded (one line/meeting); mtime-gated so stale rows self-heal. Reduces main-thread I/O. Effort: M. Impact: High. Deps: extends `MeetingBodyCache`.

**TM-2 — Route all list/card status through cache, kill `MeetingCard.hasFile()` sync reads.**
What/why: Replace `hasFile("transcript.md")` (`MeetingCard.swift:316`) and any list status with `cachedSummaryPreview`/a cached `hasTranscript` flag from TM-1. No view-body disk I/O.
UX impact: smoother scrolling, no hitch when many cards are on screen. Perf/stability: eliminates synchronous `String(contentsOf:)` on the render path — the single biggest scroll-jank/crash-on-huge-file risk in the list. Effort: S. Impact: High. Deps: TM-1.

**TM-3 — Memoize month-grid meeting lookup.**
What/why: Precompute `[startOfDay: count]` once per `(monthCursor, search)` change instead of `calendarMeetings.contains` per cell (`MeetingsView.swift:357`). Store in `@State`, rebuild in `.onChange`.
UX impact: invisible (correctness identical). Perf/stability: month render drops from O(42×N) to O(42) lookups; matters as meeting count grows. Effort: S. Impact: Med. Deps: none.

**TM-4 — Add a "Decisions" section to meeting detail + one-click capture into the ledger.**
What/why: Mirror the action-items section: a Decisions block (in Summary, and rendered even when summary is empty) listing decisions linked to this meeting, with an inline "+ Log decision" that writes to the decisions ledger pre-linked to `meeting.id`. Auto-extract candidates from the summary when available.
UX impact: closes the decisions↔ledger gap; logging a decision goes from "leave tab, open ledger, link manually" (4+ clicks) to 1 click. Perf/stability: reads are cheap (ledger is indexed by meeting id like action items); no new heavy I/O. Effort: M. Impact: High. Deps: ledger store API.

**TM-5 — Lift action-items + decisions out of the summary-gated branch into an always-present "Outcomes" strip.**
What/why: Move the action-items section (`MeetingSummaryTab.swift:59-61`) and TM-4 decisions out from behind `if summary.isEmpty {} else {}` so they render whenever items/decisions exist, plus an "Open in Tasks (filtered to this meeting)" link routing to the Tasks tab pre-filtered by `meetingID`.
UX impact: action items no longer hidden when summarization failed; full Tasks view for this meeting = 1 click (was: leave tab + manual filter, 3+). Strengthens action-items↔Tasks integration. Perf/stability: pure view reorg, no cost. Effort: S. Impact: High. Deps: Tasks tab accepting a meeting filter param via router.

**TM-6 — Keep rendered tab bodies alive (ZStack + opacity) to kill re-parse on tab switch.**
What/why: Replace the `switch tab` that rebuilds the active body (`UnifiedMeetingDetail.swift:89-96`) with a `ZStack` of the four bodies gated by `.opacity`/`allowsHitTesting`, building each lazily on first visit then retaining it. Avoids re-instantiating `MarkdownEditor`/`TranscriptSyncView` on every Summary↔Transcript bounce.
UX impact: instant tab switches, scroll position preserved per tab. Perf/stability: small memory bump (one extra rendered body) traded for no repeated markdown re-parse; cap retained tabs to the ones visited. Effort: M. Impact: Med. Deps: none.

**TM-7 — Virtualize/paginate long transcripts.**
What/why: Long calls hand the entire transcript string to `TranscriptSyncView` (`MeetingTranscriptTab.swift:38`). Split into segments (already speaker/timestamp-structured) and render in a `LazyVStack` so only on-screen segments materialize; for plain-prose fallback, chunk by paragraph with a "load more"/windowed range. Add a transcript search/jump that scrolls to a segment.
UX impact: opening a 2-hour transcript is instant; in-transcript search adds find-in-call (new capability). Perf/stability: caps memory + layout cost to the viewport regardless of length — the main crash/hang risk for marathon meetings. Effort: L. Impact: High. Deps: segment parser (partly exists in TranscriptSyncView).

**TM-8 — Collapsible "compact header" for reading mode.**
What/why: Add a disclosure that collapses attendees-row/conference URL/TagPicker/chip-row into a single line (title + time + a "details" chevron) (`MeetingDetailHeader.swift:8-80`), remembered via `@AppStorage`.
UX impact: more transcript/summary above the fold; one click toggles. Perf/stability: fewer views laid out when collapsed; negligible cost. Effort: S. Impact: Med. Deps: none.

**TM-9 — Inline attendee → Person hover card + bulk "Add all to People".**
What/why: Attendee chips open/create a Person (good), but mass-adding a 10-person external meeting is 10 clicks. Add a header "Add all attendees to People" action, and a hover preview (last met, open tasks) using the People relationship data already loaded for `relatedMeetings`.
UX impact: 10 clicks → 1 for onboarding a meeting's attendees; richer attendees↔People link. Perf/stability: hover card lazy-loads from `PeopleStore` (in-memory); no disk. Effort: M. Impact: Med. Deps: PeopleStore lookup.

**TM-10 — Persist last-active tab per meeting + global keyboard tab switching.**
What/why: `applySmartTabDefault` picks a default once (`UnifiedMeetingDetail.swift:252`) but reopening a meeting forgets which tab you were reading. Store last tab per meeting id (or globally) and bind ⌘1–4 to tabs.
UX impact: returning to a meeting lands where you left off (0 extra clicks); power users switch tabs without the mouse. Perf/stability: trivial `@AppStorage`/dictionary; combine with TM-6 so the remembered tab is already rendered. Effort: S. Impact: Low–Med. Deps: TM-6 (nice-to-have).

## Top 3 picks
1. **TM-1 (+TM-2)** — disk-backed preview index feeding list rows and killing per-render `hasFile()` reads. **Phase 1** (foundational perf/infra; biggest first-open + scroll win, scannable list).
2. **TM-7** — transcript virtualization + in-call search. **Phase 2** (the core stability fix for long meetings; unlocks find-in-transcript).
3. **TM-4 + TM-5** — decisions section + always-present Outcomes strip with 1-click jump to filtered Tasks. **Phase 3** (highest cross-tab integration value: action items↔Tasks and decisions↔ledger both land here).

TM-6 (tab retention) and TM-8/TM-10 (compact header, remembered tab, ⌘1–4) slot into **Phase 4** as polish.
