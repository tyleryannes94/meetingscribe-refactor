import Foundation

/// Seeds one bundled sample meeting on a brand-new vault so a first-run user
/// sees real value — a finished summary, transcript, and a couple of tasks —
/// in zero clicks, and Today is never empty. (D3-3)
///
/// Only runs once, and only when the vault has no real meetings, so it never
/// injects an example into an existing user's history. The sample is an
/// ordinary meeting (same on-disk files as a real recording), so it's fully
/// clickable and the user can delete it like any other.
@available(macOS 14.0, *)
enum SampleMeetingSeeder {
    private static let flagKey = "hasSeededSampleMeeting"
    static let sampleMeetingID = "sample-welcome-meeting"

    @MainActor
    static func seedIfNeeded(manager: MeetingManager) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flagKey) else { return }
        // Never seed over an existing user's real meetings — just mark done.
        guard manager.pastMeetings.isEmpty else {
            defaults.set(true, forKey: flagKey)
            return
        }
        defaults.set(true, forKey: flagKey)

        let now = Date()
        let start = now.addingTimeInterval(-2 * 3600)
        let end = start.addingTimeInterval(28 * 60)
        var meeting = Meeting(
            id: sampleMeetingID,
            title: "Welcome to MeetingScribe (example)",
            startDate: start, endDate: end,
            attendees: ["You", "Alex Rivera <alex@example.com>", "Jordan Lee <jordan@example.com>"],
            notes: nil, location: nil,
            conferenceURL: nil, calendarName: nil, seriesID: nil,
            userDescription: "Example meeting — safe to delete anytime.", userTitle: nil,
            isImpromptu: false, segmentCount: 0)
        meeting.isImported = true

        do {
            try manager.store.writeMeeting(meeting, primaryTag: nil)
            try manager.store.writeSummary(sampleSummary, for: meeting, primaryTag: nil)
            try manager.store.writeTranscript(sampleTranscript, for: meeting, primaryTag: nil)
        } catch {
            return
        }

        // A couple of starter tasks so the Tasks tab also demonstrates value.
        _ = manager.actionItems.createTask(title: "Record your first real meeting (⌘R to start)")
        _ = manager.actionItems.createTask(title: "Open the sample meeting to see its summary + transcript")

        manager.refreshPastMeetings(force: true)
    }

    // MARK: - Canned content

    private static let sampleSummary = """
    > **This is a sample meeting — delete it anytime.** It shows what MeetingScribe
    > produces after a real call: a structured summary, action items, and the full
    > transcript, all stored locally in your vault.

    # Welcome to MeetingScribe — Summary

    ## TL;DR
    A quick tour of how MeetingScribe turns a recorded call into a searchable,
    linked record. Record a meeting, and a summary like this is generated on your
    Mac — nothing leaves the device.

    ## Key Decisions
    - Keep everything local: transcription and summaries run on-device.
    - Use ⌘R to start an ad-hoc recording; the live card appears on Today.

    ## Action Items
    - [ ] You — Record your first real meeting to replace this example (due: unspecified)
    - [ ] You — Try clicking an attendee chip above to add them to People (due: unspecified)

    ## Open Questions
    - None.

    ## Notable Quotes
    - "Everything stays on your Mac." — MeetingScribe
    """

    private static let sampleTranscript = """
    [00:00] Me: Hey — thanks for hopping on. This is a quick example of what a
    transcript looks like once a meeting is recorded.

    [00:08] Them: Nice. So the audio is captured locally and transcribed on-device?

    [00:14] Me: Exactly. Whisper runs on your Mac, then a local model writes the
    summary. Nothing is uploaded anywhere.

    [00:24] Them: And the action items and people all link together afterward?

    [00:29] Me: Right — attendees become People, action items become Tasks, and
    everything is one click apart. Go ahead and record a real meeting to see it
    with your own audio.
    """
}
