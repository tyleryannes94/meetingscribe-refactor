# U2 — Family User Audit: The Parent-in-Another-City Scenario

**Lens:** A daily user who tracks relationship health with a parent living in another city. Needs call reminders, conversation logs, and friction-free "haven't talked in 2 weeks" awareness — not a CRM for colleagues but an emotional maintenance tool for the most important non-partner relationship in most adults' lives.

---

## The Scenario Narration

> "I haven't called my mom in 11 days. I open MeetingScribe and..."

### Step 1 — Adding Mom (`AddPersonSheet.swift`)

The sheet (`AddPersonSheet.swift:47–111`) opens to a clean form: name, company, role, emails, phones, address, favorites, birthday, tags, notes. The birthday field exists (`AddPersonSheet.swift:81–89`) — that's good.

**What's missing:** There is no `relationshipType`, `personCategory`, or `contactType` field anywhere in `Person.swift` or `AddPersonSheet.swift`. The only organizational primitives are free-form tags. To mark someone as "family" I have to manually create a "Family" tag — there's no first-class concept. The form's placeholder for "Event" names like "Purple Party 2026" (`AddEncounterSheet` at `PersonDetailView.swift:1900`) signals this is designed for social-scene tracking, not family maintenance. Adding my mother requires inventing an organizational convention from scratch.

There is also no field for relationship closeness, communication preference ("prefers phone calls over text"), or desired contact frequency — all natural data points for a family person record.

### Step 2 — Viewing Mom's Profile (`PersonDetailView.swift`)

The detail view is thorough: identity panel (inline edit), tags, contact rows with actionable mailto/tel links (`PersonDetailView.swift:1063–1085`), favorites, AI suggestions, relationships, encounters, meeting history, decisions, tasks, memories, attached notes, iMessage analysis. The section jump-rail (`PersonDetailView.swift:308–351`) helps navigate the 1986-line view.

**What's missing for a family user:**
- No "relationship type" banner or section that surfaces family-specific context (parents' city, living situation, health notes, names of other family members to ask about).
- The `Relationship` struct (`Person.swift:51–64`) uses a freeform `label` string — "mom" works, but the app never uses that label to unlock different UX, content, or cadence.
- The "Encounter" mental model is an event ("Purple Party 2026"). A phone call with mom doesn't fit that frame — there's no "interaction type" (phone call / video call / in-person visit / text exchange) and no duration field. The `Encounter` struct (`Encounter.swift:7–46`) has `eventName`, `location`, `notes`, `meetingID`, `voiceNoteID` — but no `type` enum. Logging "called mom for 20 minutes" requires entering an event name like "Phone call" and leaving location blank, which feels wrong for the model.
- No per-person call reminder. The identity panel has no "Remind me to call every N days" control.

### Step 3 — Logging Last Night's Call (`Encounter.swift`, `PersonDetailView.swift:1871–1936`)

I tap "Encounter" → `AddEncounterSheet` appears. I must fill in "Event" (required, `PersonDetailView.swift:1893`): the placeholder says "Purple Party 2026." I type "Phone call," pick today's date, leave location blank, write a note. Saved. The encounter appears in the encounters list.

**Friction:** The encounter model (`Encounter.swift`) has no `type` field to distinguish a phone call from an in-person visit. The `eventName` field is required and freeform — there is no picklist, no quick-log button ("Log a call now"), no duration. Logging a 25-minute catch-up call is a 5-field form originally designed for event tracking. The `Encounter.swift` model also stores `meetingID` and `voiceNoteID` cross-references, but there's no `phoneCallDuration` or `interactionMode` field.

### Step 4 — Will I Get a 2-Week Notification? (`NotificationManager.swift`)

Reading `NotificationManager.swift` top-to-bottom: the file schedules three notification types — meeting-start reminders (`syncScheduled`, line 79), transcription-complete (`notifyTranscriptionComplete`, line 141), and daily brief (`scheduleDailyBrief`, line 160). There is **no notification for "you haven't logged an interaction with this person in N days."**

The drift detection logic exists in two places:
- `ReconnectView` in `SuggestedPeopleView.swift:84–161`: computes overdue contacts using `cadenceSeconds` (median gap × 1.5, clamped 7–120 days, fallback 30 days) and surfaces them in the Today tab as a "Stay in touch" card.
- `PeopleInsightsView.swift:75–83`: the `goneCold` var fires at a hard-coded 45-day cutoff and shows a "Reconnect" card.

For my scenario (11 days, no notification): I would see nothing. The `ReconnectView` fallback cadence is 30 days — I'm at 11, so no nudge. The `PeopleInsightsView` fires at 45 days. There is **no system notification**, only in-app UI that requires me to already open the app. The "Stay in touch" card is Today-tab-only.

**Critical gap:** The entire nudge system is passive (in-app cards) and uses a single inferred-or-fixed cadence. There is no per-person configurable cadence, no macOS notification for drift, and no proactive prompt to log a call I just had.

### Step 5 — iMessage History (`MessagesAnalyzer.swift`)

`MessagesAnalyzer.analyze()` reads `~/Library/Messages/chat.db` and matches the person's phone numbers/emails to message handles. Six analysis presets exist (`PersonDetailView.swift:23–148`): relationship summary, sentiment trends, topics, communication style, action items, custom. These are genuinely useful.

**What works:** Running "Summarize relationship" on my message history with mom would give me a 3–5 sentence summary of how close/casual the relationship is and recent topics. The iMessage integration is real and working.

**What's missing:** The analysis presets are written for professional contacts ("adult professional named Tyler" in the preamble, `PersonDetailView.swift:86–91`). The prompt preamble explicitly frames both people as professionals — for a parent relationship this framing is awkward and could produce generic outputs. There's no family-specific preset (e.g., "What does she keep asking me to do?" / "What life events has she mentioned I should remember?").

### Step 6 — Drift Detection in Today Tab (`SuggestedPeopleView.swift`)

`ReconnectView` surfaces up to 4 overdue contacts sorted by most-overdue-first. The cadence computation (`SuggestedPeopleView.swift:95–101`) is clever but has a floor problem: a brand-new person with fewer than 3 encounters defaults to a 30-day cadence — so for a new-to-app family member with 1–2 logged calls, the nudge won't fire until day 30.

**What's missing:** The "Stay in touch" card shows name + "Last talked N days ago" + a chevron to open. There's no quick-log button here, no "Call now" action, no context about what was last discussed. Tapping opens the full profile — 3 more taps to log a call.

### Step 7 — Insights View (`PeopleInsightsView.swift`)

Birthday tracking works (`PeopleInsightsView.swift:86–97`) — my mom's birthday in the next 30 days would appear. The "Reconnect" card uses a 45-day hard cutoff (`goneColdDays = 45`, line 12). There's an inline "Mark reached out" checkmark button (`PeopleInsightsView.swift:29–34`) that bumps `lastInteractionAt` without logging an encounter — this is the quickest path to clearing the nudge, but it leaves no record of *what* was discussed.

---

## Existing Plan Items I Rank Highest (from my lens)

1. **PPL-1 (inline identity editing)** — already shipped per AUDIT_REPORT. Directly reduces friction for editing family member profiles. Endorse as complete.
2. **"Stay in touch" nudges (P2-1 from MASTER_PLAN_V3)** — the cadence inference is the right architecture. The 30-day fallback and 45-day `goneColdDays` constant need to be per-person configurable, not global hard-codes.
3. **Relationship TYPE PATHS** (from BRIEFING focus areas) — the briefing flags this as the primary audit bias. The code confirms: zero type-path differentiation exists today.

---

## NET-NEW Recommendations

### U2-1 — First-class `PersonCategory` enum on `Person` (S)

Add `var category: PersonCategory` to `Person.swift` with cases `.professional`, `.family`, `.partner`, `.closeFriend`, `.acquaintance`. Default `.professional` for imports, ask on first-create in `AddPersonSheet`. This single field unlocks every downstream type-path feature. No migration needed (tolerant decoder already handles missing fields, `Person.swift:196–`). Effort: S.

### U2-2 — `Encounter` interaction type + quick-log (S–M)

Add `var interactionType: InteractionType?` to `Encounter.swift` with cases `.phoneCall`, `.videoCall`, `.inPerson`, `.text`, `.email`. Add `var durationMinutes: Int?`. In the Today tab and on the person's profile, surface a "Log a call" button that pre-fills type=`.phoneCall` and opens a minimal 2-field sheet (duration + note). The "Purple Party 2026" placeholder in `AddEncounterSheet` (`PersonDetailView.swift:1900`) should change based on interaction type. Effort: S for model, M for UI.

### U2-3 — Per-person check-in cadence setting + macOS notification (M)

Add `var checkInCadenceDays: Int?` to `Person` (nil = inferred). Expose a stepper in `PersonDetailView` identity panel: "Remind me every ___ days." Wire `NotificationManager` to schedule a repeating `UNCalendarNotificationTrigger` per person when they exceed their cadence. The notification should say "You haven't logged a call with [Mom] in 14 days — tap to open or dismiss." This is the only missing notification type that matters for the family use case; `NotificationManager.swift` currently has zero such notifications. Effort: M.

### U2-4 — Family-specific iMessage analysis presets (S)

The `ConversationAnalysisPreset` enum (`PersonDetailView.swift:23–148`) has a `template(personName:customPrompt:)` method. Add two new cases gated on `person.category == .family`:
- `.lifeUpdates` — "What life events, health updates, or milestones has [Name] mentioned recently?"
- `.openLoops` — "What has [Name] asked me to do, remember, or follow up on that I haven't acknowledged?"

Remove the "adult professional" framing from the preamble when `category != .professional`. Effort: S.

### U2-5 — "Call now" one-tap from Stay-in-Touch nudge (S)

`ReconnectView` (`SuggestedPeopleView.swift:126–148`) shows name + chevron but requires tapping into the full profile to do anything. Add a `tel:` button inline if the person has a phone number, and a "Log call" button that opens a minimal encounter sheet. This reduces 4 taps to 1 for the most common family interaction. Effort: S.

### U2-6 — `goneColdDays` per-category default, not a global constant (S)

`PeopleInsightsView.swift:12` hard-codes `goneColdDays = 45` for everyone. Family contacts should use a shorter default (14 days). Professional contacts might warrant 60 days. Replace the constant with a `defaultCadence(for category: PersonCategory) -> Int` function that returns category-appropriate thresholds. Same fix needed in `ReconnectView`'s 30-day fallback (`SuggestedPeopleView.swift:89`). Effort: S.

### U2-7 — Conversation history card on profile: "Last time we talked…" (S)

`PersonDetailView` has an encounters section and a meeting history section, but nothing surfaces the most recent interaction prominently. Add a `lastContactSummary` computed view at the top of the profile (below the identity panel) that shows: last encounter date + type + one-line note, and days since. For family contacts, this should be the first thing visible — more important than tags or AI suggestions. Effort: S.

### U2-8 — Family context fields: health, city, life stage (S)

Add structured optional fields to `Person` for family-specific context: `var city: String?` (where they live), `var lifeStage: String?` (freeform: "retired, lives alone"), `var healthNotes: String?`. Surface these in a collapsible "Family context" section in `PersonDetailView` only when `category == .family`. These fields should feed the AI chat context (`personContextForAI()` at `PersonDetailView.swift:769`) so "Ask AI about Mom" responses are grounded in real context. Effort: S for model, S for view.

### U2-9 — MCP tool: `get_relationship_health` (M)

The 17-tool MCP server has `get_person`, `list_people`, `add_memory`, etc., but no tool that returns relationship health — days since last contact, upcoming birthday, open tasks, cadence status. Add `get_relationship_health(person_id)` that returns: `{ last_contact_days, cadence_days, overdue: bool, upcoming_birthday_days, open_tasks_count, last_encounter_summary }`. This enables Claude to proactively tell the user "You're overdue with your mom (14 days, cadence 10)" without the user having to open the app. Effort: M.

### U2-10 — Weekly family check-in digest notification (M)

Extend `scheduleDailyBrief()` (`NotificationManager.swift:160–171`) with a separate weekly "family check-in" notification (Sunday evening, configurable). Content: list of family-category people overdue for contact + their last contact date + any upcoming birthdays this week. This is a habit-formation nudge, not a reactive alert — it creates a ritual for Sunday relationship maintenance. Effort: M.

### U2-11 — Encounter "topics discussed" quick-tags (S)

Logging a call today has one freeform notes field. Add a multi-select `topicTags` to `Encounter` — chips like "health," "plans to visit," "venting," "asked for advice," "funny story" — that can be selected in one tap. These tags feed into the iMessage-style analysis context and into `personContextForAI()`. For a family user reviewing their relationship history, topic tags tell a richer story than free-text notes. Effort: S for model, S for UI.

### U2-12 — "They called me" vs. "I called them" direction on Encounter (S)

Add `var initiatedByMe: Bool?` to `Encounter`. Show a subtle directional badge in the encounter list. Over time, a pattern where the user never initiates is a relationship-health signal worth surfacing in the `lifeUpdates` analysis preset (U2-4). This is one bit of data with significant insight value for the family maintenance use case. Effort: S.

---

## Top 3 Picks

1. **U2-3 — Per-person check-in cadence + macOS notification.** The entire nudge system is in-app only. A family user who is already in the habit of checking the app doesn't need more in-app UI — they need a push notification on the Friday they've been too busy to call. This is the single feature that makes MeetingScribe irreplaceable vs. a sticky note on the monitor. `NotificationManager.swift` is already wired and organized; adding a new notification type is low-risk.

2. **U2-1 — `PersonCategory` enum.** Every other family-specific feature (U2-4, U2-6, U2-8) is gated on knowing which people are family. One new field on `Person` unlocks a dozen downstream improvements. This is the prerequisite for the entire family-user path.

3. **U2-2 — Encounter interaction type + quick-log.** The "Encounter" model and "Purple Party 2026" placeholder actively resist being used for phone calls. Adding `interactionType` and a one-tap "Log a call" button removes the primary logging friction. If logging a call takes more than 10 seconds, users will stop doing it — and then drift detection has no data to work with.
