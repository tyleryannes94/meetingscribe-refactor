import Foundation
import OSLog

/// The unified post-meeting pipeline (3-A / audit C-1 — the highest-consensus
/// item across the whole audit). When a meeting finalizes, the app does the
/// follow-through work for Tyler instead of waiting for him to remember.
///
/// Steps 1–2 (encounter creation, action-item owner resolution) already run
/// inline in `MeetingPipelineController.finalize`. This coordinator subscribes to
/// the `meetingFinalized` event and handles the rest, decoupled from the
/// pipeline: decision↔people cross-linking, the T+45 "review your meeting"
/// nudge, and queuing an `InsightEngine` pass. Integration push (Notion/Linear)
/// lands in Phase 6.
@available(macOS 14.0, *)
@MainActor
final class PostMeetingPipelineCoordinator {
    static let shared = PostMeetingPipelineCoordinator()
    private init() {}

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "PostMeetingPipeline")
    private var started = false
    private var task: Task<Void, Never>?
    private weak var decisions: DecisionStore?
    private weak var notifications: NotificationManager?

    func start(decisions: DecisionStore, notifications: NotificationManager) {
        guard !started else { return }
        started = true
        self.decisions = decisions
        self.notifications = notifications
        task = Task { [weak self] in
            for await event in SecondBrainEventBus.shared.subscribe() {
                guard let self else { break }
                if case let .meetingFinalized(meetingID, attendees) = event {
                    self.handleFinalized(meetingID: meetingID, attendees: attendees)
                }
            }
        }
        log.info("PostMeetingPipelineCoordinator subscribed to the event bus")
    }

    private func handleFinalized(meetingID: String, attendees: [String]) {
        var ran: [String] = []

        // STEP 3 — cross-link this meeting's decisions to its attendees.
        if !attendees.isEmpty {
            decisions?.crossLinkPersons(meetingID: meetingID, personIDs: attendees)
            ran.append("decision-crosslink(\(attendees.count))")
        }

        // STEP 5 — schedule the T+45min review nudge.
        let names = attendees.compactMap { PeopleStore.shared.person(by: $0)?.displayName }
        notifications?.scheduleMeetingReview(meetingID: meetingID, attendeeNames: names)
        ran.append("review-notification")

        // STEP 6 — queue a background InsightEngine pass.
        InsightEngine.shared.enqueueMeeting(meetingID)
        ran.append("insight-enqueue")

        // Make the automation auditable (visible in os_log; surfaced in the
        // meeting detail debug section if needed).
        log.info("Post-meeting pipeline for \(meetingID, privacy: .public): \(ran.joined(separator: ", "), privacy: .public)")
    }
}
