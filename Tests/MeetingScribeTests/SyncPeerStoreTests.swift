import XCTest
@testable import MeetingScribe

@MainActor
final class SyncPeerStoreTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncPeerStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
        SyncPeerStore.shared.reloadFromDisk()
    }

    override func tearDownWithError() throws {
        // Wipe whatever the test added so we don't leak into other suites.
        for peer in SyncPeerStore.shared.peers {
            SyncPeerStore.shared.deletePeer(id: peer.id)
        }
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    func testAddPeer() {
        let added = SyncPeerStore.shared.addPeer(label: "Work MacBook",
                                                  baseURL: "http://100.1.2.3:8765")
        XCTAssertNotNil(added)
        XCTAssertEqual(added?.label, "Work MacBook")
        XCTAssertEqual(added?.baseURL, "http://100.1.2.3:8765")
        XCTAssertFalse(added!.sharedSecret.isEmpty,
                       "missing secret should be auto-generated")
        XCTAssertEqual(SyncPeerStore.shared.peers.count, 1)
    }

    func testRejectsEmptyOrInvalidBaseURL() {
        XCTAssertNil(SyncPeerStore.shared.addPeer(label: "", baseURL: "http://x"))
        XCTAssertNil(SyncPeerStore.shared.addPeer(label: "x", baseURL: ""))
        XCTAssertNil(SyncPeerStore.shared.addPeer(label: "x", baseURL: " "))
    }

    func testDeletePeer() {
        let p = SyncPeerStore.shared.addPeer(label: "Work",
                                              baseURL: "http://100.1.2.3:8765")!
        SyncPeerStore.shared.deletePeer(id: p.id)
        XCTAssertTrue(SyncPeerStore.shared.peers.isEmpty)
    }

    func testUpdatePeer() {
        var p = SyncPeerStore.shared.addPeer(label: "Work",
                                              baseURL: "http://100.1.2.3:8765")!
        p.label = "Renamed"
        p.lastSyncAt = Date()
        SyncPeerStore.shared.updatePeer(p)
        XCTAssertEqual(SyncPeerStore.shared.peers.first?.label, "Renamed")
        XCTAssertNotNil(SyncPeerStore.shared.peers.first?.lastSyncAt)
    }

    func testIncomingSecretLookupConstantTime() {
        let p = SyncPeerStore.shared.addPeer(label: "Work",
                                              baseURL: "http://100.1.2.3:8765",
                                              sharedSecret: "specific-secret-value-12345")!
        XCTAssertEqual(SyncPeerStore.shared.peerForIncomingSecret("specific-secret-value-12345")?.id,
                        p.id)
        XCTAssertNil(SyncPeerStore.shared.peerForIncomingSecret("wrong-secret"))
        XCTAssertNil(SyncPeerStore.shared.peerForIncomingSecret("specific-secret-value-1234"))
    }

    func testPersistsAcrossReload() {
        _ = SyncPeerStore.shared.addPeer(label: "Work",
                                          baseURL: "http://100.1.2.3:8765",
                                          sharedSecret: "shared-secret-xyz")
        SyncPeerStore.shared.reloadFromDisk()
        XCTAssertEqual(SyncPeerStore.shared.peers.count, 1)
        XCTAssertEqual(SyncPeerStore.shared.peers.first?.sharedSecret, "shared-secret-xyz")
    }

    func testNewSecretIsURLSafe() {
        let s = SyncPeer.newSecret()
        XCTAssertFalse(s.isEmpty)
        XCTAssertFalse(s.contains("+"))
        XCTAssertFalse(s.contains("/"))
        XCTAssertFalse(s.contains("="))
    }
}
