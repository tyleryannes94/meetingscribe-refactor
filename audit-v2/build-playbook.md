# MeetingScribe v2 — Claude Code Build Playbook

*Each phase prompt is self-contained. Paste it into Claude Code on a fresh branch with the CLAUDE.md and master-plan.md in context. Read the master plan first if you haven't.*

---

## Ground Rules Prompt

**Paste this once into Claude Code (or append to CLAUDE.md) before starting any phase.**

```
You are building MeetingScribe v2 on an M2 Mac mini running macOS 26.3.1 (Tahoe).

REPO: ~/MeetingScribeRefactor (git remote: tyleryannes94/meetingscribe-refactor, branch: main)
APP BUNDLE ID: com.tyleryannes.MeetingScribe
CODE-SIGNING IDENTITY: "MeetingScribe Local Signer"

BRANCH STRATEGY: Create a branch per phase, named phase/P0, phase/1, phase/2, etc.
Never commit directly to main. Keep PRs focused on one phase's items.

BUILD VERIFICATION: After every non-trivial Swift change, run:
  swift build -c release
Warnings are fine. Errors block any commit. Fix errors before moving on.

DESIGN SYSTEM (NDS): All new SwiftUI views must use:
- Spacing tokens: NDS.Spacing.{xs, sm, md, lg, xl}
- Color tokens: NDS.Color.{surface, surfaceElevated, textPrimary, textSecondary, accent}
- Typography: NDS.Font.{heading, body, caption, mono}
Do not use raw Color() or raw padding values.

SCHEMA MIGRATIONS: Any change to a stored model struct must:
1. Increment SchemaVersion (SchemaEnvelope pattern)
2. Add a migration case to the relevant *SchemaMigrations enum
3. Never remove fields — only add or rename via migration
Failure to migrate will corrupt existing user data on app update.

NEVER BREAK EXISTING FUNCTIONALITY: Before and after each change, verify:
- Today view loads without crash
- Meeting recording starts and stops
- AI chat responds to a simple query
- People tab shows existing persons
Run these as manual smoke tests before every PR.

COMMIT STYLE:
- Subject: imperative, lowercase after prefix (feat:, fix:, refactor:, chore:, docs:)
- Under 72 chars
- Body only when non-obvious (explain WHY, not WHAT)
- No "Co-Authored-By" trailers

MCP BINARY: MeetingScribeMCP lives at Contents/MacOS/MeetingScribeMCP, signed with the
same identity. If you touch MCP tools, re-sign: 
  codesign --force --sign "MeetingScribe Local Signer" .build/release/MeetingScribeMCP

MASTER PLAN: ~/MeetingScribeRefactor/audit-v2/master-plan.md contains item IDs,
effort estimates, dependencies, and source agent rationale for every change.
Reference it by ID (e.g., P0-A) when explaining what you're implementing.
```

---

## Phase P0 Prompt — Critical Infrastructure

**Branch:** `phase/P0`  
**Goal:** Extract the data and event layer that every v2 feature depends on. Zero user-facing UI changes. No regressions.

```
You are implementing Phase P0 of MeetingScribe v2. These are pure infrastructure 
changes — no new UI, no visible behavior changes. The goal is to unblock 9+ 
downstream features by fixing architectural layering violations.

READ THESE FILES BEFORE STARTING (in order):
1. ~/MeetingScribeRefactor/audit-v2/master-plan.md (P0 section)
2. PeopleStore.swift (focus: line 69, SecondBrainDB instantiation)
3. SecondBrainDB.swift (full file)
4. EmbeddingService.swift (full file)
5. VaultSearchService.swift (full file)
6. MeetingManager.swift (full file — note size and @MainActor usage)
7. ActionItemStore.swift (mutation hooks)
8. DecisionStore.swift (lines 1–30, struct definition)
9. ResourceGovernor.swift (full file)
10. SchemaMigrations.swift (existing pattern to follow)

IMPLEMENT IN THIS ORDER (each must build cleanly before the next):

--- P0-C FIRST (smallest, no deps, safety prerequisite) ---
P0-C: ResourceGovernor as Universal AI Work Gate
- Add work tier enum: .backgroundEmbedding, .backgroundInsight, .backgroundNudge
- Add func canScheduleWork(tier: AIWorkTier) -> Bool
  - .backgroundEmbedding: requires !isTranscribing && thermalState < .serious
  - .backgroundInsight: requires !isTranscribing && thermalState < .serious && isPluggedIn
  - .backgroundNudge: requires thermalState < .fair
- No callers yet — just the gate. Callers come in Phase 3.
Build and verify: swift build -c release

--- P0-A NEXT (highest leverage, no deps) ---
P0-A: Extract SecondBrainDB → VaultIndexService
1. Create Infrastructure/VaultIndexService.swift as @MainActor singleton
2. Move all SecondBrainDB functionality into VaultIndexService.shared
3. Add entry points:
   - indexMeeting(_ meeting: Meeting, transcript: String?) async
   - indexTask(_ task: ActionItem) async
   - indexDecision(_ decision: Decision) async
   - indexEncounter(_ encounter: Encounter) async
   - indexVoiceNote(_ note: VoiceNote, transcript: String) async
   - removeFromIndex(entityID: String) async
4. In PeopleStore.swift: remove private let db = SecondBrainDB(). 
   Replace all db.* calls with VaultIndexService.shared.*
5. Wire ActionItemStore: after every create/update, call 
   await VaultIndexService.shared.indexTask(item)
6. Wire MeetingStore: existing embedAndStore calls go through VaultIndexService
7. Add one-time backfill migration: on first launch after update, 
   iterate existing tasks and decisions and index them
Build and verify. Run smoke tests (Today loads, chat responds).

--- P0-E NEXT (depends on P0-A conceptually, S effort) ---
P0-E: DecisionStore SchemaEnvelope + Enriched Decision Model
1. Enrich Decision struct (follow SchemaEnvelope pattern from SchemaMigrations.swift):
   - Add rationale: String? (default nil)
   - Add personIDs: [String] (default [])
   - Add projectID: String? (default nil)  
   - Add status: DecisionStatus (enum: open, superseded, resolved; default .open)
   - Add revisitDate: Date? (default nil)
2. Add DecisionSchemaMigrations enum with migration from v1 → v2
3. At summary-generation time (find the Ollama summary completion handler),
   add a rationale-extraction prompt: 
   "Extract the rationale for each decision in 1 sentence. Return JSON array of 
   {decisionID, rationale} objects."
   Store rationale on each Decision.
4. Wire DecisionStore mutations to VaultIndexService.shared.indexDecision()
Build and verify.

--- P0-B (parallel-safe with P0-E, M effort) ---
P0-B: SecondBrainEventBus
1. Create Infrastructure/SecondBrainEventBus.swift
2. Define SecondBrainEvent enum:
   - meetingFinalized(meetingID: String, attendees: [String])
   - taskCreated(task: ActionItem)
   - taskUpdated(task: ActionItem)
   - encounterLogged(encounter: Encounter, personID: String)
   - decisionExtracted(decision: Decision, meetingID: String)
   - personUpdated(personID: String)
   - insightAvailable(type: InsightType, payload: [String: Any])
3. SecondBrainEventBus.shared uses AsyncStream<SecondBrainEvent>
4. Replace current cross-store NotificationCenter posts with EventBus publishes:
   - MeetingManager: publish .meetingFinalized after pipeline completion
   - ActionItemStore: publish .taskCreated/.taskUpdated after mutations
   - EncounterStore: publish .encounterLogged after create
   - DecisionStore: publish .decisionExtracted after create
5. No subscribers yet — just the bus + publishers. Subscribers come in Phase 3.
Build and verify.

--- P0-F LAST (depends on P0-A, P0-E) ---
P0-F: SQLite Join Tables
1. In VaultIndexService (or a new SQLiteMigration), add tables:
   CREATE TABLE IF NOT EXISTS meeting_persons 
     (meeting_id TEXT, person_id TEXT, role TEXT, PRIMARY KEY (meeting_id, person_id))
   CREATE TABLE IF NOT EXISTS decision_persons 
     (decision_id TEXT, person_id TEXT, PRIMARY KEY (decision_id, person_id))
   CREATE TABLE IF NOT EXISTS task_persons 
     (task_id TEXT, person_id TEXT, role TEXT, PRIMARY KEY (task_id, person_id))
   CREATE TABLE IF NOT EXISTS person_projects 
     (person_id TEXT, project_id TEXT, PRIMARY KEY (person_id, project_id))
2. Materialize person_projects at ActionItem write time:
   when ActionItem is created with ownerPersonID + projectID, insert to person_projects
3. Backfill from existing ActionItemStore on first launch
4. Replace PersonDetailView.swift:1590 O(n) project scan with:
   SELECT project_id FROM person_projects WHERE person_id = ?
5. Add query helpers: VaultIndexService.shared.personsForMeeting(meetingID:),
   decisionsForPerson(personID:), projectsForPerson(personID:)
Build and verify. Run full smoke test suite.

--- P0-D (can be last, M effort) ---
P0-D: MeetingManager Actor Split
1. Create TranscriptionEngine: manages live recording state, 
   publishes transcribingMeetingIDs, handles mic/screen capture
2. Create MeetingLibraryService: meeting CRUD, summary fetch, 
   observable by Today + MeetingLibraryView + any future subscriber independently
3. MeetingManager becomes a thin coordinator that owns both
4. Update Today, MeetingLibraryView, and any other subscribers to observe 
   only the service they actually need (Today needs library, not transcription state)
5. Verify: Today no longer re-renders on every transcription tick
Build and verify. Run full smoke test suite.

ACCEPTANCE CRITERIA:
- swift build -c release passes with zero errors
- Today view loads, shows meetings and tasks
- Starting a meeting recording works
- AI chat responds to "What did I discuss last week?"
- PeopleStore no longer instantiates SecondBrainDB directly
- VaultIndexService.shared.indexTask() is called after ActionItem creates
- SecondBrainEventBus.shared publishes meetingFinalized after pipeline

PR TITLE: refactor: P0 — VaultIndexService extraction, EventBus, ResourceGovernor gate, join tables
```

---

## Phase 1 Prompt — Second Brain Foundation

**Branch:** `phase/1`  
**Prerequisites:** Phase P0 merged to main. Pull main before branching.

```
You are implementing Phase 1 of MeetingScribe v2: Second Brain Foundation.
P0 infrastructure is in place. These items deliver immediate visible value.

READ BEFORE STARTING:
1. ~/MeetingScribeRefactor/audit-v2/master-plan.md (Phase 1 section)
2. VaultIndexService.swift (P0-A result — understand indexTask/indexDecision APIs)
3. SecondBrainEventBus.swift (P0-B result)
4. OllamaService.swift (understand current summary generation flow)
5. PersonContextBuilder.swift (if it exists) or PeopleStore.swift + PersonDetailView.swift
6. Person.swift (model definition)
7. TodayView.swift (lines 340–460: moreSection, followUpsSection, decisionsSection)
8. GlobalSearchView.swift (lines 440–460: WeeklyRecap trigger; also ⌘K implementation)

IMPLEMENT (order matters — 1-G and 1-I first as they're independent):

1-G: Promote followUps + Decisions Out of "More" (S effort, do this first)
- In TodayView.swift, remove followUpsSection and decisionsSection from moreSection
- Wrap each in: if !items.isEmpty { section } (hide when empty, show when non-empty)
- Place followUpsSection immediately after the upNextCard / turnaroundCard area
- Place decisionsSection after followUpsSection
- Test: create a follow-up action item, verify it's visible without expanding "More"
Commit: feat: promote followUps and decisions sections out of Today "More" disclosure

1-I: O(1) WebAPI Meeting Lookup (S effort, independent)
- Find the MCP WebAPI handler that looks up meetings by ID
- Replace linear Array.first(where:) scan with a Dictionary index
- Build the index once on MeetingLibraryService init, update on mutations
Commit: perf: O(1) meeting lookup in MCP WebAPI handler

1-C: Streaming Summaries (M effort, independent of P0 data layer)
- In OllamaService.swift, add streamGenerate(prompt:) -> AsyncStream<String>
- Uses /api/generate with stream: true, parses NDJSON token stream
- In MeetingSummaryView (or wherever summary is displayed), replace:
    let summary = await OllamaService.shared.generate(prompt:)
  with a streaming display that appends tokens as they arrive
- Show a "Thinking..." placeholder until first token arrives
- Handle cancellation (user navigates away mid-stream)
Commit: feat: streaming meeting summaries via Ollama /api/generate stream

1-A + 1-B: Index Tasks, Decisions, Encounters into Vault (S effort each)
- 1-A: After ActionItemStore mutations, VaultIndexService.shared.indexTask() is called
  (P0-A may have wired this — verify and add if missing for update mutations too)
- 1-B: After DecisionStore mutations, VaultIndexService.shared.indexDecision()
  After EncounterStore mutations, VaultIndexService.shared.indexEncounter()
- Verify in AI chat: ask "What tasks do I have for next week?" — tasks should appear
- Verify: ask "What did we decide about X?" — decisions should appear
Commit: feat: index tasks, decisions, and encounters into vault FTS + embeddings

1-E: Person Aliases + LinkedExternalIDs (M effort)
- Add to Person model (SchemaEnvelope migration required):
    aliases: [String] = []
    linkedExternalIDs: [String: String] = [:]  // e.g. ["linear": "USR-123"]
- Add PersonSchemaMigrations v1→v2 case
- Expand PersonResolver.resolve(name:) to check aliases array
- Provide a UI in PersonDetailView settings section to add/edit aliases
- Common alias use case: "Tyler" vs "Ty" vs "Tyler Yannes"
Commit: feat: Person aliases + linkedExternalIDs for robust attendee resolution

1-D: PersonContextBuilder Service (M effort)
- Create People/PersonContextBuilder.swift as @MainActor service
- func buildContext(personID: String) async -> PersonContext struct containing:
    person: Person
    lastMeeting: Meeting? (most recent shared meeting)
    lastMeetingSummaryExcerpt: String? (first 300 chars)
    openTasksOwedByUs: [ActionItem]
    openTasksOwedToUs: [ActionItem]
    talkingPoints: [TalkingPoint]
    recentIMessageThemes: [String]? (from MessagesAnalyzer if available)
    strengthScore: Double?
    nextCalendarEvent: CalendarEvent?
    meetingCount: Int
- Replace all ad-hoc person context assembly in:
    PreMeetingBriefView, WeeklyRecap, StandupDigest, GlobalSearch, ChatTools
  with PersonContextBuilder.shared.buildContext(personID:)
- The context object is passed to Ollama prompts for AI-powered features
Commit: refactor: PersonContextBuilder — canonical person context assembly service

1-F: Persist RelationshipStrengthScore (M effort)
- Add to Person model (SchemaEnvelope migration):
    relationshipStrengthScore: Double = 0.0
    strengthLastComputedAt: Date? = nil
- Compute score formula (combine existing signals):
    - Meeting frequency last 90 days (weight: 0.4)
    - Days since last encounter (recency, weight: 0.3)
    - Action item follow-through rate (weight: 0.2)
    - iMessage frequency if available (weight: 0.1)
- Compute on: (a) meeting finalization for attendees, (b) manual trigger
- Gate background refresh with ResourceGovernor.shared.canScheduleWork(.backgroundEmbedding)
- Store computed score on Person, save to PersonStore
- Today KeepInTouchBoard already uses health scoring — wire in the persisted score
Commit: feat: persist relationshipStrengthScore with background refresh

1-H: Embedding Persistent Cache (M effort)
- Create Infrastructure/EmbeddingCache.swift
- NSCache<NSString, NSData> keyed by "\(entityID):\(contentHash)"
- In VaultIndexService, check cache before deserializing embedding vectors from SQLite
- Invalidate on entity update (content hash changes)
Commit: perf: persistent embedding cache — eliminate per-query vector deserialization

ACCEPTANCE CRITERIA:
- swift build -c release passes
- followUpsSection visible in Today without expanding "More" when non-empty
- Meeting summary streams token by token (no blank-wait then flash)
- AI chat: "What tasks are assigned to me?" returns task results
- AI chat: "What decisions did we make about X?" returns decision results
- PersonContextBuilder.buildContext() returns a populated struct for any person with meetings
- Person.relationshipStrengthScore is populated after a meeting with that person

PR TITLE: feat: Phase 1 — vault indexing, streaming summaries, PersonContextBuilder, strength scores
```

---

## Phase 2 Prompt — People Intelligence Overhaul

**Branch:** `phase/2`  
**Prerequisites:** Phase 1 merged. Pull main.

```
You are implementing Phase 2 of MeetingScribe v2: People Intelligence Overhaul.
The goal: make People the best tab in the app — a genuine relationship OS.

READ BEFORE STARTING:
1. ~/MeetingScribeRefactor/audit-v2/master-plan.md (Phase 2 section)
2. PersonDetailView.swift (full file — understand existing layout and data sources)
3. PersonContextBuilder.swift (Phase 1 result)
4. KeepInTouchBoard / RelationshipHealthService (understand board data model)
5. EncounterStore.swift (Encounter model, create API)
6. Person.swift (current model after Phase 1 migrations)
7. PreMeetingBriefView.swift (will receive 2-G injection)
8. MessagesAnalyzer.swift (understand available iMessage API)
9. ActionItemStore.swift (ownerPersonID field, filter API)
10. TodayView.swift (commitments section at line 399 for reference)

IMPLEMENT:

2-F: Task Mutation from People Tab (S effort — do first, quick win)
- Add "New Task" toolbar button to PersonDetailView
- On tap: show TaskQuickAddSheet pre-populated with ownerPersonID = person.id
- On save: ActionItemStore.create() with ownerPersonID set
- New task appears immediately in person's task list
Commit: feat: create task from People tab with auto-assigned ownerPersonID

2-C: Commitment Ledger Per Person (S effort)
- In PersonDetailView, add "Commitments" section:
    "You owe [Name]:" — tasks where ownerPersonID == person.id AND NOT completed
    "[Name] owes you:" — tasks where delegatedToPersonID == person.id AND NOT completed
  Use VaultIndexService join tables for O(1) lookup (task_persons table from P0-F)
- Reuse the existing owe/owed UI pattern from TodayView.swift:399
Commit: feat: per-person commitment ledger in PersonDetailView

2-G: Relationship Summary in PreMeetingBriefView (S effort)
- In PreMeetingBriefView, for each attendee with a Person record:
    1. Look up summary-all AttachedNote (first 200 chars)
    2. Look up recent iMessage themes via MessagesAnalyzer.recentThemes(contactID:)
    3. Render as "About [Name]: [summary excerpt] · Recent: [theme1], [theme2]"
- Gate iMessage lookup behind existing MessagesAnalyzer permission check
- This is additive — slot it between the attendee list and the agenda section
Commit: feat: relationship summary + iMessage context in PreMeetingBriefView

2-H: Trajectory Sparkline on Board Cards (S effort)
- On KeepInTouchBoard card for each person:
    Show 12-week mini sparkline of encounter frequency (bars or line, 12 data points)
    Store weekly encounter snapshots in a new PersonWeeklySnapshot model
    Record snapshot in background on Sunday evenings (ResourceGovernor gated)
- Sparkline renders as a small SwiftUI Shape, 48pt wide, 16pt tall
Commit: feat: 12-week relationship trajectory sparkline on KeepInTouchBoard cards

2-A: Auto-Encounter Creation from Meetings (M effort)
- Subscribe to SecondBrainEventBus.shared events of type .meetingFinalized
- For each confirmed attendee in the meeting:
    1. PersonResolver.resolve(name: attendeeName) using aliases (Phase 1)
    2. If resolved: EncounterStore.create(Encounter(personID:, meetingID:, date:, 
       source: .autoFromMeeting))
    3. If not resolved and attendee appears in 3+ meetings: 
       emit a "Suggest adding [name] to People" notification
- Idempotent: check if Encounter with meetingID already exists before creating
- This makes the entire relationship health stack accurate for professional contacts
Commit: feat: auto-create encounter records from finalized meetings

2-E: Multi-Signal Relationship Health (M effort)
- Expand RelationshipHealthService.computeScore(personID:) to incorporate:
    iMessage signal: MessagesAnalyzer.daysSinceLastMessage(contactID:) 
    — counts as a virtual encounter if < checkInInterval/2
    Meeting mention signal: count of MeetingMentionRecords (or Set<String>) in last 90 days
    — each mention counts as 0.3x a full encounter
- Update existing health badge on PersonDetailView and board cards
- Update 1-F strength score formula to use the same multi-signal computation
Commit: feat: multi-signal relationship health — iMessage + meeting mentions

2-I: MeetingMentionRecord Typed Backlink (M effort)
- Add MeetingMentionRecord struct: {meetingID, role, timestamp, excerpt: String}
- Add to Person model (SchemaEnvelope migration): 
    meetingMentionRecords: [MeetingMentionRecord] = []
    (keep old meetingMentions: Set<String> as deprecated, migrate on read)
- Populate at meeting finalization: scan summary for person mentions, extract excerpt
- Display in PersonDetailView "Meeting History" section: 
    "Mentioned in Q4 Planning (Dec 3) — 'Alex will own the budget approval'"
Commit: refactor: MeetingMentionRecord replaces raw Set<String> with typed backlinks

2-B: "Brief Me" Button on Person Profile (M effort — the flagship People feature)
- Add prominent "Brief Me" button to PersonDetailView header (below name/title)
- On tap:
    1. Show PersonBriefSheet (full-screen sheet, dismissible)
    2. Call PersonContextBuilder.shared.buildContext(personID:)
    3. Build Ollama prompt:
       "You are preparing Tyler for a meeting with [name]. 
        Last meeting: [excerpt]. Open tasks: [list]. 
        Talking points: [list]. Recent iMessage themes: [list].
        Next calendar event: [event].
        Write a 150-word conversational brief covering: 
        relationship status, key open items, and 2 suggested talking points."
    4. Stream result into PersonBriefSheet using 1-C streaming pattern
    5. Show "Refresh" button to regenerate
- Brief sheet also shows: raw context cards below the AI synthesis
Commit: feat: "Brief Me" button on person profile — Ollama-synthesized relationship brief

2-D: One-Tap Actions on KeepInTouchBoard Cards (M effort)
- Hover-reveal action strip on each board card (appears on hover, 3 actions):
    "Log check-in" → one-tap creates Encounter (pre-filled date: now, source: .manual)
    "Conversation starter" → Ollama local prompt:
      "Generate 2 casual conversation starter questions for [name] based on 
       their role ([role]) and our last discussion about [lastMeetingTopic]."
      Stream into a popover
    "Remind me" → date picker → creates a local notification
- Uses existing hover/onHover SwiftUI pattern
Commit: feat: one-tap actions on KeepInTouchBoard cards — log, AI starter, remind

2-J: Encounter Gains taskIDs (S effort)
- Add taskIDs: [String] to Encounter (SchemaEnvelope migration)
- In auto-encounter creation (2-A): populate taskIDs with action items 
  extracted from the associated meeting (filter by ownerPersonID)
- Display in encounter detail: "Action items from this meeting: [list]"
Commit: feat: Encounter.taskIDs — close person ↔ encounter ↔ task triangle

ACCEPTANCE CRITERIA:
- swift build -c release passes
- "Brief Me" button visible on any PersonDetailView, streams a coherent brief
- KeepInTouchBoard shows trajectory sparkline on each card
- Auto-encounter is created when a meeting with a known contact finalizes
- Commitment ledger visible in PersonDetailView with correct owe/owed split
- PreMeetingBriefView shows relationship summary for known attendees

PR TITLE: feat: Phase 2 — People intelligence overhaul, Brief Me, auto-encounters, commitment ledger
```

---

## Phase 3 Prompt — Post-Meeting Automation & Proactive AI

**Branch:** `phase/3`  
**Prerequisites:** Phase 2 merged. Pull main.

```
You are implementing Phase 3 of MeetingScribe v2: Post-Meeting Automation and Proactive AI.
This is the defining shift from v1 to v2. The app should do work for Tyler while 
he's in his next meeting. Nothing in this phase requires user action.

READ BEFORE STARTING:
1. ~/MeetingScribeRefactor/audit-v2/master-plan.md (Phase 3 section)
2. SecondBrainEventBus.swift (P0-B — event types and publish API)
3. ResourceGovernor.swift (P0-C — canScheduleWork() gate)
4. MeetingManager.swift / MeetingLibraryService.swift (P0-D — pipeline completion)
5. NotificationManager.swift (lines 220–260: current notification scheduling)
6. BriefCache.swift (understand pre-warm API if it exists)
7. CalendarService.swift (how calendar events are fetched)
8. ChatTools.swift (existing tool infrastructure — use as pattern for InsightEngine)
9. OllamaService.swift (understand generate() API for multi-step prompts)
10. VoiceNoteStore.swift + VoiceNote model

IMPLEMENT:

3-B: Enriched Daily-Brief Notification (S effort — do first)
- In NotificationManager.swift, find the 8am daily notification scheduler
- Replace hardcoded body string with live-computed content:
    let meetingCount = await CalendarService.shared.todayMeetings().count
    let overdueFollowUps = await ActionItemStore.shared.overdueTodayCount()
    let checkInsDue = await RelationshipHealthService.shared.overdueCheckIns().count
    body = "\(meetingCount) meetings · \(overdueFollowUps) follow-ups due · 
            \(checkInsDue) check-ins overdue"
- Add UNNotificationAction "View Standup" with deep link: 
    meetingscribe://standup
  Handle this URL in the app's URL handler
- Pre-warm BriefCache at 7:50am (10 min before notification, ResourceGovernor gated)
Commit: feat: enriched daily-brief notification with live data + deep link

3-G: Global Capture Bar (M effort)
- Create a floating NSPanel (key window, non-activating unless clicked)
- Register global hotkey: ⌘⇧Space via Carbon/EventHotKey or similar
- Panel contains: TaskQuickAddTextField (reuse TaskQuickAddParser), 
    "Record voice note" button, "Log encounter" button
- On task submit: ActionItemStore.shared.create(parsed result)
- On voice note: open mic, record until user stops, same pipeline as Notes tab
- Panel dismisses on Escape or losing focus
- Add menu bar item option to trigger it as well
Commit: feat: global capture bar — ⌘⇧Space for system-wide task/note/encounter capture

3-D: Voice Note Auto-Extract Pipeline (M effort)
- After existing Ollama polish pass on VoiceNote transcription completes:
    Add a second structured Ollama pass:
    Prompt: "Analyze this voice note transcript. Return JSON:
    {
      tasks: [{title, dueDate?, priority?}],
      personMentions: [{name, context}],
      decisions: [{text, rationale?}]
    }
    Transcript: [transcript]"
    Parse JSON response (handle malformed JSON gracefully with fallback)
    Create ActionItems from tasks array (VaultIndexService will index them)
    Resolve personMentions via PersonResolver → log mention on Person
    Create Decision entries for decision items
- Publish .taskCreated events on EventBus for each created task
- Show created items in VoiceNoteDetailView: "Extracted: 2 tasks, 1 person mention"
Commit: feat: voice note auto-extract pipeline — tasks + people + decisions from audio

3-A: Unified Post-Meeting Pipeline (L effort — the critical v2 feature)
- Create Automation/PostMeetingPipelineCoordinator.swift as Swift Actor
- Subscribe to SecondBrainEventBus events of type .meetingFinalized
- On .meetingFinalized(meetingID:, attendees:):

  STEP 1 — Encounter creation (use 2-A result, verify it fires from EventBus)
  
  STEP 2 — Action item owner resolution:
    For each ActionItem linked to the meeting with ownerPersonID == nil:
      Parse owner name from action item text (e.g., "Tyler will..." → self)
      PersonResolver.resolve(name: extractedName) 
      If resolved: update ActionItem.ownerPersonID
  
  STEP 3 — Decision cross-linking:
    For each Decision extracted from the meeting:
      Set decision.personIDs = meeting.confirmedAttendees (resolved to personIDs)
      Update DecisionStore
  
  STEP 4 — Integration push (check user preferences):
    If Notion integration enabled + "Sync meetings" preference: 
      push meeting summary page (basic version; full bidirectionality is Phase 6)
    If Linear integration enabled + "Auto-create issues" preference:
      push action items with ownerPersonID as assignee
  
  STEP 5 — Notifications:
    Fire "Meeting summary ready" notification with deep link to meeting
    Schedule T+45min "Review your meeting" notification:
      UNTimeIntervalNotificationTrigger(timeInterval: 2700, repeats: false)
      Body: "You met with [attendee names]. Review action items and decisions?"
      Action: deep link to Post-Meeting Review Mode (3-E)
  
  STEP 6 — Queue InsightEngine pass:
    PostMeetingInsightJob.shared.enqueue(meetingID: meetingID)
    (InsightEngine from 3-C will pick this up when ResourceGovernor permits)

- Make the pipeline auditable: write a PostMeetingPipelineLog entry to SQLite
  so Tyler can see what automation ran (visible in meeting detail debug section)
Commit: feat: unified post-meeting pipeline — auto encounters, owner resolution, integration push

3-C: ProactiveContextEngine / InsightEngine (L effort)
- Create Intelligence/InsightEngine.swift as Swift Actor
- Runs as a background task, gated by ResourceGovernor.shared.canScheduleWork(.backgroundInsight)
- Two trigger modes:
    (a) Queued work from PostMeetingPipelineCoordinator
    (b) Idle timer: every 4 hours if not triggered recently
- Work items the InsightEngine processes:

  RELATIONSHIP HEALTH PASS:
    For each Person where strengthLastComputedAt > 24 hours ago:
      Recompute score (1-F formula)
      If score dropped > 0.2: publish .insightAvailable(.relationshipDrift, payload)
      Update Person.strengthLastComputedAt

  PRE-MEETING BRIEF PRE-COMPUTATION:
    For each CalendarEvent in next 24 hours with known attendees:
      PersonContextBuilder.buildContext() for each attendee
      Cache result in BriefCache keyed by (personID, eventID)
      Brief is instantly available when user opens PreMeetingBriefView

  SEMANTIC NUDGE GENERATION:
    Get recently created open ActionItems (last 7 days, not completed)
    searchVaultHybrid(query: task.title, entityTypes: [.meeting, .decision]) 
    If similarity > 0.75: 
      publish .insightAvailable(.semanticNudge, 
        payload: ["task": task, "relatedMeeting": meeting])
    Rate limit: max 3 nudges per day, don't repeat within 72h

  DECISION CROSS-LINK PASS (if P0-E is complete):
    For Decisions where personIDs.isEmpty AND meetingID is set:
      Look up meeting attendees → populate personIDs

- InsightEngine publishes .insightAvailable events to EventBus
- Today view and NotificationManager subscribe to .insightAvailable to surface results
Commit: feat: InsightEngine — background relationship health, brief pre-computation, semantic nudges

3-E: Post-Meeting Review Mode in Meeting Detail (M effort)
- In UnifiedMeetingDetail, detect if meeting ended < 24 hours ago
- If yes: show collapsible "Review" banner at the top with checklist:
    ☐ Review action items ([count] extracted)
    ☐ Link decisions to people ([count] decisions)
    ☐ Schedule follow-up (opens CalendarService write-back — Phase 6)
    ☐ Export to Notion (if integration enabled)
- Each checklist item is tappable and performs the action or navigates to it
- Auto-collapses after 24h or when all items are checked
- Persist checklist state per meeting in MeetingMetadata
Commit: feat: post-meeting review mode — 24h checklist in meeting detail view

3-F: Scheduled Weekly Review Ritual (M effort)
- Add Friday 4:30pm recurring notification (UNCalendarNotificationTrigger, weekday: 6, hour: 16, minute: 30)
- Notification action: deep link to meetingscribe://weekly-review
- Create Views/WeeklyReviewView.swift (replaces or supplements WeeklyRecap.swift markdown export):
    Meeting count this week vs. prior week (delta badge)
    Action items created vs. completed (capture rate %)
    Relationships strengthened (persons whose score increased)
    Key decisions made (Decision list, linked to decisions ledger)
    Ollama-narrated reflection (stream: "Synthesize this week's highlights in 3 sentences")
    "Carry forward" section: incomplete items from last week
- InsightEngine pre-computes weekly data on Friday morning (ResourceGovernor gated)
Commit: feat: scheduled weekly review ritual — Friday notification + native WeeklyReviewView

3-H: Proactive Pre-Meeting Brief Push (M effort)
- In CalendarService, add an observer for upcoming events
- 15 minutes before each CalendarEvent with known attendees:
    Check if BriefCache has pre-computed brief (InsightEngine 3-C pre-computes)
    Fire push notification: "Meeting with [names] in 15 min"
    Action: "View Brief" → deep link to PreMeetingBriefView for that event
- Gate: only fire if user hasn't already opened the brief (track in BriefCache metadata)
- Respect Do Not Disturb / Focus modes
Commit: feat: proactive pre-meeting brief push — 15-min calendar-triggered notification

ACCEPTANCE CRITERIA:
- swift build -c release passes
- 8am notification shows meeting count and follow-up count (verify with test notification)
- After a test meeting finalizes: Encounter auto-created, T+45min notification scheduled
- InsightEngine runs without crashing on idle (monitor with os_log)
- InsightEngine does NOT run while a meeting is being transcribed (ResourceGovernor gate)
- WeeklyReviewView loads with correct meeting count for past 7 days
- ⌘⇧Space opens capture bar from any context (test from other apps)

PR TITLE: feat: Phase 3 — post-meeting pipeline, InsightEngine, weekly ritual, global capture
```

---

## Phase 4 Prompt — Knowledge Graph & Discoverability

**Branch:** `phase/4`  
**Prerequisites:** Phase 3 merged. Pull main.

```
You are implementing Phase 4 of MeetingScribe v2: Knowledge Graph and Discoverability.
The intelligence is now being computed. This phase surfaces it — turning MeetingScribe
from a smart recorder into a queryable second brain.

READ BEFORE STARTING:
1. ~/MeetingScribeRefactor/audit-v2/master-plan.md (Phase 4 section)
2. VaultIndexService.swift (understand current indexing + searchVaultHybrid())
3. ChatTools.swift (existing tool implementations — add searchDecisions here)
4. DecisionStore.swift (after P0-E enrichment)
5. ChatBubble.swift (where citations/sources UI will be added)
6. UnifiedMeetingDetail.swift (where backlinks panel goes)
7. PersonDetailView.swift (where connections panel goes)
8. GlobalSearchView.swift (where ⌘K cross-entity recency goes)

IMPLEMENT:

4-F: Backlinks + Related Meetings Panel (S effort — do first, highest ROI)
- In UnifiedMeetingDetail, add "Related" section after the summary:
    "Similar meetings" — top 3 by embedding cosine similarity (already computed, 
    just not displayed). The similarity data is already in view state — just render it.
    "Shared with [names]" — persons who attended this + other meetings 
    (O(1) via meeting_persons join table from P0-F)
- Each item is tappable: navigates to the related meeting or person
Commit: feat: related meetings + backlinks panel in UnifiedMeetingDetail

4-E: Cited Answer UX in Chat (M effort)
- In ChatBubble.swift, after AI response content, add collapsible "Sources" section:
    Show up to 5 retrieval sources used to ground this answer
    Each source: entity type icon + title + date + "Open" button
    "Open" navigates to the source entity (meeting, person, decision, task)
- In VaultSearchService.searchVaultHybrid(): ensure retrieval sources are returned 
  alongside the answer and passed to the ChatMessage model
- Gate "Sources" section: only show when sources are present (grounded answers only)
Commit: feat: cited answer UX — Sources panel on grounded AI chat responses

4-A: Decision FTS + Semantic Index + Rationale Surface (M effort)
- Verify DecisionStore mutations call VaultIndexService.shared.indexDecision() (from 1-B)
- Verify Decision.rationale is being extracted and stored (from P0-E)
- In the UI, surface rationale in DecisionDetailView (if it exists) or in the 
  decisions feed in Today's decisionsSection
- Add a "Decisions" search scope to GlobalSearchView (alongside existing scopes)
Commit: feat: decision search scope in ⌘K + rationale display in decision detail

4-C: "Why did we decide X?" Chat Tool (S effort)
- In ChatTools.swift, add SearchDecisionsTool:
    name: "searchDecisions"
    description: "Search for decisions made in meetings by topic, person, or project"
    parameters: {query: String, personID: String?, projectID: String?, status: String?}
    implementation: VaultIndexService.shared.searchDecisions(query:filters:)
    returns: top 5 decisions with rationale, meeting backlink, personIDs
- Register the tool in the ChatTools tool list
- Test: "Why did we decide to use SwiftUI instead of AppKit?" should return a decision
Commit: feat: searchDecisions chat tool — Why did we decide X?

4-B: Semantic Connections Panel (M effort)
- Reusable SemanticConnectionsView component:
    input: entityID + entityType
    queries VaultIndexService for top 5 semantically similar entities (cross-type)
    renders as a horizontal scroll strip: entity type chip + title + date
    tappable → navigates to entity
- Add to: UnifiedMeetingDetail (after 4-F backlinks), PersonDetailView, 
  (eventually) DecisionDetailView and task detail
- Use entity type icons (SF Symbols) to distinguish meetings / people / tasks / decisions
Commit: feat: semantic connections panel — cross-entity similarity on entity detail views

4-G: Expand RAG Grounding to All Entity Kinds (S/M effort)
- In VaultSearchService.searchVaultHybrid(), expand the entity types searched:
    Currently: meetings, voice notes
    Add: action items, decisions, persons (via PersonContextBuilder), encounters
- Expand ChatTools cross-entity tool chains: increase maxIterations from current value
  to allow: "Who was at the meeting where we decided X?" style multi-hop queries
- Test: "What tasks does Alex have open?" should hit task index, not just meeting transcripts
Commit: feat: expand RAG grounding to tasks, decisions, persons, and encounters

4-D: Topic-Clustered Decision Ledger View (L effort)
- Create Views/DecisionLedgerView.swift
- Navigation: add "Decisions" to sidebar or as a search scope deep link
- Layout: 
    Filter bar: by person (PersonPicker), project, date range, status (open/resolved/superseded)
    Grouping toggle: by Topic (k-means on embeddings, show cluster label) or by Date
    Each decision card: title, rationale excerpt, persons (chips), date, meeting link, status badge
- Topic clustering: run k-means (k=5–8) on decision embedding vectors, 
  label cluster with most common noun phrases from decision titles in that cluster
  Cache cluster assignments, recompute weekly (InsightEngine pass)
Commit: feat: DecisionLedgerView — topic-clustered decisions with person/project filtering

4-H: Quarterly Recap Generator (M effort)
- Extend WeeklyReviewView or create a QuarterlyRecapView
- Triggered manually ("Generate Q[n] Recap") and via a quarterly reminder
- Aggregates: 13 weekly snapshots, decisions made, relationships grown, 
  meetings by type (1:1, team, external), action item throughput
- Ollama synthesizes a 400-word "Q[n] in review" narrative
- Export option: push to Notion as a Quarterly Review page
Commit: feat: quarterly recap generator with Ollama synthesis and Notion export

4-I: ANN Vector Index (L effort — defer if timeline is tight)
- Research: HNSW implementation in Swift or SQLite-native approximation
- Replace allEmbeddings() full-table scan in searchVaultHybrid 
  with an ANN index (build index on startup, update incrementally on VaultIndexService writes)
- Target: <50ms retrieval for 10,000 embedded entities
- This is a performance optimization, not a feature. Skip if vault size < 5,000 entities.
Commit: perf: ANN vector index — replace O(n) embedding scan for hybrid search

ACCEPTANCE CRITERIA:
- swift build -c release passes
- AI chat: "What did we decide about the design system?" returns a cited decision
- Cited sources panel appears in chat bubble for grounded answers
- SemanticConnectionsView renders on meeting detail with at least 1 related item
- DecisionLedgerView loads with all decisions, filterable by person
- ⌘K "Decisions" search scope returns results

PR TITLE: feat: Phase 4 — knowledge graph, decision ledger, cited chat, semantic connections
```

---

## Phase 5 Prompt — UX Excellence & Habit Loops

**Branch:** `phase/5`  
**Prerequisites:** Phase 4 merged. Pull main.

```
You are implementing Phase 5 of MeetingScribe v2: Native macOS UX Excellence and Habit Loops.
This phase polishes the surfaces, adds daily ritual anchoring, and closes onboarding gaps.

READ BEFORE STARTING:
1. ~/MeetingScribeRefactor/audit-v2/master-plan.md (Phase 5 section)
2. TodayView.swift (full file — many changes land here)
3. GlobalSearchView.swift (⌘K implementation, backStack usage)
4. MetricsStore.swift (add ritual-completion events)
5. ChatView.swift or ChatSidebarView.swift (discovery panel goes here)
6. OnboardingView.swift or AppDelegate (find where first-launch is handled)
7. PersonDetailView.swift (inline insight cards go here)
8. InsightEngine.swift (Phase 3 result — understand .insightAvailable events)

IMPLEMENT:

5-K: "100% Local" Privacy Badge (S effort — do first, zero risk)
- Add a small "100% Local · No Cloud" badge to:
    Today view header (next to app name/date)
    Onboarding welcome screen
    PreferencesView privacy section with expanded explanation
- Use a lock.fill SF Symbol + muted text, not intrusive
Commit: feat: 100% Local privacy badge in Today header and onboarding

5-F: Capability Discovery Panel (S effort)
- In ChatSidebarView / ChatView, add collapsible "What can I ask?" section:
    Categories with example prompts populated with real user data:
    "About your meetings" → ["Summarize last week", "What did I discuss with [last person]?"]
    "About people" → ["Brief me on [most recent contact]", "Who needs a check-in?"]
    "About tasks" → ["What's overdue?", "What did I commit to Alex?"]
    "About decisions" → ["Why did we decide X?", "List Q3 decisions"]
    Replace [placeholders] with actual names from PersonStore / recent meetings
- Dismiss hint after user has sent 5 chat messages (persisted in UserDefaults)
Commit: feat: capability discovery panel — suggested prompts in chat sidebar

5-H: Post-Onboarding First Steps + Onboarding Improvements (S-M effort)
- Detect first launch after onboarding completes
- Add dismissible "First Steps" card to Today blank state:
    "Record your first meeting" (taps to start recording)
    "Add a person you meet regularly" (taps to PersonCreate sheet)
    "Ask the AI something" (taps to open chat rail with suggested prompt)
- Rewrite Screen Recording permission prompt text to plain language:
    Current: technical macOS permission language
    New: "MeetingScribe needs to record your screen to capture meeting audio from 
    Zoom, Teams, and other apps. Your recordings stay on your Mac — nothing is uploaded."
- After first meeting summary is generated: 
    Fire "Your first meeting is ready!" push notification
    Deep link to that meeting's summary view
Commit: feat: first-steps card, permission rewrite, and first-meeting notification for new users

5-B: ⌘K Cross-Entity Recency (S effort)
- In GlobalSearchView, expand the recency results shown before user types:
    Recent meetings (already there)
    Recent persons (last 5 PersonDetailView opens — track in backStack)
    Recent decisions (last 3 DecisionStore creates)
    Recent tasks (last 5 ActionItem creates)
- Show entity type icons to distinguish items
- After user types: search scope dropdown includes Decisions as a new option
Commit: feat: ⌘K cross-entity recency — people, decisions, tasks alongside meetings

5-G: Tool-Use Narration + Write-Back Confirmation Cards (M effort)
- In ChatBubble.swift, detect tool-call message types
- Replace raw JSON display with:
    Tool call: "[tool icon] Searching your vault for '[query]'..."
    Tool result (read): collapsible source count: "Found 3 relevant meetings"
    Tool result (write): confirmation card:
      "[checkmark] Created task: [title], due [date]" with Undo button
      "[checkmark] Logged encounter with [name]" with Open button
- Undo button: calls reverse operation via store's delete/undo API
Commit: feat: tool-use narration — replace raw JSON with human-readable action cards

5-A: Relational Context Strip on Entity Views (M effort)
- Create RelationalContextStrip component: horizontal ScrollView of EntityChip items
- EntityChip: SF Symbol for type + name + subtle date label, tappable → navigate
- Add to PersonDetailView (top section, below name):
    Last meeting (chip) · Next calendar event (chip) · [n] open tasks (chip) · 
    [n] decisions (chip → DecisionLedger filtered by person)
- Add to UnifiedMeetingDetail (below title):
    Attendees (person chips) · Linked decisions · Action items count
- Data from P0-F join tables — all O(1) lookups
Commit: feat: relational context strip on entity detail views — cross-tab connections

5-J: "Waiting On" Delegation Board (M effort)
- Create a "Waiting On" section in Today (or as a dedicated view linked from Today):
    Tasks where delegated = true AND completed = false
    Grouped by person (ownerPersonID or delegatedToPersonID)
    Shows: task title, days waiting (createdAt delta), person chip
    Context menu: "Follow up with [name]" (opens AI conversation starter from 2-D)
    "Mark resolved" (completes the task)
- The delegated flag and ownerPersonID already exist on ActionItem
Commit: feat: Waiting On board — first-class delegation view from Today

5-E: Inline AI Insight Cards on Entity Views (M effort)
- Subscribe to SecondBrainEventBus .insightAvailable events in PersonDetailView
- When an insight for this person arrives (or on entity open):
    Show a dismissible card at the top: 
    "[bulb icon] [Ollama-generated 2-sentence insight about this person]"
    Example: "You haven't discussed the budget approval with Alex since June — it's marked open."
- Generate insight: PersonContextBuilder.buildContext() → lightweight Ollama prompt
  (ResourceGovernor gated — only on open if last computed > 48h ago)
- Store insight + computedAt in PersonInsightCache (simple in-memory + disk cache)
Commit: feat: inline AI insight cards on PersonDetailView and UnifiedMeetingDetail

5-C: AI Morning Briefing Card on Today (M effort)
- Add "Morning Brief" card to top of TodayView (below date header, above upNextCard)
- Card shows InsightEngine's pre-computed morning synthesis (from 3-C):
    A 2–3 sentence Ollama-narrated paragraph: 
    "Today you have 3 meetings including a 1:1 with Alex where the budget approval is still open.
    You have 5 tasks due and a check-in overdue with Sarah."
- Tapping expands to show the full context breakdown
- Refreshes if InsightEngine has computed a newer brief (observe @Published property)
- Show skeleton loader while brief is being computed
Commit: feat: AI morning briefing card on Today — InsightEngine-powered synthesis

5-D: Compounding Value Dashboard + Streaks (M effort)
- Add ritual-completion events to MetricsStore:
    .dailyOpen (fired on first app open each day)
    .standupCompleted (fired on standup generation)
    .weeklyReviewCompleted (fired on WeeklyReviewView dismiss with checklist complete)
    .captureAction (fired on any task/note/encounter create)
- In Today header: add streak counter (flame.fill SF Symbol + "N day streak")
    Streak: consecutive days with at least one .dailyOpen + one .captureAction
- Add "Your Second Brain" expandable section at bottom of Today:
    12-week sparkline: meeting count per week
    12-week sparkline: action capture rate (tasks created / meetings that week)
    Total: meetings recorded, decisions captured, people tracked
    Streak counter (larger version with milestone badges at 7, 30, 100 days)
Commit: feat: compounding value dashboard — streaks, sparklines, and second-brain totals on Today

5-I: End-of-Day Wrap-Up Card on Today (M effort)
- After 5pm (or user-configurable hour): TodayView appends "End of Day" card
- Card content:
    "Today's capture: [N] tasks created, [N] meetings recorded"
    "Still open: [N] follow-ups" (tappable → followUpsSection)
    "Tomorrow: [first meeting name]" with time
    "Reflection prompt: What's the one thing you want to carry forward?" 
    (free-text field → saves as a VoiceNote-style text note)
- Card auto-expires at midnight
Commit: feat: end-of-day wrap-up card on Today — daily closure ritual

ACCEPTANCE CRITERIA:
- swift build -c release passes
- "100% Local" badge visible in Today header
- Capability discovery panel visible in chat sidebar (collapses after 5 messages)
- ⌘K shows people and decisions alongside meetings before typing
- PersonDetailView shows relational context strip (last meeting, tasks, decisions)
- Today shows AI Morning Brief card with loading state
- Streak counter visible in Today header after 2 consecutive daily opens

PR TITLE: feat: Phase 5 — UX polish, daily rituals, streaks, discovery panel, onboarding
```

---

## Phase 6 Prompt — Integration Depth & External Connectivity

**Branch:** `phase/6`  
**Prerequisites:** Phase 5 merged. Pull main.

```
You are implementing Phase 6 of MeetingScribe v2: Integration Depth and External Connectivity.
These items extend MeetingScribe into the user's broader tool ecosystem.

READ BEFORE STARTING:
1. ~/MeetingScribeRefactor/audit-v2/master-plan.md (Phase 6 section)
2. NotionService.swift or NotionIntegration.swift (existing one-way export)
3. LinearService.swift or LinearIntegration.swift (existing task push)
4. CalendarService.swift (read/write capabilities)
5. MeetingScribeMCP (tool definitions — for 6-D expansion)
6. SecondBrainEventBus.swift (6-F webhook system subscribes here)
7. PersonContextBuilder.swift (6-G Claude Projects uses this)

IMPLEMENT:

6-E: Integration Status Dashboard (S effort — do first)
- In Settings/PreferencesView, add "Integrations" section:
    For each integration (Notion, Linear, Calendar, iMessage, MCP):
    Status badge (connected/disconnected/error), last sync time, error message if any
    "Reconnect" button for auth errors
    "Test connection" button (fires a test call, shows success/failure toast)
Commit: feat: integration status dashboard in settings

6-B: Linear Action-Item Context Menu (M effort)
- In ActionItem row views (meeting detail + Today view):
    Add context menu item: "Create Linear Issue"
    Sheet: pre-fills title (task title), description (meeting context excerpt), 
    assignee (if ownerPersonID resolved to a Linear user ID via linkedExternalIDs)
    On confirm: LinearService.createIssue(...)
    On success: store Linear issue ID in ActionItem.linkedExternalIDs["linear"]
    Show "View in Linear" button on the task row after creation
Commit: feat: Linear issue creation from action item context menu

6-D: MCP Tool Surface Expansion (M effort)
- Add to MeetingScribeMCP tool definitions:
    getPersonBrief(personID: String) → PersonContext summary JSON
    searchDecisions(query: String, personID?: String) → [Decision]
    listWaitingOn(personID?: String) → [ActionItem] where delegated=true
    getRelationshipHealth(personID: String) → health score + signals
    getEncounterHistory(personID: String, limit: Int) → [Encounter]
    listOpenDecisions(projectID?: String) → [Decision] where status=.open
    scheduleFollowUp(personID: String, date: ISO8601String) → CalendarEvent
- Each tool implementation calls the corresponding in-app service
- Re-sign MCP binary after changes:
    codesign --force --sign "MeetingScribe Local Signer" .build/release/MeetingScribeMCP
Commit: feat: MCP tool surface expansion — 7 new person/decision/task tools

6-C: Calendar Write-Back (M effort)
- In PostMeetingReviewMode (3-E) and PreMeetingBriefView:
    Add "Schedule follow-up" button
    Opens a compact date/time picker + title field
    CalendarService.createEvent(title:date:attendees:notes:)
    On success: show confirmation with "View in Calendar" link
- Also wire to AI chat tool: create CalendarEventTool in ChatTools.swift
    "Schedule a follow-up with Alex for Thursday at 2pm" → create event
Commit: feat: calendar write-back — schedule follow-ups from brief and review mode

6-A: Notion Bidirectional Sync (L effort)
- Upgrade NotionService from one-way action-item export to full sync:
    CREATE: on meetingFinalized, create a Notion page in the configured database:
      Title: meeting title + date
      Properties: date, attendees (Notion relation if persons DB exists), status
      Blocks: summary, decisions (toggle list), action items (checkbox list)
      Store Notion page ID in Meeting.linkedExternalIDs["notion"]
    UPDATE: daily job polls Notion for status changes on linked pages:
      If action item checkbox is checked in Notion → mark complete in ActionItemStore
      If page is archived in Notion → mark meeting as exported
    DECISIONS: create a Notion page in a separate Decisions database for each Decision
      with rationale, persons, status, and meeting backlink
- Expose sync preferences: which databases to sync to (stored in NotionPreferences)
Commit: feat: Notion bidirectional sync — meeting pages, decisions, and status pull-back

6-F: Outbound Webhook System (M effort)
- Create Integrations/WebhookService.swift
- User can configure webhook URLs in Settings (list of {url, events: [EventType], secret})
- WebhookService subscribes to SecondBrainEventBus
- On relevant events: POST to webhook URL with JSON payload + HMAC-SHA256 signature
    meetingFinalized: {meetingID, title, attendees, summaryExcerpt, actionItemCount}
    taskCreated: {taskID, title, ownerPersonID, dueDate}
    decisionExtracted: {decisionID, text, rationale, personIDs}
- Retry on failure (3 attempts with exponential backoff)
- Show delivery log in webhook settings (last 20 deliveries with status)
Commit: feat: outbound webhook system — configurable event delivery for external automation

6-G: Claude Projects Sync (M effort)
- Create Integrations/ClaudeProjectsSync.swift
- User configures their Claude API key and target Project ID in Settings
- On a daily schedule (InsightEngine pass, ResourceGovernor gated):
    Export to project knowledge base:
    — Recent meeting summaries (last 7 days) as markdown files
    — Person briefs (PersonContextBuilder.buildContext() for top 20 persons by strength)
    — Open decisions (Decision Ledger export)
    — Open action items summary
- Uses Claude API projects file upload endpoint
- Store last sync timestamp; only re-export changed entities
Commit: feat: Claude Projects sync — MeetingScribe as living knowledge source for Claude

ACCEPTANCE CRITERIA:
- swift build -c release passes
- Integration status page visible in Settings with Notion/Linear/Calendar state
- MCP tool getPersonBrief(personID:) returns a populated JSON object (test with Claude Desktop)
- Notion sync creates a meeting page after a test meeting finalizes (if Notion connected)
- Webhook fires a POST to a test endpoint on taskCreated event
- Linear "Create Issue" context menu available on action item rows

PR TITLE: feat: Phase 6 — Notion bidirectional sync, MCP expansion, webhooks, Claude Projects
```

---

## Reusable Snippets

### PR Description Template

```markdown
## What
[1-2 sentence summary of what this PR does]

## Why (master plan reference)
Implements [item IDs] from audit-v2/master-plan.md.
[1 sentence on why this matters — the user-facing payoff]

## Changes
- [File/component]: [what changed]
- [File/component]: [what changed]

## Testing
- [ ] swift build -c release passes with zero errors
- [ ] Today view loads without crash
- [ ] Meeting recording starts and stops
- [ ] AI chat responds to a simple query
- [ ] People tab shows existing persons
- [ ] [Feature-specific smoke test]

## Dependencies
- Requires: [prior PR or branch]
- Unblocks: [next items from master plan]

## Schema migrations
- [ ] N/A — no model changes
- [ ] SchemaVersion incremented and migration case added in [StoreName]SchemaMigrations
```

---

### Smoke Test Checklist

Run before every PR. Takes < 5 minutes.

```
1. App launches without crash
2. Today view loads (shows correct date, upNextCard or empty state)
3. Navigate to Meetings tab — library shows existing meetings
4. Navigate to People tab — shows existing persons
5. Navigate to Tasks tab — shows existing tasks
6. Open chat rail — no crash, chat input available
7. Type "What did I discuss last week?" — AI responds (may be empty if no data)
8. Start a meeting recording — mic permission granted, waveform appears
9. Stop recording — pipeline runs, no crash
10. ⌘K opens GlobalSearch — shows recent items
11. Open a person — PersonDetailView loads
12. Open a meeting — UnifiedMeetingDetail loads with summary/transcript tabs
```

---

### Rescue Prompt (When Claude Code Is Stuck)

```
You appear to be stuck or going in circles. Let's reset.

Current state:
- Branch: [branch name]
- Last successful build: [describe]
- Error you're hitting: [paste error]
- What you were trying to do: [item ID from master plan]

Step back and:
1. Run swift build -c release and share the FULL error output
2. Read the file causing the error from scratch (don't trust your memory of it)
3. Check if the error is in a file YOU created in this session vs. a pre-existing file
4. If the error is in a pre-existing file, consider whether your change broke an 
   existing interface — check callers with grep
5. If stuck for more than 3 iterations on the same error, revert the failing change,
   describe what you tried, and ask for a different approach

Do not keep retrying the same fix. Fresh read → fresh approach.
```

---

### SchemaEnvelope Migration Checklist

Every time you add a field to a stored model:

```
□ Increment SchemaVersion constant in [Model]Store.swift
□ Add migration case to [Model]SchemaMigrations enum:
    case v1_to_v2: // describe what changed
        return migration that adds new field with safe default
□ Add the new field to the model struct with a default value
□ Test: install a build WITHOUT the field, add some data, then install the new build
    → existing data should still load with the field set to its default value
□ Never remove fields — only deprecate with @available(*, deprecated) comment
```
