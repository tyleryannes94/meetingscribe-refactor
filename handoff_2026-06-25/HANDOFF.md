# MeetingScribe — UX Redesign **v3** (2026-06-25)

> **READ THIS FIRST (for Claude Code / any build agent).**
>
> This handoff **SUPERSEDES** `design_handoff_ux_redesign_v2/` (the June 9 prototype).
> A previous audit concluded "the redesign is already built on `main` — nothing new to do."
> **That conclusion was about v2 and is now obsolete.** v2 was an A/B/C *exploration*.
> v3 is the **decided, unified design** — specific directions were chosen per page and a
> set of editing interactions were designed that **do not yet exist in the app**.
>
> Do **not** re-audit against `design_handoff_ux_redesign_v2`. Build to match the prototype
> and screenshots in **this** folder. When something here conflicts with what is on `main`,
> **this design wins** and the app should change.

---

## 0. What changed since v2 (the build delta)

v2 shipped each page with 2–3 alternative layouts behind a toggle. v3 picks **one winner per
page** and adds the **edit/settings interactions** that were the whole point of the redesign
("settings and editing the selection are clunky"). The concrete new work:

1. **Lock each page to its chosen layout** (remove the A/B/C variant toggles):
   - **Meetings → "Focused"** (full-width list → full-page detail).
   - **People → "Roster + Profile"** (grouped roster + horizontal profile header + tabbed work area).
   - **Tasks → "Inspector"** (board lanes + persistent right inspector).
2. **Inline, low-friction editing** on every detail (this is the headline fix):
   - **Task** properties edit via **click-to-open popover pickers** (Status, Priority, Due, Project, Assignee) — no separate edit screen, no modal-in-modal.
   - **Meeting** has an **Edit** toggle: editable title/date, attendee add/remove with a people picker, tag add/remove, and **per-meeting recording-source toggles** (Mic / System).
   - **Person** has an **Edit** toggle: editable name/role/company and contact facts (email, phone, location, birthday), plus tag add/remove.
3. **Settings overhaul** — a single organized screen (categories on the left), and **per-meeting recording sources moved onto the meeting** (out of global Settings).
4. **Voice Notes** — a real, designed page (list + record state + player + AI summary + transcript + "push → Tasks").
5. **Context-aware "New" modal** (New meeting / Add person / New task) from the toolbar.

If a screen on `main` already matches the chosen layout, keep it — but reconcile it to the
spacing, header structure, and **editing model** below. The editing model is the part most
likely missing.

---

## 1. Canonical artifacts in this folder

```
handoff_2026-06-25/
├── HANDOFF.md                         ← this file (source of truth)
├── prototype/
│   ├── MeetingScribe.dc.html          ← the unified app shell (all pages + nav + settings + modals)
│   ├── MeetingDetail.dc.html          ← meeting detail + edit mode (embedded by the shell)
│   ├── PersonWork.dc.html             ← person tabbed work area (Overview/Meetings/Tasks/Messages/Notes)
│   ├── TaskDetail.dc.html             ← task detail + property popover editors
│   └── support.js                     ← prototype runtime (NOT app code — ignore for the Swift build)
└── screens/
    ├── 01-today.png
    ├── 02-meetings-list.png
    ├── 03-meeting-detail.png
    ├── 04-meeting-edit-mode.png
    ├── 05-people-roster-profile.png
    ├── 06-person-edit-mode.png
    ├── 07-tasks-board-inspector.png
    ├── 08-voice-notes.png
    ├── 09-voice-recording.png
    ├── 10-settings.png
    └── 11-new-item-modal.png
```

**The `.dc.html` files are a design prototype, not app source.** They render in a browser via a
small custom runtime (`support.js`) and exist so you can read exact markup, inline styles, colors,
spacing, and interaction logic, then translate to SwiftUI. Read them as the spec; do not port the
runtime. All styling is inline; all layout/state logic is in the `<script data-dc-script>` class at
the bottom of each file (`renderVals()` returns the view-model; look there for behavior).

To view the prototype: open `prototype/MeetingScribe.dc.html` in a browser (it loads the sibling
`.dc.html` files and `support.js` from the same folder).

---

## 2. Design language — "Bloom" (unchanged from what's on main; reaffirmed here)

Dark plum base, warm coral primary, lilac brand accent. Headings in **Bricolage Grotesque**
(700–800), body in **Plus Jakarta Sans**. Exact tokens (use these verbatim):

```
--bg:        #15121a   (app background)
--sidebar:   #100d15   (nav rail / title bar / settings rail)
--surface:   #1e1925   (cards, inputs)
--surface-2: #271f31   (chips, secondary fills, popovers)
--surface-3: #322843   (toggles off-state, "me" avatar)
--line:      rgba(245,238,250,.09)   (hairline dividers/borders)
--line-2:    rgba(245,238,250,.16)   (stronger borders, input outlines)
--txt:       #f3eef6                 (primary text)
--txt-2:     rgba(243,238,246,.68)   (secondary text)
--txt-3:     rgba(243,238,246,.44)   (tertiary/labels)
--accent:    #ff9173   --accent-2: #f06a4c   (coral; primary gradient 135°)
--accent-soft: rgba(255,145,115,.16)
--lilac:     #b79cff   --lilac-soft: rgba(183,156,255,.16)   (brand / active nav / AI)
--mint:      #74e0bc   (success / completed / Healthy)
--sky:       #8ab4ff   (info / To-do / New)
--gold:      #ffce6b   (warning / due dates / In-progress / Slipping)
--danger:    #ff7a8a   (recording / At-risk / High priority)
```

Conventions:
- **Primary action** = coral gradient `linear-gradient(135deg, #ff9173, #f06a4c)` with `#2a1208` text.
- **Active nav item** = `--lilac-soft` fill, `--txt` label, lilac icon.
- **Eyebrow labels** = 10px, 700, letter-spacing 1px, uppercase, `--txt-3`.
- Card radius 14–18px; pill/chip radius 999px; buttons radius 9–11px.
- Avatars: rounded-square (`border-radius: 34%` for circles-ish, 12–22px radius for tiles); per-person gradient; initials in `#241636`.
- **Cadence colors:** Healthy = mint, Slipping = gold, At risk = danger, New = sky.
- **Status badges:** Live = danger dot + "Live"; Scheduled = sky chip; Summary = mint chip w/ sparkle; Transcribed = neutral chip.

---

## 3. Global chrome

- **Title bar** (44px): traffic lights, page crumb, right-aligned **page-tailored toolbar**, then Ask-AI toggle. When a recording is active, a red "Stop · 12:04" pill appears at the left of the toolbar.
- **Nav rail** (228px, `--sidebar`): logo, group **WORKSPACE** (Today, Meetings, People), group **ORGANIZE** (Tasks [open-count badge], Voice Notes), spacer, **Settings** pinned at the bottom.
- **Toolbar is per page**: Today → Search · Voice note · **New meeting**. Meetings → Search · Import calendar · **New meeting**. People → Search · Import · **Add person**. Tasks → Search · Filter · **New task**. Voice → Search · **New voice note**. The accent button opens the **New-item modal** (§9).
- **Ask-AI rail** (320px, toggled): context-aware title + suggested prompts + "Runs locally via Ollama" note. Prompts change per page.

---

## 4. Today  (screens/01)

Greeting (Bricolage 31px) + date/summary line. Two columns:
- **Left:** live-recording banner (if recording) with "Open & add notes"; **Up Next** list of meeting cards (time · title · dur/attendees · status badge) → opens meeting detail.
- **Right:** **Due today** card (checkbox + title + due badge + owner avatar, "All tasks →") and **Reconnect** card (slipping/at-risk people with cadence chip) → opens person.

Everything is click-through to the relevant page/detail.

---

## 5. Meetings — "Focused"  (screens/02, 03, 04)

**List view (02):** centered max-width column. Filter chips (All / Today / Upcoming / Past).
Time-grouped sections: **● NOW** (red), **TODAY**, **UPCOMING**, **PAST · RECORDED**. Each row:
live dot (if recording) · time (tabular) · title + "dur · source" · attendee avatar stack · status
badge · chevron. Whole row opens the detail **as a full page** (no split pane).

**Detail (03):** breadcrumb back ("← Meetings / <title>"). Header: title, "date · range · source",
primary action (Join & record / Stop recording / Re-transcribe by status) + **Edit** button.
Attendee chips (click → person). Link + tag chips. Live bar with waveform when recording. Tabs:
**Summary** (AI summary + Decisions + Action items w/ "Push all → Tasks" + audio scrubber),
**Notes** (formatting toolbar + editor + "Push notes → Tasks" / Export), **Actions** (action items
with per-item "→ Tasks" / "In Tasks" state), **Transcript** (timestamped, speaker avatars).

**Edit mode (04):** title and date become inputs; each attendee chip gets a remove (×) and an
**"+ Add people"** picker (choose from roster); tags get remove + an **add-tag** popover (free text
+ suggestions); and **per-meeting capture toggles** appear (Microphone / System audio) — this is
where recording sources live now, NOT global settings.

---

## 6. People — "Roster + Profile"  (screens/05, 06)

This replaces the cramped two-pane. **Roster** (312px): "People" + **Add**, search, then groups
**Colleagues / Clients / Prospects**, each row = avatar tile · name · role · cadence dot.

**Profile (right):** a **horizontal** header (not stacked columns) — large avatar + name + "role ·
company" + **tag row**, with right-aligned actions **Message · Log · Edit**. Below the header, a
**horizontal facts strip** of small cards: Email, Phone, Location, Birthday, Cadence, First met.
Then the **tabbed work area** (`PersonWork.dc.html`): **Overview** (Memories, Favorite things, AI
suggestions, At-a-glance), **Meetings** (shared meetings → open), **Tasks** (their open tasks),
**Messages** (stats + bars + "Analyze conversations" → local AI summary), **Notes**.

**Edit mode (06):** name/role/company become inputs in the header; the facts strip cards (Email,
Phone, Location, Birthday) become inline inputs; tags get remove (×) + an add-tag popover. Cadence
and First-met stay read-only (derived). "Edit" turns into a coral "Done".

---

## 7. Tasks — "Inspector"  (screens/07)

Header "Tasks" + meta + filter chips (All / Mine / From meetings [count] / Done). Main area = a
**3-lane board** (To do · In progress · Completed), each card showing project + meeting badges,
title, priority + due badges, owner avatar. Selecting a card loads it in the **persistent right
Inspector** (380px) = `TaskDetail.dc.html` in `inspector` layout. "Full view" expands it.

**Task editing — the core "clunky edit" fix (see TaskDetail.dc.html):** the inspector shows a
property table where **each row is a pill that opens a popover picker**:
- **Status** → To do / In progress / Completed (colored dot each).
- **Priority** → High / Medium / Low (arrow/dash/dot + color).
- **Due** → Today / Tomorrow / Wed / Fri / Next week / No date.
- **Project** → project list (colored dot) / No project.
- **Assignee** → You + roster (avatar each).
The current value is checked in the popover; picking updates immediately and closes. Title is
inline-editable (contenteditable); **Subtasks** add via an inline "Add subtask… (Enter)" row with a
live progress bar; an **Activity** timeline is below. Checking the big title checkbox toggles
Completed. Tasks extracted from meetings show a lilac "Extracted from <meeting>" chip that links back.

---

## 8. Voice Notes  (screens/08, 09)

**List (300px):** "Voice Notes" + a big **New voice note** button (coral). Rows = waveform icon ·
title · "date · duration". **Detail:** title/date/duration, audio player (play, progress, speed),
**AI summary**, **Transcript** card, and **"Push → Tasks"**. **Recording state (09):** the New
button turns red ("Stop recording"); a centered card shows "RECORDING · 00:08", an animated live
waveform, and **"Stop & transcribe"**.

---

## 9. New-item modal  (screens/11)

Opened by the toolbar accent button; **context-aware** by current page:
- **New meeting:** Title, When, Capture sources (Microphone / System audio chips).
- **Add person:** Name, Role & company, Relationship (Colleague / Client / Prospect).
- **New task:** Task, Priority (High/Med/Low), Due (Today/Tomorrow/This week).
Centered modal, header icon + title, Cancel + coral confirm. Reachable from People roster "Add" too.

---

## 10. Settings  (screens/10)

A single modal: left category rail (**General, Recording, Transcription, AI & Summaries,
Integrations, MCP Server**) + a right detail pane of grouped rows (label/description + a control:
toggle or value-pill). "Done" closes. Notable: **Recording** holds *default* sources + automation
(auto-start, detect Zoom/Meet); **per-meeting** sources live on the meeting (§5). **Transcription**
= whisper.cpp model + live transcript. **AI** = Ollama model + auto-summarize. **MCP Server** =
install in Claude Desktop + allow write tools. Everything is local-first (no API keys / outbound).

---

## 11. Data model (matches the app's existing stores — mock data in the prototype mirrors it)

- **Person:** id, name, role, company, emails[], phone, location, relationship (Colleague/Client/Prospect), tags[], firstMet, cadence + cadenceDays + lastSpokeDays, birthday, favorites[], memories[], msg stats. → `PeopleStore`.
- **Meeting:** id, title, when (today/upcoming/past), time, range, date, dur, source, attendees[personId], extra[email], link, tags[], status (recording/scheduled/summary/transcribed). → `MeetingStore`.
- **Task / ActionItem:** id, title, status (open/doing/done), priority (high/med/low), due, project, owner (personId | "me"), meeting (meetingId|null), fromMeeting. Subtasks, activity. → `ActionItemStore`.
- **Voice note:** id, title, date, dur, summary, transcript.
- **Project:** name, color.

No schema changes are required by this redesign — it's UI/UX. The new bits (per-meeting capture
sources, person tag edits, task property pickers) map onto existing fields.

---

## 12. Build order suggestion

1. Lock layouts + remove v2 variant toggles (Meetings focused / People roster+profile / Tasks inspector).
2. Task property **popover pickers** + subtasks + activity (highest-value fix).
3. Meeting **Edit mode** (attendee picker, tag editor, per-meeting capture toggles).
4. Person **Edit mode** (inline facts + tag editor).
5. Settings reorg (move per-meeting sources out; categorize).
6. Voice Notes page + record state.
7. New-item modal.

Treat the prototype's spacing, hierarchy, and interaction flow as the spec; reuse existing stores
and components where they already match.
