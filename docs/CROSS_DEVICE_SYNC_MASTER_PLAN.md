# MeetingScribe — Cross-Device One-Way Sync: Master Plan

**Goal:** Make the personal **Mac mini the always-on "hub" / data vault (second
brain)**, and let the **work MacBook push a one-way backup** of everything done in
MeetingScribe (meetings, transcripts, notes, summaries, audio, people, tasks) into
that hub — **free**, running **at least daily and ideally every 1–few hours**,
without ever clobbering the hub's own data.

This document combines five independent engineering reports into one buildable
plan. Each report explored a different transport/strategy; this master plan picks a
recommended stack, explains the trade-offs, and gives Claude Code everything needed
to build it end to end. The five full source reports live alongside this file:

| # | Report | File |
|---|--------|------|
| 1 | Tailscale + rsync over SSH (launchd) | [`sync-plans/agent-1-tailscale-rsync.md`](sync-plans/agent-1-tailscale-rsync.md) |
| 2 | In-app Swift HTTP push (extends the web server) | [`sync-plans/agent-2-inapp-http-push.md`](sync-plans/agent-2-inapp-http-push.md) |
| 3 | Syncthing send-only / receive-only | [`sync-plans/agent-3-syncthing.md`](sync-plans/agent-3-syncthing.md) |
| 4 | Git-based vault relay | [`sync-plans/agent-4-git-relay.md`](sync-plans/agent-4-git-relay.md) |
| 5 | Hub-side merge / ingestion engine | [`sync-plans/agent-5-merge-ingestion-engine.md`](sync-plans/agent-5-merge-ingestion-engine.md) |

---

## 0. TL;DR — the recommended stack

Sync has **two layers**, and they are independent:

1. **Transport** — how bytes get from the work MacBook to the hub. Four free
   options were designed (rsync, Syncthing, in-app HTTP, Git). **All four land the
   work data in the same place: a quarantined `…/MeetingScribeVault/_remote/work-macbook/`
   namespace on the hub** so the hub's live vault is structurally untouchable.
2. **Ingestion/merge** — the hub-side engine that *optionally* fuses that
   quarantined data into the single second brain (dedup people, merge tasks/tags,
   rebuild indexes), additively and idempotently.

**Recommendation:**

- **Primary transport → Tailscale + rsync over SSH, scheduled by launchd**
  (Report 1). It's $0, OS-native, strictly one-way, needs **zero app changes** to
  deliver a complete browsable backup, and Tailscale is already a blessed
  dependency in this project (`docs/PHONE_ACCESS.md`). Start here.
- **If you want continuous (near-real-time) sync → Syncthing** (Report 3) as a
  drop-in alternative transport. Same quarantine contract.
- **If you want it all inside the app (one binary, one toggle, reuse the QR/token
  pairing) → in-app HTTP push** (Report 2). More code, best UX, no extra installs.
- **If you want full version history / audit trail → Git relay** (Report 4),
  audio shipped via a parallel rsync side-channel.
- **Then, when you want work data to actually appear in your Meetings/People/Tasks
  lists (not just sit in `_remote/`) → build the merge engine** (Report 5). This is
  transport-agnostic and works no matter which of the four you chose.

You can ship the backup **today** with Report 1 (no build), and add the merge
engine later as a proper Swift feature.

---

## 1. Requirements (recap)

| Requirement | How the plan satisfies it |
|---|---|
| **Free ($0)** | Tailscale free tier (≤100 devices/3 users), rsync/ssh/launchd ship with macOS, Syncthing/Git are OSS, in-app path reuses the existing server. No cloud bucket, no subscription. |
| **At least daily, ideally every 1–few hours** | launchd `StartInterval=7200` (2h) with an optional daily `StartCalendarInterval` floor; Syncthing is continuous; in-app timer default 2h; Git relay every 1–3h. |
| **One-way (work → hub)** | rsync push-only / Syncthing Send-Only→Receive-Only / hub Git only fetch+reset / push client only POSTs. Enforced structurally on both ends. |
| **Never clobber hub data** | Everything lands under `_remote/work-macbook/`, a sibling of (never a parent of) the live vault. No `--delete` against hub data; merges are additive-only; conflicts quarantined. |
| **Hub = main vault** | The Mac mini is authoritative; the merge engine treats work data as additive and never overwrites a personal record. |

---

## 2. Grounding facts about the codebase (verified)

All five agents verified these against the live repo; the plan depends on them.

- **The vault is plain, human-readable files** (Markdown + JSON), schema-versioned
  via `SchemaEnvelope<Payload>` = `{version, data}` (`Sources/VaultKit/SchemaEnvelope.swift`,
  mirrored in `MeetingScribeShared`). No database to corrupt — ideal for file sync.
- **Vault location** defaults to `~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault`
  (iCloud Drive) or `~/Documents/MeetingNotes`, and is **configurable via the
  UserDefaults key `storageDir`** (bundle id `com.tyleryannes.MeetingScribe`). See
  `Sources/VaultKit/VaultPaths.swift` and `Sources/ScribeCore/AppSettings.swift`.
  Scripts read it with `defaults read com.tyleryannes.MeetingScribe storageDir`.
- **On-disk layout:** per-meeting folders `meetings/yyyy/yyyy-MM/<slug>/`
  (`meeting.json` = `SchemaEnvelope<MeetingDTO>`, `transcript.md`, `notes.md`,
  `summary.md`, `audio/manifest.json` + `*.m4a`); people `people/<slug>/person.json`
  + `person.md`; `encounters/<id>.json`; aggregates `tags.json`, `action_items.json`
  (+ `projects.json`, `initiatives.json`, etc.). **Rebuildable caches (never sync
  these):** `.meeting-index.json`, `_people-cache.json`, `_recent.json`, and the
  SQLite `secondbrain.db` which lives in **Application Support, outside the vault**.
- **`_inbox/` + `iCloudInboxWatcher.swift`** (`Sources/MeetingScribe/Sync/`) is the
  established precedent for "watch a vault subfolder, route items, keep a
  `.processed_ids.json` ledger." The new ingestor mirrors it.
- **An embedded, token-gated HTTP server already exists** for phone access
  (`Sources/MeetingScribe/Web/` — `HTTPServer.swift` on `NWListener` port 8765 with
  a **16 MB request cap**, `WebAPI.swift` constant-time Bearer auth, `WebServerController.swift`
  token + QR + Tailscale/LAN endpoint discovery). Report 2 extends it.
- **The app intentionally has "no background sync service"** today
  (`docs/ARCHITECTURE.md`), so a third-party daemon (rsync/Syncthing/Git) is a clean
  decoupled fit, and the in-app option is a deliberate new subsystem.
- **`PeopleStore` already implements dedup/merge** we will reuse: match precedence
  `contactIdentifier → email → phone → exact name`, fuzzy thresholds
  (`autoLinkThreshold = 0.85`, `possibleMatchThreshold = 0.6`), union merges
  (`mergeFields`, `mergeImport`, `mergePeople`, `deduplicate`), `PersonSuggestion`,
  `dismissedSignatures`, and `ingestExtraction(_:meeting:)`.
- **`ActionItemStore.mergeExternal`** already dedupes by `(source, externalID)` and
  `reconcileExtracted` preserves user-edited fields — the model for task merging.
- **`MeetingStore`** keeps `.meeting-index.json` via `upsertInIndex`/`rebuildIndexAsync`
  and already suffixes colliding folders (`-2`, `-3`) in `moveMeeting`. Its
  `reservedFolders` set (currently `["models","QuickNotes","logs","diagnostics"]`)
  is the one-line hook to make the live app ignore `_remote/`.
- **The MCP server** (`Sources/MeetingScribeMCP/main.swift`) is the precedent for
  atomic, non-AppKit vault JSON writes.

> ⚠️ **Bug found while planning (worth fixing regardless):** `PeopleStore.mergeFields`
> currently does `k.memories += other.memories` (plain concat) for memories /
> attachedNotes / photoRelativePaths. That **duplicates** them on any re-merge or
> re-import. The merge engine (Report 5) includes a `unionByID` fix that also
> hardens the existing local "Merge duplicates" path.

---

## 3. The five approaches at a glance

| | **1. Tailscale + rsync** | **2. In-app HTTP push** | **3. Syncthing** | **4. Git relay** |
|---|---|---|---|---|
| Cost | $0 | $0 | $0 | $0 |
| App code changes | **None** (core) | **Significant** (new subsystem) | **None** | **None** (scripts) |
| Cadence | Every N h (launchd) | Every N h (timer) + launch | **Continuous** | Every 1–3 h (launchd) |
| One-way enforcement | Push-only, no `--delete` | Client only POSTs | Send-Only → Receive-Only | Hub only fetch+reset |
| Needs a daemon running | sshd on hub (built-in) | App open on both | Syncthing on both | No (cron-style) |
| Version history | No (rsync mirror) | No | Optional (Staggered) | **Yes (full git log)** |
| Large audio (.m4a) | Native, resumable | Chunked upload | Native | **Exclude → rsync side-channel** |
| Off-site copy option | No | No | No | **Yes (private GitHub mirror)** |
| Best for | **Simplest free backup** | **Best in-app UX** | **Near-real-time** | **Audit / rollback** |
| Setup difficulty | Low | Medium (build) | Low–Med | Medium |

**Shared contract (all four):** write into `…/MeetingScribeVault/_remote/work-macbook/`,
exclude derived caches, never touch the hub's live tree. This is what makes the
hub-side merge engine (Report 5) transport-agnostic.

---

## 4. Recommended build path (phased)

```
Phase 0  Prereqs: Tailscale on both Macs (same account), MagicDNS on.
Phase 1  Transport — pick ONE:
           1a. rsync + launchd        (recommended default, no build)   → §5
           1b. Syncthing              (continuous)                       → §6
           1c. in-app HTTP push       (one binary, best UX, build)       → §7
           1d. Git relay              (history/audit)                    → §8
         All land work data in  <vault>/_remote/work-macbook/.
Phase 2  (optional) Hub-side merge engine — fuse _remote/ into the second brain.  → §9
Phase 3  Docs + verification + safety drills.                                     → §10–§12
```

You get a working, browsable backup at the end of Phase 1. Phase 2 is what turns
"files in a folder" into "it's actually in my second brain."

---

## 5. Transport 1a — Tailscale + rsync over SSH (RECOMMENDED DEFAULT)

> Full detail, every rsync flag explained, the hardened `rrsync` forced-command,
> and troubleshooting: **[`sync-plans/agent-1-tailscale-rsync.md`](sync-plans/agent-1-tailscale-rsync.md)**.

**Architecture:** the work MacBook runs a launchd LaunchAgent every 2h that
`rsync`s its vault into `_remote/work-macbook/` on the hub over SSH on the tailnet.
No `--delete`; temp-then-rename atomic writes; resumable audio; derived caches
excluded.

```
WORK (launchd every 2h)  ──rsync -az over SSH on tailnet──▶  HUB <vault>/_remote/work-macbook/
                                                              (hub's own data is a sibling, untouched)
```

### 5.1 Setup (both Macs)
1. **Tailscale:** `brew install --cask tailscale`; sign in with the **same** account
   on both; enable **MagicDNS** in the admin console. Record the hub's MagicDNS name
   (e.g. `mac-mini`) or `tailscale ip -4` (`100.x`) and the hub login user (`whoami`).
2. **Hub — Remote Login:** System Settings → General → Sharing → **Remote Login → On**
   (your user only). Verify from work: `ssh tyler@mac-mini 'echo ok'`.
3. **Work — dedicated SSH key:** `ssh-keygen -t ed25519 -f ~/.ssh/meetingscribe_sync -N "" -C "meetingscribe-sync"`.
4. **Authorize on hub:** `ssh-copy-id -i ~/.ssh/meetingscribe_sync.pub tyler@mac-mini`,
   then verify non-interactive: `ssh -i ~/.ssh/meetingscribe_sync -o BatchMode=yes tyler@mac-mini 'echo keyauth-ok'`.
5. **Pre-create quarantine on hub:**
   `ssh -i ~/.ssh/meetingscribe_sync tyler@mac-mini 'mkdir -p "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook"'`.

### 5.2 The sync script — `~/.local/bin/meetingscribe-sync.sh` (work Mac)
Key points (full script in Report 1): resolves the vault via `defaults read … storageDir`
with the iCloud fallback; an `flock` guard prevents overlap; an exclude file drops
derived/local artifacts; the rsync command is **push-only with NO `--delete`**;
retry/backoff loop; writes a `.last_sync` heartbeat.

```bash
RSYNC_OPTS=(
  -a -z -h                                  # archive, compress, human-readable
  --partial --partial-dir=.rsync-partial    # resume interrupted big-audio transfers
  -T "/tmp/.meetingscribe-rsync-tmp"         # write to temp, atomic-rename into place
  --no-perms --no-owner --no-group           # don't fight cross-machine uid/gid/ACLs
  --omit-dir-times                           # avoid iCloud dir-time churn
  --exclude-from="$EXCLUDE_FILE"             # derived caches / logs / models
  --timeout=600 --contimeout=30              # never wedge launchd on a dead link
  --info=stats2
)
# NO --delete  → the sync can only ADD/UPDATE in the namespace, never remove hub data.
rsync "${RSYNC_OPTS[@]}" -e "ssh -i ~/.ssh/meetingscribe_sync -o BatchMode=yes" \
      "$VAULT_LOCAL/" "tyler@mac-mini:$VAULT_REMOTE_BASE/"
```

**Exclude list** (`$EXCLUDE_FILE`): `.meeting-index.json`, `_people-cache.json`,
`_recent.json`, `_inbox/processed/`, `_inbox/.processed_ids.json`, `*.db*`,
`secondbrain.db`, `logs/`, `diagnostics/`, `models/`, `.DS_Store`, and `_remote/`
itself. Audio `*.m4a` **is** included (it's the meeting source of truth).

### 5.3 The LaunchAgent — `~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist`
`StartInterval = 7200` (2h, coalesces on wake if the laptop was asleep), `RunAtLoad`
true (covers login), optional `StartCalendarInterval` at 09:00 as a hard daily floor,
logs to `~/Library/Logs/MeetingScribe/sync.*.log`, explicit `PATH` env (launchd
plists don't expand `~`/`$HOME` — use absolute paths and your real `USERNAME`). Load:
```bash
mkdir -p ~/Library/Logs/MeetingScribe
launchctl load ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist
launchctl start com.tyleryannes.meetingscribe.sync
```

### 5.4 Safety (four structural layers)
1. **Destination is a non-authoritative namespace** — rsync can't write above its
   destination root, so hub data outside `_remote/work-macbook/` is unreachable.
2. **No `--delete`** — sync only adds/updates.
3. **Atomic temp-then-rename** — readers never see a torn `meeting.json`/`.m4a`;
   rsync rc=24 (file changed mid-sync) is treated as benign.
4. **Derived caches excluded** — the hub never ingests a foreign index; it rebuilds
   its own.

### 5.5 Hardening
Pin a forced command in the hub's `authorized_keys` so even a stolen key can only
rsync into the quarantine: `command="rrsync -wo ~/…/MeetingScribeVault/_remote/work-macbook",restrict ssh-ed25519 AAAA…`.
Optionally scope a tailnet ACL to `tcp:22` hub-only.

---

## 6. Transport 1b — Syncthing (continuous alternative)

> Full detail (launchd LaunchDaemon, `config.xml` stanzas, `.stignore`, versioning):
> **[`sync-plans/agent-3-syncthing.md`](sync-plans/agent-3-syncthing.md)**.

Free, open-source, **continuous** P2P sync. The work MacBook hosts a **Send-Only**
folder pointed at its vault; the hub accepts it as a **Receive-Only** folder pointed
at `_remote/work-macbook/` (NOT the vault root). `SendOnly → ReceiveOnly` is the
canonical one-way mirror.

- **Install (both):** `brew install syncthing`. Work: `brew services start syncthing`
  (login-scoped). Hub: a **LaunchDaemon** so it receives even at the login window,
  running as the user (so it reads the right `~`). GUI at `127.0.0.1:8384`.
- **Pair** by Device ID, then configure folder types. **Critical guardrail:** never
  share the hub's vault root — only `_remote/work-macbook/`, or a Receive-Only
  folder would treat hub-only files as "extra to delete."
- **`.stignore`** (work side): exclude `.meeting-index.json`, `_people-cache.json`,
  `_recent.json`, `_inbox/processed`, `*.tmp/*.partial`, `*.sync-conflict-*`,
  `.DS_Store`. Keep meetings/people/encounters/aggregates/audio.
- **Non-clobber:** Send-Only/Receive-Only direction + the quarantine namespace +
  **Staggered File Versioning** on the hub (history under `.stversions/`, so even an
  in-quarantine overwrite moves the old copy aside first).
- **Anywhere access:** run it over Tailscale (already in this project's toolkit) or
  Syncthing's encrypted relays. Transfers are TLS; peers authenticate by Device ID;
  keep "introducer" off.

Cons: folder-level (not record-level — the merge engine in §9 handles that), needs
the daemon running, continuous rather than a strict N-hour interval.

---

## 7. Transport 1c — In-app HTTP push (best UX, requires a build)

> Full detail (endpoint schemas, the `VaultPushSyncService`/`SyncHTTPClient`/`SyncIngest`
> Swift, chunked upload, Settings UI, curl verification):
> **[`sync-plans/agent-2-inapp-http-push.md`](sync-plans/agent-2-inapp-http-push.md)**.

Both Macs run the **same binary**; a new `syncRole` setting (`.off`/`.hub`/`.push`)
decides behavior. The hub extends its **existing** token-gated web server with a
`/sync/*` ingest API; the work Mac runs a new push service that diffs its vault by
sha256 and uploads only changes over the tailnet. Pairing reuses the existing
**QR/token** flow — same as pairing a phone.

### 7.1 Hub ingest API (extends `Sources/MeetingScribe/Web/WebAPI.swift`)
Role-gated (`.hub`) + existing Bearer auth. Routes:
- `GET /sync/state` → the hub's per-device ledger (`{path → {sha256,size,mtime}}`)
  so the client diffs locally and skips already-present files.
- `POST /sync/manifest` → client declares its file set with hashes; hub replies with
  exactly which paths it still `need`s (the dedup gate).
- `POST /sync/upload` → streams one file/chunk (metadata in `X-MS-*` headers, raw
  bytes in the body). **4 MB chunks stay under the server's 16 MB request cap** —
  no server change needed. Per-chunk + whole-file sha256 verified.
- `POST /sync/commit` → validates staging, **atomically** `replaceItemAt`s each file
  into `_remote/<deviceID>/<path>`, updates the ledger.

On-disk: `_remote/<deviceID>/…` plus `.sync-ledger.json`, `.sessions/`, `.staging/`.
**Path-escape guard** rejects `..`/absolute/`:` so a buggy client can't escape
quarantine. **Deletes are not propagated.**

### 7.2 Work client (`Sources/MeetingScribe/Sync/VaultPushSyncService.swift`)
`@MainActor` for published status; **all hashing/upload on `Task.detached`**. Builds
a manifest with **streamed** sha256 (a 500 MB m4a never loads fully into RAM), diffs
against `GET /sync/state`, uploads only `need`ed files via a `SyncHTTPClient` actor
with exponential backoff, persists a cursor. Triggers: **on launch + repeating Timer
(default 2h) + manual "Sync now"**.

### 7.3 The "app must be open" gap
The timer only ticks while the app runs (it's a menu-bar app, usually fine). Belt-
and-suspenders: a **KeepAlive LaunchAgent** on the work Mac (`open -g -a MeetingScribe`
hourly), modeled on the existing `registerScribeCoreLoginItem()`.

### 7.4 Files
**Modify:** `Models/Settings.swift` (+`SyncRole`, keys; token in Keychain),
`Web/WebAPI.swift` (route), `MeetingScribeApp.swift` (launch wiring + keep-alive),
`UI/SettingsView.swift` (`SyncSection`, mirror `PhoneAccessSection`),
`KeychainStore.swift` (token account). **Create:** `Sync/SyncIngest.swift`,
`Sync/SyncHTTPClient.swift`, `Sync/VaultPushSyncService.swift`. `CryptoKit` is in the
SDK — no `Package.swift` change. Verify with `swift build -c release` + the curl
script in Report 2 §8.

### 7.5 Security
Reuses the constant-time token; **token rotation** invalidates the client (401 →
re-pair). Over Tailscale, plain HTTP is acceptable (WireGuard E2E), but **gate
`/sync/*` to Tailscale source addresses (`100.64/10`)** so the whole-vault token
never travels an untrusted office LAN. Replay is harmless (content-addressed,
idempotent, quarantine-only); add `X-MS-Timestamp`+HMAC later if desired.

---

## 8. Transport 1d — Git relay (history / audit)

> Full detail (both transports, scripts, plists, `.gitignore`/`.gitattributes`,
> secret-scanning hook): **[`sync-plans/agent-4-git-relay.md`](sync-plans/agent-4-git-relay.md)**.

The vault is plain text → Git is a natural fit: full history, diffs, rollback,
free private hosting, and one-way is trivial (**hub only ever `fetch` + `reset`,
never pushes back**). The work Mac auto-commits + pushes every 1–3h; the hub pulls
into a **separate working copy** at `_remote/work-macbook/`.

- **Audio decision:** **exclude `*.m4a` from Git** (binary bloat is permanent) and
  ship it via a **parallel rsync-over-Tailscale** step. Repo stays pure text.
- **Two free transports:** (a) **private GitHub repo** (deploy keys: write on work,
  **read-only on hub** = a second one-way guarantee; off-site backup; avoid Git LFS
  for ongoing audio — 1 GB free tier); (b) **self-hosted bare repo on the hub over
  Tailscale SSH** (`~/MeetingScribeRelay/vault.git`) — truly unlimited/free, no third
  party. **Recommended: (b) primary**, with (a) as an optional off-site text mirror.
- **Work job:** `git add -A` → commit (skip if nothing) → push with retry/backoff →
  rsync audio. launchd `StartInterval`.
- **Hub job:** clone-once into the quarantine, then `git fetch` + `git reset --hard
  origin/main` + `git clean` (one-way; the working copy's push URL is set to
  `DISABLED_NO_PUSH`). launchd `StartInterval`.
- **Secrets:** a vault `.gitignore` keeps keychain/API keys/logs/derived caches out;
  a pre-commit hook scans for `sk-…`/AWS keys/PEM blocks. App secrets live in
  Keychain, not the vault, so the surface is small — defend in depth anyway.

Three independent one-way guarantees: separate directory, `DISABLED_NO_PUSH`,
read-only hub deploy key.

---

## 9. Phase 2 — Hub-side merge / ingestion engine (`RemoteVaultIngestor`)

> Full design (every merge rule, the Swift, the ledger, the tests, edge cases):
> **[`sync-plans/agent-5-merge-ingestion-engine.md`](sync-plans/agent-5-merge-ingestion-engine.md)**.

This is **transport-agnostic** — it runs no matter which of §5–§8 you chose,
because they all deposit work data in `_remote/work-macbook/`. Until this exists,
`_remote/` is an inert browsable backup. This engine fuses it into the single
second brain.

**Design principle (non-negotiable):** *The hub is authoritative. Work data is
additive-only.* Ingestion may **create** new records and **union** new sub-data into
existing records. It may **never** delete, overwrite, or shrink a record that already
exists. A work record that conflicts with a personal record of the same identity is
routed to a conflict quarantine for human review, never applied in place.

### 9.1 Prerequisite one-liner
Add `"_remote"` (and `"_inbox"`) to `MeetingStore.reservedFolders` so the live app's
scanner never sweeps the quarantine into the main list before an explicit ingest.

### 9.2 Provenance & identity
- **People** → `importSources.insert("work-macbook")` (existing field, survives merges).
- **Action items** → `source = "remote:work-macbook"`, `externalID = <original id>`
  (reuses the existing `(source, externalID)` dedup).
- **Meetings/encounters/tags** → provenance tracked in the import ledger keyed by a
  namespaced key `"work-macbook::<originalID>"`; optional non-breaking `origin.json`
  sidecar inside each imported meeting folder.
- **Preserve original ids** (UUID collisions are astronomically unlikely → keeps
  backlinks resolving and re-imports idempotent). **Slug** collisions get a `-2`/`-3`
  suffix (same as `MeetingStore.moveMeeting`). The pathological same-id/different-
  content case → re-key + quarantine.

### 9.3 Merge rules (summary)
- **Meetings:** new → copy tree via `MeetingStore` writers + `upsertInIndex`. Existing
  same-origin → additive refresh: union attendees; **hub keeps** its `userTitle`/
  `notes`/`health`; fill hub-empty fields from work; `transcript.md`/`summary.md`
  copied only if hub's is missing (else keep hub + drop a `.work.md` sidecar);
  **`notes.md` never overwritten** (append under a divider); audio union by segment.
- **People:** reuse the existing engine — strong match (cid/email/phone/exact name) →
  auto-merge; fuzzy ≥0.85 → auto-merge (unless conflicting strong fields → demote);
  0.6–0.85 → `PersonSuggestion` for the Today tab; <0.6 → new person. Collections
  **unioned by stable id** (the `unionByID` fix); scalars fill-empty-only;
  `createdAt=min`, `lastInteractionAt=max`. Repoint `personID`/`meetingMentions`/
  relationships through a `workID → liveID` map (mirrors `deduplicate()`).
- **Aggregates (read live → merge in-memory → atomic write, never blind-copy):**
  `action_items.json` union by `(source, externalID)` preserving hub edits;
  projects/initiatives/labels/sections union by id; `tags.json` union tags +
  per-meeting assignment lists; `encounters/` copy by id, repoint `personID`.
- **Caches rebuilt, never merged:** `MeetingStore.rebuildIndexAsync()`,
  `PeopleStore` cache + FTS5, per-meeting `indexMeeting`.

### 9.4 Idempotency — the ledger
`<vault>/_remote/.import-ledger.json` (`SchemaEnvelope` v1) maps
`namespacedKey → {contentHash (SHA-256 via CryptoKit), liveID, status, importedAt}`.
Unchanged bytes → skip (makes "every 1–2h" cheap). Changed bytes → re-run the
additive path (itself idempotent). Even a wiped ledger only causes safe redundant
re-merges, never corruption.

### 9.5 Swift shape
New files under `Sources/MeetingScribe/Sync/`: `RemoteVaultIngestor.swift`
(`@MainActor` coordinator: `plan()` dry-run, `run(dryRun:)`, `runAllPending()`),
`ImportLedger.swift`, `IngestPlan.swift`, `IngestHashing.swift`, and
`UI/Settings/RemoteImportSettingsView.swift`. New thin `PeopleStore` wrappers:
`bestStrongMatch`, `bestFuzzyMatch`, `mergeRemote(_:into:)`, `addRemotePerson`,
`enqueueRemoteMergeSuggestion`, `forceCacheWrite`. **Scan/hash on `Task.detached`;
all store mutations on `@MainActor`.** Hooks: boot (background phase, gated on a
`remoteImportEnabled` setting), a 2h timer, and a Settings "Import work data now" /
"Preview import…" (review-before-merge, mirrors `PersonSuggestion`).

### 9.6 Safety invariants (each gets a test)
No delete path; never overwrite a non-empty hub field; conflicts → quarantine;
idempotent; dry-run writes nothing; reversible (pre-merge `.before.json` snapshots
under `_remote/_undo/<runID>/`); staging is read-only to the ingestor's outputs.

---

## 10. Unified build instructions for Claude Code

Do these in order. Phases 0–1 are setup/scripts (no app build for 1a/1b/1d); Phase
1c and Phase 2 are Swift. **Per CLAUDE.md: after any non-trivial Swift edit, run
`swift build -c release` (or `make app`) and `swift test`, then ask the user once
whether to push.**

### Phase 0 — Prereqs (both Macs)
1. `brew install --cask tailscale`; sign in with the **same** account on both;
   enable MagicDNS. Record hub host (`tailscale ip -4` / MagicDNS name) and user.

### Phase 1 — choose ONE transport
**1a (recommended, no build):**
2. Hub: enable Remote Login (your user only).
3. Work: create `~/.ssh/meetingscribe_sync` keypair; `ssh-copy-id` to hub; verify
   `BatchMode=yes` login.
4. Hub: `mkdir -p "<vault>/_remote/work-macbook"`.
5. Work: install `~/.local/bin/meetingscribe-sync.sh` (Report 1 §5), edit the config
   block, `chmod +x`. Optional `brew install flock`.
6. Work: `rsync … --dry-run` to confirm the file list + excludes; then a real run;
   confirm files under `_remote/work-macbook/` + `.last_sync` on the hub.
7. Work: install the LaunchAgent (Report 1 §4), `launchctl load` + `start`; confirm
   `launchctl list | grep meetingscribe`.
8. Hub hardening: `rrsync` forced command in `authorized_keys`; optional tailnet ACL.

**1b (Syncthing):** `brew install syncthing` both; work `brew services start`, hub
LaunchDaemon (Report 3 §3); pair by Device ID; work folder Send-Only on the vault;
hub folder Receive-Only on `_remote/work-macbook/` with Staggered versioning; add
`.stignore` (Report 3 §5); verify with `syncthing cli show connections`.

**1c (in-app HTTP):** implement Report 2 §8 — add `SyncRole` + keys to
`Models/Settings.swift` (token in Keychain); create `Sync/SyncIngest.swift`,
`Sync/SyncHTTPClient.swift`, `Sync/VaultPushSyncService.swift`; route in
`Web/WebAPI.swift`; wire launch + keep-alive in `MeetingScribeApp.swift`; add
`SyncSection` to `UI/SettingsView.swift`. `swift build -c release`; verify with the
curl sequence (Report 2 §8.9); a second identical run must return `need: []`.

**1d (Git relay):** Report 4 §9 — hub bare repo + `audio-mirror`; work `.gitignore`/
`.gitattributes`/pre-commit; work push script + plist; hub pull script + plist
(`DISABLED_NO_PUSH`); test the loop with a throwaway file and confirm it lands only
in the quarantine.

### Phase 2 — Hub-side merge engine (optional, Swift; Report 5 §9)
9. `Models/Settings.swift`: add `remoteImportEnabled`, `remoteImportIntervalSeconds`
   (7200), `remoteImportReviewFirst`.
10. Add `"_remote"`/`"_inbox"` to `MeetingStore.reservedFolders`.
11. Create `Sync/ImportLedger.swift`, `Sync/IngestHashing.swift`, `Sync/IngestPlan.swift`,
    `Sync/IngestScanner.swift` (off-main walk), `Sync/RemoteVaultIngestor.swift`.
12. Extend `PeopleStore` with the wrappers in §9.5 and **fix `mergeFields` to union
    `memories`/`attachedNotes`/`photoRelativePaths` by id**.
13. Aggregate ingest via `ActionItemStore.mergeExternal` + `TagStore.setTags`.
14. Wire boot + timer in `MeetingScribeApp.swift startServices()` (gated on
    `remoteImportEnabled`); add `UI/Settings/RemoteImportSettingsView.swift` with
    Preview/Import/Conflicts.
15. Add tests under `Tests/MeetingScribeTests/` (Report 5 §9 step 10):
    new-meeting-copied, reimport-no-op, person-email-auto-merge-unions,
    fuzzy-mid-score-suggestion, memories-unioned-on-reimport, action-items-dedup,
    tags-unioned, personal-id-collision-quarantined, notes-appended-not-clobbered,
    dry-run-writes-nothing, ledger round-trip.
16. `swift build -c release` && `swift test`; then ask to push.

### Phase 3 — Docs
17. Author `docs/CROSS_DEVICE_SYNC.md` (user-facing setup for the chosen transport,
    how to pause, log locations, one-way/quarantine guarantees); cross-link from
    `README.md`. This master plan + the five reports under `docs/sync-plans/` are the
    engineering reference.

---

## 11. How to choose (decision guide)

- **"I just want my work meetings backed up, minimal fuss, free."** → **1a (rsync)**.
  No build, ship today.
- **"I want it to feel instant / near-real-time."** → **1b (Syncthing)**.
- **"I want one app, one toggle, no Terminal, reuse my phone-pairing QR."** → **1c
  (in-app HTTP)**.
- **"I want full history and the ability to roll back / audit every change."** →
  **1d (Git relay)**.
- **"I want the work data to actually show up in my Meetings/People/Tasks, deduped."**
  → add **Phase 2 (merge engine)** on top of whichever transport you picked.

You can start with 1a + later add Phase 2; the quarantine contract means the merge
engine doesn't care how the bytes arrived.

---

## 12. Cross-cutting: testing, failure modes, security

**Testing/verification (all transports):** after a sync, confirm (a) work data
appears under `_remote/work-macbook/`, (b) the hub's **own** meetings/people are
byte-identical before/after, (c) a second run is a near-no-op (idempotency), (d) a
safety drill — modify hub-authoritative data, run the sync, confirm it's untouched.

**Failure modes:** hub asleep/offline → jobs retry with backoff and coalesce on wake
(`--contimeout`/`waitsForConnectivity`/launchd); partial transfers → resumable
(`--partial` / chunked upload / git fetch); torn files → atomic temp-then-rename /
`replaceItemAt`; clock skew → content hashes are authoritative, never wall-clock.

**Security:** all transports ride **Tailscale WireGuard** (encrypted, device-
authenticated, no public exposure). rsync → dedicated key + optional `rrsync`
forced command. Syncthing → Device-ID auth + TLS, introducer off. In-app → reuse the
constant-time token, gate `/sync/*` to `100.64/10`, rotate to revoke. Git → read-only
hub deploy key + `DISABLED_NO_PUSH` + secret-scanning pre-commit. **No secrets in the
vault** (API keys live in Keychain, excluded everywhere). The quarantine + no-delete
+ additive-merge invariants mean the worst case is junk in `_remote/`, never
corruption or loss of the curated second brain.

---

## 13. Appendix — the five source reports

Each is a complete, standalone build plan with full code/configs:

1. [`sync-plans/agent-1-tailscale-rsync.md`](sync-plans/agent-1-tailscale-rsync.md) — Tailscale + rsync + launchd (the recommended default transport).
2. [`sync-plans/agent-2-inapp-http-push.md`](sync-plans/agent-2-inapp-http-push.md) — In-app Swift HTTP push extending the web server.
3. [`sync-plans/agent-3-syncthing.md`](sync-plans/agent-3-syncthing.md) — Syncthing Send-Only → Receive-Only.
4. [`sync-plans/agent-4-git-relay.md`](sync-plans/agent-4-git-relay.md) — Git-based vault relay (+ audio rsync side-channel).
5. [`sync-plans/agent-5-merge-ingestion-engine.md`](sync-plans/agent-5-merge-ingestion-engine.md) — Hub-side merge/ingestion engine (transport-agnostic Phase 2).
