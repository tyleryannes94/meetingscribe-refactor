# MeetingScribe — Working Preferences

## Repo

- GitHub: https://github.com/tyleryannes94/meetingscribe (private)
- Local: `~/MeetingScribe`
- Default branch: `main`

## Workflow rules

### Always ask to push after edits

After applying ANY code/config edit in this repo, ask the user once whether to
commit and push. Phrasing should be a yes/no question, e.g.:

> "Push these changes to `tyleryannes94/meetingscribe`?"

If they reply yes (or any clear affirmative), do all three of:
1. `git add -A`
2. `git commit -m "<concise message describing the change>"`
3. `git push`

Then confirm the push (commit SHA + branch) in the response.

Skip the push question only when:
- The edit was reverted or didn't actually change anything.
- The change is a temporary diagnostic (e.g., adding a `print` to debug, planning
  to undo it).
- The user explicitly says "don't push" / "local only".

### Commit message style

- Subject line: imperative mood, lowercase first word after a category prefix
  (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`). Under 72 chars.
- Body (optional): wrap at 80, explain WHY when it's non-obvious.
- No "Co-Authored-By" or trailers unless the user asks.

### Build verification

After non-trivial Swift edits, run `swift build -c release` or `make app`
before asking to push, so we don't push code that doesn't compile. Warnings
are fine; errors block the push.

## Environment quirks (already known)

- macOS 26.3.1 (Tahoe), Apple Silicon (M2 Mac mini).
- `~/bin/open` is a custom script that handles a `frost` shortcut and falls
  through to `/usr/bin/open` for everything else. Use `/usr/bin/open` directly
  in scripts to avoid surprises.
- Code-signing identity: "MeetingScribe Local Signer" (self-signed, in login
  keychain). TCC permissions are pinned to this cert's CN, so rebuilds don't
  re-prompt for Screen Recording / Mic / Calendar.
- App bundle id: `com.tyleryannes.MeetingScribe`. The MCP binary is bundled
  at `Contents/MacOS/MeetingScribeMCP` and signed with the same identity.
