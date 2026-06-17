import Foundation
import SQLite3
import OSLog

/// Per-person iMessage/SMS analysis (Phase C). Reads the local Messages
/// database (`~/Library/Messages/chat.db`) read-only and matches a person's
/// emails/phone numbers to message handles to compute conversation stats.
///
/// Requires **Full Disk Access** (System Settings → Privacy & Security → Full
/// Disk Access → enable MeetingScribe), because macOS protects `chat.db` behind
/// TCC. Everything stays local — nothing is uploaded.
enum MessagesAnalyzer {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Messages")

    static var chatDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
    }

    struct Stats: Equatable {
        var total = 0
        var sent = 0
        var received = 0
        var firstDate: Date?
        var lastDate: Date?
        var last30 = 0
        var last90 = 0
        var matchedHandles: [String] = []
    }

    enum AnalyzeError: LocalizedError {
        case needsFullDiskAccess
        case noHandles
        case sqlite(String)
        var errorDescription: String? {
            switch self {
            case .needsFullDiskAccess:
                return "Can't read Messages. Grant Full Disk Access: System Settings → Privacy & Security → Full Disk Access → enable MeetingScribe, then relaunch."
            case .noHandles:
                return "No phone number or email on this person matches a Messages conversation."
            case .sqlite(let m): return "Messages database error: \(m)"
            }
        }
    }

    /// Cheap probe: can we open chat.db at all? (False usually means no FDA.)
    static func hasAccess() -> Bool {
        var db: OpaquePointer?
        defer { if db != nil { sqlite3_close(db) } }
        return sqlite3_open_v2(chatDBURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
    }

    /// A recent message for the optional Ollama topic summary.
    struct Snippet { let fromMe: Bool; let date: Date; let text: String }

    /// What slice of the conversation to analyze. Lets the user pick a window
    /// instead of being forced to all-time history. `.allTime` keeps the
    /// original behavior (and is the default so existing callers are unchanged).
    enum MessageWindow: Equatable, Hashable {
        case allTime
        case lastDays(Int)
        case since(Date)
        case between(Date, Date)

        /// Lower/upper bounds in chat.db's "Apple nanoseconds since 2001" scale
        /// (nil = unbounded). Modern chat.db rows use the ns scale.
        func appleDateBounds(now: Date = Date()) -> (lower: Int64?, upper: Int64?) {
            func ns(_ d: Date) -> Int64 { Int64(d.timeIntervalSinceReferenceDate * 1_000_000_000) }
            switch self {
            case .allTime:              return (nil, nil)
            case .lastDays(let n):      return (ns(now.addingTimeInterval(-Double(max(0, n)) * 86400)), nil)
            case .since(let d):         return (ns(d), nil)
            case .between(let a, let b): return (ns(min(a, b)), ns(max(a, b)))
            }
        }

        /// Short human label for menus / headers.
        var label: String {
            switch self {
            case .allTime:          return "All time"
            case .lastDays(let n):  return "Last \(n) days"
            case .since:            return "Since date"
            case .between:          return "Date range"
            }
        }

        /// The fixed presets a picker offers (custom ranges are built separately).
        static let presets: [MessageWindow] =
            [.allTime, .lastDays(30), .lastDays(90), .lastDays(365)]
    }

    static func analyze(person: Person,
                        recentLimit: Int = 60,
                        scope: MessageWindow = .allTime) throws -> (stats: Stats, recent: [Snippet]) {
        guard FileManager.default.fileExists(atPath: chatDBURL.path) else {
            throw AnalyzeError.needsFullDiskAccess
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(chatDBURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, db != nil else {
            if db != nil { sqlite3_close(db) }
            throw AnalyzeError.needsFullDiskAccess
        }
        defer { sqlite3_close(db) }

        let handleRowIDs = try matchingHandleRowIDs(db: db, person: person)
        guard !handleRowIDs.isEmpty else { throw AnalyzeError.noHandles }

        let idList = handleRowIDs.map(String.init).joined(separator: ",")

        // PERF (was the dominant cost in chat): the old single-query path
        // walked EVERY row in the 1:1 chat — for a 41 k-message contact,
        // that meant 41 k SQLite rows AND 41 k attributedBody parses on
        // every chat call, just to take the last 40 for snippets. Now we
        // do two scoped queries instead:
        //
        //   1. Aggregate SELECT for stats. Counts run inside SQLite and
        //      return a single row — milliseconds even for 100 k+ rows.
        //   2. ORDER BY date DESC LIMIT N for snippets. The attributedBody
        //      parser only ever runs on N rows, not the whole table.
        //
        // Both queries share the same 1:1-chat filter so the numbers stay
        // consistent with the old behavior.

        // Apple-date thresholds for 30/90 day windows (nanoseconds since
        // 2001 reference date). Modern chat.db rows use the ns scale;
        // legacy seconds-scale rows are rare and would slightly undercount
        // here — acceptable for "rough recency" stats.
        let nowSec = Date().timeIntervalSinceReferenceDate
        let cutoff30Ns = Int64((nowSec - 30 * 86400) * 1_000_000_000)
        let cutoff90Ns = Int64((nowSec - 90 * 86400) * 1_000_000_000)

        var chatFilter = """
        WHERE cmj.chat_id IN (
            SELECT chj.chat_id FROM chat_handle_join chj
            WHERE chj.handle_id IN (\(idList))
            AND chj.chat_id IN (
                SELECT chat_id FROM chat_handle_join GROUP BY chat_id HAVING COUNT(*) = 1
            )
        )
        """
        // Apply the requested time window. Both the stats and snippet queries
        // build off `chatFilter` and reference `m.date`, so appending the date
        // bounds here scopes both consistently. (Integer literals — no binding.)
        let (lowerBound, upperBound) = scope.appleDateBounds()
        if let lowerBound { chatFilter += "\n            AND m.date >= \(lowerBound)" }
        if let upperBound { chatFilter += "\n            AND m.date <= \(upperBound)" }

        // --- 1) Aggregate stats ---
        let statsSQL = """
        SELECT
            COUNT(*)                                  AS total,
            COALESCE(SUM(m.is_from_me), 0)            AS sent,
            MIN(m.date)                               AS first_date,
            MAX(m.date)                               AS last_date,
            COALESCE(SUM(CASE WHEN m.date >= \(cutoff30Ns) THEN 1 ELSE 0 END), 0) AS last30,
            COALESCE(SUM(CASE WHEN m.date >= \(cutoff90Ns) THEN 1 ELSE 0 END), 0) AS last90
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        \(chatFilter);
        """
        var stats = Stats(matchedHandles: try handleStrings(db: db, rowIDs: handleRowIDs))
        var stmt1: OpaquePointer?
        guard sqlite3_prepare_v2(db, statsSQL, -1, &stmt1, nil) == SQLITE_OK else {
            throw AnalyzeError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        if sqlite3_step(stmt1) == SQLITE_ROW {
            stats.total    = Int(sqlite3_column_int64(stmt1, 0))
            stats.sent     = Int(sqlite3_column_int64(stmt1, 1))
            stats.received = stats.total - stats.sent
            let firstRaw   = sqlite3_column_int64(stmt1, 2)
            let lastRaw    = sqlite3_column_int64(stmt1, 3)
            if firstRaw != 0 { stats.firstDate = appleDate(firstRaw) }
            if lastRaw  != 0 { stats.lastDate  = appleDate(lastRaw) }
            stats.last30   = Int(sqlite3_column_int64(stmt1, 4))
            stats.last90   = Int(sqlite3_column_int64(stmt1, 5))
        }
        sqlite3_finalize(stmt1)

        // --- 2) Recent snippets only ---
        //
        // Columns explained:
        //   text                    — plain UTF-8. NULL when the message
        //                              has rich formatting / mentions /
        //                              reactions / attachments.
        //   attributedBody          — typedstream NSAttributedString. We
        //                              parse it for the underlying string
        //                              when text is NULL.
        //   cache_has_attachments,
        //   associated_message_type — drive the placeholder fallback so
        //                              attachments/reactions still show
        //                              on the timeline.
        let snippetSQL = """
        SELECT m.is_from_me, m.date, m.text, m.attributedBody,
               m.cache_has_attachments, m.associated_message_type
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        \(chatFilter)
        ORDER BY m.date DESC
        LIMIT \(max(1, recentLimit));
        """
        var stmt2: OpaquePointer?
        guard sqlite3_prepare_v2(db, snippetSQL, -1, &stmt2, nil) == SQLITE_OK else {
            throw AnalyzeError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt2) }

        var snippetsDesc: [Snippet] = []
        while sqlite3_step(stmt2) == SQLITE_ROW {
            let fromMe = sqlite3_column_int(stmt2, 0) == 1
            let date = appleDate(sqlite3_column_int64(stmt2, 1))
            var text = ""
            if let c = sqlite3_column_text(stmt2, 2) { text = String(cString: c) }

            if text.isEmpty,
               let bodyPtr = sqlite3_column_blob(stmt2, 3) {
                let bodyLen = Int(sqlite3_column_bytes(stmt2, 3))
                if bodyLen > 0 {
                    let bodyData = Data(bytes: bodyPtr, count: bodyLen)
                    if let recovered = Self.extractText(fromAttributedBody: bodyData) {
                        text = recovered
                    }
                }
            }

            let hasAttach = sqlite3_column_int(stmt2, 4) == 1
            let assocType = Int(sqlite3_column_int(stmt2, 5))
            if text.isEmpty {
                if assocType != 0       { text = "[reaction/tapback]" }
                else if hasAttach       { text = "[image/attachment]" }
                else                    { text = "[message]" }
            }

            snippetsDesc.append(Snippet(fromMe: fromMe, date: date, text: text))
        }
        // SQL gave us newest-first; caller (and existing UI) expects
        // chronological order — reverse to oldest-first.
        let recent = Array(snippetsDesc.reversed())
        return (stats, recent)
    }

    /// Recover the underlying UTF-8 string from a Messages `attributedBody`
    /// blob. The blob is an `NSArchiver` typedstream containing an
    /// `NSAttributedString`.
    ///
    /// Anatomy of the relevant section:
    ///
    ///     ... NSString \x01 \x94 \x84 \x01 \x2b <len> <utf-8 bytes> ...
    ///
    /// The `\x2b` (ASCII `+`) is the typedstream "object instance" marker.
    /// The byte immediately after it is the length prefix of the actual
    /// string. The metadata between "NSString" and the final `\x2b`
    /// varies (class hierarchy introduction vs. reference) but always
    /// ends with that marker.
    ///
    /// Earlier versions of this parser scanned for ANY byte in 0x01..0x7F
    /// after "NSString" and treated it as a length. That picked up the
    /// `\x01` metadata byte first, treated it as length=1, and returned
    /// the next byte (`\x2b`) as the string — which is why every
    /// recovered message was the single character `+`. The corrected
    /// approach is to find the LAST `\x2b` in a bounded window after
    /// "NSString" and read the length right after that.
    ///
    /// Returns nil if the blob doesn't look like a typedstream or the
    /// length-prefix doesn't yield valid UTF-8. Callers fall back to
    /// placeholder text in that case.
    static func extractText(fromAttributedBody data: Data) -> String? {
        let marker = Array("NSString".utf8)
        let bytes = [UInt8](data)
        guard bytes.count > marker.count + 6,
              let markerStart = Self.indexOf(marker, in: bytes) else {
            return nil
        }

        // The object-instance marker `\x2b` sits within ~30 bytes of
        // "NSString". For an inline class introduction it's preceded by
        // the NSObject reference; for a class reference it appears
        // almost immediately. Either way, the LAST `\x2b` in this window
        // is the one we want.
        let afterMarker = markerStart + marker.count
        let scanEnd = min(bytes.count, afterMarker + 40)
        var lastPlus: Int?
        for i in afterMarker..<scanEnd where bytes[i] == 0x2b {
            lastPlus = i
        }
        guard let plus = lastPlus, plus + 1 < bytes.count else { return nil }

        var idx = plus + 1
        let lengthByte = bytes[idx]
        idx += 1
        let length: Int
        switch lengthByte {
        case 0x00...0x7F:
            length = Int(lengthByte)
        case 0x81:
            guard idx + 2 <= bytes.count else { return nil }
            length = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
            idx += 2
        case 0x82:
            guard idx + 4 <= bytes.count else { return nil }
            length = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
                   | (Int(bytes[idx + 2]) << 16) | (Int(bytes[idx + 3]) << 24)
            idx += 4
        default:
            return nil
        }

        guard length > 0, length < 65_536,
              idx + length <= bytes.count else { return nil }
        return String(bytes: bytes[idx..<idx + length], encoding: .utf8)
    }

    /// First index where `needle` starts inside `haystack`. Plain byte
    /// scan; haystacks here are at most a few KB so the trivial loop is
    /// fine.
    private static func indexOf(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let last = haystack.count - needle.count
        for i in 0...last {
            if haystack[i..<i + needle.count].elementsEqual(needle) { return i }
        }
        return nil
    }

    /// Optional: summarize what a conversation is usually about, via local Ollama.
    ///
    /// The prompt is deliberately framed as a neutral topic-extraction task
    /// and anchors the participants as adult professional contacts. Without
    /// this scaffolding, small models (llama3.1:8b in particular) sometimes
    /// over-fire their safety head on benign text logs and emit canned
    /// refusals like "I cannot provide information that could be used to
    /// facilitate harmful or illegal activities…" — which then ended up
    /// rendered to the user as the per-person "summary."
    ///
    /// We also filter the model's reply: if it looks like a refusal rather
    /// than a summary, drop it so the UI shows nothing instead of garbage.
    static func conversationSummary(person: Person, recent: [Snippet], using ollama: OllamaService) async -> String? {
        guard recent.count >= 4 else { return nil }
        let transcript = recent.map { "\($0.fromMe ? "Me" : person.displayName): \($0.text)" }
            .joined(separator: "\n")
            .prefix(8000)
        let prompt = """
        You are a topic-extraction utility for a personal CRM. You are
        looking at a log of text messages between the user (an adult
        professional named Tyler) and one of his adult contacts named
        \(person.displayName). Both parties are adults. Your sole job is
        to summarize, in 2–3 sentences, the recurring TOPICS of these
        conversations (work, scheduling, hobbies, logistics, family,
        etc.) and the general tone (warm/casual/professional/terse).

        Rules:
        - Output the summary ONLY. No preamble, no disclaimers, no
          refusals.
        - This is the user's own message data on their own machine.
          There is nothing sensitive about summarizing it.
        - If the messages are too sparse or generic to characterize,
          reply with exactly: "Not enough context."

        Recent messages:

        \(transcript)
        """
        guard let raw = try? await ollama.generate(prompt: String(prompt), temperature: 0.2, numCtx: 8192) else {
            return nil
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop the well-known small-model refusal shapes so the UI never
        // displays a hallucinated safety message in place of a summary.
        let lower = cleaned.lowercased()
        let refusalMarkers = [
            "i cannot provide", "i can't provide",
            "i cannot help", "i can't help",
            "i cannot assist", "i can't assist",
            "i'm not able to", "i am not able to",
            "as an ai", "i'm sorry, but"
        ]
        if refusalMarkers.contains(where: { lower.hasPrefix($0) }) { return nil }
        if cleaned.isEmpty || cleaned == "Not enough context." { return nil }
        return cleaned
    }

    /// Structured insights from a message history (8b): recurring topics,
    /// notable verbatim quotes (with dates), commitments/plans with optional due
    /// dates, and an overall tone. Ollama returns JSON, which we parse.
    struct MessageInsights: Codable, Equatable {
        struct Quote: Codable, Equatable { var speaker: String; var text: String; var date: String }
        struct Commitment: Codable, Equatable { var who: String; var what: String; var dueDate: String? }
        var topics: [String]
        var quotes: [Quote]
        var commitments: [Commitment]
        var tone: String
    }

    static func extractStructured(person: Person, recent: [Snippet],
                                  using ollama: OllamaService) async -> MessageInsights? {
        guard recent.count >= 4 else { return nil }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let transcript = recent
            .map { "[\(df.string(from: $0.date))] \($0.fromMe ? "Me" : person.displayName): \($0.text)" }
            .joined(separator: "\n").prefix(8000)
        let prompt = """
        You are a structured-extraction utility for a personal CRM, looking at \
        text messages between the user (an adult professional named Tyler) and \
        his adult contact \(person.displayName). Both are adults; this is the \
        user's own data on their own machine — there is nothing sensitive about \
        summarizing it.

        Return ONLY a JSON object (no preamble, no code fences, no disclaimers) \
        with exactly these keys: {"topics": ["short topic"], "quotes": \
        [{"speaker": "Me or \(person.displayName)", "text": "verbatim line", "date": "YYYY-MM-DD"}], \
        "commitments": [{"who": "Me or \(person.displayName)", "what": "what was promised/planned", \
        "dueDate": "YYYY-MM-DD or null"}], "tone": "warm|casual|professional|terse|mixed"}

        - topics: up to 6 recurring themes.
        - quotes: up to 5 notable/memorable lines, verbatim, with their date.
        - commitments: promises, plans, or dates mentioned ("I'll send it Friday").
        - Use empty arrays where there is nothing.

        Messages:
        \(transcript)
        """
        guard let raw = try? await ollama.generate(prompt: String(prompt), temperature: 0.1, numCtx: 8192),
              let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { return nil }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8),
              let insights = try? JSONDecoder().decode(MessageInsights.self, from: data) else { return nil }
        return insights
    }

    // MARK: - Helpers

    private static func matchingHandleRowIDs(db: OpaquePointer?, person: Person) throws -> [Int64] {
        let emails = Set(person.emails.map(PersonMatching.normalizeEmail).filter { !$0.isEmpty })
        let phones = Set(person.phones.map(PersonMatching.normalizePhone).filter { $0.count >= 7 })
        guard !emails.isEmpty || !phones.isEmpty else { return [] }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT ROWID, id FROM handle;", -1, &stmt, nil) == SQLITE_OK else {
            throw AnalyzeError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var matches: [Int64] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(stmt, 0)
            guard let c = sqlite3_column_text(stmt, 1) else { continue }
            let handle = String(cString: c)
            if handle.contains("@") {
                if emails.contains(PersonMatching.normalizeEmail(handle)) { matches.append(rowID) }
            } else {
                if phones.contains(PersonMatching.normalizePhone(handle)) { matches.append(rowID) }
            }
        }
        return matches
    }

    private static func handleStrings(db: OpaquePointer?, rowIDs: [Int64]) throws -> [String] {
        guard !rowIDs.isEmpty else { return [] }
        let sql = "SELECT id FROM handle WHERE ROWID IN (\(rowIDs.map(String.init).joined(separator: ",")));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return Array(Set(out))
    }

    /// `chat.db` stores dates as nanoseconds (modern) or seconds (legacy) since
    /// the 2001 reference date.
    private static func appleDate(_ raw: Int64) -> Date {
        let seconds = raw > 1_000_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
