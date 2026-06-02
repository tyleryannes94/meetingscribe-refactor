# U3 — Friend-User Audit: Managing 5 Close Friendships
**Lens:** A user intentionally maintaining 5+ close friendships — needs friend-specific check-in cadences, shared memory logging, and "I haven't seen X in 3 months" alerts.
**Auditor:** User-scenario subagent U3 (25-agent audit, 2026-06-02)

---

## Scenario

"I want to make sure I'm not letting my friendships drift. I have 5 people I care deeply about — Alex, Maya, James, Priya, and Rami. I see them at different intervals: some monthly, some every few months. I want the app to remind me when I'm drifting, let me log a coffee or dinner easily, and give me a profile that reflects the *friendship* — not just a professional CRM card."

---

## 1. Walking the Journey

### Can I see all 5 friends grouped?

`PeopleListView.swift:18–48` — The list is one flat pool filtered by tags and a search field. There is **no relationship-type concept anywhere** in `Person.swift:77–184`. Friends, colleagues, and vendors all sit in the same undifferentiated list, sorted by recency/name/meetings/newest (`PeopleSort`, lines 475–494).

To group my 5 friends I must create a tag called "Close Friends" and manually apply it to each one. `tagChips` (lines 422–449) then lets me filter by that tag. This works but it is a workaround — the tag slot is shared with event tags like "Purple Party 2026," so there's no semantic distinction between a social-circle tag and an event tag.

The `PersonRow` (lines 525–557) shows name, role/company subtitle, and last-interaction recency. For friends the role/company subtitle is empty or irrelevant — the row reads as a blank professional card. There is no visual cue distinguishing a close friend from a calendar import.

**Gap:** No first-class relationship type. No friend-optimized list row (no streak, no shared memory preview, no "seen X weeks ago" phrasing tuned for social context).

---

### What does a friend's profile look like vs. a colleague?

`PersonDetailView.swift:241–258` — Every person gets the identical 14-section single-page profile:

```
identityPanel → tagsEditSection → photosSection → contactRows → bio →
favoritesEditSection → aiSuggestionsSection → relationshipsSection →
encountersSection → mentionedInSection → meetingHistorySection →
decisionsSection → tasksSection → memoriesSection → attachedNotesSection →
messagesSection → provenanceFooter
```

The `identityPanel` (lines 391–508) has fields for name, role, company, email, phone, address, bio. These are professional-CRM fields. For Alex the friend, role and company are noise. There is no "How we met," "love language," "communication style," or "friendship anniversary" field.

The section jump-rail (`sectionNavItems`, lines 334–351) always includes Tags, Suggestions, Relationships, Encounters, Meetings, Tasks, Notes, Messages. For a friend, "Meetings" (work-recordings) is mostly empty and confusing; "Decisions" is a professional-workflow concept.

The `ConversationAnalysisPreset` prompt template (`PersonDetailView.swift:85–148`) anchors every analysis as "Tyler" + "adult contacts" in a professional framing. The `communicationStyle` preset (lines 123–133) asks about "tone, formality, message length, response speed" — all professional communication dimensions. For a friendship, the relevant lens is warmth, humor, how they give/receive support, what topics light them up.

**Gap:** A friend's profile is a professional CRM card with the role/company fields left blank. No emotional-depth framing anywhere in the view or its AI prompts.

---

### Logging "grabbed coffee with Alex today"

`Encounter.swift:7–46` — The app-side `Encounter` model has: `id`, `personID`, `eventTagID?`, `eventName`, `date`, `location?`, `notes`, `meetingID?`, `voiceNoteID?`, `createdAt`.

The model is **event-anchored**, not interaction-anchored. `eventName` is a required field — logging "grabbed coffee" means typing an event name ("Coffee with Alex"), which auto-creates a `MeetingTag` of kind `.event` every time (noted by D4 audit). This pollutes the tag namespace.

There is no `kind` enum: no way to mark an encounter as "coffee," "phone call," "shared activity," "dinner," "quick text exchange." No `duration` field, no `mood` or `energy` field, no "who initiated" field. The D4 audit (VaultKit/Encounter.swift) confirms a better-designed encounter model exists in VaultKit with a `Kind` enum (meeting/call/email/message/note) but it is **never surfaced** in the app UI.

The `AddEncounterSheet` is a modal launched from the identity panel shortcut button (line 490) or the encounters section header. It requires typing an event name every time; there's no quick-log affordance ("coffee" in one tap, "call" in another).

**Gap (NET-NEW):** No encounter kind, no quick-log shortcut, no mood/quality field. Every "coffee with Alex" permanently creates a tag. Friction is high enough that casual friend interactions go unlogged.

---

### Does it surface the friend I haven't seen in 3 months?

`SuggestedPeopleView.swift:83–161` — `ReconnectView` is the closest thing. Its cadence logic:

- Infers cadence from median gap between encounters (≥3 encounters required; line 96–101).
- Falls back to **30 days** for anyone with fewer than 3 encounters (line 89).
- Clamps inferred cadence to **7–120 days** (line 101).
- Flags overdue at **1.5× inferred cadence** (line 109).
- Surfaces up to **4 people** on Today's "Stay in touch" strip (line 113).

The 30-day fallback means a friend I see every 3 months gets flagged as overdue after 45 days (30 × 1.5), producing false-positive noise. There is no way to set "I try to see Rami every 90 days" as a manual intent.

The cap of 4 people (line 113) means if I have 5 friends plus colleagues who've gone cold, some of my friends may be hidden.

`PeopleInsightsView.swift:75–84` — `goneCold` uses a hard-coded 45-day cutoff (`goneColdDays = 45`, line 12) with no cadence inference, surfacing up to 8 people. It applies to everyone, not friends specifically.

`NotificationManager.swift:48–71, 159–171` — Three notification categories: meeting-start, impromptu-detected, daily-brief. **Zero relationship check-in notifications.** There is no scheduled "you haven't seen Alex in 87 days" push.

**Gap:** The drift alert system is blunt (fixed cutoffs, 30-day fallback), capped at 4 people on Today, has no friend-specific cadence intent, and fires zero system notifications for friendship drift.

---

### Friendship-specific insights?

`PeopleInsightsView.swift` — Three insight cards: Reconnect (gone-cold), Upcoming birthdays, Most active. All are CRM-generic. "Most active" is encounter count + meeting mentions — for a friend context, "most active" conflates professional meeting frequency with social richness.

No cards for: upcoming shared memories (anniversaries of how you met), friend-specific check-in streaks, friends who just had a life event (new job, new kid based on memories), or "you've seen James 0 times in the past 90 days."

**Gap:** The insights panel has the right bones (reconnect, birthday) but zero friend-specific signal.

---

### Does the relationship graph show friend clusters?

`PeopleGraphViewModel.swift:38–60` — Graph edges connect two people when they share ≥1 tag OR appeared in ≥1 meeting together. For friends, this means:

- Friends tagged "Close Friends" will cluster only if they also know each other.
- Two friends I know independently (Alex and Maya have never met) have **no edge** between them, so they appear as isolated nodes despite both being in my close-friend circle.
- The graph cannot show "my 5 close friends" as a cluster unless I engineer shared tags or they share meetings.

`GraphFilterBar.swift` — Filter is by tag only, no relationship-type filter. Searching for "Close Friends" tag surfaces the group but the graph still shows them disconnected.

**Gap:** The graph edges model mutual-knowledge/co-occurrence, not "I care about these people." A friend cluster is invisible unless friends all know each other.

---

### Friendship-drift notifications?

`NotificationManager.swift` — Exhaustive review: `MEETING_START` category (lines 48–61), `IMPROMPTU_DETECTED` category (lines 63–71), `scheduleDailyBrief` (lines 159–171). No friendship-drift category, no reconnect reminder, no scheduled "check in with Alex" notification. The daily brief notification body (line 167) mentions "yesterday's recap, today's meetings, and open commitments" — no mention of relationship nudges.

**Gap:** Zero proactive friendship-maintenance notifications exist.

---

### AI suggestions for friend maintenance?

`PersonAISuggestions.swift:8–23` — Three suggestion types: tags, relationships (graph edges), encounter titles. The `PersonSuggestionEngine` prompt (lines 31–47) asks the model to propose "groups like 'client', 'family', an event, a city" as tags. The word "friend" or any friendship-maintenance concept does not appear. Suggestions are one-time-generated CRM enrichments, not ongoing maintenance prompts.

The prompt instructs the model to be "conservative — only suggest things clearly supported by the context." For a friend where the context is sparse (few logged encounters, no work meetings), the model will have little to work with and produce few suggestions.

**Gap:** AI suggestions are CRM-population tools, not friendship-maintenance coaches. No "you haven't asked Alex about his job search" type prompt, no conversation-starter generation, no reflection prompts.

---

## 2. Existing Plan Items Worth Endorsing (through this lens)

| Item | Why it matters for friends |
|---|---|
| **PPL-1** (inline identity editing) | Reduces friction enough to actually keep friend profiles current. Right now editing a friend's "About" section requires a modal. |
| **Stay-in-touch nudges** (already planned, TDY-2 adjacent) | Core to this use case; the `ReconnectView` skeleton exists but the 30-day fallback + 4-person cap need to be fixed before it's useful. |
| **PPL-2** (multi-value contact fields) | Friends often have multiple ways to reach them (phone, Signal, Instagram). Dropping the 2nd value is a real loss. |

---

## 3. NET-NEW Recommendations

### U3-1 — `PersonType` enum: friend path (S, P0 for this use case)
Add `var personType: PersonType` to `Person.swift`. Enum cases: `.closeFriend`, `.family`, `.partner`, `.professional`, `.acquaintance`. Default `.professional` for imports; prompt on manual creation. This unlocks every downstream recommendation below. No schema migration needed — tolerant decoder already uses optional-with-default pattern (lines 199+). The `Relationship.label` freeform field (line 55) is insufficient because it describes the *graph edge*, not the *contact category*.

### U3-2 — Per-person intended cadence field (S)
Add `var intendedCadenceDays: Int?` to `Person.swift`. Let the user set "I want to see Rami every 90 days" in the identity panel. `ReconnectView` (SuggestedPeopleView.swift:95–101) should prefer this over the inferred median when set. The 30-day fallback (line 89) should be type-aware: close friends default 30, acquaintances default 90. Surfaces in the identity panel as "Check in every [N] days" next to `lastInteractionAt`.

### U3-3 — Encounter quick-log with kind (M)
Replace the required-`eventName` `AddEncounterSheet` with a quick-log bar on the friend's profile: a row of kind buttons (coffee, call, dinner, text, activity, video) that each log an encounter in one tap with a sensible event name auto-generated ("Coffee · June 2"). The existing sheet stays for detailed logging. No new tag is created for quick-logs — kind is stored as a field on a revised `Encounter.kind` enum. This directly addresses the friction that prevents daily/weekly interaction logging. File to change: `Encounter.swift:7–46`, `AddEncounterSheet`.

### U3-4 — Friendship-drift notification category (M)
Add a `FRIEND_DRIFT` notification category to `NotificationManager.swift`. Scheduled nightly at the same time as the daily brief scan: for each person with `personType == .closeFriend` and `lastInteractionAt` older than `intendedCadenceDays` (or 30-day default), fire a notification: "You haven't connected with Alex in 87 days. Open their profile?" Deep-link to the person. This is the single most-requested feature archetype in friendship-maintenance apps and is **completely absent**.

### U3-5 — Friend-aware profile sections (M)
Gate sections in `PersonDetailView.swift:241–258` by `personType`. For `.closeFriend`:
- Hide: `decisionsSection` (professional concept), `meetingHistorySection` header rename to "Shared time"
- Show first: `memoriesSection` (most relevant for friends), encounter timeline, messages
- Add: "Friendship since" date field, "How we met" memory (pinned), "Love language" tag from a small enum
- AI prompts in `ConversationAnalysisPreset`: replace professional preamble with friendship framing ("adult friends") and add friend-specific presets: "What to talk about next," "Recent life updates," "Gift ideas based on their interests"

### U3-6 — "My inner circle" Today strip (S)
On TodayView, add a persistent "Inner circle" horizontal scroll strip showing the user's `closeFriend` contacts in order of overdue-ness, with a colored ring (green = seen recently, yellow = due soon, red = overdue). One tap opens their profile. This is the daily glance that makes friendship maintenance a habit. Currently Today has "Stay in touch" (up to 4, sorted most-overdue-first) but it is not type-aware — a gone-cold work contact displaces a close friend.

### U3-7 — Friend cluster in graph via type, not edges (S)
`PeopleGraphViewModel.buildGraph` (line 38) adds edges by shared tag or co-meeting. Add a third edge rule: two people with `personType == .closeFriend` get a weak synthetic edge so they cluster together visually, regardless of whether they know each other. Weight this edge lower than real connections so the layout doesn't force unrelated friends into a tangle. Alternatively, add a "type layout" mode that groups nodes by `personType` into labeled zones (Friends | Family | Work). File: `PeopleGraphViewModel.swift:38–60`.

### U3-8 — Shared memory templates for friends (S)
Add a `Memory` template picker triggered when adding a memory on a `.closeFriend` profile. Template examples: "Life update," "Shared trip," "Inside joke," "What they need support with," "Gift idea," "Their big project right now." These are the signals a good friend tracks. Currently `memoriesSection` is a raw freeform text field — templates lower the activation energy and produce more structured data the AI can later query. File: `PersonDetailView.swift:memoriesSection`.

### U3-9 — MCP tool: `get_overdue_friends` (S)
Add a new MCP tool that returns people with `personType == .closeFriend` ordered by overdue-ness (days since last interaction vs. intendedCadenceDays). Exposes friend maintenance data to Claude so "who should I reach out to this week?" can be answered from the chat without opening the People tab. The current 17-tool server has no relationship-type-aware tool. File: `Sources/MeetingScribeMCP/main.swift`.

### U3-10 — `ReconnectView` cap raised + type-filtered (S)
Change `SuggestedPeopleView.swift:113` from `.prefix(4)` to `.prefix(8)` for close friends and `.prefix(3)` for others, with `.closeFriend` contacts always appearing before acquaintances regardless of raw overdue-ness. A user with 5 close friends should never have one hidden because a work contact went cold.

### U3-11 — Encounter logging from Today (S)
Add "Log encounter" as a swipe/right-click action on any person row in the "Stay in touch" card on Today. Currently the path is: Today → open person → scroll to encounters → tap add → fill sheet. Five steps. The quick-log (U3-3) should be accessible in 2 steps from Today.

### U3-12 — Friend check-in template (M)
Add a structured check-in template surfaced when a `closeFriend` drift notification is tapped. The template is a short form: "When did you last connect? (date picker) | How did it go? (mood chip: great / good / ok / strained) | What did you talk about? (freeform) | What do you want to remember? (freeform)". Submitting logs an encounter with kind, mood, and a memory. This is the habit loop: notification → template → logged. Without the template the user taps the notification, opens the app, and has no clear next action.

---

## 4. Top 3 Picks

| Rank | Item | Why first |
|---|---|---|
| 1 | **U3-3 — Encounter quick-log with kind** | Logging friction is the primary reason friend data stays empty. With no data, cadence inference fails, AI suggestions are weak, and the drift alerts are noisy. Fix the logging surface first; everything else is downstream. |
| 2 | **U3-4 — Friend-drift notification category** | The app never proactively interrupts the user on behalf of a friendship. Without a notification, the entire system is passive — it only surfaces friends who have already drifted when the user happens to open the app. A push notification closes the habit loop. |
| 3 | **U3-1 — `PersonType` enum** | All type-aware improvements (sections, cadence defaults, graph clusters, MCP tool, notification filtering) require a `personType` field. This is the prerequisite with the smallest surface area (one field on `Person`, one picker on creation/edit). Build it once; everything else composes on top. |

---

## 5. Single Highest-Priority Recommendation

**Build U3-3 (encounter quick-log) and U3-1 (PersonType) in the same sprint.**

The friend-user's core frustration is: "I grabbed coffee with Alex, but logging it is 5 taps and a required event name, so I don't bother." After two months of not logging, the cadence inference has no data, `ReconnectView` falls back to the 30-day default, and Alex shows up as "overdue" after 45 days even when you just saw him last week. The whole system degrades because the input is too hard.

A `closeFriend` type + a one-tap encounter kind strip on the profile fixes both the categorization and the logging friction simultaneously. It is the smallest change with the largest downstream cascade — better cadence data, better AI context, better drift alerts, better graph clustering. Effort: M (about 3 days of Swift work across `Person.swift`, `Encounter.swift`, `PersonDetailView.swift`, `AddEncounterSheet`).
