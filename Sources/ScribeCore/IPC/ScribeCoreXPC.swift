import Foundation

/// XPC protocol between Scribe Core (server) and Scribe UI (client).
/// Phase 2: replace file-command IPC with this for synchronous command/response.
@objc public protocol ScribeCoreXPC {
    func startRecording(withReply reply: @escaping (Bool, String?) -> Void)
    func stopRecording(withReply reply: @escaping (Bool, String?) -> Void)
    func recordingStatus(withReply reply: @escaping (String, Double) -> Void)
    func search(_ query: String, limit: Int, withReply reply: @escaping (Data?, Error?) -> Void)
    func pendingTranscriptionIDs(withReply reply: @escaping ([String]) -> Void)
    func vaultPath(withReply reply: @escaping (String) -> Void)
    func rebuildIndex(withReply reply: @escaping (Bool) -> Void)
}
