import Foundation

/// Fire-and-forget inter-process signals via CFNotificationCenter.
/// Use Darwin notifications for signals (zero payload). Use vault files for data.
public struct DarwinNotifier {
    public static let recordingStarted  = "com.tyleryannes.meetingscribe.recordingStarted"
    public static let recordingStopped  = "com.tyleryannes.meetingscribe.recordingStopped"
    public static let transcriptionComplete = "com.tyleryannes.meetingscribe.transcriptionComplete"
    public static let vaultChanged      = "com.tyleryannes.meetingscribe.vaultChanged"
    public static let inboxChanged      = "com.tyleryannes.meetingscribe.inboxChanged"

    // ScribeCore internal command signals
    public static let startRecording    = "com.tyleryannes.ScribeCore.startRecording"
    public static let stopRecording     = "com.tyleryannes.ScribeCore.stopRecording"
    public static let transcribeNow     = "com.tyleryannes.ScribeCore.transcribeNow"
    /// Posted by ScribeCore once its services are running and it can accept
    /// startRecording commands. Distinct from recordingStopped so the UI
    /// doesn't prematurely finalize an in-flight recording.
    public static let coreReady         = "com.tyleryannes.ScribeCore.coreReady"

    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    /// Global registry: maps notification name → handler closure.
    /// CFNotificationCenter callbacks cannot capture Swift closures directly, so
    /// we store handlers here and look them up by name inside the C callback.
    private static var _handlers: [String: () -> Void] = [:]
    private static let _lock = NSLock()

    /// Registers `handler` to be called whenever `name` is posted on the Darwin
    /// notification center. The returned token is an opaque object; the caller
    /// may discard it if the observation should last for the process lifetime.
    @discardableResult
    public static func observe(_ name: String, using handler: @escaping () -> Void) -> NSObjectProtocol {
        _lock.lock()
        _handlers[name] = handler
        _lock.unlock()

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        // We use the notification name string itself (bridged to CFString) as
        // the observer pointer so the C callback can recover the name without
        // any extra bookkeeping.
        let nameRef = (name as NSString).copy() as! NSString
        let observer = Unmanaged.passRetained(nameRef).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observerPtr, cfName, _, _ in
                // Recover the name string from the observer pointer.
                guard let observerPtr else { return }
                let nameStr: String
                if let cfName {
                    nameStr = cfName.rawValue as String
                } else {
                    let ns = Unmanaged<NSString>.fromOpaque(observerPtr).takeUnretainedValue()
                    nameStr = ns as String
                }
                DarwinNotifier._lock.lock()
                let h = DarwinNotifier._handlers[nameStr]
                DarwinNotifier._lock.unlock()
                h?()
            },
            name as CFString,
            nil,
            .deliverImmediately
        )

        // Wrap the observer pointer in an NSObject so the caller gets back an
        // opaque token (the type contract). The retained NSString above keeps
        // the string alive for the process lifetime, which is fine for daemon-
        // style observations.
        return NSObject()
    }
}
