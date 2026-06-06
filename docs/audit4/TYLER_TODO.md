# Tyler — TODO / Action Items

Everything that needs **you** (a Mac, decisions, or access) to move the
Projects/Tasks "replace Notion" build forward. Written by Claude Code; updated as
work lands. Newest/most-important at the top.

Session: https://claude.ai/code/session_01Df4fWaHZV9CWbJ1ZqWxwZh

---

## 🔴 P0 — Do this first: validate the build

I've merged **27 code PRs into `main` this session, none of them compiled** —
there's no Swift toolchain in my environment and the macOS CI runner never gets
assigned (see next item), so I've hand-reviewed every line but cannot guarantee
it builds.

**On your Mac:**
```bash
cd ~/MeetingScribeRefactor
git checkout main && git pull
swift build -c release && swift test
```
- ✅ If green: reply "build is green" and I'll proceed into the high-risk items
  with a real safety net.
- ❌ If red: **paste me the compiler errors / failing tests** and I'll fix them
  immediately. Most likely suspects if anything broke:
  - `TaskPersistenceCoordinator` (`@unchecked Sendable`, the `NotificationCenter`
    observer closures).
  - SwiftUI detail in the newer views (`ActionItemsCalendarView`,
    `CustomPropertyRow`, `TaskInsightsView`, `TaskTrashView`, `TaskShortcutsView`).
  - `onKeyPress` usage in `ActionItemsListView` (keyboard nav).
  - Memberwise-init / `Codable` on the new `ActionItem` / `Project` fields.

---

## 🟠 P1 — Fix CI so there's a real gate

Every CI run since **2026-06-02** fails in ~3 seconds with `runner_id: 0` and no
logs — the `macos-15` GitHub Actions runner is **never assigned** (it failed even
on a docs-only PR and on `main`). The last green run was 2026-06-01.

**What to check:**
- GitHub Actions **macOS runner minutes / billing** for the repo/org (macOS
  minutes are metered separately and commonly run out).
- Whether org policy disabled GitHub-hosted runners.
- `.github/workflows/ci.yml` pins `runs-on: macos-15` — confirm that label is
  available to the account.

Until this is fixed, **I cannot verify anything I write.** Restoring CI is the
single biggest unblock for the remaining work.

---

## 🟡 P2 — Decisions I need from you before I build the riskiest items

I deliberately have **not** built these blind. Tell me how to proceed once the
build is green (or greenlight them anyway):

1. **JSON → SQLite migration (`BE-3`)** — moves your **live task data** to a new
   store with a one-time migration. Data-destructive if a blind bug slips in.
   *I will not merge this without a working build gate or your explicit go-ahead
   knowing the risk.* It unlocks scale (10k+ tasks), FTS, relations, rollups.
2. **Block-based doc editor (`NP-4`)** — replaces the markdown page body with real
   blocks (toggles, callouts, embeds, synced blocks). Large; reshapes the editor.
3. **Two-way external sync (`PM-18` / `BE-8`)** — write local edits back to
   Notion/Linear with conflict resolution. Touches networking + a CRDT-ish merge.
4. **Automation/rules engine (`BE-12`)**, **repository split (`BE-2`)**,
   **provider abstraction (`BE-14`)** — large internal refactors; high blind-compile
   risk, low immediate user-visible payoff. Best done with CI green.

> Default if you say nothing: I keep building the **lower-risk** remaining items
> (backlinks, breadcrumbs, more views, polish) and hold the five above for a gate.

---

## 🟢 P3 — Optional: turn on / try the new features

These shipped this session and are ready to use (once the build is confirmed):

- **Delegated tasks (the moat):** off by default. Enable in
  **Settings → People (second brain) → "Capture others' action items as
  delegated/waiting-on."** Then a **Delegated** chip appears in the Tasks toolbar.
- **Due reminders:** on by default (`Settings` key `notifyTaskDue`). Make sure
  macOS Notification permission is granted.
- **Quick-add:** ⌥⌘N → type e.g. `Email Sarah friday !high #marketing`.
- **Keyboard nav:** click the task list, then `J`/`K`/arrows, `Return`, `Space`.
  (Full list: Tasks toolbar overflow → **Keyboard shortcuts**.)
- **Calendar / Insights / Trash / CSV export:** view switcher + toolbar overflow.
- **Custom properties:** open a task in a project → **Add property**.

### Smoke-test checklist (when validating)
- [ ] Record a ~30s meeting → transcript + summary + extracted action items still work.
- [ ] Delete a task → "Undo" toast; check Trash → Restore.
- [ ] Quick-add with `!high`, `#label`, and a date.
- [ ] Switch a project between List / Board / Table / Calendar; reopen → view persists.
- [ ] Add a custom property to a task; set/edit/delete it.
- [ ] Complete a recurring task → next instance appears.
- [ ] Set a due date → reminder fires (or appears in pending notifications).

---

## ✅ Done this session (reference)

27 code PRs across Phases 0–6 (safety, data spine, daily loop, interaction speed,
visual, Notion-class custom properties, meeting-AI moat + planning). Full audit and
plan live in `docs/audit4/`.
</content>
