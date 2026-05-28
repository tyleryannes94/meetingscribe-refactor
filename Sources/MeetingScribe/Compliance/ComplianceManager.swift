import Foundation
import OSLog

/// Compliance Mode. When enabled, every time a recording starts we surface a
/// "this meeting is being recorded" disclaimer and append a `ConsentRecord` to
/// an append-only on-disk log.
///
/// The actual on-screen presentation is left to the UI: this manager posts
/// `.meetingScribeConsentDisclaimer` (with the disclaimer text in `userInfo`)
/// so a banner/toast observer can show it, and records the consent timestamp
/// regardless so the audit trail is complete.
@MainActor
final class ComplianceManager {
    static let shared = ComplianceManager()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Compliance")
    private var settings = ComplianceSettings()

    private(set) var records: [ConsentRecord] = []

    private init() {
        records = (try? Self.loadLog()) ?? []
    }

    /// Call when a recording starts. No-op unless Compliance Mode is enabled.
    /// Returns the issued record (for callers that want to display it), or nil.
    @discardableResult
    func recordingDidStart(meetingID: String, meetingTitle: String) -> ConsentRecord? {
        guard settings.enabled else { return nil }
        let text = settings.disclaimerText
        let record = ConsentRecord(
            meetingID: meetingID,
            meetingTitle: meetingTitle,
            jurisdiction: settings.jurisdiction.rawValue,
            disclaimerText: text,
            method: .displayed)
        records.append(record)
        persist()
        NotificationCenter.default.post(
            name: .meetingScribeConsentDisclaimer,
            object: nil,
            userInfo: ["text": text, "meetingID": meetingID])
        log.info("Issued recording disclaimer for meeting \(meetingID, privacy: .public).")
        return record
    }

    /// Consent log entries for a given meeting.
    func records(for meetingID: String) -> [ConsentRecord] {
        records.filter { $0.meetingID == meetingID }
    }

    // MARK: - Persistence

    private static var logURL: URL {
        let dir = AppSettings.shared.storageDir.appendingPathComponent("compliance", isDirectory: true)
        return dir.appendingPathComponent("consent-log.json")
    }

    private static func loadLog() throws -> [ConsentRecord] {
        let url = logURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ConsentRecord].self, from: data)
    }

    private func persist() {
        do {
            let url = Self.logURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Failed to persist consent log: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Notification.Name {
    /// Posted when a recording-consent disclaimer should be shown. `userInfo`
    /// carries `"text"` (the disclaimer) and `"meetingID"`.
    static let meetingScribeConsentDisclaimer =
        Notification.Name("meetingScribeConsentDisclaimer")
}
