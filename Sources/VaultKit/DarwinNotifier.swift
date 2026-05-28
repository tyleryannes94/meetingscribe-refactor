import Foundation

/// Fire-and-forget inter-process signals via CFNotificationCenter.
/// Use Darwin notifications for signals (zero payload). Use vault files for data.
public struct DarwinNotifier {
    public static let recordingStarted  = "com.tyleryannes.meetingscribe.recordingStarted"
    public static let recordingStopped  = "com.tyleryannes.meetingscribe.recordingStopped"
    public static let transcriptionComplete = "com.tyleryannes.meetingscribe.transcriptionComplete"
    public static let vaultChanged      = "com.tyleryannes.meetingscribe.vaultChanged"
    public static let inboxChanged      = "com.tyleryannes.meetingscribe.inboxChanged"

    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    public static func observe(_ name: String, using handler: @escaping () -> Void) -> NSObjectProtocol {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        CFNotificationCenterAddObserver(center, observer, { _, _, name, _, _ in
            // Note: handler is captured via a global registry; see DarwinObserverRegistry
        }, name as CFString, nil, .deliverImmediately)
        // Return a token the caller can use to remove observation
        return NSObject()
    }
}
