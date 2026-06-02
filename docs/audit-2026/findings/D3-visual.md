# D3 — Visual Design & Emotional Warmth Audit

**Lens:** For a relationship-coach app, does the design feel warm and personal,
or clinical and corporate? Focus on typography, color, spacing, and emotional
tone in People views specifically.

---

## 1. Design System Tokens (NotionDesign.swift)

**Color palette — warm neutrals, not cold blue.** `NDS` uses warm near-black
`#1C1B19` / warm off-white `#F8F7F5` (NotionDesign.swift:44–46), warm-tinted
row-hover/divider/hairline tints, and cream-biased text (`#F2EFE6` primary,
NotionDesign.swift:51). The comment "replaces the cold blue-navy" confirms this
is a deliberate recent improvement. The single brand accent is a standard purple
`#7F56D9` (NotionDesign.swift:37).

**Verdict:** the token layer is warm enough as a *neutral* productivity app.
It does nothing specifically relational. There is no secondary warm accent for
intimate relationships (rose, amber, coral), no cool accent for professional
contacts, and no semantic color differentiation by relationship type at all.

**Typography.** Tokens map to SF system styles (NotionDesign.swift:76–81):
`largeTitle/.heavy` for page titles, `callout` for body, `caption2` for tiny
metadata. Scaling-aware via `@ScaledMetric`. Legible, minimal, but zero
personality — nothing handwritten, nothing humanizing. Eyebrow labels are
all-caps tracked (NotionDesign.swift:211–215), appropriate for a Notion-clone
productivity tool, clinical for a relationship coach.

**Spacing.** `pagePadding: 56` (NotionDesign.swift:10), `cardRadius: 12`
(NotionDesign.swift:23), generous vertical `22`pt stack gaps in all People
views. Breathable. Not problematic.

---

## 2. PeopleListView — the Sidebar

`PersonRow` (PeopleListView.swift:525–557) is a two-line HStack: generic
`person.circle.fill` SF Symbol at 26pt tinted `NDS.brand.opacity(0.7)`, name
in 13.5pt semibold, role/company in `NDS.tiny`, relative date at the right
edge. There is no avatar photo, no initials circle, no warmth indicator, no
relationship-type badge.

The `SnapshotPersonRow` (PeopleListView.swift:498–522) is identical in
structure. Both rows look exactly the same for a romantic partner, a manager,
and a vendor. **No visual differentiation by relationship depth or type
whatsoever.**

Tag `FilterChip` (PeopleListView.swift:559–576) is a brand-purple capsule — the
correct token, but tags are the only way to distinguish relationship types, and
that requires the user to have manually created and applied them.

`emptyState` (PeopleListView.swift:452–455) uses `MSEmptyState` with a
`person.2` icon and a functional prompt. No warmth, no invitation.

---

## 3. PersonDetailView — the Main Relationship View

**Avatar:** a `Circle()` filled with `NDS.selectColor(current.displayName)`
(PersonDetailView.swift:395–400) — a deterministic hash into the 9-color
Notion palette. 52pt diameter, initials in `.system(size: 20, weight: .bold)`
white. This is functional: color is stable per-person, initials are immediate.
But it is entirely generic — a partner and a vendor look identical. Photos
exist as a separate section (PersonDetailView.swift:1027–1058) but they are
never promoted to the avatar position; the initials circle is always shown in
the identity panel regardless of whether photos are attached.

**Identity panel** (PersonDetailView.swift:391–508): name at `.system(size: 17,
weight: .bold)`, subtitle (role · company) at `.system(size: 12)`, then tag
chips, then action buttons (Edit · ⋯ · Trash). The buttons below are
`.borderless` with `NDS.small` font: "Encounter", "Relationship", "Ask AI".
Functional and scannable. Emotionally inert — identical layout for a spouse
and a recruiter.

**Section labels** are `NDS.sectionLabel` (caption/semibold, tracked uppercase):
"Tags", "Contact", "Suggestions", "Relationships", "Encounters", "Meetings",
"Tasks", "Memories", "Messages" (PersonDetailView.swift:334–350). This is a
CRM field list. The closest to warmth is the "Memories" label at
PersonDetailView.swift:1330 with a `sparkles` icon on each memory item at
PersonDetailView.swift:1342 — a single warm touch in the entire view.

**Relationship section** (PersonDetailView.swift:1242–1272): a label row with
`person.2.fill` icon at `NDS.brand.opacity(0.7)`, a text label (free-text
string like "spouse", "manager"), and the linked person's name. No type enum,
no color coding, no visual hierarchy distinguishing "partner" from "colleague".
The `AddRelationshipSheet` (PersonDetailView.swift:1940–1982) is a modal with
a plain TextField for the label: `"Relationship (spouse, manager, friend…)"`.
Free text. No type system.

**Favorites section** (PersonDetailView.swift:574–602): pills in `NDS.fieldBg`
with a `heart` icon on the add-field. This is the warmest UI element in the
view — a genuine "know this person" affordance. But it's visually
indistinguishable from any other pill section.

**Photos** (PersonDetailView.swift:1027–1058): 72pt thumbnails in a horizontal
scroll, only shown when `!current.photoRelativePaths.isEmpty`. Never used as the
hero avatar. A real photo exists but is buried below Tags, Contact fields, AI
suggestions, and is never promoted to the prominent avatar position.

**Encounters** (PersonDetailView.swift:1096–1111): plain rows via `EncounterRow`.
No warmth cues — just event name and note text.

**Memories** (PersonDetailView.swift:1330–1354): `sparkles` icon + free-text
chip on `NDS.fieldBg`. The only section that reads as personal and not transactional.

**Section nav rail** (PersonDetailView.swift:312–331): horizontal capsule chips
for jump navigation. Clinical/utility.

**Embedded chat column** (PersonDetailView.swift:818–847): `sidebarBg` panel
with "Ask AI about [first name]" heading and `sparkles` icon. Functional but
cold — it's a chat terminal, not a "relationship coach conversation" surface.

---

## 4. PeopleInsightsView — the Empty-State Dashboard

Three cards: "Reconnect", "Upcoming birthdays", "Most active"
(PeopleInsightsView.swift:22–55). Each uses `card()` → `.msCard()` surface.
The `row()` helper (PeopleInsightsView.swift:138–155) renders an initials
circle (26pt, `NDS.selectColor`) + name + trailing string.

**"Reconnect"** card is the warmest element in the entire People tab — a
genuine emotional prompt. But it fires on a blunt 45-day cutoff for all
contacts equally (`goneColdDays = 45`, PeopleInsightsView.swift:12). A romantic
partner should reconnect in 2 days; a quarterly vendor in 90. There is no
per-type threshold.

**"Upcoming birthdays"** card uses a gift icon — contextually warm, but styled
identically to the "Most active" (flame icon) analytical card. No visual
differentiation to signal emotional significance.

---

## 5. PeopleGraphView & PersonNodeView — the Mindmap

**PersonNodeView** (PersonNodeView.swift:16–136): avatar circle (photo or
initials gradient) + name in `.system(size: 11, weight: .semibold)` + tag pills
at 8pt. Node diameter is variable (driven by `PersonNode.diameter`). A brand
ring on selection, a cyan ring on path-highlight.

**Edge rendering** (PeopleGraphView.swift:86–111): `Canvas` strokes lines.
Edge color is `edgeColor(edge)` (not shown in excerpted code but presumably
tag-derived). Edge weight `1.0 + weight * 3.0` (RelationshipEdge.swift:37).
Pill label at midpoint for `sharedMeetingCount > 2`. Entirely analytical —
shows professional overlap (shared meetings, shared tags), not emotional
relationship type.

**Graph access** (PeopleListView.swift:198–205): demoted to a compact icon
button (`circle.hexagongrid`), with a comment that it's "rarely useful with
500+ contacts and is just decorative." This is accurate — the graph is wired
for analytical exploration, not emotional navigation. There is no layout mode
that places "partner" at center, family in an inner ring, close friends in a
next ring — the classic intimacy-zone visualization pattern.

**`GraphFilterBar`** (GraphFilterBar.swift:14–77): tag-chip filters + search +
Re-layout + List View. No relationship-type filter. No "show only close
relationships" mode.

**`GraphDetailPanel`** (GraphDetailPanel.swift:26–43): rightside panel showing
photo, name, tags, meeting count, connections. Stats-first, warm-elements absent.

---

## 6. TodayView — People Surfaces

`SuggestedPeopleView` and `ReconnectView` appear in the feed
(TodayView.swift:93–97). `ReconnectView` is the warmest today-surface element.
Neither is detailed enough to audit without reading those files, but based on
`PeopleInsightsView` which shares the same design language, they are likely
equally clinical.

---

## 7. Existing Plan Items — Endorsements Through This Lens

The following already-planned items are directly relevant to emotional warmth
and should be prioritized:

1. **PPL-1 (inline identity editing)** — removing the modal reduces friction for
   personal updates, but the real warmth gain is zero until the *fields* carry
   emotional signals. Endorse as prerequisite.
2. **PPL-5 ("About" rename)** — renaming "Notes" to "About" is a small but
   meaningful shift in emotional register. Endorse as S-effort quick win.
3. **TDY-1 ("Up next" hero strip)** — already planned; the relationship-warmth
   angle is showing attendee avatars/names warmly, not just a meeting title.
   Endorse as must-ship.
4. **Stay-in-touch nudges (existing plan)** — the blunt 45-day cadence needs
   per-type thresholds (see D3-6 below). Endorse with modification.

---

## 8. NET-NEW Recommendations

### D3-1 — Promote photos to hero avatar position [S]
**What:** When `current.photoRelativePaths` is non-empty, render the first photo
as the 52pt circle avatar in `identityPanel` (`PersonDetailView.swift:394`) via
`CachedThumbnail` (the component already exists). Fall back to the initials
circle only when no photo exists. One `if/else` branch in `identityPanel`.

**Why:** The app already stores photos but never shows them in the most-seen
position. A photo of a friend or partner makes the view feel personal
immediately. Zero schema change.

**Effort:** S (hours)

---

### D3-2 — Relationship-type enum with per-type color and icon [M]
**What:** Add `RelationshipCategory` enum to `Relationship` (Person.swift:51):
`.partner`, `.family`, `.closeFriend`, `.friend`, `.colleague`, `.other`. Keep
the free-text `label` field. Assign each category a distinct icon and a warm vs.
cool color token. In the Relationships section (PersonDetailView.swift:1242) and
in `PersonRow`, show the category icon in a tinted circle instead of the generic
`person.2.fill`. In the graph, color edges by relationship category (override
the meeting-count coloring for explicit personal relationships).

**Why:** A partner should look fundamentally different from a vendor at a glance.
The free-text label stays for nuance ("husband", "mom", "childhood best friend")
but the category drives the visual signal. This is the single most load-bearing
warmth gap.

**Effort:** M (model migration + UI: ~2 days)

---

### D3-3 — Intimacy-zone graph layout mode [M]
**What:** Add a "Personal" layout mode to `PeopleGraphView` (distinct from the
default force layout). The selected person (or user) is the center node. Ring
1: `.partner` and `.family` relationships (closest). Ring 2: `.closeFriend`.
Ring 3: `.friend`. Outer ring: `.colleague` and `.other`. Edges to the center
are styled by category color (D3-2). Standard force layout stays as the default
"Network" mode.

**Why:** The current force layout optimizes for meeting-overlap density — an
org-chart sensibility. A concentric intimacy layout reframes the graph as an
emotional map, not a collaboration chart. This is the core UX metaphor change
for a relationship coach.

**Effort:** M (new `GraphLayoutEngine` mode: ~2–3 days)

---

### D3-4 — Per-type check-in cadence on "Reconnect" cards [S]
**What:** Replace the flat `goneColdDays = 45` constant in
`PeopleInsightsView.swift:12` with a per-person computed threshold driven by
`RelationshipCategory` (D3-2): partner → 3 days, family → 7, closeFriend → 14,
friend → 30, colleague → 60, other → 90. Surface the threshold in the card as
"hasn't checked in for [N] days" with the category color.

**Why:** Treating a spouse and a quarterly vendor with the same 45-day cadence
is emotionally wrong and produces noise that users will ignore. Per-type
thresholds make nudges feel considered, not algorithmic.

**Effort:** S (a lookup table + computed property, no schema change after D3-2)

---

### D3-5 — Warm section headers for intimate relationship types [S]
**What:** When the person's primary `RelationshipCategory` (from any
Relationship where they are the subject) is `.partner` or `.family`, replace the
Notion-style uppercase eyebrow label for key sections with a lowercase, lighter-
weight style (`Font.system(.body, weight: .regular)` in `NDS.textSecondary`).
Use warmer placeholder text: "What you love about them" instead of "Favorite
things", "Together" instead of "Encounters", "Shared moments" instead of
"Memories". The section *key* stays the same; only the label text and typography
variant change by type.

**Why:** Typography register is the cheapest warmth lever. "FAVORITE THINGS" in
tracked caps reads like a CRM field; "What you love about them" reads like a
relationship journal. Zero model change.

**Effort:** S (add `var displayLabel: String` to each section, conditioned on category)

---

### D3-6 — Avatar color rings by relationship depth [S]
**What:** In `PersonRow` (PeopleListView.swift:525) and the 52pt avatar in
`identityPanel`, add a 2pt ring around the circle in the category color from
D3-2. Partner → rose/warm red, family → amber, close friend → teal, colleague →
gray. No ring for uncategorized contacts.

**Why:** At list density, even a 2pt color ring is scannable at a glance. A user
can immediately spot their partner and close friends without reading names. This
is the warmth signal that a relationship-coach app needs in its list view, and
it costs one `.overlay(Circle().strokeBorder(...))` per row.

**Effort:** S (after D3-2 provides the enum)

---

### D3-7 — Emotional tenor block at the top of PersonDetail [M]
**What:** Add a `RelationshipHealth` widget immediately below the identity panel
for persons with category `.partner`, `.family`, or `.closeFriend`. Display:
(a) last check-in days ago with a color-coded dot (green < threshold, yellow
approaching, red overdue), (b) the dominant sentiment from the most recent
ConversationAnalysis (if one exists as an `AttachedNote`), (c) a single-tap
"Log a moment" button that opens a minimal check-in sheet (mood, one line, saves
as an Encounter with `kind: .checkIn`). This widget is suppressed for
`.colleague` and `.other` categories.

**Why:** This creates the "relationship dashboard" feel at the top of the view —
the signal-at-a-glance that differentiates a personal coach from a contact list.
The data model (encounters, attached notes) already supports all three data
points.

**Effort:** M (new widget component + check-in sheet: ~2 days)

---

### D3-8 — Photo-first card variant for intimate contacts [S]
**What:** In `PeopleInsightsView.card()` for the "Reconnect" section, use a
wider 36pt avatar (with real photo if available, via D3-1) and add a warmly
worded subtitle: "Last time: [N] days ago" in `NDS.textSecondary` vs. the
current cryptic relative-date string ("3w ago"). For `.partner` entries,
prepend a subtle heart icon to the row.

**Why:** The reconnect card is already the warmest surface in the app. A 36pt
photo and a full sentence instead of an abbreviated date raises the emotional
register of the prompt without any structural change.

**Effort:** S (conditional rendering in `PeopleInsightsView.row()`)

---

### D3-9 — "Relationship snapshot" rich header in GraphDetailPanel [S]
**What:** In `GraphDetailPanel.header` (GraphDetailPanel.swift:48–65), below the
name/subtitle, add one sentence of relationship context: the category label
("Partner" · "Sister" · "Best friend") in the category color from D3-2, and the
time-since-last-interaction in plain language ("Last connected 12 days ago").
Currently the header only shows name and role/company — it reads like a business
card.

**Why:** The graph detail panel is where users go when they're exploring their
social world. Showing relationship type and recency immediately reframes the
panel from "contact info" to "relationship status."

**Effort:** S (one HStack below the subtitle, reads from existing `Person` fields)

---

### D3-10 — Suppress clinical language in the empty relationship state [S]
**What:** Replace the empty-state text in `relationshipsSection`
(PersonDetailView.swift:1252): "No relationships yet. Link family, colleagues,
or friends." → for `.partner`/`.family` category: "People who matter most to
you. Add a family member or partner." For `.colleague`: "How you know each other
at work." Keep the current text as the default fallback.

Also replace the `AddRelationshipSheet` (PersonDetailView.swift:1966) text field
placeholder "Relationship (spouse, manager, friend…)" with a picker showing
`RelationshipCategory` options first, then an optional free-text label field.

**Why:** Every bit of system-generated copy is currently CRM-speak. Warm copy at
zero-state moments (when a person profile is new and empty) sets emotional
expectations for what the app is for.

**Effort:** S (string changes + picker UI in AddRelationshipSheet)

---

### D3-11 — Warm color palette token for intimate-relationship tints [S]
**What:** Add three warmth-specific color tokens to `NDS`
(NotionDesign.swift:83–95): `NDS.warmRose = Color(hex: "#E8505B")`, `NDS.warmAmber = Color(hex: "#D97706")`, `NDS.warmTeal = Color(hex: "#0D9488")`. Use these exclusively for D3-2/D3-6 category coloring. Do not overload the existing 9-slot Notion `palette` (which is used for tag chips and would create semantic collisions).

**Why:** The existing palette is a generic tag-chip system. Relationship-type
colors need to be distinct, stable, and emotionally coded — rose for partner,
amber for family, teal for close friend. Defining them as named tokens means
every view referencing category colors stays in sync.

**Effort:** S (3 color literals in NotionDesign.swift; no behavior change)

---

## 9. Top 3 Picks

| Rank | ID | Why it matters most |
|---|---|---|
| 1 | **D3-2** — Relationship-type enum + color/icon | The root cause of every other warmth gap. Everything else (D3-3, D3-4, D3-5, D3-6, D3-7, D3-9) either requires this or becomes dramatically stronger with it. Build this first. |
| 2 | **D3-1** — Promote photos to hero avatar | Hours of work; the single highest warmth-to-effort ratio in the entire audit. A photo of a loved one transforms the view from a CRM record to a person. |
| 3 | **D3-7** — Emotional tenor / health widget | This is the feature that makes MeetingScribe feel like a relationship coach rather than a contact manager. Without it, the distinction exists only in marketing copy. |
