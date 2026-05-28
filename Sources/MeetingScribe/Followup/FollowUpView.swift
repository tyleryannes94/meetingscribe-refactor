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
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                Button {
                    copy(s.plainText)
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                ShareLink(item: s.plainText) { Label("Share", systemImage: "square.and.arrow.up") }
                Spacer()
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
}
