import Foundation

/// Captures otherwise-silent crashes — uncaught ObjC/NSException and fatal POSIX
/// signals — into the diagnostics folder so a crash is recoverable post-mortem
/// instead of vanishing. (V5 PS-3) Best-effort: file I/O in a signal handler is
/// not strictly async-signal-safe, but for a local desktop diagnostic bundle the
/// trade-off (a recoverable stack vs nothing) is worth it. We re-raise the
/// default handler so the OS crash log is still produced.
enum CrashReporter {
    private static var crashDir: URL {
        AppLog.fileURL.deletingLastPathComponent().appendingPathComponent("crashes", isDirectory: true)
    }

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.write(kind: "exception",
                                reason: exception.reason ?? exception.name.rawValue,
                                stack: exception.callStackSymbols)
        }
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig) { s in
                CrashReporter.write(kind: "signal-\(s)",
                                    reason: "fatal signal \(s)",
                                    stack: Thread.callStackSymbols)
                signal(s, SIG_DFL)   // restore default and re-raise for the OS log
                raise(s)
            }
        }
    }

    private static func write(kind: String, reason: String, stack: [String]) {
        let secs = Int(Date().timeIntervalSince1970)
        let body = """
        MeetingScribe crash
        when: \(secs) (unix)
        kind: \(kind)
        reason: \(reason)

        stack:
        \(stack.joined(separator: "\n"))
        """
        try? FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)
        try? body.write(to: crashDir.appendingPathComponent("crash-\(secs).txt"),
                        atomically: true, encoding: .utf8)
    }
}
