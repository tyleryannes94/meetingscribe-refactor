import Foundation
import AVFoundation
import OSLog

/// Receives audio buffers from an active capture, converts to 16 kHz mono int16,
/// and writes rolling WAV chunks (rotating every `chunkSeconds` of audio).
/// Each finished chunk is reported via `onChunkReady` so a downstream consumer
/// (e.g. whisper) can transcribe it immediately.
///
/// Threading: `append` is called from the audio capture thread. It converts
/// synchronously on the caller's thread (producing a buffer we own), then
/// dispatches the converted buffer to the writer's serial queue for disk I/O.
/// The source buffer is safe to read during the synchronous conversion because
/// audio taps don't reuse buffers until they return.
final class ChunkedAudioWriter {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ChunkWriter")

    private let dir: URL
    private let label: String
    private let chunkSeconds: Double
    private let outputFormat: AVAudioFormat
    private let samplesPerChunk: Int

    /// Called on the writer's queue when a chunk file is finalized.
    var onChunkReady: ((_ url: URL, _ index: Int, _ startSec: Double, _ endSec: Double) -> Void)?

    // Caller-thread state — only touched in `append` (one caller, serially):
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    // Disk queue state — only touched on `queue`:
    private let queue = DispatchQueue(label: "MeetingScribe.ChunkWriter")
    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var samplesInCurrent: Int = 0
    private var totalSamples: Int = 0
    private var chunkIndex: Int = 0
    private var chunkStartSec: Double = 0

    init(dir: URL, label: String, chunkSeconds: Double = 8) {
        self.dir = dir
        self.label = label
        self.chunkSeconds = chunkSeconds
        self.outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                          sampleRate: 16_000,
                                          channels: 1,
                                          interleaved: true)!
        self.samplesPerChunk = Int(chunkSeconds * 16_000)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Feed an input buffer from the capture thread. If the input already
    /// matches the target format (16 kHz mono int16), we skip the converter
    /// entirely — we still need our own copy of the bytes since the engine
    /// reuses the source buffer, but it's a single memcpy instead of a full
    /// format conversion.
    func append(_ buffer: AVAudioPCMBuffer) {
        // Fast path: input already 16 kHz mono int16 (e.g. ScreenCaptureKit
        // configured to match output). Just deep-copy and dispatch.
        if buffer.format.commonFormat == outputFormat.commonFormat &&
            buffer.format.sampleRate == outputFormat.sampleRate &&
            buffer.format.channelCount == outputFormat.channelCount &&
            buffer.format.isInterleaved == outputFormat.isInterleaved {
            if let copy = copyBuffer(buffer) {
                queue.async { [weak self] in self?._write(copy) }
            }
            return
        }

        if converter == nil || inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            inputFormat = buffer.format
        }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 128)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        var supplied = false
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            if supplied { outStatus.pointee = .endOfStream; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || outBuf.frameLength == 0 {
            if let e = error {
                log.error("Convert failed: \(e.localizedDescription, privacy: .public)")
            }
            return
        }
        // outBuf is fully owned by us — safe to ship to another queue.
        queue.async { [weak self] in self?._write(outBuf) }
    }

    /// Deep-copies a same-format buffer for safe handoff to the disk queue.
    private func copyBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: src.format,
                                          frameCapacity: src.frameLength) else { return nil }
        dst.frameLength = src.frameLength
        let frames = Int(src.frameLength)
        let bytesPerFrame = Int(src.format.streamDescription.pointee.mBytesPerFrame)
        // Interleaved int16 layout — single buffer in audioBufferList.
        if let s = src.audioBufferList.pointee.mBuffers.mData,
           let d = dst.mutableAudioBufferList.pointee.mBuffers.mData {
            memcpy(d, s, frames * bytesPerFrame)
        }
        return dst
    }

    /// Close out any partial trailing chunk and notify.
    func finalize(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?._rotate()
            completion?()
        }
    }

    // MARK: - Disk queue (queue-confined)

    private func _write(_ buffer: AVAudioPCMBuffer) {
        _ensureCurrentFile()
        do {
            try currentFile?.write(from: buffer)
            samplesInCurrent += Int(buffer.frameLength)
            totalSamples += Int(buffer.frameLength)
        } catch {
            log.error("Write failed: \(error.localizedDescription, privacy: .public)")
        }
        if samplesInCurrent >= samplesPerChunk {
            _rotate()
        }
    }

    private func _ensureCurrentFile() {
        guard currentFile == nil else { return }
        let filename = String(format: "%@-%04d.wav", label, chunkIndex)
        let url = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            currentFile = try AVAudioFile(forWriting: url,
                                          settings: settings,
                                          commonFormat: .pcmFormatInt16,
                                          interleaved: true)
            currentURL = url
            samplesInCurrent = 0
            chunkStartSec = Double(totalSamples) / 16_000.0
        } catch {
            log.error("Open chunk file failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func _rotate() {
        guard let url = currentURL else { return }
        // Closing the AVAudioFile finalizes the WAV header.
        currentFile = nil
        currentURL = nil
        let start = chunkStartSec
        let end = Double(totalSamples) / 16_000.0
        let index = chunkIndex
        chunkIndex += 1
        samplesInCurrent = 0
        onChunkReady?(url, index, start, end)
    }
}
