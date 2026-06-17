import Foundation
import OSLog

/// Background intelligence that runs *for* Tyler while he's elsewhere (3-C /
/// audit C-2) — the heart of the v1→v2 shift from reactive to proactive.
///
/// Every pass is gated by the `ResourceGovernor` (`.backgroundInsight` — idle,
/// cool, on wall power) so speculative AI never degrades live capture. Results
/// are published on the `SecondBrainEventBus` as `.insightAvailable` events that
/// Today and the notification layer (Phase 5) surface.
@available(macOS 14.0, *)
@MainActor
final class InsightEngine {
    static let shared = InsightEngine()
    private init() {}

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "InsightEngine")

    private var started = false
    private weak var actionItems: ActionItemStore?
    private weak var decisions: DecisionStore?
    private var idleTask: Task<Void, Never>?

    // Semantic-nudge rate limiting (max 3/day, no repeat within 72h).
    private var lastNudgeAt: [String: Date] = [:]
    private var nudgesToday = 0
    private var nudgeDayKey = ""

    func start(actionItems: ActionItemStore, decisions: DecisionStore) {
        guard !started else { return }
        started = true
        self.actionItems = actionItems
        self.decisions = decisions
        // Idle cadence: a pass every 4 hours when nothing has triggered one.
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4 * 3_600 * 1_000_000_000)
                await self?.runPass()
            }
        }
        log.info("InsightEngine started")
    }

    /// Queue a pass after a meeting finalizes (called by the pipeline coordinator).
    func enqueueMeeting(_ meetingID: String) {
        Task { [weak self] in await self?.runPass() }
    }

    /// One gated pass: relationship-health refresh, decision cross-link cleanup,
    /// and semantic nudges. Cheap and idempotent; no-ops when the gate is closed.
    func runPass() async {
        guard ResourceGovernor.shared.canScheduleWork(tier: .backgroundInsight) else {
            log.debug("InsightEngine pass skipped — ResourceGovernor gate closed")
            return
        }
        // 1. Relationship health: recompute anyone whose score is stale.
        PeopleStore.shared.refreshStaleStrengthScores()

        // 2. Semantic nudges: surface recently-created tasks that relate to
        //    something already in the vault.
        await generateSemanticNudges()
    }

    private func generateSemanticNudges() async {
        guard let actionItems else { return }
        let today = Self.dayKey()
        if today != nudgeDayKey { nudgeDayKey = today; nudgesToday = 0 }
        guard nudgesToday < 3 else { return }

        let now = Date()
        let recentOpen = actionItems.items
            .filter { $0.status != .completed && now.timeIntervalSince($0.createdAt) < 7 * 86_400 }
            .prefix(12)

        for task in recentOpen {
            guard nudgesToday < 3 else { break }
            if let last = lastNudgeAt[task.id], now.timeIntervalSince(last) < 72 * 3_600 { continue }
            let results = await PeopleStore.shared.searchVaultHybrid(task.title, limit: 4)
            // A related MEETING that isn't the task's own origin meeting.
            guard let related = results.first(where: {
                $0.entityKind == "meeting" && $0.entityID != task.meetingID
            }) else { continue }
            lastNudgeAt[task.id] = now
            nudgesToday += 1
            SecondBrainEventBus.shared.publish(.insightAvailable(
                type: .semanticNudge,
                payload: [
                    "taskID": task.id,
                    "taskTitle": task.title,
                    "relatedID": related.entityID,
                    "relatedTitle": related.title ?? "a related meeting",
                ]))
            log.info("Semantic nudge: task \(task.id, privacy: .public) ↔ meeting \(related.entityID, privacy: .public)")
        }
    }

    private static func dayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
