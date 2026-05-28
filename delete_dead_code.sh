#!/bin/bash
# Deletes 20 dead-code files from MeetingScribe architectural cleanup
# Run from ~/MeetingScribe: bash delete_dead_code.sh
set -e
BASE="$(cd "$(dirname "$0")" && pwd)"
S="$BASE/Sources/MeetingScribe"

# Backup subsystem (superseded by iCloud Drive)
rm -f "$S/Backup/iCloudBackupManager.swift"
rm -f "$S/Backup/BackupScheduler.swift"
rm -f "$S/Backup/BackupEncryption.swift"
rm -f "$S/Backup/BackupSettingsView.swift"

# CloudKit sync stub
rm -f "$S/Sync/CloudKitSyncEngine.swift"
rm -f "$S/Sync/SyncSettingsView.swift"
rm -f "$S/Sync/SyncStatus.swift"

# iPhone HTTP server (superseded by iCloud inbox)
rm -f "$S/People/iPhone/iPhoneInputService.swift"
rm -f "$S/People/iPhone/iPhoneInputHTML.swift"
rm -f "$S/People/iPhone/iPhoneInputQRView.swift"
rm -f "$S/People/iPhone/iPhoneInputSettingsView.swift"

# Team features
rm -f "$S/Team/TeamWorkspace.swift"
rm -f "$S/Team/TeamSyncService.swift"
rm -f "$S/Team/TeamSettingsView.swift"

# Compliance features
rm -f "$S/Compliance/ComplianceManager.swift"
rm -f "$S/Compliance/ComplianceSettings.swift"
rm -f "$S/Compliance/ConsentRecord.swift"

# Coaching features
rm -f "$S/Coaching/CoachingReportView.swift"
rm -f "$S/Coaching/MeetingCoach.swift"
rm -f "$S/UI/MeetingCoachTab.swift"

echo "✅ Deleted 20 dead-code files."
echo "Run: swift build -c release  to verify compilation."
