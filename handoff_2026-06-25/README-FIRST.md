# How to hand v3 to Claude Code

The terminal session got confused because it audited the **old** `design_handoff_ux_redesign_v2/`
(June 9) folder and found it already built. This folder (`handoff_2026-06-25/`) is the **new,
decided** design (v3) and supersedes it.

## Steps

1. **Unzip this `handoff_2026-06-25/` folder into the repo root** (`~/MeetingScribeRefactor/handoff_2026-06-25/`)
   and commit it, so Claude Code can read it:

   ```bash
   cd ~/MeetingScribeRefactor
   # (copy the unzipped handoff_2026-06-25/ folder here, then:)
   git add handoff_2026-06-25
   git commit -m "Add UX redesign v3 handoff (2026-06-25) — supersedes v2"
   ```

2. **Paste this prompt into the Claude Code session** (verbatim):

---

> There is a NEW design handoff at `handoff_2026-06-25/` that **supersedes**
> `design_handoff_ux_redesign_v2/`. Your earlier conclusion ("the redesign is already built on
> main") was about **v2**, which was an A/B/C exploration — it is now obsolete. **Ignore
> `design_handoff_ux_redesign_v2/` from here on.**
>
> Read `handoff_2026-06-25/HANDOFF.md` in full, then look at every PNG in
> `handoff_2026-06-25/screens/` and read the prototype source in `handoff_2026-06-25/prototype/`
> (`MeetingScribe.dc.html` is the shell; `MeetingDetail.dc.html`, `PersonWork.dc.html`,
> `TaskDetail.dc.html` are the details — these are a browser design prototype, NOT app source, so
> read them for exact layout/colors/interactions and translate to SwiftUI; do not port `support.js`).
>
> Then produce a **screen-by-screen conformance plan**: for each of Today, Meetings (focused list
> + full-page detail + Edit mode), People (roster + horizontal profile + tabs + Edit mode), Tasks
> (board + inspector + **property popover pickers**), Voice Notes (+ record state), Settings
> (categorized; per-meeting capture moved onto the meeting), and the New-item modal — list what's
> already on `main`, what differs from v3, and the exact diff to build. The headline new work is the
> **inline editing model** (task property popovers, meeting/person Edit modes) and the **Settings
> reorg** — these likely do not exist yet. Start with the plan; do not edit code until I approve it.

---

3. After it produces the plan, approve and let it build in the order under §12 of `HANDOFF.md`.

## Why your zip showed June 9 files

The zip was the repo's existing `design_handoff_ux_redesign_v2/` folder. The v3 prototype was
created in the design workspace and never committed — that's exactly what this package fixes.
