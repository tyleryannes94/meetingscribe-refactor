# Group 2 — PM: Workflows & Integrations

> Lens: how MeetingScribe fits a knowledge worker's tool stack — where data should flow in/out, which integrations have leverage, and where the app is an island.

## Full-app audit (through my lens)

**The integration map today (verified in source):**

| Surface | Direction | Capability | File |
|---|---|---|---|
| Calendar (EventKit) | **In only** | Read meetings/attendees; conference-URL extraction. **No write-back** — cannot create/update events. | `Calendar/CalendarService.swift:76,159,193` (only `requestAccess`/`convert`/`extractConferenceURL`; no `EKEvent` save) |
| Notion (in-app) | **Both** | Push action items to a DB; pull DB items into Tasks. | `ActionItems/NotionActionItemService.swift:44` (`push`), `ActionItems/TaskSyncService.swift:fetchNotion` |
| Notion (MCP) | Both | 6-tool MCP server, signed+bundled. | `Sources/NotionMCP/main.swift` |
| Linear | **In only** | GraphQL pull of issues (paged, ~300 cap). **No push** — can't create a Linear issue from an action item. | `ActionItems/TaskSyncService.swift:37` (`fetchLinear`), endpoint `api.linear.app/graphql:57` |
| Google Drive | **Out only** | Export markdown via OAuth PKCE, `drive.file` scope. | `Export/GoogleDriveService.swift:28,130` |
| Google Contacts | **In only** | Read-only multi-account People-API import. | `People/GmailContactsService.swift:29-31` (`contacts.readonly`) |
| MCP server | **Both** | 17 tools = 12 read + 5 write (`create_action_item`, `update_action_item`, `add_person`, `add_memory`, `create_meeting_note`). | `Sources/MeetingScribeMCP/main.swift:1397-1413` |
| Follow-up | **Out (manual)** | Email via `mailto:` with prefilled recipients; "Slack" is a **draft style only — copy/share, no actual Slack send**. | `Followup/FollowUpView.swift:137` (`openInMail`), `Followup/FollowUpGeneratorService.swift:41` (Slack = prompt variant) |
| iCloud inbox | **In** | `NSMetadataQuery` watcher + 4-Shortcut JSON contract (quick-note/action-item/add-person/voice-note). | `Sync/iCloudInboxWatcher.swift:31,97-108` |
| Meeting detection | **In (signal)** | Polls running-app bundle IDs (`us.zoom.xos`, Meet window titles). | `Detection/AppDetector.swift:93-118` |

**Where the app is an island (the core finding):**
1. **Calendar is read-only.** The app *consumes* the calendar but can never *write* to it — no "schedule next meeting from a follow-up," no blocking focus time, no adding a recording link to the event. The plan's follow-up section even names "schedule next meeting via EventKit write" but it isn't built. This is the single biggest asymmetry: every other meeting tool (Granola, Fathom) writes back.
2. **Linear is pull-only.** A meeting generates action items locally, but they can't become Linear issues. Notion gets a `push`; Linear doesn't. Asymmetric and surprising.
3. **"Slack" is a lie of omission.** The follow-up generator offers a Slack channel (`FollowUpSuggestion.Channel.slack`) that only produces text to copy. There is no Slack delivery, no Slack capture, no Slack OAuth anywhere in the tree (grep confirms zero `webhook`/`slack` send code). For a knowledge worker, Slack is where 70% of follow-ups actually land.
4. **No outbound automation primitive.** There is no webhook, no local HTTP/API, no "on meeting finalized → do X" rule engine. Every export is a manual button. The MCP server is the *only* programmatic surface, and it requires Claude Desktop as the driver.
5. **No CRM bridge.** The People graph is rich (memories, encounters, message history) but there is zero connection to HubSpot/Salesforce/Attio — the systems where a salesperson or founder's relationship data is supposed to live. The graph is a beautiful island.

**The unique angle:** the **MCP server + local Ollama is a genuinely differentiated workflow** that Granola/Fathom don't have. Claude can already read the whole vault and (post-`6cdec9c`) write action items, people, memories, and notes (`main.swift:1409-1413`). This makes MeetingScribe an *agent-addressable knowledge base*, not just a notetaker. The strategy should be to lean into this rather than chase a long tail of bespoke SaaS connectors — most integrations can be expressed as "MCP tool + automation rule" instead of N hand-written OAuth clients.

**Capture is iPhone-only on the inbound side.** The `_inbox/` contract (`iCloudInboxWatcher.swift:97`) is elegant but the only documented producers are 4 iPhone Shortcuts. There's no email-to-capture, no browser capture, no desktop-launcher capture — so quick capture requires reaching for your phone even while sitting at the Mac.

## Existing-plan items I rank highest (through my lens)

1. **Write-capable MCP** (V3 §4, shipped `6cdec9c`). This is the keystone of the whole integration strategy — it turns the vault into an agent-writable store and lets future integrations be thin (let Claude do the routing). Highest leverage item already done; everything below builds on it.
2. **Send the follow-up, don't just copy it** (V3 §4; `mailto` shipped, EventKit "schedule next meeting" **not**). Endorse finishing the *write* half — the email path exists (`FollowUpView.swift:137`) but the calendar write-back named in the same plan bullet is missing.
3. **Four iPhone Shortcuts** (REMAINING_WORK §3). The inbox plumbing is built and idle; the Shortcuts are the cheapest way to make inbound capture real. Endorse, but see P4-6 — the same contract should accept more producers than iPhone.
4. **NotionMCP / in-app Notion dual client** (AUDIT §5). Worth keeping in sync; it's the one place the app already does bidirectional task sync and is the template for Linear write-back (P4-2).

## NET-NEW recommendations

### P4-1 — Calendar write-back ("close the loop with the calendar") · M · **High** · no deps
EventKit is read-only today (`CalendarService.swift` has no save path). Add: (a) "Schedule next meeting" from the follow-up view → creates an `EKEvent` with attendees prefilled from the meeting and a note linking the recording; (b) on recording finalize, optionally write the summary URL / "Notes ready" into the originating calendar event's notes field; (c) "Block focus time for action items." This is the highest-asymmetry fix — the app already reads the calendar perfectly and just needs the inverse.

### P4-2 — Linear issue push (symmetry with Notion) · S · **High** · depends on existing Linear key storage
`TaskSyncService.fetchLinear` pulls but there's no `createLinearIssue`. Add a GraphQL `issueCreate` mutation mirroring `NotionActionItemService.push`, so "send to Linear" sits next to "send to Notion" on an action item. Low effort (auth + endpoint already proven), removes a glaring asymmetry, and engineers will use it daily.

### P4-3 — Real Slack delivery + capture · M · **High** · no deps (Slack app + bot token)
Replace the fake "Slack draft" with an actual integration: (a) post the follow-up to a channel/DM via `chat.postMessage`; (b) a `/scribe` slash command or message-action to capture a quick note / action item into the `_inbox` contract. Slack is where follow-ups actually live for most teams; today the app pretends to support it (`FollowUpSuggestion.Channel.slack`) but only copies text. Reuses the same generator output.

### P4-4 — Local automation rules engine ("when X, then Y") · M · **High** · depends on P4-1/P4-2/P4-3 as actions
Add a small rules layer: triggers (`meeting finalized`, `tagged #1:1`, `action item created`, `follow-up unsent > 24h`) → actions (export to Drive, push to Notion/Linear, post to Slack, write calendar event, run MCP tool). Express it as declarative rules over the existing notification posts (`vaultChanged`, the `.recording` states). This converts every one-off export button into composable workflow and is the natural home for per-tag behavior (e.g. "all-hands → export PDF to Drive; 1:1 → stay-in-touch nudge").

### P4-5 — Webhook / outbound HTTP sink + inbound webhook ingest · S–M · **Med** · pairs with P4-4
Give power users a generic escape hatch: (a) fire a configurable webhook (JSON of the meeting envelope) on finalize, so Zapier/Make/n8n/IFTTT can fan out to anything the app will never natively support; (b) accept an inbound webhook (or watched `_inbox` JSON) to create notes/tasks from external systems. One generic primitive substitutes for a dozen bespoke connectors and respects the local-first ethos (user points it at their own automation).

### P4-6 — Generalize `_inbox` capture beyond iPhone (email + desktop + clipboard) · S · **Med** · depends on iCloudInboxWatcher (built)
The `InboxEnvelope` contract (`iCloudInboxWatcher.swift:165`) already routes by `type`; the only producers are iPhone Shortcuts. Add Mac-side producers writing the same envelope: (a) a global "quick capture" launcher window (separate from F5 dictation) that drops a `quick-note`/`action-item`; (b) an "email to capture" — forward a message to a watched Gmail label and ingest via the existing Gmail OAuth; (c) "capture from clipboard/selection" service-menu item. Reuses 100% of the routing already built.

### P4-7 — Raycast / Alfred extension (frictionless desktop capture & search) · S · **Med** · depends on a local API or `_inbox` writer
Ship a Raycast extension (and Alfred workflow) that talks to either the `_inbox` contract or a tiny localhost endpoint: "New action item," "Quick note," "Search my meetings," "Open last meeting's follow-up." For a Mac power user this is *the* capture surface and it's cheap because the data layer (FTS5 `searchAll`, inbox) already exists. Turns MeetingScribe into something you hit from anywhere with two keystrokes.

### P4-8 — CRM bridge for the People graph (HubSpot/Attio first) · L · **Med** · depends on multi-value contacts (PPL-2)
The relationship graph is the moat but it's sealed off. Add a one-way enrichment sync: after a meeting, push attendee notes / "last met" / meeting summary as a HubSpot (or Attio — friendlier API) contact-activity timeline entry, and optionally pull company/title back to enrich People records. Sales/founder users keep their CRM as source-of-truth while MeetingScribe feeds it the meeting context it never had. Start with one CRM; the `ExternalTask`-style normalization pattern (`TaskSyncService.swift:6`) is the template.

### P4-9 — Public local HTTP API + OpenAPI (the non-Claude programmatic surface) · M · **Med** · no deps
The MCP server only helps people driving Claude Desktop. Expose the same read/write operations over a localhost REST API (token-gated, loopback-only) so Shortcuts, Raycast, scripts, and other agents can integrate without MCP. This is the substrate P4-5/P4-6/P4-7 ride on and makes the app scriptable by anyone, not just Claude users.

### P4-10 — Calendar-driven auto-join + auto-export per meeting type · S · **Med** · depends on P4-1 + detection (built)
Combine the existing Zoom/Meet detection (`AppDetector.swift:93`) with calendar metadata and tags: auto-start recording when a *calendar* meeting with a conference URL begins (not just any sustained mic use), and auto-route its output by tag (1:1 → People timeline; all-hands → Drive PDF). Ties three already-built systems (detection, calendar read, export) into a hands-free workflow.

### P4-11 — Browser extension for web-meeting & web-content capture · L · **Low–Med** · depends on P4-9
A Chrome/Arc extension that (a) detects Google Meet / Zoom-web / Teams-web tabs and one-clicks "record this," and (b) clips a web page / highlighted text into the vault as a note attached to a person or meeting. Covers the web-meeting gap (the app's detection is native-app biased) and adds research-capture. Larger lift; lower priority than native-Mac capture surfaces.

### P4-12 — Obsidian/markdown two-way & Readwise-style daily digest export · S · **Low** · no deps
The vault is already Obsidian-style markdown, but export is push-only and manual. Add (a) honest "your vault *is* an Obsidian vault — point Obsidian here" guidance + backlink generation between people/meeting notes, and (b) a daily/weekly digest pushed to Drive/email (meetings recorded, tasks done, follow-ups pending) reusing the planned end-of-day recap. Cheap retention + interoperability with the PKM crowd that this app's local-first design already attracts.

## Top 3 picks

1. **P4-1 — Calendar write-back.** The app reads the calendar flawlessly and writes nothing back; closing that loop ("schedule next meeting," "notes-ready on the event") is the highest-asymmetry, highest-recognition fix, and the plan already gestures at it but left it unbuilt.
2. **P4-4 — Local automation rules engine.** Converts every manual export button into composable "when X then Y" workflow and is the right architectural home for per-tag behavior — it multiplies the value of P4-1/2/3/5 rather than adding another one-off.
3. **P4-3 — Real Slack delivery + capture.** The app *pretends* to support Slack today (a draft style that only copies); making it real meets follow-ups where they actually land and reuses the generator output already built.

**Single highest-priority recommendation overall:** P4-1 (Calendar write-back) — it's the clearest "the app is an island" gap, it's already half-implied by the shipped follow-up flow, and EventKit-write is the table-stakes capability every competing meeting tool has that MeetingScribe currently lacks.
