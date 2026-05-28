import Foundation

/// A Codable-friendly JSON value used wherever we have to round-trip
/// arbitrary JSON without modeling it strongly. Shared between the main
/// app's Anthropic/Ollama chat tool plumbing and both MCP server targets
/// so we don't carry three identical reimplementations.
///
/// History: this was previously copy-pasted into
///   - Sources/MeetingScribe/Chat/AnthropicClient.swift  (`JSONValue`)
///   - Sources/MeetingScribeMCP/main.swift                 (`JSON`)
///   - Sources/NotionMCP/main.swift                        (`JSON`)
/// with subtly different naming and conformances. They're now one type.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .int(let v):     try c.encode(v)
        case .double(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let a):   try c.encode(a)
        case .object(let o):  try c.encode(o)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self)   { self = .bool(b); return }
        if let i = try? c.decode(Int.self)    { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unrecognised JSON value")
    }

    // MARK: - Convenience accessors

    public var asString: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var asInt: Int? {
        if case let .int(i) = self { return i }
        if case let .double(d) = self { return Int(d) }
        return nil
    }

    public var asDouble: Double? {
        if case let .double(d) = self { return d }
        if case let .int(i) = self { return Double(i) }
        return nil
    }

    public var asBool: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }

    public var asObject: [String: JSONValue]? {
        if case let .object(o) = self { return o }
        return nil
    }

    public var asArray: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    /// Pretty-printed JSON string. Used for echoing tool inputs to the UI
    /// and for the MCP server's wire output.
    public func prettyJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self), let s = String(data: data, encoding: .utf8) { return s }
        return "{}"
    }

    /// Compact JSON string (single line). Used for JSON-RPC wire writes.
    public func compactJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(self), let s = String(data: data, encoding: .utf8) { return s }
        return "{}"
    }
}

// MARK: - Literal conveniences (so call sites can write `.object(["k": .string("v")])`
//         exactly as before without explicit type annotations.)

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}
