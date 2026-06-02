# MeetingScribe — Claude Code Build Playbook
> Synthesized from 25-agent audit (2026-06-02). Paste one prompt per session, in order. Do not start Phase N+1 until Phase N's PR is merged and green.

## How to use

Copy PROMPT 0 and either paste it at the top of every new Claude Code session or append it permanently to `CLAUDE.md` (the preferred approach — it becomes part of the project's standing context). Then, for each build session, paste exactly one phase prompt. Work through the items it lists, let Claude Code open a PR at the end, review and merge that PR, confirm CI is green, and only then paste the next phase prompt. Each phase depends on the previous one being fully merged — skipping phases will break assumptions in later prompts. The distress-signal safety item (C2-4) and the Sparkle fix must ship in Phase 0 before any public release or announcement.

## Build order

1. Phase 0 — Critical Fixes (P0 bugs; independent of each other; do these before anything else)
2. Phase 1 — RelationshipPath Foundation (keystone model change; all later phases depend on this)
3. Phase 2 — Encounter Logging & Check-in Habit (depends on Phase 1)
4. Phase 3 — Relationship Content & AI Coaching (depends on Phase 1)
5. Phase 4 — MCP Expansion (depends on Phase 1 for relationship type; some items are independent)
6. Phase 5 — UX Polish & Small-Lift Wins (depends on Phase 1; items are individually orderable)
7. Phase 6 — Monetization (build before any public announcement)

---

## PROMPT 0 — Ground Rules (paste once / append to CLAUDE.md)

```text
## MeetingScribe — Claude Code Standing Rules

REPO
- Local: ~/MeetingScribeRefactor  Remote: tyleryannes94/meetingscribe-refactor  Branch: main
- NEVER touch ~/MeetingScribe, ~/frost, or any directory outside ~/MeetingScribeRefactor.

REFERENCE DOCS (read before implementing any item)
- docs/audit-2026/MASTER-PLAN.md — full plan with all item IDs
- docs/audit-2026/findings/E1-architecture.md — architecture detail
- docs/audit-2026/findings/E2-data-model.md — data model detail
- docs/audit-2026/findings/E3-mcp-server.md — MCP detail
- docs/audit-2026/findings/E4-performance.md — performance & reliability detail
- docs/audit-2026/findings/E5-testing.md — testing strategy
Every item ID (E4-1, P2-1, C2-4, etc.) maps to one of these files. Read the relevant section before writing any code.

COMMIT STYLE
- Prefix: feat: / fix: / refactor: / chore: / docs:
- Subject: imperative mood, lowercase first word after prefix, under 72 chars.
- Body (optional): wrap at 80, explain WHY if non-obvious.
- No Co-Authored-By trailers unless explicitly requested.

BUILD VERIFICATION
- After any non-trivial Swift edit, run: swift build -c release
- Warnings are fine. Errors block the commit. Do not push a broken build.

PUSH DISCIPLINE
- After every code/config edit, ask once: "Push these changes to tyleryannes94/meetingscribe-refactor?"
- If yes: git add -A → git commit -m "..." → git push. Then confirm SHA + branch.
- Skip the question only when: the edit was reverted, it is a temporary diagnostic, or the user says "don't push" / "local only".

SCOPE DISCIPLINE
- Implement ONLY the items listed in the current phase prompt.
- If you discover something out-of-scope that needs doing, note it in the PR description under "Out of scope / noticed" — do not implement it.

AUDIO PIPELINE GUARD
- If any item touches MeetingManager, AudioRecorder, LiveTranscriber, or MeetingPipelineController, call it out explicitly before making changes. These files carry P0 recording reliability. Proceed carefully and verify the daemon path (DarwinNotifier.recordingStopped) and the direct path (MeetingManager.stopRecording) are both still correct after every change.

ENVIRONMENT
- macOS 26.3.1 (Tahoe), Apple Silicon M2 Mac mini.
- Use /usr/bin/open directly in scripts — ~/bin/open is a custom wrapper that may redirect.
- Code-signing identity: "MeetingScribe Local Signer" (self-signed, login keychain).
- Bundle ID: com.tyleryannes.MeetingScribe. MCP binary: Contents/MacOS/MeetingScribeMCP, same signing identity.
- TCC permissions are pinned to the cert CN — rebuilds do not re-prompt for Screen Recording / Mic / Calendar.
```

---

## PROMPT 1 — Phase 0: Critical Fixes

```text
Branch: fix/phase-0-critical

Read docs/audit-2026/findings/E4-performance.md §1 and §8 (E4-1), E3-mcp-server.md §3.5 (P5-12), and MASTER-PLAN.md §3 before starting. Implement the items below in order. Run swift build -c release after each item.

ITEM 1 — E4-1: Wire finalize() into the daemon stop path [P0, DATA LOSS]
File: Sources/MeetingScribe/MeetingManager.swift, lines 136–149 (DarwinNotifier.recordingStopped observer).
Problem: The recordingStopped handler calls flush() and renderMarkdown() on the live transcriber, then writes the raw transcript and resets state — but never calls pipelineController.finalize(). Every meeting stopped via ScribeCore produces no summary, no action items, and no FTS index.
Fix:
  1. Before the state-reset block, snapshot droppedChunkCount and liveCoverageSeconds from the live transcriber (the same values used in the direct stop path at MeetingManager.swift:352).
  2. Call await pipelineController.finalize(meeting: m, audioResult: ..., liveTranscript: live, liveDroppedChunks: dropped, liveCoverageSeconds: coverage, recordedDuration: ...) with those values.
  3. Add a guard to prevent concurrent finalize calls (mirror the guard already present on the direct path).
Cross-reference: E4-performance.md §8 E4-1 for exact implementation detail.

ITEM 2 — ENG-A (residual): Verify batch-repair gate coverage
File: Sources/MeetingScribe/MeetingPipelineController.swift, lines 74–84 (needsBatchRepair).
The fix is 90% done per E4-performance.md §1. Confirm the gate checks all three conditions: droppedChunkCount > 0, recordedDuration <= tolerance (sub-one-chunk), and liveCoverageSeconds < (recordedDuration - tolerance). If the daemon path change in Item 1 now passes correct coverage metadata, this gate should fire correctly. Add a comment citing E4-1 + ENG-A so the connection is clear.

ITEM 3 — P5-12: Verify birthday field in tool_getPerson [verify-before-fixing]
File: Sources/MeetingScribeMCP/main.swift, around line 1094–1112 (tool_getPerson response dict).
Per E3-mcp-server.md §3.5: birthday IS already present at line 1106. Confirm by reading the exact lines. If birthday is present, add a code comment: "// birthday confirmed present — P5-12 audit finding was incorrect". If it is absent, add: ".string(p.birthday.map(iso) ?? "")". Do NOT make any other changes in this item.

ITEM 4 — C2-4: Distress signal pre-flight filter [safety requirement for public release]
Files: wherever the Ollama/AI pipeline processes encounter notes or relationship analysis — likely OllamaService.swift or the analysis preset runner in PersonDetailView.swift.
Before any Ollama call that processes user-written encounter notes or relationship content:
  1. Define a conservative keyword list (clear crisis language only — e.g. "kill myself", "end my life", "don't want to be here", "suicidal", "self-harm"). Keep it minimal and unambiguous.
  2. If any keyword matches the input text: skip the AI call entirely, return nil/empty result, and set a flag the call site can use to surface a gentle in-UI message: "It sounds like things may be hard right now. If you're struggling, the Crisis Text Line is here: text HOME to 741741."
  3. Use @AppStorage or a local constant for the flag — do not require a network call to check.
  4. Do not log the matched text anywhere.

ITEM 5 — Sparkle fix: Confirm updater is configured
Files: Sources/MeetingScribe/Updates/UpdaterController.swift and Resources/Info.plist.
Check:
  - UpdaterController.isConfigured logic (around line 21–24): ensure it returns true only when SUPublicEDKey is non-empty and non-placeholder.
  - Info.plist SUFeedURL: must point at github.com/tyleryannes94/meetingscribe-refactor, not the old repo. Update if wrong.
  - If SUPublicEDKey still contains "REPLACE_WITH" or is empty, note this in the PR and leave a // TODO: generate EdDSA key pair with Sparkle CLI `generate_keys` comment — do not block the PR on it, but flag it clearly.

BUILD + SMOKE TEST
After all five items:
  swift build -c release
Launch the app, start a 30-second ad-hoc recording from the menu bar, stop it, confirm summary and action items appear in MeetingDetailView. If you can trigger a daemon-path stop (ScribeCore), do so and confirm finalize() ran by checking that summary.md is written.

PR title: "fix: wire finalize() into daemon path, distress filter, Sparkle URL (Phase 0)"
PR body: list each item with pass/fail, note whether birthday was already present (P5-12), and list any environment setup still needed for Sparkle (EdDSA key).
```

---

## PROMPT 2 — Phase 1: RelationshipPath Foundation

```text
Branch: feat/phase-1-relationship-type

CRITICAL: Read E1-architecture.md §3 and §6, E2-data-model.md §3 and the NET-NEW section, E5-testing.md §5 (E5-5), and MASTER-PLAN.md §4 in full before writing a single line of code.

This is the keystone change. 22 of 25 audit agents independently identified the absence of a structured RelationshipPath enum as the root gap blocking every relationship-coaching feature. Do not start Phase 2 or 3 work until this PR is merged and CI is green.

ORDER MATTERS: write tests first (E5-5), then the enum, then the model changes, then the migration, then the UI.

STEP 1 — E5-5: Write RelationshipTypeTests BEFORE any implementation
File: Tests/MeetingScribeTests/RelationshipTypeTests.swift (new file)
Write tests covering:
  - Round-trip Codable for all RelationshipPath cases
  - Unknown future raw value ("something_new_2027") falls back gracefully (does not crash or produce a non-nil but wrong value — the tolerant try? decoder swallows bad raw values silently, so test that this is intentional and documented)
  - suggestedCheckInDays is non-nil and <= 7 for romanticPartner/spouse, non-nil and <= 14 for parent/child/sibling, non-nil for closeFriend/friend, nil for colleague/vendor/custom
  - supportsDepthContent is true for romanticPartner, spouse, closeFriend, parent, child, sibling; false for colleague, vendor, custom
Run swift test before proceeding. Tests should compile but the enum doesn't exist yet — that's expected. The tests will fail with "no such type". Proceed to Step 2.

STEP 2 — E1-1 / E2-1 / P1-1: Add RelationshipPath enum to VaultKit
File: Sources/VaultKit/RelationshipPath.swift (new file)
Owner: VaultKit — no SwiftUI dependency. Foundation-only.
```swift
public enum RelationshipPath: String, Codable, CaseIterable, Sendable {
    case romanticPartner   = "romantic_partner"
    case spouse            = "spouse"
    case exPartner         = "ex_partner"
    case parent            = "parent"
    case child             = "child"
    case sibling           = "sibling"
    case familyMember      = "family_member"
    case closeFriend       = "close_friend"
    case friend            = "friend"
    case manager           = "manager"
    case directReport      = "direct_report"
    case colleague         = "colleague"
    case mentor            = "mentor"
    case client            = "client"
    case vendor            = "vendor"
    case custom            = "custom"

    public var displayName: String { ... }  // human label distinct from rawValue

    public var suggestedCheckInDays: Int? {
        switch self {
        case .romanticPartner, .spouse: return 1
        case .parent, .child, .sibling: return 7
        case .closeFriend: return 14
        case .friend: return 30
        case .manager, .directReport: return 14
        default: return nil
        }
    }

    public var supportsDepthContent: Bool {
        switch self {
        case .romanticPartner, .spouse, .closeFriend, .parent, .child, .sibling: return true
        default: return false
        }
    }
}
```
Run swift build -c release. Run swift test — RelationshipTypeTests should now pass.

STEP 3 — E2-1: Add optional fields to Person (app model)
File: Sources/MeetingScribe/People/Person.swift
Add to Relationship struct (line 51–64):
  var path: RelationshipPath?    // nil = legacy record
Add to Person struct:
  var relationshipType: RelationshipPath? = nil
  var checkInCadenceDays: Int? = nil
  var lastCheckInAt: Date? = nil
Use the existing try? decodeIfPresent pattern for all three in Person.init(from:). Zero migration risk — existing person.json files decode with nil for all new fields. Bump personSchemaVersion to 2 in PeopleStore.swift:23.
Run swift build -c release.

STEP 4 — E2-7: Mirror new fields to PersonDTO in VaultKit
File: Sources/VaultKit/SharedModels.swift (PersonDTO and PersonRelationshipDTO)
Add path: RelationshipPath? to PersonRelationshipDTO.
Add to PersonDTO:
  public let relationshipType: String?
  public let checkInCadenceDays: Int?
  public let lastCheckInAt: Date?
Use (try? c.decodeIfPresent(...)) ?? nil — same tolerant pattern already at SharedModels.swift:216–256.
Run swift build -c release. Run swift test.

STEP 5 — E2-5: migrateToV3() in SecondBrainDB
File: Sources/MeetingScribe/Storage/SecondBrainDB.swift
Add a migrateToV3() private method:
  ALTER TABLE people ADD COLUMN relationship_type TEXT;
  ALTER TABLE people ADD COLUMN checkin_cadence_days INTEGER;
  ALTER TABLE people ADD COLUMN last_checkin_at REAL;
  ALTER TABLE encounters_idx ADD COLUMN kind TEXT;
  ALTER TABLE encounters_idx ADD COLUMN quality_rating INTEGER;
  UPDATE schema_meta SET value='3' WHERE key='schema_version';
Also add both missing indexes (from E4-5 in E4-performance.md):
  CREATE INDEX IF NOT EXISTS idx_encounters_event_tag ON encounters_idx(event_tag_id);
  CREATE INDEX IF NOT EXISTS idx_encounters_person ON encounters_idx(person_id);
Bump schemaVersion constant to 3. Call migrateToV3() from ensureSchema() when current version is 2.
Run swift build -c release.

STEP 6 — E2-10: One-time forward migration from Relationship.label strings
File: Sources/MeetingScribe/People/PeopleStore.swift (post-load pass in publishLoaded or load)
After loading each Person, if relationshipType == nil, inspect relationships[].label using:
  partnerLabels: ["spouse","partner","wife","husband","boyfriend","girlfriend","fiancé","fiancée"]
  familyLabels: ["mom","dad","mother","father","sister","brother","kid","child","parent","grandparent"]
  closeFriendLabels: ["best friend","bestie","bff","close friend"]
Set person.relationshipType accordingly and write the person back to disk if changed. Run this pass once per install (guard with a UserDefaults key "didMigrateRelationshipTypes").
Run swift build -c release. Run swift test.

STEP 7 — D2-2 / P1-2: Add RelationshipPath picker to AddPersonSheet
File: Sources/MeetingScribe/People/AddPersonSheet.swift (lines 47–113)
Add a relationship type picker as the first field. Use 3 large tap-target cards for the most common paths: [Partner / Spouse] [Family Member] [Close Friend] — plus a "More types" disclosure that shows the full RelationshipPath.allCases picker. "Skip" option leaves relationshipType nil. When a path is selected, auto-fill checkInCadenceDays from path.suggestedCheckInDays.
Run swift build -c release. Run swift test.

VERIFICATION: Phase 1 is done when:
- swift test passes (all RelationshipTypeTests green)
- swift build -c release succeeds
- A new person created in AddPersonSheet has a non-nil relationshipType
- An existing person.json with "spouse" relationship label loads with relationshipType == .romanticPartner
- get_person MCP response includes relationshipType field

PR title: "feat: add RelationshipPath enum and keystone data model (Phase 1)"
PR body: list each step with build/test status. Note that this is the keystone — Phases 2–4 depend on this PR being merged.
```

---

## PROMPT 3 — Phase 2: Encounter Logging & Check-in Habit

```text
Branch: feat/phase-2-checkin-habit

Read MASTER-PLAN.md §5 (Phase 2) and E2-data-model.md §3 E2-2 before starting. Phase 1 must be merged before this branch is created.

ITEM 1 — D4-3 / E2-2: Add EncounterKind and EncounterMood enums
Files: Sources/MeetingScribe/People/Encounter.swift and Sources/VaultKit/Encounter.swift
Add to app-side Encounter.swift:
  enum EncounterKind: String, Codable, CaseIterable, Sendable {
      case call, coffee, dinner, qualityTime, difficultConversation, inPerson,
           sharedActivity, birthday, checkIn, custom
  }
  enum EncounterMood: String, Codable, CaseIterable, Sendable {
      case great, good, neutral, tense, hard
  }
Add optional var kind: EncounterKind? and var mood: EncounterMood? to Encounter. Use tolerant decodeIfPresent — zero migration risk. Mirror these enums to VaultKit/Encounter.swift. Bump encounterSchemaVersion to 2 in PeopleStore.swift:24.
Run swift build -c release.

ITEM 2 — D4-1 / C2-1 / U3-3: Chip-first inline encounter quick-log
File: Sources/MeetingScribe/People/PersonDetailView.swift (encounters section, ~line 1096)
Replace the "Add Encounter" button that opens a sheet requiring a mandatory event name with an inline chip-first flow:
  - Row of 5 kind chips (icons + labels): Call / Coffee / Dinner / Quality Time / Difficult Conversation
  - Tapping a kind chip immediately creates and saves the encounter (eventName auto-filled from kind.displayName, date = now)
  - Below the chips: optional one-line mood chip row (Great / Good / Neutral / Tense / Hard) that appears after kind is tapped
  - Optional freeform note TextField that appears below mood chips
  - The encounter is saved as soon as kind is tapped. Note and mood update the encounter record if filled in.
  - Keep the existing AddEncounterSheet for the "full form" option (... button or swipe action), but the primary flow requires zero required fields.
Run swift build -c release.

ITEM 3 — D4-2 / P2-1: Per-person check-in notification scheduler
File: Sources/MeetingScribe/Notifications/NotificationManager.swift
Add syncPersonReminders(people: [Person]) that:
  - For each person where checkInCadenceDays is non-nil (or inferred from relationshipType.suggestedCheckInDays):
    - Computes lastInteractionAt + cadenceDays
    - If overdue OR due within 24h: schedules a UNCalendarNotificationTrigger
    - Notification body by type: romanticPartner/spouse → "Haven't logged time with [Name] in [N] days — how are they doing?"; closeFriend → "[Name] — it's been [N] days. Worth a catch-up?"; other → "[Name] — [N] days since last contact."
    - Category: PERSON_CHECKIN with two actions: "Log now" (opens quick-log) and "Snooze 3 days"
  - Removes stale notifications for people who no longer qualify
Wire syncPersonReminders() to: (1) applicationDidFinishLaunching, (2) after any encounter is saved, (3) after any person is edited.
Run swift build -c release.

ITEM 4 — P2-9: Birthday push notifications
Extend syncPersonReminders() (same file) to also schedule birthday notifications:
  - 7 days before birthday at 9am: "[Name]'s birthday is in 7 days"
  - Morning of birthday at 9am: "Happy birthday, [Name]!"
  - Use UNCalendarNotificationTrigger with dateComponents for month+day (repeats yearly)
  - Only schedule if person.birthday is non-nil
Run swift build -c release.

ITEM 5 — C3-7: Binary "Did you connect?" inline prompt in SuggestedPeopleView
File: Sources/MeetingScribe/People/SuggestedPeopleView.swift (ReconnectView cards)
Replace the chevron-only row with an inline action pair:
  - Person name + "It's been [N] days" text
  - [Yes, we talked] button: creates a quick encounter (kind=.call, date=now, no sheet) and removes the card
  - [Not yet] button: snoozes the card for 3 days (write a snoozedUntil date to person.json or UserDefaults keyed by person ID)
Run swift build -c release.

ITEM 6 — D1-6: Type-stratified reconnect thresholds
File: Sources/MeetingScribe/People/SuggestedPeopleView.swift (cadenceSeconds or goneColdDays logic ~line 95)
Replace the flat 45-day cutoff with per-type thresholds sourced from person.relationshipType?.suggestedCheckInDays ?? 45. The per-type values from RelationshipPath are: romanticPartner/spouse=1, parent/child/sibling=7, closeFriend=14, friend=30, manager/directReport=14, colleague=45, nil=45.
Run swift build -c release. Run swift test.

PR title: "feat: chip-first encounter logging and check-in notifications (Phase 2)"
```

---

## PROMPT 4 — Phase 3: Relationship Content & AI Coaching

```text
Branch: feat/phase-3-coaching-content

Read MASTER-PLAN.md §6 (Phase 3) and E1-architecture.md §6 E1-5 before starting. Phase 1 must be merged. This phase is primarily prompt rewrites and static Swift enums — no server, no Ollama changes to the inference engine itself.

ITEM 1 — U5-3 / C2-3: Type-aware Ollama prompt preamble
File: Sources/MeetingScribe/People/PersonDetailView.swift (around line 84–91, the hardcoded "adult professional" preamble)
Add a private function:
  func personContextPreamble(for path: RelationshipPath?) -> String
Return type-appropriate framing:
  - romanticPartner / spouse → "You are a warm, curious relationship coach informed by Gottman Method research. You help people understand their intimate relationships with compassion and evidence-based insight."
  - parent / child / sibling / familyMember → "You are a family therapist informed by Nonviolent Communication (NVC). You help people understand family dynamics with empathy and without judgment."
  - closeFriend → "You are a supportive coach who helps people maintain meaningful, reciprocal friendships. Your tone is warm and direct."
  - manager / directReport / colleague → "You are a professional coach. Your tone is clear, constructive, and focused on growth and collaboration."
  - nil / other → (current default preamble — do not regress)
Replace the hardcoded preamble string with a call to personContextPreamble(for: person.relationshipType).
Run swift build -c release.

ITEM 2 — P3-2: Update AI analysis presets to inject type-appropriate preamble
File: Sources/MeetingScribe/People/PersonDetailView.swift (ConversationAnalysisPreset enum, lines 1–149; and the analysisPresetMenu / runAnalysis functions)
For each of the 6 analysis presets (sentimentTrends, topicsAnalysis, communicationStyle, etc.), prepend personContextPreamble(for:) to the prompt template. For romanticPartner / spouse, add a note to the sentimentTrends preset prompting for Gottman's Four Horsemen patterns (criticism, contempt, defensiveness, stonewalling) and bid-for-connection awareness. For familyMember, prompt for NVC observations vs. evaluations. For closeFriend, prompt for shared joy, love language inference, and proximity maintenance.
Run swift build -c release.

ITEM 3 — D5-5: Reframe sentimentTrends analysis copy
File: Sources/MeetingScribe/People/PersonDetailView.swift (~line 104–111, sentimentTrends preset definition)
Replace the "Identify the general tone (warm / tense / neutral)" language with: "Describe how the conversation has felt recently: where there's been genuine connection, where things have felt more distant or strained, and what topics have come up most. Focus on patterns, not verdicts." Remove the word "tense" as a standalone verdict label. Change the saved note kind from "sentiment" to "connection-patterns" if that field is settable.
Run swift build -c release.

ITEM 4 — P1-7 / C1-3: Static coaching prompt library
File: Sources/MeetingScribe/People/RelationshipPromptLibrary.swift (new file)
Create a Swift enum RelationshipPromptLibrary with a static func rotatingPrompt(for path: RelationshipPath, encounterCount: Int) -> String? that returns a rotating coaching prompt based on week-of-year and encounter count.
Partner prompts (10 minimum): daily appreciation, repair after conflict, Gottman love map question, bid-for-connection awareness, love language check-in, dream-within-conflict exercise, fondness and admiration, turning toward vs. away, four horsemen awareness, weekly state-of-the-union.
Family prompts (8 minimum): gratitude for a specific memory, life stage awareness, NVC needs check, shared ritual idea, repair after rupture, unsaid appreciation, childhood memory question, family strength acknowledgment.
Friend prompts (8 minimum): shared joy cataloguing, drift acknowledgment, love language inference, meaningful question to ask next time, appreciation prompt, reciprocity check, shared goal idea, "what do they need right now" reflection.
No AI call required — these are static strings that load instantly.
Surface one rotating prompt in PersonDetailView's header for romanticPartner, spouse, closeFriend, parent, child, sibling (where supportsDepthContent is true). Suppress for colleague and nil.
Run swift build -c release.

ITEM 5 — C3-1: Encounter-count-gated content progression
File: Sources/MeetingScribe/People/RelationshipPromptLibrary.swift (add to the same file)
Add a ContentTier enum: onboarding (0–3 encounters), reflection (4–12), depth (13+).
Add func contentTier(for person: Person, encounterCount: Int) -> ContentTier.
In the rotatingPrompt function, return onboarding-level prompts for new relationships, reflection prompts for established ones, and depth content (Gottman exercises, NVC structured templates) only at tier .depth. This prevents showing "Four Horsemen awareness" to someone who logged one encounter.
Run swift build -c release. Run swift test.

ITEM 6 — D5-11: Emotional safety note for intimate AI analysis
File: Sources/MeetingScribe/People/PersonDetailView.swift (analysisResultView or where analysis results are displayed)
The first time a user runs any ConversationAnalysisPreset on a person with supportsDepthContent == true, show an inline note below the result: "AI analysis reflects patterns in messages, not the full picture of your relationship. It's a starting point for reflection, not a verdict." Use an @AppStorage("didShowDepthAnalysisSafetyNote") Bool flag. Include a "Don't show again" link that sets the flag permanently.
Run swift build -c release.

PR title: "feat: type-aware AI coaching content and prompt library (Phase 3)"
```

---

## PROMPT 5 — Phase 4: MCP Expansion

```text
Branch: feat/phase-4-mcp-expansion

Read E3-mcp-server.md in full before starting. Phase 1 must be merged (for relationshipType in PersonDTO). Implement E3-10 FIRST — every subsequent item in this phase is easier to write in the decomposed files.

ITEM 1 — E3-10 FIRST: Decompose main.swift into 5 focused files
Current: Sources/MeetingScribeMCP/main.swift is 1526 lines.
Create four new files in Sources/MeetingScribeMCP/ and move code with zero logic changes:
  - MCPStorage.swift (~200 lines): storageDir, resolveInsideVault, loadIndex, allMeetings, scanDiskForMeetings, readMeetingJSON, directoryForMeeting, meeting(byID:), quickNoteDirectories, readQuickNote, directoryForQuickNote, loadTags, tagNames, readText, iso, isoNow, normalizeISO8601
  - MCPPeople.swift (~250 lines): peopleRoot, loadAllPeople, person(byID:), resolvePerson, personMatches, directoryForPerson, personSlug, writePersonEnvelope, signalVaultChanged — and all people tool implementations
  - MCPMessages.swift (~250 lines): MessageStats, MessageSnippet, MessageAnalysisError, chatDBURL, normalizePhone, normalizeEmail, appleDateToSwift, analyzeMessages, extractTextFromAttributedBody, indexOfBytes
  - MCPTools.swift (~600 lines): toolList definitions, all tool_* functions for meetings/action items/write tools, normalizeStatus, normalizePriority, loadActionItemsFromDisk, loadActionItemsRaw, writeActionItemsRaw, actionItemsURL, runTool dispatcher
  - main.swift (~120 lines): JSON-RPC loop only — handle(line:), writeResponse, jsonContentResult, serverInfo, main loop
SPM picks up all .swift files in the target automatically — no Package.swift change needed. Build-verify with swift build -c release after each file is moved. Do not change any logic during the split.

ITEM 2 — E3-1 / P5-1: Add EncounterDTO to VaultKit and get_person_encounters tool
File: Sources/VaultKit/SharedModels.swift — add:
  public struct EncounterDTO: Codable, Sendable {
      public let id: String
      public let personID: String
      public let eventName: String
      public let date: Date
      public let kind: String?
      public let mood: String?
      public let location: String?
      public let notes: String
      public let meetingID: String?
      public let voiceNoteID: String?
      public let durationMinutes: Int?
      public let createdAt: Date
  }
File: Sources/MeetingScribeMCP/MCPPeople.swift — add tool get_person_encounters:
  Args: id (person, required, tolerant lookup), limit: Int = 20
  Implementation: contentsOfDirectory(at: encountersRoot) → filter .json → decode each → filter where personID matches → sort by date descending → return up to limit
  Add to toolList and runTool dispatcher.
Run swift build -c release.

ITEM 3 — E3-2: Add log_encounter write tool
File: Sources/MeetingScribeMCP/MCPPeople.swift
Tool: log_encounter
Args: id (person, required), kind (optional), mood (optional), notes (optional), date (optional, default now), meeting_id (optional)
Implementation: write a new encounter JSON to <storageDir>/encounters/<newUUID>.json. Patch person.json lastInteractionAt if encounter date is more recent (raw-JSON patch pattern — read, mutate, write, do NOT round-trip through DTO). Post signalVaultChanged(). eventName auto-filled from kind or "Quick log".
Returns: {ok, encounterId, personId, eventName, date}
Add to toolList and runTool dispatcher.
Run swift build -c release.

ITEM 4 — E3-3: Port attach_note_to_person to MCP (already in PeopleChatTools.swift)
File: Sources/MeetingScribeMCP/MCPPeople.swift
Copy the implementation from Sources/MeetingScribe/People/PeopleChatTools.swift:340–369. Adapt to raw-JSON patch pattern (append to attachedNotes array in person.json without DTO round-trip). 
Tool: attach_note_to_person
Args: id (person, required), title (required), body (required), kind (optional, default "custom")
Returns: {ok, personId, noteId, title, kind, createdAt}
Add to toolList and runTool dispatcher.
Run swift build -c release.

ITEM 5 — E3-5 / P5-6: Add get_people_needing_attention tool
File: Sources/MeetingScribeMCP/MCPPeople.swift
Tool: get_people_needing_attention
Args: limit: Int = 10
Implementation: for each person, compute daysSinceLastInteraction from lastInteractionAt. Compare to cadence: person.checkInCadenceDays ?? person.relationshipType?.suggestedCheckInDays ?? 30. Sort by overdueByDays descending. Return top N.
Returns: [{personId, displayName, daysSinceContact, personalCadenceDays, overdueByDays, lastInteractionAt}]
Add to toolList and runTool dispatcher.
Run swift build -c release.

ITEM 6 — C4-5: Add get_coaching_context composite tool
File: Sources/MeetingScribeMCP/MCPPeople.swift
Tool: get_coaching_context
Args: id (person, required)
Returns a single structured object: {
  personId, displayName, relationshipPath (raw value),
  recommendedFramework ("gottman" | "nvc" | "love_language" | "professional" | "general"),
  encounterCount, encounterFrequencyDays (median gap across last 10 encounters — nil if < 2),
  lastEncounterDate, overdueByDays,
  birthday (ISO string, nil if not set), daysUntilBirthday (nil if not set),
  recentMemories (last 3 memory texts),
  supportsDepthContent (bool from RelationshipPath),
  checkInCadenceDays
}
Compute recommendedFramework from relationshipPath: romanticPartner/spouse → gottman, parent/child/sibling/familyMember → nvc, closeFriend → love_language, manager/directReport/colleague → professional, nil/other → general.
Add to toolList and runTool dispatcher.
Run swift build -c release.

ITEM 7 — C4-1: Add resources/list endpoint with relationship brief
File: Sources/MeetingScribeMCP/main.swift (JSON-RPC handler for method "resources/list")
Handle the "resources/list" JSON-RPC method. Return a relationship brief resource:
  - Top 3 people needing attention (same logic as get_people_needing_attention, limit 3)
  - Upcoming birthdays in next 30 days (name + days until)
  - Open action items count
Format as MCP Resource objects per the MCP spec. This is the resource that appears automatically when Claude Desktop opens a session.
Run swift build -c release.

ITEM 8 — Update PersonDTO to include encounter count and fix any remaining gaps
File: Sources/VaultKit/SharedModels.swift
Add encounterCount: Int (denormalized) to PersonDTO — populate it in the MCP people reader by counting encounter files for the person. If birthday was confirmed absent in Phase 0 Item 3, fix it here. Ensure relationshipType (from Phase 1) is correctly emitted in the get_person response.
Run swift build -c release. Run swift test.

PR title: "feat: MCP decomposition and new people/coaching tools (Phase 4)"
PR body: list each new tool with its input/output shape. Note C4-6 (publish to mcpservers.org) as a zero-code follow-up action item outside this PR.
```

---

## PROMPT 6 — Phase 5: UX Polish & Small-Lift Wins

```text
Branch: feat/phase-5-ux-polish

Read MASTER-PLAN.md §8 (Phase 5) before starting. Phase 1 must be merged. Items in this phase are independent of each other — pick them up in order but each is a self-contained change.

ITEM 1 — D3-1: Promote stored photos to hero avatar
File: Sources/MeetingScribe/People/PersonDetailView.swift (identityPanel, ~line 394)
When current.photoRelativePaths is non-empty, render the first photo as a 52pt circle avatar using the existing CachedThumbnail component. Fall back to the current SF Symbol initials circle only when no photo is stored. Zero schema change.
Run swift build -c release.

ITEM 2 — D2-1 / D2-6: Relationship-coach splash in OnboardingSheet
File: Sources/MeetingScribe/Onboarding/OnboardingSheet.swift
Add a final onboarding step (case .relationshipIntro or equivalent) after the permissions flow. Copy: "MeetingScribe remembers for you. Start with the relationships that matter most." Show three large icon+label tap targets: [Partner / Spouse heart icon] [Family home icon] [Close Friend star icon] plus "I'll add people later." Each tap target creates a new person with that relationshipType pre-selected and opens the name entry field. "I'll add people later" dismisses onboarding.
Run swift build -c release.

ITEM 3 — D3-2 / D1-9: Type-specific color and icon in PersonRow
File: Sources/MeetingScribe/People/PeopleListView.swift or PersonRow view
Branch on person.relationshipType for the leading icon and tint:
  - romanticPartner / spouse → heart.circle.fill, warm rose/pink tint
  - parent / child / sibling / familyMember → house.fill, warm amber tint
  - closeFriend → star.fill, warm teal tint
  - nil / other → person.circle.fill, default accent tint
Add the three color tokens (warmRose, warmAmber, warmTeal) to NotionDesign.swift if they don't exist.
Run swift build -c release.

ITEM 4 — D5-2: Fix hardcoded font sizes in PersonDetailView (Dynamic Type)
File: Sources/MeetingScribe/People/PersonDetailView.swift
Find all .font(.system(size: X)) calls (E1-architecture.md notes ~32 of them). Replace each with the nearest semantic equivalent: .font(.system(.body)), .font(.system(.caption)), .font(.system(.title2)), etc. Use .font(.system(.body, design: .default)) for body text. Use the existing @ScaledMetric pattern or scaledFont modifier from NotionDesign.swift for any case where a precise size is truly needed. This is a WCAG 1.4.4 fix — Dynamic Type must scale these.
Run swift build -c release.

ITEM 5 — D5-1: VoiceOver labels on unlabeled interactive elements
Files: Sources/MeetingScribe/People/PeopleListView.swift, PersonDetailView.swift
Add .accessibilityLabel and .accessibilityAddTraits(.isButton) to:
  - Avatar circles that are purely decorative → .accessibilityHidden(true)
  - Section navigation chips → .accessibilityLabel("Jump to [section name]")
  - Relationship remove buttons → .accessibilityLabel("Remove relationship with [name]")
  - Encounter delete buttons → .accessibilityLabel("Delete encounter on [date]")
  - Sort menu icon → .accessibilityLabel("Sort people")
  - Filter chips → .accessibilityLabel("[filter name], [selected/not selected]") + .accessibilityAddTraits(.isToggleButton)
Run swift build -c release.

ITEM 6 — U4-2: Post-recording "Found N people" banner
File: Sources/MeetingScribe/Meetings/MeetingManager.swift or MeetingPipelineController.swift (after PersonExtractionController completes)
After person extraction finishes, if extractedCount > 0, post a ToastCenter (or equivalent in-app notification) banner: "Found [N] people in this recording — view the People tab." The banner should be dismissible and link to the People tab or the meeting's attendees list. Do not block the recording flow — this is a passive notification.
Run swift build -c release.

ITEM 7 — U4-5: "Ask AI about this attendee" context menu item
File: Sources/MeetingScribe/Meetings/MeetingDetailView.swift or AttendeeChip component (~line 775 per MASTER-PLAN)
Add a context menu item to each attendee chip: "Ask AI about [name]." Action: open the person's detail view with the chat rail open, and pre-seed the chat with: "Tell me about [name] — their history in my meetings and any notes I have about them." Use the existing openOrCreate logic to find or create the Person.
Run swift build -c release.

ITEM 8 — DEF-1: Default MeetingsView scope to .upcoming and persist
File: Sources/MeetingScribe/Meetings/MeetingsView.swift (line 26, scope initial value)
Check if this is already done (scope may already default to .upcoming via @AppStorage). If scope is still hardcoded to .all, change it to use @AppStorage("meetings.scope") with a default of .upcoming. If it's already done, add a comment: "// DEF-1 — confirmed shipped" and move on.
Run swift build -c release.

ITEM 9 — E5-6: Enable TSan in CI
File: .github/workflows/ci.yml
Add a second swift test step after the existing swift test step:
  - name: Test (Thread Sanitizer)
    run: swift test --sanitize=thread --filter AudioCountersTests
    env:
      CI: "true"
This makes AudioCountersTests.testConcurrentMutationDoesNotCrashOrLoseUpdates actually run under the sanitizer it was written for. Do not remove or modify the existing swift test step.
Run swift build -c release. Commit the YAML change.

ITEM 10 — D2-4: Rewrite PeopleListView empty-state copy
File: Sources/MeetingScribe/People/PeopleListView.swift (empty state view)
Replace "No people yet. Use Add Person or Import above to get started." with: "Your relationship memory starts here. Add the people who matter — partner, family, close friends." Update the CTA button label to "Add your first person" if it currently says something generic.
Run swift build -c release. Run swift test.

PR title: "feat: UX polish, Dynamic Type fixes, VoiceOver labels, TSan CI (Phase 5)"
```

---

## PROMPT 7 — Phase 6: Monetization

```text
Branch: feat/phase-6-monetization

IMPORTANT: Read docs/audit-2026/MASTER-PLAN.md §9 (Phase 6 — Monetization Infrastructure) in full before writing any code. Pay special attention to the positioning spine ("No Bot, No Cloud, No Subscription Required") and the free vs. Pro tier split table. Build before any public announcement.

Pricing model (from the audit, for context — do not hard-code prices in implementation, use constants):
  - One-time purchase: $49
  - Annual: $79/year
  - Lifetime launch promo: $99 (regular $149)
Payment processor: LemonSqueezy (not App Store — sandboxing conflicts with Full Disk Access + Ollama + MCP).

ITEM 1 — C5-1 / P4-1: LicenseStore singleton
File: Sources/MeetingScribe/Licensing/LicenseStore.swift (new file)
Create LicenseStore as a final class or @Observable with:
  - func validate(licenseKey: String) async -> Bool — calls LemonSqueezy REST API POST https://api.lemonsqueezy.com/v1/licenses/validate with the key. Stores validated license data in Keychain using existing KeychainStore.swift.
  - var isPro: Bool — computed from stored Keychain license state. Returns false if no valid license is stored.
  - func restore() — re-reads Keychain state on init without a network call.
  - static let shared: LicenseStore singleton.
Do NOT add any feature gates in this item — just the store. The gates come in subsequent items.
Run swift build -c release.

ITEM 2 — Settings → License tab
File: Sources/MeetingScribe/Settings/SettingsView.swift
Add a "License" tab to the Settings window. The tab shows:
  - Current plan: "Free" or "Pro — activated [date]"
  - License key input field + "Activate" button (calls LicenseStore.shared.validate)
  - Upgrade CTA: "Upgrade to Pro →" linking to the LemonSqueezy checkout URL (use a constant LEMONSQUEEZY_CHECKOUT_URL in LicenseStore.swift, value TBD — use a placeholder URL for now and add a // TODO: set checkout URL comment)
  - "Restore purchase" link (calls LicenseStore.shared.restore)
Run swift build -c release.

ITEM 3 — Free tier limits
Apply the following gates using LicenseStore.shared.isPro. Use the inline non-blocking banner pattern (see Item 5 for the banner component) — do NOT use blocking modals or paywalls:
  - iMessage analysis ConversationAnalysisPreset: free tier limited to 3 people. After the 3rd unique person analyzed, show the upgrade banner instead of running the analysis.
  - MCP write tools (log_encounter, attach_note_to_person, update_person in MCPPeople.swift): check isPro at tool entry. If false, return {ok: false, error: "Pro feature — upgrade at [checkout URL]"}.
  - Check-in notifications (NotificationManager.syncPersonReminders): free tier schedules for partner/spouse only (relationshipType in [.romanticPartner, .spouse]). Pro tier schedules for all types.
  - Relationship-type paths (RelationshipPromptLibrary.rotatingPrompt): free tier returns nil for all paths (no coaching prompts). Pro tier returns the full library.
Run swift build -c release.

ITEM 4 — C5-7: Upgrade prompt after first AI summary
File: Sources/MeetingScribe/Meetings/MeetingPipelineController.swift (after Ollama summary completes)
After the first successful AI summary is generated, if LicenseStore.shared.isPro is false and a "didShowFirstSummaryUpgradePrompt" @AppStorage flag is false:
  - Set the flag to true
  - Show a non-blocking inline banner (NOT a modal): "Your AI summary is ready. Go Pro to unlock relationship coaching, check-in reminders, and unlimited contacts. [Upgrade] [Not now]"
  - "Not now" dismisses for 7 days (store the dismissal timestamp in UserDefaults)
  - "Upgrade" opens the LemonSqueezy checkout URL
Do NOT show this prompt if the user is already Pro.
Run swift build -c release.

ITEM 5 — Non-blocking upgrade banner component
File: Sources/MeetingScribe/Licensing/UpgradeBanner.swift (new file)
Create a reusable SwiftUI view UpgradeBanner(message: String, onUpgrade: () -> Void, onDismiss: () -> Void). Style: a slim bar at the bottom of the content area (not a sheet, not a modal). Dismiss button on the right. Used by Items 3 and 4 above.
Run swift build -c release.

ITEM 6 — P4-3: Monthly Relationship Intelligence Report (Pro only)
File: Sources/MeetingScribe/People/RelationshipIntelligenceGenerator.swift (new file)
On the 1st of each month (check in applicationDidFinishLaunching or a background task), if LicenseStore.shared.isPro and it's the 1st of the month and the report hasn't been generated this month (check a "lastReportMonth" UserDefaults key):
  - Aggregate across all people: encounter frequency trends (who you've been in contact with most/least), upcoming birthdays in next 30 days, open action items count, overdue check-ins.
  - Build a prompt and call Ollama (same OllamaService used for meeting summaries) to generate a brief narrative report. Local — no cloud.
  - Write the output to <storageDir>/relationship-intelligence/<year>-<month>.md
  - Post a macOS notification: "Your monthly Relationship Intelligence Report is ready."
  - Show a card in TodayView linking to the report.
Pro only — gate on LicenseStore.shared.isPro.
Run swift build -c release.

ITEM 7 — C5-3: Update Info.plist and onboarding copy
File: Resources/Info.plist and Sources/MeetingScribe/Onboarding/OnboardingSheet.swift
Update NSHumanReadableCopyright in Info.plist to include the current year.
In OnboardingSheet, on the first or second screen, add the positioning tagline as a subtitle: "No Bot, No Cloud, No Subscription Required." (This is a brand claim for the free tier, not a paywall message — show it to all users.)
Run swift build -c release. Run swift test.

PR title: "feat: monetization infrastructure, LicenseStore, Pro tier gates (Phase 6)"
PR body: list the LemonSqueezy checkout URL as a TODO, list any placeholder values that need to be replaced before go-live.
```

---

## Reusable Snippets

### PR Description Template

```text
## Summary
[One sentence describing what this phase implements.]

## Items implemented
- [ID]: [item title] — [file:line if relevant] — [DONE / SKIPPED / PARTIAL]

## Build verification
- [ ] swift build -c release passed
- [ ] swift test passed
- [ ] Smoke test: [describe what was manually tested]

## Out of scope / noticed (do not implement — save for next phase)
- [item]: [brief description]

## Breaking changes
None / [describe if any]

## Audio pipeline impact
None / [describe changes to MeetingManager, AudioRecorder, LiveTranscriber, MeetingPipelineController]
```

---

### Smoke Test Checklist

1. Launch the app — confirm no crash on startup, People tab loads.
2. Open People tab — verify empty state copy shows relationship-coach framing.
3. Add a new person using AddPersonSheet — verify the relationship type picker appears as the first field.
4. Select "Partner / Spouse" — verify checkInCadenceDays is auto-filled.
5. Save the person — verify they appear in PeopleListView with a heart icon and warm rose tint.
6. Open the person's detail view — verify the coaching prompt banner appears in the header.
7. Tap a kind chip (e.g., "Coffee") to log a quick encounter — verify the encounter is saved without requiring a name field.
8. Open Notifications in System Settings — verify a check-in reminder is scheduled for the person.
9. Open Claude Desktop — run `get_coaching_context` with the person's ID — verify the response includes relationshipPath, encounterCount, supportsDepthContent, and recommendedFramework.
10. Run `log_encounter` from Claude Desktop — verify the encounter appears in the app after a refresh.
11. Run `get_people_needing_attention` — verify the person appears with overdueByDays computed correctly.
12. Start and stop a 30-second recording via the menu bar — verify summary.md and action items are written.
13. Verify the daemon path: if ScribeCore is running, stop a recording via ScribeCore and confirm summary.md is written (E4-1 fix validation).

---

### "You're Stuck" Rescue Prompt

```text
I'm stuck on an item in the MeetingScribe Claude Code Build Playbook. Here is the context:

Phase: [phase number and name]
Item ID: [e.g., E4-1, P2-1]
What I'm trying to do: [one sentence]
What happened: [error message or unexpected behavior]
Files I've already read: [list]

Before suggesting anything, please:
1. Read docs/audit-2026/MASTER-PLAN.md §[relevant section] for the full context on this item.
2. Read docs/audit-2026/findings/[relevant file].md for the exact implementation detail (file:line citations, proposed code).
3. Read the actual file at the cited location and confirm the current state before proposing a fix.

Constraints:
- Do NOT modify the audio pipeline (MeetingManager, AudioRecorder, LiveTranscriber, MeetingPipelineController) unless the item explicitly requires it.
- Use the raw-JSON patch pattern for all MCP write tools (read → JSONSerialization → mutate → write, do not round-trip through DTOs).
- All new Person/Encounter fields must use tolerant decodeIfPresent — never a required Codable key.
- Run swift build -c release after the fix before committing.
```
