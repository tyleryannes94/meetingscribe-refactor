import Foundation
import OSLog

/// Single-shot-per-session backfill of action items from every past
/// meeting's `summary.md`. Extracted from `MeetingManager` (audit 5.1)
/// so the Today / Action Items views can observe backfill progress
/// without re-rendering on every unrelated MeetingManager change.
@available(macOS 14.0, *)
@MainActor
final class ActionItemBackfillController: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ActionItemBackfill")

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var processed: Int = 0
    @Published private(set) var total: Int = 0

    private let store: MeetingStore
    private let tagStore: TagStore
    private let actionItems: ActionItemStore
    private var didBackfill = false

    init(store: MeetingStore, tagStore: TagStore, actionItems: ActionItemStore) {
        self.store = store
        self.tagStore = tagStore
        self.actionItems = actionItems
    }

    /// Backfills action items for every past meeting that has a summary
    /// but no items yet. Idempotent within a session.
    func runIfNeeded(meetings: [Meeting], force: Bool = false) {
        guard force || !didBackfill else { return }
        didBackfill = true
        isRunning = true
        processed = 0
        total = meetings.count
        let snapshot = meetings
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for m in snapshot {
                let needsExtract = await MainActor.run {
                    self.actionItems.items(for: m.id).isEmpty
                }
                if needsExtract {
                    let summary = await MainActor.run {
                        self.store.readSummary(for: m, primaryTag: self.tagStore.primaryTag(for: m))
                    }
                    if !summary.isEmpty {
                        let extracted = ActionItemExtractor.extract(from: summary, meeting: m)
                        await MainActor.run {
                            self.actionItems.reconcileExtracted(extracted, for: m.id)
                        }
                    }
                }
                await MainActor.run { self.processed += 1 }
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    /// Re-extract for a single meeting (manual button in the detail view).
    func reextract(for meeting: Meeting) {
        let s = store.readSummary(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
        guard !s.isEmpty else { return }
        let extracted = ActionItemExtractor.extract(from: s, meeting: meeting)
        actionItems.reconcileExtracted(extracted, for: meeting.id)
    }
}
