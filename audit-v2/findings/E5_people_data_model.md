# People Data Model & Cross-Feature Connectivity — MeetingScribe v2 Audit

**Agent:** E5 | **Sub-lens:** Person model fields, PersonResolver reliability, cross-entity joins, "person context" as connective tissue

---

## Top friction points / gaps (file:line citations)

### 1. Person carries no computed relationship-strength field — scoring is call-site math
`Person.relevanceScore(encounterCount:)` (Person.swift:412) calculates a coarse signal on demand but the result is never persisted. Every consumer — Today, PeopleListView, PreMeetingBriefView, ChatSession — recomputes from scratch against different data snapshots. There is no `relationshipStrengthScore: Double?` persisted on the record, no `lastStrengthComputedAt: Date?`, and no scheduled background job to refresh it. Consequence: the score degrades silently as data grows and is unavailable for offline/proactive features (e.g., "top relationships at risk" push on the Today view).

### 2. Person has no `linkedProjectIDs` — the Tasks→People join doesn't exist at rest
Action items link to people via `ownerPersonID` (ActionItem.swift:28), and a project's meetings are joined via `project.meetingIDs`, but there is no reverse edge: `Person` has no `linkedProjectIDs: [String]` field. To answer "what projects is Jane working on?" the app must full-scan ActionItemStore filtering on `ownerPersonID == jane.id` and then walk the Initiative→Project hierarchy. PersonDetailView.swift:1590 and :2071 do exactly this — live, in the view, with no cache.

### 3. PersonResolver fails on name-only attendees at scale — no alias layer
`PersonResolver.resolve` (PersonResolver.swift:70) is email-first, exact-name-second. Name normalization is in `PersonMatching.normalizeName` (not audited here) but aliases extracted by `PersonExtractor` are stored on `ExtractedPerson.aliases` (PersonExtractor.swift:7) and *never written back to `Person`*. So if a meeting transcript says "Horst" and the contact is "Horst Bauer", the resolver misses them unless the email matches. `Person` has no `aliases: [String]` field and no `linkedExternalIDs: [String]` (e.g., LinkedIn handle, Slack member ID) that could widen resolution surface.

### 4. `meetingMentions` is a `Set<String>` of IDs with no rich metadata
Person.swift:239-240 stores raw meeting IDs but carries no attendee-vs-transcript distinction, no role (organizer / invitee / mentioned), no speaker-map association. PreMeetingBriefView and PeopleChatTools have to reload the full Meeting object to reconstruct context, and there is no way to query "meetings where Jane was the organizer" without scanning every meeting.

### 5. `personContextForAI()` is a 1468-LOC private method inside PersonDetailView
PersonDetailView.swift:1169 — a ~37-line context assembler — is private to the view. ChatSession, PreMeetingBriefView, MeetingChatTools, and WeeklyRecap each build their own person context strings ad hoc. There is no canonical `PersonContextBuilder` service, meaning context quality differs across surfaces, and improvements to one don't propagate.

### 6. Encounter has no `taskIDs: [String]` — action-item context is lost
Encounter.swift links back to a `meetingID` and `voiceNoteID` but not to `ActionItem` IDs. If a task was created because of a conversation with Jane at a specific meeting, that triangle (person ↔ encounter ↔ task) cannot be reconstructed without a full ActionItemStore scan.

### 7. `ingestExtraction` fuzzy-match threshold is a hard constant — no per-person tuning
PeopleStore.swift:1261 uses `Self.autoLinkThreshold` (a single constant). Common names ("Michael", "Alex") will false-positive; rare names will miss. There is no per-person `autoLinkSensitivity: Double?` field, no feedback loop from user confirmations/dismissals back to the threshold.

---

## Existing items to endorse (from prior plan or codebase)

- `relevanceScore(encounterCount:)` (Person.swift:412) — sound foundation; needs persistence + scheduling.
- `emitMeetingEncounters` (PeopleStore.swift:1188) — correctly deduplicates and creates encounter edges from finalized meetings. The ±2h dedup window is pragmatic.
- `PersonResolver` single-source parsing (PersonResolver.swift:37) — fixed the 6-site divergence problem; keep and extend.
- `ingestExtraction` suggestion queue (PeopleStore.swift:1243) — tiered confidence flow (auto-link / suggest / new) is the right UX pattern.
- `talkingPoints: [String]` (Person.swift:243) — correct placement; powers pre-meeting brief. Should be extended with `talkingPointMeetingID: String?` metadata.

---

## NET-NEW recommendations

### E5-1: Persist `relationshipStrengthScore` + schedule background refresh
- **What:** Add `var relationshipStrengthScore: Double?` and `var strengthLastComputedAt: Date?` to `Person`. Create a `RelationshipStrengthService` that runs nightly (or after each meeting finalize) to recompute scores using encounter recency/frequency, open tasks, memories, iMessage sentiment, and mutual meeting count. Persist to `person.json` via existing `SchemaEnvelope` tolerant decoder pattern.
- **Why (second-brain angle):** Enables proactive "at-risk relationship" alerts on Today view, rank-orders the keep-in-touch board without live computation, and gives the AI chat a fast numerical signal ("Tyler's top 5 colleagues by strength this month").
- **Cross-feature connections:** Today (drift strip ordering), PreMeetingBriefView (sort attendees by strength), GlobalSearch (boost person results), WeeklyRecap ("relationship health this week"), AI chat tool `get_person`.
- **Effort:** M | **Impact:** High
- **Deps:** none

### E5-2: Add `aliases: [String]` and `linkedExternalIDs: [String: String]` to Person
- **What:** `aliases` stores known alternate names/nicknames ("Horst" for "Horst Bauer", "JD" for "John Doe"). `linkedExternalIDs` is a keyed dictionary: `["slack": "U012AB3CD", "linear": "user_xxx", "linkedin": "horst-bauer-123"]`. PersonResolver consults aliases before falling through to "no match". ExternalIDs enable future Slack/Linear integration to resolve message authors to Person records without email.
- **Why (second-brain angle):** Closes the resolver gap on name-only attendees. A person mentioned once by first name in 10 transcripts now accumulates correctly, feeding the relationship strength score and surface count — compounding returns across every AI feature.
- **Cross-feature connections:** PersonResolver (wider match surface), MeetingPipelineController (better auto-link), Linear sync (task owner resolution), Slack integration (message attribution), iMessage analysis (correlation to person record).
- **Effort:** M | **Impact:** High
- **Deps:** E5-1 (strength signal improves with better linking)

### E5-3: `PersonContextBuilder` — canonical service replacing ad-hoc context strings
- **What:** Extract `personContextForAI()` (PersonDetailView.swift:1169) into a standalone `PersonContextBuilder` struct with a typed `PersonContext` value type: `{ person, recentMeetings, openTasks, memories, talkingPoints, strengthScore, upcomingDates }`. Expose a static `build(for:) -> PersonContext` and a `formatted(detail: .brief/.standard/.deep) -> String` method. Wire into ChatSession, PreMeetingBriefView, MeetingChatTools, WeeklyRecap, and the MCP server tools.
- **Why (second-brain angle):** Every AI surface currently builds a different, inconsistent picture of a person. A unified builder means one improvement immediately sharpens all six consumer surfaces. The `PersonContext` type is also embeddable in `PreMeetingBriefView` as a SwiftUI data model, removing the brittle view-level assembly.
- **Cross-feature connections:** AI chat (PeopleChatTools), PreMeetingBriefView, WeeklyRecap, MCP server (`get_person` tool), StandupDigest, GlobalSearch result expansion.
- **Effort:** M | **Impact:** High
- **Deps:** none (can be shipped before E5-1/E5-2, then enhanced)

### E5-4: `linkedProjectIDs: [String]` reverse edge on Person — materialized at task-write time
- **What:** Add `var linkedProjectIDs: Set<String>` to `Person`. `ActionItemStore` writes to this set whenever a task with `ownerPersonID` is assigned/moved to a project, and clears the entry on completion/deletion. A `PersonDetailView` "Projects" section replaces the current full-scan (PersonDetailView.swift:1590).
- **Why (second-brain angle):** Enables the "What is Jane working on?" question to be answered in O(1) instead of O(tasks × projects). Unlocks a cross-tab widget on PersonDetailView: "Active projects involving this person." Also enables initiative-level relationship intelligence: "Tyler collaborates with Jane on 3 active projects."
- **Cross-feature connections:** PersonDetailView (projects section), Today 1:1 strip (show shared projects for upcoming 1:1s), PeopleChatTools (`get_person` tool), PreMeetingBriefView (shared project context), GlobalSearch (filter people by project).
- **Effort:** S | **Impact:** High
- **Deps:** none

### E5-5: `MeetingMentionRecord` — replace raw `Set<String>` with typed backlink
- **What:** Replace `meetingMentions: Set<String>` with `meetingMentions: [MeetingMentionRecord]` where `MeetingMentionRecord` carries `{ meetingID, role: MentionRole (attendee/transcript/organizer), addedAt: Date }`. Tolerant decoder defaults raw IDs to `.transcript` role on migration.
- **Why (second-brain angle):** Enables queries like "meetings Jane organized" or "meetings where Jane was mentioned only in transcript (not invited)" — critical for surfacing relationship depth vs. casual reference. Organizer detection is already derivable from `meeting.organizer` (if present) at link time.
- **Cross-feature connections:** PersonDetailView (Mentioned In section), PreMeetingBriefView (attendee vs. mention), AI chat (richer person timeline), WeeklyRecap (relationship depth analysis).
- **Effort:** M | **Impact:** Med
- **Deps:** E5-3 (PersonContextBuilder consumes the richer type)

### E5-6: Encounter gains `taskIDs: [String]` — close the person ↔ encounter ↔ task triangle
- **What:** Add `var taskIDs: [String]` to `Encounter.swift`. When `MeetingPipelineController` creates tasks from a finalized meeting that also emits encounters (both are done synchronously in `MeetingPipelineController.swift:219-246`), write the extracted task IDs to the encounter. AI chat can then answer "what did we decide at my last meeting with Jane?" and immediately cite the tasks that came out of it.
- **Why (second-brain angle):** Completes the three-way join that makes the second brain coherent. Currently a user can see encounters and tasks separately but cannot ask "what commitments came from this interaction?"
- **Cross-feature connections:** PersonDetailView (encounter detail → linked tasks), AI chat (PeopleChatTools), MCP `get_encounter` tool, PreMeetingBriefView (show open tasks from past encounters with this attendee).
- **Effort:** S | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **E5-3 (PersonContextBuilder)** — Zero model changes, immediate quality uplift across all six AI surfaces, O(M) effort, unblocks every downstream "person context" feature in v2.
2. **E5-1 (Persisted strength score)** — Enables the proactive "relationship health" layer that distinguishes MeetingScribe v2 from a CRM. Feeds Today, WeeklyRecap, and the AI chat simultaneously.
3. **E5-2 (Aliases + externalIDs on Person)** — Fixes the silent data-loss bug where name-only attendees fail to accumulate relationship history. Compounds: every correctly-linked encounter improves strength scores, AI context, and encounter counts.
