import Foundation
import AVFoundation

/// Lightweight audio-buffer analysis used by the silence-detection watchdog.
/// Computes RMS amplitude over the first channel of a PCM buffer in whichever
/// common format the source happens to use (Float32 for mic via AVAudioEngine,
/// Int16 for system audio via ScreenCaptureKit). No allocations on the hot
/// path beyond the buffer pointer access.
enum AudioBufferAnalysis {
    /// Returns RMS amplitude in the 0...1 range (where 1.0 == full-scale).
    /// Returns 0 if the buffer has no readable channel data.
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        if let int16 = buffer.int16ChannelData?[0] {
            var sumSq: Float = 0
            let scale = Float(Int16.max)
            for i in 0..<frames {
                let v = Float(int16[i]) / scale
                sumSq += v * v
            }
            return (sumSq / Float(frames)).squareRoot()
        }

        if let float = buffer.floatChannelData?[0] {
            var sumSq: Float = 0
            for i in 0..<frames {
                let v = float[i]
                sumSq += v * v
            }
            return (sumSq / Float(frames)).squareRoot()
        }

        if let int32 = buffer.int32ChannelData?[0] {
            var sumSq: Float = 0
            let scale = Float(Int32.max)
            for i in 0..<frames {
                let v = Float(int32[i]) / scale
                sumSq += v * v
            }
            return (sumSq / Float(frames)).squareRoot()
        }

        return 0
    }
}
