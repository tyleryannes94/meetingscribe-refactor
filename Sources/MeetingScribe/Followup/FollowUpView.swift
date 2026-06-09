import SwiftUI
import AppKit

/// Generates and displays a follow-up draft for a meeting. Pick a channel,
/// generate via Ollama, then copy or share the result.
///
/// Decoupled from the app's models on purpose — callers pass plain strings
/// (title, summary, action-item titles) so this view can be hosted anywhere.
@available(macOS 14.0, *)
struct FollowUpView: View {
    let meetingTitle: String
    let summary: String
    let actionItems: [String]
    /// Email addresses to prefill the "To:" line when opening in Mail.
    var recipients: [String] = []
    /// When set, enables follow-up sent-state tracking (P2-6).
    var meetingID: String? = nil
    @State private var markedSent = false

    @State private var channel: FollowUpSuggestion.Channel = .email
    @State private var suggestion: FollowUpSuggestion?
    @State private var isGenerating = false
    @State private var errorText: String?
    @State private var copied = false

    private let generator = FollowUpGeneratorService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let err = errorText { errorBanner(err) }
                if let s = suggestion { draft(s) }
                else if !isGenerating { emptyHint }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if let id = meetingID { markedSent = FollowUpStatus.isSent(id) } }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $channel) {
                ForEach(FollowUpSuggestion.Channel.allCases) { c in
                    Label(c.label, systemImage: c.systemImage).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .onChange(of: channel) { _, _ in suggestion = nil }

            Button {
                generate()
            } label: {
                if isGenerating {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Drafting…") }
                } else {
                    Label(suggestion == nil ? "Draft follow-up" : "Regenerate",
                          systemImage: "sparkles")
                }
            }
            .disabled(isGenerating)
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var emptyHint: some View {
        Text("Generate an \(channel.label.lowercased()) recap from this meeting's summary and action items.")
            .font(.callout).foregroundStyle(.secondary)
    }

    private func draft(_ s: FollowUpSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let subject = s.subject, !subject.isEmpty {
                Text("Subject").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(subject).font(.callout.weight(.medium)).textSelection(.enabled)
            }
            Text(s.body)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
            HStack(spacing: 8) {
                Button {
                    copy(s.plainText)
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                if channel == .email {
                    Button {
                        openInMail(subject: s.subject ?? "Follow-up: \(meetingTitle)", body: s.body)
                    } label: { Label("Open in Mail", systemImage: "envelope") }
                }
                ShareLink(item: s.plainText) { Label("Share", systemImage: "square.and.arrow.up") }
                Spacer()
                if let id = meetingID {
                    // Track sent-state so Today stops resurfacing it. (P2-6)
                    Button {
                        FollowUpStatus.setSent(id, !markedSent)
                        markedSent.toggle()
                    } label: {
                        Label(markedSent ? "Sent ✓" : "Mark as sent",
                              systemImage: markedSent ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .tint(markedSent ? .green : nil)
                }
            }
            .controlSize(.small)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func generate() {
        isGenerating = true
        errorText = nil
        copied = false
        let channel = channel
        Task {
            do {
                let result = try await generator.generate(
                    channel: channel,
                    meetingTitle: meetingTitle,
                    summary: summary,
                    actionItems: actionItems)
                suggestion = result
            } catch {
                errorText = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    /// Open the default mail client with a pre-composed draft (recipients +
    /// subject + body prefilled). "Send the follow-up, don't just copy it."
    private func openInMail(subject: String, body: String) {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = recipients.joined(separator: ",")
        comps.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        // mailto requires %20 (not '+') for spaces in the query.
        if let url = comps.url ?? URL(string: "mailto:") {
            NSWorkspace.shared.open(url)
        }
    }
}
