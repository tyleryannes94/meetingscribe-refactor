import Foundation
import OSLog

/// Central place every catch block should funnel through. Routes errors to:
///   • Unified log + on-disk app.log (via AppLog)
///   • The opt-in diagnostics buffer (used by "Export diagnostics")
///   • Optional banner publisher consumers can observe
///
/// Why this exists: today, error handling is scattered. Some sites use
/// `Logger.error`, others `AppLog.error`, others swallow with `try?`, others
/// post to a per-controller `lastError: String?`. That makes it impossible to
/// (a) ask the user for "all the recent errors in one place" and (b) wire any
/// uniform UI surface (red banner) without touching every catch block.
///
/// Usage:
///     do { try something() }
///     catch let e as SummaryError { ErrorReporter.shared.report(e, category: .summary) }
///     catch { ErrorReporter.shared.report(error, category: .unknown) }
///
/// Or in async contexts:
///     await ErrorReporter.shared.reportAsync(error, category: .audio,
///                                            context: ["meeting": id])
@MainActor
public final class ErrorReporter: ObservableObject {
    public static let shared = ErrorReporter()

    /// Most recent N errors, newest first. Surfaced by "Export diagnostics".
    @Published public private(set) var recent: [AppError] = []
    /// Banner state — last error a UI surface should consider showing.
    /// Consumers can clear it by calling `dismissBanner()`.
    @Published public private(set) var banner: AppError?

    private let maxRecent = 100
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe",
                             category: "ErrorReporter")

    private init() {}

    // MARK: - Report

    /// Report a `Reportable` (domain error) in a known category.
    public func report(_ error: Reportable,
                       category: AppError.Category,
                       context: [String: String] = [:],
                       showBanner: Bool = false) {
        record(error.asAppError(category: category, context: context),
               showBanner: showBanner)
    }

    /// Report an arbitrary `Error`. Falls back to its `localizedDescription`.
    public func report(_ error: Error,
                       category: AppError.Category,
                       context: [String: String] = [:],
                       showBanner: Bool = false) {
        // Prefer the richer path if the error already conforms.
        if let r = error as? Reportable {
            return report(r, category: category, context: context, showBanner: showBanner)
        }
        let app = AppError(userMessage: error.localizedDescription,
                           debugDetail: String(describing: error),
                           category: category,
                           underlying: error,
                           context: context)
        record(app, showBanner: showBanner)
    }

    /// Direct AppError path for sites that construct one explicitly.
    public func report(_ app: AppError, showBanner: Bool = false) {
        record(app, showBanner: showBanner)
    }

    /// Same as `report` but safe to call from any actor.
    public nonisolated func reportAsync(_ error: Error,
                                        category: AppError.Category,
                                        context: [String: String] = [:],
                                        showBanner: Bool = false) {
        Task { @MainActor in
            self.report(error, category: category, context: context, showBanner: showBanner)
        }
    }

    public func dismissBanner() { banner = nil }

    /// Snapshot for "Export diagnostics" — caller is responsible for writing.
    public func snapshot() -> [AppError] { recent }

    // MARK: - Internals

    private func record(_ app: AppError, showBanner: Bool) {
        recent.insert(app, at: 0)
        if recent.count > maxRecent { recent.removeLast(recent.count - maxRecent) }
        if showBanner { banner = app }

        // Mirror to app.log so it lands in the on-disk diagnostics bundle.
        var ctx = app.context
        if let u = app.underlying { ctx["underlying"] = String(describing: u) }
        if let d = app.debugDetail { ctx["debugDetail"] = d }
        AppLog.error(app.category.rawValue, app.userMessage, ctx)
    }
}
