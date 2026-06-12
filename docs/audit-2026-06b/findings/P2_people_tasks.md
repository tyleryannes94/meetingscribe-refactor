# PM — People ↔ Tasks/Commitments Integration
> Lens: every task should know which human it involves — who asked, who owes whom, what to raise next time you talk — and every person surface should answer "what's open between us?"

## Full-app audit (through my lens)

### Strong (the rails exist)
- **`ActionItem.ownerPersonID` is a real, well-designed hard link** with back-compat decoding and an explicit purpose comment: "Enables exact, bidirectional person↔task navigation" (`Sources/MeetingScribe/ActionItems/ActionItem.swift:23-28`). `delegated` ("waiting-on", PM-19) also exists (`ActionItem.swift:84-85`).
- **`TaskQuery` already supports a person facet** — `Scope.person(String)` and `Filters.ownerPersonID` (`ActionItems/TaskQuery.swift:23-24, 33`) with a pure engine and tests.
- **Store-level person APIs exist**: `setOwnerPerson(_:personID:ownerName:)` and `items(forPerson:)` (`ActionItems/ActionItemStore.swift:905-914`).
- **PersonDetailView has a Tasks tab** with per-person quick-add that hard-links the new task (`People/PersonDetailView.swift:1509-1550`) and a legacy-tolerant owner matcher (`PersonDetailView.swift:1486-1497`).
- **TaskPageView can link assignee → Person and navigate** (`UI/TaskPageView.swift:217-260`).

### Weak (the rails are unwired or drifting)
- **The extractor never sets `ownerPersonID`.** `ActionItemExtractor.extract` parses a free-text `owner` and stops (`ActionItems/ActionItemExtractor.swift:39-55`). Across the whole app there are exactly **two** call sites that ever set the hard link — both manual (`TaskPageView.swift:227-244`, `PersonDetailView.swift:1513`). So in practice the person↔task graph is empty unless the user hand-links every task.
- **`TaskQueryEngine` is dead code in the UI.** Its only consumer is `ActionItemStore.tasks(matching:)` (`ActionItemStore.swift:172-173`); no view calls it. Meanwhile **three parallel filter implementations drift**: `ActionItemsViewModel.filteredSorted` (`UI/ActionItemsViewModel.swift:113-174`), the live view's own chain (`UI/ActionItemsListView.swift:280-310`), and `TaskQuery`. The resurrected `ActionItemsViewModel` (planned 2A) is itself unwired — `ActionItemsView` still carries ~25 `@State` vars (`UI/ActionItemsView.swift:12-59`).
- **Two competing definitions of "mine."** `ActionItemsListView.isMine` treats unassigned as mine (`ActionItemsListView.swift:313-318`); `ActionItemExtractor.isMine` treats unassigned as not-mine unless the text names you (`ActionItemExtractor.swift:65-88`). The "My open" chip and the capture filter will disagree.
- **Owner grouping/sorting keys on the raw string.** `GroupBy.owner` buckets by `$0.owner ?? "Unassigned"` (`ActionItemsViewModel.swift:244-246`); table sort likewise (`UI/ActionItemsTableView.swift:32`). "Sarah", "Sarah Chen", and "sarah@x.com" are three different people to the Tasks tab.
- **Owner chips render but never navigate.** Avatar + name are static decoration in `UI/MeetingActionRow.swift:31-36`, `UI/TriageInboxView.swift:88-92`, `UI/ActionItemsTableView.swift:89-92`. Click cost to reach a task owner's profile from any list/board/meeting row today: **impossible** (only via opening the full task page → arrow button).
- **The waiting-on universe is silently discarded by default.** `captureDelegatedTasks` defaults `false` (`Models/Settings.swift:349-351`), so others' commitments from meetings are dropped at extraction (`ActionItemExtractor.swift:37-38`); the "Delegated" chip only even appears if such items exist (`UI/ActionItemsChrome.swift:323-327`).
- **Pre-meeting brief is people-blind on tasks.** `PreMeetingBriefView.openItemsSection` lists items flat — no owner shown, no per-attendee grouping, no navigation (`UI/PreMeetingBriefView.swift:74-109`); matching is by meeting co-attendance, not by person link (`PreMeetingBriefView.swift:177-181`).
- **Follow-ups aren't addressed to anyone.** `FollowUpGeneratorService` makes one generic email/Slack from summary + item strings (`Followup/FollowUpGeneratorService.swift:10-20`) — no recipient, no Person record, no "here's what *you* owe me" framing.
- **Tasks IA has zero person concept.** `ActionItemsSidebar.swift` contains no person/owner section (grep: 0 hits); `OwnerScope` is only `anyone/mine/delegated` (`ActionItemsView.swift:114-117`). Quick-add parses `!priority #label date` but no person token (`ActionItems/TaskQuickAddParser.swift:24-70`).
- **Web forks the mental model**: the mobile Tasks API round-trips only the free-text `owner` string, never `ownerPersonID` (`Web/WebAPI.swift:692, 711`).
- **Today's "Needs attention" hides the humans** — rows show title/meeting/due only (`UI/NeedsAttentionWidget.swift:60-88`).

### Missing entirely
- No per-person agenda ("raise this next time we talk"). No waiting-on aging/nudges. No open-task counts on people list rows or attendee chips. No attendee-first assignment in the meeting Actions tab (`UnifiedMeetingDetail.swift:193-236` offers confirm/add, never assign).

## Existing-plan items I rank highest
1. **2C directed commitments (`direction` + `personID`)** — the single most important model change; everything below composes with it.
2. **2C inline meeting→task creation with bidirectional links** — meetings are where person context is richest; capture the link at birth.
3. **2A `EntityLink` open protocol** — owner chips, "From meeting" labels, and brief rows all need one `router.open(_:)`.
4. **2A resurrect `ActionItemsViewModel`** — but it must absorb `TaskQuery` (see P2-10), not become a fourth filter implementation.
5. **2H per-report 1:1 prep digest** — endorse, and generalize beyond direct reports (P2-5).
6. **Phase 5 commitment accountability engine** — the long-game payoff of all of the below.

## NET-NEW recommendations

### P2-1 — Auto-resolve extracted owners to Person records
- **What/why:** At extraction (and at triage-confirm), resolve `parsed.owner` against `PeopleStore` — exact alias/email match, then attendee-of-this-meeting fuzzy match — and stamp `ownerPersonID` (`ActionItemExtractor.swift:39-55` currently leaves it nil forever). Ambiguous matches surface as a one-click confirm chip in the Triage row. Backfill pass over existing `action_items.json` using the matcher already written in `PersonDetailView.swift:1472-1497`, hoisted out (see P2-10). Also expose `ownerPersonID` through `WebAPI.swift:711` so mobile doesn't fork.
- **User value:** The planned iOwe/theyOwe ledger is an empty room without this — today the person↔task graph populates only via 2 manual call sites. Person task views, briefs, and health signals all light up retroactively.
- **Effort:** M
- **Impact:** High
- **Depends on:** none (gates planned 2C; gates P2-2/4/5/6/12)

### P2-2 — People facet in the Tasks IA (sidebar section + person scope)
- **What/why:** Add a "People" group to the Tasks rail (`UI/ActionItemsSidebar.swift` — currently zero person concept) listing the top N linked owners with open/overdue counts; selecting one drives the *already-built but never-called* `TaskQuery.Scope.person` (`TaskQuery.swift:23`, engine wired only at `ActionItemStore.swift:172`). Add a matching `@person` filter chip next to "My open" in `ActionItemsChrome.swift:315-327`.
- **User value:** "Everything between me and Priya" becomes one click from Tasks — today it requires leaving Tasks for PersonDetail. Counts the clicks: person-filtered task view 4+ clicks (switch tab → People → find person → Tasks tab) → 1.
- **Effort:** M
- **Impact:** High
- **Depends on:** P2-1

### P2-3 — Owner chips that navigate (and link) everywhere
- **What/why:** Make the avatar+name renders in `MeetingActionRow.swift:31-36`, `TriageInboxView.swift:88-92`, `ActionItemsTableView.swift:89-92`, and `NeedsAttentionWidget` rows live: linked → `router.openPerson(pid)`; unlinked → small popover "Link to person / Create person" (reusing the P2-1 resolver). This is the concrete people-spec for the planned `EntityLink` work, which never enumerates task owner chips.
- **User value:** Task→human navigation goes from impossible-from-lists to one click; unlinked owners self-heal as users touch them.
- **Effort:** S
- **Impact:** High
- **Depends on:** P2-1, planned 2A EntityLink

### P2-4 — Per-person agenda accumulation ("Next time we talk")
- **What/why:** A lightweight `agendaPersonIDs: [String]?` on `ActionItem` plus an "Agenda" swimlane on PersonDetail and a `>@person` quick-add affix. Anything — task, note line, triage item — can be flagged "raise with Sarah." When a meeting with Sarah is recorded/finalized, her queued agenda shows in the pre-meeting brief and in-meeting scratchpad, then prompts "discussed → done / carry forward." Nothing in the plans covers between-meeting accumulation (2H's digest is read-only prep for reports).
- **User value:** Kills the "I had three things for this call and remembered none" failure — the core promise of a relationship second brain. Things 3's Agenda-style mechanic, but auto-surfaced by the calendar.
- **Effort:** M
- **Impact:** High
- **Depends on:** P2-1 (resolver), pairs with planned pre-meeting brief (2D)

### P2-5 — Person-grouped pre-meeting brief ("Between you and …")
- **What/why:** Restructure `PreMeetingBriefView.openItemsSection` (`PreMeetingBriefView.swift:74-109`) from a flat anonymous list into per-attendee cards: avatar + "You owe (2) · They owe (1) · To discuss (3)", each row navigable, sourced from `ownerPersonID`/direction/agenda instead of meeting co-attendance only (`:177-181`). Same component reused in the attendee hover card and 1:1 digest.
- **User value:** The brief finally answers the only pre-meeting question that matters: *what's open between us?* — per human, not per meeting.
- **Effort:** M
- **Impact:** High
- **Depends on:** P2-1; P2-4; planned 2C direction field

### P2-6 — Waiting-on lifecycle: capture by default, age, nudge
- **What/why:** Flip `captureDelegatedTasks` default to true (`Models/Settings.swift:349-351`) so others' commitments stop being silently discarded; add a permanent "Waiting on" sidebar bucket grouped by person with age badges ("waiting 9d"); add a one-click **Nudge** action that opens a person-addressed follow-up draft (P2-7) quoting the commitment and its source meeting. The plan adds the `direction` *field*; nothing specifies the waiting-on *lifecycle*.
- **User value:** Accountability for the other side of every commitment — the half of "who owes whom" the app currently throws away at extraction (`ActionItemExtractor.swift:37-38`).
- **Effort:** M
- **Impact:** High
- **Depends on:** planned 2C direction; P2-1

### P2-7 — Person-addressed follow-up drafts
- **What/why:** Extend `FollowUpGeneratorService` (one generic blob today, `FollowUpGeneratorService.swift:10-20`) to take a recipient `Person`: prompt includes *their* open items vs yours, addresses them by name, prefills their email from the Person record into a `mailto:`. Sending logs an encounter / bumps `lastInteractionAt` — wiring follow-ups into the relationship loop, which planned 2H ("persist sent-status") doesn't touch.
- **User value:** Follow-up becomes a directed social act ("here's what each of us owes"), and doing it keeps the relationship health score honest.
- **Effort:** M
- **Impact:** Med
- **Depends on:** P2-1, P2-6

### P2-8 — `@person` and `>person` tokens in quick-add
- **What/why:** `TaskQuickAddParser` handles `!priority #label date` only (`TaskQuickAddParser.swift:24-70`). Add `@name` → fuzzy person match (recent-interaction-first, the `TaskPageView.swift:17-21` ranking) setting `ownerPersonID`+`owner`, and `>name` → theyOwe/delegated. Inline autocomplete popover in the quick-add field. This is the *tasks-capture* spec the Phase-3 "smart @-mention completions" line never details — and it should ship with 2C, not Phase 3.
- **User value:** A fully person-attributed task in one typed line: "send deck @sarah friday !high" — assignment cost drops from 4 clicks through an unsearchable 50-item menu (`TaskPageView.swift:233-253`) to 0.
- **Effort:** M
- **Impact:** High
- **Depends on:** P2-1 resolver; planned 2C direction

### P2-9 — Attendee-first assignment in meeting Actions tab
- **What/why:** `MeetingActionRow` has no assign affordance and the Actions tab none either (`UnifiedMeetingDetail.swift:193-236`). Add an inline avatar menu per row listing *this meeting's attendees* (already Person-linkable via `MeetingPersonConnectPanel`, `UnifiedMeetingDetail.swift:154-163`) + "Me"; one click sets owner+`ownerPersonID`. Replace `TaskPageView`'s flat 50-person `Menu` with the same searchable, attendees-first picker component.
- **User value:** Assignment happens where the context is — right after the meeting, choosing among the 4 humans who were actually there, not scrolling 50 contacts.
- **Effort:** S
- **Impact:** High
- **Depends on:** P2-1 (shared picker/resolver)

### P2-10 — One `PersonResolver` + collapse the four filter brains
- **What/why:** Hoist owner-string→Person resolution (currently private in `PersonDetailView.swift:1472-1497`) into a shared `PersonResolver` used by the extractor, grouping, web, and pickers; key `GroupBy.owner` and table owner-sort on resolved personID with string fallback (fixes the 3-buckets-per-human bug, `ActionItemsViewModel.swift:244-246`); reconcile the two contradictory `isMine` definitions (`ActionItemsListView.swift:313-318` vs `ActionItemExtractor.swift:65-88`); and make the resurrected `ActionItemsViewModel` compile down to `TaskQuery` so the engine stops being dead code (`ActionItemStore.swift:172`).
- **User value:** Person identity behaves identically in every view, badge, and the web — prerequisite for trusting any per-person count the app shows.
- **Effort:** M
- **Impact:** Med (but multiplies every other item's correctness)
- **Depends on:** none

### P2-11 — Humans on Today: person chips in Needs Attention + "owed to people" lens
- **What/why:** Add the owner avatar/person chip to `NeedsAttentionWidget` rows (`NeedsAttentionWidget.swift:60-88`) and a second segment "Waiting on others" (delegated, aging-sorted). Rows deep-link to the task *and* the person (chip). Today currently shows drift (relationships) and dues (tasks) as separate worlds; this is the join.
- **User value:** The morning glance answers "who am I blocking, who is blocking me" — not just "what is due."
- **Effort:** S
- **Impact:** Med
- **Depends on:** P2-1, P2-6

### P2-12 — Open-commitment counts on people surfaces
- **What/why:** Badge `PeopleListView` rows and the planned attendee hover card with "3 open · 1 overdue" from `store.items(forPerson:)` (`ActionItemStore.swift:912-914`), tappable into the P2-2 person-scoped task view; show "✓ nothing open between you" as the premium empty state.
- **User value:** Every glance at a person carries their task truth; the People tab stops being a contacts list and becomes a ledger.
- **Effort:** S
- **Impact:** Med
- **Depends on:** P2-1, P2-2

## Top 3 picks
1. **P2-1 Auto-resolve extracted owners → Person records** — the unlock; without it the planned directed-commitments ledger ships empty.
2. **P2-4 Per-person agenda accumulation** — the most differentiated net-new capability; turns the app from recorder into relationship working memory.
3. **P2-6 Waiting-on lifecycle (capture-by-default + age + nudge)** — recovers the half of every meeting's commitments the app currently deletes.

**Single highest-priority rec overall: P2-1.** Every person↔task feature — planned (2C iOwe/theyOwe, ledger, backlinks) and proposed (agenda, briefs, nudges, facets) — reads `ownerPersonID`, and today only two manual code paths in the entire app ever write it.
