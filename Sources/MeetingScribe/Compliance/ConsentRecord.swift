import Foundation

/// A persisted record that a recording-consent disclaimer was issued for a
/// meeting. Kept as an append-only audit log so there's a defensible trail of
/// when/where consent was sought.
struct ConsentRecord: Identifiable, Codable, Hashable, Sendable {
    enum Method: String, Codable, Sendable {
        /// Disclaimer shown on screen / in the UI.
        case displayed
        /// Disclaimer spoken aloud (e.g. TTS at recording start).
        case spoken
    }

    var id: String
    var meetingID: String
    var meetingTitle: String
    var timestamp: Date
    /// Jurisdiction in effect when consent was sought (e.g. "US", "EU").
    var jurisdiction: String
    var disclaimerText: String
    var method: Method

    init(
        id: String = UUID().uuidString,
        meetingID: String,
        meetingTitle: String,
        timestamp: Date = Date(),
        jurisdiction: String,
        disclaimerText: String,
        method: Method = .displayed
    ) {
        self.id = id
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.timestamp = timestamp
        self.jurisdiction = jurisdiction
        self.disclaimerText = disclaimerText
        self.method = method
    }
}
