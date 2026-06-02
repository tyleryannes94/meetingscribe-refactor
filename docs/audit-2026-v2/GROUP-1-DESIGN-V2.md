# Group 1 — Design Findings (V2 Audit)

## Summary of 5 design agents

---

## Convergence themes across D1–D5

### 🔴 CRITICAL: Multiple Phase 1–2 features were planned but never fully wired

**ALL 5 agents independently found that key Phase 1–6 deliverables are either missing or broken:**

| Finding | Agents | Severity |
|---|---|---|
| `AddPersonSheet` has NO `RelationshipType` picker — every person created gets `.unset` | D1, D2, D5 | 🔴 Critical — breaks entire Phase 2 habit loop |
| `ProPaywallView` is defined but never presented — FeatureGate.paywallFeature has no sheet binding anywhere in the app | D1, D2, D3 | 🔴 Critical — zero monetization works |
| `FeatureGate.LOG_NOW` notification action has no handler — deep-link silently no-ops | D4 | 🔴 Critical — habit loop broken |
| `healthScore` ManagedFeature exists but the arc ring UI is 0% implemented | D5 | 🔴 Critical — paywall promises a non-existent feature |
| `syncPersonReminders()` never called on app launch — only called from QuickEncounterSheet | D2, D4 | 🟠 High — notifications fire only if user has already used QuickEncounterSheet |

---

## D1 — UI Code Quality
**Top picks:** (1) QuickEncounterSheet's "auto-save on kind tap" promise is broken — KindChip only toggles state, never calls saveIfValid(). (2) ProPaywallView has no host — zero sheet presentations found across all Sources/. (3) AddPersonSheet missing RelationshipType picker means every user starts with .unset and sees no coaching features.
**Priority:** Wire `ProPaywallView` presentation first — one `.sheet(item:)` modifier unblocks the entire monetization layer.

## D2 — Onboarding
**Top picks:** (1) Onboarding wizard has zero mention of relationship types/coaching — the app's most differentiated feature is invisible on first run. (2) No "what's new" screen for upgrading users. (3) TodayView cold-start empty state is meeting-centric with no prompt to add relationships.
**Priority:** Call `syncPersonReminders()` on app launch — currently silently skipped, meaning notifications never fire for any user.

## D3 — Visual Design
**Top picks:** (1) `RelationshipType.colorName` is a dead stub — the color assets don't exist and no view reads the property — every consumer improvises its own color. (2) KindChip/MoodChip bypass NDS tokens entirely (hardcoded corners, colors). (3) ProPaywallView uses 5+ hardcoded literal colors where `NDS.brand`/`NDS.palette` exist.
**Priority:** Add `RelationshipType.color: Color` backed by NDS.palette — one property kills all hardcoded relationship colors downstream.

## D4 — Notifications
**Top picks:** (1) `LOG_NOW` action registered but never handled — UNUserNotificationCenterDelegate has `default: break`. (2) All notification body copy is static and generic — doesn't mention days-since-contact. (3) `romanticPartner` defaultCheckInDays=1 with no frequency floor = daily notifications guaranteed to be disabled within a week.
**Priority:** Wire `LOG_NOW` to open `QuickEncounterSheet` for the specified personID — the entire habit loop hinges on this.

## D5 — Health Score
**Top picks:** (1) Arc ring UI is 0% built — not in PersonDetailView, no algorithm, no placeholder. (2) Need `Person+ConnectionStrength.swift` with exponential recency decay + 90-day consistency + depth signals. (3) Free vs Pro tier should be dot (free) vs arc ring (pro), not grayed-out.
**Priority:** Build `connectionStrength(encounters:) -> Double` algorithm first — it's the dependency for all other health score items and takes <80 lines.

---

## Top 5 Design findings across the whole group

1. **ProPaywallView never presented** (D1-N2) — zero monetization works until wired
2. **AddPersonSheet missing RelationshipType picker** (D1-N3/D2-2) — collapses Phase 2 habit loop for all new users
3. **LOG_NOW notification action silently no-ops** (D4-2) — the primary habit-formation mechanism is broken
4. **Health score 0% implemented** (D5-02) — paywall promises a non-existent feature
5. **RelationshipType.colorName is a dead stub** (D3-1) — design system gap exposes ad-hoc colors across all new components
