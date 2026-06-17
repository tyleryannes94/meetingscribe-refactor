# Audit — Person Detail Redesign (de-cram, fix buttons, de-tab)

*Agent: person-view. `PersonDetailView.swift`. User: "super crammed, weird button sizes for important things, a bunch of unnecessary tabs."*

## Current problems
- **Three columns at once.** `HSplitView` (line 366) = `detailPane` + chat column; `detailPane` (490) splits AGAIN into a fixed **300pt `identityPane`** (503) + tabbed `workArea` (570). The 300pt pane is the "crammed" one.
- **Identity pane overloaded** (503-518): 7 stacked sections in 300pt. `identityPanel` (778-909) alone packs avatar/name, inline-edit form, **two `FlowLayout` button rows (5+3 = 8 actions)**, relationship-type menu, health badge.
- **Weird button sizes (confirmed):** primary cluster (852-875) mixes `MSPrimaryButtonStyle` 34 next to `MSSecondaryButtonStyle` 30 → ragged; second cluster (880-897) is `.borderless`+`.font(NDS.small)` → tiny, sub-44pt taps, for *important* verbs (Log encounter). `reconnectSection` (1006) uses off-theme `.borderedProminent.controlSize(.small)`.
- **Too many tabs / siloing.** `MSPillTabs` (574) over `PersonTab` (.overview/.meetings/.messages/.notes); the scroll-indicator on the pills is itself a symptom of the 300pt cram. Tasks buried in Meetings tab; can't see open tasks + last meeting together.
- **Fit risk:** user confirmed "fit is good now"; current no-clip safety = the `FlowLayout` wrappers + scrolling pills. Moving actions to the *wide* canvas removes the constraint; keep `FlowLayout` for any multi-control metadata row.

## Proposed layout — two columns, one scrolling work canvas
Drop the inner 300pt split. `detailPane` becomes a single scrolling column: **compact full-width header** + collapsible `MSSection`s. Keep the outer chat column (out of scope).

**Compact header** (replaces `identityPanel`): `[avatar48] Name / role·company` on the left; `[Brief Me]` (the one `MSPrimaryButtonStyle` CTA) + `[⋯]` overflow on the right; a thin metadata row under the name with the relationship-type menu + one health badge (fold `healthRing` into it), wrapped in `FlowLayout` as the fit guardrail. The ⋯ menu holds the secondary actions: Log encounter, Add relationship, Ask AI, Edit, Edit all fields…, Delete (replaces both old button rows).

Section mapping (each an `MSSection`):
| Section | Contains | Default |
|---|---|---|
| Reconnect (if overdue) | `reconnectSection`(2073)+insight text(525) | expanded |
| **Tasks** | `tasksSection`(1762)+`commitmentLedger`(1801) | **expanded** |
| Meetings & decisions | add-to-meeting(677)+`meetingHistorySection`(1449)+`mentionedInSection`(1988)+`decisionsSection`(1414) | expanded |
| Identity | `tagsEditSection`(1058)+`contactRows`(1543)+`favoritesEditSection`(1110)+bio(1655)+`photosSection`(1595) | expanded |
| People | `relationshipsSection`(1875)+`inCommonSection`(1936)+weekly prompt(1913) | collapsed |
| History | `encountersSection`+heatmap(1664)+`storySection`(628) | collapsed |
| Notes & memories | `talkingPointsSection`(2291)+`memoriesSection`(2336)+`attachedNotesSection`(2563)+`evidenceSection`(2222) | collapsed |
| Messages | `messagesSection`(2365)+analysis | collapsed |
| footer | `provenanceFooter`(2634)+`aiSuggestionsSection`(1158) | — |

## Button-sizing fixes
Rule from `05`: one `MS*ButtonStyle` per role, no raw `.borderless`/`.borderedProminent`/`.controlSize` for actions.
1. `:852-875` — delete first FlowLayout row; keep `Brief Me` as the sole primary; Edit/⋯/Delete → overflow.
2. `:880-897` — delete the `.borderless` row; Log encounter/Relationship/Ask AI → overflow menu items.
3. `.borderless`+small accessories → `MSTertiaryButtonStyle`: `:1170`(Suggest),`:1881`(Add relationship),`:2382`(Scan),`:2421`(Analyze…),`:1601`(Add photo),`:1562`(Add email),`:1708`(checkInGoal).
4. `:1006` `.borderedProminent.controlSize(.small)` → `MSPrimaryButtonStyle`. `:1073/1134` bare `Button("Add")` → `MSTertiaryButtonStyle`.
5. Icon-only `.borderless` (trash, xmark, chevrons) → `.minTap()`.

## De-tabbing plan
Eliminate `MSPillTabs`/`PersonTab` (287-299,574). One scroll column of `MSSection`s (table above), per-section persisted open/closed (`@AppStorage`). Editable note surfaces (talking points/memories/attached) live under "Notes & memories"; keep inline add fields; repoint `keyboardVerbs` (344) `N` to expand that section, `T` to Tasks; delete `⌘1–5` (353-356) and dead `sectionNav` (698-738).

## Tasks integration
Promote `tasksSection`+`commitmentLedger` to a top-level **Tasks** section, **expanded by default, directly under the header** (highest-signal: open commitments). Quick-add (1775) + ledger (1801) move verbatim; header shows open-count via `MSSection` trailing slot.

## Build plan (each green; flag/section-by-section)
1. Adopt `MSTertiaryButtonStyle` at the `.borderless` accessories (pure visual). *(depends on `05` step1-2)*
2. Compact header: replace both button rows with Brief Me + ⋯ overflow; type menu + health in a `FlowLayout` metadata row. **Eyeball fit vs baseline here.**
3. Collapse inner two-pane into one `ScrollView` column, still keyed off `personTab` (transitional).
4. Convert sections to `MSSection`; promote Tasks; delete `PersonTab`/`personTab`/`workArea`/`workContent`/`MSPillTabs` use; repoint `keyboardVerbs`.
5. Button-size sweep + `.minTap()` on icon buttons.
