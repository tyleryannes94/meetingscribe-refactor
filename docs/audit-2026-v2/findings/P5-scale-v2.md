# P5 — Multi-Relationship Scale UX

**Lens: Multi-relationship management at scale — does the UX hold up with 20 people across 4 relationship types?**

---

## Full-app audit through this lens

### Q1 — Is `FeatureGate.unlimitedPeople` actually enforced anywhere?

**Answer: No. The gate is a dead flag.**

`FeatureGate.swift` defines `unlimitedPeople` (line 26: `case unlimitedPeople`) and `isEnabled(.unlimitedPeople)` returns `false` for free users (line 80). But a grep of every file under `Sources/` turns up **zero call sites** for `FeatureGate.shared.isEnabled(.unlimitedPeople)` or `isEnabled(.unlimitedCheckIns)`. Neither `PeopleListView.swift`, `AddPersonSheet.swift`, nor `PersonDetailView.swift` call `FeatureGate` at all. `ProPaywallView.swift` references the case in a display string (line 104) but is never presented from any of these views — `ProPaywallView` has no `.sheet` binder connected to PeopleListView or AddPersonSheet.

In DEBUG, `overrideAllEnabled = true` (FeatureGate.swift:52) would bypass the check anyway, but the check simply does not exist. A free user can add person 6, 7, 50 — the gate does nothing.

Additionally, `FeatureGate.paywallFeature` is only ever set from `StoreKitManager.showPaywall()` (StoreKitManager.swift:64), which is itself never called from any people-management surface.

### Q2 — `StayConnectedSection` caps at 3: what happens to people 4–17?

**Answer: They are silently dropped. There is no "See all" affordance.**

`StayConnectedSection.swift` line 14–20:
```swift
.prefix(3)
.map { $0 }
```
The computed property `overdueRelationships` hard-applies `.prefix(3)` before the view renders. With 17 overdue people, 14 are invisible. The `body` has no "See all overdue" link, no count badge ("17 overdue"), and no navigation hook into the People tab filtered by overdue state. `TodayView.swift` also puts `StayConnectedSection` well down the feed scroll (after follow-ups, commitments, decisions, on-this-day, recent notes) — it may be off-screen entirely for most Today visits.

### Q3 — `PersonDetailView` encounter list: pagination or virtualization?

**Answer: Neither. Raw `ForEach` over the full unbounded encounter set.**

`PersonDetailView.swift` line 1188:
```swift
ForEach(mine) { e in EncounterRow(encounter: e) { people.deleteEncounter(e) } }
```
`mine` is `people.encounters(for: current.id)` — the full unsorted array. No `.prefix()`, no `List` with lazy loading, no pagination, no "show more" button. A power user logging every coffee, call, and text exchange could accumulate 50–100 encounters; the view renders all of them synchronously on the main thread. (For comparison, the meeting backlinks section does use `.prefix(30)` at line 1015, but encounters get none.)

### Q4 — The `presentTypes` filter: the "first family member" UX trap

**Answer: The filter chips disappear exactly when you need them most.**

`PeopleListView.swift` lines 55–58:
```swift
private var presentTypes: [RelationshipType] {
    let used = Set(people.people.map(\.relationshipType)).subtracting([.unset])
    return RelationshipType.allCases.filter { used.contains($0) }
}
```
And the chips are conditionally rendered only when `presentTypes.count > 1` (line 201). So:
- If you have zero typed people, no chips appear.
- If all your people are one type, no chips appear.
- If you want to add your first "family" person and mentally pre-filter the list to context-check, the chip for "Family" does not exist yet.

This is a discovery/intent problem: the filter is reactive (shows only what exists) but users think of relationship types prospectively ("I want to see my family group").

### Q5 — Priority/triage with 5 partner + 8 family + 7 friends all overdue

**Answer: No prioritization algorithm. The app offers a single sort: overdue days descending.**

`StayConnectedSection.swift` line 17:
```swift
.sorted { overdueDays($0) > overdueDays($1) }
```
That is the only triage signal: raw days overdue. There is no weighting by:
- Relationship type (a romantic partner 5 days overdue arguably outranks a friend 30 days overdue)
- Relationship health score (gated behind `ManagedFeature.healthScore`, itself unimplemented)
- Upcoming birthdays
- Last encounter sentiment (Mood enum exists in QuickEncounterSheet but is not read back)
- Reciprocal communication patterns

The `list_overdue_check_ins` MCP tool (`main.swift` ~line 1640) sorts purely by `overdueDays` as well. There is no cross-tool or cross-view prioritization surface.

In TodayView, `StayConnectedSection` (3 people) and `ReconnectView` (separate, "stay in touch" drift view) both appear on the same scroll, potentially showing overlapping people from different algorithms — creating visual duplication without helping the user understand priority.

### Q6 — Pro value prop at the 5-person limit

**Answer: The limit does not exist in practice; there is no upgrade trigger.**

As established in Q1, the `unlimitedPeople` gate has zero enforcement. Even if it were enforced, the paywall is never surfaced from person-add flows. `ProPaywallView` has no `.sheet(isPresented:)` binding in `PeopleListView` or `AddPersonSheet`. There is no inline "You've used 4 of 5 free relationships" progress indicator, no soft warning at person 4, and no hard block at person 5. The entire monetization arc for the CRM side of the product is inert.

---

## Existing-plan items I rank highest (through scale lens)

1. **Wire StoreKit 2 purchase** (known gap #1) — prerequisite for any gate enforcement; without it the entire P5 audit is moot
2. **`healthScore` arc UI** (known gap #3) — the single best prioritization signal; drives triage at scale
3. **`RelationshipNotificationManager.syncPersonReminders()` on app launch** (known gap #5) — at 20 people, stale notification state means the overdue list in StayConnectedSection could be wrong on every cold open
4. **`PersonDTO` memberwise init missing `relationshipType`** (known gap #7) — at scale, bulk imports via MCP tools would silently drop relationship type assignments

---

## Net-new recommendations

### P5-01 — Enforce the `unlimitedPeople` gate with a contextual upgrade trigger
**What:** In `AddPersonSheet.save()`, check `FeatureGate.shared.isEnabled(.unlimitedPeople)` against a count of people with `relationshipType != .unset`. If the user hits 5 typed people and is free, abort save and call `FeatureGate.shared.showPaywall(for: .unlimitedPeople)`. Wire `ProPaywallView` as a `.sheet` off `PeopleListView.$showAdd` or as a separate binding on `FeatureGate.shared.paywallFeature`. Add a soft "4/5 typed relationships" progress pill to the actionsRow in the sidebar.

**Why:** The gate exists architecturally but is completely bypassed. Without enforcement there is no revenue pressure and no upgrade moment.

**User value:** Creates a natural, non-annoying upgrade moment at the exact point of value realization ("I want to add my 6th important person").

**Effort:** S | **Impact:** Critical (monetization prerequisite) | **Deps:** known gap #1 (StoreKit wire)

---

### P5-02 — Replace the hard `.prefix(3)` in `StayConnectedSection` with a "Top 3 + badge" pattern
**What:** Show the 3 most-critical overdue people (using P5-03's priority score) but add a tappable "N more overdue" disclosure row at the bottom that navigates to People tab with a pre-applied overdue filter. Also add a count badge to the section header: "Stay connected (17)".

**Why:** With 20 typed relationships, the current hard cap silently buries 14 people the user is supposed to be nurturing. No affordance to discover the rest destroys the coaching value of the cadence system.

**User value:** Users can see at a glance that 17 relationships need attention; the "N more" tap gives them a quick path to the full list.

**Effort:** S | **Impact:** High | **Deps:** P5-03 (priority score), a pre-filtered People route in `WorkspaceRouter`

---

### P5-03 — Relationship-type-weighted priority score for triage
**What:** Add a `priorityScore(for person: Person, overdueDays: Int) -> Double` function (new file `RelationshipPriorityEngine.swift`) using: `overdueDays * typeWeight + birthdayBonus + healthPenalty`. Weights: `romanticPartner = 2.0`, `familyMember = 1.8`, `closeFriend = 1.5`, `friend = 1.2`, `colleague = 1.0`, `acquaintance = 0.6`. `birthdayBonus`: +50 if birthday within 14 days. `healthPenalty`: use last-encounter mood (`.tense`/`.hard` = +20 urgency). Use this score in `StayConnectedSection`, `list_overdue_check_ins` MCP, and a new "Relationship Triage" view.

**Why:** Raw overdue days treats a romantic partner 5 days overdue as less urgent than an acquaintance 30 days overdue. At 20+ relationships, the user cannot manually triage — the app must.

**User value:** The daily "Stay connected" surface shows the right 3 people, not just the longest-neglected ones.

**Effort:** M | **Impact:** High | **Deps:** none (Mood and RelationshipType already exist)

---

### P5-04 — Encounter list virtualization cap with "Show all N" disclosure
**What:** In `PersonDetailView.encountersSection`, change `ForEach(mine)` to `ForEach(mine.prefix(showAllEncounters ? mine.count : 8))` with a `@State private var showAllEncounters = false` flag and a "Show all N encounters" button when `mine.count > 8`. Reverse-sort by date so newest is first.

**Why:** `PersonDetailView.swift:1188` renders the full unbounded encounter array synchronously. A user who logs diligently for 12 months could have 80+ encounters. This causes visible list jank on scroll into the section and is unnecessary — users almost never need encounter #47.

**User value:** Detail view stays snappy even for long-term, high-cadence relationships.

**Effort:** S | **Impact:** Medium | **Deps:** none

---

### P5-05 — Static relationship-type chips: always show all 7 types
**What:** Change `PeopleListView.relationshipTypeChips` to always show all `RelationshipType.allCases` (minus `.unset`), not just `presentTypes`. Keep the `presentTypes.count > 1` guard replaced by `people.people.contains { $0.relationshipType != .unset }`. Tapping a chip for a type with zero people could display "No [Family] people yet — add one?" inline.

**Why:** `PeopleListView.swift:55–58` derives chip visibility from existing data. A user browsing their people list and thinking "let me see all my family" finds the chip absent if they have only one family member, or absent entirely if adding their first. The filter serves both navigation AND mental model — it should be stable.

**User value:** Relationship type filter becomes a consistent navigation affordance, not a reactive data echo.

**Effort:** S | **Impact:** Medium | **Deps:** none

---

### P5-06 — "Relationship Triage" weekly digest view (new surface)
**What:** A new `RelationshipTriageView` — accessible from a "Weekly review" button on TodayView or the People tab header — that renders a prioritized, grouped list of all overdue people, segmented by urgency tier: 🔴 Critical (>2x cadence overdue), 🟡 Due this week, 🟢 On track. Each tier shows all people (not capped at 3), with one-tap quick-log from each row. Include a completion metric: "You're connected with 12/20 relationships this month."

**Why:** TodayView's StayConnectedSection + ReconnectView is a point-in-time surface, not a review surface. At 20+ relationships, users need a periodic "how am I doing across all relationships?" moment — the app has no such view.

**User value:** Turns the app from a passive reminder tool into an active relationship coaching loop; users can see the full picture once a week and batch-log several encounters in sequence.

**Effort:** M | **Impact:** High | **Deps:** P5-03 (priority score)

---

### P5-07 — Overdue relationship filter route in PeopleListView
**What:** Add `RelationshipFilter.overdue` as a first-class filter option in `PeopleListView` (alongside the relationship-type chips). Accessible via: the "N more" link from P5-02, a menubar notification deep-link, and a keyboard shortcut. The filter reuses the existing `filtered` pipeline with an added `isOverdue($0)` predicate.

**Why:** Currently there is no way to view all overdue people in the People tab — only the 3-person StayConnectedSection and the unrelated ReconnectView. A user who wants to batch-review all 17 overdue relationships has no path.

**User value:** Enables "power triage mode" — open People → filter Overdue → work through the list top to bottom with quick-log.

**Effort:** S | **Impact:** Medium | **Deps:** P5-02

---

### P5-08 — Per-relationship-type cadence summary in sidebar footer
**What:** Add a compact stats footer below the people list in `PeopleListView`: "Partner: ✓ 1/1 · Family: ⚠ 3/8 · Friends: ✓ 5/7". Each segment is a tappable chip that applies the type+overdue filter combination. Computed from `people.people` in a `private var healthSummary` computed property, no new data models needed.

**Why:** With 20 people across 4 types, the user has no at-a-glance answer to "how am I doing with my family?" without manually scrolling the list. The type summary footer answers this with one visual pass.

**User value:** Ambient awareness of relationship health by type; motivates opening overdue segments.

**Effort:** S | **Impact:** Medium | **Deps:** P5-07 (overdue filter route)

---

### P5-09 — Dedup `StayConnectedSection` and `ReconnectView` on TodayView
**What:** `TodayView.swift` places both `StayConnectedSection` (overdue by cadence) and `ReconnectView` (drift by last-interaction) in the same scroll feed. These two views likely surface overlapping people since long-overdue people are also drifting. Merge them into a single `RelationshipNudgesSection` with two toggle-able tabs ("Overdue" / "Drifting") or a unified sorted list that de-dupes by person ID and picks the more urgent framing.

**Why:** Showing the same person in two separate sections with different framing is confusing at scale. It also inflates Today's visual length when the user has many relationships.

**User value:** Cleaner Today feed; single relationship action surface rather than two competing ones.

**Effort:** M | **Impact:** Medium | **Deps:** none

---

### P5-10 — Relationship type badge on overdue notifications
**What:** In `RelationshipNotificationManager.swift`, when building `UNMutableNotificationContent` for a check-in reminder, include the relationship type emoji and priority tier in the notification subtitle: "❤️ Partner · 5 days overdue" vs "👥 Friend · 12 days overdue". Use the `priorityScore` from P5-03 to set `UNNotificationContent.interruptionLevel` — partner/critical gets `.timeSensitive`, friend/acquaintance gets `.passive`.

**Why:** When 8+ notifications stack in Notification Center, the user cannot tell which relationship matters most without opening the app. Type+tier context in the notification body enables in-notification triage.

**User value:** Users can decide which check-in to act on from the lock screen without opening the app.

**Effort:** S | **Impact:** Medium | **Deps:** P5-03 (priority score), known gap #5 (sync on launch)

---

### P5-11 — Relationship type as a Pro tier anchor (free: 2 types, Pro: all 7)
**What:** Re-scope the free tier's `unlimitedPeople` gate. Instead of "5 typed relationships", gate it as: "2 relationship types free (e.g., Friend + Colleague), all 7 types require Pro." This is a stickier, more memorable limit — users hit it the moment they add a third type, not at person count 6. Show a type-count indicator in the type picker: "2/2 types used (Pro unlocks all)".

**Why:** The current 5-person limit is arbitrary and invisible (unenforced). A type-count limit is self-evident (users understand "you have 2 types") and creates an upgrade moment at a more emotionally resonant point: "I want to add my romantic partner but that's a 3rd type."

**User value:** Clearer mental model of what Pro unlocks; more compelling upgrade trigger.

**Effort:** M | **Impact:** High | **Deps:** P5-01 (gate enforcement infrastructure), known gap #1

---

### P5-12 — Batch quick-log from `StayConnectedSection` ("Log all as checked in")
**What:** Add a secondary action to `StayConnectedSection`'s header: a "Quick log all" button that opens a single confirmation sheet: "Log a check-in for all 3 overdue people?" with a shared Mood chip selector. On confirm, calls `people.addEncounter()` for each person with the selected mood and a generic note ("Checked in via batch log").

**Why:** When all 3 shown people are in the same social context (e.g., same group of friends), logging them individually requires 3 sheet open/close cycles. At 20 relationships, friction compounds.

**User value:** Reduces 3-encounter logging from ~90 seconds (3x sheet open → chip select → save) to ~10 seconds.

**Effort:** S | **Impact:** Low-Medium | **Deps:** none

---

## Top 3 picks

1. **P5-01** (Enforce `unlimitedPeople` gate + upgrade trigger) — the entire monetization model for the CRM side is inert; nothing else matters until this fires
2. **P5-03** (Relationship-type-weighted priority score) — foundational signal that feeds StayConnectedSection, MCP tools, triage view, and notifications; highest leverage single investment
3. **P5-02** ("Top 3 + N more" pattern in StayConnectedSection) — the hardest immediate UX regression at scale; silently buries 14 overdue relationships in a 3-item cap with no escape hatch

## Single highest-priority recommendation

**P5-01 — Enforce the `unlimitedPeople` gate with a contextual upgrade trigger.**

The gate is defined, the paywall view is built, the copy is written — but `FeatureGate.shared.isEnabled(.unlimitedPeople)` is called exactly zero times from any person-management surface. This means the product has no monetization lever on its CRM features at all. All other P5 scale improvements (triage, priority scoring, batch log) are table stakes for paid users but currently exist without any paywall boundary. Wire the check in `AddPersonSheet.save()`, present `ProPaywallView` via `FeatureGate.shared.paywallFeature` observation in `PeopleListView`, and add the soft "4/5 typed relationships" progress indicator — this is a half-day implementation on top of infrastructure that already exists.
