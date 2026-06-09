# Archive — old `meetingscribe` repo planning docs

These four documents are the only artifacts unique to the **old** `tyleryannes94/meetingscribe`
repo (formerly checked out at `~/MeetingScribe` / `~/MeetingScribeFresh`). They are kept here
for historical reference; the old repo was retired on 2026-06-09.

All **code** from that repo is fully superseded by this repo (`meetingscribe-refactor`): a
file-by-file comparison confirmed the staged "Phase 0" concurrency/perf bug fixes and the
`audit-pass` commit were already present here (in several cases byte-identical, and carried into
the `ScribeCore` daemon target).

| File | What it is |
|---|---|
| `MASTER_PLAN.md` | 2026-05-27 two-binary efficiency/architecture plan (5-agent synthesis). |
| `MASTER_PLAN_V2.md` | Expanded architecture synthesis (25-agent). |
| `HANDOFF.md` | Operational handoff for the architecture refactor (now done). |
| `MeetingScribe_Improvements.docx` | Changelog of the 25-agent backend + UX audit — every item marked **Done**. |

The two-binary architecture these describe **is implemented** here (`Sources/ScribeCore`).
