import Foundation

/// Fetches a lightweight "what's on your Linear plate today" snapshot for the
/// Brain Dump page. Wraps the existing `TaskSyncService.fetchLinear` —
/// filtering down to issues assigned to the configured user and in an open
/// state — and maps the result to the smaller `LinearBriefIssue` DTO the
/// brain-dump source carries.
enum LinearBriefService {
    enum BriefError: Error, LocalizedError {
        case missingAPIKey
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No Linear API key set. Add one in Settings → Task sync."
            }
        }
    }

    /// Returns the open issues currently assigned to the user, sorted by due
    /// date (earlier first, undated at the end). Caps at 25 so a heavy queue
    /// doesn't blow the planner's context budget.
    static func fetchMyAssignedIssuesToday(apiKey: String) async throws -> [LinearBriefIssue] {
        let raw = try await TaskSyncService.fetchLinear(apiKey: apiKey)
        let userAliases = AppSettings.shared.myNameTokens
        let mine = raw.filter { task in
            guard task.status != .completed else { return false }
            guard let owner = task.owner?.lowercased() else { return false }
            // Aliases live as either the user's full name or first-token names —
            // an inclusive contains() match catches "Tyler", "tyler.yannes", etc.
            return userAliases.contains(where: { owner.contains($0) })
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let mapped: [LinearBriefIssue] = mine.map { task in
            LinearBriefIssue(
                identifier: identifier(from: task),
                title: task.title,
                url: task.externalURL.flatMap(URL.init(string:)),
                dueDate: task.dueDate,
                priority: priorityRank(task.priority),
                state: task.status.label
            )
        }

        return Array(mapped.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return (lhs.priority ?? 99) < (rhs.priority ?? 99)
            }
        }.prefix(25))
    }

    /// Linear's GraphQL `id` is a UUID. Public-facing identifiers like
    /// `ABC-123` live in the `url`. Surface a short form by parsing the URL's
    /// last path component when present so the brain-dump UI reads like Linear.
    private static func identifier(from task: ExternalTask) -> String {
        if let urlStr = task.externalURL,
           let url = URL(string: urlStr) {
            let comps = url.pathComponents.filter { !$0.isEmpty && $0 != "/" }
            // Linear paths look like /TEAM/issue/ABC-123/title — pick the last
            // segment that contains a digit.
            if let last = comps.reversed().first(where: { $0.contains(where: { $0.isNumber }) }) {
                return String(last.uppercased().prefix(12))
            }
        }
        return String(task.externalID.prefix(8))
    }

    private static func priorityRank(_ p: ActionItem.Priority) -> Int {
        switch p {
        case .urgent: return 0
        case .high:   return 1
        case .medium: return 2
        case .low:    return 3
        }
    }
}
