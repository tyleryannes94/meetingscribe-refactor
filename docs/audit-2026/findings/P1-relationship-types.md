# P1 — Relationship Type Architecture
**Lens:** Product Strategy — Partner / Family / Close Friend type paths, each with its own onboarding, check-in cadence, content library, and UI emphasis.
**Auditor:** Product Strategy subagent (25-agent audit, 2026-06-02)

---

## 1. Current-state evidence

### Person model — no relationship type field (anywhere)

`Sources/MeetingScribe/People/Person.swift` is the canonical on-disk record (77 fields, lines 77–184). There is **no `relationshipType`, `closenessLevel`, `pathType`, or equivalent field** anywhere in the struct. The nearest concept is:

- `relationships: [Relationship]` (line 119) — a *graph edge* to other people (`toPersonID` + `label`). The label is a freeform `String` (e.g. "spouse", "manager", "kid", "friend") with zero semantic enforcement. `Relationship.swift:56`.
- `tagIDs: Set<String>` (line 92) — reuses the MeetingTag namespace; "family" can be stored as a tag but there is no typed distinction between a CRM event tag (Purple Party 2026) and a relationship category tag (Family).

`Sources/VaultKit/Person.swift` (VaultKit's Foundation-only mirror, lines 1–47) is even sparser: `name`, `emails`, `company`, `role`, `notes`, `tags`. No relationship-type concept.

`Sources/VaultKit/SharedModels.swift` — `PersonDTO` (lines 186–277) and `PersonRelationshipDTO` (lines 175–183) expose the same structure to the MCP servers. No type enum.

**Verdict:** The relationship-type layer is **completely absent** from every model layer — app model, VaultKit DTO, and MCP surface.

---

### Check-in / cadence — blunt inference only

`Sources/MeetingScribe/People/SuggestedPeopleView.swift:81–161` contains `ReconnectView`, which is the only cadence logic in the codebase. It:
- Infers cadence from the median gap between encounters (3+ needed; line 96–101).
- Falls back to 30 days for anyone with fewer than 3 encounters (line 89).
- Clamps to 7–120 days (line 101).
- Flags overdue at 1.5× inferred cadence (line 109).
- Renders up to 4 names on Today's "Stay in touch" strip (line 113).

There is **no per-type cadence override**, no structured check-in template, no habit loop, no notification category for relationship nudges. The 30-day blunt fallback makes a romantic partner and a loose acquaintance indistinguishable.

`Sources/MeetingScribe/Notifications/NotificationManager.swift` has three notification categories: meeting-start, impromptu-detected, and daily-brief (line 48–71, 159–171). Zero relationship check-in categories.

---

### UI — single undifferentiated profile surface

`Sources/MeetingScribe/People/PersonDetailView.swift` renders every person through the same 14-section single-page profile (lines 241–258):
```
identityPanel → tagsEditSection → photosSection → contactRows → notes →
favoritesEditSection → aiSuggestionsSection → relationshipsSection →
encountersSection → mentionedInSection → meetingHistorySection →
decisionsSection → tasksSection → memoriesSection → attachedNotesSection →
messagesSection → provenanceFooter
```
A close friend and a vendor contact get the exact same view. There is no type-gating on which sections appear. The AI analysis presets (`ConversationAnalysisPreset`, lines 23–148 of PersonDetailView.swift) — summary, sentiment, topics, communication style, action items, custom — are type-agnostic: they use the same prompt framing ("adult professional named Tyler") regardless of whether the person is a romantic partner or a client.

---

### AddPersonSheet — no type selector

`Sources/MeetingScribe/People/AddPersonSheet.swift` collects: name, company, role, email, phone, address, favorites, birthday, tags, bio (lines 14–41). No path selection. No "How do you know this person?" step. No onboarding differentiation between a new romantic partner and a new colleague.

---

### Encounter model — kind enum exists but is underused

`Sources/VaultKit/Encounter.swift:7–9` has `Kind: {meeting, call, email, message, note}`. But `Sources/MeetingScribe/People/Encounter.swift` (the app-side version) has no `Kind` field at all — it uses `eventTagID + eventName + notes`. The VaultKit Kind enum is richer but lives in the shared layer and is not surfaced in any UI picker or AI prompt.

---

### MCP — write tools do not touch relationship type

`Sources/MeetingScribeMCP/main.swift` tools relevant to people (lines 1429–1436):
- `list_people` / `get_person` / `get_person_messages` / `list_person_meetings` — read-only, no type field exposed
- `add_person` (line 1289) — writes `display_name`, `company`, `role`, `emails`, `phones`, `bio` — **no `relationshipType`**
- `add_memory` (line 1339) — appends a memory string — no type context used in prompting
- No `update_person`, no `log_checkin`, no `set_checkin_cadence` tool exists

Claude via MCP cannot know whether it's talking about a romantic partner or a coworker, cannot set a custom check-in cadence, and cannot log a structured check-in encounter.

---

## 2. Existing plan items most relevant to this lens

Items already planned that this work depends on or should align with:

| Plan item | Relevance |
|---|---|
| **PPL-1** inline identity editing | Any type-path UI depends on identity fields being fast to edit; do PPL-1 first |
| **PPL-2** multi-value contact fields | Partner/family often have multiple phones; prerequisite for clean profile |
| **"stay in touch" nudges** (SuggestedPeopleView) | Cadence logic is the hook — extend it, don't rebuild it |
| **per-tag summary templates** | Relationship type can drive per-type prompt templates at the same layer |
| **god-file decomposition** (PersonDetailView 1986 lines) | Type-path sections will add hundreds more lines; decompose first |

**Endorse from existing plan:** per-tag summary templates and the nudge infrastructure are the two best anchors for the type-path work. They already demonstrate the pattern; we extend it.

---

## 3. NET-NEW recommendations

### P1-1 — Add `RelationshipPath` enum to `Person` (minimal viable schema change)
**Effort: S** — hours

Add a single optional typed field to `Person` with backward-compatible decoding:

```swift
enum RelationshipPath: String, Codable, CaseIterable, Sendable {
    case partner       // romantic partner / spouse
    case family        // parent, sibling, child, extended
    case closeFriend   // intimate friend, inner circle
    case friend        // regular friend
    case colleague     // professional, default if nothing set
    case acquaintance  // loose connection
}
```

Add `var relationshipPath: RelationshipPath?` to `Person.swift` (defaulting to `nil` / `.colleague` on decode). Mirror in `PersonDTO` in `SharedModels.swift` and `VaultKit/Person.swift`. This is a one-field addition with tolerant decode — zero migration risk.

**Why now:** every other recommendation in this document requires this field. It is the keystone.

---

### P1-2 — Type-aware `AddPersonSheet` onboarding step ("How do you know them?")
**Effort: S**

Prepend a step-0 to `AddPersonSheet` when `editing == nil`: a 3-card picker:

```
[ Romantic partner ]   [ Family member ]   [ Close friend ]
[ Colleague ]          [ Acquaintance ]
```

Each card shows a one-line description ("your spouse, partner, or significant other"). Selection sets `relationshipPath`. Skip link for people who don't want to categorize. For `partner` and `family`, a secondary question appears: "What's the relationship label?" (spouse / partner / parent / sibling / child / other) — this populates the freeform `Relationship.label` on the self-referential graph edge, not just the path enum.

The current sheet is 460×540 (`AddPersonSheet.swift:111`). Widen to 500×580 to accommodate the card row without scrolling.

---

### P1-3 — Per-type check-in cadence overrides with UI control
**Effort: M**

`ReconnectView.cadenceSeconds()` (`SuggestedPeopleView.swift:95`) today infers cadence purely from encounter history. Extend it:

1. Add `var checkInCadenceDays: Int?` to `Person` (nil = infer, otherwise explicit override).
2. In `PersonDetailView`, add a "Check-in cadence" row below the Encounters section header: a `Picker` or `Stepper` showing "Every N days" with sensible defaults by path:
   - `.partner` → 1 day (daily)
   - `.family` → 7 days (weekly)
   - `.closeFriend` → 14 days (biweekly)
   - `.friend` → 30 days (monthly)
   - `.colleague` → infer (existing behavior)
   - `.acquaintance` → 90 days
3. `ReconnectView.cadenceSeconds()` reads `checkInCadenceDays ?? inferredCadence`.
4. The "Stay in touch" strip on Today prioritizes by path order: partner first, then family, then closeFriends.

This replaces the blunt 30-day fallback with emotionally appropriate defaults.

---

### P1-4 — Structured check-in templates per relationship type
**Effort: M**

Add a `CheckInTemplate` concept: a pre-filled `AddEncounterSheet` variant that appears when the user taps "Check in" from the "Stay in touch" nudge instead of just opening the profile. Templates differ by type:

**Partner:** "How are we doing this week?" → sections: energy / stress / gratitude / what I appreciate / upcoming needs. Maps to Gottman's Four Horsemen prevention (what went well, what's one repair to make).

**Family:** "Monthly family check-in" → sections: what's new in their life, things I want to remember (birthdays near, health, milestones), one thing I want to do together.

**Close friend:** "Catch-up log" → when did we last talk, what did we cover, what do I want to follow up on, how are they really doing.

Each template writes an `Encounter` with a `notes` blob containing the structured fields as Markdown. The template is rendered as a focused mini-form (`Sheet`, ~400×520), not the full-profile view. Tapping "Done" saves the encounter and updates `lastInteractionAt`.

Implementation: add `CheckInTemplateSheet.swift` (new file ~200 lines) + a `checkIn(for:)` factory method that returns the right sheet variant from `RelationshipPath`.

---

### P1-5 — Type-gated PersonDetailView section ordering and AI prompt framing
**Effort: M**

The current section order (`PersonDetailView.swift:241–258`) is universal. Gate and reorder by path:

| Section | partner | family | closeFriend | colleague | acquaintance |
|---|---|---|---|---|---|
| Check-in status / streak | first | first | first | hidden | hidden |
| Love languages / communication style | show | show | show | hidden | hidden |
| Memories | expanded | expanded | expanded | collapsed | hidden |
| Encounters | full | full | full | condensed | condensed |
| Work info (company, role) | hidden | hidden | optional | first | first |
| Messages analysis | show | show | show | show | optional |
| Tasks | condensed | condensed | condensed | full | full |

Change `ConversationAnalysisPreset.template()` (`PersonDetailView.swift:84–148`) to accept a `RelationshipPath` and adjust the preamble: for `partner`, replace "adult professional" framing with "romantic partner / spouse" framing and add context about emotional attunement. For `family`, add family-systems framing. These prompt changes are safe and dramatically improve AI output relevance.

---

### P1-6 — Relationship health score card (partner + closeFriend paths only)
**Effort: M**

For `.partner` and `.closeFriend`, add an optional "Health" section at the top of PersonDetailView: a compact card showing:
- Days since last check-in (vs. cadence target)
- Streak: "N check-ins in a row on schedule"
- One AI-generated prompt: "Based on recent memories and messages, one thing worth appreciating about [name] this week…" (runs only when the card is expanded, uses the last 200 messages and recent memories as context)

This is the habit loop: the user sees the card → opens the profile → reads the appreciation prompt → takes action → logs a check-in → streak increments. No gamification badges needed — the streak number is enough.

The health card lives in `PersonDetailView` behind a `if current.relationshipPath == .partner || current.relationshipPath == .closeFriend { healthCard }` guard. It can be hidden by the user.

---

### P1-7 — Per-type AI coaching prompts embedded in the profile
**Effort: M**

Add a `RelationshipCoachSection` (new view, ~150 lines) that replaces or augments the generic `aiSuggestionsSection`. Content differs by path:

**Partner path:** Gottman-based rotating prompts. Examples:
- "Ask [name] one 'open dream' question this week — what are you hoping for most right now?"
- "The Gottman 5:1 ratio: did you have 5 positive interactions for every difficult one this week?"
- Bids for connection tracker: "Log a moment you turned toward each other."

**Family path:** Positive psychology + life-stage awareness:
- Birthday 30 days out → "Your mom's birthday is in 30 days. What would make her feel seen?"
- For a parent: "What's one story from their past you've never asked about?"

**Close friend path:** NVC + proximity maintenance:
- "When did you last tell [name] something real? Not logistical — something true."
- "Is there anything unresolved between you? Name it, then decide if it matters."

These are stored as a rotating prompt library per path (JSON or Swift enum), not AI-generated — they load instantly and are psychologically grounded. AI is only invoked when the user wants a personalized variant.

Implementation: add `Sources/MeetingScribe/People/RelationshipCoachContent.swift` (~200 lines) containing the prompt library, plus `RelationshipCoachSection.swift` (~150 lines) for the view.

---

### P1-8 — PeopleList grouping and visual distinction by relationship type
**Effort: S**

`PeopleListView.swift` currently groups by tag filter or sorts by recency/name/meetings (lines 42–61). Add a `RelationshipPath` grouping mode: "Inner circle" (partner + family + closeFriends) floated to the top with a subtle section divider, then friends, then colleagues/acquaintances. Each path gets a distinct icon in the sidebar row:
- Partner: `heart.fill`
- Family: `house.fill`
- Close friend: `star.fill`
- Friend: `person.fill`
- Colleague: `briefcase.fill`

This grouping is toggled via the existing sort menu (add `.innerCircle` to `PeopleSort`). It does not replace tag-based filtering — tags and type coexist.

---

### P1-9 — MCP tools: `update_person_type`, `log_checkin`, `get_relationship_health`
**Effort: M**

Three new MCP tools in `Sources/MeetingScribeMCP/main.swift`:

**`update_person`** (general-purpose, replaces the gap): accepts `id` + any subset of `{relationship_path, checkin_cadence_days, bio, role, company}`. Writes directly to `person.json` via the same file-write path as `add_person`. This is the write-side companion to `get_person`.

**`log_checkin`**: accepts `id`, `notes` (optional), `mood` (optional: "good/neutral/difficult"), `template` (optional: "partner/family/friend"). Creates an `Encounter` with `eventName = "Check-in"` and the structured notes, updates `lastInteractionAt`. Claude can prompt Tyler to log a check-in ("You haven't logged a check-in with Sarah in 18 days — want me to log one now?").

**`get_relationship_health`**: returns for a given person: days since last check-in, cadence target, streak, overdue status, and the last 3 memories. This is the read-side for check-in awareness — Claude can surface "You're overdue with your partner" without the user opening the app.

These three tools make Claude a genuinely useful relationship coach, not just a data retriever.

---

### P1-10 — Notification category: `RELATIONSHIP_CHECKIN`
**Effort: S**

Add a fourth `UNNotificationCategory` to `NotificationManager.swift` (after line 71):

```swift
static let categoryCheckIn = "RELATIONSHIP_CHECKIN"
static let actionLogCheckIn = "LOG_CHECKIN"
static let actionSnooze3Days = "SNOOZE_3_DAYS"
```

`syncScheduled` currently fires only for meetings. Add a companion method `syncCheckInReminders(for people: [Person])` that iterates overdue people (same logic as `ReconnectView.candidates`), schedules a notification per person with type-appropriate copy:
- Partner: "You haven't logged a check-in with [name] in N days. Everything okay?"
- Family: "It's been a while since you connected with [name]. Worth a quick call?"
- Close friend: "[name] hasn't heard from you in N days."

Actions: "Log check-in" (opens app → person detail → check-in sheet) + "Snooze 3 days." The `onLogCheckIn` callback is routed via `AppDelegate`/`MainWindow` deep-link into the check-in sheet.

---

### P1-11 — Love language + attachment style fields (partner path only)
**Effort: S**

Add two optional `String?` fields to `Person`: `loveLanguage` and `attachmentStyle`. These are purely display fields — rendered as chips in the identity panel for `.partner` persons only. The `AddPersonSheet` partner-path onboarding step includes a simple picker: "Their love language (optional)" with the 5 Chapman options, and "Attachment style (optional)": secure / anxious / avoidant / disorganized.

These fields feed into the AI coaching prompts (P1-7): the partner-path appreciation prompt knows to frame suggestions in the partner's love language. E.g., if love language is "words of affirmation," the Ollama prompt says: "Your partner's love language is words of affirmation. Suggest one thing Tyler could say or write this week."

Schema impact: two optional `String?` fields, tolerant decode, no migration needed.

---

### P1-12 — Relationship graph view filtered by path
**Effort: S**

`PeopleListView.swift:70–74` already has a `graphMode` toggle that renders `PeopleGraphView`. Add a path filter to the graph: show only `.partner + .family + .closeFriend` nodes by default (the inner circle), with an "all relationships" toggle. This makes the graph emotionally meaningful instead of cluttered with 500 colleagues. Inner-circle nodes are colored by path (partner = red, family = blue, closeFriend = yellow). No new data needed — just graph-level filtering on `RelationshipPath`.

---

## 4. Top 3 picks

| Rank | Item | Why it's first |
|---|---|---|
| **1** | **P1-1** — `RelationshipPath` enum in `Person` | Zero-risk, hours of work, unlocks every other recommendation. Without it, nothing else in this list can be built coherently. Keystone schema change. |
| **2** | **P1-3** — Per-type check-in cadence with UI control | The existing `ReconnectView` is good infrastructure. Adding path-default cadences + an explicit override turns a blunt 30-day heuristic into a genuinely useful relationship habit tool. High perceived value, M effort. |
| **3** | **P1-7** — Per-type AI coaching prompts | This is what separates MeetingScribe from a CRM. Embedding Gottman/NVC/attachment-theory prompts into the partner and friend paths — without requiring AI generation — delivers immediate emotional depth at low cost. The prompt library is static Swift; only the personalized variant calls Ollama. |

---

## 5. Implementation order

1. **P1-1** (schema, S) — add the enum, tolerant decode, update PersonDTO + VaultKit
2. **P1-8** (list grouping, S) — visual proof the type field matters, immediate feedback
3. **P1-2** (onboarding, S) — new people get typed on creation
4. **P1-3** (cadence, M) — extend existing nudge infrastructure
5. **P1-4** (check-in templates, M) — structured check-in sheet
6. **P1-7** (coaching prompts, M) — static prompt library + view
7. **P1-5** (view gating, M) — type-conditional sections
8. **P1-9** (MCP tools, M) — Claude can coach via chat
9. **P1-10** (notifications, S) — habit loop closes
10. **P1-11** (love language, S) — partner path depth
11. **P1-6** (health score card, M) — streak + appreciation prompt
12. **P1-12** (graph filter, S) — inner circle visualization

Total effort estimate: ~3–4 weeks of focused development, all incremental and ship-safe (no breaking changes to existing data).
