# D5 — Health Score UX v2

**Lens:** Is the "connection strength" arc ring communicating well — and is it even built?

---

## 1. Implementation Status: Not Built

The `healthScore` case exists in `FeatureGate.ManagedFeature` (`FeatureGate.swift:8`) with the comment
`// Connection strength arc in PersonDetailView`. It is gated as Pro-only (`isEnabled` returns `false`,
line 71). `ProPaywallView.swift` promises "Connection strength score + encounter heat map" in its feature
bullet list (line 38).

**There is zero health score UI in `PersonDetailView.swift`.** A full grep for `healthScore`,
`connectionStrength`, `arc`, `gauge`, `ring`, `Arc`, `Ring`, `Gauge`, `Score`, and `Health` in that
file returned zero substantive hits — only generic Swift string-handling (`String`, `score` as a local
variable for `relevanceScore`). No `ConnectionStrength`, `HealthArc`, or `RelationshipHealth` files
exist anywhere in `Sources/`.

The only stub is the `ManagedFeature.healthScore` enum case. There is no placeholder view, no grayed-out
ring, no skeleton, no computed property on `Person`, and no algorithm. The feature is purely nominal.

Available signals in the current data model (`Person.swift:155–213`, `Encounter.swift`):

| Signal | Field | Notes |
|---|---|---|
| Days since last interaction | `Person.lastInteractionAt` | Updated by encounters and meeting mentions |
| Encounter count | `PeopleStore.encounterCountIndex` | Already O(1) via didSet index |
| Check-in cadence target | `Person.effectiveCheckInDays` | Type-aware default |
| Memories logged | `Person.memories.count` | Depth proxy |
| Meeting mentions | `Person.meetingMentions.count` | Ambient engagement |
| Birthday set | `Person.birthday != nil` | Profile richness |
| Relationship type | `Person.relationshipType` | Critical for score calibration |

There is no `Encounter.mood`, `Encounter.kind` (the QuickEncounterSheet extensions are local to that
file), or `lastCheckInAt` field — meaning quality signals are absent from the model today.

---

## 2. Algorithm Design

### 2a. What makes a score meaningful vs. gameable

A meaningful connection-strength score measures **actual relational investment**, not app activity.
The failure mode of naive designs: users log phantom encounters to keep a green ring, which is worse
than not having the feature.

**Anti-gaming principles:**
- Weight *recency decay* exponentially, not linearly — the curve should punish dormancy hard after
  the cadence window passes, not reward catch-up logging.
- Never reward encounter *count* without also considering *time distribution* — five logs in one day
  should not outscore one per week for five weeks.
- Cap the contribution of any single encounter type (e.g., iMessages alone should not max the score).
- Suppress score increases for encounters with the same event name logged within 24 hours of each other
  (prevents bulk-logging).

### 2b. Proposed algorithm — `ConnectionStrength`

Score range: 0.0–1.0 (displayed as 0–100 or a 0°–270° arc).

```
score = recencyScore × 0.50
      + consistencyScore × 0.30
      + depthScore × 0.20
```

**recencyScore** (0–1): exponential decay from last interaction.
```
let daysSince = Date().timeIntervalSince(lastInteractionAt) / 86_400
let target    = Double(effectiveCheckInDays)
recencyScore  = exp(-daysSince / target)
// At 0 days: 1.0. At 1× target: ~0.37. At 2× target: ~0.14. At 3×: ~0.05.
```

**consistencyScore** (0–1): regularity of encounters over the past 90 days.
```
let windows      = 3                            // 3 × 30-day windows
let windowCounts = [count_0_30d, count_30_60d, count_60_90d]
let populated    = windowCounts.filter { $0 > 0 }.count
consistencyScore = Double(populated) / Double(windows)
// Touched in all 3 windows → 1.0; only last 30d → 0.33; never → 0.
```

**depthScore** (0–1): qualitative investment signals.
```
var depth = 0.0
if memories.count >= 3      { depth += 0.4 }  // knows them well
if memories.count >= 10     { depth += 0.2 }  // very well documented
if meetingMentions.count > 0 { depth += 0.2 } // shows up in professional life too
if birthday != nil          { depth += 0.1 }  // knows personal details
if !favorites.isEmpty       { depth += 0.1 }  // knows preferences
depthScore = min(depth, 1.0)
```

**Relationship-type calibration:** The cadence denominator in `recencyScore` already adjusts via
`effectiveCheckInDays` — romantic partners (default 3d) decay fast; acquaintances (default 90d) decay
slowly. No separate multiplier needed; this is the right design.

**Encounter quality modifier (post-QuickEncounterSheet mood data):** Once `Encounter.mood` is on the
canonical model (a dependency of D5-05 below), apply a mood multiplier:
```
moodMultiplier = encounters_last30d.map { $0.mood.weight }.average()
// .great → 1.2, .good → 1.1, .neutral → 1.0, .tense → 0.85, .hard → 0.7
finalScore = min(rawScore × moodMultiplier, 1.0)
```
Do not apply the mood multiplier until mood data exists on the canonical `Encounter` struct —
bootstrapping on zero mood data silently ignores it (defaults to ×1.0).

**Implementation home:** `Person+ConnectionStrength.swift` — a computed property extension:
```swift
extension Person {
    func connectionStrength(encounters: [Encounter]) -> Double { … }
}
```
Takes encounters as a parameter (not fetched internally) so it is pure, testable, and does not couple
Person to PeopleStore.

---

## 3. Psychological Risks

This is the most important design constraint for an intimate relationship app.

**Risk 1: Score as verdict.** A user who sees their romantic partner at score 12/100 at 11 pm after
a hard week may interpret it as evidence the relationship is failing, not evidence the *app* hasn't
been used. The score reflects *logged activity*, not relationship health.

**Mitigation:** Never call it a "health score" in the UI copy. Use "Connection rhythm" or "Check-in
streak" — language that frames it as *your engagement with the app*, not a verdict on the relationship.
The feature is already named `connectionStrength` in the gate comment, which is better than "health."

**Risk 2: Guilt as a habit driver.** Duolingo's streak counter works because a missed Spanish lesson
has no emotional consequence. A missed check-in with a grieving parent has enormous weight. A red arc
ring at 9 am is a guilt trigger, not a motivation trigger, for high-empathy users (the exact audience
for this product).

**Mitigation:** Score should be visible only on PersonDetailView (not in list cells or notification
badges). Never show score in a notification. Add the `suppressReconnectNudge` flag (already proposed
as D5-7 in the master plan) — long-press to suppress for estranged relationships.

**Risk 3: Comparative ranking.** If the score appears in `PeopleListView` as a sort key or badge,
users may unconsciously rank their relationships by a metric. This is corrosive.

**Mitigation:** Score is **private to PersonDetailView only**. PeopleListView shows only overdue
status (a binary: yes/no dot), not a numeric rank.

**Risk 4: False precision.** An arc showing 63% implies measurement accuracy that doesn't exist.
Logarithmic decay curves are not validated relationship science.

**Mitigation:** Never show a number. Show the arc ring only in three color bands: green (healthy
cadence), amber (approaching overdue), red (overdue). The arc *angle* carries the gradient; no
digit is ever rendered alongside it.

---

## 4. Visualization — What to Build

### Benchmark analysis

| Product | Mechanic | What it teaches |
|---|---|---|
| **Apple Fitness rings** | Three concentric closure arcs — Move, Exercise, Stand | Closure metaphor is immediately legible; color conveys goal progress; works without numbers; gap = quantity remaining. Key insight: **the gap is the message**, not the filled portion. |
| **Duolingo streak** | Fire icon + day count + freeze mechanic | Streak counters trigger loss aversion (Kahneman 1979). Effective for low-stakes habits. Dangerous for intimate relationships — ending a streak feels like failure, not a data point. Do NOT copy. |
| **Streaks (iOS app)** | Circular calendar heatmap per habit | Per-day dots in a ring calendar communicate distribution without numeric scores. **Best model for MeetingScribe** — shows rhythm, not verdict. |
| **Fabulous / Finch** | Emotion-first framing; no hard scores | Avoided explicit failure states entirely. Gentle language: "it's been a while" not "43% strength." |

### Recommendation: Cadence Ring, not Health Score Arc

A single arc ring showing **closure toward the next check-in window** (not a cumulative score) is
safer and more honest. Think: "you have 4 days left in your 7-day window" displayed as a ring that
fills as the deadline approaches, then resets on contact. This is Apple Fitness rings semantics, not
a percentile score.

Paired alongside it: a 12-week dot heatmap (Streaks-style) showing which weeks had encounters. This
communicates *rhythm* without implying a verdict on the relationship's quality.

```
┌─────────────────────────────────────────┐
│  [●●●●●●●●●●●●] Cadence ring (arc)      │
│   "3 days until next check-in"          │
│                                         │
│  [· · ■ · ■ · ■ ■ · ■ · ·] 12-week     │
│   dot heatmap                           │
└─────────────────────────────────────────┘
```

The arc ring shows **days remaining / cadence target** — 100% = just checked in, 0% = overdue.
Color: teal (>50% remaining) → amber (25–50%) → soft red (<25%, i.e., overdue). No number.

---

## 5. Existing Plan Items Ranked Highest Through This Lens

| ID | Item | Why it ranks |
|---|---|---|
| **BRIEFING gap #3** | `healthScore` gate exists, UI not built | The most direct item; unblocking it is this audit's mandate |
| **D5-11 (master plan)** | Emotional safety note for intimate relationship analysis | Must ship *alongside* any score UI; cannot be deferred |
| **D5-7 (master plan)** | `suppressReconnectNudge` flag | Required to handle estranged relationships safely |
| **P1-6 / D3-7 (master plan)** | Relationship health block top of PersonDetailView | The design frame that hosts the score card |
| **E1-3** | Split EncounterStore from PeopleStore | Required before `connectionStrength(encounters:)` is injected cleanly |

---

## 6. Net-New Recommendations

---

### D5-01 — Rename "health score" to "connection rhythm" everywhere

**What:** Audit all copy in `FeatureGate.swift`, `ProPaywallView.swift`, comments, and any future UI
strings. Replace every instance of "health score" / "health arc" with "connection rhythm" or
"cadence ring."

**Why:** "Health score" implies a clinical verdict on the relationship. "Rhythm" implies a practice —
something you can return to, not something you pass or fail.

**User value:** Reduces anxiety for users in difficult relationship phases. Aligns with the product's
coaching philosophy (Gottman, NVC) which explicitly avoids deficit framing.

**Effort:** S (copy change only)

**Impact:** High (frames every subsequent UI decision)

**Deps:** None

---

### D5-02 — `Person+ConnectionStrength.swift` — implement the algorithm

**What:** New extension file with `connectionStrength(encounters: [Encounter]) -> Double` computed per
the algorithm in section 2b above. Pure function, no side effects, no Store coupling. Returns 0.0–1.0.
Add `connectionStrengthBand: ConnectionBand` (`.strong / .fading / .overdue`) for UI use.

**Why:** The gate is declared; the math doesn't exist. Without this, PersonDetailView has nothing to
render even when the gate opens.

**User value:** Enables the Pro feature to actually display. Unblocks D5-03, D5-04.

**Effort:** S (< 80 lines; pure Swift)

**Impact:** High (prerequisite for all score UI)

**Deps:** None (uses existing `Person` fields and passed-in `[Encounter]`)

---

### D5-03 — `CadenceRingView` — the arc ring component

**What:** A standalone SwiftUI view. Renders a 270° `Arc` stroke (`Path` + `trimmedPath`) showing
`days remaining / effectiveCheckInDays` as fill ratio. Color via `ConnectionBand`. No number label.
Below the ring: short prose label — "3 days until check-in" / "Overdue by 2 days" / "Check in today."

**Why:** The ring is the Pro visual centerpiece promised in `ProPaywallView`. Its simplicity (three
colors, no numbers) deliberately avoids the false-precision trap identified in risk section 4.

**User value:** Legible at a glance. Communicates urgency without scoring the relationship.

**Effort:** S–M (ring math is ~30 lines; prose label generation is ~20 lines)

**Impact:** High

**Deps:** D5-02

```swift
struct CadenceRingView: View {
    let person: Person
    let encounters: [Encounter]          // from PeopleStore
    // …
    var fillRatio: Double { … }          // 0.0 (overdue) → 1.0 (just logged)
    var band: ConnectionBand { … }
    var label: String { … }              // "3 days until check-in"
}
```

---

### D5-04 — 12-week encounter dot heatmap (`EncounterRhythmView`)

**What:** A horizontal row of 12 filled/empty circles, one per week, colored by encounter presence
(filled = at least one encounter that week, empty = none). Placed below the cadence ring in
PersonDetailView's connection section.

**Why:** The heatmap communicates *distribution* (Streaks app model) without implying a verdict.
A user who sees 8 of 12 weeks filled understands their rhythm intuitively. A single 12/100 score
would cause distress; a sparse-but-present dot pattern just invites curiosity.

**User value:** Replaces any numeric score. Tells the story of the relationship's rhythm over time.

**Effort:** S

**Impact:** Medium-High

**Deps:** D5-02 (uses same encounter data)

---

### D5-05 — Persist `Encounter.mood` and `Encounter.kind` on the canonical model

**What:** Add `mood: EncounterMood?` and `kind: EncounterKind?` to `VaultKit/Encounter.swift` and to
the encounter JSON schema. Resolve the known enum conflict (BRIEFING gap #6): deprecate the
QuickEncounterSheet-local extensions, migrate their cases into the canonical enums.

**Why:** The `connectionStrength` algorithm's mood multiplier (section 2b) requires these fields to
exist on the canonical struct. Without them, encounter quality is invisible to the score. Also
eliminates the existing enum conflict that corrupts MCP-read encounter data.

**User value:** Algorithm becomes sensitive to quality, not just frequency. A week of hard
conversations should read differently from a week of easy ones.

**Effort:** M (two enum migrations + schema bump, but decoder-tolerant pattern already exists)

**Impact:** High (quality signal + bug fix)

**Deps:** None

---

### D5-06 — Free tier: binary "nudge dot" in PersonDetailView, not grayed arc

**What:** Free users should NOT see a grayed-out, padlocked arc ring — that's a nagging upsell
pattern. Instead, free users see only a small color dot (teal / amber / red) next to the person's
name in PersonDetailView header, labeled "Check-in due" or nothing. Tapping the dot opens the
paywall *contextually* ("See your connection rhythm in detail with Pro"). Pro users see the full
arc ring + heatmap.

**Why:** Grayed-out "teaser" visualizations are widely reported as frustrating in freemium UX
research (see Spotify's grayed shuffle, Duolingo's locked owl). A minimal binary affordance
communicates value without showing a broken experience. The dot is useful on its own.

**User value:** Free users get actionable signal (overdue yes/no). Pro users get the full picture.
The upgrade moment is contextual and desire-driven, not frustration-driven.

**Effort:** S

**Impact:** High (monetization conversion + free user satisfaction)

**Deps:** D5-02

---

### D5-07 — Emotional safety note for the connection section (intimate types only)

**What:** For `relationshipType in [.romanticPartner, .familyMember, .closeFriend]`: render a
one-time inline note beneath the `CadenceRingView` on first display. Text: *"This rhythm reflects
when you've logged time together in MeetingScribe — not a measure of how strong your relationship
is."* One `@AppStorage` flag per person dismisses it permanently. "Got it" link.

**Why:** Directly addresses Psychological Risk #1 (section 3). Already proposed as D5-11 in the
master plan's AI-analysis context, but that proposal applies only to AI analysis runs. The score
display itself needs the same guard at first display.

**User value:** Prevents the most emotionally harmful misreading of the feature.

**Effort:** S

**Impact:** Critical (safety; cannot ship score UI without this)

**Deps:** D5-03

---

### D5-08 — Gate the full arc behind `FeatureGate.healthScore` correctly in PersonDetailView

**What:** When `FeatureGate.shared.isEnabled(.healthScore)` is false, render the dot-only variant
(D5-06). When true, render `CadenceRingView` + `EncounterRhythmView`. Wire the tap-to-paywall path:
`FeatureGate.shared.showPaywall(for: .healthScore)`. In DEBUG, `overrideAllEnabled = true` already
bypasses — no change needed there.

**Why:** The gate case exists but is never consulted by PersonDetailView because the UI doesn't
exist. This wires the final connection.

**User value:** Monetization path becomes functional. Pro users see the full UI; free users see
the dot + upgrade nudge.

**Effort:** S

**Impact:** High

**Deps:** D5-03, D5-06

---

### D5-09 — No score in notifications, list cells, or dock badge

**What:** Add a code-level convention (doc comment on `CadenceRingView` and `connectionStrength()`)
explicitly prohibiting use in list cells, notifications, or any badge. If `StayConnectedSection`
is updated in a future phase, it must use the binary overdue-boolean, not the score float.

**Why:** The most common product mistake for this class of feature (Fitbit, Pillow, Streaks) is
score-leakage into ambient contexts where it causes anxiety without actionability.

**User value:** Preserves the safe container (PersonDetailView only) so the feature doesn't
colonize the emotional ambient experience of the app.

**Effort:** S (documentation + one-line guard)

**Impact:** Medium (preventive)

**Deps:** D5-02

---

### D5-10 — MCP `get_relationship_health` tool exposes rhythm data, not a score float

**What:** The master plan proposes a `get_relationship_health` composite MCP tool (E3-6). This
recommendation constrains its schema: return `daysSinceLastEncounter`, `overdueByDays`,
`cadenceTargetDays`, `encounterCountLast30d`, `encounterCountLast90d`, `weeklyPattern` (12-bool
array), and `band: "strong" | "fading" | "overdue"`. **Do not return a raw score float.** Let
the LLM (Claude) interpret the band + days; don't feed it a number it will interpret as a verdict.

**Why:** An LLM given `connectionStrength: 0.23` will narrate it as "your relationship is at 23%
strength" which is harmful. `band: "fading"` with `overdueByDays: 4` yields "you're 4 days past
your usual check-in window" — actionable and non-judgmental.

**User value:** Safer coaching outputs. Consistent with the "rhythm not verdict" framing.

**Effort:** S (schema design only; the tool build is E3-6's effort)

**Impact:** Medium

**Deps:** D5-02, E3-6 (master plan)

---

## 7. Top 3 Picks

**D5-02** — Implement `connectionStrength(encounters:)` algorithm. Pure function, no UI, unblocks
everything. Without this, no other D5 item ships. Effort: S. Impact: High.

**D5-03 + D5-07** — `CadenceRingView` plus the emotional safety note as an atomic unit. These two
must ship together; deploying the ring without the safety note for intimate relationship types is a
user-harm risk.

**D5-06** — Free-tier dot (binary overdue signal) instead of grayed-out arc. Changes the monetization
experience from frustrating to useful, which is the conversion path that actually converts.

---

## 8. Single Highest-Priority Recommendation

**D5-02 — Implement `Person+ConnectionStrength.swift` now, even though the UI will follow later.**

The feature gate is declared. The paywall promises the feature. The algorithm takes 10 minutes to
write and has no UI surface area, no risk, no psychological harm vector, and no deps. Once it
exists, D5-03, D5-04, D5-06, D5-08, and D5-10 can all be built against it independently. Doing
the UI (D5-03) first without the algorithm produces a hardcoded stub; doing the algorithm first
means any contributor can build the UI component against a real function. The algorithm is the
critical path.

Estimated effort: S (under 80 lines, pure Swift extension, one new file).

---

*Findings by D5 — Health Score UX agent. Source citations: `FeatureGate.swift:8,71`,
`ProPaywallView.swift:38`, `Person.swift:155–213`, `Encounter.swift:1–44`,
`PeopleStore.swift:47–55,139`, `PersonDetailView.swift` (zero health score UI confirmed).*
