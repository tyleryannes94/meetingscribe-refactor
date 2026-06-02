# Group 4 — End-User Persona Findings Summary
> 5 agents: U1 Partner · U2 Family · U3 Friend · U4 Meeting-First · U5 Conflict/Repair
> Date: 2026-06-02

## Convergence — ALL 5 personas independently raised the same issues

| Theme | Agents | Signal |
|---|---|---|
| `Person` has NO `relationshipType` field — partner/family/friend all get identical CRM treatment | U1, U2, U3, U4, U5 | 🔴 Perfect convergence across every persona |
| Encounter logging too high friction — "event name" required, 5-step sheet, no `kind` picker | U1, U2, U3, U5 | 🔴 Kills the daily logging habit |
| Zero push notifications for relationship maintenance (drift, birthday, check-in) | U1, U2, U3, U5 | 🔴 The habit loop exists only when user opens the app |
| AI preamble hard-codes "adult professional" for ALL analysis presets including sentiment/emotional | U1, U5 | 🟠 Unsafe framing for intimate relationship analysis |
| Auto-extraction post-recording is completely invisible — no banner, no signal | U4 | 🟠 Pipeline works, nobody knows it exists |
| "Add N attendees to People" batch button creates records silently, no follow-through | U4 | 🟡 Wasted conversion moment |

## Top Picks Per Persona

**U1 (Partner):** U1-1 — `relationshipType` enum on `Person` (S, root unlock). U1-3 — Per-person check-in cadence + `RELATIONSHIP_CHECKIN` notification category. U1-5 — Quick-log encounter widget with kind picker + mood (drops friction 5→1 step).

**U2 (Family):** U2-3 — Per-person drift push notification via `UNCalendarNotificationTrigger` (M, the only thing that works when user isn't thinking about the app). U2-1 — `PersonCategory` enum (S). U2-2 — Encounter type field + quick-log (phone call logging currently requires filling "Purple Party 2026" style event name field).

**U3 (Friend portfolio):** U3-3 — One-tap kind strip for encounter logging (coffee/call/dinner/text — S/M, kills data starvation). U3-4 — `FRIEND_DRIFT` push notification category (M). U3-1 — `PersonType` enum (S, prerequisite for everything).

**U4 (Meeting-first):** U4-3 — Pre-populate "Met at: [meeting]" memory when chip creates new person + "what's this relationship?" prompt (S/M, highest leverage moment). U4-2 — Post-recording "Found N people" dismissible banner (extraction pipeline works, zero visibility). U4-5 — "Ask AI about this attendee" right-click chip action (10 lines, connects two working systems).

**U5 (Conflict/repair):** U5-1 — Relationship privacy tier + `relationshipType` enum (pre-condition for everything). U5-3 — Relationship-type-aware AI preamble — fix `PersonDetailView.swift:84` hard-coded "adult professional" for intimate relationships (S, 30 lines). U5-4 — "Difficult conversation" encounter shortcut with mood field + journal prompts (S, no AI required).

## Critical Code Framing Issue (U5 + D5)
**`sentimentTrends` analysis at `PersonDetailView.swift:104–111`** renders a verdict of "warm / tense / neutral" with no context, no path forward, and clinical language. For a user processing a relationship conflict, this reads as the app judging their relationship rather than supporting reflection. **Fix: reframe as "moments of connection vs distance" with a forward-looking prompt.**

## Single Highest-Priority Recommendation (Persona Group)
**Encounter quick-log (U3-3/U1-5)** — a one-tap kind strip (call/coffee/dinner/quality time/difficult conversation) that replaces the 5-step "event name" form. Every persona's logging habit depends on this being frictionless. An app that requires a calendar-event-style form to log "had dinner with my partner" will never build a daily practice.

## Detail Files
- `findings/U1-partner-user.md`
- `findings/U2-family-user.md`
- `findings/U3-friend-user.md`
- `findings/U4-meeting-first.md`
- `findings/U5-repair-user.md`
