# Cross-Device Vault Backup — Syncthing One-Way Push (Work MacBook → Personal Hub)

**Status:** Implementation plan (planning only — no source changes)
**Author:** Agent 3 (Syncthing approach)
**Date:** 2026-06-02
**Scope:** Continuous, free, one-way backup of the work MacBook's MeetingScribe
vault into the personal Mac mini "hub," landing in a **quarantined namespace**
so the hub's live second brain is never clobbered.

---

## 0. TL;DR / Recommendation

Use **Syncthing** with a **Send-Only** folder on the work MacBook and a
**Receive-Only** folder on the hub, pointed at a quarantine path
`…/MeetingScribeVault/_remote/work-macbook/` (NOT the live vault root). Run it as
a **launchd service** on both Macs so it syncs at boot without anyone logged in.
Add a `.stignore` to skip derived indexes/caches and in-flight temp files, and
turn on **Staggered File Versioning** on the hub so even a "Receive Only" folder
can never destructively delete or overwrite history.

This is the best fit for the user's stated requirements — **free, continuous,
one-way, hub-data-never-clobbered** — and it needs **zero app changes** to work.
An optional, light app-side "import from `_remote/`" feature is described in §7
but is strictly additive.

Why not the alternatives (full comparison in §2):
- **rsync + cron/launchd:** also free and one-way, but it's *polling* (you pick
  an interval), it has no GUI/health dashboard, and `--delete` is a footgun.
  Great as a fallback; weaker as a daily driver.
- **iCloud Drive:** the vault default *already lives* in iCloud, but iCloud is
  **two-way and account-scoped** — it can't express "push only, never pull, and
  land in a different folder on the other machine." It also can't separate a
  work identity's data from a personal identity's vault. Wrong tool for a
  one-way *backup into a separate namespace*.

---

## 1. Overview & Architecture

```
        WORK MacBook                                  PERSONAL Mac mini (HUB)
 ┌───────────────────────────┐                ┌────────────────────────────────────┐
 │ MeetingScribe app         │                │ MeetingScribe app (the "vault")     │
 │   writes vault files       │                │   LIVE vault root:                  │
 │                            │                │   ~/.../MeetingScribeVault/         │
 │ Vault (storageDir):       │                │     ├── meetings/yyyy/yyyy-MM/<slug> │
 │  ~/.../MeetingScribeVault/ │                │     ├── people/<slug>/               │
 │   ├── meetings/...         │                │     ├── tags.json                   │
 │   ├── people/...           │                │     ├── action_items.json           │
 │   ├── tags.json            │                │     ├── _people-cache.json (local)  │
 │   ├── action_items.json    │                │     ├── .meeting-index.json (local) │
 │   └── (derived caches)     │                │     └── _remote/        ◄── QUARANTINE
 │                            │                │           └── work-macbook/          │
 │  ┌──────────────────────┐ │   encrypted    │             ├── meetings/...         │
 │  │ Syncthing (launchd)  │ │   P2P (TLS)    │  ┌────────────────────────┐          │
 │  │ folder = vault       │ ├───────────────►│  │ Syncthing (launchd)    │          │
 │  │ type = SEND ONLY     │ │  LAN direct or │  │ folder = _remote/...   │          │
 │  └──────────────────────┘ │  relay/Tailnet │  │ type = RECEIVE ONLY    │          │
 │                            │                │  │ versioning = Staggered │          │
 └───────────────────────────┘                │  └────────────────────────┘          │
                                              └────────────────────────────────────┘

  Data flows ONE WAY:  work vault  ──►  hub:_remote/work-macbook/
  Hub's LIVE vault (meetings/, people/, tags.json…) is a SIBLING of _remote/,
  never written by Syncthing. Receive-Only + Staggered versioning = non-clobber.
```

Key design points:

1. **Two distinct folder *types*.** Syncthing folders have a `type`. Send-Only
   *announces* changes but refuses to apply remote changes; Receive-Only
   *applies* changes but refuses to push local edits back. The pairing
   `SendOnly → ReceiveOnly` is the canonical one-way mirror.
2. **Different filesystem paths on each side.** The work folder points at the
   live work vault. The hub folder points at a **quarantine subdir**
   `_remote/work-macbook/`. Because the two Syncthing folders share a *Folder
   ID* (the logical link) but map to *different local paths*, the work vault
   lands *next to*, not *on top of*, the hub's vault.
3. **The hub's live vault is never a Syncthing folder.** Nothing Syncthing does
   can touch `meetings/`, `people/`, `tags.json`, etc. on the hub. The only path
   Syncthing owns on the hub is `_remote/work-macbook/`.

> ⚠️ **Critical guardrail — never share the hub's vault root.** If you ever point
> the hub's Receive-Only folder at the live `MeetingScribeVault/` root, a
> Receive-Only folder will happily *delete* hub-only files that don't exist on
> the sender (it treats them as "extra files to remove" unless versioned). The
> quarantine subdir makes that structurally impossible.

---

## 2. Why Syncthing (and honest trade-offs)

### What Syncthing is
Free, open-source (MPL-2.0), continuously-running peer-to-peer file
synchronization. No cloud account, no server you rent, no per-seat fee. Devices
authenticate each other by cryptographic **Device ID** (the hash of a
self-signed TLS cert). All transfers are TLS-encrypted. It works:
- **On the same LAN** — direct local discovery, full LAN speed.
- **Across networks** — via Syncthing's global discovery + community relay
  servers (encrypted end-to-end; relays only see ciphertext), OR — cleaner and
  faster — over **Tailscale**, which this repo already recommends for phone
  access (`docs/PHONE_ACCESS.md`). Tailscale gives both Macs stable private IPs
  so Syncthing connects directly with no relay.

### Why it fits *these* requirements
| Requirement | Syncthing |
| --- | --- |
| **Free** | Yes — OSS, no fees, no account. |
| **At least daily / every 1–few hrs** | Better: **continuous** (watches the FS, syncs within seconds of a change). |
| **One-way only** | Native: Send-Only ↔ Receive-Only folder types. |
| **Hub data never clobbered** | Quarantine namespace + Receive-Only + file versioning. |
| **No login required** | Runs as a launchd service at boot. |
| **No app changes** | Operates entirely outside the app on plain vault files. |

The MeetingScribe vault is **plain Markdown + JSON files** (`SchemaEnvelope`
`{version,data}`), which is exactly what file-level sync handles best — no
database to corrupt, no proprietary container. The app explicitly has **"no
background sync service"** (`docs/ARCHITECTURE.md:591`), so a third-party daemon
is a clean, decoupled fit.

### vs. rsync + cron/launchd
- **rsync pros:** built into macOS, dead simple, trivially one-way, easy to
  script `--exclude` lists, `--link-dest` snapshots are cheap.
- **rsync cons:** it's **pull/poll on a timer**, not event-driven — you choose
  an interval (e.g. hourly), so changes lag. No GUI, no health/conflict
  dashboard, no built-in versioning UI, and a fat-fingered `--delete` against
  the wrong target can wipe the hub. Requires SSH between the Macs.
- **Verdict:** keep rsync in your back pocket as a **belt-and-suspenders nightly
  job** (Appendix B), but Syncthing is the better continuous primary.

### vs. iCloud Drive
- The vault's *default* path is already in iCloud
  (`Sources/VaultKit/VaultPaths.swift:8`), so iCloud "just works" for a single
  identity — but:
- iCloud is **bidirectional and account-bound.** You can't say "push work→hub
  but never hub→work," and you can't land the work data in a *different folder*
  on the hub. Both machines would have to be on the **same Apple ID**, merging
  work and personal data into one vault — the opposite of a quarantined backup.
- iCloud also throttles, defers under "Optimize Mac Storage," and evicts files
  to dataless stubs — unfriendly to large `.m4a` audio.
- **Verdict:** wrong semantics for a one-way backup into a separate namespace.

### Honest Syncthing cons
- **Folder/file-level, not record-level.** It mirrors files; it has no idea what
  a "meeting" is. If you want the hub app to *merge* work meetings into the
  second brain (rebuild indexes, de-dup people), that's an extra import step
  (§7), not automatic.
- **Needs the daemon running on both ends.** If the work MacBook's Syncthing is
  off, nothing flows. (launchd at boot + a menu-bar reminder mitigates this.)
- **Not a "set the interval to exactly N hours" tool** — it's continuous-on-
  change. That *exceeds* "every 1–few hours," but if you specifically want
  batched/throttled pushes you tune the watcher/scan settings (§6).
- **Both machines must be reachable at the same time** for a sync to complete.
  The work laptop pushes when it's awake and online; the hub catches up whenever
  both are up. For a Mac mini that's basically always-on, this is a non-issue.

---

## 3. Install & Run-as-Service (do on BOTH Macs)

### 3.1 Install via Homebrew

Syncthing ships two relevant formulae. Use the **plain CLI formula**
(`syncthing`) — it includes a `brew services` integration and is lighter than
the menu-bar cask. (The GUI cask `syncthing-macos`/menu-bar app is optional and
described in §3.4.)

```bash
brew install syncthing
```

This installs the `syncthing` binary (Apple Silicon: `/opt/homebrew/bin/syncthing`).

### 3.2 First run to generate identity + config

Run it once in the foreground so it generates the device certificate/ID and the
default `config.xml`, then quit with Ctrl-C:

```bash
syncthing --no-browser
# wait until you see "My ID: XXXXXXX-..." then Ctrl-C
```

Config + keys land in:
```
~/Library/Application Support/Syncthing/
  ├── config.xml      # folders, devices, GUI settings
  ├── cert.pem        # this device's TLS cert
  ├── key.pem
  └── index-v0.14.0.db/  (or similar) — internal index
```

Grab the **Device ID** any time with:
```bash
syncthing --device-id
```

### 3.3 Run as a launchd service (boot, no login)

`brew services` registers a *LaunchAgent*, which only runs when the user is
**logged in**. For "syncs even when no one is logged in" you want a **LaunchDaemon**
(runs at boot, as the user, via `UserName`). Two options:

**Option A — simplest (`brew services`, runs at login):**
```bash
brew services start syncthing
```
Good enough for the **work MacBook** (the laptop is in use when it's open, so a
login-scoped agent is fine — it starts when you log in and pushes while you work).

**Option B — LaunchDaemon (runs at boot, even at the login window):**
Recommended for the **always-on hub** so it receives backups even when the Mac
mini reboots and sits at the login screen.

Write `/Library/LaunchDaemons/com.tyleryannes.syncthing.plist` (requires sudo):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tyleryannes.syncthing</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/syncthing</string>
        <string>serve</string>
        <string>--no-browser</string>
        <string>--no-restart</string>
        <string>--logflags=3</string>
    </array>
    <!-- Run as the actual user so it reads ~/Library/Application Support
         and ~/Library/Mobile Documents (iCloud) with the right permissions. -->
    <key>UserName</key>
    <string>REPLACE_WITH_MAC_USERNAME</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/Users/REPLACE_WITH_MAC_USERNAME</string>
        <!-- Bind GUI to loopback only (default, but explicit): -->
        <key>STGUIADDRESS</key>
        <string>127.0.0.1:8384</string>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>/Users/REPLACE_WITH_MAC_USERNAME/Library/Logs/syncthing.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/REPLACE_WITH_MAC_USERNAME/Library/Logs/syncthing.err.log</string>
</dict>
</plist>
```

Load it:
```bash
sudo chown root:wheel /Library/LaunchDaemons/com.tyleryannes.syncthing.plist
sudo chmod 644 /Library/LaunchDaemons/com.tyleryannes.syncthing.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.tyleryannes.syncthing.plist
sudo launchctl print system/com.tyleryannes.syncthing | head -20   # verify "state = running"
```

> Note on iCloud paths: if the vault lives under
> `~/Library/Mobile Documents/com~apple~CloudDocs/…` (the default), a
> LaunchDaemon reading another user's iCloud can hit permission/eviction quirks.
> Running **as the user** (`UserName` + correct `HOME`) avoids most of this. If
> you see iCloud-eviction stubs, point the vault `storageDir` at a *local* path
> (e.g. `~/Documents/MeetingNotes`, already a supported default) on at least the
> hub — see §6.4. This is the most reliable configuration.

### 3.4 GUI access

The web admin GUI is at **http://127.0.0.1:8384** (loopback only by default —
not exposed to the network). Open it on each Mac to do the pairing in §4. To
manage the *hub's* Syncthing from the work laptop, either:
- SSH-tunnel: `ssh -L 8384:127.0.0.1:8384 hub.local` then browse localhost:8384, or
- reach it over Tailscale and temporarily set `STGUIADDRESS` to the tailnet IP
  *with a GUI password set* (Settings → GUI → set user/password). Don't expose
  8384 unauthenticated.

Optional menu-bar app: `brew install --cask syncthing-macos` gives a tray icon
and "open GUI" shortcut. Cosmetic; the launchd service does the real work.

---

## 4. Folder Configuration, Step by Step

We'll use a fixed, human-readable **Folder ID** so both sides match:
`meetingscribe-vault-work`.

### 4.1 Pair the two devices

1. On the **work MacBook**, open GUI (127.0.0.1:8384) → **Actions → Show ID** →
   copy the Device ID (or `syncthing --device-id`).
2. On the **hub**, open GUI → **Add Remote Device** → paste the work Device ID →
   name it `work-macbook` → Save.
3. On the **work MacBook**, when the hub appears as a pending device (or add it
   manually with the hub's Device ID) → name it `hub-mini` → Save.
4. Confirm both show **"Connected"** (green) under Remote Devices. On the same
   LAN this is instant; cross-network, give global discovery/relay a minute, or
   put both on Tailscale first (recommended).

Equivalent `config.xml` device stanza (auto-written by the GUI; shown for
reference) — on the **work** machine's config:
```xml
<device id="HUBDEVICE-ID-HERE-...." name="hub-mini" compression="metadata"
        introducer="false">
    <address>dynamic</address>
    <!-- or a fixed Tailscale address: <address>tcp://100.x.y.z:22000</address> -->
</device>
```

### 4.2 Create the **Send-Only** folder on the work MacBook

GUI → **Add Folder**:
- **Folder Label:** `MeetingScribe Vault (work)`
- **Folder ID:** `meetingscribe-vault-work`  ← must match the hub exactly
- **Folder Path:** the work vault. Read it from the app's setting — it's
  `UserDefaults "storageDir"` (`Sources/ScribeCore/AppSettings.swift:7,21`),
  falling back to the iCloud default
  (`Sources/VaultKit/VaultPaths.swift:5-9`):
  ```bash
  defaults read com.tyleryannes.MeetingScribe storageDir 2>/dev/null \
    || echo "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"
  ```
- **Sharing tab:** check **hub-mini**.
- **Advanced tab → Folder Type:** **Send Only**.
- **Advanced → Fs Watcher:** Enabled (near-real-time). **Full Rescan Interval:**
  3600s (hourly safety scan).
- Leave **File Versioning: None** on the *sender* (versioning belongs on the
  receiver).

> Optional safety: sync a **copy**, not the live vault. If you'd rather not let
> Syncthing watch the live work vault directly, point the Send-Only folder at a
> nightly `rsync` mirror (`~/MeetingScribeVaultMirror/`). Costs disk + a cron
> job; gains an air-gap between the app and the sync tool. Default
> recommendation is to sync the live vault directly — it's simpler and
> Send-Only never writes to it.

Equivalent `config.xml` (work machine):
```xml
<folder id="meetingscribe-vault-work" label="MeetingScribe Vault (work)"
        path="/Users/USER/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"
        type="sendonly" rescanIntervalS="3600" fsWatcherEnabled="true">
    <device id="HUBDEVICE-ID-HERE-...."></device>
    <versioning></versioning>
</folder>
```

### 4.3 Accept it as **Receive-Only** on the hub, into the quarantine path

When the share offer arrives on the hub, the GUI shows
**"work-macbook wants to share folder meetingscribe-vault-work."** Click **Add**:
- **Folder ID:** `meetingscribe-vault-work` (pre-filled — keep it).
- **Folder Path:** **the quarantine subdir, NOT the live vault root:**
  ```
  ~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook
  ```
  (or, if the hub vault is local: `~/Documents/MeetingNotes/_remote/work-macbook`).
  Create it first:
  ```bash
  mkdir -p "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook"
  ```
- **Advanced → Folder Type:** **Receive Only**.
- **File Versioning:** **Staggered** (see §6).
- Save.

Equivalent `config.xml` (hub):
```xml
<folder id="meetingscribe-vault-work" label="MeetingScribe Vault (work)"
        path="/Users/USER/.../MeetingScribeVault/_remote/work-macbook"
        type="receiveonly" rescanIntervalS="3600" fsWatcherEnabled="true">
    <device id="WORKDEVICE-ID-HERE-...."></device>
    <versioning type="staggered">
        <param key="maxAge" val="2592000"/>   <!-- keep 30 days of versions -->
        <param key="cleanInterval" val="3600"/>
    </versioning>
</folder>
```

After saving on both ends, the work vault begins replicating into
`_remote/work-macbook/` on the hub — *next to*, never *over*, the hub's live
vault.

---

## 5. `.stignore` — what to skip and why

Put this file at the **root of the synced folder on the WORK MacBook** (the
sender), i.e. `…/MeetingScribeVault/.stignore`. `.stignore` is itself synced
unless you mark lines with `(?d)`, but it's safest to configure it on the sender
side. Patterns are relative to the folder root.

```gitignore
// ── Derived index / caches — each machine rebuilds these locally ──
// Per-machine SQLite-ish meeting index. Never share; the hub has its own.
.meeting-index.json
_people-cache.json

// Inbox plumbing: drop folder + processed receipts are device-local workflow,
// not backup-worthy. (iCloudInboxWatcher.swift owns these.)
_inbox/processed
// (Keep _inbox itself? It's a transient drop zone for iPhone Shortcuts.
//  Exclude its working state but you may keep top-level _inbox if you want
//  in-flight drops backed up. Default: skip processed receipts only.)

// Recent-meetings stub regenerated on demand (MeetingStore.swift:219).
_recent.json

// Local-only metadata caches.
_cache
_meta.json

// In-flight / temp / partials — never sync half-written files.
*.tmp
*.partial
*.download
*~
.DS_Store
.localized

// Syncthing's own conflict copies (don't recurse them around).
*.sync-conflict-*

// macOS resource forks / Spotlight noise.
._*
.Spotlight-V100
.fseventsd
.TemporaryItems
```

**Keep (do NOT ignore) — these ARE the backup:**
- `meetings/yyyy/yyyy-MM/<slug>/` → `meeting.json`, `transcript.md`, `notes.md`,
  `summary.md`, `mic.m4a`, `system.m4a`, `audio/` (segments + `manifest.json`)
- `people/<slug>/` → `person.json`, `person.md`
- `encounters/`
- Aggregates: `tags.json`, `action_items.json`, `people-tags.json`,
  `projects.json`, `initiatives.json`, `project_sections.json`, `task_labels.json`
- `QuickNotes/<slug>/`, `Daily/`

Rationale: the JSON/Markdown *source of truth* is small and precious — sync all
of it. The derived index (`.meeting-index.json`), people cache
(`_people-cache.json`), and `secondbrain.db` (which lives in **Application
Support**, *outside* the vault per `VaultPaths.swift:11-17`, so it's not in scope
anyway) are rebuildable and machine-specific; syncing them would (a) waste
bandwidth and (b) risk one machine's stale index landing on the other. The audio
`.m4a` files are the bandwidth driver — see §6.

> `secondbrain.db` is **not** under the vault root (it's in
> `~/Library/Application Support/MeetingScribe/`), so it will never be synced by
> this folder. Good — that's the desired behavior.

---

## 6. One-Way + Non-Clobber Design

Three independent layers guarantee the hub is never destructively modified:

### 6.1 Direction: Send-Only ↔ Receive-Only
- The **work** folder is **Send Only**: Syncthing announces its files but will
  **never apply** anything received from the hub. So even if the hub's copy
  changed, it can't propagate back to work.
- The **hub** folder is **Receive Only**: it applies what work sends but **never
  pushes** local edits out, and it flags any *local* changes as "Local
  Additions" you can **Revert** (discard) — it does not send them to work.
- Net effect: edits flow strictly **work → hub**.

### 6.2 Namespace separation (the big one)
- The hub's Syncthing folder is rooted at `_remote/work-macbook/`. The hub's
  **live vault** (`meetings/`, `people/`, `tags.json`, `action_items.json`, …)
  is a **sibling**, completely outside any Syncthing folder. Therefore **no
  Syncthing operation can read, modify, or delete the hub's real data.** This is
  the structural guarantee that "hub data is never clobbered" — it's not a
  setting that can be misconfigured at the file level; the live vault simply
  isn't in scope.

### 6.3 File Versioning on the hub = non-destructive even within the quarantine
A Receive-Only folder *can* delete/overwrite files **inside its own root** when
the sender deletes/overwrites them (e.g., the app rewrites `meeting.json` during
self-heal, `MeetingStore.swift:150-155`). To keep history:
- **Staggered File Versioning** (recommended): keeps a thinning history under
  `_remote/work-macbook/.stversions/` — 1 version/hour for a day, 1/day for 30
  days, then pruned. Nothing is ever hard-deleted; you can recover any prior
  `transcript.md`/`meeting.json`.
- Alternative **Trash Can Versioning:** every replaced/deleted file moves to
  `.stversions/` once (simpler, keeps exactly the last copy). Choose Trash Can
  if you only want "undelete," Staggered if you want point-in-time history.

So even *inside* the quarantine, "overwrite" really means "move old copy to
`.stversions/`, then write new." Truly destructive loss requires losing both the
sender and the hub's `.stversions/`.

### 6.4 Keeping the hub's primary vault truly separate
- The hub app's `storageDir` (`AppSettings.swift:21`) points at the **live vault
  root** — *not* at `_remote/`. The app never treats `_remote/` as part of its
  store unless you build the optional importer (§7), and even then importing is
  an explicit *copy* into the live store.
- If you want belt-and-suspenders isolation, set the **hub** vault to a *local*
  path (`~/Documents/MeetingNotes`, a supported default) and keep `_remote/`
  under it. This sidesteps iCloud eviction entirely for the received data.

---

## 7. Optional App Integration (light, additive — not required for backup)

The backup works with **zero app changes**. Two optional, low-risk enhancements:

### 7.1 Settings / Help panel pointing users to setup
Add a **"Cross-device backup (Syncthing)"** section to the existing
`Sources/MeetingScribe/UI/SettingsView.swift` (sibling to the existing "Phone
access (web)" section described in `docs/PHONE_ACCESS.md`). It would:
- Show the device's vault path (`AppSettings.vaultURL`) so the user can paste it
  into Syncthing's Folder Path.
- Detect whether `…/MeetingScribeVault/_remote/` exists and, if so, list the
  sub-namespaces (e.g. `work-macbook`) with a meeting count.
- Link to a new `docs/CROSS_DEVICE_SYNC.md` (matching the tone/structure of
  `docs/PHONE_ACCESS.md`).

No new sync code — this is a read-only informational panel + a "Reveal in
Finder" button.

### 7.2 "Import from `_remote/`" feature (the real integration)
Because Syncthing only mirrors *files*, the received work meetings sit in the
quarantine as inert folders. A small importer can fold them into the hub's
second brain. Reuse the **existing ingest precedent**
(`Sources/MeetingScribe/Sync/iCloudInboxWatcher.swift`), which already watches a
vault subfolder via `NSMetadataQuery` and routes items into subsystems via
callbacks (`onQuickNote`, `onActionItem`, `onAddPerson`, `onVoiceNote`).

Plan (new file, e.g. `Sources/MeetingScribe/Sync/RemoteVaultImporter.swift`):
1. **Scan** `…/MeetingScribeVault/_remote/work-macbook/meetings/**/<slug>/`.
2. For each meeting folder, read `meeting.json` (`SchemaEnvelope<Meeting>`) and
   skip if a meeting with that ID already exists in the hub's
   `MeetingStore` (`Sources/MeetingScribe/Storage/MeetingStore.swift`).
3. **Copy** the folder (`meeting.json`, `transcript.md`, `notes.md`,
   `summary.md`, `audio/`, `*.m4a`) into the hub's live layout
   `meetings/yyyy/yyyy-MM/<slug>/` via `MeetingStore` write paths
   (`writeMeeting`/`writeTranscript`/etc., `MeetingStore.swift:256-304`). Prefix
   or tag imported meetings (e.g. add a `source: "work-macbook"` tag) so they're
   distinguishable.
4. Merge **people** from `_remote/.../people/<slug>/` into the hub's
   `PeopleStore` (`Sources/MeetingScribe/People/PeopleStore.swift`), de-duping by
   slug; let the store rebuild `_people-cache.json`.
5. Merge **action items** from the remote `action_items.json` into the hub's
   `ActionItemStore` (`Sources/MeetingScribe/ActionItems/ActionItemStore.swift`),
   de-duping by ID.
6. **Rebuild the index** (`.meeting-index.json` / `secondbrain.db`) via the
   existing index-rebuild path so search/people pick up the imports.
7. Surface as a **manual button** first ("Import N new meetings from
   work-macbook"), gated and idempotent — never auto-overwrite hub records.
   Promote to automatic only after it's proven idempotent.

This keeps the dangerous part (writing into the live store) inside the app's
existing, de-duping store APIs rather than in Syncthing — Syncthing only ever
touches the quarantine.

> Per CLAUDE.md build rules, any of these Swift changes must be
> `swift build -c release` / `make app` clean before pushing, and you'd ask
> before committing. This report makes **no** source changes.

---

## 8. Step-by-Step Build / Setup (copy-paste)

### Part A — Claude Code can do now (docs only)
1. Create this plan (done): `docs/sync-plans/agent-3-syncthing.md`.
2. (Optional, on request) Author a user-facing `docs/CROSS_DEVICE_SYNC.md`
   mirroring `docs/PHONE_ACCESS.md`'s tone, summarizing §3–§6 for the user.
3. (Optional, on request) Add the §7.1 read-only Settings panel + §7.2 importer
   behind a feature flag; build-verify; then ask to push per CLAUDE.md.

### Part B — User runs on BOTH Macs
```bash
# 1. Install
brew install syncthing

# 2. Generate identity + config (Ctrl-C after "My ID:")
syncthing --no-browser

# 3a. Work MacBook — login-scoped service is fine:
brew services start syncthing

# 3b. Hub Mac mini — boot-scoped LaunchDaemon (see §3.3 for the plist):
sudo nano /Library/LaunchDaemons/com.tyleryannes.syncthing.plist   # paste §3.3
sudo chown root:wheel /Library/LaunchDaemons/com.tyleryannes.syncthing.plist
sudo chmod 644 /Library/LaunchDaemons/com.tyleryannes.syncthing.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.tyleryannes.syncthing.plist

# 4. Print each device's ID (run on each Mac)
syncthing --device-id
```

### Part C — Pair + configure (GUI at 127.0.0.1:8384)
```
HUB:   mkdir -p "~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook"
WORK:  GUI → Add Remote Device → paste HUB device ID → name "hub-mini"
HUB:   GUI → Add Remote Device → paste WORK device ID → name "work-macbook"
WORK:  GUI → Add Folder
         ID    = meetingscribe-vault-work
         Path  = <output of: defaults read com.tyleryannes.MeetingScribe storageDir>
         Share = hub-mini
         Type  = Send Only   (Advanced tab)
         FsWatcher = on, Rescan = 3600s
HUB:   Accept the incoming share →
         Path  = ~/.../MeetingScribeVault/_remote/work-macbook
         Type  = Receive Only
         Versioning = Staggered (maxAge 30d)
WORK:  Drop the §5 .stignore at the vault root.
```

### Part D — Verify
```bash
# On either Mac:
syncthing cli show connections        # both devices "connected": true
syncthing cli show system | grep myID

# On the HUB, after first sync, confirm files landed in quarantine ONLY:
ls "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook/meetings"
# And confirm the live vault is untouched (no Syncthing metadata at its root):
ls "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"   # no .stfolder here

# Live test: create a dummy meeting folder on WORK, watch it appear on HUB
# within seconds under _remote/work-macbook/.
```

(`syncthing cli` talks to the running daemon via its REST API; you may need to
export the API key once: `export STGUIAPIKEY=$(…)` or use `--gui-apikey`. The
key is in `config.xml` under `<gui><apikey>`.)

---

## 9. Testing, Failure Modes, Troubleshooting, Security

### 9.1 Verification checklist
- [ ] Both devices show **Connected** (green) in each GUI.
- [ ] Work folder type = **Send Only**; hub folder type = **Receive Only**.
- [ ] Hub folder path ends in **`/_remote/work-macbook`** (NOT the vault root).
- [ ] A new file on work appears on the hub within ~seconds (fsWatcher) or
      within the rescan interval at worst.
- [ ] `.stignore` is excluding `.meeting-index.json`, `_people-cache.json`,
      `_recent.json`, `*.tmp` (check "Out of Sync Items" shows none of these).
- [ ] Hub `.stversions/` populates when a file is replaced (delete a test file
      on work; confirm the old copy is preserved on the hub, not gone).
- [ ] Reboot the hub → daemon comes back (`launchctl print system/com.tyleryannes.syncthing`).

### 9.2 Failure modes & fixes
| Symptom | Cause | Fix |
| --- | --- | --- |
| Devices won't connect | LAN discovery blocked / different networks | Put both on **Tailscale**, add the tailnet IP as a static `<address>`; or verify ports 22000/tcp+udp (data) and 21027/udp (discovery) aren't firewalled. |
| Stuck "Syncing" on large `.m4a` | Bandwidth / sleep | Set send/receive rate limits (Settings → Connections), or sync over LAN/Tailscale; ensure the laptop doesn't sleep mid-transfer (it resumes on wake). |
| Hub shows "Local Additions" | App rewrote a file on the hub (e.g. importer, or you edited in quarantine) | Receive-Only "**Revert**" discards them (one-way intent), or stop editing inside `_remote/`. |
| iCloud evicted files to stubs | Optimize Mac Storage on iCloud vault | Use a **local** vault path on the hub (§6.4), or disable "Optimize Mac Storage." |
| Conflicts (`*.sync-conflict-*`) | Same file edited on both ends | Shouldn't happen one-way; if it does, the work copy wins on the sender. Don't edit inside the hub quarantine. |
| Daemon not running at login window | Used `brew services` (LaunchAgent) on the hub | Switch the hub to the **LaunchDaemon** in §3.3. |
| `.stignore` not taking effect | Placed on the wrong side / typo | It must be at the **sender's** folder root; "Rescan" to re-evaluate. |

### 9.3 Security
- **Device authentication:** peers are identified by **Device ID** (TLS cert
  hash). Only the two IDs you explicitly add can connect; unknown devices are
  rejected. Treat Device IDs as semi-public (they're not secrets, but only add
  ones you control).
- **Encryption in transit:** all device-to-device traffic is **TLS**. Over
  relays, traffic is end-to-end encrypted; relays only forward ciphertext.
- **Keep introducer OFF** (`introducer="false"`). With only two devices you
  don't want auto-introduction adding third parties.
- **Untrusted-device option:** if you ever route through a less-trusted relay or
  want the hub to hold *encrypted-at-rest* copies, Syncthing supports
  **"Untrusted (Encrypted)"** device sharing with a password — the receiver
  stores only encrypted blobs. Not needed for a hub you fully control, but
  available.
- **GUI:** bound to **127.0.0.1:8384** (loopback) by default — not network-
  exposed. If you must reach it remotely, do it over **Tailscale** *and* set a
  GUI username/password; never bind 8384 to `0.0.0.0` unauthenticated.
- **Firewall:** allow `syncthing` (it'll prompt via macOS Application Firewall
  the first time). Ports: **22000/tcp+udp** (sync data, QUIC), **21027/udp**
  (local discovery). Over Tailscale you can skip opening anything to the public
  internet.
- **No cloud copy:** unlike iCloud, no third party ever holds your plaintext.
  The only copies are on your two Macs (plus `.stversions/` history on the hub).

---

## Appendix A — Why the quarantine path is non-negotiable
A Receive-Only folder, when the sender deletes a file, will delete the local
copy too (moving it to `.stversions/` if versioning is on). If the hub's *live
vault root* were the Receive-Only folder, then any hub-only meeting that doesn't
exist on the work laptop would be flagged as a "Local Addition" and could be
**Reverted (deleted)** — clobbering your personal data. Rooting the folder at
`_remote/work-macbook/` makes the hub's real vault physically out of scope.

## Appendix B — rsync fallback (optional belt-and-suspenders nightly)
Keep this as a redundant nightly mirror in addition to Syncthing, never instead
of it for one-way safety (note: **no `--delete`** against the live root; target a
quarantine path and never the hub vault root):
```bash
# On the WORK MacBook, via launchd nightly:
rsync -av --partial \
  --exclude='.meeting-index.json' --exclude='_people-cache.json' \
  --exclude='_recent.json' --exclude='*.tmp' --exclude='.DS_Store' \
  "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/" \
  hub-mini.tailnet:'~/.../MeetingScribeVault/_remote/work-macbook-rsync/'
```
Use `--link-dest` for cheap dated snapshots if you want point-in-time history
without Syncthing's `.stversions/`.

---

## Appendix C — Repo facts verified for this plan
- Vault default path & iCloud root: `Sources/VaultKit/VaultPaths.swift:5-9`.
- `storageDir` UserDefaults key + fallback: `Sources/ScribeCore/AppSettings.swift:7,21`.
- Derived DB lives in App Support, **outside** vault: `VaultPaths.swift:11-17`.
- Meeting layout `meetings/yyyy/yyyy-MM/<slug>/` with `meeting.json`,
  `transcript.md`, `notes.md`, `summary.md`, `mic.m4a`, `system.m4a`, `audio/`:
  `Sources/MeetingScribe/Storage/MeetingStore.swift:9-15,95-155,256-304`.
- People `people/<slug>/` + `_people-cache.json`, `encounters/`:
  `Sources/MeetingScribe/People/PeopleStore.swift:15,17,300`.
- Aggregates: `tags.json` (`Storage/TagStore.swift:6`), `action_items.json`
  (`ActionItems/ActionItemStore.swift:5`), plus `projects.json`,
  `initiatives.json`, `_recent.json` (`MeetingStore.swift:219`).
- Local index `.meeting-index.json` (`MeetingStore.swift:58`).
- Existing external-ingest precedent (NSMetadataQuery + callbacks):
  `Sources/MeetingScribe/Sync/iCloudInboxWatcher.swift`.
- "No background sync service" by design: `docs/ARCHITECTURE.md:591`.
- Tailscale already endorsed for remote access: `docs/PHONE_ACCESS.md`.
- macOS 14+ target: `Package.swift:14` (`platforms: [.macOS(.v14)]`).
```
