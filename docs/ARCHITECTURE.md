# MeetingScribe — Architecture & Technical Breakdown

A deep dive into how MeetingScribe is built, the responsibilities of each module, and the data + control flow between them. Audience: developers reading or extending the code.

> The companion [USER_GUIDE.md](USER_GUIDE.md) covers the same app from the user's perspective. This document assumes you've at least skimmed that.

---

## High-level

MeetingScribe is a Swift / SwiftUI macOS 14+ app. The codebase is ~31k lines across 250+ Swift files. It's compiled with SwiftPM (`swift build -c release`) and bundled into a normal `.app` with `make app`. There are three executable targets and two libraries:

| Target | Kind | Purpose |
|---|---|---|
| `MeetingScribe` | App (executable) | The Mac app itself. SwiftUI scenes + everything below. |
| `MeetingScribeMCP` | Executable | Standalone JSON-RPC stdio server that exposes MeetingScribe data to Claude Desktop / Claude Code via MCP. Bundled inside the app and registered with Claude on opt-in. |
| `NotionMCP` | Executable | Optional second MCP server that surfaces a Notion workspace to Claude. Bundled alongside but registered separately. |
| `MeetingScribeShared` | Library | Decode-only DTOs (`MeetingDTO`, `PersonDTO`, `QuickNoteDTO`, `ActionItemDTO`, `JSONValue`, `SchemaEnvelope`). Imported by all three executables so the MCP servers can read the app's on-disk state without re-implementing the model layer. |
| `SecondBrainCore` | Library | Dependency-free `Person` / `Encounter` models intended for a future iOS target. Not yet used by the app itself; lives parallel to `MeetingScribe.Person`. |

External dependencies (Package.swift): Sparkle (auto-updates) and Apple's `ml-stable-diffusion` (Core ML SD for the Media tab).

External tools the app drives via subprocess: `ollama` (LLM runtime), `whisper-cli` (whisper.cpp), `afconvert` (Apple's m4a → wav converter). All three are expected to be installed via Homebrew; the app surfaces clear errors when they're missing and, where possible, auto-downloads model files on first use.

---

## Top-level source layout

```
Sources/
├── MeetingScribe/                    (the app)
│   ├── MeetingScribeApp.swift        @main — SwiftUI App scene + boot
│   ├── MeetingManager.swift          Central @MainActor app-state controller
│   ├── MeetingPipelineController.swift
│   ├── RecordingMonitor.swift
│   ├── WorkspaceIndex.swift          Search + entity catalog (extension on MeetingManager)
│   ├── AI/                           OllamaService (LLM HTTP client)
│   ├── ActionItems/                  Action items + projects + initiatives
│   ├── Audio/                        ScreenCaptureKit + AVAudioEngine recording
│   ├── Backup/                       Export and snapshot
│   ├── Calendar/                     EventKit wrapper + cache
│   ├── Chat/                         In-app assistant (Anthropic + Ollama clients, tools)
│   ├── Coaching/                     Real-time meeting hints (experimental)
│   ├── Compliance/                   Per-meeting recording-consent gating
│   ├── Detection/                    AppDetector — sees when Zoom/Meet is foregrounded
│   ├── Diagnostics/                  AppLog, ErrorReporter, KeychainStore
│   ├── Export/                       Google Drive sync + Markdown exporters
│   ├── Followup/                     LLM-generated follow-up emails / messages
│   ├── Hotkey/                       Carbon API global hotkey + QuickDictation
│   ├── MCP/                          MCPInstaller — writes/updates Claude config
│   ├── MediaGeneration/              Core ML Stable Diffusion image generator
│   ├── Models/                       Meeting, NoteTemplate, Settings, Tag, WorkspaceLinks
│   ├── Notifications/                UNUserNotificationCenter wrapper
│   ├── People/                       Second-brain CRM (Person, store, FTS5 index, importers)
│   ├── QuickNotes/                   Voice notes (separate from meeting recordings)
│   ├── Storage/                      MeetingStore, TagStore, MeetingBodyCache, AudioManifestStore
│   ├── Sync/                         Lightweight cross-device sync (Box, S3-compatible)
│   ├── Team/                         Per-user identity + team scoping
│   ├── Transcription/                whisper.cpp runner + diarization
│   ├── UI/                           SwiftUI views, by section
│   ├── Updates/                      Sparkle integration
│   └── Widgets/                      Quick-add menu bar widget
├── MeetingScribeMCP/main.swift       The JSON-RPC stdio server
├── MeetingScribeShared/              Decode-only DTOs + JSONValue + SchemaEnvelope
├── NotionMCP/main.swift              Notion-querying MCP server
└── SecondBrainCore/                  Dependency-free Person/Encounter for future iOS
```

---

## Boot sequence

`MeetingScribeApp` (`@main`) is the SwiftUI scene definition. It owns the top-level `@StateObject`s:

- `CalendarService` — EventKit wrapper, publishes `upcoming: [Meeting]`
- `MeetingManager` — the central app-state controller (recording state, past meetings list, action items, etc.)
- `NotificationManager` — UNUserNotificationCenter wrapper
- `AppDetector` — runs an NSWorkspace observer that sees when Zoom or Google Meet (in a browser tab) is foregrounded
- `FloatingOverlayController` — manages the small "recording in progress" pill window
- `ChatSession` — owns the running chat conversation + tool dispatch
- `UpdaterController` — Sparkle wrapper

In `startServices()` (run from `.task` on the root view), boot is split into two phases:

1. **Fast path** (synchronous on main actor, must complete before any user interaction):
   - One-time settings migrations (e.g. `migrateOllamaModelIfNeeded()` bumps `llama3.1:8b` → `qwen2.5:7b` on existing installs)
   - Wire notification handlers, register the global hotkey, attach chat tools to the manager, observe settings changes
2. **Background** (`Task.detached(priority: .utility)` or similar):
   - Prime the meeting index from disk
   - Keychain migration (slow first-keychain-unlock)
   - Request notification authorization
   - `ensureOllamaRunning()` — auto-start `ollama serve` if the user has the binary but isn't running it
   - Clean up orphaned audio chunks
   - Warm the top-N meeting body cache so the first detail click is instant

This split exists because earlier versions ran everything on the fast path and the window would freeze for several seconds on launch. The pattern now is: anything that needs to be true before the first UI event = fast path; everything else = detached task.

---

## The recording pipeline

End-to-end, what happens when you click "Record meeting":

```
MeetingManager.startRecording()
   │
   ├─→ AudioRecorder.start(in: meetingDir, segment: index)
   │       │
   │       ├─→ MicRecorder      (AVAudioEngine → ChunkedAudioWriter, 5-min .m4a segments)
   │       └─→ SystemAudioRecorder (ScreenCaptureKit → ChunkedAudioWriter)
   │
   ├─→ LiveTranscriber.start(meetingDir)
   │       │
   │       └─→ Polls every 30s for completed segments, runs whisper-cli on each,
   │           emits SwiftUI-bindable rolling transcript
   │
   └─→ floatingOverlay.show() — small pill window with timer + stop button

[ user clicks Stop ]

MeetingManager.stopRecording()
   │
   ├─→ AudioRecorder.stop() → returns directory + per-source file lists
   ├─→ liveTranscriber.renderMarkdown() → captures whatever live got
   ├─→ pipelineController.finalize(meeting:, audioResult:, liveTranscript:)
   │       │
   │       ├─→ Decide: is the live transcript long enough to use as-is, or
   │       │           should we re-run whisper-cli over the full audio for a
   │       │           higher-quality pass? (Threshold + per-source heuristics.)
   │       │
   │       ├─→ If re-running: WhisperTranscriber.transcribe(sources: …)
   │       │       │
   │       │       └─→ Per source: afconvert to 16 kHz mono WAV →
   │       │           WhisperRunner.run(audio:, output: .segments)
   │       │             ├─→ Tries GPU first (Metal backend)
   │       │             ├─→ On empty output (pre-M5 Metal bug), retries on CPU
   │       │             └─→ Writes JSON via whisper-cli's --output-json,
   │       │                 parses into segments
   │       │
   │       ├─→ Merge per-source segments → speaker-labeled markdown
   │       │   ("Me: …" for mic, "Them: …" for system audio)
   │       │
   │       ├─→ Write transcript.md to meetingDir
   │       │
   │       ├─→ OllamaService.summarize(meeting:, transcript:)
   │       │       │
   │       │       └─→ POSTs to local Ollama /api/generate with the
   │       │           summary prompt template — produces a structured
   │       │           Markdown doc with TL;DR, decisions, action items,
   │       │           open questions, notable quotes.
   │       │
   │       ├─→ Write summary.md
   │       │
   │       ├─→ ActionItemExtractor.extract(from: summary)
   │       │       │
   │       │       └─→ Parses the "## Action Items" section into
   │       │           ActionItem records (id, title, owner, due, priority),
   │       │           merges into ActionItemStore
   │       │
   │       ├─→ If autoExtractPeople: PersonExtractionController runs
   │       │   a second Ollama pass to list people mentioned in the
   │       │   transcript, then publishes suggestions on the Today tab
   │       │
   │       └─→ Update meeting.json with `health` status, mark
   │           transcribingIDs.remove(meeting.id)
   │
   └─→ state = .idle, pastMeetings refreshed
```

`MeetingPipelineController` owns this entire post-stop flow as a separate `@MainActor` `ObservableObject` (split from `MeetingManager` in Phase 6 so views observing pipeline progress don't invalidate on unrelated state changes). It also owns the "Transcribe Now" button state per meeting, exposed as `transcribingIDs: Set<String>`.

### Audio capture details

- **Mic** (`MicRecorder`): `AVAudioEngine` input node tap, configurable sample rate. Buffer level emitted to `AudioLevelMeter` for the UI VU meter. Auto-restart on input config changes (e.g. plugging in headphones mid-call).
- **System audio** (`SystemAudioRecorder`): `SCStream` from ScreenCaptureKit, audio-only filter. Catches everything the speakers would play — Zoom, browser tab, system sounds. Auto-restart on `SCStreamDelegate.stream(_:didStopWithError:)`.
- **Chunked writing** (`ChunkedAudioWriter`): rolls a new `.m4a` file every 5 minutes so the live transcriber has digestible segments AND so a crash mid-meeting only loses the trailing partial chunk. Files written via `AVAssetWriter` with passthrough — no transcoding during capture.
- **Manifest** (`AudioManifestStore`): per-meeting `audio/manifest.json` records which segment files belong to which source. Replaces filename-parsing as the source of truth.

### Transcription details

- **`WhisperRunner`**: single place that knows how to invoke `whisper-cli`. Consolidated from three near-identical earlier implementations. Owns: argv construction (including the documented "do NOT pass `--no-context`" guard), the GPU→CPU empty-output retry, subprocess lifecycle, stderr capture for diagnostics, and the GPU vs CPU run selection.
- **`WhisperTranscriber`**: batch use case — takes a list of `(source, file)` pairs, runs them all, merges into speaker-labeled segments.
- **`LiveTranscriber`**: streaming use case — polls every 30s for new completed segments and runs them through `WhisperRunner`. Owns its own rolling-cache so already-processed segments don't get redone.
- **`QuickTranscribe`**: one-shot use case for voice notes + dictation. Synchronous (semaphore-wrapped) because the dictation hotkey can't be async.
- **Auto-bootstrap**: if `~/Documents/MeetingNotes/models/ggml-base.en.bin` is missing on the first transcription, `WhisperRunner.tryAutoDownloadBaseEnModel` pulls it from the canonical whisper.cpp HuggingFace host (~148 MB) and installs it atomically. Only fires for the default base.en path so a user with a custom model isn't overwritten.

### Summarization details

`OllamaService` is a thin HTTP client against the local Ollama server (`http://127.0.0.1:11434`). Two endpoints used:

- `POST /api/generate` — single-shot prompt → completion. Used by summarizer, transcript polisher, person extractor, conversation analyses.
- `POST /api/chat` — multi-turn conversation with tool calls. Used by the in-app chat (see below).

`OllamaService.ensureRunning()` launches `ollama serve` as a detached `nohup` process if the server isn't responding. Logs go to `<storage>/logs/ollama.log`.

Connection state is tracked via an `OSAllocatedUnfairLock` with a 5-second freshness window so a burst of generate calls only pays one `/api/tags` probe.

---

## The chat system

The chat is the most complex subsystem. Three things make it work:

### 1. `OllamaChatClient` — the runtime

Wraps Ollama's `/api/chat` endpoint with native tool calling. The flow:

```
ChatSession.sendUserMessage("…")
   │
   └─→ OllamaChatClient.send(messages:, system:, tools:, runTool:)
         │
         └─→ while iterations < maxIterations (default 6):
               │
               ├─→ POST /api/chat with the full conversation +
               │   tool catalog (translated to OpenAI-compatible
               │   tools format)
               │
               ├─→ Decode response. If parsed.message.tool_calls is
               │   empty BUT parsed.message.content contains a leaked
               │   JSON tool call (small-model regression), recover via
               │   extractLeakedToolCall() and synthesize the call.
               │
               ├─→ For each tool call:
               │     ├─→ Compute signature = "<tool>:<sorted-json args>"
               │     ├─→ If seenToolSignatures contains it: short-circuit
               │     │   with a "you already called this" tool_result and
               │     │   skip execution. (Stops models from looping.)
               │     └─→ Otherwise: await runTool(name, input), append
               │         the result as a tool_result block.
               │
               ├─→ If no tool_calls and content non-empty: return
               │   (the assistant produced a final answer)
               │
               └─→ Otherwise loop with the tool results in context
```

Several robustness features:

- **Auto-pull on 404**: if Ollama responds 404 with "model 'X' not found", parse the model name, emit a "Pulling local model" notice into the chat, run `ollama pull` inline, and retry the call. Only one attempt per session via `triedAutoPull` flag.
- **Tool-call dedup**: per-session `seenToolSignatures: Set<String>` (signature = canonical JSON of args). Stops small models from looping on the same tool with the same input.
- **Leaked-JSON recovery**: when the model emits `{"name": "list_meetings", "parameters": {…}}` as plain text instead of populating `tool_calls` (a known `llama3.1:8b` failure mode), `extractLeakedToolCall` scans the content for the LAST `0x2b` byte (typedstream object marker) after the NSString class hash and reconstructs the call.
- **`num_ctx = 4096`**: deliberately conservative. Prefill is the dominant per-turn cost on M-series Macs; everything in the chat fits comfortably.

### 2. `ChatTools` — the tool catalog + dispatcher

`ChatTools` is a thin router that owns five domain-specific handlers. Each handler exposes its own `tools: [AnthropicClient.Tool]` catalog and a `run(name:input:)` that returns `nil` if the call isn't for them:

| Handler | Tools |
|---|---|
| `MeetingChatTools` | get_overview, list_meetings, get_meeting, get_transcript, get_notes, get_summary, list_voice_notes, get_voice_note |
| `ActionItemChatTools` | list_action_items, create_task, set_action_status, set_action_priority, set_action_due_date, list_projects |
| `IntegrationChatTools` | push_action_item_to_notion, sync_external_tasks, linear_list_projects, linear_list_teams, linear_create_issue, export_meeting_to_drive |
| `FileChatTools` | list_chat_folders, list_files, read_file, write_file, edit_file, search_files |
| `PeopleChatTools` | list_people, get_person, get_person_messages, list_person_meetings, attach_note_to_person |

Adding a tool touches one ~200-line file. Each handler is `@MainActor` and conforms to a `ChatToolHandler` protocol. The router walks them in order; first non-nil `run` wins.

### 3. `ChatSession` — the SwiftUI binding

`@MainActor final class ChatSession: ObservableObject` owns the message log (`@Published var messages: [AnthropicClient.Message]`), the running flag, and the page context (`@Published var pageContext: String`). The system prompt is computed dynamically:

```
systemPrompt = WHERE THE USER IS RIGHT NOW (pageContext)
               + OVERVIEW + tool catalog descriptions
               + CRITICAL rules (no JSON-leak, no safety refusals, route
                 person queries via list_people first, etc.)
```

`pageContext` is set by the views — `MainWindow.onChange(of: section)` for the top-level tab, and `PersonDetailView.onAppear` / `onChange(of: current.id)` to override with the specific person's info (name + id + role + company + email + phone). When the user navigates away from a person, `onDisappear` restores the generic "People tab" context.

### Tolerant person lookup

A subtle but important detail in `PeopleChatTools.resolvePerson`: small models sometimes pass `"Horst"` or `"horst@example.com"` instead of the UUID the system prompt asks for. Rather than fail the tool call, `resolvePerson` tries: UUID → exact displayName → exact email/phone → single substring displayName match. The failure message includes the offending input ("no person matched `<input>`") so the model can course-correct.

---

## The people graph (second brain)

The People tab is its own substantial subsystem. The model:

```
Person
├── id, displayName, company, role
├── emails[], phones[], addresses[]
├── bio (markdown)
├── tagIDs (linked to PeopleTagStore — separate from MeetingTagStore)
├── memories: [Memory]            (id, text, occurredOn?, createdAt)
├── attachedNotes: [AttachedNote] (id, title, body, kind, createdAt) — saved analyses
├── relationships: [Relationship] (id, toPersonID, label, createdAt) — bidirectional
├── meetingMentions: Set<String>  (meeting IDs that mention this person)
├── photoRelativePaths[]
├── importSources                 ("manual", "contacts", "gmail", "calendar", "transcript", …)
├── contactIdentifier?            (CN identifier for de-duping on re-import)
├── birthday?, favorites[]
└── createdAt, updatedAt, lastInteractionAt
```

### Storage

Each person is a folder at `<storage>/people/<slug>/`:

```
person.json     — canonical SchemaEnvelope-wrapped record
person.md       — human-readable mirror, regenerated on every write
photos/*.*      — attached photos
```

`PeopleStore` (`@MainActor`) keeps the in-memory `[Person]` synced. Two writebacks per change:

- **person.json**: per-person, written synchronously on edit
- **`_people-cache.json`**: combined cache of every person + encounters + suggestions + dismissed signatures. Rewritten by a debounced background queue. Read on next launch instead of walking 1000s of person.json files (which was minutes on machines with scanners intercepting every open syscall).

### Search

There are TWO search paths for people. This is historically a sharp edge:

- **`PeopleStore.filteredPeople(query:tagID:includeGhosts:)`**: used by the People tab list. Backed by an FTS5 SQLite index (`SecondBrainDB.searchPersonIDs`). Falls back to in-memory `Person.matches(_:)` if the index returns empty.
- **`MeetingManager.search(_:)` in `WorkspaceIndex.swift`**: used by global ⌘K. Plain in-memory string contains across displayName / emails / phones / company / role / bio / memories / attached notes — with diacritic + width folding. The FTS5 path was tried here and reproducibly dropped specific contacts (the search_index table is sometimes stale / mis-tokenized); plain in-memory matching is unambiguous and fast enough for the 1000s of contacts a user typically has.

The Cmd+K search palette also has a People tab that bypasses `WorkspaceIndex.search` entirely and delegates to `PeopleStore.filteredPeople` directly — gives the user a guaranteed-working escape hatch when the unified search has an edge case.

### iMessage analysis (`MessagesAnalyzer`)

Opens `~/Library/Messages/chat.db` read-only via SQLite3. Requires Full Disk Access. Per-person analysis runs two scoped queries:

1. **Aggregate stats** — single SELECT with COUNT/SUM/MIN/MAX/CASE-WHEN for total, sent, received, first/last date, last-30/90-day counts. Comes back as one row — milliseconds even for 100k+ messages.
2. **Recent snippets** — `ORDER BY date DESC LIMIT N`. Only the last N messages get the attributedBody parse + placeholder fallback treatment.

This two-query split was a meaningful perf fix; the original implementation walked every row + parsed every attributedBody, which took multiple seconds per chat call for a heavy texter.

### attributedBody parser

Modern iMessage leaves `message.text` NULL when the message has rich formatting, mentions, link previews, reactions, or pure-attachment payloads. The actual text lives in `attributedBody` — an `NSArchiver` typedstream blob. A full typedstream decoder is overkill; `MessagesAnalyzer.extractText(fromAttributedBody:)` does the minimum:

1. Locate `"NSString"` in the bytes (the inline class introduction marker).
2. Find the LAST `0x2b` (ASCII `+`, the typedstream object-instance marker) in a 40-byte window after `NSString`.
3. Read the length-prefix byte right after the marker (0x01..0x7F direct, 0x81 + 2-byte LE, 0x82 + 4-byte LE).
4. Read length bytes as UTF-8.

Earlier versions scanned for ANY plausible length byte and picked up the `\x01` metadata byte first — which produced "+" for every recovered message. Looking for the LAST `\x2b` is what made it work.

When extraction fails, the analyzer falls back to placeholder strings based on `cache_has_attachments` (→ "[image/attachment]") and `associated_message_type` (→ "[reaction/tapback]") so attachments and reactions still show up on the timeline.

### Person extraction from transcripts

`PersonExtractor` is an opt-in (Settings → People → "Auto-extract people from meetings") background pass that runs after every meeting summary. It feeds the transcript to Ollama with a prompt asking for a structured list of people mentioned, then `PeopleStore.ingestExtraction(_:meeting:)` reconciles them:

- Exact name + email/phone match → link the existing person, add `meeting.id` to their `meetingMentions`
- Strong fuzzy match (similarity ≥ `autoMatchThreshold`) → same
- Moderate match (≥ `possibleMatchThreshold`) → publish as a `PersonSuggestion` for user confirmation on the Today tab
- No match → propose a new person, also as a suggestion

Suggestions the user dismisses are remembered (`dismissedSignatures`) so we don't re-suggest them next time.

---

## Storage layout (on disk)

Everything is plain files under `~/Documents/MeetingNotes/` (configurable in Settings). The format is intentionally human-readable and grep-friendly. Schema-versioned via `SchemaEnvelope<Payload>` — `{ "version": N, "data": {…} }` — so we can migrate without breaking older files.

```
~/Documents/MeetingNotes/
├── .meeting-index.json          MeetingStore's mtime + manifest cache (rebuilt on demand)
├── _people-cache.json           PeopleStore's combined snapshot
├── tags.json                    All meeting tags + (meetingID → [tagID]) assignments
├── action_items.json            All action items + projects + initiatives + labels
│
├── <tag>/<meeting-slug>/        Per-meeting directory (one tag = primary, others link via tags.json)
│   ├── meeting.json             SchemaEnvelope<MeetingDTO>
│   ├── audio/
│   │   ├── manifest.json        SchemaEnvelope<AudioManifestDTO>
│   │   ├── mic-001.m4a, mic-002.m4a, …
│   │   └── sys-001.m4a, sys-002.m4a, …
│   ├── transcript.md            Final merged transcript (speaker-labeled)
│   ├── notes.md                 User's own notes (typed in the app)
│   └── summary.md               Ollama-generated summary
│
├── QuickNotes/<note-slug>/      Voice notes (separate from meeting recordings)
│   ├── note.json
│   ├── audio.m4a
│   ├── transcript.md            Raw Whisper output
│   └── polished.md              Ollama-cleaned version
│
├── people/<person-slug>/
│   ├── person.json              SchemaEnvelope<Person>
│   ├── person.md                Markdown mirror (regenerated)
│   └── photos/<uuid>.<ext>
│
├── encounters/<encounter-id>.json   SchemaEnvelope<Encounter>
│
├── models/
│   └── ggml-base.en.bin          whisper.cpp model (auto-downloaded on first use)
│
└── logs/
    ├── app.log                   Errors / warnings, used by Settings → "Open app error log"
    ├── transcription.log         Every whisper-cli invocation with argv + exit code + stderr
    └── ollama.log                ollama serve output, when the app auto-launched it
```

### Schema versioning

`SchemaEnvelope<Payload: Codable>` (in `MeetingScribeShared`) wraps every persisted record. On decode it validates `currentVersion` matches; an optional `migrate:` closure can upgrade older payloads in-place. Today most types ship `currentVersion: 1` and rely on tolerant Codable decoding (every field added after the first release is optional with a default) for forward compat. The envelope is in place for the future where a field needs to be renamed or restructured.

### Index file

`MeetingStore.IndexFile` is `~/Documents/MeetingNotes/.meeting-index.json` — a digest of every meeting's metadata so the MeetingScribeMCP server can answer `list_meetings` in O(1) without walking 100s of meeting.json files. The app maintains it on every store mutation; the MCP server falls back to a one-time disk walk if the index is missing (e.g. first run after a manual file move).

### Keychain

API keys (Linear, Notion, Google Drive client ID/secret/refresh token) live in macOS Keychain via `KeychainStore`. Originally these were in UserDefaults; the migration runs on first launch in a background task (`KeychainStore.migrateAllFromUserDefaults`). Once in keychain they're accessible only after the user enters their password the first time.

---

## The MCP servers

`MeetingScribeMCP` is a standalone executable, no UI dependencies. It reads — and, as of the write-tools addition, also writes — the on-disk meeting / voice note / action item / person / tag files via the shared DTOs. Writes patch the raw JSON in place (existing records are never round-tripped through the lossy DTOs), are append-only for notes, and post a `vaultChanged` Darwin notification.

### Wire protocol

Stdin/stdout JSON-RPC 2.0, one message per line. Three method namespaces:

- `initialize` → returns server info + capabilities
- `tools/list` → returns the static tool catalog
- `tools/call` → dispatches to the right `tool_*` function and wraps the result in MCP's content-array shape

### Tools exposed

17 tools (12 read + 5 write) as of this writing:

Read:
- `list_meetings`, `get_meeting`, `get_transcript`, `get_notes`, `get_summary`
- `list_voice_notes`, `get_voice_note`
- `list_action_items`
- `list_people`, `get_person`, `get_person_messages`, `list_person_meetings`

Write:
- `create_action_item`, `update_action_item`, `add_person`, `add_memory`, `create_meeting_note`

The read People tools were mirrored from the in-app chat. `get_person_messages` does the same two-query split + attributedBody parse + placeholder fallback as the in-app analyzer; the two surfaces report identical numbers. The write tools patch the on-disk JSON directly (no PeopleStore/AppKit dependency), so the agent can mutate the vault — create tasks, add people, append memories, write meeting notes — not just read it.

### Installation flow

`MCPInstaller` (`Sources/MeetingScribe/MCP/MCPInstaller.swift`) handles registering with Claude Desktop:

1. Find Claude's config file (`~/Library/Application Support/Claude/claude_desktop_config.json`).
2. Merge in (or update) an entry under `mcpServers` pointing at the bundled `MeetingScribeMCP` binary path with `MEETINGSCRIBE_STORAGE` env var set to the app's storage directory.
3. Same flow for `NotionMCP` if the user installs that one.

Self-test action in the Integrations tab spawns the MCP binary and runs an `initialize` + `tools/list` round-trip to verify it works.

---

## Build, sign, ship

### `make app`

```
make app
   ├─→ swift build -c release          (SwiftPM, all three executables)
   ├─→ check-sparkle-key               (refuses to build if public key is placeholder)
   ├─→ bundle MeetingScribe.app        (build/MeetingScribe.app)
   │     ├─→ Copy MeetingScribe binary into Contents/MacOS/MeetingScribe
   │     ├─→ Copy MeetingScribeMCP into Contents/MacOS/MeetingScribeMCP
   │     ├─→ Copy NotionMCP into Contents/MacOS/NotionMCP
   │     ├─→ Embed Sparkle.framework
   │     └─→ Stamp Info.plist with the current short git SHA as CFBundleVersion
   └─→ codesign --identity "MeetingScribe Local Signer" with a stable
       designated requirement so TCC permissions survive rebuilds
```

### `make install`

```
make install
   ├─→ rsync to /Applications/MeetingScribe.app
   ├─→ lsregister --register so LaunchServices picks up the new bundle
   └─→ Verify CFBundleVersion matches `git rev-parse --short HEAD`
       (catches the "you forgot to rebuild" mistake)
```

### Code signing

The cert (`MeetingScribe Local Signer`) is self-signed and created by `scripts/create-signing-cert.sh` on first install. Critical detail: TCC (the system that grants Microphone / Screen Recording / Calendar / Full Disk Access permissions) identifies the app by `(bundle ID, designated requirement)`. The designated requirement is:

```
identifier "com.tyleryannes.MeetingScribe" and certificate leaf[subject.CN] = "MeetingScribe Local Signer"
```

Both pieces are stable across rebuilds, so permissions don't get re-prompted every time you build. If TCC fell back to the binary hash (the default without a designated requirement), every `make install` would invalidate every permission.

The `MeetingScribeMCP` and `NotionMCP` binaries inside the bundle are also signed with the same identity — they inherit the app's permissions when launched as children, which is what lets the MCP server read iMessage when Claude Desktop launches it.

### Notarization

For distributing to users outside your own machine, see `NOTARIZATION.md`. The release flow uses Apple notarization (via `notarytool`) so the app doesn't get Gatekeeper-quarantined on other Macs. Notarized releases are published to the GitHub releases page; Sparkle auto-update checks against the releases feed.

---

## Concurrency model

The app uses Swift's actor model heavily. Three rules:

- **`@MainActor`** everything that touches `@Published` or directly drives SwiftUI. `MeetingManager`, `PeopleStore`, `ChatSession`, `MeetingPipelineController`, all view models, all observable objects.
- **`Task.detached(priority:)`** for anything that does disk I/O, subprocess work, or Ollama calls. Result published back to main via `await MainActor.run`.
- **`OSAllocatedUnfairLock`** for the rare shared mutable state that needs cheap cross-thread access — currently used by `OllamaService` for its connection-state cache.

The codebase has accumulated Swift 6 strict-concurrency warnings (everything `OllamaService`, `AudioRecorder`, `UNUserNotificationCenter`, `AVAsset`-related, etc.) — they all stem from system frameworks and our own classes not being marked `Sendable`. These don't block the current build (Swift 5.10 mode) but would need a sweep before flipping to Swift 6 strict.

`Package.swift` enables `StrictConcurrency=targeted` so we get the warnings early and can fix incrementally.

---

## SwiftUI app shell

`MainWindow.swift` is the root scene. Top-level layout:

```
GeometryReader
└── HStack(spacing: 0)
    ├── navRail              (~200pt — the seven tabs)
    ├── tabContent           (the active tab's view)
    └── ChatSidebar          (280-380pt, conditional on chatVisible + window width >= 860)
```

The chat sidebar auto-collapses when the window is too narrow. The user's preference is preserved — it comes back when there's room.

Each tab is a separate top-level view. They're built on first selection (no eager pre-warming, after profiling showed the prewarm path was competing for the main thread with the first-paint render of the default tab). The chat session is shared across all tabs so messages persist as the user navigates.

### `MainWindow.routeEntity(kind:id:)`

Central navigation routine. Search palette and `meetingscribe://` link clicks both flow through here. Handles:

- `.meeting` → opens the meeting detail sheet (`UnifiedMeetingDetail`)
- `.voiceNote` → switches to Notes tab, posts `meetingScribeOpenVoiceNote`
- `.project` / `.actionItem` → switches to Tasks tab
- `.person` → switches to People tab, posts `meetingScribeOpenPerson`
- `.attachedNote` → opens the parent person (split on `::` in the rawID)
- `.chatQuery` → expands the chat sidebar and posts the query for ChatSession to send
- `.tag` → switches to People tab, posts `meetingScribeFilterByTag`

Each routed view listens for the relevant notification name in `WorkspaceLinks.swift`. This decouples search from view internals — the search palette doesn't need to know how each tab handles selection.

### Notifications used

- `.meetingScribeOpenSearch` — ⌘K opens the palette
- `.meetingScribeOpenEntity` — clicking a `meetingscribe://` link in any markdown view
- `.meetingScribeOpenVoiceNote`, `.meetingScribeOpenPerson`, `.meetingScribeRunChat`, `.meetingScribeFilterByTag` — search palette / cross-view routing
- `.meetingScribeAddPerson` — ⇧⌘P keyboard shortcut
- `.meetingScribeSettingsChanged` — settings dialog posts this, observers (hotkey, calendar refresh) re-read

---

## Background services running while the app is open

- **AppDetector** (`Detection/`): NSWorkspace observer that polls the frontmost app every few seconds. Detects Zoom, Google Meet (via browser tab title), Slack huddles. Used to:
  - Trigger `onImpromptuDetected` so the user gets a notification offering to record
  - Drive auto-record if Settings → Auto-record is on
  - Provide context to the floating overlay
- **Calendar timer**: fires every 60s, refreshes upcoming events, syncs notification triggers, checks for auto-record candidates
- **AmbientMeetingDetector** (`Detection/`): opt-in mic-RMS detector that pings when a meeting *seems* to be happening based on speech patterns (multi-speaker, sustained vs intermittent). Off by default
- **PersonExtractionController** (`People/`): queue of pending transcripts waiting for the second Ollama pass (auto-extract people). Off by default
- **TaskSyncService** (`ActionItems/`): periodic poll of Linear / Notion for changes (if either is configured). Bidirectional — also pushes local changes back
- **OllamaService connection-state cache**: passive, updates on every call

---

## Adding a new feature: the typical path

Most additions follow a clear pattern. Example: "I want a chat tool that lists my recent Google Drive files."

1. **Define the tool** in `IntegrationChatTools.swift`: add an entry to the `tools` catalog with name + description + JSON schema, add the case to the `run(name:input:)` dispatcher.
2. **Implement the function**: read from `GoogleDriveService`, return a JSON string via `ChatToolHelpers.jsonString(_:)`.
3. **Update the system prompt** in `ChatSession.swift` if the tool needs special instructions.
4. **(Optional)** Mirror into `Sources/MeetingScribeMCP/main.swift` if Claude Desktop should also see it.

For a new on-disk type:

1. Add the in-app model (e.g. `Sources/MeetingScribe/People/Whatever.swift`) with `Codable` conformance + tolerant decode.
2. Add a DTO mirror in `Sources/MeetingScribeShared/SharedModels.swift` if the MCP server needs to read it.
3. Add store methods in the relevant `*Store` (`MeetingStore`, `PeopleStore`, etc.) with `writePerson` / `writeMeeting` / etc.
4. Add UI in the relevant SwiftUI view.

---

## What's intentionally NOT there

A few things the codebase doesn't have, by design:

- **No analytics / telemetry / crash reporting service**. Errors go to `~/Documents/MeetingNotes/logs/app.log` (the user can export via Settings → Diagnostics → Export). Nothing leaves the machine.
- **No background sync service**. Cross-device sync is opt-in (`Sources/MeetingScribe/Sync/`) and supports a small set of S3-compatible / Box backends. By default the app is single-machine.
- **No SwiftData / Core Data**. Plain Codable JSON on disk. The reason: storage portability + grepability. Users can `cd ~/Documents/MeetingNotes && grep -r "thing"` and it works.
- **No GraphQL / network DB layer**. All reads/writes go through small per-domain stores (`MeetingStore`, `PeopleStore`, etc.) that own their own caching + file I/O.

---

## Known sharp edges

If you're touching the code, these are the things that bit prior contributors:

- **TCC permissions vs binary hash**: any change to the signing identity or designated requirement invalidates every permission the user has granted. Don't change `SIGN_IDENTITY` in the Makefile without a migration plan.
- **macOS Tahoe toolbar overlay**: the translucent toolbar overlays the top of every scroll view by default. Detail views need explicit top padding (≥ 60pt) or the title row gets clipped.
- **`NSUnarchiver` is gone**: macOS 12+ removed the typedstream decoder, which is why `MessagesAnalyzer` has a hand-rolled byte parser instead of just deserializing the attributedBody blob.
- **Ollama doesn't issue tool_use IDs**: we synthesize them as `ollama_<iteration>_<index>` so the AnthropicClient.Message shape stays consistent.
- **`whisper-cli --no-context` is a footgun**: produces garbled output in some configurations. `WhisperRunner.argv` has a guard comment.
- **`whisper-cli --flash-attn` produces empty output** on M2/M3 with the current homebrew ggml/whisper.cpp build. Disabled by default in Settings.
- **Swift 6 strict concurrency** isn't on. Flipping it would surface ~80 warnings in our code (mostly `Sendable` violations around `OllamaService`, `AudioRecorder`, `UNUserNotificationCenter`). Worth doing as its own dedicated PR.
- **PeopleStore FTS5 index** (`SecondBrainDB.search_index`) is sometimes stale or mis-tokenized. The People tab masks this with an in-memory fallback when FTS returns empty; the global ⌘K palette bypasses FTS entirely and uses plain in-memory contains.

---

## Test coverage

There's a `MeetingScribeTests` target (Tests/MeetingScribeTests). Coverage is uneven — concentrated around the trickiest parts (schema envelope decoding, audio segment merging, the attributedBody parser, the chat tool dispatcher). UI is not covered (would need XCUITest, hasn't been a priority).

`swift test` runs the suite. Most tests are pure model tests; a few use temporary directories for the storage layer.

---

## Where to start reading the code

For someone new to the codebase, here's a reading order that gives you the most context fastest:

1. **`Sources/MeetingScribe/MeetingScribeApp.swift`** — the SwiftUI scene, what gets owned at top level, the boot sequence
2. **`Sources/MeetingScribe/MeetingManager.swift`** — the central controller; trace recording lifecycle from `startRecording` to `stopRecording`
3. **`Sources/MeetingScribe/MeetingPipelineController.swift`** — what happens after stop
4. **`Sources/MeetingScribe/Storage/MeetingStore.swift`** — on-disk model
5. **`Sources/MeetingScribe/Models/Meeting.swift`** — the canonical meeting model
6. **`Sources/MeetingScribe/Chat/ChatSession.swift`** + **`OllamaChatClient.swift`** — the chat runtime
7. **`Sources/MeetingScribe/Chat/ChatTools.swift`** + the five domain handlers — the tool surface
8. **`Sources/MeetingScribe/People/PeopleStore.swift`** + **`Person.swift`** — second-brain model
9. **`Sources/MeetingScribe/People/MessagesAnalyzer.swift`** — iMessage integration
10. **`Sources/MeetingScribeMCP/main.swift`** — what data we expose to external clients
11. **`Sources/MeetingScribeShared/SharedModels.swift`** + **`SchemaEnvelope.swift`** — the cross-target DTOs and persistence envelope

Everything else (UI, integrations, diagnostics, audio details) hangs off this skeleton.
