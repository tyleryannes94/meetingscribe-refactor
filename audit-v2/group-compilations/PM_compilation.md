# Product Management Group Compilation — MeetingScribe v2 Audit

**Agents:** PM1 (Interconnectedness), PM2 (People Strategy), PM3 (AI Features), PM4 (Workflows & Integrations), PM5 (Retention & Habit Loops)  
**Compiled by:** PM5

---

## Convergence within this group (items 2+ agents raised independently)

### 1. WeeklyRecap must become a living ritual, not a static markdown file
PM1-8, PM3-6, PM5-1 all independently identified that `WeeklyRecap.swift` generates a flat markdown file on demand but has no scheduled trigger, no in-app native view, no carry-forward comparison, and no AI synthesis. PM2-9 adds that it should include a relationship pulse section. PM3-6 proposes an Ollama-composed narrative. PM5-1 proposes a Friday notification + native SwiftUI panel. These converge on one thing: the weekly review needs to become a native, scheduled, AI-enriched ritual surface — not a file export.

### 2. Post-meeting pipeline must be automatic across all tabs
PM1-1 ("Post-Meeting Automation Pipeline"), PM2-1 ("Auto-Encounter from Meetings"), PM4-1 ("Post-Meeting Workflow Engine"), and PM5-3 ("Post-Meeting Ritual Engine") all independently reached the same conclusion: a meeting ending is the highest-value event in the app and today requires 6+ manual steps across tabs (encounter log, action item review, people update, export). The group consensus is a single orchestrated pipeline triggered when summary generation completes.

### 3. Proactive AI push is the defining gap between v1 and v2
PM1-3 ("Proactive Semantic Nudges"), PM3-1 ("Proactive Insight Engine"), PM5-1 (weekly ritual notification), PM5-2 (enriched daily notification), PM5-3 (post-meeting follow-up) all identify the same structural gap: Ollama is always on, always free, but every AI interaction is purely pull-based. The product currently has zero scheduled background AI work despite a `ResourceGovernor` already designed for it. This is the highest-consensus finding in the PM group.

### 4. Daily brief notification is generic and non-actionable
PM5-2 specifically audits `NotificationManager.swift:234–245` and finds the 8am notification body is generic text with no deep link. PM4 notes integration failure notifications are cryptic. PM1 notes the standup digest has no push trigger. The convergent fix: enrich the morning notification with live data and a direct deep link to the standup sheet.

### 5. People → Tasks cross-tab path is broken or invisible
PM1 (data flow gaps), PM2-5 (no task create from People), PM2-6 (relationship summary invisible in pre-meeting brief) all independently note that the People tab cannot create tasks and the Tasks tab cannot filter by person without manual steps. The relationship data is rich but the workflow paths are dead ends.

### 6. Embeddings are built but entirely invisible
PM1 ("embeddings computed but never surfaced"), PM3-2 ("Semantic Ask Your Vault"), PM1-5 ("Embedding-Powered Context Flash") all flag that `EmbeddingService` computes cosine similarity across all content but the user sees none of it. Making embeddings navigable in the UI is the highest-ROI infrastructure unlock.

### 7. MetricsStore tracks production events but zero habit events
PM5 uniquely raises that `MetricsStore.swift` has no ritual-completion events. This is a prerequisite for every streak, milestone, and behavioral feedback loop in the group's retention recommendations.

---

## All net-new recommendations (deduplicated, with source agent IDs)

### Post-Meeting & Meeting Loop
| ID | Title | Source |
|----|-------|--------|
| PM1-1 | Post-Meeting Automation Pipeline (auto people/tasks/projects from meeting) | PM1 |
| PM2-1 | Auto-Encounter Creation from Meetings | PM2 |
| PM3-3 | AI Relationship Brief (pre-1:1 narrative synthesis) | PM3 |
| PM4-1 | Post-Meeting Workflow Engine (user-configurable trigger → actions) | PM4 |
| PM5-3 | Post-Meeting Ritual Engine (T+45min follow-up notification) | PM5 |
| UX3-1 | Post-Meeting Review Mode in meeting detail (from UX group) | UX3 |

### Proactive AI & Nudge Engine
| ID | Title | Source |
|----|-------|--------|
| PM1-3 | Proactive Semantic Nudges via scheduled Ollama pass | PM1 |
| PM3-1 | Proactive Insight Engine (silent background enrichment) | PM3 |
| PM5-1 | Scheduled Weekly Review Ritual (Friday notification + native UI) | PM5 |
| PM5-2 | Enriched Daily-Brief Notification with deep link | PM5 |
| PM5-5 | End-of-Day Wrap-Up Card on Today | PM5 |

### Second Brain Value & Retention
| ID | Title | Source |
|----|-------|--------|
| PM5-4 | Compounding Value Dashboard (totals, sparklines, streaks) | PM5 |
| PM5-6 | Free-Tier Relationship Nudge (check-in lite as upgrade driver) | PM5 |
| PM1-8 | Live WeeklyRecap Dashboard (replace static MD file) | PM1 |
| PM3-6 | AI Digest Composer (Ollama-narrated weekly summary) | PM3 |
| PM2-9 | People Intelligence Weekly Digest (relationship pulse in recap) | PM2 |

### Interconnectedness & Data Flow
| ID | Title | Source |
|----|-------|--------|
| PM1-2 | Automatic Person Enrollment from recurring attendees | PM1 |
| PM1-4 | Decision Lifecycle Tracking (owner, linked tasks, status, revisit) | PM1 |
| PM1-5 | Embedding-Powered Context Flash in Pre-Meeting Brief | PM1 |
| PM1-6 | Voice Notes Auto-Triage (task/person/meeting links from voice) | PM1 |
| PM1-7 | Relationship Drift Alert on Today | PM1 |
| PM2-6 | Relationship Summary Auto-Surfaced in PreMeetingBrief | PM2 |
| PM3-2 | Semantic "Ask Your Vault" — exposed embeddings as navigable UI | PM3 |
| PM3-4 | Expand RAG grounding to all entity kinds (people, tasks, voice notes) | PM3 |

### People Intelligence
| ID | Title | Source |
|----|-------|--------|
| PM2-2 | Relationship Velocity Signal + Trajectory Badge | PM2 |
| PM2-3 | One-Tap Actions on KeepInTouchBoard cards | PM2 |
| PM2-4 | Person Intelligence Card (proactive pre-surface, auto-refreshing) | PM2 |
| PM2-5 | Task Mutation from People Tab (create task with ownerPersonID) | PM2 |
| PM2-7 | Mutual Contacts / Second-Degree Discovery | PM2 |
| PM2-8 | Adaptive PersonDetailView Layout by relationship type | PM2 |
| PM2-10 | MCP Tools for Relationship Intelligence | PM2 |

### Integrations & Workflows
| ID | Title | Source |
|----|-------|--------|
| PM4-2 | Notion Bidirectional Sync (meetings + decisions, not just tasks) | PM4 |
| PM4-3 | Unified Export Renderer (parity across all destinations) | PM4 |
| PM4-4 | Linear Action-Item Context Menu + Auto-Create | PM4 |
| PM4-5 | Calendar Write-Back (due dates + follow-up scheduling) | PM4 |
| PM4-6 | Outbound Webhook System for External Automation | PM4 |
| PM4-7 | Saved Export Preferences Per Destination | PM4 |
| PM4-8 | Unified Integration Status + Health Dashboard | PM4 |
| PM4-9 | People → Attendee Resolution in All Export Paths | PM4 |
| PM4-10 | Shared Tool Definition Registry (MCP + in-app chat parity) | PM4 |

### AI Infrastructure
| ID | Title | Source |
|----|-------|--------|
| PM3-5 | ResourceGovernor as universal AI work gating authority | PM3 |
| PM3-7 | SummaryFeedback aggregation + global prompt learning | PM3 |
| PM3-8 | In-context AI annotations on transcript ("highlight + ask") | PM3 |

---

## Group's top 10 picks with rationale

**1. PM1-1 / PM2-1 / PM4-1 / PM5-3 — Unified Post-Meeting Pipeline**  
Consensus pick across all 5 agents. A meeting ending is the highest-value event in the product and today requires 6+ manual steps. Automating encounter creation, owner resolution, export, and a follow-up notification at T+45min makes v2 feel qualitatively different from v1 in the first 10 minutes of use. Prerequisite for approximately half of all other recommendations.

**2. PM5-2 — Enriched Daily-Brief Notification with Deep Link**  
S effort, H impact. The 8am notification is the keystone daily habit driver and it currently delivers a generic body with no deep link. Injecting live content ("4 meetings · 2 overdue · Alex's birthday tomorrow") and a "View Standup" action that deep-links to the standup sheet is the single highest-ROI retention intervention available. Builds on existing infrastructure in `NotificationManager.swift:234–245`.

**3. PM5-1 — Scheduled Weekly Review Ritual**  
Converged on by PM1, PM2, PM3, PM5. The Friday 4:30pm notification + native `WeeklyReviewView` with carry-forward comparison and Ollama reflection prompt transforms the weekly review from a passive export into a closure ritual. This is the highest-compounding habit in knowledge work and the only surface that gives the user a felt sense of the second brain's accumulated value.

**4. PM3-1 / PM1-3 — Proactive Insight Engine (Scheduled Background Ollama)**  
Converged on by PM1 and PM3. `ResourceGovernor` already exists but gates nothing except live transcription. A background `InsightEngine` actor that runs relationship health scoring, decision tracking, and semantic nudge generation on idle (AC + nominal thermal) has zero marginal cost and converts the product from reactive to proactive. This is the defining architectural gap between v1 and v2.

**5. PM1-5 / PM3-2 — Embeddings Made Visible (Context Flash + Vault Surface)**  
Converged on by PM1 and PM3. The embedding index is fully built and dark. PM1-5 surfaces it at the highest-leverage moment (pre-meeting brief: "this topic overlaps with your Q2 planning decision"). PM3-2 makes it navigable as a "Related" strip across entity detail views. Together they turn a sunk infrastructure cost into daily visible value. S effort for PM1-5 (read-only query).

**6. PM2-1 — Auto-Encounter Creation from Meetings**  
Converged on by PM2 and PM1. The relationship health score and KeepInTouchBoard are meaningless for professional contacts if encounters only come from manual logs. Auto-creating an Encounter from each confirmed meeting attendee requires no new model fields (`Encounter.meetingID` already exists) and makes the entire People intelligence stack accurate for the majority of real-world use.

**7. PM2-3 — One-Tap Actions on KeepInTouchBoard Cards**  
The board identifies who needs attention but offers no path to action. Adding "Log check-in," "AI conversation starter" (Ollama, instant, free), and "Remind me" as a hover-reveal action strip converts the board from a guilt dashboard to a workflow tool. The AI conversation starter from local Ollama is the "Clay moment" that justifies the People feature's existence.

**8. PM5-4 — Compounding Value Dashboard with Streak Counters**  
Unique to PM5. The second brain's value compounds invisibly — the user has no felt return on investment signal and no consistency driver. A streak counter (flame icon + day count in Today header) anchored to daily opens and standup completions is one of the highest-ROI habit mechanics available. The sparklines (12-week meeting frequency, action capture rate) make the growth of the brain visible. Requires new `MetricsStore` events (PM5 prerequisite across all retention features).

**9. PM4-2 — Notion Bidirectional Sync (Meetings + Decisions)**  
Converged as PM4's top pick. Notion is the most common external second brain. Today's Notion integration is one-way, action-item-only, and flat. A full bidirectional sync that creates meeting summary pages with decisions and attendee relations, and pulls status changes back, turns MeetingScribe into the authoritative write-head for the user's knowledge system rather than a parallel silo.

**10. PM2-6 / PM3-3 — Relationship Summary in Pre-Meeting Brief + AI Narrative**  
Converged on by PM2 and PM3. The pre-meeting brief is where relationship intelligence has maximum ROI (2 minutes before a call). PM2-6 costs almost nothing — `summary-all` AttachedNote already exists, just needs a 200-character pull. PM3-3 adds full Ollama-synthesized narrative (commitments, tensions, talking points). Together they transform the brief from a calendar view into a genuine coaching surface.

---

## Highest-priority single recommendation from this group

**Unified Post-Meeting Pipeline (PM1-1 + PM2-1 + PM4-1 + PM5-3)**

Every agent independently identified that a meeting ending is the highest-value moment in the app and is completely unorchestrated today. The convergent recommendation: when summary generation completes, automatically (1) create Encounter records for each confirmed attendee, (2) resolve action item owners against PeopleStore, (3) push to configured external integrations, (4) fire `notifyTranscriptionComplete`, and (5) schedule a T+45min "Did you capture everything?" follow-up notification. This single pipeline change makes the second brain self-populating rather than requiring 6+ manual steps after every meeting — and is the prerequisite dependency cited by PM1-2, PM1-4, PM2-2, PM3-1, PM3-3, and PM5-3.
