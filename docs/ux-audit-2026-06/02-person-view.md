# UX Audit — Person Detail View & People

*Agent: person-view designer. Scope: `PersonDetailView.swift` (~3040 lines), `PeopleListView.swift`, `QuickEncounterSheet.swift`, `AddPersonSheet.swift`, `TagPicker.swift`, `RelationshipHealth.swift`, `PeopleStore.swift`, `MessagesAnalyzer.swift`.*

## P0
- **Information overload.** The fixed 300pt identity pane stacks 7 sections (identityPanel, insight card, tags, contact rows, relationships, encounters, photos) AND the work area has 6 tabs (overview/story/meetings/tasks/messages/notes), each deep. `PersonDetailView.swift:501-517,288-300`. → Collapse identity pane to a sticky header (avatar + name + 1 CTA + ⋯ menu); reduce 6 tabs → ~3 (Overview/Meetings/Notes; fold Story into Overview).
- **Tag add is 4 clicks behind a hidden Menu → popover → alert.** `tagsEditSection:1057-1092`. The **Favorites** section (`:1135-1140`) is the right pattern: an inline TextField + Add. → Inline tag TextField; Enter creates+adds.
- **Two confusing "add encounter" buttons** — "Encounter" in identityPanel (`:881`) and "Add" in encountersSection header (`:1674`), both opening the same sheet. → Consolidate to one "Log encounter".

## P1 — the engagement bug (user-reported)
- **`lastInteractionAt` ignores texts/SMS.** It's bumped only by encounters (`PeopleStore.swift:651-654`). The iMessage signal (`recomputeStrength` ~`:1280-1303`) only lowers `daysSince` for the **strength score**, not `lastInteractionAt`. So the "overdue by N days" insight (`PersonDetailView.swift:558-565`) and badge show stale dates — a person you text daily reads as "91 days overdue". → In `recomputeStrength`, if iMessage `lastDate > lastInteractionAt`, bump + persist it; in `relationshipInsight`, use the more-recent of encounter vs text; call `refreshIMessageSignals()` on `onAppear` (`:378`).
- **Blended cadence:** when texting is frequent (last30 ≥ 10), assume ~weekly cadence rather than the encounter-derived one.
- Identity-pane action buttons (8 across 2 FlowLayouts, `:852-895`) — collapse to "Brief Me" + ⋯ menu; promote "Log check-in" to primary.

## P2 / P3
- Inline edit mode lacks a form background/visual cue (`:783-836`); move Save/Cancel beside the fields.
- "In common" co-attendees buried in Overview (`:1941-1973`) → promote near Relationships.
- Message analysis scattered across messagesSection/analysisPresetMenu/analyzePopover/deepAnalysisControl (`:2370-2872`) → one "Analyze" card (presets as pills + range + Run + result; Quick/Deep toggle).
- AI-suggested tag chips have tiny "+" targets (`:1195-1199`) — bigger, with accepted-state checkmark.
- People list sort (recent/name/meetings/newest) is hidden in AppStorage (`PeopleListView.swift:43-82`) → visible Sort menu.
- QuickEncounterSheet: show last 3 encounter kinds / highlight most-used (`:139-150`).
- Health badge popover → add a contextual "Call/Email <name>" action (`:940-960`).

**Key finding:** the iMessage integration is *partial* — recency feeds the score but not `lastInteractionAt`, which is the biggest credibility issue (overdue dates look wrong).
