import Foundation

/// One piece of context attached to a `BrainDumpSession`. The planner sees the
/// composer body PLUS a markdown summary of each source when it builds its
/// seed turn, so a pasted URL or a daily Linear brief becomes useful background
/// without the user having to copy/paste content into the composer.
///
/// Discriminator-encoded `Codable` (kind + payload) so new source types slot
/// in without breaking the existing on-disk shape.
enum BrainDumpSource: Codable, Identifiable, Hashable {
    case url(URLSource)
    case search(SearchSource)
    case linearBrief(LinearBriefSource)
    case slackBrief(SlackBriefStub)

    var id: String {
        switch self {
        case .url(let s):         return s.id
        case .search(let s):      return s.id
        case .linearBrief(let s): return s.id
        case .slackBrief(let s):  return s.id
        }
    }

    /// Rough token estimate so the UI can show a budget badge and the planner
    /// can decide what to truncate. ~4 chars per token (English heuristic).
    var tokenEstimate: Int {
        switch self {
        case .url(let s):         return max(1, s.extractedMarkdown.count / 4)
        case .search(let s):      return max(1, s.results.reduce(0) { $0 + $1.snippet.count } / 4)
        case .linearBrief(let s): return max(1, s.issues.count * 12)
        case .slackBrief:         return 0
        }
    }

    var kindLabel: String {
        switch self {
        case .url:         return "Link"
        case .search:      return "Search"
        case .linearBrief: return "Linear"
        case .slackBrief:  return "Slack"
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable {
        case url, search, linearBrief, slackBrief
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .url(let s):         try c.encode(Kind.url,         forKey: .kind); try c.encode(s, forKey: .payload)
        case .search(let s):      try c.encode(Kind.search,      forKey: .kind); try c.encode(s, forKey: .payload)
        case .linearBrief(let s): try c.encode(Kind.linearBrief, forKey: .kind); try c.encode(s, forKey: .payload)
        case .slackBrief(let s):  try c.encode(Kind.slackBrief,  forKey: .kind); try c.encode(s, forKey: .payload)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .url:         self = .url(try c.decode(URLSource.self,         forKey: .payload))
        case .search:      self = .search(try c.decode(SearchSource.self,   forKey: .payload))
        case .linearBrief: self = .linearBrief(try c.decode(LinearBriefSource.self, forKey: .payload))
        case .slackBrief:  self = .slackBrief(try c.decode(SlackBriefStub.self, forKey: .payload))
        }
    }
}

// MARK: - URL source

/// A URL the user (or AI) attached. `URLFetcher` fetches it, `ReadabilityExtractor`
/// reduces it to a compact Markdown rendering of the main article. The planner
/// sees the markdown, soft-capped per source so a 5K-word essay can't swallow
/// the whole 8K context window.
struct URLSource: Codable, Identifiable, Hashable {
    var id: String
    var url: URL
    /// Best-effort article title. Falls back to the host when extraction fails.
    var title: String
    /// Markdown extraction of the page. Empty while the fetch is in flight,
    /// short error sentence on failure.
    var extractedMarkdown: String
    var fetchedAt: Date
    /// True while the URL is still being fetched.
    var isLoading: Bool
    /// User-facing error if the fetch / extraction failed.
    var error: String?

    init(id: String = UUID().uuidString,
         url: URL,
         title: String = "",
         extractedMarkdown: String = "",
         fetchedAt: Date = Date(),
         isLoading: Bool = true,
         error: String? = nil) {
        self.id = id
        self.url = url
        self.title = title.isEmpty ? (url.host ?? url.absoluteString) : title
        self.extractedMarkdown = extractedMarkdown
        self.fetchedAt = fetchedAt
        self.isLoading = isLoading
        self.error = error
    }
}

// MARK: - Search source

/// A web search the AI ran via `WebSearchService`. We keep the top N results
/// (title / url / snippet / publishedAt) and an optional AI-generated summary
/// the planner can reference. Provider name is stored so a later swap (Brave,
/// Exa) doesn't make existing sources look broken.
struct SearchSource: Codable, Identifiable, Hashable {
    var id: String
    var query: String
    var provider: String
    var results: [WebSearchResult]
    var summary: String?
    var searchedAt: Date

    init(id: String = UUID().uuidString,
         query: String,
         provider: String,
         results: [WebSearchResult],
         summary: String? = nil,
         searchedAt: Date = Date()) {
        self.id = id
        self.query = query
        self.provider = provider
        self.results = results
        self.summary = summary
        self.searchedAt = searchedAt
    }
}

struct WebSearchResult: Codable, Hashable {
    var title: String
    var url: URL
    var snippet: String
    var publishedAt: Date?
}

// MARK: - Linear brief source

/// A snapshot of the user's open Linear issues at brief-pull time. Carries
/// just enough info to render a "What's on your Linear plate" panel and let
/// the planner reference items by id.
struct LinearBriefSource: Codable, Identifiable, Hashable {
    var id: String
    var fetchedAt: Date
    var issues: [LinearBriefIssue]

    init(id: String = UUID().uuidString,
         fetchedAt: Date = Date(),
         issues: [LinearBriefIssue]) {
        self.id = id
        self.fetchedAt = fetchedAt
        self.issues = issues
    }
}

struct LinearBriefIssue: Codable, Hashable {
    /// The Linear identifier (e.g. "ABC-123").
    var identifier: String
    var title: String
    var url: URL?
    var dueDate: Date?
    /// Linear's `priority` int (0=no priority … 4=low). Kept opaque so the
    /// planner can use it as a hint without us baking a mapping in.
    var priority: Int?
    /// Workflow state name ("In Progress", "Todo", …).
    var state: String?
}

// MARK: - Slack brief (stub)

/// Placeholder for a future Slack daily-brief integration. Keeping the shape
/// real (rather than just a "soon" flag) means SlackBriefService can fill it
/// in without touching the on-disk schema.
struct SlackBriefStub: Codable, Identifiable, Hashable {
    var id: String
    var note: String
    var requestedAt: Date

    init(id: String = UUID().uuidString,
         note: String = "Slack daily brief — coming soon",
         requestedAt: Date = Date()) {
        self.id = id
        self.note = note
        self.requestedAt = requestedAt
    }
}
