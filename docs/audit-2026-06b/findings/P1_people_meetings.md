# PM Group — People ↔ Meetings Integration
> Lens: every meeting surface should answer "who are the humans here, what do I know about them, and what do we owe each other?" — before, during, and after the call.

## Full-app audit (through my lens)

### Strong (genuinely good bones)

- **Inline attendee→person connect panel.** Clicking an attendee chip opens `MeetingPersonConnectPanel` as a trailing inspector instead of yanking you to the People tab (`UnifiedMeetingDetail.swift:153-163`, `MeetingPersonConnectPanel.swift:12-94`). Linking saves the email onto the person, adds the meeting to their timeline, and bumps `lastInteractionAt` (`MeetingPersonConnectPanel.swift:251-261`). This is the best people↔meeting interaction in the app.
- **LLM person extraction with confidence-tiered ingestion.** `PersonExtractionController.swift:38-91` + `PeopleStore.ingestExtraction` (`PeopleStore.swift:1171-1228`): ≥0.85 fuzzy match auto-links and bumps last-interaction; 0.6–0.85 queues an "is this X?" suggestion. Real product thinking.
- **Pre-meeting brief already synthesizes.** `PreMeetingBriefView.swift:197-239` builds a series-aware Ollama brief (last occurrence summary + open commitments + talking points). The planned "proactive pre-meeting brief" (2D) has a solid base to push from.
- **Person→meeting direction works.** `PersonDetailView` Meetings tab unions recorded + unrecorded calendar meetings into one badged timeline (`PersonDetailView.swift:1209-1230`), shows decisions from linked meetings (`:1174-1207`), and offers "Add \(person) to a meeting" (`:418-428`).

### Weak / missing (the integration gap)

1. **No identity layer — meetings reference people as free strings.** `Meeting.attendees: [String]` holds raw `"Name <email>"` strings (`Models/Meeting.swift:65`); the reverse edge is `person.meetingMentions` (`People/Person.swift:220`). There is no `attendeePersonIDs`, so the same `"Name <email>"` parsing is re-implemented at least six times: `MeetingDetailHeader.swift:586-594`, `MeetingPersonConnectPanel.swift:28-41`, `CalendarAttendeeImporter.swift:29-52`, `PreMeetingBriefView.swift:242-253`, `PersonDetailView.swift:1148-1155`, `MeetingSummaryTab.swift:302-308` — each with different matching rules.
2. **The follow-up recipient resolver is broken for calendar meetings.** `MeetingSummaryTab.swift:302-308` compares the *raw attendee string* (`"Jane Smith <jane@acme.com>"`) against `person.displayName` with `caseInsensitiveCompare` — it never parses out the email that's sitting right there in the string. Net effect: "Draft follow-up…", the #1 post-meeting action, opens with empty recipients for typical invite-sourced meetings.
3. **Fuzzy substring matching produces false positives.** `PersonDetailView.attendeeMatches` (`PersonDetailView.swift:1148-1155`) uses `a.contains(personName)` — a person named "Dan" claims every meeting with "Daniel" in the attendee list. Identity should be email-keyed, not substring-keyed.
4. **Bulk "Add N to People" creates people but doesn't link the meeting.** `addAllAttendeesToPeople` (`MeetingDetailHeader.swift:608-613`) calls `createPerson` only — no `addMeetingMention`, no `bumpLastInteraction`. The single-attendee connect panel does both (`MeetingPersonConnectPanel.swift:251-261`). Two adjacent affordances, two different outcomes.
5. **Calendar attendees with known emails are never auto-linked at finalize.** `addMeetingMention` fires from only three call sites — the manual connect panel, the fuzzy transcript-extraction path, and suggestion confirm (grep: `PeopleStore.swift:1191,1241`, `MeetingPersonConnectPanel.swift:253`). A meeting whose invite lists `jane@acme.com`, where Jane is already a Person with that exact email, produces *no* meeting↔person edge unless Jane happens to be *named* in the transcript. Email is a perfect join key and it's unused.
6. **Zero speaker↔person identity.** `TranscriptSyncView` parses and colors speaker labels (`TranscriptSyncView.swift:28-67,262-272`) but there is no rename, no "this is Jane" mapping, no link to a Person — grep for `renameSpeaker|speakerMap` returns nothing. The live transcript hard-codes `"Me"`→blue / everything else→green (`MeetingTranscriptTab.swift:86-90`). The plan's "surface speaker diarization" (2E) specs a toggle, not the identity-mapping UX.
7. **No persistent people presence inside meeting detail.** The header shows first-name chips with a 5pt green dot (`MeetingDetailHeader.swift:744-848`); the 320pt inspector appears only transiently for linking. Nowhere in a meeting can you see a person's role, relationship health, last-met date, or open commitments — the exact "relationship second brain" the app sells, invisible at its highest-traffic surface.
8. **Record time is people-blind.** `NewMeetingSheet.swift` captures a title only — ad-hoc meetings start with `attendees: []` and there is no way to say who you're meeting. `MeetingManager.addAttendee` (`MeetingManager.swift:597`) exists but is reachable only from `PersonDetailView` (person→meeting direction), never meeting→person.
9. **Meeting lists hide the humans.** `MeetingCard.swift:156-160` renders `"3 attendees"` as text. No avatars anywhere in Meetings/Today lists — both a people-integration miss and a "cheap vs. expensive" tell (Notion Calendar, Cron, and Granola all lead with face piles).
10. **Meeting Ask AI and the brief ignore the people graph.** `MeetingChatTab.swift:39-40` passes attendees as raw strings; `PreMeetingBriefView.generateSynthesis` feeds the LLM only meeting-derived context — no person bios, memories, encounters, or relationship type from `PeopleStore`, even for linked people.
11. **Recorded meetings never become encounters.** Encounters and meetings are parallel streams; finishing a recorded meeting with Jane doesn't appear on her `EncounterHeatMap` or feed health depth — only `lastInteractionAt` gets (sometimes) bumped via extraction.

## Existing-plan items I rank highest

1. **Attendee chip hover-card + "Add to People" (2A)** — the highest-traffic people↔meeting touchpoint; but spec it on a real identity layer (P1-1) or it inherits the string-matching bugs above.
2. **Auto-bump `lastInteractionAt` from finalized-meeting attendees (2B)** — partially shipped via extraction (`PeopleStore.swift:1195`); finishing it for email-matched calendar attendees is the cheapest honesty fix for drift/health.
3. **Directed commitments with `personID` (2C)** — the meeting↔person edge that creates daily pull-back ("I owe Priya"); everything in my P1-2 rail gets richer once this lands.
4. **Proactive pre-meeting brief + `get_meeting_prep` (2D)** — `PreMeetingBriefView` proves the synthesis works; scheduling it N minutes before the event converts it from pull to push.
5. **Surface speaker diarization (2E)** — necessary substrate for P1-3, but the plan stops at "transcript toggle"; the identity mapping is where the value is.
6. **Per-report 1:1 prep digest (2H)** — the person-aware brief extension; should consume the same person-context injection as P1-10 rather than a bespoke path.

## NET-NEW recommendations

### P1-1 — AttendeeResolver: one email-keyed identity layer + auto-link at finalize
- **What/why:** A single `AttendeeResolver` (VaultKit-adjacent) that parses `"Name <email>"` once and resolves attendee→Person by normalized email first, exact name second — replacing the six divergent ad-hoc parsers (`MeetingDetailHeader.swift:586`, `MeetingPersonConnectPanel.swift:28`, `CalendarAttendeeImporter.swift:29`, `PreMeetingBriefView.swift:242`, `PersonDetailView.swift:1148`, `MeetingSummaryTab.swift:302`). On meeting finalize (and on calendar sync for past meetings), auto-call `addMeetingMention` + `bumpLastInteraction` for every exact-email match — today that edge is only created manually or by fuzzy transcript extraction. Fixes outright bugs: empty follow-up recipients (`MeetingSummaryTab.swift:302-308`), "Dan" matching "Daniel" (`PersonDetailView.swift:1151-1154`), and bulk-add not linking (`MeetingDetailHeader.swift:608-613`).
- **User value:** Every downstream people feature (rail, briefs, health, follow-ups) becomes truthful with zero clicks; follow-up recipients populate themselves.
- **Effort:** M
- **Impact:** High (it's the foundation; three bugs die in one PR)
- **Depends on:** none

### P1-2 — People rail: a persistent "Who's here" inspector in meeting detail
- **What/why:** Promote the transient connect panel (`UnifiedMeetingDetail.swift:153-163`) into a toggleable, persistent trailing rail listing every resolved attendee: avatar, role · company, relationship-health band capsule (reuse the shipped `RelationshipHealth` badge), "last met N days ago", and open commitments each way once 2C lands. Unlinked attendees show inline "Connect" (the current panel becomes one expanded state of a rail row). One keyboard toggle (Cmd-Opt-P), same rail in live/upcoming/past modes.
- **User value:** "Can I see and act on the humans involved, right here?" goes from *no* to *yes* on the app's highest-traffic detail surface; replaces ~4 navigations (meeting → People tab → person → back) with zero.
- **Effort:** M
- **Impact:** High
- **Depends on:** P1-1

### P1-3 — Speaker→person identity mapping ("This is Jane")
- **What/why:** In `TranscriptSyncView`, make every speaker chip (`TranscriptSyncView.swift:151-170`) clickable → popover person-picker seeded with this meeting's resolved attendees (one-click "Speaker 2 = Jane"). Persist a per-meeting `speakers.json` sidecar mapping label→personID; render person names + `RelationshipType.color` everywhere the label appears (transcript rows, live view's hard-coded Me/Them at `MeetingTranscriptTab.swift:86-90`), and attribute talk-time + extracted action items to actual Person records. The plan's diarization item (2E) surfaces speakers; this is the missing half that turns audio into relationship data.
- **User value:** "What did Jane actually say?" becomes answerable; speaker-attributed commitments stop being strings; per-person talk-time unlocks the Phase-3 conversation intelligence with no rework.
- **Effort:** M
- **Impact:** High
- **Depends on:** P1-1 (picker seeding); pairs with 2E

### P1-4 — "Who's this with?" people picker at record time
- **What/why:** `NewMeetingSheet.swift` captures only a title; ad-hoc meetings are born people-less and `addAttendee` (`MeetingManager.swift:597`) is unreachable from the meeting side. Add an @-style multi-select people field (token field over `PeopleStore`, create-on-enter for new names) that writes `attendees` + meeting↔person links at creation. When a person is picked, show a one-line context card under the field: "Last met May 28 · 2 open items" — relationship context surfaced at the moment of capture.
- **User value:** The most common impromptu flow ("quick call with Jane") finally produces a person-linked meeting; record-time prep context for free.
- **Effort:** M
- **Impact:** High
- **Depends on:** P1-1

### P1-5 — Shared-history strip: "3rd meeting with Jane this quarter"
- **What/why:** The person page shows meeting history (`PersonDetailView.swift:1209-1230`) but the meeting shows nothing about history. Add a one-line strip under the attendee row in `MeetingDetailHeader` for past/live meetings: "You've met Jane 12× · last: May 28 — *pricing follow-up*" (count + last shared meeting title from `meetingMentions` ∩ `pastMeetings`). Click → opens the people rail (P1-2) scrolled to that person's shared timeline. For multi-person meetings, summarize the most-significant relationship and overflow the rest.
- **User value:** Continuity at a glance — the "second brain" demonstrates memory exactly where you'd brag about it; zero clicks vs. today's meeting→People→person→Meetings-tab (4 clicks).
- **Effort:** S
- **Impact:** Med-High
- **Depends on:** P1-1 (P1-2 enriches it)

### P1-6 — Bulk-add parity: "Add N to People" must link + bump (with undo toast)
- **What/why:** `addAllAttendeesToPeople` (`MeetingDetailHeader.swift:608-613`) creates Person records but never calls `addMeetingMention` or `bumpLastInteraction`, so bulk-added people have empty timelines while individually-connected ones don't (`MeetingPersonConnectPanel.swift:251-261`). Route both paths through one `linkAttendee(meeting:person:)` helper; confirm with a ToastCenter toast + Undo.
- **User value:** The one-click onboarding path stops producing hollow person records; trust in the timeline.
- **Effort:** S
- **Impact:** Med (small, but it's silent data-model divergence today)
- **Depends on:** none (folds into P1-1 if built together)

### P1-7 — Face piles on meeting rows (Today, Meetings list, MeetingCard)
- **What/why:** Replace the `"3 attendees"` text (`MeetingCard.swift:156-160`) with an overlapping `MSAvatar` stack (max 4 + "+N"), ringed in `RelationshipType.color` for resolved people and neutral for strangers. Benchmark: Notion Calendar's and Granola's event rows lead with faces; text counts read cheap.
- **User value:** Scanning "who's my day with" without opening anything; the premium-feel pillar and the people pillar in one S-sized change.
- **Effort:** S
- **Impact:** Med-High
- **Depends on:** P1-1 (for ring color/resolution; degrades gracefully without)

### P1-8 — Person-aware follow-up composer
- **What/why:** Beyond fixing recipients (P1-1): group the follow-up draft by person — "For Jane: items she owes / you owe her" using directed commitments (2C), with per-recipient include-checkboxes; on send/copy, log a `followUp` touch on each recipient (feeds health + `lastInteractionAt`). Today `FollowUpView` receives flat title arrays (`MeetingSummaryTab.swift:218-226`).
- **User value:** The #1 post-meeting action becomes relationship-aware and self-records; closes the loop the planned follow-up-lifecycle item (2H) only tracks.
- **Effort:** M
- **Impact:** Med-High
- **Depends on:** P1-1; richer after 2C

### P1-9 — Recorded meetings emit encounters (one interaction stream)
- **What/why:** On finalize, write an `Encounter(kind: .meeting, meetingID:)` for each linked person, so `EncounterHeatMap`, encounter counts (`PeopleInsightsView.swift:108`), and health *depth* reflect meetings — not just manual quick-logs. The plan's auto-bump (2B) updates one timestamp; this makes meetings first-class interactions with dedup (skip if a manual encounter exists within ±2h).
- **User value:** Health scores and heat maps stop lying for people you mostly *meet* rather than manually log; kills double bookkeeping.
- **Effort:** M
- **Impact:** Med
- **Depends on:** P1-1

### P1-10 — Inject person context into meeting Ask AI + brief synthesis
- **What/why:** `MeetingChatTab` passes attendees as raw strings (`MeetingChatTab.swift:39-40`) and `PreMeetingBriefView.generateSynthesis` (`PreMeetingBriefView.swift:197-228`) uses only meeting-derived context. For resolved people, inject a compact person block (role/company, relationship type, last 3 memories, open commitments) into both prompts. Local-only, so no privacy cost; cap tokens per person.
- **User value:** "What should I ask Jane?" answers from the relationship graph, not just this transcript; briefs say "she mentioned her daughter's graduation last time" — the magic the product promises.
- **Effort:** S-M
- **Impact:** High
- **Depends on:** P1-1

### P1-11 — "Mentioned, not present" chips in the people rail
- **What/why:** Transcript extraction already finds people *discussed* who weren't attendees (`PeopleStore.ingestExtraction`). Surface them as a second rail section — "Mentioned: Sarah (client), Tom" — with the extraction's one-line context (`PersonSuggestion.summary`, `PeopleStore.swift:1206-1218`) and quick actions: link/create, attach the context as a person memory, or "create task re: Sarah". Today these land only in the separate `SuggestedPeopleView` queue, divorced from the meeting that produced them.
- **User value:** The invisible cast of every meeting (clients, partners, reports discussed) flows into the graph in-context, where you still remember who "Sarah" is.
- **Effort:** M
- **Impact:** Med
- **Depends on:** P1-2

### P1-12 — Live "in the room" quick-capture per person
- **What/why:** While recording, the people rail (P1-2) pins each linked attendee with two one-tap actions: "Note about Jane" (timestamped, saved as a person memory linked to this meeting) and "Commitment → Jane" (pre-filled directed action item). Complements the planned in-meeting scratchpad (2D), which is meeting-scoped, not person-scoped.
- **User value:** Capture "Jane seemed hesitant about pricing" at second 14:32 with the person edge intact — 1 tap vs. today's record-it-in-notes-then-re-file-it-later (5+ steps, usually skipped).
- **Effort:** M
- **Impact:** Med-High
- **Depends on:** P1-2; richer after 2C

## Top 3 picks

1. **P1-1 AttendeeResolver + auto-link at finalize** — the keystone: one identity layer kills three live bugs and makes every other people↔meeting feature truthful.
2. **P1-2 People rail in meeting detail** — the visible payoff of the mandate; humans become first-class citizens on the app's busiest screen.
3. **P1-3 Speaker→person mapping** — the only item that converts *audio* into relationship data; no competitor with a local-first stance has this.

**Single highest-priority recommendation overall: P1-1.** It is M-effort, fixes the broken follow-up recipients today, and is a hard dependency for the rail, the face piles, the briefs, honest health scores, and the planned hover-cards — build it first or every people feature ships on sand.
