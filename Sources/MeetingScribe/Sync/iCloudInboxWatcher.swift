import Foundation
import OSLog

/// Watches vault/_inbox/ for files dropped by iPhone Shortcuts.
/// Routes them by `type` field into the appropriate subsystem.
/// Correlates .m4a + .json sidecar pairs for voice notes (120s timeout).
@available(macOS 14.0, *)
@MainActor
final class iCloudInboxWatcher {
    static let shared = iCloudInboxWatcher()
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "iCloudInboxWatcher")

    private var query: NSMetadataQuery?
    private var pendingVoiceNotes: [String: VoicePair] = [:]
    private var processedIDs: Set<String> = []
    private var vaultURL: URL?

    // Callbacks — set by the owner
    var onQuickNote: ((InboxEnvelope) -> Void)?
    var onActionItem: ((InboxEnvelope) -> Void)?
    var onAddPerson: ((InboxEnvelope) -> Void)?
    var onVoiceNote: ((URL, InboxEnvelope) -> Void)?

    struct VoicePair {
        var jsonURL: URL?
        var audioURL: URL?
        var envelope: InboxEnvelope?
        var receivedAt: Date = .now
    }

    func start(vaultURL: URL) {
        self.vaultURL = vaultURL
        loadProcessedIDs()

        // Ensure inbox directory exists
        let inboxURL = vaultURL.appendingPathComponent("_inbox", isDirectory: true)
        let processedURL = inboxURL.appendingPathComponent("processed", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: processedURL, withIntermediateDirectories: true)

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            NSMetadataItemPathKey,
            inboxURL.path
        )
        q.notificationBatchingInterval = 2.0

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate, object: q
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: q
        )
        q.start()
        self.query = q
        log.info("iCloudInboxWatcher started at \(inboxURL.path)")
    }

    func stop() {
        if let q = query {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        }
        query?.stop()
        query = nil
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        query?.disableUpdates()
        defer { query?.enableUpdates() }

        guard let items = query?.results as? [NSMetadataItem] else { return }
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)

            let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            processItem(at: url)
        }
        evictStalePairs()
    }

    private func processItem(at url: URL) {
        let ext = url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent
        guard !processedIDs.contains(stem) else { return }

        if ext == "json" {
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? JSONDecoder().decode(InboxEnvelope.self, from: data) else {
                moveToProcessed(url); return
            }
            switch envelope.type {
            case "quick-note":   onQuickNote?(envelope); moveToProcessed(url)
            case "action-item":  onActionItem?(envelope); moveToProcessed(url)
            case "add-person":   onAddPerson?(envelope); moveToProcessed(url)
            case "voice-note":
                pendingVoiceNotes[stem, default: VoicePair()].jsonURL = url
                pendingVoiceNotes[stem]?.envelope = envelope
                checkVoicePair(stem: stem)
            default:
                log.warning("Unknown inbox type: \(envelope.type)")
                moveToProcessed(url)
            }
        } else if ext == "m4a" {
            pendingVoiceNotes[stem, default: VoicePair()].audioURL = url
            checkVoicePair(stem: stem)
        }
    }

    private func checkVoicePair(stem: String) {
        guard let pair = pendingVoiceNotes[stem],
              let jsonURL = pair.jsonURL, let audioURL = pair.audioURL,
              let envelope = pair.envelope else { return }
        pendingVoiceNotes.removeValue(forKey: stem)
        onVoiceNote?(audioURL, envelope)
        moveToProcessed(jsonURL)
        moveToProcessed(audioURL)
    }

    private func evictStalePairs() {
        let stale = pendingVoiceNotes.filter { Date().timeIntervalSince($0.value.receivedAt) > 120 }
        for (key, pair) in stale {
            if let url = pair.jsonURL { moveToProcessed(url) }
            if let url = pair.audioURL { moveToProcessed(url) }
            pendingVoiceNotes.removeValue(forKey: key)
            log.warning("Evicted stale voice pair: \(key)")
        }
    }

    private func moveToProcessed(_ url: URL) {
        guard let vaultURL else { return }
        let processedURL = vaultURL.appendingPathComponent("_inbox/processed", isDirectory: true)
        let dest = processedURL.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.moveItem(at: url, to: dest)
        processedIDs.insert(url.deletingPathExtension().lastPathComponent)
        saveProcessedIDs()
    }

    // MARK: - Persistence

    private var processedLogURL: URL? {
        vaultURL?.appendingPathComponent("_inbox/.processed_ids.json")
    }

    private func loadProcessedIDs() {
        guard let url = processedLogURL, let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
        processedIDs = Set(ids)
    }

    private func saveProcessedIDs() {
        guard let url = processedLogURL,
              let data = try? JSONEncoder().encode(Array(processedIDs)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Inbox envelope model

struct InboxEnvelope: Codable {
    let type: String
    let id: String
    let created: String
    var title: String?
    var body: String?
    // Action item
    var dueDate: String?
    var priority: String?
    // Person
    var name: String?
    var company: String?
    var email: String?
    var phone: String?
    var role: String?
    // Voice note
    var audioFile: String?
    var durationSeconds: Int?
}
