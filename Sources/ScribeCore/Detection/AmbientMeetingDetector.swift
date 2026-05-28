import Foundation
import CoreAudio
import OSLog

/// Detects "you're probably in a meeting" by watching whether the default
/// **input device** (microphone) is actively in use by *some* process — the
/// signal a call app like Zoom/Meet/Teams produces when it opens the mic.
///
/// NOTE: the plan called for `AVAudioSession`, but that framework is iOS-only —
/// it does not exist on macOS. The macOS-correct equivalent is CoreAudio's
/// `kAudioDevicePropertyDeviceIsRunningSomewhere`, which reports whether the
/// device is running for any process on the system. We poll it on a timer and,
/// after `secondsThreshold` of continuous mic use, post a notification once.
///
/// This complements `AppDetector` (which watches for known call *apps*): this
/// path catches mic-using apps we don't have a window/URL signature for.
@MainActor
final class AmbientMeetingDetector {
    static let shared = AmbientMeetingDetector()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "AmbientDetector")

    private enum Keys {
        static let enabled = "ambientDetectionEnabled"
        static let threshold = "ambientDetectionThreshold"
    }

    private var timer: Timer?
    private var continuousSeconds = 0
    private var hasFiredForCurrentSession = false

    /// Seconds of continuous mic use before we consider it a meeting. Driven by
    /// the sensitivity slider (lower = more sensitive). Default 20s.
    var secondsThreshold: Int {
        let v = UserDefaults.standard.integer(forKey: Keys.threshold)
        return v > 0 ? v : 20
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    private init() {}

    /// Start monitoring only if the user enabled it. Safe no-op otherwise — the
    /// feature ships off by default.
    func startIfEnabled() {
        guard Self.isEnabled else { return }
        start()
    }

    func start() {
        guard timer == nil else { return }
        continuousSeconds = 0
        hasFiredForCurrentSession = false
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        log.info("Ambient meeting detection started (threshold \(self.secondsThreshold)s).")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        continuousSeconds = 0
        hasFiredForCurrentSession = false
    }

    // MARK: - Polling

    private func poll() {
        guard Self.micIsInUse() else {
            // Mic released → reset, ready to detect the next session.
            continuousSeconds = 0
            hasFiredForCurrentSession = false
            return
        }
        continuousSeconds += 1
        if continuousSeconds >= secondsThreshold, !hasFiredForCurrentSession {
            hasFiredForCurrentSession = true
            log.info("Sustained mic use (\(self.continuousSeconds)s) — posting ambient-meeting notification.")
            NotificationCenter.default.post(name: .meetingScribeAmbientMeetingDetected, object: nil)
        }
    }

    // MARK: - CoreAudio

    /// Whether the default input device is currently running for any process.
    nonisolated static func micIsInUse() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private nonisolated static func defaultInputDevice() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }
}

extension Notification.Name {
    /// Posted when sustained microphone use suggests an untracked meeting
    /// started. Observers can offer to start recording.
    static let meetingScribeAmbientMeetingDetected =
        Notification.Name("meetingScribeAmbientMeetingDetected")
}
