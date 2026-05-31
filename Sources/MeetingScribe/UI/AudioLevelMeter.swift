import SwiftUI

/// Whispr-Flow / Granola-style audio activity indicator.
///
/// Renders N vertical bars whose heights animate with the latest RMS reading
/// from each audio source. Each bar has its own random "wave offset" so the
/// motion looks natural rather than uniformly synchronized — gives the
/// impression of live audio rather than a single flat meter.
@available(macOS 14.0, *)
struct AudioLevelMeter: View {
    /// Latest mic level (0...1).
    let micLevel: Float
    /// Latest system-audio level (0...1).
    let systemLevel: Float
    /// Whether the recording is currently active. When false, bars settle to a
    /// quiet idle wiggle.
    var isActive: Bool = true
    /// Number of bars to draw.
    var bars: Int = 9
    /// Maximum bar height in points.
    var height: CGFloat = 24
    /// Single-channel mode: when set, every bar tracks this one level and uses
    /// `monoTint`. Used by Direction A's split MIC / SYS rows on the live card.
    var monoLevel: Float? = nil
    var monoTint: Color? = nil

    /// Combined mic + system meter (default).
    init(micLevel: Float, systemLevel: Float, isActive: Bool = true,
         bars: Int = 9, height: CGFloat = 24) {
        self.micLevel = micLevel
        self.systemLevel = systemLevel
        self.isActive = isActive
        self.bars = bars
        self.height = height
    }

    /// Single-channel meter — one source, one tint.
    init(level: Float, tint: Color, isActive: Bool = true,
         bars: Int = 9, height: CGFloat = 24) {
        self.micLevel = level
        self.systemLevel = level
        self.isActive = isActive
        self.bars = bars
        self.height = height
        self.monoLevel = level
        self.monoTint = tint
    }

    var body: some View {
        // TimelineView drives the wiggle animation without a RunLoop timer.
        // The schedule pauses when the view is offscreen (default behavior).
        TimelineView(.animation(minimumInterval: 0.08, paused: !isActive)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate / 0.08
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(barColor(i))
                        .frame(width: 3, height: barHeight(i, phase: phase))
                        .animation(.spring(response: 0.18, dampingFraction: 0.55),
                                   value: barHeight(i, phase: phase))
                }
            }
            .frame(height: height)
            // Purely decorative — VoiceOver should skip the individual bars.
            .accessibilityHidden(true)
        }
    }

    /// Combines mic + system levels; mic-dominated bars on the left, system on
    /// the right, with overlap in the middle. `phase` is the current animation
    /// phase derived from the TimelineView date.
    private func barHeight(_ i: Int, phase: Double) -> CGFloat {
        let total = Float(bars)
        let pos = Float(i)
        // Triangular mix: bar 0 is all-mic, bar N-1 is all-system.
        let micWeight  = max(0, 1 - pos / total)
        let sysWeight  = max(0, pos / total)
        let blended = monoLevel.map { max(0.02, $0) }
            ?? max(0.02, micLevel * micWeight + systemLevel * sysWeight)

        // Add a small per-bar wiggle that keeps things visually alive even
        // when the input is flat.
        let wigglePhase = phase * 0.55 + Double(i) * 0.6
        let wiggle = isActive ? CGFloat(abs(sin(wigglePhase)) * 0.12) : 0

        // Audio levels live in roughly 0...0.3 for normal speech. Scale to
        // visible range with a square-root for perceptual evenness.
        let scaled = CGFloat(sqrt(blended)) * 1.7 + wiggle
        return max(3, min(height, scaled * height))
    }

    private func barColor(_ i: Int) -> Color {
        if let monoTint { return monoTint }
        // Center bars use the accent color (mixed mic+system), outer bars
        // shade slightly toward the source they represent.
        let total = Float(bars)
        let pos = Float(i)
        let micShare = 1 - pos / total
        if micShare > 0.7      { return .blue.opacity(0.85) }
        else if micShare > 0.3 { return NDS.brand }
        else                   { return .green.opacity(0.85) }
    }
}
