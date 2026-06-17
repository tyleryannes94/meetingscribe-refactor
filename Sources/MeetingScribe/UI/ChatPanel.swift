import SwiftUI
import AppKit
import VaultKit

/// Reusable Chat surface. Same chat experience whether it's living
/// in the Today sidebar, inside a meeting's expanded detail, or in a
/// standalone view. Just the messages + input — folders / scheduled tasks
/// are owned by the host view.
@available(macOS 14.0, *)
struct ChatPanel: View {
    @ObservedObject var session: ChatSession
    /// Optional context to prepend to each user message. Used by the
    /// per-meeting Chat tab so the AI knows which call the user is
    /// asking about without having to mention it every time.
    var contextPrefix: String? = nil
    /// Visual density. `.compact` (sidebar / meeting detail) tightens
    /// padding and font sizes; `.regular` is the standalone view.
    var density: Density = .regular
    /// Optional placeholder examples shown when the chat is empty.
    var examplePrompts: [String]? = nil
    /// 5-F: optional categorized "What can I ask?" prompt groups, shown
    /// collapsibly in the empty state. Takes precedence over examplePrompts.
    var capabilitySections: [CapabilitySection]? = nil

    struct CapabilitySection: Identifiable {
        let id = UUID()
        let label: String
        let prompts: [String]
    }

    enum Density { case compact, regular }

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool
    /// P0-2: which capability groups are open. Only the first is seeded open so
    /// the empty state stays calm while prompts remain discoverable.
    @State private var expandedSections: Set<UUID> = []
    @State private var didSeedDisclosure = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: density == .compact ? 10 : 14) {
                        if session.messages.isEmpty {
                            emptyView
                        }
                        ForEach(Array(session.messages.enumerated()), id: \.offset) { _, msg in
                            ChatBubble(message: msg, density: density)
                        }
                        if session.isRunning {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, density == .compact ? 12 : 18)
                        }
                        if let err = session.lastError {
                            errorBanner(err)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, density == .compact ? 12 : 16)
                }
                .onChange(of: session.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            Divider()
            inputBar
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(NDS.brand)
                Text("Ask anything")
                    .font(density == .compact ? .callout.weight(.semibold)
                                              : .title3.weight(.semibold))
            }
            if let sections = capabilitySections {
                Text("What can I ask?")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedSections.contains(section.id) },
                        set: { isOpen in
                            if isOpen { expandedSections.insert(section.id) }
                            else { expandedSections.remove(section.id) }
                        })) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(section.prompts, id: \.self) { promptButton($0) }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text(section.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary).textCase(.uppercase)
                    }
                    .onAppear {
                        if idx == 0 && !didSeedDisclosure {
                            expandedSections.insert(section.id)
                            didSeedDisclosure = true
                        }
                    }
                }
            } else if let prompts = examplePrompts {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prompts, id: \.self) { promptButton($0) }
                }
            }
            Label("Running locally via Ollama. No API key, no outbound traffic.",
                  systemImage: "lock.shield")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, density == .compact ? 12 : 18)
    }

    /// A tappable suggested-prompt chip that drops the text into the input.
    private func promptButton(_ text: String) -> some View {
        Button {
            input = text
            inputFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.circle").font(.caption2)
                    .foregroundStyle(NDS.textTertiary)
                Text(text).font(.caption).multilineTextAlignment(.leading)
                    .foregroundStyle(NDS.textSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: NDS.radiusSmall)
                .strokeBorder(NDS.hairline, lineWidth: 0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(err).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, density == .compact ? 12 : 18)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // P2: context breadcrumb — shows what the assistant is scoped to
            // (a meeting / person) without a heavy header. The anchor persists
            // across top-level navigation; the trailing × lets the user clear
            // it without resetting the whole conversation.
            if !session.contextLabel.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "scope").scaledFont(10).foregroundStyle(NDS.textTertiary)
                    Text("About: \(session.contextLabel)")
                        .scaledFont(11).foregroundStyle(NDS.textSecondary).lineLimit(1)
                    Button { session.clearAnchor() } label: {
                        Image(systemName: "xmark")
                            .scaledFont(9, weight: .semibold)
                            .foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Unpin chat from \(session.contextLabel)")
                }
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(NDS.fieldBg, in: Capsule())
                .help("The assistant is grounded on \(session.contextLabel) — stays anchored as you navigate.")
            }
            inputRow
        }
        .padding(.horizontal, density == .compact ? 10 : 14)
        .padding(.vertical, density == .compact ? 8 : 10)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { submit() }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(NDS.fieldBg,
                            in: RoundedRectangle(cornerRadius: NDS.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: NDS.radiusSmall)
                    .strokeBorder(NDS.hairline, lineWidth: 0.5))
                .font(density == .compact ? .callout : .body)
            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: density == .compact ? 22 : 26))
                    .foregroundStyle(canSubmit ? NDS.brand
                                                : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.isRunning
    }

    private func submit() {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !session.isRunning else { return }
        let text: String
        if let ctx = contextPrefix, !ctx.isEmpty {
            text = "\(ctx)\n\nUser question: \(raw)"
        } else {
            text = raw
        }
        input = ""
        Task { await session.sendUserMessage(text) }
    }
}

// MARK: - Chat bubble

@available(macOS 14.0, *)
struct ChatBubble: View {
    let message: AnthropicClient.Message
    var density: ChatPanel.Density

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .user
                      ? "person.crop.circle.fill" : "sparkles")
                    .foregroundStyle(message.role == .user ? .blue : .purple)
                Text(message.role == .user ? "You" : "Chat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(.horizontal, density == .compact ? 12 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: AnthropicClient.ContentBlock) -> some View {
        switch block {
        case .text(let s):
            if let attr = try? AttributedString(markdown: s,
                                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attr).font(density == .compact ? .callout : .body)
                    .textSelection(.enabled)
            } else {
                Text(s).font(density == .compact ? .callout : .body).textSelection(.enabled)
            }
        case .toolUse(_, let name, let input):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "wrench.adjustable")
                    .foregroundStyle(.tertiary).font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("→ \(name)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    if !input.isEmpty && density == .regular {
                        Text(JSONValue.object(input).prettyJSON())
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(6)
                    }
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        case .toolResult(_, let content, let isError):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isError ? "exclamationmark.triangle" : "checkmark")
                    .foregroundStyle(isError ? .orange : .green).font(.caption)
                Text(String(content.prefix(density == .compact ? 300 : 800)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(density == .compact ? 4 : 8)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background((isError ? Color.orange : Color.green).opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
