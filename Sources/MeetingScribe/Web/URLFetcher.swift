import Foundation
import OSLog

/// One fetched URL: the final URL after redirects, MIME type, HTML body, and
/// the `Etag` / `Last-Modified` headers so a future revisit can do a 304 check.
struct FetchedPage {
    var finalURL: URL
    var mimeType: String
    var html: String
    var etag: String?
    var lastModified: String?
    var bytesRead: Int
}

/// Foundation-only URL fetcher for the Brain Dump page. Used by the
/// `fetch_url` planner tool and by direct paste-to-attach in the composer.
///
/// Constraints kept tight on purpose:
///   - HTTPS only (Ollama/local exemption is handled by `EgressPolicy`).
///   - User-Agent looks like a real desktop browser so we don't get the
///     "you look like a bot" landing pages.
///   - 12 s timeout, 5 redirects max.
///   - 2 MB body cap — the planner can't usefully chew anything bigger, and a
///     runaway page (CDN-served video, infinite-scroll archive) would otherwise
///     ruin a single fetch.
enum URLFetcher {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "URLFetcher")
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 MeetingScribe-BrainDump"
    private static let maxBodyBytes = 2 * 1024 * 1024 // 2 MB
    private static let defaultTimeout: TimeInterval = 12

    enum FetchError: Error, LocalizedError {
        case invalidURL
        case nonHTTPResponse
        case httpStatus(Int)
        case bodyTooLarge(Int)
        case notHTML(String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:           return "That URL doesn't look valid."
            case .nonHTTPResponse:      return "Server returned a non-HTTP response."
            case .httpStatus(let c):    return "Server returned HTTP \(c)."
            case .bodyTooLarge(let n):  return "Page was too large to read (\(n / 1024) KB)."
            case .notHTML(let m):       return "Expected HTML, got \(m)."
            case .network(let m):       return m
            }
        }
    }

    static func fetch(_ url: URL, timeout: TimeInterval = defaultTimeout) async throws -> FetchedPage {
        try EgressPolicy.assertGenericOutboundAllowed(url)

        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                     forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw FetchError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw FetchError.nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw FetchError.httpStatus(http.statusCode)
        }
        if data.count > maxBodyBytes {
            throw FetchError.bodyTooLarge(data.count)
        }
        let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "text/html").lowercased()
        guard mime.contains("text/html") || mime.contains("xml") || mime.contains("text/plain") else {
            throw FetchError.notHTML(mime)
        }

        let encoding = Self.encoding(fromMime: mime)
        let html = String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        return FetchedPage(
            finalURL: http.url ?? url,
            mimeType: mime,
            html: html,
            etag: http.value(forHTTPHeaderField: "Etag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            bytesRead: data.count
        )
    }

    /// `Content-Type: text/html; charset=ISO-8859-1` → `.isoLatin1`. Falls back
    /// to UTF-8 when the header doesn't carry a charset or it's something we
    /// don't recognise.
    private static func encoding(fromMime mime: String) -> String.Encoding {
        let parts = mime.split(separator: ";")
        for raw in parts {
            let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix("charset=") else { continue }
            let charset = String(trimmed.dropFirst("charset=".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            switch charset {
            case "utf-8", "utf8":        return .utf8
            case "iso-8859-1", "latin1": return .isoLatin1
            case "windows-1252":         return .windowsCP1252
            case "us-ascii", "ascii":    return .ascii
            default: break
            }
        }
        return .utf8
    }
}
