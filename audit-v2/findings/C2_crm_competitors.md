# CRM & Relationship Intelligence Competitors — MeetingScribe v2 Audit

**Agent ID:** C2 | **Sub-Lens:** Clay, Folk, Dex — what they do that MeetingScribe People lacks

---

## Top friction points / gaps (file:line citations)

### What exists (briefly, to orient gaps)
- `Person.swift`: rich struct — `relationshipType`, `checkInCadenceDays`, `memories`, `encounters`, `talkingPoints`, `specialDates`, `meetingMentions`, `attachedNotes`, `relevanceScore(encounterCount:)`, `isGhost(encounterCount:)`.
- `Encounter.swift`: single interaction log — date, event name, location, notes, optional `meetingID` / `voiceNoteID`. No channel field, no sentiment field, no AI-extracted topics.
- `KeepInTouchBoard.swift:1-60`: 4-band kanban (Overdue/Drifting/Steady/Thriving) by health score. Triage-oriented. No enrichment. No ranked "reason to reach out" per card.

### Critical gaps vs. competitors

**1. No relationship health score surface** — `relevanceScore` (`Person.swift`) and `RelationshipHealth` exist in code but are invisible to the user. The KeepInTouchBoard uses band labels; there is no numeric momentum indicator or trend line ("relationship is cooling fast vs. slowly drifting").

**2. No contact enrichment pipeline** — Clay's core superpower is waterfall enrichment (150+ data sources). Folk's 1-click enrichment finds email, phone, and the "strongest mutual connection." Dex syncs LinkedIn job changes and fires a reminder when a contact changes roles. MeetingScribe has `company` and `role` fields that sit static after import — no mechanism to detect stale data or prompt updates.

**3. No "warm intro" / mutual connection query** — Folk explicitly surfaces "strongest connection" for each lead. Clay waterfalls LinkedIn + mutual data. MeetingScribe has a people graph (force-directed) but it maps who knows whom inside MeetingScribe — it does not surface "Tyler knows Alice who knows Bob you're trying to reach" as an actionable warm intro path.

**4. No per-person AI Recap Brief** — Folk's "Recap Assistant" synthesizes all emails, WhatsApp, meetings, notes, and LinkedIn activity into a structured brief (overview + key points + next steps) before a call. MeetingScribe has a `PreMeetingBriefView` at the *meeting* level but no on-demand "catch me up on this person" summary inside `PersonDetailView`. The `attachedNotes` field holds analyses saved manually — there is no automatic recap triggered before a meeting with that person.

**5. No relationship momentum / velocity signal** — Clay tracks intent signals (job change, company news, funding). Dex surfaces "job title changed — perfect time to reach out." MeetingScribe tracks `lastInteractionAt` and encounter frequency but has no *signal-driven* trigger ("Sarah just started at a new company — reach out now while it's warm").

**6. No AI-drafted follow-up from meeting content** — Folk's "Follow-up Assistant" scans conversations, detects inactive threads with pending next steps, and drafts a follow-up in the user's voice. MeetingScribe extracts action items from meetings but does not auto-generate a follow-up *message* addressed to the person.

**7. Encounter record is shallow** — `Encounter.swift` stores date/event/notes. No channel (`iMessage`, `email`, `calendar`, `voice note`, `meeting`), no sentiment field, no AI-extracted topics. Folk and Dex unify all channel signals (email + WhatsApp + LinkedIn + calendar) into a single timeline per person. MeetingScribe has the *data* (iMessage analysis, meetings, voice notes all exist) but the encounter record does not aggregate or index it.

**8. No network graph "introduction path"** — The existing people graph is visual but not query-able ("who is my shortest path to X?"). No competitor nails this for personal networks; MeetingScribe has the co-attendance data to do it.

---

## Existing items to endorse (from prior plan or codebase)

- `relevanceScore` formula in `Person.swift` — good bones; needs UI exposure.
- `KeepInTouchBoard.swift` — solid kanban structure; extend rather than replace.
- `talkingPoints` array — already feeds `PreMeetingBriefView`; extend to AI-generated prep.
- `meetingMentions` backlinks — the data for "who attended which meeting" is there; join it into the per-person recap.
- `MessagesAnalyzer` / iMessage integration — unique vs. all three competitors; double down.
- `checkInGoalDays` / `effectiveCheckInDays` — good cadence model; expose it visually.

---

## NET-NEW recommendations

### C2-1: Local AI "Person Recap Brief" — on-demand + pre-meeting auto-inject
- **What:** A "Catch me up" button in `PersonDetailView` (and auto-surfaced in `PreMeetingBriefView` when the attendee is a known Person) that runs an Ollama prompt over all signals for that person: meeting transcripts where they appear (`meetingMentions`), encounter notes, iMessage analysis summary, `memories`, `talkingPoints`, `attachedNotes`. Returns a structured brief: last interaction, what was discussed, open commitments, suggested talking points, upcoming special dates. Cached with a "refresh" affordance.
- **Why (second-brain angle):** Folk's Recap Assistant is cloud-gated and sales-oriented. MeetingScribe can deliver the same locally, privately, and with *richer signals* (actual transcript content + iMessage + voice notes — no competitor has all three). Zero marginal cost via Ollama.
- **Cross-feature connections:** Meetings tab (pre-meeting brief), People tab (PersonDetailView), Today tab (1:1 section), AI chat (tool `get_person_recap`).
- **Effort:** M | **Impact:** High
- **Deps:** none (Ollama + existing data already wired)

### C2-2: Relationship Momentum Score — velocity trend overlay on KeepInTouchBoard
- **What:** Augment the existing `RelationshipHealth` band with a *velocity vector*: is the relationship improving, stable, or deteriorating vs. the prior 30-day window? Display as a tiny trend arrow on each board card and a color-shifted ring on `PersonDetailView`. Computed purely from encounter frequency deltas — no new data needed.
- **Why (second-brain angle):** The current board shows *state* (Overdue/Thriving). Velocity tells Tyler which Steady relationships are silently cooling before they hit Drifting — proactive, not reactive. No competitor delivers this natively in a personal tool.
- **Cross-feature connections:** KeepInTouchBoard, PersonDetailView health ring, Today "Relationships" widget.
- **Effort:** S | **Impact:** High
- **Deps:** none

### C2-3: "Warm Intro Path" query on the People Graph
- **What:** Add a query mode to the existing people graph: "Who do I know that knows [target person]?" Implemented as 2-hop BFS over the `relationships` graph + `meetingMentions` co-attendance (two people who appeared in the same meeting = implicit tie). Surface as a ranked list with path explanations: "You → Alice (Close Friend, met 3x) → Bob (co-attended Q4 Planning)."
- **Why (second-brain angle):** Clay charges enterprise prices for mutual connection data pulled from external APIs. MeetingScribe already owns the co-attendance graph in meeting transcripts + explicit `relationships` edges — free signal no competitor can match for Tyler's actual network.
- **Cross-feature connections:** People graph (existing), Meetings tab (attendee co-presence), AI chat (`find_intro_path` tool).
- **Effort:** M | **Impact:** High
- **Deps:** none

### C2-4: Signal-Driven "Reach Out Now" Cards — local enrichment from calendar + iMessage
- **What:** A lightweight signal detector (runs nightly via background timer, already a pattern in `WeeklyRecap.swift`): scans calendar for new employers detected in invite signatures, iMessage for long silences broken by a new message, meeting notes for "just joined X" mentions. Surfaces as a special card type in the KeepInTouchBoard: "Sarah mentioned starting at Anthropic — great time to reach out." Drafts an opening message via Ollama.
- **Why (second-brain angle):** Dex fires on LinkedIn job-change webhooks (cloud-dependent, LinkedIn TOS-fraught). MeetingScribe can detect the same signal from meeting transcripts and calendar — fully local, richer context.
- **Cross-feature connections:** KeepInTouchBoard, Today tab (relationship widget), Meetings (transcript scanner), iMessage analyzer.
- **Effort:** L | **Impact:** High
- **Deps:** C2-1 (Ollama message drafting)

### C2-5: AI Follow-up Message Drafter — post-meeting, per-attendee
- **What:** After a meeting closes (summary generated), MeetingScribe proposes a follow-up message for each attendee who has open action items assigned to Tyler or commitments made to them. Ollama drafts the message in Tyler's voice using the meeting summary + prior encounter history + iMessage tone analysis. One-click copy to clipboard or draft to iMessage/email.
- **Why (second-brain angle):** Folk's Follow-up Assistant is the most-loved feature by their users. MeetingScribe already has better raw material (transcript, action items, iMessage tone profile). This closes the loop from meeting → relationship maintenance automatically.
- **Cross-feature connections:** Meetings tab (post-meeting summary), People tab (encounter log auto-populated), Today tab (pending follow-ups widget).
- **Effort:** M | **Impact:** High
- **Deps:** C2-1

### C2-6: Encounter Channel Enrichment — unified multi-channel timeline
- **What:** Extend `Encounter` with a `channel` enum (`meeting | iMessage | email | voiceNote | manualLog`) and AI-extracted `topics: [String]`. Migrate existing: meetings linked via `meetingID` → `channel = .meeting`; iMessage analysis snapshots → auto-create `.iMessage` encounters with extracted topics. Display as a unified timeline in `PersonDetailView`.
- **Why (second-brain angle):** Every competitor unifies multi-channel signals into one contact timeline. MeetingScribe has iMessage, meeting transcripts, voice notes, and manual encounters as *separate* data stores with no unified view. The data exists; it just is not joined.
- **Cross-feature connections:** PersonDetailView, PeopleStore, iMessage analyzer, meeting backlinks.
- **Effort:** M | **Impact:** Med
- **Deps:** none

### C2-7: Ghost Contact Triage UI
- **What:** Surface `isGhost(encounterCount:)` (already computed in `Person.swift`) as a dedicated section in the People list: "X imported contacts with no signal — archive, enrich, or tag?" Bulk-archive, add a memory, or tag to raise relevance score. Prevents ghost inflation of the people count.
- **Why (second-brain angle):** Clay built an entire CRM enrichment business around the problem of stale/empty contact records. MeetingScribe already has the detection logic — just no UI for it.
- **Cross-feature connections:** PeopleListView, import pipeline, tags.
- **Effort:** S | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **C2-1 (Person Recap Brief)** — highest leverage: closes the "Catch me up" gap vs. Folk's most-praised feature, uses all existing data (transcripts + iMessage + memories), free via Ollama, and directly feeds PreMeetingBriefView. Immediately makes People the best tab in the app.
2. **C2-2 (Relationship Momentum Score)** — tiny engineering effort (pure computation over existing encounter data), high daily value, differentiates MeetingScribe from all three competitors who show state but not velocity.
3. **C2-5 (Post-Meeting Follow-up Drafter)** — closes the meeting-to-relationship loop that no competitor closes as well, given MeetingScribe's combined transcript + iMessage tone profile advantage.
