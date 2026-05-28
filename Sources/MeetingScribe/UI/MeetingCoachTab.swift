import SwiftUI

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    /// "Coach" tab — conversational-hygiene metrics derived from the transcript
    /// (talk-time balance, question count, action-item density). See Phase 3 /
    /// MeetingCoach.swift + CoachingReportView.swift.
    @ViewBuilder
    var coachBody: some View {
        let diarized = transcript.isEmpty ? nil : DiarizedTranscript.parse(transcript)
        let itemCount = meeting.map { manager.actionItems.items(for: $0.id).count } ?? 0
        let report = MeetingCoach.analyze(transcript: transcript,
                                          diarized: diarized,
                                          actionItemCount: itemCount)
        CoachingReportView(report: report)
    }
}
