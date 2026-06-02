# Group 3 — Engineering Findings (V2 Audit)

## Summary of 5 engineering agents (E1–E5)

---

## Convergence themes across E1–E5

| Theme | Agents | Severity |
|---|---|---|
| `tool_logEncounter` writes `{"version":1}` envelope key; SchemaEnvelope decodes `schemaVersion` — every MCP encounter silently discarded | E3 | 🔴 Critical data corruption |
| `FeatureGate.isEnabled()` called zero times in non-Monetization code — zero gating in production | E5, P2 | 🔴 Critical |
| `RelationshipPromptLibrary` has zero callers in the entire codebase | E1 | 🔴 Dead code |
| `QuickEncounterSheet.saveIfValid()` double-fires on Return (onSubmit + keyboardShortcut) — duplicate encounter records | E1 | 🔴 Data integrity |
| `scheduleCheckIn` dedup guard returns early if notification exists — stale fire dates never updated | E4, D4 | 🔴 Notification reliability |
| `insertPerson()` never writes `relationship_type` or `check_in_cadence_days` to SQLite — Phase D data silently lost on index rebuild | E2 | 🟠 High |
| `isPro` reads from UserDefaults — trivially bypassed with `defaults write` | E5 | 🟠 High |
| No `Transaction.updates` listener — background purchases/renewals never register | E5 | 🟠 High |
| Birthday notifications inside 7-day horizon guard — ~80% of users never get them | E4 | 🟠 High |
| `deletePerson` never cancels birthday notifications (`repeats: true`) — ghost birthday reminders forever | E4 | 🟠 High |
| `PersonDTO` memberwise init omits `relationshipType` and `checkInCadenceDays` | E1 | 🟡 Medium |

---

## E1 — New Code Quality
**Critical issues:** (1) `saveIfValid()` double-save via both `onSubmit` and `keyboardShortcut(.return)`. (2) `RelationshipPromptLibrary` — zero callers. (3) `PersonDTO` memberwise init missing Phase D fields.
**Additional:** N+1 notification scheduling (pending fetch per person), DST arithmetic via raw `86400`, `registerCategories()` closure actor boundary (Swift 6 failure risk).
**Priority:** `isSaving` guard in `saveIfValid()` — prevents duplicate encounter records.

## E2 — SQLite Migration
**Key finding:** Migration is additive/safe (`ALTER TABLE ADD COLUMN`), but `insertPerson()` never writes new Phase D fields — SQLite index permanently diverges from JSON source of truth. No transaction wrapping migrations.
**Top picks:** (1) Add Phase D fields to `insertPerson()`. (2) Wrap migrations in transactions. (3) Add `SecondBrainDB` migration tests.
**Priority:** `insertPerson()` fix — data silently lost every time the index rebuilds.

## E3 — MCP Tool Implementation
**CRITICAL BUG:** `tool_logEncounter` writes `{"version": 1, "data": enc}` but the decode path uses `schemaVersion` key — every encounter logged via MCP is silently discarded by the app. One-word fix.
**Additional:** O(n×m) I/O in `listOverdueCheckIns` (100 people × all encounter files per person). Epoch-zero `createdAt` fallback flags legacy contacts as 20,000 days overdue.
**Priority:** Fix envelope key mismatch — critical data corruption.

## E4 — Notification Reliability
**Key bugs:** (1) Stale dedup guard — fire dates never updated after logging. (2) Birthday reminders inside 7-day horizon guard — most users never scheduled. (3) `deletePerson` doesn't cancel `repeats: true` birthday notifications.
**Top picks:** (1) Remove-then-re-add when computed fire date differs. (2) Move birthday scheduling outside horizon guard. (3) Add `cancelPersonNotifications(id:)` to delete path.
**Priority:** Stale dedup fix — makes `syncPersonReminders` idempotently correct instead of idempotently wrong.

## E5 — StoreKit Completeness
**Key gaps:** (1) No `Transaction.updates` listener — background purchases never register. (2) `isPro` from UserDefaults — trivially bypassed. (3) Zero `isEnabled()` calls outside Monetization/.
**10-step checklist to ship real purchase:** See E5 findings file for full list.
**Priority:** Add `Transaction.updates` listener in `startServices()` + wire ProPaywallView sheet.

---

## Top 5 Engineering findings

1. **`tool_logEncounter` envelope key mismatch** (E3-N1) — silent data corruption on every MCP write
2. **`scheduleCheckIn` stale dedup** (E4-1) — correct fire dates never written for existing notification holders
3. **`insertPerson()` drops Phase D fields** (E2-R2) — SQLite index diverges from JSON truth on every rebuild
4. **`saveIfValid()` double-fires on Return** (E1-N1) — duplicate encounter records on every keyboard-enter save
5. **No `Transaction.updates` listener** (E5-1) — background purchases + renewals never received
