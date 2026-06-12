import SwiftUI
import AVFoundation

// MARK: - Data model

/// A single parsed utterance from the transcript.
struct TranscriptSegment: Identifiable, Equatable {
    let id: UUID
    let speaker: String
    let startSeconds: TimeInterval
    let text: String

    /// Time string shown in the timestamp column (e.g. "1:23" or "1:23:45").
    var timeLabel: String {
        let s = Int(startSeconds)
        let h = s / 3600; let m = (s % 3600) / 60; let r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }
}

/// Parser for the WhisperTranscriber output format:
///   `Me [0:05]: First sentence here.`
///   `Them [1:23]: Another utterance.`
struct TranscriptParser {
    static func parse(_ markdown: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let lines = markdown.components(separatedBy: .newlines)
        // Pattern: Speaker [H:MM] or Speaker [M:SS] or Speaker [H:MM:SS]
        let pattern = #"^(.+?)\s*\[(\d+:\d{2}(?::\d{2})?)\]:\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return fallbackParse(markdown)
        }
        for line in lines {
            let r = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: r) else { continue }
            func group(_ i: Int) -> String {
                guard let rng = Range(match.range(at: i), in: line) else { return "" }
                return String(line[rng])
            }
            let speaker = group(1).trimmingCharacters(in: .whitespaces)
            let timeStr = group(2)
            let text = group(3).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let secs = parseTime(timeStr)
            segments.append(TranscriptSegment(id: UUID(), speaker: speaker,
                                              startSeconds: secs, text: text))
        }
        // If no structured segments found, try the bold-speaker markdown format
        return segments.isEmpty ? fallbackParse(markdown) : segments
    }

    /// Fallback: try **Speaker:** prefix format (e.g. "**Me:** text")
    private static func fallbackParse(_ markdown: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let lines = markdown.components(separatedBy: .newlines)
        let pattern = #"^\*\*(.+?):\*\*\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        for line in lines {
            let r = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: r) else { continue }
            func g(_ i: Int) -> String {
                guard let rng = Range(match.range(at: i), in: line) else { return "" }
                return String(line[rng])
            }
            segments.append(TranscriptSegment(id: UUID(), speaker: g(1),
                                              startSeconds: 0, text: g(2)))
        }
        return segments
    }

    private static func parseTime(_ s: String) -> TimeInterval {
        let parts = s.split(separator: ":").compactMap { TimeInterval($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }
}

// MARK: - TranscriptSyncView

/// Navigable, audio-synced transcript view.
///
/// Features:
/// - Speaker-colored rows with timestamp + speaker + text columns
/// - Click timestamp → seek audio to that moment
/// - Active line highlights as audio plays (when a player is attached)
/// - Speaker jump chips at the top
/// - Inline search with highlight
@available(macOS 14.0, *)
struct TranscriptSyncView: View {
    let rawTranscript: String
    /// Optional reference to the audio controller for seek + sync.
    var audioController: AudioPlayerController?
    /// Seed the find bar (U2-2) — e.g. carried from a search hit.
    var initialSearch: String? = nil

    @State private var segments: [TranscriptSegment] = []
    @State private var isVisible = false
    @State private var speakers: [String] = []
    @State private var speakerColors: [String: Color] = [:]
    @State private var activeSegmentID: UUID?
    @State private var searchText: String = ""
    @State private var selectedSpeaker: String? = nil
    @State private var syncActive: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(NDS.divider)
            if segments.isEmpty {
                emptyTranscriptView
            } else {
                transcriptScroll
            }
        }
        .onAppear {
            isVisible = true; parse()
            if let seed = initialSearch, !seed.isEmpty, searchText.isEmpty { searchText = seed }
        }
        .onDisappear { isVisible = false }
        .onChange(of: rawTranscript) { _, _ in parse() }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            // ARCH-2: skip work when this tab isn't on-screen (the keep-alive
            // ZStack keeps hidden tabs mounted) or when audio isn't playing —
            // updateActiveSegment already no-ops when not playing.
            guard isVisible else { return }
            updateActiveSegment()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").scaledFont(11).foregroundStyle(NDS.textTertiary)
                TextField("Search transcript…", text: $searchText)
                    .scaledFont(12)
                if !searchText.isEmpty {
                    // C1-7: live match counter so you know if it's worth scanning.
                    Text("\(filteredSegments.count)")
                        .scaledFont(10.5, weight: .semibold).monospacedDigit()
                        .foregroundStyle(filteredSegments.isEmpty ? NDS.danger : NDS.textTertiary)
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").scaledFont(11)
                            .foregroundStyle(NDS.textTertiary)
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(NDS.hairline, lineWidth: 1))
            .frame(maxWidth: 200)

            // Speaker jump chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(speakers, id: \.self) { spk in
                        Button {
                            selectedSpeaker = selectedSpeaker == spk ? nil : spk
                        } label: {
                            Text(spk)
                                .scaledFont(11, weight: .medium)
                                .foregroundStyle(selectedSpeaker == spk
                                    ? .white : (speakerColors[spk] ?? NDS.brand))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(
                                    selectedSpeaker == spk
                                        ? (speakerColors[spk] ?? NDS.brand)
                                        : (speakerColors[spk] ?? NDS.brand).opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Sync toggle (only if audio exists)
            if audioController != nil {
                Button {
                    syncActive.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: syncActive ? "waveform.badge.checkmark" : "waveform")
                            .scaledFont(11)
                        Text(syncActive ? "Synced" : "Sync")
                            .scaledFont(11, weight: .medium)
                    }
                    .foregroundStyle(syncActive ? NDS.brand : NDS.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(syncActive ? NDS.brand.opacity(0.10) : NDS.fieldBg,
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(
                        syncActive ? NDS.brand.opacity(0.3) : NDS.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(syncActive ? "Auto-scroll with audio" : "Manual scroll")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Scroll body

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSegments) { seg in
                        TranscriptRow(
                            segment: seg,
                            isActive: seg.id == activeSegmentID,
                            speakerColor: speakerColors[seg.speaker] ?? NDS.brand,
                            searchHighlight: searchText,
                            hasAudio: audioController != nil
                        ) {
                            // Tap timestamp → seek
                            audioController?.commitScrub()  // flush any pending
                            audioController?.scrub(to: seg.startSeconds)
                            audioController?.commitScrub()
                        }
                        .id(seg.id)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .onChange(of: activeSegmentID) { _, newID in
                guard syncActive, let id = newID,
                      audioController?.isPlaying == true else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyTranscriptView: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform").scaledFont(36).foregroundStyle(NDS.textTertiary)
            Text("No transcript").font(.headline)
            Text("This meeting has no transcript yet. Start a Transcribe Now job to generate one.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Data

    private var filteredSegments: [TranscriptSegment] {
        var result = segments
        if let spk = selectedSpeaker { result = result.filter { $0.speaker == spk } }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.text.lowercased().contains(q) || $0.speaker.lowercased().contains(q) }
        }
        return result
    }

    private func parse() {
        let parsed = TranscriptParser.parse(rawTranscript)
        segments = parsed
        let spkList = parsed.map(\.speaker).reduce(into: [String]()) { arr, s in
            if !arr.contains(s) { arr.append(s) }
        }
        speakers = spkList
        // Deterministic colors per speaker from NDS palette
        speakerColors = Dictionary(uniqueKeysWithValues: spkList.enumerated().map { i, s in
            (s, speakerColor(for: s, index: i))
        })
    }

    private func speakerColor(for speaker: String, index: Int) -> Color {
        // Index-based color so "Me" is always blue, "Them" is green, etc.
        let colors: [Color] = [NDS.brand, .green, .orange, .teal, .pink, .cyan]
        return colors[index % colors.count]
    }

    private func updateActiveSegment() {
        guard let ctrl = audioController, ctrl.isPlaying else { return }
        let t = ctrl.currentTime
        // Find the last segment whose startSeconds ≤ currentTime
        if let seg = segments.last(where: { $0.startSeconds <= t }) {
            if seg.id != activeSegmentID { activeSegmentID = seg.id }
        }
    }
}

// MARK: - Individual transcript row

@available(macOS 14.0, *)
private struct TranscriptRow: View {
    let segment: TranscriptSegment
    let isActive: Bool
    let speakerColor: Color
    let searchHighlight: String
    let hasAudio: Bool
    let onSeek: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timestamp column (clickable if audio)
            Button {
                if hasAudio { onSeek() }
            } label: {
                HStack(spacing: 4) {
                    if hasAudio && isHovered {
                        Image(systemName: "play.fill")
                            .scaledFont(8)
                            .foregroundStyle(speakerColor)
                            .transition(.opacity)
                    }
                    Text(segment.timeLabel)
                        .font(.system(size: 11, weight: .medium).monospacedDigit()) // design-lint:allow
                        .foregroundStyle(hasAudio ? speakerColor.opacity(0.8) : NDS.textTertiary)
                }
                .frame(width: 68, alignment: .trailing)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
            .disabled(!hasAudio)

            // Active left bar
            Rectangle()
                .fill(isActive ? speakerColor : .clear)
                .frame(width: 2)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)

            // Speaker label
            Text(segment.speaker)
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(speakerColor)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)

            // Utterance text
            highlightedText
                .scaledFont(13)
                .foregroundStyle(NDS.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(isActive ? speakerColor.opacity(0.08) : (isHovered ? NDS.rowHover : .clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.08), value: isHovered)
    }

    private var highlightedText: Text {
        guard !searchHighlight.isEmpty else { return Text(segment.text) }
        let text = segment.text
        let q = searchHighlight.lowercased()
        var result = Text("")
        var remaining = text[...]
        while let range = remaining.range(of: q, options: .caseInsensitive) {
            result = result + Text(String(remaining[..<range.lowerBound]))
            result = result + Text(String(remaining[range]))
                .foregroundStyle(Color.yellow)
                .bold()
            remaining = remaining[range.upperBound...]
        }
        result = result + Text(String(remaining))
        return result
    }
}
