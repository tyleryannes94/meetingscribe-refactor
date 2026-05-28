import SwiftUI
import VaultKit

/// Scribe Core — headless background daemon.
/// Owns all audio capture, transcription, AI processing, and the menu bar extra.
/// No Dock icon. Registered as a Login Item via SMAppService.
@available(macOS 14.0, *)
@main
struct ScribeCoreApp: App {
    @NSApplicationDelegateAdaptor(ScribeCoreAppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar extra is the only UI surface
        MenuBarExtra("MeetingScribe", systemImage: "waveform.circle") {
            // MenuBarView will be moved here in Phase 2 completion
            Text("Scribe Core running")
                .padding()
        }
    }
}

@available(macOS 14.0, *)
final class ScribeCoreAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and App Switcher — this is a background daemon
        NSApp.setActivationPolicy(.prohibited)

        // Start services
        Task { @MainActor in
            await ScribeCoreServices.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            await ScribeCoreServices.shared.stop()
        }
    }
}
