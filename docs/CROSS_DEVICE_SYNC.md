# Cross-device sync — back up your work Mac into your second brain

This sets up a **one-way backup**: everything MeetingScribe records on your **work
MacBook** is copied, every couple of hours, into a safe corner of your **personal
Mac mini** (your always-on "hub" / second brain). It's **free**, runs in the
background, and **can never overwrite or delete anything on the hub** — work data
lands in its own quarantined folder (`_remote/work-macbook/`).

Under the hood it's `rsync` over SSH, carried on your private **Tailscale** network,
scheduled by macOS `launchd`. You already have Tailscale on your Mac mini and iPhone;
the only new requirement is Tailscale on the **work MacBook** too.

> For the design rationale and the other transport options that were considered, see
> [`CROSS_DEVICE_SYNC_MASTER_PLAN.md`](CROSS_DEVICE_SYNC_MASTER_PLAN.md) and
> [`sync-plans/agent-1-tailscale-rsync.md`](sync-plans/agent-1-tailscale-rsync.md).

```
   WORK MacBook  ──(launchd every 2h)──►  rsync over SSH on Tailscale  ──►  Mac mini HUB
   your live vault                                                          <vault>/_remote/work-macbook/
                                                                            (the hub's own data sits
                                                                             alongside, untouched)
```

---

## What you need (5 minutes)

| | Mac mini (HUB) | Work MacBook |
|---|---|---|
| Tailscale, signed into the **same** account | ✅ you have it | **install it** |
| MeetingScribe installed | ✅ | ✅ |
| Remote Login (SSH) enabled | **turn on** (below) | — |
| Homebrew `rsync` (recommended) | — | `brew install rsync` |

---

## Part A — Prepare the hub (Mac mini), one time

1. **Enable Remote Login** so the work Mac can deliver files:
   **System Settings → General → Sharing → Remote Login → On** (limit "Allow access
   for" to your user).
2. **Note two things** the installer will ask for — run these in Terminal on the mini:
   ```bash
   tailscale ip -4     # the hub's tailnet address, e.g. 100.101.102.103
   whoami              # the hub login user, e.g. tyler
   ```
   (If you've enabled MagicDNS, you can use the hub's short name instead of the
   `100.x` address — either works.)

That's all on the hub. You do **not** install anything from this repo there; the
work Mac creates its quarantine folder over SSH automatically.

---

## Part B — Set it up on the work MacBook (one command)

1. Make sure **Tailscale** is installed and signed into the same account:
   ```bash
   brew install --cask tailscale   # then open it and sign in
   brew install rsync              # recommended (more capable than macOS's built-in)
   ```
2. Get this repo onto the work Mac (or just copy the `scripts/sync/` folder), then run:
   ```bash
   bash scripts/sync/install-sync.sh
   ```
   The installer walks you through everything:
   - checks Tailscale / rsync / your vault location,
   - asks for the hub's address + user (from Part A),
   - creates a dedicated SSH key and authorizes it on the hub (one password prompt),
   - verifies the connection works without a password,
   - installs the sync script and a `launchd` job that runs **every 2 hours and at
     login**,
   - does a **dry run**, then offers to do the first real sync.

That's it. From now on it runs by itself.

---

## Verify it's working

On the **work Mac**:
```bash
tail -f ~/Library/Logs/MeetingScribe/sync.log     # watch a run
launchctl list | grep meetingscribe               # confirm the job is loaded
bash ~/.local/bin/meetingscribe-sync.sh           # run a sync right now
```
On the **hub**, your work data shows up under the quarantine (it does **not** mix
into your own meetings):
```bash
ls "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook"
cat "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook/.last_sync"
```

---

## Everyday commands (work Mac)

| Do this | Command |
|---|---|
| Sync now | `bash ~/.local/bin/meetingscribe-sync.sh` |
| Preview what would sync | `bash ~/.local/bin/meetingscribe-sync.sh --dry-run` |
| Watch logs | `tail -f ~/Library/Logs/MeetingScribe/sync.log` |
| Change hub/interval/etc. | edit `~/.config/meetingscribe-sync/config.env` (or re-run the installer) |
| Pause syncing | `launchctl bootout gui/$(id -u)/com.tyleryannes.meetingscribe.sync` |
| Resume | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist` |
| Remove it | `bash scripts/sync/uninstall-sync.sh` (add `--purge` to also drop the key/config) |

**Change the schedule:** edit `StartInterval` in
`~/Library/LaunchAgents/com.tyleryannes.meetingscribe.sync.plist` (`3600` = hourly,
`7200` = 2 h, `10800` = 3 h), then reload with the pause/resume commands above. The
plist also has a commented-out daily 09:00 floor you can enable.

---

## Why your hub data is safe (one-way + non-clobber)

Four independent guarantees:

1. **Different destination.** Work files land only in
   `…/MeetingScribeVault/_remote/work-macbook/`. The hub's own meetings/people live
   *outside* that folder, so the sync physically cannot reach them.
2. **No deletes.** The sync only ever **adds or updates** in the quarantine (rsync
   runs without `--delete`). Deleting a meeting on the work Mac never deletes
   anything on the hub.
3. **Atomic writes.** Files transfer to a temp area and are renamed into place, so
   the hub never sees a half-written `meeting.json` or audio file. Large audio
   resumes if a transfer is interrupted.
4. **Derived caches excluded.** The hub keeps rebuilding its own search index and
   caches; the work Mac never ships a stale one. (`.meeting-index.json`,
   `_people-cache.json`, logs, the Whisper model blobs, and `secondbrain.db` are all
   skipped. Your meeting audio **is** included.)

Right now the work data simply *sits* in `_remote/` as a complete, browsable backup.
A future app feature (the "ingestion engine" in the master plan) can optionally fold
it into your main Meetings/People/Tasks lists, deduplicated — but that's opt-in and
not required for the backup to protect you.

---

## Security

- All traffic rides **Tailscale's WireGuard tunnel** — encrypted device-to-device,
  never exposed to the public internet, no port forwarding.
- The sync uses a **dedicated SSH key** (`~/.ssh/meetingscribe_sync`), not your
  GitHub/identity key.
- **Optional hardening** — lock that key to *only* rsync into *only* the quarantine,
  so even a stolen key can't run other commands or escape the folder. On the **hub**,
  edit `~/.ssh/authorized_keys` and prefix the `meetingscribe_sync` line with:
  ```
  command="rrsync -wo ~/Library/Mobile\ Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/work-macbook",restrict ssh-ed25519 AAAA…yourkey…
  ```
  (`rrsync` ships with rsync.)
- No secrets travel in the backup: API keys live in the macOS Keychain, not the
  vault, and logs are excluded.

---

## Troubleshooting

- **`Permission denied (publickey)` / asks for a password under launchd.** The key
  isn't authorized on the hub. Re-run `ssh-copy-id -i ~/.ssh/meetingscribe_sync.pub
  USER@HUB`, then `ssh -i ~/.ssh/meetingscribe_sync -o BatchMode=yes USER@HUB 'echo ok'`.
- **`Operation timed out` / can't reach the hub.** Tailscale must be **connected on
  both Macs** (check the menu-bar icon / `tailscale status`), and the mini must have
  **Remote Login on**. The job retries with backoff and runs on the next wake.
- **The job never runs.** `launchctl list | grep meetingscribe` should show the
  label; check `~/Library/Logs/MeetingScribe/sync.err.log`. Re-run the installer to
  reload it.
- **iCloud "files not downloaded".** If your vault is in iCloud Drive, some files may
  be cloud-only placeholders. Force them local once:
  `find "$VAULT" -type f -exec brctl download {} \;` — or point MeetingScribe's
  storage at a local folder (`~/Documents/MeetingNotes`) in Settings.
- **First sync is slow.** The initial run copies all your audio; every run after that
  only sends what changed. You can kick off the first one manually from Terminal and
  let the schedule take over afterward.
- **macOS firewall prompt on the hub** the first time — allow incoming connections
  for Remote Login / `sshd`.

---

## Files in this kit

```
scripts/sync/
├── install-sync.sh        # run this on the work MacBook (interactive setup)
├── uninstall-sync.sh      # remove it (--purge also drops key + config)
├── meetingscribe-sync.sh  # the rsync push script (installed to ~/.local/bin)
└── com.tyleryannes.meetingscribe.sync.plist.template   # launchd schedule template
```
Config lives at `~/.config/meetingscribe-sync/config.env`; logs at
`~/Library/Logs/MeetingScribe/sync*.log`.
