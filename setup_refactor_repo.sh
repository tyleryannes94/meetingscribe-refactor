#!/bin/bash
# MeetingScribe Refactor — Separate Repo Setup Script
# Run this from ~/MeetingScribe: bash setup_refactor_repo.sh
#
# What it does:
#   1. Clears the stuck git lock
#   2. Copies the refactored code to ~/MeetingScribeRefactor
#   3. Sets up ~/MeetingScribeRefactor as a fresh git repo
#   4. Restores ~/MeetingScribe to your original clean state
#   5. Builds the refactored app
#
# Before running: create a new empty GitHub repo at
#   https://github.com/new
#   Name suggestion: meetingscribe-refactor
#   Set to Private, no README/gitignore
# Then run this script.

set -e
ORIG="$HOME/MeetingScribe"
REFACTOR="$HOME/MeetingScribeRefactor"

echo ""
echo "==================================================="
echo "  MeetingScribe Refactor — Separate Repo Setup"
echo "==================================================="
echo ""

# ── Step 1: Clear git lock ────────────────────────────
echo "▶ Step 1: Clearing git lock in ~/MeetingScribe..."
rm -f "$ORIG/.git/HEAD.lock" "$ORIG/.git/index.lock" 2>/dev/null || true
echo "  ✓ Lock cleared"

# ── Step 2: Copy refactored working tree ─────────────
echo ""
echo "▶ Step 2: Copying refactored code to ~/MeetingScribeRefactor..."
if [ -d "$REFACTOR" ]; then
    echo "  ~/MeetingScribeRefactor already exists — removing old copy..."
    rm -rf "$REFACTOR"
fi
# Copy everything except the .git directory
rsync -a --exclude='.git' "$ORIG/" "$REFACTOR/"
echo "  ✓ Copied to $REFACTOR"

# ── Step 3: Set up new git repo ───────────────────────
echo ""
echo "▶ Step 3: Initializing fresh git repo in ~/MeetingScribeRefactor..."
cd "$REFACTOR"
git init -b main
git add -A
git commit -m "feat: MeetingScribe Refactor — Phase 0+1+2 architectural rebuild

Phase 0 — 6 bugs fixed:
- DispatchSemaphore crash eliminated (WhisperRunner + QuickTranscribe)
- @Published render storm stopped (tagStore + liveTranscriber → let)
- Main-thread timer storm fixed (push-based AudioLevelMeter via TimelineView)
- refreshPastMeetings debounced (300ms PassthroughSubject)
- Cold-cache disk scan moved off @MainActor (Task.detached)
- TOCTOU recording race fixed (.starting/.stopping transient states)

Phase 1 — Vault hardening:
- VaultKit library (merges SecondBrainCore + MeetingScribeShared)
- NSFileCoordinator on all MeetingStore writes
- FTS5 schema v2 (unified vault_content + all entity types + recency ranking)
- SQLite moved to Application Support (not iCloud Drive)
- iCloud Drive as default vault location
- Date-partitioned directory layout + one-time migration wizard
- iCloudInboxWatcher (NSMetadataQuery, iPhone Shortcuts inbox)
- _recent.json written on every meeting save
- ObsidianExporter inverted (auto-writes .md per meeting)
- Onboarding vault location step added

Phase 2 — ScribeCore binary scaffolded:
- ScribeCore executable target (LSUIElement background daemon)
- VaultCommandWatcher (file-based IPC via vault/_commands/)
- ScribeCoreXPC protocol (7 methods, ready for XPC wiring)
- Audio + Transcription + Detection + AI + Calendar + Notifications in ScribeCore
- ScribeCoreXPCClient in Scribe UI
- SMAppService Login Item registration
- DarwinNotifier for fire-and-forget IPC signals"
echo "  ✓ Initial commit created"

# ── Step 4: Restore ~/MeetingScribe to original ───────
echo ""
echo "▶ Step 4: Restoring ~/MeetingScribe to original committed state..."
cd "$ORIG"
git checkout .
git clean -fd --exclude='MASTER_PLAN.md' --exclude='MASTER_PLAN_V2.md' --exclude='HANDOFF.md'
echo "  ✓ ~/MeetingScribe restored to commit feb5409"

# ── Step 5: Build the refactored app ─────────────────
echo ""
echo "▶ Step 5: Building ~/MeetingScribeRefactor..."
cd "$REFACTOR"

# Delete dead code files first
if [ -f "delete_dead_code.sh" ]; then
    echo "  Deleting 20 dead-code files..."
    bash delete_dead_code.sh
    git add -A
    git commit -m "chore: delete 20 dead-code files (backup, compliance, team, iPhone HTTP)"
fi

echo "  Running swift build -c release..."
swift build -c release 2>&1 | tail -20

echo ""
echo "==================================================="
echo "  Build complete."
echo ""
echo "  Next steps:"
echo ""
echo "  1. Push to GitHub (create the repo first at https://github.com/new):"
echo "     cd ~/MeetingScribeRefactor"
echo "     git remote add origin https://github.com/tyleryannes94/meetingscribe-refactor.git"
echo "     git push -u origin main"
echo ""
echo "  2. If build succeeded, install the app:"
echo "     make app   (or your usual sign+install script)"
echo "     OR copy .build/release/MeetingScribe to /Applications/"
echo ""
echo "  Your ORIGINAL ~/MeetingScribe is untouched and working."
echo "==================================================="
