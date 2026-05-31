# UX02 — Meetings tab + Meeting Detail pane

Senior-PM lens on the Meetings list, scope/filters, and the full UnifiedMeetingDetail pane (summary/transcript/notes/Ask-AI tabs, action items, follow-up, tags, attendees). Goal: every necessary action ≤2 clicks after opening a meeting; surface frequent actions; keep it low-lift.

## Lift from V4

- **DEF-1 / DEF-3** — Default Meetings scope = upcoming + persist; promote Draft-follow-up. Both are ALREADY shipped in this code (`MeetingsView.swift:24` `@AppStorage scope = .upcoming`; `MeetingSummaryTab.swift:38` follow-up button moved to top of summary). Re-affirm; build on them.
- **D1-5** — Bidirectional clickable person↔meeting↔task links. Directly relevant: attendee chips here are right-click-only (`MeetingDetailHeader.swift:565`), and the "Add to People" path is buried in a context menu. (FEAT-A is anchored; I only propose the adjacent attendee→person *click* affordance below.)
- **D1-2** — Register `meetingscribe://` + `onOpenURL`. Backlinks panel already posts `.meetingScribeOpenEntity` (`MeetingNotesTab.swift:132`); a deep-link "copy link to this meeting" rides on this for free.
- **P5-3** — Summary 👍/👎 feedback loop. The summary tab (`MeetingSummaryTab.swift:43`) is a dead-end read-only render today; a thumbs control is a natural low-lift add here.

## UX improvements (5)

### UX2-1 — Attendee chip is a one-click button, not a hidden right-click menu
**Friction today:** Attendee chips (`MeetingDetailHeader.swift:547–574`) only respond to `contextMenu` (right-click). "Add to People" — the single most common attendee action — is invisible: a user has no signal it exists. Discovering + adding a person to the CRM = right-click (1) → menu item (2), and most users never find it. Adding all attendees = N right-clicks.
**Fix:** Make the chip a left-click `Button`. If the person exists → open PersonDetail (deep-link via the existing `.meetingScribeOpenEntity` notification). If not → click opens a tiny inline confirm ("Add Jane to People?") with one button. Keep the context menu as the power path.
**Clicks:** add-to-People 2→1; open-person ∞→1.
**Effort:** S. `existingPerson` lookup already exists at line 540.

### UX2-2 — "Add all attendees to People" bulk affordance on the attendee row
**Friction today:** The attendee scroll row (`MeetingDetailHeader.swift:25–42`) shows chips but offers zero bulk action. Linking a 6-person meeting's attendees into the CRM is 6 separate right-click→menu sequences (~12 clicks).
**Fix:** Add a trailing "+ Add all to People" pill at the end of the attendee row, shown only when ≥1 attendee is not yet a Person. One click loops `createPerson` over the unmatched names (logic already at lines 527–545).
**Clicks:** link all attendees ~12→1.
**Effort:** S. Adjacent to FEAT-A (email/people linking) but a distinct net-new bulk button.

### UX2-3 — Tag picker auto-focuses the "New tag" field + commits on Return
**Friction today:** Tag popover (`TagPicker.swift:73–84`) opens with no focus; creating a new tag is: + (1) → click into field (2) → type → click Create (3). The field also doesn't submit on Return (no `.onSubmit`).
**Fix:** `@FocusState` auto-focus the New-tag field on popover open and add `.onSubmit { createTag }`. Existing tags are already one-click checkboxes — good.
**Clicks:** create+apply new tag 3→2 (open, type+Return).
**Effort:** S.

### UX2-4 — Stop the smart-tab default fighting the user; use a synchronous gate
**Friction today:** `applySmartTabDefault` (`UnifiedMeetingDetail.swift:239–255`) sleeps 300 ms then *jumps* the tab to Summary for past meetings. The tab visibly snaps after the pane has already painted (often on Notes/Transcript), which reads as a glitch and can land a user mid-scroll on the wrong tab. The summary string is already in the synchronous body cache (`reload()` line 169) on first paint.
**Fix:** Decide the default tab from the synchronous cache snapshot inside `reload()` (if `cached.summary` non-empty → `.summary`), removing the async sleep+jump entirely.
**Clicks:** removes a jarring post-load jump; 0 added.
**Effort:** S.

### UX2-5 — Surface "Reveal in Finder / Export / Recover" out of the triple-nested overflow menu
**Friction today:** Export to Markdown/PDF/Drive/Obsidian sits at overflow (1) → "Export…" submenu (2) → format (3) = 3 clicks (`MeetingDetailHeader.swift:299–316`). Recover is similarly 3 deep (line 285). These violate the 2-click rule for past meetings. The header has horizontal room next to the `···`.
**Fix:** Flatten one level — promote a single "Export" split-button (default = Markdown, dropdown = others) beside the `···`, and lift "Reveal in Finder" to a direct overflow item (it already is — but Export/Recover submenus are the offenders). Keep Recover in overflow but un-nest its two upload items to top level of the menu.
**Clicks:** export 3→2; recover 3→2.
**Effort:** small-M.

## Feature improvements (5)

### FT2-1 — One-click "Copy link to this meeting" (`meetingscribe://meeting/<id>`)
**What/why:** No way to grab a stable link to a meeting today. The deep-link plumbing exists (backlinks post `.meetingScribeOpenEntity`, D1-2 registers the scheme). Add a "Copy link" item to the overflow menu.
**Value:** Paste a meeting into a task, a note's `@`-mention, Slack, or an email — makes the graph linkable from outside the app.
**Effort:** S. **Dependency:** D1-2 (scheme registration) for the link to resolve on click; copy works regardless.

### FT2-2 — Inline thumbs 👍/👎 on the rendered summary
**What/why:** The local LLM summary is the product's variable-quality core with zero feedback signal (`MeetingSummaryTab.swift:43`). Add a small thumbs pair below the summary; 👎 reveals an optional one-line "what was off?" and offers Regenerate (the regenerate path already exists at line 76).
**Value:** Closes P5-3's feedback loop and gives users an immediate "fix this summary" escape hatch instead of a dead-end read-only block.
**Effort:** S. **Dependency:** none for capture; steering regeneration is later.

### FT2-3 — "Add attendees as recipients" toggle in the follow-up draft
**What/why:** FollowUpView already resolves attendee→People→email and prefills mailto (`MeetingSummaryTab.swift:179`, `FollowUpView.swift:138`), but silently drops attendees with no matching Person. Show the resolved recipient chips at the top of the draft with a count ("To: 3 of 5 attendees — 2 not in People") and a one-click "add the missing 2."
**Value:** Makes the send trustworthy (you see who it's going to) and nudges CRM completion. Ties follow-up to FEAT-A/UX2-2.
**Effort:** small-M.

### FT2-4 — Quick "owner = attendee" picker on inline action items
**What/why:** Inline action-item rows (`MeetingSummaryTab.swift:231`) show `owner` as static text and offer no way to set it; you must leave for the Tasks tab. The meeting's attendee list is right there.
**Value:** Assign an action item to a meeting attendee in 2 clicks (menu → name) without context-switching. The `owner` field already exists on `ActionItem`.
**Effort:** small-M. **Dependency:** none.

### FT2-5 — Per-meeting search/jump-to inside long transcripts
**What/why:** Transcript tab (`MeetingTranscriptTab.swift:38` → `TranscriptSyncView`) has no in-document find; the list-pane search (`MeetingsView.swift:97`) only matches title/attendees, never transcript text. On a 90-min call, finding "what did we decide about pricing" means manual scroll.
**Value:** A tiny find-bar (⌘F) scoped to the open transcript — high-frequency recall action, fully local. A precursor/complement to the V4 FTS5 recall moat (C2-1) but shippable standalone for the *current* meeting.
**Effort:** small-M. **Dependency:** none (string search over the loaded transcript).

## Top 3 picks

1. **UX2-1 — clickable attendee chips.** Highest-leverage, lowest-lift: turns a hidden right-click into a discoverable one-click person link/add. Pure win, `existingPerson` lookup already written.
2. **FT2-2 — summary thumbs + one-click regenerate.** Converts the dead-end summary into a feedback + self-heal surface; satisfies P5-3 at S effort.
3. **UX2-5 — flatten Export/Recover out of the 3-deep overflow.** The clearest 2-click-rule violation in the detail pane today; flattening restores compliance.

**Single highest-value low-lift win:** UX2-1 — make the attendee chip a real one-click button (open Person if known, add if not), with UX2-2's "Add all to People" as its natural sibling.
