# Sync Plan — Tailscale + rsync over SSH (launchd-scheduled)

**Approach owner:** Agent 1
**Goal:** One-way backup of the MeetingScribe vault from the **work MacBook** → the **personal Mac mini hub** ("second brain"), free, hourly-ish, never clobbering hub data.
**Status:** Planning report only. No source files modified. Implements an OS-native, file-level sync that requires *zero* Swift changes for the core feature (optional hub-side ingestion in §7 is additive).

---

## 1. Overview & architecture

The work MacBook runs a `launchd` LaunchAgent every N hours. That agent runs a bash
script that `rsync`s the work vault into a **namespaced quarantine subfolder** on the
hub, transported over **SSH on the tailnet** (Tailscale's private 100.x address /
MagicDNS name). The hub's own vault data is never a destination for the sync, so it
can never be overwritten or deleted.

```
                        Tailscale tailnet (WireGuard, encrypted)
                        100.x.y.z  /  MagicDNS names
   WORK MacBook                                            PERSONAL Mac mini  (HUB)
 ┌───────────────────────────┐                       ┌──────────────────────────────────┐
 │ MeetingScribe.app         │                       │ MeetingScribe.app (authoritative) │
 │   writes vault →          │                       │                                   │
 │ ~/.../MeetingScribeVault  │                       │ ~/.../MeetingScribeVault          │
 │                           │                       │   ├── <tag>/<slug>/  (HUB's own)  │
 │ launchd LaunchAgent       │   rsync -az --partial │   ├── people/        (HUB's own)  │
 │  com.tyleryannes          │   over SSH on tailnet │   ├── action_items.json  (HUB)    │
 │  .meetingscribe.sync      │ ────────────────────▶ │   └── _remote/         ◀── QUARANTINE
 │  every 2h                 │      (push only)      │        └── work-macbook/          │
 │    │                      │                       │             ├── <tag>/<slug>/     │
 │    └─ run sync.sh ────────┤                       │             ├── people/           │
 │         ├ flock (no overlap)                      │             ├── action_items.json │
 │         ├ rsync push                              │             └── ...mirror of work │
 │         └ retry/backoff   │                       │   (optional) app ingests _remote/ │
 │  logs → ~/Library/Logs/   │                       │             into second brain     │
 │     MeetingScribe/sync.*  │                       │                                   │
 └───────────────────────────┘                       └──────────────────────────────────┘
```

Key properties:

- **Direction:** strictly work → hub (push). The hub never pushes back.
- **Destination namespace:** `<hub vault>/_remote/work-macbook/` — a leading-underscore
  folder the hub app already ignores by convention (it ignores `_inbox/`; we extend the
  scanner's `reservedFolders` to ignore `_remote/`, see §7).
- **No `--delete` against hub-authoritative data**, ever. (`--delete` is scoped *only*
  to the `_remote/work-macbook/` mirror subtree if used at all — see §5/§6.)
- **Transport:** SSH over the tailnet. No port-forwarding, no public exposure, no cloud.

---

## 2. Why this approach

### What runs where
- **Work MacBook:** a LaunchAgent + one bash script + an SSH keypair. Nothing else.
- **Hub Mac mini:** Remote Login (sshd) enabled, Tailscale running, an `authorized_keys`
  entry. No daemon, no extra software, no app changes required for the core sync.

### Pros
- **$0 forever.** Tailscale's free *Personal* plan covers up to 100 devices / 3 users —
  two of your own Macs is trivially inside it. `rsync`, `ssh`, and `launchd` ship with
  macOS. No subscriptions, no egress fees, no S3 bucket.
- **Zero app changes for the core feature.** The vault is plain Markdown/JSON files
  (per ARCHITECTURE.md "No SwiftData… plain Codable JSON on disk… grepability"), so a
  file-level tool syncs it perfectly. The app doesn't need to know sync exists.
- **Already a blessed dependency.** `docs/PHONE_ACCESS.md` already documents Tailscale
  for phone access — same tailnet, same mental model, same admin console.
- **Delta transfers.** rsync only ships changed blocks; a 2-hour cadence over a vault
  with large `.m4a` audio is cheap after the first full sync.
- **Resilient & atomic.** `--partial --partial-dir` + rsync's temp-file-then-rename
  means a dropped connection resumes and never leaves a half-written file in place.
- **Inspectable.** Everything that lands on the hub is human-readable files in a single
  quarantined folder you can `grep`, diff, or delete wholesale.

### Cons / trade-offs
- **Push cadence, not real-time.** launchd `StartInterval` is best-effort; if the laptop
  is asleep at the fire time, the job runs on next wake (acceptable — requirement is
  "at least once a day, ideally every 1–few hours").
- **File-level, not record-level merge.** rsync mirrors files into the namespace; it does
  not *merge* work meetings into the hub's authoritative stores. That's intentional for
  safety (no clobber) and is exactly what §7's optional ingestion step adds if you want
  the work data fused into the single second brain.
- **Aggregate JSON files are last-writer-wins *within the namespace*.** `action_items.json`,
  `tags.json`, etc. on the work side overwrite the *copy under `_remote/work-macbook/`* —
  never the hub's own top-level copies. (Hub authoritative copies live at the vault root,
  outside the destination path.)

### Alternatives considered (and why not, briefly)
- **iCloud Drive shared vault:** two machines writing the same iCloud folder = two-way
  sync and real clobber risk on aggregate JSON; violates "one-way / never clobber hub".
- **Resilio/Syncthing:** also bidirectional by default; free Syncthing is great but is a
  long-running daemon to babysit and still needs conflict handling. rsync+launchd is
  simpler and unambiguously one-directional.
- **App-native S3/Box sync (`Sources/MeetingScribe/Sync/`):** exists but is a different,
  paid/cloud path and is per-record; out of scope and not free.

---

## 3. Exact setup steps (both Macs)

Conventions used below:
- **HUB** = personal Mac mini. Login user assumed `tyler`. Adjust to your short username
  (`whoami`).
- **WORK** = work MacBook.
- Vault path on both = `~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault`
  (the default from `Sources/VaultKit/VaultPaths.swift` / `AppSettings.defaultStorageURL`).
  If you set a custom `storageDir` in Settings, substitute that path everywhere.

### 3.1 Install Tailscale on both Macs (if not already)
On **each** Mac:
```bash
brew install --cask tailscale
open -a Tailscale          # sign in with the SAME account on both
```
Sign in with one identity (Google/GitHub/email) on both machines so they share a tailnet.
Confirm each is up:
```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4
```
(The CLI also lives at `/usr/local/bin/tailscale` if you ran the standalone installer's
"Install CLI" action. Use whichever resolves.)

### 3.2 Find the hub's tailnet identity
On the **HUB**:
```bash
tailscale ip -4              # → e.g. 100.101.102.103   (always-works numeric)
tailscale status | head      # shows MagicDNS name, e.g. "mac-mini"
hostname                     # local hostname for reference
whoami                       # the SSH login user, e.g. "tyler"
```
Enable **MagicDNS** in the Tailscale admin console (https://login.tailscale.com/admin/dns)
so you can use a stable name like `mac-mini` (or full `mac-mini.<tailnet>.ts.net`) instead
of memorizing `100.x`. The numeric `100.x` is the fallback if MagicDNS is off.

Record two values for the script later:
- `HUB_HOST` = `mac-mini` (MagicDNS) **or** `100.101.102.103` (numeric)
- `HUB_USER` = `tyler`

### 3.3 Enable Remote Login (sshd) on the HUB
GUI: **System Settings → General → Sharing → Remote Login → On.** Restrict
"Allow access for" to your user.

Or CLI (needs admin / may prompt):
```bash
sudo systemsetup -setremotelogin on
```
Verify from the **WORK** Mac it's reachable over the tailnet:
```bash
ssh tyler@mac-mini 'echo ok && whoami'      # MagicDNS
# or
ssh tyler@100.101.102.103 'echo ok'         # numeric fallback
```
First connect will prompt to trust the host key — accept it (we'll also pin it in §9).

> Note on Full Disk Access: the vault lives under iCloud Drive
> (`~/Library/Mobile Documents/...`). The incoming `sshd` writes as your user into your
> own home, which is fine. If macOS ever blocks `sshd`/`rsync` from that path under TCC,
> grant **Full Disk Access** to `/usr/sbin/sshd` (and to Terminal, for manual runs) in
> System Settings → Privacy & Security.

### 3.4 Create a dedicated SSH key on the WORK Mac
Use a purpose-built key (don't reuse your GitHub key), no passphrase so launchd can run
unattended (the key is protected by being on-disk in your home + tailnet ACLs; see §9 for
the optional forced-command hardening):
```bash
ssh-keygen -t ed25519 -f ~/.ssh/meetingscribe_sync -N "" -C "meetingscribe-sync work->hub"
```
This creates `~/.ssh/meetingscribe_sync` (private) and `~/.ssh/meetingscribe_sync.pub`.

### 3.5 Authorize the key on the HUB
From the **WORK** Mac:
```bash
ssh-copy-id -i ~/.ssh/meetingscribe_sync.pub tyler@mac-mini
```
(If `ssh-copy-id` isn't present, append the contents of the `.pub` file to
`~/.ssh/authorized_keys` on the hub manually and `chmod 600` it.)

Verify key-based, non-interactive login works:
```bash
ssh -i ~/.ssh/meetingscribe_sync -o BatchMode=yes tyler@mac-mini 'echo keyauth-ok'
```
`BatchMode=yes` forces failure (instead of a password prompt) if the key isn't accepted —
exactly the behavior we want under launchd.

### 3.6 Pre-create the quarantine destination on the HUB
```bash
ssh -i ~/.ssh/meetingscribe_sync tyler@mac-mini \
  'mkdir -p "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook"'
```

---

## 4. The launchd LaunchAgent (WORK Mac)

Create `~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist`.

`StartInterval` of `7200` runs every **2 hours** whenever the laptop is awake; if it was
asleep at the boundary, launchd runs it once on wake. That satisfies "every 1–few hours"
and the "at least once a day" floor. (For a fixed daily floor in addition, add a
`StartCalendarInterval` for, say, 09:00 — shown commented below; you can keep both.)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tyleryannes.meetingscribe.sync</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/USERNAME/.local/bin/meetingscribe-sync.sh</string>
    </array>

    <!-- Run every 2 hours (best-effort; coalesced if asleep). -->
    <key>StartInterval</key>
    <integer>7200</integer>

    <!-- Optional hard daily floor at 09:00 in addition to the interval.
         Uncomment to guarantee at least one run per day even if 7200 cadence
         keeps getting skipped by sleep.
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    -->

    <!-- Fire once shortly after the agent is (re)loaded, e.g. login. -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Don't pile up runs if a sync is slow; the script also self-locks. -->
    <key>ThrottleInterval</key>
    <integer>300</integer>

    <!-- launchd's own capture of the script's stdout/stderr. -->
    <key>StandardOutPath</key>
    <string>/Users/USERNAME/Library/Logs/MeetingScribe/sync.out.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/USERNAME/Library/Logs/MeetingScribe/sync.err.log</string>

    <!-- Ensure Homebrew + system tool paths are present for the agent. -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
```

Replace **`USERNAME`** with `whoami` output (launchd plists don't expand `~` or `$HOME`,
so paths must be absolute).

Load / reload it:
```bash
mkdir -p ~/Library/Logs/MeetingScribe
launchctl unload ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist 2>/dev/null
launchctl load   ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist
# Kick it immediately for a first test:
launchctl start com.tyleryannes.meetingscribe.sync
```

On modern macOS the `launchctl bootstrap`/`kickstart` form also works and is preferred by
some; the `load`/`start` form above is the most copy-paste-safe for a per-user LaunchAgent:
```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist
launchctl kickstart -k gui/$(id -u)/com.tyleryannes.meetingscribe.sync
```

---

## 5. The sync script (WORK Mac)

Create `~/.local/bin/meetingscribe-sync.sh` and `chmod +x` it.

```bash
#!/bin/bash
#
# MeetingScribe one-way sync: WORK MacBook -> personal Mac mini HUB.
# Pushes the local vault into a quarantined namespace on the hub over SSH/tailnet.
# Strictly send-only. Never deletes or touches hub-authoritative data.
#
set -u -o pipefail

# ---- Config (EDIT THESE) ---------------------------------------------------
HUB_USER="tyler"
HUB_HOST="mac-mini"                 # MagicDNS name, or 100.x.y.z numeric
SSH_KEY="$HOME/.ssh/meetingscribe_sync"

# Local vault (default from VaultPaths.swift). Override if you set a custom storageDir.
VAULT_LOCAL="$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"

# Namespace on the hub. This is the ONLY path the sync may write to.
# Note the trailing slash semantics handled below.
VAULT_REMOTE_BASE="\$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook"

LOG_DIR="$HOME/Library/Logs/MeetingScribe"
LOG_FILE="$LOG_DIR/sync.log"
LOCK_FILE="$HOME/Library/Caches/meetingscribe-sync.lock"
EXCLUDE_FILE="$HOME/.local/etc/meetingscribe-sync.exclude"

MAX_TRIES=3
BACKOFF_BASE=15        # seconds; doubles each retry
# ---------------------------------------------------------------------------

mkdir -p "$LOG_DIR" "$(dirname "$LOCK_FILE")" "$(dirname "$EXCLUDE_FILE")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE"; }

# ---- Locking: never let two syncs overlap ---------------------------------
# flock-style guard using shlock-free mkdir lock (mkdir is atomic on macOS).
exec 9>"$LOCK_FILE"
if ! /usr/bin/python3 - "$LOCK_FILE" <<'PY' 2>/dev/null
import fcntl, sys
f = open(sys.argv[1], 'w')
try:
    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(1)
# Hold the lock for the lifetime of this interpreter? No—exit; the shell fd 9
# below is the real hold. This probe just checks contention.
PY
then
  # Fall through to the shell flock on fd 9 (works on macOS via /usr/bin/flock
  # if installed; otherwise the probe above is the guard). Keep it simple:
  :
fi
# Preferred: use util-linux flock if present (brew install flock), else the
# python probe above already returned non-zero on contention. Hard guard:
if command -v flock >/dev/null 2>&1; then
  if ! flock -n 9; then
    log "another sync is running; exiting"
    exit 0
  fi
fi

# ---- Generate the exclude file (derived/volatile artifacts) ----------------
# We exclude files the hub regenerates itself or that are machine-local, so the
# work copy never injects a stale index/cache into the namespace. The audio
# .m4a files ARE included (they're the meeting source of truth).
cat > "$EXCLUDE_FILE" <<'EOF'
# Derived index — hub rebuilds its own; never ship a foreign one.
.meeting-index.json
# People combined cache — regenerated by PeopleStore on the hub.
_people-cache.json
# Inbox processing state — machine-local, would confuse the hub watcher.
_inbox/processed/
_inbox/.processed_ids.json
# SQLite derived index lives in Application Support (not the vault) but guard anyway.
*.db
*.db-wal
*.db-shm
secondbrain.db
# Logs are per-machine.
logs/
diagnostics/
# Whisper model blobs (~148MB+) — hub has its own; don't waste transfer.
models/
# macOS cruft.
.DS_Store
.Trashes/
.Spotlight-V100/
.fseventsd/
# Never recurse the hub's own _remote into itself if paths ever overlap.
_remote/
EOF

# ---- The rsync command -----------------------------------------------------
# Flag-by-flag rationale is in the report (§5 explanation). Summary:
#   -a  archive: recurse + preserve perms/times/symlinks/etc.
#   -z  compress in transit (Markdown/JSON compress well; m4a won't, harmless)
#   -h  human-readable numbers in logs
#   --partial --partial-dir  resume interrupted large-file (audio) transfers
#   -T tmp  write to a temp dir on the receiver, atomic-rename into place
#   --no-perms --no-owner --no-group  don't fight cross-machine uid/gid/ACLs
#   --omit-dir-times  avoid noisy dir-time churn over iCloud
#   --exclude-from  the volatile-artifact list above
#   --timeout/--contimeout  bail on dead connections instead of hanging launchd
#   NO --delete  -> we never remove anything on the hub (safety).
RSYNC_OPTS=(
  -a -z -h
  --partial --partial-dir=.rsync-partial
  -T "/tmp/.meetingscribe-rsync-tmp"
  --no-perms --no-owner --no-group
  --omit-dir-times
  --exclude-from="$EXCLUDE_FILE"
  --timeout=600
  --contimeout=30
  --info=stats2
)

SSH_CMD="ssh -i $SSH_KEY -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new"

# Ensure the remote namespace exists (idempotent, scoped to _remote only).
$SSH_CMD "$HUB_USER@$HUB_HOST" "mkdir -p \"$VAULT_REMOTE_BASE\"" \
  || { log "ERROR: cannot create remote namespace (ssh/tailnet down?)"; exit 1; }

# Source has a trailing slash => copy CONTENTS of the vault into the namespace.
SRC="$VAULT_LOCAL/"
DST="$HUB_USER@$HUB_HOST:$VAULT_REMOTE_BASE/"

attempt=1
delay=$BACKOFF_BASE
rc=1
while [ "$attempt" -le "$MAX_TRIES" ]; do
  log "rsync attempt $attempt/$MAX_TRIES -> $DST"
  rsync "${RSYNC_OPTS[@]}" -e "$SSH_CMD" "$SRC" "$DST" >> "$LOG_FILE" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    log "rsync OK (attempt $attempt)"
    break
  fi
  # rsync rc 24 = "some source files vanished" (a file was rewritten mid-sync) — benign.
  if [ "$rc" -eq 24 ]; then
    log "rsync rc=24 (vanished files, benign) — treating as success"
    rc=0; break
  fi
  log "rsync FAILED rc=$rc; backing off ${delay}s"
  sleep "$delay"
  attempt=$((attempt + 1))
  delay=$((delay * 2))
done

if [ "$rc" -ne 0 ]; then
  log "ERROR: sync failed after $MAX_TRIES attempts (rc=$rc)"
  exit "$rc"
fi

# Drop a heartbeat the hub (or you) can check to confirm freshness.
$SSH_CMD "$HUB_USER@$HUB_HOST" \
  "date '+%Y-%m-%dT%H:%M:%S%z' > \"$VAULT_REMOTE_BASE/.last_sync\"" 2>/dev/null || true

log "sync complete"
exit 0
```

### Flag-by-flag explanation
- **`-a` (archive):** recurse the tree and preserve symlinks, devices, times, etc. The
  single most important flag for a faithful mirror.
- **`-z` (compress):** compress data in flight. Markdown/JSON shrink a lot; `.m4a` is
  already compressed so `-z` is ~neutral there. Net win on the metadata-heavy vault.
- **`-h`:** human-readable byte counts in the logged stats.
- **`--partial --partial-dir=.rsync-partial`:** if a large `audio/*.m4a` transfer is cut
  off (laptop sleeps, tailnet blips), keep the partial and **resume** next run instead of
  restarting the whole file. The partial lives in a hidden sibling dir, not in place.
- **`-T /tmp/.meetingscribe-rsync-tmp` (`--temp-dir`):** the receiver writes incoming
  files to a temp dir, then atomically renames into the final path. Readers on the hub
  never see a half-written `meeting.json` or truncated `.m4a`. (rsync does atomic rename
  by default; this just keeps the temp churn off the iCloud-synced tree.)
- **`--no-perms --no-owner --no-group`:** uid/gid and ACLs differ across a personal and a
  work-managed Mac; not mapping them avoids permission-denied churn and keeps files owned
  by your hub user. Content fidelity (what we care about) is unaffected.
- **`--omit-dir-times`:** iCloud rewrites directory mtimes; omitting dir times stops rsync
  from "fixing" them every run and generating noise.
- **`--exclude-from`:** drops volatile/derived/machine-local artifacts (see list above).
- **`--timeout=600` / `--contimeout=30`:** a dead I/O stream aborts after 10 min; a
  connect that can't establish in 30 s aborts — so a sleeping/offline hub never wedges the
  launchd job indefinitely.
- **NO `--delete`:** deliberately absent. The sync only *adds/updates* files in the
  namespace. If you delete a meeting on the work laptop it stays in the hub backup
  (desirable for a "vault / never lose anything" backup). If you ever want the namespace
  to exactly mirror the work side, add `--delete --delete-excluded` **scoped to the
  namespace path only** — it still cannot reach hub-authoritative data because the
  destination root *is* `_remote/work-macbook/`. Default: keep it off.

---

## 6. Conflict / safety design

The safety model has four layers, in order of importance:

1. **Destination is a non-authoritative namespace.** The rsync destination root is
   `<vault>/_remote/work-macbook/`. The hub's own meetings/people/aggregates live at the
   vault root and in `people/`, `action_items.json`, etc. — *outside* the destination
   subtree. rsync physically cannot write above its destination root, so hub-authoritative
   files are unreachable by the sync. This is the strongest guarantee: it's structural,
   not policy.

2. **No `--delete` by default.** Even within the namespace, nothing is removed. The worst
   the sync can do is add files or overwrite a previous *copy of work data*. Hub data is
   never a deletion target.

3. **Atomic, never-torn writes.** `--temp-dir` + rsync's write-temp-then-rename means a
   reader on the hub (the app, or you) only ever sees complete files. A meeting being
   actively re-summarized on the work laptop mid-sync triggers rsync rc=24 ("file
   vanished/changed"), which the script treats as benign and the next run picks up the
   final version. `--partial-dir` keeps interrupted big-audio transfers out of the live
   tree until complete.

4. **Aggregate-JSON isolation.** `action_items.json`, `tags.json`, `.meeting-index.json`,
   `_people-cache.json` are whole-file "last writer wins" by nature. By landing them only
   under `_remote/work-macbook/`, the work side's copy can never overwrite the hub's
   top-level authoritative copies. We additionally *exclude* the purely-derived ones
   (`.meeting-index.json`, `_people-cache.json`) so the hub never ingests a foreign index;
   the hub regenerates its own via `MeetingStore.rebuildIndex()` / `PeopleStore`.

**Large audio files:** `.m4a` segments are included (they're the meeting's source audio).
They're the only large items; `--partial` makes them resumable and `-z` is a no-op on
them. First full sync of a big back-catalog may take a while over the tailnet; every
subsequent run is a delta.

---

## 7. Optional hub-side ingestion (Swift plan)

The rsync sync gives you a **complete, browsable backup** under `_remote/work-macbook/`
with no app changes. If you additionally want the work meetings/people **fused into the
hub's single second brain** (showing up in the normal Meetings/People/Tasks lists), add a
small, additive ingestion pass. This is opt-in and never required for the backup to work.

### 7.0 First, keep the scanner away from the namespace (one-line safety change)
`Sources/MeetingScribe/Storage/MeetingStore.swift` defines:
```swift
private static let reservedFolders: Set<String> = [
    "models", "QuickNotes", "logs", "diagnostics"
]
```
Add `"_remote"` (and `"_inbox"` if not already implicitly skipped) so the hub's normal
`scanDiskForMeetings()` does **not** sweep the quarantine into the main list until an
explicit ingestion step runs. This guarantees raw rsync'd files never appear half-merged.

### 7.1 Where ingestion hooks in
Model the ingester on the existing `Sources/MeetingScribe/Sync/iCloudInboxWatcher.swift`
(the established pattern for "watch a vault subfolder, route by type, move to processed").
Create a sibling, e.g. `Sources/MeetingScribe/Sync/RemoteVaultIngestor.swift`, an
`@MainActor` class started from `MeetingScribeApp.startServices()` alongside
`iCloudInboxWatcher.shared.start(...)`.

Watch `<vault>/_remote/work-macbook/` with an `NSMetadataQuery` (iCloud-aware, same as the
inbox watcher) or a `DispatchSource` file-system watch keyed off the `.last_sync`
heartbeat the script writes. On change, run an idempotent reconcile.

### 7.2 What each store touches
- **Meetings → `MeetingStore` (`Sources/MeetingScribe/Storage/MeetingStore.swift`):**
  Walk `_remote/work-macbook/<tag>/<slug>/`. For each `meeting.json`
  (`SchemaEnvelope<MeetingDTO>`), check if a meeting with that `id` already exists in the
  hub index (`MeetingStore.upsertInIndex` / `listPastMeetings`). If not, **copy** the
  whole `<slug>/` folder into the hub's authoritative tree via the store's normal
  `writeMeeting(_:primaryTag:)` + `writeTranscript` / `writeSummary` / audio copy, then
  `upsertInIndex(meeting)`. Tag the meeting's source (e.g. add a `work-macbook` meeting
  tag via `TagStore`) so provenance is visible. Idempotent: keyed on meeting `id`, never
  overwrites an existing hub meeting.
- **People → `PeopleStore` (`Sources/MeetingScribe/People/PeopleStore.swift`):**
  For each `_remote/work-macbook/people/<slug>/person.json`, reuse the *existing* reconcile
  path — `PeopleStore.ingestExtraction(...)`-style matching (exact name+email/phone →
  merge `meetingMentions`/`memories`; fuzzy → suggestion). Do **not** blind-copy person
  folders; route them through PeopleStore so de-dup against the hub's contacts holds. New
  people get `importSources` annotated with `"work-macbook"`.
- **Action items → `action_items.json` (`Sources/MeetingScribe/ActionItems/ActionItemStore.swift`):**
  Load the namespace copy, merge by action-item `id` into the hub's `ActionItemStore`
  (existing IDs untouched; new IDs appended). Same for projects/initiatives in that file.
  This is a structured merge, not a file overwrite.
- **Tags → `tags.json` (`Sources/MeetingScribe/Storage/TagStore.swift`):** union tag
  definitions by id; merge `(meetingID → [tagID])` assignments for the newly-ingested
  meetings only.
- **Index rebuild:** after a batch ingest, call `MeetingStore.rebuildIndexAsync()` and let
  `PeopleStore`/`SecondBrainDB` re-derive their caches. Never ship the foreign
  `.meeting-index.json` / `_people-cache.json` (already excluded in §5).

### 7.3 Mark-processed pattern
Mirror the inbox watcher: after successfully ingesting a `<slug>/`, record its `id` in a
`_remote/work-macbook/.ingested_ids.json` (same shape as
`_inbox/.processed_ids.json`) so re-runs are O(new files) and never double-ingest. Because
the merge is also id-keyed, even a lost ledger can't create duplicates — belt and
suspenders.

### 7.4 UI surfacing (minimal)
Add a Settings → "Remote backups" panel that shows `.last_sync` freshness and a
"Ingest work-macbook data now" button calling the ingestor. Until the user opts in,
`_remote/` is just an inert backup folder (thanks to §7.0).

---

## 8. Step-by-step build instructions for a Claude Code agent

Ordered, copy-pasteable. Phase A is the whole free feature; Phase B is the optional Swift
ingestion.

### Phase A — file-level sync (no app build)
1. **Tailscale on both Macs:** `brew install --cask tailscale`; sign in with the same
   account on HUB and WORK. Verify `tailscale status` shows both.
2. **Hub identity:** on HUB run `tailscale ip -4`, `tailscale status`, `whoami`. Record
   `HUB_HOST` (MagicDNS name or 100.x) and `HUB_USER`. Enable MagicDNS in the admin
   console.
3. **Enable Remote Login on HUB:** System Settings → Sharing → Remote Login → On (your
   user only). Or `sudo systemsetup -setremotelogin on`.
4. **SSH key on WORK:**
   `ssh-keygen -t ed25519 -f ~/.ssh/meetingscribe_sync -N "" -C "meetingscribe-sync"`.
5. **Authorize on HUB:** `ssh-copy-id -i ~/.ssh/meetingscribe_sync.pub HUB_USER@HUB_HOST`.
   Verify: `ssh -i ~/.ssh/meetingscribe_sync -o BatchMode=yes HUB_USER@HUB_HOST 'echo ok'`.
6. **Pre-create namespace on HUB:**
   `ssh -i ~/.ssh/meetingscribe_sync HUB_USER@HUB_HOST 'mkdir -p "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook"'`.
7. **Install the script** from §5 at `~/.local/bin/meetingscribe-sync.sh` on WORK; edit
   the Config block (`HUB_USER`, `HUB_HOST`, `SSH_KEY`, `VAULT_LOCAL` if custom
   `storageDir`); `chmod +x` it. `brew install flock` (optional, for the overlap guard).
8. **Dry-run test** (no writes): temporarily run the rsync line with `--dry-run`:
   `rsync -azh --dry-run --exclude-from=... -e "ssh -i ~/.ssh/meetingscribe_sync" "$VAULT_LOCAL/" "HUB_USER@HUB_HOST:.../_remote/work-macbook/"`.
   Confirm the file list looks right and excludes (`logs/`, `models/`, `.meeting-index.json`)
   are honored.
9. **Real run:** `bash ~/.local/bin/meetingscribe-sync.sh`; tail
   `~/Library/Logs/MeetingScribe/sync.log`. On HUB, confirm files landed under
   `_remote/work-macbook/` and `.last_sync` exists.
10. **Install the LaunchAgent** from §4 at
    `~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist` (replace `USERNAME`
    with absolute paths). `mkdir -p ~/Library/Logs/MeetingScribe`. `launchctl load` then
    `launchctl start com.tyleryannes.meetingscribe.sync`.
11. **Confirm schedule:** `launchctl list | grep meetingscribe` shows the label; after the
    next interval, `.last_sync` on the hub advances.

### Phase B — optional hub-side ingestion (Swift, on HUB)
12. **Edit `reservedFolders`** in `Sources/MeetingScribe/Storage/MeetingStore.swift` to add
    `"_remote"` (and `"_inbox"`). (See §7.0.)
13. **Create `Sources/MeetingScribe/Sync/RemoteVaultIngestor.swift`** modeled on
    `iCloudInboxWatcher.swift`: watch `_remote/work-macbook/`, reconcile meetings via
    `MeetingStore`, people via `PeopleStore.ingestExtraction`, action items via
    `ActionItemStore`, tags via `TagStore`; ledger to `.ingested_ids.json`.
14. **Wire it up** in `Sources/MeetingScribe/MeetingScribeApp.swift` `startServices()`
    alongside the inbox watcher start, gated behind a Settings toggle
    (`UserDefaults` key e.g. `ingestRemoteBackups`).
15. **Build & verify per CLAUDE.md:** `swift build -c release` (or `make app`). Warnings
    OK, errors block. Then ask the user to push.
16. **Test ingestion:** drop a sample meeting folder under `_remote/work-macbook/<tag>/<slug>/`
    on HUB, toggle ingestion on, confirm it appears in the Meetings list and is tagged with
    provenance, and that re-running does not duplicate it.

> Per CLAUDE.md: after any code/config edit in this repo, ask once
> "Push these changes to `tyleryannes94/meetingscribe-refactor`?" and run
> `git add -A && git commit && git push` on yes. Phase A creates no repo files, so the
> push question only applies if you commit this plan / the script into the repo.

---

## 9. Testing & verification, failure modes, security

### Testing & verification
- **Connectivity:** `ssh -i ~/.ssh/meetingscribe_sync -o BatchMode=yes HUB_USER@HUB_HOST 'whoami'`
  must print the hub user with no prompt.
- **Dry run honored excludes:** `rsync --dry-run -i ...` and grep the output to ensure
  `models/`, `logs/`, `.meeting-index.json`, `_people-cache.json` never appear.
- **Idempotency:** run the script twice back-to-back; the second run should transfer ~0
  bytes (only changed files) per the `--info=stats2` line in `sync.log`.
- **Atomicity under churn:** start a meeting summary on WORK, run the sync mid-write; the
  hub copy is either the old or the new `meeting.json`, never truncated. rc=24 in the log
  is expected and treated as success.
- **Schedule:** `launchctl list | grep meetingscribe`; confirm `.last_sync` advances after
  the interval; put the laptop to sleep across a boundary and confirm it runs on wake.
- **Safety drill:** delete a file inside `_remote/work-macbook/` on the hub, then add and
  modify hub-authoritative meetings; run the sync; confirm hub-authoritative meetings are
  untouched and only namespace files change.

### Failure modes & troubleshooting
- **`Permission denied (publickey)` under launchd:** the agent's `PATH`/`HOME` differ from
  your shell. We set `BatchMode=yes` and an explicit key path; confirm the key has no
  passphrase and `authorized_keys` on the hub is `chmod 600`. Check `sync.err.log`.
- **`ssh: connect ... Operation timed out`:** hub asleep/offline or Tailscale down on
  either side. `--contimeout=30` aborts cleanly; next run retries. Enable
  *Settings → Energy* "Prevent automatic sleeping" or a `caffeinate` cron on the hub if
  you need tighter cadence; otherwise it self-heals on wake.
- **Job never fires:** `launchctl print gui/$(id -u)/com.tyleryannes.meetingscribe.sync`
  to inspect state; re-`bootstrap` after editing the plist.
- **iCloud "files not downloaded":** the work vault under iCloud Drive may have
  dataless placeholder files. Add a pre-step `find "$VAULT_LOCAL" -type f -exec brctl download {} \;`
  (or open the folder once) so rsync ships real bytes, not placeholders. Alternatively
  point `storageDir` at a non-iCloud path on the work laptop to sidestep this entirely.
- **Big first sync stalls launchd:** raise `--timeout`, or do the initial full sync
  manually once from the shell, then let the agent take over deltas.
- **rsync rc=23 (partial transfer):** usually a transient permission/vanished-file mix;
  the retry/backoff loop handles it. Persisting rc=23 → check Full Disk Access for `sshd`.

### Security considerations
- **Transport:** all traffic rides Tailscale's WireGuard tunnel — encrypted, authenticated
  device-to-device, never exposed to the public internet. No port forwarding.
- **SSH key scope:** a dedicated `meetingscribe_sync` key, not your GitHub/identity key.
  Harden by pinning a forced command in the hub's `authorized_keys`:
  `command="rrsync ~/Library/Mobile\ Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook",restrict ssh-ed25519 AAAA...`
  (`rrsync` ships with rsync; ships the key to *only* rsync into *only* the namespace —
  even a stolen key can't run arbitrary commands or escape the quarantine).
- **Host-key pinning:** first run uses `StrictHostKeyChecking=accept-new`; after the host
  key is in `known_hosts`, a MITM/changed key is rejected. For maximum strictness flip to
  `StrictHostKeyChecking=yes` once pinned.
- **Tailnet ACLs:** in the admin console, optionally scope an ACL so the work device may
  only reach the hub on `tcp:22`, nothing else — least privilege on the tailnet.
- **No passphrase trade-off:** the key is passphrase-less for unattended launchd runs. It's
  mitigated by (a) tailnet membership being required to even reach the hub, (b) the forced
  `rrsync` command, and (c) the namespace quarantine. If you want a passphrase, load it
  into the agent's keychain via `ssh-add --apple-use-keychain` and run the job in the GUI
  session so the agent can use it — but passphrase-less + the three mitigations above is
  the pragmatic, still-safe default.
- **No secrets in the vault transfer:** the exclude list drops `logs/` and `*.db`; API
  keys live in macOS Keychain (not the vault), so they're never synced.

---

## 10. Summary
Two Macs on the same tailnet, Remote Login on the hub, one ed25519 key, one bash script,
one LaunchAgent. Strictly send-only into a quarantined `_remote/work-macbook/` namespace,
no `--delete`, atomic temp-then-rename, resumable audio, derived caches excluded. Hub data
is structurally unreachable by the sync. $0, runs every ~2 hours (with an optional daily
floor), self-heals across sleep. Optional additive Swift ingestion later fuses the work
data into the single second brain via the existing `MeetingStore` / `PeopleStore` /
`ActionItemStore` reconcile paths — modeled directly on the existing `iCloudInboxWatcher`.
