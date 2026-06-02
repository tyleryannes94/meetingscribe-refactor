# Agent 4 — Git-Relay Vault Sync (Work MacBook → Personal Mac mini Hub)

**Approach:** One-way vault sync via Git to a free private repo relay.
The work MacBook auto-commits its MeetingScribe vault (curated subset) on a
schedule and `git push`es to a private remote. The personal Mac mini ("hub")
only ever `git fetch` + hard-resets a **quarantined working copy** living
*inside* the hub vault at `_remote/work-macbook/`. The hub's own live vault data
is never touched, and the hub never pushes back — one-way is enforced
structurally, not by convention.

**Cost:** $0. **Cadence:** every 1–3 h via launchd (configurable down to
minutes). **Audio:** excluded from Git, shipped via a parallel rsync-over-Tailscale
side-channel (recommended) — keeps the repo small and history clean.

---

## 1. Overview & architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│ WORK MacBook                                                               │
│                                                                            │
│  Live vault (configurable via UserDefaults "storageDir")                   │
│   ~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/       │
│     <tag>/<slug>/  meeting.json transcript.md notes.md summary.md          │
│     people/<slug>/ person.json person.md                                   │
│     tags.json  action_items.json  encounters/  _recent.json               │
│     audio/*.m4a            ← NOT committed (see §4)                         │
│                                                                            │
│   ┌─ launchd: com.tyleryannes.meetingscribe.gitpush  (every 1–3h) ──────┐  │
│   │  1. flock (no overlap)                                              │  │
│   │  2. git add -A     (vault .git lives in the vault root)             │  │
│   │  3. git commit -m "work-macbook sync <ISO8601> (<host>)"           │  │
│   │  4. git push  ───────────────────────────────┐  (retry w/ backoff) │  │
│   │  5. rsync -a --delete audio/  →  hub:audio/ ──┼──┐ (Tailscale SSH)  │  │
│   └────────────────────────────────────────────────┼──┼───────────────┘  │
└────────────────────────────────────────────────────┼──┼──────────────────┘
                                                      │  │
                          (a) private GitHub repo  ◄──┘  │ rsync side-channel
                          or (b) bare repo on hub        │ (audio only)
                                  via Tailscale SSH       │
                                                      │  │
┌─────────────────────────────────────────────────────▼──▼──────────────────┐
│ PERSONAL Mac mini  (HUB / vault / "second brain")                          │
│                                                                            │
│  Live hub vault (UNTOUCHED by sync):                                       │
│   ~/Library/Mobile Documents/.../MeetingScribeVault/                       │
│     <hub's own meetings, people, tags.json, action_items.json …>           │
│                                                                            │
│   ┌─ launchd: com.tyleryannes.meetingscribe.gitpull (every 1–3h) ───────┐  │
│   │  QUARANTINE — separate working copy, NEVER the live root:           │  │
│   │   …/MeetingScribeVault/_remote/work-macbook/                        │  │
│   │  1. git fetch origin                                                │  │
│   │  2. git reset --hard origin/main   (fast-forward-proof, one-way)    │  │
│   │  3. rsync target  …/_remote/work-macbook/<tag>/<slug>/audio/        │  │
│   └────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│   Optional in-app ingestion (§8): import _remote/work-macbook/* into the   │
│   MeetingStore / PeopleStore / action_items.json, rebuild .meeting-index.  │
└────────────────────────────────────────────────────────────────────────────┘
```

Key invariant: **the live vault root and the quarantine are different
directories.** `_remote/` is gitignored in the hub's *own* repo (if any) and is
the *only* place the pull job writes. The hub's MeetingStore root never sees the
work data unless an explicit, idempotent ingestion step copies it in.

---

## 2. Why Git is the right fit (and the honest cons)

The MeetingScribe vault is **plain, human-readable, grep-friendly files**:
Markdown (`transcript.md`, `notes.md`, `summary.md`, `person.md`) and
schema-versioned JSON (`meeting.json`, `person.json`, `tags.json`,
`action_items.json`) wrapped in `SchemaEnvelope<Payload>` `{version,data}`.
Verified in-repo:

- `Sources/VaultKit/VaultPaths.swift` → default vault
  `~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault`.
- `Sources/ScribeCore/AppSettings.swift` / main-app AppSettings →
  `storageDir` UserDefaults key overrides the path.
- `Sources/MeetingScribe/Storage/MeetingStore.swift` → per-meeting
  `<tag>/<slug>/`, derived `.meeting-index.json` at vault root.
- `Sources/MeetingScribeMCP/main.swift` → reads `tags.json`,
  `action_items.json`, `people/<slug>/person.json`.

Why Git wins:

- **Diff-native.** Each meeting note is a small text file; Git stores deltas and
  shows exactly what changed per sync. Perfect audit trail of every meeting.
- **Free private hosting.** GitHub private repos are unlimited and free; a bare
  repo over Tailscale costs nothing at all.
- **Full history + rollback.** Accidental deletion on the work side never
  destroys hub data — the hub keeps every prior commit; you can `git checkout`
  any past state.
- **One-way is trivial to enforce.** "Hub only ever `fetch` + `reset --hard`,
  never `push`." There is no write path back to work. No bidirectional merge
  engine to misbehave.
- **Robust conflict semantics / atomicity.** A push is all-or-nothing; a partial
  network failure leaves the remote at the previous good commit.

Honest cons (and how this plan addresses them):

- **Binary audio bloat.** `.m4a` files are large, opaque, and would balloon
  Git history forever. → **We exclude audio from Git** and ship it via rsync
  (§4). Repo stays text-only and tiny.
- **Not real-time.** Git push is batch, not streaming. → Fine: requirement is
  "daily, ideally every 1–few hours." launchd at 1–3 h satisfies it.
- **Merge edge cases.** Concurrent edits to the *same* aggregate file
  (`tags.json`) on both machines. → Irrelevant here because **the work repo is a
  single-writer push and the hub never edits the quarantine.** The hub's *own*
  vault is a physically separate directory, so there is nothing to merge.
- **Secrets risk.** Vault could theoretically contain a stray key. → §7 gitignore
  + secret-scan pre-push hook.

---

## 3. Two transport options (both free)

### (a) Private GitHub repo

- Create a **private** repo `meetingscribe-vault-relay` (separate from the code
  repo `tyleryannes94/meetingscribe-refactor`).
- **Auth: a per-machine deploy key with write access** (preferred over a PAT —
  scoped to exactly one repo, revocable, no account-wide blast radius).
  - Work MacBook gets a deploy key with **write** (it pushes).
  - Hub gets a deploy key with **read-only** (it only fetches) — this is a second
    structural guarantee of one-way.
- Pros: off-site backup (survives a house fire that takes both Macs),
  web UI to browse history, works even when Tailscale/hub is offline.
- Cons / caveats:
  - **GitHub blocks single files > 100 MB** and warns > 50 MB. Text vault files
    are tiny, so this is a non-issue *because we exclude audio*. If you ever
    chose to commit audio, you'd need **Git LFS**, whose free tier is only
    **1 GB storage + 1 GB/month bandwidth** — too small for ongoing audio. So:
    do **not** put audio in GitHub LFS for this use case.
  - Repo soft-cap ~5 GB recommended by GitHub; text-only we'll never approach it.

### (b) Self-hosted bare repo on the hub over Tailscale SSH (truly free, no third party)

- On the hub, create a bare repo: `~/MeetingScribeRelay/vault.git`.
- Work MacBook pushes over Tailscale SSH:
  `git remote add origin tyler@hub-tailscale-name:MeetingScribeRelay/vault.git`.
- Tailscale gives both Macs a stable private DNS name (MagicDNS, e.g.
  `mac-mini.tailnet-xxxx.ts.net`) and an always-on WireGuard tunnel — no port
  forwarding, no public exposure.
- Pros: **zero third parties, unlimited size**, the same Tailscale tunnel
  carries the audio rsync, lowest latency. Audio "just works" with no LFS.
- Cons: no off-site copy (if the hub dies, the only backup is the work clone +
  the hub's own vault); requires both machines on the tailnet for a sync to land.

### Recommendation

**Use (b) self-hosted bare repo over Tailscale as the primary**, because it is
unlimited, fully free, has no audio-size constraints, and reuses the single
Tailscale tunnel for both text (Git) and audio (rsync). It matches the user's
"FREE, no third party" preference and the M2 Mac mini is the always-on hub by
design.

**Optionally add (a) GitHub as a second push remote** for off-site disaster
recovery of the *text* vault only (`git remote set-url --add --push origin …`).
Both remotes receive the same commits; the hub still pulls from the bare repo.
This gives you off-site backup at no extra cost without sacrificing the
unlimited local path. The rest of this report assumes (b) primary with (a) as an
optional mirror, and notes where commands differ.

---

## 4. Audio strategy

**Decision: exclude audio from Git entirely; sync it with a parallel
rsync-over-Tailscale step.**

Rationale: `.m4a` are large append-only binaries that never diff well; in Git
they bloat history permanently (even after deletion, blobs persist in packs).
rsync transfers only changed/new files, supports `--delete` to mirror, and runs
over the same Tailscale tunnel. This keeps the relay repo pure text (fast clone,
clean diffs, GitHub-mirror-friendly) while still backing up every recording.

The vault repo `.gitattributes` (line-ending + safety; no LFS):

```gitattributes
# Treat known text vault files as text with LF endings (stable diffs).
*.md      text eol=lf
*.json    text eol=lf
*.txt     text eol=lf
# Binaries that should NEVER be diffed if one slips through .gitignore.
*.m4a     binary
*.wav     binary
*.bin     binary
*.png     binary
*.jpg     binary
```

The vault repo `.gitignore` (the repo that lives at the vault root — distinct
from the source-code repo's gitignore). Audio + derived caches excluded:

```gitignore
# ── Audio: shipped via rsync side-channel, NEVER via Git ──
*.m4a
*.wav
audio/
chunks/
**/chunks/__rolling/

# ── Derived / cache / index files (regenerated on each device) ──
.meeting-index.json
_people-cache.json
_inbox/processed/
_inbox/.processed_ids.json
logs/
*.log
models/*.bin
models/ggml-*.bin
_recent.json            # device-local iPhone-shortcut stub; regenerated

# ── Secrets / never commit (see §7) ──
*.p12
*.pem
*.cer
*.key
.env
secrets.json
**/*apikey*
**/*api_key*
**/*token*

# ── macOS junk ──
.DS_Store
._*
.Spotlight-V100
.Trashes

# ── The quarantine itself must never be re-committed if this repo is
#    ever cloned onto the hub side-by-side with its own vault. ──
_remote/
```

> If you instead chose the GitHub-only path *and* wanted audio off-site, the
> alternative is Git LFS — but its 1 GB free quota makes it unsuitable for
> continuous audio. Stick with rsync.

---

## 5. Work-side automation

### 5.1 Push script — `~/bin/meetingscribe-vault-push.sh`

```bash
#!/bin/bash
# meetingscribe-vault-push.sh
# One-way push of the MeetingScribe vault (text via Git, audio via rsync)
# from the work MacBook to the hub relay. Idempotent, lock-protected, retrying.
set -u

# ── Config ───────────────────────────────────────────────────────────────────
# Resolve the live vault exactly as the app does: UserDefaults "storageDir"
# (Sources/ScribeCore/AppSettings.swift) with the iCloud default fallback.
STORAGE_DIR="$(defaults read com.tyleryannes.MeetingScribe storageDir 2>/dev/null)"
if [ -z "${STORAGE_DIR}" ]; then
  STORAGE_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"
fi
VAULT="${STORAGE_DIR}"

# Hub over Tailscale (option b). Set to your MagicDNS name.
HUB_SSH="tyler@mac-mini.tailnet-xxxx.ts.net"
HUB_AUDIO_DEST="${HUB_SSH}:MeetingScribeRelay/audio-mirror/"
GIT_BRANCH="main"

LOCK="/tmp/meetingscribe-vault-push.lock"
LOG="${HOME}/Library/Logs/meetingscribe-vault-push.log"
MAX_RETRIES=4

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"; }

# ── Lock: never overlap two syncs ─────────────────────────────────────────────
exec 9>"$LOCK"
if ! /usr/bin/flock -n 9; then
  log "another push is running; exiting"
  exit 0
fi

[ -d "$VAULT" ] || { log "vault not found at $VAULT"; exit 1; }
cd "$VAULT" || { log "cannot cd to vault"; exit 1; }

# ── First-run: ensure this vault is a git repo wired to the relay ─────────────
if [ ! -d "$VAULT/.git" ]; then
  log "initializing git repo in vault"
  git init -q
  git checkout -q -b "$GIT_BRANCH" 2>/dev/null || git branch -m "$GIT_BRANCH"
  git remote add origin "${HUB_SSH}:MeetingScribeRelay/vault.git"
  # (.gitignore / .gitattributes should already be present — see §9.)
fi

# ── Stage + commit (skip cleanly when nothing changed) ────────────────────────
git add -A
if git diff --cached --quiet; then
  log "no changes to commit"
else
  STAMP="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
  git commit -q -m "work-macbook sync ${STAMP} (${HOST})" \
    || { log "commit failed"; exit 1; }
  log "committed work changes"
fi

# ── Push text with retry + exponential backoff ────────────────────────────────
attempt=1; delay=5; pushed=0
while [ "$attempt" -le "$MAX_RETRIES" ]; do
  if git push -q origin "$GIT_BRANCH"; then
    log "git push ok (attempt ${attempt})"; pushed=1; break
  fi
  log "git push failed (attempt ${attempt}); sleeping ${delay}s"
  sleep "$delay"; attempt=$((attempt+1)); delay=$((delay*2))
done
[ "$pushed" -eq 1 ] || { log "git push gave up after ${MAX_RETRIES} attempts"; }

# ── Audio side-channel: rsync only changed .m4a, mirror with --delete ─────────
# -a archive, -z compress, --delete mirror, --partial resume, prune empty dirs.
attempt=1; delay=5
while [ "$attempt" -le "$MAX_RETRIES" ]; do
  if rsync -az --delete --partial --prune-empty-dirs \
        --include='*/' \
        --include='*.m4a' --include='*.wav' \
        --exclude='*' \
        -e ssh \
        "${VAULT}/" "${HUB_AUDIO_DEST}"; then
    log "rsync audio ok (attempt ${attempt})"; break
  fi
  log "rsync audio failed (attempt ${attempt}); sleeping ${delay}s"
  sleep "$delay"; attempt=$((attempt+1)); delay=$((delay*2))
done

log "push cycle complete"
exit 0
```

Notes:
- `defaults read com.tyleryannes.MeetingScribe storageDir` matches the bundle id
  `com.tyleryannes.MeetingScribe` and the `storageDir` key in
  `AppSettings.swift`, so the script always tracks the same vault the app uses.
- rsync mirrors audio into a **separate** `audio-mirror/` tree on the hub
  (parallel to `vault.git`), preserving the `<tag>/<slug>/audio/*.m4a` layout so
  ingestion (§8) can rejoin text + audio by relative path.
- `--delete` makes audio a true mirror of the work side. If you prefer
  append-only audio backup (never delete on hub), drop `--delete`.

### 5.2 LaunchAgent — `~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpush.plist`

Runs every 2 hours (`StartInterval` 7200 s) **and** at load/login, so an
overnight-asleep Mac syncs on wake.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tyleryannes.meetingscribe.gitpush</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/tyler/bin/meetingscribe-vault-push.sh</string>
  </array>

  <!-- Every 2 hours. Use 3600 for hourly, 10800 for 3h. -->
  <key>StartInterval</key>
  <integer>7200</integer>

  <!-- Also run once when the agent is (re)loaded, e.g. on login/wake. -->
  <key>RunAtLoad</key>
  <true/>

  <!-- Coalesce missed runs (e.g. laptop was asleep) into one on wake. -->
  <key>StartOnMount</key>
  <false/>

  <key>StandardOutPath</key>
  <string>/Users/tyler/Library/Logs/meetingscribe-vault-push.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/tyler/Library/Logs/meetingscribe-vault-push.err.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <!-- Don't hammer CPU; sync is I/O bound. -->
  <key>ProcessType</key>
  <string>Background</string>
  <key>LowPriorityIO</key>
  <true/>
</dict>
</plist>
```

Load it:

```bash
launchctl unload ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpush.plist 2>/dev/null
launchctl load   ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpush.plist
launchctl start  com.tyleryannes.meetingscribe.gitpush   # fire once now
```

> `StartInterval` timers do **not** fire while asleep; the missed run coalesces
> into a single execution on wake, plus `RunAtLoad` covers login. For
> wake-from-sleep precision you could instead use `StartCalendarInterval` with
> `pmset` scheduled wakes, but for "every 1–3 h backup" `StartInterval` is
> simpler and sufficient.

---

## 6. Hub-side automation

The hub runs the bare repo (push target) **and** a pull job that materializes a
read-only working copy into the quarantine. The quarantine is the **only** thing
the hub writes; the hub's live vault is never touched.

### 6.1 Pull script — `~/bin/meetingscribe-vault-pull.sh`

```bash
#!/bin/bash
# meetingscribe-vault-pull.sh
# Hub side. Materialize the work MacBook's relay into a QUARANTINED working copy
# inside the hub vault at _remote/work-macbook/. ONE-WAY: fetch + hard reset only.
set -u

HUB_STORAGE="$(defaults read com.tyleryannes.MeetingScribe storageDir 2>/dev/null)"
if [ -z "${HUB_STORAGE}" ]; then
  HUB_STORAGE="${HOME}/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"
fi

# Quarantine lives INSIDE the hub vault but is a SEPARATE directory from any
# live meeting/people data. It is gitignored in the hub's own repo (if any).
QUARANTINE="${HUB_STORAGE}/_remote/work-macbook"
BARE="${HOME}/MeetingScribeRelay/vault.git"      # local bare repo on the hub
AUDIO_SRC="${HOME}/MeetingScribeRelay/audio-mirror"   # rsync landing zone
GIT_BRANCH="main"

LOCK="/tmp/meetingscribe-vault-pull.lock"
LOG="${HOME}/Library/Logs/meetingscribe-vault-pull.log"
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"; }

exec 9>"$LOCK"
/usr/bin/flock -n 9 || { log "pull already running; exit"; exit 0; }

# ── First-run: clone the bare repo into the quarantine working copy ───────────
if [ ! -d "${QUARANTINE}/.git" ]; then
  log "cloning relay into quarantine ${QUARANTINE}"
  mkdir -p "$(dirname "$QUARANTINE")"
  git clone -q "file://${BARE}" "$QUARANTINE" || { log "clone failed"; exit 1; }
  cd "$QUARANTINE" || exit 1
  # HARD one-way guard: remove any push capability from this working copy.
  git remote set-url --push origin DISABLED_NO_PUSH
fi

cd "$QUARANTINE" || { log "cannot cd quarantine"; exit 1; }

# ── One-way pull: fetch then HARD RESET to remote. Never merge, never push. ───
# This means even if someone hand-edits the quarantine, the work side always
# wins and the hub never tries to send anything back.
if git fetch -q origin "$GIT_BRANCH"; then
  git reset --hard "origin/${GIT_BRANCH}" -q && log "fetched + reset to origin/${GIT_BRANCH}"
  git clean -fdq -e audio -e '*.m4a'    # drop stray files, but keep synced audio
else
  log "fetch failed; leaving quarantine at previous good state"
fi

# ── Pull audio from the rsync landing zone into the quarantine tree ───────────
# audio-mirror mirrors <tag>/<slug>/audio/*.m4a; rejoin into the working copy so
# each meeting dir has both text (from Git) and audio (from rsync).
if [ -d "$AUDIO_SRC" ]; then
  rsync -a --include='*/' --include='*.m4a' --include='*.wav' --exclude='*' \
        "${AUDIO_SRC}/" "${QUARANTINE}/" && log "audio merged into quarantine"
fi

log "pull cycle complete"
exit 0
```

**Why this can never clobber hub data:**
1. `QUARANTINE` is a distinct directory (`_remote/work-macbook/`); the hub's live
   meetings live at the vault root and in `people/`, `<tag>/…` — different paths.
2. The hub working copy's push URL is set to `DISABLED_NO_PUSH`, so an accidental
   `git push` errors out instead of writing to the relay.
3. The hub's GitHub deploy key (if mirroring) is **read-only**.
4. The only mutation the script makes is to `_remote/work-macbook/` — confirmed
   by every write path in the script being rooted under `$QUARANTINE`.

### 6.2 Bare repo + landing zone setup (one-time, on the hub)

```bash
mkdir -p ~/MeetingScribeRelay
git init --bare ~/MeetingScribeRelay/vault.git
( cd ~/MeetingScribeRelay/vault.git && git symbolic-ref HEAD refs/heads/main )
mkdir -p ~/MeetingScribeRelay/audio-mirror
```

### 6.3 LaunchAgent — `~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpull.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tyleryannes.meetingscribe.gitpull</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/tyler/bin/meetingscribe-vault-pull.sh</string>
  </array>
  <!-- Pull slightly more often than the push interval so data lands promptly.
       Push=7200s; pull=3600s keeps quarantine fresh. -->
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/tyler/Library/Logs/meetingscribe-vault-pull.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/tyler/Library/Logs/meetingscribe-vault-pull.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>ProcessType</key>
  <string>Background</string>
  <key>LowPriorityIO</key>
  <true/>
</dict>
</plist>
```

Load:

```bash
launchctl unload ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpull.plist 2>/dev/null
launchctl load   ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpull.plist
launchctl start  com.tyleryannes.meetingscribe.gitpull
```

---

## 7. Secrets & safety

**What must never be committed** (already partially covered by the source repo's
root `.gitignore`, mirrored into the vault repo `.gitignore` in §4):

- Keychain items / code-signing material: `*.p12 *.pem *.cer *.key`.
- API keys / tokens: `.env`, `secrets.json`, `**/*apikey*`, `**/*token*`.
- App secrets are stored in macOS Keychain and UserDefaults, **not** in the
  vault — verified: `AppSettings.swift` reads keys from `UserDefaults.standard`
  (e.g. `ollamaURL`, `whisperBinary`), none of which are written into vault
  files. So the vault is structurally low-risk, but we defend in depth anyway.

**Pre-push secret-scan hook** — install at the vault repo
`~/.../MeetingScribeVault/.git/hooks/pre-commit` (and/or `pre-push`):

```bash
#!/bin/bash
# Block commits that look like they contain secrets.
if git diff --cached --name-only -z | xargs -0 grep -lEI \
   '(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN .*PRIVATE KEY-----|api[_-]?key\s*[:=])' \
   2>/dev/null; then
  echo "❌ Possible secret detected in staged files. Commit aborted." >&2
  exit 1
fi
exit 0
```

`chmod +x` the hook. Verify nothing sensitive is already tracked:

```bash
cd "$VAULT" && git ls-files | grep -Ei '\.(p12|pem|cer|key)$|secret|token|apikey' || echo "clean"
```

**Private-repo settings (GitHub mirror path):** repo Visibility = Private;
enable **Push protection** + **Secret scanning** in repo Settings → Security;
use a **read-only** deploy key on the hub and a **write** deploy key on work.

**Namespace separation (personal vs work):** the hub quarantine path
`_remote/work-macbook/` is a sibling of the live data, not interleaved. Personal
meetings remain at the vault root / `people/`; work meetings stay confined to
`_remote/work-macbook/` until/unless explicit ingestion (§8) copies them in with
a `source: work-macbook` provenance tag. This keeps "what's mine" vs "what's
synced from work" auditable at the filesystem level.

---

## 8. Optional in-app ingestion (Swift plan)

Goal: surface `_remote/work-macbook/` meetings & people inside the hub's second
brain without polluting the live tree, mirroring the existing `_inbox/` ingestion
precedent (`Sources/MeetingScribe/Sync/iCloudInboxWatcher.swift`).

**New file:** `Sources/MeetingScribe/Sync/RemoteVaultImporter.swift`.

Responsibilities (idempotent, source-tagged, never destructive to hub data):

1. **Locate quarantine.**
   `let remoteRoot = AppSettings.shared.storageDir
        .appendingPathComponent("_remote/work-macbook", isDirectory: true)`.

2. **Walk meetings.** For each `<tag>/<slug>/meeting.json` under `remoteRoot`,
   decode via `SchemaEnvelope.decode(MeetingDTO.self, …)` (same path used in
   `Sources/MeetingScribeMCP/main.swift:104`). Stamp an importer field, e.g.
   `meeting.source = "work-macbook"`, to keep provenance.

3. **Import into MeetingStore.** Reuse
   `Sources/MeetingScribe/Storage/MeetingStore.swift`:
   - `writeMeeting(_:primaryTag:)` to materialize into the live tree (writes the
     `SchemaEnvelope` per `writeMeetingFile`), or keep them quarantined and only
     register their relative paths in the in-memory index.
   - Dedupe by `meeting.id` against `listPastMeetings()` so re-running is a
     no-op. Copy associated `transcript.md`/`notes.md`/`summary.md` via
     `writeTranscript`/`writeUserNotes`/`writeSummary`.
   - Copy `audio/*.m4a` (present in the quarantine because the pull job rsynced
     it) into the meeting dir.

4. **Import people.** For each `_remote/work-macbook/people/<slug>/person.json`,
   decode (`PersonDTO`, per MCP `main.swift:346`) and upsert through
   `Sources/MeetingScribe/People/PeopleStore.swift`. Merge by person `slug`;
   union encounter records rather than overwrite, so a person who appears in both
   personal and work meetings keeps a unified record. Then call
   `PeopleStore.rebuildIndex()` (line 142) / `rebuildIndexIfNeeded()`.

5. **Merge `action_items.json`.** Load the hub's
   `storageDir/action_items.json` and the quarantine's copy (both are
   `SchemaEnvelope`-wrapped arrays — see MCP `main.swift:198,252`). Union by
   action-item id; never drop hub-native items. Write back via the same
   `coordinatedWrite` mechanism used elsewhere in MeetingStore.

6. **Merge `tags.json`.** Union tag definitions (`TagStore`,
   `Sources/MeetingScribe/Storage/TagStore.swift:40`) so work-only tags appear in
   the hub's tag list; conflicts resolve hub-wins on display name.

7. **Rebuild the derived index.** After import, force a rescan:
   `MeetingStore.listPastMeetings(forceRescan: true)` to regenerate
   `.meeting-index.json` (the `IndexFile` at vault root, MeetingStore lines
   ~419), and the SQLite `secondbrain.db` index via `PeopleStore.rebuildIndex()`.

8. **Trigger.** Either (a) a `FileSystemEventStream`/`NSMetadataQuery` watcher on
   `_remote/work-macbook/` modeled on `iCloudInboxWatcher.start(vaultURL:)`, or
   (b) a manual "Import work meetings" button in the hub Settings/Sync UI that
   calls `RemoteVaultImporter.run()`. Recommend (b) first (explicit, safe), then
   add (a) once verified.

All imports are **additive and idempotent**: dedupe-by-id, union-merge
aggregates, hub-wins on conflicts. The hub's own meetings/people/action items are
never deleted or overwritten.

---

## 9. Step-by-step build instructions for Claude Code

> Planning only — these are the exact, ordered, copy-pasteable steps to execute
> on the two machines. No source files are modified by this report.

### A. Hub (Mac mini) — one-time

```bash
# 1. Tailscale up (if not already) and note the MagicDNS name.
tailscale status
# 2. Bare relay repo + audio landing zone.
mkdir -p ~/MeetingScribeRelay
git init --bare ~/MeetingScribeRelay/vault.git
( cd ~/MeetingScribeRelay/vault.git && git symbolic-ref HEAD refs/heads/main )
mkdir -p ~/MeetingScribeRelay/audio-mirror
# 3. Drop the pull script + plist (full contents in §6).
mkdir -p ~/bin ~/Library/Logs ~/Library/LaunchAgents
#   (write ~/bin/meetingscribe-vault-pull.sh  — §6.1)
#   (write ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpull.plist — §6.3)
chmod +x ~/bin/meetingscribe-vault-pull.sh
launchctl load ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpull.plist
```

### B. Work MacBook — one-time

```bash
# 1. Tailscale up; confirm you can ssh the hub.
ssh tyler@mac-mini.tailnet-xxxx.ts.net 'echo hub-reachable'
# 2. Resolve the vault path and add the relay files INSIDE it.
VAULT="$(defaults read com.tyleryannes.MeetingScribe storageDir 2>/dev/null)"
[ -z "$VAULT" ] && VAULT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault"
#   (write "$VAULT/.gitignore"      — §4)
#   (write "$VAULT/.gitattributes"  — §4)
#   (write "$VAULT/.git/hooks/pre-commit" — §7 ; chmod +x after git init)
# 3. Drop push script + plist.
mkdir -p ~/bin ~/Library/Logs ~/Library/LaunchAgents
#   (write ~/bin/meetingscribe-vault-push.sh  — §5.1)
#   (write ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpush.plist — §5.2)
chmod +x ~/bin/meetingscribe-vault-push.sh
# 4. Initialize + first push (the script self-inits git on first run):
bash ~/bin/meetingscribe-vault-push.sh
chmod +x "$VAULT/.git/hooks/pre-commit"
# 5. Load the timer.
launchctl load ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.gitpush.plist
launchctl start com.tyleryannes.meetingscribe.gitpush
```

### C. Optional GitHub mirror (off-site text backup)

```bash
gh repo create meetingscribe-vault-relay --private --confirm
# Add as an extra PUSH url on the work side (same branch, both remotes receive):
cd "$VAULT"
git remote set-url --add --push origin git@github.com:tyleryannes94/meetingscribe-vault-relay.git
git remote set-url --add --push origin tyler@mac-mini.tailnet-xxxx.ts.net:MeetingScribeRelay/vault.git
# Generate a write deploy key for work, read-only deploy key for hub, install in repo Settings → Deploy keys.
```

### D. New doc to author: `docs/CROSS_DEVICE_SYNC.md`

Create `docs/CROSS_DEVICE_SYNC.md` summarizing: architecture diagram (§1), the
two scripts' locations, the launchd labels, how to pause sync
(`launchctl unload …`), where logs live (`~/Library/Logs/meetingscribe-vault-*`),
and the one-way / quarantine guarantees. Cross-link from `README.md`.

---

## 10. Testing, verification, failure modes, security

### Test the full loop

```bash
# WORK: create a throwaway meeting note in the vault, then force a push.
echo "# test $(date)" > "$VAULT/_test/$(date +%s)/notes.md"   # any <tag>/<slug>
bash ~/bin/meetingscribe-vault-push.sh
tail -n 20 ~/Library/Logs/meetingscribe-vault-push.log

# HUB: force a pull and confirm the note arrives in the QUARANTINE (not live).
bash ~/bin/meetingscribe-vault-pull.sh
ls -R "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook/_test"
tail -n 20 ~/Library/Logs/meetingscribe-vault-pull.log
```

Verification checklist:
- [ ] Note appears under `_remote/work-macbook/…`, **not** at the hub vault root.
- [ ] Hub's own meetings unchanged (`git -C "$VAULT" status` on hub shows no
      deletions of live data; the quarantine is the only changed path).
- [ ] `.m4a` files arrive via rsync into `…/audio/`, and are **absent** from
      `git log --stat` on the relay (text-only history).
- [ ] Re-running push with no changes logs "no changes to commit" and pushes
      nothing.
- [ ] `git -C "$QUARANTINE" remote get-url --push origin` → `DISABLED_NO_PUSH`.
- [ ] Pre-commit hook blocks a deliberately-planted fake `sk-...` key.

### Failure modes & troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Push hangs / "Permission denied (publickey)" | Tailscale down or SSH key not on hub | `tailscale status`; `ssh-copy-id` to hub; retry loop will back off |
| "non-fast-forward" on push | Someone pushed to relay out of band | Work is sole writer; if it happens, `git push --force-with-lease` (work owns the branch) |
| Quarantine has uncommitted junk | manual edits on hub | pull script's `git reset --hard` + `git clean` self-heals next cycle |
| Audio missing on hub | rsync leg failed (Git leg can succeed independently) | check pull/push logs; rerun script; rsync `--partial` resumes |
| Repo growing despite text-only | an `.m4a` slipped past `.gitignore` before it was added | `git rm --cached` the blob; consider `git filter-repo` to purge history |
| Laptop asleep, no syncs | `StartInterval` doesn't fire asleep | coalesced run on wake + `RunAtLoad`; acceptable for ≤3h SLA |
| Launchd job not running | wrong PATH / perms | check `~/Library/Logs/*.err.log`; ensure `EnvironmentVariables.PATH` includes `/opt/homebrew/bin` |

### Security summary

- **One-way enforced three ways:** quarantine is a separate dir; hub push URL is
  `DISABLED_NO_PUSH`; (GitHub path) hub deploy key is read-only.
- **No secrets in transit:** vault holds no keys (they live in Keychain/UserDefaults);
  `.gitignore` + pre-commit scan defend in depth; Tailscale encrypts all traffic
  end-to-end (WireGuard); GitHub mirror is private + push-protected.
- **Hub data integrity:** every write path in the pull script is rooted under
  `_remote/work-macbook/`; the live vault is never a target. Full Git history on
  the relay means any bad work-side state is rollback-able.
- **Disaster recovery:** primary = hub bare repo (always-on M2); optional GitHub
  mirror gives an off-site copy of the text vault.

---

### TL;DR recommendation

Self-hosted **bare Git repo over Tailscale SSH** for text + **rsync-over-Tailscale**
for audio, driven by launchd every 1–3 h, landing in a **quarantined
`_remote/work-macbook/` working copy** that the hub only ever `fetch`+`reset`s.
Fully free, no third party, unlimited size, hub data structurally protected, with
an optional private-GitHub mirror for off-site text backup.
