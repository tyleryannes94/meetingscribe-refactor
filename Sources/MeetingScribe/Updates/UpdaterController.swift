import SwiftUI
import AppKit
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
    /// When Sparkle last polled the appcast (background or manual). Surfaced in
    /// Settings so the user can see the updater is actually running.
    @Published var lastChecked: Date?
    /// Mirrors Sparkle's `automaticallyChecksForUpdates`. Two-way bound by the
    /// Settings toggle; writes through to the live updater.
    @Published var automaticChecks: Bool = false {
        didSet {
            guard Self.isConfigured,
                  controller.updater.automaticallyChecksForUpdates != automaticChecks else { return }
            controller.updater.automaticallyChecksForUpdates = automaticChecks
        }
    }

    /// Whether the in-app updater is live (a real EdDSA key is baked in). When
    /// false the Settings UI explains updates aren't wired for this build.
    var isUpdaterConfigured: Bool { Self.isConfigured }

    /// The appcast URL Sparkle polls — shown in Settings for transparency.
    var feedURLString: String {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "—"
    }

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
            controller.updater.publisher(for: \.lastUpdateCheckDate)
                .receive(on: RunLoop.main)
                .assign(to: &$lastChecked)
            // Seed the toggle from the live updater. Assigning in init does not
            // fire the didSet, so this won't write back redundantly.
            automaticChecks = controller.updater.automaticallyChecksForUpdates
        }
    }

    func checkForUpdates() {
        guard Self.isConfigured else { return }
        // Pre-flight the appcast feed for the user-initiated check. When no
        // release has been published yet (or the feed is otherwise
        // unreachable) the URL 404s and Sparkle pops a raw, alarming
        // network-error dialog — which is the "error" users hit clicking this.
        // Detect that first and show a clear, friendly explanation instead.
        // Background/scheduled checks are untouched — only this path pre-flights.
        let feed = feedURLString
        Task { @MainActor in
            if await Self.feedIsReachable(feed) {
                controller.checkForUpdates(nil)
            } else {
                Self.presentNoFeedAlert(releasesPage: Self.releasesPage(fromFeed: feed))
            }
        }
    }

    /// Derives the human-facing "latest release" page from the appcast feed URL
    /// (…/releases/latest/download/appcast.xml → …/releases/latest) so the
    /// fallback alert can send the user straight to a manual download.
    nonisolated static func releasesPage(fromFeed feed: String) -> URL? {
        if let r = feed.range(of: "/releases/") {
            return URL(string: String(feed[..<r.upperBound]) + "latest")
        }
        return URL(string: feed)
    }

    /// True when the appcast feed responds with a success status. Used to avoid
    /// firing Sparkle's check (and its raw error UI) against a 404 feed.
    nonisolated static func feedIsReachable(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    @MainActor
    static func presentNoFeedAlert(releasesPage: URL?) {
        let alert = NSAlert()
        alert.messageText = "Couldn't reach the update feed"
        alert.informativeText = """
        MeetingScribe couldn't reach its update feed, so it can't check for a \
        new version automatically right now. This happens when the latest \
        GitHub Release doesn't include the signed appcast yet, or the releases \
        aren't publicly reachable.

        You can still grab the newest build manually from GitHub Releases.
        """
        alert.alertStyle = .informational
        if releasesPage != nil {
            alert.addButton(withTitle: "View Latest Release")
        }
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        if releasesPage != nil, response == .alertFirstButtonReturn, let url = releasesPage {
            NSWorkspace.shared.open(url)
        }
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
    @Published var lastChecked: Date?
    @Published var automaticChecks: Bool = false
    var isUpdaterConfigured: Bool { false }
    var feedURLString: String {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "—"
    }
    static var isConfigured: Bool { false }
    func checkForUpdates() {}
}

@MainActor
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterController
    var body: some View { EmptyView() }
}
#endif
