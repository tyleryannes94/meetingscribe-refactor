# MeetingScribe — Usability Critique (5 Personas)

_Grounded in the current rebuilt code at `MeetingScribeRefactor/Sources/MeetingScribe`. The app now has a 5-section nav rail (Today, Meetings, People, Tasks, Voice Notes), a warm design system, a NavigationSplitView Meetings tab, a two-column People detail, summary-first meeting tabs, inline action items, a follow-up draft button, and a pre-meeting brief. Calendar was folded into Meetings; Integrations moved into the Settings gear._

---

## USER-1 — Back-to-back-calls CS rep

**Who I am:** I live in this app 6 hours a day. Zoom call ends, next one starts in 4 minutes. I need to stop, glance at what I owe the customer, and jump into the next call recording without thinking.

**My day, step by step:**

- I open the app to **Today**. Good news: the big filled **Record Meeting** button is right at the top, and there's a **Join & record** pill when my next call has a link. That's a real improvement — I used to hunt for the record button. The pill row (Join & record / Voice note / New task / New page) is tidy.
- A call is starting. I see the **Join & Record** menu-button on the upcoming card. The split of "Join & Record" as the primary action with a dropdown for "Join (no recording)" / "Record only" is genuinely the right default for me — under time pressure I just hit the big button.
- Call's over. The just-finished meeting shows under **Today → Today** as a past card. I click it and it **expands inline** below the card. It defaults to the **Summary** tab once the summary lands — exactly what I want to skim before the next call. The inline detail is forced to a `minHeight: 520`, which on Today means the whole feed jumps and I have to scroll past a tall panel to reach my action items widget below. With 4 calls today, expanding two of them turns the Today feed into a long scroll.
- **Friction — collapse/expand vs. the Meetings tab are two different mental models.** On Today the card expands in place with a "Collapse" chevron at the bottom; in the **Meetings** tab the same meeting opens as a full right-hand page in a split view (no expand, no back arrow needed). Same data, two interaction patterns. When I'm moving fast I keep trying to expand-in-place in Meetings and instead it just swaps the right pane — fine, but it's a context switch I didn't ask for.
- **Friction — Summary tab delay.** The smart default waits 300ms after the body loads before flipping to Summary. On a fast machine that's a visible flash of the Notes tab before it jumps to Summary. Minor, but jarring 30 times a day.
- **Friction — no "next call" countdown / auto-join.** I rely on the OS notification for "meeting starting in 10s." Inside the app there's no persistent "next call in X min" banner on Today. The header subtitle says "2 upcoming today" but not _when_.
- **"I used to be able to…"** — I swear I used to see transcript/notes/summary status chips at a glance on the card. Now the past card shows a single plain-English pill ("Ready" / "Transcribing" / "No transcript"). That's actually clearer for me, so no complaint — just noting the change.

**Top 3 asks:**
1. A persistent "Next call in 12 min — Join & Record" banner on Today (with countdown).
2. Make inline expand on Today height-adaptive (don't force 520pt min) so a quick summary peek doesn't blow up the feed.
3. Unify the open-a-meeting gesture — let me collapse/expand in Meetings too, or at least make Today open the same full page so I'm not switching models.

---

## USER-2 — Manager running 1:1s on the People CRM

**Who I am:** I have ~14 direct reports plus skip-levels. Before every 1:1 I open the person, re-read my notes and our last meeting, and jot a memory.

**My day, step by step:**

- **People** tab. Left sidebar (260–380pt) is a clean searchable list with tag filter chips. I type a name, click in. The detail is now a **two-column** layout: a fixed **280pt identity panel** on the left (avatar, Edit/Delete, tags, contact rows, relationships, favorites) and a **tabbed right column** (Notes / Meetings / Messages). This is a big improvement over a single cramped scroll — the identity stuff stays put while I work in the tabs.
- **The layout is NOT cramped or cut off** for a normal-width window. But there's a real **wasted-width** problem: the right column's content is capped at `maxWidth: 720` and left-aligned, so on my 27" monitor I have the 240pt nav rail + 280pt identity panel + ~720pt content + a big empty gutter on the right, _and_ the Chat sidebar eating another ~340pt. With everything open I have two columns of person data and a third of the screen is dead space.
- **Friction — editing a person is still a MODAL sheet.** I click **Edit** and a 460×540 `AddPersonSheet` pops over everything. For a quick "update her title" I'd much rather click the field inline and type. The whole identity panel is read-only; every change is a round-trip through the modal. This is the single biggest day-to-day annoyance.
- **Friction — adding a memory is inline (good) but adding an encounter/relationship is a sheet.** Inconsistent: Memories has an inline "Add a memory…" field right there, but Encounters and Relationships each open their own sheet. I never know which interaction I'll get.
- **Friction — Meetings tab on a person only shows recordings.** "In your recordings" matches by email or name-in-attendees. My 1:1s often aren't recorded, so the person's Meetings tab is frequently empty even though we meet weekly. There's a "Mentioned in" backlink section and encounters, but no clean "every calendar meeting with this person" list.
- **Nice:** the conversation-analysis presets (Summarize relationship, Sentiment & trends, etc.) on the Messages tab are genuinely useful for prepping a sensitive 1:1 — and "Save to notes" persisting them is exactly right.
- **"I used to be able to…"** — feels like I should be able to click a tag chip on the person to jump to everyone with that tag, but the chips in the identity panel are display-only (`removable: false`, no tap action). Tag filtering only works from the sidebar chips.

**Top 3 asks:**
1. **Inline editing** of name/role/company/email directly in the identity panel — kill the modal for quick edits.
2. Let the right column use the full window width (or make the 720pt cap a preference); reclaim the dead gutter.
3. On a person's Meetings tab, show ALL calendar meetings with them (not just recorded ones), and make identity-panel tag chips tappable to filter.

---

## USER-3 — Founder / PM living in Tasks

**Who I am:** I run the company out of the Tasks tab. Initiatives → projects (pages) → tasks. I triage action items that fall out of every meeting.

**My day, step by step:**

- **Tasks** (⌘4). Left **ProjectRail** (230pt) with initiatives/projects/meetings; default landing is **All Tasks** (not the dashboard), so I see every open item immediately. That's the right call — I want the work, not a welcome screen.
- View modes List / Table / Board are all there, plus rich filters (This Week, Overdue, In Progress…) and group-by (Meeting / Priority / Status / Due). For a local app this is a legitimately strong task surface.
- **Big win:** action items now show **inline on the meeting Summary tab** with a one-tap "mark done" circle. After a call I read the summary and check off what got done without ever leaving the meeting. The same items live in Tasks with full CRUD. This closed the loop that used to make me navigate back and forth.
- **Friction — the inline action-item rows on the Summary are read-mostly.** I can toggle done and see owner + priority dot, but I can't edit the title, set a due date, or reassign owner inline — for that I have to go to the Tasks tab and find the item. So "quick triage right after the call" is half-implemented: I can complete, but not refine.
- **Friction — no way to create a task from a meeting summary.** If the AI missed an action item, I read the transcript, spot it, and… there's no "+ add action item" button on the meeting detail. I have to switch to Tasks, create it, and manually associate the meeting. The Today quick-action "New task" creates an _unassociated_ task.
- **Friction — Tasks tab has no Chat context tie-in for the selected project.** The Chat sidebar context updates for People (it injects the person id) but the Tasks tab just gets a generic "Tasks workspace" context, so I can't ask "summarize open items in this project" and have it know which project I'm looking at.
- **Friction — the follow-up button is buried.** The **Draft follow-up…** button only appears at the bottom of the Summary tab, _after_ the rendered summary and _before_ the action items. For long summaries I scroll a lot to reach the single most valuable post-meeting action.
- **"I used to be able to…"** — I expected the Today "New page" / "New task" pills to drop me onto the new item. They do flip me to Tasks, but a freshly created "Untitled" project/"New task" isn't auto-selected/opened for rename, so I have to find it.

**Top 3 asks:**
1. Make inline action items on the Summary fully editable (title, due, owner) and add a **"+ Add action item"** button on the meeting detail that auto-links to that meeting.
2. Pin **Draft follow-up** to the top of the Summary tab (or the detail header) — it's the #1 next action.
3. Wire the selected project into Chat context, and auto-open newly created tasks/projects for immediate rename.

---

## USER-4 — Privacy-conscious, keyboard-first power user

**Who I am:** Everything local (Ollama, Whisper, my own vault folder). I hate reaching for the mouse and I read every permission prompt.

**My day, step by step:**

- **Privacy:** I love that the onboarding opens with a **vault-location picker** before any permission, that Calendar is described as **read-only**, that chat is "Local · <model>", and that the conversation analysis runs through local Ollama. The permission pre-explainer (mic, screen recording, calendar, notifications, accessibility) with bullets and a Skip button is exactly the respectful flow I want. Accessibility is correctly marked optional ("skip if you don't use F5 dictation").
- **Keyboard nav:** ⌘1–⌘5 jump between sections, ⌘K is global search, ⇧⌘P adds a person, ⌘R / ⇧⌘R for recording, ⇧⌘N for a note. Good coverage for the top-level moves.
- **Friction — keyboard support collapses INSIDE a tab.** Once I'm in Meetings, there's no way to move selection in the meeting list with arrow keys / Enter — the rows are plain `Button`s in a `ScrollView`, not a focusable `List`. People and Voice Notes DO use a `List(selection:)` so arrows work there, but Meetings is mouse-only for selection. Inconsistent and it stops me cold.
- **Friction — no shortcut for the assistant toggle, the scope filter, or the meeting tabs.** The Summary/Transcript/Notes/Chat segmented picker has no key binding; I can't ⌘-number between meeting tabs. The Meetings scope pills (All/Upcoming/Past) are mouse-only.
- **Friction — Calendar tab is orphaned.** The code still has a full `CalendarTabView` (month grid, week strip) but it's not in the 5-item nav rail and there's no shortcut to it. The Today "All past + upcoming calls" link routes to **Meetings**, not the calendar view. So the month view exists but I can't get to it. That's dead/unreachable UI from my seat.
- **Friction — Chat sidebar auto-hides below 860pt width** and there's no keyboard toggle, only the toolbar button. When I tile windows narrow, the assistant silently vanishes; I have to widen and mouse to the toolbar.
- **Privacy nit:** the analysis prompts hard-code the user's name ("an adult professional named Tyler") in the preamble. As a privacy person I'd want that to read from my actual profile, not a baked-in string — it implies a single-user assumption and leaks a name into every local prompt.

**Top 3 asks:**
1. Make the Meetings list a real focusable `List` so ↑/↓/Enter select meetings like People and Notes already do.
2. Add shortcuts for: toggle assistant, switch meeting tabs (⌘1–4 within detail), and cycle the scope filter.
3. Either surface the Calendar/month view in the nav (or a shortcut) or remove the orphaned `CalendarTabView`; and don't bake a hard-coded name into local analysis prompts.

---

## USER-5 — Brand-new, non-technical, first launch

**Who I am:** Someone sent me this app. I've never used a transcription tool. I just want to record a meeting and get notes.

**My first 10 minutes:**

- First launch shows the **onboarding sheet**: "Where to store your vault?" with an iCloud Drive recommendation and a Change Location button, then one screen per permission with plain-English bullets. This is reassuring and not scary. The **Skip** button on each permission means I don't feel trapped. Good.
- **Confusion — "vault" is jargon.** Screen one says "store your vault" and "MeetingScribe keeps all recordings, transcripts, and notes in a single folder." I don't know what a vault is. "Where should we save your notes and recordings?" would land better.
- **Confusion — Screen recording asks me to "quit and relaunch the app once."** As a non-technical user, being told mid-onboarding that I'll have to quit and reopen the app makes me think something's broken. And the screen-recording grant just opens System Settings and marks itself "pending manual" — I'm dumped into macOS settings with no clear "come back here when done."
- After onboarding I land on **Today**. It's mostly empty (no calendar yet) with a friendly empty state: "Nothing on today's calendar" + Import. The big **Record Meeting** button is obvious. I press it — and I'm not sure anything happened beyond the button changing to "Stop recording." There's a "Recording now" card, which helps, but no "we're listening" reassurance up front.
- **Confusion — Voice Notes vs. Meetings vs. ad-hoc recording.** I see "Record Meeting" on Today, "Voice Note" and "Ad-hoc Recording" in the toolbar, and a "Voice Notes" nav item. As a newbie I have no idea what the difference is between a voice note and a meeting recording, or when to use which. Three recording entry points, no explanation.
- **Confusion — the Chat sidebar is on by default** taking a third of the window, with example prompts about "action items from yesterday's meetings" — I have no meetings yet, so it's noise that crowds out the actual app on my smaller laptop screen.
- **Confusion — empty Tasks/People/Meetings.** Each has a decent empty state, but nothing tells me the intended flow ("record a call → it appears here → action items extract automatically"). I don't understand that these tabs fill themselves.
- **Nice:** once I import or record something, the past card's "Transcribing… → Ready" pill is clear, and the summary appearing automatically feels magical.

**Top 3 asks:**
1. Replace "vault" with plain language, and on the Screen Recording step, explain the quit/relaunch in friendly terms with a "Reopen MeetingScribe" button instead of leaving me in System Settings.
2. A one-time "here's how this works" overview after onboarding (record → transcribe → summary → tasks), and disambiguate Voice Note vs. Meeting recording with a one-line description on each button.
3. Default the Chat sidebar **closed** for first-launch users (open it after they have content), so the empty app isn't dominated by an assistant with nothing to talk about.

---

## Cross-persona synthesis

### Most common complaints (appear across multiple personas)

- **Editing a person is modal, not inline** (USER-2 hard, echoed by USER-3's "can't edit inline" pattern and USER-4's keyboard friction). The read-only identity panel forcing a 460×540 sheet for any change is the loudest single complaint.
- **Wasted horizontal width** (USER-2 explicit, USER-1 implicit). The 720pt content cap on People detail + always-on Chat sidebar leaves a dead gutter on large displays; meanwhile the Chat sidebar crowds small displays (USER-5).
- **Two different "open a meeting" models** — inline expand (Today/Calendar, min 520pt) vs. full split-view page (Meetings). Inconsistent gesture and the forced 520pt min height bloats the Today feed (USER-1, USER-4).
- **Inconsistent inline-vs-sheet interactions** — Memories inline but Encounters/Relationships/Person-edit are sheets; action items toggle inline but can't be edited inline (USER-2, USER-3).
- **Keyboard/selection gaps inside tabs** — Meetings list isn't a focusable List (People/Notes are), no shortcuts for tabs/assistant/scope (USER-4).
- **Orphaned Calendar/month view** — full `CalendarTabView` exists but is unreachable from the 5-item rail; the Today "all calls" link goes to Meetings instead (USER-4).
- **Onboarding/first-run clarity** — "vault" jargon, the scary "quit and relaunch," three undifferentiated recording entry points, and a Chat sidebar that's loud when empty (USER-5).

### Top 8 asks (ranked by cross-persona weight)

1. **Inline-edit the person identity panel** (name/role/company/email/tags) — retire the modal for quick edits. _(USER-2, USER-3, USER-4)_
2. **Unify the meeting-open interaction** and make Today's inline expand height-adaptive instead of a forced 520pt min. _(USER-1, USER-4)_
3. **Reclaim wasted width** — let People detail use full width (or a pref), and default Chat closed for new users / make it keyboard-toggleable. _(USER-2, USER-1, USER-5)_
4. **Fully editable inline action items + a "+ Add action item" on the meeting detail** that auto-links to the meeting. _(USER-3)_
5. **Make the Meetings list a focusable List** with ↑/↓/Enter selection, matching People/Notes. _(USER-4)_
6. **Surface or remove the orphaned Calendar/month view**, and point the Today "all calls" link somewhere consistent. _(USER-4)_
7. **Promote Draft follow-up** to the top of the Summary/header — it's the highest-value post-meeting action and it's currently buried. _(USER-3, USER-1)_
8. **First-run clarity** — de-jargon "vault," friendlier Screen-Recording relaunch step, a short "how it works" overview, and disambiguate Voice Note vs. Meeting recording. _(USER-5)_

### What the rebuild clearly improved

The summary-first meeting detail with inline, checkable action items + the follow-up draft button finally closes the record → review → act loop in one place, and the warm two-column People detail (sticky identity panel + tabbed Notes/Meetings/Messages) plus the respectful vault-first, skip-friendly permission onboarding make the app feel dramatically more coherent and trustworthy than a cramped single-scroll predecessor.
