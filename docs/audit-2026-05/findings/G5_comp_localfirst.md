# G5 — Competitive Analysis: Local-First / Open PKM ecosystems

> Lens: How well does MeetingScribe play with the open PKM world it borrows from (Obsidian, Logseq, Anytype)? Is the vault *actually* Obsidian-compatible, or is it markdown-shaped lock-in? Could MeetingScribe be an Obsidian **companion** rather than a silo?

The headline: MeetingScribe writes markdown, but the markdown it writes is **not** the markdown it claims. The good Obsidian-flavored builder (`ObsidianExporter.markdown(for:)`) — wikilinks, attendee frontmatter, inline tags — is only reachable through an *optional, manual* export. The file that actually lands in the vault on every meeting (`writeMarkdownFile(for:to:)`) is a stripped-down sibling with **no people, no wikilinks, and tags scraped from a folder name**. So the on-disk vault an Obsidian user would point at is materially worse than the export the code advertises. That gap is the spine of this report.

## Full-app audit (through my lens)

### Two markdown writers, and the wrong one is canonical

`ObsidianExporter` has two code paths:

- **`markdown(for:summary:notes:transcript:tags:)`** (`ObsidianExporter.swift:95-144`) — the real deal. Emits `attendees:` list frontmatter, a `tags: [meeting, …]` array, a `## People` section of `- [[Name]]` wikilinks, inline `#tags`, and sanitizes tags for Obsidian (`:180`). This is genuinely Obsidian-native. But it is only called by the **manual** export-to-external-vault flow (`export(_:filename:settings:)`, `:151`), which falls back to an `NSSavePanel`.
- **`writeMarkdownFile(for:to:)`** (`ObsidianExporter.swift:20-88`) — the one that auto-runs after **every** finalize and transcribe (`MeetingPipelineController.swift:199`, `:303`, `:319`, and the ScribeCore twin at `127/209/218`). It writes `{slug}.md` *inside the meeting folder*. It has **no People section, no `[[wikilinks]]`, no `attendees:` / `people:` frontmatter**, and derives `tags:` from `meetingFolderURL.deletingLastPathComponent().lastPathComponent` (`:36-37`) — i.e. the parent folder name, which after the v2 date-partitioned migration is `2026-05`, not a tag at all. So the canonical vault file ships **month numbers in the tags field**.

Net: the vault that an Obsidian user actually opens has flat, link-less notes. The relationship graph — the thing MASTER_PLAN_V2 calls "the product" (V2 §"Protect the Moat") — is invisible to Obsidian's own graph view, Dataview, and the new Bases engine.

### Frontmatter is not Obsidian-"Properties"-clean

Obsidian's structured layer (Bases, 2026) reads **only YAML frontmatter** — it does not parse note body or Dataview-style inline fields ([Architect's Guide to Obsidian Bases](https://chughkabir.com/guide-obsidian-bases/)). That makes frontmatter the single most valuable real estate in the file. MeetingScribe's canonical writer emits only `id, title, date, duration, tags` (`:46-51`) and bungles `tags`. The richer builder emits `attendees:` but as a YAML list of bare strings (`:116-119`), not `"[[Name]]"` link values — so even there, Bases sees text, not clickable Link objects. The ecosystem's own answer to exactly this (typed wikilinks synced into frontmatter) already exists as the [Wikilink Types plugin](https://github.com/penfieldlabs/obsidian-wikilink-types); MeetingScribe is on the wrong side of that convention.

### No per-person notes → dangling links by construction

Even the good export writes `- [[Alice Smith]]`, but MeetingScribe **never writes a `People/Alice Smith.md` note into the vault**. People live in SQLite (`PeopleStore`) and the app's own `WorkspaceIndex`/`backlinks(toMeetingID:)` (`WorkspaceIndex.swift:61`, `UnifiedMeetingDetail.swift:208`). So in Obsidian every attendee wikilink is an unresolved (dangling) link — clicking it creates an empty note. The relationship graph is real *inside the app* and *absent in the vault*. That's the silo.

### Tags split-brained across folder, frontmatter, and tags.json

Tags are stored in `TagStore`/`tags.json` and as a folder grouping, then re-derived from the folder name at markdown-write time. Three sources of truth, none authoritative in the file Obsidian reads. The briefing notes `meeting.json` + `tags.json` as the vault sidecars — those are MeetingScribe-private schemas, fine as derived data, but they mean the markdown isn't self-describing.

### No daily/periodic notes — the spine of every Obsidian workflow

Obsidian users live in **Daily Notes + Periodic Notes** (Calendar, Periodic Notes, Dataview, Tasks, Templater are *the* five plugins, [Obsibrain 2026](https://www.obsibrain.com/blog/top-obsidian-plugins-in-2026-the-essential-list-for-power-users)). MeetingScribe has a "Today" hub *inside the app* but writes nothing to a `Daily/2026-05-30.md` an Obsidian user would already have open. A meeting that happened "today" doesn't appear in today's daily note. This is the cheapest, highest-trust integration MeetingScribe is leaving on the table.

### Sync story is honest but undersold

V2/V3 correctly land on "iCloud Drive vault, SQLite in App Support, no real backup subsystem" (V3 ENG-E). That is exactly the no-lock-in posture Obsidian users trust — the whole reason they pick Syncthing/iCloud/Git over hosted Sync is *data ownership and plain-markdown portability* ([Synch, 2026](https://synch.run/blog/obsidian-sync-alternatives/)). MeetingScribe already inherits this for free by being a folder of files. But it under-delivers on portability (above) and over-claims nothing — the opportunity is to *lean into* "your notes are yours, open them in anything."

### Where competitors are going (and what it means)

- **Logseq is splitting into "Logseq OG" (markdown, file-based, forever) and "Logseq" (SQLite DB)** ([logseq.io](https://logseq.io/page/b2ad9ce1-9cb7-4436-8083-54cb4516d324/df4dc09d-0a12-4c87-904e-22a9bf4c350a), [db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)). The DB version is faster but the community backlash was about *losing the plain-file guarantee*. Lesson for MeetingScribe: keep markdown the **canonical** store (you already do — don't regress it into "SQLite is truth, markdown is export").
- **Anytype** is the only major PKM with default e2e P2P sync via [any-sync](https://github.com/anyproto/any-sync) (CRDT, zero-knowledge), but pays for it with a verbose JSON block format that needs a [third-party exporter](https://github.com/jfcostello/AnyBlock-To-Markdown) to get to markdown. That's the *opposite* trade-off from MeetingScribe — Anytype owns sync but loses portability. MeetingScribe's wedge is "portable by construction." Protect it.
- **Obsidian Bases** (2026) makes frontmatter the query substrate. If MeetingScribe writes clean Bases-ready frontmatter, a user gets a no-code "all meetings with [[Alice]] last quarter" database view *for free, in Obsidian*, with zero MeetingScribe UI work.

## Existing-plan items I rank highest

1. **V2 per-meeting `.md` on every save / "Obsidian Mobile compatibility" template** (V2 §"Per-meeting Markdown template"). Right instinct — but as audited, the *shipped* writer doesn't match the *templated* one (it drops `people:` and bungles `tags:`). Endorse, and treat my C3-1 as the correction that makes it true.
2. **V3 ENG-E — backup honesty / "stored locally; put your vault in iCloud Drive"** (V3 §3.6). This is the local-first trust message. Endorse strongly; it's also a marketing wedge, not just a bug fix.
3. **V3 ENG-B — vault migration writes back paths + date-partitioned layout** (V3 §3.6). A half-migrated vault is an *unstable* vault, and instability is what makes Obsidian users flee a tool. Endorse as a prerequisite to any portability promise.
4. **V3 "unified find-everything / FTS5 searchAll → GlobalSearchView"** (V3 §4). Good, but note it's the *app-internal* graph; my C3-2/C3-3 push the same graph *into the vault* so Obsidian/Dataview can consume it too. Endorse as complementary.
5. **V2 SQLite-stays-in-App-Support** (V2 §"Critical change"). Correct and important: never sync a `.db` in the vault. This is also what keeps the vault pure markdown+json, i.e. portable. Endorse.

## NET-NEW recommendations

### C3-1 — Make the canonical auto-written `.md` truly Obsidian-native (merge the two writers)
**What/why:** Delete the lossy `writeMarkdownFile` body; have the auto-write call the rich `markdown(for:)` builder so the file *on disk* gets `attendees:`, real `tags:` (from `TagStore`, not the folder name — fixes the `2026-05`-as-tag bug at `ObsidianExporter.swift:36`), inline `#tags`, and a `## People` wikilink section. One writer, one truth.
**User value:** The vault a user opens in Obsidian is finally the good one — graph view, search, and tag pane all work.
**Effort:** S–M · **Impact:** High · **Depends on:** none (independent of C3-2).

### C3-2 — Write real per-person notes into a `People/` folder so wikilinks resolve
**What/why:** On person create/update, emit `People/{Name}.md` with frontmatter (`role, company, email, aliases:`) mirroring `PeopleStore`. Meeting `[[Alice Smith]]` links now resolve instead of dangling, and Obsidian's backlinks panel shows every meeting with Alice — the relationship graph, *rendered by Obsidian itself*. Use `aliases:` frontmatter so name variants (already tracked in `PersonExtractor.aliases`) collapse to one note.
**User value:** The app's killer "People graph" moat becomes visible and navigable in the open ecosystem, not trapped in SQLite.
**Effort:** M · **Impact:** High · **Depends on:** C3-1 (link targets must exist).

### C3-3 — Daily-note append: drop each meeting into `Daily/YYYY-MM-DD.md`
**What/why:** Follow the Periodic Notes convention. On finalize, append a `- HH:MM [[meeting-slug]] — title` bullet under a `## Meetings` heading in that day's daily note (create if absent, never clobber user content — insert under a managed `<!-- meetingscribe:begin -->…<!-- :end -->` block). This is *the* integration Obsidian users expect and the stickiest one ([Obsibrain 2026](https://www.obsibrain.com/blog/top-obsidian-plugins-in-2026-the-essential-list-for-power-users)).
**User value:** Meetings show up where the user already journals; MeetingScribe slots into an existing daily-notes habit instead of demanding a new surface.
**Effort:** S–M · **Impact:** High · **Depends on:** C3-1.

### C3-4 — "Open vault in Obsidian" + Obsidian-vault detection
**What/why:** Detect an `.obsidian/` folder at the vault root; if present, surface a one-click "Open in Obsidian" (`obsidian://open?vault=…&file=…`) on every meeting and offer to write notes Obsidian-style. If absent, offer "Set up this folder as an Obsidian vault" (drop a minimal `.obsidian/app.json`). Deep-link the *current* meeting via `obsidian://`.
**User value:** Positions MeetingScribe as an explicit Obsidian **companion**, not a competitor — the single biggest trust signal to that audience.
**Effort:** S · **Impact:** Med–High · **Depends on:** C3-1.

### C3-5 — Bases-ready frontmatter + ship a starter `.base`
**What/why:** Since Bases queries frontmatter only, write rich, typed frontmatter (`type: meeting`, `attendees: ["[[A]]","[[B]]"]` as Link-typed list, `duration_min: 30` numeric, `has_recording: true`) and ship a `Meetings.base` template the user can drop in for an instant no-code meeting database/kanban in Obsidian.
**User value:** Users get a queryable meeting database in Obsidian with zero MeetingScribe UI work — leverages the ecosystem instead of rebuilding it.
**Effort:** M · **Impact:** Med · **Depends on:** C3-1, C3-2.

### C3-6 — A read-side extension/plugin hook: `vault/_plugins/` post-finalize scripts
**What/why:** MeetingScribe will never match Obsidian's 2700+ plugins ([dsebastien 2026](https://www.dsebastien.net/the-must-have-obsidian-plugins-for-2026/)) — so don't try; *borrow* the model. After finalize, run any executable/JS in `vault/_plugins/on-meeting-finalized/` with the meeting JSON on stdin (sandboxed, opt-in, user-authored). This is the "extension system" the plans miss, done the local-first way: files, not an API.
**User value:** Power users wire MeetingScribe to anything (custom summaries, webhook to Slack, write to their own Dataview index) without forking the app.
**Effort:** M–L · **Impact:** Med · **Depends on:** stable finalize pipeline.

### C3-7 — Round-trip import: ingest hand-edited markdown back into the model
**What/why:** Today edits flow app→file. If a user fixes a typo in `summary.md` or adds a `[[Person]]` in Obsidian, MeetingScribe should read it back (it already watches `_inbox/` via `iCloudInboxWatcher` — extend the watcher to meeting folders, reconcile frontmatter→`meeting.json`/`tags.json`). True portability is *bidirectional*; one-way export is still a soft silo.
**User value:** Users can live in Obsidian *and* MeetingScribe without one stomping the other — the core local-first promise.
**Effort:** M · **Impact:** Med–High · **Depends on:** C3-1 (canonical frontmatter to parse).

### C3-8 — `EXPORT.md` / vault-portability manifest + "leave anytime" guarantee
**What/why:** Write a human-readable `README.md`/`SCHEMA.md` at the vault root documenting the folder layout, frontmatter fields, and the fact that everything is plain markdown+json (no DB needed to read it). State plainly: "delete this app and your notes still open in any editor." Mirrors the Logseq-OG trust posture the community demanded.
**User value:** Lowers adoption risk to near-zero for the lock-in-averse Obsidian crowd; turns "what if I quit?" from a fear into a selling point.
**Effort:** S · **Impact:** Med · **Depends on:** none.

### C3-9 — Community templates: per-tag summary templates as shareable `.md` files
**What/why:** The existing-plan "per-tag summary templates" idea (V3 §4) should be **files in `vault/_templates/`**, not hardcoded prompts — so users can edit, version, and *share* them (the way Obsidian users swap daily-note templates on GitHub gists, [bennewton999 gist](https://gist.github.com/bennewton999/62b4a034445a24532591bc4c55a52cf5)). A `1on1.md` / `all-hands.md` / `decisions.md` template folder, picked by tag.
**User value:** Taps the open-PKM culture of sharing setups; templates become a community surface and a low-effort growth loop.
**Effort:** S–M · **Impact:** Med · **Depends on:** per-tag template plumbing.

### C3-10 — Don't let the future SQLite/CKSync work demote markdown to "export"
**What/why:** Explicit guardrail, learned from Logseq's split. As V3's FTS5/CKSync items land (V2 Phase 3), keep markdown+json the *canonical* store and SQLite/CloudKit strictly derived/rebuildable (V2 already says this for FTS5 — make it a documented invariant + a CI test that the vault fully round-trips with the `.db` deleted).
**User value:** Permanent protection of the portability moat; the app can never quietly become a database-first silo.
**Effort:** S (mostly a documented invariant + one test) · **Impact:** High (strategic) · **Depends on:** none.

## Top 3 picks

1. **C3-1 — Merge the two markdown writers so the canonical vault file is the Obsidian-native one.** Everything else in this report (resolving links, Bases, daily notes, round-trip) is built on the file actually being good. It's also a near-pure bug fix (the lossy writer ships `2026-05` as a tag), so it's the highest impact-to-effort item in the whole audit through this lens.
2. **C3-2 — Write per-person `People/*.md` notes so wikilinks resolve.** This is what makes the relationship-graph moat *visible in Obsidian* rather than trapped in SQLite — turning the product's differentiator into an ecosystem superpower instead of a silo.
3. **C3-3 — Daily-note append.** The single stickiest, lowest-cost way to slot MeetingScribe into the habit Obsidian users already have, positioning it as a companion, not a replacement.

**Single highest-priority recommendation overall: C3-1.** The vault is the API to the entire open-PKM world, and right now MeetingScribe is shipping a degraded version of its own format. Fix the canonical writer first; it unlocks C3-2 through C3-7 and corrects a live data-quality bug at the same time.
