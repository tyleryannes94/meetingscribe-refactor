import XCTest

/// Smoke test that the MeetingScribeMCP executable advertises the three new
/// Brain Dump tools in its `tools/list` response. We can't `@testable import`
/// the MCP target (it's a separate executable), so we drive the binary as a
/// subprocess and parse the JSON-RPC reply.
///
/// The build product path comes from `SWIFT_BUILD_BIN` if set (CI passes
/// `swift build --show-bin-path`); otherwise we try the conventional
/// `.build/debug` and `.build/release` paths next to the package root.
final class BrainDumpMCPRegistrationTests: XCTestCase {

    func testTopLevelToolsListAdvertisesBrainDumpTools() throws {
        // Locate the MCP binary. We walk up from this file looking for a
        // `.build/.../MeetingScribeMCP` so the test works on local laptops
        // and CI without environment fiddling.
        guard let binary = Self.locateMCPBinary() else {
            throw XCTSkip("MeetingScribeMCP binary not built; run `swift build` first.")
        }

        let tmpStorage = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpMCPRegTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpStorage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpStorage) }

        let proc = Process()
        proc.executableURL = binary
        proc.environment = ProcessInfo.processInfo.environment
            .merging(["MEETINGSCRIBE_STORAGE": tmpStorage.path]) { _, new in new }
        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = Pipe()
        try proc.run()

        // Send: initialize + tools/list, then close stdin.
        let initRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"# + "\n"
        let listRequest = #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"# + "\n"
        stdin.fileHandleForWriting.write(Data(initRequest.utf8))
        stdin.fileHandleForWriting.write(Data(listRequest.utf8))
        try? stdin.fileHandleForWriting.close()

        // Bound the wait so a hung binary doesn't hang the test runner.
        let deadline = Date().addingTimeInterval(8)
        var collected = Data()
        var foundList = false
        while Date() < deadline {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty {
                if !proc.isRunning { break }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            collected.append(chunk)
            if let text = String(data: collected, encoding: .utf8),
               text.contains("submit_brain_dump"),
               text.contains("list_brain_dump_sessions"),
               text.contains("get_brain_dump_session") {
                foundList = true
                break
            }
        }
        proc.terminate()
        proc.waitUntilExit()

        XCTAssertTrue(foundList,
                      "tools/list should advertise submit_brain_dump, list_brain_dump_sessions, get_brain_dump_session.")
    }

    private static func locateMCPBinary() -> URL? {
        if let override = ProcessInfo.processInfo.environment["MEETINGSCRIBE_MCP_BINARY"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        // Walk up from this file (Tests/MeetingScribeTests/<this>.swift) to
        // find the package root, then look for .build/{debug,release}.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let pkg = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) {
                for variant in ["debug", "release"] {
                    let candidate = dir
                        .appendingPathComponent(".build")
                        .appendingPathComponent(variant)
                        .appendingPathComponent("MeetingScribeMCP")
                    if FileManager.default.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
