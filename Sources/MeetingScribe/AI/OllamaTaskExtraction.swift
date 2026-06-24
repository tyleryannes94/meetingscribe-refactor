import Foundation

/// A task the local LLM pulled out of a free-text brain-dump, before the user
/// confirms it. `suggestedProjectID` is resolved against the existing projects;
/// when the model named a project we couldn't match, `suggestedProjectName`
/// carries the raw name so the UI can offer to create it.
struct ExtractedTaskDraft: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var priority: ActionItem.Priority
    var dueDate: Date?
    var suggestedProjectID: String?
    var suggestedProjectName: String?
}

extension OllamaService {
    /// Raw JSON shape the model emits — decoded then resolved into
    /// `ExtractedTaskDraft`s by `extractTaskDrafts`.
    private struct RawExtractedTask: Decodable {
        var title: String
        var priority: String?
        var due: String?
        var project: String?
    }

    /// Turn a free-text brain-dump into structured task drafts, each tagged with
    /// a suggested priority, due date, and best-matching existing project.
    ///
    /// `projects` is the list of (id, name) the model may assign to — it is told
    /// to use one of these names verbatim or none. Project names are resolved
    /// back to ids case-insensitively here, so the model never sees ids.
    func extractTaskDrafts(from text: String,
                           projects: [(id: String, name: String)],
                           now: Date = Date()) async throws -> [ExtractedTaskDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        let pretty = DateFormatter()
        pretty.dateFormat = "EEEE, MMMM d, yyyy"
        let todayISO = iso.string(from: now)
        let todayPretty = pretty.string(from: now)

        let projectList = projects.isEmpty
            ? "(none yet)"
            : projects.map { "- \($0.name)" }.joined(separator: "\n")

        let prompt = """
        You convert a person's brain-dump into a clean, deduplicated task list.
        Today is \(todayPretty) (\(todayISO)).

        Existing projects you may assign tasks to (use the name VERBATIM, or null):
        \(projectList)

        Output ONLY a JSON array — no prose, no code fences. Each element:
        {"title": string, "priority": "low"|"medium"|"high"|"urgent", "due": "YYYY-MM-DD" or null, "project": <one existing project name> or null}

        Rules:
        - One element per distinct, actionable task. Split compound items ("do X and Y") into separate tasks.
        - title is a short imperative phrase (e.g. "Email Sarah the deck"). Strip filler.
        - Infer priority from urgency cues ("asap", "urgent", "important", deadlines). Default "medium".
        - Resolve relative dates (today, tomorrow, "friday", "next week") to an absolute YYYY-MM-DD from today's date. Use null when no date is implied.
        - "project" MUST be exactly one of the listed names, or null. NEVER invent a project name.
        - Ignore lines that are notes/thoughts, not tasks.
        - If there are no tasks, output exactly: []

        BRAIN DUMP:
        \(trimmed)
        """

        let raw = try await generate(prompt: prompt, temperature: 0.2, numCtx: 8192)
        guard let json = Self.firstJSONArray(in: raw),
              let data = json.data(using: .utf8) else { return [] }
        let decoded = (try? JSONDecoder().decode([RawExtractedTask].self, from: data)) ?? []

        // Resolve project names → ids, case-insensitively.
        func projectID(for name: String?) -> (id: String?, name: String?) {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name.lowercased() != "null" else { return (nil, nil) }
            if let match = projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return (match.id, match.name)
            }
            // Model named something we don't have — surface the raw name so the
            // UI can offer to create it.
            return (nil, name)
        }

        return decoded.compactMap { item -> ExtractedTaskDraft? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let pr = ActionItem.Priority(rawValue: (item.priority ?? "medium").lowercased()) ?? .medium
            let due = item.due.flatMap { iso.date(from: $0) }
            let (pid, pname) = projectID(for: item.project)
            return ExtractedTaskDraft(title: title, priority: pr, dueDate: due,
                                      suggestedProjectID: pid, suggestedProjectName: pname)
        }
    }

    /// A short, focused "what to actually do today" plan, considering the user's
    /// brain-dump plus the tasks already on their plate. Returns plain Markdown.
    func planTodayPriorities(brainDump: String,
                             currentTasks: [String],
                             now: Date = Date()) async throws -> String {
        let pretty = DateFormatter()
        pretty.dateFormat = "EEEE, MMMM d"
        let dump = brainDump.trimmingCharacters(in: .whitespacesAndNewlines)
        let onPlate = currentTasks.isEmpty
            ? "(nothing tracked yet)"
            : currentTasks.prefix(40).map { "- \($0)" }.joined(separator: "\n")

        let prompt = """
        You are a sharp executive assistant helping someone focus their day \
        (\(pretty.string(from: now))).

        Tasks already on their plate today:
        \(onPlate)

        Their brain-dump of everything on their mind:
        \(dump.isEmpty ? "(empty)" : dump)

        Write a tight focus plan in Markdown:
        ## Top 3 priorities
        A numbered list of the 3 things that matter most today, each one line, \
        with a one-clause reason.
        ## Also if there's time
        A short bullet list of secondary items.
        ## Park for later
        Anything that isn't really today.

        Be decisive and specific. No preamble, no closing remarks.
        """
        return try await generate(prompt: prompt, temperature: 0.3, numCtx: 8192)
    }

    /// Pulls the first top-level JSON array substring out of a model response,
    /// tolerating stray prose or code fences around it.
    static func firstJSONArray(in s: String) -> String? {
        guard let start = s.firstIndex(of: "["),
              let end = s.lastIndex(of: "]"), start < end else { return nil }
        return String(s[start...end])
    }
}
