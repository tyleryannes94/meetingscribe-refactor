import Foundation
import Darwin

/// Captures otherwise-silent crashes — uncaught ObjC/NSException and fatal POSIX
/// signals — into the diagnostics folder so a crash is recoverable post-mortem
/// instead of vanishing. (V5 PS-3) We re-raise the default handler so the OS
/// crash log (.ips) is still produced.
///
/// Two very different execution contexts:
///   • `NSSetUncaughtExceptionHandler` runs in a NORMAL context, so it may use
///     Foundation freely (rich, timestamped report with symbolized frames).
///   • A POSIX `signal` handler must be **async-signal-safe**: no malloc, no
///     Foundation, no Swift runtime allocation. The previous version called
///     `Thread.callStackSymbols` (→ `backtrace_symbols` + ObjC array bridging →
///     malloc), `Date()`, string interpolation and `FileManager`/`String.write`
///     from inside the handler. Re-entering malloc while the heap lock may be
///     held (e.g. during a SIGABRT raised from `free`) deadlocks or double-faults
///     — exactly the secondary crash seen in the field. The signal path below
///     now uses ONLY `open`/`write`/`backtrace`/`backtrace_symbols_fd`, all of
///     which are async-signal-safe, with the destination path resolved up front.
enum CrashReporter {
    private static var crashDir: URL {
        AppLog.fileURL.deletingLastPathComponent().appendingPathComponent("crashes", isDirectory: true)
    }

    /// Pre-resolved, NUL-terminated destination for the signal handler. Built
    /// once at `install()` time (where allocation is safe) so the handler itself
    /// never has to touch Foundation or malloc to learn where to write.
    private static var signalPath: [CChar] = []

    static func install() {
        // Uncaught ObjC/Swift exceptions: normal context → rich report is fine.
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.writeRich(kind: "exception",
                                    reason: exception.reason ?? exception.name.rawValue,
                                    stack: exception.callStackSymbols)
        }

        // Resolve (and create) the signal-crash file path NOW, while it's safe.
        try? FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)
        signalPath = crashDir.appendingPathComponent("crash-signal.txt").path.utf8CString.map { $0 }

        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            // The closure captures nothing → converts to a C function pointer.
            signal(sig) { s in
                CrashReporter.handleSignalSafely(s)
                signal(s, SIG_DFL)   // restore default and re-raise for the OS log
                raise(s)
            }
        }
    }

    /// Async-signal-safe crash note: opens the pre-resolved path and writes a
    /// fixed header plus a raw backtrace. Uses only signal-safe syscalls
    /// (`open`/`write`/`close`/`backtrace`/`backtrace_symbols_fd`) — no malloc,
    /// no Foundation, no Swift allocation.
    private static func handleSignalSafely(_ s: Int32) {
        let fd: Int32 = signalPath.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress, buf.count > 1 else { return -1 }
            return open(base, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }
        guard fd >= 0 else { return }
        writeRaw(fd, "MeetingScribe crash\nkind: signal ")
        writeRaw(fd, signalName(s))
        writeRaw(fd, "\nstack:\n")
        // `backtrace` + `backtrace_symbols_fd` are async-signal-safe (unlike
        // `backtrace_symbols`, which mallocs). Frame buffer lives on the stack.
        withUnsafeTemporaryAllocation(of: UnsafeMutableRawPointer?.self, capacity: 128) { frames in
            let n = backtrace(frames.baseAddress, Int32(frames.count))
            backtrace_symbols_fd(frames.baseAddress, n, fd)
        }
        close(fd)
    }

    /// `write(2)` the bytes of a compile-time string literal. `StaticString`
    /// exposes its UTF-8 directly (the bytes live in the binary), so there is no
    /// allocation — safe inside a signal handler.
    private static func writeRaw(_ fd: Int32, _ s: StaticString) {
        s.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }
    }

    private static func signalName(_ s: Int32) -> StaticString {
        switch s {
        case SIGABRT: return "SIGABRT"
        case SIGILL:  return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE:  return "SIGFPE"
        case SIGBUS:  return "SIGBUS"
        case SIGTRAP: return "SIGTRAP"
        default:      return "unknown"
        }
    }

    /// Rich report for the uncaught-exception path (NOT a signal context).
    private static func writeRich(kind: String, reason: String, stack: [String]) {
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
