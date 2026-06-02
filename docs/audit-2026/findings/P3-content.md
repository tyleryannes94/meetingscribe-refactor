# P3 — Content & Learning Frameworks Audit
**Lens:** What relationship psychology content (Gottman, attachment theory, love languages, NVC, DBT interpersonal skills) should be embedded; exercise templates; reflection prompts per relationship type.

---

## 1. Lens Statement

MeetingScribe's People module currently operates as a CRM with iMessage analysis bolted on. There is no psychological framework content, no per-relationship-type reflection logic, and no structured exercise or check-in template system. The app can tell you *when* you last talked to someone but cannot help you understand *how* that relationship is going or what you could do differently. This audit identifies what content exists, what is missing, and the specific frameworks, delivery mechanisms, and data model additions needed to turn it into a genuine relationship coach.

---

## 2. What Content Currently Exists

### 2.1 AI Suggestions — Tags, Relationships, Encounters Only
`Sources/MeetingScribe/People/PersonAISuggestions.swift:8–72`

`PersonSuggestionEngine` generates three categories: `tags`, `relationships`, and `encounters`. The prompt (`PersonAISuggestions.swift:31–47`) treats the person as a CRM entry — the suggested enrichments are purely organizational ("groups like client, family, an event, a city"). There is no emotional tone, no reflection question, no prompt to consider what the relationship needs. The AI output schema has no field for a relationship health signal, a growth suggestion, or a framework-specific insight.

### 2.2 Conversation Analysis Presets — Generic, Framework-Free
`Sources/MeetingScribe/People/PersonDetailView.swift:23–148`

Six presets exist: `relationshipSummary`, `sentimentTrends`, `topicsThemes`, `communicationStyle`, `actionItems`, `custom`. The prompts (`PersonDetailView.swift:84–148`) are generic journalistic summaries ("how close/casual the relationship is," "general tone"). None reference attachment styles, love languages, Gottman's Four Horsemen, NVC needs vs. observations, or DBT DEAR MAN/GIVE skills. A `communicationStyle` analysis, for example, describes surface habits ("tone, formality, message length") with no framework to interpret them. The prompt preamble explicitly frames the pair as "adult professionals," which suppresses the emotional depth needed for partner/family/close-friend analysis.

### 2.3 Person Model — No Relationship Type Field
`Sources/MeetingScribe/People/Person.swift:77–185`

`Person` has `displayName`, `role`, `company`, `bio`, `memories`, `relationships`, `attachedNotes`, `favorites`, `birthday`. There is no `relationshipType` enum (partner / parent / sibling / close friend / colleague / acquaintance). The `Relationship` struct (`Person.swift:51–64`) has a freeform `label` ("spouse," "manager," "friend") but the app never branches UI or AI behavior on this label. There is no field for attachment style, love language, communication preference, or relationship health score.

### 2.4 Encounter Model — Event-Log, No Reflection Fields
`Sources/MeetingScribe/People/Encounter.swift:7–46`

`Encounter` has `eventName`, `date`, `location`, `notes`, `meetingID`, `voiceNoteID`. The `notes` field is pure freeform. There is no structured reflection: no "how did this interaction feel?", no "what went well / what was hard?", no rating, no framework tag (e.g., "quality time," "words of affirmation moment," "repair attempt").

### 2.5 NoteTemplate — Professional Templates Only, Zero Relationship Templates
`Sources/MeetingScribe/Models/NoteTemplate.swift:1–116`

Five templates exist: `meeting-notes`, `one-on-one`, `standup`, `decision-log`, `weekly-review`. All are workplace-professional. No relationship check-in templates, no partner debrief template, no family visit template, no friend reconnection template. The template system is Phase 4 and wired to a slash menu — it is the right delivery mechanism but the relationship content doesn't exist.

### 2.6 PeopleInsightsView — Recency, Birthdays, Activity Only
`Sources/MeetingScribe/People/PeopleInsightsView.swift:7–155`

Three insight cards: "Reconnect" (gone cold, 45-day cutoff), "Upcoming birthdays," "Most active." The "Reconnect" card is the closest thing to a relationship health signal, but it is purely time-based with no context about relationship type, why the contact is important, or what kind of reconnection would be meaningful. A partner who hasn't been "logged" in 45 days gets the same card as an acquaintance.

### 2.7 MCP — People Tools Are Read/Write CRM, No Relationship-Coaching Surface
`Sources/MeetingScribeMCP/main.swift:733–881`

MCP tools: `list_people`, `get_person`, `get_person_messages`, `list_person_meetings`, `add_person`, `add_memory`, `create_meeting_note`. Claude via MCP can read memories, relationships, messages, and meetings, and can write memories and add people. There is no tool to read or write: relationship type, love language, attachment style, check-in templates, reflection prompts, or relationship health data. Claude cannot currently suggest a Gottman exercise or deliver a DBT skill prompt through the MCP surface.

### 2.8 NotificationManager — Meeting Nudges Only
`Sources/MeetingScribe/Notifications/NotificationManager.swift:159–181`

Notifications are wired for: pre-meeting alerts, daily brief (8am), impromptu recording detection. No per-person check-in reminders, no recurring relationship habit prompts ("You haven't had a quality conversation with [partner] logged this week"), no relationship-type-specific nudges.

---

## 3. Existing Plan Items I Rank Highest (from This Lens)

| ID | Plan Item | Ranking | Why It Matters for Content |
|---|---|---|---|
| PPL-1 | Inline field editing (click-to-edit name/role/company) | High | Required for the `relationshipType` field I'm proposing — a modal-only edit flow blocks users from quickly classifying their contacts |
| PPL-2 | Multi-value contact fields | Medium | Structural prerequisite for storing multiple love languages, communication preferences per person without one-value-overwrites-another bugs |
| TDY-1 | "Up next" hero strip | Medium | The right delivery slot for a relationship check-in prompt scheduled around a meeting with a close contact |
| per-tag summary templates (from BRIEFING existing plan) | Tag-scoped templates | High | Already planned as NoteTemplate extension — relationship type templates should land here |

---

## 4. NET-NEW Recommendations

### P3-1: Add `RelationshipType` Enum to Person Model
**Effort: S**

Add a first-class typed field to `Person.swift` alongside the freeform `relationships` array:

```swift
enum RelationshipType: String, Codable, CaseIterable {
    case romanticPartner, spouse
    case parent, child, sibling
    case closeFriend
    case colleague, manager, report
    case acquaintance
    case mentor, mentee
}
var primaryRelationshipType: RelationshipType?
```

This single field unlocks every other recommendation below. The freeform `Relationship.label` can be inferred into this type on import (if label contains "spouse" → `.spouse`). Surface it as a picker in the identity panel — one tap above the role/company fields. Drives distinct UI sections, AI prompt branching, check-in cadence, and framework selection.

### P3-2: Relationship-Type-Specific AI Analysis Presets
**Effort: M**

Extend `ConversationAnalysisPreset` with type-aware branches. Currently the preamble hard-codes "adult professionals" even when analyzing messages with a romantic partner. Add:

- **Partner preset**: Gottman lens — scan for criticism, contempt, defensiveness, stonewalling (Four Horsemen); note bids for connection responded to or missed; highlight repair attempts. Remove "professional" framing from preamble.
- **Family preset**: NVC lens — distinguish observations from evaluations; identify underlying needs being expressed; note guilt/obligation language vs. genuine request language.
- **Close Friend preset**: love language inference — which language does this person seem to use and respond to? Quality time signals (making plans), words of affirmation (compliments given/received), acts of service (offers to help).
- **Colleague preset**: keep the existing professional framing; add DBT DEAR MAN check — did asks get made clearly with stated rationale?

Branching is simple: `ConversationAnalysisPreset.template(personName:customPrompt:)` accepts an optional `RelationshipType` parameter and selects the appropriate framework framing.

### P3-3: Relationship Check-In Templates in NoteTemplate
**Effort: S**

Add five relationship-type-specific templates to `NoteTemplate.all` (currently only professional templates exist):

- **Partner check-in** (`partner-checkin`): "What's working well between us this week? / What's felt hard or unspoken? / What do I appreciate about them that I haven't said? / One thing I want to ask for / One thing I can offer."
- **Family visit debrief** (`family-debrief`): "How did I feel arriving vs. leaving? / What dynamic showed up that I want to understand better? / What did I appreciate? / What boundary or need do I want to communicate differently next time?"
- **Friend reconnection** (`friend-reconnect`): "What did we talk about? / How did they seem — energetically, emotionally? / What do they need support with? / What do I want to do together next?"
- **Gottman Daily Check-In** (`gottman-daily`): "One thing I noticed my partner did today (observation, not evaluation) / My emotional bid response today / What repair looks like if needed."
- **Attachment Moment** (`attachment-moment`): "Did I reach for or pull away? / What was underneath that? / What would secure behavior have looked like?"

These drop into the existing slash menu with zero schema changes.

### P3-4: Structured Encounter Reflection Fields
**Effort: S–M**

Extend `Encounter` with opt-in reflection metadata:

```swift
var qualityRating: Int?        // 1–5, optional
var frameworkTag: String?       // "quality-time", "repair-attempt", "bid-missed", "NVC-moment"
var reflectionNote: String?     // "What I noticed about myself in this interaction"
var emotionAfter: String?       // free-form or enum: "warm", "drained", "grateful", "unresolved"
```

The `AddEncounterSheet` gains an optional "How did it feel?" section (collapsed by default, tap to expand — no friction for quick logs). These fields are scored by the AI in P3-2 analyses and surfaced in P3-7's relationship health dashboard.

### P3-5: Per-Person Check-In Cadence (NotificationManager Extension)
**Effort: M**

Add to `Person`:

```swift
var checkInCadenceDays: Int?    // nil = off; 7 = weekly; 14 = biweekly; 30 = monthly
var lastCheckInAt: Date?
```

`NotificationManager` gains a `syncRelationshipCheckIns(for people: [Person])` method alongside `syncScheduled(for meetings:)`. Per-person notifications fire at a configurable time (default 7pm) on the interval: "Time to check in with [name] — you haven't logged an interaction in [N] days." Tapping opens the person directly. Cadence defaults by relationship type: partner → 1 day (daily brief, not notification-spam), close friend → 7 days, family → 14 days, colleague → 30 days. The user can override per person. This is the "habit loop" the product brief calls for and nothing in the existing plan covers.

### P3-6: Love Languages Profile Field + Inference
**Effort: S (field) + M (inference)**

Add to `Person`:

```swift
var loveLanguage: LoveLanguage?
struct LoveLanguage: Codable {
    var primary: String    // "quality_time", "words", "acts", "gifts", "touch"
    var notes: String      // "responds well to specific compliments, not generic"
}
```

The field is manually settable from the identity panel. The AI analysis preset (P3-2, friend/partner branch) infers it from message history and suggests it: "Based on 6 months of messages, [Name] frequently initiates plans (quality time), often thanks you for help (acts of service), and rarely uses physical affection language. Suggested primary: quality time." The suggestion card follows the existing `PersonAISuggestions` pattern — surfaced as a dismissable card, one tap to accept.

### P3-7: Relationship Health Dashboard in PeopleInsightsView
**Effort: M**

Replace/extend the three-card `PeopleInsightsView` with a relationship health section for people who have `primaryRelationshipType = .romanticPartner`, `.closeFriend`, or family types:

- **Partner card**: last encounter date + quality rating average over last 30 days + Gottman ratio (positive-to-negative moment balance, estimated from encounter `frameworkTag` values). Alert when ratio drops below 5:1.
- **Close friends card**: "You've seen [Name] [N] times in the past [X] days. Their usual pattern with you is [frequency estimate]. They may be drifting — reach out?" (Uses encounter frequency to detect drift, not just last-interaction date.)
- **Family card**: upcoming visit dates + debrief notes count.

The existing "Reconnect" card (45-day cutoff, same for everyone) becomes type-aware: partners get a 3-day alert, close friends 14 days, family 30 days, colleagues 45 days. This is a direct enhancement to `PeopleInsightsView.swift:76–83` where `goneColdDays` is currently a hard-coded constant.

### P3-8: Attachment Theory Profile Field + Context Injection
**Effort: S (field) + M (AI use)**

Add to `Person`:

```swift
var attachmentStyle: AttachmentStyle?
enum AttachmentStyle: String, Codable {
    case secure, anxious, avoidant, disorganized
}
var myAttachmentDynamic: String?  // freeform: "I tend to get anxious when they go quiet"
```

This is for self-reflection, not labeling others. The field surfaces in the identity panel under a "Relationship context" collapsible section (not always visible — sensitive data). When set, the AI analysis presets inject the style into the prompt: "The user identifies an anxious dynamic with this person — flag moments in the messages where this might be showing up." The `custom` preset's sheet gains a hint: "Tip: mention their attachment style for deeper analysis."

### P3-9: MCP Tools for Relationship Coaching Data
**Effort: M**

Add four MCP tools to `main.swift`:

1. **`get_relationship_profile`** — returns `primaryRelationshipType`, `loveLanguage`, `attachmentStyle`, `checkInCadenceDays`, `lastCheckInAt`, `qualityRating` average for a person. Claude can use this to tailor any response.
2. **`log_encounter`** — write an encounter with `qualityRating`, `frameworkTag`, `emotionAfter`, `reflectionNote`. Currently there is no MCP tool to log an encounter at all. Claude in a chat session should be able to say "I'll log this conversation as a quality-time encounter" and do it.
3. **`get_relationship_health`** — returns the Gottman ratio, check-in streak, days since last encounter, and a flag if the cadence is overdue. Claude can proactively surface: "You haven't logged quality time with [partner] in 5 days — want me to log something?"
4. **`set_relationship_context`** — write `attachmentStyle`, `loveLanguage`, `checkInCadenceDays`, `myAttachmentDynamic` to a person. Lets Claude guide a "set up your relationship profile" onboarding conversation and write the results.

### P3-10: Encounter Quick-Log from Today View (Relationship Habit Entry Point)
**Effort: S**

The `TodayView` already has a "suggested people" surface (from the BRIEFING's existing plan). Add a one-tap "Log a moment" button per suggested person that opens a half-sheet: pre-filled with today's date, the person's name, and the first available template for their relationship type (P3-3). The user writes one sentence and taps Save — 10 seconds total. This is the habit formation entry point. Without a frictionless daily entry point, the reflection templates (P3-3) and encounter fields (P3-4) will go unused regardless of how good the content is.

### P3-11: DBT DEAR MAN / GIVE / FAST Prompt on Tough Conversations
**Effort: S**

Add a "Prepare for a hard conversation" affordance to the person's detail view — a button in the action menu (ellipsis) that opens a structured DBT-framed prompt sheet:

- **DEAR MAN section**: "Describe the situation (facts only): / Express how you feel: / Assert what you want: / Reinforce why it matters to them: / Stay mindful — what's the one thing you want them to know? / Appear confident (what's your opening line?): / Negotiate — what would you accept instead?"
- **GIVE section** (relationship preservation): "Be Gentle — how will you avoid attacks? / Act Interested — what question will you ask? / Validate — how will you show you understand their perspective? / Use Easy Manner — how will you keep the tone light?"

The output from filling this sheet auto-populates a pre-meeting brief (stored as an `AttachedNote` with `kind = "difficult-conversation-prep"`). Claude via MCP can read this note and use it as context when the user asks for coaching after the conversation.

### P3-12: Relationship Framework Onboarding for New Close Contacts
**Effort: S**

When a user sets `primaryRelationshipType` to `romanticPartner`, `closeFriend`, or a family type, trigger a one-time contextual onboarding card (dismissable, inline in the person's detail view): "Want to get more from your time together? Take 2 minutes to set up a relationship profile." Card links to: (a) love language quick-picker (5 cards, tap the one that fits), (b) check-in cadence selector, (c) one reflection question ("What's one thing you want to work on in this relationship?"). This populates the fields added in P3-6, P3-5, and P3-8. Without a prompted setup flow, these fields will sit empty for most users. Effort is S because the UI is a single card + existing sheet pattern; the fields already exist after P3-5/6/8.

---

## 5. Top 3 Picks

### Pick 1 (Highest Priority): P3-2 — Relationship-Type-Specific AI Analysis Presets
The conversation analysis feature is already built and used. The marginal cost to add Gottman/NVC/love-language branching is a prompt rewrite — no schema changes, no new UI, no new infrastructure. The gain is immediate: a user analyzing iMessages with their partner goes from a generic "tone: warm, topics: weekend plans" to a Gottman-lens reading that flags a missed bid for connection or a repair attempt. This is the fastest path from zero psychological framework to first-class relationship coaching content. Effort: M. Unblocked right now.

### Pick 2: P3-1 + P3-5 (bundled) — RelationshipType Field + Per-Person Check-In Cadence
These two are interdependent and together constitute the foundation every other recommendation builds on. `RelationshipType` makes AI prompts smarter (P3-2), makes templates relevant (P3-3), makes insights type-aware (P3-7), and makes the MCP surface meaningful (P3-9). The cadence notification (P3-5) is the habit loop — without recurring prompts, users open the People tab only when they already remember someone. Total effort: M+S = one focused sprint.

### Pick 3: P3-10 — Encounter Quick-Log from Today View
Content frameworks fail if entry is friction-heavy. The reflection templates (P3-3), structured encounter fields (P3-4), and health dashboard (P3-7) all require data to work. A 10-second log-a-moment flow from TodayView, pre-populated with the relationship type template, is the habit-formation wedge. Today's "suggested people" card already surfaces the right person at the right time — the missing piece is a one-tap action that captures the moment before it's forgotten. Effort: S.

---

## 6. Delivery Mechanism Recommendation

Content should be delivered in three modes — not all inline:

| Mode | When | What |
|---|---|---|
| **Inline on demand** | User opens a person's detail | Framework-aware analysis presets (P3-2), DEAR MAN prep sheet (P3-11), relationship profile onboarding card (P3-12) |
| **Scheduled / habitual** | Check-in cadence notification (P3-5), Today view daily | Quick-log encounter (P3-10), partner daily brief, check-in prompts |
| **Retrospective** | After logging an encounter or after a meeting | "How did it go?" reflection prompt auto-offered when encounter is added for a close/partner type person |

Avoid putting framework content behind deep navigation. Gottman ratios buried in a sub-sub-view will never be seen. The rule: any content a user should encounter regularly must be reachable from Today view or a notification in ≤2 taps.
