# Competitive — Personal-CRM / Relationship-Product UX (Dex · Clay/Mesh · Folk · Monica · Covve)
> How the best people-products design person profiles, timelines, reminders, and people↔meeting/task integration — and where MeetingScribe's People surfaces fall short of that bar (June 2026 state).

## Full-app audit (through my lens)

**Strong (genuinely competitive already):**
- The chip-first `QuickEncounterSheet` is best-in-class quick-log design — kind chips → optional mood → optional note, "under 10 seconds from open to saved" (`Sources/MeetingScribe/People/QuickEncounterSheet.swift:69-74`). Dex/Covve have nothing this fast for logging an interaction.
- Health score + band ("Health 62 · Drifting" capsule, `People/PersonDetailView.swift:746-763`) and the Today "Stay connected" strip ordered worst-health-first (`UI/StayConnectedSection.swift:15-24`) match Covve's relationship-strength concept and Clay's Home "who to think about today" feed ([clay.earth](https://clay.earth/), [crm.org Covve review](https://crm.org/news/covve-review)).
- `MeetingPersonConnectPanel` — linking an attendee to a person *without leaving the meeting* (`UI/MeetingPersonConnectPanel.swift:5-11`) is better people↔meeting integration than Dex's calendar sync, which only matches on email.
- The 13-week `EncounterHeatMap` + streak (`People/EncounterHeatMap.swift:14-61`) is a genuinely novel consistency visual none of the five competitors have.
- Duplicate review/merge with keep-the-stronger-record logic (`People/PeopleListView.swift:629-705`) is on par with Clay/Nexus dedupe.

**Weak / missing (the gaps):**
1. **No unified person timeline — the defining personal-CRM surface.** Clay's Timeline "brings together Moments — your first, last, and upcoming calendar events, emails, and text messages — with your notes about a person… all the context you need, readable at-a-glance" ([Clay: Introducing Timeline](https://library.clay.earth/hc/en-us/articles/19323744721947-Introducing-Timeline)); Dex sells "remember your interactions with the timeline" ([getdex.com/product](https://getdex.com/product/)); Folk has unified contact timelines ([folk.app](https://www.folk.app/articles/folk-crm-ai-features)). MeetingScribe *fragments* the same data across four places: encounters live in the left identity pane (`PersonDetailView.swift:1417-1436`), meeting history in the Meetings tab (`:1209-1230`), message stats in the Messages tab (`:1712-1751`), memories/notes in the Notes tab (`:1684-1708`, `:1907`), decisions in yet another section (`:1174-1207`). Answering "what's our story?" requires visiting 4 tabs.
2. **Quick-log isn't reachable from the person profile.** `PersonDetailView.swift:342-346` still opens the *old* long-form `AddEncounterSheet`; the premium `QuickEncounterSheet` is only wired from Today's drift strip (`StayConnectedSection.swift:122`). The profile — the most natural place to log — has the worst flow (click Encounter → type event name → pick date → save ≈ 5 interactions vs. 1 chip tap).
3. **Mood data is captured then thrown away.** `QuickEncounterSheet.saveIfValid()` serializes mood as a `" [mood:great]"` string suffix inside `notes` (`QuickEncounterSheet.swift:205-211`) — nothing ever parses it back; the heat map colors purely by count (`EncounterHeatMap.swift:63-71`). The emotional signal the app is uniquely positioned to own (it has transcripts + iMessage sentiment) dead-ends as string pollution.
4. **Encounter kind is persisted as an emoji string** — `eventName: "\(kind.emoji) \(kind.rawValue)"` → `"📞 Call"` written into the vault (`QuickEncounterSheet.swift:209`). Data polluted with presentation; un-queryable, un-restylable.
5. **Reconnect prompts have no context and no action.** Dex's nudges arrive "with context: who they are, when you last talked, what you discussed," and Clay's Nexus drafts the outreach email ([getdex.com](https://getdex.com/), [clay.earth/nexus](https://clay.earth/nexus)). MeetingScribe's Reconnect card offers a bare checkmark that silently bumps `lastInteractionAt` (`People/PeopleInsightsView.swift:26-35`) — it rewards *dismissing* the relationship, not nurturing it.
6. **The health badge is unexplained and trendless.** A static capsule with a hover tooltip (`PersonDetailView.swift:747-763`). No breakdown of *why* 62, no direction (improving/declining), no suggested next action. Premium products never show a score they can't explain.
7. **Only one special date: birthday** (`People/Person.swift:224`). Dex reminders cover "anniversary? product launch? high-school graduation?" ([getdex.com/product](https://getdex.com/product/)); Monica tracks arbitrary life events ([monicahq.com](https://www.monicahq.com/)).
8. **No "how long you've known each other" story.** Clay's Cards "summarize how long you've known each other and how much you interact and present a timeline of your first, most recent, and upcoming interactions" ([Clay: About Cards](https://library.clay.earth/hc/en-us/articles/6821293867675-About-Cards)). MeetingScribe has the data (first encounter, `createdAt`, provenance footer `PersonDetailView.swift:1978`) but never composes the sentence.
9. **The graph is a write-off instead of an asset.** Demoted to an "experimental… just decorative" icon (`PeopleListView.swift:212-218`), yet `RelationshipEdge.sharedMeetingCount` (`People/Graph/PeopleGraphView.swift:100-109`) is exactly the co-occurrence data Clay/Nexus monetizes as "who do I know at…" and intro paths.
10. **Emoji-as-iconography reads cheap.** Relationship types render as raw emoji in list rows (`PeopleListView.swift:582-586`), the type picker (`PersonDetailView.swift:780-791`), and Today badges (`StayConnectedSection.swift:81-83`). Things 3 / Craft / Linear never use OS emoji as system glyphs; `RelationshipType.color` (shipped, PR #89) exists precisely to replace this and is barely used.
11. **People list rows hide the one signal that matters.** `PersonRow` shows name + relative time (`PeopleListView.swift:575-601`) but not health — triage requires opening each person, while Covve color-codes strength right in the list ([crm.org](https://crm.org/news/covve-review)).
12. **No keyboard model on the profile.** Clay: "take a note with 'N', switch to About with 'A', Timeline with 'T'" ([Clay Timeline article](https://library.clay.earth/hc/en-us/articles/19323744721947-Introducing-Timeline)); Dex sells ⌘K + shortcuts as a headline feature. PersonDetailView has zero `keyboardShortcut` affordances outside sheet defaults.

## Existing-plan items I rank highest
1. **2B chip-first encounter quick-log on PersonDetailView** — the sheet already exists and is excellent; the profile still opens the legacy form (`PersonDetailView.swift:343`). Cheapest 5→1-click win in the app.
2. **2A EntityLink/router unification** — person-detail decision and mention rows still navigate via raw `NotificationCenter.post` (`PersonDetailView.swift:1184-1186`, `:1643-1645`); backlinks can't feel instant until this lands.
3. **2B warm copy + photo hero avatar** — `MSAvatar` already accepts an image (`UI/MSAvatar.swift:11-24`) and `photoRelativePaths` exists, yet the profile renders initials (`PersonDetailView.swift:599`). Faces are the #1 premium signal in every competitor.
4. **2D pre-meeting briefs / 2H 1:1 prep digest** — Dex's "before a call, surface a brief on the person" is now table stakes ([getdex.com blog](https://getdex.com/blog/personal-crm-email-calendar-integration/)).
5. **2B auto-bump lastInteractionAt + calendar-aware drift** — every reminder competitor lives or dies on truthful recency; without it the health system cries wolf.
6. **2G PersonDetailView decomposition (2,300+ LOC)** — prerequisite for every redesign below.

## NET-NEW recommendations

### C2-1 — Unified "Story" timeline as the person profile's default tab
- **What/why:** Replace the Overview tab default with a single reverse-chronological stream interleaving encounters (kind+mood), recorded meetings, calendar-only meetings, memories, attached notes, decisions, and message-volume markers — ending at a "First met" anchor card. The data is all loaded today, just split across `encountersSection`/`meetingHistorySection`/`memoriesSection`/`decisionsSection`/`messagesSection` (`PersonDetailView.swift:1417/1209/1684/1174/1712`). This is the category-defining surface: Clay Timeline ([source](https://library.clay.earth/hc/en-us/articles/19323744721947-Introducing-Timeline)), Dex unified timeline ([source](https://getdex.com/product/)), Folk unified timelines ([source](https://www.folk.app/articles/folk-crm-ai-features)), Monica's journal-per-contact ([source](https://www.monicahq.com/)). MeetingScribe has *richer* data (transcripts!) than all four and the worst presentation of it.
- **User value:** "What's our story?" answered in one scroll instead of 4 tab visits; the profile becomes desirable, not administrative.
- **Effort:** M (data is in memory; this is a view-layer merge — gated on PersonDetailView decomposition)
- **Impact:** High
- **Depends on:** 2G decomposition; none net-new

### C2-2 — Keep-in-touch board: a health-band kanban as a People list mode
- **What/why:** Add a third People view mode (list · graph · **board**): columns Thriving / Steady / Drifting / Overdue, cards = avatar + last-interaction + cadence, drag-to-Thriving opens the quick-log, right-edge "snooze" sets `lastCheckInAt`. Dex ships exactly this — "a Kanban-style keep-in-touch board that visually shows who you've reached out to and who's due for follow-up" ([Dex personal-CRM guide](https://getdex.com/blog/personal-crm-for-networking/)). All inputs exist (`RelationshipHealth`, `effectiveCheckInDays`, `StayConnectedSection.swift:38-51`); the ActionItems board layout can be reused.
- **User value:** Whole-network triage in one screen; turns the health score from a per-person stat into a workflow.
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### C2-3 — Health "why" popover + trend arrow + next-best action
- **What/why:** Make the health capsule (`PersonDetailView.swift:747-763`) clickable: a popover showing the three score components (recency vs. cadence, frequency, consistency) as mini-bars, a 12-week score sparkline, and ONE suggested action ("24 days past your monthly cadence — log a call or schedule coffee") with a button that runs it. Competitors never show unexplained numbers: Covve pairs strength with "why now" nudges ([crm.org](https://crm.org/news/covve-review)); Clay Home explains every suggestion ([clay.earth](https://clay.earth/)).
- **User value:** Converts a passive grade into trust + an act-now affordance; differentiates the score from a gimmick.
- **Effort:** S–M (formula already pure in `VaultKit.RelationshipHealth`; historical series computable from encounter dates)
- **Impact:** High
- **Depends on:** none

### C2-4 — Reconnect-with-context: last-topic snippet + local AI message draft
- **What/why:** Upgrade the Reconnect card (`PeopleInsightsView.swift:20-38`) and Stay-connected rows: each row expands to show *what you last talked about* (last encounter note, last meeting title, or last iMessage topic) and two actions — "Draft a message" (Ollama, relationship-type-aware tone, copies to clipboard/mailto) and "Log it". Kill the bare bump-checkmark, which currently rewards dismissal. Dex nudges "with context: who they are, when you last talked, what you discussed" ([getdex.com](https://getdex.com/)); Clay's Nexus "drafts emails" and suggests outreach ([clay.earth/nexus](https://clay.earth/nexus)); Folk's AI "writes a one-sentence opener for each contact from fields you already maintain" ([folk.app](https://www.folk.app/articles/folk-crm-ai-features)). MeetingScribe can do this 100% locally — a marquee privacy demo.
- **User value:** Removes the real blocker to reconnecting (not remembering *what to say*); reach-out goes from app-switch + blank cursor → 1 click.
- **Effort:** M
- **Impact:** High
- **Depends on:** C2-3 optional; Ollama presence (graceful fallback to snippet-only)

### C2-5 — Special dates beyond birthday (anniversaries + custom recurring)
- **What/why:** `Person` carries exactly one date field (`Person.swift:224`). Add `specialDates: [{label, date, recurring}]` — anniversary, kid's birthday, "started new job", custom — surfaced in PeopleInsightsView's birthday card (generalized to "Coming up"), Today, and check-in notifications. Dex's reminder pitch is literally "Have an upcoming anniversary? Product launch? High school graduation?" ([getdex.com/product](https://getdex.com/product/)); Monica's life-events model proves the personal-side demand ([monicahq.com](https://www.monicahq.com/)).
- **User value:** The moments that most strengthen relationships are exactly the non-birthday ones nobody remembers.
- **Effort:** S (additive JSON field + reuse `nextOccurrence` logic at `PeopleInsightsView.swift:115-126`)
- **Impact:** Med–High
- **Depends on:** none

### C2-6 — Promote mood to a first-class field; mood-tinted heat map + trendline
- **What/why:** Stop serializing mood into the notes string (`QuickEncounterSheet.swift:205-206`); add `mood: String?` to `Encounter`, migrate by parsing existing `[mood:x]` tags. Then (a) tint `EncounterHeatMap` cells by dominant mood instead of count-only opacity (`EncounterHeatMap.swift:63-71`), (b) show a mood trendline in the C2-3 popover. No competitor has per-interaction emotional telemetry — this is MeetingScribe's "relationship coach" wedge made visible, and today it's literally being thrown away.
- **User value:** "Our last three calls felt tense" becomes glanceable; the coach loop gets its key signal.
- **Effort:** S–M
- **Impact:** Med–High (High for the partner/family wedge)
- **Depends on:** none

### C2-7 — De-emoji the people system: typed glyph + color chips everywhere
- **What/why:** Replace raw emoji as system iconography — relationship type in rows (`PeopleListView.swift:582-586`), picker (`PersonDetailView.swift:780-791`), Today badges (`StayConnectedSection.swift:81-83`) — with SF Symbol + `RelationshipType.color` capsule chips (the color shipped in PR #89 and is barely used). Also stop persisting `"📞 Call"` into `eventName` (`QuickEncounterSheet.swift:209`): store `kind` raw value, render emoji/symbol at view time. Benchmark: Things 3/Linear/Craft never use OS emoji as UI chrome; Clay/Dex use drawn glyphs exclusively.
- **User value:** Single biggest "clean and expensive" lever on People surfaces; unlocks consistent dark-mode/tint behavior and queryable encounter kinds.
- **Effort:** S
- **Impact:** Med (visual), High (data hygiene)
- **Depends on:** none

### C2-8 — "In common" module: salvage the graph into the profile
- **What/why:** The force graph is demoted as "rarely useful… just decorative" (`PeopleListView.swift:212-218`), yet its edge data (`sharedMeetingCount`, explicit relationships) is the valuable part. Add an "In common" section to the person profile: people who co-attend meetings with them (with counts), explicit relations, shared tags — each chip navigating via the router. This is the local-first version of Clay/Nexus's network navigation ("find the right person, make better introductions" — [clay.earth/nexus](https://clay.earth/nexus)) and Monica's relationship mapping ([github.com/monicahq/monica](https://github.com/monicahq/monica)).
- **User value:** "Who else knows Priya?" / "who should join this meeting?" answered on the profile; graph investment finally pays rent.
- **Effort:** M (reuse `PeopleGraphViewModel` edge builder headlessly)
- **Impact:** Med–High
- **Depends on:** 2A EntityLink

### C2-9 — "Known for 3 years" relationship summary line + first-met hero
- **What/why:** Compose the sentence Clay's Cards lead with — "summarize how long you've known each other and how much you interact… first, most recent, and upcoming interactions" ([Clay: About Cards](https://library.clay.earth/hc/en-us/articles/6821293867675-About-Cards)) — into the identity panel under the name: *"Known ~3 years · met at Purple Party 2026 · 14 meetings · last seen 6d ago"*. Inputs all exist: earliest encounter, `createdAt`, provenance footer (`PersonDetailView.swift:1978`), meeting counts.
- **User value:** Instant emotional grounding on every profile open; the single line that makes the product feel like it *knows* your relationships.
- **Effort:** S
- **Impact:** Med
- **Depends on:** pairs with C2-1's "First met" anchor

### C2-10 — Health-ring avatars across every people surface
- **What/why:** Wrap `MSAvatar` (`UI/MSAvatar.swift:9-44`) with an optional band-colored ring (the planned ring is profile-only) and adopt it in `PersonRow` (`PeopleListView.swift:575-601`), attendee chips (`UI/MeetingDetailHeader.swift:25-51`), Stay-connected rows, and graph nodes. Covve's list-level strength color-coding ([crm.org](https://crm.org/news/covve-review)) proves glanceable triage demand; rings also instantly make *meetings* people-aware ("this attendee is drifting") — the audit's pillar 3 with zero new layout.
- **User value:** Network health visible everywhere people appear, not just on one profile widget.
- **Effort:** S
- **Impact:** Med–High
- **Depends on:** 2B ring formula (shipped); C2-7 recommended first so ring color ≠ emoji clash

### C2-11 — Keyboard-first person profile (N / L / T / ⌘1–5)
- **What/why:** Clay ships single-key profile verbs ("N" note, "A" about, "T" timeline — [source](https://library.clay.earth/hc/en-us/articles/19323744721947-Introducing-Timeline)); Dex headline-features ⌘K speed ([source](https://getdex.com/product/)). Add to PersonDetailView: `N` focus new-memory field, `L` open QuickEncounterSheet, `T` new task for person, `⌘1–5` switch `PersonTab` (`PersonDetailView.swift:276-287`). Complements (does not duplicate) the planned global Cmd-K.
- **User value:** Power-user muscle memory; "expensive" apps are felt through the keyboard.
- **Effort:** S
- **Impact:** Med
- **Depends on:** C2-12 wiring of QuickEncounterSheet

### C2-12 — One encounter flow: retire AddEncounterSheet, wire QuickEncounterSheet into the profile
- **What/why:** Concrete redesign of the planned 2B item: `PersonDetailView` still opens the legacy long-form `AddEncounterSheet` (`PersonDetailView.swift:343`), while the 1-tap `QuickEncounterSheet` is reachable only from Today (`StayConnectedSection.swift:122`). Replace all `showAddEncounter` call sites (`:343`, `:687`, `:1424`) with QuickEncounterSheet, add an "event name" optional field for the import-party use case, delete the old sheet. Two parallel flows for the same verb is a usability fork no competitor tolerates.
- **User value:** Logging from the profile: ~5 interactions → 1 tap, everywhere, consistently.
- **Effort:** S
- **Impact:** High
- **Depends on:** none (it *completes* plan item 2B)

## Top 3 picks
1. **C2-1 Unified Story timeline** — the defining personal-CRM surface; MeetingScribe has the best data and the most fragmented presentation of any product reviewed.
2. **C2-4 Reconnect-with-context + local AI draft** — turns drift detection into actual reconnection, 100% locally; no competitor can match the privacy story.
3. **C2-2 Keep-in-touch board** — converts the shipped health score into a daily whole-network workflow (Dex-proven).

**Single highest-priority rec overall:** C2-1 — but ship C2-12 first (an S-effort fix that completes an already-planned item and removes the app's most embarrassing usability fork on its most important entity).
