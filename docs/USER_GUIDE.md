# MeetingScribe — User Guide

A friendly walkthrough of what MeetingScribe does, how to use it day-to-day, and how to get the most out of it. Everything in MeetingScribe runs on your Mac — no cloud, no logins, no data leaving your machine.

---

## What is MeetingScribe?

MeetingScribe is a local-first macOS app that quietly captures your meetings and notes, then turns them into searchable, queryable knowledge. Think of it as a personal recording studio, transcription service, AI summarizer, contact CRM, and chat assistant — all bundled into one app that lives on your Mac.

Things you can do with it:

- **Record a meeting** (Zoom, Google Meet, in-person, anything that makes sound on your computer) and get a transcript + AI summary + action items when it ends.
- **Dictate a voice note** with a global hotkey from anywhere on your Mac — no need to open the app.
- **Talk to a chat assistant** that knows about all your past meetings, voice notes, tasks, contacts, and iMessages.
- **Track people** the same way a CRM does — emails, phones, notes, the texts you've exchanged, the meetings you've had together.
- **Run AI analyses** on any contact's iMessage history — sentiment, topics, conversation summaries — and save those analyses to that person's record.

Everything is yours, stored as plain files in `~/Documents/MeetingNotes/`. You can poke at it with the Finder. You can back it up. If you ever stop using the app, the data is still readable.

---

## Setup (one time)

The README has the full install command. Here's what you actually need to know after it finishes:

### Permissions to grant

The first time you launch the app, macOS will prompt you for a handful of permissions. Click through them — without these, the relevant features don't work:

| Permission | Why MeetingScribe needs it |
|---|---|
| **Microphone** | To record your voice during a meeting |
| **Screen Recording** | To capture the other side of the call (Zoom, browser audio). After granting this one, quit and relaunch the app. |
| **Calendar (Full Access)** | So your scheduled meetings show up automatically |
| **Notifications** | To remind you when a meeting is about to start |
| **Accessibility** (optional) | Lets the global dictation hotkey paste text into other apps automatically |
| **Full Disk Access** (optional) | Lets the People tab read your iMessage history. Enable in System Settings → Privacy & Security → Full Disk Access |

If you missed any of these, you can grant them later — the app will surface clear errors that tell you exactly which permission is missing.

### What ships ready vs. what you set up

The installer puts these in place automatically:

- **Whisper** (transcription engine) and its default model (`ggml-base.en.bin`, ~148 MB)
- **Ollama** (local LLM runtime) and the default model (`qwen2.5:7b`, ~5 GB — the chat works much better than the older `llama3.1:8b`)

If a model ever goes missing — say you reinstall Ollama — the app will auto-download what it needs the first time you ask.

You opt in separately to:

- **Linear / Notion** (for syncing tasks and pushing action items) — see Integrations tab
- **Google Drive** (for exporting meeting summaries) — see Integrations tab
- **Claude Desktop** as an external client of your MeetingScribe data via MCP — also Integrations tab

---

## The main tabs

Down the left side of the window are seven tabs. Here's what each one does.

### Today

The home view. Shows you:

- Today's date and a one-line calendar summary ("3 meetings today" / "Nothing on the calendar")
- Quick actions: Record meeting, Join & record, Voice note, New task, New page
- Action items widget (today + yesterday's tasks, open by default)
- The currently recording meeting, if any
- Today's calls (past + upcoming)
- A link to the Calendar tab for full history

If you join a Zoom or Google Meet call, the app auto-detects it and offers to start recording — you don't have to remember to hit a button.

### Meetings

Every past meeting, sortable and tagged. Click into any meeting to see:

- **Transcript** — every word said, with speaker labels ("Me" vs. "Them") where they could be inferred
- **Notes** — your own freeform notes you typed during or after the meeting
- **Summary** — AI-generated overview with TL;DR, key decisions, action items, open questions, notable quotes

You can re-run transcription (e.g. after the app updated to a better Whisper model) or re-run the summary if the first one missed something.

### People

A lightweight CRM. Every contact you've imported (from Apple Contacts, Gmail, calendar attendees, vCard/CSV files, or by hand) lives here. The detail view shows:

- Name, role, company, emails, phones, address, birthday
- **Photos** you've attached
- **Memories** — short freeform facts you want to remember ("loves single-origin coffee")
- **Notes** — long-form analyses saved from the chat assistant (sentiment trends, relationship summaries, etc. — see *Analyze conversation* below)
- **Relationships** — links to other people ("spouse", "manager", "kid")
- **Encounters** — where/when you last met
- **Messages** — your iMessage history with this person, with stats (total, sent/received, 30-day & 90-day activity)
- **Mentioned in** — meetings whose transcript mentions this person

#### Analyze conversation

If you've granted Full Disk Access, click "Analyze" on the Messages section to load your iMessage stats, then "Analyze conversation" to run an AI analysis. Pick a preset:

- **Summarize relationship** — 3–5 sentences on overall tone and topics
- **Sentiment & trends** — mood shifts, recurring themes
- **Topics & themes** — bulleted list of what you talk about
- **Communication style** — how the other person typically writes
- **Pending action items** — open follow-ups from your recent thread
- **Custom prompt** — write your own question

Each preset has two modes:

- **Recent 1000 messages** (default) — fast, ephemeral. Good for "how have things been lately?"
- **All time (cache + save)** — runs over the FULL conversation, persists the result as a Note on that person. Re-opening the menu later shows "Refresh all-time analysis" so you know it's cached.

After any analysis runs, hit **"Save to notes"** to keep it on the person's record forever. Saved notes are searchable and survive app restarts.

### Tasks

Project-management workspace for action items.

- **Initiatives** — top-level goals (e.g. "Q1 hiring", "ship v2")
- **Projects** — markdown pages with embedded checklists
- **Action items** — individual tasks with owner, priority, due date, status (open/in-progress/completed)

Tasks get auto-extracted from every meeting summary, so if a teammate says "I'll send the contract by Friday", that becomes an action item assigned to them with a Friday due date. You can also push tasks out to **Linear** or **Notion** if you've connected those.

### Calendar

Month / week / day views of your real macOS calendars. Shows past meetings (anything you recorded shows as recorded) and upcoming events (live-status badge appears when a meeting is starting now).

### Media

Local AI-generated images and videos. Has its own image generator backed by Core ML Stable Diffusion (Apple Silicon) — useful for creating placeholder graphics or visual aids.

### Notes

Freestanding voice notes — anything you dictated outside of a meeting. Includes the raw Whisper transcript, a "polished" version where Ollama cleans up punctuation and capitalization, and an optional "AI Prompt" version that rewrites your recording into a structured prompt using the TCREI framework (Task, Context, References, Evaluate, Iterate). Use the swap hotkey to flip between raw and polished when pasting; use the AI-prompt hotkey to rewrite a dictation into a prompt in place. Each version is also shown side-by-side in the note detail, with a Generate button for the AI Prompt.

### Integrations

One place to configure every external service:

- **Linear** (API key) — sync tasks bidirectionally
- **Notion** (API key + database ID) — push action items, create pages
- **Google Drive** (OAuth) — export meeting summaries
- **Calendar** — already wired up via EventKit
- **Ollama** — local AI; this is where the "Pull qwen2.5:7b" button lives if the chat ever complains the model is missing
- **Claude Desktop (MCP)** — install the bundled MeetingScribeMCP server so Claude can query your data

---

## The Chat sidebar

The right-hand sidebar (toggle with the rightmost toolbar icon) is a chat assistant that knows everything in your workspace. It runs entirely on your Mac via Ollama — same engine that does the meeting summaries.

### What it can do

The chat has tools for every kind of data in the app:

- **Meetings**: get_overview, list_meetings, get_meeting, get_transcript, get_notes, get_summary
- **Voice notes**: list_voice_notes, get_voice_note
- **Tasks**: list_action_items, create_task, set_action_status, set_action_priority, set_action_due_date, list_projects
- **People**: list_people, get_person, get_person_messages, list_person_meetings
- **Save analyses**: attach_note_to_person — lets the chat save its own output to a person's record
- **Integrations**: push_action_item_to_notion, sync_external_tasks (Linear/Notion → Tasks), linear_list_projects, linear_list_teams, linear_create_issue, export_meeting_to_drive
- **Chat folders**: list_chat_folders, list_files, read_file, write_file, edit_file, search_files (sandboxed file access in folders you've approved)

### Tips for fast, useful chats

- The chat **knows what page you're on**. Open Horst's contact, then ask "what about next week's trip?" — the model assumes you mean Horst. No need to re-type the name.
- **Be specific about scope**. "What did we decide last week?" runs faster than "summarize everything" because the chat can scope the tool calls.
- The chat **won't loop on the same tool**. If you ask something and it keeps spinning, it'll short-circuit duplicate tool calls with an error rather than waste your time.
- For analyses you want to keep: tell the chat **"save it to [person]'s notes"** and it'll persist the result as an AttachedNote you can find later.
- For natural-language requests across the whole workspace: open ⌘K, type the question — anything 3+ words gets an "Ask Chat: …" option at the bottom that sends it to the sidebar.

### Connected chat folders

The sidebar header has a folder icon. Click it to grant the chat access to specific folders on your Mac (e.g. `~/Documents/Projects/MyClient`). Once granted, the chat can list, read, write, and search files in those folders only — sandboxed, so it can't roam outside what you've approved.

---

## Global search (⌘K)

Press ⌘K from anywhere in the app. The search palette opens with a tab row at the top:

- **All** — everything (meetings, voice notes, projects, action items, people, notes)
- **People** — contacts only (uses the same proven search as the People tab)
- **Meetings** — past calls only
- **Tasks** — projects + action items
- **Notes** — saved AttachedNotes (relationship summaries, etc.) and meeting notes
- **Voice** — voice note transcripts

Two special syntaxes:

- **`#tag-name`** — filters to entities carrying that tag (works for both meeting tags and people tags)
- **3+ word natural-language query** — appends an "Ask Chat: …" option at the bottom of results so you can route the question to the assistant

Arrow keys move selection; Enter opens the highlighted result; Esc closes.

---

## Workflows: how people actually use this

### "What came out of yesterday's meetings?"

Open the chat sidebar → type that question. The chat calls `get_overview` once, sees yesterday's meetings + open action items + recent voice notes in one shot, and answers in 2–3 sentences. Fast (one tool call).

### "What did I discuss with Sarah last week?"

Open Sarah's contact in the People tab (⌘K → "Sarah" → People tab → click her). Her contact info now becomes the chat's context. In the chat sidebar, just type "what did we talk about last week?" — the model uses Sarah's id and calls `get_person_messages` directly.

### "Summarize my relationship with my brother"

People tab → click on him → Messages section → "Analyze" (if not already loaded) → "Analyze conversation" menu → "Summarize relationship" → "All time (cache + save)". Wait a few minutes for it to read every message you've ever exchanged. Result gets saved to his notes automatically. Re-opening the menu later shows "Refresh all-time analysis" so you can rerun deliberately when the analysis feels stale.

### "Capture an ad-hoc thought while I'm coding"

Press your dictation hotkey (default: configurable in Settings → Dictation). Talk for as long as you want. Press the hotkey again to stop. The raw Whisper transcript appears in your clipboard immediately — paste it wherever you want. Ollama also runs a "polish" pass in the background to clean up punctuation; press the swap hotkey to flip to the polished version when you paste.

### "Dictate a request to paste into an AI"

Dictate your request, then press the **AI-prompt hotkey** (default F7). The just-inserted text is replaced in place with a structured prompt built using the TCREI framework — Task, Context, References, Evaluate, Iterate — so it reads like a proper engineering blueprint instead of a vague ask. Press the swap hotkey to flip back to the raw/polished version. This rewrite is optional and runs on demand, so it only touches Ollama when you ask for it.

### "Record a Zoom call I'm about to join"

Two options:
1. Just join the call. The app auto-detects you're in a Zoom meeting and offers to record.
2. Open the Today tab and click **Record meeting**. The recording starts immediately and continues until you click Stop. When you stop, the pipeline kicks off: merge audio segments → final Whisper pass → Ollama summary → extract action items. Done in 30–60 seconds for a typical 30-minute call.

### "Push a meeting summary to my team's Notion"

Integrations tab → Notion → paste your API key and the action-items database ID. Then in any meeting summary, click the Notion icon next to an action item. It creates a Notion page in the database with the item details and links back to the source meeting.

### "Make Claude Desktop able to query my meetings"

Integrations tab → Claude Desktop (MCP) → "Install in Claude Desktop". This registers the bundled MeetingScribeMCP server in Claude's config. Restart Claude Desktop. Now Claude has 17 tools over local JSON-RPC (no network calls): it can list your meetings, read summaries, look up people, and query iMessage stats — and it can also write back, creating tasks, adding people, appending memories, and writing meeting notes ("add a task to follow up with Alice by Friday"). Writes are surgical: they patch the underlying files without rewriting your existing data, and notes are only ever appended.

---

## Settings worth knowing

A few non-obvious settings you can change in Settings → :

| Setting | What it does |
|---|---|
| **Storage location** | Where your meeting library lives. Default `~/Documents/MeetingNotes`. Change this to point to a cloud-synced folder if you want library sync. |
| **Whisper model** | Default `ggml-base.en.bin` (English-only, fastest). Swap to `ggml-large-v3.bin` if you have a beefy Mac and want noticeably better accuracy. |
| **Whisper GPU** | On by default. Disable if you see empty transcripts (rare, only happens on older Apple Silicon + certain whisper.cpp versions). |
| **Whisper diarization** | Off by default. When on, attempts to label segments with speaker IDs. Adds processing time. |
| **Ollama model** | Default `qwen2.5:7b`. The chat doesn't work well with smaller models that lack native tool-calling. |
| **Auto-extract people** | Off by default. When on, every meeting's summary runs a second Ollama pass to identify people mentioned, then offers them as suggestions on the Today tab. |
| **Auto-record** | Off by default. When on, any calendar meeting you join gets recorded automatically. |
| **Notify at meeting start** | Sends a banner notification when a calendar meeting is starting. |
| **Dictation hotkey** | Pick the key combo you want for global dictation. F5 by default. |
| **Dictation swap hotkey** | Flips the clipboard between raw and polished transcript versions. |
| **AI-prompt hotkey** | Optional. Rewrites the last dictation into a TCREI-structured AI prompt in place. F7 by default. |

---

## Troubleshooting

### "Whisper model not found"

The app auto-downloads `ggml-base.en.bin` from the canonical whisper.cpp host on first use. If the auto-download failed (no network, etc.), it'll surface a clear error. Manually: `brew install whisper-cpp` and the default model gets dropped in `~/Documents/MeetingNotes/models/ggml-base.en.bin`.

### "Ollama HTTP 404: model not found"

Same auto-pull pattern: the first chat that hits a missing model triggers an inline `ollama pull <model>` and surfaces a "Pulling local model" notice in the chat bubble. ~5 GB download for qwen2.5:7b. Or: open Integrations → click "Pull qwen2.5:7b".

### Chat is slow

Several things to check:
- Make sure you're on `qwen2.5:7b` (Settings → Ollama → Model). Older `llama3.1:8b` is much weaker and slower.
- Big iMessage threads make `get_person_messages` slow. Lower the snippet limit in the prompt ("show me only 10 recent messages").
- First chat after launch always pays Ollama cold-start cost. Subsequent ones are faster.

### Chat doesn't find a contact

Use ⌘K → People tab to search. The People tab uses a different (more reliable) search path than the global search did historically.

### iMessage section says "No phone number or email on this person matches a Messages conversation"

The contact in MeetingScribe doesn't have any email or phone that matches an existing iMessage thread. Edit the contact and add the email/phone the person texts you from.

### "Permission denied" reading iMessage

Grant Full Disk Access: System Settings → Privacy & Security → Full Disk Access → toggle MeetingScribe on. Then relaunch the app.

---

## Where your data lives

Everything is plain files in your Documents folder:

```
~/Documents/MeetingNotes/
├── <tag>/<meeting-id>/
│   ├── meeting.json       (metadata: title, time, attendees, tags)
│   ├── audio/             (per-segment .m4a files)
│   ├── transcript.md      (Whisper output)
│   ├── notes.md           (your typed notes)
│   └── summary.md         (Ollama summary)
├── QuickNotes/<note-id>/
│   ├── note.json
│   ├── audio.m4a
│   ├── transcript.md
│   ├── polished.md
│   └── prompt.md          (optional TCREI AI-prompt rewrite)
├── people/<slug>/
│   ├── person.json        (contact + memories + attached notes + relationships)
│   ├── person.md          (human-readable mirror, regenerated on every write)
│   └── photos/            (attached photos)
├── encounters/<id>.json
├── tags.json              (meeting tag definitions + assignments)
├── action_items.json      (extracted action items + projects)
├── models/                (whisper.cpp model files)
└── logs/
    ├── app.log            (errors, warnings — used by Settings → "Open app error log")
    ├── transcription.log  (every whisper-cli invocation)
    └── ollama.log         (the Ollama server, if auto-started)
```

You can grep, back up, sync, version-control, or migrate any of this with normal tools.

---

## What's NOT on disk

Two things live elsewhere:

- **API keys** (Linear, Notion, Google) — macOS Keychain, accessible only with your password
- **iMessages** — Apple's own `~/Library/Messages/chat.db`. MeetingScribe opens this read-only when you click "Analyze" on a contact's Messages section. We never copy iMessage contents out unless YOU explicitly save an analysis as a Note.

---

## Privacy posture

A few facts worth knowing if you care about where data goes:

- **No telemetry**. The app makes zero network calls for analytics, crash reports, feature flags, or any other "phone home" pattern.
- **All AI runs locally**. Whisper and Ollama are both local. The chat, transcription, summarization, person extraction, and analysis features never call out to OpenAI / Anthropic / anyone.
- **The only outbound traffic** comes from integrations YOU configured: Linear / Notion / Google Drive API calls when you sync. And only against their APIs — your data isn't relayed through a third-party MeetingScribe server.
- **Apple notarization / updates**: Sparkle checks for app updates against the GitHub releases page. That's the only background network call. You can disable it in Settings.

---

## Help, feedback, bugs

This is an open-source personal project: https://github.com/tyleryannes94/meetingscribe

Issues, PRs, and feature requests welcome. For a developer-oriented breakdown of the architecture and code, see [ARCHITECTURE.md](ARCHITECTURE.md).
