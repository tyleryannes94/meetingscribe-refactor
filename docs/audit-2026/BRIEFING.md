# Shared Briefing — MeetingScribeRefactor 25-Agent Audit

You are one of 25 expert agents auditing MeetingScribe (the refactored version). Read this whole file first.

## The target
MeetingScribe is a 229-file, 50,554-line native macOS SwiftUI app. Local-first meeting transcription (whisper.cpp + Ollama), with a rich People/Second Brain CRM module, 17-tool MCP server for Claude integration, action item tracker, and node/edge mindmap relationship visualization. Tech: Swift 5.9+, SwiftUI, SPM, SQLite/FTS5, NSFileCoordinator. Targets macOS 14+, Apple Silicon primary.

## Repo path
`/Users/tyleryannes/MeetingScribeRefactor/` — key areas:
- `Sources/MeetingScribe/People/` — the relationship/Second Brain module (PRIMARY FOCUS)
- `Sources/MeetingScribe/Chat/` — MCP + AI chat integration
- `Sources/MeetingScribe/UI/` — all main views (TodayView, MeetingsView, UnifiedMeetingDetail, etc.)
- `Sources/MeetingScribeMCP/main.swift` — 17-tool MCP server (1526 lines)
- `Sources/VaultKit/` — shared models (Person, Encounter, SharedModels)
- `Sources/MeetingScribe/Models/` — Meeting.swift, Settings.swift, Tag.swift
- `Sources/MeetingScribe/ActionItems/` — ActionItem.swift, ActionItemStore.swift
- `Sources/MeetingScribe/Audio/` — recording pipeline
- `Sources/MeetingScribe/Transcription/` (if present) or ScribeCore equivalents

## REQUIRED: read existing plans before auditing
Skim these before proposing anything — do NOT re-list what's already here:
- `/Users/tyleryannes/MeetingScribeRefactor/MASTER_PLAN_V3.md`
- `/Users/tyleryannes/MeetingScribeRefactor/AUDIT_REPORT_2026-05-30.md`
- `/Users/tyleryannes/MeetingScribeRefactor/HANDOFF.md`

## What is ALREADY PLANNED (go BEYOND this)
The existing plans already cover: (1) ENG-A transcript tail truncation P0 fix (flush() before renderMarkdown); (2) VaultKit consolidation replacing SecondBrainCore + MeetingScribeShared dead targets; (3) NavSplitView for Meetings (done), Today expand/collapse fix (NAV-1/2); (4) inline Person field editing (PPL-1, modal → click-to-edit); (5) multi-value contact fields PPL-2; (6) full-window-width LAY-1/2 (remove 720/920 caps, chat rail default-closed); (7) default MeetingsView scope to .upcoming DEF-1; (8) "up next" hero strip TDY-1; (9) "stay in touch" nudges; (10) speaker-labeled transcript (SpeakerDiarization.swift exists, unwired); (11) global ⌘N quick-add task; (12) write-capable MCP (already done in current build — 5 write tools); (13) per-tag summary templates; (14) god-file decomposition (PersonDetailView 1986 lines, PeopleStore 1359 lines, MCP main.swift 1526 lines); (15) ARCH-1 CaptureKit de-dup (app ↔ daemon audio/transcription file duplication); (16) ScribeCore XPC transport (scaffolded, not live); (17) date-partitioned vault layout + VaultMigrationSheet; (18) iCloud inbox watcher; (19) FTS5 v2 unified search; (20) Sparkle SUFeedURL fix.

**Your job: endorse the few existing items that matter most through your lens, then propose NET-NEW improvements and features the existing plans miss entirely.**

## This audit's focus — bias ALL proposals toward these
1. **Relationship TYPE PATHS** — partner / family member / close friend paths with distinct content, check-in cadences, UI flows, and psychological frameworks per type
2. **Check-in features** — recurring prompts per person, habit loops, encounter reminders, "haven't logged X in N days" nudges, structured check-in templates
3. **Relationship content depth** — attachment theory, love languages, Gottman, NVC, DBT interpersonal skills, communication styles embedded as exercises and reflection prompts
4. **MCP expansion** — what People/relationship data Claude should be able to read AND write; new tools beyond the current 17
5. **Multi-path UX** — a user managing a romantic partner, a parent, and 3 close friends should have distinct flows for each type without confusion
6. **Small-lift wins** — quick improvements anywhere in the app (hours of work, immediate user value)

## Guiding principles
- **Evidence over opinion** — cite file:line for every structural observation
- **Distinguish clearly**: "endorsing existing plan item X" vs "NET-NEW: my idea"
- **Effort discipline**: S = hours, M = days, L = weeks
- **Be opinionated**: say what to build, not "consider building"
- **Relationship app lens**: the People module is being evolved into a relationship coach, not just a CRM — think emotional depth, safety, habit formation, not just data fields

## Output — write your markdown file, then return a short summary
1. Write your full analysis to the file path given in your task description
2. Structure: heading + lens statement; full-app audit through your lens with file:line; existing-plan items you rank highest (3-6); NET-NEW recommendations (6-12 items with PREFIX-n IDs); top 3 picks
3. Return a ~120–150 word summary: your role, top 3 net-new picks, single highest-priority recommendation

Be concrete, opinionated, cite code. Avoid generic advice. Use the ID prefix assigned in your task.
