# Shared Briefing — MeetingScribe 25-Agent Audit v2

You are one of 25 expert agents auditing **MeetingScribe**, a local-first macOS meeting intelligence + relationship coaching app (Swift / macOS 14+, 236 .swift files, ~18,000 LOC). Read this whole file before you do anything else.

---

## The target (what it is)

MeetingScribe is a macOS menubar app that:
1. **Records meetings** (mic + system audio), transcribes via Whisper, generates summaries and action items via Claude/Ollama
2. **Manages a People graph** ("Second Brain") — per-person profiles, memories, iMessage history, encounter logging, meeting backlinks
3. **Coaches relationships** — check-in cadence reminders, relationship-type-aware AI prompts, coaching frameworks
4. **Exposes an MCP server** so Claude Desktop can query/write all the above data locally

**Tech stack:** Swift 5.10, SwiftUI, SQLite (via SQLite3 directly), UserNotifications, StoreKit 2 (stubbed), Sparkle (for updates), Whisper (local model), Ollama/Claude (for summaries/AI)

**Key modules:** `MeetingScribe/` (main app), `ScribeCore/` (daemon), `VaultKit/` (shared DTOs), `MeetingScribeMCP/` (MCP server), `NotionMCP/` (Notion integration)

---

## Where to read the live source

`/sessions/adoring-lucid-mendel/mnt/MeetingScribeRefactor/Sources/` — key areas:
- `MeetingScribe/Monetization/` — FeatureGate.swift, ProPaywallView.swift, StoreKitManager.swift
- `MeetingScribe/People/` — Person.swift, QuickEncounterSheet.swift, RelationshipNotificationManager.swift, RelationshipPromptLibrary.swift, PeopleListView.swift, PersonDetailView.swift
- `MeetingScribe/UI/` — TodayView.swift, StayConnectedSection.swift
- `VaultKit/` — SharedModels.swift (PersonDTO with Phase D fields), Person.swift, Encounter.swift
- `MeetingScribeMCP/main.swift` — 6 new Phase 4 people tools (lines 883–955 for schemas, 1524–1760 for implementations)
- `/sessions/adoring-lucid-mendel/mnt/MeetingScribeRefactor/mcp-registry.json`

---

## REQUIRED first step — read existing plans so you ADD net-new

Read these before auditing (skim; you don't need every line):
- `/sessions/adoring-lucid-mendel/mnt/MeetingScribeRefactor/docs/audit-2026/MASTER-PLAN.md` — the PRIOR master plan (Phases 0–6 were built from this)
- `/sessions/adoring-lucid-mendel/mnt/MeetingScribeRefactor/docs/phase-6-summary.md` — summary of Phase 6 (monetization)
- `/sessions/adoring-lucid-mendel/mnt/MeetingScribeRefactor/docs/phase-5-summary.md` — Phase 5 summary

---

## What is ALREADY BUILT (do NOT re-list — go beyond it)

Phases 0–6 were implemented from the prior master plan. Here is what now EXISTS in the codebase:

**Phase 0 (fixes):** daemon `finalize()` wired, Sparkle config fixed, MCP birthday field added, transcript truncation fixed

**Phase 1 (RelationshipType):**
- `RelationshipType` enum in `Person.swift` (7 cases: romanticPartner, familyMember, closeFriend, friend, colleague, acquaintance, unset) with `displayName`, `defaultCheckInDays`, `supportsDepthContent`, `emoji`, `colorName`
- `Person.relationshipType: RelationshipType` + `checkInCadenceDays: Int?` + `effectiveCheckInDays: Int` computed property
- Relationship type picker in `AddPersonSheet` + filter chips in `PeopleListView`
- `PersonDTO` in `SharedModels.swift` includes `relationshipType: String?` + `checkInCadenceDays: Int?`

**Phase 2 (QuickEncounterSheet + Notifications):**
- `QuickEncounterSheet.swift` — chip-first logging (Kind + Mood chips, optional note, date override), calls `people.addEncounter()` then reschedules notifications
- `Encounter.Kind` extension on `Encounter` in `QuickEncounterSheet.swift` (call/coffee/videoCall/message/metUp/milestone)
- `Encounter.Mood` extension (great/good/neutral/tense/hard)
- `RelationshipNotificationManager.swift` — schedules per-person check-in and birthday reminders via `UNCalendarNotificationTrigger`
- `StayConnectedSection.swift` in `TodayView` — shows up to 3 overdue people with one-tap quick-log button

**Phase 3 (Coaching content):**
- `RelationshipPromptLibrary.swift` — 28 static prompts (11 partner/Gottman, 8 family/NVC, 9 closeFriend/love-language), `weeklyPrompt(for:)` rotates by ISO week
- Dynamic AI preamble per relationship type (exists in `PersonDetailView.swift`)
- Health score referenced in `FeatureGate.ManagedFeature.healthScore` — but the actual arc ring UI is NOT in PersonDetailView

**Phase 4 (6 new MCP tools):**
All 6 implemented in `MeetingScribeMCP/main.swift`:
- `list_encounters` — returns encounter array for a person
- `log_encounter` — writes a new encounter JSON file
- `get_check_in_status` — overdue/cadence status for one person
- `list_overdue_check_ins` — sorted list of overdue people
- `get_coaching_context` — cadence + framework recommendation + birthday countdown
- `attach_note_to_person` — patches person.json with a new attachedNote

**Phase 5 (UX polish + mcp-registry.json):**
- `mcp-registry.json` at repo root with 23 tools listed
- UX improvements to PeopleListView (filter bar, debounced search)

**Phase 6 (Monetization stub):**
- `FeatureGate.swift` — `ManagedFeature` enum (8 cases), `isEnabled()` function, `paywallFeature` state
- `ProPaywallView.swift` — full paywall UI with feature bullets, $4.99/month pricing, "Start 7-Day Free Trial" CTA
- `StoreKitManager.swift` — stub with TODO comments, no real StoreKit calls, purchase() shows "Coming Soon" alert
- In DEBUG: `overrideAllEnabled = true` — ALL gates bypass in development

---

## What is ALREADY PLANNED but NOT YET BUILT (do NOT just re-list)

The prior master plan (Phases 7–10, which were the logical next steps) included:
- Phase 7: Quality/completeness fixes for new code (code review, testing)
- Phase 8: Relationship coach depth (deeper coaching content, progressive arcs)
- Phase 9: Monetization wiring (real StoreKit 2, receipt validation)
- Phase 10: Polish + habit loop improvements

**Your job: endorse the few existing items that matter most through your lens, then propose NET-NEW improvements and features the existing plans miss. Reward novelty + specificity.**

---

## Critical gaps already spotted (audit these, don't re-propose)

These are known issues — acknowledge them in "existing plan items I rank highest" but focus your net-new elsewhere:
1. `StoreKitManager.purchase()` shows a "Coming Soon" alert — 0% functional
2. `FeatureGate.overrideAllEnabled = true` in DEBUG — nothing is ever gated during development
3. `healthScore` ManagedFeature exists but the arc ring UI is NOT implemented in PersonDetailView
4. `ProPaywallView` is defined but it's unclear where/how it's presented (no sheet binding found in main views)
5. `RelationshipNotificationManager.syncPersonReminders()` is called from `QuickEncounterSheet` but NOT on app launch
6. Two parallel `Encounter.Kind` enums exist: one in `VaultKit/Encounter.swift` (meeting/call/email/message/note) and one in `QuickEncounterSheet.swift` (call/coffee/videoCall/message/metUp/milestone) — they conflict
7. `PersonDTO`'s memberwise init at bottom of SharedModels.swift does NOT include `relationshipType` or `checkInCadenceDays`
8. `get_coaching_context` MCP tool returns "Active listening and consistent follow-through" for all relationship types except partner/family/closeFriend — friend/colleague/acquaintance get the fallback

---

## Guiding principles for this audit

- **Evidence over opinion** — cite file:line for every claim
- **Go beyond the known gaps above** — they're already spotted; find what's NEXT
- **Distinguish clearly** between endorsing-existing vs net-new
- **Be specific** — "add a field" is weak; "add `Person.communicationStyle: CommunicationStyle?` enum (visual/auditory/kinesthetic) used in AI preamble to adapt coaching language" is strong
- **Competitive agents:** do live web research; cite URLs
- **Effort discipline:** use S/M/L — S = hours, M = 1-2 days, L = week+

---

## Output — write a markdown file, then return a short summary

1. Write your full analysis to: `/sessions/adoring-lucid-mendel/mnt/MeetingScribeRefactor/docs/audit-2026-v2/findings/<YOUR_FILE>.md`
2. Structure per the findings template:
   - Heading + one-line lens statement
   - Full-app audit through your lens (cite file:line)
   - Existing-plan items you rank highest (3–6)
   - NET-NEW recommendations (6–12 items, each with ID/What/Why/User value/Effort/Impact/Deps)
   - Top 3 picks + single highest-priority recommendation
3. Return a ~120–150 word summary: your role, top 3 net-new picks, single highest-priority recommendation.

Use the ID prefix assigned to you in your task. Unique IDs thread through to the master plan.
