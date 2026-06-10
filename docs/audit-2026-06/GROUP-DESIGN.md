# Senior Product Designer — Compiled Group Digest

_Audit 2026-06 · MeetingScribe Refactor · 5 agents: visual-system, nav-ia, interaction, onboarding-ftux, accessibility_

## Executive Summary

MeetingScribe has unusually strong design bones for a 59K-LOC indie app: a warm "Bloom" NDS design system (coral/lilac/mint), a centralized `WorkspaceRouter`, native `NavigationSplitView` in Meetings, `scaledFont` Dynamic Type, an `NDS.motion()` reduce-motion helper, a `.minTap()` 44pt utility, and a mature `ToastCenter` undo pattern. The problem is **adoption, not architecture**. Good primitives exist but are applied inconsistently — `.minTap()` has one call site, `NDS.motion()` is used in ~6 places, two button families (Untitled* vs MS*) coexist in the same view, three tabs each implement split-view differently, and 230+ icon-only buttons ship without VoiceOver labels.

Three patterns dominate the findings:

1. **"Wire up what already exists."** The single highest-leverage cluster is finishing partially-built systems: route Today's meeting cards through the existing `WorkspaceRouter.openMeeting()`, resurrect the dead `ActionItemsViewModel`, implement the `RelationshipType.color` stub, and apply the already-defined `NDS.splitPaneTopInset` everywhere. These are S/M effort with high impact because the hard parts are done.

2. **"Systematic sweep" accessibility debt.** Icon labels, color-only status dots, `.minTap()`, and reduce-motion gating are each cited by 2-3 agents independently. They are WCAG-blocking, low-architecture, and mechanical — ideal Phase 1/2 work.

3. **Warmth + first-run cohesion.** The relationship-coach half of the app reads "clinical" (CRM eyebrow caps, no relationship-color signaling, generic system buttons in onboarding). A cluster of small typography/color/copy changes plus a guided FTUX bridge would close the gap between the warm copy intent and the cold execution.

The single connective thread is `RelationshipType.color` and `WorkspaceRouter` selection unification — each unblocks 4-6 downstream recommendations, so they should land first.

## Prioritized Recommendations

| # | Title | Type | Area | Impact | Effort | Phase | Description |
|---|-------|------|------|--------|--------|-------|-------------|
| 1 | Gate all motion through `NDS.motion()` + Reduce Motion | improvement | Design System / A11y | High | S | 1 | `NDS.motion()` exists but only ~6 call sites use it; audit every `withAnimation`/`.animation`/`.transition`, route through it with a documented 3-speed hierarchy (fast 0.15 / standard 0.22 / slow 0.35). Merges 3 agents. |
| 2 | Icon-button `.accessibilityLabel` + `.help()` sweep | improvement | Accessibility | High | M | 1 | 230+ `Image(systemName:)` buttons; many lack VoiceOver labels (PersonDetailView remove buttons, MeetingDetailHeader overflow). Reuse `.help()` strings; `NotionIconButton` is the template. |
| 3 | Pair color-only status dots with glyph + label | improvement | Accessibility | High | M | 1 | 15+ `Circle().fill(color)` status encodings (MeetingsView:331, priority pips, recording health) violate WCAG/colorblind-safe. Add 1-char glyph + `.accessibilityLabel`. |
| 4 | Consolidate button system — retire Untitled*, adopt MS* + `.minTap()` | improvement | Design System / Interaction | Med | S | 1 | Untitled* and MS* primaries coexist in the same TodayView; native `.bordered`/`.borderedProminent` drift across detail headers AND onboarding sheets. One canonical MS* family; apply `.minTap()` to icon buttons. Merges 3 agents. |
| 5 | Implement `RelationshipType.color` (NDS-backed) | improvement | Design System | High | S | 1 | Replace the dead `colorName` stub with a real `color: Color` mapping each case to NDS palette. **Unblocks recs 6, 12-15.** |
| 6 | Loading skeleton tri-state (loading/loaded/empty) | improvement | Interaction | High | M | 1 | Cold-cache detail views flash "No summary / No transcript" as if errors. Add `LoadState` enum keyed on `loadedAt`, `.redacted(.placeholder)` Bloom skeletons; reduce-motion aware. |
| 7 | Route Today cards into canonical Meetings detail via router | improvement | Nav & IA | High | S | 2 | TodayView inline expand/collapse violates the "never collapse" rule; `router.openMeeting()` already exists, just isn't called. Delete `expandedMeetingID` + `cardWithDetail` (~50 LOC). |
| 8 | Migrate ProPaywallView to NDS brand tokens | improvement | Design System | High | S | 1 | Three color leaks (`.pink/.purple` gradient, `.tint(.purple)` CTA, 6 literal bullet colors) in the monetization-critical screen. Swap to `NDS.brand`/palette. |
| 9 | Refactor magic-number top inset → shared `NDS.splitPaneTopInset` | fix | Layout / Nav & IA | Med | S | 1 | PeopleListView's `.padding(.top, 60)` doesn't match the detail pane; constant is defined but applied inconsistently, so list/detail misalign. Merges 2 agents. |
| 10 | Unify all split panes under one native `NavigationSplitView` shell | improvement | Nav & IA | High | M | 2 | Meetings uses native split; People uses `HSplitView`; Tasks uses hand-rolled HStack+divider. One shared wrapper with `@SceneStorage` sidebar state fixes drift + ⌘[ nav. |
| 11 | Add `selectedPersonID` to router; unify all person-open paths | improvement | Nav & IA | High | M | 2 | Three incompatible pathways (list state, NotificationCenter jump, dead attendee chips). Add `openPerson()` parallel to `openMeeting()`; delete the notification. |
| 12 | Cross-entity `EntityLink` open protocol on router | improvement | Nav & IA | High | M | 2 | Define `enum EntityLink { meeting/person/task/decision }` + `router.open(_:)` so every chip/row/label navigates correctly once. Fixes dead attendee chips, "From meeting" labels, decision→person. Depends on 11. |
| 13 | Attendee chip hover card + one-click "Add to People" | new-feature | Interaction / Onboarding | High | M | 2 | Attendee chips are read-only text; add debounced hover card with name/email/org + "Add to People" (routes via PersonExtractionController). Closes the 5-click Meetings→People gap. Merges 2 agents. |
| 14 | Recents rail + ⌘K quick-switcher | new-feature | Nav & IA | High | M | 2 | Track `(section, entityID, timestamp)` in router (cap 5), surface in nav rail + top of ⌘K. Cuts reopen friction 3→1 clicks for the most-repeated action. |
| 15 | Resurrect `ActionItemsViewModel` as single source of task state | improvement | Nav & IA | Med | M | 2 | 12 pieces of view-local `@State` in ActionItemsView; the ViewModel exists but is dead. Migrate + `@AppStorage`-persist filter/viewMode/groupBy across tab switches. |
| 16 | RelationshipHealth widget below identity panel | new-feature | Visual Design | High | M | 2 | For partner/family/closeFriend: days-since-check-in dot, recent sentiment, one-tap "Log a moment". The "relationship dashboard" moment that differentiates coach from contact manager. Depends on 5. |
| 17 | Post-onboarding "Setup Complete" celebration + quick-start | new-feature | Onboarding | High | M | 1 | Silent transition drops users on empty Today after 6 permission screens. Add a "you're ready" sheet (1-sentence what / 3 jobs / 30-sec nudge) before `maybeShowSetupCheck()`. |
| 18 | Auto-populate People from meeting attendees with prompt | improvement | Onboarding | High | S | 1 | After transcription, banner "Found 3 attendees — add to People?" with "Add all" using email as dedup key. Pairs with rec 13. |
| 19 | Adaptive "Next steps" progress card on Today | new-feature | Onboarding | High | M | 2 | `UserProgressTracker` (onboarded/first-recording/first-person/first-task) drives evolving guidance instead of generic empty widgets; vanishes day 7. |
| 20 | Restore month-view as Meetings list-mode toggle; delete orphaned CalendarTabView | improvement | Nav & IA | Med | M | 2 | ~500 LOC of unreachable calendar logic; `listMode` toggle already exists but `.month` case is empty. Wire month-grid to `selectedMeetingID`, delete dead file. |
| 21 | Clarify SetupCheck: required (transcription) vs optional (Ollama) | improvement | Onboarding | Med | S | 1 | Two rows imply both are required to record. Split into "Recording" (required) / "Summaries" (optional); stop users wasting 15 min on Ollama they don't need. |
| 22 | Drag-to-reorder affordance (handle + preview + drop accent) | improvement | Interaction | Med | M | 2 | Drag mechanics are wired in Action Items list/board but invisible — add hover six-dot handle, scale preview, drop-zone accent. |
| 23 | Promote user photo to hero avatar + relationship-color ring | improvement | Visual Design | Med | S | 1-2 | Photos exist but are buried in a scroll strip; render first as the 52pt avatar, add a 2pt RelationshipType.color ring for at-a-glance scanning. Depends on 5. |
| 24 | Warm typography + copy for intimate relationship types | improvement | Visual Design | Med | S | 2 | Swap CRM-style tracked caps ("FAVORITE THINGS") for lowercase journal copy ("What you love about them") when category is partner/family. Cheapest warmth lever. Depends on 5. |
| 25 | Dynamic Type: adaptive frames on fixed-size sheets + heading traits | improvement | Accessibility | Med-High | M | 2-3 | 5 sheets hard-code `.frame(w,h)` and clip at large text (Onboarding 480×480, GlobalSearch, TaskInsights). Move to minWidth/idealWidth; add `.accessibilityHeading` traits for VoiceOver skimming. |

## Top 5 Bets

The highest impact-per-effort, ordered to respect dependencies:

1. **Gate all motion + finish the accessibility sweep (recs 1-3).** Three agents independently flagged motion gating, icon labels, and color-only dots. These are WCAG-blocking, low-architecture, and mostly mechanical — the single biggest quality-and-inclusion win for the effort, and table stakes for shipping.

2. **Implement `RelationshipType.color` (rec 5).** An S-effort fill of a dead stub that unblocks the relationship-color ring, health widget, warm headers, and at-a-glance People scanning — the cheapest path to making the "coach" half feel less clinical.

3. **Route Today cards through the existing router + unify person/entity selection (recs 7, 11, 12).** `openMeeting()` already exists; extending the same pattern to people and a generic `EntityLink` makes every chip/row/label navigate correctly once, killing the "click does nothing" dead ends and the duplicate Today detail layer.

4. **Loading skeleton tri-state (rec 6).** Converts the "flash of fake-empty" on every cold tab into perceived 40-60% faster opens with a reusable Bloom skeleton language — directly improves the first impression on the app's most-used surface.

5. **Bridge onboarding into first value (recs 17, 18).** A "you're ready" celebration plus a one-tap attendee→People prompt closes the silent drop-off after 6 permission screens and the 5-click Meetings→People chasm — turning setup completion into the first productive action.

---

_Carried from prior plans (high-confidence continuations): recs 1, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 16, 20, 22-25. Net-new this cycle: recs 2, 3, 12, 13, 17-19, 21 and the keyboard-focus / heading-hierarchy / a11y-test-process items folded into the accessibility cluster._
