# Group 1 — Design Findings Summary
> 5 agents: D1 IA/Nav · D2 Onboarding · D3 Visual · D4 Check-ins · D5 Accessibility
> Date: 2026-06-02

## Convergence (themes 3+ agents independently raised)

| Theme | Agents | Signal |
|---|---|---|
| `Person` model has NO `relationshipType` field — partner/family/friend are structurally identical | D1, D2, D3, D4 | 🔴 CRITICAL — all downstream type-path features blocked by this |
| Zero per-person push notification / check-in reminder infrastructure | D4, D2, D5 | 🔴 The only habit driver that works outside the app |
| Onboarding never mentions People / relationship coach angle | D2, D1 | 🟠 Every user misses the app's deepest differentiator |
| People views are clinical CRM, not warm relationship app | D3, D4, D5 | 🟠 Emotional design entirely absent |
| 32 hardcoded font sizes in PersonDetailView bypass scaledFont | D5 | 🟡 WCAG 1.4.4 failure |

## Top Picks Per Agent

**D1 (IA & Nav):** D1-1 — Add `PersonCategory` enum to `Person` model (S effort, unlocks everything). D1-6 — Type-stratified reconnect nudges with per-type thresholds. D1-5 — Relationship Health section with Gottman prompts.

**D2 (Onboarding):** D2-1 — Relationship-coach splash screen at end of onboarding (S). D2-2 — `relationshipType` field in `AddPersonSheet`. D2-6 — Guided first-person add with 3 large relationship-type tap targets.

**D3 (Visual):** D3-2 — `RelationshipCategory` enum with per-type color/icon (M). D3-1 — Promote photos to hero avatar position (S). D3-7 — Emotional health widget at top of PersonDetailView for intimate contacts.

**D4 (Check-ins):** D4-2 — Per-person `UNCalendarNotificationTrigger` check-in scheduler (the only habit driver that works when user is NOT in app). D4-1 — Inline quick check-in field (drops friction 5→2 steps). D4-3+D4-7 — Encounter `kind` enum + relationship type on Person (foundational).

**D5 (Accessibility):** D5-2 — Fix 32 hardcoded font sizes in PersonDetailView (Dynamic Type, WCAG 1.4.4). D5-5 — Reframe AI sentiment analysis copy from clinical to observational/non-judgmental. D5-1 — VoiceOver labels on ~40 unlabeled interactive elements in People.

## Key Structural Findings (file:line)
- `Sources/MeetingScribe/People/Person.swift` — no `relationshipType`, no `desiredCheckInCadence` field anywhere
- `Sources/VaultKit/Person.swift` — VaultKit model also has no relationship type
- `Sources/MeetingScribe/UI/OnboardingSheet.swift` — no mention of People module
- `Sources/MeetingScribe/People/PersonDetailView.swift:1918` — encounter log is a 5-step sheet; memory add is 2-step inline (line 1334) — huge friction gap
- `Sources/MeetingScribe/People/SuggestedPeopleView.swift:84` — "Stay in touch" nudge exists only as in-app widget, never generates push notification
- `Sources/MeetingScribe/UI/NotionDesign.swift` — NDS color tokens are warm (cream/purple) but no per-relationship-type differentiation
- `PersonDetailView.swift` — 32 hardcoded `.font(.system(size:))` calls bypass scaledFont

## Single Highest-Priority Recommendation (Design Group)
**Add `PersonCategory` / `relationshipType` enum to `Person` model immediately.** This is a 2-hour Swift model change (+ VaultKit mirror) that unlocks every downstream feature: type-specific check-in cadences, per-type notification thresholds, UI differentiation, content frameworks, MCP tools, and onboarding flows. Without it, none of the relationship-coach features can be built in a principled way. It is the prerequisite for 80% of Phase 1–4 work.

## Detail Files
- `findings/D1-nav-ia.md`
- `findings/D2-onboarding.md`
- `findings/D3-visual.md`
- `findings/D4-checkins.md`
- `findings/D5-accessibility.md`
