import Foundation
import OSLog

/// A task pulled from an external system, normalized to our model. Deduped on
/// (source, externalID) by `ActionItemStore.mergeExternal`.
struct ExternalTask {
    let externalID: String
    let externalURL: String?
    let title: String
    let notes: String?
    let status: ActionItem.Status
    let priority: ActionItem.Priority
    let dueDate: Date?
    let owner: String?
    let projectName: String?
}

/// Pulls issues/tasks from Linear and Notion using their FREE APIs and a
/// locally-stored personal token. No LLM / agent involved, so there are no
/// per-call charges — this is plain HTTPS against the official endpoints.
enum TaskSyncService {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "TaskSync")

    enum SyncError: Error, LocalizedError {
        case http(String, Int, String)
        case decode(String)
        var errorDescription: String? {
            switch self {
            case .http(let svc, let c, let m): return "\(svc) HTTP \(c): \(String(m.prefix(300)))"
            case .decode(let m): return "Could not parse response: \(m)"
            }
        }
    }

    // MARK: - Linear (GraphQL)

    static func fetchLinear(apiKey: String) async throws -> [ExternalTask] {
        var out: [ExternalTask] = []
        var after: String? = nil
        var pages = 0
        repeat {
            let (batch, next) = try await linearPage(apiKey: apiKey, after: after)
            out.append(contentsOf: batch)
            after = next
            pages += 1
        } while after != nil && pages < 6   // cap ~300 issues
        return out
    }

    private static func linearPage(apiKey: String, after: String?) async throws -> ([ExternalTask], String?) {
        let afterArg = after.map { ", after: \"\($0)\"" } ?? ""
        let query = """
        { issues(first: 50\(afterArg)) { pageInfo { hasNextPage endCursor }
          nodes { id title description url dueDate priority
            state { type } assignee { name } project { name } } } }
        """
        var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.http("Linear", -1, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.http("Linear", http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              let issues = dataObj["issues"] as? [String: Any],
              let nodes = issues["nodes"] as? [[String: Any]] else {
            // GraphQL errors come back with 200 + an "errors" array.
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = obj["errors"] as? [[String: Any]],
               let first = errors.first?["message"] as? String {
                throw SyncError.http("Linear", 200, first)
            }
            throw SyncError.decode("unexpected Linear payload")
        }

        let tasks: [ExternalTask] = nodes.compactMap(linearTask(from:))
        let pageInfo = issues["pageInfo"] as? [String: Any]
        let hasNext = pageInfo?["hasNextPage"] as? Bool ?? false
        let endCursor = pageInfo?["endCursor"] as? String
        return (tasks, hasNext ? endCursor : nil)
    }

    private static func linearTask(from node: [String: Any]) -> ExternalTask? {
        guard let id = node["id"] as? String,
              let title = node["title"] as? String else { return nil }
        let stateType = (node["state"] as? [String: Any])?["type"] as? String ?? "backlog"
        let priorityNum = node["priority"] as? Int ?? 0
        return ExternalTask(
            externalID: id,
            externalURL: node["url"] as? String,
            title: title,
            notes: node["description"] as? String,
            status: linearStatus(stateType),
            priority: linearPriority(priorityNum),
            dueDate: parseISODate(node["dueDate"] as? String),
            owner: (node["assignee"] as? [String: Any])?["name"] as? String,
            projectName: (node["project"] as? [String: Any])?["name"] as? String)
    }

    // MARK: - Linear projects

    struct LinearProjectRef: Identifiable, Sendable, Hashable {
        let id: String
        let name: String
    }

    /// All Linear projects the key can see (for linking).
    static func fetchLinearProjects(apiKey: String) async throws -> [LinearProjectRef] {
        let query = "{ projects(first: 100) { nodes { id name state } } }"
        let data = try await linearRequest(apiKey: apiKey, query: query)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["data"] as? [String: Any],
              let projects = d["projects"] as? [String: Any],
              let nodes = projects["nodes"] as? [[String: Any]] else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = obj["errors"] as? [[String: Any]],
               let first = errors.first?["message"] as? String {
                throw SyncError.http("Linear", 200, first)
            }
            throw SyncError.decode("unexpected Linear projects payload")
        }
        return nodes.compactMap { n in
            guard let id = n["id"] as? String, let name = n["name"] as? String else { return nil }
            return LinearProjectRef(id: id, name: name)
        }
    }

    /// Every issue belonging to a specific Linear project.
    static func fetchLinearProjectIssues(apiKey: String, projectID: String) async throws -> [ExternalTask] {
        var out: [ExternalTask] = []
        var after: String? = nil
        var pages = 0
        repeat {
            let afterArg = after.map { ", after: \"\($0)\"" } ?? ""
            let query = """
            { project(id: "\(projectID)") { issues(first: 50\(afterArg)) {
              pageInfo { hasNextPage endCursor }
              nodes { id title description url dueDate priority
                state { type } assignee { name } project { name } } } } }
            """
            let data = try await linearRequest(apiKey: apiKey, query: query)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = obj["data"] as? [String: Any],
                  let project = d["project"] as? [String: Any],
                  let issues = project["issues"] as? [String: Any],
                  let nodes = issues["nodes"] as? [[String: Any]] else {
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errors = obj["errors"] as? [[String: Any]],
                   let first = errors.first?["message"] as? String {
                    throw SyncError.http("Linear", 200, first)
                }
                break
            }
            out.append(contentsOf: nodes.compactMap(linearTask(from:)))
            let pageInfo = issues["pageInfo"] as? [String: Any]
            after = (pageInfo?["hasNextPage"] as? Bool ?? false) ? pageInfo?["endCursor"] as? String : nil
            pages += 1
        } while after != nil && pages < 10
        return out
    }

    private static func linearRequest(apiKey: String, query: String, variables: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.http("Linear", -1, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.http("Linear", http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Linear teams + create issue

    struct LinearTeamRef: Identifiable, Sendable, Hashable { let id: String; let key: String; let name: String }
    struct LinearIssueResult: Sendable { let id: String; let identifier: String; let url: String }

    static func fetchLinearTeams(apiKey: String) async throws -> [LinearTeamRef] {
        let data = try await linearRequest(apiKey: apiKey, query: "{ teams(first: 50) { nodes { id key name } } }")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["data"] as? [String: Any],
              let teams = d["teams"] as? [String: Any],
              let nodes = teams["nodes"] as? [[String: Any]] else {
            throw SyncError.decode("unexpected Linear teams payload")
        }
        return nodes.compactMap { n in
            guard let id = n["id"] as? String, let key = n["key"] as? String, let name = n["name"] as? String else { return nil }
            return LinearTeamRef(id: id, key: key, name: name)
        }
    }

    static func createLinearIssue(apiKey: String, teamID: String, title: String,
                                  description: String?, projectID: String?) async throws -> LinearIssueResult {
        let mutation = """
        mutation IssueCreate($input: IssueCreateInput!) {
          issueCreate(input: $input) { success issue { id identifier url } }
        }
        """
        var input: [String: Any] = ["teamId": teamID, "title": title]
        if let description, !description.isEmpty { input["description"] = description }
        if let projectID, !projectID.isEmpty { input["projectId"] = projectID }
        let data = try await linearRequest(apiKey: apiKey, query: mutation, variables: ["input": input])
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["data"] as? [String: Any],
              let create = d["issueCreate"] as? [String: Any],
              (create["success"] as? Bool) == true,
              let issue = create["issue"] as? [String: Any],
              let id = issue["id"] as? String else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = obj["errors"] as? [[String: Any]], let m = errors.first?["message"] as? String {
                throw SyncError.http("Linear", 200, m)
            }
            throw SyncError.decode("issueCreate failed")
        }
        return LinearIssueResult(id: id,
                                 identifier: issue["identifier"] as? String ?? "",
                                 url: issue["url"] as? String ?? "")
    }

    private static func linearStatus(_ type: String) -> ActionItem.Status {
        switch type {
        case "completed", "canceled": return .completed
        case "started":               return .inProgress
        default:                       return .open   // backlog / unstarted / triage
        }
    }
    private static func linearPriority(_ n: Int) -> ActionItem.Priority {
        switch n {
        case 1: return .urgent
        case 2: return .high
        case 3: return .medium
        case 4: return .low
        default: return .medium   // 0 = no priority
        }
    }

    // MARK: - Notion (database query)

    static func fetchNotion(apiKey: String, databaseID: String) async throws -> [ExternalTask] {
        var out: [ExternalTask] = []
        var cursor: String? = nil
        var pages = 0
        repeat {
            let (batch, next) = try await notionPage(apiKey: apiKey, databaseID: databaseID, cursor: cursor)
            out.append(contentsOf: batch)
            cursor = next
            pages += 1
        } while cursor != nil && pages < 6
        return out
    }

    private static func notionPage(apiKey: String, databaseID: String, cursor: String?) async throws -> ([ExternalTask], String?) {
        let url = URL(string: "https://api.notion.com/v1/databases/\(databaseID)/query")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["page_size": 100]
        if let cursor { body["start_cursor"] = cursor }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.http("Notion", -1, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.http("Notion", http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else {
            throw SyncError.decode("unexpected Notion payload")
        }

        let tasks: [ExternalTask] = results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            let title = notionTitle(props["Name"]) ?? notionFirstTitle(props) ?? "Untitled"
            return ExternalTask(
                externalID: id,
                externalURL: page["url"] as? String,
                title: title,
                notes: notionRichText(props["Notes"]) ?? notionRichText(props["Description"]),
                status: notionStatus(notionStatusName(props["Status"])),
                priority: notionPriority(notionSelectName(props["Priority"])),
                dueDate: parseISODate(notionDate(props["Due"])),
                owner: notionRichText(props["Owner"]),
                projectName: notionSelectName(props["Project"]) ?? notionRichText(props["Project"]))
        }
        let hasMore = obj["has_more"] as? Bool ?? false
        let next = obj["next_cursor"] as? String
        return (tasks, hasMore ? next : nil)
    }

    // MARK: - Notion property decoders

    private static func notionTitle(_ prop: Any?) -> String? {
        guard let p = prop as? [String: Any], let arr = p["title"] as? [[String: Any]] else { return nil }
        let s = arr.compactMap { ($0["plain_text"] as? String) }.joined()
        return s.isEmpty ? nil : s
    }
    /// Falls back to whatever property is of type title if it isn't named "Name".
    private static func notionFirstTitle(_ props: [String: Any]) -> String? {
        for (_, v) in props {
            if let p = v as? [String: Any], p["type"] as? String == "title",
               let arr = p["title"] as? [[String: Any]] {
                let s = arr.compactMap { $0["plain_text"] as? String }.joined()
                if !s.isEmpty { return s }
            }
        }
        return nil
    }
    private static func notionRichText(_ prop: Any?) -> String? {
        guard let p = prop as? [String: Any], let arr = p["rich_text"] as? [[String: Any]] else { return nil }
        let s = arr.compactMap { ($0["plain_text"] as? String) }.joined()
        return s.isEmpty ? nil : s
    }
    private static func notionStatusName(_ prop: Any?) -> String? {
        guard let p = prop as? [String: Any] else { return nil }
        if let st = p["status"] as? [String: Any] { return st["name"] as? String }
        if let sel = p["select"] as? [String: Any] { return sel["name"] as? String }
        return nil
    }
    private static func notionSelectName(_ prop: Any?) -> String? {
        guard let p = prop as? [String: Any], let sel = p["select"] as? [String: Any] else { return nil }
        return sel["name"] as? String
    }
    private static func notionDate(_ prop: Any?) -> String? {
        guard let p = prop as? [String: Any], let d = p["date"] as? [String: Any] else { return nil }
        return d["start"] as? String
    }
    private static func notionStatus(_ name: String?) -> ActionItem.Status {
        switch (name ?? "").lowercased() {
        case "completed", "done", "complete": return .completed
        case "in progress", "started", "doing": return .inProgress
        default: return .open
        }
    }
    private static func notionPriority(_ name: String?) -> ActionItem.Priority {
        switch (name ?? "").lowercased() {
        case "urgent": return .urgent
        case "high": return .high
        case "low": return .low
        default: return .medium
        }
    }

    // MARK: - Shared

    private static func parseISODate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // Notion / Linear due dates are often plain "yyyy-MM-dd".
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }
}

// MARK: - Manager hook

@available(macOS 14.0, *)
extension MeetingManager {
    var hasTaskConnectors: Bool {
        let s = AppSettings.shared
        let linear = !(s.linearAPIKey ?? "").isEmpty
        let notion = !(s.notionAPIKey ?? "").isEmpty && !(s.notionActionItemsDatabaseID ?? "").isEmpty
        return linear || notion
    }

    var linearConfigured: Bool { !(AppSettings.shared.linearAPIKey ?? "").isEmpty }

    /// Fetches the list of Linear projects available for linking.
    func fetchLinearProjectList() async -> [TaskSyncService.LinearProjectRef] {
        guard let key = AppSettings.shared.linearAPIKey, !key.isEmpty else { return [] }
        do { return try await TaskSyncService.fetchLinearProjects(apiKey: key) }
        catch {
            lastTaskSyncError = (error as? TaskSyncService.SyncError)?.localizedDescription ?? error.localizedDescription
            return []
        }
    }

    /// Imports a Linear project's issues and homes them under the given local
    /// project (enabling its database). Re-runnable to re-sync.
    func importLinearProject(localProjectID: String, linearProjectID: String) async {
        guard let key = AppSettings.shared.linearAPIKey, !key.isEmpty else { return }
        guard !isSyncingTasks else { return }
        isSyncingTasks = true
        lastTaskSyncError = nil
        defer { isSyncingTasks = false }
        do {
            let tasks = try await TaskSyncService.fetchLinearProjectIssues(apiKey: key, projectID: linearProjectID)
            let created = actionItems.mergeExternal(source: "linear", tasks: tasks, assignProjectID: localProjectID)
            actionItems.setProjectLinearID(localProjectID, linearProjectID: linearProjectID)
            actionItems.setProjectDatabaseEnabled(localProjectID, true)
            AppSettings.shared.lastTaskSync = Date()
            lastTaskSyncSummary = "Linear: \(tasks.count) issues imported (\(created) new)"
        } catch {
            lastTaskSyncError = (error as? TaskSyncService.SyncError)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Pulls from every configured connector, merges into the store, and
    /// records a human-readable summary. Safe to call repeatedly (deduped).
    func syncExternalTasks() async {
        guard !isSyncingTasks else { return }
        let settings = AppSettings.shared
        isSyncingTasks = true
        lastTaskSyncError = nil
        defer { isSyncingTasks = false }

        var summaries: [String] = []
        var errors: [String] = []

        if let key = settings.linearAPIKey, !key.isEmpty {
            do {
                let tasks = try await TaskSyncService.fetchLinear(apiKey: key)
                let created = actionItems.mergeExternal(source: "linear", tasks: tasks)
                summaries.append("Linear: \(tasks.count) issues (\(created) new)")
            } catch {
                errors.append("Linear — \(error.localizedDescription)")
            }
        }

        if let key = settings.notionAPIKey, !key.isEmpty,
           let db = settings.notionActionItemsDatabaseID, !db.isEmpty {
            do {
                let tasks = try await TaskSyncService.fetchNotion(apiKey: key, databaseID: db)
                let created = actionItems.mergeExternal(source: "notion", tasks: tasks)
                summaries.append("Notion: \(tasks.count) items (\(created) new)")
            } catch {
                errors.append("Notion — \(error.localizedDescription)")
            }
        }

        if summaries.isEmpty && errors.isEmpty {
            lastTaskSyncError = "No connectors configured. Add a Linear or Notion key in Settings → Integrations."
        } else {
            settings.lastTaskSync = Date()
            lastTaskSyncSummary = summaries.joined(separator: " · ")
            if !errors.isEmpty { lastTaskSyncError = errors.joined(separator: "\n") }
        }
    }
}
