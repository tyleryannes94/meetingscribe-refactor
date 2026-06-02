# E1 — New Code Quality (Phase 1–6)

**Lens:** Are the Phase 1–6 files production-ready or prototype-quality? Every
claim is cited to a specific file and line.

---

## Full-App Audit Through This Lens

### E1-01 · CRITICAL · Stub body compiles but does nothing — StoreKitManager
**File:** `Sources/MeetingScribe/Monetization/StoreKitManager.swift:34–38`

`purchase(_:)` resolves to setting `lastError` with a human-readable string:
```swift
await MainActor.run {
    lastError = "StoreKit 2 purchase not yet implemented. ..."
}
```
There is no `throw`, no `Result`, and no callback to the caller. The only
side-effect visible to the user is the `showPurchaseAlert` state in
`ProPaywallView`. Combined with `overrideAllEnabled = true` in DEBUG (see
E1-02), this entire code path is unreachable in development.

**Severity:** 🔴 Critical — purchase flow is 0% functional.

---

### E1-02 · HIGH · DEBUG override silently bypasses every gate
**File:** `Sources/MeetingScribe/Monetization/FeatureGate.swift:51–54`

```swift
#if DEBUG
var overrideAllEnabled: Bool = true
#else
let overrideAllEnabled: Bool = false
#endif
```

Because `isEnabled(_:)` short-circuits on `overrideAllEnabled` before
checking `isPro`, no gate is ever exercised during development. The paywall
cannot be tested without hacking this value, and QA cannot verify that
free-tier limits are enforced.

**Severity:** 🟠 High — monetization entirely untestable without source
modification.

---

### E1-03 · CRITICAL · `RelationshipPromptLibrary` is dead code — never called
**Files:**
- `Sources/MeetingScribe/People/RelationshipPromptLibrary.swift:59` —
  `weeklyPrompt(for:)` defined
- No call site exists anywhere in `Sources/`

The entire library (28 prompts + `weeklyPrompt`) has zero callers. The
docstring says it is "surfaced in PersonDetailView's identity panel" but
`PersonDetailView.swift` contains no reference to `RelationshipPromptLibrary`
or `weeklyPrompt`. Phase 3 shipped the content but never wired the display.

**Severity:** 🔴 Critical — the primary Phase 3 deliverable is invisible to
users.

---

### E1-04 · CRITICAL · `StoreKitManager.triggerUpgradePromptIfNeeded` is dead code
**File:** `Sources/MeetingScribe/Monetization/StoreKitManager.swift:57–65`

The function is defined but has zero callers anywhere in `Sources/`. The
comment says it should fire "after first AI summary" but no summary path calls
it. The 7-day throttle logic, `UserDefaults` key, and `showPaywall` dispatch
all do nothing because no code path invokes this function.

**Severity:** 🟠 High — automatic upgrade prompts never appear.

---

### E1-05 · CRITICAL · `ProPaywallView` is never presented — `paywallFeature` is never observed in a `.sheet`
**Files:**
- `Sources/MeetingScribe/Monetization/FeatureGate.swift:61` — `paywallFeature: ManagedFeature? = nil`
- `Sources/MeetingScribe/UI/MainWindow.swift:303` — `.sheet(item: $activeSheet)` (different sheet enum)
- No view binds `.sheet(item: $FeatureGate.shared.paywallFeature)` anywhere in `Sources/`

`showPaywall(for:)` sets `paywallFeature` on the `@Observable` singleton, but
no SwiftUI host observes that property to present the sheet. Setting state
that nothing reads is a no-op.

**Severity:** 🔴 Critical — confirmed gap from BRIEFING, cited here with
exact lines for the fix target.

---

### E1-06 · HIGH · `syncPersonReminders` never called on app launch — only from `QuickEncounterSheet`
**Files:**
- `Sources/MeetingScribe/People/QuickEncounterSheet.swift:215–219` — the only call site
- `Sources/MeetingScribe/People/RelationshipNotificationManager.swift:58` — function definition

A user who opens the app, taps into the People tab, and waits for a
notification will never receive one because the scheduler only runs after
explicitly logging an encounter via `QuickEncounterSheet`. Notifications are
not scheduled on launch, after editing a person's cadence, or after adding a
new person.

**Severity:** 🟠 High — the entire notification habit loop is broken for
cold-start users.

---

### E1-07 · HIGH · `PersonDTO` memberwise init missing Phase D fields
**File:** `Sources/VaultKit/SharedModels.swift:267–285`

The handwritten `public init(id:displayName:...)` omits `relationshipType`
and `checkInCadenceDays` entirely. Any code that constructs a `PersonDTO` via
this init (e.g. test fixtures, MCP server constructors, in-memory builds) will
produce a DTO with `nil` Phase D fields even when the caller has real values.
The tolerant `Codable` decode path handles these fields correctly; only the
manual init is broken.

```swift
// Line 267 — signature ends with importSources: [String] = []
// No relationshipType, no checkInCadenceDays parameters follow.
```

**Severity:** 🟠 High — any programmatic PersonDTO construction drops
relationship data silently.

---

### E1-08 · HIGH · Auto-save comment contradicts implementation — `KindChip` tap does NOT save
**File:** `Sources/MeetingScribe/People/QuickEncounterSheet.swift:71, 120–135`

The block comment on line 71 states:
```
1. Tap a Kind chip (required)  ← auto-saves on tap
```
But the `KindChip` action closure (lines 122–124) only toggles `selectedKind`;
it never calls `saveIfValid()`. The sheet stays open and requires an explicit
"Save check-in" button tap. This is a documentation lie that will confuse
future engineers and mis-set user expectations in UI copy.

**Severity:** 🟡 Medium — documentation/UX inconsistency; not a crash, but
"auto-saves on tap" is never true.

---

### E1-09 · MEDIUM · Double-save race via `onSubmit` + `keyboardShortcut(.return)`
**File:** `Sources/MeetingScribe/People/QuickEncounterSheet.swift:159, 196`

`TextField` declares `.onSubmit { saveIfValid() }` and the Save button
declares `.keyboardShortcut(.return, modifiers: [])`. On macOS, pressing
Return when focus is in the text field fires **both** handlers in the same
event delivery pass: `onSubmit` first, then the keyboard shortcut on the
button. `saveIfValid()` has no idempotency guard (no `isSaving` flag, no
`selectedKind = nil` before `dismiss()`), so two encounters can be written to
`PeopleStore` for a single user action.

**Severity:** 🟠 High — data integrity bug; user can silently create duplicate
encounter records.

---

### E1-10 · MEDIUM · `scheduleCheckIn` issues N+1 `pendingNotificationRequests()` IPC calls
**File:** `Sources/MeetingScribe/People/RelationshipNotificationManager.swift:119–121`

Inside the per-person loop, `scheduleCheckIn` calls:
```swift
let pending = await center.pendingNotificationRequests()
```
This is an async IPC round-trip to `UserNotificationsd` per person. For a
user with 30 typed relationships this is 30 separate out-of-process round-
trips. The pending list should be fetched once before the loop (as is already
done for the cancellation sweep at lines 113–117) and passed in.

**Severity:** 🟡 Medium — performance; visible latency on large people graphs.

---

### E1-11 · MEDIUM · `registerCategories` closure is unguarded — crosses actor boundary
**File:** `Sources/MeetingScribe/People/RelationshipNotificationManager.swift:41–45`

`registerCategories()` is called from `init()` of a `@MainActor` class, but
`getNotificationCategories(_:)` delivers its completion handler on an
**unspecified queue**. The closure then calls
`UNUserNotificationCenter.setNotificationCategories(_:)` without hopping back
to the main actor. The `@preconcurrency import UserNotifications` suppresses
the Swift concurrency warning but does not fix the underlying data race.
Under Swift 6 strict concurrency this will be an error.

**Severity:** 🟡 Medium — concurrency correctness; latent Swift 6 build
failure.

---

### E1-12 · MEDIUM · Birthday "week-before" notification silently skipped when birthday has already passed this year
**File:** `Sources/MeetingScribe/People/RelationshipNotificationManager.swift:185–200`

```swift
if let thisYearBd = cal.date(from: nextBdComponents), thisYearBd > now {
    // week-before scheduled
}
// else: no fallback to next year
```

When `thisYearBd <= now` (birthday already passed in 2026), the `if` block is
skipped and no next-year week-before notification is ever scheduled. The
birthday-day notification is correctly set to `repeats: true`, but the "7
days out" warning fires once and then disappears forever for anyone enrolled
after their birthday.

**Severity:** 🟡 Medium — functional bug for >50% of users depending on
enrollment date.

---

### E1-13 · LOW · `StoreKitManager` uses `ObservableObject` / `@Published` while `FeatureGate` uses `@Observable`
**Files:**
- `Sources/MeetingScribe/Monetization/StoreKitManager.swift:24` — `ObservableObject`
- `Sources/MeetingScribe/Monetization/FeatureGate.swift:44` — `@Observable`

`ProPaywallView` calls `StoreKitManager.shared.restorePurchases()` via a bare
`Task` (line 79) but holds no `@ObservedObject` or `@StateObject` reference to
`StoreKitManager`. The `isLoading` and `lastError` `@Published` properties
are therefore never observed by the view — the Restore button shows no
spinner and no error feedback.

**Severity:** 🟡 Medium — silent UX failure; user gets no feedback after
tapping Restore.

---

### E1-14 · LOW · Hardcoded `86400` used for "days" arithmetic throughout
**Files:**
- `Sources/MeetingScribe/UI/StayConnectedSection.swift:29`
- `Sources/MeetingScribe/People/RelationshipNotificationManager.swift:75, 79, 90, 188`

`86400` seconds is used as a fixed-length day in time-interval arithmetic.
This breaks across DST transitions (a day can be 82800 or 90000 seconds),
causing check-in due dates to drift by 1–2 hours across spring/autumn
clock changes. `Calendar.dateComponents(_:from:to:)` or
`Calendar.date(byAdding:value:to:)` should be used instead.

**Severity:** 🟡 Low — subtle DST bug; affects users near midnight on
transition days.

---

### E1-15 · LOW · Two `Encounter.Kind` enums with overlapping raw values
**Files:**
- `Sources/VaultKit/Encounter.swift:7` — `Kind { meeting, call, email, message, note }`
- `Sources/MeetingScribe/People/QuickEncounterSheet.swift:9` — `Kind { call, coffee, videoCall, message, metUp, milestone }`

Both are nested under different `Encounter` types (`VaultKit.Encounter` vs.
`MeetingScribe.Encounter`), so there is no compiler error. But the
`eventName` written by `QuickEncounterSheet` is `"\(kind.emoji) \(kind.rawValue)"` —
a freeform string rather than a persisted `Kind` enum case. The VaultKit
`Encounter.Kind` is never written to disk by this path. Any future code that
tries to decode `kind` from JSON written by `QuickEncounterSheet` will fail or
produce `.note` as a fallback.

**Severity:** 🟡 Medium — schema inconsistency; future decode bug.

---

## Existing-Plan Items I Rank Highest

1. **Wire `ProPaywallView` into a host view** (plan Phase 9) — unblocks the
   entire monetization layer with one `.sheet(item:)` modifier. (E1-05)

2. **Real StoreKit 2 `purchase()`** (plan Phase 9) — the current stub makes
   every revenue test impossible. (E1-01)

3. **Call `syncPersonReminders()` on app launch** (plan Phase 7) — the habit
   loop is broken for all cold-start users. (E1-06)

4. **Add `RelationshipPromptLibrary` call in `PersonDetailView`** (plan Phase 8)
   — Phase 3's primary deliverable is invisible. (E1-03)

5. **Fix `PersonDTO` memberwise init** (plan Phase 7) — prevents silent data
   loss in any non-decode construction path. (E1-07)

---

## NET-NEW Recommendations

### E1-N1 · Add `isSaving` guard to `saveIfValid()` to prevent duplicate encounters
**What:** Add `@State private var isSaving = false` to `QuickEncounterSheet`;
gate `saveIfValid()` with `guard !isSaving else { return }` and set
`isSaving = true` before writing.
**Why:** `onSubmit` + `keyboardShortcut(.return)` fire together on Return keypress
(E1-09). Without this guard a single keypress writes two `Encounter` records.
**User value:** Data integrity — no phantom duplicate encounters in the
relationship history.
**Effort:** S | **Impact:** High | **Deps:** none

---

### E1-N2 · Introduce `FeatureGate.debugMode: Bool` distinct from `overrideAllEnabled`
**What:** Replace the blanket `overrideAllEnabled = true` in DEBUG with a
`debugMode` flag that can simulate free-tier, paid-tier, or paywalled states.
Add a hidden developer menu in `SettingsView` to toggle between modes.
**Why:** With `overrideAllEnabled = true` it is impossible to test the paywall
flow, the free-tier limits, or the upgrade prompt without modifying source (E1-02).
**User value:** Prevents shipping gate bugs by making all monetization states
QA-testable.
**Effort:** S | **Impact:** High | **Deps:** none

---

### E1-N3 · Replace N+1 `pendingNotificationRequests()` calls with a single pre-fetch
**What:** In `syncPersonReminders`, fetch `center.pendingNotificationRequests()`
once before the `for` loop and pass the result (as a `Set<String>` of
identifiers) into `scheduleCheckIn`. Remove the per-person fetch inside
`scheduleCheckIn`.
**Why:** N out-of-process IPC calls for N people is O(N) latency on every
encounter save (E1-10). Pre-fetching reduces this to O(1).
**User value:** No user-visible latency when logging encounters with large
contact lists.
**Effort:** S | **Impact:** Medium | **Deps:** E1-06 (launch call adds urgency)

---

### E1-N4 · Fix `registerCategories` to re-enter `@MainActor` inside the completion handler
**What:** Change the `getNotificationCategories` closure to use
`Task { @MainActor in ... }` to hop back before calling
`setNotificationCategories`.
**Why:** Completion handlers from `UNUserNotificationCenter` are delivered on
an unspecified queue; the current code mutates categories off-main-actor from
a `@MainActor` class init (E1-11). This will become a build error under Swift 6
strict concurrency.
**User value:** Correctness; prevents potential category registration crashes on
Swift 6 migration.
**Effort:** S | **Impact:** Medium | **Deps:** none

---

### E1-N5 · Replace fixed `86400` arithmetic with `Calendar.date(byAdding:)` throughout
**What:** Audit all occurrences of `* 86400` or `/ 86400` in
`StayConnectedSection.swift` and `RelationshipNotificationManager.swift` and
replace with `Calendar.current.date(byAdding: .day, value:, to:)` and
`Calendar.current.dateComponents([.day], from:to:).day`.
**Why:** DST transitions make a calendar day ≠ 86400 seconds (E1-14).
Check-in due dates drift by up to 2 hours for users in DST-observing locales.
**User value:** Correct cadence dates year-round; no phantom "1 day overdue"
on clock-change weekends.
**Effort:** S | **Impact:** Medium | **Deps:** none

---

### E1-N6 · Fix birthday "week-before" notification to handle next-year case
**What:** In `scheduleBirthdayReminders`, when `thisYearBd <= now`, compute
`nextBdComponents.year = currentYear + 1` and schedule the week-before
notification for next year.
**Why:** The current code silently skips the week-before notification for
anyone enrolled after their birthday (E1-12). This affects >50% of users
depending on enrollment date.
**User value:** Reliable birthday-week reminders every year, not just the year
of enrollment.
**Effort:** S | **Impact:** Medium | **Deps:** none

---

### E1-N7 · Consolidate `Encounter.Kind` — adopt `QuickEncounterSheet` cases in the persisted model
**What:** Add `coffee`, `videoCall`, `metUp`, `milestone` to `VaultKit.Encounter.Kind`
(keeping `meeting`/`email` for backcompat). Update `QuickEncounterSheet` to
write `kind` as the typed enum rather than embedding it in `eventName` as a
freeform string.
**Why:** The two parallel `Kind` enums (E1-15) create a decode gap. The MCP
`list_encounters` tool returns raw JSON; if a caller tries to decode `kind`
from encounters written by `QuickEncounterSheet` they get garbage.
**User value:** Consistent encounter data across the app and MCP tools.
**Effort:** M | **Impact:** Medium | **Deps:** schema migration for existing encounter files

---

### E1-N8 · Wire `RelationshipPromptLibrary.weeklyPrompt` into `PersonDetailView`
**What:** In `PersonDetailView`, add a `WeeklyPromptCard` view below the
relationship-type badge that calls `RelationshipPromptLibrary.weeklyPrompt(for:)`
and displays the result behind a `FeatureGate.isEnabled(.relationshipContent)`
check.
**Why:** The entire library is dead code (E1-03). One call site and one view
component delivers Phase 3's primary user-visible feature.
**User value:** Coaching prompts surface in the only view users spend time in
per-person; the paywall bullet "Relationship coaching frameworks" becomes real.
**Effort:** S | **Impact:** High | **Deps:** E1-05 (paywall must be presentable for gate to matter)

---

### E1-N9 · Add `StoreKitManager` observation to `ProPaywallView` via `@ObservedObject`
**What:** Add `@ObservedObject private var store = StoreKitManager.shared` to
`ProPaywallView`. Gate the Restore button with `store.isLoading` to show a
`ProgressView` and display `store.lastError` in the alert.
**Why:** Currently `isLoading` and `lastError` are published but never
observed in the view (E1-13). User taps Restore and gets zero feedback.
**User value:** Restore flow shows spinner → success/failure instead of silently
doing nothing.
**Effort:** S | **Impact:** Medium | **Deps:** E1-01 (real StoreKit needed for end-to-end)

---

### E1-N10 · Add `relationshipType` and `checkInCadenceDays` to `PersonDTO` memberwise init
**What:** Add `relationshipType: String? = nil, checkInCadenceDays: Int? = nil`
parameters to the `public init` at `SharedModels.swift:267`. Assign them in
the body. This is a purely additive API change — all existing callers get the
`nil` default.
**Why:** The memberwise init omits Phase D fields (E1-07). Any code that
constructs a `PersonDTO` programmatically (test fixtures, MCP response builders)
silently drops relationship type.
**User value:** MCP tools that construct `PersonDTO` responses include
`relationshipType` correctly, enabling Claude to reason about relationship tiers.
**Effort:** S | **Impact:** High | **Deps:** none

---

## Top 3 Picks

1. **E1-N1** (isSaving guard) — data integrity; ship-blocker quality bug
2. **E1-N10** (PersonDTO memberwise init) — silent data loss; one-line fix with
   high blast radius
3. **E1-N8** (wire `weeklyPrompt`) — turns Phase 3's dead code into a live feature

## Single Highest-Priority Recommendation

**E1-N1 — add `isSaving` guard to `saveIfValid()`.**
It is the only issue in this set that silently corrupts user data on a
keyboard shortcut most users will hit. The fix is three lines and has no
dependencies.
