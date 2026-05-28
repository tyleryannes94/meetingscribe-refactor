import Foundation
import AppKit
import OSLog

/// Polls running apps to detect when the user joins a Zoom meeting or
/// Google Meet tab. Fires `onImpromptuDetected(source)` exactly once per
/// session (i.e. it stops firing while the call is still going, and only
/// fires again after the user leaves and rejoins).
///
/// Also publishes `currentCallSource` so other components (like the
/// auto-record-on-meeting-start logic) can check whether the user has
/// actually joined a call before triggering recording.
@MainActor
final class AppDetector: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "AppDetector")

    /// Live read of which call (if any) the user is currently in.
    /// `"Zoom"` / `"Meet"` / `nil`. Updated each poll cycle.
    @Published private(set) var currentCallSource: String?

    /// Called when an impromptu meeting is detected. Source = "Zoom" / "Meet" / etc.
    var onImpromptuDetected: ((_ source: String) -> Void)?

    /// Called every poll, with the currently-detected source if any. Useful
    /// for showing a "you're in a Zoom call" indicator in the UI.
    var onStatusUpdate: ((_ source: String?) -> Void)?

    /// External signal from MeetingManager — when a recording is active we
    /// shouldn't prompt the user.
    var isRecording: () -> Bool = { false }

    private var timer: Timer?
    private var lastDetectedSource: String?

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Run once immediately.
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        // Always track presence — even when impromptu notifications are off —
        // because auto-record-on-meeting-start needs this signal too.
        let source = detectActiveCall()
        currentCallSource = source
        onStatusUpdate?(source)

        // Only push the "Record impromptu?" notification when the setting is on.
        guard AppSettings.detectZoomImpromptu else {
            lastDetectedSource = source
            return
        }
        if let source, source != lastDetectedSource, !isRecording() {
            lastDetectedSource = source
            onImpromptuDetected?(source)
        } else if source == nil {
            lastDetectedSource = nil
        }
    }

    /// Returns "Zoom", "Meet", or nil. "Slack huddle" detection is unreliable
    /// because Slack doesn't expose huddle state via any public surface — we
    /// skip it rather than misfire.
    ///
    /// Cheap path first: NSWorkspace.runningApplications is a cached CFArray.
    /// We only invoke the heavier CGWindowListCopyWindowInfo when a target
    /// app is actually running — most polls return immediately.
    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "company.thebrowser.Browser",         // Arc
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "com.brave.Browser"
    ]
    private static let browserOwnerNames: Set<String> = [
        "Google Chrome", "Google Chrome Beta", "Google Chrome Canary",
        "Arc", "Safari", "Microsoft Edge", "Brave Browser"
    ]

    private func detectActiveCall() -> String? {
        let running = NSWorkspace.shared.runningApplications
        let runningBundleIDs = Set(running.compactMap { $0.bundleIdentifier })
        let zoomRunning = runningBundleIDs.contains("us.zoom.xos")
        let browserRunning = !runningBundleIDs.isDisjoint(with: Self.browserBundleIDs)

        // Bail out without making the CGWindowList syscall if neither Zoom nor
        // any browser is alive. This is the common case.
        guard zoomRunning || browserRunning else { return nil }

        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] ?? []

        if zoomRunning {
            let inZoomMeeting = windows.contains { w in
                guard (w[kCGWindowOwnerName as String] as? String) == "zoom.us",
                      let name = w[kCGWindowName as String] as? String else { return false }
                return name.lowercased().contains("meeting")
            }
            if inZoomMeeting { return "Zoom" }
        }

        if browserRunning {
            let inMeet = windows.contains { w in
                guard let owner = w[kCGWindowOwnerName as String] as? String,
                      Self.browserOwnerNames.contains(owner),
                      let name = w[kCGWindowName as String] as? String else { return false }
                let n = name.lowercased()
                return n.contains("meet - ") || n.contains("meet.google.com")
            }
            if inMeet { return "Meet" }
        }

        return nil
    }
}
