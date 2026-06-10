import Foundation
import VaultKit

/// Routes HTTP requests to the in-memory stores. Runs on `@MainActor` because
/// every store it touches (`MeetingManager`, `ActionItemStore`, `PeopleStore`,
/// `TagStore`, `DecisionStore`, `QuickNotesController`) is main-actor isolated —
/// and writing *through* those stores means edits made from the phone get the
/// same persistence, index updates, dedup, and change notifications as edits
/// made in the desktop UI.
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
    private var tagStore: TagStore { manager.tagStore }
    private var decisionStore: DecisionStore { manager.decisions }
    private var quickNotes: QuickNotesController { manager.quickNotesController }

    // MARK: - Entry point

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let comps = request.components

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
        case "health":     return health()
        case "today":      return today()
        case "meetings":   return await meetings(request, rest)
        case "people":     return people(request, rest)
        case "projects":   return projects(request, rest)
        case "tasks":      return tasks(request, rest)
        case "voicenotes": return voicenotes(request, rest)
        case "search":     return search(request)
        default:           return .error(404, "Unknown endpoint")
        }
    }

    // MARK: - Root / auth handshake

    private func serveRoot(_ request: HTTPRequest) -> HTTPResponse {
        let token = AppSettings.shared.webServerToken
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
            "tasks": actionItems.items.count,
            "voicenotes": quickNotes.notes.count
        ])
    }

    // MARK: - Meetings

    private func meetings(_ request: HTTPRequest, _ rest: [String]) async -> HTTPResponse {
        if rest.count == 1 {
            guard request.method == "GET" else { return .error(405, "Method not allowed") }
            let limit = Int(request.query["limit"] ?? "") ?? 300
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

        // /api/meetings/:id/audio?track=mic|system
        if rest.count >= 3, rest[2] == "audio" {
            let track = request.query["track"] == "system" ? "system.m4a" : "mic.m4a"
            let dir = meetingStore.directory(for: meeting, primaryTag: nil)
            return fileResponse(dir.appendingPathComponent(track), request: request, contentType: "audio/mp4")
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
            dict["calendarName"] = meeting.calendarName ?? ""
            dict["transcript"] = transcript
            dict["summary"] = summary
            dict["notes"] = userNotes

            // Tags
            var tagDicts: [[String: Any]] = []
            for t in tagStore.tags(for: meeting) {
                tagDicts.append(["name": t.name, "symbol": t.symbol ?? "", "colorHex": t.colorHex ?? ""])
            }
            dict["tags"] = tagDicts

            // Extracted action items for this meeting
            dict["actionItems"] = actionItems.items(for: meeting.id).map(taskSummary)

            // Decisions
            var decisionDicts: [[String: Any]] = []
            for d in decisionStore.decisions where d.meetingID == meeting.id {
                decisionDicts.append(["id": d.id, "text": d.text, "date": isoString(d.date)])
            }
            dict["decisions"] = decisionDicts

            // People mentioned in / linked to this meeting
            var mentionDicts: [[String: Any]] = []
            for p in people.people where p.meetingMentions.contains(meeting.id) {
                mentionDicts.append(["id": p.id, "name": p.displayName, "company": p.company])
            }
            dict["peopleMentioned"] = mentionDicts

            // Audio availability
            dict["audio"] = audioTracks(for: dir)
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

    private func audioTracks(for dir: URL) -> [String] {
        var tracks: [String] = []
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("mic.m4a").path) { tracks.append("mic") }
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("system.m4a").path) { tracks.append("system") }
        return tracks
    }

    private func meetingSummary(_ m: Meeting) -> [String: Any] {
        var hasSummary = false
        if let rel = m.relativeFolderPath, !rel.isEmpty {
            let url = meetingStore.root.appendingPathComponent(rel).appendingPathComponent("summary.md")
            hasSummary = FileManager.default.fileExists(atPath: url.path)
        }
        return [
            "id": m.id,
            "title": m.displayTitle,
            "start": isoString(m.startDate),
            "end": isoString(m.endDate),
            "attendees": m.attendees,
            "isImpromptu": m.isImpromptu,
            "isImported": m.isImported,
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

        // POST /api/people/:id/encounters — quick-log an encounter from the phone.
        if rest.count == 3, rest[2] == "encounters", request.method == "POST" {
            let body = jsonBody(request)
            let title = (body["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let notes = (body["notes"] as? String) ?? ""
            guard !title.isEmpty else { return .error(400, "title is required") }
            _ = people.addEncounter(to: id, eventName: title,
                                    location: (body["location"] as? String),
                                    notes: notes)
            let fresh = people.person(by: id) ?? person
            return .jsonObject(personDetail(fresh), status: 201)
        }

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
            "tags": tagNames(p.tagIDs),
            "relationshipType": p.relationshipType.rawValue,
            "relationshipLabel": p.relationshipType.displayName
        ]
        if let last = p.lastInteractionAt { dict["lastInteractionAt"] = isoString(last) }
        if let h = personHealth(p) { dict["health"] = h }
        return dict
    }

    /// Server-computed connection health for typed relationships — same shared
    /// `VaultKit.RelationshipHealth` the desktop badge + MCP tool use, so the
    /// phone shows the identical score.
    private func personHealth(_ p: Person) -> [String: Any]? {
        guard p.relationshipType != .unset else { return nil }
        let encs = people.encounters(for: p.id)
        let dates = encs.map(\.date).sorted(by: >)
        let medianGap: Int = {
            guard dates.count >= 2 else { return 0 }
            var gaps = (0..<(dates.count - 1)).map { Int(dates[$0].timeIntervalSince(dates[$0 + 1]) / 86400) }
            gaps.sort()
            return gaps[gaps.count / 2]
        }()
        let last = dates.first ?? p.lastInteractionAt
        let daysSince = last.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 9_999
        let h = RelationshipHealth(daysSinceLast: daysSince, cadenceDays: p.effectiveCheckInDays,
                                   encounterCount: encs.count, medianGapDays: medianGap)
        return ["score": h.score, "band": h.band.rawValue,
                "daysSinceLast": daysSince, "overdue": daysSince > p.effectiveCheckInDays]
    }

    // MARK: - Today (home dashboard)

    /// Aggregated home payload mirroring the desktop Today tab: drifting
    /// relationships (worst health first), tasks due/overdue, and recent meetings.
    private func today() -> HTTPResponse {
        let now = Date()

        // Drifting typed relationships — overdue, ordered by lowest health.
        let drift = people.people
            .filter { $0.relationshipType != .unset }
            .compactMap { p -> (Person, [String: Any])? in
                guard let h = personHealth(p), (h["overdue"] as? Bool) == true else { return nil }
                return (p, h)
            }
            .sorted { (($0.1["score"] as? Int) ?? 0) < (($1.1["score"] as? Int) ?? 0) }
            .prefix(8)
            .map { personSummary($0.0) }

        // Tasks due within 7 days or already overdue (open only).
        let soon = now.addingTimeInterval(7 * 86400)
        let dueTasks = actionItems.openItems()
            .filter { item in
                guard let due = item.dueDate else { return false }
                return due <= soon
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(12)
            .map(taskSummary)

        let recentMeetings = meetingStore.listPastMeetings(limit: 6).map(meetingSummary)

        return .jsonObject([
            "drift": Array(drift),
            "dueTasks": Array(dueTasks),
            "recentMeetings": recentMeetings
        ])
    }

    private func personDetail(_ p: Person) -> [String: Any] {
        var dict = personSummary(p)
        dict["bio"] = p.bio
        dict["emails"] = p.emails
        dict["phones"] = p.phones
        dict["addresses"] = p.addresses
        dict["favorites"] = p.favorites
        dict["createdAt"] = isoString(p.createdAt)
        if let bday = p.birthday { dict["birthday"] = isoString(bday) }
        dict["importSources"] = Array(p.importSources).sorted()

        // Memories
        var memoryDicts: [[String: Any]] = []
        for m in p.memories.sorted(by: { $0.createdAt > $1.createdAt }) {
            var md: [String: Any] = ["id": m.id, "text": m.text]
            if let on = m.occurredOn { md["occurredOn"] = isoString(on) }
            memoryDicts.append(md)
        }
        dict["memories"] = memoryDicts

        // Attached notes (analyses)
        var noteDicts: [[String: Any]] = []
        for n in p.attachedNotes.sorted(by: { $0.createdAt > $1.createdAt }) {
            noteDicts.append(["id": n.id, "title": n.title, "kind": n.kind, "body": n.body])
        }
        dict["attachedNotes"] = noteDicts

        // Relationships (resolve names)
        var relDicts: [[String: Any]] = []
        for r in p.relationships {
            relDicts.append([
                "id": r.id,
                "label": r.label,
                "toPersonID": r.toPersonID,
                "toPersonName": people.person(by: r.toPersonID)?.displayName ?? "Unknown"
            ])
        }
        dict["relationships"] = relDicts

        // Encounters
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

        // Meetings this person is mentioned in
        if !p.meetingMentions.isEmpty {
            var byID: [String: Meeting] = [:]
            for m in meetingStore.listPastMeetings(limit: 100_000) { byID[m.id] = m }
            var mentionDicts: [[String: Any]] = []
            for mid in p.meetingMentions {
                guard let m = byID[mid] else { continue }
                mentionDicts.append(["id": m.id, "title": m.displayTitle, "start": isoString(m.startDate)])
            }
            dict["mentionedIn"] = mentionDicts.sorted {
                ($0["start"] as? String ?? "") > ($1["start"] as? String ?? "")
            }
        } else {
            dict["mentionedIn"] = [[String: Any]]()
        }

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
        var dict: [String: Any] = [
            "id": p.id,
            "name": p.name,
            "icon": p.icon ?? "",
            "colorHex": p.colorHex ?? "",
            "status": p.status.rawValue,
            "openCount": actionItems.openCount(forProject: p.id)
        ]
        if let iid = p.initiativeID, let initiative = actionItems.initiative(id: iid) {
            dict["initiative"] = initiative.name
        }
        return dict
    }

    private func projectDetail(_ p: Project) -> [String: Any] {
        var dict = projectSummary(p)
        dict["body"] = p.body
        dict["tasks"] = actionItems.items(forProject: p.id).map(taskSummary)

        // Sections
        var sectionDicts: [[String: Any]] = []
        for s in actionItems.sections(forProject: p.id) {
            sectionDicts.append(["id": s.id, "name": s.name])
        }
        dict["sections"] = sectionDicts

        // Child projects
        var childDicts: [[String: Any]] = []
        for c in actionItems.childProjects(of: p.id) {
            childDicts.append(["id": c.id, "name": c.name, "openCount": actionItems.openCount(forProject: c.id)])
        }
        dict["children"] = childDicts

        // Linked meetings
        var linked: [[String: Any]] = []
        if let mids = p.meetingIDs, !mids.isEmpty {
            var byID: [String: Meeting] = [:]
            for m in meetingStore.listPastMeetings(limit: 100_000) { byID[m.id] = m }
            for mid in mids {
                guard let m = byID[mid] else { continue }
                linked.append(["id": m.id, "title": m.displayTitle, "start": isoString(m.startDate)])
            }
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
        guard actionItems.items.contains(where: { $0.id == id }) else { return .error(404, "Task not found") }

        // Subtasks: /api/tasks/:id/subtasks  and  /api/tasks/:id/subtasks/:subID
        if rest.count >= 3, rest[2] == "subtasks" {
            if rest.count == 3, request.method == "POST" {
                let body = jsonBody(request)
                guard let title = (body["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
                    return .error(400, "title is required")
                }
                actionItems.addSubtask(id, title: title)
            } else if rest.count == 4, request.method == "PUT" {
                actionItems.toggleSubtask(id, subtaskID: rest[3])
            } else if rest.count == 4, request.method == "DELETE" {
                actionItems.deleteSubtask(id, subtaskID: rest[3])
            } else {
                return .error(405, "Method not allowed")
            }
            let fresh = actionItems.items.first { $0.id == id }!
            return .jsonObject(taskSummary(fresh))
        }

        let item = actionItems.items.first(where: { $0.id == id })!
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
            if body.keys.contains("startDate") { actionItems.setStartDate(id, startDate: parseDate(body["startDate"] as? String)) }
            if body.keys.contains("owner") { actionItems.setOwner(id, owner: body["owner"] as? String) }
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
        if let start = t.startDate { dict["startDate"] = isoString(start) }
        if let sid = t.sectionID { dict["sectionID"] = sid }
        if let pid = t.projectID {
            dict["projectID"] = pid
            dict["projectName"] = actionItems.project(id: pid)?.name ?? ""
        }
        // Subtasks
        var subDicts: [[String: Any]] = []
        for s in t.subtaskList {
            subDicts.append(["id": s.id, "title": s.title, "done": s.done])
        }
        dict["subtasks"] = subDicts
        // Labels
        var labelDicts: [[String: Any]] = []
        for l in actionItems.labels(for: t) {
            labelDicts.append(["id": l.id, "name": l.name, "colorHex": l.colorHex])
        }
        dict["labels"] = labelDicts
        return dict
    }

    // MARK: - Voice notes

    private func voicenotes(_ request: HTTPRequest, _ rest: [String]) -> HTTPResponse {
        if rest.count == 1 {
            guard request.method == "GET" else { return .error(405, "Method not allowed") }
            quickNotes.refresh()
            var list = quickNotes.notes
            if let q = request.query["q"]?.lowercased(), !q.isEmpty {
                list = list.filter { $0.title.lowercased().contains(q) || $0.snippet.lowercased().contains(q) }
            }
            return .jsonObject(["voicenotes": list.map(voiceNoteSummary)])
        }

        let id = rest[1]
        guard let note = quickNotes.notes.first(where: { $0.id == id }) else {
            return .error(404, "Voice note not found")
        }

        // /api/voicenotes/:id/audio
        if rest.count >= 3, rest[2] == "audio" {
            let url = quickNotes.audioURL(note)
            return fileResponse(url, request: request, contentType: "audio/mp4")
        }

        switch request.method {
        case "GET":
            var dict = voiceNoteSummary(note)
            dict["transcript"] = quickNotes.readTranscript(note)
            dict["polished"] = quickNotes.readPolished(note)
            dict["hasAudio"] = FileManager.default.fileExists(atPath: quickNotes.audioURL(note).path)
            return .jsonObject(dict)
        case "PUT":
            let body = jsonBody(request)
            if let transcript = body["transcript"] as? String { quickNotes.saveTranscript(transcript, for: note) }
            if let polished = body["polished"] as? String { quickNotes.savePolished(polished, for: note) }
            return .jsonObject(["ok": true])
        case "DELETE":
            quickNotes.delete(note)
            return .jsonObject(["ok": true])
        default:
            return .error(405, "Method not allowed")
        }
    }

    private func voiceNoteSummary(_ n: QuickNote) -> [String: Any] {
        [
            "id": n.id,
            "title": n.title,
            "createdAt": isoString(n.createdAt),
            "durationSeconds": n.durationSeconds,
            "snippet": n.snippet,
            "wasDictation": n.wasDictation
        ]
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
        for n in quickNotes.notes where n.title.lowercased().contains(q) || n.snippet.lowercased().contains(q) {
            results.append(["kind": "voicenote", "id": n.id, "title": n.title, "subtitle": n.snippet])
        }
        return .jsonObject(["results": Array(results.prefix(80))])
    }

    // MARK: - File serving (audio, with Range support)

    /// Serves a file honoring HTTP Range requests, so iOS Safari's `<audio>`
    /// element can stream and seek. Open-ended / missing ranges are capped to a
    /// chunk so a large recording never has to be buffered whole in memory.
    private func fileResponse(_ url: URL, request: HTTPRequest, contentType: String) -> HTTPResponse {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeNum = attrs[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return .error(404, "File not found")
        }
        defer { try? handle.close() }
        let size = sizeNum.intValue
        guard size > 0 else { return .error(404, "Empty file") }
        let maxChunk = 2 * 1024 * 1024

        var start = 0
        var end = size - 1
        var partial = false
        if let range = request.header("range"), range.hasPrefix("bytes=") {
            partial = true
            let spec = range.dropFirst("bytes=".count)
            let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            start = Int(parts.first ?? "") ?? 0
            if parts.count > 1, let e = Int(parts[1]), e >= start { end = e }
        }
        // Cap the served chunk.
        if end - start + 1 > maxChunk { end = min(start + maxChunk - 1, size - 1) }
        if start >= size {
            return HTTPResponse(status: 416,
                                headers: ["Content-Range": "bytes */\(size)", "Accept-Ranges": "bytes"])
        }

        let length = end - start + 1
        try? handle.seek(toOffset: UInt64(start))
        let data = (try? handle.read(upToCount: length)) ?? Data()

        var headers: [String: String] = [
            "Content-Type": contentType,
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store"
        ]
        if partial || end < size - 1 {
            headers["Content-Range"] = "bytes \(start)-\(end)/\(size)"
            return HTTPResponse(status: 206, headers: headers, body: data)
        }
        return HTTPResponse(status: 200, headers: headers, body: data)
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
