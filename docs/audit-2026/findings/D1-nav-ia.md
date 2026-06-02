# D1 — UX Information Architecture & Navigation Audit
**Sub-lens: People tab relationship-type navigation, context-switching between partner / family / friend views, and overall nav structure**
**Date:** 2026-06-02
**Auditor:** Nav-IA specialist (D1 prefix)

---

## Lens statement

This audit evaluates how a user who maintains a romantic partner, a parent, and three close friends experiences the People module. The core question is: does the app give each relationship *type* a distinct, appropriately-weighted navigation path? Can the user mentally "enter the partner context" or "enter the family context" with confidence that the UX will match the emotional register of that relationship? Does the nav rail and routing architecture support that, or does it route everyone through the same undifferentiated CRM list?

---

## Full-app audit through a nav-IA / relationship-type lens

### Nav rail (`MainWindow.swift:9–36`)

The top-level rail has five sections: Today, Meetings, People, Tasks, Voice Notes, grouped under WORKSPACE and ORGANIZE. "People" is a single undifferentiated entry — there is no sub-section for partner, family, or friends. A user with 400 contacts, 1 partner, 2 parents, and 5 close friends enters the exact same list view as a user with 400 professional contacts. The nav rail treats all relationship types as equivalent. There is no affordance to jump directly to "my partner" or "family members" from the rail.

The rail does not support section badges or counts (e.g., "3 people need a check-in"), which means temporal nudges have to live downstream in Today or PeopleInsightsView. That is a reachability gap for relationship-type-specific check-ins.

### People list (`PeopleListView.swift:68–130`)

The list is filtered by **tags** (AND-semantic chip row, `tagFilters`) and **search query**. Tags are shared with the meeting namespace — they are event tags like "Purple Party 2026", not relationship-type tags. There is no first-class filter for relationship *type*. A user would have to manually create tags named "Partner", "Family", "Friend" and apply them — a discoverable workaround, but not an intentional design.

`PersonRow` (`PeopleListView.swift:524–557`) shows: name, role/company subtitle, last-interaction recency. There is no visual signal for relationship type. A partner, a parent, and a coworker look identical in the list row. There is no icon, color, or badge difference.

The empty detail pane defaults to `PeopleInsightsView` (`PeopleListView.swift:462–471`) which shows: Reconnect cards, upcoming birthdays, and Most Active. These are generic CRM insights, not relationship-type-aware. "Reconnect" is valuable but treats all lapsed contacts identically — the urgency of not texting your partner for 45 days is categorically different from not emailing a loose acquaintance.

`PeopleSort` (`PeopleListView.swift:475–494`) offers: recent, name, meetings, newest. No sort by relationship type or relationship closeness.

### Person model (`Sources/MeetingScribe/People/Person.swift:77–185`)

**There is no `relationshipType` field on `Person`.** The model has:
- `relationships: [Relationship]` — directed graph edges to *other people*, not a classification of the person's type from the user's perspective.
- `Relationship.label: String` (line 57) — freeform ("spouse", "manager", "kid", "friend") but this is an edge label in a person-to-person graph, not a classification of the record itself.
- `tagIDs: Set<String>` — could be abused as type classifier, but is structurally shared with event tags.
- `importSources: Set<String>` — provenance, not type.

The `Relationship` struct at `Person.swift:51–64` is the closest thing to type-awareness, but it models *connections between people*, not "what is this person to me." There is no `PersonRelationshipType` enum, no `myRelationshipTo: RelationshipType` field, and no codable storage for it.

**VaultKit's `Person` model (`Sources/VaultKit/Person.swift:9–47`) is even leaner** — just id, name, emails, company, role, notes, tags. No relationship type of any kind. The VaultKit model is the MCP-facing interface, so Claude via MCP has zero signal about relationship type.

### Person detail (`PersonDetailView.swift:151–306`)

The detail view is a single scrollable page with a horizontal section-jump rail:
Tags | Contact | Suggestions | Relationships | Encounters | Meetings | Tasks | Notes | Messages.

The section order and content are identical regardless of whether the person is a romantic partner, a parent, or a work colleague. There is no type-path branching. The view does not adapt to relationship type.

The "Relationships" section (`PersonDetailView.swift:248–250` references `relationshipsSection`) is a graph-edge display — who this person is connected to in the network — not a "how I relate to this person" coaching section.

The AI analysis presets (`ConversationAnalysisPreset`, `PersonDetailView.swift:23–148`) are: Summarize relationship, Sentiment & trends, Topics & themes, Communication style, Pending action items, Custom. These are generic message-analysis presets. None of them are type-aware — there is no "Gottman check-in" preset for a partner, no "attachment pattern" analysis for a family member, no "friendship maintenance" template for a close friend.

The prompt preamble at `PersonDetailView.swift:86–91` hard-codes "Tyler" and frames every analysis as "adult professionals" — which is accurate for work contacts but tonally wrong for a partner or parent.

### TodayView (`TodayView.swift:93–97`)

`ReconnectView` appears in the Today feed but is a generic "haven't talked to X in N days" list — not filtered or weighted by relationship type. A lapsing conversation with a spouse and a lapsing conversation with a business contact receive equal visual treatment.

`SuggestedPeopleView` appears below meetings in Today but has no relationship-type context.

### WorkspaceRouter (`WorkspaceRouter.swift:1–94`)

Routing to a person (`openPerson`) posts a notification with a person ID; `PeopleListView` selects that person. There is no routing concept for "open in partner mode" or "open check-in flow for partner." The router has no type-awareness. Deep links and search results open all people identically.

### PeopleInsightsView (`PeopleInsightsView.swift:15–169`)

The insights panel (shown when no person is selected) has three buckets: Reconnect (45-day cutoff, line 76), Upcoming birthdays (30-day window, line 86), Most active (by encounter count, line 99). None of these are type-stratified. There is no "Partner check-in" or "Family" section. A partner who hasn't been logged in 45 days sits in the same "Reconnect" list as any other contact.

---

## Existing plan items I endorse most strongly (through this lens)

| ID | Plan item | Why it matters for relationship-type nav | Priority |
|---|---|---|---|
| PPL-1 | Inline identity-panel editing | Inline editing is prerequisite for adding a relationship-type field without a disruptive modal — makes type assignment frictionless | High |
| PPL-3 | Tag chips tappable to filter list | If relationship types land as a first-class filter (D1-2), this pattern is the implementation blueprint | High |
| TDY-1 | "Up next" hero strip | The hero strip is the right place to surface a "partner check-in reminder" for close relationships | Medium |
| NAV-4 | Move app shell to NavigationSplitView | A real sidebar enables relationship-type sub-sections (D1-3) without hacking the tag chip row | Medium |

---

## NET-NEW recommendations

### D1-1 — Add `PersonCategory` enum and `category` field to `Person`

**What:** Add a first-class `PersonCategory` enum (`partner`, `family`, `closeFriend`, `friend`, `colleague`, `acquaintance`, `other`) to `Sources/MeetingScribe/People/Person.swift`. Store it as a codable field with default `.other`. Mirror it in `Sources/VaultKit/Person.swift` so the MCP server can read and write it.

**Why:** Every type-path feature downstream (D1-2 through D1-8) requires this field. Without it, all relationship intelligence is tag-heuristics. The `Relationship.label` field (Person.swift:57) is a graph edge — it does not classify the record itself.

**How:** `enum PersonCategory: String, Codable, CaseIterable { case partner, family, closeFriend, friend, colleague, acquaintance, other }`. Add `var category: PersonCategory = .other` to the struct. Tolerant decoder default: `.other`. Expose in `AddPersonSheet` as a segmented control or picker at the top of the form, above Name.

**Effort:** S. **Impact:** Unlocks all downstream type-path features.

---

### D1-2 — Relationship-type filter strip above the People list

**What:** Replace (or augment) the current tag chip row in `PeopleListView` with a primary filter strip showing `PersonCategory` values as persistent chips above the tag chips. "All | Partner | Family | Close Friends | Friends | Colleagues". Selecting a category filters the list AND changes the list header to match ("Your Partner", "Family", etc.).

**Why:** Currently a user has no way to quickly see only their close relationships. The tag chip row (`PeopleListView.swift:422–449`) is the right pattern — extend it up one level. A user managing a partner + parents + 3 close friends should be able to press "Partner" and see exactly one person in a deliberately intimate UI context.

**How:** Add `@State private var categoryFilter: PersonCategory? = nil` alongside `tagFilters`. Apply in `filtered` computed property. Category chips live above tag chips in `sidebar`. When `categoryFilter == .partner` and exactly one person matches, auto-select them.

**Effort:** S (once D1-1 lands). **Impact:** The single highest-value navigation change for multi-relationship users.

---

### D1-3 — Relationship-type sub-sections in the nav rail (or sidebar header)

**What:** When the user is in the People tab, the sidebar header ("People") should show a secondary nav: "All People | Close Relationships | Professional". Tapping "Close Relationships" shows only `partner + family + closeFriend` categories. This is a different UX register — intimate, not CRM.

**Why:** The nav rail has no way to enter an "intimate mode." A user checking in with their partner should not have to scroll past 200 work contacts. This creates a clear mental boundary between personal and professional relationship management.

**How:** Add a `PeopleViewMode` enum (`all`, `close`, `professional`) to `PeopleListView` state. Toggle as a segmented `Picker` in the sidebar title row (replacing/extending the current `Text("People").font(.title2)` at line 193). The mode is persisted via `@AppStorage("people.viewMode")`.

**Effort:** S. **Impact:** Emotional clarity for multi-context users.

---

### D1-4 — Type-adapted PersonDetailView: render different sections per `PersonCategory`

**What:** `PersonDetailView` must adapt its section content and order based on `PersonCategory`. For `partner`: surface a dedicated "Relationship Health" section at the top (D1-5), promote the check-in/encounter section, demote professional fields (role, company). For `family`: surface "Family moments" memory section at top, birthday countdown. For `closeFriend`: surface "Shared experiences" and "Inside references" memory sections. For `colleague`: current default layout.

**Why:** The section order and content in `PersonDetailView.swift:334–351` is currently identical for a romantic partner and a sales contact. The "Relationships" section jump-rail item today links to a graph-edge display, not a coaching surface.

**How:** `sectionNavItems` (`PersonDetailView.swift:334–351`) is already dynamically built — add a `switch current.category { ... }` that inserts or suppresses sections. The `VStack` at line 240 already conditionally renders sections — extend this pattern.

**Effort:** M. **Impact:** Deep emotional resonance for the relationship-coach positioning.

---

### D1-5 — Relationship health section (partner / family / close friend path)

**What:** For `category == .partner` (and optionally `.family`, `.closeFriend`), add a "Relationship Health" section to `PersonDetailView` that surfaces: last encounter date + days since, a check-in streak (consecutive weeks with at least one logged encounter), and a rotating Gottman/love-language prompt ("When did you last express appreciation explicitly?", "What is their primary love language?"). For family: a "Family memory" prompt. For close friends: a "How are they really doing?" open field.

**Why:** The existing `ConversationAnalysisPreset` enum targets message-analysis. There is nothing in the app that asks the user reflective questions about their close relationships. This is the relationship-coach moat.

**How:** New `RelationshipHealthView(person: Person, category: PersonCategory)` SwiftUI view, inserted at the top of the partner detail path. Prompt bank is a static array keyed by category, rotated weekly by `Calendar.current.component(.weekOfYear, from: Date()) % prompts.count`.

**Effort:** M. **Impact:** Highest emotional differentiation from a generic CRM.

---

### D1-6 — Type-aware `PeopleInsightsView`: stratified reconnect nudges

**What:** Replace the single undifferentiated "Reconnect" card in `PeopleInsightsView.swift:21–38` with type-stratified cards: "Partner" (if last encounter > 7 days), "Family" (> 14 days), "Close Friends" (> 21 days), then all others at 45 days. Each card uses emotionally appropriate language — "You and [Partner] haven't logged time together in N days" vs. "Haven't caught up with [Friend] in a while."

**Why:** The current cutoff (45 days, `PeopleInsightsView.swift:76`) treats all relationships equally. A 45-day gap with a spouse is a crisis; a 45-day gap with a loose acquaintance is normal. Different categories need different urgency thresholds and different copy.

**How:** In `goneCold` (`PeopleInsightsView.swift:75–83`), replace the flat cutoff with a `switch p.category { case .partner: 7; case .family: 14; case .closeFriend: 21; default: 45 }`. Build separate computed arrays per type. Render in distinct cards with different icons and copy.

**Effort:** S (once D1-1 lands). **Impact:** Immediately changes the emotional register of the insights panel.

---

### D1-7 — MCP: expose `category` and add `get_relationship_health` tool

**What:** Extend the VaultKit `Person` model (D1-1) and the MCP server to (a) include `category` in all `get_person` / `list_people` responses and (b) add a new `get_relationship_health(person_id)` tool that returns: category, last encounter date, encounter count in last 30 days, streak (consecutive weeks with encounters), and the next suggested check-in prompt. Also add `set_person_category(person_id, category)` as a write tool.

**Why:** Claude currently receives zero signal about relationship type (`Sources/VaultKit/Person.swift:9–47` has no category field). A user asking "how am I doing with my close relationships?" gets a generic list. With category, Claude can reason: "You haven't logged time with your partner in 12 days and your last three encounters were under 30 minutes — that's shorter than your usual pattern."

**How:** Two new tools in `Sources/MeetingScribeMCP/main.swift`: `get_relationship_health` (read) and `set_person_category` (write). Follows existing write-tool pattern (`add_person`, `add_memory`).

**Effort:** S. **Impact:** Unlocks the entire relationship-coach use case via Claude.

---

### D1-8 — Relationship-type quick-add from the nav rail

**What:** Add a "+" menu to the People nav rail item (on hover or right-click) with type-pre-selected options: "Add Partner", "Add Family Member", "Add Close Friend", "Add Contact". Each opens `AddPersonSheet` with the `category` picker pre-set.

**Why:** Currently `AddPersonSheet` opens via toolbar (`⇧⌘P`) or the sidebar Add button, with no pre-selected type context. A user who thinks "I want to add my mom" has to remember to set the category after the fact. Type-first creation is the correct mental model for an intentional relationship manager.

**How:** `MainWindow.swift` already handles `.meetingScribeAddPerson` notifications (line 408). Add a companion `addPersonWithCategory` notification that carries a `PersonCategory` payload. `AddPersonSheet` accepts an optional `seedCategory: PersonCategory?` param (same pattern as `seedTagID` in `PeopleListView.swift:91`).

**Effort:** S. **Impact:** Removes friction from intentional relationship setup.

---

### D1-9 — Relationship-type badging in the PersonRow and list

**What:** Add a small colored dot or icon to `PersonRow` (`PeopleListView.swift:524–557`) for non-`.colleague` / non-`.acquaintance` / non-`.other` categories. Partner: heart icon (red). Family: house icon (blue). Close friend: star icon (amber). These appear to the left of the name, replacing the generic `person.circle.fill` icon.

**Why:** The current list row shows identical icons for all contacts. A user scanning their list for their partner has to read every name. A small type indicator provides instant spatial scanning — the user knows their partner is at the top without reading.

**How:** In `PersonRow.body`, replace `Image(systemName: "person.circle.fill")` with a `switch person.category { case .partner: Image(systemName: "heart.circle.fill").foregroundStyle(.red); ... default: Image(systemName: "person.circle.fill") }`.

**Effort:** S (once D1-1 lands). **Impact:** Immediate scan efficiency for multi-relationship users.

---

### D1-10 — Relationship-type-aware ConversationAnalysisPresets

**What:** Extend `ConversationAnalysisPreset` with type-aware presets that appear only for matching categories: `.partnerCheckIn` (partner), `.parentChildDynamic` (family), `.friendshipDepth` (closeFriend). Each has a psychologically-grounded prompt template — `.partnerCheckIn` uses Gottman's four horsemen framework to flag contempt/criticism/defensiveness/stonewalling patterns; `.parentChildDynamic` prompts on reciprocity and boundary patterns; `.friendshipDepth` asks whether the friendship feels reciprocal and energizing.

**Why:** The current preset list at `PersonDetailView.swift:23–30` is generic across all relationship types. These prompts would be alarming applied to a work contact but genuinely useful for close relationships. Type-gating ensures they only appear where appropriate.

**How:** Add a `visibleFor: Set<PersonCategory>` property to `ConversationAnalysisPreset`. Filter the picker in `PersonDetailView` by `current.category`. The preamble at line 86–91 also needs to shed the hard-coded "adult professionals" framing for intimate relationships.

**Effort:** S. **Impact:** The most direct route to "relationship coach" positioning.

---

### D1-11 — Per-category default check-in cadence and "overdue" badge

**What:** Store a per-person `checkInCadenceDays: Int?` field (defaulting to category-based defaults: partner=7, family=14, closeFriend=21, friend=30). When `lastInteractionAt` is more than `checkInCadenceDays` ago, show an orange "Overdue" badge on the `PersonRow` and in the nav rail People item (count badge of overdue close-relationship check-ins).

**Why:** The current "gone cold" detection in `PeopleInsightsView` uses a flat 45-day cutoff and is only visible on the insights panel. There is no proactive badging in the list or the nav rail. A user who opens People should immediately see which close relationships need attention, not have to navigate to the insights panel.

**How:** Add `var checkInCadenceDays: Int?` to `Person` (tolerant decoder default: nil). Compute `var isCheckInOverdue: Bool` as an extension. `PersonRow` shows an orange dot when true. Nav rail `NavRailItem` for `.people` shows a badge count via a `@Published var overdueCheckInCount: Int` on `PeopleStore`.

**Effort:** M. **Impact:** Makes the relationship health system proactive, not reactive.

---

## Top 3 picks

1. **D1-1 — `PersonCategory` field** is the absolute prerequisite. Without it, every downstream item is a workaround. This is an hour of Swift work and unlocks 8 of the 11 items above. Ship it in the next PR.

2. **D1-6 — Type-stratified reconnect nudges** in `PeopleInsightsView` is the smallest change with the biggest emotional impact. A partner who hasn't been logged in 12 days appearing in the same "Reconnect" list as a casual acquaintance is tonally wrong. Fix the thresholds and copy — this is a morning of work.

3. **D1-5 — Relationship Health section** (partner / family / close friend) is the feature that makes MeetingScribe a relationship coach rather than a CRM. A rotating Gottman/love-language prompt at the top of a partner profile is a week of work and the clearest differentiator in the entire product.
