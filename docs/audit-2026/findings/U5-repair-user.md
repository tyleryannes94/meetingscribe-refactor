# U5 — The Repair-Focused User
## Lens: Emotional Safety, Private Reflection, and Conflict-Aware Relationship Tracking

**Scenario:** "I had a difficult conversation with my partner last night. I want to log it privately, think through what happened, and figure out how to repair things. This app is already on my Mac. Can it hold this for me safely?"

---

## 1. What the code actually offers today

### What is "safe" for this user right now

The data layer is **local-first JSON + SQLite**, stored in `~/Library/Application Support/MeetingScribe/` with no sync, no cloud upload, and no telemetry. `SecondBrainDB.swift` is a derived FTS index rebuilt from canonical JSON — no encryption at rest, but also no network surface. For a user whose threat model is "other apps / services reading my thoughts," the stack is safe enough. The JSON files are human-readable and Finder-browsable, which cuts both ways: there is no opaque cloud holding sensitive notes, but there is also no app-level encryption or password protection on the People folder.

**What the user CAN do today:**
- Create a Person record for their partner and add a freeform `Memory` entry (e.g., "Argument about household responsibilities, 2026-06-01") via `PersonDetailView.swift:1096–1112` (memoriesSection, inline add field).
- Add an `Encounter` entry with a location and freeform `notes` field — the closest thing to "logging where things stand" (`Encounter.swift:1–46`).
- Write a long-form `AttachedNote` (custom analysis → "Save to notes") to capture their own reflection (`PersonDetailView.swift:1495–1516`).
- Use the embedded "Ask AI about [partner]" chat column for real-time coaching questions (`PersonDetailView.swift:817–847`). This is the app's strongest asset for repair work.

---

## 2. What feels clinical or judgmental — specific framing concerns

### 2a. The "sentiment trends" preset (file:line — PersonDetailView.swift:103–113)

The `sentimentTrends` analysis preset reads iMessage history and outputs language like:

> "Identify the general tone (warm / **tense** / neutral / etc.) and call out any **recent shifts in mood, energy, or topic**."

For a user who just had a fight with their partner, seeing the AI output "tense" as a label on their relationship — stamped to the Messages section visible every time they open the person's profile — could feel like a clinical verdict, not a starting point. The word "tense" has no nuance around WHY, no compassion, and no next step. This is the most emotionally charged language in the codebase and it appears in a prominent, persistent UI surface.

**File:line:** `PersonDetailView.swift:104–111` (sentimentTrends template), rendered in `analysisResultView` at line 1437–1466.

### 2b. "Gone cold" framing (PeopleInsightsView.swift:22–38)

The insights dashboard shows a "Reconnect" card labeled **"Haven't talked in a while"** with `person.crop.circle.badge.exclamationmark` (an exclamation icon). For a user in a difficult period with their partner — where silence may be intentional, a boundary, or part of a repair cycle — being shown an alert icon and a "mark reached out" check button is tone-deaf. It implies inaction is a failure state.

**File:line:** `PeopleInsightsView.swift:22–38`

### 2c. Memories section is freeform with no privacy tier

`Memory.text` is a plain string with no sensitivity flag, no category, and no display-hiding affordance (`Person.swift:6–18`). When the user types "we argued about money again and I walked out," that memory sits in the same visual tier as "loves single-origin coffee." There is no way to mark a memory as private, collapse it, or protect it from being read by a casual shoulder-surfer viewing the profile. The section header just says "Memories" — there is no emotional container, no locked state, no hint that these could be sensitive.

### 2d. The AI prompt preamble anchors all context as "adult professional" (PersonDetailView.swift:84–92)

Every AI analysis prompt prepends:

> "You are an analyst summarizing the personal communication of the user (an adult professional named Tyler) and one of his adult contacts named [X]."

The word "professional" explicitly frames the relationship as workplace-adjacent. For a romantic partner, this framing is wrong and could cause the model to avoid emotionally meaningful language in favor of dry productivity-speak. The preamble exists to suppress safety refusals from small Ollama models — but its side-effect is desensitizing the output for intimate relationships.

**File:line:** `PersonDetailView.swift:84–92` (preamble string in `template(personName:customPrompt:)`)

### 2e. The encounter model has no emotional quality field (Encounter.swift:1–46)

An `Encounter` captures `eventName`, `date`, `location`, and freeform `notes`, but has no structured field for emotional valence, energy level, or relational state. A repair-focused user logging "difficult conversation 2026-06-01" has no way to mark this as "hard" versus the "Purple Party 2026" encounter in the same list. The encounters timeline looks identical regardless of the emotional register of each event.

**File:line:** `Encounter.swift:7–22`

### 2f. No privacy isolation for a "relationship type: partner" record

`Person.swift` has no `relationshipType` enum. The app treats a romantic partner identically to a colleague: same profile layout, same AI prompts, same insights card framing (birthday, "reconnect", "most active"), same meeting-mention backlinks. There is no dedicated flow, no different language, and no way to tell the system "this person is my partner — apply different defaults."

**File:line:** `Person.swift:77–184` (no `relationshipType` or `privacyLevel` field)

---

## 3. What is missing for a repair-focused user

### What would make this feel like a "private journal + coach"

The user has a difficult conversation. They want to:
1. **Log the event privately** — with emotional framing, not clinical taxonomy.
2. **Reflect without judgment** — write freely without the entry being analyzed or surfaced.
3. **Track the repair arc** — is this getting better or worse over time?
4. **Get non-judgmental coaching** — NVC prompts, Gottman de-escalation, repair attempts.
5. **Know the data is theirs alone** — visible confirmation nothing is leaving the device.

The app currently handles step 4 partially (the AI chat column exists and accepts free questions) but none of the others in a form designed for emotional safety.

---

## 4. Endorsing existing plan items (through this lens)

**PPL-1 (inline field editing):** Directly relevant — the repair user needs frictionless logging, not a modal interrupting a vulnerable moment. Endorse at highest priority.

**Relationship TYPE PATHS (Briefing §1):** This is the single highest-leverage gap. Partner / family / close friend paths with distinct prompts, distinct cadences, and distinct insight framing would address almost every emotional safety gap above. Fully endorse building this before any other People enhancement.

---

## 5. NET-NEW recommendations

### U5-1 — Relationship privacy tier on Person (S, P0 for this user)

Add a `privacySensitive: Bool` flag (default `false`) and a `relationshipType: RelationshipType` enum (`professional`, `personal`, `romantic`, `family`, `closeFriend`) to `Person.swift`. When `privacySensitive == true`:
- The person's entry is hidden from the "gone cold" insights card.
- Memories and encounters with a `sensitive` flag are collapsed by default with a "Tap to reveal" affordance.
- The AI preamble changes from "adult professional" to a relationship-type-aware frame.
- No backlink from meeting transcripts surfaces sensitive people on the main meetings list.

**File to change:** `Person.swift` (model), `PeopleInsightsView.swift` (filter), `PersonDetailView.swift` (preamble and memory display).

### U5-2 — Emotional quality field on Encounter (S)

Add `mood: EncounterMood?` to `Encounter.swift` where `EncounterMood` is an enum: `warm`, `neutral`, `difficult`, `repair`, `breakthrough`. Surface as a colored dot in the encounter list. Over time this becomes the emotional timeline the repair user is actually asking for. No DB migration — JSON default-nil is already the tolerant-decoder pattern (`Encounter.swift` uses same Codable approach as `Person`).

**File to change:** `Encounter.swift`, `AddEncounterSheet` (add mood picker), `EncounterRow` (add color dot).

### U5-3 — Relationship-type-aware AI prompt preamble (S)

The current preamble (`PersonDetailView.swift:84–92`) hard-codes "adult professional." Add a `promptPreamble(for person: Person)` helper that branches on `person.relationshipType`:
- `.romantic` → "You are a thoughtful, empathetic relationship coach helping Tyler reflect on his relationship with his partner [Name]. Be warm, specific, and non-judgmental."
- `.family` → "...helping Tyler reflect on his relationship with a family member..."
- `.closefriend` → "...reflecting on a close friendship..."
- `.professional` → existing preamble unchanged.

This directly fixes the desensitization in all six presets including `sentimentTrends`.

### U5-4 — "Difficult conversation" encounter shortcut (S)

Add a pre-filled encounter template: "Log a hard moment." Opening this shortcut pre-populates `eventName` with "Conversation", sets `mood = .difficult`, and opens a multi-line `notes` field with the prompt: "What happened? What did each of you need? What felt unresolved?" No AI involvement — just a structured journal entry. This is the immediate escape hatch the repair user needs at 11pm after the argument. The existing `AddEncounterSheet` is the right place; add a "Hard moment" template button at the top.

**File to change:** `AddEncounterSheet` (add template button), `Encounter.swift` (add `mood`).

### U5-5 — Repair arc visualization (M)

Once `Encounter.mood` exists, add a micro-chart to `PersonDetailView` (above the encounters list) that plots mood over the last 30 encounters as a sparkline. Color: `.difficult` = amber, `.repair` = blue, `.breakthrough` = green. The user can see at a glance whether things are trending better. This is the "is it getting better" question answered visually, not analytically. Implementation: a `Canvas`-based sparkline, ~80 lines, no external dependency.

### U5-6 — NVC / Gottman coaching prompt library for partner path (M)

The existing chat column (`PersonDetailView.swift:817–847`) has four hardcoded example prompts ("Give me a briefing on X", "What are my open tasks?", etc.) that are explicitly professional. For `relationshipType == .romantic` or `.family`, replace these with repair-aware prompts:
- "Help me understand what my partner needed in that conversation."
- "What's a repair attempt I could try today?"
- "How do I express my own needs without escalating?"
- "Reflect back what happened — was I listening?"

These are the Gottman Four Horsemen / NVC / DBT prompts baked in as seeded questions. The chat model already handles free-form questions; this is purely a UI strings change with relationship-type branching.

**File to change:** `PersonDetailView.swift:838–845` (examplePrompts array, branched by relationship type).

### U5-7 — Private memory toggle ("sensitive" flag on Memory) (S)

Add `isSensitive: Bool = false` to `Memory`. In `memoriesSection`, sensitive memories render as a collapsed card showing only the date and a lock icon, expandable on click. This gives the user confidence that a casual glance at their laptop won't expose the entry. The data stays in the same JSON — no encryption, but a UI-level hiding that respects the emotional register of the content.

**File to change:** `Person.swift` (Memory struct), `PersonDetailView.swift` (memoriesSection rendering).

### U5-8 — "Repair check-in" structured check-in template (M)

Add a relationship-type-specific check-in template for partner/family records. When a `Person` has `relationshipType == .romantic` or `.family` and the last encounter was marked `.difficult`, surface a gentle nudge in `PeopleInsightsView` (replacing the "reconnect" alert icon with a softer "How are things with [Name]? You logged a hard moment X days ago."). Tapping opens a structured check-in sheet with 4 questions:
1. How did things feel today? (mood picker)
2. Did anything shift? (freeform)
3. What do you want to remember? (freeform → Memory)
4. Do you need coaching? (opens AI chat pre-primed)

This is the habit loop the repair user needs: a gentle, non-judgmental invitation to re-engage after a hard moment.

### U5-9 — "No export, no cloud" privacy badge (S)

Add a one-line privacy disclosure near the top of `PersonDetailView` for sensitive relationships: a small lock icon + "Stored only on this Mac." This costs 3 lines of SwiftUI and directly addresses the "know it's mine alone" psychological need. The SecondBrainDB already does this technically — the badge just makes it legible to a user in a vulnerable state.

### U5-10 — Reframe "gone cold" language for personal relationships (S)

In `PeopleInsightsView.swift:22–38`, the "Reconnect" card uses `person.crop.circle.badge.exclamationmark`. For `privacySensitive == true` or `relationshipType != .professional` people, replace the exclamation icon with a softer `heart.circle` and change the subtitle from "Haven't talked in a while" to "Haven't checked in recently." Remove these people from the "gone cold" list entirely if their last encounter was marked `.difficult` or `.repair` — silence may be intentional in a repair context.

---

## 6. Top 3 picks

**Highest priority: U5-1 — Relationship privacy tier + type field on Person.**
Everything else in this audit depends on it. Without `relationshipType`, every other fix is a workaround. This is a model change (~15 lines in `Person.swift`) with cascading UX benefits — and it's the pre-condition for the BRIEFING's "relationship type paths" goal.

**Second: U5-3 — Relationship-type-aware AI preamble.**
A 30-line change in `PersonDetailView.swift` that transforms the AI from a "professional analyst" into an "empathetic coach" for the person that matters most to the user. Highest leverage-to-effort ratio in this audit.

**Third: U5-4 — "Difficult conversation" encounter shortcut.**
The repair user's immediate need at 11pm is a fast, safe place to log what happened. This is an S-effort addition to `AddEncounterSheet` that meets them at the moment of need.

---

## 7. Encryption gap (SecondBrainDB.swift)

Data is plaintext on disk. `SecondBrainDB.swift:53–58` stores at `~/Library/Application Support/MeetingScribe/secondbrain.db` with no SQLCipher, no keychain-backed key, and no `NSFileProtection`. The canonical JSON files (person.json) are equally open. For a user logging intimate conflict notes about their partner, this is a real gap — the Mac FileVault is the only protection. A future phase should offer SQLCipher or at minimum an OS-level Data Protection class for the Application Support folder. Not blocking for immediate repair-user features, but worth naming explicitly.

**File:line:** `SecondBrainDB.swift:84–86` (`sqlite3_open` — no encryption options passed)
