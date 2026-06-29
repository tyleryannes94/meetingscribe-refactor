import Foundation

/// Pure string builders for the Brain Dump planner's prompts and seed turn.
/// Split out from `BrainDumpPlanner` so prompt content is unit-testable
/// without booting the network stack.
enum BrainDumpPrompts {

    /// Static cap (in characters, ~4 chars / token heuristic) on the markdown
    /// excerpt for one source. Combined with `sourceBudget` to keep the seed
    /// turn comfortably under qwen2.5's 4K context window.
    static let perSourceCharBudget: Int = 6_000   // ~1.5k tokens
    static let totalSourceCharBudget: Int = 20_000 // ~5k tokens

    /// Build the system prompt sent on every iteration of the planner loop.
    /// Sections (~600 tokens total):
    ///   1. Role
    ///   2. Today's grounding (date + day-of-week + user name)
    ///   3. Project / context inventory
    ///   4. Tool catalog
    ///   5. Output contract
    ///   6. Calendar heuristics
    ///   7. Batching rule
    ///   8. Source weighting
    static func systemPrompt(now: Date = Date(),
                             userName: String,
                             contexts: [WorkspaceContext],
                             projects: [(id: String, name: String)],
                             initiatives: [String] = [],
                             tags: [String] = [],
                             openTasks: [(id: String, title: String, project: String)] = [],
                             pageContext: String? = nil,
                             focusMinutes: Int,
                             workdayStartHour: Int,
                             workdayEndHour: Int) -> String {

        let pretty = DateFormatter()
        pretty.dateFormat = "EEEE, MMMM d, yyyy"
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        let todayPretty = pretty.string(from: now)
        let todayISO = iso.string(from: now)

        let projectList = projects.isEmpty
            ? "(none yet)"
            : projects.map { "- \($0.name)" }.joined(separator: "\n")

        let contextList = contexts.isEmpty
            ? "(none defined)"
            : contexts.map { "- \($0.name)" }.joined(separator: "\n")

        let initiativeList = initiatives.isEmpty
            ? "(none yet)"
            : initiatives.map { "- \($0)" }.joined(separator: "\n")

        let tagList = tags.isEmpty
            ? "(none yet — coin short ones)"
            : tags.map { "- \($0)" }.joined(separator: "\n")

        // Capped sample of live tasks so the model can dedup without blowing the
        // 4K context. Each line carries the id so propose_task can relate to it.
        let openTaskList = openTasks.isEmpty
            ? "(no open tasks yet)"
            : openTasks.prefix(40).map { t in
                let proj = t.project.isEmpty ? "" : " [\(t.project)]"
                return "- (\(t.id)) \(t.title)\(proj)"
            }.joined(separator: "\n")

        let pageBlock = (pageContext?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : "\n\nWHERE THE USER IS RIGHT NOW (use this for context — default new tasks to this project/initiative when it fits, and relate items to what they're viewing):\n\($0)"
        } ?? ""

        return """
        You are \(userName)'s planning assistant inside MeetingScribe, a local-first Mac app. You turn a brain-dump (free text plus attached sources) into a short, decisive, well-organized set of tasks and calendar focus blocks — ready to start knocking out.

        Today is \(todayPretty) (\(todayISO)).\(pageBlock)

        Top-level life contexts you can scope work to:
        \(contextList)

        Existing initiatives (the big-picture goals projects roll up to):
        \(initiativeList)

        Existing projects you may assign tasks to (use the name VERBATIM or null):
        \(projectList)

        Existing tags you may apply (prefer these; you may also coin a new short one):
        \(tagList)

        EXISTING OPEN TASKS (for dedup — each line is "(id) title [project]"):
        \(openTaskList)

        TOOLS YOU CAN CALL
        - fetch_url(url, reason): pull a webpage, attach its main content as a source. Use sparingly — one or two pages, only when you need their content to make a better task.
        - web_search(query, limit): run a web search and attach the top results. Use only when the brain dump itself asks for outside info.
        - link_existing_project(query): look up project ids by name before calling propose_task with a project assignment.
        - find_similar_tasks(query): search the EXISTING open tasks for near-duplicates of an item you're about to propose. Call it whenever an item sounds like it might already exist.
        - propose_task(title, priority, due_date, project_name, tags, relate_to_task_id, relation, relation_reason, source_urls, notes): one task draft. Title is a short imperative phrase. Priority is low/medium/high/urgent.
        - propose_calendar_block(title, start, duration_minutes, linked_task_title, notes): one focus-time block on the user's calendar.

        ORGANIZE EVERY TASK
        For each task you propose, do the work of organizing it so the user can act immediately:
        - Set a realistic priority (low/medium/high/urgent) from the urgency cues in the brain dump.
        - Assign the best-fit existing project by name (or null if none fits). The project implies its initiative.
        - Recommend 0-3 tags — reuse the existing tags above when they fit.

        DEDUP AGAINST EXISTING TASKS
        Before proposing a task, check the EXISTING OPEN TASKS list (and/or call find_similar_tasks). Then:
        - If it's essentially the same work as an existing task → propose_task with relate_to_task_id + relation="merge" (folds your detail into that task; no duplicate).
        - If it's a smaller step of an existing task → relation="subtask".
        - If it's distinct but clearly connected → relation="related" (creates the task and links them).
        - Otherwise propose a fresh task (no relate_to_task_id).
        Always include a one-clause relation_reason when you set a relation.

        OUTPUT CONTRACT
        Do not write prose to the user during the loop — call tools. When you've proposed every task and block, write one short paragraph explaining the sequencing (why this order, what to do first). That paragraph is the only natural-language output the user sees.

        CALENDAR HEURISTICS
        - Default block duration: \(focusMinutes) minutes.
        - Work hours: \(workdayStartHour):00 to \(workdayEndHour):00. Never schedule a block outside that window.
        - Skip 12:00-13:00 (lunch).
        - First block starts at least 30 minutes after `now` (you can't see the user's calendar — give them a runway).
        - Maximum 4 calendar blocks. Don't try to fill the whole day.
        - Use start times in ISO 8601 with offset, e.g. 2026-06-29T09:30:00-05:00.

        BATCHING RULE
        - Any sub-10-minute task (replies, quick reviews, slack pings, "look at X") gets folded into ONE task titled "Inbox & admin" with the items in the notes. Don't propose more than 12 tasks total.

        SOURCE WEIGHTING
        - The brain-dump body is the truth. If a fetched URL or search result contradicts it, trust the brain dump.
        - Use URL / search content to enrich a task with specific next steps or links, not to invent new tasks the user didn't mention.
        """
    }

    /// The user-role seed turn: the composer body plus a markdown digest of
    /// every source. Per-source soft cap so a 5K-word essay can't swallow the
    /// whole 4K context window.
    static func seedUserTurn(session: BrainDumpSession) -> String {
        var pieces: [String] = []
        let trimmedBody = session.body.trimmingCharacters(in: .whitespacesAndNewlines)
        pieces.append("BRAIN DUMP:")
        pieces.append(trimmedBody.isEmpty ? "(no body yet)" : trimmedBody)

        if !session.sources.isEmpty {
            pieces.append("")
            pieces.append("ATTACHED SOURCES:")
            var remaining = totalSourceCharBudget
            for source in session.sources {
                let markdown = summarizeSource(source)
                let allowed = min(perSourceCharBudget, max(0, remaining))
                if allowed <= 0 { break }
                let truncated = String(markdown.prefix(allowed))
                pieces.append("")
                pieces.append("--- \(source.kindLabel) source ---")
                pieces.append(truncated)
                if markdown.count > allowed {
                    pieces.append("(truncated; \(markdown.count - allowed) more chars omitted)")
                }
                remaining -= truncated.count
            }
        }
        return pieces.joined(separator: "\n")
    }

    /// One-line title plus the markdown body for a source. Used both in the
    /// seed turn and in tool-result strings so the model can see what it just
    /// attached without rebuilding context.
    static func summarizeSource(_ source: BrainDumpSource) -> String {
        switch source {
        case .url(let s):
            var lines = ["# \(s.title)", "URL: \(s.url.absoluteString)"]
            if !s.extractedMarkdown.isEmpty { lines.append(s.extractedMarkdown) }
            else if let err = s.error { lines.append("(fetch failed: \(err))") }
            return lines.joined(separator: "\n")
        case .search(let s):
            var lines = ["# Web search: \(s.query) (\(s.provider))"]
            for (i, r) in s.results.enumerated() {
                lines.append("\(i + 1). [\(r.title)](\(r.url.absoluteString))")
                if !r.snippet.isEmpty {
                    lines.append("   \(r.snippet)")
                }
            }
            if let summary = s.summary, !summary.isEmpty {
                lines.append("")
                lines.append("Summary: \(summary)")
            }
            return lines.joined(separator: "\n")
        case .linearBrief(let s):
            var lines = ["# Linear brief (your assigned issues)"]
            for issue in s.issues {
                let due = issue.dueDate.map {
                    let f = DateFormatter(); f.dateFormat = "MMM d"
                    return " (due \(f.string(from: $0)))"
                } ?? ""
                let state = issue.state.map { " — \($0)" } ?? ""
                lines.append("- [\(issue.identifier)] \(issue.title)\(state)\(due)")
            }
            return lines.joined(separator: "\n")
        case .slackBrief(let s):
            return "# Slack brief\n\(s.note)"
        }
    }
}
