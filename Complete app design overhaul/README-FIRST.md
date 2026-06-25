# How to hand this to Claude Code

This folder (`handoff_2026-06-25/`) is the **clean, verified** UX redesign handoff (v4). It
supersedes every earlier handoff in the repo (`design_handoff_bloom_redesign 2/`,
`design_handoff_ux_redesign_v2/`, and any prior `handoff_2026-06-25/`).

Why the earlier attempts failed: the old handoffs described files that **don't exist** in the repo
(`MeetingDetailHeader.swift`, `MeetingNotesTab.swift`, an editable `MarkdownEditor.swift`). The build
agent went looking for them, couldn't reconcile the described structure with the real code, and
stalled. **`HANDOFF.md` + `FILE_MAP.md` here were checked against the live source on `main`** and also
tell the agent what's **already built** so it stops re-building things and only finishes the gaps.

## Steps

1. Commit this folder to the repo root so Claude Code can read it:
   ```bash
   cd ~/MeetingScribeRefactor
   git add handoff_2026-06-25
   git commit -m "docs: add verified UX redesign v4 handoff (supersedes prior)"
   ```

2. Paste this prompt into the Claude Code session (verbatim):

---

> Read `handoff_2026-06-25/HANDOFF.md` and `handoff_2026-06-25/FILE_MAP.md` in full, then look at
> every PNG in `handoff_2026-06-25/screens/` and read the prototype in
> `handoff_2026-06-25/prototype/` (`MeetingScribe.dc.html` is the shell; `MeetingDetail.dc.html`,
> `PersonWork.dc.html`, `TaskDetail.dc.html` are the details — a browser design prototype, NOT app
> source. Read them for exact layout/colors/spacing/interactions and translate to SwiftUI; do not
> port `support.js`).
>
> **Ignore all earlier handoffs** (`design_handoff_bloom_redesign 2/`,
> `design_handoff_ux_redesign_v2/`). They reference files that do not exist
> (`MeetingDetailHeader.swift`, `MeetingNotesTab.swift`, an editable `MarkdownEditor.swift`) — the
> real meeting detail is a single `UnifiedMeetingDetail.swift`; see `FILE_MAP.md`.
>
> Most of this redesign is **already implemented** on `main`. Do NOT rebuild from scratch. Produce a
> **screen-by-screen conformance plan**: for each of Today, Meetings (list + `UnifiedMeetingDetail` +
> Edit mode), People (roster + `PersonDetailView` + inline Edit), Tasks (board + inspector property
> popovers in `ActionItemsPropertyDrawer.swift`), Voice Notes (`QuickNotesView`), Settings
> (`SettingsView`; per-meeting capture moved onto the meeting), and the New-item sheets — open the
> **real file named in `FILE_MAP.md`**, state what already matches the prototype, and list the exact
> remaining diff. The headline new work is the inline editing model (person fields, task property
> popovers, per-meeting capture toggles) and finishing Today's click-into navigation — these are the
> gaps called out in `HANDOFF.md` §3–§10. **The floating voice-note pill (`HANDOFF.md` §3 GC-1,
> `prototype/VoiceNotePill.dc.html`) is currently broken (every label truncates) and is a P0 — rebuild
> `FloatingOverlay.swift` to the 3-state spec with the anti-truncation rules.** Start with the plan; do
> not edit code until I approve it.
>
> **Responsive + mobile are mandatory on every screen** (`HANDOFF.md` §13–§14): the prototype's
> 1440×900 frame is a reference, not a fixed size. No fixed content widths, no clipping, no horizontal
> app scrollbar — use `min/ideal/maxWidth` + `maxWidth:.infinity`, wrap every chip/badge/tag/button row
> with `FlowLayout`/`ViewThatFits`, give text-bearing flex children `minWidth:0` + truncation, remove
> the 720/920 content caps (prose keeps a ~720 reading measure only), and collapse multi-pane layouts
> by the §13.3 breakpoints. On **compact width / phone** (`horizontalSizeClass == .compact` or < 700px),
> switch the nav rail to a bottom tab bar, push details full-screen with a back button instead of split
> views, turn inspectors/property popovers into sheets/menus, make modals full-screen, and use ≥44pt
> touch targets + Dynamic Type + safe-area insets. Verify each screen at a narrow (~700px) and a wide
> window before moving on.
>
> Build in the order in `HANDOFF.md` §12. After each screen, run `swift build -c release` (or
> `make app`) before moving on, and use the `NDS` tokens + `MSComponents` rather than raw colors/controls.

---

3. After it produces the plan, approve and let it build screen-by-screen in the `HANDOFF.md` §12 order.

## What's in this package
- `HANDOFF.md` — source of truth: design tokens, the corrected file map, and per-screen
  *already-built vs remaining-diff* with severities.
- `FILE_MAP.md` — fast screen → real Swift file lookup, plus the list of non-existent files to avoid.
- `prototype/` — the four screen `.dc.html` design files (open `MeetingScribe.dc.html`; each file also
  opens standalone) + **`VoiceNotePill.dc.html`** (the floating voice-note pill, all 3 states) +
  `support.js` (ignore for the Swift build).
- `screens/` — 11 reference PNGs.
