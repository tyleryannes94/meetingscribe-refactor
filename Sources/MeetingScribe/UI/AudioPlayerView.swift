import SwiftUI
@preconcurrency import AVFoundation
import Combine

/// Apple Voice Memos-style audio player:
///   ⏪15  ⏯  ⏩15  •  scrubbable progress bar  •  current / total time
/// Optionally accepts multiple URLs and stitches them into a single queue.
struct AudioPlayerView: View {
    let title: String?

    @StateObject private var controller: AudioPlayerController

    init(title: String? = nil, urls: [URL]) {
        self.title = title
        _controller = StateObject(wrappedValue: AudioPlayerController(urls: urls))
    }

    /// Convenience for a single audio file.
    init(title: String? = nil, url: URL) {
        self.init(title: title, urls: [url])
    }

    var body: some View {
        // C1-3: render the controls from the owned controller. Standalone
        // callers (e.g. voice notes) own their player here; the meeting detail
        // hosts a shared controller and drives `AudioPlayerBar` directly so the
        // transcript's tap-to-seek and the visible player are the same player.
        AudioPlayerBar(title: title, controller: controller)
            .onDisappear { controller.release() }
    }
}

/// The audio-transport UI bound to an externally-owned controller. Used both by
/// `AudioPlayerView` (which owns the controller) and by the meeting detail,
/// which shares one controller with `TranscriptSyncView` so tap-to-seek works.
@available(macOS 14.0, *)
struct AudioPlayerBar: View {
    let title: String?
    @ObservedObject var controller: AudioPlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 14) {
                Button { controller.skip(-15) } label: {
                    Image(systemName: "gobackward.15").font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!controller.ready)
                .accessibilityLabel("Skip back 15 seconds")

                Button { controller.togglePlay() } label: {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .scaledFont(30)
                }
                .buttonStyle(.borderless)
                .disabled(!controller.ready)
                .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")

                Button { controller.skip(15) } label: {
                    Image(systemName: "goforward.15").font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!controller.ready)
                .accessibilityLabel("Skip forward 15 seconds")

                // FIX: scrub(to:) updates the display only — no AVPlayer seek
                // during drag (which was calling removeAllItems() every frame,
                // causing the restart-on-scrub bug). commitScrub() fires once
                // when the drag ends via onEditingChanged.
                Slider(value: Binding(get: { controller.currentTime },
                                      set: { controller.scrub(to: $0) }),
                       in: 0...max(0.01, controller.duration),
                       onEditingChanged: { editing in
                           controller.scrubbing = editing
                           if !editing { controller.commitScrub() }
                       })
                    .disabled(!controller.ready)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(format(controller.currentTime)) of \(format(controller.duration))")

                Text("\(format(controller.currentTime)) / \(format(controller.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .trailing)
            }
            if let err = controller.loadError {
                Text(err).font(.caption2).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func format(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, r) }
        return String(format: "%d:%02d", m, r)
    }
}

@available(macOS 14.0, *)
@MainActor
final class AudioPlayerController: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var ready: Bool = false
    @Published var loadError: String?
    var scrubbing = false

    private let player = AVPlayer()
    private var urls: [URL]
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(urls: [URL]) {
        self.urls = urls
        player.volume = 1.0
        attachObservers()
        Task { await buildComposition() }
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
    }

    /// Overlay every source file on ONE composition timeline so a meeting's mic
    /// + system tracks play together (a real conversation) instead of one after
    /// the other. A single-file voice note is just a one-track composition.
    /// Replaces the old sequential AVQueuePlayer and its fragile queue-rebuild
    /// seeking — and explicitly sets volume so playback is never silent.
    private func buildComposition() async {
        let composition = AVMutableComposition()
        var maxDuration = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            do {
                guard let src = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let dur = try await asset.load(.duration)
                guard dur.isNumeric, dur > .zero else { continue }
                guard let dest = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try dest.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero)
                if dur > maxDuration { maxDuration = dur }
            } catch {
                loadError = error.localizedDescription
            }
        }
        let total = CMTimeGetSeconds(maxDuration)
        guard total > 0 else {
            ready = false
            if loadError == nil { loadError = "No playable audio in this recording." }
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
        player.volume = 1.0
        duration = total
        ready = true
    }

    private func attachObservers() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.scrubbing { return }
            let t = self.player.currentTime()
            if t.isNumeric { self.currentTime = CMTimeGetSeconds(t) }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player.pause()
            self.isPlaying = false
            self.seek(to: 0)
        }
    }

    func togglePlay() {
        guard ready else { return }
        if isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func skip(_ seconds: TimeInterval) {
        seek(to: max(0, min(duration, currentTime + seconds)))
    }

    /// Visual-only update during drag — no AVPlayer interaction, so the slider
    /// doesn't fire a seek on every tick.
    func scrub(to time: TimeInterval) {
        currentTime = time
    }

    /// Commit the seek when the drag ends. Called once per scrub gesture.
    func commitScrub() {
        seek(to: currentTime)
    }

    /// Single-timeline seek (the composition is one item, so no queue juggling).
    private func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func stop() {
        player.pause()
        isPlaying = false
    }

    /// Swap in a new set of source files and rebuild the composition. Used by
    /// the meeting detail when the user switches meetings while one shared
    /// controller backs both the transport bar and the synced transcript
    /// (C1-3). No-ops when the URLs are unchanged so playback isn't restarted.
    func reload(urls newURLs: [URL]) {
        guard newURLs != urls else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        ready = false
        loadError = nil
        urls = newURLs
        guard !newURLs.isEmpty else { return }
        Task { await buildComposition() }
    }

    /// Fully tears down the player: removes observers and drops the current
    /// item so its decoded audio buffers can be reclaimed. Call from
    /// `.onDisappear` so switching meetings doesn't accumulate ghost players.
    func release() {
        if let t = timeObserver {
            player.removeTimeObserver(t)
            timeObserver = nil
        }
        if let e = endObserver {
            NotificationCenter.default.removeObserver(e)
            endObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        ready = false
    }
}
