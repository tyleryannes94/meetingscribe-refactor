# D4 — Check-in & Encounter Interaction Design Audit

**Lens:** How encounter logging and check-in prompts are currently presented,
what the interaction loop feels like, and what is missing for a meaningful
check-in habit.

---

## 1. What Encounter Is Today

### Two Encounter models — a structural debt

There are two separate `Encounter` types in the codebase that serve different
purposes and are not unified:

**`Sources/MeetingScribe/People/Encounter.swift` (the app model):**
- Fields: `id`, `personID`, `eventTagID?`, `eventName`, `date`, `location?`,
  `notes`, `meetingID?`, `voiceNoteID?`, `createdAt`
- Concept: "I was at this *event* with this person." Encounter = an event-
  anchored moment, not a relational check-in.
- Missing: no `kind` enum (coffee / call / text / birthday / shared activity),
  no emotional quality field, no duration, no "initiated by" direction.

**`Sources/VaultKit/Encounter.swift` (the shared model):**
- Fields: `id`, `personID`, `kind` (meeting/call/email/message/note), `date`,
  `sourceID?`, `title`, `summary?`
- Has a `Kind` enum, but is a richer touchpoint-log model, not used by the app
  UI at all. The VaultKit model is never surfaced in `PersonDetailView`.

These two models coexist and diverge. The app builds encounters using the
app-model struct, while the VaultKit model (the better-designed one for check-
in purposes) sits inert. This means MCP tools reading VaultKit data see a
different encounter shape than the app records.

---

## 2. How a User Currently Logs a Check-In

### The path: 5 taps, 1 sheet, 1 required field

1. Open People tab → select person.
2. Scroll to the "Encounters" section (below Tags, Contact, AI Suggestions,
   Relationships — roughly mid-page).
3. Tap the "Add" button header, or the "Encounter" shortcut in the identity
   panel (`PersonDetailView.swift:490-494`).
4. A `AddEncounterSheet` opens at 420×460pt (`PersonDetailView.swift:1918`).
5. Required: type an `eventName`. Optional: date picker, location, notes. Save.

`AddEncounterSheet` auto-creates a `MeetingTag` of kind `.event` for every
encounter saved (`PersonDetailView.swift:1926`), meaning every "coffee with
Sarah" spawns a new event tag. For serial check-ins with the same person this
will balloon tag lists.

**Friction assessment:** High. The sheet has no quick-capture mode. To log "had
coffee with Sarah today" requires: open person, scroll to mid-page section, tap
Add, type a name for the event, pick a date (pre-filled to today but still
requiring attention), optionally add context, save. No voice note path. No
in-line quick entry (compare how Memories has an inline field at
`PersonDetailView.swift:1334`). There is no global "log a check-in" shortcut.

### The "Mentioned in" shortcut path

There is one fast path: if a meeting exists that mentions this person, a
`+` button next to that meeting row (`PersonDetailView.swift:1309-1316`) lets
the user log it as an encounter with a single tap — no sheet. This is the
lowest-friction path in the current app, but it only exists for recorded
meetings, not spontaneous encounters.

---

## 3. Encounter History UI

`EncounterRow` (`PersonDetailView.swift:1836–1867`) renders:
- SF Symbol `mappin.and.ellipse` (place icon — conceptually wrong for a
  recurring check-in with a close friend; implies geography, not relationship)
- `eventName` in bold
- Date + location (tiny text)
- Notes (small text)
- Delete button

There is no encounter edit affordance. Once logged, an encounter can only be
deleted, not corrected. No way to add a retrospective note. No way to link
a voice note after the fact.

Encounters are listed chronologically with no grouping (no "this month / last
month" dividers) and no count summary. A person with 30 encounters has a
long, unscannable list.

---

## 4. Recurring Reminder Mechanisms

**`NotificationManager.swift`** has two categories:
- `MEETING_START` — fires 10s before a calendar meeting.
- `IMPROMPTU_DETECTED` — fires when Zoom is detected.
- `daily-brief` — fires at 8am if enabled (`NotificationManager.swift:160`).

**There is zero per-person check-in reminder mechanism.** No notification is
ever scheduled that says "You haven't checked in with [person] in N days."

`ReconnectView` (`SuggestedPeopleView.swift:84–161`) computes overdue contacts
using an inferred cadence (`cadenceSeconds(for:)` at line 95), but it only
appears as a silent widget on TodayView — it never generates a push
notification. A user who doesn't open the app won't see it.

`PeopleInsightsView.swift:76–83` also surfaces a `goneCold` list (45-day
hardcoded cutoff), but again, only as an in-app card.

The `Person` model has no `desiredCheckInCadence` field, no `nextCheckInDue`
derived property, and no mechanism to let the user say "remind me about this
person every 2 weeks."

---

## 5. Check-in Templates

None exist. `AddEncounterSheet` has four fields: event name, date, location,
notes. There is no:
- Quick template for "coffee / lunch / call / text"
- Structured field for emotional quality or energy level after the interaction
- Prompt for "what did you want to follow up on?"
- Relationship-type-aware prompt (e.g., for a partner: "Did you express
  appreciation today?" for a friend: "What made you both laugh?")
- Post-encounter reflection prompt (e.g., Gottman's bid/response pattern for
  close relationships)

The AI suggestion engine (`PersonAISuggestions.swift`) can suggest encounters
to log (inferred from meeting context), but these suggestions have only a
`title` and `note` — no structured fields, no type, no quality dimension.

---

## 6. TodayView: Do People / Check-Ins Appear?

`TodayView.swift` includes:
- `SuggestedPeopleView` — people from transcripts needing confirmation, not
  check-in prompts.
- `ReconnectView` — "Stay in touch" nudges for overdue contacts.

`ReconnectView` taps through to the person's detail page; it does not offer a
quick-log action inline. The user must navigate to the person and go through
the full AddEncounterSheet flow. No "Log a quick check-in with Sarah" CTA
exists on Today.

The ReconnectView uses `cadenceSeconds(for:)` which requires at least 3
encounters to infer a cadence. For people with fewer than 3 encounters it falls
back to 30 days regardless of relationship type (a romantic partner and a casual
acquaintance get the same 30-day default).

---

## 7. Existing Plan Items Worth Endorsing (through this lens)

The following existing plan items are directly relevant to check-in interaction:

**Endorse — PPL-3 (encounter add inline like memories):** Memories have an
inline text field at `PersonDetailView.swift:1334` that lets users type and
press Enter. Encounters should have the same affordance for the ultra-common
"had coffee / quick call / texted today" case. This would drop the friction
from 5 steps to 2. Effort S.

**Endorse — "stay in touch" nudges (in plan):** ReconnectView exists but is
notification-free. Converting it to a UNNotification is the completion of this
plan item and is the highest-leverage retention hook in the app. Effort S.

**Endorse — relationship type paths (briefing focus item #1):** The cadence
logic in `SuggestedPeopleView.swift:95` uses a one-size cadence; a
relationship-type field on `Person` would let the app apply distinct cadence
thresholds (partner: daily, close friend: weekly, colleague: monthly) and
distinct check-in templates per type.

---

## 8. NET-NEW Recommendations

### D4-1 — Inline quick check-in field on PersonDetailView
**What:** Add an inline "Log today's check-in" row above the encounters list,
parallel to how the Memories section has an inline text field
(`PersonDetailView.swift:1334`). A single text field pre-populated with
today's date, pressing Enter creates the encounter immediately. Optional
"kind" pill buttons (coffee / call / visit / text) before the text field to
skip the event-name step. No sheet for the common case.
**Impact:** Drops "had coffee with X today" from 5 steps to 2. The most
frequent use case becomes frictionless.
**Effort:** S.

### D4-2 — Per-person check-in notification scheduler
**What:** Add `checkInReminderDays: Int?` to `Person` (nil = off). In
`NotificationManager.syncScheduled(for:)`, add a second pass that schedules
repeating `UNCalendarNotificationTrigger` notifications for each person whose
`lastInteractionAt` + `checkInReminderDays * 86400 < now`. Notification body:
"Haven't checked in with [Name] in N days — how are they doing?" Tapping opens
the person detail. The per-person setting is exposed in PersonDetailView as a
simple "Remind me every _ days" stepper.
**Impact:** The only mechanism that drives the app to the user instead of
waiting for the user to come to the app. Essential for habit formation.
**Effort:** M.

### D4-3 — Encounter kind enum + quick-kind buttons
**What:** Merge the two `Encounter` models: adopt the VaultKit `Kind` enum
(meeting / call / email / message / note) into the app Encounter, and add three
more: `coffee`, `activity`, `visit`. Expose these in both the inline quick-entry
(D4-1) and `AddEncounterSheet` as a segmented control or pill-row that replaces
the `eventName` field for common cases (tapping "coffee" pre-fills the name;
freeform text still available). This also fixes the VaultKit/app model
divergence.
**Impact:** Structural clarity; enables filtering by kind ("show all calls with
this person"), analytics ("you text more than you call"), and kind-aware check-
in prompts.
**Effort:** M (model change + migration + UI).

### D4-4 — Encounter edit affordance
**What:** Add an "Edit" button (pencil icon) to `EncounterRow`, presenting the
same `AddEncounterSheet` pre-populated with the existing encounter's data.
Currently encounters are delete-only; correcting a date or adding a retrospective
note requires deletion and re-creation. Also expose a "Add voice note" attachment
to an existing encounter.
**Impact:** Reduces data-quality anxiety about logging quickly. Users log
immediately knowing they can refine.
**Effort:** S.

### D4-5 — Structured post-encounter reflection prompt
**What:** When the user logs an encounter (saves `AddEncounterSheet` or submits
the inline quick entry), show a one-step non-blocking prompt: "Anything to
remember from this?" with 2-3 relationship-type-aware suggestions as hint text.
For relationship type `partner`: "Did you notice a bid for connection?"
For type `close friend`: "What made you both laugh or feel connected?"
For type `colleague`: "Any follow-up needed?"
The user can type or dismiss. The answer becomes the encounter's `notes` field.
**Impact:** Transforms a check-in log into a light reflective practice. One
question, answered or skipped, builds qualitative depth over time without
requiring a full Gottman framework upfront.
**Effort:** S (conditional on D4-3 having relationship type).

### D4-6 — Check-in streak / habit visualization on PersonDetailView
**What:** Above the encounters list, show a compact 12-week "heat map" grid
(like GitHub contributions) where each cell = a week and color intensity =
number of encounters. A "Current streak: N weeks" label. Show target cadence
(from D4-2) as a dotted line on the grid. No library needed — a simple
`LazyHGrid` of colored squares.
**Impact:** Habit visualization is the single most effective intervention for
sustaining a check-in practice. Makes the relationship's health visible at a
glance. Particularly motivating for close friend and partner paths.
**Effort:** S.

### D4-7 — Relationship-type-aware cadence defaults
**What:** Add `relationshipType: RelationshipType` enum to `Person` with cases:
`partner`, `familyMember`, `closeFriend`, `friend`, `colleague`, `acquaintance`.
Default cadence thresholds: partner 1d, familyMember 3d, closeFriend 7d,
friend 14d, colleague 30d, acquaintance 90d. `ReconnectView.cadenceSeconds(for:)`
uses `person.relationshipType` as its baseline instead of the hardcoded 30d
fallback, and the override still applies for people with 3+ encounters.
`AddEncounterSheet` and the inline field show type-appropriate placeholder text.
**Impact:** Foundational to multi-path UX. A partner should never share the
same 30-day default as a colleague. This is the model change that unlocks D4-2,
D4-5, and D4-8.
**Effort:** M.

### D4-8 — Check-in prompt templates per relationship type
**What:** A `CheckInPromptLibrary` struct with 3–5 prompts per `RelationshipType`
(D4-7). Shown as optional hint text in `AddEncounterSheet.notes` TextEditor when
the user hasn't typed yet. Examples:
- `partner`: "Did you each feel heard today? / What's one thing you appreciated?"
- `closeFriend`: "What's weighing on them right now? / What did you laugh about?"
- `familyMember`: "How are they actually doing, beyond 'fine'?"
- `colleague`: "Did you deliver on your commitments? Any blockers to raise?"
Prompts rotate through the library on each open (seeded by day of year) so they
don't go stale. User can also "shuffle" with a button.
**Impact:** Embeds Gottman / NVC / attachment-aware thinking into the act of
logging, without requiring the user to know those frameworks. The app becomes a
coach, not just a CRM.
**Effort:** S (library is static text; integration is one hint-text binding).

### D4-9 — "Quick check-in" global shortcut
**What:** Add a global keyboard shortcut (⌥⌘K or similar, distinct from ⌘N
task) that opens a compact floating panel: a person picker (type-ahead), a kind
selector (D4-3), and a one-line notes field. Saves the encounter and dismisses.
Accessible from any tab without navigating to People.
**Impact:** Meets the user where they are. After any meeting, call, or coffee,
the user can log it without context-switching away from what they're doing.
The single biggest friction reduction for people who aren't in People tab.
**Effort:** M.

### D4-10 — Encounter-linked MCP tools
**What:** Add two MCP tools to the 17-tool server:
1. `log_encounter(person_id, kind, date?, notes?, location?)` — creates an
   encounter record for a person from the Claude chat. A user in a meeting with
   Claude can say "log that I just had coffee with Sarah."
2. `get_encounter_history(person_id, limit?, kind_filter?)` — returns the
   encounter log for a person, filterable by kind and with the most recent
   interaction date prominently surfaced.
The current 17 tools include `get_person_messages` but no encounter read/write.
This means Claude has no way to answer "when did I last see Sarah in person?"
vs. "when did I last talk to Sarah?" — crucial distinction for relationship depth.
**Impact:** Claude becomes a real relationship coach when it can read and write
encounter history. Enables prompts like "I'm about to see Marcus — what's our
history and what should I bring up?"
**Effort:** S (MCP tools are thin wrappers; model/store already supports it).

### D4-11 — Encounter timeline view (chronological, cross-person)
**What:** A new "Timeline" sub-view in People (accessible from the PeopleListView
sidebar or PeopleInsightsView) showing all encounters across all people in
reverse-chronological order, with person chip, kind icon, and notes preview.
Filterable by person tag (e.g., "show only family"). This is the "relationship
journal" view — a log of all social interactions in one place, not scattered
across individual person profiles.
**Impact:** Gives the user a sense of their overall social life health. Identifies
weeks where they only had work encounters and no personal ones. Creates a
feedback loop at the aggregate level, not just the per-person level.
**Effort:** M.

### D4-12 — "Gone cold" notification (not just in-app card)
**What:** Convert `PeopleInsightsView.goneCold` (currently an in-app card with a
45-day hardcoded cutoff) into a weekly notification that fires Sunday evening:
"You haven't connected with [Name1] or [Name2] in a while — they'd probably
love to hear from you." Uses a `UNCalendarNotificationTrigger` scheduled for
Sunday 7pm. Respects the per-person `relationshipType` threshold (D4-7) instead
of the hardcoded 45 days. The notification body names at most 2 people to keep
it actionable.
**Impact:** Closes the gap between the app's insight capability and its ability
to surface that insight when the user is not already in the app. A Sunday
evening prompt is the socially natural moment to plan the week's outreach.
**Effort:** S.

---

## 9. Top 3 Picks

**#1 — D4-2 (Per-person check-in notification scheduler)**
This is the highest-priority recommendation because no amount of in-app UX
improvement matters if the user has to remember to open the app. A per-person
notification scheduler is the only mechanism that drives habit formation from
outside the app. It is also the most differentiating feature for a relationship
coach versus a CRM: the app reaches out to you on behalf of your relationships.

**#2 — D4-1 (Inline quick check-in field)**
The current 5-step sheet for logging "had coffee with X" is the primary
friction preventing a check-in habit. An inline 2-step entry identical to the
Memories pattern (`PersonDetailView.swift:1334`) removes that friction entirely.
This is the highest-value, lowest-effort change in the entire check-in surface.

**#3 — D4-7 + D4-3 combined (Relationship type + Encounter kind)**
These two model additions are the foundation everything else builds on. Without
`relationshipType` on Person, the cadence logic is one-size-fits-all (a partner
and a coworker get the same 30-day default). Without encounter `kind`, there is
no way to distinguish "we texted" from "we had dinner" from "we had a hard
conversation." Both are M-effort changes with cascading benefits across all
other D4 recommendations and the existing "stay in touch" and "gone cold"
features.
