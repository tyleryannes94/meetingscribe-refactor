import Foundation

/// Routes HTTP requests to the in-memory stores. Runs on `@MainActor` because
/// every store it touches (`MeetingManager`, `ActionItemStore`, `PeopleStore`)
/// is main-actor isolated — and writing *through* those stores means edits made
/// from the phone get the same persistence, index updates, dedup, and change
/// notifications as edits made in the desktop UI.
///
/// Auth: every `/api/*` request must present the shared token, either as the
/// `ms_token` cookie (set when the phone first opens the QR link) or an
/// `Authorization: Bearer <token>` header. The root page hands out the cookie.
@MainActor
final class WebAPI {
    private let manager: MeetingManager

    init(manager: MeetingManager) {
        self.manager = manager
    }

    private var actionItems: ActionItemStore { manager.actionItems }
    private var meetingStore: MeetingStore { manager.store }
    private var people: PeopleStore { PeopleStore.shared }

    // MARK: - Entry point

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let comps = request.components

        // Root page + handshake.
        if comps.isEmpty || comps == ["index.html"] {
            return serveRoot(request)
        }
        if comps == ["favicon.ico"] {
            return HTTPResponse(status: 204)
        }

        guard comps.first == "api" else {
            return .html(WebAssets.notFoundHTML, status: 404)
        }
        guard isAuthorized(request) else {
            return .error(401, "Unauthorized — open the link from the QR code in MeetingScribe → Settings.")
        }

        let rest = Array(comps.dropFirst())
        switch rest.first {
        case "health":   return health()
        case "meetings": return await meetings(request, rest)
        case "people":   return people(request, rest)
        case "projects": return projects(request, rest)
        case "tasks":    return tasks(request, rest)
        case "search":   return search(request)
        default:         return .error(404, "Unknown endpoint")
        }
    }

    // MARK: - Root / auth handshake

    private func serveRoot(_ request: HTTPRequest) -> HTTPResponse {
        let token = AppSettings.shared.webServerToken
        // QR-link handshake: ?t=<token> sets the cookie, then redirects to a
        // clean URL so the token doesn't linger in the address bar.
        if let t = request.query["t"], constantTimeEqual(t, token) {
            let cookie = "ms_token=\(token); Path=/; Max-Age=31536000; SameSite=Lax; HttpOnly"
            return .redirect(to: "/", setCookie: cookie)
        }
        if let c = request.cookies["ms_token"], constantTimeEqual(c, token) {
            return .html(WebAssets.appHTML)
        }
        return .html(WebAssets.unlockHTML)
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let token = AppSettings.shared.webServerToken
        guard !token.isEmpty else { return false }
        if let c = request.cookies["ms_token"], constantTimeEqual(c, token) { return true }
        if let auth = request.header("authorization"), auth.lowercased().hasPrefix("bearer ") {
            let presented = String(auth.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            if constantTimeEqual(presented, token) { return true }
        }
        if let t = request.query["t"], constantTimeEqual(t, token) { return true }
        return false
    }

    /// Length-checked, branch-free comparison so a near-miss token can't be
    /// timed out character by character.
    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in ab.indices { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }

    // MARK: - Health

    private func health() -> HTTPResponse {
        .jsonObject([
            "ok": true,
            "name": AppSettings.shared.userName,
            "meetings": meetingStore.listPastMeetings(limit: 100_000).count,
            "people": people.people.count,
            "projects": actionItems.projects.count,
            "tasks": actionItems.items.count
        ])
    }

    // MARK: - Meetings

    private func meetings(_ request: HTTPRequest, _ rest: [String]) async -> HTTPResponse {
        if rest.count == 1 {
            guard request.method == "GET" else { return .error(405, "Method not allowed") }
            let limit = Int(request.query["limit"] ?? "") ?? 200
            var list = meetingStore.listPastMeetings(limit: limit)
            if let q = request.query["q"]?.lowercased(), !q.isEmpty {
                list = list.filter {
                    $0.displayTitle.lowercased().contains(q)
                        || $0.attendees.joined(separator: " ").lowercased().contains(q)
                }
            }
            return .jsonObject(["meetings": list.map(meetingSummary)])
        }

        let id = rest[1]
        guard let meeting = meetingStore.listPastMeetings(limit: 100_000).first(where: { $0.id == id }) else {
            return .error(404, "Meeting not found")
        }

        switch request.method {
        case "GET":
            let dir = meetingStore.directory(for: meeting, primaryTag: nil)
            let transcript = await meetingStore.readTranscriptAsync(at: dir)
            let summary = await meetingStore.readSummaryAsync(at: dir)
            let userNotes = await meetingStore.readUserNotesAsync(at: dir)
            var dict = meetingSummary(meeting)
            dict["calendarNotes"] = meeting.notes ?? ""
            dict["userDescription"] = meeting.userDescription ?? ""
            dict["location"] = meeting.location ?? ""
            dict["conferenceURL"] = meeting.conferenceURL ?? ""
            dict["transcript"] = transcript
            dict["summary"] = summary
            dict["notes"] = userNotes
            return .jsonObject(dict)

        case "PUT":
            let body = jsonBody(request)
            var updated = meeting
            if let t = body["userTitle"] as? String {
                updated.userTitle = t.trimmingCharacters(in: .whitespaces).isEmpty ? nil : t
            }
            if let d = body["userDescription"] as? String {
                updated.userDescription = d
            }
            do { try meetingStore.writeMeeting(updated, primaryTag: nil) }
            catch { return .error(500, "Failed to save meeting") }
            if let notes = body["notes"] as? String {
                try? meetingStore.writeUserNotes(notes, for: updated, primaryTag: nil)
            }
            return .jsonObject(["ok": true])

        default:
            return .error(405, "Method not allowed")
        }
    }

    private func meetingSummary(_ m: Meeting) -> [String: Any] {
        var hasSummary = false
        if let rel = m.relativeFolderPath, !rel.isEmpty {
            let url = meetingStore.root
                .appendingPathComponent(rel)
                .appendingPathComponent("summary.md")
            hasSummary = FileManager.default.fileExists(atPath: url.path)
        }
        return [
            "id": m.id,
            "title": m.displayTitle,
            "start": isoString(m.startDate),
            "end": isoString(m.endDate),
            "attendees": m.attendees,
            "isImpromptu": m.isImpromptu,
            "hasSummary": hasSummary
        ]
    }

    // MARK: - People

    private func people(_ request: HTTPRequest, _ rest: [String]) -> HTTPResponse {
        if rest.count == 1 {
            switch request.method {
            case "GET":
                var list = people.people
                if let q = request.query["q"]?.lowercased(), !q.isEmpty {
                    list = list.filter {
                        $0.displayName.lowercased().contains(q) || $0.company.lowercased().contains(q)
                    }
                }
                return .jsonObject(["people": list.map(personSummary)])
            case "POST":
                let body = jsonBody(request)
                let name = (body["name"] as? String ?? body["displayName"] as? String ?? "")
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return .error(400, "name is required") }
                let person = people.createPerson(
                    displayName: name,
                    company: body["company"] as? String ?? "",
                    role: body["role"] as? String ?? "",
                    email: body["email"] as? String ?? "",
                    phone: body["phone"] as? String ?? "",
                    bio: (body["bio"] as? String) ?? (body["notes"] as? String) ?? "")
                return .jsonObject(personDetail(person), status: 201)
            default:
                return .error(405, "Method not allowed")
            }
        }

        let id = rest[1]
        guard let person = people.person(by: id) else { return .error(404, "Person not found") }

        switch request.method {
        case "GET":
            return .jsonObject(personDetail(person))
        case "PUT":
            let body = jsonBody(request)
            var updated = person
            if let v = (body["displayName"] as? String) ?? (body["name"] as? String) { updated.displayName = v }
            if let v = body["company"] as? String { updated.company = v }
            if let v = body["role"] as? String { updated.role = v }
            if let v = (body["bio"] as? String) ?? (body["notes"] as? String) { updated.bio = v }
            if let v = body["email"] as? String { updated.emails = v.isEmpty ? [] : [v] }
            if let v = body["phone"] as? String { updated.phones = v.isEmpty ? [] : [v] }
            people.updatePerson(updated)
            return .jsonObject(personDetail(updated))
        default:
            return .error(405, "Method not allowed")
        }
    }

    private func personSummary(_ p: Person) -> [String: Any] {
        var dict: [String: Any] = [
            "id": p.id,
            "name": p.displayName,
            "company": p.company,
            "role": p.role,
            "email": p.primaryEmail,
            "tags": tagNames(p.tagIDs)
        ]
        if let last = p.lastInteractionAt { dict["lastInteractionAt"] = isoString(last) }
        return dict
    }

    private func personDetail(_ p: Person) -> [String: Any] {
        var dict = personSummary(p)
        dict["bio"] = p.bio
        dict["emails"] = p.emails
        dict["phones"] = p.phones
        dict["favorites"] = p.favorites
        dict["createdAt"] = isoString(p.createdAt)

        let sortedMemories = p.memories.sorted { $0.createdAt > $1.createdAt }
        var memoryDicts: [[String: Any]] = []
        for m in sortedMemories {
            memoryDicts.append(["id": m.id, "text": m.text])
        }
        dict["memories"] = memoryDicts

        let sortedEncounters = people.encounters
            .filter { $0.personID == p.id }
            .sorted { $0.date > $1.date }
            .prefix(50)
        var encounterDicts: [[String: Any]] = []
        for e in sortedEncounters {
            encounterDicts.append([
                "id": e.id,
                "kind": e.meetingID != nil ? "meeting" : "note",
                "date": isoString(e.date),
                "title": e.eventName,
                "summary": e.notes,
                "location": e.location ?? "",
                "meetingID": e.meetingID ?? ""
            ])
        }
        dict["encounters"] = encounterDicts

        dict["tasks"] = actionItems.items(forPerson: p.id).map(taskSummary)
        return dict
    }

    private func tagNames(_ ids: Set<String>) -> [String] {
        ids.compactMap { PeopleTagStore.shared.tag(by: $0)?.name }.sorted()
    }

    // MARK: - Projects

    private func projects(_ request: HTTPRequest, _ rest: [String]) -> HTTPResponse {
        if rest.count == 1 {
            switch request.method {
            case "GET":
                let sorted = actionItems.projects.sorted {
                    if $0.status != $1.status { return $0.status == .active }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return .jsonObject(["projects": sorted.map(projectSummary)])
            case "POST":
                let body = jsonBody(request)
                guard let name = (body["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                    return .error(400, "name is required")
                }
                let project = actionItems.createProject(name: name)
                if let bodyText = body["body"] as? String { actionItems.setProjectBody(project.id, body: bodyText) }
                let fresh = actionItems.project(id: project.id) ?? project
                return .jsonObject(projectDetail(fresh), status: 201)
            default:
                return .error(405, "Method not allowed")
            }
        }

        let id = rest[1]
        guard let project = actionItems.project(id: id) else { return .error(404, "Project not found") }

        switch request.method {
        case "GET":
            return .jsonObject(projectDetail(project))
        case "PUT":
            let body = jsonBody(request)
            if let v = body["name"] as? String { actionItems.setProjectName(id, name: v) }
            if let v = body["body"] as? String { actionItems.setProjectBody(id, body: v) }
            if let v = body["status"] as? String, let s = Project.Status(rawValue: v) {
                actionItems.setProjectStatus(id, status: s)
            }
            let fresh = actionItems.project(id: id) ?? project
            return .jsonObject(projectDetail(fresh))
        default:
            return .error(405, "Method not allowed")
        }
    }

    private func projectSummary(_ p: Project) -> [String: Any] {
        [
            "id": p.id,
            "name": p.name,
            "icon": p.icon ?? "",
            "colorHex": p.colorHex ?? "",
            "status": p.status.rawValue,
            "openCount": actionItems.openCount(forProject: p.id)
        ]
    }

    private func projectDetail(_ p: Project) -> [String: Any] {
        var dict = projectSummary(p)
        dict["body"] = p.body
        dict["tasks"] = actionItems.items(forProject: p.id).map(taskSummary)
        let linked = (p.meetingIDs ?? []).compactMap { mid -> [String: Any]? in
            guard let m = meetingStore.listPastMeetings(limit: 100_000).first(where: { $0.id == mid }) else { return nil }
            return ["id": m.id, "title": m.displayTitle, "start": isoString(m.startDate)]
        }
        dict["meetings"] = linked
        return dict
    }

    // MARK: - Tasks

    private func tasks(_ request: HTTPRequest, _ rest: [String]) -> HTTPResponse {
        if rest.count == 1 {
            switch request.method {
            case "GET":
                var list = actionItems.items
                if let s = request.query["status"], let st = ActionItem.Status(rawValue: s) {
                    list = list.filter { $0.status == st }
                }
                if let pid = request.query["project"] { list = list.filter { $0.projectID == pid } }
                if let q = request.query["q"]?.lowercased(), !q.isEmpty {
                    list = list.filter { $0.title.lowercased().contains(q) }
                }
                let sorted = list.sorted { $0.updatedAt > $1.updatedAt }
                return .jsonObject(["tasks": sorted.map(taskSummary)])
            case "POST":
                let body = jsonBody(request)
                guard let title = (body["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
                    return .error(400, "title is required")
                }
                let item = actionItems.createTask(title: title, projectID: body["projectID"] as? String)
                if let p = body["priority"] as? String, let pr = ActionItem.Priority(rawValue: p) {
                    actionItems.setPriority(item.id, priority: pr)
                }
                if let due = parseDate(body["dueDate"] as? String) { actionItems.setDueDate(item.id, dueDate: due) }
                if let notes = body["notes"] as? String { actionItems.setNotes(item.id, notes: notes) }
                let fresh = actionItems.items.first { $0.id == item.id } ?? item
                return .jsonObject(taskSummary(fresh), status: 201)
            default:
                return .error(405, "Method not allowed")
            }
        }

        let id = rest[1]
        guard let item = actionItems.items.first(where: { $0.id == id }) else { return .error(404, "Task not found") }

        switch request.method {
        case "GET":
            return .jsonObject(taskSummary(item))
        case "PUT":
            let body = jsonBody(request)
            if let v = body["title"] as? String { actionItems.setTitle(id, title: v) }
            if let v = body["status"] as? String, let s = ActionItem.Status(rawValue: v) {
                actionItems.setStatus(id, status: s)
            }
            if let v = body["priority"] as? String, let p = ActionItem.Priority(rawValue: v) {
                actionItems.setPriority(id, priority: p)
            }
            if body.keys.contains("notes") { actionItems.setNotes(id, notes: body["notes"] as? String) }
            if body.keys.contains("dueDate") { actionItems.setDueDate(id, dueDate: parseDate(body["dueDate"] as? String)) }
            if body.keys.contains("projectID") { actionItems.setProject(id, projectID: body["projectID"] as? String) }
            let fresh = actionItems.items.first { $0.id == id } ?? item
            return .jsonObject(taskSummary(fresh))
        case "DELETE":
            actionItems.delete(id)
            return .jsonObject(["ok": true])
        default:
            return .error(405, "Method not allowed")
        }
    }

    private func taskSummary(_ t: ActionItem) -> [String: Any] {
        var dict: [String: Any] = [
            "id": t.id,
            "title": t.title,
            "status": t.status.rawValue,
            "priority": t.priority.rawValue,
            "notes": t.notes ?? "",
            "owner": t.owner ?? "",
            "meetingID": t.meetingID,
            "meetingTitle": t.meetingTitle,
            "createdAt": isoString(t.createdAt),
            "updatedAt": isoString(t.updatedAt)
        ]
        if let due = t.dueDate { dict["dueDate"] = isoString(due) }
        if let pid = t.projectID {
            dict["projectID"] = pid
            dict["projectName"] = actionItems.project(id: pid)?.name ?? ""
        }
        return dict
    }

    // MARK: - Search

    private func search(_ request: HTTPRequest) -> HTTPResponse {
        let q = (request.query["q"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return .jsonObject(["results": []]) }
        var results: [[String: Any]] = []

        for m in meetingStore.listPastMeetings(limit: 2000) where m.displayTitle.lowercased().contains(q) {
            results.append(["kind": "meeting", "id": m.id, "title": m.displayTitle, "subtitle": isoString(m.startDate)])
        }
        for p in people.people where p.displayName.lowercased().contains(q) || p.company.lowercased().contains(q) {
            results.append(["kind": "person", "id": p.id, "title": p.displayName, "subtitle": p.company])
        }
        for t in actionItems.items where t.title.lowercased().contains(q) {
            results.append(["kind": "task", "id": t.id, "title": t.title, "subtitle": t.status.label])
        }
        for pr in actionItems.projects where pr.name.lowercased().contains(q) {
            results.append(["kind": "project", "id": pr.id, "title": pr.name, "subtitle": pr.status.label])
        }
        return .jsonObject(["results": Array(results.prefix(60))])
    }

    // MARK: - Helpers

    private func jsonBody(_ request: HTTPRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private func isoString(_ date: Date) -> String { Self.isoFormatter.string(from: date) }
    private func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return Self.isoFormatter.date(from: s)
    }
}
