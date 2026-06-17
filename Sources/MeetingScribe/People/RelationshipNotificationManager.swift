import Foundation
@preconcurrency import UserNotifications
import OSLog

/// Schedules and maintains per-person check-in reminder notifications and
/// birthday reminders. Separate from `NotificationManager` (which handles
/// meeting-capture notifications) to keep each file focused.
///
/// Notification identifiers are stable across sync calls so the system
/// deduplicates: scheduling the same notification twice is a no-op.
///
///   person-checkin-<id>       — recurring check-in reminder
///   person-birthday-<id>      — birthday notification (annually)
///   person-birthday-week-<id> — one-week-before birthday reminder
///
@available(macOS 14.0, *)
@MainActor
final class RelationshipNotificationManager {
    static let shared = RelationshipNotificationManager()
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "RelationshipNotifications")

    static let categoryCheckIn  = "PERSON_CHECKIN"
    static let actionLogNow     = "LOG_NOW"

    private init() {
        registerCategories()
    }

    private func registerCategories() {
        let logAction = UNNotificationAction(
            identifier: Self.actionLogNow,
            title: "Log check-in",
            options: [.foreground])
        let cat = UNNotificationCategory(
            identifier: Self.categoryCheckIn,
            actions: [logAction],
            intentIdentifiers: [],
            options: [])
        // Re-register without removing the categories set by NotificationManager —
        // we read existing categories and append ours.
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing
            updated.insert(cat)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
        }
    }

    // MARK: - Check-in reminders

    /// Sweeps all people with `relationshipType != .unset` and schedules
    /// a notification when `lastInteractionAt + effectiveCheckInDays` is in
    /// the past or within the next 24 hours. Idempotent — safe to call on
    /// launch, after saving an encounter, and after editing a person.
    ///
    /// - Parameters:
    ///   - people: All people from `PeopleStore.people`.
    ///   - encountersByPersonID: Last-encounter dates keyed by person id.
    func syncPersonReminders(people: [Person],
                             encountersByPersonID: [String: Date] = [:]) async {
        let center = UNUserNotificationCenter.current()

        // Build the set of check-in notification IDs we WANT to keep.
        var wantedIDs: Set<String> = []

        for person in people {
            guard person.relationshipType != .unset else { continue }
            let id = "person-checkin-\(person.id)"
            wantedIDs.insert(id)

            // Determine last interaction date.
            let lastInteraction = person.lastInteractionAt
                ?? encountersByPersonID[person.id]
                ?? person.createdAt

            let cadence = TimeInterval(person.effectiveCheckInDays) * 86400
            let dueDate = lastInteraction.addingTimeInterval(cadence)

            // Only schedule if overdue or due within the next 7 days.
            let horizon = Date().addingTimeInterval(7 * 86400)
            guard dueDate <= horizon else { continue }

            let fireDate = max(dueDate, Date().addingTimeInterval(60)) // at least 1 min from now
            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            // Fire at 9am on the due day if the computed time is in the past.
            if fireDate <= Date() {
                components = DateComponents()
                components.hour = 9
                components.minute = 0
                // Use tomorrow 9am if today 9am is also in the past.
                var tomorrowComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
                tomorrowComponents.hour = 9
                tomorrowComponents.minute = 0
                if let tomorrow9am = Calendar.current.date(from: tomorrowComponents) {
                    let t = UNCalendarNotificationTrigger(
                        dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrow9am),
                        repeats: false)
                    await scheduleCheckIn(id: id, person: person, trigger: t, center: center)
                }
                continue
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            await scheduleCheckIn(id: id, person: person, trigger: trigger, center: center)

            // Birthday notifications
            await scheduleBirthdayReminders(for: person, center: center)
        }

        // Cancel notifications for people whose type was reset to .unset.
        let existing = await center.pendingNotificationRequests()
        let toCancel = existing
            .map(\.identifier)
            .filter { $0.hasPrefix("person-checkin-") && !wantedIDs.contains($0) }
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toCancel)
        }
    }

    private func scheduleCheckIn(id: String,
                                  person: Person,
                                  trigger: UNCalendarNotificationTrigger,
                                  center: UNUserNotificationCenter) async {
        // Deduplicate — don't reschedule if already pending.
        let pending = await center.pendingNotificationRequests()
        if pending.contains(where: { $0.identifier == id }) { return }

        let content = UNMutableNotificationContent()
        content.title = "\(person.relationshipType.emoji) Check in with \(person.displayName)"
        content.body = "It's been a while. \(checkInBody(for: person.relationshipType))"
        content.categoryIdentifier = Self.categoryCheckIn
        content.userInfo["personID"] = person.id
        content.sound = .default

        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(req)
        } catch {
            log.error("Failed to schedule check-in for \(person.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 2-D: an ad-hoc "remind me to reach out" nudge scheduled `days` from now,
    /// independent of the cadence reminders. Used by the KeepInTouch board.
    func scheduleOneOff(person: Person, days: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(person.relationshipType.emoji) Reach out to \(person.displayName)"
        content.body = "You asked to be reminded to get in touch."
        content.userInfo["personID"] = person.id
        content.sound = .default
        let interval = max(60, TimeInterval(days) * 86_400)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let req = UNNotificationRequest(identifier: "oneoff-\(person.id)-\(Int(interval))",
                                        content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func checkInBody(for type: RelationshipType) -> String {
        switch type {
        case .romanticPartner: return "How are things between you two?"
        case .familyMember:    return "Give them a call or send a message."
        case .closeFriend:     return "It might be time for a proper catch-up."
        case .friend:          return "Drop them a quick note."
        default:               return "Log a quick check-in to keep the relationship warm."
        }
    }

    // MARK: - Birthday reminders

    private func scheduleBirthdayReminders(for person: Person, center: UNUserNotificationCenter) async {
        guard let birthday = person.birthday else { return }
        let cal = Calendar.current
        let now = Date()

        // Compute the next occurrence of their birthday.
        var birthdayComponents = cal.dateComponents([.month, .day], from: birthday)

        // Birthday notification (day of).
        let birthdayID = "person-birthday-\(person.id)"
        birthdayComponents.hour = 9
        birthdayComponents.minute = 0
        let birthdayTrigger = UNCalendarNotificationTrigger(dateMatching: birthdayComponents, repeats: true)

        let birthdayContent = UNMutableNotificationContent()
        birthdayContent.title = "🎂 \(person.displayName)'s birthday!"
        birthdayContent.body = "Today is a great day to reach out."
        birthdayContent.sound = .default
        birthdayContent.userInfo["personID"] = person.id

        let birthdayPending = await center.pendingNotificationRequests()
        if !birthdayPending.contains(where: { $0.identifier == birthdayID }) {
            let req = UNNotificationRequest(identifier: birthdayID, content: birthdayContent, trigger: birthdayTrigger)
            try? await center.add(req)
        }

        // One-week-before reminder (non-repeating, computed for this year/next).
        let weekBeforeID = "person-birthday-week-\(person.id)"
        if !birthdayPending.contains(where: { $0.identifier == weekBeforeID }) {
            // Find the next birthday date.
            var nextBdComponents = birthdayComponents
            let currentYear = cal.component(.year, from: now)
            nextBdComponents.year = currentYear
            if let thisYearBd = cal.date(from: nextBdComponents), thisYearBd > now {
                let weekBefore = thisYearBd.addingTimeInterval(-7 * 86400)
                if weekBefore > now {
                    let weekContent = UNMutableNotificationContent()
                    weekContent.title = "🎂 \(person.displayName)'s birthday is in 7 days"
                    weekContent.body = "Plan something special."
                    weekContent.sound = .default
                    weekContent.userInfo["personID"] = person.id
                    let wbComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: weekBefore)
                    let wbTrigger = UNCalendarNotificationTrigger(dateMatching: wbComponents, repeats: false)
                    let req = UNNotificationRequest(identifier: weekBeforeID, content: weekContent, trigger: wbTrigger)
                    try? await center.add(req)
                }
            }
        }
    }
}
