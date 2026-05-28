import Foundation
import OSLog
import VaultKit

/// Minimal Anthropic Messages-API client with tool-use support. Talks to
/// `api.anthropic.com/v1/messages`, runs the local tool-call loop until the
/// model returns a final assistant message, and surfaces the conversation
/// back via a Combine-friendly publisher.
///
/// Tools are defined in `ChatTools.swift` (same names + schemas as the
/// `MeetingScribeMCP` server so the Chat shares the model's "mental
/// model" of how to query the local data).
final class AnthropicClient {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Anthropic")
    static let defaultModel = "claude-sonnet-4-5"
    /// Bumped occasionally — keep in sync with docs.
    static let apiVersion = "2023-06-01"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum ClientError: Error, LocalizedError {
        case missingAPIKey
        case http(Int, String)
        case decode(String)
        case toolExecutionFailed(String, String)
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API key not set. Add it in Settings → Chat."
            case .http(let c, let m): return "Anthropic API HTTP \(c): \(m)"
            case .decode(let m):      return "Could not decode Anthropic response: \(m)"
            case .toolExecutionFailed(let name, let m):
                return "Tool '\(name)' failed: \(m)"
            }
        }
    }

    // MARK: - Conversation primitives

    /// Wire-level role for an Anthropic message.
    enum Role: String, Codable { case user, assistant }

    /// One block of content inside a message. Anthropic supports several
    /// types; we use text, tool_use, and tool_result.
    enum ContentBlock: Codable, Hashable {
        case text(String)
        case toolUse(id: String, name: String, input: [String: JSONValue])
        case toolResult(toolUseID: String, content: String, isError: Bool)

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
            case toolUseID = "tool_use_id"
            case content
            case isError = "is_error"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let s):
                try c.encode("text", forKey: .type)
                try c.encode(s, forKey: .text)
            case .toolUse(let id, let name, let input):
                try c.encode("tool_use", forKey: .type)
                try c.encode(id, forKey: .id)
                try c.encode(name, forKey: .name)
                try c.encode(input, forKey: .input)
            case .toolResult(let tid, let content, let isError):
                try c.encode("tool_result", forKey: .type)
                try c.encode(tid, forKey: .toolUseID)
                try c.encode(content, forKey: .content)
                try c.encode(isError, forKey: .isError)
            }
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try c.decode(String.self, forKey: .text))
            case "tool_use":
                let id = try c.decode(String.self, forKey: .id)
                let name = try c.decode(String.self, forKey: .name)
                let input = try c.decodeIfPresent([String: JSONValue].self, forKey: .input) ?? [:]
                self = .toolUse(id: id, name: name, input: input)
            case "tool_result":
                let tid = try c.decode(String.self, forKey: .toolUseID)
                let content = (try? c.decode(String.self, forKey: .content)) ?? ""
                let isError = (try? c.decode(Bool.self, forKey: .isError)) ?? false
                self = .toolResult(toolUseID: tid, content: content, isError: isError)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c,
                    debugDescription: "Unknown content block type: \(type)")
            }
        }
    }

    struct Message: Codable {
        let role: Role
        let content: [ContentBlock]
    }

    struct Tool: Codable {
        let name: String
        let description: String
        let input_schema: JSONValue
    }

    // MARK: - Request / response wire types

    private struct MessagesRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
        let tools: [Tool]?
    }

    private struct MessagesResponse: Decodable {
        let id: String?
        let role: String?
        let content: [ContentBlock]
        let stop_reason: String?
    }

    // NOTE: Chat now runs entirely against the local Ollama instance —
    // see OllamaChatClient. The Message / Tool / ContentBlock types
    // defined above are still the canonical conversation model and are
    // shared with the Ollama client; the Anthropic-API call path has been
    // removed.
}

// MARK: - JSON value type
//
// `JSONValue` now lives in the `MeetingScribeShared` module — one canonical
// implementation used by AnthropicClient, both MCP servers, and any future
// consumer that needs to round-trip arbitrary JSON without a strong model.
// (Previously this enum was duplicated three times across the codebase.)
