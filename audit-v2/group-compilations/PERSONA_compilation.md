# Persona Group Compilation — MeetingScribe v2 Audit

**Agents:** U1 (Daily Executive), U2 (Relationship Manager), U3 (PM / Researcher), U4 (High-Velocity Founder), U5 (Non-Technical / New Adopter)  
**Compiled by:** U5

---

## Convergence within this group (items 2+ agents raised independently)

### 1. followUpsSection and decisionsSection are buried in "More" — all five personas suffer
- U1: "followUpsSection is hidden behind moreSection disclosure (TodayView.swift:344)" — exec misses follow-ups at end of day
- U3: "TodayView decisionsSection (TodayView.swift:437) right place for a recent decisions feed; needs date-range filtering"
- U5: "Heavy content hidden behind disclosure means new users never discover it exists"
- **Verdict:** Unmuting these sections (show when non-empty, hide when empty) is the highest-ROI S-effort change in the whole Today view.

### 2. PreMeetingBriefView is invisible until the user knows to look for it
- U1: "Requires manual navigation — no push to Today" (TodayView.swift:66 upNextCard lacks brief preview)
- U2: "No 'prep brief' button on the Person profile itself — it's only inside a meeting's transcript tab" (MeetingTranscriptTab.swift:28)
- U5: "Only discovered after recording a meeting, navigating to Meetings tab, selecting the meeting, then finding the tab"
- **Verdict:** The brief needs to be proactively pushed (U1-1), accessible from Person profiles (U2-1), and explained to new users (U5-1 / U5-3).

### 3. turnaroundCard is too narrow and too late
- U1: "15-min window only (TodayView.swift:167) — too late for any meaningful prep"
- U4: "No between-calls capture mode — 5-minute gap between 10 meetings is the highest-leverage capture window"
- **Verdict:** Expand to a 30-minute dual-panel (U1-2) and add transit-session context (U4-4).

### 4. AI/Ollama features are powerful but invisible to users
- U5: "Chat has no suggested prompts; new users don't know it exists"
- U4: "Voice note pipeline runs Ollama polish but never auto-extracts tasks or links people"
- U3: "Embeddings exist but are never exposed to users in search or decision retrieval"
- U1: "BriefCache warms only on manual open — proactive background warming would cost nothing"
- **Verdict:** Ollama is always running at zero marginal cost. The bottleneck is not AI capability — it is the complete absence of proactive intelligence delivery to the user without them asking first.

### 5. No end-to-end "what happened today / this week" proactive surface
- U1: "No dedicated Friday/week-end surface; WeeklyRecap is pull-only and triggered only from GlobalSearch (GlobalSearchView.swift:449)"
- U3: "No quarterly roll-up; user must open N weekly recaps and copy-paste"
- U4: "StandupDigest is pull-only, shallow, not pushed"
- U5: "New users never discover any of these features because there is no milestone that surfaces them"
- **Verdict:** Every persona independently discovered that the app generates useful periodic intelligence but never delivers it unprompted.

### 6. People data is underconnected across tabs
- U2: "No commitment ledger per person; only global owe/owed at TodayView.swift:399"
- U3: "Decisions have no ownerPersonID (DecisionStore.swift:6–12)"
- U4: "Voice notes mention people but PersonResolver is never triggered"
- U5: "People tab is entirely invisible in the new-user journey"
- **Verdict:** People is described as "the connective tissue of the whole second brain" in the briefing, but it is the least connected tab in practice.

### 7. Capture is tab-gated when it should be app-global
- U4: "TaskQuickAddParser only triggerable from inside the Tasks tab (no system-wide hotkey)"
- U4: "Voice note requires navigating to Notes tab — 3+ interactions"
- U1: "turnaroundCard offers one-tap add action item but only in a 15-minute window"
- U5: "Import meeting recording is the fallback empty state action — wrong for new users"
- **Verdict:** Every capture flow (task, voice note, encounter) requires the user to already be in the right tab. A global capture bar (U4-1) would remove the navigation tax for all personas.

---

## All net-new recommendations (deduplicated, with source agent IDs)

| ID | Title | Effort | Impact | Source |
|----|-------|--------|--------|--------|
| U1-1 | Proactive Morning Brief Push to Today | M | High | U1 |
| U1-2 | Expanded turnaroundCard: "Just Ended / Up Next" Dual Panel | M | High | U1 |
| U1-3 | End-of-Day Digest Mode | L | High | U1 |
| U1-4 | Friday Weekly Intelligence Report (Proactive) | M | High | U1 |
| U1-5 | Promote followUpsSection + decisionsSection Out of "More" | S | High | U1 |
| U1-6 | Live Brief Injection into Recording Notes | S | High | U1 |
| U2-1 | One-Click "Brief Me" Button on Every Person Profile | M | High | U2 |
| U2-2 | Commitment Ledger Per Person | S | High | U2 |
| U2-3 | Multi-Signal Relationship Health (iMessage + Meeting Mentions) | M | High | U2 |
| U2-4 | Conference / Event Rapid-Capture Mode | M | High | U2 |
| U2-5 | Relationship Trajectory Sparkline on Board Cards | S | Med | U2 |
| U2-6 | Proactive Weekly Relationship Brief (Notification + Today Widget) | M | High | U2 |
| U2-7 | talkingPoint Aging + Auto-Surface in Pre-Meeting Brief | S | Med | U2 |
| U2-8 | Reconnect Opener from Board Card (Not Just Profile) | S | Med | U2 |
| U3-1 | Decision Rationale Extraction — enrich Decision struct | M | High | U3 |
| U3-2 | Decision FTS + Semantic Index | M | High | U3 |
| U3-3 | Topic-Clustered Decision Ledger View | L | High | U3 |
| U3-4 | Quarterly Recap Generator | M | High | U3 |
| U3-5 | "Why did we decide X?" Chat Tool | S | High | U3 |
| U3-6 | Project History Timeline in Tasks | M | High | U3 |
| U3-7 | "Discussed in these meetings" Backlink on Every Decision | S | Med | U3 |
| U4-1 | Global Capture Bar (⌘⇧Space) | M | High | U4 |
| U4-2 | Voice Note → Auto-Extract Pipeline (tasks + people) | M | High | U4 |
| U4-3 | "Waiting On" Board — First-Class Delegation View | M | High | U4 |
| U4-4 | Between-Calls Context Session | L | High | U4 |
| U4-5 | Proactive StandupDigest Push + Delegation Rollup | S | High | U4 |
| U4-6 | Menubar Quick-Record with 1-Tap Stop | M | High | U4 |
| U5-1 | Post-Onboarding "First Steps" Card on Today | S | High | U5 |
| U5-2 | Screen Recording Plain-Language Rewrite + Visual Explainer | S | High | U5 |
| U5-3 | "First Meeting Ready" Notification + Guided Tour | M | High | U5 |
| U5-4 | Chat Suggested Prompts for New Users | S | High | U5 |
| U5-5 | Ollama Health Check with Plain-Language Recovery UI | M | High | U5 |

---

## Group's top 10 picks with rationale

**#1 — U1-5: Promote followUpsSection + decisionsSection Out of "More"**  
S effort, impacts every persona every day. Follow-ups are time-sensitive (rot within 24h); hiding them behind a disclosure is a trust failure. This is the highest ROI change in the entire group — one afternoon of refactoring gives every user immediate daily value.

**#2 — U5-3: "First Meeting Ready" Notification + Guided Tour**  
Closes the single highest-probability abandonment cliff: user records a meeting, nothing obviously happens, they assume the app is broken. Zero new capabilities required — just surfacing what already happened. Directly determines whether a new user becomes a retained user.

**#3 — U4-1: Global Capture Bar (⌘⇧Space)**  
Eliminates the navigation tax on every capture action for every persona. The Tab-gated capture pattern is a structural flaw that compounds across all 5 personas. TaskQuickAddParser already supports rich syntax — this just makes it available everywhere.

**#4 — U2-1: One-Click "Brief Me" Button on Every Person Profile**  
The single most visible proof that MeetingScribe is a second brain. All the raw material (last meeting, open tasks, talking points, iMessage themes, next calendar event) already exists and is connected to the person. The app just refuses to synthesize it without being asked. M effort, maximum "wow" moment.

**#5 — U4-2: Voice Note → Auto-Extract Pipeline**  
The app transcribes voice notes (Ollama pass already runs) but never extracts tasks or links people. This is leaving the most obvious value on the floor. One additional Ollama pass per note closes the loop from "I said it" to "it's tracked."

**#6 — U1-1: Proactive Morning Brief Push to Today**  
BriefCache already exists. CalendarService already lists today's meetings. Adding a background pre-warm job turns the most important feature (PreMeetingBriefView) from "user must navigate to find it" into "it's waiting for you at 7am." Zero new AI infrastructure.

**#7 — U3-2: Decision FTS + Semantic Index**  
Decisions are the most structurally underserved entity in the data model. They are extracted into DecisionStore but not indexed for search, not embedded, and not queryable via chat tools. Indexing them (M effort) unlocks U3-3, U3-4, and U3-5 as downstream wins.

**#8 — U2-2: Commitment Ledger Per Person**  
The `ownerPersonID` field already exists on every ActionItem. The Today tab already has a global owe/owed split. Scoping it to the person profile (S effort) makes every 1:1 prep flow dramatically more useful across U1 (exec), U2 (relationship manager), and U4 (founder delegating).

**#9 — U5-1: Post-Onboarding "First Steps" Card on Today**  
The Today blank state ("Nothing on today's calendar — use a quick action above") is a dead end for new users. A simple dismissible card with 3 concrete next steps bridges the gap between permission grant and first value delivery. S effort, potentially doubles new-user retention in week 1.

**#10 — U4-5: Proactive StandupDigest Push + Delegation Rollup**  
StandupDigest is completely pull-based today (`StandupDigest.swift` must be manually triggered). Adding a scheduled push notification at 8am with delegation accountability turns an existing feature into a daily habit driver for exec, founder, and PM personas simultaneously.

---

## Highest-priority single recommendation from this group

**U1-5: Promote followUpsSection + decisionsSection Out of "More"**

This is not the most technically interesting recommendation, but it is the one that delivers value immediately to every user across every persona with the least risk. Follow-ups hidden in a disclosure group are follow-ups that rot. Decisions hidden in a disclosure group are decisions that get re-litigated. Both sections already exist with correct logic and correct data — they are simply placed behind a disclosure that most users will never expand at the moment they need the information most.

The architectural principle it enforces is more important than the feature itself: **the app should never hide time-sensitive, actionable intelligence behind a user gesture**. Applying this principle consistently to the Today view is the first step toward MeetingScribe feeling like a proactive second brain rather than a passive archive.

Implementation: remove `followUpsSection` and `decisionsSection` from `moreSection` in `TodayView.swift`. Wrap each in a content-availability guard (hide when empty, show when non-empty). One engineer, one afternoon, ships in one PR.
