#!/bin/bash
#
# uninstall-sync.sh — remove the MeetingScribe one-way sync from the WORK MacBook.
#
# Stops + removes the launchd job and the installed script. By default it LEAVES:
#   - the config file (so you can re-install with the same settings),
#   - the SSH key,
#   - the data already backed up on the hub.
# Pass --purge to also remove the config and the local SSH key.
#
set -u -o pipefail

LABEL="com.tyleryannes.meetingscribe.sync"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALLED_SCRIPT="$HOME/.local/bin/meetingscribe-sync.sh"
CONFIG_DIR="$HOME/.config/meetingscribe-sync"
SSH_KEY="$HOME/.ssh/meetingscribe_sync"

GREEN=$'\033[32m'; RESET=$'\033[0m'
ok() { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }

# Stop + remove the launchd job.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true
[ -f "$PLIST_DEST" ] && rm -f "$PLIST_DEST" && ok "Removed launchd job"
[ -f "$INSTALLED_SCRIPT" ] && rm -f "$INSTALLED_SCRIPT" && ok "Removed $INSTALLED_SCRIPT"

if [ "${1:-}" = "--purge" ]; then
  [ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR" && ok "Removed config $CONFIG_DIR"
  [ -f "$SSH_KEY" ] && rm -f "$SSH_KEY" "${SSH_KEY}.pub" && ok "Removed SSH key $SSH_KEY"
  printf 'Note: the key may still be in the hub\047s ~/.ssh/authorized_keys — remove it there if you want.\n'
else
  ok "Left config + SSH key in place (re-install with the same settings via install-sync.sh). Use --purge to remove them too."
fi

printf 'Your backed-up data on the hub (_remote/...) was NOT touched.\n'
ok "Uninstalled."
