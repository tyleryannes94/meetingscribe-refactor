// CompatShim.swift
// Stub implementations of AppLog and ErrorReporter for the ScribeCore target.
// These types are defined in the MeetingScribe UI target; ScribeCore copies of
// audio/AI files reference them. Rather than rewriting every call site, we
// provide lightweight OSLog-backed stubs here so ScribeCore compiles standalone.

import Foundation
import OSLog

private let shimLog = Logger(subsystem: "com.tyleryannes.ScribeCore", category: "Compat")

// MARK: - AppLog

enum AppLog {
    static func info(_ category: String, _ message: String, _ context: [String: Any] = [:]) {
        shimLog.info("\(category, privacy: .public): \(message, privacy: .public)")
    }
    static func warn(_ category: String, _ message: String, _ context: [String: Any] = [:]) {
        shimLog.warning("\(category, privacy: .public): \(message, privacy: .public)")
    }
    static func error(_ category: String, _ message: String, _ context: [String: Any] = [:]) {
        shimLog.error("\(category, privacy: .public): \(message, privacy: .public)")
    }
    static func debug(_ category: String, _ message: String, _ context: [String: Any] = [:]) {
        shimLog.debug("\(category, privacy: .public): \(message, privacy: .public)")
    }
}

// MARK: - ErrorReporter

final class ErrorReporter {
    static let shared = ErrorReporter()
    private init() {}

    enum Category {
        case audio, transcription, summary, integration, calendar, unknown
    }

    func report(_ error: Error, category: Category = .unknown, context: [String: String] = [:]) {
        shimLog.error("[\(String(describing: category), privacy: .public)] \(error.localizedDescription, privacy: .public)")
    }

    func reportAsync(_ error: Error, category: Category = .unknown, context: [String: String] = [:]) {
        shimLog.error("[\(String(describing: category), privacy: .public)] \(error.localizedDescription, privacy: .public)")
    }
}
