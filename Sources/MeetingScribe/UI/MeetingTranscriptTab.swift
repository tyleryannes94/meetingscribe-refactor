import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    // MARK: - Audio

    @ViewBuilder
    var audioBar: some View {
        if !audioURLs.isEmpty || !importedRecordingURLs.isEmpty {
            VStack(spacing: 0) {
                if !audioURLs.isEmpty {
                    AudioPlayerBar(title: audioURLs.count > 1 ? "Recording (mic + system)" : "Recording",
                                   controller: audioController)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }
                ForEach(Array(importedRecordingURLs.enumerated()), id: \.offset) { idx, url in
                    Divider()
                    AudioPlayerView(title: "Imported Recording \(idx + 1)", urls: [url])
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    /// U2-2: pull a search query carried from a search hit, seed the
    /// transcript find bar, and scroll the canvas to the transcript section.
    /// (Pre-M10 this also set `tab = .transcript`; the canvas now shows
    /// every section in one scroll column, so a `scrollTo` does the same
    /// job without dropping the user's place in the rest of the meeting.)
    func consumeTranscriptQuery() {
        guard let q = router.pendingTranscriptQuery, !q.isEmpty else { return }
        transcriptSearchSeed = q
        pendingScrollAnchor = .transcript
        router.pendingTranscriptQuery = nil
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
        // D4-1: translate raw engine stderr (e.g. "whisper-cli failed (1)… run
        // ./scripts/setup.sh") into a plain diagnosis; the raw text lives behind
        // "Details", never leading.
        MSErrorState(presented: ErrorPresenter.present(err), raw: err)
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

/// Renders markdown for the transcript/summary panes.
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
