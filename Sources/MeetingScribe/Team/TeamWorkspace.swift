import Foundation

/// A shared team workspace — a named group of members with a set of meetings
/// shared into it. The unit of multi-user collaboration; today it's a local
/// model that `TeamSyncService` will eventually back with a CloudKit shared
/// zone.
struct TeamWorkspace: Identifiable, Codable, Hashable, Sendable {
    struct Member: Identifiable, Codable, Hashable, Sendable {
        enum Role: String, Codable, CaseIterable, Sendable { case owner, editor, viewer }
        var id: String          // stable member id (e.g. iCloud user record name)
        var displayName: String
        var email: String?
        var role: Role
    }

    var id: String
    var name: String
    var memberIDs: [String]
    var sharedMeetingIDs: [String]
    var members: [Member]
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        memberIDs: [String] = [],
        sharedMeetingIDs: [String] = [],
        members: [Member] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.sharedMeetingIDs = sharedMeetingIDs
        self.members = members
        self.createdAt = createdAt
    }

    var owner: Member? { members.first { $0.role == .owner } }
}
