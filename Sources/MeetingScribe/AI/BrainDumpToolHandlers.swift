import Foundation
import VaultKit
import OSLog

/// Dispatches the planner's five tool calls (`fetch_url`, `web_search`,
/// `propose_task`, `propose_calendar_block`, `link_existing_project`) against
/// the live stores and emits structured events the UI can render in its
/// activity log.
///
/// Lives on the main actor because every store mutation it touches
/// (`BrainDumpStore`, `ActionItemStore.projects`) is main-actor isolated.
@MainActor
final class BrainDumpToolHandlers {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "BrainDumpTools")
    let sessionID: String
    let store: BrainDumpStore
    let actionItems: ActionItemStore
    /// Receives one event per tool call so the UI can show the model's
    /// progress without waiting for the final assistant turn.
    let progress: (BrainDumpPlannerEvent) -> Void

    init(sessionID: String,
         store: BrainDumpStore,
         actionItems: ActionItemStore,
         progress: @escaping (BrainDumpPlannerEvent) -> Void) {
        self.sessionID = sessionID
        self.store = store
        self.actionItems = actionItems
        self.progress = progress
    }

    /// Catalog used both by the in-app planner loop and by the in-app chat
    /// (`BrainDumpChatTools` registers a subset of these so the existing chat
    /// can drop ideas into the Brain Dump page).
    static var planTools: [AnthropicClient.Tool] {
        [
            .init(name: "fetch_url",
                  description: "Fetch a URL, extract its main article body as Markdown, and attach it to the current brain dump as a source.",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("url")]),
                    "properties": .object([
                        "url": .object(["type": .string("string"), "description": .string("Absolute https URL to fetch.")]),
                        "reason": .object(["type": .string("string"), "description": .string("One-clause reason you're fetching this — surfaced to the user.")])
                    ])
                  ])),
            .init(name: "web_search",
                  description: "Search the web with the user's configured provider (Tavily) and attach the top results as a source.",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("query")]),
                    "properties": .object([
                        "query": .object(["type": .string("string")]),
                        "limit": .object(["type": .string("integer"), "default": .int(5)])
                    ])
                  ])),
            .init(name: "link_existing_project",
                  description: "Look up an existing project by name to use in propose_task. Returns up to 3 candidates by case-insensitive substring match.",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("query")]),
                    "properties": .object([
                        "query": .object(["type": .string("string")])
                    ])
                  ])),
            .init(name: "propose_task",
                  description: "Propose one task for the user to review. The user accepts/edits/rejects in the review pane; accepted tasks are created in MeetingScribe's task store.",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("title")]),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "priority": .object(["type": .string("string"), "description": .string("low | medium | high | urgent")]),
                        "due_date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD or null")]),
                        "project_name": .object(["type": .string("string"), "description": .string("Must match an existing project name exactly, or null.")]),
                        "source_urls": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "notes": .object(["type": .string("string")])
                    ])
                  ])),
            .init(name: "propose_calendar_block",
                  description: "Propose one calendar focus block for the user to review. The user accepts to create it in macOS Calendar.",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("title"), .string("start")]),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "start": .object(["type": .string("string"), "description": .string("ISO 8601 datetime with offset, e.g. 2026-06-29T09:30:00-05:00")]),
                        "duration_minutes": .object(["type": .string("integer"), "description": .string("Defaults to user's preference (25).")]),
                        "linked_task_title": .object(["type": .string("string")]),
                        "notes": .object(["type": .string("string")])
                    ])
                  ]))
        ]
    }

    /// Tool dispatcher. Returns the same `Result<String, Error>` shape as
    /// every other ChatTool handler so the OllamaChatClient loop sees a
    /// uniform interface.
    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "fetch_url":               return await fetchURL(input)
        case "web_search":              return await webSearch(input)
        case "link_existing_project":   return linkProject(input)
        case "propose_task":            return proposeTask(input)
        case "propose_calendar_block":  return proposeBlock(input)
        default:                        return nil
        }
    }

    // MARK: - fetch_url

    private func fetchURL(_ input: [String: JSONValue]) async -> Result<String, Error> {
        guard let raw = input["url"]?.asString,
              let url = URL(string: raw), url.scheme?.lowercased() == "https" else {
            return .failure(BrainDumpToolError.badInput("fetch_url needs an https url"))
        }
        let reason = input["reason"]?.asString ?? ""
        progress(.toolCalled(name: "fetch_url", summary: "Fetching \(url.host ?? url.absoluteString)…"))

        // Insert a loading placeholder so the source panel shows the URL as
        // soon as the call begins. We'll replace it with the resolved source
        // once the fetch lands.
        let placeholder = URLSource(url: url, title: url.host ?? url.absoluteString)
        store.attachSource(sessionID, .url(placeholder))

        do {
            let page = try await URLFetcher.fetch(url)
            let article = ReadabilityExtractor.extract(html: page.html, baseURL: page.finalURL)
            var resolved = placeholder
            resolved.title = article.title.isEmpty ? (page.finalURL.host ?? raw) : article.title
            resolved.extractedMarkdown = article.markdown
            resolved.isLoading = false
            resolved.url = page.finalURL
            store.attachSource(sessionID, .url(resolved))

            progress(.sourceAttached(label: resolved.title))
            return .success("""
            {"ok":true,"title":"\(escape(resolved.title))","words":\(article.wordCount),"reason":"\(escape(reason))"}
            """)
        } catch {
            var failed = placeholder
            failed.isLoading = false
            failed.error = error.localizedDescription
            store.attachSource(sessionID, .url(failed))
            progress(.toolFailed(name: "fetch_url", message: error.localizedDescription))
            return .success("""
            {"ok":false,"error":"\(escape(error.localizedDescription))"}
            """)
        }
    }

    // MARK: - web_search

    private func webSearch(_ input: [String: JSONValue]) async -> Result<String, Error> {
        guard let query = input["query"]?.asString,
              !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(BrainDumpToolError.badInput("web_search needs a query"))
        }
        let limit = input["limit"]?.asInt ?? 5
        guard let provider = WebSearchService.current() else {
            progress(.toolFailed(name: "web_search", message: "no provider configured"))
            return .success("""
            {"ok":false,"error":"Web search is off or no API key is configured. Ask the user to enable it in Integrations → Brain Dump."}
            """)
        }

        progress(.toolCalled(name: "web_search", summary: "Searching \"\(query)\"…"))
        do {
            let results = try await provider.search(query, limit: limit)
            let source = SearchSource(query: query, provider: provider.name, results: results)
            store.attachSource(sessionID, .search(source))
            progress(.sourceAttached(label: "Search: \(query) (\(results.count))"))
            return .success(jsonSearchSummary(provider: provider.name, query: query, results: results))
        } catch {
            progress(.toolFailed(name: "web_search", message: error.localizedDescription))
            return .success("""
            {"ok":false,"error":"\(escape(error.localizedDescription))"}
            """)
        }
    }

    private func jsonSearchSummary(provider: String, query: String, results: [WebSearchResult]) -> String {
        // Keep the model-facing summary terse — title + url + a clipped
        // snippet. Anything longer wastes context.
        let rows: [String] = results.prefix(8).map { r in
            let snippet = String(r.snippet.prefix(220))
            return """
            {"title":"\(escape(r.title))","url":"\(escape(r.url.absoluteString))","snippet":"\(escape(snippet))"}
            """
        }
        return """
        {"ok":true,"provider":"\(escape(provider))","query":"\(escape(query))","results":[\(rows.joined(separator: ","))]}
        """
    }

    // MARK: - link_existing_project

    private func linkProject(_ input: [String: JSONValue]) -> Result<String, Error> {
        let query = (input["query"]?.asString ?? "").lowercased()
        guard !query.isEmpty else {
            return .failure(BrainDumpToolError.badInput("link_existing_project needs a query"))
        }
        let matches = actionItems.projects
            .filter { $0.name.lowercased().contains(query) }
            .prefix(3)
            .map { ["id": $0.id, "name": $0.name] }
        let rows = matches.map {
            """
            {"id":"\(escape($0["id"] ?? ""))","name":"\(escape($0["name"] ?? ""))"}
            """
        }
        return .success("""
        {"ok":true,"matches":[\(rows.joined(separator: ","))]}
        """)
    }

    // MARK: - propose_task

    private func proposeTask(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let title = input["title"]?.asString,
              !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(BrainDumpToolError.badInput("propose_task needs a title"))
        }
        let priorityRaw = input["priority"]?.asString ?? "medium"
        let dueDate = parseDueDate(input["due_date"]?.asString)
        let (projectID, projectName) = resolveProject(input["project_name"]?.asString)
        let urlStrings: [String] = {
            if case let .array(items) = (input["source_urls"] ?? .null) {
                return items.compactMap { $0.asString }
            }
            return []
        }()
        let sourceURLs = urlStrings.compactMap { URL(string: $0) }
        let notes = input["notes"]?.asString

        let draft = TaskDraft(
            title: title,
            priorityRaw: priorityRaw,
            dueDate: dueDate,
            suggestedProjectID: projectID,
            suggestedProjectName: projectName,
            notes: notes,
            sourceURLs: sourceURLs
        )
        store.appendDraft(sessionID, .task(draft))
        progress(.draftProposed(kind: "task", label: title))
        return .success("""
        {"ok":true,"id":"\(draft.id.uuidString)","title":"\(escape(title))"}
        """)
    }

    // MARK: - propose_calendar_block

    private func proposeBlock(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let title = input["title"]?.asString,
              !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(BrainDumpToolError.badInput("propose_calendar_block needs a title"))
        }
        guard let startStr = input["start"]?.asString,
              let start = parseISO(startStr) else {
            return .failure(BrainDumpToolError.badInput("propose_calendar_block needs `start` as ISO 8601"))
        }
        let duration = input["duration_minutes"]?.asInt
            ?? AppSettings.shared.brainDumpDefaultFocusMinutes
        let linkedTaskTitle = input["linked_task_title"]?.asString
        let notes = input["notes"]?.asString

        let draft = CalendarBlockDraft(
            title: title,
            start: start,
            durationMinutes: duration,
            linkedTaskTitle: linkedTaskTitle,
            notes: notes
        )
        store.appendDraft(sessionID, .calendarBlock(draft))
        progress(.draftProposed(kind: "calendar_block", label: title))
        return .success("""
        {"ok":true,"id":"\(draft.id.uuidString)","title":"\(escape(title))","start":"\(startStr)"}
        """)
    }

    // MARK: - Parsers / helpers

    private func parseDueDate(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
              s.lowercased() != "null" else { return nil }
        // Prefer ISO 8601 datetime, fall back to YYYY-MM-DD.
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        // Fall back to "yyyy-MM-dd HH:mm" local — small models sometimes drop
        // the zone offset entirely.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    private func resolveProject(_ raw: String?) -> (id: String?, name: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, raw.lowercased() != "null" else { return (nil, nil) }
        if let match = actionItems.projects
            .first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame }) {
            return (match.id, match.name)
        }
        return (nil, raw)
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

enum BrainDumpToolError: Error, LocalizedError {
    case badInput(String)
    var errorDescription: String? {
        switch self {
        case .badInput(let m): return m
        }
    }
}

/// One event surfaced to the planner's caller (the UI). Drives the activity
/// log strip under the composer and the "Plan with AI" button's enabled state.
enum BrainDumpPlannerEvent: Identifiable, Hashable {
    case started
    case toolCalled(name: String, summary: String)
    case toolFailed(name: String, message: String)
    case sourceAttached(label: String)
    case draftProposed(kind: String, label: String)
    case finished(reasoning: String?)
    case failed(message: String)

    var id: UUID { UUID() }

    var label: String {
        switch self {
        case .started:                       return "Planning started…"
        case .toolCalled(_, let s):          return s
        case .toolFailed(let n, let m):      return "\(n) failed: \(m)"
        case .sourceAttached(let l):         return "Attached: \(l)"
        case .draftProposed(let k, let l):
            return k == "task" ? "Proposed task: \(l)" : "Proposed block: \(l)"
        case .finished(let r):               return r.map { "Done — \($0)" } ?? "Done."
        case .failed(let m):                 return "Planning failed: \(m)"
        }
    }

    var isError: Bool {
        switch self {
        case .toolFailed, .failed: return true
        default:                   return false
        }
    }
}
