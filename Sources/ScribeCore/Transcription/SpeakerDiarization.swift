import Foundation

/// One identified speaker in a diarized transcript. `index` is the raw
/// `SPEAKER_NN` number whisper assigns; `displayName` is what the UI shows
/// (user-renamable later — e.g. "Me", "Alice").
struct Speaker: Identifiable, Hashable, Sendable {
    let index: Int
    var displayName: String

    var id: Int { index }

    init(index: Int, displayName: String? = nil) {
        self.index = index
        self.displayName = displayName ?? "Speaker \(index + 1)"
    }
}

/// A single contiguous turn by one speaker.
struct DiarizedSegment: Identifiable, Hashable, Sendable {
    let id = UUID()
    let speakerIndex: Int
    var text: String
}

/// A transcript split into speaker turns, parsed from whisper.cpp's
/// `--diarize` output (which inlines `[SPEAKER_NN]` markers into the text).
struct DiarizedTranscript: Sendable {
    var speakers: [Speaker]
    var segments: [DiarizedSegment]

    var isEmpty: Bool { segments.isEmpty }

    /// Whether any real speaker turns were detected (vs. a single untagged blob,
    /// which is what you get from a model that ignored `--diarize`).
    var hasMultipleSpeakers: Bool { speakers.count > 1 }

    /// Parse whisper diarized output. Recognizes `[SPEAKER_00]`, `[SPEAKER 1]`,
    /// and `(speaker 2)` style markers, case-insensitively. Text before the
    /// first marker is attributed to speaker 0.
    static func parse(_ raw: String) -> DiarizedTranscript {
        let pattern = #"[\[(]\s*speaker[_ ]?(\d+)\s*[\])]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return DiarizedTranscript(speakers: [], segments: [])
        }

        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))

        var segments: [DiarizedSegment] = []
        var seenIndices: Set<Int> = []

        func appendTurn(speaker: Int, text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            segments.append(DiarizedSegment(speakerIndex: speaker, text: trimmed))
            seenIndices.insert(speaker)
        }

        if matches.isEmpty {
            // No markers — single untagged speaker.
            appendTurn(speaker: 0, text: raw)
        } else {
            // Leading text before the first marker → speaker 0.
            let firstStart = matches[0].range.location
            if firstStart > 0 {
                appendTurn(speaker: 0, text: ns.substring(to: firstStart))
            }
            for (i, match) in matches.enumerated() {
                let idx = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let textStart = match.range.location + match.range.length
                let textEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
                guard textEnd >= textStart else { continue }
                appendTurn(speaker: idx,
                           text: ns.substring(with: NSRange(location: textStart, length: textEnd - textStart)))
            }
        }

        let speakers = seenIndices.sorted().map { Speaker(index: $0) }
        return DiarizedTranscript(speakers: speakers, segments: segments)
    }

    /// Render back to plain markdown with `**Speaker N:**` prefixes — handy for
    /// display or for feeding a speaker-attributed transcript to the summarizer.
    func markdown() -> String {
        let nameByIndex = Dictionary(uniqueKeysWithValues: speakers.map { ($0.index, $0.displayName) })
        return segments.map { seg in
            let name = nameByIndex[seg.speakerIndex] ?? "Speaker \(seg.speakerIndex + 1)"
            return "**\(name):** \(seg.text)"
        }.joined(separator: "\n\n")
    }
}
