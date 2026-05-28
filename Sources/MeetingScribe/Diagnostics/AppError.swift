import Foundation

/// Canonical error wrapper for any code path that wants to:
///   - Log a failure consistently (OSLog + transcription log)
///   - Surface a user-readable banner / inline message
///   - Categorize the failure for future telemetry or "Export diagnostics"
///
/// Existing per-domain error types (`SummaryError`, `TranscribeError`,
/// `DriveError`, `NotionError`, etc.) continue to exist — they read well
/// at the call site. They conform to `Reportable` to convert into an
/// `AppError` when reporting through `ErrorReporter`.
public struct AppError: Error, CustomStringConvertible {
    public enum Category: String, Sendable {
        case audio
        case transcription
        case summary
        case storage
        case calendar
        case notifications
        case integration         // notion / linear / drive
        case mcp
        case chat
        case hotkey
        case update              // sparkle
        case unknown
    }

    /// Best-effort end-user message. Short and actionable when possible.
    public let userMessage: String
    /// Longer technical description (stack-trace-equivalent — included in
    /// diagnostics exports, not shown to the user by default).
    public let debugDetail: String?
    public let category: Category
    public let underlying: Error?
    public let context: [String: String]
    public let timestamp: Date

    public init(userMessage: String,
                debugDetail: String? = nil,
                category: Category,
                underlying: Error? = nil,
                context: [String: String] = [:],
                timestamp: Date = Date()) {
        self.userMessage = userMessage
        self.debugDetail = debugDetail
        self.category = category
        self.underlying = underlying
        self.context = context
        self.timestamp = timestamp
    }

    public var description: String {
        var out = "[\(category.rawValue)] \(userMessage)"
        if let detail = debugDetail, !detail.isEmpty { out += " — \(detail)" }
        if let u = underlying { out += " (underlying: \(u))" }
        if !context.isEmpty {
            let pairs = context.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            out += " {\(pairs)}"
        }
        return out
    }
}

/// Anything that can present itself as a user-facing error. Domain error
/// enums conform here so call sites can `ErrorReporter.shared.report(myErr,
/// category: .audio)` without wrapping by hand.
public protocol Reportable: Error {
    var userMessage: String { get }
    var debugDetail: String? { get }
}

extension Reportable {
    public var debugDetail: String? { nil }

    /// Default conversion to `AppError`. Override in conforming types only
    /// if you want richer context.
    public func asAppError(category: AppError.Category,
                           context: [String: String] = [:]) -> AppError {
        AppError(userMessage: userMessage,
                 debugDetail: debugDetail,
                 category: category,
                 underlying: self,
                 context: context)
    }
}

// (Removed: the previous extension on `LocalizedError` provided default
// `userMessage` and `debugDetail` implementations. Combined with
// `Reportable`'s own default `debugDetail`, conforming types saw two
// candidates and Swift couldn't pick one. Now: each conforming type
// provides `userMessage` (and optionally `debugDetail`) explicitly in
// its `: Reportable` extension. Default still applies via the Reportable
// extension above when `debugDetail` is omitted.)
