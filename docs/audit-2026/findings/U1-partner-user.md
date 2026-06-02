# U1 — Partner Relationship User Audit

**Lens:** I am a power user who tracks my romantic partner in MeetingScribe. I
open the app every day, want check-in prompts, and use it to build a living
record of our relationship — fights, wins, growth moments, recurring patterns.

---

## 1. Full Narrative: My Daily Experience in the App

### "I want to add my partner for the first time."

I hit ⇧⌘P or click "+ Add" and get `AddPersonSheet`
(`Sources/MeetingScribe/People/AddPersonSheet.swift:47–113`). The sheet gives
me Name, Company, Role, Email, Phone, Address, Favorites, Birthday, Tags, and
Notes. **There is no "Relationship type" field anywhere in the sheet, the
model, or any view.** My partner becomes indistinguishable from a vendor
contact: same form, same model fields, same relevance weight. The only way to
signal this is a free-text Tag ("partner") or a Relationship edge
(`Person.swift:119`) with a label string — but neither drives any behavior
difference. No prompt cadence, no section visibility, no AI framing changes as
a result.

Missing: a `relationshipType` enum (`.romantic`, `.family`, `.closeFriend`,
`.professional`) on `Person` (`Person.swift:77–184`) — absent from the model
entirely.

### "I want to log that we had dinner together last night."

I open her profile, scroll past Tags, Contact, AI Suggestions, Relationships
(roughly the middle of the page — `PersonDetailView.swift:248`), and find
"Encounters." I click the "Encounter" shortcut in the identity panel
(`PersonDetailView.swift:490–494`) or the "Add" button in the section header.
`AddEncounterSheet` opens (420×460).

The sheet asks for **Event name** (required). For a CRM where I meet a
colleague at a conference, "Purple Party 2026" makes sense. For logging dinner
with my partner, calling every dinner an "event" is jarring. The Encounter
model (`Encounter.swift:7–46`) has no `kind` field — no way to distinguish
"date night," "difficult conversation," "quality time," or "phone call." There
is no emotional quality field, no duration field, no "who initiated" direction.
Every log entry looks like a conference badge.

The VaultKit model (`Sources/VaultKit/Encounter.swift`) does have a `Kind`
enum (meeting / call / email / message / note), but **it is never surfaced in
the app UI** — the app only uses the app-local `Encounter.swift` struct. Two
diverged models, neither right for a relationship journal.

I wish: a quick-log widget on the partner's profile — one tap for "We spent
time together today" with optional mood, optional duration, optional note. No
event name required.

### "I want to see what my partner's profile looks like."

`PersonDetailView.swift:241–258` renders 14+ sections in a fixed order for
every person:

```
identityPanel → tagsEditSection → photos → contactRows → notes →
favoritesEditSection → aiSuggestions → relationships → encounters →
mentionedInMeetings → meetingHistory → decisions → tasks → memories →
attachedNotes → messages → provenanceFooter
```

The sections "Meeting history," "Decisions," "Mentioned in," and "Tasks" are
built for the work CRM use case. For a romantic partner, meeting history is
irrelevant (we don't have recorded Zoom calls). The section nav
(`PersonDetailView.swift:334–351`) always includes "Meetings" and "Tasks" even
when both are empty for this person. There is no "Relationship health" section,
no "Check-in log," no "How we're doing" section, no recurring patterns view.

The AI chat column (`PersonDetailView.swift:819–847`) is grounded with generic
prompts: "Give me a briefing," "What are my open tasks with them?" — appropriate
for colleagues, not partners.

### "Does my partner appear on Today?"

Yes, indirectly. `TodayView.swift:93–96` includes `SuggestedPeopleView` (from
transcript extraction) and `ReconnectView` ("Stay in touch"). If I haven't
logged an encounter in a while my partner may appear in "Stay in touch." That
is the **only** partner-specific surface on Today.

**What does not exist:**
- A "Partner check-in" prompt at any fixed cadence
- A morning nudge like "You haven't logged quality time with [partner] in 3
  days — how was yesterday?"
- A relationship health score or streak visible on Today
- A pinned partner card above the meeting feed (partners are not work meetings)

### "Do I get drift warnings?"

`ReconnectView` (`SuggestedPeopleView.swift:83–161`) does fire drift warnings,
but only if:
- `p.lastInteractionAt` is set (populated from encounters)
- The elapsed time > 1.5× inferred cadence from encounter gaps
- The person has at least 3 past encounters (falls back to 30 days otherwise —
  meaning a new partner entry with 0–2 encounters gets a blunt 30-day fallback,
  which is silent for the first month even if I haven't logged anything)

**No per-type override:** a romantic partner and a loose acquaintance share the
same 30-day fallback (`SuggestedPeopleView.swift:89`). There is no way to say
"flag me if I haven't logged anything with my partner in 2 days."

### "Will the app remind me if I haven't logged anything in a week?"

No. `NotificationManager.swift` schedules three notification categories:

1. `MEETING_START` — upcoming calendar meeting (line 49–60)
2. `IMPROMPTU_DETECTED` — Zoom call detected (line 63–68)
3. Daily brief at 8am (line 160–171)

**There is no `RELATIONSHIP_CHECKIN` category, no per-person nudge scheduler,
no "you haven't logged [partner] in N days" notification.** The daily brief
fires unconditionally and contains no relationship content.

`AppSettings` has `notifyAtMeetingStart: Bool` and `dailyBriefEnabled: Bool`
(`SettingsView.swift` pattern) — no relationship nudge toggle exists.

### "What AI help do I get on the partner profile?"

`PersonAISuggestions.swift` generates tags, relationships, and encounter
suggestions from meetings + profile context. The prompt template
(`PersonSuggestionEngine.generate`, line 31–48) is framed generically for a
"personal CRM." No partner-specific psychology (love languages, attachment
theory, Gottman repair bids) is embedded anywhere.

`ConversationAnalysisPreset` (`PersonDetailView.swift:23–148`) offers 6
presets: relationship summary, sentiment trends, topics, communication style,
action items, custom. The preamble hardcodes "adult professional named Tyler"
even when run against a romantic partner — this is both tonally wrong and
mildly risky (the "professional" framing is a model-safety workaround, but it
misaligns the output for personal context).

No preset exists for: "How have we been fighting lately?", "What are our
recurring conflict patterns?", "What have we celebrated together?", "Suggest a
date idea based on her favorites."

---

## 2. Existing Plan Items I Rank Highest (Through This Lens)

**PPL-1 (inline identity editing)** — already shipped; the click-to-edit panel
works. Good foundation but irrelevant for the partner use-case gap.

**Stay-in-touch nudges (already in ReconnectView)** — the infrastructure
exists; the per-type cadence override is the missing link. Endorsing this as the
highest-value small lift.

**TDY-1 (up-next hero)** — already shipped; not relevant to partner use-case.

**PPL-4 (unrecorded calendar meetings)** — ships meeting history for people
without recordings. Slightly useful for partners but not the core gap.

---

## 3. NET-NEW Recommendations

### U1-1: `relationshipType` field on `Person` — the root unlock (S effort)

Add `var relationshipType: RelationshipType = .professional` to
`Person.swift:77–184` with a `RelationshipType` enum:

```swift
enum RelationshipType: String, Codable, CaseIterable {
    case romantic, family, closeFriend, professional, acquaintance
}
```

Zero migration risk: tolerant decoder pattern already in place
(`Person.swift:196–222`). This single field unlocks every subsequent feature
without any existing behavior changing. Expose it in `AddPersonSheet` as a
picker (after Name, before Company), and in the inline identity edit panel.

**Why net-new:** P1-relationship-types agent also identified this gap. My
addition: make the field drive section visibility in `PersonDetailView` —
`.professional` → show Meetings/Tasks/Decisions first; `.romantic` → show
Encounters/Memories/Health first; hide the "Mentioned in meetings" section for
romantic/family types by default.

---

### U1-2: Relationship-type-gated section ordering in PersonDetailView (M)

Conditionalize the section order in `PersonDetailView.swift:241–258` on
`current.relationshipType`. For `.romantic`:

1. Identity panel
2. **Relationship health** (new — see U1-4)
3. Encounters (move UP — the most used section for a partner)
4. Memories
5. Photos + Favorites
6. AI suggestions (partner-tuned prompts)
7. Messages
8. Relationships (graph edges)
9. Tags
10. Contact / Meetings / Decisions / Tasks (collapsed by default)

The section nav chips already exist — reorder them dynamically. This is a
`.sectionNavItems` rewrite plus section ordering change, no new data model
needed. **File:line:** `PersonDetailView.swift:334–351`, `PersonDetailView.swift:241–258`.

---

### U1-3: Per-type check-in cadence override on Person + notification category (M)

Add `var checkInCadenceDays: Int?` to `Person` (nil = infer from history, same
as today). For `.romantic` default this to 2 (daily-ish). Add a
`RELATIONSHIP_CHECKIN` notification category to
`NotificationManager.swift:48–71`:

```swift
static let categoryRelationshipCheckin = "RELATIONSHIP_CHECKIN"
static let actionLogEncounter = "LOG_ENCOUNTER"
static let actionSnooze24h = "SNOOZE_24H"
```

Schedule a repeating check per person: if `person.lastInteractionAt` is older
than `checkInCadenceDays * 86400`, fire: "Haven't logged time with [partner]
in N days — how was yesterday?" with a "Log now" action that opens the quick-
log widget (U1-5). This is a genuine habit loop — the only one the app
currently lacks for personal relationships. **File:line:** `NotificationManager.swift:39–71`.

---

### U1-4: Relationship Health Score + Today strip (M)

Compute a lightweight `RelationshipHealthScore` for each person typed
`.romantic` or `.closeFriend`:

- **Recency component:** days since last encounter (lower = better)
- **Depth component:** encounter notes length + memory count (richer logs =
  healthier signal)
- **Streak component:** consecutive-days-with-log streak

Surface on the person's profile as a simple visual (color-coded arc, 0–100) and
as a small card on Today below the "Up next" hero for `.romantic` and
`.family` people. This gives the "relationship practice" feedback loop: you
log, you see the score move, you feel rewarded. **No model stored** — computed
from existing encounter + memory arrays on the fly to avoid stale data.

---

### U1-5: Quick-log encounter widget — "How was today?" (S)

A dedicated quick-log surface that does NOT require typing an event name.
`Encounter.eventName` is currently required (`Encounter.swift:25`); for a
partner quick-log, default it to "Quality time" or the person's first name +
today's date. The widget is a compact popover from Today or from the partner
profile header:

- Encounter kind picker: Date night / Quality time / Difficult conversation /
  Check-in call / Milestone
- Mood slider (1–5, emoji-mapped)
- Optional free-text note
- Optional photo attachment

This writes an `Encounter` with `eventName` prefilled from kind, so nothing
breaks in the existing model. **File:line gap:** `Encounter.swift:7` — add
`var kind: EncounterKind?` enum. `AddEncounterSheet` stays for detailed logs.

---

### U1-6: Partner-tuned AI analysis presets in ConversationAnalysisPreset (S)

When `current.relationshipType == .romantic`, add/swap presets in
`PersonDetailView.swift:23–148`:

- Replace "Pending action items" with "Recurring conflict patterns"
- Add "Celebration log" (what milestones/wins have we shared?)
- Add "Date idea from her favorites" (uses `current.favorites` as input)
- Fix the preamble to say "romantic partner" instead of "adult professional"
  when type is `.romantic`

The `ConversationAnalysisPreset` enum is `CaseIterable`; adding cases is a
one-file change. The template preamble is `func template(personName:
customPrompt:)` at `PersonDetailView.swift:84` — add a `personType`
parameter.

---

### U1-7: MCP tool `log_encounter` + `get_relationship_health` (M)

The MCP server (`Sources/MeetingScribeMCP/main.swift`) has `add_memory` and
`add_person` but **no way to log an encounter or read check-in history.** Claude
cannot answer "When did I last spend quality time with [partner]?" from a tool
call — only from a memory if the user manually typed one.

Add two tools:

```
log_encounter(person_id, kind, date?, notes?, mood?) → encounter id
get_relationship_health(person_id) → last_encounter, days_since, streak,
    recent_encounters[5], cadence_days
```

This makes partner-relationship data Claude-accessible in real time. The data
already exists in the JSON files; the MCP just needs read/write wiring.

---

### U1-8: "On this day" resurface for partner memories (S)

`TodayView.swift` already has `onThisDaySection` (line 87) — resurfacing
meetings from prior years on today's date. Extend this logic to resurface
**partner memories and encounters** dated to today's MM-DD in prior years:
"One year ago today: dinner at [restaurant]. What was going on then?"

This is a retention hook and a conversation starter. Requires filtering
`people.encounters(for: partnerID)` by month-day match.
**File:line:** `TodayView.swift:87`.

---

### U1-9: Partner pin / People sidebar shortcut (S)

The People list has no concept of pinned or prioritized contacts. For a daily
user managing a romantic partner, opening the People tab → scrolling → finding
the partner is 3–4 extra steps if the list is long.

Add a `var isPinned: Bool` to `Person` (off by default), surfaced as a context
menu item ("Pin to top") in the People list. Pinned people float to the top
regardless of sort. This also enables pinning on Today — the partner card
could live there permanently rather than only appearing when overdue. **File:line
gap:** `Person.swift:77` — no `isPinned` field.

---

### U1-10: Structured reflection templates as AttachedNote kinds (S)

`AttachedNote.kind` is a free-form string (`Person.swift:33`). For `.romantic`
type, add a "New reflection" button that prefills a structured template as a
draft `AttachedNote`:

- Weekly check-in (What went well / What was hard / What I appreciate / What
  I want to work on)
- Monthly relationship review (Same 4 sections + intention for next month)
- Conflict debrief (What happened / My role / Partner's perspective / Repair)

These write to `person.attachedNotes` as kind `"weekly-checkin"`,
`"monthly-review"`, `"conflict-debrief"`. They surface as a dedicated
"Reflections" section in the reordered partner view (U1-2). The MCP's `add_memory`
and `get_person` tools expose them immediately.

---

### U1-11: "Haven't logged [partner] in N days" Today banner (S)

A small, dismissible banner at the top of Today (above upNextCard) for any
person with `relationshipType == .romantic` or `.family` and
`lastInteractionAt` older than `checkInCadenceDays`. Text: "No log with
[name] in 4 days — tap to add a quick note." One tap opens the U1-5 quick-log
popover. Dismiss persists for 24h via `UserDefaults`.

This is the in-app complement to U1-3 notifications. **File:line:** insert
above `upNextCard` at `TodayView.swift:57`.

---

### U1-12: Partner-aware AI context in the chat column (S)

`PersonDetailView.swift:834–844` sets example prompts in the right-column chat.
When `current.relationshipType == .romantic`, swap to partner-tuned prompts:

- "How have we been doing emotionally lately?"
- "Summarize our last 5 logged encounters."
- "What patterns keep showing up in our conversations?"
- "Suggest something thoughtful based on what she's been dealing with."

Also update `updateChatContext()` (called at `.onAppear`) to inject the
relationship type into the Claude context string so the model knows it is
reasoning about a romantic partner, not a business contact. **File:line:**
`PersonDetailView.swift:272`, `PersonDetailView.swift:834`.

---

## 4. Top 3 Picks (Through This Lens)

1. **U1-1 (relationshipType field)** — the root unlock. An S-effort model
   change that gates every other improvement. Build it first.

2. **U1-3 (per-person check-in cadence + notification category)** — this is
   the habit loop the app completely lacks. Without a proactive nudge, a daily
   logging practice never forms. The notification infrastructure is already
   mature; adding one category and a scheduler is an M lift that delivers
   outsized retention value.

3. **U1-5 (quick-log encounter widget)** — the current encounter flow requires
   too many taps and an "event name" framing that is wrong for daily partner
   logging. A frictionless quick-log surface (kind picker + optional mood +
   note) is the difference between a habit that sticks and one that doesn't.
