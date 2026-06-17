import SwiftUI

/// Settings UI for outbound webhooks (6-F) plus a delivery-health view (6-E).
/// Lives in its own "Automation" tab so it doesn't disturb the existing
/// Connections tab. Reads/writes `WebhookService.shared`.
@available(macOS 14.0, *)
struct WebhookSettingsView: View {
    @ObservedObject private var service = WebhookService.shared
    @State private var newURL = ""
    @State private var newEvents = ""
    @State private var newSecret = ""

    private static let eventNames = ["meetingFinalized", "taskCreated", "decisionExtracted"]

    var body: some View {
        Form {
            Section("Outbound webhooks") {
                Text("Fire a signed POST to an external endpoint (Zapier, n8n, your own script) when something happens. Leave events empty to receive all. A secret adds an X-MeetingScribe-Signature HMAC-SHA256 header.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($service.configs) { $config in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("", isOn: $config.enabled).labelsHidden()
                            TextField("https://example.com/hook", text: $config.url)
                                .textFieldStyle(.roundedBorder)
                            Button("Test") { Task { await service.test(config) } }
                            Button(role: .destructive) {
                                service.configs.removeAll { $0.id == config.id }
                            } label: { Image(systemName: "trash") }
                        }
                        Text(config.events.isEmpty ? "All events" : config.events.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add a webhook").font(.caption.weight(.semibold))
                    TextField("Endpoint URL", text: $newURL).textFieldStyle(.roundedBorder)
                    TextField("Events (comma-separated, blank = all)", text: $newEvents).textFieldStyle(.roundedBorder)
                    TextField("Secret (optional)", text: $newSecret).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let url = newURL.trimmingCharacters(in: .whitespaces)
                        guard !url.isEmpty else { return }
                        let events = newEvents.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        service.configs.append(WebhookConfig(url: url, events: events, secret: newSecret))
                        newURL = ""; newEvents = ""; newSecret = ""
                    }
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Known events: " + Self.eventNames.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Section("Recent deliveries") {
                if service.deliveries.isEmpty {
                    Text("No deliveries yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(service.deliveries) { d in
                        HStack(spacing: 8) {
                            Image(systemName: d.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(d.ok ? .green : .orange)
                            Text(d.event).font(.caption.weight(.medium))
                            Text(d.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text("\(d.statusCode)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            Text(d.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
