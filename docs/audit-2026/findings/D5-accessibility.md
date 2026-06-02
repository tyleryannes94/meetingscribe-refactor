# D5 — Accessibility & Emotional Safety Audit

**Lens:** VoiceOver coverage, Dynamic Type, contrast in People views, and the emotional safety of copy/prompts when users engage in relationship introspection.

---

## 1. Executive Summary

The People module has some targeted accessibility wins but has significant structural gaps: Dynamic Type is applied through NDS font tokens for most UI, but 32 hardcoded `.font(.system(size:))` calls in `PersonDetailView.swift` alone bypass scaling. VoiceOver labels exist on exactly five interactive elements in the entire People surface — enough to show the pattern was started, nowhere near enough coverage for meaningful keyboard/AT navigation. The emotional tone of AI prompts is largely appropriate (observational, non-prescriptive), but one prompt type ("Sentiment & trends") uses the word "tense" as a classifier that could feel pathologizing when users are processing relationship strain. The "Stay in touch" framing in TodayView is warm and non-pressuring. No contrast issues in NDS tokens rise to WCAG failure at the specified alpha values, but tertiary text in dark mode sits at roughly 3.2:1 — below the 4.5:1 requirement for normal-sized text.

---

## 2. Full Audit by File

### 2.1 `PersonDetailView.swift` — VoiceOver coverage

**What's there:** Five `.accessibilityLabel` calls:
- Line 479: `"Edit all fields"` on the ellipsis button — good.
- Line 484: `"Delete person"` on the trash button — good.
- Line 1316: `"Log this meeting as an encounter"` on the `plus.circle` button — good.
- Line 1454: `"Dismiss analysis output"` on the xmark button — good.
- Line 1862: `"Delete encounter"` on the xmark in `EncounterRow` — good.

**What's missing:**

- The **initials-avatar circle** (line 396–403) has no `.accessibilityLabel`. VoiceOver reads it as an unlabeled group. Should be `.accessibilityLabel("\(current.displayName), avatar")` or `.accessibilityHidden(true)` if treated as decorative.
- The **inline identity tap target** (line 429–431) — `VStack` with `.onTapGesture { beginIdentityEdit() }` — has no accessibility modifier. It reads as a static text block, not an interactive element. Should carry `.accessibilityLabel("Edit name, role, and company")` and `.accessibilityAddTraits(.isButton)`.
- **Section nav-rail chips** (lines 312–332): all twelve chip buttons render with their label text only (`Text(item.label)`). VoiceOver will read "Tags", "Relationships", etc. but nothing indicates these are scroll-anchors ("jump to Tags section"). Add `.accessibilityHint("Scrolls to the \(item.label) section")`.
- **`FilterChip` in PeopleListView** (line 566–575): tag filter buttons have no `.accessibilityLabel` and no indication of toggled state. VoiceOver cannot communicate whether a filter is active. Add `.accessibilityLabel("\(label) filter, \(active ? "selected" : "not selected")")`.
- **PersonRow** (lines 525–556): the entire row is a `List` selection item, which macOS VoiceOver will read as the person's display name, but the recency timestamp (`"2d ago"`) has no context — VoiceOver reads it as a standalone number. Wrap the row in an `.accessibilityElement(children: .combine)` with a composed label: `"\(person.displayName)\(subtitle.isEmpty ? "" : ", \(subtitle)"), last interaction \(relative)"`.
- **Encounter add button affordances** (lines 490–504): three `.buttonStyle(.borderless)` buttons — "Encounter", "Relationship", "Ask AI" — have only their label `Text` for VoiceOver. The icon-only `systemImage` alongside each label means VoiceOver reads "plus calendar.badge.plus Encounter" (including the SF Symbol name). Use `Label` correctly with explicit `title` + `systemImage` and verify the title is what VoiceOver speaks (it should be), or suppress the image with `.accessibilityHidden(true)` on the image.
- **`deepAnalysisControl`** (lines 1723–1742): The "Run" / "Refresh" button has no label beyond its title, but the adjacent descriptive text ("One thorough pass over the entire history") is a separate `VStack` child that VoiceOver will not associate with the button. Add `.accessibilityLabel(deepNote == nil ? "Run deep analysis" : "Refresh deep analysis — last run \(dateFormatter.string(from: deepNote!.createdAt))")`.
- **Remove-relationship xmark button** (line 1263): `Image(systemName: "xmark.circle.fill")` with no `.accessibilityLabel`. Should be `"Remove \(rel.label) relationship"`.
- **Remove-favorite xmark button** (line 582–585): Same pattern — no label. Should be `"Remove \(fav) from favorites"`.
- **Remove-tag `TagChip`** (line 539–543): `TagChip(tag:removable:onRemove:)` — the remove button inside `TagChip` is not visible in this file; it needs auditing inside the shared component, but no `.accessibilityLabel` is passed through from this call site.
- **Photo thumb context menu** (line 1055–1058): the `CachedThumbnail` inside `photoThumb` has no `.accessibilityLabel`. VoiceOver cannot identify photos.

### 2.2 `PeopleListView.swift` — VoiceOver coverage

- **`NotionIconButton` for graph view** (line 200–203): The `NotionIconButton` component in `NotionDesign.swift` at line 244 reads `.accessibilityLabel(help.isEmpty ? systemName.replacingOccurrences(of:".", with:" ") : help)`. Here `help: "Graph view (experimental)"` is supplied, so VoiceOver correctly reads "Graph view (experimental)". Solid.
- **Sort menu** (line 160–172): the `Menu` label `Image(systemName: "arrow.up.arrow.down")` has no `.accessibilityLabel`. VoiceOver reads it as "arrow up arrow down" from the symbol name. Should be `"Sort people"`.
- **Bulk "Select" / "Done" button** (lines 177–182): correctly labeled by its `Text` content. Fine.
- **`ghostFooter` toggle** (lines 402–419): the button uses a `Label` which VoiceOver reads, but the state (showing vs. hiding) is not communicated as a toggled state. Add `.accessibilityLabel(showGhosts ? "Hide low-signal contacts" : "Show \(people.ghostCount) more contacts")` with `.accessibilityAddTraits(showGhosts ? .isSelected : [])` or use `.accessibilityValue(showGhosts ? "visible" : "hidden")`.
- **`DuplicateReviewSheet` "Not duplicates" button** (line 648): reads as plain text ("Not duplicates") — acceptable but adding `.help("Keep both records separate")` would improve discoverability.
- **`MSSearchField`** (line 222): the search field component is not audited here, but if it's a wrapped `NSSearchField` it needs an `.accessibilityLabel("Search people by name, company, or role")` explicitly.

### 2.3 `PersonAISuggestions.swift` — AI suggestion framing

The `PersonSuggestionEngine.generate` prompt (lines 31–47) is well-framed: "Be conservative — only suggest things clearly supported by the context, and never invent people or events." The instruction to never invent is a genuine safety measure.

**No emotional safety concerns here.** The suggestions are categorized as tags, relationships, and encounters — neutral organizational constructs. The "encounters" label itself is not charged.

One latent risk: if the model suggests a `tag` like "difficult" or a `relationship.label` like "estranged", the UI surfaces this verbatim as a chip without any tone-softening. The model is instructed to be conservative, but a small Ollama model may still emit unfiltered descriptors. NET-NEW recommendation follows.

### 2.4 `PersonDetailView.swift` — AI prompt tone (ConversationAnalysisPreset templates)

Lines 84–148: The `preamble` (line 85–91) anchors both parties as "adult professionals" — this is a prompt-engineering hack to prevent small model over-refusal, documented inline. Fine in context.

**`sentimentTrends` template (line 103–113):** The instruction "call out any recent shifts in mood, energy, or topic" and the parenthetical "(warm / tense / neutral / etc.)" is the most emotionally charged language in the entire codebase. The output feeds directly into the user's People profile and could be read during a moment of relationship tension. The word "tense" as an illustrative category is accurate but risks:
1. Making the user feel surveilled ("the AI is monitoring how tense my relationship is").
2. Validating a conflict interpretation that the AI cannot verify.

**Recommended reframe (see D5-8 below):** replace "warm / tense / neutral" with "warm / more formal / neutral / quieter" and change "call out recent shifts in mood" to "note any changes in how frequently or warmly you're connecting." This preserves analytical value while removing the clinical-diagnostic register.

**`communicationStyle` template (line 123–130):** "Describe [name]'s communication style" is third-person and objectifying. For an intimate relationship (partner, close friend), this framing positions the other person as a subject of analysis rather than a co-participant. For colleagues, it's fine. This is a problem the single-template design cannot solve without relationship-type awareness — which ties into the briefing's emphasis on type-path differentiation.

**The `preamble` "Do not refuse" instruction (line 90):** This is invisible to users but worth flagging — the model is being instructed to override its safety checks for any message content. This is acceptable for iMessage logs between consenting adults on a private device, but if future versions allow other data sources (shared notes, third-party imports), this instruction would need revisiting.

### 2.5 `Encounter.swift` — field names and copy

The `Encounter` model is clean and non-judgmental:
- `eventName: String` — neutral.
- `notes: String` with comment "Freeform — 'wore a purple shirt, works in renewable energy'" — the example is positive/factual and sets a welcoming precedent.
- No field named "conflict", "problem", or anything pathologizing.

**One gap:** there is no `mood` or `quality` field on encounters, which means a user who wants to log "this visit was hard" has no structured place to do so. The only option is free-text `notes`. For close relationship tracking (partner, family), this matters — a person may want to note that a visit was emotionally draining without writing a journal entry. A 1–5 felt-quality field with optional emoji label would serve this (see D5-6).

The `AddEncounterSheet` (lines 1869–1920) uses the label "Event" for `eventName` and "Notes" for `notes`. These are appropriate. The placeholder copy for `notes` (not set in the sheet — it's a plain `TextField("Notes…", text: $notes)`) is neutral. The "Save" / "Cancel" button pair is standard and appropriate.

### 2.6 `NotionDesign.swift` — color contrast

**Dark mode contrast analysis:**

| Token | Foreground RGB+α | Background RGB+α | Approx ratio | WCAG AA normal text (4.5:1) |
|---|---|---|---|---|
| `textPrimary` on `bg` | #F2EFE6 on #1C1B19 | High | ~13:1 | Pass |
| `textSecondary` on `bg` | #D2CC BE @ 0.72 effective | ~8:1 | Pass | |
| `textTertiary` on `bg` | #D2CCBE @ 0.42 effective | ~3.2:1 | **Fail** for normal text |
| `textTertiary` on `fieldBg` | #D2CCBE @ 0.42 on #FFF5E1 @ 0.055 | ~3.0:1 | **Fail** |
| `brand` (#7F56D9) on `bg` (#1C1B19) | | ~5.4:1 | Pass for large/bold |
| `brand` on `fieldBg` | | ~5.0:1 | Pass for large text; borderline normal |

`NDS.textTertiary` is used for:
- Encounter dates (`EncounterRow`, line 1854)
- Person row subtitle text (`PersonRow`, line 540)
- Tag filter timestamps
- All section-label eyebrow text
- "No encounters yet" / "No tasks" empty-state messages

These are small text (caption/caption2 ≈ 11–12pt). At approximately 3.0–3.2:1 against the dark background, they fail WCAG AA. Users with low-contrast vision sensitivity will struggle, particularly in the sidebar where `sidebarBg` is even darker (#161513), dropping contrast further.

**Light mode:** `textTertiary` is `(26,25,23 @ 0.38)` on `(248,247,245)` — approximately 3.5:1. Also below 4.5:1 for normal text.

**Brand on `bg`:** The purple #7F56D9 on dark #1C1B19 achieves approximately 5.4:1 — passes for normal text but is marginal. Interactive elements using only brand color (the "Suggest" / "Refresh" buttons in `aiSuggestionsSection`, for example) should be tested with users who have protan/deuteranopia.

**Light mode tertiary specifically:** The inline timestamp text in `PersonRow` — `"2d ago"` — is `textTertiary` on `bg` at 3.5:1 against the list background. This is non-interactive decoration, which WCAG allows at 3:1, but it is user data that the design implies is meaningful. Users who sort by "Recent activity" depend on this information being legible.

### 2.7 `TodayView.swift` — people-related copy

- **"Stay in touch"** (`SuggestedPeopleView.swift`, line 123): warm, invitation-style. Does not say "overdue" or "you've been ignoring". The sub-copy "Last talked N days ago" is factual and non-accusatory. This is the right tone.
- **ReconnectView row copy** (line 156–160): "Last talked over a year ago" — factual. Could feel guilt-inducing for someone who has deliberately distanced from a person. See NET-NEW D5-7.
- **"Suggested people"** heading (line 17): neutral. The question framing in `SuggestionRow` ("Is 'X' the same as Y?" / "Add X?") is conversational and non-pressuring.
- **No `.accessibilityLabel` on any element in `TodayView.swift`** — confirmed zero matches. The entire Today view, including all meeting cards, the "Follow-ups to send" section, and the "Stay in touch" card, has no explicit accessibility labeling. VoiceOver will read button titles and text content but miss semantic grouping and state.

### 2.8 `PersonExtractor.swift` — how people are named

- People extracted from transcripts receive a `oneLineSummary` (line 9). The example in the prompt (line 83) is "Raised the pricing concern" — professionally framed, observational, not judgmental.
- `primaryContext` values: "speaker", "attendee", "third_party" — neutral taxonomic labels, not shown to users (internal only).
- The filter `!selfAliases.contains(n)` (line 113) correctly prevents the user from appearing as an extracted person about themselves, which avoids a weird reflexive-analysis loop.
- No concerns here. The extraction is purely structural and the outputs are used only to propose People records, not to surface characterizations of behavior.

---

## 3. Existing Plan Items — Ranked Through This Lens

**Endorsing (highest priority from D5 perspective):**

1. **LAY-1 (contentMaxWidth relaxation):** The NDS comment at `NotionDesign.swift:14` already references Dynamic Type reflow as a prerequisite — "enlarged Dynamic Type can reflow — prereq for D5-2." This is correctly identified. Wide fixed layouts break Dynamic Type at XL/XXL settings. Endorsing as a prerequisite for accessibility compliance. Already partially done (1100 instead of 720).

2. **PPL-5 ("Notes" label collision → rename bio to "About"):** The current dual use of "Notes" — once for the bio section (`PersonDetailView.swift:1089`) and again for attached analyses (line 1500) — is confusing for sighted users and creates a VoiceOver navigation nightmare: two sections both announced as "Notes". Renaming the bio to "About" is a one-line fix with high VoiceOver impact.

3. **PPL-1 (inline identity editing):** Already partially implemented. The tap target on the name+role+company block (line 429) is critical for motor-accessibility users who cannot accurately hit a small "Edit" button but can tap a larger text region. The current implementation still lacks the `.accessibilityAddTraits(.isButton)` that would signal its interactivity to VoiceOver.

---

## 4. NET-NEW Recommendations

### D5-1 — Comprehensive VoiceOver pass on People views (S)

**What:** Add `.accessibilityLabel` + `.accessibilityAddTraits(.isButton)` to all icon-only interactive elements in `PersonDetailView`, `PeopleListView`, and `SuggestedPeopleView`. Specifically: avatar circle (decorative → `.accessibilityHidden(true)`), section nav chips (add `.accessibilityHint`), relationship remove buttons, favorite remove buttons, sort menu icon, filter chip active-state, and `FilterChip` active/inactive announcement.

**Why:** Currently 5 explicit labels cover a view with ~40 interactive elements. A VoiceOver user navigating a person's profile cannot perform basic tasks: they cannot determine which filter chip is active, cannot remove a relationship label, and cannot identify photos.

**Effort:** S — purely additive modifiers, no logic changes.

### D5-2 — Replace all hardcoded `.font(.system(size:))` in People views with `scaledFont` or NDS tokens (M)

**What:** `PersonDetailView.swift` alone has 32 calls to `.font(.system(size:))` (confirmed by grep). These hardcode the point size and do not scale with the user's system text-size setting. The `scaledFont` modifier already exists in `NotionDesign.swift:139` and `@ScaledMetric` is already used in `ScaledSystemFont`. The fix is mechanical: replace each `.font(.system(size:X))` with `.scaledFont(X, relativeTo: .body)` or the appropriate NDS token.

**Why:** Low-vision users who set their Mac to XL or Accessibility text sizes will see People labels, timestamps, and section headers lock at small sizes while other app content scales. This is a WCAG 1.4.4 failure ("Resize text").

**Effort:** M — 32 call sites in `PersonDetailView` + additional in `PeopleListView`, `SuggestedPeopleView`, `TodayView`. Mechanical but needs visual QA at each text size step.

### D5-3 — Raise `NDS.textTertiary` contrast to 4.5:1 minimum (S)

**What:** Increase dark-mode `textTertiary` alpha from 0.42 to approximately 0.58 (keeping the warm neutral tint), and light-mode from 0.38 to 0.50. Run spot-checks against `bg`, `sidebarBg`, and `fieldBg` at both values.

**Why:** At 0.42/dark, `textTertiary` renders at ~3.2:1 against `bg` — below the WCAG AA 4.5:1 threshold for normal (non-large) text. This token is used for encounter dates, person row subtitles, all empty-state messages, and section labels — non-decorative, user-meaningful text.

**Note:** Test that raising alpha does not collapse the visual hierarchy between `textSecondary` and `textTertiary` — if it does, also raise `textSecondary` proportionally.

**Effort:** S — two constant changes in `NotionDesign.swift`, visual QA across all surfaces.

### D5-4 — Add `.accessibilityLabel` to TodayView people-related elements (S)

**What:** The entire `TodayView.swift` has zero `.accessibilityLabel` modifiers (confirmed). Add:
- `SuggestedPeopleView`: `.accessibilityLabel("Suggested person: \(suggestion.extractedName). \(suggestion.summary). From meeting: \(suggestion.meetingTitle). Actions: Add, Dismiss.")` or use `.accessibilityElement(children: .contain)` with grouped labeling.
- `ReconnectView` cards: `.accessibilityLabel("Stay in touch with \(item.person.displayName). \(Self.lastText(item.last)). Tap to open profile.")`
- Section headers ("Stay in touch", "Follow-ups to send", etc.): `.accessibilityAddTraits(.isHeader)`.

**Effort:** S — non-breaking additive.

### D5-5 — Reframe `sentimentTrends` prompt copy to be observational, not diagnostic (S)

**What:** In `PersonDetailView.swift:103–113`, change the `sentimentTrends` template:

- **Current:** `"Analyze sentiment trends... Identify the general tone (warm / tense / neutral / etc.) and call out any recent shifts in mood, energy, or topic."`
- **Proposed:** `"Describe how the conversation has felt recently: how often you're connecting, whether the topics are warmer or more practical, and any shifts in frequency or length. 5–8 sentences. Ground every observation in the messages — no speculation."`

Remove the parenthetical "(warm / tense / neutral / etc.)" — these labels are analyst-speak that, rendered back to a user reviewing a strained relationship, can feel like a clinical verdict on a situation the AI cannot fully understand.

Change the saved note kind label from `"sentiment"` to `"connection-patterns"` to align with the reframe.

**Why:** The sentimentTrends preset is the only place in the entire codebase that uses clinical-register language about relationship quality. When a user runs it on a friend they are drifting from, or a partner they are arguing with, reading "the tone has been tense recently" in their own notes app can amplify distress rather than help. Observational language ("you're connecting less frequently") is equally informative without the diagnostic weight.

**Effort:** S — prompt text change only.

### D5-6 — Add optional felt-quality field to Encounter model (S-M)

**What:** Add an optional `quality: EncounterQuality?` field to `Encounter.swift`. Define `EncounterQuality` as an enum with cases like `.energizing`, `.neutral`, `.draining`, `.difficult` — or a simple 1–3 scale with emoji. Surface this in `AddEncounterSheet` as an optional row: "How did it feel?" with 3–4 tappable emoji/icon options (no label required — the icons carry the meaning and are less clinical than a slider).

**Why:** For close relationships (partner, family, close friends), users will want to log that a dinner was hard, or that a call left them feeling better. The current Encounter model offers only free-text `notes`, which requires the user to explicitly write "this was draining" — creating unnecessary friction and a written record that may feel harsh to reread. A lightweight felt-quality signal gives the AI better input (for "how are my interactions with this person going?") without requiring the user to pathologize in writing.

**Effort:** S for the model and sheet UI. M if you want the quality to feed into the AI context blob in `personContextForAI()`.

### D5-7 — Make "Stay in touch" nudges opt-out per person (S)

**What:** Add a per-person flag `suppressReconnectNudge: Bool` to the Person model, settable from the ReconnectView card via a long-press/right-click context menu: "Don't remind me about [name]". When set, exclude the person from `ReconnectView.candidates`.

**Why:** Users track people in their People list for many reasons — estranged family members, former colleagues, people they've deliberately stepped back from. Seeing "Last talked over a year ago — time to reach out?" about someone they've intentionally distanced from creates anxiety and a sense of surveillance without consent. The opt-out respects user agency and avoids the app making implicit value judgments about which relationships should be maintained.

**Effort:** S — one bool on the Person model, one menu item in `ReconnectView`, one filter in `candidates`.

### D5-8 — Add relationship-type sensitivity layer to AI prompt templates (M)

**What:** Thread the relationship type (partner, family member, close friend, colleague, acquaintance) from the Person model into `ConversationAnalysisPreset.template(personName:customPrompt:)`. Add a second parameter `relationshipType: String?`. For intimate types (partner, family, close friend), soften the template framing:

- Remove third-person objectifying language ("describe [name]'s communication style") in favor of first-person relational language ("describe how you and [name] communicate together").
- For the `communicationStyle` preset with an intimate relationship, add to the preamble: "Frame this as a reflection on the connection, not an analysis of the other person's behavior."
- For `sentimentTrends` with an intimate relationship, add: "This person matters deeply to the user — be especially careful not to characterize the relationship in reductive terms."

**Why:** A single prompt template for "communication style" works for colleagues but is objectifying for a romantic partner. The briefing explicitly calls out relationship type paths as the primary audit focus. This is the minimal first step toward type-aware AI framing without requiring full template branching.

**Effort:** M — requires surfacing the relationship type in the `ConversationAnalysisPreset` call chain, which currently only has access to the person's name. Needs a small model change to pass the relationship label.

### D5-9 — Add `accessibilityReduceMotion` guard to People view animations (S)

**What:** `NotionDesign.swift` already defines `NDS.motion(_:reduce:)` at line 116 and the `pulsingSymbol(active:)` extension at line 126, both gated on the `accessibilityReduceMotion` environment variable. However, `withAnimation` calls in `PeopleListView` (line 405: `withAnimation { showGhosts.toggle() }`) and the `QuickActionCard` hover animation (`NotionDesign.swift:397`) are not gated. Apply the `NDS.motion` helper or read `@Environment(\.accessibilityReduceMotion)` at both call sites.

**Effort:** S — two call sites; pattern already established in the codebase.

### D5-10 — VoiceOver announcement for AI generation state (S)

**What:** When `aiRunning` transitions from `false → true` and back in `aiSuggestionsSection`, post an `.accessibilityAnnouncement` so VoiceOver users know a background process started/finished. Currently the only state indication is a `ProgressView` that VoiceOver cannot meaningfully describe in context.

```swift
// When aiRunning becomes true:
UIAccessibility.post(notification: .announcement,
    argument: "Generating AI suggestions for \(current.displayName)")
// When aiRunning becomes false (success):
UIAccessibility.post(notification: .announcement,
    argument: aiSuggestions?.isEmpty == false
        ? "AI suggestions ready for \(current.displayName)"
        : "No new suggestions found")
```

**Effort:** S — two `UIAccessibility.post` calls (macOS: `NSAccessibility.post(element:notification:)`).

### D5-11 — Emotional safety onboarding note for relationship analysis features (S)

**What:** The first time a user runs any `ConversationAnalysisPreset` on a person they have categorized as "partner", "family", or "close friend", show a one-time tooltip or inline note:

> "AI analysis reflects patterns in messages, not the full picture of your relationship. It's a starting point for reflection, not a verdict."

Show this inline below the analysis result, not as a blocking dialog. Include a "Don't show again" link.

**Why:** Users who are in relationship difficulty are exactly the users most likely to run sentiment analysis on a close contact. An AI output that reads "the tone has been strained recently" — even after the prompt improvements in D5-5 — can feel devastating without context. A one-sentence framing reminder costs almost nothing and could prevent a user from reading an AI output as an authoritative judgment on their relationship.

**Effort:** S — one `@AppStorage` bool + one inline conditional `Text` view.

### D5-12 — Audit and label AI suggestion chips with dismiss affordance for VoiceOver (S)

**What:** The suggestion chips in `aiSuggestionsSection` (line 706–719) show a tag chip with `"Add '\(label)'"` help text. But there is no dismiss action on individual suggestions — the only way to hide a suggestion is to accept it or wait for a refresh. VoiceOver users have no way to dismiss unwanted suggestions without accepting them. Add a small "Dismiss" button (`Image(systemName: "xmark")`) to each `suggestionRow` with `.accessibilityLabel("Dismiss suggestion: \(title)")`. Update `dismissedSuggestions` on tap. This also removes an existing UX gap for sighted users.

**Effort:** S — UI addition to `suggestionRow` and `suggestionChip`.

---

## 5. Top 3 Picks

| Rank | ID | Why highest priority |
|------|-----|---------------------|
| 1 | **D5-2** | 32 hardcoded point sizes in `PersonDetailView` block Dynamic Type scaling for the app's richest, most-used view. This is a WCAG 1.4.4 failure that affects every low-vision user. Mechanical fix with established infrastructure. |
| 2 | **D5-5** | The `sentimentTrends` prompt is the only place in the codebase that uses diagnostic language about relationship quality. Given the briefing's emphasis on relationship coaching, not surveillance, this is the most urgent emotional safety fix. It's a prompt text change — minutes of work, potentially significant user impact. |
| 3 | **D5-1** | Zero VoiceOver usability on 35+ interactive elements in the People views. A keyboard/AT user cannot navigate a person's profile, filter by tag, or dismiss suggestions. Five minutes of label additions per section would bring baseline compliance; a systematic pass is needed. |

---

## 6. Single Highest-Priority Recommendation

**Fix D5-2 first.** Dynamic Type support is foundational — it must be in place before any other accessibility work (VoiceOver labels on text that doesn't scale are worse than no labels). The infrastructure is already built (`scaledFont`, `NDS` tokens, `@ScaledMetric`). The 32+ hardcoded sizes in `PersonDetailView` are a WCAG failure that affects the primary relationship-management surface every session. A focused two-hour pass replacing `.font(.system(size:X))` with `scaledFont(X, relativeTo:)` or the nearest NDS token would close this gap entirely.
