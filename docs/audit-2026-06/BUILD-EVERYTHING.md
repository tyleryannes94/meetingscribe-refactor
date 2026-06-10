# BUILD EVERYTHING — autonomous overnight build kickoff

This doc launches Claude Code in **fully autonomous mode** to build out every phase in
[`MASTER-PLAN.md`](./MASTER-PLAN.md) (backed by the five `GROUP-*.md` digests in this
folder), merging each phase to `main`, updating the app locally, and cutting a Sparkle
release per phase so your work MacBook can update itself.

---

## ▶ PASTE THIS INTO TERMINAL

```bash
cd ~/MeetingScribeRefactor && git checkout main && git pull --ff-only
cat > /tmp/ms-autobuild.txt <<'PROMPT'
You are running UNATTENDED and AUTONOMOUS. The user is asleep. Do NOT ask any questions, do NOT wait for confirmation, and do NOT stop until the whole plan is built. Make reasonable decisions on your own and record them. You already have bypass permissions — proceed with every edit, build, commit, push, PR, and merge automatically.

SOURCE OF TRUTH
- Read docs/audit-2026-06/MASTER-PLAN.md in full, plus GROUP-DESIGN.md, GROUP-PM.md, GROUP-ENGINEERING.md, GROUP-END-USER.md, GROUP-COMPETITIVE.md in the same folder for detail.
- Execute the phases in order (Phase 1 first, then 2, 3, ... to the last phase). Within a phase, build every workstream it lists.
- Follow ~/MeetingScribeRefactor/CLAUDE.md for commit style, build verification, signing, and environment quirks.

PER-PHASE LOOP (repeat for every phase, in order)
1. git checkout main && git pull --ff-only. Create a branch: phase-<N>-<short-slug>.
2. Build every workstream in the phase. Touch the specific files the plan names. Match the surrounding code's style.
3. After any non-trivial Swift change, run: swift build -c release  (or: make app). Errors BLOCK — fix them before continuing. Warnings are fine.
4. Commit in logical chunks using the CLAUDE.md commit style (feat:/fix:/refactor:/docs:/chore:, imperative, <72 chars). No Co-Authored-By trailers.
5. When the phase compiles clean: git push -u origin the branch, then open a PR with gh pr create (title = "phase <N>: <theme>", body = what shipped + DoD checklist). Then MERGE it yourself: gh pr merge --squash --delete-branch.
6. git checkout main && git pull --ff-only. Run: make install  (updates the installed app on this Mac). If make install fails, run make app then make install again; if still failing, log it and continue — do not stop.
7. Cut a release so the work MacBook can auto-update: find the latest tag with  git tag --sort=-v:refname | head -1  (currently v1.2), bump the MINOR (v1.2 -> v1.3 for phase 1, v1.4 for phase 2, and so on), then: git tag <next> && git push origin <next>. This triggers the Sparkle release workflow.
8. Append a one-line status to docs/audit-2026-06/BUILD-LOG.md: phase, tag, PR link, what shipped. Commit it to main and push.
9. Move to the next phase. Keep going with NO pause between phases.

ALWAYS-PROCEED + HOLD RULE
- Default is ALWAYS BUILD AND MERGE. Only HOLD an individual workstream (not the whole phase) if it is genuinely unsafe to auto-merge: it cannot be made to compile, it is destructive/irreversible, it needs a human secret/credential/paid account you don't have, it deletes user data, or correctness is truly ambiguous.
- To HOLD: do NOT merge that item. Commit it onto a single accumulating branch named phase-final-hold (create it once, off main, and keep adding to it). Add an entry to docs/audit-2026-06/HELD-ITEMS.md explaining WHAT was held and WHY, and what decision is needed. Then continue with the rest of the phase — never let one held item stall the others.
- Everything that is safe still ships normally. Holding is the exception, not the default.

FINAL PHASE (after all numbered phases are merged)
- If phase-final-hold has any commits: get it compiling as best you can (swift build -c release), push it, and open a PR with gh pr create — but DO NOT MERGE IT. Leave it open for the user.
- Write docs/audit-2026-06/MORNING-REPORT.md: every phase built + merged + the release tag for each, the make install result, the held-items PR link with a plain-English explanation of each held item so the user can decide whether to merge it, and anything that failed. Commit and push it to main.

DISCIPLINE
- Never push code that doesn't compile to main. A branch can be WIP; main must always build.
- If you get stuck on one workstream, hold it (rule above) and keep moving — do not halt the whole run.
- Keep going until every phase plus the final-hold step is done, then stop and leave the MORNING-REPORT.md as the last word.
PROMPT
claude --print --dangerously-skip-permissions --model claude-opus-4-8 "$(cat /tmp/ms-autobuild.txt)" 2>&1 | tee ~/ms-autobuild.log
```

---

## What it does (plain English)

- **Auto mode, no prompts.** `--dangerously-skip-permissions` + `--print` runs Claude Code headless and unattended; it never pauses for approval and runs the agent loop until the work is done.
- **Builds every phase in order**, on its own `phase-N-*` branch, verifying `swift build -c release` before anything lands.
- **Merges each phase itself** (`gh pr merge --squash`) into `main`, then `make install` so the app on this Mac is updated.
- **Cuts a Sparkle release per phase** by bumping the tag (`v1.2 → v1.3 → v1.4 …`) and pushing it, so your **work MacBook auto-updates** (Check for Updates… picks it up).
- **Always proceeds.** The default is build-and-merge. Anything genuinely unsafe to auto-merge is *held* on `phase-final-hold`, logged in `HELD-ITEMS.md`, and the run keeps going.
- **Leaves you a morning report.** At the end it opens (but does **not** merge) a single PR for the held items and writes `MORNING-REPORT.md` explaining everything shipped, every release tag, and what's awaiting your call. You merge the held PR yourself if it looks good.
- **Progress is tailed** to `~/ms-autobuild.log` and summarized live in `docs/audit-2026-06/BUILD-LOG.md`.

## Notes / caveats

- Releases are tag-driven via Sparkle (see `RELEASING.md`). Each pushed `vX.Y` tag triggers `.github/workflows/release.yml`. **One-time check:** confirm `Resources/Info.plist :SUFeedURL` points at the repo you actually publish releases to, or the work MacBook won't see the updates.
- If a release workflow needs the `SPARKLE_PRIVATE_KEY` secret and it isn't set, the tag push still lands but the signed release won't publish — that'll show up in `MORNING-REPORT.md`.
- To watch it overnight: `tail -f ~/ms-autobuild.log`. To stop it: Ctrl-C in that terminal.
