# MeetingScribe — Deep Page Redesign Master Plan (2026-06, round 2)

*Synthesized from a second 5-agent PM/designer audit focused on fundamentally reworking the **Meetings** and **People** pages: kill the tabs, show content all-at-once with collapsible sections, fix inconsistent/"weird" button sizes, and make **Tasks** a first-class connected signal across both. Per-area detail in `01`–`05`. Paste-and-build prompts in [`BUILD-PROMPTS.md`](BUILD-PROMPTS.md).*

## The through-line (where all 5 agents converged)

1. **Both detail pages are over-tabbed.** Meeting detail = 4 tabs (Meeting/Actions/Transcript/Ask AI); Person detail = 4 pills (Overview/Meetings/Messages/Notes) crammed into a 300pt column. → **One scrolling canvas of collapsible sections per page; everything reachable without tab-hopping.**
2. **There is no shared collapsible-section component.** Sections are bare `VStack` + `NotionEyebrow`; the only disclosure is a one-off hand-rolled chevron in `MeetingSummaryTab`. → **Build one `MSSection` component first; route every section on both pages through it.**
3. **"Weird button sizes" is real and has a precise cause.** The app already ships a correct 4-tier button system (`MSPrimary` 34 / `MSSecondary` 30 / `MSTertiary` 28 / `NotionIconButton` 30² + 44 tap), but important actions bypass it for AppKit defaults (`.borderedProminent`, `.controlSize(.small)`, bare `.borderless`+`.font(NDS.small)`). → **Rule: every action uses an `MS*ButtonStyle`; ban the AppKit fallbacks; add `MSInlineButton` + `msMenuButtonChrome()` wrappers; lint to prevent regression.**
4. **Tasks are disconnected.** A task's source meeting and owner are rarely one click away, and open/overdue task counts aren't visible from the People list, meeting cards, or meeting summary owner rows. → **Make every task row's meeting + owner navigable; surface open/overdue counts on person rows, meeting cards, and inline.**

## Critical build sequencing

**Shared foundation lands FIRST** — both page redesigns depend on it. Then de-tab each page onto it. Tasks-integration increments are mostly independent and interleave.

```
Phase F  Foundation        MSSection + MSInlineButton + msMenuButtonChrome   (agent 5 steps 1–2)
Phase B  Button cleanup    fix header Options chrome, person .borderedProminent/.borderless  (agent 5 steps 3,5)
Phase M  Meeting canvas    de-tab → MSSection stack, flag-gated migration    (agent 1 + agent 5 step 7)
Phase P  Person canvas     compact header + MSSection stack, Tasks promoted  (agent 2 + agent 5 step 6)
Phase L  People list       triage grouping + richer rows + density           (agent 3)
Phase T  Tasks linkage     navigable meeting/owner everywhere + count badges  (agent 4)
Phase X  Cleanup           delete DetailTab/PersonTab enums + MSPillTabs use; design-lint guard
```

Tasks increments T1–T3 (navigable owner/meeting, zero model change) can ship anytime after Phase F. Count badges (T5–T6) depend on the person-list rows (Phase L) and `MeetingCard`.

## Hard constraints (do not fight these)

- **`MarkdownEditor`/`RichMarkdownEditor` is an `NSScrollView`-backed `NSViewRepresentable`** — it CANNOT live inside an outer SwiftUI `ScrollView`. The canvases must give the notes editor (and the transcript/chat panes) **bounded, explicit heights** so each scrolls internally; the page "scrolls" via collapsed short headers. A top-level `ScrollView` is only safe once every long child has a fixed frame.
- **`TranscriptSyncView` is heavy + interactive** (search/seek). Lazy-mount it behind a collapsed disclosure (`if expanded { … }`) so it isn't instantiated on first paint of a past meeting.
- **The transcript slot multiplexes by mode** (live transcript / pre-meeting brief / past transcript). Keep the multiplex; just relabel the section per mode.
- **Person profile "fit is good now"** (user-confirmed after a careful pass). The cram-safety comes from `FlowLayout` wrappers + scrolling pills. Moving the action cluster into the *wide* canvas (≥560pt) removes the 300pt constraint rather than fighting it; keep `FlowLayout` for any multi-control metadata row as a guardrail. Flag this risk on every person-pane step.

## Risk notes

- This is a large, multi-PR effort. Every step must compile green (`Build complete!` + no real `error:`) before merge; `make install` every ~2 increments so the user evaluates each.
- Meeting + Person de-tab are flag-gated migrations (build the new canvas beside the tabs, migrate section-by-section, flip default, then delete tabs) so nothing breaks mid-flight.
- Audits historically over-flag already-built items — verify each against code before building (e.g. People sort menu already exists; person tabs already 6→4).

See `01`–`05` for the full per-area proposals with file:line references and step-by-step build plans.
