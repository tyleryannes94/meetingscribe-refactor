# D2 — Onboarding & First-Run UX Audit

**Lens:** Path from install to first meaningful relationship-type interaction —
friction in adding the first person, trust signals, and how the app explains
the People / relationship-coach angle.

---

## 1. What onboarding currently covers

The first-run path has three distinct phases:

### Phase 1 — Permission onboarding (`OnboardingSheet.swift`)
Shown once when `hasCompletedOnboarding == false` (`MainWindow.swift:71–72`).
A 480×480 modal with step dots walks the user through:

1. **Vault location** (`OnboardingSheet:54–121`) — choose iCloud Drive vs a
   custom folder. Good: sensible default, one-tap "Use iCloud Drive" button.
2. **Five permission screens** (`PermissionKind.allCases`) — Microphone,
   Screen Recording, Calendar, Notifications, Accessibility. Each screen has
   a subtitle, bullet list of use cases, and skip affordance.

**What the onboarding does NOT mention:**
- The People module exists.
- The app is a relationship coach / Second Brain for the people in your life.
- What "People" means or what value it delivers.
- That you should add anyone before, during, or after your first meeting.

The value proposition presented is entirely: *local transcription + summary*.
The relationship layer — arguably the app's deepest differentiator — is
invisible during first-run.

### Phase 2 — AI-stack readiness (`SetupCheckSheet.swift`, `SetupReadiness.swift`)
Shown automatically after onboarding if Whisper model or Ollama is not ready
(`MainWindow:442–448`). Covers transcription model download and Ollama startup.
Clean, non-technical UI. Skippable. Zero mention of People or relationship
features — this is correctly scoped to recording prerequisites.

### Phase 3 — Sample meeting seed (`SampleMeetingSeeder.swift:17–99`)
First-launch only, seeds one canned "Welcome to MeetingScribe" meeting so
Today is never empty (`MainWindow:364`). The sample summary reads as a
meeting-recorder demo. The only People-adjacent gesture is a single bullet:
"Try clicking an attendee chip above to add them to People" — buried in the
sample action items. There is no sample Person, no People tab prompt, no
explanation of what the People module is for.

---

## 2. Path to first meaningful People interaction

1. User completes onboarding → lands on Today.
2. Today shows: sample meeting card, quick actions (record/voice note/import), task widget. Nothing pointing to People.
3. User must independently discover the People tab in the left nav rail (`MainWindow.swift:124`) labeled "People" with icon `person.2`.
4. Clicking People → `PeopleListView`. Empty state (`PeopleListView:452–456`): "No people yet. Use Add Person or Import above to get started — from Contacts, Gmail, your calendar, or a file."
5. Empty state is utilitarian CRM-speak ("from Contacts, Gmail…") — not relationship-coach framing.
6. **Right pane** when nobody is selected: `PeopleInsightsView` — a relationship dashboard (reconnect nudges, birthdays, most-active). This is the best first-run discovery surface, but the user only sees it after navigating to People with zero people, which is a confusing context (a dashboard with no data).
7. To add the first person, user clicks "+" → `AddPersonSheet` (460×540 modal, `AddPersonSheet:111`). The sheet collects: Name, Company, Role, Email, Phone, Address, Favorites, Birthday, Tags, Notes.

**Critical gap: no relationship type in `AddPersonSheet`.** The sheet has no field for "Who is this person to you?" — partner, parent, close friend, colleague, acquaintance. The `Relationship` model (`Person.swift:51–63`) stores a `label: String` and a `toPersonID`, meaning relationships are between two People-records — not a classification of a person's role in the user's life. Assigning a relationship type requires: (a) adding a second person, (b) going into the first person's detail view, (c) scrolling to the Relationships section, (d) clicking "Add" (disabled until `people.count >= 2`, `PersonDetailView:1249`), (e) filling out a freeform TextField with placeholder text "spouse, manager, friend…", (f) searching for the second person. There is no path to say "this person is my partner" without another record already in the system.

---

## 3. Trust signals audit

For an app that holds sensitive personal data — relationship dynamics, iMessage
history, voice recordings — trust signals matter acutely. Current signals:

**Present:**
- Onboarding permission bullets mention "Read-only — never writes to your calendar" (Calendar bullet, `OnboardingSheet:381`) — good.
- Screen Recording bullet: "Used only for audio — no video, no screenshots" (`OnboardingSheet:379`) — good.
- `SetupCheckSheet` headline: "MeetingScribe runs entirely on your Mac" (`SetupCheckSheet:19`) — strong local-first statement.
- `AppSettings.allowRemoteOllamaEndpoint` default `false` with an egress-policy guard (`Settings.swift:272–274`) — good architecture, but never surfaced to the user.

**Missing:**
- No privacy statement in onboarding — zero mention of what data stays local, what (if anything) leaves the device, or who can see it.
- No trust signal specific to the People/relationship data. iMessage analysis (`PersonDetailView:MessagesAnalyzer`) reads a user's private message history — this is never explained during setup.
- No "all data stays on your Mac" hero statement *in the onboarding flow itself* (it exists in `SetupCheckSheet` but that's post-onboarding).
- No explanation of the vault (`vault/`) concept or what "local-first" means for their relationship data.

---

## 4. Relationship-coach angle

Zero evidence of the relationship-coach angle in the first-run path. No
copy, no framing, no persona. The word "relationship" appears in:
- The Relationships section label inside `PersonDetailView:1245` (buried deep in a person's profile).
- The `AddRelationship` sheet header (`PersonDetailView:1957`).
- `SuggestedPeopleView` section label "Stay in touch" (`SuggestedPeopleView:123`).

The app's deepest value — "I help you be a better partner, parent, friend by
remembering what matters about the people you care about" — is never stated.
The nav rail label just says "People". The empty state says "No people yet."
A new user who is not already pre-sold cannot discover that the app is a
relationship coach from the onboarding or first-run experience.

---

## 5. Endorsement of existing plan items (through this lens)

**Strongly endorse:**

- **PPL-1** (inline identity editing) — reduces the cost of the first edit after adding someone, but does not address the root gap (no first-run People story).
- **TDY-1** ("up next" hero strip) — reduces first-run confusion on Today, but still doesn't mention People.
- **D3-3** (sample meeting seed) — already done; the seed should be extended with a sample Person (see D2-5 below).

These existing items are worth doing but none closes the specific gap this audit surfaces: the complete absence of a People/relationship-coach narrative in the first-run path.

---

## 6. NET-NEW Recommendations

### D2-1 — Relationship-coach value screen in onboarding (S effort)
**What:** Add a single "splash" screen at the END of `OnboardingSheet` (after permissions, before dismissal) framing the People module. Copy example:

> **MeetingScribe remembers for you.**
> After every call, the people in your meetings are linked — their context, history, and follow-ups — all local, all searchable.
> Head to **People** to add the relationships that matter most.

Tap targets: "Go to People →" (switches section + opens `AddPersonSheet`) or "Start recording first". No new infrastructure needed — add a `case .intro` step to `OnboardingSheet`, render a static view, place it last in the step sequence.
**Why now:** This is the cheapest way to surface the app's core identity to every new user. Every user currently finishes onboarding with zero awareness that the relationship coach exists.

---

### D2-2 — Relationship TYPE as a first-class field in `AddPersonSheet` (S–M)
**What:** Add a "Relationship to you" picker as the first field in `AddPersonSheet`, above Name:

```
Relationship type:  [Partner]  [Family]  [Close friend]  [Colleague]  [Other]
```

Backed by a new `PersonRelationshipType` enum (or a `String` stored in
`Person.relationshipType`) — separate from the person-to-person `Relationship`
model. This answers "who is this person to ME" rather than "who are they to
another Person record." This field should inform: check-in cadence, coaching
prompts, which framework is offered (Gottman for partner, love languages for
family, NVC for difficult colleagues), and future notification copy.

**File:** `AddPersonSheet.swift:47–113`, `Person.swift:77–185`.
**Effort:** S to add the picker + store the field. M to wire cadence/coaching implications downstream.

---

### D2-3 — Seed a sample Person alongside the sample meeting (S)
**What:** Extend `SampleMeetingSeeder.seedIfNeeded` (`SampleMeetingSeeder.swift:17`) to also create one sample Person (e.g., "Alex Rivera") linked to the sample meeting, with a pre-filled bio, one memory ("loves coffee"), a `relationshipType` of "Colleague", and a "Stay in touch" note. This makes People non-empty on first launch, surfaces the PeopleInsightsView in a meaningful state, and demonstrates the end-to-end relationship capture story without the user doing any work.
**Effort:** S.

---

### D2-4 — "People" empty-state rewrite with relationship-coach framing (S)
**What:** Replace `PeopleListView:452–456` ("No people yet. Use Add Person or Import above…") with a purpose-driven empty state:

> **Your relationship memory starts here.**
> Add the people who matter — partner, family, close friends. MeetingScribe tracks your history with each one and reminds you when it's time to reconnect.
> [+ Add your first person] [Import from Contacts]

The existing import path stays; the primary CTA becomes adding a personally-meaningful person, not importing a contact list. The icon should be `heart.text.square` or similar — not the generic `person.2` — to signal the emotional register.
**File:** `PeopleListView.swift:452–456`.
**Effort:** S (copy + icon swap + button wiring).

---

### D2-5 — Trust statement banner in onboarding (S)
**What:** Add a persistent one-liner to the footer of every `OnboardingSheet` step (vault step AND all permission steps):

> "Your recordings, transcripts, and relationship notes never leave this Mac."

This is already true and architecturally enforced; it just needs to be said. Place it between the step-dots and the bottom of the permission body. Color: `NDS.textTertiary`. One line of SwiftUI in `permissionStepBody` and `vaultStepBody`.
**File:** `OnboardingSheet.swift:54–199`.
**Effort:** S (30-minute change).

---

### D2-6 — Guided first-person add flow with relationship-type branching (M)
**What:** After onboarding completes (`.onChange(of: showOnboarding)` in `MainWindow.swift:368–372`), if the People store is empty, present a lightweight "guided first add" — not the full `AddPersonSheet` but a 2-step card:

**Step 1:** "Who do you want to stay closer with?" — three large tap targets:
- Partner / Spouse
- Family member
- Close friend

**Step 2:** Name entry + optional birthday. Save creates the person with the chosen `relationshipType`, a default check-in cadence (weekly for partner, bi-weekly for family, monthly for friend), and an initial check-in reminder.

This creates the user's first person with high intent, framed in relationship terms, not CRM terms. The full `AddPersonSheet` remains available for subsequent adds.
**Effort:** M (new view + wiring, no model changes beyond D2-2's `relationshipType` field).

---

### D2-7 — iMessage privacy notice before first Messages analysis (S)
**What:** The app reads a user's iMessage history for conversation analysis
(`PersonDetailView:messagesSection`). Before the first `MessagesAnalyzer` call
on any person, show a one-time modal:

> "To analyze your conversations with [Name], MeetingScribe reads your
> iMessages on this Mac. This analysis runs locally — messages are sent to
> your local Ollama model only. Nothing leaves your Mac."
> [Analyze] [Not now]

Store the consent flag in `AppSettings` or `UserDefaults`. This is a meaningful
trust signal for sensitive data and reduces the risk of a user feeling surprised
by what the app can read.
**Effort:** S.

---

### D2-8 — "Relationship type" chip on Person row in the list (S)
**What:** Once D2-2's `relationshipType` field exists, show a color-coded chip
on each row in `PeopleListView` — e.g., a pink "Partner" chip, an orange
"Family" chip, a blue "Friend" chip. This gives the list a relationship-coach
visual identity rather than looking like a CRM contact list. It also helps the
user instantly see coverage ("I have my partner in here, but not my parents
yet").
**Effort:** S (once D2-2's model change lands).

---

### D2-9 — First-run "today's People" nudge on Today (S)
**What:** When `PeopleStore.shared.people.isEmpty`, show a single inline card on Today below the meetings section:

> **Add the people who matter.**
> Your contacts, encounters, and follow-ups all live in People.
> [Open People →]

Dismiss after the user adds their first person. Controlled by a `@AppStorage("hasAddedFirstPerson")` flag (set in `PeopleStore.updatePerson` when `people.count` goes from 0 to 1).
**File:** `TodayView.swift` (after the `emptyState` path or as an inlined section).
**Effort:** S.

---

### D2-10 — Relationship-type–specific onboarding journey (L)
**What:** This is the long game. Once relationship types exist (D2-2, D2-6),
build type-specific first-week journeys triggered on first add:

- **Partner path:** Day 1 notification "What's one thing [Name] did this week that you appreciated?" (love languages seed). Day 3: "Log an encounter with [Name]." Day 7: "How connected have you felt this week?"
- **Family path:** Similar but spaced at 2-week intervals with prompts oriented toward quality time and communication style.
- **Close friend path:** Monthly cadence, "You haven't logged a conversation with [Name] in 4 weeks — reach out?"

These are structured check-in template sequences, not push notification spam. Each nudge is a `UserNotification` at a time the user sets during the guided first add (D2-6). The prompts pre-populate an Encounter modal with a structured reflection template.
**Effort:** L (requires D2-2, D2-6, check-in template infrastructure, notification scheduling).

---

## 7. Top 3 picks

**D2-1 — Relationship-coach splash screen at onboarding end** is the single highest-priority recommendation. It costs an afternoon of work and ensures every new user understands what the app's deepest feature is before they close the onboarding flow. Without it, the majority of users will use MeetingScribe as a transcription tool and never discover the relationship layer.

**D2-2 — Relationship type as first-class field in AddPersonSheet** is the architectural keystone. Every downstream coaching feature — cadence, framework selection, check-in templates, notification copy — needs to know whether a person is a partner, family member, or friend. This is a one-day model + UI change that unblocks the entire relationship-coach roadmap.

**D2-6 — Guided first-person add flow** is the UX complement to D2-2. The existing `AddPersonSheet` is a CRM form. A guided flow built around "who do you want to stay closer with?" reframes the entire interaction in relationship terms and creates the user's first person with the correct context. Pair with D2-3 (sample person seed) for users who skip the guided flow.
