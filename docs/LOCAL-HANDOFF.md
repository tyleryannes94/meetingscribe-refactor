# MeetingScribe — Local Diagnose & Fix Handoff

You are Claude Code running **locally** on the user's Mac mini (macOS Tahoe, Apple
Silicon), inside the repo `~/MeetingScribeRefactor`. A prior **remote** session
diagnosed the situation but could not build or touch the filesystem (it ran on
Linux with no Swift toolchain and no access to the Mac). Your job is to finish
the work locally. Read this whole brief before acting.

> Standing user preference: **never put comments in terminal commands** you give
> the user to paste. Also: after any code/config edit, ask the user once (yes/no)
> before you commit and push (see repo `CLAUDE.md`).

---

## PRIORITY 0 — Restore the user's meeting library FIRST (before any build)

**Background.** A prior step ran `clean-reinstall.sh`, which **moved** (an instant
rename — NOT a delete) the meeting library to
`~/Documents/MeetingNotes.backup-20260625-130652`. Then naive `mv`-based restore
blocks were pasted **more than once**. Those blocks are **not idempotent**, so the
real data may now be in one of several places. **Do not run blind `mv` blocks.**
Inspect first, act second, and **never delete anything** — move folders aside to
timestamped names instead.

The app's configured meeting library path is `~/Documents/MeetingNotes`. The real
library is roughly **2.6 MB** and contains per-meeting subfolders (each with audio
`.m4a`, a `meeting.json`, transcripts, etc.) plus people data.

### Step 1 — survey every candidate location

```bash
ls -la ~/Documents | grep -i meetingnotes
du -sh ~/Documents/MeetingNotes* 2>/dev/null
find ~/Documents -maxdepth 3 \( -iname "meeting.json" -o -iname "*.m4a" -o -iname "person.json" \) 2>/dev/null | head -20
```

The real data is most likely at ONE of:
- `~/Documents/MeetingNotes.backup-20260625-130652` — the original backup, OR
- `~/Documents/MeetingNotes.empty-recreated/MeetingNotes` — **nested** (this is what
  happens when the non-idempotent restore block runs twice: run 1 restores the
  data, run 2 moves the restored folder *into* `.empty-recreated/` and then the
  follow-up `mv` of the now-missing backup errors out), OR
- already correctly at `~/Documents/MeetingNotes` (restore already succeeded).

Identify the folder that actually holds the meeting data (largest size, contains
meeting subfolders with audio/json). That is the source of truth.

### Step 2 — quit the app so it can't recreate an empty folder mid-restore

```bash
osascript -e 'tell application "MeetingScribe" to quit'
sleep 2
```

### Step 3 — restore safely (adapt to what Step 1 found; never delete)

If `~/Documents/MeetingNotes` currently exists but is empty/just-recreated, move it
aside to a **timestamped** name first, then move the real data folder into place.
Example shape (substitute the real source folder you identified):

```bash
[ -d ~/Documents/MeetingNotes ] && mv ~/Documents/MeetingNotes ~/Documents/MeetingNotes.stale-$(date +%s)
mv "<REAL_DATA_FOLDER_FROM_STEP_1>" ~/Documents/MeetingNotes
ls -la ~/Documents/MeetingNotes
```

Verify the `ls` shows the user's actual meeting subfolders.

### Step 4 — relaunch and confirm

```bash
open /Applications/MeetingScribe.app
```

Report **exactly** where you found the data and where you moved it. Leave any
leftover empty/backup/stale folders in place (timestamped) until the user confirms
everything is back; clean those up only on their explicit say-so.

---

## Where things stand (verified from the repo + CI by the remote session)

- This is a **SwiftUI macOS app**. The redesign codename is **"Bloom"**: dark plum
  theme (`#15121a`), **coral** primary CTAs (`#ff9173`), **lilac** nav (`#b79cff`),
  squircle avatars, chunky rounded corners, fonts **Bricolage Grotesque** (display)
  + **Plus Jakarta Sans** (body).
- **Bloom is already merged to `origin/main` and builds clean.** Current good commit
  is **`24cf266`**. CI (`.github/workflows/ci.yml`, runner `macos-15`) on that commit
  is **green**: `design-lint.sh fail` + `swift build -c release` + `swift test` all
  pass.
- Design tokens live in `Sources/MeetingScribe/UI/NotionDesign.swift` (the `NDS`
  enum). Shared Bloom components are in `MSComponents.swift` (`msCard`,
  `bloomAmbientGlow()`, `MSTintedHeaderCard`). Fonts are bundled in `Resources/Fonts/`.
- On top of Bloom, `origin/main` also carries **7 per-screen "conform to design comp"
  commits**: Today (2-column), Meetings (list + tabs), Tasks (board + inspector),
  Voice Notes, People (roster + header), chrome/nav, Settings (880×600 left-rail).
- **The new design IS rendering correctly** as of the last successful build (confirmed
  via screenshots: coral "Record Meeting" button, "Good afternoon, Tyler", lilac nav,
  pill tabs, Brain-dump panel). So the original "I don't see the design" complaint was
  a **stale/wrong build**, not missing code.

## Root causes of the earlier "I don't see it" (avoid these)

1. **Two repo trees exist:** `~/MeetingScribe` (DEPRECATED) and `~/MeetingScribeRefactor`
   (CURRENT). Building from the deprecated tree reinstalls the old app forever. Always
   build from `~/MeetingScribeRefactor`.
2. **`make app` does NOT install** — it only writes `build/MeetingScribe.app`. The user
   was stopping there. Use **`make dev`** (build → install to `/Applications` → relaunch).
3. The design landed in a burst on 2026-06-25; several intermediate commits had **red
   CI**. Only HEAD `24cf266` is green. Ensure HEAD is `24cf266` (or a newer green `main`)
   before building.

## Environment facts & gotchas

- Build **with warnings is fine** — the package uses `StrictConcurrency=targeted`, which
  emits MANY warnings (Sendable/main-actor). Only hard **errors** block. Toolchain:
  Swift 6.x / Xcode 16.
- Verify the running build via the app: **Settings → Version** shows `CFBundleVersion`,
  which is `git describe` stamped at build time (expect `v2.1-219-g24cf266`). An old
  value there means a stale `/Applications/MeetingScribe.app` is launching.
- `clean-reinstall.sh`'s "⚠ Versions don't match" line is a **false alarm** — it compares
  the full stamp `v2.1-…-g24cf266` against the short sha `24cf266`. Same commit.
- **Do not run `clean-reinstall.sh` again** — it relocates the meeting library (that's
  what caused the Priority 0 scare). For day-to-day rebuilds, **`make dev` is all that's
  needed.**
- Signing identity: "MeetingScribe Local Signer" (self-signed); TCC perms persist across
  rebuilds. Don't change it.
- Keychain creds + UserDefaults are preserved across reinstalls.

## OPEN QUESTION you must resolve with the user

The user created a "brand new design" in Claude Design at:
`https://claude.ai/design/p/9827be9f-f105-4b8b-8017-e9cf5b1a491a?file=MeetingScribe+Redesign.dc.html`

That URL is **auth-gated** (returns 403 to automated fetches) — the remote session could
not open it, and you probably can't either. The deciding question:

> **Is that design NEWER than the Bloom + 7 comp commits already on `main`, or is it the
> same handoff that's already implemented?**

The 7 "conform to comp" commits strongly suggest it may already be built. Until you can
actually see the artifact, **do not assume there is unbuilt design work.** Ask the user to
either (a) export/save the design's HTML/CSS into the repo (e.g. a `design_handoff/` folder,
like the existing `design_handoff_bloom_redesign 2/`), or (b) paste screenshots.

## Tasks, in order

1. **Restore the data (Priority 0). Verify and report where it was and where it went.**
2. Confirm repo + commit: in `~/MeetingScribeRefactor`, `git rev-parse --short HEAD` should
   read `24cf266` (or newer green `main`). If not: `git checkout main && git pull origin main`.
3. Build + install: `make dev`. Confirm `Build complete!` and `✓ Installed`. If the build
   **errors** (not warnings), capture and fix it — that is the real "claims built but I don't
   see it" failure mode.
4. Launch; verify Bloom renders and Settings → Version matches HEAD.
5. Resolve the OPEN QUESTION. If the Claude-Design artifact is genuinely newer than `main`,
   do a screen-by-screen conformance pass against the `NDS` tokens + per-screen views, keep
   `scripts/design-lint.sh fail` at zero, build/test, and **ask before pushing**.

## Success criteria

- `~/Documents/MeetingNotes` restored with all real meeting folders; app shows the user's data.
- `make dev` builds clean and installs; relaunched app shows Bloom (coral/lilac/plum); Settings →
  Version matches HEAD.
- A clear yes/no on whether the Claude-Design URL contains unbuilt work, plus either "fully
  matches" or a concrete gap list + fixes.

---

## Session history (what was already tried, so you don't repeat it)

- Remote session confirmed Bloom + 7 comp commits are on `origin/main` @ `24cf266`, CI green.
- User ran `make dev` and `clean-reinstall.sh` locally; **both built and installed successfully**
  (`Build complete!`, `✓ Installed`, stamped `v2.1-219-g24cf266`). The new design rendered.
- `clean-reinstall.sh` moved the meeting library to `~/Documents/MeetingNotes.backup-20260625-130652`,
  which alarmed the user (data appeared "deleted" — it wasn't).
- Naive `mv` restore blocks were pasted, possibly more than once → data may now be **nested** at
  `~/Documents/MeetingNotes.empty-recreated/MeetingNotes`. This is why Priority 0 says inspect-first.
