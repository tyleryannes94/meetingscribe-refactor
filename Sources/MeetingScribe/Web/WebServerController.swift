import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import OSLog

private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "WebServerController")

/// Owns the embedded web server's lifecycle and the data the Settings UI needs
/// to show the connection card (URLs + QR code). A `@MainActor` singleton so
/// both the app (which starts it at launch) and `SettingsView` (which toggles
/// it) talk to the same instance — mirrors `PeopleStore.shared`.
@MainActor
final class WebServerController: ObservableObject {
    static let shared = WebServerController()

    private let server = HTTPServer()
    private var api: WebAPI?

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private init() {}

    /// Called once at launch with the app's manager so the API can read/write
    /// through the live stores.
    func configure(manager: MeetingManager) {
        if api == nil { api = WebAPI(manager: manager) }
        if AppSettings.shared.webServerToken.isEmpty {
            AppSettings.shared.webServerToken = Self.makeToken()
        }
    }

    func startIfEnabled() {
        if AppSettings.shared.webServerEnabled { start() }
    }

    func start() {
        guard let api else {
            lastError = "Web server not configured yet"
            return
        }
        let port = UInt16(clamping: AppSettings.shared.webServerPort)
        do {
            try server.start(port: port) { request in
                await api.handle(request)
            }
            isRunning = true
            lastError = nil
            log.info("Web server started on port \(port, privacy: .public)")
        } catch {
            isRunning = false
            lastError = error.localizedDescription
            log.error("Web server failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        server.stop()
        isRunning = false
    }

    func restart() {
        stop()
        start()
    }

    /// Toggle from the Settings UI: persists the choice and (re)starts/stops.
    func setEnabled(_ enabled: Bool) {
        AppSettings.shared.webServerEnabled = enabled
        if enabled { start() } else { stop() }
    }

    func setPort(_ port: Int) {
        AppSettings.shared.webServerPort = port
        if isRunning { restart() }
    }

    // MARK: - Token

    var token: String { AppSettings.shared.webServerToken }

    func regenerateToken() {
        AppSettings.shared.webServerToken = Self.makeToken()
        objectWillChange.send()
        if isRunning { restart() }   // invalidate old cookies/links
    }

    /// 24 random bytes, hex-encoded → 48 chars. Plenty for a personal,
    /// LAN/Tailscale-scoped secret.
    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Connection endpoints

    struct Endpoint: Identifiable {
        let id = UUID()
        /// "Same Wi-Fi", "Anywhere (Tailscale)", "Bonjour name".
        let label: String
        /// Full URL including the one-time `?t=` handshake.
        let url: String
    }

    /// The URLs the phone can use, with the token embedded so scanning/tapping
    /// "just works". Returns an empty array when no usable address is found.
    func endpoints() -> [Endpoint] {
        let port = AppSettings.shared.webServerPort
        let token = AppSettings.shared.webServerToken
        func url(_ host: String) -> String { "http://\(host):\(port)/?t=\(token)" }

        var result: [Endpoint] = []
        if let tailscale = NetworkInfo.tailscaleIP() {
            result.append(Endpoint(label: "Anywhere (Tailscale)", url: url(tailscale)))
        }
        if let lan = NetworkInfo.lanIP() {
            result.append(Endpoint(label: "Same Wi-Fi", url: url(lan)))
        }
        if let host = NetworkInfo.localHostName {
            result.append(Endpoint(label: "Bonjour name", url: url(host)))
        }
        return result
    }

    // MARK: - QR

    /// A QR code encoding `string`, rendered at a crisp size for display.
    func qrImage(for string: String) -> NSImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale: CGFloat = 8
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
