import Foundation
import OSLog

/// Drives the Phase B person-extraction pass: runs the LLM over a meeting's
/// transcript, then feeds the result into `PeopleStore` for fuzzy-match
/// auto-linking / suggestion queueing. Mirrors `ActionItemBackfillController`
/// (audit 5.1) so views can observe progress with scoped invalidation.
///
/// Local-only (Ollama). Nothing leaves the machine.
@available(macOS 14.0, *)
@MainActor
final class PersonExtractionController: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "PersonExtraction")

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var processed: Int = 0
    @Published private(set) var total: Int = 0

    private let store: MeetingStore
    private let tagStore: TagStore
    private let summarizer: OllamaService
    private var didBackfill = false

    /// Cap the per-session backfill so a large library doesn't trigger dozens
    /// of LLM passes at once. Recent meetings are processed first; the rest get
    /// picked up over subsequent sessions (each meeting is extracted once, then
    /// remembered via `PeopleStore.markExtracted`).
    private let backfillCap = 25

    init(store: MeetingStore, tagStore: TagStore, summarizer: OllamaService = OllamaService()) {
        self.store = store
        self.tagStore = tagStore
        self.summarizer = summarizer
    }

    /// Extract people from a single meeting (called after a recording finalizes,
    /// or manually from the detail view). Fire-and-forget.
    func extract(for meeting: Meeting, force: Bool = false) {
        guard AppSettings.shared.autoExtractPeople || force else { return }
        guard force || !PeopleStore.shared.hasExtracted(meeting.id) else { return }
        let primary = tagStore.primaryTag(for: meeting)
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let transcript = await MainActor.run { self.store.readTranscript(for: meeting, primaryTag: primary) }
            await self.runOne(meeting: meeting, transcript: transcript)
        }
    }

    /// One-shot per-session backfill over the most recent un-extracted meetings.
    func runIfNeeded(meetings: [Meeting], force: Bool = false) {
        guard AppSettings.shared.autoExtractPeople else { return }
        guard force || !didBackfill else { return }
        didBackfill = true

        let pending = meetings
            .filter { force || !PeopleStore.shared.hasExtracted($0.id) }
            .sorted { $0.startDate > $1.startDate }
            .prefix(backfillCap)
            .map { $0 }
        guard !pending.isEmpty else { return }

        isRunning = true
        processed = 0
        total = pending.count
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for m in pending {
                let primary = await MainActor.run { self.tagStore.primaryTag(for: m) }
                let transcript = await MainActor.run { self.store.readTranscript(for: m, primaryTag: primary) }
                await self.runOne(meeting: m, transcript: transcript)
                await MainActor.run { self.processed += 1 }
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    /// Runs the extraction + ingestion for one meeting. Marks the meeting as
    /// extracted even when zero people came back, so we don't re-pay the LLM
    /// cost for a transcript that genuinely mentions nobody.
    private func runOne(meeting: Meeting, transcript: String) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "# Transcript" else {
            await MainActor.run { PeopleStore.shared.markExtracted(meeting.id) }
            return
        }
        let extracted = await PersonExtractor.extract(from: transcript, meeting: meeting, using: summarizer)
        await MainActor.run {
            PeopleStore.shared.ingestExtraction(extracted, meeting: meeting)
            PeopleStore.shared.markExtracted(meeting.id)
        }
    }
}
