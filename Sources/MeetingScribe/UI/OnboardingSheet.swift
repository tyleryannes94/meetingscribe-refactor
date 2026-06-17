import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics
@preconcurrency import EventKit
@preconcurrency import UserNotifications

/// One-time first-launch onboarding that pre-explains every macOS permission
/// the app needs BEFORE the system dialog appears. Users who tap "Don't
/// Allow" once never see the system dialog again, so context up front
/// materially improves grant rate (audit 8.3).
///
/// Lifecycle: shown once when `hasCompletedOnboarding` is false. The first
/// screen is the vault location picker; subsequent screens cover each macOS
/// permission. After all screens are seen, the sheet dismisses and the flag flips.
@available(macOS 14.0, *)
struct OnboardingSheet: View {
    @Binding var isPresented: Bool
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    /// step == 0 is the vault-location screen; steps 1…N are permissions.
    @State private var step: Int = 0
    /// Per-step state — driven by the system check + the user's actions.
    @State private var permissions: [PermissionState] = PermissionKind.allCases.map { .init(kind: $0) }
    /// Polls CGPreflightScreenCaptureAccess after the user is sent to Settings,
    /// so the Screen Recording grant is detected without a manual re-check. (D3-6)
    @State private var screenPollTask: Task<Void, Never>?

    /// Current vault path — mirrors AppSettings.shared.storageDir but held in
    /// local state so the picker can show a live preview before confirm.
    @State private var vaultURL: URL = AppSettings.shared.storageDir

    private var isVaultStep: Bool { step == 0 }
    private var permissionIndex: Int { step - 1 }
    private var currentPermission: PermissionState { permissions[permissionIndex] }

    // Total dots = vault step + permission steps
    private var totalSteps: Int { 1 + permissions.count }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader   // C3-9: brand the first five minutes
            if isVaultStep {
                vaultStepBody
            } else {
                permissionStepBody
            }
        }
        .frame(minWidth: 480, maxWidth: 480, minHeight: 520)
        .task { await refreshAllStatuses() }
    }

    /// The app mark + wordmark (C3-9), matching the nav rail — so onboarding
    /// reads as MeetingScribe, not a system-gray setup wizard.
    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .scaledFont(15, weight: .bold)
                .foregroundStyle(NDS.avatarText)
                .frame(width: 30, height: 30)
                .background(NDS.brandMarkGradient,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: NDS.accent.opacity(0.30), radius: 7, y: 4)
            Text("MeetingScribe")
                .scaledFont(17, weight: .bold, relativeTo: .title3, kind: .display)
                .tracking(-0.3)
            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 6)
    }

    // MARK: - Vault location step

    private var vaultStepBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "externaldrive.fill.badge.icloud")
                    .scaledFont(38, weight: .regular)
                    .foregroundStyle(.tint)
                Text("Where should we keep your library?")
                    .font(.title2.weight(.semibold))
                Text("MeetingScribe keeps all recordings, transcripts, and notes in a single folder on your Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .padding(.top, 32).padding(.bottom, 24)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("Current location:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                    Text(vaultURL.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path,
                        with: "~"))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 10) {
                    Button("Use iCloud Drive (Recommended)") {
                        vaultURL = AppSettings.defaultStorageURL
                        AppSettings.shared.storageDir = vaultURL
                    }
                    .buttonStyle(.bordered)

                    Button("Change Location…") {
                        chooseVaultLocation()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Spacer()
                Button("Continue") {
                    AppSettings.shared.storageDir = vaultURL
                    advance()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.bar)

            stepDots
        }
    }

    private func chooseVaultLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for your MeetingScribe library"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            vaultURL = url
        }
    }

    // MARK: - Permission step

    private var permissionStepBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: currentPermission.kind.systemImage)
                    .scaledFont(38, weight: .regular)
                    .foregroundStyle(.tint)
                Text(currentPermission.kind.title)
                    .font(.title2.weight(.semibold))
                Text(currentPermission.kind.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .padding(.top, 32).padding(.bottom, 24)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(currentPermission.kind.bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .scaledFont(12)
                        Text(bullet).font(.body)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Skip", role: .cancel) { advance() }
                Spacer()
                if currentPermission.kind == .screenRecording && currentPermission.status == .granted {
                    // Grant detected — it only takes effect after a relaunch, so
                    // offer a one-tap Reopen instead of the old "quit and
                    // relaunch" cliff. (D3-6)
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                    Button("Reopen MeetingScribe") { relaunchApp() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    if currentPermission.status == .denied {
                        Button("Open System Settings") { openSystemSettings(for: currentPermission.kind) }
                    }
                    Button(currentPermission.status.actionLabel) {
                        Task { await requestPermission(currentPermission.kind) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.bar)

            stepDots
        }
    }

    // MARK: - Shared step-dots indicator

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == step ? NDS.brand : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Navigation

    private func advance() {
        screenPollTask?.cancel()
        screenPollTask = nil
        if step + 1 < totalSteps {
            step += 1
        } else {
            hasCompletedOnboarding = true
            isPresented = false
        }
    }

    // MARK: - Permission interactions

    private func requestPermission(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await mark(kind: .microphone, granted: granted)
            advance()
        case .screenRecording:
            // Prompt + register the app in the Screen Recording list. If it's
            // already granted this returns true; otherwise we open the pane and
            // poll for the grant so we can offer a one-tap Reopen. We DON'T
            // auto-advance — the user stays here until they Reopen or Skip. (D3-6)
            if CGRequestScreenCaptureAccess() {
                await mark(kind: .screenRecording, granted: true)
            } else {
                openSystemSettings(for: .screenRecording)
                await mark(kind: .screenRecording, granted: false, manual: true)
                startScreenRecordingPolling()
            }
        case .calendar:
            let granted = await (try? EKEventStore().requestFullAccessToEvents()) ?? false
            await mark(kind: .calendar, granted: granted)
            advance()
        case .notifications:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            await mark(kind: .notifications, granted: granted)
            advance()
        case .accessibility:
            // No programmatic API; AXIsProcessTrusted reads, doesn't request.
            openSystemSettings(for: .accessibility)
            await mark(kind: .accessibility, granted: AXIsProcessTrusted(), manual: true)
            advance()
        }
    }

    /// Polls the real Screen Recording grant for ~90 s after the user is sent to
    /// Settings; flips the step to .granted the moment macOS reports access, so
    /// the "Reopen MeetingScribe" button appears without a manual re-check. (D3-6)
    private func startScreenRecordingPolling() {
        screenPollTask?.cancel()
        screenPollTask = Task {
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                if CGPreflightScreenCaptureAccess() {
                    await mark(kind: .screenRecording, granted: true)
                    return
                }
            }
        }
    }

    /// Relaunch the app so a freshly-granted Screen Recording permission takes
    /// effect — launches a new instance, then terminates this one. (D3-6)
    private func relaunchApp() {
        screenPollTask?.cancel()
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private func mark(kind: PermissionKind, granted: Bool, manual: Bool = false) async {
        if let i = permissions.firstIndex(where: { $0.kind == kind }) {
            permissions[i].status = granted ? .granted : (manual ? .pendingManual : .denied)
        }
    }

    private func refreshAllStatuses() async {
        for i in permissions.indices {
            permissions[i].status = await Self.currentStatus(for: permissions[i].kind)
        }
    }

    private static func currentStatus(for kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            default: return .needed
            }
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .denied, .restricted: return .denied
            default: return .needed
            }
        case .notifications:
            let s = await UNUserNotificationCenter.current().notificationSettings()
            switch s.authorizationStatus {
            case .authorized, .provisional: return .granted
            case .denied: return .denied
            default: return .needed
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .needed
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .needed
        }
    }

    private func openSystemSettings(for kind: PermissionKind) {
        let url: URL? = switch kind {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .calendar:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
        if let url { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Types

@available(macOS 14.0, *)
enum PermissionKind: String, CaseIterable {
    case microphone, screenRecording, calendar, notifications, accessibility

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .screenRecording: return "Screen Recording"
        case .calendar: return "Calendar"
        case .notifications: return "Notifications"
        case .accessibility: return "Accessibility (optional)"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone: return "Captures your side of the conversation."
        case .screenRecording: return "Captures the OTHER side of the call using macOS screen-audio access. Grant it in System Settings — this screen detects it and offers a one-tap Reopen."
        case .calendar: return "Labels recordings with the meeting title and attendees from your calendar."
        case .notifications: return "Notifies you 10 seconds before a calendar meeting starts and offers to join + record."
        case .accessibility: return "Only needed for the F5 global dictation hotkey — lets the app paste the transcript at your cursor."
        }
    }

    var bullets: [String] {
        switch self {
        case .microphone: return ["Your voice during recordings", "Voice notes from the Notes tab", "F5 quick dictation"]
        case .screenRecording: return ["Captures meeting audio without a virtual audio device", "Used only for audio — no video, no screenshots", "After granting, tap Reopen here — no manual relaunch"]
        case .calendar: return ["Reads any calendar already in macOS Calendar (Google, iCloud, Outlook)", "Read-only — never writes to your calendar", "Used for titles, attendees, and auto-record"]
        case .notifications: return ["\"Meeting starting in 10s — Join & Record\" alerts", "Impromptu Zoom / Meet detection", "Pipeline-finished confirmations"]
        case .accessibility: return ["Lets dictation paste at the cursor in any app", "Skip if you don't use F5 dictation — everything else works"]
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: return "mic.fill"
        case .screenRecording: return "rectangle.on.rectangle.angled"
        case .calendar: return "calendar"
        case .notifications: return "bell.badge.fill"
        case .accessibility: return "accessibility.fill"
        }
    }
}

enum PermissionStatus: Equatable {
    case needed, granted, denied, pendingManual

    var actionLabel: String {
        switch self {
        case .needed: return "Allow"
        case .granted: return "Continue"
        case .denied: return "Try Again"
        case .pendingManual: return "Continue"
        }
    }
}

struct PermissionState: Identifiable {
    let kind: PermissionKind
    var status: PermissionStatus = .needed
    var id: PermissionKind { kind }
}
