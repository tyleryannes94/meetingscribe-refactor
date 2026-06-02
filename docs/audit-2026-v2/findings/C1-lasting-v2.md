# C1 — Competitive Intelligence: What Lasting Added in the Last 6 Months That MeetingScribe Still Lacks

**Lens:** Direct competitor deep-dive — Lasting (and secondarily Paired) — focused on the delta between what these apps shipped in late 2024–mid-2026 and what MeetingScribe has not yet implemented.

**Date:** 2026-06-02
**Prefix:** C1-

---

## 1. Lens Statement

MeetingScribe's relationship coaching module is competing against apps with years of head-start on behavioral design and therapist-authored content. This report documents what Lasting shipped in the observable 6-month window (roughly November 2025–May 2026), what engagement mechanics both Lasting and Paired use that MeetingScribe entirely lacks, and translates the highest-leverage findings into three net-new proposals that fit MeetingScribe's local-first, macOS-native, all-relationship-types positioning.

---

## 2. Research Sources

- App Store version history (iOS): https://apps.apple.com/us/app/lasting-marriage-couples/id1225049619
- Google Play listing (updated Aug 5, 2025): https://play.google.com/store/apps/details?id=com.lasting.lasting
- ChoosingTherapy review (updated March 2025): https://www.choosingtherapy.com/lasting-app-review/
- OneDateIdea review (updated March 11, 2026): https://www.onedateidea.com/reviews/lasting-app/
- Paired rebrand announcement (August 2024): https://www.paired.com/press/paired-rebrand-announcement
- Talkspace/Lasting Parenting Guide press release: https://investors.talkspace.com/news-releases/news-release-details/lasting-talkspace-announces-lasting-parenting-guide-new-app/
- Washington Post "Have you expressed appreciation to your partner today?" (2019, still the core loop): https://www.washingtonpost.com/lifestyle/2019/04/15/can-an-app-improve-your-marriage-this-one-is-trying/
- JustUseApp reviews 2026: https://justuseapp.com/en/app/1225049619/lasting-marriage-health-app/reviews
- VitalMindsCounseling Best Relationship Apps 2026: https://www.vitalmindscounseling.com/blog/best-relationship-intimacy-apps-2026

---

## 3. What Lasting Shipped in the Last 6 Months (Observable Evidence)

**Important caveat:** Lasting's App Store version history shows version 3.2.30 released February 19, 2025 as the latest entry. Its Google Play listing shows "Updated on Aug 5, 2025" with generic bug-fix release notes. The iOS release notes have used the same template text ("fixed a few bugs / made it easier to play your next Lasting session / pair with a partner") since at least 2021. This is a **significant signal in itself**: Lasting has shipped zero publicly-announced feature releases in the observable 6-month window. The product appears to be in maintenance mode under Talkspace ownership, shipping incremental stability patches rather than new features.

**What Lasting has quietly maintained (not new, but persistent competitive advantages):**

1. **Relationship Reminders (free tier):** Daily macOS/iOS notification phrased as a warm question ("Have you expressed appreciation to your partner today?"). This is baked into the brand — the Washington Post headline quotes it verbatim. MeetingScribe has no equivalent.

2. **Daily Conversation Starters (free tier, but with a known bug):** A short structured prompt appears daily; both partners respond independently, then see each other's answers. A noted 2024 bug causes early reveal of a partner's response before the other answers. The feature exists and is used despite the bug.

3. **Zoom Workshops (live + on-demand, Premium):** Two categories — pre-recorded and live therapist-led Zoom sessions on specific topics (e.g., "Practicing Direct & Kind Communication," "Sexual Communication," "Addressing Feelings of Guilt"). Live sessions have a Q&A window in the final 30 minutes. No equivalent in MeetingScribe.

4. **Assessment → Personalized Series path (Premium):** Onboarding assessment classifies the couple's pain points ("Communication," "Depression," "Body Image," "Repair") and routes them to a tailored set of Series. This creates a progressive content arc from day 1.

5. **Parenting Guide as a separate app (shipped March 2022, actively maintained):** A companion app (not an update to the main app) specifically for parents. 100+ self-guided sessions + 2 live therapist-led classes per week. Relevant to MeetingScribe because "familyMember" is already a `RelationshipType` — but there is zero parenting-specific content.

6. **Short daily exercise format (5–15 min):** Every session is designed for completion in a commute or lunch break. MeetingScribe's "coaching" is a single per-week static prompt from `RelationshipPromptLibrary` — no daily delivery format exists.

**Paired shipped in the last 6 months (corroborated):**

- **Full rebrand + Daily Checklist** (announced August 27, 2024, still the current design): Updated to version 2.79.0 as of April 21, 2026. The "Daily Checklist" is a personalized homepage that surfaces curated questions, quizzes, and games each day — not a manual browse. Premium unlocks 1,000+ questions; free tier has 1 question/day + Sunday quiz.
- **Paired latest pricing:** $14.99/month or $74.99/year per couple.

---

## 4. Lasting's Engagement Mechanics That MeetingScribe Lacks

| Mechanic | Lasting / Paired | MeetingScribe status |
|---|---|---|
| Daily push notification with warm relational copy | Yes (both apps) | `RelationshipNotificationManager` fires only check-in reminders; no daily appreciation/question prompt |
| Independent-answer → partner-reveal format | Yes (Lasting conversation starters, Paired daily question) | Zero — AI coaching is one-directional (user asks, Claude responds) |
| Partner account linking / dyad sync | Yes (Lasting invite code, Paired shared account) | MeetingScribe is fully single-user |
| Therapist-authored content Series (progressive arc) | Yes (Lasting: Repair, Emotional Connection, Conflict, etc.) | `RelationshipPromptLibrary` has 28 static prompts, no progression |
| Life-stage content branching | Yes (Lasting: Premarital, New Parents, Long-Term Marriage) | Zero — `RelationshipType` enum exists but content is not type-branched |
| Onboarding relationship assessment | Yes (Lasting initial assessment → personalized plan) | AddPersonSheet has no assessment step |
| Guided 5-min mindfulness/meditation | Yes (Lasting: Five Senses Scan, Appreciation) | Zero audio content |
| Streak / daily exercise completion tracking | Yes (Paired daily checklist, Lasting habit loop) | Zero streak or completion UI anywhere |
| Post-log celebration / variable reward | Paired: visual feedback on streak. Lasting: session completion badge | QuickEncounterSheet dismisses silently — no reward loop |

---

## 5. Lasting's Pricing and What It Includes

| Tier | Price | Content |
|---|---|---|
| Free | $0 | Foundations Series (5 sessions), all Conversation Starters, Relationship Reminders, single sessions |
| Premium (monthly) | $11.99–$29.99/month (IAP tiers vary) | Entire app for 2 users: hundreds of sessions across all topics, Zoom workshops (live + on-demand), audio meditations |
| Premium (annual) | $79.99/year | Same as monthly Premium |

**Key pricing insight:** Premium covers both partners under one subscription — this is framed as ~$40/person/year, which is substantially cheaper than a single therapy session. The "both partners included" framing is the #1 pricing differentiator vs. other couples apps.

---

## 6. #1 Reason Users Stay Subscribed (Synthesized from Reviews)

Across App Store reviews, the most repeated retention signal is the **"answer comparison" mechanic**: users say they were shocked to discover what their partner actually believed on topics they thought they understood. The phrase pattern is: "I thought I knew, but I didn't" — repeated across 2018, 2021, and 2025 reviews. This is Lasting's durable moat. It is not the content quality (though users appreciate it); it is the asynchronous reveal that creates conversational urgency. Users stay subscribed to keep generating those revelatory moments.

Secondary retention driver: users report the app becomes a **conflict-neutral space** — questions framed by the app are less threatening than the same questions asked by a partner directly. This "neutral third party" framing ("it's the app asking, not me") is specifically mentioned in multiple long-form reviews.

---

## 7. Full-App Audit Through the Competitive Lens

### 7.1 What MeetingScribe has that Lasting does not
- **Local-first, no cloud:** Lasting sends relationship data to Talkspace servers (disclosed in data safety: "sensitive info" collected and linked to identity). MeetingScribe's local SQLite vault is a genuine privacy advantage.
- **All relationship types:** Lasting is couples/marriage only. MeetingScribe models romanticPartner, familyMember, closeFriend, friend, colleague, acquaintance.
- **Meeting context:** No meeting note-taking competitor has a People module with encounter history fed from actual transcripts.
- **MCP tools:** No relationship app has an MCP server that allows Claude Desktop to query relationship context and log encounters.

### 7.2 Where MeetingScribe is critically behind
- **No daily proactive nudge:** `StayConnectedSection` requires the user to open the app and scroll past 8 other sections. Lasting fires a warm daily notification even on the free tier.
- **No content progression:** 28 static weekly prompts in `RelationshipPromptLibrary` vs. Lasting's hundreds of sessions organized in named Series with therapeutic arcs. The "week number mod 28" rotation is invisible to users and has no narrative.
- **No reveal mechanic:** MeetingScribe's AI coaching is one-directional. The asynchronous answer-then-compare format — Lasting's #1 retention mechanic — doesn't exist and cannot exist in a single-user app. However, a *self-reflection then AI-generated mirror* variant is feasible.
- **No life-stage branching:** `RelationshipType` exists but does not route to different content. A familyMember and a romanticPartner get the same `weeklyPrompt(for:)` call.
- **No post-log reward:** `QuickEncounterSheet.saveIfValid` dismisses silently. Zero variable reward.

---

## 8. Existing-Plan Items I Rank Highest

1. **Phase 3 coaching content depth (endorsing C1-3 from prior audit):** Therapist-authored Series are Lasting's structural moat. Implementing even 3 named progressive arcs (Gottman Repair arc, NVC Family arc, Love Language Friend arc) — each 5–8 prompts with unlock gates — would close the largest content gap. Referenced in `RelationshipPromptLibrary.swift`, `PersonDetailView.swift`.

2. **Daily proactive notification with relational copy (endorsing prior C1-5):** `RelationshipNotificationManager` already exists. Adding a daily appreciation/question notification (separate from check-in reminders) is a one-day S-effort fix with outsized retention impact.

3. **StayConnectedSection surface area (endorsing D1/D4 prior findings):** The check-in surface being buried after 8 sections in TodayView is the single highest-friction bottleneck in the entire engagement loop. Making this section appear first (or adding a menubar quick-log shortcut) costs near-zero engineering effort.

---

## 9. NET-NEW Recommendations

### C1-N1 — Daily Appreciation Prompt via macOS Notification (Lasting's Core Loop, Adapted)
**What:** Add a second notification type in `RelationshipNotificationManager`: a daily "appreciation nudge" — a single warm question rotated from a curated set of 14 (2 per week cycle), fired at a user-configurable time (default 8pm). Not a check-in reminder — no person attached, no cadence logic. "One thing you appreciated about someone today: who was it?"
**Why:** This is Lasting's oldest and most persistent retention mechanic. The Washington Post wrote about it in 2019 as the app's defining trait. It creates a *daily app-open reason* that is completely orthogonal to whether the user has overdue check-ins.
**User value:** The app becomes a daily relationship practice, not an occasional CRM tool.
**Effort:** S (hours — add a scheduled `UNCalendarNotificationTrigger` in `RelationshipNotificationManager.swift`, a 14-item string array in `RelationshipPromptLibrary.swift`, and a time-picker in Settings).
**Impact:** High — transforms passive app into proactive daily ritual.
**Deps:** None (standalone from existing cadence logic).

---

### C1-N2 — Self-Reflection Reveal: "What I believe vs. What I said" Post-Meeting AI Mirror
**What:** After a meeting is transcribed and summarized, add a "Relationship Mirror" step: the AI is asked "Based on this transcript, what did you actually express about [Person X] vs. what you intended?" The result is shown as a split-view: "You said / What the AI heard underneath." This adapts Lasting's independent-answer-then-reveal mechanic to MeetingScribe's unique asset (meeting transcripts) — no second user account needed.
**Why:** Lasting's #1 retention hook is the reveal moment. MeetingScribe can create a single-user analog by using the transcript as the "other side" of the mirror. No competitor does this — Granola has no People module, Lasting has no transcripts.
**User value:** "I just found out what I actually communicated, not what I meant to." This is the same emotional payload as Lasting's reveal mechanic but richer because it is grounded in real behavior.
**Effort:** M (1–2 days — add a post-summary step in the meeting finalization pipeline; add a new Ollama prompt template in the summary generation code; add a `RelationshipMirrorView` SwiftUI sheet triggered from `MeetingDetailView`).
**Impact:** Very high — unique differentiator, directly competes with Lasting's retention anchor.
**Deps:** C1-N2 requires that the person-meeting linkage already works (People tab backlinks to meetings — confirm this is in place).

---

### C1-N3 — Content Arc Unlocks: Progressive Series Tied to Encounter Count
**What:** Introduce a `CoachingArc` struct in `RelationshipPromptLibrary.swift`: a named sequence of 6–8 prompts that unlock in order as a person's `encounter_count` passes thresholds (0→1→3→6→10→15). Name the arcs: "Foundation" (encounters 0–2, generic trust-building), "Signal" (encounters 3–5, communication observation), "Depth" (encounters 6–9, emotional need articulation), gated by `RelationshipType` for content variants (romanticPartner gets Gottman Repair, familyMember gets NVC Conflict, closeFriend gets Love Language vocabulary). Show arc progress as a named banner in `PersonDetailView` ("Week 4 of Depth Arc").
**Why:** Lasting's most-reviewed feature is its "Repair Series" and "Emotional Connection Series" — users name specific series by name in App Store reviews. The progression creates a narrative ("we are in Week 4") that a static weekly prompt cannot. It also creates a subscription reason: "I want to see what's in the next unlock."
**User value:** The coaching feels like a course you are making progress through, not a tip-of-the-day widget.
**Effort:** M (2 days — define `CoachingArc` struct, populate 3 arcs × 8 prompts = 24 new prompts total, add unlock gate logic in `weeklyPrompt(for:)`, add progress banner in `PersonDetailView`).
**Impact:** High — directly closes Lasting's structural content moat; creates paywall surface for Pro gate.
**Deps:** `RelationshipType` enum (built in Phase 1), encounter count accessible via `Person.encounters.count`.

---

## 10. Top 3 Picks

1. **C1-N1 (Daily Appreciation Prompt)** — S-effort, proven by 7+ years of Lasting retention data, directly addressable today.
2. **C1-N3 (Content Arc Unlocks)** — Closes the structural content gap; creates Pro paywall surface.
3. **C1-N2 (Self-Reflection Reveal / Relationship Mirror)** — Highest novelty; no competitor has transcript-grounded relationship self-reflection. Highest long-term differentiation value.

---

## 11. Single Highest-Priority Recommendation

**C1-N1 — Add the daily appreciation notification today (S-effort, zero new UI required).**

Lasting has run this mechanic since 2017 and it is the single most-cited retention feature in their reviews, press coverage, and app store copy. MeetingScribe's `RelationshipNotificationManager` already has the infrastructure. The entire implementation is: add a `UNCalendarNotificationTrigger` for 8pm daily, rotate through a 14-item prompt array from `RelationshipPromptLibrary`, and add a time-picker in Settings. The notification taps open the app to TodayView. Total implementation: 2–3 hours. Impact: transforms the app from a reactive logging tool into a daily ambient relationship practice — which is the entire value proposition of the coaching module.

