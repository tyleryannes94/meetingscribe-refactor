import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    // MARK: - Audio

    @ViewBuilder
var audioBar: some View {
        if !audioURLs.isEmpty {
            AudioPlayerView(title: audioURLs.count > 1 ? "Audio (mic + system)" : "Audio",
                            urls: audioURLs)
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
var transcriptBody: some View {
        switch mode {
        case .live:
            LiveTranscriptScroll(transcriber: manager.liveTranscriber,
                                 recordingStartedAt: liveStartedAt)
        case .upcoming(let m):
            // Pre-meeting brief: prior meetings with same attendees + open
            // action items from those meetings. Far more useful than the
            // old "No transcript yet" placeholder.
            PreMeetingBriefView(meeting: m)
                .environmentObject(manager)
        case .past:
            if transcript.isEmpty {
                if bodyLoaded {
                    placeholder(systemImage: "waveform",
                                title: "No transcript",
                                message: "This meeting didn't capture audio, or transcription failed.")
                } else {
                    MSSkeleton(lines: 8).padding(24)   // loading, not empty (PP-1)
                }
            } else {
                // Use the navigable sync view when transcript has structured
                // speaker/timestamp data. Falls back gracefully if format is plain prose.
                TranscriptSyncView(rawTranscript: transcript)
            }
        }
    }

    /// When recording started (used by the live transcript pane to count down
    /// to the next 5-minute chunk).
var liveStartedAt: Date? {
        if case .recording(_, let at) = manager.state { return at }
        return nil
    }
}

/// Auto-scrolling live transcript pane. Shows the finalized 5-minute chunks
/// plus a footer with the countdown to the next chunk.
@available(macOS 14.0, *)
struct LiveTranscriptScroll: View {
    @ObservedObject var transcriber: LiveTranscriber
    let recordingStartedAt: Date?
    @State private var now: Date = Date()

    /// 5 minutes — must match `chunkSeconds` in AudioRecorder.swift.
    private let chunkSeconds: TimeInterval = 300

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let err = transcriber.lastError {
                        errorBanner(err)
                    }

                    if transcriber.segments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recording — first transcript chunk in \(countdownString())")
                                .font(.callout).foregroundStyle(.secondary)
                            Text("MeetingScribe transcribes the call in 5-minute chunks. The first chunk drops in once 5 minutes of audio is captured.")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding()
                    } else {
                        ForEach(transcriber.segments) { seg in
                            HStack(alignment: .top, spacing: 8) {
                                Text(seg.speaker)
                                    .font(.caption.bold())
                                    .frame(width: 50, alignment: .leading)
                                    .foregroundStyle(seg.speaker == "Me" ? .blue : .green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(seg.text).font(.body)
                                    Text("\(LiveTranscriber.format(seg.startSec)) – \(LiveTranscriber.format(seg.endSec))")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .id(seg.id)
                            .padding(.horizontal)
                        }
                        // Live "currently buffering" footer
                        HStack(spacing: 8) {
                            if transcriber.isProcessing {
                                ProgressView().controlSize(.small)
                                Text("Transcribing chunk…").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.secondary).font(.caption)
                                Text("Next chunk in \(countdownString())")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: transcriber.segments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .onReceive(tick) { now = $0 }
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Live transcription error").font(.caption.bold())
                Text(err).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
    }

    private func countdownString() -> String {
        guard let start = recordingStartedAt else { return "5:00" }
        let elapsed = now.timeIntervalSince(start)
        // Time since last chunk close. If we have N transcribed segments, the
        // recording-elapsed-seconds at the last chunk boundary is the max endSec
        // of all transcribed segments. Otherwise the chunk count is 0.
        let lastBoundary = transcriber.lastTranscribedSecond > 0
            ? transcriber.lastTranscribedSecond
            : 0
        let intoCurrentChunk = max(0, elapsed - lastBoundary)
        let remaining = max(0, chunkSeconds - intoCurrentChunk)
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Tab order is intentional: Summary first (post-meeting review),
/// then Transcript, then My Notes, then Ask AI.
/// For live/upcoming meetings the default is Transcript or My Notes
/// (see UnifiedMeetingDetail.applySmartTabDefault).
enum DetailTab: String, CaseIterable, Identifiable {
    case summary, transcript, notes, chat
    var id: String { rawValue }
    var label: String {
        switch self {
        case .summary:    return "Summary"
        case .transcript: return "Transcript"
        case .notes:      return "My Notes"
        case .chat:       return "Ask AI"
        }
    }
    var systemImage: String {
        switch self {
        case .summary:    return "sparkles"
        case .transcript: return "text.alignleft"
        case .notes:      return "note.text"
        case .chat:       return "bubble.left.and.sparkles"
        }
    }
}

/// Renders markdown for the transcript/summary tabs.
/// Uses MarkdownEditor in read-only mode so block-level constructs
/// (## headings, --- dividers, indented lists) render correctly.
/// For long transcripts this is significantly more performant than
/// AttributedString.init(markdown:) which blocks synchronously.
@available(macOS 14.0, *)
struct MarkdownText: View {
    let raw: String
    init(_ raw: String) { self.raw = raw }
    var body: some View {
        MarkdownEditor(text: .constant(raw), isEditable: false)
    }
}
