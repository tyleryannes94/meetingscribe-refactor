import SwiftUI
import AVFoundation
import CoreGraphics
@preconcurrency import EventKit
@preconcurrency import UserNotifications

/// One-click self-diagnostics (P5-6): whisper model, Ollama, disk, and the
/// macOS permissions the app needs. For a local app the user is their own ops
/// team, so a single "is everything working?" view saves a lot of guessing.
@available(macOS 14.0, *)
struct HealthCheckSheet: View {
    @Binding var isPresented: Bool
    @State private var rows: [Row] = []
    @State private var running = false

    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let ok: Bool
        let detail: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Health check").font(.system(size: 20, weight: .bold))
            if running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { r in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(r.ok ? .green : .orange)
                        .font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(.system(size: 13, weight: .semibold))
                        Text(r.detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
            HStack {
                Button("Re-run") { Task { await run() } }.disabled(running)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 470)
        .task { await run() }
    }

    private func run() async {
        running = true
        defer { running = false }
        var out: [Row] = []

        let modelReady = WhisperRunner.isModelReady
        out.append(Row(name: "Transcription model",
                       ok: modelReady,
                       detail: modelReady ? "Installed." : "Not downloaded — open the Setup Check to install it."))

        let ollamaUp = await OllamaService().isReachable(allowCache: false)
        out.append(Row(name: "Local AI engine (Ollama)",
                       ok: ollamaUp,
                       detail: ollamaUp ? "Running and reachable."
                             : (OllamaService.binaryPath == nil ? "Not installed."
                                                                 : "Installed but not running.")))

        let freeGB = freeDiskGB()
        out.append(Row(name: "Disk space",
                       ok: freeGB >= 5,
                       detail: String(format: "%.1f GB available%@", freeGB,
                                      freeGB < 5 ? " — low; transcription/summaries need headroom." : ".")))

        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        out.append(Row(name: "Microphone",
                       ok: mic,
                       detail: mic ? "Granted." : "Not granted — your voice won't be captured."))

        let screen = CGPreflightScreenCaptureAccess()
        out.append(Row(name: "Screen Recording",
                       ok: screen,
                       detail: screen ? "Granted." : "Not granted — the other side of calls won't be captured."))

        let cal = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        out.append(Row(name: "Calendar",
                       ok: cal,
                       detail: cal ? "Granted." : "Not granted — meeting titles/attendees won't auto-fill."))

        let notif = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let notifOk = notif == .authorized || notif == .provisional
        out.append(Row(name: "Notifications",
                       ok: notifOk,
                       detail: notifOk ? "Granted." : "Not granted — meeting-start and 'ready' alerts are off."))

        rows = out
    }

    private func freeDiskGB() -> Double {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let bytes = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return Double(bytes) / 1_000_000_000
    }
}
