import Foundation

/// Kinds of background insight the `InsightEngine` (Phase 3) can surface.
enum InsightType: String, Sendable, Codable {
    case relationshipDrift
    case semanticNudge
    case morningBrief
    case weeklyReview
    case preMeetingBrief
    case decisionCrossLink
}

/// A typed cross-store event (P0-B / audit C-15).
///
/// Before this, every cross-tab behavior was wired by one store reaching into
/// another, or by stringly-typed `NotificationCenter` posts. That made the
/// post-meeting automation pipeline (Phase 3) and background AI jobs impossible
/// to compose without coupling every store to every feature. This bus is the
/// single typed seam: stores *publish* facts about what happened; future
/// subscribers (the pipeline coordinator, InsightEngine, Today, notifications)
/// react — without the publisher knowing they exist.
///
/// All payloads are value types so the event is `Sendable` and safe to deliver
/// across tasks.
enum SecondBrainEvent: Sendable {
    /// A meeting's full post-stop pipeline finished. `attendees` are resolved
    /// Person ids (already matched against the people graph).
    case meetingFinalized(meetingID: String, attendees: [String])
    case taskCreated(task: ActionItem)
    case taskUpdated(task: ActionItem)
    case encounterLogged(encounter: Encounter, personID: String)
    case decisionExtracted(decision: Decision, meetingID: String)
    case personUpdated(personID: String)
    /// A background insight became available for the UI / notifications to show.
    case insightAvailable(type: InsightType, payload: [String: String])
    /// A Brain Dump session was just created (in-app or via MCP). MainWindow
    /// listens so it can flash a "new from Claude Code" toast.
    case brainDumpSessionCreated(sessionID: String)
    /// A Brain Dump session's body / sources / drafts changed.
    case brainDumpUpdated(sessionID: String)
}

/// Process-wide multicast event bus for `SecondBrainEvent`s.
///
/// `subscribe()` returns a fresh `AsyncStream` per caller (a single
/// `AsyncStream` only supports one consumer, but Phase 3 has several — the
/// pipeline coordinator, InsightEngine, Today, the notification layer). Each
/// registered continuation receives every published event; continuations clean
/// themselves up when their stream is cancelled or deallocated.
///
/// `@MainActor` because every publisher (the stores) is already main-actor
/// isolated, so publishing never hops actors. Subscribers consume on whatever
/// task they iterate from.
@MainActor
final class SecondBrainEventBus {
    static let shared = SecondBrainEventBus()
    private init() {}

    private var continuations: [UUID: AsyncStream<SecondBrainEvent>.Continuation] = [:]

    /// Subscribe to the stream of events. The returned stream stays live until
    /// the caller stops iterating (or the surrounding task is cancelled).
    func subscribe() -> AsyncStream<SecondBrainEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    /// Publish an event to every current subscriber. No-op when there are none
    /// (the P0 state — publishers are wired, subscribers arrive in Phase 3).
    func publish(_ event: SecondBrainEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }
}
