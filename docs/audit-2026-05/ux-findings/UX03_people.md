# People / CRM — UX & Small-Feature Quick-Wins (Senior PM lens)

Low-lift polish for the People tab (list + detail, tags/filtering, editing, memories/encounters/relationships, photos, links). Anchors FEAT-A (email+people linking) and FEAT-B (multi-select bulk tagging) are canon — everything below is **net-new and complementary**, built to make those anchors shine.

Surface audited live: `PeopleListView.swift`, `PersonDetailView.swift`, `PeopleStore.swift`, `PeopleTagStore.swift`, `AddPersonSheet.swift` in `~/MeetingScribeRefactor/Sources/MeetingScribe/People`.

## Lift from V4

- **PPL-1 (Inline person editing)** — already partly shipped (`PersonDetailView.swift:337-368` inline identity edit). Re-affirm; the wins below extend it (clickable contact rows, tag prefill).
- **D1-5 (clickable person↔meeting↔task links)** — directly relevant: the "In your recordings" rows in the Meetings tab (`PersonDetailView.swift:528-545`) are dead `HStack`s with no tap target, while "Mentioned in" rows (`:725`) *are* clickable. Unify so both route.
- **D1-2 (`meetingscribe://` scheme + onOpenURL)** — unlocks "open this person" deep links from MCP/Shortcuts; pairs with FT3-4 quick-add.
- **D2-3 (unify accent to brand purple)** — the People filter chips and tab underline already use `NDS.brand` (`PeopleListView.swift:284`, `PersonDetailView.swift:262`); keep them on-brand as the global pass lands.

---

## UX improvements (5)

### UX3-1 — Make contact rows actionable (mailto / tel / copy), not dead text
**Friction today:** `contactRow` (`PersonDetailView.swift:647-652`) renders email/phone/address as plain `Text` with only `.textSelection(.enabled)`. To email someone you see in the CRM you must select → copy → switch to Mail → paste → type. That's 5+ steps and leaves the app. This silos the CRM from the comms it's supposed to anchor (violates Fluid-connection principle).
**Fix:** Wrap each row in a `Button`/`Link` — email → `mailto:`, phone → `tel:`/`facetime:`, address → Apple Maps; add a hover "copy" affordance. ~15 lines, reuses the existing row builder.
**Clicks:** email a contact 5+ → **1**.
**Effort:** S.

### UX3-2 — Surface "last interaction" in the list row
**Friction today:** `PersonRow` (`PeopleListView.swift:256-270`) shows only `role · company`. The store already sorts by `relevanceScore` using `lastInteractionAt` (`PeopleStore.swift:1077-1081`), but the user can't *see* recency — so "who have I gone cold on?" requires opening each person (1 click each, N people). The whole stay-in-touch value of a CRM is invisible in the list.
**Fix:** Add a trailing relative-date label ("2w ago" / "—") to `PersonRow` from `person.lastInteractionAt`. Pure read, no new state.
**Clicks:** judge recency N clicks → **0** (visible at a glance).
**Effort:** S.

### UX3-3 — Prefill the active tag when adding a person while filtered
**Friction today:** When the list is filtered to a tag chip (e.g. "Purple Party 2026", `PeopleListView.swift:207-212`) and the user hits **Add Person**, `AddPersonSheet()` opens with `tagIDs = []` (`PeopleListView.swift:43`, `AddPersonSheet.swift:34`). They must re-open the tag popover and re-pick the very tag they're standing in. Breaks the "bring frequent actions to the front" principle for the core event-roster workflow.
**Fix:** Pass `tagFilter` into the sheet as a seed (`AddPersonSheet(seedTagID:)`) and pre-insert it. ~6 lines.
**Clicks:** tag a new attendee 3 → **1**.
**Effort:** S.

### UX3-4 — Bring Encounter + Relationship "Add" to the identity panel (2-click rule)
**Friction today:** After clicking into a person, logging an encounter requires switching to the **Meetings** tab first, then Add (`PersonDetailView.swift:289, 669`) — and adding a relationship is only reachable once the Relationships section already exists, which it doesn't render until there's ≥1 relationship (`PersonDetailView.swift:488`). So the *first* relationship is effectively unreachable from a fresh profile. Violates the 2-click rule.
**Fix:** Add a compact "＋ Encounter / ＋ Relationship" action pair under the identity buttons (`:449-467`), always visible, mirroring the existing inline-edit/ellipsis/trash row. Reuses the existing sheets.
**Clicks:** log encounter 2 → **1**; add first relationship (unreachable) → **1**.
**Effort:** S.

### UX3-5 — Multi-select tag *filtering* (AND chips), not single-select only
**Friction today:** Filter chips are mutually exclusive — tapping a second chip replaces the first (`PeopleListView.swift:209-211` sets `tagFilter` to a single id; `filteredPeople` takes one `tagID`, `PeopleStore.swift:1083`). "Everyone who is *both* 'Investor' *and* 'SF'" is impossible; the user falls back to scanning. This is the read-side complement to FEAT-B's write-side bulk tagging.
**Fix:** Change `tagFilter: String?` → `Set<String>` and intersect in `filteredPeople` (`result.filter { $0.tagIDs.isSuperset(of: selected) }`). Chips toggle in/out of the set. ~20 lines across two files.
**Clicks:** narrow to two tags (impossible) → **2 chip taps**.
**Effort:** small-M.

---

## Feature improvements (5)

### FT3-1 — Tag-management mini-UI (rename / recolor / delete / merge)
**What/why:** `PeopleTagStore` exposes `renameTag`, `deleteTag`, `setEventDetails` (`:110-131`) but **nothing in the UI calls them** — a typo'd tag ("Purpl Party") is permanent and clutters the chip row forever. Add a small "Manage tags…" popover (gear next to the chips, `PeopleListView.swift:202`) listing tags with rename / color / delete, plus a count of how many people use each (`usedTagIDs`/per-tag count already derivable). Makes FEAT-B's bulk-tagging trustworthy — you can clean up after a bad bulk apply.
**User value:** Keeps the taxonomy clean; unblocks the single most-used filter surface. **Effort:** small-M. **Dep:** none.

### FT3-2 — Bulk-action bar pattern (the chrome FEAT-B lives in)
**What/why:** FEAT-B adds multi-select + bulk tagging; it needs a host. Define a thin selection bar that slides up over the list when ≥1 row is checked — "N selected · Tag · Remove tag · Merge · Delete · Clear". This is the *frame*, not the tag logic (which is FEAT-B). Building it as a reusable bar means bulk-delete and bulk-merge (FT3-3) come nearly free.
**User value:** One consistent home for every multi-row action; no buried menus. **Effort:** small-M. **Dep:** complements FEAT-B (don't duplicate its tag picker).

### FT3-3 — Manual merge from selection (pick 2, merge)
**What/why:** Dedupe today is automatic-only — "Merge all duplicates" or the heuristic `DuplicateReviewSheet` (`PeopleListView.swift:82, 294`). There's no way to merge two people the heuristic *misses* (e.g. "Bob" vs "Robert Smith", no shared email). `mergePeople(keep:remove:)` already exists (`PeopleStore.swift:726`). Wire a "Merge 2 selected" action into the FT3-2 bar that opens a tiny keeper-picker.
**User value:** Closes the dedupe gap the auto-merge can't reach. **Effort:** S (store method exists). **Dep:** FT3-2 selection bar.

### FT3-4 — Global Quick-Add Person (⇧⌘P from anywhere)
**What/why:** The shortcut hint "(⇧⌘P)" is already shown (`PeopleListView.swift:97`) and `AddPersonSheet` is built to be presented globally (its doc-comment says so, `AddPersonSheet.swift:2-3`), but adding a person still effectively means navigating to the People tab first. Register a true app-level command so a name can be captured mid-meeting without leaving the current tab.
**User value:** Capture-anywhere — the CRM grows during the meeting, not after. **Effort:** S. **Dep:** light (app command registration); pairs with D1-2.

### FT3-5 — Birthday & "going cold" nudges in the identity panel
**What/why:** Birthday is stored and shown as a static date (`PersonDetailView.swift:586-588`) with no "in 3 days" / age cue, and `lastInteractionAt` is never surfaced as a prompt. Add two tiny inline badges in the identity panel: "🎂 in 5 days" when within 14 days, and "Last spoke 4 mo ago" when stale. Pure derivations from existing fields; no new storage.
**User value:** Turns the CRM from a filing cabinet into a relationship prompt — the reason people keep a personal CRM. **Effort:** S. **Dep:** stronger once V4 P2-1 makes `lastInteractionAt` truthful, but works today on the stored value.

---

## Top 3 picks

1. **UX3-1 — Actionable contact rows (mailto/tel/copy).** Pure win, ~15 lines, kills a 5-step copy-paste-app-switch and directly serves Fluid-connection. Highest value-per-line on the surface.
2. **FT3-1 — Tag-management mini-UI.** Store methods already exist and are unreachable; a small popover makes tags (and therefore FEAT-B bulk tagging) safe to actually use.
3. **UX3-4 — Encounter/Relationship Add on the identity panel.** Fixes a true 2-click-rule violation *and* an unreachable-first-relationship dead end, reusing existing sheets.

**Single highest-value low-lift win:** **UX3-1** — making email/phone/address tappable. It's the smallest diff with the biggest "this feels like a real CRM" payoff and stitches the People tab into the user's actual communication tools.
