import SwiftUI
import AppKit

/// "Getting things ready" — the in-app first-run setup card (D3-1). Shows the
/// status of the two things recording needs (the whisper model + Ollama) and
/// offers one-tap remediation, so a non-technical user never meets a raw shell
/// command. Presented automatically on launch when the stack isn't ready, and
/// reachable again from Settings.
@available(macOS 14.0, *)
struct SetupCheckSheet: View {
    @ObservedObject var setup: SetupReadiness
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Getting things ready")
                    .scaledFont(20, weight: .bold)
                Text("MeetingScribe runs entirely on your Mac. Two local pieces power recording and summaries — let's make sure they're set up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            modelRow
            Divider()
            ollamaRow

            if let err = setup.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Re-check") { Task { await setup.refresh() } }
                    .disabled(setup.busy != nil)
                Spacer()
                if setup.isReady {
                    Button("Done") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(MSPrimaryButtonStyle())
                } else {
                    Button("Skip for now") { isPresented = false }
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .task { await setup.refresh() }
    }

    // MARK: - Rows

    private var modelRow: some View {
        componentRow(
            title: "Transcription model",
            subtitle: setup.whisperReady
                ? "Installed and ready."
                : "A ~140 MB on-device speech model. Downloads once.",
            ready: setup.whisperReady,
            busy: setup.busy == .downloadingModel,
            busyLabel: "Downloading…"
        ) {
            if !setup.whisperReady {
                Button("Download") { Task { await setup.downloadModel() } }
                    .disabled(setup.busy != nil)
            }
        }
    }

    @ViewBuilder
    private var ollamaRow: some View {
        componentRow(
            title: "Summary engine (on-device AI)",
            subtitle: ollamaSubtitle,
            ready: setup.ollamaRunning,
            busy: setup.busy == .startingOllama,
            busyLabel: "Starting…"
        ) {
            if setup.ollamaRunning {
                EmptyView()
            } else if setup.ollamaInstalled {
                Button("Start") { Task { await setup.startOllama() } }
                    .disabled(setup.busy != nil)
            } else {
                Button("Get Ollama") {
                    if let u = URL(string: "https://ollama.com/download") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }

    private var ollamaSubtitle: String {
        if setup.ollamaRunning { return "Running and reachable." }
        if setup.ollamaInstalled { return "Installed but not running yet." }
        return "Powers summaries on-device. Install it once, then come back and re-check."
    }

    // MARK: - Row chrome

    @ViewBuilder
    private func componentRow<Trailing: View>(
        title: String,
        subtitle: String,
        ready: Bool,
        busy: Bool,
        busyLabel: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .scaledFont(18)
                .foregroundStyle(ready ? Color.green : NDS.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).scaledFont(14, weight: .semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(busyLabel).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                trailing()
            }
        }
    }
}
