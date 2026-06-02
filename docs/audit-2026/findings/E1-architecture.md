# E1 — Architecture Audit: PersonDetailView Decomposition, PeopleStore Extraction, RelationshipPath Model

**Lens:** Swift/macOS architecture — god-file decomposition, module boundaries, RelationshipType as a first-class model concept.
**Auditor prefix:** E1-
**Date:** 2026-06-02

---

## 1. PersonDetailView.swift — Section Map (1986 lines)

The file contains one `struct PersonDetailView` (lines 155–1833), two supporting sheets (`AddEncounterSheet` lines 1871–1936, `AddRelationshipSheet` lines 1938–1985), and one row view (`EncounterRow` lines 1836–1867). The supporting sheets are currently `private struct` embedded in the same file. The main view has these logical MARK sections:

| Lines | MARK | What it is | Split candidate? |
|---|---|---|---|
| 1–149 | (top-level enums) | `AnalysisScope`, `ConversationAnalysisPreset` (149 lines) | Extract to `ConversationAnalysisPreset.swift` |
| 155–307 | `body` | `HSplitView` layout, sheets, confirmationDialog | Keep (view skeleton) |
| 308–351 | Section jump-rail (U3) | `sectionNav(_:)` + `sectionNavItems` | Child view: `PersonSectionNav` |
| 352–509 | Inline identity editing | `beginIdentityEdit`, `saveIdentityEdit`, `identityPanel` | Child view: `PersonIdentityPanel` |
| 511–619 | Tags (inline add) + Favorites (inline add) | `tagsEditSection`, `favoritesEditSection` | Child views: `PersonTagsSection`, `PersonFavoritesSection` |
| 620–815 | AI suggestions | `aiSuggestionsSection`, `generateAISuggestions`, context builder | Child view: `PersonAISuggestionsSection` + extract engine calls to `PersonDetailViewModel` |
| 817–855 | Embedded chat column | `personChatColumn` | Child view: `PersonChatColumn` |
| 856–981 | Meeting history | `meetingHistorySection`, `timelineRow`, `loadCalendarMeetings` | Child view: `PersonMeetingHistory` |
| 882–919 | Decisions | `decisionsSection` | Child view: `PersonDecisionsSection` |
| 983–1094 | Contact rows + Photos + Notes | `header`, `contactRows`, `photosSection`, `notes` | Child views: `PersonContactRows`, `PersonPhotosSection` |
| 1096–1112 | Encounters | `encountersSection` | Child view: (already has `EncounterRow`) — extract `PersonEncountersSection` |
| 1113–1273 | Tasks (cross-tab) | `tasksSection`, `taskRow`, owner-matching logic | Child view: `PersonTasksSection`; owner-matching logic → `PersonDetailViewModel` |
| 1242–1273 | Relationships (display) | `relationshipsSection` | Child view: `PersonRelationshipsSection` |
| 1274–1321 | Meeting backlinks ("Mentioned in") | `mentionedInSection` | Merge into `PersonMeetingHistory` |
| 1328–1354 | Memories | `memoriesSection` | Child view: `PersonMemoriesSection` |
| 1356–1829 | iMessage analysis | `messagesSection`, `analysisPresetMenu`, `analysisResultView`, `runAnalysis`, `runDeepMessageAnalysis`, etc. (~470 lines) | Child view: `PersonMessagesSection` + extract `PersonMessagesViewModel` |
| 1575–1833 | Actions + formatters | `addMemory`, `attachPhotos`, `analyzeMessages`, `updateChatContext`, etc. | Business logic → `PersonDetailViewModel` |

**Proposed split (9 child views + 1 view-model):**

```
PersonDetailView.swift          ~200 lines (body + sheet wiring only)
PersonIdentityPanel.swift       ~160 lines
PersonContactSection.swift      ~80 lines
PersonTagsSection.swift         ~80 lines
PersonFavoritesSection.swift    ~60 lines
PersonAISuggestionsSection.swift ~200 lines
PersonRelationshipsSection.swift ~80 lines
PersonEncountersSection.swift   ~60 lines
PersonMeetingHistory.swift      ~120 lines (recorded + calendar + backlinks)
PersonTasksSection.swift        ~140 lines
PersonMemoriesSection.swift     ~60 lines
PersonMessagesSection.swift     ~480 lines (largest; iMessage analysis)
PersonChatColumn.swift          ~50 lines
PersonDetailViewModel.swift     ~120 lines (owner-match, context builder, AI glue)
ConversationAnalysisPreset.swift ~150 lines (AnalysisScope + enum moved out)
```

**Total after split: ~15 files, none over ~480 lines.** The messages section is the hardest to shrink further because prompt templates are content, not structure.

---

## 2. PeopleStore.swift — Responsibility Map (1359 lines)

The store is a `@MainActor final class` currently doing six distinct jobs:

| Lines | MARK | Responsibility | Extract to |
|---|---|---|---|
| 1–101 | Setup / init | Cache subscriber, list snapshot | Keep in `PeopleStore` |
| 105–134 | Launch snapshot (PC-1) | `ListSnapshot` type + build/load | Keep (small) |
| 136–262 | Index (SQLite/FTS5 + semantic) | `rebuildIndex`, `searchVault`, hybrid BM25+cosine | Extract: `PeopleSearchEngine` (wraps `SecondBrainDB`) |
| 264–292 | Paths | `peopleRoot`, `encountersRoot` etc. | Keep (private) |
| 296–470 | Load (cache fast path + per-file) | `load`, `loadPeople`, `loadEncounters`, etc. | Extract: `PeoplePersistence` actor |
| 473–580 | Person CRUD | `createPerson`, `updatePerson`, `deletePerson`, `writePerson` | Keep core, extract `PeoplePersistence` for disk I/O |
| 581–650 | Encounter CRUD | `addEncounter`, `bumpLastInteraction`, `deleteEncounter`, `writeEncounter` | Extract: `EncounterStore` (separate `@MainActor` class) |
| 651–700 | Import & merge | `importPeople`, `matchIndex`, `mergeImport`, `dedupeEmails` | Extract: `PeopleImportEngine` |
| 759–888 | Profile: memories, photos, notes | `addMemory`, `addAttachedNote`, `attachPhoto`, etc. | Keep in `PeopleStore` (or move to `PersonProfileStore`) |
| 860–888 | Relationships | `addRelationship`, `removeRelationship` | Move to `RelationshipStore` (see §4) |
| 890–1099 | Merge duplicates | `mergePeople`, `deduplicate`, `duplicateCandidates` | Extract: `PeopleDeduplicator` |
| 1106–1191 | Auto-extraction (Phase B) | `ingestExtraction`, `confirmSuggestion`, `dismissSuggestion` | Extract: `PersonExtractionStore` |
| 1234–1287 | Search (filtered people) | `filteredPeople`, `ghostCount`, `usedTagIDs` | Keep in `PeopleStore` (query interface) |
| 1289–1359 | Helpers | `recencyThenName`, `markdownMirror` | Keep or move mirror to `PeoplePersistence` |

**Recommended extraction priority:**

1. **`EncounterStore`** — fully orthogonal CRUD with its own disk layout; zero risk. `PeopleStore` keeps `encounters(for:)` as a query on the shared actor. S effort.
2. **`PeoplePersistence`** — extract `load`, `loadPeople`, `loadEncounters`, all `write*` methods as a non-isolated actor. Removes ~300 lines from `PeopleStore` and makes the store free of file I/O detail. M effort.
3. **`PersonExtractionStore`** — auto-extraction + suggestion pipeline (Phase B) is already self-contained; extracting it removes ~80 lines and clarifies that `PeopleStore` is identity-and-search, not pipeline. S effort.
4. **`PeopleDeduplicator`** — stateless algorithm over a `[Person]` snapshot; can be a free function or struct. S effort.

---

## 3. RelationshipPath — Adding to Model and DTO

### 3.1 Current state

`Person.swift:51–64` defines `Relationship` with a freeform `label: String` ("spouse", "manager", "kid", "friend"). There is no enum; the `AddRelationshipSheet` (line 1966) uses a raw `TextField`. The Graph module (`RelationshipEdge.swift`) uses shared tag/meeting co-occurrence, not the `label` field, so the edge carries no type signal.

`PersonRelationshipDTO` in `VaultKit/SharedModels.swift:175–183` mirrors the same freeform `label`. `PersonDTO:186–276` also has no path field.

### 3.2 Proposed `RelationshipPath` enum

**Owner: `VaultKit`** — it must be readable by the MCP server, the daemon, and the app without importing SwiftUI. Foundation-only, lives in a new `Sources/VaultKit/RelationshipPath.swift`:

```swift
// Sources/VaultKit/RelationshipPath.swift
public enum RelationshipPath: String, Codable, CaseIterable, Sendable {
    // Personal / intimate
    case romanticPartner   = "romantic_partner"
    case spouse            = "spouse"
    case exPartner         = "ex_partner"

    // Family
    case parent            = "parent"
    case child             = "child"
    case sibling           = "sibling"
    case familyMember      = "family_member"

    // Close social
    case closeFriend       = "close_friend"
    case friend            = "friend"

    // Professional
    case manager           = "manager"
    case directReport      = "direct_report"
    case colleague         = "colleague"
    case mentor            = "mentor"
    case client            = "client"
    case vendor            = "vendor"

    // Catch-all
    case custom            = "custom"

    /// Human display label (distinct from rawValue so rawValue stays stable).
    public var displayName: String { ... }

    /// Cadence hint — how many days between nudges (nil = no nudge).
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

    /// Whether this path unlocks relationship-depth content (attachment frameworks,
    /// Gottman exercises, NVC templates).
    public var supportsDepthContent: Bool {
        switch self {
        case .romanticPartner, .spouse, .closeFriend, .parent, .child, .sibling: return true
        default: return false
        }
    }
}
```

### 3.3 Adding to `Person` (app model) without breaking existing decoders

`Person.swift` uses a custom `init(from:)` with `try?`-optional decoding for every field (lines 199–222). Adding `relationshipPath` follows the same pattern:

In `Relationship` struct:
```swift
// Person.swift:51 — inside Relationship
var path: RelationshipPath?    // nil = legacy record (had no path)
```

In `Person.init(from:)` decoder extension — already uses `try?`-defaults, so:
```swift
// No CodingKeys change needed: Relationship's own Codable picks up the new field.
// Older person.json without "path" key: path decodes as nil (RelationshipPath? optional).
```

**Zero migration risk.** Old records decode with `path = nil`; new records decode their path. No schema version bump required.

### 3.4 Adding to `PersonRelationshipDTO` / `PersonDTO` in VaultKit

`SharedModels.swift:175` — add `path: RelationshipPath?` to `PersonRelationshipDTO`:

```swift
public struct PersonRelationshipDTO: Codable, Sendable {
    public let id: String
    public let toPersonID: String
    public let label: String
    public let path: RelationshipPath?   // new; nil for legacy records
    public let createdAt: Date
    public init(id: String, toPersonID: String, label: String,
                path: RelationshipPath? = nil, createdAt: Date) { ... }
}
```

`PersonDTO` custom decoder (`SharedModels.swift:216`) is already `try?`-tolerant, so the wrapped `[PersonRelationshipDTO]` read picks up the new field automatically. **No decoder breakage.**

### 3.5 `AddRelationshipSheet` — replace TextField with Picker

`PersonDetailView.swift:1966` currently presents a free-form `TextField("Relationship (spouse, manager, friend…)")`. Replace with:

```swift
Picker("Type", selection: $selectedPath) {
    ForEach(RelationshipPath.allCases, id: \.self) {
        Text($0.displayName).tag($0)
    }
}
// Optional overide label when path == .custom
if selectedPath == .custom {
    TextField("Describe the relationship", text: $label)
}
```

`Relationship.label` becomes auto-populated from `selectedPath.displayName` for non-custom paths. Store both: the enum for logic, the label for human display.

---

## 4. Module Boundary Analysis

### Current boundaries (Package.swift)

```
VaultKit  (Foundation only) ← imported by:
    MeetingScribe (app)
    ScribeCore (daemon)
    MeetingScribeMCP
    NotionMCP

MeetingScribe ← PeopleStore, PersonDetailView, all UI
```

### Relationship-type logic ownership

**`RelationshipPath` enum → VaultKit** (confirmed: no SwiftUI dependency; MCP server needs it to emit typed relationship data from `get_person`; daemon needs it for future smart check-in scheduling).

**Check-in cadence computation** (`suggestedCheckInDays`) → VaultKit (pure logic on enum, no store access).

**UI adaptation per path** (showing Gottman content vs. professional templates) → `MeetingScribe` target only. The app reads `person.relationships[n].path` and branches its view logic. VaultKit must not import SwiftUI.

**`EncounterStore`** when extracted — should live in `MeetingScribe` target (it holds `[Encounter]` which has `@Published`, UI observers). Not a VaultKit concern unless a DTO version is needed by the MCP.

**`PeopleSearchEngine`** wrapping `SecondBrainDB` — stays in `MeetingScribe` (SQLite, `OSLog`). Could be a protocol-typed dependency in the future, but not yet worth moving to VaultKit.

### Graph module

`Sources/MeetingScribe/People/Graph/` contains 7 files (PeopleGraphView, RelationshipEdge, GraphDetailPanel, GraphLayoutEngine, PersonNodeView, GraphFilterBar, PersonNode, PeopleGraphViewModel). `RelationshipEdge.swift:11` currently draws edges from shared tag/meeting co-occurrence only — it ignores `Relationship.label` entirely. After `RelationshipPath` lands, edge color/weight should also reflect the path type (intimate = warmer color, professional = cooler), which is a one-file change in `RelationshipEdge.swift`.

---

## 5. Existing Plan Items: Endorsements Through This Lens

From the plans already documented — items worth prioritizing from an architecture perspective:

1. **God-file decomposition (PersonDetailView + PeopleStore)** — already planned; my section map above is the concrete split. Highest priority: the messages section (~470 lines with two async Task pipelines) is the hardest to reason about when embedded in a 1986-line file.

2. **PPL-1 (inline identity editing)** — already partially done (`editingIdentity` state, lines 170–179). The `PersonIdentityPanel` extraction above makes it easier to add per-field click-to-edit without the rest of the view re-rendering.

3. **PPL-2 (multi-value contact fields)** — the `setPrimary` helper at line 383 explicitly calls out `// don't clobber emails[1...]`. This is ready for a `PersonContactRows` child view that renders `ForEach` over all values with +/− buttons.

4. **ARCH-1 CaptureKit de-dup** — relevant because `PeoplePersistence` extraction is the same pattern: pulling disk I/O into a non-isolated actor reduces `@MainActor` surface area and makes the future CaptureKit refactor easier by demonstrating the pattern.

---

## 6. NET-NEW Recommendations

### E1-1: `RelationshipPath` enum in VaultKit with cadence metadata (S)
Implement the enum exactly as specified in §3 above. Add to `VaultKit/RelationshipPath.swift`. Propagate to `Relationship`, `PersonRelationshipDTO`, `PersonDTO`. Replace the freeform TextField in `AddRelationshipSheet` with a Picker. **This unlocks all path-specific features downstream at zero decoder cost.** The enum's `suggestedCheckInDays` and `supportsDepthContent` properties are the first two hooks.

### E1-2: `PersonDetailViewModel` — extract business logic from the view (M)
Create `PersonDetailViewModel.swift` (owned by `MeetingScribe`, not VaultKit) as an `@Observable` or `ObservableObject` class holding:
- `ownerTokens(_:)` and `ownerMatchesPerson(_:)` logic (currently private to the view, lines 1117–1142)
- `personContextForAI()` (line 769) — assembles the context blob the AI uses
- `updateChatContext()` (line 1623) — chat rail grounding
- The `analysisOutput` / `analysisRunning` / `deepRunning` state machines

This separates 150+ lines of testable logic from SwiftUI rendering and makes the iMessage analysis pipeline unit-testable without booting a full view hierarchy.

### E1-3: `EncounterStore` — split encounter CRUD from `PeopleStore` (S)
Extract lines 581–650 (`addEncounter`, `bumpLastInteraction`, `deleteEncounter`, `writeEncounter`, `encounters(for:)`) into a standalone `@MainActor final class EncounterStore`. `PeopleStore` holds a reference; the view accesses it via `@EnvironmentObject`. This removes ~70 lines from `PeopleStore` and makes encounter logic independently testable. The MCP server's `get_meeting` already doesn't call PeopleStore for encounters — no MCP changes needed.

### E1-4: Path-aware check-in scheduler in VaultKit (M)
Add `CheckInScheduler` to VaultKit:
```swift
// VaultKit/CheckInScheduler.swift
public struct CheckInScheduler {
    public static func isDue(person: PersonDTO, encounters: [EncounterDTO]) -> Bool { ... }
    public static func daysSinceLastContact(person: PersonDTO, encounters: [EncounterDTO]) -> Int { ... }
    public static func nudgeMessage(path: RelationshipPath, daysSince: Int) -> String { ... }
}
```
This is pure value logic that the app, the MCP server, and eventually a Widget extension can call without importing SwiftUI. Feeds TDY-1 ("up next") and "stay in touch" nudges. **Foundation-only, no actor required.**

### E1-5: Relationship section → path-branched UI (M)
After E1-1, `PersonRelationshipsSection.swift` (extracted) should branch on `rel.path`:
- `romanticPartner / spouse / closeFriend` → show "Depth" button (opens relationship content: love languages, Gottman 4 Horsemen check, NVC templates).
- `parent / child / sibling` → show "Family" check-in prompt template.
- `manager / directReport` → show "1:1 prep" shortcut linking to the person's meeting history.
- `custom / nil` → current plain label display.

No model change beyond E1-1. The UI switch is a `switch rel.path` in the extracted child view.

### E1-6: Reciprocal label consistency (S)
`PeopleStore.addRelationship(from:to:label:)` (line 863) mirrors the SAME label bidirectionally ("spouse" ↔ "spouse"). After E1-1, implement semantic inversion:
```swift
// VaultKit/RelationshipPath.swift
public var reciprocal: RelationshipPath {
    switch self {
    case .parent: return .child
    case .child: return .parent
    case .manager: return .directReport
    case .directReport: return .manager
    default: return self     // symmetric paths
    }
}
```
`addRelationship` then passes `path.reciprocal` when writing the mirror record. **Zero decoder impact; purely additive.**

### E1-7: `RelationshipPath` in Graph edges (S)
`RelationshipEdge.swift:11` currently ignores `Relationship.label`. After E1-1, add:
```swift
// RelationshipEdge
let primaryPath: RelationshipPath?   // strongest path among direct relationships
```
`PeopleGraphViewModel` (which builds edges) already knows both people; it can read `person.relationships` to find the path. Color the edge by category: warm (personal), neutral (friend), cool (professional). One-file change.

### E1-8: `PersonDTO` — add `relationshipPath` exposure for MCP (S)
The MCP server's `get_person` tool returns a `PersonDTO`. After E1-1, `PersonRelationshipDTO.path` surfaces to Claude automatically. Add a new MCP tool `get_relationship_context(personID:)` that returns:
```json
{
  "path": "romantic_partner",
  "checkInDueDays": 1,
  "suggestedTemplate": "daily_partner_checkin",
  "lastEncounterDays": 3
}
```
This makes Claude relationship-type-aware without requiring prompt hacking — it knows whether to suggest a Gottman exercise vs. a 1:1 agenda.

### E1-9: `PeoplePersistence` non-isolated actor (M)
Extract all `write*` and `load*` methods from `PeopleStore` into:
```swift
actor PeoplePersistence {
    func writePerson(_ person: Person, root: URL) throws { ... }
    func loadAll(root: URL) -> (people: [Person], encounters: [Encounter]) { ... }
    func writeCache(_ cache: Cache, url: URL) { ... }
}
```
`PeopleStore` calls `await persistence.writePerson(...)` and moves off `@MainActor` for all I/O. This removes the `DispatchQueue.global(qos: .utility).async` escape hatches (lines 96, 696) and makes the actor isolation model consistent. M effort but prerequisite for any future iCloud sync.

### E1-10: `PersonExtractionStore` — decouple Phase B pipeline (S)
Extract lines 1116–1231 (auto-extraction, `ingestExtraction`, `confirmSuggestion`, `dismissSuggestion`, `writeSuggestion`) into `PersonExtractionStore`. `PeopleStore` becomes a simple delegate. The extraction store owns `suggestions: [PersonSuggestion]` and calls back into `PeopleStore.addMeetingMention` and `PeopleStore.bumpLastInteraction`. Zero behavior change; clarifies that `PeopleStore` is identity-and-search, not pipeline.

---

## 7. Top 3 Picks

1. **E1-1 (`RelationshipPath` enum in VaultKit) — S effort, maximum leverage.** Every relationship-depth feature (check-in nudges, depth content, path-aware UI, typed MCP output) is gated on this one enum. It's additive, decoder-safe, and 100% backward compatible. Build this first.

2. **E1-3 (`EncounterStore` extraction) — S effort, immediate clarity.** Encounter CRUD is fully orthogonal to person identity. Extracting it reduces `PeopleStore` by ~70 lines with zero behavioral change and establishes the pattern for the larger `PeoplePersistence` extraction (E1-9). Pairs with E1-4 since `CheckInScheduler` needs encounter data.

3. **E1-2 (`PersonDetailViewModel`) — M effort, unblocks testing.** The `personContextForAI()` context builder and `ownerMatchesPerson` logic are completely untested because they live inside a SwiftUI view struct. Extracting them into a `@Observable` class unlocks unit tests for the most relationship-critical logic in the codebase (AI context assembly, task attribution). Also the prerequisite for making `PersonMessagesSection` independently state-manageable.

---

## 8. Single Highest-Priority Recommendation

**Build `RelationshipPath` in VaultKit first (E1-1).** It is the foundation stone every other relationship-depth feature rests on. Without an enum, all path-specific UI (`romanticPartner` check-in cadence, family templates, professional 1:1 prep) requires string comparisons against freeform labels — brittle, untestable, and invisible to the MCP server. The implementation is small (~80 lines in VaultKit, ~30 lines of changes to `Person.swift`, `SharedModels.swift`, and `AddRelationshipSheet`), is completely decoder-safe (nil default on optional field), and immediately unlocks E1-4 through E1-8. Do this in one sitting before any UI work.
