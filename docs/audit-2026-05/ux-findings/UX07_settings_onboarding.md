# UX07 — Settings + Onboarding / First-Run Quick Wins

Senior-PM lens on the panes that decide whether a first-run user ever gets to a working app: the permission flow (`OnboardingSheet`), the Settings window (`SettingsView`), the MCP install screen, the connector cards (`IntegrationsView`), and how "what's connected / working" is surfaced. Low-lift polish only — not the V4 DMG/installer rework.

## Lift from V4 (relevant, already-planned, low-lift)

- **D3-3** — Bundled sample/demo meeting so Today is never empty and first value arrives in zero clicks. Directly de-confuses first run; pairs with FT7-5 below.
- **D3-6 / U5-7** — Screen-Recording grant auto-detection + a real "Reopen MeetingScribe" relaunch helper, replacing the "quit and relaunch" cliff. The onboarding screen literally tells users to "quit + relaunch the app" (`OnboardingSheet.swift:312,322`) with no affordance — see UX7-2.
- **U5-2 / D3-1** — In-app "Getting things ready" Setup Check (download whisper model, start Ollama in-GUI). The status plumbing for this already half-exists in `OllamaStatusRow` (`SettingsView.swift:657`) and `MCPInstaller.selfTest()`; FT7-1 is the lighter glance version that can ship before the full Setup Check.
- **P5-6** — One-click "Run a health check" (whisper/Ollama/permissions/disk). FT7-1 is the front-of-app, lower-lift surface for the same signal.

---

## UX improvements (5)

### UX7-1 — Reachable Settings: the gear is the ONLY door, and it opens a 13-section flat scroll
**Friction today:** Settings is the macOS `Settings` scene (`MeetingScribeApp.swift:125`), opened from one gear button at the bottom of the rail (`MainWindow.swift:156`) or ⌘, . It's a single 560×580 `Form` with ~13 stacked sections (Storage, Capture, Calendar, Impromptu, Dictation, MCP, Notion MCP, Integrations, Google Drive, Whisper.cpp, Diagnostics, Ollama, People, Obsidian) and **no tabs and no search field** (`SettingsView.swift:49–413`). Reaching "Whisper language" or "Obsidian template" = open Settings (1 click) + scroll past 8–11 sections hunting visually. That fails the 3-click/findability spirit even though it's technically 1 click to *open*.
**Fix:** Wrap the existing `Form` sections in a `TabView { ... }.tabViewStyle(.automatic)` with 4–5 macOS-standard preference tabs (General/Storage · Capture & Calendar · AI & Transcription · Integrations · Diagnostics). Pure re-parenting of sections already written — zero new logic. Any setting becomes: open (1) → click tab (2) → it's on screen (3).
**Clicks:** find a buried setting 1 + N-section scroll → **≤3 and no hunting**.
**Effort:** small-M.

### UX7-2 — Permission screens promise a manual "quit + relaunch" with no button to do it
**Friction today:** The Screen Recording step's subtitle and bullets say *"After granting, you'll need to quit and relaunch the app once"* and *"After granting, quit + relaunch the app"* (`OnboardingSheet.swift:312,322`). There is no relaunch affordance — the user is told to do OS chores by hand, mid-onboarding, which reads as broken. After tapping "Open System Settings" (`:170`) they're dumped into System Settings with no return path.
**Fix:** Add a "Relaunch MeetingScribe" button on the Screen Recording step (and any `.pendingManual` step) that execs a relaunch helper (`Process` re-open of the bundle + `NSApp.terminate`). Re-label the bullet to "Grant access, then tap Relaunch — we'll reopen for you." (Net-new copy + button around the V4 D3-6 detection.)
**Clicks:** manual quit→find app→reopen (≈4 + context switch) → **1 button**.
**Effort:** S.

### UX7-3 — "Skip" on a permission step is indistinguishable from a hard denial, with no recovery later
**Friction today:** Every permission step offers `Button("Skip", role: .cancel) { advance() }` (`OnboardingSheet.swift:167`). Skipping advances and the onboarding flag flips to true forever (`:204`) — and **there is no way to re-run onboarding** (`hasCompletedOnboarding` is only ever set `true`, never reset; confirmed no reset path in source). A user who skips Microphone has no in-app route back to that pre-explained prompt; they must discover the System Settings deep-link buried in Settings.
**Fix:** (a) On skip, persist which permissions are still ungranted; (b) add a "Re-run setup" / "Permissions" row in Settings → Diagnostics (or the General tab) that flips `hasCompletedOnboarding = false` and re-presents the sheet. Two-line change in `SettingsView` + reuse of the existing sheet.
**Clicks:** recover a skipped permission today = effectively impossible without OS knowledge → **2 clicks** (Settings → Re-run setup).
**Effort:** S.

### UX7-4 — Two competing connector UIs; the *better* one is dead code, the *worse* one ships
**Friction today:** `IntegrationsView.swift` is a polished card UI — per-connector "Connected / Not connected" status pills (`:386`), inline "Test connection", and a smart "you're on the bad default model, Pull <recommended>" nudge (`:190`). **It is never instantiated anywhere** (grep: only its own `struct` declaration). Its header comment in `MainWindow.swift:6` says "Integrations moved to Settings," but `SettingsView` re-implements the same connectors as flat `Form` sections *without* the status pills or one-click model pull (`SettingsView.swift:112–310`). So users get the inferior duplicate and the good affordances are unreachable.
**Fix:** Replace the MCP / Notion / Integrations / Google / Ollama `Form` sections in `SettingsView` with the existing `IntegrationsView` (drop it into the new "Integrations" tab from UX7-1). Deletes duplicated code and instantly upgrades every connector to status-pill + inline-test + model-nudge UX. Mostly deletion + one embed.
**Clicks:** unchanged to reach, but each connector's state/test goes from "read paragraph + guess" → **glanceable pill + 1-click test**.
**Effort:** small-M.

### UX7-5 — MCP install copy assumes Claude knowledge and hides the snippet behind a disclosure
**Friction today:** The MCP section leads with bare buttons ("Copy config snippet", "Install in Claude Desktop") and the only "what is this / did it work" guidance is two `.caption` paragraphs and a collapsed `DisclosureGroup("Show config snippet")` (`SettingsView.swift:112–189`). A first-run user can't tell *order of operations* (install → restart Claude → ask it to list meetings) at a glance, and "Bundled / not found" (`:114`) is jargon. After install the only confirmation is a sentence telling them to quit and reopen Claude Desktop.
**Fix:** Add a tiny numbered 1-2-3 stepper above the buttons ("1. Install  2. Restart Claude Desktop  3. Ask Claude to list your meetings"), turn the post-install sentence into an inline success banner with the same green seal style as `binaryExists`, and re-label "Bundled" → "MCP server ready". Copy + a 3-row `VStack` — no logic.
**Clicks:** unchanged; comprehension/first-success rate up.
**Effort:** S.

---

## Feature improvements (5)

### FT7-1 — "What's connected" health strip at the top of Settings (and a rail dot)
**What/why:** Status is scattered — MCP seal (`SettingsView.swift:114`), Ollama row (`:657`), Drive (`:262`), Calendar (`IntegrationsView` only). There's no single "is my app actually working" glance. Add a compact horizontal status strip pinned to the top of the Settings window: Mic · Screen Rec · Calendar · Ollama · Whisper model · MCP, each a colored dot + label, reusing the checks already written (`OnboardingSheet.currentStatus`, `OllamaService.isReachable`, `mcp.binaryExists`). Optionally tint the rail gear (`MainWindow.swift:156`) amber if any core capability is down.
**User value:** Self-diagnosis in one look; the #1 "why isn't it transcribing?" support question answers itself.
**Effort:** small-M (all probes exist; this is composition). **Dependency:** none; complements V4 P5-6.

### FT7-2 — Sensible-default "Recommended setup" one-tap on first run
**What/why:** Defaults are reasonable individually (chat rail off, iCloud vault recommended) but a new user still has to manually: pick vault, grant 4 perms, start Ollama, pull the right model. Add a single "Use recommended setup" button on the onboarding vault step that: sets iCloud vault, sets `ollamaModel` to `recommendedOllamaModel`, and flags the post-onboarding Setup Check to auto-start Ollama + offer the model pull (`IntegrationsView.pullRecommendedModel` already exists, `:285`).
**User value:** Collapses the entire "make it actually work" path into one tap for the 80% who want defaults.
**Effort:** small-M. **Dependency:** rides V4 U5-2 Setup Check; the model-pull action already exists.

### FT7-3 — Surface the "you're on the bad default model" warning where users actually look
**What/why:** `IntegrationsView` has a great guard — if `ollamaModel != recommendedOllamaModel`, it shows an orange "llama3.1:8b leaks tool-call JSON / over-refuses; pull <recommended>" nudge with a one-click Pull button (`:190–199`). Because that view is dead code (UX7-4), **no user ever sees it.** Even after fixing UX7-4, also surface a one-line amber chip in the Today/header health strip (FT7-1) when on a known-bad model.
**User value:** Quietly fixes the single biggest summary-quality footgun without the user knowing the model matters.
**Effort:** S. **Dependency:** UX7-4 or FT7-1.

### FT7-4 — Settings search / quick-jump field
**What/why:** Even tabbed (UX7-1), 13 sections is a lot. Add a small search field at the top of Settings that filters/scrolls to the matching section by keyword ("whisper", "obsidian", "linear", "hotkey"). Sections are static and few, so a simple title/keyword map → scroll-to-anchor is enough; no need for live form filtering.
**User value:** Setting findability in one keystroke; future-proofs as sections grow.
**Effort:** small-M. **Dependency:** UX7-1 (shared container).

### FT7-5 — First-run "you're all set" completion screen with next-step affordances
**What/why:** Onboarding ends by silently dismissing the sheet (`OnboardingSheet.advance` → `isPresented = false`, `:204`) onto a likely-empty Today. Add a final completion step: a short checklist of what got granted (green/grey), plus 2 buttons — "Record a test meeting" and "Open the sample meeting" (pairs with V4 D3-3). Turns the dead-end dismiss into an obvious first action.
**User value:** Closes the loop, gives immediate first value, reduces "now what?" drop-off.
**Effort:** S. **Dependency:** D3-3 sample meeting for the second button (first button works alone).

---

## Top 3 picks

1. **UX7-4 — ship the dead `IntegrationsView` in place of the flat-Form connector sections.** Highest leverage per hour: it's mostly *deletion*, and it instantly upgrades every connector to status pills + inline test + the bad-model nudge that's currently invisible.
2. **FT7-1 — "what's connected" health strip in Settings.** Every underlying probe already exists; composing them into one glance kills the most common "why isn't it working" confusion.
3. **UX7-2 + UX7-3 — relaunch button + a "re-run setup" path.** The onboarding currently asks users to do OS chores by hand and offers zero recovery if they skip a permission; both are tiny code changes that remove genuine first-run dead-ends.

**Single highest-value low-lift win:** UX7-4 — the better connector UI is already written and tested, just unwired; activating it is near-pure win.
