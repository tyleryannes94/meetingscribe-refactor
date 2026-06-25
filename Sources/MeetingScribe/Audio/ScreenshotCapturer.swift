import Foundation
import AppKit
import ScreenCaptureKit
import OSLog

/// One-shot still capture via `SCScreenshotManager` (macOS 14+). Mirrors the
/// three capture targets used by `ScreenRecorder`.
@available(macOS 14.0, *)
enum ScreenshotCapturer {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Screenshot")

    enum Target {
        case fullScreen
        case window(SCWindow)
        case region(CGRect)
    }

    /// Captures the target and returns a CGImage. Throws if no display is found.
    static func capture(_ target: Target) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "MeetingScribe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available for capture."])
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.showsCursor = false

        switch target {
        case .fullScreen:
            filter = SCContentFilter(display: display, excludingWindows: [])
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.width = max(Int(window.frame.width * scale), 1)
            config.height = max(Int(window.frame.height * scale), 1)
        case .region(let rect):
            filter = SCContentFilter(display: display, excludingWindows: [])
            config.sourceRect = rect
            config.width = max(Int(rect.width * scale), 1)
            config.height = max(Int(rect.height * scale), 1)
        }

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Writes a CGImage to `url` as PNG.
    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch {
            log.error("writePNG failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
