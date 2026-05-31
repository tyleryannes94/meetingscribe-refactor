# Group 4 — Simulated End User: Non-Technical + Accessibility Needs

> My lens: I'm not a developer. I have low vision, lean on larger text and sometimes
> VoiceOver, and I don't open Terminal. Someone told me this app is private and I
> *want* to believe that — but I need the app to keep proving it to me, in plain
> words, at every step. I value calm, reassurance, and clarity over features.

---

## Full-app audit (through my lens)

I walked the seven workflows in my brief. Here's where I felt lost, scared, or shut out.

### 1. "Install without Terminal" — I'm blocked before I start

The very first instruction in `README.md:13-21` is a Terminal block:
`git clone … && cd … && ./install.sh`. That is a wall, not a door. I don't know what
`git` is, I've never opened Terminal, and "clone" sounds like I'm copying something
illegal. There is **no `.dmg`, no double-click installer, no App Store link** anywhere
in the repo. The "one command" framing assumes I'm comfortable typing commands — I'm
the opposite. **I cannot install this app by myself. Full stop.**

Even if a friend ran it for me, the script (`README.md:23-37`) downloads **~148 MB**
(whisper model) **plus ~4.9 GB** (Ollama model) silently, asks me to click "Always
Allow" on a scary **keychain** dialog, and warns I'll have to **quit and relaunch**
after Screen Recording. Every one of those is a moment where I'd assume something
broke and give up.

### 2. "Understand what's happening to my data" — the word *vault*

First onboarding screen (`OnboardingSheet.swift:56`) asks **"Where to store your
vault?"** I don't have a vault. A vault is a bank thing, or a crypto thing. The
subtitle (`:58`) is actually *good* plain language ("keeps all recordings,
transcripts, and notes in a single folder on your Mac") — but the **headline uses the
jargon and the body explains it**, which is backwards. The buttons say "Use iCloud
Drive (Recommended)" (`:86`) and "Change Location…" — but nobody told me what iCloud
Drive *is* or why it's recommended, and the path preview (`:74`) shows
`~/Documents/MeetingNotes` in **monospaced font** with a `~`, which reads like code to me.

### 3. "Grant scary-sounding permissions" — mostly warm, two land-mines

Credit where due: the permission screens (`OnboardingSheet.swift:296-337`) are the
**best part of the app for me**. Each one says what it captures in one sentence
("Captures your side of the conversation," `:311`) with reassuring bullets ("Used only
for audio — no video, no screenshots," `:322`; "Read-only — never writes to your
calendar," `:323`). That is exactly the tone I need everywhere.

But two things terrified me:
- **Screen Recording.** Even with the gentle copy, granting "Screen Recording" to an
  app that records my meetings *sounds* like it's watching my whole screen. The bullet
  reassures me, but the permission **name** (which is what macOS shows in its own
  dialog) does not — and the app can't change that.
- **The "quit and relaunch" step** (`:312`, `:322`). To me, "you'll need to quit and
  relaunch the app once" reads as *the app is broken and I have to restart it.* There's
  no "Reopen MeetingScribe for me" button — I'm just expected to know to do this. I
  would assume I broke something.

Also: the **Accessibility** permission (`:305`, "Accessibility (optional)") shares its
name with the macOS accessibility *settings I rely on*. Seeing an app ask for
"Accessibility" access made me nervous it would interfere with VoiceOver. (It's for the
F5 hotkey, but I had to read three lines to learn that.)

### 4. "Record my first meeting" — three doors, no guide

After onboarding, I'm dropped into the app with **no "here's how it works" overview**
(the plan flags this gap at V3 §5, and it's real). On Today I see "Record Meeting"
(`TodayView.swift:128`), the toolbar has "Ad-hoc Recording" (`:379`), and there's a
"Notes" voice-note recorder too. **Three ways to record, zero explanation of the
difference.** I don't know which one is "my first meeting." I'd freeze.

When summaries fail, the error text I'd see is **pure Terminal**: "Run `brew services
start ollama` (or open a terminal and run `ollama serve`)" (`OllamaService.swift:34`).
That is gibberish to me and it's *in a red error I can't dismiss with understanding.*

### 5. "Read the summary with large text" — the app fights my eyes

This is the worst structural finding: **there is not a single accessibility or
text-size affordance in the entire UI codebase.** I searched all of
`Sources/MeetingScribe` for `dynamicTypeSize`, `accessibilityLabel`, `VoiceOver`
handling, or a text-scale setting — **zero matches.** Instead the UI hard-codes a
custom design system (`NotionDesign.swift` / `NDS.*` tokens, `font(.system(size:…))`)
and **caps content width at 720pt** (`NotionDesign.swift:11`, `PersonDetailView:277`,
`TodayView:60`). For me that means:
- Text does not grow when I bump the system text size.
- Custom `NDS` fonts and `.caption`/`.caption2` everywhere (e.g. the dense Settings
  help text, `SettingsView.swift:104,335,341,355,371`) render **tiny** — caption2 is
  ~10pt — and I literally cannot read them.
- Buttons and chips have no `accessibilityLabel`, so **VoiceOver** would announce icons
  as "image" or read nothing useful.
The app is, today, **not usable for me without sighted help.**

### 6. "Trust that nothing left my computer" — the promise is uneven and unprovable

The README bottom line (`README.md:311`) is bold: *"No telemetry, no network calls
except to your own local Ollama."* That's the promise I was sold. But auditing the
code, that claim is **not fully true** once I touch anything beyond the core loop:
- The in-app **Chat sends my data to `api.anthropic.com`** (`AnthropicClient.swift:18`)
  — a cloud server.
- Google Drive export, Gmail contacts, Notion, Linear are all **cloud calls**
  (`GoogleDriveService.swift`, `GmailContactsService.swift`, `NotionActionItemService.swift`,
  `TaskSyncService.swift`).

So "private" is true for *record → transcribe → summarize*, but the app **never tells me,
in the moment, when something is about to leave my Mac.** The only reassurance lives in
**one buried Settings caption** (`SettingsView.swift:385`, "Nothing leaves your machine")
and one Integrations line (`IntegrationsView.swift:185`). There is **no persistent,
plain-language privacy surface** I can open to confirm "right now, nothing has been
sent." I'm asked to trust, but given no running proof — and the headline claim
over-promises versus what the optional features actually do.

### 7. Settings & Integrations — a wall of words I don't understand

If I ever opened Settings (`SettingsView.swift`) looking for "make text bigger," I'd
instead drown in: "MCP Server (for Claude Desktop / Claude Code)", "Notion MCP",
"OAuth Client ID", "Internal Integration Secret", "GGML model path", "flash-attention",
"`brew install ollama`", "`ollama pull`". Integrations (`IntegrationsView.swift:44`)
calls everything **"connectors"** and **"free API."** None of these words mean anything
to me, and there's no "simple mode" that hides them.

---

## Existing-plan items I rank highest (through my lens)

1. **V3 §5 — De-jargon "vault" → "where should we save your notes and recordings?"**
   This is the first word I hit and the first place I'm lost. Highest-value single copy fix for me.
2. **V3 §5 — Explain the Screen-Recording "quit and relaunch" warmly + add a "Reopen
   MeetingScribe" affordance.** Right now that step reads as *the app is broken.* A
   button that relaunches for me removes a give-up moment.
3. **V3 §5 — One-time "how it works" overview after onboarding (record → transcribe →
   summary → tasks).** Without it I don't know which of the three record buttons to press.
4. **V3 §5 — Disambiguate Voice Note vs Meeting recording vs Ad-hoc.** Three doors,
   no signage — I freeze at the first decision.
5. **ENG-E — Backup honesty ("stored locally; nothing claims backed-up").** I take
   "iCloud / backed up" literally; an over-promise here would cost me real data and trust.
6. **LAY-2 — Chat rail closed by default.** The cloud-calling Chat panel being open by
   default both clutters my screen and quietly invites me into the one feature that
   *isn't* private.

These help me, but **none of them address the two things that actually lock me out:
I can't install it, and I can't read it.** That's where my net-new work goes.

---

## NET-NEW recommendations

### U5-1 — No-Terminal `.dmg` installer (double-click, drag-to-Applications)
**What/why:** Ship a signed, notarized `.dmg` (or `.pkg`) as a GitHub Release asset.
Move the `brew`/whisper/Ollama bootstrap *inside* a first-launch in-app step (see U5-2),
not a shell script. The current only path is `git clone && ./install.sh`
(`README.md:13-21`), which I cannot do.
**User value:** I can install the app the same way I install everything else — by
double-clicking and dragging an icon. This is the single thing standing between me and
ever using the product.
**Effort:** L (notarization + bundling the model fetch). **Impact:** High.
**Depends on:** none (unblocks everything else for my persona).

### U5-2 — In-app "Getting things ready" setup screen (no Terminal, with progress)
**What/why:** Replace the silent ~5 GB script downloads (`README.md:28-29`) with a
friendly first-launch screen: a checklist ("Downloading the listening engine… 40%",
"Downloading the writing assistant…") with plain names, a progress bar, pause/retry,
and a one-line "this is a one-time download of about 5 GB; it may take a few minutes."
**User value:** I see *something is happening* instead of a frozen app, and I'm never
asked to run a command. Big downloads stop being a silent failure point.
**Effort:** M. **Impact:** High. **Depends on:** U5-1.

### U5-3 — "Plain Language" mode (de-jargons the whole UI, not just onboarding)
**What/why:** A single setting (ON by default for new users) that swaps every
jargon term for plain words app-wide: *vault → "your notes folder"*, *MCP → "let Claude
read your notes"*, *Ollama → "the on-device writing assistant"*, *daemon →
"background helper"*, *connectors → "apps you've linked."* Today the warm language stops
at the permission screens; Settings/Integrations are a jargon wall
(`SettingsView.swift:112,191,375`, `IntegrationsView.swift:44`).
**User value:** I can actually read and trust the whole app, not just the welcome.
**Effort:** M (a string table + term map). **Impact:** High. **Depends on:** none.

### U5-4 — Larger-Text / Accessibility mode + full Dynamic Type & VoiceOver pass
**What/why:** There is **zero** accessibility support in the UI (no `dynamicTypeSize`,
no `accessibilityLabel`, hard-coded `NDS` font sizes, 720pt width caps). Add: (a) honor
the system text-size / Dynamic Type so my OS setting scales the app; (b) an in-app
"Larger Text" slider for people who don't change it system-wide; (c) `accessibilityLabel`
on every icon button/chip so VoiceOver speaks; (d) replace `.caption2` body help text
with readable sizes.
**User value:** The app becomes usable for me at all. Right now it isn't.
**Effort:** L. **Impact:** High. **Depends on:** relates to LAY-1 (width caps).

### U5-5 — Trust / Privacy dashboard: "Right now, 0 bytes have left your Mac"
**What/why:** A dedicated, always-reachable panel (and a menu-bar glance) that shows,
in plain language and live: a big green "Everything stays on your Mac" when only the
local loop is used; a per-feature ledger ("Local: recording, transcription, summary,
people. Leaves your Mac *only if you turn it on*: Chat → Anthropic, Google Drive,
Notion, Linear"); and a running counter of bytes/requests actually sent off-device
(0 by default). Today the only proof is one buried caption (`SettingsView.swift:385`)
and a README claim (`README.md:311`) that is **technically over-stated** given
`AnthropicClient.swift:18`.
**User value:** I stop having to *trust* and start being able to *verify*, in words I
understand. This is the feature that lets me believe "private."
**Effort:** M. **Impact:** High. **Depends on:** none.

### U5-6 — Honest, in-the-moment "this will leave your Mac" confirmations
**What/why:** Any action that makes a network call to a non-local service (Chat first
message, Drive export, Notion/Linear sync) shows a one-time, plain checkpoint: "This
sends your meeting text to Anthropic's servers to answer. Everything else stays local.
Continue?" with a "don't ask again for Chat" remember.
**User value:** The privacy promise becomes specific and trustworthy instead of an
absolute claim that quietly isn't. I'm never surprised that data left.
**Effort:** S. **Impact:** High. **Depends on:** U5-5 (shares the data-flow model).

### U5-7 — "Reopen MeetingScribe for me" button after Screen Recording
**What/why:** The Screen-Recording step tells me to "quit and relaunch the app once"
(`OnboardingSheet.swift:312,322`) with no help. Add a button on that screen that
relaunches the app for me (write a marker, `NSApp.terminate` + a tiny relaunch helper),
so I never have to know what "relaunch" means or fear I broke it.
**User value:** Removes a guaranteed give-up moment for non-technical users.
**Effort:** S. **Impact:** Med. **Depends on:** none.

### U5-8 — Guided "Record your first meeting" coach mark
**What/why:** First time I'm on Today with no recordings, overlay a single calm prompt
on the "Record Meeting" button (`TodayView.swift:128`): "Ready to try it? Press here,
talk for a minute, then press Stop. I'll write the notes for you." Disambiguate the
three entry points (Meeting vs Ad-hoc vs Voice Note) with one sentence each.
**User value:** I know exactly what to press and what will happen — no freezing at
three unexplained doors.
**Effort:** S. **Impact:** High. **Depends on:** V3 §5 "how it works" overview (complements it).

### U5-9 — Human-readable status everywhere (kill Terminal in error messages)
**What/why:** Replace developer error strings shown to users with plain guidance +​
a button. E.g. `OllamaService.swift:34` ("Run `brew services start ollama`…") becomes
"The writing assistant isn't running. [Start it for me]" wired to the existing
`service.ensureRunning()` (`SettingsView.swift:729`). Same for whisper/model errors
(`README.md:217`).
**User value:** I'm never shown a command I can't run; the app fixes itself or tells me
in words. **Effort:** M. **Impact:** Med. **Depends on:** none.

### U5-10 — "Lite" simplified UI (one-button mode)
**What/why:** A toggle (offered at onboarding) that hides Integrations, MCP, Chat,
dictation, tags, and the Notion/Linear/Drive clutter, leaving: Today (Record + my
meetings) and the meeting summary. The full app is overwhelming
(`SettingsView.swift` has ~12 dense sections).
**User value:** I get a calm app that does the one thing I came for, and I can grow into
more later. **Effort:** M. **Impact:** Med. **Depends on:** U5-3 (plain language).

### U5-11 — Spoken / read-aloud summary ("Read this to me")
**What/why:** A "Read aloud" button on each meeting summary using `AVSpeechSynthesizer`.
Given my low vision, even with larger text, *hearing* the summary is often easier than
reading a wall of it.
**User value:** I can consume my notes hands-free and eyes-free. Pairs naturally with a
local-first app (no cloud TTS needed). **Effort:** S. **Impact:** Med.
**Depends on:** none.

### U5-12 — Plain-language permission pre-summary + rename "Accessibility" ask
**What/why:** Before the macOS dialogs, show one screen: "macOS will now ask you 4
yes/no questions. Saying yes lets the app hear your meetings and label them. It's safe —
here's what each one means." And relabel the F5 permission from "Accessibility
(optional)" (`OnboardingSheet.swift:305`) to "Keyboard shortcut for dictation
(optional)" so I don't confuse it with the VoiceOver/accessibility settings I depend on.
**User value:** The scariest moment (a barrage of system permission popups) becomes
predictable and the naming stops alarming accessibility users specifically.
**Effort:** S. **Impact:** Med. **Depends on:** none.

---

## Top 3 picks

1. **U5-1 — No-Terminal `.dmg` installer.** Nothing else matters if I can't install the
   app, and `git clone && ./install.sh` means I can't. This is the gate.
2. **U5-4 — Larger-Text / Accessibility mode + Dynamic Type & VoiceOver pass.** The
   second gate: even installed, the app has *zero* accessibility support and tiny
   hard-coded `.caption2` text I cannot read.
3. **U5-5 — Trust / Privacy dashboard showing "0 bytes have left your Mac."** This is
   what lets me actually *believe* the privacy promise — especially since the README's
   "no network calls except local Ollama" is over-stated versus the cloud Chat
   (`AnthropicClient.swift:18`) and cloud export features.

**Single highest-priority recommendation overall:** **U5-1 (no-Terminal installer).**
For a non-technical user it's binary — I either can run the app or I can't, and today
I can't.
