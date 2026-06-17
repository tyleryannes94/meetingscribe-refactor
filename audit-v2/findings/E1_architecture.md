# Architecture & State Management Findings — MeetingScribe v2 Audit

## Top friction points / gaps (file:line citations)

### 1. MeetingManager is still a god object despite partial decomposition
`MeetingManager.swift:23` is `@MainActor final class` owning: recording state, pastMeetings array, tagStore, actionItems, decisions, dictation, bodyCache, quickNotesController, pipelineController, actionItemBackfill, personExtraction, liveTranscriber, AudioRecorder, WhisperTranscriber, OllamaService, and the isSyncingTasks / lastTaskSyncError / lastTaskSyncSummary for external task sync. That is 14+ distinct concerns in one ObservableObject. Any change to transcribingMeetingIDs or isSyncingTasks invalidates every view that `@EnvironmentObject`s the manager — including Today, MainWindow toolbar, and MeetingsView simultaneously.

### 2. PeopleStore.shared is a singleton piercing the environment graph in 51+ call sites
`PeopleStore.swift:20` is `static let shared`. Despite being injected as `.environmentObject(PeopleStore.shared)` in `MeetingScribeApp.swift:37`, views like `MeetingDetailHeader.swift:641,666,678,682,683`, `MeetingChatTab.swift:45`, `MeetingSummaryTab.swift:417`, `MeetingPipelineController.swift:219,224,225,239`, `ActionItemStore.swift:513`, and `WorkspaceIndex.swift:39,309` all reach `PeopleStore.shared` directly. This bypasses SwiftUI's dependency graph — those views/controllers do NOT re-render reactively when people change.

### 3. Cross-store wiring is imperative, not reactive
The link from a meeting pipeline completion to PeopleStore is: `MeetingPipelineController.swift:224` calls `PeopleStore.shared.linkAttendees(of:)` — a fire-and-forget imperative call. There is no Combine publisher or async stream carrying "meeting completed → update People graph → refresh Today dashboard → update task owner suggestions". Each hop is a manual method call scattered across files. Adding a new cross-feature flow (e.g., "a task completed → log an encounter") requires finding and modifying multiple files.

### 4. NotificationCenter still used as an inter-tab bus for non-navigation events
`MainWindow.swift:478` uses `NotificationCenter.default.post(name: .meetingScribeRunChat, ...)` to dispatch a chat query — a stringly-typed, fire-and-forget event with no type safety. `MeetingScribeApp.swift:92–100` uses NotificationCenter for ⌘1–⌘5 navigation even though `WorkspaceRouter` exists. 25 total post sites. The router is correctly designed but the old NC pattern co-exists and creates ambiguity about which channel to use.

### 5. ActionItemStore is @MainActor but accesses PeopleStore.shared on a background queue
`ActionItemStore.swift:513` reads `PeopleStore.shared.people` inside what appears to be a sync context. PeopleStore is `@MainActor` — this is a latent data-race if ActionItemStore ever calls this off-main.

### 6. ChatSession is wired via imperative `attach()`, not environment injection
`ChatSession.swift:47` defines `func attach(manager: MeetingManager)`, called at `MeetingScribeApp.swift:185`. ChatSession accesses `PeopleStore.shared` directly (`ChatSession.swift:250`). This means the AI assistant has no reactive observation of People or Tasks changes — it reads a static snapshot at query time.

### 7. No reactive intelligence bus between domains
There is no `SecondBrainEventBus` or equivalent. When a meeting finishes, PeopleStore is updated imperatively. When a person's relationship health drops, nothing notifies Today. When a task becomes overdue, nothing surfaces in the meeting pre-brief. The data relationships exist in the models but there is no publish/subscribe mechanism to propagate state changes proactively across domains.

---

## Existing items to endorse (from prior plan or codebase)

- `WorkspaceRouter.swift` — excellent design. Typed routes, browser-style history, `pendingRoute` mailbox pattern for one-shot deep links. This is the right foundation.
- Sub-controller decomposition in `MeetingManager` (audit 5.1 / Batch 6) — `quickNotesController`, `pipelineController`, `personExtraction` as separate ObservableObjects is the right direction. Continue splitting.
- `MeetingScribeApp.swift:37–51` environment injection of sub-controllers — the comment on line 40 ("scoped sub-controllers") correctly articulates the goal of scoped invalidation.
- `PeopleStore` O(1) index rebuilds (`personIndex`, `encounterCountIndex` via `didSet`) — good perf pattern.
- `WorkspaceIndex.swift` as a cross-entity catalog — the right abstraction for search; should be extended to be the reactive hub.

---

## NET-NEW recommendations

### E1-1: `AppEnvironment` — Single Typed Dependency Container
- **What:** Replace the 8 `@StateObject` declarations in `MeetingScribeApp` plus 20 singletons with a single `AppEnvironment: ObservableObject` that holds typed references to every domain store. Inject it once via `.environment(\.appEnv, env)`. Views declare `@Environment(\.appEnv) var env` and access `env.people`, `env.tasks`, `env.meetings` — never `.shared`. Eliminates 51+ `PeopleStore.shared` call sites with compile-time-safe references.
- **Why (second-brain angle):** A coherent second brain requires coherent state. The current mix of environment injection and direct singleton access means the same data has two access paths with different reactivity semantics. A unified container makes cross-domain observation trivially composable.
- **Cross-feature connections:** All 5 tabs, ChatSession, WorkspaceIndex, MCP server, WebAPI
- **Effort:** M | **Impact:** High
- **Deps:** none (purely additive refactor)

### E1-2: `SecondBrainEventBus` — Typed Async Stream of Domain Events
- **What:** A lightweight actor (`SecondBrainEventBus`) with an `AsyncStream<SecondBrainEvent>` where `SecondBrainEvent` is an enum: `.meetingFinalized(Meeting)`, `.personUpdated(Person)`, `.taskCompleted(ActionItem)`, `.encounterLogged(Encounter)`, `.relationshipDrifted(Person)`, etc. Stores publish into it; Today, PreMeetingBrief, and the AI chat subscribe. Replace the 7 imperative cross-store calls in `MeetingPipelineController` with single event publishes.
- **Why (second-brain angle):** This is the nervous system of the second brain. Right now the app is a set of siloed stores with point-to-point wiring. An event bus means: meeting finishes → Today updates automatically, People encounter logged, AI chat context refreshes, pre-meeting brief for next attendee regenerates. Zero new code required in the emitting store.
- **Cross-feature connections:** Meetings → People → Today → Tasks → ChatSession → PreMeetingBrief
- **Effort:** M | **Impact:** High
- **Deps:** E1-1 (easier with unified container but not required)

### E1-3: Break MeetingManager into 3 Domain Services
- **What:** Extract from `MeetingManager`:
  1. `RecordingService` — owns `RecordingState`, `activeMeeting`, `AudioRecorder`, `WhisperTranscriber`, IPC to ScribeCore
  2. `MeetingLibraryService` — owns `pastMeetings`, `MeetingStore`, `bodyCache`, `TagStore`, the prefetch/refresh logic
  3. `AIProcessingService` — owns `OllamaService`, transcription queue, `isSyncingTasks`, `ollamaReachable`
  Keep `MeetingManager` as a thin facade forwarding properties for backwards compatibility, but annotate it as deprecated. Sub-controllers already extracted (pipelineController, etc.) become sub-services of `AIProcessingService`.
- **Why (second-brain angle):** The Today view rendering invalidates when `isSyncingTasks` changes — a completely unrelated concern. A 3-way split means Today observes only `MeetingLibraryService`, the toolbar observes only `RecordingService`, and the pipeline observes only `AIProcessingService`. Faster redraws, cleaner mental model, and makes it possible to run `AIProcessingService` as a background actor.
- **Cross-feature connections:** All 5 tabs (scoped subscriptions), MenuBarExtra, Settings
- **Effort:** L | **Impact:** High
- **Deps:** E1-1

### E1-4: `ProactiveContextEngine` — Reactive Cross-Domain Intelligence Layer
- **What:** A new `@MainActor` service (not a singleton, injected via `AppEnvironment`) that subscribes to `SecondBrainEventBus` and emits `ProactiveInsight` structs: upcoming-meeting attendee has open tasks, relationship health dropped below threshold, action item from a meeting was never assigned, a person hasn't been contacted despite a committed follow-up. Today tab renders these as a "Needs Attention" feed without any tab needing to query multiple stores.
- **Why (second-brain angle):** This is what separates a second brain from a filing cabinet. The current app requires the user to manually correlate across tabs. ProactiveContextEngine does that correlation automatically and surfaces it where Tyler is (Today), not buried in the People or Tasks tab.
- **Cross-feature connections:** Meetings, People, Tasks → Today (one-way push); optional: triggers chat rail highlight
- **Effort:** L | **Impact:** High
- **Deps:** E1-2

### E1-5: Eliminate Remaining NotificationCenter Navigation Posts
- **What:** `MeetingScribeApp.swift:92–100` ⌘1–⌘5 menu commands post NotificationCenter navigation events even though `WorkspaceRouter` exists. Replace all 25 NotificationCenter post sites with direct router calls or typed `AppEnvironment` method calls. Centralize in a `CommandDispatcher` that `MeetingScribeApp` owns and passes to commands.
- **Why (second-brain angle):** Type safety and debuggability. A stringly-typed NC post for navigation that fires into a router that already exists is technical debt that will cause missed navigations when lazy tabs haven't registered their listeners yet (the exact bug WorkspaceRouter was built to fix).
- **Cross-feature connections:** All 5 tabs, command menu, MenuBarExtra
- **Effort:** S | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **E1-2** (SecondBrainEventBus) — highest leverage per line of code; converts 7 imperative cross-store calls into a typed stream that makes every future cross-domain feature trivial to wire
2. **E1-4** (ProactiveContextEngine) — the feature that makes this feel like a second brain rather than 5 tabs; directly addresses Tyler's interconnectedness goal
3. **E1-3** (MeetingManager split) — eliminates the most significant render-thrashing bottleneck (Today re-renders on every transcribingMeetingIDs tick) and is a prerequisite for making MeetingLibraryService observable by multiple tabs independently
