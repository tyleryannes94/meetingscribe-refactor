import Foundation

/// A single screen recording — captured outside any calendar meeting.
/// Files live at: <storageDir>/ScreenRecordings/<slug>/
///   ├── recording.json
///   ├── recording.mov        (screen video + system audio; mic muxed if enabled)
///   ├── mic.m4a              (sidecar mic track — only when mic muxing fell back)
///   ├── thumbnail.png
///   ├── transcript.md        (Whisper on the audio track — Phase 1)
///   ├── frames/…             (sampled frames — Phase 2)
///   ├── ocr.md               (Vision OCR — Phase 2)
///   └── summary.md           (Ollama summary — Phase 2)
struct ScreenRecording: Identifiable, Codable, Hashable {
    /// What was captured. Mirrors the three SCContentFilter variants.
    enum Mode: String, Codable, Hashable {
        case fullScreen, window, region

        var label: String {
            switch self {
            case .fullScreen: return "Full screen"
            case .window: return "Window"
            case .region: return "Region"
            }
        }
    }

    var id: String
    var title: String
    var createdAt: Date
    var durationSeconds: Double
    /// Pixel dimensions of the captured video (post-scaling).
    var width: Int
    var height: Int
    var mode: Mode
    /// True when a microphone voice-over track was captured alongside the screen.
    var hasMic: Bool
    /// True when mic capture fell back to a sidecar `mic.m4a` (couldn't mux into
    /// the mov). Playback/transcription then stitch the sidecar in.
    var micIsSidecar: Bool
    /// First ~150 chars of transcript for the list preview.
    var snippet: String

    var slug: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let datePart = f.string(from: createdAt)
        let safe = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(safe.prefix(40))
        return "\(datePart)-\(truncated.isEmpty ? "Recording" : truncated)"
    }
}
