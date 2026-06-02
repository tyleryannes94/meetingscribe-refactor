# Group 2 — Product Findings (V2 Audit)

## Summary of 5 product agents (P1–P5)

---

## Convergence themes across P1–P5

| Theme | Agents | Severity |
|---|---|---|
| `FeatureGate.isEnabled()` called ZERO times outside Monetization/ — everything free forever | P2, P5, E5 | 🔴 Critical |
| `RelationshipPromptLibrary` has zero callers — Phase 3's primary feature is dead code | P1, P2 | 🔴 Critical |
| `syncPersonReminders()` never called on app launch — notifications never fire for most users | P3, D2, D4 | 🔴 Critical |
| `StayConnectedSection` caps at 3 with no "See all" — 17+ overdue people invisible | P5, D1 | 🟠 High |
| No variable reward after logging encounter — Hooked model breaks at step 3 | P3, P1 | 🟠 High |
| Habit loop requires 5–6 steps from menubar; no check-in surface in menubar popover | P3 | 🟠 High |
| `log_encounter` MCP tool accepts freeform `kind` with no enumeration — garbage in | P4, E3 | 🟡 Medium |
| No MCP `prompts` capability — Claude has no workflow orchestration for coaching | P4 | 🟡 Medium |

---

## P1 — Relationship Coach Completeness
**Top picks:** (1) Personalize `weeklyPrompt(for:)` based on encounter history — mood tags stored as strings, never parsed back for personalization. (2) 24h follow-up notification after a tense/hard mood encounter. (3) Conflict debrief preset in `ConversationAnalysisPreset` for recent hard encounters.
**Priority:** Prompt personalization — turns static strings into a responsive coach with zero AI cost.

## P2 — Monetization Wiring
**Key finding:** Zero `isEnabled()` calls outside Monetization/. `ProPaywallView` has no `.sheet(item:)` binding in any view. `unlimitedPeople`, `checkInNotifications`, `relationshipContent` — all freely accessible.
**Top picks:** (1) Wire `ProPaywallView` sheet in MainWindow — one modifier. (2) Flip `overrideAllEnabled` default to require explicit opt-in. (3) Wire `weeklyPrompt` into PersonDetailView behind Pro gate.
**Priority:** Sheet binding for ProPaywallView — activates entire monetization layer.

## P3 — Habit Loop
**Key finding:** Fails all 4 Hooked model stages. No reward after save, no menubar quick-log, no re-engagement for lapsed users.
**Top picks:** (1) Overdue people + quick-log in MenuBarView popover (2-tap access). (2) Post-meeting "who did you see?" anchor prompt. (3) Post-save animation + running count (variable reward).
**Priority:** MenuBarView overdue quick-log — the app is menubar-first; the habit loop must live there.

## P4 — MCP Coaching Quality
**Key finding:** Tools return data dumps without orchestration. No MCP `prompts` capability. Framework fields return labels not playbooks.
**Top picks:** (1) Add MCP `prompts/list` + `prompts/get` with 3 workflow templates. (2) Replace framework string with structured object (principle + questions). (3) Include `memories` in `get_coaching_context`.
**Priority:** MCP `prompts` capability — without workflow orchestration, all other tool improvements remain ad-hoc.

## P5 — Scale
**Key finding:** `unlimitedPeople` gate never enforced. No triage/priority algorithm. Encounter list has no pagination.
**Top picks:** (1) Enforce `unlimitedPeople` in AddPersonSheet.save() with paywall trigger. (2) `RelationshipPriorityEngine` weighting by type + overdue days + mood. (3) "Top 3 + N more overdue" disclosure in StayConnectedSection.
**Priority:** Enforce the people limit — the gate infrastructure exists but is wired to nothing.

---

## Top 5 Product findings

1. **Zero isEnabled() calls in production code** (P2) — the entire monetization model is inert
2. **RelationshipPromptLibrary is dead code** (P1, P2) — Phase 3's centerpiece feature unreachable
3. **No menubar check-in surface** (P3) — habit loop impossible for a menubar-first app
4. **log_encounter silently writes corrupt envelope key** (E3/P4) — MCP writes discarded by app
5. **No MCP prompts capability** (P4) — Claude can't orchestrate multi-tool coaching workflows
