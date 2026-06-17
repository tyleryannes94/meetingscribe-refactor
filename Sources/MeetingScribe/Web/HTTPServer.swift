import Foundation
import Network
import OSLog

private let httpLog = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "WebServer")

/// A parsed HTTP/1.1 request. Value type so it crosses the actor hop into the
/// `@MainActor` `WebAPI` cleanly.
struct HTTPRequest: Sendable {
    var method: String
    /// Path component only, percent-decoded (e.g. "/api/meetings/123").
    var path: String
    var query: [String: String]
    /// Header keys are lowercased.
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// Convenience: the request cookies as a dictionary.
    var cookies: [String: String] {
        guard let raw = header("cookie") else { return [:] }
        var out: [String: String] = [:]
        for pair in raw.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    /// Path split into non-empty components: "/api/meetings/123" → ["api","meetings","123"].
    var components: [String] {
        path.split(separator: "/").map(String.init)
    }
}

/// An HTTP response ready to serialize.
struct HTTPResponse: Sendable {
    var status: Int = 200
    var headers: [String: String] = [:]
    var body: Data = Data()

    static func json(_ data: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": "application/json; charset=utf-8"],
                     body: data)
    }

    static func jsonObject(_ object: Any, status: Int = 200,
                           setCookie: String? = nil) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        var headers: [String: String] = ["Content-Type": "application/json; charset=utf-8"]
        if let setCookie { headers["Set-Cookie"] = setCookie }
        return HTTPResponse(status: status, headers: headers, body: data)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data()
        return .json(data, status: status)
    }

    static func html(_ html: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": "text/html; charset=utf-8"],
                     body: Data(html.utf8))
    }

    static func redirect(to location: String, setCookie: String? = nil) -> HTTPResponse {
        var headers = ["Location": location]
        if let setCookie { headers["Set-Cookie"] = setCookie }
        return HTTPResponse(status: 302, headers: headers)
    }
}

/// A tiny HTTP/1.1 server built on Network.framework. One request per
/// connection (`Connection: close`) — no keep-alive, which keeps the parser
/// trivial and is perfectly adequate for a single-user phone client on the LAN
/// or over Tailscale.
///
/// Binds to all interfaces, so the same port is reachable via the Mac's LAN IP,
/// its Tailscale 100.x address, and localhost simultaneously.
final class HTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let queue = DispatchQueue(label: "com.tyleryannes.MeetingScribe.httpserver",
                                      attributes: .concurrent)
    private var listener: NWListener?
    private var handler: Handler?

    /// Strong references to in-flight connections, keyed by identity. Without
    /// this the `HTTPConnection` would deallocate the instant `accept` returns
    /// (its NW callbacks hold only `weak self`), so it would accept the socket
    /// and then never reply. Guarded by `connectionsLock`.
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private let connectionsLock = NSLock()

    var isRunning: Bool { listener != nil }

    /// Starts listening on `port`. Throws if the port can't be bound (e.g. in
    /// use by another process).
    func start(port: UInt16, handler: @escaping Handler) throws {
        stop()
        self.handler = handler

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HTTPServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Listen on all interfaces (default) so LAN + Tailscale both work.

        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                httpLog.info("Web server listening on port \(port, privacy: .public)")
            case .failed(let error):
                httpLog.error("Web server failed: \(error.localizedDescription, privacy: .public)")
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connectionsLock.lock()
        let live = connections.values
        connections.removeAll()
        connectionsLock.unlock()
        for conn in live { conn.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        guard let handler else { connection.cancel(); return }
        let conn = HTTPConnection(connection: connection, queue: queue, handler: handler)
        let key = ObjectIdentifier(conn)
        connectionsLock.lock()
        connections[key] = conn          // retain until it finishes
        connectionsLock.unlock()
        conn.onClose = { [weak self] in
            guard let self else { return }
            self.connectionsLock.lock()
            self.connections[key] = nil
            self.connectionsLock.unlock()
        }
        conn.start()
    }
}

/// Drives a single connection: receive → parse one request → dispatch → respond
/// → close.
private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: HTTPServer.Handler
    private var buffer = Data()
    /// Cap total request size (headers + body) to avoid unbounded growth.
    private let maxRequestBytes = 16 * 1024 * 1024

    /// Invoked exactly once when the connection finishes, so the server can drop
    /// its strong reference. Guarded by `closedFlag`.
    var onClose: (() -> Void)?
    private var closed = false
    private let closedLock = NSLock()

    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping HTTPServer.Handler) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        pump()
    }

    /// Tears the connection down and notifies the server once.
    func cancel() {
        closedLock.lock()
        let alreadyClosed = closed
        closed = true
        closedLock.unlock()
        connection.cancel()
        if !alreadyClosed { onClose?() }
    }

    private func pump() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil { self.cancel(); return }
            if let data, !data.isEmpty { self.buffer.append(data) }

            if let request = self.parseIfComplete() {
                self.dispatch(request)
            } else if self.buffer.count > self.maxRequestBytes {
                self.respondAndClose(.error(413, "Request too large"))
            } else if isComplete {
                self.cancel()
            } else {
                self.pump()
            }
        }
    }

    /// Returns a fully-parsed request, or nil if more bytes are still needed.
    private func parseIfComplete() -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else { return nil }

        let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if available < contentLength { return nil }   // wait for the rest of the body

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = buffer.subdata(in: bodyStart..<bodyEnd)

        // Split target into path + query.
        var path = target
        var query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            path = String(target[..<q])
            let queryString = String(target[target.index(after: q)...])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                let name = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let val = kv.count > 1 ? (String(kv[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "") : ""
                query[name] = val
            }
        }
        path = path.removingPercentEncoding ?? path

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    private func dispatch(_ request: HTTPRequest) {
        let handler = self.handler
        Task {
            let response = await handler(request)
            self.respondAndClose(response)
        }
    }

    private func respondAndClose(_ response: HTTPResponse) {
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/octet-stream"
        }

        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        var out = Data(head.utf8)
        out.append(response.body)
        connection.send(content: out, completion: .contentProcessed { [weak self] _ in
            self?.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default:  return "OK"
        }
    }
}
