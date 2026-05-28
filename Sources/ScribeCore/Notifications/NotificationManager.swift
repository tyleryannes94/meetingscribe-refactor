import Foundation
@preconcurrency import UserNotifications
import AppKit
import OSLog

/// Schedules and handles macOS notifications:
///   • Reminder + "Join & Record" action at the start of each upcoming meeting.
///   • Impromptu prompt: "Record this Zoom call?" when Zoom is detected.
/// Routes action taps back via callbacks so the rest of the app can react.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Notifications")

    static let categoryMeeting = "MEETING_START"
    static let categoryImpromptu = "IMPROMPTU_DETECTED"
    static let actionJoinAndRecord = "JOIN_AND_RECORD"
    static let actionRecordOnly = "RECORD_ONLY"
    static let actionRecordImpromptu = "RECORD_IMPROMPTU"
    static let actionDismiss = "DISMISS"

    /// Called when the user taps "Join & Record" on a meeting notification.
    /// Payload dict contains the keys from the encoded meeting (e.g. "id", "title", "conferenceURL").
    var onJoinAndRecord: (([String: String]) -> Void)?
    /// Called when the user taps "Record" (without joining) on a meeting notification.
    var onRecordMeeting: (([String: String]) -> Void)?
    /// Called when the user taps "Record impromptu" on a detection notification.
    var onRecordImpromptu: ((_ source: String) -> Void)?

    private var scheduledMeetingIDs: Set<String> = []
    private let meetingPayloadKey = "meetingJSON"
    private let sourcePayloadKey = "source"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Auth failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func registerCategories() {
        let join = UNNotificationAction(identifier: Self.actionJoinAndRecord,
                                        title: "Join & Record",
                                        options: [.foreground])
        let recordOnly = UNNotificationAction(identifier: Self.actionRecordOnly,
                                              title: "Record (don't join)",
                                              options: [.foreground])
        let dismiss = UNNotificationAction(identifier: Self.actionDismiss,
                                           title: "Dismiss",
                                           options: [])
        let meetingCat = UNNotificationCategory(identifier: Self.categoryMeeting,
                                                actions: [join, recordOnly, dismiss],
                                                intentIdentifiers: [],
                                                options: [])

        let recordImp = UNNotificationAction(identifier: Self.actionRecordImpromptu,
                                             title: "Record Impromptu",
                                             options: [.foreground])
        let impCat = UNNotificationCategory(identifier: Self.categoryImpromptu,
                                            actions: [recordImp, dismiss],
                                            intentIdentifiers: [],
                                            options: [])

        UNUserNotificationCenter.current().setNotificationCategories([meetingCat, impCat])
    }

    // MARK: - Scheduling

    /// Schedules a one-shot notification ~10s before each upcoming meeting's
    /// start time. Clears prior scheduled notifications for meetings no longer
    /// in the list. Safe to call repeatedly.
    ///
    /// Each stub dict must contain:
    ///   - "id": String (unique meeting identifier)
    ///   - "title": String (display title)
    ///   - "startDate": String (ISO 8601)
    ///   - "conferenceURL": String? (optional, presence enables "Join & Record")
    func syncScheduled(for meetingStubs: [[String: Any]]) async {
        guard AppSettings.notifyAtMeetingStart else {
            await UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            scheduledMeetingIDs.removeAll()
            return
        }
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let existingIDs = Set(existing.map { $0.identifier })

        // Cancel anything we previously scheduled that's no longer relevant.
        let liveIDs = Set(meetingStubs.compactMap { $0["id"] as? String }.map { "meeting-\($0)" })
        let toCancel = existingIDs.subtracting(liveIDs).filter { $0.hasPrefix("meeting-") }
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toCancel))
        }

        let isoParser = ISO8601DateFormatter()

        for stub in meetingStubs {
            guard let meetingID = stub["id"] as? String,
                  let startDateStr = stub["startDate"] as? String,
                  let startDate = isoParser.date(from: startDateStr) else { continue }
            let displayTitle = stub["title"] as? String ?? "Meeting"
            let conferenceURL = stub["conferenceURL"] as? String ?? ""

            let id = "meeting-\(meetingID)"
            if existingIDs.contains(id) { continue }
            let triggerDate = startDate.addingTimeInterval(-10)
            if triggerDate.timeIntervalSinceNow < 0 { continue }

            let content = UNMutableNotificationContent()
            content.title = displayTitle
            content.subtitle = "Starting now"
            content.body = conferenceURL.isEmpty
                ? "Tap Record to start capturing this meeting."
                : "Tap Join & Record to join and start capturing."
            content.categoryIdentifier = Self.categoryMeeting
            // Store a simple payload dict so handleAction can reconstruct key fields.
            var payload: [String: String] = ["id": meetingID, "title": displayTitle, "startDate": startDateStr]
            if !conferenceURL.isEmpty { payload["conferenceURL"] = conferenceURL }
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: data, encoding: .utf8) {
                content.userInfo[meetingPayloadKey] = str
            }
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, triggerDate.timeIntervalSinceNow),
                repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(req)
                scheduledMeetingIDs.insert(meetingID)
            } catch {
                log.error("schedule failed for \(displayTitle, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Posts an immediate notification when an impromptu meeting is detected.
    func notifyImpromptuDetected(source: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(source) call detected"
        content.body = "You're in a call that isn't in your calendar. Record it?"
        content.categoryIdentifier = Self.categoryImpromptu
        content.userInfo[sourcePayloadKey] = source
        content.sound = .default
        let req = UNNotificationRequest(identifier: "impromptu-\(UUID().uuidString)",
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        Task { @MainActor in
            self.handleAction(actionID, userInfo: info)
            completionHandler()
        }
    }

    @MainActor
    private func handleAction(_ actionID: String, userInfo: [AnyHashable: Any]) {
        // Decode the lightweight payload dict (id, title, startDate, conferenceURL?).
        let payload: [String: String]? = {
            guard let str = userInfo[meetingPayloadKey] as? String,
                  let data = str.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return nil }
            return dict
        }()

        switch actionID {
        case Self.actionJoinAndRecord:
            if let p = payload {
                if let urlStr = p["conferenceURL"], let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
                onJoinAndRecord?(p)
            }
        case Self.actionRecordOnly:
            if let p = payload { onRecordMeeting?(p) }
        case Self.actionRecordImpromptu:
            let source = (userInfo[sourcePayloadKey] as? String) ?? "Impromptu"
            onRecordImpromptu?(source)
        case UNNotificationDefaultActionIdentifier:
            // Tap on the notification body — open the app window.
            NSApp.activate(ignoringOtherApps: true)
            if let p = payload { onRecordMeeting?(p) }
        default:
            break
        }
    }
}
