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
    var onJoinAndRecord: ((Meeting) -> Void)?
    /// Called when the user taps "Record" (without joining) on a meeting notification.
    var onRecordMeeting: ((Meeting) -> Void)?
    /// Called when the user taps "Record impromptu" on a detection notification.
    var onRecordImpromptu: ((_ source: String) -> Void)?

    private var scheduledMeetingIDs: Set<String> = []
    private let meetingPayloadKey = "meetingJSON"
    private let sourcePayloadKey = "source"
    private let deepLinkKey = "deepLink"

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
    func syncScheduled(for meetings: [Meeting], briefs: [String: String] = [:]) async {
        guard AppSettings.shared.notifyAtMeetingStart else {
            await UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            scheduledMeetingIDs.removeAll()
            return
        }
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let existingIDs = Set(existing.map { $0.identifier })

        // Cancel anything we previously scheduled that's no longer relevant.
        let liveIDs = Set(meetings.map { "meeting-\($0.id)" })
        let toCancel = existingIDs.subtracting(liveIDs).filter { $0.hasPrefix("meeting-") }
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toCancel))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for m in meetings {
            let id = "meeting-\(m.id)"
            if existingIDs.contains(id) { continue }
            let triggerDate = m.startDate.addingTimeInterval(-10)
            if triggerDate.timeIntervalSinceNow < 0 { continue }

            let content = UNMutableNotificationContent()
            content.title = m.displayTitle
            content.subtitle = "Starting now"
            let action = (m.conferenceURL ?? "").isEmpty
                ? "Tap Record to start capturing this meeting."
                : "Tap Join & Record to join and start capturing."
            // Prepend a synthesized brief so the user is prepped, not just
            // pinged. (P2-2)
            if let brief = briefs[m.id], !brief.isEmpty {
                content.body = "\(brief)\n\(action)"
            } else {
                content.body = action
            }
            content.categoryIdentifier = Self.categoryMeeting
            if let payload = try? encoder.encode(m),
               let str = String(data: payload, encoding: .utf8) {
                content.userInfo[meetingPayloadKey] = str
            }
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, triggerDate.timeIntervalSinceNow),
                repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(req)
                scheduledMeetingIDs.insert(m.id)
            } catch {
                log.error("schedule failed for \(m.displayTitle, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Schedules a one-shot reminder at each incomplete task's due date, and
    /// cancels reminders for tasks that were completed, deleted, or rescheduled
    /// into the past (P2-1). Mirrors `syncScheduled(for:)` and is safe to call
    /// repeatedly. Capped to the soonest 60 due tasks to stay well under the
    /// system's pending-notification limit. Tapping deep-links to the task.
    func syncTaskReminders(for tasks: [ActionItem], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let existingTaskIDs = Set(existing.map(\.identifier)).filter { $0.hasPrefix("task-reminder-") }

        guard AppSettings.shared.notifyTaskDue else {
            if !existingTaskIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(existingTaskIDs))
            }
            return
        }

        let eligible = Self.tasksNeedingDueReminder(tasks, now: now)
        let liveIDs = Set(eligible.map { "task-reminder-\($0.id)" })
        let toCancel = existingTaskIDs.subtracting(liveIDs)
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toCancel))
        }

        for t in eligible {
            guard let due = t.dueDate else { continue }
            let id = "task-reminder-\(t.id)"
            // Re-add so a changed due date updates the fire time.
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let content = UNMutableNotificationContent()
            content.title = "Task due: \(t.title)"
            content.body = t.owner.flatMap { $0.isEmpty ? nil : "Assigned to \($0)" } ?? "This task is now due."
            content.sound = .default
            content.userInfo[deepLinkKey] = "meetingscribe://actionItem/\(t.id)"
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, due.timeIntervalSince(now)), repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(req)
            } catch {
                log.error("task reminder schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pure selection of which tasks get a due-date reminder: incomplete, with a
    /// future due date, soonest first, capped to `limit` (system notification
    /// budget). Testable seam — no notification-center side effects.
    nonisolated static func tasksNeedingDueReminder(_ tasks: [ActionItem], now: Date,
                                                    limit: Int = 60) -> [ActionItem] {
        tasks
            .filter { $0.status != .completed && ($0.dueDate.map { $0 > now } ?? false) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(limit)
            .map { $0 }
    }

    /// Posts an immediate notification when transcription + summary finishes
    /// for a meeting. This is the most valuable notification — it closes the
    /// loop for the user ("your meeting is ready to review").
    func notifyTranscriptionComplete(meeting: Meeting, summarySnippet: String = "") {
        let content = UNMutableNotificationContent()
        content.title = "Meeting ready: \(meeting.displayTitle)"
        let snippet = summarySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = snippet.isEmpty
            ? "Transcript and summary are ready to review."
            : String(snippet.prefix(160))
        content.sound = .default
        // Deep link so tapping opens the meeting (routed via the registered
        // scheme, D1-2) instead of just activating the app. (U3-5)
        content.userInfo[deepLinkKey] = "meetingscribe://meeting/\(meeting.id)"
        let req = UNNotificationRequest(
            identifier: "transcription-\(meeting.id)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Schedules (or cancels) a repeating 8am "morning brief" nudge. (P2-5)
    func scheduleDailyBrief() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-brief"])
        guard AppSettings.shared.dailyBriefEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.body = "Your daily brief: yesterday's recap, today's meetings, and open commitments. Open MeetingScribe → Standup."
        content.sound = .default
        var when = DateComponents(); when.hour = 8; when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: "daily-brief", content: content, trigger: trigger))
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meeting: Meeting? = {
            guard let str = userInfo[meetingPayloadKey] as? String,
                  let data = str.data(using: .utf8) else { return nil }
            return try? decoder.decode(Meeting.self, from: data)
        }()

        switch actionID {
        case Self.actionJoinAndRecord:
            if let m = meeting {
                if let urlStr = m.conferenceURL, let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
                onJoinAndRecord?(m)
            }
        case Self.actionRecordOnly:
            if let m = meeting { onRecordMeeting?(m) }
        case Self.actionRecordImpromptu:
            let source = (userInfo[sourcePayloadKey] as? String) ?? "Impromptu"
            onRecordImpromptu?(source)
        case UNNotificationDefaultActionIdentifier:
            // Tap on the notification body — open the app window, and follow a
            // deep link to the meeting if one was attached. (U3-5)
            NSApp.activate(ignoringOtherApps: true)
            if let link = userInfo[deepLinkKey] as? String, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            } else if let m = meeting {
                onRecordMeeting?(m)
            }
        default:
            break
        }
    }
}
