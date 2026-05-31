# Design — Onboarding & First-Run Experience

**Lens:** Map the full first-run journey for a non-technical user — from download to first value (first recording → first summary) — and find the drop-off, confusion, and trust moments along the way.

## Full-app audit (through my lens)

### The journey today, step by step

**Step 0 — Install.** There are two completely different install paths, and the app only works after the technical one. `install.sh` (`install.sh:1-119`) does the real heavy lifting: brew-installs `whisper-cpp`, `ollama`, `jq`, downloads the ~140 MB whisper model, pulls `llama3.1:8b` (~4.7 GB), creates a self-signed cert, builds and signs the app. **A non-technical user who just double-clicks `MeetingScribe.app` gets none of this.** The in-app safety nets are partial:
- The whisper model auto-downloads, but only on the default `models/ggml-base.en.bin` path (`WhisperRunner.swift:296-303, 318-322`) and only when first transcription runs — silently, with no UI.
- Ollama auto-starts via `ensureRunning()` (`OllamaService.swift:110-169`) — but only if the `ollama` **binary already exists**; if it doesn't, it just returns false and the user later sees a raw shell-command error: *"Run `brew services start ollama`…"* (`OllamaService.swift:34`). That is a dead end for a non-technical user.

So the real first-run truth is: **the GUI onboarding assumes the CLI install already happened.** That gap is the single biggest first-run risk and is unowned by any plan.

**Step 1 — Launch → OnboardingSheet.** A 480×480 sheet appears after a 200 ms delay (`MainWindow.swift:319-324`). It's genuinely good: vault picker first (`OnboardingSheet.swift:50-117`), then one screen per permission, each pre-explaining *before* the system dialog fires (`OnboardingSheet.swift:134-183`), every step Skip-friendly (`:167`). This is the strongest part of the FRE.

**Step 2 — The Screen-Recording cliff.** The copy literally says *"After granting, you'll need to quit and relaunch the app once"* (`OnboardingSheet.swift:312, 322`) and the action just dumps the user into System Settings (`OnboardingSheet.swift:219-220`). There is **no "Reopen MeetingScribe" button**, no relaunch helper, no detection that the grant happened. A non-technical user reads "quit and relaunch" as *the app is broken*. The plan flags this (V3 §5) but only as copy — the missing affordance is the real fix.

**Step 3 — No status check for the local AI stack.** Onboarding covers macOS *permissions* but never verifies the two things the app cannot run without: a whisper model and a reachable Ollama. There's no "checking your setup" screen, no progress bar for the 140 MB / 4.7 GB downloads, no "this happens once" reassurance. The downloads are invisible (`WhisperRunner.swift:342` logs only) so the first recording can hang for minutes with no explanation.

**Step 4 — Onboarding ends with no "what now."** `advance()` flips `hasCompletedOnboarding` and dismisses (`OnboardingSheet.swift:200-207`). There is **no "how it works" overview** (record → transcribe → summarize → tasks), confirmed by the plan's own V3 §5 wish-list. The user lands on Today.

**Step 5 — Empty Today.** If the calendar is empty the user sees "Nothing on today's calendar" + an *Import recording* button (`TodayView.swift:286-301`). The primary "Record Meeting" CTA is in the quick-actions row above (`TodayView.swift:122-129`), but nothing guides the user to it, and there's no sample/demo meeting so the first thing they ever see is empty space. First *value* (a real summary) requires them to run a live meeting — a high-commitment first act.

**Step 6 — Three record entry points, no explanation.** "Record Meeting" (`TodayView.swift:124`, ad-hoc `for: nil`), Voice Notes, and calendar-driven auto-record all exist with no disambiguation — the plan notes this (V3 §5) but it's unbuilt.

**Step 7 — MCP install.** Buried in Settings → MCP Server (`install.sh:112-114`, `MCPInstaller.swift:72-90`). `installInClaudeDesktop()` writes the config but requires a manual Claude Desktop restart, and `claudeDesktopConfigURL` may not even exist if the user never opened Claude (`MCPInstaller.swift:31-34`). For the target user this is an advanced, undiscoverable feature with no in-context prompt.

### Trust / privacy moments
The app's entire pitch is "100% on-device," yet **nothing in the FRE says so.** The vault screen says "a single folder on your Mac" (`OnboardingSheet.swift:58`) and Screen Recording says "no video, no screenshots" (`OnboardingSheet.swift:322`) — good but scattered. There's no single privacy reassurance moment, and the big network downloads (HuggingFace, Ollama) happen *silently*, which is exactly when a privacy-anxious user assumes data is being uploaded. That's a trust own-goal.

## Existing-plan items I rank highest

1. **V3 §5 "Reopen MeetingScribe" affordance for the Screen-Recording step** — the single most broken-feeling moment in the FRE. Endorse, but it needs to be an actual relaunch button + grant-detection, not just warmer copy.
2. **ENG-D — gate the ~140 MB model fetch behind onboarding consent** — directly serves the trust + "big download" anxiety. The consent UI is the onboarding deliverable.
3. **V3 §5 "how it works" overview after onboarding** — closes the empty "what now" gap at Step 4.
4. **LAY-2 — chat rail closed on first run** — a cluttered first screen hurts comprehension; endorse specifically for FRE.
5. **V3 §5 de-jargon "vault" + disambiguate the three record entry points** — both reduce first-run confusion cheaply.

## NET-NEW recommendations

**D3-1 — In-app "Setup Check" gate before first recording (S/M, High).** Before the first record, run a readiness check: whisper model present? Ollama installed + reachable? If not, show a friendly remediation card with a progress bar and a one-tap "Install local AI engine" that drives the download/Ollama-start in-GUI — never a shell command. Replaces the dead-end `OllamaService.swift:34` error. *Depends on: surfacing WhisperRunner download + ensureRunning state to the UI.*

**D3-2 — Guided first recording ("coachmark run").** First time the user taps Record Meeting, overlay 3 lightweight coachmarks: "We're capturing your mic + the call's audio," "Stop anytime here," "Your summary appears here when you stop." Converts the highest-commitment first act into a guided one. (M, High). *Depends on: D3-5 checklist optional.*

**D3-3 — Bundled sample/demo meeting (S, High).** Ship one canned meeting (audio optional; pre-made transcript + summary + action items) seeded on first run so Today is never empty and the user sees the *output* shape before recording anything real. A "This is an example — delete it anytime" banner. Delivers first value in zero clicks. *No dependency.*

**D3-4 — Privacy reassurance moment (S, High).** A dedicated onboarding card (or a persistent "On-device" badge near Record): "Everything runs on your Mac. The only downloads are the open-source AI models, one time. Nothing you say leaves this device." Pair it with a visible progress bar on the model/Ollama downloads so the network activity is *explained, not discovered.* *Pairs with ENG-D, D3-1.*

**D3-5 — First-run progress checklist on Today (M, Med).** A dismissible "Get started" card: ☐ Grant Screen Recording ☐ Download AI engine ☐ Record your first meeting ☐ Connect to Claude (optional). Auto-checks as each completes; disappears when done. Gives non-technical users a sense of progress and a path to first value. *Depends on D3-1 for the engine state.*

**D3-6 — Screen-Recording grant auto-detection + relaunch helper (S, High).** Poll `CGPreflightScreenCaptureAccess()` after sending the user to Settings; when it flips to granted, swap the copy to "Granted ✓ — Reopen now" and relaunch via a helper (`open` a launch-agent or re-exec). Removes the "is it broken?" cliff entirely. Strict upgrade over V3 §5's copy-only fix. *No dependency.*

**D3-7 — "Record a test 30 seconds" onboarding step (S, Med).** Optional final onboarding card: "Record 30 seconds of yourself talking so we can confirm mic + transcription work." Produces a real (tiny) summary, validating the whole pipeline before a real meeting — and doubles as the model-download trigger so it happens during onboarding, not mid-meeting. *Depends on D3-1.*

**D3-8 — Contextual "what is this?" disambiguation for the three capture modes (S, Med).** Inline one-liners on Record Meeting / Voice Note / auto-record (popover on first hover, or a single info row): "Record Meeting = a call. Voice Note = a quick spoken memo. Auto-record = we start when a calendar call begins." *No dependency.*

**D3-9 — Friendly installer mode for non-technical users (M, Med).** `install.sh` is engineer-facing (assumes Terminal comfort, brew, signing). Ship a notarized/pre-signed `.dmg` with models *not* bundled but an in-app first-run downloader (D3-1), so the GUI path alone produces a working app. Today the GUI path silently depends on the CLI path having run. *Depends on D3-1; larger if real notarization is in scope.*

**D3-10 — Deferred MCP "Connect to Claude" prompt (S, Med).** Don't surface MCP during onboarding (too advanced). After the user's 2nd or 3rd real meeting, a one-time Today card: "Want to ask Claude about your meetings? Connect in one click." Tapping runs `installInClaudeDesktop()` and shows the "restart Claude Desktop" step with a guide. Moves a powerful-but-buried feature to a teachable moment. *Depends on MCPInstaller (exists).*

**D3-11 — "Resume setup" entry point (S, Low).** Because every onboarding step is Skip-friendly (`OnboardingSheet.swift:167`), a user can skip everything and be stranded. Add a persistent "Finish setup" item in Settings (and a Today nudge if core permissions/engine are missing) that re-opens the onboarding sheet at the first incomplete step. *No dependency.*

**D3-12 — Vault location: explain iCloud trade-off in plain language (S, Low).** The "Use iCloud Drive (Recommended)" button (`OnboardingSheet.swift:86`) gives no reason. Add one line: "Recommended — syncs across your Macs and acts as your backup. Or keep it fully local." Ties into ENG-E backup-honesty so the FRE doesn't over-promise. *Pairs with ENG-E.*

## Top 3 picks

1. **D3-1 — In-app Setup Check before first recording.** The biggest unowned first-run risk is that the GUI app silently assumes the CLI installer ran. Closing this is the difference between "works" and "mysteriously broken" for a non-technical user.
2. **D3-3 — Bundled sample/demo meeting.** Cheapest possible path to first *value* — the user sees a real summary before committing to a live recording, and Today is never an empty void.
3. **D3-6 — Screen-Recording grant auto-detection + relaunch helper.** Turns the single most "this is broken" moment of the FRE into a smooth, confidence-building one.

**Single highest-priority recommendation overall: D3-1** — guarantee a working app from the GUI path alone with a friendly in-app setup check and visible download progress.
