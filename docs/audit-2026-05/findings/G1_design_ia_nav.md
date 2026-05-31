# Design — Information Architecture & Navigation

*Lens: how the app is structured into sections, how users move between them, how they find things, and how surfaces link to each other.*

## Full-app audit (through my lens)

The rebuild genuinely advanced the IA — 7→5 sections, a grouped left rail (`WORKSPACE` / `ORGANIZE`), Meetings as a real `NavigationSplitView`, a ⌘K palette, ⌘1–⌘5 jumps, and a `meetingscribe://` entity-link model. But under the hood the navigation is still **four incompatible models stitched together**, and the cross-surface graph the product is built on (meeting↔person↔task) is only half-wired in the UI.

**1. The app shell is not a navigation container — it's an opacity switcher.** `MainWindow.tabContent` is a `ZStack` of all visited tabs, shown/hidden via `.opacity` + `.allowsHitTesting` (`MainWindow.swift:86-103`). This is the *one* place V3 said should become a `NavigationSplitView` (NAV-4) and it didn't happen. Consequences cascade: there is no shared navigation path, so no app-level back/forward, no breadcrumb, no `NavigationPath` to drive deep-links into, and every tab has to reinvent its own detail-presentation.

**2. A meeting still opens four different ways.** This is the core IA defect and it directly contradicts the plan's "one canonical meeting surface" goal:
- Meetings tab → split-view detail pane (`MeetingsView.swift:55-70`).
- Today → `NavigationStack` push with a back arrow (`TodayView.swift:28-39, 259-279`).
- Global search → **modal sheet** `meetingSheet(_:)` at 860×680 (`MainWindow.swift:296, 393-410`).
- PersonDetail backlink → posts `.meetingScribeOpenEntity` → `routeEntity(.meeting)` → **also the modal sheet** (`MainWindow.swift:423-428`; `PersonDetailView.swift:727-731`).
The `routeEntity` path still carries the exact `dismiss + DispatchQueue.asyncAfter(0.18)` hack V3 flagged (NAV-3) at `MainWindow.swift:463-466`. So the same object has three different chromes (split pane / pushed page / floating sheet) and two different back behaviors. Users build no stable mental model of "where a meeting lives."

**3. Per-tab navigation models are inconsistent.** Today = `NavigationStack`+push (`TodayView.swift:28`); Meetings = `NavigationSplitView` (`MeetingsView.swift:45`); People = bare `HSplitView`+`selection` (`PeopleListView.swift:35`); Voice Notes = `HSplitView`+`selection` (`QuickNotesView.swift:18`); Tasks = custom `ProjectRail`+pane. Only Today and the Summary tab use `NavigationStack` at all (grep: just `MainWindow`, `MeetingSummaryTab`, `TodayView`). So master-detail tabs (People, Voice Notes) have **no back affordance and no deep-link push** — selection is the only navigation primitive, and it's lost on tab switch.

**4. The cross-surface graph is read-only and lossy in the UI.** PersonDetail's primary "In your recordings" list (`PersonDetailView.swift:511-552`) renders meetings as **static `HStack`s with no Button/tap** — you literally cannot click from a person to their meeting there. Only the secondary `meetingMentions` backlink list is tappable, and it dumps you into the modal sheet. Attendees on a meeting (`MeetingDetailHeader.swift:505+`) are clickable only via **right-click context menu** ("Add to People"), with no left-click to open an existing person and no visual cue that a chip is a known contact (`existingPerson` is computed but only gates the context menu). The relationship graph is the product's moat, yet the navigable links between its three node types are mostly absent or hidden.

**5. The `meetingscribe://` scheme is registered nowhere with the OS.** `WorkspaceLinks.swift` defines a full URL scheme and parser, but there is **no `CFBundleURLSchemes` in Info.plist and no `onOpenURL`/Apple-Event handler anywhere** (grep returns NONE). So links work only inside the running app's markdown editor — Spotlight, the MCP server, iPhone Shortcuts, Mail follow-ups, and Reminders cannot deep-link a user to a specific meeting/person/task. The infrastructure is built but the front door is locked.

**6. Search is a teleport, not navigation.** ⌘K (`GlobalSearchView`) is good — scoped filter tabs, recency suggestions, keyboard nav. But results have **no path** behind them: picking a meeting opens the orphan modal sheet, so search can't leave you "inside Meetings with that meeting selected and the list still there to keep browsing." There's also no recent-history or "back to results," and the People filter quietly forks to a *different* code path (`peopleSearch` vs `WorkspaceIndex`) to dodge an index bug (`GlobalSearchView.swift:190-201`) — a sign the unified index isn't actually unified.

**7. Findability gaps in the rail itself.** "Tasks" maps to section `.actions` and "Voice Notes" to `.notes` (`MainWindow.swift:16-18`) — fine, but the rail has **no live state badges** (no count of meetings finalizing, overdue tasks, or unsent follow-ups), so the only way to discover work is to open each tab. The "needs attention" intelligence exists but lives *inside* Today (`NeedsAttentionWidget`), invisible from anywhere else.

**8. Empty states are decorative, not navigational.** Meetings empty (`MeetingsView.swift:179-192`), People empty, the detail placeholders ("Select a meeting") describe the void but offer no next action wired to the actual entry points (Meetings empty doesn't surface Import/Record; the detail placeholder isn't a CTA). They're dead ends.

## Existing-plan items I rank highest

1. **NAV-4 — move the app shell to a real `NavigationSplitView`** (V3 §3.1). Through my lens this is the keystone: it's the prerequisite for app-level back/forward, a shared navigation path to deep-link into, and consistent detail presentation. Without it, every other nav fix is a local patch.
2. **NAV-3 — route search/deep-link into Meetings selection, not a modal sheet** (V3 §3.1). Kills the 4th meeting chrome and the `asyncAfter(0.18)` hack. This is what makes "one canonical meeting surface" actually true.
3. **Unified "find everything about X"** (V3 §4 / REMAINING_WORK §4). Search-as-navigation is the highest-leverage findability lever in a relationship app; the fact that People search already forks code paths shows the index needs to genuinely unify.
4. **PPL-4 — show all calendar meetings per person, not just recorded** (V3 §3.3). A person→meeting tab that reads empty for un-recorded 1:1s breaks the core mental model that People is the hub of your relationships.
5. **DEF-2 — make Meetings a focusable `List(selection:)`** (V3 §3.5). Keyboard parity across master-detail tabs is table stakes for navigation consistency.

## NET-NEW recommendations

**D1-1 — One canonical entity router with a real `NavigationPath` per tab.**
*What/why:* Introduce a single `WorkspaceRouter` that owns a `NavigationPath` for each section and a `func open(_ entity:)` that always resolves to the *same* in-tab destination (meeting→Meetings selection, person→People selection, task→Tasks). Replace the `activeSheet = .meeting(...)` modal and the `asyncAfter(0.18)` hack entirely. *User value:* a meeting/person/task looks and behaves identically no matter where you came from; back always means the same thing. *Effort:* M. *Impact:* High. *Depends on:* NAV-4 (shell as NavigationSplitView).

**D1-2 — Register `meetingscribe://` with the OS + add `onOpenURL`.**
*What/why:* Add `CFBundleURLSchemes` to Info.plist and an `onOpenURL` (or `kAEGetURL`) handler that pipes the parsed `WorkspaceLink` into D1-1's router. *User value:* MCP, Shortcuts, Mail follow-ups, Reminders, and Spotlight can deep-link straight to the right meeting/person/task — the in-app link model finally reaches outside the app. *Effort:* S. *Impact:* High. *Depends on:* WorkspaceLink (exists); pairs with D1-1.

**D1-3 — App-wide back/forward + history.**
*What/why:* Once the shell is a NavigationSplitView with a router, add ⌘[ / ⌘] (and the trackpad swipe) bound to a navigation history stack that spans tabs — "you were on Person → jumped to their meeting → back returns to the person." Today's local NavigationStack and Meetings' selection don't compose into this today. *User value:* the single biggest "I'm lost" fix; matches every native macOS app. *Effort:* M. *Impact:* High. *Depends on:* D1-1.

**D1-4 — Live, app-wide breadcrumb / context bar.**
*What/why:* A thin bar atop the content pane showing `Section › Entity › Tab` (e.g. `People › Horst › Meetings`), each segment tappable. None exists; the only "where am I" cue is the rail highlight. *User value:* orientation in deep states (a meeting's Transcript tab reached from a person's backlink gives zero breadcrumbs today). *Effort:* M. *Impact:* Med. *Depends on:* D1-1.

**D1-5 — Make person↔meeting↔task links bidirectional and clickable everywhere.**
*What/why:* Turn PersonDetail's "In your recordings" rows into buttons that route via D1-1 (`PersonDetailView.swift:526-548` is currently dead static rows); make attendee chips left-clickable to open the existing person (use the already-computed `existingPerson`) and show a subtle "known contact" dot; surface a meeting's action items as links to Tasks and vice-versa. *User value:* the relationship graph becomes actually navigable, not just stored. *Effort:* M. *Impact:* High. *Depends on:* D1-1.

**D1-6 — Live nav-rail badges.**
*What/why:* Add count/status badges to rail items: Meetings ("2 finalizing" from `transcribingMeetingIDs`), Tasks (overdue+due-today), Today (unsent follow-ups). The data already feeds `NeedsAttentionWidget`; promote it to the rail. *User value:* discover work without opening every tab — the rail becomes a dashboard. *Effort:* S. *Impact:* Med. *Depends on:* none.

**D1-7 — Actionable empty states wired to entry points.**
*What/why:* Replace descriptive empty states (`MeetingsView.swift:179`, People empty, detail placeholders) with primary CTAs bound to real actions (Meetings-empty → Record / Import / Connect calendar; "Select a meeting" placeholder → "Record your first meeting"). *User value:* new users get a path forward instead of a dead end; removes a documented first-run failure mode. *Effort:* S. *Impact:* Med. *Depends on:* none.

**D1-8 — Recent / Pinned section at the top of the rail (cross-type).**
*What/why:* A small "RECENT" group above WORKSPACE listing the last 3–5 entities the user opened *of any type* (meeting, person, task), plus user-pinnable items. The router already knows what was opened. *User value:* the fastest path back to the 2–3 things you're actively working — far faster than re-searching or re-filtering. *Effort:* M. *Impact:* Med. *Depends on:* D1-1 (needs the router's open-history).

**D1-9 — Persist per-tab navigation/selection state across tab switches.**
*What/why:* Today's `selectedMeeting` and People/Notes `selection` are plain `@State` that survive only because the ZStack keeps tabs alive; once the shell becomes a NavigationSplitView (NAV-4) this breaks. Lift selection/path into the router (or `@SceneStorage`) so returning to a tab restores exactly where you were. *User value:* tab switches stop feeling like a reset. *Effort:* S–M. *Impact:* Med. *Depends on:* NAV-4 / D1-1.

**D1-10 — Search results carry a navigation path (no teleport-and-trap).**
*What/why:* After D1-1, ⌘K results route into the canonical in-tab destination *and* leave the list/selection intact so the user can keep browsing; add a lightweight "recent searches" row and ESC-returns-to-results. Also retire the People-search code fork (`GlobalSearchView.swift:190-201`) by fixing the underlying WorkspaceIndex so search is genuinely unified. *User value:* search becomes a navigation tool you can iterate in, not a one-shot jump. *Effort:* M. *Impact:* Med. *Depends on:* D1-1.

**D1-11 — Disambiguate the three "record" entry points in the IA.**
*What/why:* Voice Note vs Ad-hoc Meeting vs Join-&-Record are scattered across the toolbar (`PersistentToolbarButtons`), Today quick actions, and the menu bar with no shared grouping or labels explaining the difference. Consolidate into one labeled "New" affordance (split-button or menu) with a one-line description per option, surfaced consistently in rail + Today. *User value:* removes the documented "three entry points, no explanation" confusion. *Effort:* S. *Impact:* Med. *Depends on:* none.

**D1-12 — Tab as a typed enum with declared default detail + restoration, killing the orphan-sheet pattern category.**
*What/why:* Formalize that every section declares `(listView, detailView, emptyDetail)` and is driven by the router — so no surface can grow a bespoke modal (the meeting sheet) again. A structural guardrail, not a one-off fix. *User value:* keeps the "one canonical surface" property from eroding as features are added. *Effort:* M. *Impact:* Med (durability). *Depends on:* D1-1, NAV-4.

## Top 3 picks

1. **D1-1 — One canonical entity router with a real per-tab `NavigationPath`.** Collapses the four meeting chromes into one, removes the timing hack, and is the foundation everything else (back/forward, breadcrumb, deep-links, recents) builds on. This is the single highest-leverage IA change in the app.
2. **D1-2 — Register `meetingscribe://` with the OS + `onOpenURL`.** Tiny effort, outsized payoff: it turns the existing link model into a real deep-link surface for MCP, Shortcuts, Mail, and Spotlight. The plumbing already exists; only the OS front door is missing.
3. **D1-5 — Bidirectional, clickable person↔meeting↔task links everywhere.** The relationship graph is the product's moat, but its UI links are currently dead static rows and hidden context menus. Making the graph navigable is what makes the "second brain" feel like one.
