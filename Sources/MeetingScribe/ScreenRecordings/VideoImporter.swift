import Foundation
import OSLog

/// Fetches a video from a web URL into a temp file so it can be imported and
/// analyzed. Two free paths:
///   1. `yt-dlp` (if installed) — handles YouTube / Vimeo / most streaming sites.
///   2. Direct download — for URLs that point straight at a media file
///      (`.mp4` / `.mov` / `.webm` / …).
/// This is a user-initiated fetch; it is intentionally NOT routed through the
/// local-only `EgressPolicy` (that guards the AI pipeline, not user downloads).
enum VideoImporter {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "VideoImporter")

    enum ImportError: LocalizedError {
        case badURL
        case notDirectMedia
        case download(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "That doesn't look like a valid URL."
            case .notDirectMedia:
                return "That link isn't a direct video file. Install yt-dlp (`brew install yt-dlp`) to import from YouTube and other sites, or paste a direct .mp4/.mov link."
            case .download(let m): return "Download failed: \(m)"
            }
        }
    }

    /// Resolves a URL string to a local temp video file. Caller imports + deletes.
    static func fetch(_ urlString: String) async throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw ImportError.badURL
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MSImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        if let ytdlp = ytDlpPath() {
            return try await runYtDlp(ytdlp, url: trimmed, into: tmp)
        }
        // No yt-dlp: only direct media links work.
        let ext = url.pathExtension.lowercased()
        guard ScreenRecordingStore.importableVideoExtensions.contains(ext) else {
            throw ImportError.notDirectMedia
        }
        return try await directDownload(url, into: tmp, ext: ext)
    }

    // MARK: - yt-dlp

    static func ytDlpPath() -> String? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp",
                          "/opt/homebrew/opt/yt-dlp/bin/yt-dlp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func runYtDlp(_ binary: String, url: String, into dir: URL) async throws -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        // Prefer an mp4 ≤1080p so the file stays reasonable and AVFoundation-friendly.
        proc.arguments = ["-f", "mp4[height<=1080]/best[height<=1080]/best",
                          "-o", dir.appendingPathComponent("video.%(ext)s").path,
                          "--no-playlist", url]
        proc.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async { proc.waitUntilExit(); cont.resume() }
        }
        guard proc.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ImportError.download("yt-dlp exited \(proc.terminationStatus). \(err.suffix(300))")
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        guard let file = files.first(where: { $0.lastPathComponent.hasPrefix("video.") }) else {
            throw ImportError.download("yt-dlp produced no file.")
        }
        return file
    }

    // MARK: - Direct download

    private static func directDownload(_ url: URL, into dir: URL, ext: String) async throws -> URL {
        do {
            let (tmpURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImportError.download("HTTP \(http.statusCode)")
            }
            let dest = dir.appendingPathComponent("video.\(ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            return dest
        } catch let e as ImportError {
            throw e
        } catch {
            throw ImportError.download(error.localizedDescription)
        }
    }
}
