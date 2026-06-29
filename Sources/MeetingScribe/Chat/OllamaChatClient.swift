import Foundation
import VaultKit
import OSLog

/// Chat client that runs entirely on the local Ollama instance — no API
/// key, no outbound traffic past 127.0.0.1:11434. Speaks Ollama's
/// `/api/chat` endpoint with tool-calling enabled (OpenAI-compatible
/// `tools` parameter + `tool_calls` in the response).
///
/// Returns the same `[AnthropicClient.Message]` shape as `AnthropicClient`
/// so the rest of the app (ChatSession, the chat UI) doesn't care which
/// backend produced the turn.
final class OllamaChatClient {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "OllamaChat")
    private let service = OllamaService()

    enum ClientError: Error, LocalizedError {
        case notReachable
        case http(Int, String)
        case decode(String)
        var errorDescription: String? {
            switch self {
            case .notReachable: return "Ollama isn't running. The Chat needs a local LLM. Open Settings → Ollama → Start, or run `ollama serve`."
            case .http(let c, let m): return "Ollama HTTP \(c): \(m)"
            case .decode(let m):      return "Could not decode Ollama response: \(m)"
            }
        }
    }

    // MARK: - Wire types

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [OllamaMessage]
        let tools: [OllamaTool]?
        let stream: Bool
        let options: Options
        /// Ollama structured-output mode. "json" forces a single valid JSON
        /// object reply (no tool loop) — used by the one-shot path. Omitted from
        /// the wire when nil (synthesized `encodeIfPresent`), so existing tool
        /// calls are unaffected.
        var format: String? = nil
        struct Options: Encodable {
            let temperature: Double
            let num_ctx: Int
        }
    }

    private struct OllamaMessage: Codable {
        let role: String                     // "system" | "user" | "assistant" | "tool"
        let content: String
        let tool_calls: [OllamaToolCall]?
    }

    private struct OllamaToolCall: Codable {
        let function: OllamaFunctionCall
    }

    private struct OllamaFunctionCall: Codable {
        let name: String
        let arguments: JSONValue
    }

    private struct OllamaTool: Encodable {
        let type: String = "function"
        let function: ToolFunction
        struct ToolFunction: Encodable {
            let name: String
            let description: String
            let parameters: JSONValue
        }
    }

    private struct ChatResponse: Decodable {
        let message: OllamaMessage
        let done: Bool?
    }

    // MARK: - Send

    /// One non-streaming request that returns a single JSON object — no tool
    /// loop. Dramatically faster than `send(...)` for "analyze and return a
    /// structured result" tasks (one round-trip instead of up to N), and far more
    /// reliable on small local models, which are flaky at multi-turn tool calling.
    /// `timeoutSeconds` is deliberately short so a slow/stuck model fails fast and
    /// the caller can fall back to whatever it already has.
    func oneShotJSON(system: String,
                     user: String,
                     timeoutSeconds: TimeInterval = 60,
                     numCtx: Int = 4_096) async throws -> String {
        _ = await service.ensureRunning()
        guard await service.isReachable() else { throw ClientError.notReachable }
        let body = ChatRequest(
            model: AppSettings.shared.ollamaModel,
            messages: [
                .init(role: "system", content: system, tool_calls: nil),
                .init(role: "user", content: user, tool_calls: nil)
            ],
            tools: nil,
            stream: false,
            options: .init(temperature: 0.2, num_ctx: numCtx),
            format: "json"
        )
        let url = AppSettings.shared.ollamaURL.appendingPathComponent("api/chat")
        try EgressPolicy.assertOllamaEgressAllowed(url)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeoutSeconds
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw ClientError.notReachable }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1, bodyStr)
        }
        return (try? JSONDecoder().decode(ChatResponse.self, from: data).message.content) ?? ""
    }

    func send(messages startMessages: [AnthropicClient.Message],
              system: String?,
              tools: [AnthropicClient.Tool],
              maxIterations: Int = 9,   // 4-G: deeper multi-hop (person→decisions→meetings)
              progress: @MainActor (AnthropicClient.Message) -> Void = { _ in },
              runTool: @escaping (_ name: String, _ input: [String: JSONValue]) async -> Result<String, Error>
    ) async throws -> [AnthropicClient.Message] {
        // Make sure Ollama is up — auto-launch via `ollama serve` if not.
        _ = await service.ensureRunning()
        guard await service.isReachable() else { throw ClientError.notReachable }

        var convo = startMessages
        var iterations = 0
        // First-use guard: if Ollama doesn't have the configured model
        // installed yet, we'll pull it inline ONCE and retry. The flag
        // makes sure a chronically-unavailable model can't loop forever.
        var triedAutoPull = false

        // Tool-call dedup. Small models occasionally fall into a "same
        // tool, same args" loop (we saw qwen2.5:7b call get_person 5x in
        // a row with identical input). Track a signature of every
        // (tool, args) tuple actually executed and short-circuit the
        // second occurrence with a hint to use the previous result,
        // instead of paying another LLM round-trip for the same data.
        var seenToolSignatures = Set<String>()

        let ollamaTools = tools.map { tool -> OllamaTool in
            OllamaTool(function: .init(
                name: tool.name,
                description: tool.description,
                parameters: tool.input_schema
            ))
        }

        while iterations < maxIterations {
            iterations += 1

            var wire: [OllamaMessage] = []
            if let system { wire.append(.init(role: "system", content: system, tool_calls: nil)) }
            wire.append(contentsOf: Self.translateToOllama(convo))

            // Cap num_ctx at 4096 — prefill is the dominant cost per turn
            // on M-series Macs running qwen2.5:7b. 16k was generous but
            // basically nothing in this chat ever needs that much: the
            // system prompt + tool catalog + a few tool results fit in
            // ~2k tokens. Bumping back up is one constant change away if
            // a future flow genuinely needs the room.
            let body = ChatRequest(
                model: AppSettings.shared.ollamaModel,
                messages: wire,
                tools: ollamaTools.isEmpty ? nil : ollamaTools,
                stream: false,
                options: .init(temperature: 0.3, num_ctx: 4_096)
            )
            let url = AppSettings.shared.ollamaURL.appendingPathComponent("api/chat")
            // E4-3: chat carries meeting content — block a non-local endpoint
            // unless the user has explicitly approved remote egress.
            try EgressPolicy.assertOllamaEgressAllowed(url)
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 600
            req.httpBody = try JSONEncoder().encode(body)

            let (data, response): (Data, URLResponse)
            do { (data, response) = try await URLSession.shared.data(for: req) }
            catch { throw ClientError.notReachable }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1

                // Auto-pull on first-use. If the user is on the migrated
                // default (qwen2.5:7b) but hasn't pulled it yet, Ollama
                // returns a 404 with `{"error":"model 'X' not found"}`.
                // Pull it inline and retry instead of dumping the raw
                // JSON in the chat bubble. One attempt per session — if
                // the pull itself fails, we surface the original error.
                if !triedAutoPull, code == 404,
                   let missing = Self.extractMissingModel(from: bodyStr) {
                    triedAutoPull = true
                    let notice = AnthropicClient.Message(
                        role: .assistant,
                        content: [.text("Pulling local model `\(missing)` — this is a one-time ~5 GB download (will take 30 s – a few min). Won't happen again.")]
                    )
                    convo.append(notice)
                    await progress(notice)
                    do {
                        try await Self.pullModel(missing)
                        // Don't count this iteration against maxIterations
                        // — the retry below replaces the failed call.
                        iterations -= 1
                        continue
                    } catch {
                        throw ClientError.http(code,
                            "Couldn't auto-pull `\(missing)`: \(error.localizedDescription). " +
                            "Try `ollama pull \(missing)` in Terminal, or Integrations → Pull \(missing).")
                    }
                }

                throw ClientError.http(code, bodyStr)
            }
            let parsed: ChatResponse
            do { parsed = try JSONDecoder().decode(ChatResponse.self, from: data) }
            catch { throw ClientError.decode(error.localizedDescription) }

            // Translate Ollama's assistant turn into AnthropicClient blocks.
            // Some small models (notably llama3.1:8b) regress and emit a
            // tool-call JSON object as plain `content` instead of
            // populating `tool_calls`. Recover those so the loop still
            // fires the tool instead of showing the user raw JSON.
            var blocks: [AnthropicClient.ContentBlock] = []
            var nativeCalls = parsed.message.tool_calls ?? []
            var visibleContent = parsed.message.content

            if nativeCalls.isEmpty,
               let leaked = Self.extractLeakedToolCall(from: visibleContent,
                                                       knownToolNames: Set(tools.map(\.name))) {
                nativeCalls.append(.init(function: leaked.call))
                visibleContent = leaked.remaining
                log.info("Recovered leaked tool call \(leaked.call.name, privacy: .public) from message content")
            }

            if !visibleContent.isEmpty {
                blocks.append(.text(visibleContent))
            }
            for (i, call) in nativeCalls.enumerated() {
                // Ollama doesn't issue tool_use IDs the way Anthropic does —
                // mint a synthetic one so the UI/loop can match results back.
                let id = "ollama_\(iterations)_\(i)"
                let inputDict: [String: JSONValue]
                if case let .object(pairs) = call.function.arguments {
                    inputDict = pairs
                } else {
                    inputDict = [:]
                }
                blocks.append(.toolUse(id: id, name: call.function.name, input: inputDict))
            }

            let assistantMsg = AnthropicClient.Message(role: .assistant, content: blocks)
            convo.append(assistantMsg)
            await progress(assistantMsg)

            // If no tool calls, we're done.
            let toolUses: [(id: String, name: String, input: [String: JSONValue])] =
                blocks.compactMap { block in
                    if case let .toolUse(id, name, input) = block { return (id, name, input) }
                    return nil
                }
            guard !toolUses.isEmpty else { return convo }

            // Run each tool, accumulate results as a user message of
            // tool_result blocks (matches AnthropicClient's representation;
            // when we translate to Ollama we'll fan it out into role:"tool"
            // entries). Dedup identical (tool, args) calls — see
            // `seenToolSignatures` above for the why.
            var results: [AnthropicClient.ContentBlock] = []
            for tu in toolUses {
                let signature = Self.toolSignature(name: tu.name, input: tu.input)
                if seenToolSignatures.contains(signature) {
                    log.info("Short-circuiting duplicate tool call \(tu.name, privacy: .public)")
                    results.append(.toolResult(
                        toolUseID: tu.id,
                        content: "You already called `\(tu.name)` with these exact arguments earlier in this conversation. Use the previous result — do not call it again. If the previous answer wasn't enough, either (a) call a DIFFERENT tool, or (b) answer the user directly with what you already have.",
                        isError: true))
                    continue
                }
                seenToolSignatures.insert(signature)

                let outcome = await runTool(tu.name, tu.input)
                switch outcome {
                case .success(let s):
                    results.append(.toolResult(toolUseID: tu.id, content: s, isError: false))
                case .failure(let err):
                    results.append(.toolResult(toolUseID: tu.id,
                                               content: err.localizedDescription,
                                               isError: true))
                }
            }
            let userTurn = AnthropicClient.Message(role: .user, content: results)
            convo.append(userTurn)
            await progress(userTurn)
        }
        throw ClientError.http(-2, "Ollama tool-use loop exceeded \(maxIterations) iterations")
    }

    /// Defensive parser for the failure mode where a small model emits a
    /// tool-call as plain `content` instead of populating `tool_calls`.
    ///
    /// Catches both common shapes:
    ///   {"name": "list_meetings", "parameters": {"days": 1}}
    ///   {"name": "list_meetings", "arguments": {"days": 1}}
    ///
    /// The JSON may be wrapped in ```json fences, surrounded by chatty
    /// text ("Let me check… {…}"), or be the entire content. We require a
    /// `name` field matching a known tool to avoid hijacking benign
    /// JSON-looking text the user / assistant might legitimately produce.
    ///
    /// Returns the synthesized function call plus whatever non-JSON text
    /// remains (so a model that says "Let me check that for you. {…}"
    /// still gets to show its preamble).
    private static func extractLeakedToolCall(from raw: String,
                                              knownToolNames: Set<String>)
        -> (call: OllamaFunctionCall, remaining: String)? {

        // Strip ```json … ``` fences before searching.
        var text = raw
        if let fenceRange = text.range(of: "```json", options: .caseInsensitive) {
            text.replaceSubrange(fenceRange, with: "")
        }
        text = text.replacingOccurrences(of: "```", with: "")

        // Find the first balanced { … } that decodes to an object with a
        // recognized name. Brace-matching is necessary because the JSON
        // can contain nested objects ("parameters": { … }).
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            guard chars[i] == "{" else { i += 1; continue }
            var depth = 0
            var inString = false
            var escaped = false
            var j = i
            while j < chars.count {
                let c = chars[j]
                if escaped { escaped = false; j += 1; continue }
                if c == "\\" && inString { escaped = true; j += 1; continue }
                if c == "\"" { inString.toggle() }
                else if !inString {
                    if c == "{" { depth += 1 }
                    else if c == "}" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                }
                j += 1
            }
            if depth == 0 && j < chars.count {
                let candidate = String(chars[i...j])
                if let data = candidate.data(using: .utf8),
                   let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                   case let .object(obj) = value,
                   case let .string(name)? = obj["name"],
                   knownToolNames.contains(name) {
                    let argsValue = obj["arguments"] ?? obj["parameters"] ?? .object([:])
                    let argsObj: JSONValue = {
                        if case .object = argsValue { return argsValue }
                        return .object([:])
                    }()
                    var remaining = String(chars[..<i]) + String(chars[(j + 1)...])
                    remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (OllamaFunctionCall(name: name, arguments: argsObj), remaining)
                }
            }
            i += 1
        }
        return nil
    }

    /// Deterministic signature for a tool invocation — `<name>:<compact-json>`.
    /// Used by the per-session dedup cache to detect identical repeats.
    /// JSON is canonicalised via JSONValue's sorted-keys compact encoding
    /// so map-key ordering can't cause two equivalent calls to hash apart.
    static func toolSignature(name: String, input: [String: JSONValue]) -> String {
        let argsJSON = JSONValue.object(input).compactJSON()
        return "\(name)|\(argsJSON)"
    }

    /// Parse Ollama's "model not found" 404 body to recover the offending
    /// model name. Body looks like: {"error":"model 'qwen2.5:7b' not found"}
    /// We accept single OR double quotes around the model and don't depend
    /// on exact prefix wording in case Ollama changes the phrasing.
    static func extractMissingModel(from body: String) -> String? {
        guard body.lowercased().contains("not found") else { return nil }
        // Look for a quoted model id. Try both quote styles.
        for quote in ["'", "\""] {
            let parts = body.components(separatedBy: quote)
            // First quoted segment after "model" is the model name.
            for (i, seg) in parts.enumerated() {
                if i > 0, parts[i - 1].lowercased().hasSuffix("model "),
                   !seg.isEmpty, seg != quote {
                    return seg
                }
            }
        }
        // Fallback: pick the first quoted token if any exists.
        if let first = body.split(separator: "'").dropFirst().first {
            return String(first)
        }
        return nil
    }

    /// Run `ollama pull <model>` as a detached Process and await its
    /// exit. Used by the first-use auto-pull path so a fresh install
    /// doesn't error out the first time the user types into chat.
    /// Throws if the binary isn't installed or the pull fails.
    static func pullModel(_ model: String) async throws {
        guard let binary = OllamaService.binaryPath else {
            throw ClientError.http(-3,
                "Ollama isn't installed. `brew install ollama` then try again.")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["pull", model]
        // Pipe stdout/stderr to /dev/null — `ollama pull` prints a noisy
        // progress bar that's useless without a TTY anyway. We just care
        // about the exit code.
        proc.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardError = FileHandle(forWritingAtPath: "/dev/null")
        try proc.run()
        // Wait off the cooperative pool so we don't pin the actor.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                proc.waitUntilExit()
                cont.resume()
            }
        }
        guard proc.terminationStatus == 0 else {
            throw ClientError.http(-4,
                "`ollama pull \(model)` exited \(proc.terminationStatus)")
        }
    }

    /// Translate the canonical [Anthropic-format] message log into Ollama's
    /// wire format. Tool results that travel as user-role tool_result blocks
    /// become separate role:"tool" messages.
    private static func translateToOllama(_ messages: [AnthropicClient.Message]) -> [OllamaMessage] {
        var out: [OllamaMessage] = []
        for m in messages {
            // Pull text + tool_use out of assistant messages.
            if m.role == .assistant {
                var text = ""
                var calls: [OllamaToolCall] = []
                for block in m.content {
                    switch block {
                    case .text(let s): text += s
                    case .toolUse(_, let name, let input):
                        calls.append(.init(function: .init(name: name,
                                                            arguments: .object(input))))
                    case .toolResult: break
                    }
                }
                out.append(.init(role: "assistant",
                                 content: text,
                                 tool_calls: calls.isEmpty ? nil : calls))
                continue
            }
            // User messages can contain text OR tool_result blocks. Tool
            // results become role:"tool" entries.
            for block in m.content {
                switch block {
                case .text(let s):
                    out.append(.init(role: "user", content: s, tool_calls: nil))
                case .toolResult(_, let content, _):
                    out.append(.init(role: "tool", content: content, tool_calls: nil))
                case .toolUse: break
                }
            }
        }
        return out
    }
}
