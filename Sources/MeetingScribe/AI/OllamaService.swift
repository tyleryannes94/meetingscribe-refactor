import Foundation
import OSLog
import os

/// Talks to a local Ollama instance (default http://127.0.0.1:11434) to summarize
/// transcripts. Uses `/api/generate` with streaming disabled for simplicity.
final class OllamaService {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Ollama")

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let options: Options
        struct Options: Encodable {
            let temperature: Double
            let num_ctx: Int
        }
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    /// One NDJSON frame from a streaming `/api/generate` response (1-C).
    private struct StreamChunk: Decodable {
        let response: String?
        let done: Bool?
    }

    // MARK: - Meeting-type templates (C1-8)
    //
    // The summary prompt used to be one-size-fits-all, so a 1:1 recap and a
    // sales-call recap came out shaped identically. We infer the meeting TYPE
    // from its title + attendee count and inject a short, type-specific
    // instruction block into the prompt so summaries become scannable documents
    // shaped to the meeting kind. `.general` injects nothing, preserving the
    // exact pre-existing prompt for anything we can't confidently classify.

    enum MeetingType {
        case oneOnOne, standup, salesCall, interview, general

        /// Best-effort classification from the meeting's title and attendee
        /// count. Conservative by design: when no clear signal is present we
        /// return `.general`, which leaves today's prompt unchanged.
        static func infer(from meeting: Meeting) -> MeetingType {
            // Prefer a user-edited title if present; otherwise the invite title.
            let title = (meeting.userTitle ?? meeting.title).lowercased()
            let attendeeCount = meeting.attendees.count

            func titleHas(_ needles: [String]) -> Bool {
                needles.contains { title.contains($0) }
            }

            // Explicit title keywords win, checked specific → broad so that an
            // "Interview / demo prep" leans interview rather than salesCall.
            if titleHas(["interview", "candidate", "screen"]) { return .interview }
            if titleHas(["sales", "demo", "discovery", "prospect"]) { return .salesCall }
            if titleHas(["standup", "stand-up", "scrum", "daily"]) { return .standup }
            if titleHas(["1:1", "1-on-1", "1 on 1", "one on one", "one-on-one"]) { return .oneOnOne }

            // "<Name A> / <Name B>" sync naming — only a 1:1 when it's really
            // two people.
            if title.contains(" / "), attendeeCount <= 2 { return .oneOnOne }

            // Attendee-count tiebreaker, used ONLY when the title gave no signal:
            // exactly two participants with a neutral title leans 1:1. Anything
            // else (0, 1, or many) stays conservative and falls back to general.
            if attendeeCount == 2 { return .oneOnOne }

            return .general
        }

        /// Short instruction block injected into the summary prompt. Empty for
        /// `.general` so the assembled prompt is byte-for-byte unchanged.
        var instructionBlock: String {
            switch self {
            case .general:
                return ""
            case .oneOnOne:
                return """
                This was a 1:1. Focus on what each person committed to, the \
                follow-ups and blockers each owns, and any feedback or growth \
                notes that came up. Keep it personal and forward-looking.
                """
            case .standup:
                return """
                This was a standup. Organize the recap per person as \
                yesterday / today / blockers. Keep each entry terse, and \
                surface blockers prominently so they aren't buried.
                """
            case .salesCall:
                return """
                This was a sales call. Capture the prospect's needs and pain \
                points, objections raised, any budget / timeline / \
                decision-maker signals, and clear next steps to advance the deal.
                """
            case .interview:
                return """
                This was an interview. Summarize the signal on each competency \
                discussed, the candidate's strengths and any concerns, citing \
                evidence from the transcript. Stay neutral and evidence-based, \
                and end with a hire / no-hire recommendation prompt.
                """
            }
        }
    }

    enum SummaryError: Error, LocalizedError {
        case unreachable(String)
        case notInstalled
        case http(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .unreachable(let m):
                return "Could not reach the local AI engine (Ollama): \(m). Open MeetingScribe's setup check to start it, or launch Ollama from Applications."
            case .notInstalled:
                return "The local AI engine (Ollama) isn't installed yet. Open MeetingScribe's setup check to install it — no Terminal needed."
            case .http(let c, let m): return "Ollama HTTP \(c): \(m)"
            case .decode(let m): return "Could not decode Ollama response: \(m)"
            }
        }
    }

    /// Common locations where `brew install ollama` puts the CLI.
    private static let candidateBinaries: [String] = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/opt/homebrew/opt/ollama/bin/ollama"
    ]

    /// Returns the first ollama binary that exists, or nil if none.
    static var binaryPath: String? {
        candidateBinaries.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Connection state machine (audit 4.5)
    //
    // Was: every generate() / summarize() call probed reachability via a
    // fresh HTTP request, even when Ollama was obviously up because we'd
    // just successfully talked to it. With auto-polish running for every
    // new voice note, that meant N redundant probes per minute.
    //
    // Now: track the last known state with a short freshness window. The
    // probe still runs when the state is stale or the last call failed,
    // but a stream of back-to-back generates only pays one probe.

    enum ConnectionState: Equatable, Sendable {
        case unknown
        case connected(at: Date)
        case disconnected(at: Date, reason: String?)
    }

    /// Process-shared state, protected with an unfair-lock so multiple
    /// concurrent generate() calls don't race the state mutation.
    private static let stateLock = OSAllocatedUnfairLock<ConnectionState>(initialState: .unknown)
    private static let freshnessWindow: TimeInterval = 5

    /// Best-known reachability without any I/O. Useful for UI badges.
    static var cachedState: ConnectionState { stateLock.withLock { $0 } }

    private static func recordReachable() {
        stateLock.withLock { $0 = .connected(at: Date()) }
    }
    private static func recordUnreachable(_ reason: String?) {
        stateLock.withLock { $0 = .disconnected(at: Date(), reason: reason) }
    }

    /// Pings `/api/tags` to check whether the local Ollama server is up. Fast
    /// — short timeout, no startup attempt. Safe to call frequently. Caches
    /// successful results for `freshnessWindow` seconds so a burst of calls
    /// pays only one round-trip.
    func isReachable(allowCache: Bool = true) async -> Bool {
        if allowCache, case let .connected(at) = Self.cachedState,
           Date().timeIntervalSince(at) < Self.freshnessWindow {
            return true
        }
        let url = AppSettings.shared.ollamaURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if ok { Self.recordReachable() } else { Self.recordUnreachable("HTTP not 200") }
            return ok
        } catch {
            Self.recordUnreachable(error.localizedDescription)
            return false
        }
    }

    /// If Ollama isn't running, launches `ollama serve` as a detached process
    /// via `nohup` (so it outlives our app). Waits up to `timeout` seconds
    /// for it to respond. Returns true if Ollama is reachable by the end.
    @discardableResult
    func ensureRunning(timeout: TimeInterval = 10) async -> Bool {
        if await isReachable() { return true }
        guard let binary = Self.binaryPath else {
            log.error("ollama not installed in any known location")
            AppLog.error("Ollama", "Binary not found in any known Homebrew location")
            return false
        }
        // Per-user log location (was: /tmp/meetingscribe-ollama.log, which is
        // world-readable on macOS — a security smell even though Ollama's
        // stdout rarely contains anything sensitive). NSTemporaryDirectory()
        // resolves to /var/folders/.../T/ which is per-user 700.
        let logDir = AppSettings.shared.storageDir.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logPath = logDir.appendingPathComponent("ollama.log").path

        // Launch via the binary directly with detached I/O — no shell-injection
        // surface, no quoting bugs around paths with spaces.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["serve"]
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            proc.standardOutput = handle
            proc.standardError = handle
        } else if FileManager.default.createFile(atPath: logPath, contents: nil),
                  let handle = FileHandle(forWritingAtPath: logPath) {
            proc.standardOutput = handle
            proc.standardError = handle
        } else {
            // Fallback: discard if we can't open the log file.
            proc.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
            proc.standardError = FileHandle(forWritingAtPath: "/dev/null")
        }
        // Detach so the child outlives the app's lifetime.
        proc.qualityOfService = .utility
        do {
            try proc.run()
        } catch {
            ErrorReporter.shared.reportAsync(error, category: .integration,
                                             context: ["service": "ollama", "binary": binary])
            return false
        }
        AppLog.info("Ollama", "Launched ollama serve — polling for readiness",
                    ["log": logPath, "binary": binary])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await isReachable() {
                AppLog.info("Ollama", "Ollama is up")
                return true
            }
        }
        AppLog.error("Ollama", "Ollama did not respond within \(Int(timeout))s",
                     ["log": logPath])
        return false
    }

    /// Generic prompt → completion. Used by anything that needs to talk to
    /// the local LLM with a custom prompt (transcript polishing, ad-hoc
    /// helpers, etc.). Calls /api/generate with streaming off.
    func generate(prompt: String,
                  temperature: Double = 0.2,
                  numCtx: Int = 8192) async throws -> String {
        let settings = AppSettings.shared
        if !(await isReachable()) {
            guard Self.binaryPath != nil else { throw SummaryError.notInstalled }
            _ = await ensureRunning()
            guard await isReachable() else { throw SummaryError.unreachable("auto-start timed out") }
        }

        let url = settings.ollamaURL.appendingPathComponent("api/generate")
        // E4-3: refuse to POST content to a non-local endpoint unless approved.
        try EgressPolicy.assertOllamaEgressAllowed(url)
        let body = GenerateRequest(
            model: settings.ollamaModel,
            prompt: prompt,
            stream: false,
            options: .init(temperature: temperature, num_ctx: numCtx)
        )
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 600

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw SummaryError.unreachable(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.http(-1, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SummaryError.http(http.statusCode,
                                    String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 3-D: pull a strict `## Action Items` section out of free text (a voice
    /// note transcript), in the same format `ActionItemExtractor` parses for
    /// meetings. Returns the markdown; the caller runs the extractor on it.
    func extractActionItems(from transcript: String) async throws -> String {
        let aliases = AppSettings.shared.myNameAliases.joined(separator: ", ")
        let prompt = """
        You extract action items from a voice note. Output ONLY a Markdown \
        section, nothing else:

        ## Action Items
        - [ ] <owner> — <action> (due: <date or "unspecified">)

        Rules:
        - Every item starts with an owner. Use "Me" when the speaker (\(aliases)) \
        committed to it; use a person's name for tasks owned by someone else.
        - Include a due date only if one is stated.
        - If there are no clear action items, output exactly: None.
        - Do NOT add any other sections, preamble, or commentary.

        TRANSCRIPT:
        \(transcript)
        """
        return try await generate(prompt: prompt, temperature: 0.2, numCtx: 4096)
    }

    /// Stream tokens from `/api/generate` (stream:true, NDJSON), invoking
    /// `onToken` for each chunk as it arrives and returning the full text (1-C).
    /// Turns the 30–90s blank wait on a summary into a live "thinking" view.
    /// `onToken` is invoked off the main actor — hop to main in UI callers.
    func streamGenerate(prompt: String,
                        temperature: Double = 0.2,
                        numCtx: Int = 8192,
                        onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        let settings = AppSettings.shared
        if !(await isReachable()) {
            guard Self.binaryPath != nil else { throw SummaryError.notInstalled }
            _ = await ensureRunning()
            guard await isReachable() else { throw SummaryError.unreachable("auto-start timed out") }
        }
        let url = settings.ollamaURL.appendingPathComponent("api/generate")
        try EgressPolicy.assertOllamaEgressAllowed(url)
        let body = GenerateRequest(model: settings.ollamaModel, prompt: prompt, stream: true,
                                   options: .init(temperature: temperature, num_ctx: numCtx))
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 600

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do { (bytes, response) = try await URLSession.shared.bytes(for: req) }
        catch { throw SummaryError.unreachable(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw SummaryError.http(-1, "no http response") }
        guard (200..<300).contains(http.statusCode) else { throw SummaryError.http(http.statusCode, "") }

        var full = ""
        for try await line in bytes.lines {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { continue }
            if let piece = chunk.response, !piece.isEmpty { full += piece; onToken(piece) }
            if chunk.done == true { break }
        }
        return full.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Summarize, optionally streaming tokens to `onToken` as they arrive (1-C).
    /// When `onToken` is nil the behavior is identical to the original blocking
    /// call, so every existing caller is unaffected.
    func summarize(meeting: Meeting, transcript: String,
                   summaryGuidance: String? = nil,
                   onToken: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let settings = AppSettings.shared

        // Make sure Ollama is up. Cheap if it already is, otherwise auto-launches.
        if !(await isReachable()) {
            guard Self.binaryPath != nil else { throw SummaryError.notInstalled }
            _ = await ensureRunning()
            guard await isReachable() else {
                throw SummaryError.unreachable("auto-start timed out")
            }
        }

        let url = settings.ollamaURL.appendingPathComponent("api/generate")
        // E4-3: the transcript must not leave the device via a non-local URL.
        try EgressPolicy.assertOllamaEgressAllowed(url)

        let prompt = Self.buildPrompt(meeting: meeting, transcript: transcript, summaryGuidance: summaryGuidance)
        if let onToken {
            return try await streamGenerate(prompt: prompt, temperature: 0.2, numCtx: 6144, onToken: onToken)
        }
        let body = GenerateRequest(
            model: settings.ollamaModel,
            prompt: prompt,
            stream: false,
            options: .init(temperature: 0.2, num_ctx: 6144)
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 600

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw SummaryError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.http(-1, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            throw SummaryError.http(http.statusCode, s)
        }
        do {
            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw SummaryError.decode(error.localizedDescription)
        }
    }

    private static func buildPrompt(meeting: Meeting, transcript: String,
                                    summaryGuidance: String? = nil) -> String {
        let userName = AppSettings.shared.userName
        let attendees = meeting.attendees.isEmpty ? "Unknown" : meeting.attendees.joined(separator: ", ")
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: meeting.startDate)

        let feedback = SummaryFeedback.steeringNote(for: meeting.id).map {
            "\n\nThe user was unhappy with the previous summary for this meeting. Their feedback: \"\($0)\". Address it directly in this version.\n"
        } ?? ""

        // C1-8: type-specific shaping. Empty (and thus a no-op) for `.general`,
        // so untyped meetings get exactly the prompt they got before.
        let typeGuidance = MeetingType.infer(from: meeting).instructionBlock
        let typeBlock = typeGuidance.isEmpty ? "" : "\n\n\(typeGuidance)"
        // Per-tag custom instructions (when the meeting's tag defines a template).
        let tagBlock = (summaryGuidance?.isEmpty == false)
            ? "\n\nAdditional instructions for this meeting's category:\n\(summaryGuidance!)"
            : ""

        return """
        You are a professional meeting summarizer. Your job is to produce a complete, standalone summary of the meeting below — thorough enough that someone who wasn't on the call can fully understand everything that was discussed, decided, and left open. The reader should not need to consult the transcript.\(feedback)\(typeBlock)\(tagBlock)

        Meeting: \(meeting.title)
        When: \(when)
        Attendees: \(attendees)

        Transcript ("Me" = \(userName), "Them" = all other speakers):

        \(transcript)

        ---

        Write the summary now using EXACTLY these sections in order. Do not skip any section. Do not add new sections. No preamble before the title.

        # \(meeting.title) — Meeting Summary

        ## What Was Discussed
        Write a detailed narrative paragraph (not bullets) for each major topic, in the order it came up. Each paragraph should cover: what was raised, the full substance of the conversation around it, any disagreements or open exploration, and how or whether it was resolved. Be thorough — a reader must understand the full context of each topic without the transcript. Include specifics: numbers, names, deadlines, product names, amounts, percentages — anything concrete that was mentioned. If a topic had multiple sub-threads, cover each one. Aim for completeness over brevity.

        ## Key Decisions
        A bulleted list of every concrete decision reached. Each bullet: what was decided, who decided it, and why (the reasoning given in the call). If a decision was tentative or conditional, say so. If no decisions were made, write "No formal decisions were made."

        ## Action Items
        A task checklist of every commitment made. Format each as:
        - [ ] **[Owner]** — [exactly what they will do] (due: [date if mentioned, otherwise "unspecified"])
        Only assign \(userName) as owner when they personally committed on the call. Use full names or roles for others. Be precise — "review the contract draft" is better than "follow up." If none, write "No action items."

        ## Open Questions
        A bulleted list of every unresolved question, blocker, or topic that needs follow-up. Include who raised it if relevant. Be specific about what is unknown or undecided. If none, write "None identified."

        Keep every section. Be direct and specific throughout. No filler phrases like "the team discussed" or "it was noted that."
        """
    }
}
