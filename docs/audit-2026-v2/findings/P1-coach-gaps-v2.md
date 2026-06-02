# P1 — Relationship Coach Completeness Gaps (v2)

**Lens:** Senior PM who has deeply used Lasting, Paired, and BetterHelp. After Phases 1–3, what does a truly great relationship coach app do that MeetingScribe still lacks?

---

## Full-App Audit Through This Lens

### What exists

- `RelationshipPromptLibrary.swift`: 28 static prompts (11 partner/Gottman, 8 family/NVC, 9 closeFriend/love-language), rotating by ISO week via `weeklyPrompt(for:)`. Only three relationship types get prompts — `friend`, `colleague`, and `acquaintance` get `nil`.
- `PersonDetailView.swift:80–178`: Dynamic AI preamble per relationship type. Partner gets Gottman framing, family gets NVC framing, close friend gets generic "supportive coach." No further coaching framework appears.
- `QuickEncounterSheet.swift:43–58`: `Encounter.Mood` enum — great/good/neutral/tense/hard as raw chips. Mood is appended as a tag in the note string (`[mood:tense]`) rather than stored as a typed field, making it impossible to query longitudinally.
- `ConversationAnalysisPreset` (PersonDetailView.swift:23–70): 6 presets — none is "conflict debrief," "repair attempt," or crisis-specific. No preset adapts its prompt based on encounter history.
- No `loveLanguage` or `attachmentStyle` field exists on `Person.swift` (confirmed grep: zero hits). The master plan lists `P1-11` for these but they are not implemented.
- No streak UI, heat map, or longitudinal chart exists in any People view (heat map appears only as a bullet in `ProPaywallView.swift:42` — not built).
- No multi-user / shared-session feature exists anywhere.
- No milestone or anniversary celebration logic exists for relationship milestones beyond birthday reminders in `RelationshipNotificationManager.swift:13`.
- `TodayView.swift:255` has a meeting anniversary ("On This Day") feature for meetings, but nothing equivalent for relationship milestones.

### Gaps against Lasting / Paired / BetterHelp

| Dimension | Lasting / Paired behavior | MeetingScribe reality |
|---|---|---|
| Daily structured reflection | 5-min guided sessions, 2–3 targeted questions per day | Weekly prompt only; no daily cadence, no question-answer flow |
| Progress tracking | Paired: "connection streak" counter, week-over-week graph | Zero longitudinal UI; heat map exists only as paywall copy |
| Partner-specific features | Both partners install the app; shared prompts, joint check-ins | Entirely single-user; no concept of a "partner account" |
| Crisis/conflict support | Lasting: "After a hard conversation" flow with 4 structured steps | Only `Encounter.Kind.milestone` exists; no conflict debrief preset, no repair scaffolding |
| Personalization | Prompts adapt to logged patterns (love language learned from usage) | Prompts rotate by ISO week, ignoring encounter history, mood data, or logged frequency |
| Milestone celebration | Anniversary notifications, "1 year together" card, confetti moment | Birthday notification only; no relationship-milestone dates, no celebration trigger |

---

## Existing-Plan Items I Rank Highest

1. **P1-11** — `loveLanguage` + `attachmentStyle` on `Person` for romanticPartner. These two fields are the minimum for Lasting-parity personalization. Without them, every prompt is generic.
2. **P3-2** — Per-type AI analysis presets (`.partnerCheckIn`, `.difficultConversationDebrief`). The `ConversationAnalysisPreset` enum is the hook; adding a conflict-debrief case is S effort with high coach value.
3. **C3-1** — Progressive content arcs (encounter-count unlocks). This is the key differentiator from Paired's static content — prompts that deepen as the relationship deepens.
4. **D4-6 / P2-4** — 13-week encounter heat map. The paywall bullets it; users need to see it to value it.
5. **D5-6** — `quality: EncounterQuality?` on `Encounter`. The current mood-as-tag-string (`[mood:tense]`) is unqueryable; a typed field enables longitudinal mood charting.

---

## NET-NEW Recommendations

### P1-N1 — Daily reflection prompt (not weekly)
**What:** Add a `dailyPrompt(for:on:)` function to `RelationshipPromptLibrary` that returns a short (≤25-word) question for today, drawn from a separate pool of ~30 per-type "micro-reflection" prompts. Surface one as a banner in `PersonDetailView` if `lastReflectedAt` (new `@AppStorage` key) is not today. Tap to answer → inline text field → saves as `Encounter` with `kind = .reflection`.

**Why:** Lasting's core habit is daily 5-min sessions. Weekly rotation means the user might not see a prompt for 7 days. One question a day at the top of PersonDetailView costs zero AI calls and drives daily opens.

**User value:** Habit formation — the primary churn driver for all relationship apps is "I forgot to use it." Daily prompt creates a return trigger.

**Effort:** S (2–3 hours) — new static arrays + one `@AppStorage` date + a banner view.

**Impact:** High — directly addresses the #1 engagement gap vs. Lasting.

**Deps:** RelationshipType (Phase 1, already built).

---

### P1-N2 — Relationship start date + milestone notification
**What:** Add `relationshipStartDate: Date?` to `Person.swift` (tolerant decoder, additive). For `romanticPartner` and `closeFriend`, fire an annual `UNCalendarNotificationTrigger` on the anniversary: "Today is N years since you and [Name] [became partners / became close friends]. A good day to celebrate." Also surface a card in `TodayView` in `onThisDay`-style alongside meeting anniversaries.

**Why:** Lasting and Paired both celebrate relationship milestones with confetti-style moments. MeetingScribe has birthday notification infrastructure already (`RelationshipNotificationManager.swift:13`) — a start-date anniversary reuses the same pattern with one new notification category.

**User value:** Emotional resonance. Users who see their 3-year anniversary surface in the app feel the product understands their life, not just their calendar.

**Effort:** S — new `Date?` field + one new notification category.

**Impact:** Medium-High — delight moment that drives word-of-mouth.

**Deps:** None (additive to Person model).

---

### P1-N3 — Conflict debrief mode with DEAR MAN / repair scaffolding
**What:** Add a new `ConversationAnalysisPreset` case `.conflictDebrief` (PersonDetailView.swift:23). Prompt template: "Walk through four steps — (1) What happened, in facts only. (2) What you felt. (3) What you need going forward. (4) What repair you could offer." Show this preset only when the most recent encounter has `mood == .tense || .hard` OR when `kind == .difficultConversation` (once that kind lands from the existing plan). Save as `kind = "conflict-debrief"` in `AttachedNote`.

**Why:** BetterHelp and Lasting both have "hard conversation" frameworks. MeetingScribe has the hook (`Encounter.Mood.tense/hard`) but no downstream support. This is the exact moment users are most likely to open the app and need structure.

**User value:** A user who just had a fight with their partner and logs it tense gets a guided debrief, not just a blank note field.

**Effort:** S — one new enum case + one prompt template (~40 lines).

**Impact:** High — highest emotional stakes use case; BetterHelp users switch for exactly this.

**Deps:** `ConversationAnalysisPreset` already exists; no schema change.

---

### P1-N4 — Longitudinal mood trend mini-chart on PersonDetailView
**What:** Add a compact 12-week bar sparkline below the encounter heat map (once built) showing average encounter quality per week. Color: teal = great/good, amber = neutral, red = tense/hard. Requires mood to be a typed field, not a tag string — depends on the `EncounterQuality` field from D5-6.

**Why:** Paired shows "connection over time." Lasting shows sentiment trajectory. MeetingScribe logs mood but buries it in note text as `[mood:tense]` (QuickEncounterSheet.swift:205–206). A 12-week sparkline makes the data visible.

**User value:** "I can see we've been more tense the last 3 weeks" is a coaching insight no standalone journaling app delivers.

**Effort:** M (typed mood field S + sparkline view M).

**Impact:** High — transforms encounter logs from a diary into coaching intelligence.

**Deps:** D5-6 (`EncounterQuality` typed field on `Encounter`), Phase 2 heat map.

---

### P1-N5 — Prompt personalization based on encounter history
**What:** Extend `weeklyPrompt(for:)` to accept an `encounterHistory: [Encounter]` parameter. If the last 3 encounters for a partner all have `mood == .tense`, return a repair-focused prompt from a separate `repairPrompts` array instead of the standard rotation. If `encounterCount < 3`, return an onboarding prompt. This is a pure-function change to `RelationshipPromptLibrary` — no AI call, no server.

**Why:** All three comparators (Lasting, Paired, BetterHelp) adapt content to user state. MeetingScribe's prompts are ISO-week-deterministic and ignore everything the user has logged. A single `if` branch on recent mood history is the minimum viable personalization.

**User value:** "The app noticed we've been having hard conversations and is helping me think about repair" — that's the Lasting moment of "this product gets me."

**Effort:** S — refactor `weeklyPrompt` signature + 5 repair prompts + 5 onboarding prompts.

**Impact:** High — the personalization gap is the single biggest coach-completeness failure.

**Deps:** `EncounterQuality` typed field (D5-6), or use existing mood-tag parsing as a stopgap.

---

### P1-N6 — "How did it go?" follow-up prompt 24h after a tense encounter
**What:** When an encounter is logged with `mood == .tense` or `mood == .hard`, schedule a `UNTimeIntervalNotificationTrigger` for 24 hours later: "[Name] — how are things feeling today after yesterday?" Tapping opens `PersonDetailView` with the quick-log sheet pre-open. One new notification category `RELATIONSHIP_FOLLOWUP` with actions "Better" / "Still processing" / "Log update."

**Why:** BetterHelp's entire value proposition is "ongoing support." Lasting has a next-day check-in after conflict content. MeetingScribe has the notification infrastructure (`RelationshipNotificationManager.swift`) and mood data but does nothing with them post-log.

**User value:** The app follows up — the defining behavior of a coach versus a journal.

**Effort:** S (hours) — reuses existing notification infrastructure.

**Impact:** High — follow-up notification is the habit-loop mechanism that turns a one-time log into an ongoing coaching relationship.

**Deps:** Typed `EncounterQuality` field (for clean mood check), or mood-tag string parsing.

---

### P1-N7 — Connection streak counter (visible, not paywalled)
**What:** Add a computed property `currentStreak(for: Person, encounters: [Encounter], cadenceDays: Int) -> Int` that counts consecutive cadence periods with at least one encounter. Display as a compact badge "🔥 4-week streak" next to the person's name in `PersonDetailView`'s identity panel. Keep the detailed heat map Pro-gated but show the streak badge to all users.

**Why:** Paired's connection streak is its most-shared social feature. The paywall currently gates the heat map behind Pro — but users need *something* visible to feel progress before they pay. A streak integer is trivially cheap to compute and show.

**User value:** Gamification hook — "I've checked in with my mom every week for 8 weeks" creates intrinsic motivation to maintain the streak.

**Effort:** S — pure computed property + one Text badge.

**Impact:** Medium-High — retention lever that costs nothing to show free-tier users.

**Deps:** Phase 2 heat map data (encounter array + cadence), already in `PeopleStore.encounters(for:)`.

---

### P1-N8 — Shared prompt / couple mode (CloudKit-backed, partner opt-in)
**What:** Add an opt-in "shared journal" mode for `romanticPartner` persons only. User generates a shareable iCloud link (CloudKit public record). Partner installs MeetingScribe and accepts the link — both see the same rotating weekly prompt and can each add a private response. Responses stay local; only the prompt selection is shared (tiny CloudKit write). No real-time sync required.

**Why:** This is the one feature Paired has that MeetingScribe structurally cannot replicate without CloudKit — and it's the reason couples choose Paired over a personal journal. It makes the relationship a first-class shared entity.

**User value:** "We're both doing the same weekly reflection" is the entire Paired value prop.

**Effort:** L — CloudKit shared zones, auth flow, deep link handling.

**Impact:** Very High — transforms MeetingScribe from a personal relationship tracker to a couples tool. Largest moat expansion available.

**Deps:** Phase 5 CloudKit `TeamSyncService` stub already exists; adapt for relationship context. `RelationshipStartDate` (P1-N2).

---

### P1-N9 — "Relationship goals" field per person
**What:** Add `relationshipGoals: [String]` (max 3, free-text chips) to `Person`. For partner: "More quality time," "Better conflict repair," "Weekly date night." Surfaced in the identity panel as editable chips. The weekly coaching prompt selector prefers prompts aligned to the declared goal.

**Why:** BetterHelp's first session asks "what are your goals?" Lasting's courses are goal-structured. MeetingScribe has zero mechanism for a user to declare what they're trying to improve — so every prompt is equally irrelevant. Goals give the engine a target.

**User value:** "This app helps me work toward what I actually want in this relationship, not just track what happened."

**Effort:** S–M — `[String]` field on Person + chips UI + goal-to-prompt mapping function.

**Impact:** Medium-High — unlocks intent-driven personalization without any AI call.

**Deps:** P1-11 (loveLanguage/attachmentStyle) for full personalization, but goals alone are valuable standalone.

---

### P1-N10 — "Gratitude log" encounter kind with dedicated prompt
**What:** Add `gratitude` to `Encounter.Kind` in `QuickEncounterSheet.swift`. When selected, replace the free-text note with three pre-labeled fields: "What they did," "How it made you feel," "Did you tell them?" (yes/no). Save as standard encounter with kind=gratitude and notes composed from the three fields. Surface a "Gratitude logged" momentary celebration animation.

**Why:** Gottman's research underpins the 5:1 positive-to-negative ratio. Lasting has an explicit "appreciate your partner" daily prompt. The closest MeetingScribe has is the generic note field. A structured gratitude encounter kind requires zero AI and directly operationalizes Gottman.

**User value:** Builds the positive-logging habit that prevents the app from becoming a grievance log.

**Effort:** S — one new Kind case + a 3-field form variation in `QuickEncounterSheet`.

**Impact:** Medium-High — emotional health of the logging habit; prevents negativity bias in AI analysis.

**Deps:** None (additive to existing QuickEncounterSheet).

---

### P1-N11 — Coach summary card: "How this relationship is going"
**What:** Add a `CoachSummaryCard` view at the top of `PersonDetailView` (above the identity panel, for `supportsDepthContent` types). Shows: (a) last encounter date + mood emoji, (b) streak badge, (c) one sentence of AI-generated "connection temperature" (a lightweight 50-token Ollama call, cached for 24h), (d) today's coaching prompt. This replaces the blank top area and makes the coaching function immediately visible on open.

**Why:** BetterHelp's dashboard shows "how you've been doing" at a glance. Lasting opens to your streak and today's question. MeetingScribe's PersonDetailView opens to the identity panel — no coach framing is visible without scrolling.

**User value:** The product feels like a coach the moment you open a person's profile.

**Effort:** M — new SwiftUI card + 50-token Ollama call + 24h cache.

**Impact:** High — first-impressions redesign of the core coaching surface.

**Deps:** P1-N7 (streak), P1-N1 (daily prompt), Phase 2 heat map data.

---

## Top 3 Picks

1. **P1-N5 — Prompt personalization based on encounter history** — the single biggest gap vs. Lasting. Zero AI cost. Pure logic. Changes the fundamental character of the product from "planner" to "coach."

2. **P1-N3 — Conflict debrief preset** — highest-stakes moment where a coach app must show up. One new enum case + 40-line prompt. S effort, maximum emotional relevance.

3. **P1-N6 — 24h follow-up after tense encounter** — the defining behavior of coaching vs. journaling. Reuses existing notification infrastructure. Creates the habit loop.

---

## Single Highest-Priority Recommendation

**P1-N5 (Prompt personalization based on encounter history).**

The weekly ISO-week rotation in `RelationshipPromptLibrary.weeklyPrompt(for:)` ignores everything the user has logged. A single function-signature change to accept `[Encounter]` and branch on recent mood history turns 28 static strings into a responsive coaching engine — at zero AI cost, zero server calls, and S effort. This is the architectural move that separates MeetingScribe from a static-prompt newsletter and earns the "coach" label the product already claims.
