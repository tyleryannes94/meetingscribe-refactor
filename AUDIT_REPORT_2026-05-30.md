# MeetingScribe — Refactor Audit Report

**Date:** 2026-05-30
**Canonical repo:** `~/MeetingScribeRefactor` (remote `tyleryannes94/meetingscribe-refactor`), HEAD `dd44be2`
**Legacy repo:** `~/MeetingScribe` (remote `tyleryannes94/meetingscribe`), HEAD `feb5409`
**Method:** 5 independent audit agents — (1) plan↔code parity, (2) old→refactor lost-code, (3) committed vs installed, (4) build & structural integrity, (5) MCP & integration surface — cross-checked against `MASTER_PLAN_V2.md` and `MASTER_PLAN_V3.md`.

---

## TL;DR

The refactor is in **good shape**. The original worry — *"some code never made it into the refactor repo, nor got installed locally"* — turned out to be **largely unfounded**:

- **No genuinely lost code.** Every one of the ~20 files that exist in the old repo but not the refactor was either on the master plan's explicit "Files to Delete (21)" cut list, or was deliberately re-homed (e.g. the Calendar tab folded into Meetings). Nothing the user had has silently disappeared.
- **Working tree is clean** and the **locally-built app matches HEAD exactly** (`CFBundleVersion = dd44be2`). No uncommitted source, no untracked `.swift`, no stranded branch work.
- **Most of V2/V3 is built**, including all 6 V2 "Phase 0" bugs, all 5 V3 data-integrity P0s, the VaultKit/two-binary split, the iCloud inbox watcher, and the write-capable MCP tools.

The real issues are smaller and fall into three buckets: **(A) one residual data-integrity gap** (ENG-A fallback), **(B) the installed `/Applications` copy can't be verified from here + a wrong-repo install foot-gun**, and **(C) tech-debt/doc-drift cleanup** (orphaned dead targets, stale architecture doc, Sparkle feed URL pointing at the old repo).

---

## Severity-ranked issue list

| # | Severity | Issue | Where | Fix |
|---|----------|-------|-------|-----|
| 1 | 🔴 High | **ENG-A batch-fallback gate is incomplete.** `flush()` tail-recovery works, but the trigger to fall back to a batch re-transcribe is only "live transcript is empty." A *truncated-but-nonempty* live transcript with `droppedChunkCount > 0` will skip the repair pass → silent partial transcript. | `MeetingPipelineController.swift:88` (`liveIsUseful`); `droppedChunkCount` unused at finalize | Gate on coverage: force batch when `droppedChunkCount > 0` OR live duration < (meeting duration − one chunk). |
| 2 | 🟠 Med | **Installed `/Applications` app not verifiable from this session + wrong-repo foot-gun.** Both repos build `com.tyleryannes.MeetingScribe` into `/Applications`, so they overwrite each other. The OLD repo still has `build/MeetingScribe.app` stamped `805a8f5-dirty`. If you ever installed from `~/MeetingScribe`, the running app is stale. | host `/Applications/MeetingScribe.app` (unmounted); `~/MeetingScribe/build/` | Run the verification one-liner below; if mismatch, run `~/MeetingScribeRefactor/clean-reinstall.sh`. Delete `~/MeetingScribe/build/`. |
| 3 | 🟠 Med | **Orphaned dead library targets.** `SecondBrainCore` (4 files) and `MeetingScribeShared` (3 files) are **byte-identical** to code now in `VaultKit` and imported by **zero** files in `Sources/` (only 3 test files import `MeetingScribeShared`). Live drift risk. | `Package.swift`; `Sources/SecondBrainCore/`, `Sources/MeetingScribeShared/` | Migrate the 3 test imports to `VaultKit`, then delete both targets + products. |
| 4 | 🟡 Low | **Doc drift — MCP described as read-only/12 tools.** Server now has **17 tools incl. 5 writers** (verified live). Docs predate commit `6cdec9c`. | `docs/ARCHITECTURE.md:417,429,436`; `docs/USER_GUIDE.md:160` | Update docs to 17 tools, note write capability. |
| 5 | 🟡 Low | **Sparkle `SUFeedURL` points at the OLD repo.** Auto-update appcasts would be pulled from `github.com/tyleryannes94/meetingscribe`, not `…/meetingscribe-refactor`. | `Resources/Info.plist:45` | Repoint to the refactor repo's appcast (confirm intended release repo first). |
| 6 | 🟡 Low | **ARCH-1 CaptureKit de-dup not done.** ~28 Audio/Transcription files duplicated across app↔daemon; 4 key ones (`AudioRecorder`, `WhisperRunner`, `NotificationManager`, `LiveTranscriber`) have already **diverged**. ENG-A/ENG-D fixes must be maintained in two copies. | `Sources/MeetingScribe/{Audio,Transcription}` ↔ `Sources/ScribeCore/{…}` | Planned (Phase 4): extract a shared `CaptureKit` library. CI ratchet blocks *new* dupes today. |
| 7 | 🟡 Low | **V3 req #1 — People panel spacing.** Still a `.padding(.top, 60)` magic number (with a misleading "72pt" comment) instead of the planned `.safeAreaInset`; panes may not align. | `PeopleListView.swift:131-133`, `PersonDetailView.swift:239,273` | Replace with `.safeAreaInset` or a shared constant. |
| 8 | ⚪ Cosmetic | Empty stub dirs (`Backup/ Coaching/ Compliance/ Team/`), spent scripts (`delete_dead_code.sh`, `setup_refactor_repo.sh`), `Sources/.DS_Store`, 11 stale already-merged remote branches. | repo root / `Sources/` / origin | Delete; prune merged remote branches. |

**Net:** one functional fix worth doing soon (#1), one thing to verify on your Mac (#2), and a pile of low-risk cleanup. No emergency, no lost features.

---

## 1. Did code fail to make it into the refactor? (Agent 2)

**Verdict: No genuine losses.** Files in old-but-not-refactor, all accounted for:

| Feature | Old location | Fate in refactor | Verdict |
|---|---|---|---|
| Backup (4 files) | `MeetingScribe/Backup/` | Deleted — superseded by iCloud-Drive vault (plan called the old one "not a real backup") | Planned |
| CloudKit sync (3) | `MeetingScribe/Sync/` | Deleted — replaced by vault + `Sync/iCloudInboxWatcher.swift`; real CKSyncEngine deferred to Phase 3 | Planned / re-homed |
| iPhone HTTP input (4) | `MeetingScribe/People/iPhone/` | Deleted (~700 LOC HTTP server) — replaced by iCloud Drive inbox watcher + Shortcuts | Re-homed |
| Team (3) | `MeetingScribe/Team/` | Deleted — "never shipped, unused" | Planned |
| Compliance (3) | `MeetingScribe/Compliance/` | Deleted — was firing consent prompts by default (a bug); below value threshold for solo use | Planned |
| Coaching (3) | `MeetingScribe/Coaching/` + `UI/MeetingCoachTab.swift` | Deleted — was orphaned (unwired) in old repo | Planned |
| **Calendar tab** | `UI/CalendarTabView.swift` (510 LOC, **was a live tab**) | Deleted in `d3ff251`; month grid **re-homed** into Meetings (List/Month toggle, `MeetingsView.swift:258-326`) | Re-homed (off-list but functional survives) |
| Initiative model | `MeetingScribeShared/Initiative.swift` | Re-homed to `ActionItems/Initiative.swift` | Re-homed |

The only off-plan deletion was the **Calendar tab**, but its capability survives inside Meetings. If you specifically miss a dedicated full-screen calendar tab, it's recoverable from old commit `feb5409:Sources/MeetingScribe/UI/CalendarTabView.swift` — but that's a UX preference, not lost functionality. Outside `Sources/`, **nothing** in the old repo is missing from the refactor; all other differences are *additions* (CI, docs, HANDOFF, scripts, the ScribeCore/VaultKit split).

---

## 2. Plan vs. what's actually built (Agent 1)

**V2 "Phase 0" bugs:** all 6 fixed (DispatchSemaphore→async, `@Published`-wrapping removed, 12Hz timers consolidated/moved off RunLoop, refresh debounced, cold-cache scan backgrounded, TOCTOU `.starting/.stopping` guards). **21-file cut list:** all deleted. **Vault/data layer:** SQLite moved to Application Support, iCloud-Drive default, FTS5 v2 schema verbatim incl. recency-boost ranking, NSFileCoordinator writes, per-meeting Obsidian `.md`, `_recent.json`, date-partitioned layout. **VaultKit** exists with the planned surface. **iCloudInboxWatcher** built + wired. **XPC protocol** fully defined; **ScribeCore daemon** extracted with login-item registration.

**V3 requirements #1–#7:** #2 (inline People editing), #3 (Today hub), #4 (click-in nav, no expand/collapse; Calendar removed), #5 (full-width + chat rail closed by default), #6 (default upcoming scope, persisted), #7 (restored Add-to-People / +action-item / open-in-Mail) — **all built**. #1 (People spacing) — **partial** (issue #7 above). **Data-integrity P0s:** ENG-B/C/D/E/F/G all fixed; **ENG-A partial** (issue #1 above).

**Plan items NOT built:**
- **ARCH-1 CaptureKit de-dup** (issue #6) — deferred to Phase 4.
- **NSXPCConnection client wrapper** — protocol defined and daemon side exists, but live UI↔daemon transport is still the file-command bridge. *This was explicitly deferred to Phase 2 in the plan; the client file says so.* Not a regression.
- **Four iPhone Shortcuts** — not in repo, but these are client-side iOS artifacts, expected to live outside the Swift repo.

---

## 3. Committed vs. installed (Agent 3)

- **Working tree:** clean. No tracked diffs, no staged changes, no untracked `.swift`, no stashes. (`build/`, `.build/` are correctly gitignored.)
- **Branches:** the 11 "unmerged" remote branches are stale — every commit is content-equivalent to a squash-merged PR (#1–#11) already in `main`. No stranded work. Safe to prune.
- **Built artifact:** `build/MeetingScribe.app` → `CFBundleVersion = dd44be2` = `git rev-parse --short HEAD`. **Exact match.** All binaries present (`MeetingScribe`, `MeetingScribeMCP`, `NotionMCP`); `ScribeCore.app` builds as a **sibling** bundle, not nested — confirm that matches your mental model.
- **Cannot read `/Applications/MeetingScribe.app`** from this session (not mounted). Verify on your Mac:

```bash
# Pass/fail: is the installed app the current HEAD?
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/MeetingScribe.app/Contents/Info.plist)" \
  = "$(git -C ~/MeetingScribeRefactor rev-parse --short HEAD)" ] \
  && echo "INSTALLED MATCHES HEAD (dd44be2)" || echo "MISMATCH — run clean-reinstall"
```

If it mismatches (or shows `805a8f5-dirty` → you installed from the old repo), run `~/MeetingScribeRefactor/clean-reinstall.sh`. **Recommendation:** only ever install via the refactor repo; delete `~/MeetingScribe/build/` to kill the foot-gun.

---

## 4. Build & structure (Agent 4)

- **Build:** static analysis only — no Swift/macOS toolchain in the audit sandbox, so no compile was claimed. CI (`.github/workflows/ci.yml`, macOS-15 / Swift 6.x) is the source of truth; the pinned toolchain is load-bearing (Swift 5.10 turns two concurrency items into hard errors).
- **Package.swift ↔ Sources:** clean 1:1 mapping; all 7 targets resolve, all 5 ScribeCore `exclude` entries exist, no orphaned source dirs.
- **Duplication guard:** **passes.** 28 known app↔daemon dupes baselined in `scripts/capturekit-dup-baseline.txt`; no new dupes. Guard only covers the app↔daemon tree — it does **not** see the orphaned VaultKit/SecondBrainCore/MeetingScribeShared model dupes (issue #3).
- **Diverged dupes:** `AudioRecorder` (~11 lines), `WhisperRunner` (~59), `NotificationManager` (~83), `LiveTranscriber` (~37) differ between app and daemon copies — expected drift pending CaptureKit extraction.
- **Cleanup scripts:** `delete_dead_code.sh` already ran (all 20 targets gone) — now a no-op; `setup_refactor_repo.sh` is a spent one-time bootstrap. Both deletable.

---

## 5. MCP & integrations (Agent 5)

- **MCP tools:** committed source defines exactly the **17** tools the live server exposes — including all 5 write tools from `6cdec9c` (`create_action_item`, `update_action_item`, `add_person`, `add_memory`, `create_meeting_note`). **No drift** between source and installed binary; no uncommitted work. Writes patch raw JSON (lossless), are append-only for notes, and post `vaultChanged`.
- **NotionMCP:** 6 tools, fully implemented, wired in `Package.swift`, bundled + signed by the Makefile.
- **MCPInstaller:** binary paths (`Contents/MacOS/MeetingScribeMCP`, `…/NotionMCP`) match the Makefile bundle layout; registers under `~/Library/Application Support/Claude/claude_desktop_config.json`; passes `MEETINGSCRIBE_STORAGE`; has a self-test. Correct.
- **Integrations:** Linear (task sync), Google Drive (full OAuth PKCE export), Google Contacts (People API import), in-app Notion (push/pull action items) — all substantively wired, no stubs/TODOs. Two parallel Notion clients (bundled `NotionMCP` vs in-app `NotionActionItemService`) — intentional, but a drift risk to keep in sync.
- **Info.plist/entitlements:** bundle id correct; all usage-description keys present (mic, screen capture, calendar ×2, contacts, Apple Events); entitlements match active features. **Two doc/config drifts:** stale MCP docs (#4) and the Sparkle feed URL pointing at the old repo (#5).

---

## Recommended next actions

1. **Fix ENG-A fallback gate** (issue #1) — the one real data-integrity residual. Force a batch re-transcribe when `droppedChunkCount > 0` or live coverage is short.
2. **Verify the installed app** on your Mac with the one-liner in §3; reinstall from the refactor repo if it's stale; delete `~/MeetingScribe/build/`.
3. **Delete the orphaned targets** `SecondBrainCore` + `MeetingScribeShared` (migrate 3 test imports to `VaultKit` first).
4. **Refresh docs + Sparkle URL** (issues #4, #5).
5. **Housekeeping:** remove empty stub dirs, spent scripts, `.DS_Store`; prune merged remote branches.
6. **Schedule** the CaptureKit extraction (issue #6) to retire the diverging app↔daemon duplication.
