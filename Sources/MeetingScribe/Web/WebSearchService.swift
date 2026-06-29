import Foundation
import OSLog

/// Protocol every web-search backend conforms to. The Brain Dump planner
/// calls `search(_:limit:)` from its `web_search` tool; the concrete impl is
/// resolved lazily so a user with no key configured gets a clean "configure
/// the provider" message instead of a crashy nil-fetch.
protocol WebSearchProvider {
    /// Display name shown in the UI ("Tavily").
    var name: String { get }
    func search(_ query: String, limit: Int) async throws -> [WebSearchResult]
}

enum WebSearchError: Error, LocalizedError {
    case noProviderConfigured
    case missingAPIKey(provider: String)
    case http(Int, String)
    case decode(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "Web search is off. Turn it on in Integrations → Brain Dump and add a provider key."
        case .missingAPIKey(let provider):
            return "No API key set for \(provider). Add it in Integrations → Brain Dump."
        case .http(let c, let m):    return "Search HTTP \(c): \(m)"
        case .decode(let m):         return "Couldn't decode the search response: \(m)"
        case .network(let m):        return m
        }
    }
}

/// Factory that returns the currently-configured provider, or nil when web
/// search is unavailable. Callers can show "configure search" CTAs without
/// having to thread errors through.
enum WebSearchService {
    static func current() -> (any WebSearchProvider)? {
        guard AppSettings.shared.allowBrainDumpWebAccess else { return nil }
        switch AppSettings.shared.webSearchProvider {
        case "tavily":
            guard let key = AppSettings.shared.tavilyAPIKey, !key.isEmpty else { return nil }
            return TavilySearchProvider(apiKey: key)
        default:
            return nil
        }
    }
}

// MARK: - Tavily

/// Tavily web search. Simple JSON POST → typed results. Tavily's free tier is
/// the smallest setup-cost path for the Brain Dump page; the protocol seam
/// above lets a future Brave/Exa swap be a one-file change.
///
/// API: `POST https://api.tavily.com/search`
///   body: { api_key, query, search_depth: "basic", max_results }
///   response: { results: [{ title, url, content, published_date }] }
final class TavilySearchProvider: WebSearchProvider {
    let name = "Tavily"
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "TavilySearch")
    private let endpoint = URL(string: "https://api.tavily.com/search")!
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    private struct RequestBody: Encodable {
        let api_key: String
        let query: String
        let search_depth: String
        let max_results: Int
        let include_answer: Bool
    }

    private struct ResponseBody: Decodable {
        let results: [TavilyResult]?
    }

    private struct TavilyResult: Decodable {
        let title: String?
        let url: String?
        let content: String?
        let published_date: String?
        let score: Double?
    }

    func search(_ query: String, limit: Int) async throws -> [WebSearchResult] {
        try EgressPolicy.assertGenericOutboundAllowed(endpoint)

        let body = RequestBody(
            api_key: apiKey,
            query: query,
            search_depth: "basic",
            max_results: max(1, min(10, limit)),
            include_answer: false
        )

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw WebSearchError.network(error.localizedDescription) }

        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.network("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw WebSearchError.http(http.statusCode, msg)
        }

        let decoded: ResponseBody
        do { decoded = try JSONDecoder().decode(ResponseBody.self, from: data) }
        catch { throw WebSearchError.decode(error.localizedDescription) }

        let iso = ISO8601DateFormatter()
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        return (decoded.results ?? []).compactMap { r in
            guard let urlStr = r.url, let url = URL(string: urlStr),
                  let title = r.title else { return nil }
            return WebSearchResult(
                title: title,
                url: url,
                snippet: r.content ?? "",
                publishedAt: r.published_date.flatMap { iso.date(from: $0) ?? dateOnly.date(from: $0) }
            )
        }
    }
}
