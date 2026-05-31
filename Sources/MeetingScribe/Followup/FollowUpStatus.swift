import Foundation

/// Per-meeting follow-up "sent" state (P2-6/U3-3). Lightweight UserDefaults flag
/// so recently-finished meetings can be resurfaced until their follow-up is
/// actually sent — previously there was no sent state at all.
enum FollowUpStatus {
    private static func key(_ id: String) -> String { "followup.sent.\(id)" }

    static func isSent(_ meetingID: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(meetingID))
    }

    static func setSent(_ meetingID: String, _ sent: Bool) {
        if sent { UserDefaults.standard.set(true, forKey: key(meetingID)) }
        else { UserDefaults.standard.removeObject(forKey: key(meetingID)) }
    }
}
