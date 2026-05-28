import Foundation
import OSLog

/// Pushes ActionItems to a Notion database via the Notion REST API.
///
/// Uses the user's stored integration secret (`AppSettings.notionAPIKey`) and
/// target database (`notionActionItemsDatabaseID`). The integration must be
/// shared with the target database in Notion (open the DB page, click ⋯ →
/// Connections → add the integration).
///
/// Expected database schema (created by the user; if a property is missing
/// it's just skipped in the payload — Notion errors with a 400 in that case
/// and we surface the message):
///   • Name      — title
///   • Status    — status   (Open / In Progress / Completed)
///   • Priority  — select   (Low / Medium / High / Urgent)
///   • Due       — date
///   • Meeting   — rich_text (denormalized meeting title)
///   • Owner     — rich_text (optional)
///
/// If `notionActionItemsDatabaseID` is unset, we error out — there's no
/// sensible "default" location for the Notion API.
struct NotionActionItemService {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "NotionPush")
    private static let apiBase = URL(string: "https://api.notion.com/v1/")!
    private static let notionVersion = "2022-06-28"

    enum NotionError: Error, LocalizedError {
        case missingAPIKey
        case missingDatabaseID
        case http(Int, String)
        case decode(String)
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:    return "Notion API key isn't set. Open Settings → Notion MCP → Set Notion API key."
            case .missingDatabaseID: return "No Notion Action Items database configured. Open Settings → Notion MCP → Set Notion API key and add the database ID."
            case .http(let c, let m): return "Notion API HTTP \(c): \(m)"
            case .decode(let m):    return "Could not decode Notion response: \(m)"
            }
        }
    }

    /// Creates a new Notion page in the configured database for this item.
    /// Returns (pageID, pageURL) on success.
    static func push(_ item: ActionItem) async throws -> (id: String, url: String) {
        let settings = AppSettings.shared
        guard let key = settings.notionAPIKey, !key.isEmpty else { throw NotionError.missingAPIKey }
        guard let dbID = settings.notionActionItemsDatabaseID, !dbID.isEmpty else {
            throw NotionError.missingDatabaseID
        }

        let body = buildCreatePayload(item: item, databaseID: dbID)
        return try await postCreate(body: body, key: key)
    }

    /// Updates an existing Notion page (when `notionPageID` is set) to
    /// reflect the latest local state. Used when the user changes status /
    /// priority / due date AFTER a push.
    static func update(_ item: ActionItem) async throws {
        let settings = AppSettings.shared
        guard let key = settings.notionAPIKey, !key.isEmpty else { throw NotionError.missingAPIKey }
        guard let pageID = item.notionPageID, !pageID.isEmpty else { return }

        let url = apiBase.appendingPathComponent("pages/\(pageID)")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["properties": properties(for: item)]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NotionError.http(-1, "no http response") }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            throw NotionError.http(http.statusCode, s)
        }
    }

    // MARK: - Internals

    private static func postCreate(body: [String: Any], key: String) async throws -> (id: String, url: String) {
        let url = apiBase.appendingPathComponent("pages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NotionError.http(-1, "no http response") }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            AppLog.error("Notion", "Create page failed",
                         ["status": "\(http.statusCode)", "body": String(s.prefix(400))])
            throw NotionError.http(http.statusCode, s)
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let id = obj["id"] as? String ?? ""
            let url = obj["url"] as? String ?? ""
            return (id, url)
        } catch {
            AppLog.error("Notion", "Decode create response failed", error: error)
            throw NotionError.decode(error.localizedDescription)
        }
    }

    private static func buildCreatePayload(item: ActionItem, databaseID: String) -> [String: Any] {
        return [
            "parent": ["database_id": databaseID],
            "properties": properties(for: item)
        ]
    }

    /// Builds the `properties` object for both create + update. We send
    /// every property we know about; Notion will 400 if a property doesn't
    /// exist in the target DB — that error is surfaced verbatim so the
    /// user can fix their schema.
    private static func properties(for item: ActionItem) -> [String: Any] {
        var props: [String: Any] = [
            "Name": [
                "title": [
                    ["text": ["content": item.title]]
                ]
            ],
            "Status": [
                "status": ["name": notionStatusName(item.status)]
            ],
            "Priority": [
                "select": ["name": item.priority.label]
            ],
            "Meeting": [
                "rich_text": [
                    ["text": ["content": item.meetingTitle]]
                ]
            ]
        ]
        if let due = item.dueDate {
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withInternetDateTime]
            props["Due"] = [
                "date": ["start": df.string(from: due)]
            ]
        }
        if let owner = item.owner, !owner.isEmpty {
            props["Owner"] = [
                "rich_text": [
                    ["text": ["content": owner]]
                ]
            ]
        }
        return props
    }

    private static func notionStatusName(_ status: ActionItem.Status) -> String {
        switch status {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }
}
