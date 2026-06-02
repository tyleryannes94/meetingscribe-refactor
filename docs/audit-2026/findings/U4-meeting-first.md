# U4 — Meeting-First: The Upgrade Path from Attendee to Tracked Relationship

**Lens:** A user whose primary use case is meeting transcription. I record meetings first. People are secondary — but I want a natural path to invest in a relationship I met through a meeting.

---

## The Scenario

> "I just had a great meeting with someone I want to stay in touch with. I go to their meeting in MeetingScribe, and..."

### Step 1 — I see the attendee row in the meeting header

`MeetingDetailHeader.swift:26–51` — after every meeting, attendee names are rendered as `AttendeeChip` pills in a horizontal scroll. Each chip shows initials, a first-name label, and a green dot if the person is already in People.

The chips are interactive: left-click calls `openOrCreate()` (`MeetingDetailHeader.swift:775`), which either opens the existing Person record or immediately creates a new one with `PeopleStore.shared.createPerson(displayName:email:)` and navigates to it (`MeetingDetailHeader.swift:779`). There is also a batch affordance — "Add N to People" (`MeetingDetailHeader.swift:39–46`) — which bulk-creates all unadded attendees in one tap, silently, with no confirmation, and no navigation to the new records.

**What works:** one-click promotion from attendee chip to Person is real and wired.

**What's broken:** the batch "Add N to People" creates people and drops you back in the meeting with no feedback beyond the chips updating. There is no "view them" follow-through (`MeetingDetailHeader.swift:40–44`, `addAllAttendeesToPeople` at line 550 — pure side-effect, no navigation). You have to manually switch to People and search.

### Step 2 — Auto-extraction has already run (or will)

`PersonExtractionController.swift:38–46` fires a post-recording LLM pass over the transcript via Ollama, classifying people as `"speaker"`, `"attendee"`, or `"third_party"`. The result goes into `PeopleStore.ingestExtraction`.

`PersonExtractor.swift:67–88` — the extraction prompt is well-tuned but skips the user by alias (hardcoded `"Tyler"` in the prompt, line 76), and truncates transcripts at 14,000 chars (`PersonExtractor.swift:47`). Long meetings where the interesting person only speaks in the second half may be missed entirely. No fallback for truncation; no confidence threshold gate before ingestion.

`CalendarAttendeeImporter.swift:11–26` — a separate, simpler path that resolves `meeting.attendees` strings into `PersonImport` structs for bulk import. It dedupes by email first, name second. This is purely structural (no LLM); it runs from `PeopleImportController.importCalendarAttendees()`.

**The gap:** these two paths are both opt-in or background-only. There is no user-visible signal in the meeting detail that says "I found 3 people in this transcript — want to add them?" The `PersonExtractionController` just silently ingests. A user who doesn't know to check People will never discover the extraction happened.

### Step 3 — I navigate to the Person record

The `PersonDetailView.swift:856–981` meeting history section is the payoff for the meeting-first user. It shows:

- Recorded meetings with this person (attendee-matched or transcript-mentioned), clickable back to the canonical meeting detail (`PersonDetailView.swift:947–948`)
- Unrecorded calendar meetings from the past 180 days (`PersonDetailView.swift:869–877`)
- Decisions extracted from linked meetings (`PersonDetailView.swift:886–918`)

**What works:** this is genuinely good — a unified timeline that mixes recorded + calendar-only meetings, deduped by minute-bucket. Most people tools miss the "unrecorded 1:1" case; this one doesn't.

**What's missing:** the meeting history tab shows the meeting list and a "Recorded"/"Calendar" badge, but no summary excerpt, no action items extracted from that meeting, and no "what did we discuss last time" glance. You have to click through to the meeting and navigate to the summary tab to get content.

### Step 4 — Can I ask Claude about this person from within the meeting?

`PeopleChatTools.swift:82–98` — `list_person_meetings` exists and links meetings by both attendee name match and Phase B transcript-mention. The chat tools know how to answer "what have I discussed with Jane?" from within the meeting's Chat tab (`UnifiedMeetingDetail.swift:99`, `DetailTab.chat`).

**What's missing:** there is no in-meeting UI that says "Ask AI about this attendee." The Chat tab is generic meeting chat. To invoke `list_person_meetings`, the user would have to type the question manually. There is no "jump to this person's profile and ask AI about them from this meeting's context" path.

---

## Existing Plan Items — Endorsements Through This Lens

1. **PPL-4 (MASTER_PLAN_V3.md):** Show all calendar meetings, not only recorded ones, in the person's Meetings tab. Already partially done in the live code (`PersonDetailView.swift:869–877`), but the plan still has the right framing — worth verifying the 180-day window is surfaced in settings.

2. **PPL-1 (MASTER_PLAN_V3.md):** Inline identity editing. Directly relevant here: when I create a person from a meeting attendee chip, I land on a read-only header with an "Edit" button that opens a modal. The moment of creation is the best moment to enrich a record (add their company, role, a note from the meeting). The modal breaks that flow.

3. **TDY-1 (MASTER_PLAN_V3.md):** "Up next" hero strip. The flip side of meeting-first: before the meeting, I want to see who I'll be meeting and link to their People records from Today.

---

## NET-NEW Recommendations

### U4-1 — Post-add navigation from batch import (S effort)

**Problem:** `addAllAttendeesToPeople` at `MeetingDetailHeader.swift:550` creates people silently and returns. The user has no path to see who was just added.

**Fix:** after the batch add, show a compact inline "N people added — view them" affordance that opens the first new person or pushes a filtered People list. Add a `router.openPerson()` call for the single-person case; for multi, a sheet listing the new records with one-click open.

This is a two-line change for single-person; a 20-line change for multi. S effort, immediate user value.

### U4-2 — Extraction surface: show a "People found" banner in meeting detail (M effort)

**Problem:** `PersonExtractionController` runs silently. The user never knows it found anyone.

**Fix:** after extraction completes, if `PeopleStore.ingestExtraction` created or updated any records, post a dismissible banner in `UnifiedMeetingDetail` (similar to the "Recording interrupted" banner at `MeetingDetailHeader.swift:450–466`): "Found 3 people in this transcript — Sarah, Horst, Ana. Add to People?" with one-tap confirm per name.

Wire from `PersonExtractionController.@Published isRunning` → `processed` → fire a notification the detail view observes. This closes the biggest discoverability gap in the pipeline.

### U4-3 — Relationship intent capture at creation time (M effort)

**Problem:** when a meeting attendee chip is tapped and `openOrCreate()` fires, the user lands on a blank Person record with no context about *why* they added this person. There is no "how do you know this person?" or "what do you want to track?" prompt.

**Fix:** when creating a new person from a meeting chip (`MeetingDetailHeader.swift:779`), pre-populate:
- `importSources` with `"meeting:\(m.id)"`
- A bootstrapping memory: "Met at: \(m.displayTitle) on \(date)" — inserted as the first `Memory` entry automatically, not requiring the user to write anything

Then show a lightweight "What's this relationship?" picker (3 options: Professional contact / Someone I want to stay in touch with / Friend or family) that sets the person's tag and drives check-in cadence defaults. This is the single highest-leverage place to capture relationship intent: the user is already motivated, they just clicked "add."

### U4-4 — "Last discussed" excerpt in Person meeting history (S effort)

**Problem:** `PersonDetailView.swift:956–981`, `timelineRowContent`, shows the meeting title and date but no content. A returning user checking "what did we discuss last time?" has to click through to the meeting, switch to the Notes/Summary tab, and read.

**Fix:** load a 1–2 sentence excerpt from the meeting summary cache and show it under the title in each `timelineRow`. `MeetingBodyCache` is already available to the detail view via `manager.bodyCache`; this is a read from the existing cache with no disk I/O on the hot path. The excerpt should truncate to ~120 chars with a "See full summary" link.

### U4-5 — "Discuss with Claude" chip action (M effort)

**Problem:** there is no in-meeting path to ask Claude about a specific attendee. The `list_person_meetings` and `get_person` tools exist but are unreachable without manually typing a question in the Chat tab.

**Fix:** add a long-press or right-click option on each `AttendeeChip` (`MeetingDetailHeader.swift:760–769`, contextMenu): "Ask AI about [name]." Tapping switches to the Chat tab and pre-seeds a message: "Tell me about [name] — our meeting history and what we've worked on together." This is 10 lines of Swift connecting the existing chip contextMenu to the existing ChatSession. High value, S effort once the chip navigation is already working.

### U4-6 — Relationship type defaults at extraction time (M effort)

**Problem:** `PersonExtractor.swift:8–11` classifies people as `"speaker"`, `"attendee"`, or `"third_party"` but this context is discarded after ingestion — `PeopleStore.ingestExtraction` does not map `primaryContext` to any relationship type, tag, or check-in cadence.

**Fix:** map `primaryContext` → default tag at ingestion:
- `"speaker"` → tag "Collaborator" + 30-day check-in default
- `"attendee"` → tag "Professional contact" + 90-day check-in default
- `"third_party"` → tag "Mentioned" + no check-in

This is a small change to `PeopleStore.ingestExtraction` and gives every auto-extracted person a meaningful starting state. The user can override; the extraction provides an opinionated default.

### U4-7 — "Reconnect" prompt sourced from meeting history (M effort)

**Problem:** the planned "stay in touch" nudges (MASTER_PLAN_V3.md) are person-global. They have no awareness of meeting recency. A person you met 6 weeks ago in a great recorded 1:1 should surface a smarter reconnect prompt than a contact you've never met.

**Fix:** when generating reconnect suggestions, weight people who have at least one *recorded* meeting (not just a calendar mention) and whose most recent meeting was 30–90 days ago. Surface the meeting title in the nudge: "You had a great call with Sarah (Product sync, Apr 15). Want to follow up?" This threads meeting data through the relationship habit loop — the core value proposition of this app.

### U4-8 — Transcript truncation blind spot for late-appearing people (L effort)

**Problem:** `PersonExtractor.swift:47` clips transcripts at 14,000 chars. A 90-minute meeting's interesting attendee who speaks at the 60-minute mark will be missed. No fallback; no indicator the transcript was clipped.

**Fix:** for meetings where the transcript exceeds the cap, run a second extraction pass over the tail (chars 14,000–28,000). Add a `clipped: Bool` flag to the extraction result and a warning in the Person extraction banner (U4-2). This is the only correctness gap in the pipeline that silently produces wrong data — a person you want to track doesn't appear in People because they spoke too late.

---

## Top 3 Picks

**U4-3 — Relationship intent at creation time** is the highest-leverage new idea. The moment a user taps an attendee chip and creates a person is the only moment where motivation, context, and the relevant meeting are all simultaneously present. Pre-populating a "Met at" memory and asking "what's this relationship?" turns a blank CRM entry into the first step of an actual relationship practice. Nothing in the existing plan captures this.

**U4-2 — Extraction surface banner** closes the biggest discoverability gap. The auto-extraction pipeline is real and working, but users who don't already know it exists will never discover it. A dismissible "Found 3 people in this transcript" banner after each recording makes the pipeline visible.

**U4-5 — "Ask AI about this attendee" chip action** is the smallest-effort highest-surprise-value addition: 10 lines of code connecting two already-working systems (AttendeeChip contextMenu + ChatSession pre-seed) and it makes the app feel like a relationship intelligence tool rather than a transcription tool with a contacts sidebar.
