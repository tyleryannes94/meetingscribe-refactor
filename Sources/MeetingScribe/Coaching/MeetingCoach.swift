import Foundation

/// Per-speaker share of the conversation.
struct TalkTimeSlice: Identifiable, Hashable {
    let speaker: String
    let words: Int
    /// 0...1 fraction of total words.
    let fraction: Double
    var id: String { speaker }
}

/// The output of analyzing a single meeting transcript. Cheap, deterministic
/// heuristics — no model calls — so it can run inline as the Coach tab renders.
struct CoachingReport {
    var totalWords: Int
    var questionCount: Int
    var actionItemCount: Int
    var talkTime: [TalkTimeSlice]
    var suggestions: [String]

    /// Action items per 1,000 words — a rough "did this meeting produce
    /// outcomes" signal.
    var actionItemDensity: Double {
        guard totalWords > 0 else { return 0 }
        return Double(actionItemCount) / Double(totalWords) * 1000
    }

    /// Largest single-speaker share (0...1), or 0 when talk time is unknown.
    var dominanceFraction: Double { talkTime.map(\.fraction).max() ?? 0 }

    static let empty = CoachingReport(totalWords: 0, questionCount: 0,
                                      actionItemCount: 0, talkTime: [], suggestions: [])
}

/// Analyzes a transcript for conversational-hygiene signals: talk-time
/// balance, how many questions were asked, and whether the meeting produced a
/// proportionate number of action items.
enum MeetingCoach {

    static func analyze(transcript: String,
                        diarized: DiarizedTranscript? = nil,
                        actionItemCount: Int) -> CoachingReport {
        let words = wordCount(in: transcript)
        let questions = transcript.filter { $0 == "?" }.count
        let talk = talkTime(from: diarized)

        var report = CoachingReport(
            totalWords: words,
            questionCount: questions,
            actionItemCount: actionItemCount,
            talkTime: talk,
            suggestions: []
        )
        report.suggestions = suggestions(for: report)
        return report
    }

    // MARK: - Components

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private static func talkTime(from diarized: DiarizedTranscript?) -> [TalkTimeSlice] {
        guard let d = diarized, d.hasMultipleSpeakers else { return [] }
        let nameByIndex = Dictionary(uniqueKeysWithValues: d.speakers.map { ($0.index, $0.displayName) })
        var wordsBySpeaker: [Int: Int] = [:]
        for seg in d.segments {
            wordsBySpeaker[seg.speakerIndex, default: 0] += wordCount(in: seg.text)
        }
        let total = max(1, wordsBySpeaker.values.reduce(0, +))
        return wordsBySpeaker
            .map { idx, w in
                TalkTimeSlice(speaker: nameByIndex[idx] ?? "Speaker \(idx + 1)",
                              words: w,
                              fraction: Double(w) / Double(total))
            }
            .sorted { $0.words > $1.words }
    }

    private static func suggestions(for r: CoachingReport) -> [String] {
        var out: [String] = []

        if r.dominanceFraction >= 0.7, let top = r.talkTime.first {
            out.append("\(top.speaker) spoke ~\(Int(top.fraction * 100))% of the time. "
                       + "Consider making more room for others.")
        }
        if !r.talkTime.isEmpty, r.dominanceFraction < 0.55 {
            out.append("Talk time was well balanced across participants. 👏")
        }
        if r.totalWords > 400 && r.questionCount < 3 {
            out.append("Few questions were asked (\(r.questionCount)). "
                       + "Asking more questions tends to surface alignment gaps.")
        }
        if r.totalWords > 600 && r.actionItemCount == 0 {
            out.append("No action items came out of a substantial discussion — "
                       + "did anything need a clear owner and next step?")
        }
        if r.actionItemCount > 0 && r.actionItemDensity < 1.5 && r.totalWords > 800 {
            out.append("Action-item density is low for the meeting length. "
                       + "Worth confirming everything actionable was captured.")
        }
        if out.isEmpty {
            out.append("Nothing notable — this looks like a healthy, focused meeting.")
        }
        return out
    }
}
