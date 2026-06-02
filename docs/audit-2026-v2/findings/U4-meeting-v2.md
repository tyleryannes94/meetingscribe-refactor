# U4 — Meeting-First Persona Audit v2

**Lens:** Sam, 38, product manager. Uses MeetingScribe for transcription and action items. Relationship coaching is irrelevant noise. Every section below asks: does this hurt Sam's primary workflow?

---

## Full-app audit through Sam's lens

### Q1 — Does `StayConnectedSection` appear Monday morning?

**Short answer: No — correctly gated. But there is a latent cadence trap for `.unset` people.**

`StayConnectedSection` (`UI/StayConnectedSection.swift:19–23`) filters to `$0.relationshipType != .unset` before checking `isOverdue`. Sam's calendar-imported colleagues default to `.unset` (`Person.swift:319`: `decodeIfPresent … ?? .unset`), so they are excluded from the section. The section itself is wrapped in `if !items.isEmpty { … }` (`StayConnectedSection.swift:46`), so it renders nothing for Sam.

However: `RelationshipType.unset.defaultCheckInDays` returns `14` (`Person.swift:86`). If Sam ever manually sets even one contact to any non-unset type (including `.colleague`), that person enters the overdue pool after 30 days and the section appears. Sam will see a pink "Stay connected" card with a heart icon on her meeting-centric home screen with no way to dismiss or collapse it — the section has no "hide" button, no settings toggle, and no acknowledgement flow.

**Verdict:** Safe on cold install. Becomes a nuisance the moment any typed person goes overdue.

---

### Q2 — Spurious "💑 Check in with [colleague]" notification?

**Not possible from import alone, but the notification sync is missing from app launch.**

`RelationshipNotificationManager.syncPersonReminders` (`RelationshipNotificationManager.swift:63`) has a hard guard: `guard person.relationshipType != .unset else { continue }`. Calendar attendees and contact imports both land as `.unset` by default (`PeopleStore.swift:658–686` — `importPeople` calls `Person(displayName:…)` with no `relationshipType` argument; the default is `.unset`). The auto-extraction LLM (`PersonExtractionController.swift`, `PersonExtractor.swift`) never assigns a `relationshipType`. So Sam's colleagues cannot receive check-in notifications unless Sam explicitly sets their type.

`syncPersonReminders` is only called from one location — `QuickEncounterSheet.swift:218`. It is **not** called on app launch (`MeetingScribeApp.startServices()` has no call; confirmed by `grep -rn "syncPersonReminders"`). This means:

- Notifications scheduled from a prior session survive across relaunches unchanged. A `colleague`-typed person whose last encounter was logged via MCP `log_encounter` (bypassing `QuickEncounterSheet`) will still have the old stale notification queued. Their title would be `"💼 Check in with [Name]"`, not `"💑"` — the emoji is correctly type-keyed (`RelationshipNotificationManager.swift:128`). The briefing scenario's romance emoji for a colleague is not reproduced by the code, but a stale cadence notification for a colleague Sam already contacted is very reproducible.

---

### Q3 — Relationship filter chips in People list taking up space?

**Correctly gated — the `presentTypes.count > 1` threshold is clean for Sam.**

`PeopleListView` (`PeopleListView.swift:80–86`) computes `presentTypes` by removing `.unset` from the set of all used types. The chip bar is only rendered when `presentTypes.count > 1` (`PeopleListView.swift:260`). Sam with zero or one non-unset typed person sees no chip bar at all. The `PersonRow` (`PeopleListView.swift:337`) shows a relationship emoji badge inline only when `person.relationshipType != .unset` — correctly hidden for Sam's colleagues.

**Clean for Sam.** The threshold of `> 1` means if Sam has one partner and one colleague, the bar appears even if she never uses the filter — a minor nuisance but not a blocker.

---

### Q4 — Do Phase 4 MCP People tools break the existing meeting tools?

**No functional regression, but `get_coaching_context`'s "proactively" instruction is a live hazard.**

The `runTool` switch (`main.swift:1780–1807`) adds 6 new cases in a flat chain alongside 17 existing tools. No namespacing. Sam asking Claude "summarize my meeting" gets LLM context that includes all 23 tool schemas, including `get_coaching_context` (`main.swift:930`): description says "Use this to proactively coach the user on their relationship." The word **"proactively"** instructs the LLM to call this tool without user prompting. Sam asking "what did we decide in yesterday's meeting?" could receive an unsolicited relationship health report if an attendee is a typed person.

`mcp-registry.json` bundles all 23 tools under a description "Local-first meeting intelligence **with relationship coaching**" — this is how Claude Desktop displays the integration to Sam, who never opted into coaching.

---

### Q5 — Notification permission request — is there an explanation?

**No explanation shown; the system dialog fires immediately on first launch with no context.**

`MeetingScribeApp.startServices()` (`MeetingScribeApp.swift:200`) calls `Task { await notifications.requestAuthorization() }` unconditionally. `NotificationManager.requestAuthorization()` (`NotificationManager.swift:39–45`) calls `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])` with no usage string and no custom pre-prompt UI.

`Info.plist` has usage descriptions for Mic, Screen Capture, Calendar, Contacts, and AppleEvents — but no `NSUserNotificationUsageDescription` (macOS doesn't enforce one; the absence means no app-defined explanation appears). Sam sees a bare dialog and cannot distinguish "meeting ready" banners (wanted) from relationship check-in reminders (unwanted). If she denies, she loses both. This is compounded by Phase 2's `RelationshipNotificationManager.registerCategories()` (`RelationshipNotificationManager.swift:26`) silently adding the `PERSON_CHECKIN` category on every launch — all categories are granted or denied together.

---

### Q6 — Startup performance regressions from Phase 1–4 code?

**No critical-path regressions. Two latent concerns.**

`PeopleStore.init()` (`PeopleStore.swift:72–101`) loads off-main via `DispatchQueue.global(qos: .userInitiated)` with `ListSnapshot` fast-path. The SecondBrainDB v3 migration (`SecondBrainDB.swift:247–255`) is lazy — it runs inside `ensureSchema()` on first DB access, not synchronously at startup. `RelationshipNotificationManager.registerCategories()` (`RelationshipNotificationManager.swift:26`) calls `getNotificationCategories` asynchronously. Phase 4 MCP tools are in a separate process and add zero app startup cost.

**Latent concern 1 (TodayView layout):** `TodayView`'s feed now renders `SuggestedPeopleView`, `StayConnectedSection`, and `ReconnectView` in the same `ScrollView` VStack (`TodayView.swift:77–82`). All three evaluate on every `@Published` change from `PeopleStore`. With hundreds of auto-extracted contacts, frequent layout passes occur even when all three sections are empty for Sam. No measurement exists to confirm this is above threshold.

**Latent concern 2 (Ollama backfill interaction):** `backfillPeopleIfNeeded()` fires 25 sequential Ollama LLM calls after a 400ms delay. Each newly extracted person now also triggers the SecondBrainDB v3 write path. The marginal cost is small but un-metered.

---

## Existing-plan items I rank highest (through Sam's lens)

1. **Known gap #5 — `syncPersonReminders` not called on launch.** Stale notifications from prior sessions fire at arbitrary times for typed colleagues, with no recourse short of killing notification permission. One-line fix in `startServices()`.
2. **Known gap #6 — dual `Encounter.Kind` enums.** MCP `log_encounter` and the app's `QuickEncounterSheet` use different enums. Sam's Claude-assisted encounter log is silently inconsistent with what the People tab shows.
3. **Known gap #7 — `PersonDTO` memberwise init missing `relationshipType`.** Silent data loss for any Swift consumer using the explicit init rather than `Codable` decoding; blocks trustworthy MCP round-trips.

---

## Net-new recommendations

### U4-1 — Meeting-tools-only MCP mode / tool category filter
**What:** Add `"category": "meeting"` or `"category": "people"` to each tool object in `mcp-registry.json` and expose a `tools/list?category=meeting` filter in the MCP server's `tools/list` handler. Default to `all`.
**Why:** Sam's Claude session loads 23 tool schemas including `get_coaching_context` ("proactively coach the user on their relationship"), which nudges Claude toward unsolicited coaching during meeting summaries.
**User value:** Sam's Claude sessions stay meeting-focused; relationship tools are invisible unless requested.
**Effort:** S (hours) — add `category` field to 23 tool objects + one filter branch in the JSON-RPC `tools/list` handler.
**Impact:** High for meeting-first users; zero regression for relationship users.
**Deps:** None.

### U4-2 — Notification pre-prompt sheet before `requestAuthorization`
**What:** On first launch (check `UserDefaults` flag `didExplainNotifications`), show a one-screen sheet before calling `requestAuthorization`: "MeetingScribe sends two kinds of notifications: (1) Meeting ready — when transcription finishes. (2) Check-in reminders — optional, for contacts labeled as friends or family." Include a toggle: "Enable check-in reminders" (defaults off). If toggled off, skip `RelationshipNotificationManager.registerCategories()`.
**Why:** Sam is shown a raw system dialog. She doesn't know "allow" also enables relationship reminders. Denying blocks her "Meeting ready" banner.
**User value:** Sam can allow meeting notifications while opting out of relationship reminders in the same flow.
**Effort:** S (half-day) — one `OnboardingNotificationSheet.swift` + `UserDefaults` flag + conditional `registerCategories`.
**Impact:** High. Reduces notification-denial rate; decouples meeting and relationship notification channels.
**Deps:** None.

### U4-3 — `StayConnectedSection` dismiss/collapse control
**What:** Add a chevron toggle to collapse `StayConnectedSection` (persisted in `AppStorage("stayConnectedCollapsed")`). Show a "Don't show this" option that writes `AppSettings.shared.stayConnectedEnabled = false`. Toggle appears in the section header row.
**Why:** Sam will eventually set at least one contact's relationship type. Once any typed contact goes overdue, the pink heart card appears in her meeting home screen with no suppression path.
**User value:** Meeting-first users get a clean Today feed. Relationship-coach users are unaffected.
**Effort:** S (hours) — `@AppStorage` state + `if AppSettings.shared.stayConnectedEnabled` guard + header chevron.
**Impact:** Medium-high. Eliminates the most visible relationship-feature intrusion into Sam's core workflow.
**Deps:** None.

### U4-4 — Sync `RelationshipNotificationManager` on app launch, off-main
**What:** In `startServices()` (`MeetingScribeApp.swift`), add after the 400ms stagger: `Task.detached(priority: .background) { await RelationshipNotificationManager.shared.syncPersonReminders(people: await MainActor.run { PeopleStore.shared.people }) }`.
**Why:** Known gap #5 in the briefing. Any encounter logged via MCP `log_encounter` or direct file edit leaves stale notifications queued indefinitely. Fix is one line.
**User value:** Sam's contacts never get stale "check in" pings after they were already contacted.
**Effort:** S (minutes) — one `Task.detached` call.
**Impact:** High correctness fix; also endorses an existing known gap.
**Deps:** None.

### U4-5 — Action item count in "Meeting ready" notification body
**What:** In `wirePipelineNotification` (`MeetingScribeApp.swift:155–174`), pass `manager.actionItems.items.filter { $0.meetingID == meeting.id }.count` into `notifyTranscriptionComplete` and append `"· \(count) action items"` to the notification body.
**Why:** Sam's primary use case is action item capture. The current "Meeting ready" body shows a prose summary snippet she doesn't need. The count is what tells her whether to open the app immediately.
**User value:** Sam decides at a glance whether to open the app. Reduces time-to-first-action.
**Effort:** S (hours) — pass count through to `notifyTranscriptionComplete`; extend the method signature by one `Int` parameter.
**Impact:** High for Sam's core loop.
**Deps:** `ActionItemStore` is already available via `manager.actionItems`.

### U4-6 — Remove "proactively" instruction from relationship MCP tool descriptions
**What:** In `main.swift:930–940`, change `get_coaching_context` description from "Use this to proactively coach the user on their relationship" to "Only call when the user explicitly asks about a relationship or contact check-in status." Apply same change to `list_overdue_check_ins` (`main.swift:920`).
**Why:** "Proactively" in a tool description is a direct instruction to the LLM to call the tool without user prompting. Sam asking "what are my action items?" should not produce a relationship health report.
**User value:** Meeting summaries stay meeting-focused.
**Effort:** S (minutes) — string edit.
**Impact:** Medium. Behavioral change in Claude's tool selection with zero code risk.
**Deps:** None.

### U4-7 — Action item quick-complete from "Meeting ready" notification
**What:** Add a `UNNotificationAction` identifier `COMPLETE_TOP_ACTION` to the `MEETING_FINALIZED` notification category. When triggered, mark the first open action item from that meeting as complete and send a follow-up "Marked complete" banner. Register the action in `NotificationManager.registerCategories()` and handle it in the delegate's `didReceive` method.
**Why:** Sam's core loop is: attend meeting → "Meeting ready" banner → open app → mark action items. Removing the "open app" step for simple single-item meetings reduces friction substantially.
**User value:** One fewer app-open for Sam's most common scenario.
**Effort:** M (1–2 days) — notification category + delegate response handler + `ActionItemStore.complete(id:)`.
**Impact:** High for Sam's core workflow.
**Deps:** None.

### U4-8 — Meeting summary collapse with action items above the fold
**What:** In `UnifiedMeetingDetail.swift`, default the summary section to collapsed (showing only the first paragraph), with a "Show full summary" toggle. Action items section moves above the summary in the detail layout. Add a `@AppStorage("summaryDefaultExpanded")` preference.
**Why:** Sam opens a meeting detail and must scroll past a multi-paragraph summary to reach action items. The item she wants is below the fold by default.
**User value:** Sam's primary artifact (action items) is visible without scrolling.
**Effort:** S (hours) — `@State var summaryExpanded = false` + conditional `VStack` height + reorder sections.
**Impact:** Medium. Incremental quality-of-life for Sam's daily workflow.
**Deps:** None.

---

## Top 3 picks

1. **U4-2 — Notification pre-prompt sheet.** Sam currently faces a no-context system dialog that, if denied, permanently blocks the "Meeting ready" banner she relies on. This is the highest-friction moment in Sam's first-run experience and costs half a day to fix.

2. **U4-1 — Meeting-tools-only MCP mode.** The `get_coaching_context` "proactively coach" instruction in the tool description is a live hazard causing Claude to inject relationship coaching into meeting summary sessions without user intent. The fix is a string edit, but the behavioral implication is significant.

3. **U4-5 — Action item count in "Meeting ready" notification.** Sam's entire value proposition from MeetingScribe is action item capture. Surfacing the count in the notification subtitle removes a full app-open from her core loop.

---

## Single highest-priority recommendation

**U4-2 — Notification pre-prompt sheet.**

It is the only finding that can actively harm Sam's core functionality (she denies the system dialog, loses "Meeting ready" banners permanently) and the only one that bundles a silent opt-out for the relationship features she doesn't want — all in a single half-day fix.
