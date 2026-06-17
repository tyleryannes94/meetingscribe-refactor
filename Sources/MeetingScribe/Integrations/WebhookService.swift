import Foundation
import CryptoKit
import OSLog

/// A user-configured outbound webhook (6-F). Fires a signed POST when a chosen
/// event happens, so external automation (Zapier, n8n, a personal script) can
/// react without an MCP client.
struct WebhookConfig: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var url: String
    /// Event kinds this endpoint wants: "meetingFinalized", "taskCreated",
    /// "decisionExtracted". Empty ⇒ all.
    var events: [String] = []
    /// Optional shared secret — when set, payloads carry an HMAC-SHA256 signature
    /// in the `X-MeetingScribe-Signature` header.
    var secret: String = ""
    var enabled: Bool = true
}

/// A record of one delivery attempt, shown in the webhook settings log.
struct WebhookDelivery: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var date: Date
    var event: String
    var url: String
    var statusCode: Int
    var ok: Bool
}

/// Outbound webhook dispatcher (6-F / audit PM4-6, C5-1). Subscribes to the
/// `SecondBrainEventBus` and POSTs a JSON payload (+ HMAC signature) to each
/// matching endpoint, retrying with exponential backoff. The first integration
/// that turns the typed event bus into an external extension point.
@available(macOS 14.0, *)
@MainActor
final class WebhookService: ObservableObject {
    static let shared = WebhookService()
    private init() { load() }

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Webhooks")
    private var started = false
    private var task: Task<Void, Never>?

    @Published var configs: [WebhookConfig] = [] { didSet { save() } }
    @Published private(set) var deliveries: [WebhookDelivery] = []

    private var configURL: URL { AppSettings.shared.storageDir.appendingPathComponent("webhooks.json") }

    func start() {
        guard !started else { return }
        started = true
        task = Task { [weak self] in
            for await event in SecondBrainEventBus.shared.subscribe() {
                guard let self else { break }
                await self.dispatch(event)
            }
        }
    }

    // MARK: - Dispatch

    private func dispatch(_ event: SecondBrainEvent) async {
        guard let (name, payload) = Self.encode(event) else { return }
        for config in configs where config.enabled
            && (config.events.isEmpty || config.events.contains(name)) {
            await deliver(name: name, payload: payload, to: config)
        }
    }

    private func deliver(name: String, payload: [String: Any], to config: WebhookConfig) async {
        guard let url = URL(string: config.url), let body = try? JSONSerialization.data(
            withJSONObject: ["event": name, "data": payload], options: [.sortedKeys]) else { return }

        var lastStatus = -1
        for attempt in 0..<3 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(name, forHTTPHeaderField: "X-MeetingScribe-Event")
            if !config.secret.isEmpty {
                let sig = Self.sign(body, secret: config.secret)
                req.setValue(sig, forHTTPHeaderField: "X-MeetingScribe-Signature")
            }
            req.httpBody = body
            req.timeoutInterval = 15
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                lastStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
                if (200..<300).contains(lastStatus) {
                    recordDelivery(name: name, url: config.url, status: lastStatus, ok: true)
                    return
                }
            } catch {
                lastStatus = -1
            }
            // Exponential backoff: 1s, 2s.
            if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(1 << attempt) * 1_000_000_000) }
        }
        recordDelivery(name: name, url: config.url, status: lastStatus, ok: false)
        log.error("Webhook delivery to \(config.url, privacy: .public) failed (\(lastStatus))")
    }

    private func recordDelivery(name: String, url: String, status: Int, ok: Bool) {
        deliveries.insert(WebhookDelivery(date: Date(), event: name, url: url, statusCode: status, ok: ok), at: 0)
        if deliveries.count > 20 { deliveries.removeLast(deliveries.count - 20) }
    }

    /// "Test connection" — fire a synthetic ping to one endpoint.
    func test(_ config: WebhookConfig) async {
        await deliver(name: "ping", payload: ["message": "MeetingScribe webhook test"], to: config)
    }

    // MARK: - Payload encoding

    private static func encode(_ event: SecondBrainEvent) -> (String, [String: Any])? {
        switch event {
        case let .meetingFinalized(meetingID, attendees):
            return ("meetingFinalized", ["meetingID": meetingID, "attendees": attendees])
        case let .taskCreated(task):
            return ("taskCreated", ["taskID": task.id, "title": task.title,
                                    "ownerPersonID": task.ownerPersonID ?? "",
                                    "dueDate": task.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""])
        case let .decisionExtracted(decision, meetingID):
            return ("decisionExtracted", ["decisionID": decision.id, "text": decision.text,
                                          "rationale": decision.rationale ?? "",
                                          "personIDs": decision.personIDs, "meetingID": meetingID])
        default:
            return nil   // taskUpdated / encounterLogged / personUpdated / insightAvailable not exported by default
        }
    }

    private static func sign(_ body: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode([WebhookConfig].self, from: data) else { return }
        configs = decoded
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
