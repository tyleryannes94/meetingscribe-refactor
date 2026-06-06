import XCTest
@testable import MeetingScribe

/// Phase 5 (NP-1): custom database properties — the schema lives on the
/// project, typed values on the task. Verifies CRUD + that deleting a
/// definition scrubs its values, and that PropertyValue round-trips through
/// Codable (it's persisted inside action_items.json).
@MainActor
final class TaskPropertiesTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskPropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    func testAddSetAndDeletePropertyScrubsValues() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let p = store.createProject(name: "DB")
        let def = store.addProperty(toProject: p.id, name: "Effort", type: .number)
        XCTAssertEqual(store.propertyDefs(forProject: p.id).map(\.name), ["Effort"])

        let t = store.createTask(title: "task", projectID: p.id)
        store.setPropertyValue(t.id, propID: def.id, .number(5))
        XCTAssertEqual(store.items.first { $0.id == t.id }?.properties?[def.id], .number(5))

        store.deleteProperty(def.id, fromProject: p.id)
        XCTAssertTrue(store.propertyDefs(forProject: p.id).isEmpty, "definition removed")
        XCTAssertNil(store.items.first { $0.id == t.id }?.properties?[def.id], "value scrubbed")
    }

    func testPropertyValueCodableRoundTrip() throws {
        let values: [PropertyValue] = [
            .text("hi"), .number(3.5), .select("Done"), .checkbox(true),
            .date(Date(timeIntervalSince1970: 1_700_000_000)), .url("https://x.y")
        ]
        let data = try JSONEncoder().encode(values)
        let back = try JSONDecoder().decode([PropertyValue].self, from: data)
        XCTAssertEqual(back, values)
    }
}
