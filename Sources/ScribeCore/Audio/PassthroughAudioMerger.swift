import Foundation
@preconcurrency import AVFoundation
import OSLog

/// Concatenates multiple AAC `.m4a` audio files into one output `.m4a`.
///
/// History: an early version used `AVAssetExportPresetAppleM4A`, which always
/// re-encoded (tens of seconds of waste on long meetings — audit 3.3). It was
/// replaced by a hand-rolled `AVAssetReader`→`AVAssetWriter` passthrough mux,
/// but that called `requestMediaDataWhenReady` once per segment — and that API
/// may only be called ONCE per writer input. The second call threw an uncaught
/// AVFoundation `NSException`, so EVERY multi-segment merge crashed the app with
/// SIGABRT (single-segment recordings took a plain copy path and were unaffected,
/// which is why the bug hid). It also fought AAC encoder priming / edit lists.
///
/// Current approach: build an `AVMutableComposition`, insert each segment's audio
/// track in order (which respects per-segment edit lists / priming), and export
/// once. We prefer `AVAssetExportPresetPassthrough` (no re-encode); if the
/// sources aren't passthrough-compatible we fall back to `AVAssetExportPresetAppleM4A`
/// (re-encode) so recovery still produces a valid, complete file. Fail-soft: a
/// single unreadable segment is skipped with a warning rather than aborting.
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
        guard !segments.isEmpty else { throw MergeError.noSegments }

        // Concatenate every segment into one composition track, in order.
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MergeError.writerInit("could not add composition audio track")
        }

        var cursor: CMTime = .zero
        var inserted = 0
        for url in segments {
            do {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard let track = tracks.first else {
                    throw MergeError.readerInit(url, "no audio track")
                }
                let duration = try await asset.load(.duration)
                guard duration.isValid, duration > .zero else {
                    throw MergeError.readerInit(url, "zero/invalid duration")
                }
                try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                              of: track, at: cursor)
                cursor = cursor + duration
                inserted += 1
            } catch {
                // Soft-fail on a single bad segment so a crash-truncated file at
                // the end of a long meeting doesn't lose the rest.
                log.error("Skipping bad segment \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                AppLog.warn("AudioMerger", "Skipped segment during merge",
                            ["url": url.path, "error": error.localizedDescription])
            }
        }
        guard inserted > 0 else { throw MergeError.writerFailed("no readable segments") }

        // Prefer passthrough (no re-encode); fall back to re-encode if the
        // sources aren't passthrough-compatible, so recovery never fails outright.
        let (status, error) = await export(composition, to: output,
                                           preset: AVAssetExportPresetPassthrough)
        if status != .completed {
            log.notice("Passthrough export failed (\(error?.localizedDescription ?? "unknown", privacy: .public)); retrying with re-encode.")
            let (status2, error2) = await export(composition, to: output,
                                                 preset: AVAssetExportPresetAppleM4A)
            if status2 != .completed {
                throw MergeError.writerFailed(error2?.localizedDescription
                                              ?? error?.localizedDescription ?? "unknown")
            }
        }
        log.info("Merged \(inserted) segments → \(output.lastPathComponent, privacy: .public) (\(cursor.seconds, format: .fixed(precision: 1))s)")
    }

    /// Runs one export pass with the given preset. Removes any prior output
    /// first. Returns the terminal status + error (never throws).
    private static func export(_ composition: AVMutableComposition, to output: URL,
                               preset: String) async -> (AVAssetExportSession.Status, Error?) {
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            return (.failed, MergeError.writerInit("export session init (\(preset))"))
        }
        session.outputURL = output
        session.outputFileType = .m4a
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        return (session.status, session.error)
    }
}
