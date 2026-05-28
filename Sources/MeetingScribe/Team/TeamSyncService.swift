import Foundation
import OSLog

/// Team sync (STUB).
///
/// Will sync `TeamWorkspace`s and their shared meetings via CloudKit **shared
/// zones**: the workspace owner creates a custom zone in their private DB,
/// shares it with a `CKShare`, and invited members accept into their shared DB.
/// Records: a workspace record + one record per shared meeting, mirrored to the
/// local store on fetch.
///
/// Today this just holds workspaces in memory and exposes the shape the UI and
/// future CloudKit implementation will use.
actor TeamSyncService {
    static let shared = TeamSyncService()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "TeamSync")
    private var workspaces: [TeamWorkspace] = []

    private init() {}

    func allWorkspaces() -> [TeamWorkspace] { workspaces }

    @discardableResult
    func createWorkspace(name: String) -> TeamWorkspace {
        let ws = TeamWorkspace(name: name)
        workspaces.append(ws)
        // TODO(CloudKit): create a custom zone + CKShare in the owner's private DB.
        log.info("Created local workspace \(ws.id, privacy: .public).")
        return ws
    }

    /// Invite a member by email. Stub — real impl sends a `CKShare` participant
    /// invite (URL the invitee opens to accept into their shared DB).
    func invite(email: String, to workspaceID: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        var ws = workspaces[idx]
        let member = TeamWorkspace.Member(id: UUID().uuidString, displayName: email,
                                          email: email, role: .viewer)
        ws.members.append(member)
        ws.memberIDs.append(member.id)
        workspaces[idx] = ws
        // TODO(CloudKit): add participant to the workspace's CKShare.
        log.info("Invited \(email, privacy: .private) to workspace \(workspaceID, privacy: .public) (local stub).")
    }

    /// Share a meeting into a workspace.
    func shareMeeting(_ meetingID: String, into workspaceID: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        if !workspaces[idx].sharedMeetingIDs.contains(meetingID) {
            workspaces[idx].sharedMeetingIDs.append(meetingID)
        }
        // TODO(CloudKit): write a meeting record into the workspace's shared zone.
    }

    /// Fetch remote changes. No-op stub.
    func sync() async {
        // TODO(CloudKit): fetch shared-zone changes, reconcile into local store.
    }
}
