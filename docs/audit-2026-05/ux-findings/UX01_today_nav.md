# Today Tab + Global Navigation — Low-Lift UX & Feature Quick-Wins

Senior PM lens on the app shell, the nav rail, tab switching/back behavior, and the Today home — applying the 3-click rule to global nav and Today.

## Lift from V4

- **D1-2 (S)** — Register `meetingscribe://` + `onOpenURL`. The shell already parses `WorkspaceLink` (`MainWindow.swift:379-384`, `routeEntity`) but the OS scheme is unregistered, so notifications/Shortcuts/Spotlight can't deep-link into a tab. Relevant to global nav.
- **D4-2 (M)** — Turn ⌘K into a real command palette. The rail shows a "⌘K" chip (`MainWindow.swift:141-153`) but it only opens `GlobalSearchView` search, not actions. Nav-adjacent.
- **D4-1 (M)** — Single global record toggle + persistent HUD. Today's primary "Record Meeting" button (`TodayView.swift:122-134`) and the toolbar button (`MainWindow.swift:562`) duplicate state with no global hotkey beyond ⌘R menu item.
- **D5-1 (S)** — Reduce-motion pass on the primary screen (Today is the launch tab).

## UX improvements (5)

### UX1-1 — Remove dead `calendarLink`; Today has no path to the full Meetings list
- **Friction:** `calendarLink` is fully built (`TodayView.swift:224-255`) but never rendered in `feed` (`TodayView.swift:50-85`). So from Today there is **no visible link to all past/upcoming meetings** — the user must hit the nav rail. The empty-state copy even references "the Calendar tab" that no longer exists. Reaching the full list = 1 rail click, but the dead code implies a designed-but-dropped affordance.
- **Fix:** Render `calendarLink` at the bottom of the feed (after `todaySection`), update copy from "Calendar tab" → "Meetings". Restores the intended "see everything" exit from Today.
- **Clicks:** N/A (adds a missing affordance; keeps Meetings ≤1 click from Today).
- **Effort:** S.

### UX1-2 — Make ⌘1–⌘5 / nav posts reset the Today detail push (back-state leak)
- **Friction:** Today owns its own `NavigationStack` with a pushed `selectedMeeting` detail (`TodayView.swift:28-39`). Switching tabs via the rail or ⌘1 (`MainWindow.swift:386-389`) only flips `section`; it does **not** clear `selectedMeeting`. Because tabs are kept-alive via opacity (`MainWindow.swift:86-97`), returning to Today lands you back **inside the pushed meeting detail**, not the home feed — a confusing "I pressed Today but I'm on a meeting" moment. Violates the spirit of the 3-click rule (the home is not reliably reachable in 1 click).
- **Fix:** When `section` becomes `.today` from a nav event (or on `meetingScribeNavigate` to `.today`), reset `selectedMeeting = nil`. ~3 lines.
- **Clicks:** Today-home reliably 1 click (was sometimes 2: Today → back).
- **Effort:** S.

### UX1-3 — Nav rail has no active-section keyboard discoverability / shortcut hints
- **Friction:** ⌘1–⌘5 jump to sections (`MeetingScribeApp.swift:75-86`) but the rail items (`NavRailItem`, `MainWindow.swift:474-509`) show no shortcut hint, so the feature is invisible. Only ⌘K is surfaced. New users never learn the fastest nav path.
- **Fix:** Add a trailing `Text("⌘1")…` hint (reuse the muted `NDS.tiny` style already used for the ⌘K chip) on hover/selection, or a `.help()` tooltip per item. No new wiring — the shortcuts exist.
- **Clicks:** unchanged; improves discoverability of the 1-click path.
- **Effort:** S.

### UX1-4 — Meeting opens two different ways from the shell (sheet vs. push) — inconsistent back behavior
- **Friction:** From Today a meeting **pushes** a full-page detail with a system back arrow (`TodayView.swift:259-279`); from global search / deep-link the same meeting opens in a **modal sheet** with a "Done" button (`MainWindow.swift:296`, `meetingSheet:393-410`, fixed 860×680). Same entity, two mental models and two "go back" gestures. (This is the small, surgical slice of V4's D1-1 router — not the whole router.)
- **Fix:** Route search/deep-link meeting opens through the same push as Today (or vice-versa) so back behavior is one thing. Low-lift version: make the sheet path post into Today's `selectedMeeting` instead of `activeSheet = .meeting`.
- **Clicks:** unchanged; removes a back-gesture inconsistency.
- **Effort:** small-M.

### UX1-5 — `asyncAfter(0.05/0.18)` timing hacks for cross-tab routing are fragile
- **Friction:** Routing into a not-yet-built tab relies on sleep-then-post hacks: `openPerson` waits 0.05s (`TodayView.swift:369-375`) and `routeEntity` waits 0.18s after dismissing a sheet (`MainWindow.swift:463-468`). Tabs build lazily on first selection (`MainWindow.swift:88-97`), so a slow first build can drop the notification → the user lands on the right tab but the person/meeting never opens. Intermittent "nothing happened" on first navigation.
- **Fix:** Replace the post-after-delay with a pending-route `@State` the destination view consumes on first appear (e.g. `manager.pendingPersonOpen`), so the action fires deterministically once the tab mounts. Removes both magic delays.
- **Clicks:** unchanged; fixes a flaky 1-click action.
- **Effort:** small-M.

## Feature improvements (5)

### FT1-1 — "Jump to now" / current-time anchoring isn't the issue; add a Today date context line that's actionable
- **What/why:** Today's subtitle (`TodayView.swift:355-364`) summarizes counts ("2 upcoming today · 1 earlier") but the counts aren't clickable. Make the "upcoming today" count tap-scroll to `todaySection` and "earlier today" tap to the past block — micro-nav within a long feed.
- **Value:** Faster orientation on a busy day without scrolling past widgets.
- **Effort:** S. **Dep:** none.

### FT1-2 — Recently-visited entities in the nav rail (or ⌘K)
- **What/why:** There's no "recents" anywhere; every return to a meeting/person is a fresh search or scroll. Add a small "Recent" list (last 3–5 opened entities) at the bottom of the rail or top of `GlobalSearchView`. The routing plumbing (`routeEntity`) already exists — just record the last N opened IDs.
- **Value:** Turns repeat navigation from 3 clicks (tab → scroll → open) into 1.
- **Effort:** small-M. **Dep:** light pairing with D1-2/D4-2.

### FT1-3 — Persist last-opened meeting/scroll so Today restores context
- **What/why:** `section` is persisted (`mainWindow.lastSelectedSection`, `MainWindow.swift:50`) but Today's `selectedMeeting` and scroll are not. Relaunch always dumps you at the top of the feed even if you were mid-review. Persist the last-open meeting ID (open-on-launch optional, behind a setting).
- **Value:** "Pick up where I left off" — meaningful for a daily-driver app.
- **Effort:** S. **Dep:** UX1-2 (shared `selectedMeeting` lifecycle).

### FT1-4 — Empty-Today still shows nothing to *do* beyond Import
- **What/why:** The empty state (`TodayView.swift:286-301`) only offers "Import meeting recording." On a no-meetings day the app has no reason to be open. Add 1–2 contextual nudges already computable: "X action items due today" (NeedsAttentionWidget data) and "Reconnect with N people" (ReconnectView data) as buttons in the empty state.
- **Value:** Today is never a dead end; drives into the two retention surfaces already present.
- **Effort:** S. **Dep:** reuses existing widget stores.

### FT1-5 — Surface background-finalize state on Today, not just the toolbar
- **What/why:** When a stopped meeting is still transcribing, the only indicator is a tiny toolbar pill ("N finalizing", `MainWindow.swift:594-600`). A user on Today doesn't see it and wonders where their just-finished meeting went. Add a lightweight inline "Finalizing 1 meeting…" row at the top of `todaySection` driven by `manager.transcribingMeetingIDs`.
- **Value:** Removes the "did my recording save?" anxiety on the home screen.
- **Effort:** S. **Dep:** none.

## Top 3 picks

1. **UX1-2** (S) — Reset Today's pushed detail on tab switch. Highest intuition-to-effort: fixes a real "Today isn't Today" back-state bug for ~3 lines.
2. **UX1-1** (S) — Wire up the already-built `calendarLink` and fix stale "Calendar tab" copy. Pure dead-code activation; restores Today→Meetings exit.
3. **FT1-2** (small-M) — Recents in the rail / ⌘K. Collapses repeat navigation from 3 clicks to 1 on the app's most-repeated action (reopening a person/meeting).

**Single highest-value low-lift win:** UX1-2 — making the home tab reliably return to the home feed.
