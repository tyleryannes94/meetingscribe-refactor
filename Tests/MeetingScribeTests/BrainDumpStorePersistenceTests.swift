import XCTest
@testable import MeetingScribe

/// Round-trip tests for `BrainDumpStore` — create / mutate / re-read /
/// schema-envelope decoding. Mirrors the pattern in MeetingStoreTests:
/// point AppSettings.storageDir at a fresh tmp dir, write through the store,
/// flush the persistence coordinator, then construct a second store and
/// assert it sees the same sessions.
@MainActor
final class BrainDumpStorePersistenceTests: XCTestCase {

    private var tmpDir: URL!
    private var originalStorageDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        originalStorageDir = AppSettings.shared.storageDir
        AppSettings.shared.storageDir = tmpDir
    }

    override func tearDownWithError() throws {
        AppSettings.shared.storageDir = originalStorageDir
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testCreateSessionRoundTrips() async throws {
        let store = BrainDumpStore()
        await store.awaitInitialLoad()

        let created = store.createSession(title: "Q3 planning",
                                          body: "Need to ship the docs by Friday.")
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSessionID, created.id)

        TaskPersistenceCoordinator.shared.flushNow()

        let reloaded = BrainDumpStore()
        await reloaded.awaitInitialLoad()
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.sessions.first?.id, created.id)
        XCTAssertEqual(reloaded.sessions.first?.title, "Q3 planning")
        XCTAssertEqual(reloaded.sessions.first?.body,
                       "Need to ship the docs by Friday.")
    }

    func testSourceAndDraftMutationsPersist() async throws {
        let store = BrainDumpStore()
        await store.awaitInitialLoad()

        let session = store.createSession(body: "Refactor the planner module.")
        let url = URL(string: "https://example.com/article")!
        let source = URLSource(url: url, title: "Example",
                               extractedMarkdown: "# Hello\n\nWorld.",
                               isLoading: false)
        store.attachSource(session.id, .url(source))

        let draft = TaskDraft(
            title: "Email the team about the refactor",
            priorityRaw: "high",
            dueDate: Date(timeIntervalSinceReferenceDate: 1_000_000),
            sourceURLs: [url]
        )
        store.appendDraft(session.id, .task(draft))

        TaskPersistenceCoordinator.shared.flushNow()

        let reloaded = BrainDumpStore()
        await reloaded.awaitInitialLoad()
        let live = try XCTUnwrap(reloaded.session(session.id))
        XCTAssertEqual(live.sources.count, 1)
        if case .url(let u) = live.sources.first {
            XCTAssertEqual(u.title, "Example")
            XCTAssertEqual(u.extractedMarkdown, "# Hello\n\nWorld.")
        } else {
            XCTFail("Expected URL source")
        }
        XCTAssertEqual(live.drafts.count, 1)
        if case .task(let t) = live.drafts.first {
            XCTAssertEqual(t.title, "Email the team about the refactor")
            XCTAssertEqual(t.priorityRaw, "high")
            XCTAssertEqual(t.sourceURLs.first, url)
        } else {
            XCTFail("Expected task draft")
        }
        XCTAssertEqual(live.state, .reviewing,
                       "appendDraft on a draft session transitions to reviewing")
    }

    func testEnvelopeIsSchemaVersioned() async throws {
        let store = BrainDumpStore()
        await store.awaitInitialLoad()
        _ = store.createSession(body: "test")
        TaskPersistenceCoordinator.shared.flushNow()

        let url = tmpDir.appendingPathComponent("brain_dump_sessions.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BrainDumpSessionEnvelope.self, from: data)
        XCTAssertEqual(envelope.schemaVersion, BrainDumpSchemaMigrations.currentVersion)
        XCTAssertEqual(envelope.data.count, 1)
    }

    func testCorruptFileFallsBackToBackup() async throws {
        let store = BrainDumpStore()
        await store.awaitInitialLoad()
        let created = store.createSession(title: "Important", body: "Saved")
        TaskPersistenceCoordinator.shared.flushNow()

        let live = tmpDir.appendingPathComponent("brain_dump_sessions.json")
        let backup = live.appendingPathExtension("bak")

        // After the first save .bak might not exist yet; create one explicitly
        // by writing again, which copies the live file to .bak before
        // overwriting (see TaskPersistenceCoordinator.writeNow).
        store.setTitle(created.id, "Important 2")
        TaskPersistenceCoordinator.shared.flushNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path),
                      ".bak should be written before overwriting")

        // Corrupt the live file. The next store should fall through to .bak
        // and surface the prior session.
        try Data("{ not json".utf8).write(to: live, options: .atomic)
        let reloaded = BrainDumpStore()
        await reloaded.awaitInitialLoad()
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.sessions.first?.title, "Important")
    }
}
