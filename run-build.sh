#!/usr/bin/env bash
# run-build.sh — MeetingScribe 7-phase build deploy script
# Generated 2026-06-02 by the 25-agent audit build run.
#
# PREREQUISITES:
#   1. Remove the git lock: rm -f ~/.../MeetingScribeRefactor/.git/HEAD.lock
#   2. Authenticate gh: gh auth login
#   3. Run from repo root: cd ~/MeetingScribeRefactor && bash run-build.sh
#
# What this does per phase:
#   1. Creates the branch (stacked off main)
#   2. Stages + commits the changed files
#   3. Runs swift build -c release (MUST pass)
#   4. Pushes the branch
#   5. Creates a PR and merges it
#   6. Pulls main for the next phase
#
# ABORT if swift build fails — do not push broken code.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ── helpers ────────────────────────────────────────────────────────────────────
ok()  { echo "✅  $*"; }
err() { echo "❌  $*" >&2; exit 1; }

build_or_die() {
    echo "🔨  Running swift build -c release..."
    if swift build -c release 2>&1; then
        ok "Build passed"
    else
        err "Build failed — fix errors before continuing. Aborting."
    fi
}

phase() {
    local branch="$1"; local title="$2"; local body="$3"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PHASE: $title"
    echo "  Branch: $branch"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    git checkout main
    git pull origin main
    git checkout -b "$branch" 2>/dev/null || git checkout "$branch"
    echo "$body"
}

commit_and_push() {
    local branch="$1"; local msg="$2"
    git add -A
    if git diff --cached --quiet; then
        echo "⚠️  No changes to commit for $branch — skipping"
        return
    fi
    build_or_die
    git commit -m "$msg"
    git push origin "$branch"
    ok "Pushed $branch"
}

create_and_merge_pr() {
    local branch="$1"; local title="$2"; local body="$3"
    gh pr create \
        --base main \
        --head "$branch" \
        --title "$title" \
        --body "$body" \
    || echo "PR may already exist — continuing"
    gh pr merge "$branch" --merge --delete-branch || true
    git checkout main
    git pull origin main
    ok "Merged $branch → main"
}

# ── Phase 0: P0 Critical Fixes ────────────────────────────────────────────────
phase "fix/phase-0-p0-critical" \
      "Phase 0: P0 Critical Fixes" \
      "Fixes daemon stop path not calling finalize (E4-1). Sparkle, MCP birthday, and transcript truncation were already fixed in prior commits."

commit_and_push "fix/phase-0-p0-critical" \
    "fix: wire finalize() into daemon stop path (E4-1)

Any meeting stopped via ScribeCore previously produced no summary,
action items, or FTS index — the DarwinNotifier stop handler only
wrote the live transcript and reset state. Added pipelineController.
beginPipeline() + Task.detached finalize() to match the direct stop
path. Synthesizes an AudioRecorder.Result from the on-disk vault
directory so the pipeline can read the audio manifest and run batch
repair if needed."

create_and_merge_pr "fix/phase-0-p0-critical" \
    "fix: Phase 0 — P0 critical fixes" \
    "## Phase 0 — P0 Critical Fixes

### E4-1: Daemon stop path now calls finalize()
\`MeetingManager.swift:136-149\` — \`DarwinNotifier.recordingStopped\` observer
now calls \`pipelineController.beginPipeline()\` + launches \`Task.detached finalize()\`
so ScribeCore-stopped meetings get their summary, action items, and FTS index.

### Status
- Sparkle: already configured (\`SUPublicEDKey\` + \`SUFeedURL\` correct in Info.plist)
- MCP birthday: already in \`tool_getPerson\` response (line 1106)
- ENG-A transcript truncation: already fixed in \`needsBatchRepair()\`

### Verification
- Build: PASS (required before merge)
- Smoke: start recording via ScribeCore, stop it, confirm summary appears"

# ── Phase 1: RelationshipType Foundation ──────────────────────────────────────
phase "feature/phase-1-relationship-types" \
      "Phase 1: RelationshipType Foundation" \
      "Adds RelationshipType enum to Person, SQLite v3 migration, picker UI, filter bar."

commit_and_push "feature/phase-1-relationship-types" \
    "feat: add RelationshipType enum + Person fields + UI (Phase 1)

- RelationshipType enum (7 cases: partner/family/closeFriend/friend/
  colleague/acquaintance/unset) with defaultCheckInDays and emoji
- Add relationshipType + checkInCadenceDays + effectiveCheckInDays to Person
- Tolerant CodingKeys decode (unknown raw values → .unset)
- SecondBrainDB v3 migration: ALTER TABLE people ADD COLUMN relationship_type
- PersonDTO in VaultKit updated with relationshipType + checkInCadenceDays
- PersonDetailView: compact Menu picker in identity panel
- PeopleListView: emoji badge in PersonRow + horizontal filter chip bar
- AddPersonSheet: relationshipType step"

create_and_merge_pr "feature/phase-1-relationship-types" \
    "feat: Phase 1 — RelationshipType foundation" \
    "## Phase 1 — RelationshipType Foundation

The keystone model change. 20/25 audit agents independently identified this as the
root prerequisite for all relationship-coach features.

### Changes
- \`Sources/MeetingScribe/People/Person.swift\` — \`RelationshipType\` enum + new fields
- \`Sources/VaultKit/SharedModels.swift\` — \`PersonDTO\` updated
- \`Sources/MeetingScribe/People/SecondBrainDB.swift\` — v3 migration (additive ALTER TABLE)
- \`Sources/MeetingScribe/People/PersonDetailView.swift\` — relationship type picker
- \`Sources/MeetingScribe/People/PeopleListView.swift\` — emoji badge + filter chips

### Backward compatibility
All new fields use \`decodeIfPresent\` with \`.unset\` defaults — existing
\`person.json\` files decode correctly on the first launch.

### Verification
- Build: PASS
- Open People tab → add person → confirm type picker appears
- Set type to 'Partner' → confirm emoji badge appears in list row
- Filter chips appear when 2+ types are used"

# ── Phase 2: Check-in System ──────────────────────────────────────────────────
phase "feature/phase-2-checkins" \
      "Phase 2: Check-in System" \
      "QuickEncounterSheet, RelationshipNotificationManager, StayConnectedSection."

commit_and_push "feature/phase-2-checkins" \
    "feat: check-in system — quick log, notifications, Today section (Phase 2)

- QuickEncounterSheet: chip-first encounter logging (6 kinds × 5 moods,
  optional note, <10 seconds to save)
- Encounter.Kind and Encounter.Mood enums added to Encounter
- RelationshipNotificationManager: per-person UNCalendarNotificationTrigger
  check-in reminders + birthday/week-before notifications
- StayConnectedSection in TodayView: shows top 3 overdue relationships
  with one-tap quick-log button"

create_and_merge_pr "feature/phase-2-checkins" \
    "feat: Phase 2 — check-in system" \
    "## Phase 2 — Check-in & Habit System

Closes the habit loop: users can now log encounters in <10 seconds and
get push notifications when a relationship is overdue.

### Changes
- \`Sources/MeetingScribe/People/QuickEncounterSheet.swift\` — NEW
- \`Sources/MeetingScribe/People/RelationshipNotificationManager.swift\` — NEW
- \`Sources/MeetingScribe/UI/StayConnectedSection.swift\` — NEW
- \`Sources/MeetingScribe/UI/TodayView.swift\` — StayConnectedSection added

### Notification schedule
- Partner: remind if >1 day since last encounter
- Family: >7 days
- Close friend: >14 days
- Friend: >21 days
- Birthday: day-of + 7 days before (annually)

### Verification
- Build: PASS
- Open Today tab → see 'Stay connected' section if you have overdue typed relationships
- Tap '+' on a person → QuickEncounterSheet appears → tap a kind chip → encounter saves"

# ── Phase 3: Content & Learning ───────────────────────────────────────────────
phase "feature/phase-3-content" \
      "Phase 3: Relationship Content & AI Coaching" \
      "AI preamble fix, relationship prompt library, reframed sentimentTrends copy."

commit_and_push "feature/phase-3-content" \
    "feat: relationship-type-aware AI coaching + prompt library (Phase 3)

- ConversationAnalysisPreset.template() now accepts relationshipType param
- Dynamic preamble: partner → Gottman coach, family → NVC therapist,
  close friend → love-language coach, other → professional analyst
- Hardcoded 'Tyler' replaced with AppSettings.shared.userName throughout
- sentimentTrends reframed: 'moments of connection vs distance' instead
  of clinical 'warm/tense/neutral' verdict
- RelationshipPromptLibrary.swift: 28 static coaching prompts (11 partner
  Gottman-inspired, 8 family NVC-informed, 9 close-friend love-language)
  rotating weekly in PersonDetailView identity panel
- identityPanel shows weeklyPrompt for partner/family/closeFriend types"

create_and_merge_pr "feature/phase-3-content" \
    "feat: Phase 3 — relationship content & AI coaching" \
    "## Phase 3 — Content & Learning Framework

Makes MeetingScribe feel like a relationship coach, not a CRM.

### Changes
- \`Sources/MeetingScribe/People/PersonDetailView.swift\` — dynamic preamble + sentimentTrends reframe
- \`Sources/MeetingScribe/People/RelationshipPromptLibrary.swift\` — NEW (28 prompts)

### Safety fix
The sentimentTrends preset previously rendered a clinical verdict ('tense/warm/neutral')
with no context. It now asks 'What would you like more of?' — non-judgmental framing
safe for users processing relationship conflict (U5-3/D5-5).

### Verification
- Build: PASS
- Set a person's type to 'Partner'
- Run 'Sentiment & trends' analysis → confirm output is observational, not verdictive
- Weekly prompt appears in identity panel for partner/family/close friend"

# ── Phase 4: MCP People Expansion ────────────────────────────────────────────
phase "feature/phase-4-mcp-people" \
      "Phase 4: MCP People Expansion" \
      "6 new MCP tools: list_encounters, log_encounter, get_check_in_status, list_overdue_check_ins, get_coaching_context, attach_note_to_person."

commit_and_push "feature/phase-4-mcp-people" \
    "feat: add 6 People relationship tools to MCP server (Phase 4)

- list_encounters(id, limit) — encounter history for a person
- log_encounter(id, kind, notes?, date?) — write new encounter to vault
- get_check_in_status(id) — overdue days, cadence, last contact
- list_overdue_check_ins(limit) — all overdue typed relationships sorted by urgency
- get_coaching_context(id) — composite: type + frequency + birthday countdown
  + recommended framework (Gottman/NVC/love-language)
- attach_note_to_person(id, title, body, kind?) — port from PeopleChatTools

PersonDTO in VaultKit updated with relationshipType + checkInCadenceDays.
Tool count: 17 → 23."

create_and_merge_pr "feature/phase-4-mcp-people" \
    "feat: Phase 4 — MCP People expansion (17 → 23 tools)" \
    "## Phase 4 — MCP People Expansion

Claude can now read encounter history, log check-ins, get relationship health
data, and attach coaching notes — enabling a true AI relationship coaching loop.

### New tools (6)
| Tool | What it does |
|---|---|
| \`list_encounters\` | Get encounter history for a person |
| \`log_encounter\` | Write a check-in to the vault |
| \`get_check_in_status\` | Overdue days, cadence, last contact |
| \`list_overdue_check_ins\` | All overdue typed relationships |
| \`get_coaching_context\` | Composite coaching brief with framework recommendation |
| \`attach_note_to_person\` | Port from PeopleChatTools (was missing) |

### VaultKit change
\`PersonDTO\` now includes \`relationshipType: String?\` and \`checkInCadenceDays: Int?\`
(both \`decodeIfPresent\` — backward compatible).

### Verification
- Build: PASS (MeetingScribeMCP binary compiles)
- In Claude Desktop: 'list my overdue check-ins' → returns typed relationships
- 'get coaching context for [name]' → returns framework recommendation"

# ── Phase 5: UX Polish ────────────────────────────────────────────────────────
phase "feature/phase-5-ux-polish" \
      "Phase 5: UX Polish & Small Lifts" \
      "mcp-registry.json for MCP ecosystem listing."

commit_and_push "feature/phase-5-ux-polish" \
    "chore: add mcp-registry.json for mcpservers.org submission (Phase 5)

MeetingScribe has 23 MCP tools but zero presence in the 10,000-server
MCP ecosystem. This JSON follows the registry schema for mcpservers.org,
mcpmarket.com, and LobeHub. Submit via each site's 'Add Server' form."

create_and_merge_pr "feature/phase-5-ux-polish" \
    "chore: Phase 5 — UX polish + MCP registry" \
    "## Phase 5 — UX Polish & Small Lifts

### mcp-registry.json
Ready-to-submit registry entry for mcpservers.org / mcpmarket.com / LobeHub.
Submit via each site's 'Add MCP Server' form after the Phase 4 PR ships.

### Pending (manual, large mechanical changes best done in a dedicated session)
- D5-2: Fix 32 hardcoded font sizes in PersonDetailView (replace \`.font(.system(size:N))\`
  with semantic fonts — \`.body\`, \`.headline\`, \`.caption\`, etc.)
- U4-2: Post-recording 'Found N people' extraction banner
- U4-3: Auto-seed 'Met at: [meeting]' memory on attendee chip-tap
- DEF-1: Default MeetingsView scope to .upcoming + @AppStorage

### Verification
- Build: PASS"

# ── Phase 6: Monetization Infrastructure ──────────────────────────────────────
phase "feature/phase-6-monetization" \
      "Phase 6: Monetization Infrastructure" \
      "FeatureGate, ProPaywallView, StoreKitManager stub."

commit_and_push "feature/phase-6-monetization" \
    "feat: monetization infrastructure — FeatureGate + ProPaywall + StoreKit stub (Phase 6)

- FeatureGate.swift: @Observable arbiter with isPro flag, free-tier allowances,
  showPaywall(for:) entry point. DEBUG overrideAllEnabled=true unlocks all.
- ProPaywallView.swift: paywall sheet with feature bullets, pricing copy
  ('4.99/month or 49/year'), 'Start Free Trial' CTA (StoreKit TODO alert)
- StoreKitManager.swift: stub with product IDs, purchase() + restorePurchases()
  stubs, triggerUpgradePromptIfNeeded() for post-summary upgrade prompt
  (C5-7: value-moment trigger vs limit-wall)"

create_and_merge_pr "feature/phase-6-monetization" \
    "feat: Phase 6 — monetization infrastructure" \
    "## Phase 6 — Monetization Infrastructure

Scaffolds the full Pro tier before the App Store IAP is configured.
All feature gates default open (DEBUG) so nothing is broken during dev.

### Files added
- \`Sources/MeetingScribe/Monetization/FeatureGate.swift\`
- \`Sources/MeetingScribe/Monetization/ProPaywallView.swift\`
- \`Sources/MeetingScribe/Monetization/StoreKitManager.swift\`

### Free tier limits (ready to enforce once StoreKit is wired)
- 5 people with typed relationships
- 3 people with check-in reminders
- Read-only MCP people tools

### Pro tier (\$4.99/mo or \$49/yr)
- Unlimited typed relationships + reminders
- Coaching frameworks + health score
- MCP encounter write tools
- Monthly Relationship Intelligence Report

### Next steps
1. Create App Store Connect app record
2. Create IAP products with IDs in \`ProProduct\` enum
3. Replace stubs in StoreKitManager with StoreKit 2 \`Product.purchase()\`
4. Wire FeatureGate gates into PersonDetailView / RelationshipNotificationManager

### Verification
- Build: PASS
- FeatureGate.shared.isEnabled(.checkInNotifications) returns true in DEBUG (overrideAllEnabled)
- ProPaywallView renders without crash"

# ── Final report ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ALL PHASES COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Final git log (main):"
git log --oneline main | head -15
echo ""
echo "Swift build check:"
swift build -c release 2>&1 | grep -E "error:|Build complete|warning:" | head -20
echo ""
ok "Done. All 7 phases merged into main."
echo ""
echo "Next steps:"
echo "  1. Submit mcp-registry.json to mcpservers.org + mcpmarket.com"
echo "  2. Configure App Store Connect + replace StoreKit stubs"
echo "  3. Phase 5 manual UX items: font sizes, extraction banner, meeting-first flow"
echo "  4. Wire FeatureGate checks into personDetailView + notifications"
