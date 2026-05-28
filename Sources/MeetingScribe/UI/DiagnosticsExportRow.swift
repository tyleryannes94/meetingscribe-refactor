import SwiftUI
import AppKit

/// Settings → Diagnostics row for the "Export diagnostics" action.
/// Builds the bundle (`DiagnosticsExporter.exportBundle`) on a background
/// task so the Settings window doesn't hitch, then reveals the resulting
/// zip in Finder. No automatic upload — user always presses the button
/// (audit 8.2).
@available(macOS 14.0, *)
struct DiagnosticsExportRow: View {
    @State private var isExporting: Bool = false
    @State private var lastBundle: URL?
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    Task { await runExport() }
                } label: {
                    if isExporting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Bundling…")
                        }
                    } else {
                        Label("Export diagnostics…", systemImage: "shippingbox")
                    }
                }
                .disabled(isExporting)
                if let url = lastBundle {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }
            }
            Text("Bundles app.log, transcription log, Ollama log, recent errors, system info, and an allowlist-redacted settings snapshot into one zip you can drop into a GitHub issue. NO keychain items or audio files are included.")
                .font(.caption2).foregroundStyle(.secondary)
            if let err = lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func runExport() async {
        isExporting = true
        lastError = nil
        defer { isExporting = false }
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try await MainActor.run { try DiagnosticsExporter.exportBundle() }
            }.value
            lastBundle = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
        }
    }
}
