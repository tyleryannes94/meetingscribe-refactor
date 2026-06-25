import Foundation
import AVFoundation
import Vision
import CoreGraphics
import OSLog

/// Local, on-device understanding of a screen recording: samples frames at a
/// fixed cadence and runs Vision OCR over them to recover the on-screen text
/// (docs, slides, code, errors). No network — pure Vision framework. The text
/// it returns is combined with the audio transcript and fed to the local LLM
/// for the summary (see `OllamaService.analyzeScreenRecording`).
@available(macOS 14.0, *)
enum ScreenAnalyzer {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ScreenAnalyzer")

    /// One frame's worth of recognized text plus its timestamp.
    struct FrameText { let seconds: Double; let lines: [String] }

    /// Samples up to `maxFrames` frames (every `interval`s) and OCRs each.
    /// Writes the sampled PNGs to `framesDir` for an optional future vision pass.
    static func ocr(videoURL: URL,
                    framesDir: URL,
                    interval: Double = 2.0,
                    maxFrames: Int = 40) async -> [FrameText] {
        let asset = AVURLAsset(url: videoURL)
        let duration: Double
        do { duration = try await CMTimeGetSeconds(asset.load(.duration)) }
        catch { return [] }
        guard duration.isFinite, duration > 0 else { return [] }

        // Build the sample times, capping the count so a long recording stays cheap.
        let step = max(interval, duration / Double(maxFrames))
        var times: [Double] = []
        var t = 0.5
        while t < duration && times.count < maxFrames { times.append(t); t += step }
        if times.isEmpty { times = [min(0.5, duration / 2)] }

        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.4, preferredTimescale: 600)

        var out: [FrameText] = []
        for (idx, sec) in times.enumerated() {
            guard let cg = try? await gen.image(at: CMTime(seconds: sec, preferredTimescale: 600)).image
            else { continue }
            let name = String(format: "%06d.png", idx)
            ScreenshotCapturer.writePNG(cg, to: framesDir.appendingPathComponent(name))
            let lines = recognizeText(in: cg)
            if !lines.isEmpty { out.append(FrameText(seconds: sec, lines: lines)) }
        }
        log.info("OCR sampled \(times.count) frames, \(out.count) had text")
        return out
    }

    /// Synchronous Vision OCR on one frame; returns deduped, non-trivial lines.
    private static func recognizeText(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        let observations = request.results ?? []
        var lines: [String] = []
        var seen = Set<String>()
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip noise: empty, single chars, or low-confidence fragments.
            guard text.count >= 3, candidate.confidence > 0.3, !seen.contains(text) else { continue }
            seen.insert(text)
            lines.append(text)
        }
        return lines
    }

    /// Flattens OCR'd frames into a compact, deduped Markdown block of the
    /// distinct on-screen text — what the LLM reads alongside the transcript.
    static func onScreenTextMarkdown(_ frames: [FrameText]) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        for frame in frames {
            for line in frame.lines where !seen.contains(line.lowercased()) {
                seen.insert(line.lowercased())
                lines.append(line)
            }
        }
        // Bound the size we hand the model (keep the first ~400 distinct lines).
        return lines.prefix(400).joined(separator: "\n")
    }
}
