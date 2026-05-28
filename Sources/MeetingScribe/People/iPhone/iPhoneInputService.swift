import Foundation
import Network
import OSLog

/// A tiny on-device HTTP server (Phase 7-B, Option 1) that lets an iPhone on the
/// same Wi-Fi add a person to MeetingScribe by opening a web form. Built on
/// `Network.framework` — no third-party web server. The listener takes an
/// ephemeral port (so it never collides with another process), serves a
/// self-contained mobile HTML form on `GET /`, and creates a `Person` on
/// `POST /add-person`.
///
/// Design decisions (documented per Task 4):
///   • The form posts `application/x-www-form-urlencoded`, and the optional
///     photo is base64-encoded into a hidden field by a little JS `FileReader`
///     shim — that sidesteps multipart parsing entirely for a single contact.
///   • The server binds to all interfaces; we surface the LAN IP for the QR URL.
///   • Person creation hops to the main actor (PeopleStore is `@MainActor`).
@MainActor
final class iPhoneInputService: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "iPhoneInput")

    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16?
    @Published private(set) var connectionCount = 0
    @Published private(set) var lastAdded: String?
    @Published private(set) var addedCount = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.tyleryannes.MeetingScribe.iPhoneInput")

    /// The URL an iPhone should open, e.g. `http://192.168.1.42:51234/add-person`.
    var formURL: String? {
        guard let port, let ip = Self.localIPAddress() else { return nil }
        return "http://\(ip):\(port)/add-person"
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)   // ephemeral port
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let assigned = listener.port?.rawValue
                    Task { @MainActor in
                        self.port = assigned
                        self.isRunning = true
                    }
                case .failed(let error):
                    self.log.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                    Task { @MainActor in self.stop() }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            listener.start(queue: queue)
        } catch {
            log.error("Failed to start listener: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = nil
        connectionCount = 0
    }

    // MARK: - Connection handling

    private nonisolated func accept(_ conn: NWConnection) {
        Task { @MainActor in self.connectionCount += 1 }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                Task { @MainActor in self?.connectionCount = max(0, (self?.connectionCount ?? 1) - 1) }
            default:
                break
            }
        }
        conn.start(queue: queue)
        receive(on: conn, buffer: Data())
    }

    private nonisolated func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let request = Self.parseIfComplete(buf) {
                self.handle(request, on: conn)
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(on: conn, buffer: buf)
            }
        }
    }

    // MARK: - Request parsing

    private struct Request {
        let method: String
        let path: String
        let body: String
    }

    /// Returns a parsed request once the buffer holds a full message, else nil.
    private nonisolated static func parseIfComplete(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0].uppercased()
        let path = parts[1]

        // Find Content-Length for body-bearing requests.
        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "content-length" {
                contentLength = Int(kv[1]) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let bodyData = data.subdata(in: bodyStart..<data.endIndex)
        if method == "POST" && bodyData.count < contentLength {
            return nil   // wait for more
        }
        let body = String(data: bodyData, encoding: .utf8) ?? ""
        return Request(method: method, path: path, body: body)
    }

    // MARK: - Routing

    private nonisolated func handle(_ request: Request, on conn: NWConnection) {
        let pathOnly = request.path.components(separatedBy: "?").first ?? request.path
        if request.method == "POST" && pathOnly == "/add-person" {
            let fields = Self.parseFormURLEncoded(request.body)
            Task { @MainActor in
                let name = self.createPerson(from: fields)
                self.respond(on: conn, html: Self.confirmationHTML(name: name), status: "200 OK")
            }
        } else {
            // Any GET (/, /add-person, favicon, etc.) returns the form.
            respond(on: conn, html: Self.formHTML, status: "200 OK")
        }
    }

    private nonisolated func respond(on conn: NWConnection, html: String, status: String) {
        let body = Data(html.utf8)
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: text/html; charset=utf-8\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"
        var out = Data(response.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Person creation (main actor)

    /// Maps the submitted form fields onto a new `Person`. Returns the name for
    /// the confirmation page.
    private func createPerson(from fields: [String: String]) -> String {
        let name = (fields["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }

        // Resolve / create people-tags from the comma list.
        let tagNames = (fields["tags"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tagIDs = Set(tagNames.map { PeopleTagStore.shared.createTag(name: $0).id })

        let person = PeopleStore.shared.createPerson(
            displayName: name,
            company: fields["company"] ?? "",
            role: fields["role"] ?? "",
            email: fields["email"] ?? "",
            phone: fields["phone"] ?? "",
            bio: fields["notes"] ?? "",
            tagIDs: tagIDs
        )

        // Optional base64 photo (data URL or raw base64).
        if let photo = fields["photo"], !photo.isEmpty {
            let base64 = photo.components(separatedBy: ",").last ?? photo
            if let data = Data(base64Encoded: base64) {
                PeopleStore.shared.attachPhoto(to: person.id, data: data, ext: "jpg")
            }
        }

        lastAdded = name
        addedCount += 1
        log.info("Added person via iPhone form: \(name, privacy: .public)")
        return name
    }

    // MARK: - Helpers

    /// Parses `application/x-www-form-urlencoded` into a dictionary.
    private nonisolated static func parseFormURLEncoded(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in body.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            let key = percentDecode(kv[0])
            let value = percentDecode(kv[1])
            result[key] = value
        }
        return result
    }

    private nonisolated static func percentDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    /// First non-loopback IPv4 address (en0/en1 preferred) for the QR URL.
    nonisolated static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let addr = current.pointee.ifa_addr.pointee
            if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
               (flags & IFF_LOOPBACK) == 0,
               addr.sa_family == UInt8(AF_INET) {
                let name = String(cString: current.pointee.ifa_name)
                if name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(current.pointee.ifa_addr, socklen_t(addr.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return address
    }
}
