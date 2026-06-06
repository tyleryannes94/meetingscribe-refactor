import Foundation
import AppKit
import OSLog

/// Debounced, coalesced, off-main file writer for the Projects/Tasks stores
/// (P0-1 / BE-1).
///
/// Before this, every task mutation re-encoded the whole array and wrote it
/// atomically **on the main actor** — so a drag (N midpoint-`sortIndex` writes)
/// or checking several subtasks meant N synchronous full-DB file replacements on
/// the UI thread, exactly the disk I/O the store's init comment blames for launch
/// stalls under a file-scanner.
///
/// Now `ActionItemStore` encodes on the main actor (cheap for these small files)
/// and hands the bytes here. Writes are:
///   - **off the main thread** (a private serial queue),
///   - **coalesced per file** (only the latest bytes for a path are written),
///   - **debounced** (rapid bursts collapse into one write),
///   - **durable** (flushed synchronously on app terminate / resign-active).
///
/// All mutable state is confined to `queue`, so the type is a safe
/// `@unchecked Sendable`.
final class TaskPersistenceCoordinator: @unchecked Sendable {
    static let shared = TaskPersistenceCoordinator()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "TaskPersistence")
    private let queue = DispatchQueue(label: "com.tyleryannes.MeetingScribe.taskpersist", qos: .utility)
    private let debounce: TimeInterval
    /// Latest pending bytes per file path (only the newest write survives).
    private var pending: [String: Data] = [:]
    /// In-flight debounce work item per path, so a new write cancels the old one.
    private var work: [String: DispatchWorkItem] = [:]

    init(debounce: TimeInterval = 0.4) {
        self.debounce = debounce
        // Self-contained durability: flush whatever is pending when the app is
        // about to quit or loses active state, so a debounced write is never
        // lost on exit. Observers fire on the main thread; flushNow drains the
        // serial queue synchronously.
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.flushNow()
        }
        nc.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.flushNow()
        }
    }

    /// Queue a coalesced, debounced atomic write of `data` to `url`. Returns
    /// immediately; the actual write happens off-main after the debounce window.
    func write(_ data: Data, to url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending[url.path] = data
            self.work[url.path]?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.flush(pathFor: url) }
            self.work[url.path] = item
            self.queue.asyncAfter(deadline: .now() + self.debounce, execute: item)
        }
    }

    /// Write the newest pending bytes for one path (runs on `queue`).
    private func flush(pathFor url: URL) {
        guard let data = pending[url.path] else { return }
        pending[url.path] = nil
        work[url.path] = nil
        writeNow(data, to: url)
    }

    /// Synchronously write every pending file now (app terminate / resign).
    /// Drains on the serial queue so it can't race an in-flight `flush`.
    func flushNow() {
        queue.sync {
            let snapshot = pending
            pending.removeAll()
            for (_, item) in work { item.cancel() }
            work.removeAll()
            for (path, data) in snapshot {
                writeNow(data, to: URL(fileURLWithPath: path))
            }
        }
    }

    /// The single atomic write, with directory creation. Called only on `queue`.
    private func writeNow(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            log.error("task persist write failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
