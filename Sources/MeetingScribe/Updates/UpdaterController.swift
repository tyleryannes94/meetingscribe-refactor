import SwiftUI
#if canImport(Sparkle)
import Sparkle

/// Wraps Sparkle's standard updater so SwiftUI can drive it. The updater
/// auto-starts and schedules background checks per the Info.plist keys
/// (SUEnableAutomaticChecks / SUScheduledCheckInterval); the menu command
/// triggers an immediate, user-initiated check.
///
/// Updates are delivered via the appcast at `SUFeedURL` and verified against
/// the EdDSA public key in `SUPublicEDKey`. See RELEASING.md for the one-time
/// key setup and the GitHub Actions release flow.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    /// Only start Sparkle once a real EdDSA public key is baked in (see
    /// RELEASING.md). Until then the placeholder would make every launch log a
    /// "failed to start updater" error, so we keep it dormant.
    static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !key.isEmpty && !key.hasPrefix("REPLACE_WITH")
    }

    init() {
        let start = Self.isConfigured
        controller = SPUStandardUpdaterController(startingUpdater: start,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        if start {
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .assign(to: &$canCheckForUpdates)
        }
    }

    func checkForUpdates() {
        guard Self.isConfigured else { return }
        controller.checkForUpdates(nil)
    }
}

/// Menu command — appears under the app menu as "Check for Updates…".
@MainActor
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterController
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

#else

/// Fallback when Sparkle isn't linked (keeps the app buildable). No-op updater.
@MainActor
final class UpdaterController: ObservableObject {
    @Published var canCheckForUpdates = false
    func checkForUpdates() {}
}

@MainActor
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterController
    var body: some View { EmptyView() }
}
#endif
