# FILE_MAP — screen → real Swift file (quick lookup)

> Verified against `tyleryannes94/meetingscribe-refactor@main`. Paths are under
> `Sources/MeetingScribe/`. Use this to jump straight to the right file; full context per
> screen is in `HANDOFF.md`.

## Shell / global chrome
| Thing | File |
|---|---|
| Nav rail, keep-alive tabs, title bar, sheets wiring | `UI/MainWindow.swift` |
| Per-page toolbar button sets + actions | `ToolbarModel` (referenced from `MainWindow.swift`) |
| Title-bar "Stop · MM:SS" pill | `RecordingStopPill` (mounted in `MainWindow.swift`) |
| In-app meeting recording dock | `MeetingRecordDock` (mounted in `MainWindow.swift`) |
| Voice-note floating hover pill | `UI/FloatingOverlay.swift` || Assistant rail | `UI/ChatSidebar.swift` |
| ⌘K command palette | `UI/GlobalSearchView.swift` |
| Design tokens (Bloom) | `UI/NotionDesign.swift` (`NDS`) |
| Reusable components / button styles | `UI/MSComponents.swift`, `UI/MSAvatar.swift` |

## Pages
| Screen | File(s) |
|---|---|
| Today | `UI/TodayView.swift` |
| Meetings list | `UI/MeetingsView.swift` |
| **Meeting detail + tabs + Edit mode** | **`UI/UnifiedMeetingDetail.swift`** (`MeetingTab`; modes `.live/.upcoming/.past`) |
| Meeting notes editor (editable) | `RichMarkdownEditor` |
| Meeting summary render (read-only) | `MarkdownEditor` |
| Attendee → person inline | `MeetingPeopleRail`, `MeetingPersonConnectPanel` |
| Meeting action-item rows | `MeetingActionRow` |
| People roster | `People/PeopleListView.swift` |
| Person profile + tabs + Edit | `People/PersonDetailView.swift` |
| Person create/edit modal | `People/AddPersonSheet.swift` |
| Message analysis | `People/MessagesAnalyzer.swift` |
| Encounter heatmap / AI suggestions | `People/EncounterHeatMap.swift`, `People/PersonAISuggestions.swift` |
| Tasks workspace | `UI/ActionItemsView.swift` |
| Tasks sub-nav | `UI/ActionItemsSidebar.swift` |
| Tasks top bar / view switcher | `UI/ActionItemsChrome.swift` |
| Tasks list / board | `UI/ActionItemsListView.swift`, `UI/ActionItemsBoardView.swift` |
| **Task property popover editors** | **`UI/ActionItemsPropertyDrawer.swift`** + board inspector |
| Tasks filters / triage / smart views | `UI/ActionItemsViewModel.swift` |
| Voice Notes | `UI/QuickNotesView.swift` |
| Settings | `UI/SettingsView.swift` |
| New meeting modal | `NewMeetingSheet` (from `MainWindow.swift`) |
| New person modal | `People/AddPersonSheet.swift` |
| New task | inline `actionItems.createTask(...)` (from `MainWindow.swift` / Tasks) |

## Data / stores (no schema changes needed)
| Model | File |
|---|---|
| Person | `People/Person.swift`, `People/PeopleStore.swift` |
| Meeting | `Models/Meeting.swift`, `Storage/MeetingStore.swift`, `MeetingManager.swift` |
| Task / ActionItem | `ActionItems/ActionItem.swift`, `ActionItems/ActionItemStore.swift` |
| Project / Initiative | `ActionItems/Project.swift`, `ActionItems/Initiative.swift` |
| Voice note | `QuickNotes/QuickNote.swift`, `QuickNotes/QuickNoteStore.swift` |
| Tags | `Storage/TagStore.swift`, `People/PeopleTagStore.swift` |

## ⚠️ Files referenced by OLD handoffs that DO NOT EXIST — do not create or look for these
- `MeetingDetailHeader.swift` → it's part of **`UnifiedMeetingDetail.swift`**
- `MeetingNotesTab.swift` / `MeetingActionsTab.swift` → tabs inside **`UnifiedMeetingDetail.swift`**
- editable `MarkdownEditor.swift` → the editable editor is **`RichMarkdownEditor`**; `MarkdownEditor` is read-only
- `FloatingOverlay.swift` for the meeting dock → the meeting dock (`MeetingRecordDock`) is mounted in **`MainWindow.swift`**; `FloatingOverlay.swift` is for the **voice-note** hover pill only
