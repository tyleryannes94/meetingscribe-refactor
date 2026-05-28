import SwiftUI
import AVFoundation
import Combine

/// Apple Voice Memos-style audio player:
///   ⏪15  ⏯  ⏩15  •  scrubbable progress bar  •  current / total time
/// Optionally accepts multiple URLs and stitches them into a single queue.
@available(macOS 14.0, *)
struct AudioPlayerView: View {
    let title: String?
    let urls: [URL]

    @StateObject private var controller: AudioPlayerController

    init(title: String? = nil, urls: [URL]) {
        self.title = title
        self.urls = urls
        _controller = StateObject(wrappedValue: AudioPlayerController(urls: urls))
    }

    /// Convenience for a single audio file.
    init(title: String? = nil, url: URL) {
        self.init(title: title, urls: [url])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 14) {
                Button { controller.skip(-15) } label: {
                    Image(systemName: "gobackward.15").font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!controller.ready)

                Button { controller.togglePlay() } label: {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.borderless)
                .disabled(!controller.ready)

                Button { controller.skip(15) } label: {
                    Image(systemName: "goforward.15").font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!controller.ready)

                Slider(value: Binding(get: { controller.currentTime },
                                      set: { controller.scrub(to: $0) }),
                       in: 0...max(0.01, controller.duration),
                       onEditingChanged: { editing in controller.scrubbing = editing })
                    .disabled(!controller.ready)

                Text("\(format(controller.currentTime)) / \(format(controller.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .onDisappear { controller.release() }
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
    var scrubbing = false

    private let player: AVQueuePlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: AnyCancellable?
    private let items: [AVPlayerItem]

    init(urls: [URL]) {
        self.items = urls.map { AVPlayerItem(url: $0) }
        self.player = AVQueuePlayer(items: items)
        self.player.actionAtItemEnd = .advance

        Task { await measureDuration() }
        attachObservers()
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
    }

    private func attachObservers() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.scrubbing { return }
            self.currentTime = self.absoluteCurrentTime()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // If we ran past the LAST queued item, hop back to start and pause.
            if self.player.currentItem == nil {
                self.player.pause()
                self.isPlaying = false
                self.seekAbsolute(0)
            }
        }
    }

    private func measureDuration() async {
        var total: TimeInterval = 0
        for item in items {
            do {
                let asset = item.asset
                let cm = try await asset.load(.duration)
                if cm.isNumeric {
                    total += CMTimeGetSeconds(cm)
                }
            } catch {
                // Skip
            }
        }
        await MainActor.run {
            self.duration = total
            self.ready = total > 0
        }
    }

    func togglePlay() {
        if isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func skip(_ seconds: TimeInterval) {
        seekAbsolute(max(0, min(duration, absoluteCurrentTime() + seconds)))
    }

    func scrub(to time: TimeInterval) {
        currentTime = time
        seekAbsolute(time)
    }

    func stop() {
        player.pause()
        isPlaying = false
    }

    /// Fully tears down the player: removes observers, empties the queue, and
    /// drops AVPlayerItem references so their decoded audio buffers can be
    /// reclaimed by ARC. Call from `.onDisappear` of the view that owns this
    /// controller so switching meetings doesn't accumulate ghost players.
    func release() {
        if let t = timeObserver {
            player.removeTimeObserver(t)
            timeObserver = nil
        }
        if let e = endObserver {
            NotificationCenter.default.removeObserver(e)
            endObserver = nil
        }
        statusObserver?.cancel()
        statusObserver = nil
        player.pause()
        player.removeAllItems()
        isPlaying = false
        ready = false
    }

    /// Returns the player's time relative to the START of the first queued
    /// item — accounting for items already finished.
    private func absoluteCurrentTime() -> TimeInterval {
        guard let current = player.currentItem,
              let idx = items.firstIndex(of: current) else { return 0 }
        var t: TimeInterval = 0
        for i in 0..<idx {
            let d = items[i].duration
            if d.isNumeric { t += CMTimeGetSeconds(d) }
        }
        let cur = player.currentTime()
        if cur.isNumeric { t += CMTimeGetSeconds(cur) }
        return t
    }

    /// Seeks to an absolute time across the queue: figures out which item to
    /// jump to and the offset within it.
    private func seekAbsolute(_ time: TimeInterval) {
        var remaining = time
        for (i, item) in items.enumerated() {
            let d = item.duration
            let dSec = d.isNumeric ? CMTimeGetSeconds(d) : 0
            if remaining <= dSec || i == items.count - 1 {
                // Tear down the queue and rebuild from item `i` so we land on it.
                player.removeAllItems()
                for j in i..<items.count {
                    // Items can only be inserted once. If they were already in the
                    // queue, recreate them by URL.
                    if let urlAsset = items[j].asset as? AVURLAsset {
                        let fresh = AVPlayerItem(url: urlAsset.url)
                        player.insert(fresh, after: nil)
                    } else {
                        player.insert(items[j], after: nil)
                    }
                }
                let cm = CMTime(seconds: max(0, remaining), preferredTimescale: 600)
                player.currentItem?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
                return
            }
            remaining -= dSec
        }
    }
}
