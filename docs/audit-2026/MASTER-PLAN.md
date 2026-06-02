# MeetingScribe — Master Plan v4 (25-Agent Audit Synthesis)

> **Target:** `~/MeetingScribeRefactor`
> **Method:** 25 independent agents in 5 groups — Design (D1–D5) · Product (P1–P5) · Engineering (E1–E5) · Personas (U1–U5) · Competitive (C1–C5)
> **Date:** 2026-06-02
> **Status:** Proposed — for Tyler's review before implementation
> **Supersedes:** `MASTER_PLAN_V3.md` (the 20-agent synthesis), `AUDIT_REPORT_2026-05-30.md`

---

## 1. Executive Summary

The biggest opportunity is the **relationship coach angle**: Granola's $125M raise at $1.5B in March 2026 repositioned them entirely as an enterprise AI context layer, vacating the individual power-user segment. MeetingScribe has a structurally superior local-first privacy story, write-capable MCP tools that Granola lacks, and a People module that no meeting tool competitor has — the ingredients for a genuine relationship coach product are already in place. The keystone unlock is a single `RelationshipPath/PersonCategory` enum on `Person`, raised independently by 22 of 25 agents across every group.

The biggest risks are three bugs that block any credible public release. The daemon stop path in `MeetingManager.swift:136–149` never calls `finalize()`, meaning every meeting stopped via ScribeCore produces no summary, no action items, and no FTS index — silent data loss on the primary recording path (E4-1, NEW). `UpdaterController.isConfigured` returns `false` and the Sparkle `SUFeedURL` still points at the old repo, meaning no installed user can ever receive an update (C5, NEW). A one-line omission in `main.swift:1094` silently drops `birthday` from every MCP `get_person` response (P5-12, NEW — though E3's re-read of the source suggests this may already be present; verify before fixing). The C2 distress-signal safety requirement must also ship before any public release.

The key convergence insight: the `RelationshipPath` enum is not a relationship feature — it is an architectural primitive that 22 agents independently discovered is the prerequisite for nearly everything else in this plan. Build it once, build it right in VaultKit, and every subsequent feature becomes a thin branch on a solid foundation.

---

## 2. Convergence Map

Themes independently raised by 3 or more agents, with the count and assigned phase:

| Theme | Agents who raised it | Count | Phase |
|---|---|---|---|
| `Person` has no `relationshipType`/`PersonCategory`/`RelationshipPath` field — partner/family/friend are structurally identical | D1, D2, D3, D4, P1, P2, P3, P4, E1, E2, E3, U1, U2, U3, U4, U5, C1, C2, C3, C5 | 20 | Phase 1 (keystone) |
| Encounter logging requires 5+ steps and a required "event name" — the kind/chip picker is missing | D4, P2, P3, U1, U2, U3, U5, C2, C3 | 9 | Phase 2 |
| Zero per-person push notifications for check-in reminders, birthday alerts, or drift warnings | D4, P1, P2, P3, U1, U2, U3, U5, C1, C3 | 10 | Phase 2 |
| Encounter history completely invisible to MCP — no `EncounterDTO`, no `get_person_encounters`, no `log_encounter` | E3, P5, D4, U1, P2, P3 | 6 | Phase 4 |
| AI preamble hard-codes "adult professional" framing for all analysis including intimate relationship notes | D5, U1, U5, P3, C2 | 5 | Phase 3 |
| Sparkle silently dead — `UpdaterController.isConfigured = false`, `SUFeedURL` points at old repo | C5, P4, AUDIT_REPORT | 3 | Phase 0 |
| Birthday field decoded correctly in `PersonDTO` but never written into MCP `get_person` response | P5, E3 | 2 | Phase 0 |
| Daemon stop path (`DarwinNotifier.recordingStopped`) never calls `finalize()` — no summary/actions/FTS for daemon-recorded meetings | E4 | 1 (P0) | Phase 0 |
| `attach_note_to_person` implemented in `PeopleChatTools.swift` but never ported to MCP `main.swift` | E3, P5 | 2 | Phase 4 |
| Granola raised $125M at $1.5B and pivoted to enterprise — individual segment wide open | C4, C5 | 2 | Strategic |
| Distress signal pre-flight filter required before Ollama processes intimate relationship notes | C2, D5, U5 | 3 | Phase 0 |
| `sentimentTrends` uses clinical "tense/warm/neutral" verdict without context or forward path | D5, U5, C2 | 3 | Phase 5 |
| MCP server invisible in 10,000-server ecosystem — no registry listing | C4 | 1 (quick win) | Phase 4 |
| No monetization infrastructure anywhere in codebase — zero `LicenseStore`, no tier gating | P4, C5 | 2 | Phase 6 |
| `PersonDetailView.swift` is a 1,986-line god-file that blocks contributors | E1, E2, E3 | 3 | Phase 6 |
| `PeopleInsightsView` reconnect cutoff (45d) treats all relationships equally — no per-type threshold | D1, D3, D4, U2, U3, P2 | 6 | Phase 2 |
| Auto-extraction post-recording is completely invisible — no banner, no discovery | U4, P2 | 2 | Phase 5 |

---

## 3. Phase 0 — Critical Fixes (do first, independent of UI)

These items are P0: data loss, broken core promises, or hard requirements before public release. They are independent of each other and can be done in any order.

### Phase 0 item table

| ID | Title | File:line | Effort | Why P0 |
|---|---|---|---|---|
| **E4-1** | Wire `finalize()` into daemon stop path | `MeetingManager.swift:136–149` | S (hours) | Every meeting stopped via ScribeCore produces no summary, no action items, no FTS index — silent data loss on primary recording path |
| **ENG-A** (V3, residual) | Batch-repair gate covers `droppedChunkCount > 0` and coverage gap | `MeetingPipelineController.swift:74–84` | S | Already partially fixed; E4-1 must call `finalize()` with correct coverage metadata for this gate to fire on daemon path |
| **P5-12** | Birthday field fix in `tool_getPerson` | `main.swift:1094–1112` | S (one line) | Verify whether `birthday` is actually absent from the response dict; if so, add `.string(p.birthday.map(iso) ?? "")` |
| **C5/Sparkle** | Fix `UpdaterController.isConfigured`; point `SUFeedURL` at refactor repo; generate EdDSA key pair | `UpdaterController.swift:21–24`, `Resources/Info.plist:45` | S | No installed user can receive any update. Zero distribution channel for paid launch |
| **C2-4** | Distress signal pre-flight filter before Ollama processes intimate relationship encounter notes | `PersonDetailView.swift` AI pipeline | S | Safety requirement for public release. A user in crisis writing about a difficult relationship should not have that text processed by AI without a simple keyword guard |

### E4-1 implementation note

`MeetingManager.swift:136–149` — the `DarwinNotifier.recordingStopped` observer writes the raw live transcript and resets state without ever calling `pipelineController.finalize(meeting:audioResult:liveTranscript:liveDroppedChunks:liveCoverageSeconds:recordedDuration:)`. Wire it in: snapshot `droppedChunkCount` and `liveCoverageSeconds` from the live transcriber before teardown, then call `finalize()` with those values. The finalize call is already wired correctly for the direct (non-daemon) path at `MeetingManager.swift:352`.

### C5/Sparkle implementation note

1. Generate an EdDSA key pair: `generate_keys` from Sparkle CLI.
2. Embed public key in `Info.plist:SUPublicEDKey` (replace the `REPLACE_WITH` placeholder in `UpdaterController.swift:22`).
3. Fix `SUFeedURL` in `Resources/Info.plist:45` to point at `github.com/tyleryannes94/meetingscribe-refactor`.
4. Set `isConfigured = true` once both are wired.

---

## 4. Phase 1 — Relationship Type Foundation

The keystone model change that unlocks everything in Phases 2–6. **Do not start Phase 2 work until Phase 1 lands.** This is a single PR with zero breaking changes.

### Why this is the keystone

22 of 25 agents independently identified the absence of a first-class `RelationshipType` / `PersonCategory` / `RelationshipPath` enum on `Person` as the root gap. Every subsequent feature — check-in cadences, notification copy, AI prompt framing, MCP coaching tools, UI section ordering, encounter kind defaults, monetization feature gating — branches off this one field.

### Phase 1 items (implement in this order)

| ID | Title | File | Effort | Notes |
|---|---|---|---|---|
| **E5-5** | Write `RelationshipTypeTests` BEFORE writing any `RelationshipType` code | `Tests/MeetingScribeTests/RelationshipTypeTests.swift` | S | Round-trip all cases; unknown raw value fallback to `.other`; per-type default cadence sanity check. The `try?`-everywhere decoder will silently discard a misspelled rawValue — test first. |
| **E1-1 / E2-1 / P1-1** | Add `RelationshipPath` enum to `VaultKit` | `Sources/VaultKit/RelationshipPath.swift` (new file) | S | Foundation-only, `public enum RelationshipPath: String, Codable, CaseIterable, Sendable`. Cases: `romanticPartner`, `spouse`, `parent`, `child`, `sibling`, `familyMember`, `closeFriend`, `friend`, `manager`, `directReport`, `colleague`, `mentor`, `client`, `vendor`, `custom`. Add `suggestedCheckInDays: Int?` and `supportsDepthContent: Bool` computed properties on the enum. |
| **E2-1** | Add `relationshipType: RelationshipType?` + `checkInCadenceDays: Int?` + `lastCheckInAt: Date?` to `Person` | `Sources/MeetingScribe/People/Person.swift:77–184` | S | Tolerant decoder `try?` pattern already in place at lines 199–222. Zero migration risk. Bump `personSchemaVersion` to `2`. |
| **E1-1** | Add `path: RelationshipPath?` to `Relationship` struct | `Person.swift:51–64` | S | Additive, decoder-safe. The freeform `label` stays for display nuance. |
| **E2-7** | Mirror new fields to `PersonDTO` in VaultKit | `Sources/VaultKit/SharedModels.swift:186–277` | S | Add `relationshipType: String?`, `checkInCadenceDays: Int?`, `lastCheckInAt: Date?` with `decodeIfPresent` — existing tolerant pattern. |
| **E2-5** | `migrateToV3()` in `SecondBrainDB` | `Sources/MeetingScribe/Storage/SecondBrainDB.swift:34` | S | Additive `ALTER TABLE ADD COLUMN` only: `relationship_type TEXT`, `checkin_cadence_days INTEGER`, `last_checkin_at REAL` on `people`; `kind TEXT`, `quality_rating INTEGER` on `encounters_idx`. Bump `schemaVersion` to `3`. Insert built-in check-in templates. |
| **E2-10** | One-time forward migration: infer `relationshipType` from existing `Relationship.label` strings | `PeopleStore.swift` (post-load pass) | S | Map `"spouse"/"partner"/"wife"/"husband"` → `.romanticPartner`; `"mom"/"dad"/"mother"/"father"/"sister"/"brother"/"kid"/"parent"` → `.familyMember`. Existing users get instant type classification without re-entering data. |
| **D2-2 / P1-2** | Add relationship type picker as first field in `AddPersonSheet` | `Sources/MeetingScribe/People/AddPersonSheet.swift:47–113` | S | 3-card picker: `[Partner/Spouse]  [Family Member]  [Close Friend]  [Colleague]  [Acquaintance]`. Sets `person.relationshipType`. Pre-fills default `checkInCadenceDays` from enum's `suggestedCheckInDays`. |
| **E5-5** | `RelationshipTypeTests` pass (run tests) | CI | S | Must pass before any Phase 2 work starts. |

### Verification: Phase 1 done when

- `RelationshipTypeTests` pass in CI
- `swift build -c release` succeeds
- A new person can be created with a relationship type from `AddPersonSheet`
- Existing `person.json` files with `"spouse"` relationship labels decode with `relationshipType == .romanticPartner`
- `get_person` MCP response includes `relationshipType` field

---

## 5. Phase 2 — Encounter Logging & Check-in Habit

The habit loop that makes MeetingScribe irreplaceable. **Depends on Phase 1.** These items reduce logging friction from 5 steps to 1, and add the only mechanism that drives habit formation from *outside* the app.

### The logging friction problem

All five persona agents (U1–U5) independently found the same critical friction: logging "had coffee with my partner" requires opening the app, finding the person, scrolling to Encounters, tapping Add, typing an "event name" (required), picking a date, and saving. For a daily relationship maintenance habit, this is fatal. The memory-add pattern at `PersonDetailView.swift:1334` is the correct model — extend it to encounters.

### Phase 2 items

| ID | Title | Source agents | Effort | Impact |
|---|---|---|---|---|
| **D4-3 / E2-2** | Add `EncounterKind` enum to `Encounter.swift` | D4, U1, U2, U3, P3, E2 | M | `coffee`, `call`, `videoCall`, `inPerson`, `sharedActivity`, `birthday`, `checkIn`, `difficultConversation`, `custom`. Tolerant decoder, zero migration risk. |
| **D4-1 / U1-5 / C2-1** | Chip-first inline encounter quick-log on `PersonDetailView` | D4, U1, U2, U3, C2, C3 | S | Replace "event name" form with: kind strip (icons for call/coffee/dinner/quality time/difficult conversation) + optional one-line note + optional mood chip. Pressing Enter creates encounter immediately — mirrors the Memories inline field pattern at line 1334. `eventName` auto-filled from kind. |
| **D4-2 / P2-1 / P1-10** | Per-person check-in notification scheduler | D4, P1, P2, P3, U1, U2, U3, C1, C3 | M | Add `syncPersonReminders(people: [Person])` to `NotificationManager.swift`. New category `RELATIONSHIP_CHECKIN` with "Quick log" and "Snooze 3 days" actions. Per-type copy: partner → "Haven't logged time with [Name] in N days — how are they doing?". Fires when `lastInteractionAt + checkInCadenceDays * 86400 < now`. Default cadences by type: partner=7d, family=14d, closeFriend=21d, friend=30d. |
| **D1-6 / D3-4** | Type-stratified reconnect nudges in `PeopleInsightsView` | D1, D3, D4, U2, U3, P2 | S | Replace flat `goneColdDays = 45` with per-type thresholds: partner=7, family=14, closeFriend=21, friend=30, colleague=45. Type-appropriate copy: "You and [Partner] haven't logged time together in N days." |
| **P2-9** | Birthday and anniversary push notifications | P2, P3, U1, C1 | S | `Person.birthday` exists (line 103) and `PeopleInsightsView` already computes upcoming birthdays. Fire push via `UNCalendarNotificationTrigger`: 7 days before and morning of. One new notification category. |
| **C3-7** | Binary "Did you connect?" inline prompt in `SuggestedPeopleView` | C3, P3 | S | Replace the chevron-only row in `ReconnectView` with an inline "Yes / Not yet" button pair. "Yes" fires the chip-first quick-log (Phase 2, above). Converts passive card to an active habit trigger. |
| **D4-6 / P2-4** | 13-week encounter heat map on `PersonDetailView` | D4, P2, U1 | S | `LazyHGrid` of 91 cells (1 cell = 1 week), color intensity = encounter count. "Current streak: N weeks." No third-party library. Data from `PeopleStore.encounters(for:)`. |
| **P2-8** | Check-in goal setting per person | P2, D4 | S | Add `checkInGoalDays: Int?` to `Person` (aspirational, vs. inferred). Stepper in `PersonDetailView`. Shows as target line on heat map. |
| **D5-6** | Optional felt-quality field on `Encounter` | D5, U5, P3, E2 | S | `quality: EncounterQuality?` enum: `energizing`, `neutral`, `draining`, `difficult`. 3-4 tappable emoji chips (no label needed) in the quick-log widget. |

---

## 6. Phase 3 — Relationship Content & AI Coaching

The frameworks that make this a coach, not a CRM. **Depends on Phase 1.** Most items here are prompt rewrites and static Swift enums — no server, immediate depth.

### The "relationship coach" gap

The app's deepest value proposition — "I help you be a better partner, parent, friend" — has zero content backing it. No Gottman framework, no NVC, no love languages, no DBT skills appear anywhere in the codebase. The AI analysis presets exist and work but use generic CRM framing. Phases 2 and 3 are what separate MeetingScribe from Dex (a cloud CRM with no coaching) and from every meeting-recording competitor.

### Phase 3 items

| ID | Title | Source agents | Effort | Impact |
|---|---|---|---|---|
| **U5-3 / D5-5 / P3-2** | Relationship-type-aware Ollama prompt preamble | U5, D5, P3, C2, U1 | S (30 lines) | Replace hard-coded "adult professional" preamble in `PersonDetailView.swift:86–91` with type-aware persona: partner → Gottman coach framing; family → NVC framing; closeFriend → love-language inference. Add `relationshipType` parameter to `ConversationAnalysisPreset.template(personName:customPrompt:)`. |
| **D5-5** | Reframe `sentimentTrends` prompt from clinical to observational | D5, U5, C2 | S | Change from "Identify the general tone (warm / tense / neutral)" to "Describe how the conversation has felt recently: how often you're connecting, whether the topics are warmer or more practical." Remove the "tense" label. Change saved note kind from `"sentiment"` to `"connection-patterns"`. |
| **P1-7 / C1-3** | Static coaching prompt library per relationship type | P1, P3, C1, C3 | M | New `Sources/MeetingScribe/People/RelationshipCoachContent.swift` (~200 lines). Swift enum with 3–5 rotating prompts per `RelationshipPath`. Partner: Gottman's 5:1 ratio, bids for connection. Family: NVC observation vs. evaluation. Close friend: love language inference, proximity maintenance. Prompts rotate by `Calendar.current.component(.weekOfYear) % prompts.count`. No AI call required — loads instantly. |
| **P3-2** | Per-type AI analysis presets | P3, D1, U1 | M | Extend `ConversationAnalysisPreset` with type-gated presets: `.partnerCheckIn` (Gottman Four Horsemen scan), `.parentChildDynamic` (NVC lens), `.friendshipDepth` (love language inference), `.difficultConversationDebrief` (repair attempt identification). Add `visibleFor: Set<RelationshipPath>` property. Filter picker by `current.relationshipType`. |
| **C3-1** | Progressive content arcs (encounter-count unlocks) | C3 | M | 4-week partner arc, 6-week close-friend arc. Encounter count gates deeper prompts: `encounters.count < 4` → onboarding prompts; `4–12` → reflection prompts; `> 12` → depth content. Implemented as a `contentTier(for: Person) -> ContentTier` function on `RelationshipCoachContent`. |
| **U5-4 / P3-11** | "Difficult conversation" encounter shortcut with journal prompts | U5, P3 | S | Pre-filled `EncounterKind.difficultConversation` template with structured fields: Describe (facts only) / Express (feelings) / Assert (what I want) / Anticipate (their perspective). Saves as encounter with `kind = .difficultConversation`. No AI required — immediate value. |
| **P1-6 / D3-7** | Relationship health block at top of `PersonDetailView` for close relationships | P1, D3, D4 | M | For `relationshipType` in `[.romanticPartner, .spouse, .closeFriend, .parent, .child, .sibling]`: show a compact card with (a) days since last check-in vs. cadence target with color-coded dot, (b) current streak, (c) one rotating coaching prompt. Suppressed for `.colleague` and unclassified. |
| **P2-3** | Re-engagement banner after 7+ day app absence | P2 | S | Track `AppSettings.shared.lastOpenedAt`. If `Date() - lastOpenedAt > 7 days`, show a dismissible banner on `TodayView`: "Welcome back — here's what's been waiting." Shows count of overdue check-ins, unprocessed meetings, overdue action items. |
| **D5-11** | Emotional safety one-time note for intimate relationship analysis | D5, U5 | S | First time a user runs any `ConversationAnalysisPreset` on a partner/family/close-friend person: show inline note below result: "AI analysis reflects patterns in messages, not the full picture of your relationship. It's a starting point for reflection, not a verdict." `@AppStorage` flag, "Don't show again" link. |
| **P1-11** | Love language + attachment style fields (partner path) | P1, P3, E2 | S | Two optional `String?` fields on `Person`: `loveLanguage` and `attachmentStyle`. Picker chips in identity panel for `.romanticPartner` persons only. Feeds into coaching prompt selection. |
| **D5-7** | Per-person suppress reconnect nudge flag | D5 | S | `suppressReconnectNudge: Bool` on `Person`. Long-press context menu on `ReconnectView` cards: "Don't remind me about [name]." Handles estranged relationships and deliberate distance without the app creating guilt. |

---

## 7. Phase 4 — MCP Expansion

New tools that enable Claude to coach on relationships. **Depends on Phase 1 for `relationshipType`. Some items (E3-3, P5-12) are independent and can ship earlier.**

### Current MCP gaps

The 17-tool server is read-heavy and meeting-centric. Encounter history, attached notes, and relationship type are all invisible to Claude Desktop. The `attach_note_to_person` tool exists in `PeopleChatTools.swift` but was never ported to `main.swift` — Claude Desktop cannot persist coaching analyses. `get_people_needing_attention` does not exist — Claude cannot open a session proactively.

### Phase 4 items

| ID | Title | Source agents | Effort | Notes |
|---|---|---|---|---|
| **E3-3** | Port `attach_note_to_person` from `PeopleChatTools.swift` to MCP `main.swift` | E3, P5 | S (30 lines) | Copy existing logic from `PeopleChatTools.swift:340–369`. Adapt to raw-JSON patch pattern. **Can ship independently in Phase 0.** Makes coaching sessions cumulative in Claude Desktop. |
| **E3-1 / P5-1** | `EncounterDTO` in VaultKit + `get_person_encounters` read tool | E3, P5, D4, U1 | S | Add `EncounterDTO` to `SharedModels.swift`. Reader: `contentsOfDirectory(at: encountersRoot)` filtered by `personID`. Returns `eventName`, `date`, `location`, `notes`, `meetingID`. |
| **E3-2 / P5-2** | `log_encounter` write tool | E3, P5, U1, P3 | S–M | Write `<storageDir>/encounters/<uuid>.json` via raw-JSON (same pattern as `tool_addMemory`). Patch `person.json:lastInteractionAt` if encounter date is more recent. Post `signalVaultChanged()`. |
| **E3-5 / P5-6** | `get_people_needing_attention` proactive read tool | E3, P5, P2 | S | Port `ReconnectView.cadenceSeconds(for:)` logic server-side. Returns top N people sorted by `overdueByDays` descending. Enables Claude to open sessions with: "Two people need attention: your sister (42 days) and Horst (18 days)." |
| **E3-4 / P5-8** | `update_person` write tool | E3, P5, P1 | S–M | Patch identity fields: `display_name`, `company`, `role`, `bio`, `birthday`, `relationship_type`. Raw-JSON patch, does NOT touch memories/encounters/attachedNotes. Closes the gap where Claude can discover "got engaged" but cannot update the `role` field. |
| **E3-6 / P5-4** | `get_relationship_health` composite read tool | E3, P5, P2, P1 | M | Single call returning: `daysSinceLastInteraction`, `daysSinceLastEncounter`, `message` counts (30/90d), encounter counts, `overdueByDays`, `personalCadenceDays`, `birthdayCountdown`, `recentMemories` (last 3), `healthSignals` (server-computed). Degrades gracefully when encounters not yet built. |
| **C4-1 / P5-11** | MCP `resources/list` endpoint with relationship brief | C4, P5 | M | Proactive context at session start. Returns a "relationship brief" resource: people needing attention, upcoming birthdays, recent encounters. Differentiates from every listed MCP server in the ecosystem. |
| **C4-5** | `get_coaching_context` composite tool | C4, P5 | M | Single tool: relationship type + encounter frequency + birthday countdown + framework recommendation. Unique in the MCP ecosystem. Lets small local models (qwen2.5:7b) coach accurately without multi-step chains. |
| **E3-10** | Decompose `main.swift` (1,526 lines) into 5 focused files | E3 | M | `main.swift` (~120 lines, JSON-RPC loop only) · `MCPStorage.swift` (~200 lines) · `MCPPeople.swift` (~250 lines) · `MCPMessages.swift` (~250 lines) · `MCPTools.swift` (~600 lines). SPM picks up all `.swift` files automatically — no `Package.swift` change needed. Build-verify before pushing. |
| **C4-6** | Publish MCP server to mcpservers.org and mcpmarket.com | C4 | S (zero code) | Free distribution channel. Granola and Dex are already listed in the 10,000-server ecosystem. MeetingScribe is invisible. Submit the existing server — zero code changes required. |
| **E4-5** | Add missing SQLite indexes: `encounters_idx(event_tag_id)` and `encounters_idx(person_id)` | E4 | S | Add two `CREATE INDEX IF NOT EXISTS` statements to `migrateToV3()`. Turns full table scans into O(log N) lookups. These run on `@MainActor` today — measurable freeze with large encounter sets. |

---

## 8. Phase 5 — UX Polish & Small-Lift Wins

High signal-to-effort items. Most are S effort and can be picked up in any order after Phase 1 lands.

| ID | Title | Source agents | Effort | Notes |
|---|---|---|---|---|
| **D3-1** | Promote photos to hero avatar position | D3, U1 | S | When `current.photoRelativePaths` is non-empty, render first photo as 52pt circle avatar in `identityPanel` (`PersonDetailView.swift:394`) via existing `CachedThumbnail`. Fall back to initials only when no photo. Zero schema change. |
| **D2-1** | Relationship-coach splash screen at end of `OnboardingSheet` | D2 | S | Add a `case .intro` step at end of permission flow. Copy: "MeetingScribe remembers for you. Add the relationships that matter most." Two CTAs: "Go to People →" or "Start recording first." |
| **D2-6** | Guided first-person add flow with 3 large tap targets | D2 | M | After onboarding, if `PeopleStore.people.isEmpty`, show 2-step card: (1) three large targets — Partner/Spouse · Family member · Close friend; (2) Name + optional birthday. Creates person with correct `relationshipType` and default cadence. |
| **D1-6** | Type-stratified reconnect thresholds in `PeopleInsightsView` | D1, D3 | S | Already in Phase 2 — duplicate entry removed. |
| **D3-2 / D1-9** | Type-specific color/icon differentiation in `PersonRow` | D3, D1, P1 | S | Partner: `heart.circle.fill` in `NDS.warmRose`. Family: `house.fill` in `NDS.warmAmber`. Close friend: `star.fill` in `NDS.warmTeal`. Others: `person.circle.fill`. Add three warmth color tokens to `NotionDesign.swift`. |
| **U4-2** | Post-recording "Found N people" dismissible banner | U4, P2 | M | After `PersonExtractionController` completes, post a banner in `UnifiedMeetingDetail`: "Found 3 people in this transcript — Sarah, Horst, Ana. Add to People?" One-tap confirm per name. |
| **U4-3** | "Met at [meeting]" auto-memory + relationship intent on attendee chip creation | U4 | M | When a user taps an attendee chip and creates a new Person, pre-populate: (a) memory "Met at: [meeting title]", (b) a "What's this relationship?" prompt opening the type picker from Phase 1. |
| **D5-2** | Fix 32 hardcoded `.font(.system(size:))` calls in `PersonDetailView` | D5 | M | Replace each with `.scaledFont(X, relativeTo: .body)` or nearest NDS token. The `scaledFont` modifier and `@ScaledMetric` pattern already exist in `NotionDesign.swift:139`. WCAG 1.4.4 failure. |
| **D5-1** | VoiceOver labels on ~40 unlabeled interactive elements in People views | D5 | S | Add `.accessibilityLabel` + `.accessibilityAddTraits(.isButton)` to: avatar circle (decorative → `.accessibilityHidden(true)`), section nav chips (add `.accessibilityHint`), relationship remove buttons, favorite remove buttons, sort menu icon, filter chip state. |
| **DEF-1** (V3) | Default `MeetingsView` scope to `.upcoming` + `@AppStorage` persist | — | S | Already planned in V3 but not yet verified shipped. `MeetingsView.swift:26` — replace `scope = .all` with `@AppStorage("meetings.scope")`. |
| **NAV-1/2** (V3) | Fix Today expand/collapse → `NavigationSplitView` model | — | M | Already planned in V3. `TodayView.swift:23/245/296` still uses inline `expandedMeetingID`. |
| **E5-6** | Enable TSan in CI (`--sanitize=thread`) | E5 | S (one YAML line) | `AudioCountersTests.testConcurrentMutationDoesNotCrashOrLoseUpdates` was written for TSan but CI never passes the flag. Add second `swift test` step: `swift test --sanitize=thread --filter AudioCountersTests`. |
| **U4-5** | "Ask AI about this attendee" right-click chip action in meeting detail | U4 | S (~10 lines) | Context menu on `AttendeeChip`: "Ask AI about [name]" → opens that person's detail view with the chat rail open. Connects two working systems with a context menu item. |
| **D2-4** | Rewrite empty-state copy in `PeopleListView` with relationship-coach framing | D2 | S | Replace "No people yet. Use Add Person or Import above to get started" with: "Your relationship memory starts here. Add the people who matter — partner, family, close friends." |
| **E5-1** | `NameSimilarityTests` — 10 cases for Jaro-Winkler auto-link threshold | E5 | S | Pin boundary behavior: "Sara" vs "Sarah" → ≥0.85 (auto-link); "Jane" vs "John Smith" → < 0.60 (no suggest). Gates all People auto-linking; zero tests today. |

---

## 9. Phase 6 — Monetization Infrastructure

Build this before any public announcement. Zero monetization infrastructure exists anywhere in the codebase today — clean slate.

### Positioning spine (from C5-3)

> **"No Bot, No Cloud, No Subscription Required."**

Granola's pivot to enterprise leaves the individual power user segment open. This is the positioning that captures them.

### Free vs. Pro tier split

| Feature | Free | Pro |
|---|---|---|
| Recording + transcription | Up to 10 meetings/month | Unlimited |
| AI summaries + action items | First 10 meetings (trial) | Unlimited |
| People CRM — unlimited contacts | Yes | Yes |
| Memory capture + encounters | Yes | Yes |
| Basic relationship insights (birthdays, reconnect) | Yes | Yes |
| Auto-people extraction from transcripts | First 10 meetings | Unlimited |
| iMessage analysis + ConversationAnalysisPreset | First 3 people | Unlimited |
| Speaker diarization | No | Yes |
| Linear / Notion / Google Drive integrations | No | Yes |
| MCP write tools | No | Yes |
| Relationship type paths (partner/family/friend coaching) | No | Yes |
| Monthly Relationship Intelligence Report | No | Yes |
| Check-in reminders per person | Basic (partner only) | All types, all cadences |

### Pricing recommendation (from C5 + P4, reconciled)

| Model | Price | Rationale |
|---|---|---|
| One-time purchase | $49 | Below Granola's annual cost ($168/yr); above impulse-buy threshold |
| Annual subscription | $79/year (~$6.60/month) | Below Paired ($83.99/yr/couple); sustainable for relationship coach positioning |
| Lifetime (launch promo) | $99 (regular $149) | Rewards early adopters; generates upfront capital |

Use **LemonSqueezy** (not Paddle — has built-in license key validation; saves 2–3 days of integration work). Sell direct, not App Store (Full Disk Access + Ollama + MCP server requirements conflict with App Store sandboxing; avoid 30% cut at launch volumes).

### Phase 6 items

| ID | Title | Source agents | Effort | Notes |
|---|---|---|---|---|
| **P4-1 / C5-1** | `LicenseStore` singleton + LemonSqueezy checkout | P4, C5 | M | Keychain-backed `LicenseStore.shared.isPro`. Check before presenting AI summaries, MCP write tools, `ConversationAnalysisPreset`. Inline upgrade banner (not a blocking modal): "AI features are Pro — [Upgrade] [Not now]". Banner dismissed for 7 days. |
| **P4-3** | Monthly on-device Relationship Intelligence Report | P4, C5 | M | Pro-only monthly deliverable. AI-generated report covering all tracked relationships: who you've drifted from, who's been most present, recurring themes, upcoming birthdays. Local Ollama — no cloud cost. `RelationshipIntelligenceGenerator` aggregates across all persons. Pro retention hook — user stays subscribed even in quiet months. |
| **C5-7** | Upgrade prompt trigger: after first AI summary, not at a limit wall | C5, P4 | S | Do NOT show the upgrade prompt when the user hits a feature limit cold. Show it after the first successful AI summary: "Enjoyed that? AI features are Pro." This triggers at peak satisfaction — estimated 3% → 6–8% conversion lift. |
| **E1-2** | `PersonDetailViewModel` — extract business logic out of the view struct | E1 | M | Extract `personContextForAI()`, `ownerMatchesPerson()`, analysis state machines into `@Observable` class. Makes iMessage analysis pipeline unit-testable. Prerequisite for contributors working on Phase 3 content features without touching the 1,986-line view. |
| **E1-3** | `EncounterStore` — split encounter CRUD from `PeopleStore` | E1 | S | Extract lines 581–650 into standalone `@MainActor final class EncounterStore`. Removes ~70 lines from `PeopleStore`, independently testable. |
| **E1-9 / ARCH-3** | `PersonDetailView.swift` god-file decomposition | E1, E3 | M | 9 child views + 1 view-model per E1 decomposition map. Target: none over ~480 lines. Enables contributors to work on coaching sections without touching the full 1,986-line file. |

---

## 10. How To Use This Plan

1. **Phases are dependency-ordered.** Phase 0 is non-negotiable and independent of everything. Phase 1 (the `RelationshipPath` enum) is the keystone — do not start Phases 2–4 until Phase 1 is merged and CI is green.

2. **Write tests before model code.** E5-5 (`RelationshipTypeTests`) must be written before the `RelationshipType` enum ships. The tolerant `try?`-everywhere decoder will silently discard a misspelled rawValue; only a round-trip test catches it.

3. **Each item ID resolves to a full write-up.** Every ID (e.g., `E3-1`, `P2-9`, `C2-4`) maps to a specific section in `docs/audit-2026/findings/<file>.md` with exact `file:line` citations, proposed Swift code, and effort breakdown.

4. **Follow CLAUDE.md workflow.** Branch per phase. Run `swift build -c release` before committing. Ask before pushing.

5. **Phase 0 can be done in any order.** The four Phase 0 items are independent of each other and of everything else. Start there today.

6. **MCP registry (C4-6) is zero-code.** Submit the existing MCP server to mcpservers.org and mcpmarket.com before any public announcement. Free distribution in a 10,000-server ecosystem where Granola and Dex are already listed.

7. **Use this document as the single reference.** If there is a conflict between this plan and V3, this plan governs. V3 items that are fully shipped (PPL-1 inline editing, write-capable MCP, ENG-B through G) are noted as complete in the audit; they do not appear here.

---

## Appendix — Full Item Catalog

All net-new items from the 25-agent audit, grouped by phase. Effort: S = hours to 1 day; M = 2–5 days; L = 1–2 weeks.

| ID | Title | Source agents | Phase | Effort | Impact |
|---|---|---|---|---|---|
| **E4-1** | Wire `finalize()` into daemon stop path | E4 | 0 | S | P0 — data loss on all daemon-recorded meetings |
| **P5-12** | Birthday field fix in `tool_getPerson` | P5 | 0 | S | P0 — birthday coaching completely blocked (verify first) |
| **C5/Sparkle** | Fix Sparkle `isConfigured` + `SUFeedURL` + EdDSA key | C5, P4 | 0 | S | P0 — no user can receive any update |
| **C2-4** | Distress signal pre-flight filter | C2, D5, U5 | 0 | S | Safety requirement for public release |
| **E5-5** | `RelationshipTypeTests` BEFORE enum code | E5 | 1 | S | Guards against silent decoder discards |
| **E1-1 / P1-1 / E2-1** | `RelationshipPath` enum in VaultKit | E1, E2, P1, D1, D2, D4, U1–U5, C1–C3 | 1 | S | Keystone unlock — 22 agents converged |
| **E2-5** | `migrateToV3()` in SecondBrainDB | E2, E4 | 1 | S | SQL-layer filtering and indexes |
| **E2-10** | Forward migration: infer type from `Relationship.label` | E2 | 1 | S | Zero user friction — existing data auto-classified |
| **E2-7** | Mirror new fields to `PersonDTO` | E2, E3 | 1 | S | MCP sees `relationshipType` |
| **D2-2 / P1-2** | Relationship type picker in `AddPersonSheet` | D2, P1, U1–U3 | 1 | S | All new people get typed at creation |
| **D4-3 / E2-2** | `EncounterKind` enum on `Encounter` | D4, E2, U1–U3 | 2 | M | Structural foundation for habit loop |
| **D4-1 / C2-1** | Chip-first inline encounter quick-log | D4, C2, U1–U3 | 2 | S | Drops friction 5 steps → 1 |
| **D4-2 / P2-1** | Per-person check-in notification scheduler | D4, P1, P2, U1–U3 | 2 | M | Only mechanism that works outside the app |
| **D1-6** | Type-stratified reconnect thresholds | D1, D3, P2, U2, U3 | 2 | S | Partner 7d vs. colleague 45d — emotionally appropriate |
| **P2-9** | Birthday push notifications | P2, P3 | 2 | S | `Person.birthday` exists; never pushed |
| **C3-7** | Binary "Did you connect?" inline prompt | C3, P3 | 2 | S | Converts passive card to active habit |
| **D4-6 / P2-4** | 13-week encounter heat map | D4, P2 | 2 | S | Habit visualization — streak visibility |
| **P2-8** | Check-in goal setting per person | P2, D4 | 2 | S | Aspirational vs. inferred cadence |
| **D5-6** | Optional felt-quality field on `Encounter` | D5, U5, P3 | 2 | S | Enables "this was hard" without writing a journal |
| **U5-3 / D5-5** | Type-aware Ollama prompt preamble | U5, D5, P3, C2 | 3 | S (30 lines) | Removes "adult professional" framing for partner/family |
| **D5-5** | Reframe `sentimentTrends` prompt to observational | D5, U5 | 3 | S | Removes clinical "tense" verdict |
| **P1-7 / C1-3** | Static coaching prompt library per type | P1, P3, C1, C3 | 3 | M | Gottman/NVC/love-language prompts, no AI required |
| **P3-2** | Per-type AI analysis presets | P3, D1, U1 | 3 | M | Partner → Gottman; family → NVC; friend → love language |
| **C3-1** | Progressive content arcs (encounter-count unlocks) | C3 | 3 | M | Deeper prompts as relationship deepens |
| **U5-4 / P3-11** | "Difficult conversation" encounter shortcut | U5, P3 | 3 | S | DBT-structured template, no AI required |
| **P1-6 / D3-7** | Relationship health block at top of detail view | P1, D3, D4 | 3 | M | Coach identity — streak + prompt + health signal |
| **P2-3** | Re-engagement banner after 7+ day absence | P2 | 3 | S | Brings lapsed users back with context |
| **D5-11** | Emotional safety note for intimate AI analysis | D5, U5 | 3 | S | "AI is a starting point, not a verdict" |
| **P1-11** | Love language + attachment style fields | P1, P3, E2 | 3 | S | Partner path depth fields |
| **D5-7** | Per-person suppress reconnect nudge flag | D5 | 3 | S | Handles estranged relationships gracefully |
| **E3-3** | Port `attach_note_to_person` to MCP | E3, P5 | 4 | S (30 lines) | Cumulative coaching sessions in Claude Desktop |
| **E3-1 / P5-1** | `EncounterDTO` + `get_person_encounters` tool | E3, P5 | 4 | S | Temporal coaching — "when did we last meet in person?" |
| **E3-2 / P5-2** | `log_encounter` MCP write tool | E3, P5 | 4 | S–M | "Log that I just had coffee with Jordan" from Claude |
| **E3-5 / P5-6** | `get_people_needing_attention` tool | E3, P5, P2 | 4 | S | Proactive coaching — opens session with who needs attention |
| **E3-4 / P5-8** | `update_person` write tool | E3, P5 | 4 | S–M | Claude can correct name/role/type after discovering changes |
| **E3-6 / P5-4** | `get_relationship_health` composite tool | E3, P5 | 4 | M | Single call with all coaching signals — works with small models |
| **C4-1** | MCP `resources/list` endpoint with relationship brief | C4, P5 | 4 | M | Proactive context at session start |
| **C4-5** | `get_coaching_context` composite tool | C4, P5 | 4 | M | Unique in the 10,000-server MCP ecosystem |
| **E3-10** | Decompose `main.swift` into 5 focused files | E3 | 4 | M | Enables adding new tools without editing a 1,526-line monolith |
| **C4-6** | Publish MCP server to mcpservers.org + mcpmarket.com | C4 | 4 | S (zero code) | Free discovery in a 10,000-server ecosystem |
| **E4-5** | Missing SQLite indexes on `encounters_idx` | E4 | 4 | S | Turns full table scans into O(log N) |
| **D3-1** | Promote photos to hero avatar position | D3 | 5 | S | Hours of work; highest warmth-to-effort ratio |
| **D2-1** | Relationship-coach splash in onboarding | D2 | 5 | S | Every new user discovers the relationship layer |
| **D2-6** | Guided first-person add — 3 large tap targets | D2 | 5 | M | Type-first creation with correct relational framing |
| **D3-2 / D1-9** | Type-specific color/icon in `PersonRow` | D3, D1 | 5 | S | Instant scan — partner and colleague look different |
| **U4-2** | "Found N people" extraction banner | U4 | 5 | M | Makes invisible pipeline visible |
| **U4-3** | "Met at [meeting]" auto-memory + relationship intent | U4 | 5 | M | Highest-leverage moment: creation time |
| **D5-2** | Fix 32 hardcoded font sizes in `PersonDetailView` | D5 | 5 | M | WCAG 1.4.4 — Dynamic Type for low-vision users |
| **D5-1** | VoiceOver labels on ~40 unlabeled elements | D5 | 5 | S | Baseline AT compliance |
| **DEF-1** | Default Meetings scope to `.upcoming` + `@AppStorage` | V3 carry | 5 | S | Already planned; verify shipped |
| **NAV-1/2** | Fix Today expand/collapse → `NavigationSplitView` | V3 carry | 5 | M | Already planned; verify shipped |
| **E5-6** | Enable TSan in CI | E5 | 5 | S (1 YAML line) | `AudioCountersTests` was written for TSan; CI never runs it |
| **U4-5** | "Ask AI about this attendee" chip context menu | U4 | 5 | S (~10 lines) | Connects two working systems |
| **D2-4** | Rewrite `PeopleListView` empty-state copy | D2 | 5 | S | Relationship-coach framing from first impression |
| **E5-1** | `NameSimilarityTests` — 10 Jaro-Winkler cases | E5 | 5 | S | Guards auto-link threshold that gates all People extraction |
| **P4-1 / C5-1** | `LicenseStore` + LemonSqueezy checkout | P4, C5 | 6 | M | Foundation of all revenue |
| **P4-3** | Monthly Relationship Intelligence Report (Pro) | P4, C5 | 6 | M | Pro retention hook — value even in quiet months |
| **C5-7** | Upgrade prompt at first AI summary (not limit wall) | C5 | 6 | S | 3% → 6–8% conversion lift |
| **E1-2** | `PersonDetailViewModel` — extract business logic | E1 | 6 | M | Unit-testable AI pipeline; unblocks contributors |
| **E1-3** | `EncounterStore` split from `PeopleStore` | E1 | 6 | S | Independently testable encounter CRUD |
| **ARCH-3 / E1** | `PersonDetailView` god-file decomposition | E1, E3 | 6 | M | 9 child views; enables parallel contributor work |
| **E5-3** | `MCPVaultTests` — security-critical path containment | E5 | 5–6 | S | Tests `resolveInsideVault` path traversal guard |
| **E5-4** | `EncounterRoundTripTests` | E5 | 5–6 | S | Serialize/deserialize all optional fields |
| **E4-9** | Surface `AVAssetWriter` finalization failures | E4 | 5–6 | M | Silent corrupted audio on disk-full / interrupted write |
| **E2-3** | `RelationshipProfile` sub-struct (love language, attachment, goals) | E2 | 6 | M | Avoids ballooning `Person` flat field count |
| **D1-5** | Relationship Health section per type in `PersonDetailView` | D1 | 5–6 | M | Gottman/NVC prompts surfaced as a dedicated section |
| **D2-9** | First-run "Add the people who matter" nudge on Today | D2 | 5 | S | Shows when `PeopleStore.people.isEmpty` |
| **P2-2** | Weekly relationship health digest notification (Sunday 7pm) | P2 | 5–6 | S | Weekly habit anchor for relationship maintenance |
| **P2-6** | "On this day" flashback push notification | P2 | 5–6 | S | Emotional anchoring from prior-year encounters |
| **D4-9** | Global ⌥⌘K quick check-in shortcut | D4 | 5–6 | M | Log "had coffee with Sarah" from any tab |
| **D4-11** | Encounter timeline view (chronological, cross-person) | D4 | 6 | M | "Relationship journal" — aggregate view of social life |
| **P1-8** | PeopleList grouping by relationship type | P1, D1 | 5–6 | S | Inner circle (partner+family+closeFriend) floated to top |
| **E1-6** | Reciprocal label consistency (`parent` ↔ `child`) | E1 | 5–6 | S | Semantic inversion on `addRelationship` |
| **D3-3** | Intimacy-zone concentric graph layout mode | D3 | 6 | M | Emotional map — partner at center, family ring 1, friends ring 2 |
| **E2-9** | `content_library` + `person_content_progress` SQLite tables | E2 | 6 | M | Persistent exercise tracking (Gottman exercises, NVC prompts) |
| **E5-8** | `SecondBrainDBTests` — FTS5 and embedding round-trip | E5 | 6 | M | FTS5 is the search engine; 0% tested today |
| **U1-11** | "Haven't logged [partner] in N days" Today banner | U1 | 5 | S | In-app complement to push notifications |
| **P2-5** | Relationship health score on `PeopleInsightsView` | P2 | 6 | S | Composite 0–100 score for diagnostic use |
| **P4-4** | Non-modal contextual upgrade banner architecture | P4 | 6 | S | Inline dismiss-and-return pattern, not a blocking paywall |

---

*Generated 2026-06-02 from 25-agent audit. Each item ID resolves to a full write-up in `docs/audit-2026/findings/`. Total phases: 6 + Phase 0. Total net-new items: 79. Items already shipped from V3 (PPL-1 inline editing, write-capable MCP, ENG-B through G) are not repeated here.*
