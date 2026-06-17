# Non-Technical User / New Adopter (U5) Findings — MeetingScribe v2 Audit

**Agent ID:** U5  
**Sub-lens:** End-user persona — smart but non-technical, installed yesterday, needs things to just work, abandons anything that requires configuration in the first 30 seconds

---

## Top friction points / gaps (file:line citations)

### 1. Onboarding ends at permissions — the user has no idea what to do next
`OnboardingSheet.swift:242` flips `hasCompletedOnboarding = true` and dismisses. The user lands on Today, which on day 0 shows `emptyState` (`TodayView.swift:810`): "Nothing on today's calendar — use a quick action above, or import an existing recording." That message assumes the user already knows about quick actions and import flows. There is no "here's what to do first" card, no sample data, no guided next step. For a non-technical user, this blank Today view is a dead end that reads as "the app is broken."

### 2. Onboarding covers permissions but never shows what the app *does*
`OnboardingSheet.swift:8–51` walks through vault location + 5 macOS permissions. This is technically correct but describes the plumbing, not the product. A new user who just granted microphone and screen recording access has no mental model of: what a "second brain" is, what a transcript looks like, what happens after a meeting ends, or why they should care about the People tab. There is no value-demo screen — no screenshot, no GIF, no sample output — anywhere in the onboarding flow.

### 3. Screen Recording permission is confusing for non-technical users
`OnboardingSheet.swift:388–392` subtitles the Screen Recording step: "Captures the OTHER side of the call using macOS screen-audio access. Grant it in System Settings — this screen detects it and offers a one-tap Reopen." The term "screen-audio access" is not a concept any non-technical user has. The user almost certainly thinks screen recording = video, and "screen-audio" sounds like a hack or a typo. The bullets (`OnboardingSheet.swift:399`) say "Used only for audio — no video, no screenshots" but the reassurance comes after the confusing label. Most non-technical users will skip this permission and then wonder why only their own voice shows up.

### 4. Chat tab has no affordance for a first-time user
`ChatSession.swift:52–79` shows that the system prompt is rich and context-aware, but the chat panel itself (wherever it appears in the UI) opens with a blank message field. There are no suggested prompts, no "try asking…" hints, no examples. A non-technical user does not know that an AI assistant is available at all, let alone what it can do with their meetings and contacts. The power of the tool-use system — over meetings, people, tasks — is completely invisible.

### 5. "Meetings" tab empty state is actionable but cold
`MeetingsView.swift:337–349` shows "No meetings yet — Meetings appear after you record a call, or when your calendar syncs" with a "Record a meeting" button. This is functional but bare. A new user's first questions are: what will happen when I record? how long does it take? will I see a transcript? The empty state answers none of these and provides no preview of the output they'd get.

### 6. TodayView emptyState offers "Import meeting recording" as the second action
`TodayView.swift:815–820` surfaces an import button when there are no meetings. "Import meeting recording" sounds technical and implies the user needs to have an audio file already. A non-technical user's mental model is "record → it appears." They don't know what format to import, where to find an existing file, or why they'd do this instead of recording.

### 7. No "first meeting" celebration or milestone
After a user records and processes their first meeting, nothing in the UI acknowledges it. There is no "Your first meeting is ready!" notification, no success state in Today, no prompt to explore the transcript or summary. The user has to know to open the Meetings tab and click on the new entry to discover the output. A user who doesn't see obvious evidence the meeting was processed is likely to assume it failed.

### 8. People tab is invisible in the new-user journey
There is nothing in onboarding or the Today empty state that mentions people / contacts. A non-technical user who opens the People tab on day 1 sees a contacts list with no entries and a complex multi-source import panel. They have no idea that MeetingScribe will automatically extract people from meeting attendees. The "add person" flow is completely non-obvious if you haven't recorded a meeting yet.

### 9. "Ollama" terminology exposed in settings
`OllamaChatClient.swift` and related settings presumably expose "Ollama" as the AI backend. A non-technical user will not know what Ollama is, whether it is set up, or why the chat might not work. If Ollama is not running, the chat silently produces no response (or an error) — there is no user-friendly "your local AI isn't running — here's how to fix it" state.

### 10. The 5-tab navigation has no visual hierarchy for a new user
`TodayView.swift`, `MeetingsView.swift`, People, Tasks, Voice Notes — all five tabs are presented equally. A non-technical user has no signal about which tab is their home base, which one to use first, or what order makes sense. The word "Today" suggests "start here" but nothing else in the nav reinforces that.

---

## Existing items to endorse (from prior plan or codebase)

- **OnboardingSheet permission pre-explanation (audit 8.3):** The philosophy of explaining permissions before the system dialog is exactly right. Keep and expand it to include product value.
- **Screen Recording polling + "Reopen" button (`OnboardingSheet.swift:287–311`):** This is a genuinely thoughtful fix for a real macOS UX cliff. Non-technical users benefit from this most. Keep it.
- **MeetingsView actionable empty state (`MeetingsView.swift:341`):** "Record a meeting" button in the empty state is correct. Needs more context about what happens next.
- **TodayView backfill on appear (`TodayView.swift:44–52`):** Deferred backfills that don't block first paint are the right pattern — good for everyone, especially users on slower machines.

---

## NET-NEW recommendations

### U5-1: Post-Onboarding "First Steps" Card on Today
- **What:** After `hasCompletedOnboarding` flips to true, show a dismissible card at the top of Today (above all other content) with 3 concrete next steps: "1. Record your next meeting. 2. After it ends, open it to see your transcript + summary. 3. Ask the chat anything about your meetings." Card disappears once the user has their first processed meeting. No configuration required — it's purely informational and self-dismissing.
- **Why (second-brain angle):** The biggest threat to the second-brain value loop is abandonment before the first "aha" moment. This card bridges the gap between permission grant and first real value delivery.
- **Cross-feature connections:** Today (display), Meetings (first-meeting detection trigger), Chat (surfaces the chat feature unprompted)
- **Effort:** S | **Impact:** High
- **Deps:** none

### U5-2: Screen Recording Plain-Language Rewrite + Visual Explainer
- **What:** Replace "macOS screen-audio access" with "your Mac's system audio" throughout onboarding and settings. Add a simple 3-row visual inside the Screen Recording step: mic icon (your voice ✓), monitor icon (other people's voices ✓), camera icon (video ✗). A single illustration removes the "is this spying on me?" anxiety before it forms.
- **Why (second-brain angle):** Permission grant rate directly determines recording quality. Non-technical users skipping Screen Recording produces single-speaker transcripts — which are useless for capturing what others said.
- **Cross-feature connections:** OnboardingSheet, any Settings screen that mentions audio capture, RecordingMonitor
- **Effort:** S | **Impact:** High
- **Deps:** none

### U5-3: "First Meeting Ready" Success Notification + Guided Tour
- **What:** When `MeetingPipelineController` finishes processing a meeting for the first time (detectable via a `firstMeetingProcessed` flag in `AppStorage`), fire a macOS notification: "Your first MeetingScribe meeting is ready — transcript, summary, and action items extracted." Tapping the notification opens the meeting detail. Inside the detail view, show a one-time 3-tooltip coach-mark tour: "This is your transcript → This is your AI summary → These are your action items." Tour is shown once and stored in `AppStorage("hasSeenMeetingTour")`.
- **Why (second-brain angle):** Discovery of core features (transcript, summary, action items) is gated on the user knowing to look. Non-technical users need the product to show them what it did, not wait for them to find it.
- **Cross-feature connections:** MeetingPipelineController (trigger), NotificationManager (delivery), UnifiedMeetingDetail (coach marks), ActionItemStore (demonstrates action item extraction)
- **Effort:** M | **Impact:** High
- **Deps:** `NotificationManager.swift` already in `ScribeCore/Notifications/`

### U5-4: Chat Suggested Prompts for New Users
- **What:** When `ChatSession.messages` is empty (first session or cleared), render 4 tappable suggestion chips inside the chat panel: "What were my last 3 meetings about?", "What action items do I have this week?", "Who did I meet with most this month?", "Remind me what I discussed with [last meeting attendee]." Chips are replaced by the user's actual message history after the first send. Chips are generated dynamically using the user's actual data (most recent meeting title, most recent person name) so they feel personal, not generic.
- **Why (second-brain angle):** Chat tool-use is the highest-leverage feature for a second brain, but its discoverability for a non-technical user is near zero. Suggested prompts lower the barrier from "what do I even type?" to one tap.
- **Cross-feature connections:** ChatSession (empty state detection), MeetingManager (last meeting for dynamic chip copy), PeopleStore (last contact for dynamic chip copy)
- **Effort:** S | **Impact:** High
- **Deps:** ChatSession, OllamaChatClient

### U5-5: Ollama Health Check with Plain-Language Recovery UI
- **What:** On every app launch, `OllamaChatClient` should ping Ollama's health endpoint. If it fails, show a non-blocking banner in the chat panel (not a modal): "Local AI is offline — [How to fix ›]". The "How to fix" link opens a small popover with two steps: "1. Open Terminal and run: ollama serve" + a copy button, or "2. Download Ollama from ollama.com". If the user has never set up Ollama at all, detect this on first launch (before onboarding ends) and offer a guided setup step.
- **Why (second-brain angle):** Ollama being down silently breaks the entire chat/intelligence layer. A non-technical user who tries chat once, gets silence or an error, and never tries again has permanently lost access to the highest-value feature.
- **Cross-feature connections:** OllamaChatClient (health check), ChatSession (banner injection), OnboardingSheet (optional Ollama setup step for new installs)
- **Effort:** M | **Impact:** High
- **Deps:** OllamaService.swift, OllamaChatClient.swift

---

## Top 3 picks

1. **U5-3 (First Meeting Notification + Tour)** — closes the biggest drop-off cliff: user records a meeting, nothing obviously happens, they assume it failed and uninstall.
2. **U5-1 (Post-Onboarding First Steps Card)** — zero-effort path from permission screen to first value; bridges the dead blank Today state.
3. **U5-2 (Screen Recording Plain-Language Rewrite)** — single-speaker transcripts are the most common reason MeetingScribe looks broken to new users; fixing the copy costs almost nothing.
