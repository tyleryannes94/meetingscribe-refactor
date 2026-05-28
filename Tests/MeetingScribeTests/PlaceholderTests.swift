import XCTest
@testable import MeetingScribe
@testable import MeetingScribeShared

/// Placeholder test ensuring the test target compiles. Real high-leverage
/// tests for ActionItemExtractor, MeetingStore drift detection, and the
/// whisper JSON parser are added in Batch 8.
final class PlaceholderTests: XCTestCase {
    func testJSONValueRoundTrip() throws {
        let v: JSONValue = .object([
            "name": .string("hello"),
            "n": .int(42),
            "ok": .bool(true),
            "nested": .array([.null, .double(1.5)])
        ])
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(v, decoded)
    }

    func testSchemaEnvelopeRoundTrip() throws {
        struct Payload: Codable, Equatable { let x: Int; let y: String }
        let env = SchemaEnvelope(version: 2, data: Payload(x: 7, y: "hi"))
        let data = try JSONEncoder().encode(env)
        let back: Payload = try SchemaEnvelope.decode(Payload.self, from: data, currentVersion: 2)
        XCTAssertEqual(back, env.data)
    }

    func testSchemaEnvelopeReadsLegacyRawPayload() throws {
        struct Payload: Codable, Equatable { let x: Int }
        let raw = try JSONEncoder().encode(Payload(x: 11))
        let back: Payload = try SchemaEnvelope.decode(Payload.self, from: raw, currentVersion: 2)
        XCTAssertEqual(back, Payload(x: 11))
    }
}
