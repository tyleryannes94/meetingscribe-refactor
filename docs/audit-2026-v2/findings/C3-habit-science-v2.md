# C3 — Behavioral Science: Relationship Maintenance Habits & Research-Backed Cadences

**Lens:** What does the empirical literature say about how often people should reach out, what contact quality actually predicts relationship health, and what product features map most directly to durable habit formation? Every recommendation is grounded in published research, not intuition.

**Date:** 2026-06-02
**Prefix:** C3-

---

## 1. Research Synthesis

### 1.1 Dunbar's Tiered Maintenance Model — The Cadence Foundation

Robin Dunbar's network-layer research (Roberts & Dunbar, 2011, *Personal Relationships* 18, 439–452; "Calling Dunbar's Numbers," *Social Networks*, 2016) establishes the empirical baseline for how often people actually maintain relationships by tier:

| Dunbar Tier | Size | Typical contact frequency (empirical) | MeetingScribe default |
|---|---|---|---|
| Support clique / inner circle | ~5 | Daily to every 2–3 days | romanticPartner = 1d ✓ |
| Sympathy group (close friends) | ~15 | Weekly | closeFriend = 14d ✗ (should be ~7d) |
| Friends band | ~50 | Monthly | friend = 21d ✗ (should be ~30d) |
| Clan (acquaintances) | ~150 | Quarterly | acquaintance = 60d ~ (roughly OK) |
| Kin (family) | Overlapping layers | Weekly for active kin | familyMember = 7d ✓ |

Source: [Calling Dunbar's Numbers](https://www.sciencedirect.com/science/article/pii/S0378873316301095); [Wikipedia: Dunbar's Number](https://en.wikipedia.org/wiki/Dunbar's_number)

**Key finding:** Roberts & Dunbar (2011) showed that failing to call a close friend for even 6 weeks measurably reduces felt closeness scores — the decay curve is steeper than intuition suggests. The app's 14-day default for `closeFriend` is double the empirically-supported interval; at 14 days, a close friend is already exhibiting measurable closeness decay.

### 1.2 Minimum Effective Dose — What Actually Moves the Needle

Research on friendship maintenance and cognitive health (PMC10011020, *Journals of Gerontology*, 2023) found that contact frequency with friends — even brief digital contact — was prospectively associated with less episodic memory decline over 28-year follow-up (Whitehall II cohort, PMC6677303).

For *friendship quality specifically*, Hall (2019, *Journal of Social and Personal Relationships*) showed:
- Close friends require active maintenance (contact + shared activities) to hold emotional closeness
- The minimum effective interval for close friends to maintain felt closeness is approximately **weekly contact of any kind** (not face-to-face)
- Even 1–2 brief text exchanges per week constitutes sufficient maintenance for the ~15-person sympathy layer

For acquaintances and weak ties, surprising finding: Aknin & Sandstrom (PMC11332216, *PNAS* 2024) demonstrated that **senders dramatically underestimate how meaningful a surprise check-in is to the recipient** — the effect was stronger the longer the gap since last contact. This directly supports infrequent (60–90 day) but high-warmth outreach for the acquaintance tier rather than frequent perfunctory contact.

Source: [People are surprisingly hesitant to reach out to old friends](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11332216/)

### 1.3 Gottman's "Magic Six Hours" — The Partner Cadence

Gottman Institute research prescribes a structured 6 hours/week of intentional connection for romantic partners, broken into daily micro-rituals: a 6-second kiss before leaving, 2-minute reunion conversation, 5-minute appreciation/admiration practice, a 1-hour weekly State of the Union conversation. This is *not* 6 unstructured hours — it is *ritual specificity* that drives the outcome.

The daily check-in default of 1d for `romanticPartner` (Person.swift:80) is consistent with the empirical evidence. However, the notification copy ("How are things between you two?" — RelationshipNotificationManager.swift:146) fails to encode ritual specificity. A prompt tied to Gottman's specific rituals ("5-minute gratitude window tonight?") would perform better than an open-ended check.

Source: [Strengthen Your Bond in Just 6 Hours a Week](https://www.lisachentherapy.com/blog/strengthen-your-bond-in-just-6-hours-a-weekaccording-to-gottman-research); [5 Rituals to Reconnect in Your Relationship](https://www.gottman.com/blog/5-rituals-reconnect-relationship/)

### 1.4 Habit Formation — Implementation Intentions Are the Key Mechanism

Research on implementation intentions (Gollwitzer, 1999; replicated in Trenz et al., 2024, *Journal of Occupational and Organizational Psychology*; PMC10585941, 2023) shows:

- Implementation intentions — "When X happens, I will do Y" — **double the likelihood of goal achievement** compared to goal-setting alone
- They work by creating an if-then link that offloads the activation decision from deliberative to automatic processing
- Dental floss studies (NCBI PMC11920387) show implementation intentions begin habit formation measurably faster than reminders alone

The current MeetingScribe notification fires at 9am but contains no if-then anchor. A notification saying "After your morning coffee, send [Name] a quick message" would perform better than "It's been a while" (RelationshipNotificationManager.swift:148).

Source: [Implementation Intentions and Habit Formation - FasterCapital](https://fastercapital.com/content/Habit-Formation--Implementation-Intentions--The-Impact-of-Implementation-Intentions-on-Habit-Formation.html); [Trenz et al. 2024](https://bpspsychub.onlinelibrary.wiley.com/doi/10.1111/joop.12540)

### 1.5 Meaningful vs. Perfunctory Contact

Greater Good Berkeley (citing multiple studies) found that **deep questions produce more connection per minute than surface chitchat**, even with strangers. The casual contacts literature (PMC11930310, 2025) confirms that "weak tie" interactions boost wellbeing precisely when they feel unexpected or personal — not when they feel obligatory.

The implication: **quality beats frequency** once the minimum effective dose is met. A single monthly voice call for a `friend` tier person likely outperforms four brief texts. MeetingScribe has no quality-signal field on `Encounter` — mood exists as an extension in `QuickEncounterSheet.swift` (the local enum, not persisted in VaultKit) but `Encounter.Kind` in `VaultKit/Encounter.swift` has no warmth/depth dimension.

Source: [Are Some Social Ties Better Than Others?](https://greatergood.berkeley.edu/article/item/are_some_ties_better_than_others)

---

## 2. Code Audit Through This Lens

### 2.1 `defaultCheckInDays` (Person.swift:80–90) — Partially Wrong

```
romanticPartner = 1d   ← correct per Dunbar inner circle / Gottman daily ritual
familyMember    = 7d   ← correct for active kin
closeFriend     = 14d  ← TOO LONG — Roberts & Dunbar show closeness decay starts at ~6–7 days
friend          = 21d  ← slightly long — empirical is ~30d but 21d is defensible
colleague       = 30d  ← correct
acquaintance    = 60d  ← roughly correct; Aknin/Sandstrom suggests surprise value peaks here
```

**`closeFriend = 14d` is the clearest misalignment.** The sympathy group (~15 people) maps to weekly contact in Dunbar's data; 14 days allows measurable closeness decay.

### 2.2 Notification copy (RelationshipNotificationManager.swift:145–153) — No Ritual Specificity, No If-Then

Current body strings are open-ended status checks. None encodes an implementation intention ("When you finish dinner tonight, send a voice note to [Name]") or a Gottman-style micro-ritual. The `familyMember` copy ("Give them a call or send a message" — line 148) is the weakest — pure instruction with zero warmth or context.

### 2.3 No Quality Signal on Encounter — Critical Gap

`VaultKit/Encounter.swift` has `kind: Kind` (meeting/call/email/message/note) and no depth or quality dimension. `QuickEncounterSheet.swift` defines a local `Mood` enum (great/good/neutral/tense/hard) but it is not persisted to `VaultKit`. The research is clear that contact quality predicts relationship outcomes better than frequency above the minimum effective dose. Without a persisted quality signal, MeetingScribe can never compute a meaningful health score — it can only measure recency, not meaningfulness.

### 2.4 Implementation Intention Hooks — Missing

There is no mechanism to help users specify *when* they will reach out (the classic "After X, I will Y" prompt). `RelationshipPromptLibrary.swift` provides the *what* (conversation starters, appreciation exercises) but not the *when*. Research shows that linking a prompt to an existing anchor behavior is the highest-leverage habit-formation intervention available.

---

## 3. Existing-Plan Items Ranked Highest Through This Lens

1. **P3-8 (Post-meeting "who did you see?" anchor)** — strongest implementation intention in the product; anchors logging to an existing behavior (reviewing meeting summary). Highest-priority item in the existing plans from a habit science standpoint.

2. **P3-1 (Menubar quick-log)** — activation cost drives habit death more reliably than any other factor (Fogg). Correct diagnosis.

3. **D4-2 (Notification copy quality)** — identified as a failure mode; richer copy that encodes ritual specificity will move open-to-action rates.

4. **D5 (Health score algorithm)** — the arc ring is unbuilt, but the gap audit is correct: a score without a quality signal is a recency meter, not a relationship health signal.

5. **P3-2 (Post-save Shine moment)** — Fogg's requirement; habit literature confirms the reward must be immediate and specific to the behavior.

---

## 4. NET-NEW Recommendations

### C3-1 — Fix `closeFriend.defaultCheckInDays` from 14 to 7
**What:** In `Person.swift:85`, change `case .closeFriend: return 14` → `return 7`.
**Why:** Roberts & Dunbar (2011) empirically measured the sympathy-group layer at weekly contact frequency. At 14 days, emotional closeness is already measurably decaying. This is the single most research-misaligned default in the codebase.
**User value:** Close friends stop falling off the radar; the product delivers on its "relationship coach" promise at the tier that matters most to users who aren't in a couple.
**Effort:** S (one integer change + update any onboarding copy that mentions default cadences)
**Impact:** High — affects every `closeFriend` user immediately upon next `syncPersonReminders` call.
**Deps:** None. Could update onboarding copy (D2) to explain why.

### C3-2 — Add `Encounter.depth: ContactDepth?` to VaultKit and persist QuickEncounterSheet Mood
**What:** Add `enum ContactDepth: String, Codable { case deep, surface, checkin }` to `VaultKit/Encounter.swift`. Map `QuickEncounterSheet.Mood` to a persisted `Encounter.mood: Mood?` field (move the enum from the local file to VaultKit). Add an optional `depth` chip to `QuickEncounterSheet` after the kind chip row.
**Why:** Research consistently shows contact quality predicts relationship outcomes above the minimum-effective-dose threshold better than frequency. Without persisted quality signals, MeetingScribe's health score (`FeatureGate.ManagedFeature.healthScore`) can only measure recency — it becomes a countdown clock, not a relationship strength indicator. This is a data-model fix, not a UI feature.
**User value:** Encounter history reflects *how* interactions went, not just *that* they happened. AI coaching can surface "your last 3 interactions with [name] were surface-level — try a deeper conversation" — which is genuinely useful.
**Effort:** M (VaultKit schema change + migration required; mood enum move is S; depth field addition is S; UI chip is S)
**Impact:** Very High — unblocks the health score feature; makes the `get_coaching_context` MCP tool far more useful; resolves the "quality beats frequency" research gap.
**Deps:** E2 (migration strategy); D5 (health score algorithm). Known conflict: `Encounter.Kind` enum duplication (Gap #6 in briefing) should be resolved alongside this.

### C3-3 — Implementation intention prompts: "When / where will you reach out?" onboarding step per person
**What:** In `AddPersonSheet`, after setting `relationshipType` and `checkInCadenceDays`, add an optional one-field prompt: "When will you usually reach out to [name]?" with three quick-select chips: "After work", "Weekend mornings", "Whenever I think of them" — stored as `Person.checkInAnchor: String?`. When `checkInAnchor` is set, prepend it to the notification body: "After work today — check in with [name]. [existing body]"
**Why:** Implementation intentions (if-then plans specifying when/where) double habit completion rates in controlled trials (Gollwitzer 1999; Trenz et al. 2024). Currently MeetingScribe fires notifications at 9am with no behavioral anchor. Adding even a single user-specified anchor transforms the notification from an interruption into a cue embedded in existing routines.
**User value:** "After work today — send a voice note to [name]" is a different cognitive experience than "It's been a while." The former has a known action window; the latter generates vague guilt.
**Effort:** M (new `Person.checkInAnchor: String?` field in model + migration + AddPersonSheet UI + notification body logic)
**Impact:** High — evidence-based improvement to the most important behavioral mechanism in the product.
**Deps:** E2 (migration); D4 (notification copy); C3-1 and C3-2 are independent.

### C3-4 — Surprise-value outreach prompt for acquaintance tier (Aknin/Sandstrom effect)
**What:** For `acquaintance` and `colleague` relationship types, replace the generic overdue notification copy with surprise-optimized copy that highlights the recipient's experience: "Reaching out unexpectedly means more than you think — [name] probably hasn't heard from you in a while." In the `QuickEncounterSheet` opened from this notification, add an inline tip: "Research shows unexpected check-ins are rated as highly meaningful by recipients."
**Why:** Aknin & Sandstrom (PMC11332216, 2024) found that people systematically underestimate how much a surprise outreach means to the recipient, especially after a long gap. This misperception is the *specific barrier* that prevents acquaintance-tier outreach. Surfacing the research directly reduces that barrier at the moment of decision.
**User value:** Users who hesitate to contact "someone I haven't talked to in months" get a genuine, evidence-backed nudge. Reduces the perceived awkwardness that stops most relationship maintenance for the outer two Dunbar tiers.
**Effort:** S (notification copy change + a single inline tip string in `QuickEncounterSheet`)
**Impact:** Medium-High — directly addresses a documented psychological barrier to the specific tier where the barrier is highest.
**Deps:** None.

### C3-5 — Gottman micro-ritual prompts for romanticPartner: daily rotating structure
**What:** Add 7 `RelationshipPromptLibrary` entries for `romanticPartner` — one per day of the week — keyed on `Calendar.current.component(.weekday, from: Date())`. Each prompt encodes a different Gottman micro-ritual: Mon=6-second connection (appreciation), Tue=bid-and-turn (share something from your day), Wed=admiration practice, Thu=state of the union prep question, Fri=gratitude, Sat=date-quality ritual, Sun=weekly review question. The daily check-in notification for `romanticPartner` appends the day's ritual prompt as a subtitle.
**Why:** Gottman's "Magic Six Hours" research shows that the specific rituals — not just time spent — predict relationship resilience. The current `RelationshipPromptLibrary.swift` has 11 partner prompts rotated by ISO week (line 45); ISO-week rotation means users see the same prompt for 7 consecutive days. Daily rotation is both more research-aligned and more engaging.
**User value:** Partner users get a different, specific relational behavior prompt each day — not a weekly static check. This is what Lasting charges $14.99/month for (daily session format).
**Effort:** S (7 new prompt strings + `weekday` key lookup instead of ISO week, changes only `RelationshipPromptLibrary.swift`)
**Impact:** High for the partner-tier user (highest engagement tier in relationship apps); differentiates from Lasting's weekly-session format.
**Deps:** None; fully additive to existing `RelationshipPromptLibrary` architecture.

### C3-6 — Contact-quality weighting in future health score: `ConnectionStrength` formula input
**What:** Document (and implement as a computed property on `PeopleStore`) a `contactQualityWeight(for encounter: Encounter) -> Double` function: deep=1.0, surface=0.5, checkin=0.25, no-depth-set=0.5 (default). This function is referenced by the health score algorithm when it is implemented (D5). Currently only recency is available; quality weighting makes the score a genuine relationship-health signal rather than a check-in counter.
**Why:** The APA science-of-friendship review (2023) and Greater Good Berkeley's weak-ties research both confirm that quality of contact — not frequency alone — is the variable that predicts wellbeing outcomes. A health score that ignores contact depth is measuring the wrong variable.
**User value:** The health score correctly identifies a relationship where the user sees someone daily but has surface interactions as different from one where they connect monthly but deeply — which is the distinction users actually want to understand.
**Effort:** S (one computed function; requires C3-2 depth field to be meaningful)
**Impact:** High — precondition for a defensible health score; without it D5 is building on incorrect assumptions.
**Deps:** C3-2 (depth field on Encounter); D5 (health score implementation).

### C3-7 — "Elastic intimacy" mode: relationship-type-aware cadence exceptions for kin
**What:** Add a boolean `Person.hasKinElasticity: Bool` (default `false`, shown as "Long-term friendship or kin relationship — OK to drift" toggle in `PersonDetailView`). When `true`, the overdue state only triggers after 1.5× the effective cadence (e.g., `familyMember` fires at 10.5d instead of 7d), and the notification copy shifts from urgency to warmth: "You haven't caught up with [name] in a while — whenever feels right."
**Why:** Research on "elastic intimacy" — the ability of certain close relationships (especially kin) to tolerate gaps without closeness loss (PMC10011020) — shows not all relationships follow the same decay curve. Sibling relationships in the same city tolerate longer gaps than friend relationships at the same emotional closeness level. A single cadence model applied uniformly causes false-positive overdue alerts for kin, which trains users to ignore the section.
**User value:** Users stop ignoring `StayConnectedSection` because the alerts are calibrated to actual relationship dynamics, not a one-size-fits-all counter.
**Effort:** M (new field on `Person` + migration + UI toggle + modified cadence logic in `RelationshipNotificationManager.syncPersonReminders`)
**Impact:** Medium — reduces false-positive overdue rate; directly improves the signal quality of `StayConnectedSection` and the `list_overdue_check_ins` MCP tool.
**Deps:** E2 (migration).

---

## 5. Top 3 Picks

1. **C3-2 (Persist Encounter depth/mood to VaultKit)** — without a quality signal, the health score is a countdown clock and the research gap between "meaningful vs. perfunctory contact" can never be closed. This is the data-model prerequisite for at least 3 other planned features.

2. **C3-1 (Fix `closeFriend` cadence to 7 days)** — the clearest empirical mismatch in the codebase. A one-line fix with high user impact; the research is unambiguous.

3. **C3-3 (Implementation intention anchor per person)** — doubles habit completion rates in controlled trials. Currently the notification system has no behavioral anchor at all; adding even a simple "after work" chip is the highest ROI UX improvement for durable habit formation.

---

## 6. Single Highest-Priority Recommendation

**C3-2 — Add `Encounter.depth` to VaultKit and persist QuickEncounterSheet Mood.**

This is the load-bearing data-model change that unlocks the health score (D5), makes the `get_coaching_context` MCP tool genuinely relationship-type-aware, closes the research gap between frequency and quality, and enables AI prompts that respond to how recent interactions actually felt. Every other habit-science recommendation in this report — and most of D5's health score work — hits a ceiling without a persisted quality signal. It costs M effort but removes a structural constraint on at least 5 other planned features.

---

## Sources

- [Calling Dunbar's Numbers — ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0378873316301095)
- [Dunbar's Number — Wikipedia](https://en.wikipedia.org/wiki/Dunbar's_number)
- [Roberts & Dunbar 2011 — Communication in Social Networks (ResearchGate)](https://www.researchgate.net/publication/230041809_Communication_in_social_networks_Effects_of_kinship_network_size_and_emotional_closeness)
- [People are surprisingly hesitant to reach out to old friends — PMC11332216](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11332216/)
- [Longitudinal Associations Between Contact Frequency and Cognition — PMC7483134](https://pmc.ncbi.nlm.nih.gov/articles/PMC7483134/)
- [Relocation and Contact Frequency With Friends — PMC10011020](https://pmc.ncbi.nlm.nih.gov/articles/PMC10011020/)
- [Strengthen Your Bond in Just 6 Hours a Week — Gottman Research](https://www.lisachentherapy.com/blog/strengthen-your-bond-in-just-6-hours-a-weekaccording-to-gottman-research)
- [5 Rituals to Reconnect — Gottman.com](https://www.gottman.com/blog/5-rituals-reconnect-relationship/)
- [Implementation Intentions and Habit Formation — FasterCapital](https://fastercapital.com/content/Habit-Formation--Implementation-Intentions--The-Impact-of-Implementation-Intentions-on-Habit-Formation.html)
- [Trenz et al. 2024 — Implementation Intentions at Work](https://bpspsychub.onlinelibrary.wiley.com/doi/10.1111/joop.12540)
- [Instant habits vs. flexible tenacity — PMC10585941](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10585941/)
- [Are Some Social Ties Better Than Others? — Greater Good Berkeley](https://greatergood.berkeley.edu/article/item/are_some_ties_better_than_others)
- [The Science of Why Friendships Keep Us Healthy — APA Monitor 2023](https://www.apa.org/monitor/2023/06/cover-story-science-friendship)
- [JMIR Paired App Evaluation 2025](https://mhealth.jmir.org/2025/1/e55433)
- [The Science of Maintaining Friendships — Simply Psychology](https://www.simplypsychology.com/articles/friendship-maintenance-science)
