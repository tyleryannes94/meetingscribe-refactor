# End-User Persona — Non-Technical User (therapist / coach / sales professional)
> I bought this to remember what my clients tell me. The moment the app says "Ollama," "vault," "MCP," or "whisper-cli," I assume it wasn't built for me — and the moment I can't delete a session, I can't ethically use it at all.

## Full-app audit (through my lens)

I walked the app as Dana, a couples therapist who records sessions (with consent), keeps notes on ~40 clients, and has never opened Terminal.

### Scenario 1 — First launch to first recorded conversation

**The first sentence of the app is jargon.** Onboarding screen 1 is titled **"Where to store your vault?"** (`Sources/MeetingScribe/UI/OnboardingSheet.swift:60`). Dana doesn't have a vault; banks have vaults. The body copy underneath is actually perfect — "MeetingScribe keeps all recordings, transcripts, and notes in a single folder on your Mac" (`OnboardingSheet.swift:62`) — the title just needs to match the body's voice. The folder picker also says "Choose a folder for your MeetingScribe vault" (`OnboardingSheet.swift:129`).

**Permission screens are 80% excellent, with three engineer leaks.** The consequence-led bullets ("Used only for audio — no video, no screenshots", `OnboardingSheet.swift:379`) are exactly right. But: "Captures the OTHER side of the call via **ScreenCaptureKit**" (`OnboardingSheet.swift:369`) — an Apple framework name in a permission explainer; "**Whispr-Flow-style** F5 dictation" (`OnboardingSheet.swift:378`) — explains one product via another product Dana has never heard of; and "Accessibility (optional)" leads with a hotkey she doesn't know exists (`OnboardingSheet.swift:372`).

**Setup Check is genuinely good — and then hands her a developer tool.** `SetupCheckSheet.swift` is the most persona-aware surface in the app ("A ~140 MB on-device speech model. Downloads once.", `SetupCheckSheet.swift:61`). But the second row is "Local AI engine (Ollama)" with a **"Get Ollama"** button that opens ollama.com (`SetupCheckSheet.swift:88-91`) — a developer download page with terminal examples — then asks her to "come back and re-check" (`SetupCheckSheet.swift:100`). "Skip for now" (`SetupCheckSheet.swift:45`) carries no stated consequence, so Dana skips it, records her first session, and silently gets no summary forever.

**Strong:** `SampleMeetingSeeder.swift:1-54` (a finished example meeting on first run, "safe to delete anytime") is exactly what a non-technical user needs — Today is never blank and "what this app produces" is shown, not described.

### Scenario 2 — Something fails silently: do I understand what happened?

**Success notifies; failure doesn't.** The pipeline posts "Meeting ready: …" only on completion (`Sources/MeetingScribe/MeetingScribeApp.swift:291-303`, `Notifications/NotificationManager.swift:200`). When summarization fails, the only record is an internal analytics event (`MeetingManager.swift:696` → `ActivityLog.summaryFailed`). Dana finds out days later, mid-session-prep, when the Summary tab says: **"Ollama wasn't running when this meeting finished, or summarization failed."** (`UI/MeetingSummaryTab.swift:175`) — a sentence that blames a noun she's never met and offers two alternative causes with no verdict. (Credit: the "Generate Summary" retry button at `MeetingSummaryTab.swift:194` is the right affordance — the copy above it is the problem.)

**Raw stderr reaches the screen.** The live-transcription error banner (`UI/MeetingTranscriptTab.swift:128-140`) renders `LiveTranscriber` messages verbatim, including: *"whisper-cli failed (1): model file is corrupted or empty. **Re-download it via ./scripts/setup.sh**"* and *"Try ./scripts/build-whisper-cpu.sh for a CPU-only fallback"* (`Transcription/LiveTranscriber.swift:222-227`). This tells a therapist mid-client-call to go run shell scripts. The empty-audio path is similar: "Audio file at \(p) is empty (0 bytes)…" (`Transcription/WhisperRunner.swift:73`) leaks a filesystem path.

**Ambiguity is offloaded onto the user.** "This meeting didn't capture audio, **or** transcription failed." (`MeetingTranscriptTab.swift:35`). The app knows which one happened (it has `MeetingHealthBadge` reasons at `UI/MeetingHealthBadge.swift:60-61`); the copy refuses to say.

### Scenario 3 — Finding a past conversation without knowing the word "transcript"

⌘K search (`UI/GlobalSearchView.swift`) is the right mechanism, and the FTS5/hybrid plumbing behind it is real (`GlobalSearchView.swift:229-246`). Two failures through this lens:

1. **Results give no evidence.** `ftsEntity()` maps a match to **title + date only** (`GlobalSearchView.swift:253-266`). Dana searches "panic attacks" and gets "Session — Mar 4". Did it match? Where? She has to open each result and hunt. No matched-sentence snippet, no highlight — the single biggest comprehension gap in recall.
2. **The placeholder undersells the superpower.** "Search meetings, notes, projects, action items…" (`GlobalSearchView.swift:101`) describes *containers*. Dana's mental model is "find the conversation where Maria mentioned her sister." Nothing tells her she can search what was *said*.

Also: the sidebar has "Voice Notes" while search filters offer both "Notes" and "Voice" (`GlobalSearchView.swift:35-36` vs `MainWindow.swift:18`) — two namespaces for the same word.

### Scenario 4 — Do I trust this app with intimate client conversations?

**The privacy story is told in footnotes.** "Running locally via Ollama. No API key, no outbound traffic." (`UI/ChatPanel.swift:94`); "your meeting content will leave this device" warning (`UI/SettingsView.swift:566`); "Nothing leaves your machine" (`SettingsView.swift:572`). All good sentences — scattered across captions in five places, none of which Dana will read. There is **no Privacy section anywhere in Settings** (section list: `SettingsView.swift:77-581` — About, You, Storage, Capture, …, "MCP Server (for Claude Desktop / Claude Code)" at :243, "Whisper.cpp" at :477, "Ollama" at :552).

**You cannot delete a conversation.** Tasks have delete + undo + a 30-day trash (`UI/TaskTrashView.swift:53`); people have delete with a clear warning (`People/PeopleListView.swift:373`); **meetings have no delete affordance at all** — `deleteMeeting`/"Delete meeting"/"Move to Trash" appear nowhere in the app target, and `MeetingDetailHeader.swift`'s ⋯ menu offers edit/re-transcribe/recover/export only (`UI/MeetingDetailHeader.swift:396`). For a clinician, a recording system with no erase function is disqualifying — not a Phase-2 nicety.

**The paywall leaks developer scaffolding.** Now that PR #89 wired `ProPaywallView` into `MainWindow`, end users can see: *"StoreKit 2 purchase is not yet wired. To unlock Pro during development, set FeatureGate.shared.isPro = true in Xcode."* (`Monetization/ProPaywallView.swift:91`) and *"**MCP relationship tools** require Pro"* (`ProPaywallView.swift:100`). Nothing erodes trust in a privacy product faster than visibly unfinished commerce copy.

**iMessage analysis is trust-jarring as presented.** "Analyze messages" / "Deep analysis" / "Custom analysis prompt" on a person (`People/PersonDetailView.swift:1780, 2150, 1882`) reads as surveillance until you find the one caption explaining it's local (`UI/IntegrationsView.swift:164`). The explanation lives in Integrations; the scary buttons live on the person.

**Strong trust/warmth surfaces worth protecting:** `QuickEncounterSheet.swift:95-135` ("Log check-in", "How did you connect?", "How did it feel?") is the best copy in the app — zero jargon, emotionally literate, auto-saves on one tap. `HealthCheckSheet.swift:83-99` states consequences plainly ("Not granted — your voice won't be captured"). The auto-record explainer at `SettingsView.swift:147` ("…meetings you skip won't trigger a surprise recording") anticipates exactly the fear a recorder-app user has.

### Smaller observations
- Meetings and People use nearly identical sidebar glyphs: `person.2.fill` vs `person.2` (`MainWindow.swift:24-25`). Meetings shouldn't wear a people icon at all — Dana confuses the two tabs for her first week.
- "Ad-hoc Recording" (`UI/TodayView.swift:638`, menu bar `MainWindow.swift:746`) — "ad-hoc" is consultant-speak; "Quick recording" says the same thing.
- Settings "Impromptu detection" (`SettingsView.swift:169`) names the mechanism, not the benefit ("Notice calls automatically").
- `QuickNotesView.swift:407` tells the user to "run whisper against the recorded audio"; `:413` pitches "Task, Context, References, Evaluate, Iterate" prompt-engineering structure inside a voice-notes app.
- `IntegrationsView.swift:191-199` and `SettingsView.swift:555` put `` `ollama pull …` `` backtick commands and "brew install ollama" (`SettingsView.swift:944`) in user-facing copy.

## Existing-plan items I rank highest

1. **HELD item #6 — onboarding de-jargon sweep (1E)** — it's blocked only on a voice decision; the jargon inventory below (U4-1) *is* that decision, ready to greenlight.
2. **Retention & right-to-forget (2G)** — through this lens it's not data-layer hygiene; "Delete this conversation" is the difference between a therapist adopting or abandoning, and today the affordance doesn't exist at all.
3. **Provable-privacy panel (1D)** — the five scattered privacy captions need one room; this is the trust qualifier for the intimate-conversations buyer.
4. **Apple Foundation Models backend (Phase 3)** — removes the "go download a developer tool from ollama.com" cliff entirely; for this persona it's the single biggest activation unlock and deserves to pull forward.
5. **Live + post-recording status feedback (2E)** — "did it capture?" is the fear that makes non-technical users double-record on their phone as backup.
6. **SetupCheck required-vs-optional split (1E, held)** — recording must never look blocked on the optional summary engine.

## NET-NEW recommendations

### U4-1 — Jargon inventory + voice decision, enforced by lint
- **What/why:** The held de-jargon item needs a concrete word map, not a vibe. Proposed voice: **name things by what they hold or do, never by what they're built from; technology names survive only as parentheticals inside Settings → Advanced.** The map: "vault" → "your library" (folder metaphor stays: "one folder on your Mac"); "Ollama" → "the summary engine" / "on-device AI (Ollama)" in Settings only; "MCP" → "Claude connection"; "whisper / whisper-cli / Whisper.cpp" → "speech-to-text engine"; "ScreenCaptureKit" → "macOS screen-audio access"; "Ad-hoc Recording" → "Quick recording"; "Impromptu detection" → "Notice calls automatically"; "Whispr-Flow-style" → delete; FTS5/embeddings/daemon → never user-facing. Then add a **design-lint denylist rule** (CI already runs design-lint per `HELD-ITEMS.md`) failing any new `Text("…Ollama|vault|MCP|whisper|daemon…")` outside `SettingsView` Advanced — so the sweep can't regress. Specific first targets: `OnboardingSheet.swift:60,129,369,372,378`, `SetupCheckSheet.swift:76`, `MeetingSummaryTab.swift:119,175`, `ProPaywallView.swift:100`, section headers `SettingsView.swift:243,477,552,570`.
- **User value:** Dana never reads a word she has to google; comprehension on every surface.
- **Effort:** S (copy) + S (lint rule)
- **Impact:** High
- **Depends on:** none (it unblocks held item #6)

### U4-2 — Two-layer Settings: everyday vs. Advanced
- **What/why:** Settings is one scroll where "Your name" (`SettingsView.swift:129`) sits between "Software Update" build-from-source instructions (`:125`) and, further down, "MCP Server (for Claude Desktop / Claude Code)" (`:243`), "Whisper.cpp" (`:477`), "Notion MCP" (`:322`), and `ollama pull` commands (`:555`). Restructure into ~5 plain tabs — General · Recording · Notifications · **Privacy & data** · Connections — with a collapsed **Advanced** group holding Whisper.cpp, MCP, Notion MCP, Cross-device sync, and model selection. Power features become discoverable-on-purpose instead of ambient intimidation.
- **User value:** A non-technical user finds every setting she'd actually change without scrolling past terminal commands; power users lose nothing.
- **Effort:** M
- **Impact:** High
- **Depends on:** U4-1 (section names)

### U4-3 — Human-readable error layer (one `ErrorPresenter`, three fields)
- **What/why:** Raw engine output reaches the UI: `MeetingTranscriptTab.swift:128-140` renders `LiveTranscriber.swift:222-227`'s "whisper-cli failed (1)… Re-download it via ./scripts/setup.sh" verbatim; `WhisperRunner.swift:73` leaks file paths; `IntegrationsView.swift:278` says "run `ollama serve`". Add a single mapping layer: every user-visible error becomes **{what happened (one plain sentence), what it means for your recording, one button}** — and the button wires to the *in-app* remediation that already exists (`SetupReadiness.downloadModel()` at `SetupReadiness.swift:36`, `startOllama()` at `:50`), never a script. Raw text moves behind a "Details" disclosure for support.
- **User value:** Failure stops feeling like the user's fault; recovery is one click ("Re-download the speech model") instead of a shell script.
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### U4-4 — Failure parity: notify when a summary *doesn't* arrive
- **What/why:** Only success notifies (`MeetingScribeApp.swift:291-303`); failure logs to internal analytics (`MeetingManager.swift:696`). Add (a) a notification — "Session saved. The summary is waiting — open MeetingScribe to finish it." — and (b) a Today banner on any meeting <48h old with transcript-but-no-summary: "Yesterday's conversation has no summary yet → Generate". The retry machinery exists (`MeetingSummaryTab.swift:184-198`); it's just never *offered*, only findable.
- **User value:** Dana learns about a failed summary the same evening, not during next week's session prep. Clicks to recovery: discover-by-accident → 1 notification tap.
- **Effort:** S
- **Impact:** High
- **Depends on:** U4-3 for the wording

### U4-5 — Search results that show the matched sentence
- **What/why:** `ftsEntity()` returns title+date only (`GlobalSearchView.swift:253-266`). Surface the FTS5 `snippet()` for the match — the actual sentence containing "panic attacks", query terms bolded, speaker label when diarization knows it — as a second line on each result row. Rename the placeholder (`GlobalSearchView.swift:101`) to **"Find anything that was said — people, conversations, tasks…"**. This is also the premium-feel move: Things 3/Notion-grade search shows *evidence*, not filenames.
- **User value:** "Find the conversation where Maria mentioned her sister" works on the first try, with proof, without knowing the word "transcript". Confidence per search: open-3-results-and-scan → read-one-snippet.
- **Effort:** M
- **Impact:** High
- **Depends on:** none

### U4-6 — Trust Center: one room for "Your data", including Delete this conversation
- **What/why:** Unify the planned provable-privacy panel (1D) and right-to-forget (2G) into a single user-facing surface — **Settings → Privacy & data** plus a matching item in the meeting ⋯ menu. Contents: where everything lives ("Open my folder" button on the real path), what leaves this Mac ("Nothing — checked live", with the remote-Ollama and phone-access toggles relocated here from `SettingsView.swift:565,982`), who else can read it (Claude connection on/off, iMessage analysis on/off with the local-only explanation moved from `IntegrationsView.swift:164` to the point of use), and **"Delete this conversation"** (audio + transcript + summary + index, with undo-window) added to `MeetingDetailHeader.swift`'s menu — the affordance that today exists for tasks (`TaskTrashView.swift`) and people but not meetings. The net-new part is the *unification + the meeting-level delete entry point*: trust is evaluated in one glance, not assembled from captions.
- **User value:** The "can I ethically use this with clients?" question gets a one-screen yes. This is the conversion surface for therapists, coaches, lawyers, and sales pros under NDA.
- **Effort:** M (UI) — the purge itself is planned 2G work
- **Impact:** High
- **Depends on:** 2G retention primitive for full purge; UI can ship first with folder-level delete

### U4-7 — Per-client consent tracking + recording-etiquette script
- **What/why:** The plan's 1D includes a consent-script helper; go further for the relationship professional: a **"Consent noted ✓" field on Person** (set once, shown as a quiet badge), a one-time card on first recording with a new attendee ("Recording someone? Here's a one-line script: *'I keep a private recording on my computer only — nothing goes to the cloud. OK?'*"), and the badge surfaced in the pre-meeting brief. Two-party-consent states make this a legal requirement for exactly this persona.
- **User value:** Turns a legal anxiety into a workflow feature; deepens the "people-first" pillar (consent is a property of a *relationship*, not a meeting).
- **Effort:** S–M
- **Impact:** Med (High for the professional wedge)
- **Depends on:** U4-6 (lives alongside the trust surfaces)

### U4-8 — Fix the sidebar's identity confusion (icons + names)
- **What/why:** Meetings uses `person.2.fill` and People uses `person.2` (`MainWindow.swift:24-25`) — the two most important tabs are visually twins. Give Meetings a conversation/calendar glyph (`bubble.left.and.bubble.right.fill` or `calendar`); align the "Notes"/"Voice"/"Voice Notes" naming triangle (`MainWindow.swift:18`, `GlobalSearchView.swift:35-36`) to one word ("Voice notes" everywhere). Rename "Ad-hoc Recording" → "Quick recording" in the menu bar (`MainWindow.swift:746`) and Today placeholder (`TodayView.swift:638`).
- **User value:** Week-one navigation errors disappear; the rail reads as designed rather than assembled.
- **Effort:** S
- **Impact:** Med
- **Depends on:** U4-1

### U4-9 — Capability-aware UI: never advertise what can't work yet
- **What/why:** Progressive disclosure keyed on `SetupReadiness`: while Ollama is absent, the Assistant rail, "Ask Chat" search rows (`GlobalSearchView.swift:305-311`), summary placeholders, and Re-polish buttons should not present as broken features — they should present as one *locked* state: "Summaries are off — turn on the summary engine (one download, ~5 min)" linking to the Setup Check. Today the upcoming-meeting placeholder already promises "Ollama will draft a summary" (`MeetingSummaryTab.swift:119`) to a user who skipped Ollama and will never get one.
- **User value:** The app makes one promise it can keep, instead of five it can't; the upgrade moment is a single understandable choice.
- **Effort:** M
- **Impact:** High
- **Depends on:** U4-1 (copy), pairs with planned SetupCheck split

### U4-10 — Paywall copy emergency pass
- **What/why:** `ProPaywallView.swift:91` ships developer instructions ("set FeatureGate.shared.isPro = true in Xcode") to end users now that the sheet is wired (PR #89), and `:100` sells "MCP relationship tools". Replace with honest pre-launch copy ("Pro purchasing isn't available yet") or gate the sheet until StoreKit lands; rename the MCP bullet "Ask Claude about your relationships".
- **User value:** The single cheapest trust save in the app — unfinished commerce copy on a privacy product reads as "this is someone's hobby project."
- **Effort:** S
- **Impact:** High (trust), trivially small
- **Depends on:** none

### U4-11 — Replace first-summary confetti with a "here's what just happened" recap
- **What/why:** A concrete redesign of the planned Day-0 confetti (1E): after the first real recording finalizes, show a one-time three-row card narrating the artifacts in plain words — "**Recorded** (the audio file, on this Mac) → **Typed out** (every word, searchable) → **Summarized** (the short version)" — each row tappable to that artifact, ending with "All of this stayed on your Mac." Celebration without comprehension is sugar; this builds the mental model that makes every later surface legible (and is the moment to teach ⌘K).
- **User value:** The user who understands the three artifacts never needs the word "transcript" explained again.
- **Effort:** S–M
- **Impact:** Med-High
- **Depends on:** none

## Top 3 picks

1. **U4-6 — Trust Center + "Delete this conversation"** — the buy/no-buy surface for everyone whose conversations are sensitive; meeting deletion currently doesn't exist anywhere in the UI.
2. **U4-3 + U4-4 — human-readable errors + failure-parity notifications** — the app currently fails in engineer-speak or in silence; both are abandonment events for this persona.
3. **U4-5 — matched-sentence search snippets** — turns recall from "search then hunt" into "search then see," without the user learning any vocabulary.

**Single highest-priority recommendation overall:** greenlight HELD item #6 *using the U4-1 word map as the voice decision* — it is S-effort, already approved in spirit by two audits, blocks nothing, and every other comprehension fix (U4-2, U4-8, U4-9, U4-11) inherits its vocabulary. Pair it with U4-10 in the same PR since the paywall is now live and leaking dev copy.
