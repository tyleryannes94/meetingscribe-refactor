import Foundation
@preconcurrency import AVFoundation
import OSLog

/// Concatenates multiple AAC `.m4a` audio files into one output `.m4a`
/// WITHOUT re-encoding. Was previously `AVAssetExportPresetAppleM4A`, which
/// always re-encoded the entire concatenated stream — tens of seconds to
/// minutes of pure waste on long meetings (audit 3.3).
///
/// Approach: use `AVAssetReaderTrackOutput` with `outputSettings: nil` to
/// read packetized (compressed) samples, then write them straight through
/// `AVAssetWriterInput(mediaType: .audio, outputSettings: nil)`. The packet
/// payloads are copied byte-for-byte; only the container is rewritten.
///
/// Properly reports progress via fine-grained logging hooks. Fail-soft:
/// if a single segment can't be opened (corruption, write interrupted by a
/// crash), it's skipped with a logged warning rather than failing the whole
/// merge.
enum PassthroughAudioMerger {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe",
                                    category: "AudioMerger")

    enum MergeError: Error, LocalizedError {
        case noSegments
        case writerInit(String)
        case readerInit(URL, String)
        case writerFailed(String)
        case readerFailed(URL, String)

        var errorDescription: String? {
            switch self {
            case .noSegments: return "No segments to merge."
            case .writerInit(let m): return "AVAssetWriter init failed: \(m)"
            case .readerInit(let u, let m):
                return "AVAssetReader init failed for \(u.lastPathComponent): \(m)"
            case .writerFailed(let m): return "AVAssetWriter failed during merge: \(m)"
            case .readerFailed(let u, let m):
                return "AVAssetReader failed during merge for \(u.lastPathComponent): \(m)"
            }
        }
    }

    static func merge(segments: [URL], into output: URL) async throws {
        guard let first = segments.first else { throw MergeError.noSegments }

        // Use the first segment's format description to seed the writer.
        let firstAsset = AVURLAsset(url: first)
        let firstTracks = try await firstAsset.loadTracks(withMediaType: .audio)
        guard let firstTrack = firstTracks.first else {
            throw MergeError.readerInit(first, "no audio track")
        }
        let formatDescs = try await firstTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescs.first else {
            throw MergeError.readerInit(first, "no format descriptions")
        }

        try? FileManager.default.removeItem(at: output)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
        } catch {
            throw MergeError.writerInit(error.localizedDescription)
        }
        // `outputSettings: nil` + `sourceFormatHint: formatDesc` = passthrough.
        let writerInput = AVAssetWriterInput(mediaType: .audio,
                                             outputSettings: nil,
                                             sourceFormatHint: formatDesc)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw MergeError.writerInit(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        var cursor: CMTime = .zero
        let appendQueue = DispatchQueue(label: "MeetingScribe.Merger.append")

        for url in segments {
            do {
                let written = try await appendSegment(url: url,
                                                       to: writerInput,
                                                       on: appendQueue,
                                                       startingAt: cursor)
                cursor = cursor + written
            } catch {
                // Soft-fail on a single bad segment so a crash-truncated
                // file at the end of a long meeting doesn't lose the rest.
                log.error("Skipping bad segment \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                AppLog.warn("AudioMerger", "Skipped segment during merge",
                            ["url": url.path, "error": error.localizedDescription])
            }
        }

        writerInput.markAsFinished()

        let finalStatus = await withCheckedContinuation { (cont: CheckedContinuation<AVAssetWriter.Status, Never>) in
            writer.finishWriting {
                cont.resume(returning: writer.status)
            }
        }
        if finalStatus == .failed {
            throw MergeError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        log.info("Merged \(segments.count) segments → \(output.lastPathComponent, privacy: .public) (\(cursor.seconds, format: .fixed(precision: 1))s)")
    }

    /// Reads one segment's packetized samples and appends them to the
    /// writer input, rebased so the segment starts at `startingAt`.
    /// Returns the duration of audio appended (so the caller can advance
    /// its cursor).
    private static func appendSegment(url: URL,
                                       to writerInput: AVAssetWriterInput,
                                       on queue: DispatchQueue,
                                       startingAt cursor: CMTime) async throws -> CMTime {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw MergeError.readerInit(url, "no audio track")
        }
        let duration = try await asset.load(.duration)

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw MergeError.readerInit(url, error.localizedDescription) }

        // outputSettings: nil → packetized passthrough (no decode).
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else {
            throw MergeError.readerInit(url, "reader can't add packetized output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw MergeError.readerInit(url, reader.error?.localizedDescription ?? "startReading failed")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        // Done — either end of stream or reader failed.
                        if reader.status == .completed {
                            cont.resume()
                        } else if reader.status == .failed {
                            cont.resume(throwing:
                                MergeError.readerFailed(url, reader.error?.localizedDescription ?? "unknown"))
                        } else {
                            cont.resume()
                        }
                        return
                    }
                    if let rebased = Self.rebase(sample, by: cursor) {
                        writerInput.append(rebased)
                    } else {
                        writerInput.append(sample)
                    }
                }
            }
        }

        return duration
    }

    /// Rebase a sample's PTS by `offset` so concatenated segments form a
    /// monotonic timeline. Returns nil on failure (caller falls back to
    /// the un-rebased buffer, which is occasionally good enough).
    private static func rebase(_ sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var infos = [CMSampleTimingInfo](repeating: .init(), count: Int(count))
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &infos, entriesNeededOut: nil)
        for i in 0..<infos.count {
            if infos[i].presentationTimeStamp.isValid {
                infos[i].presentationTimeStamp = infos[i].presentationTimeStamp + offset
            }
            if infos[i].decodeTimeStamp.isValid {
                infos[i].decodeTimeStamp = infos[i].decodeTimeStamp + offset
            }
        }
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                            sampleBuffer: sample,
                                                            sampleTimingEntryCount: count,
                                                            sampleTimingArray: infos,
                                                            sampleBufferOut: &out)
        return status == noErr ? out : nil
    }
}
