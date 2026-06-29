import SwiftUI

/// Middle column of the Brain Dump page — every source attached to the active
/// session. Each card is collapsible (a long article markdown shouldn't
/// dominate the panel) and shows a rough token budget so the user can prune
/// before re-running the planner.
@available(macOS 14.0, *)
struct BrainDumpSourcePanel: View {
    @EnvironmentObject var store: BrainDumpStore
    let session: BrainDumpSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NDS.divider)
            if session.sources.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(NDS.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack.fill").scaledFont(13).foregroundStyle(NDS.brand)
            Text("Sources").scaledFont(13, weight: .semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            let total = session.sources.reduce(0) { $0 + $1.tokenEstimate }
            if total > 0 {
                Text("~\(total) tok")
                    .font(NDS.tiny.monospacedDigit())
                    .foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "link").scaledFont(18).foregroundStyle(NDS.textTertiary)
            Text("Paste URLs, run a search, or pull a Linear brief.")
                .font(NDS.small).foregroundStyle(NDS.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.sources) { source in
                    sourceCard(source)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func sourceCard(_ source: BrainDumpSource) -> some View {
        switch source {
        case .url(let s):         urlCard(s)
        case .search(let s):      searchCard(s)
        case .linearBrief(let s): linearCard(s)
        case .slackBrief(let s):  slackCard(s)
        }
    }

    // MARK: - URL

    private func urlCard(_ s: URLSource) -> some View {
        DisclosureCard(
            kind: "Link",
            title: s.title,
            subtitle: s.url.host ?? s.url.absoluteString,
            tokens: max(1, s.extractedMarkdown.count / 4),
            isLoading: s.isLoading,
            error: s.error,
            onRemove: { store.removeSource(session.id, sourceID: s.id) }
        ) {
            if !s.extractedMarkdown.isEmpty {
                Text(s.extractedMarkdown)
                    .font(NDS.small).foregroundStyle(NDS.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let err = s.error {
                Text(err).font(NDS.small).foregroundStyle(NDS.selectColor("red"))
            } else {
                Text("Fetching…").font(NDS.small).foregroundStyle(NDS.textTertiary)
            }
        }
    }

    // MARK: - Search

    private func searchCard(_ s: SearchSource) -> some View {
        DisclosureCard(
            kind: "Search (\(s.provider))",
            title: s.query,
            subtitle: "\(s.results.count) results",
            tokens: s.results.reduce(0) { $0 + max(1, $1.snippet.count / 4) },
            isLoading: false,
            error: nil,
            onRemove: { store.removeSource(session.id, sourceID: s.id) }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let summary = s.summary, !summary.isEmpty {
                    Text(summary)
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(NDS.divider)
                }
                ForEach(s.results, id: \.url) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Link(r.title, destination: r.url)
                            .font(NDS.small.weight(.semibold))
                        Text(r.snippet)
                            .font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    // MARK: - Linear

    private func linearCard(_ s: LinearBriefSource) -> some View {
        DisclosureCard(
            kind: "Linear",
            title: "\(s.issues.count) assigned issue\(s.issues.count == 1 ? "" : "s")",
            subtitle: Self.relativeDate(s.fetchedAt),
            tokens: s.issues.count * 12,
            isLoading: false,
            error: nil,
            onRemove: { store.removeSource(session.id, sourceID: s.id) }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(s.issues, id: \.identifier) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Text(issue.identifier)
                            .font(NDS.tiny.monospaced())
                            .foregroundStyle(NDS.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            if let url = issue.url {
                                Link(issue.title, destination: url).font(NDS.small)
                            } else {
                                Text(issue.title).font(NDS.small)
                            }
                            if issue.state != nil || issue.dueDate != nil {
                                HStack(spacing: 6) {
                                    if let state = issue.state {
                                        Text(state).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                    }
                                    if let due = issue.dueDate {
                                        Text("Due \(Self.shortDate(due))")
                                            .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                if s.issues.isEmpty {
                    Text("No open issues assigned to you.")
                        .font(NDS.small).foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }

    // MARK: - Slack

    private func slackCard(_ s: SlackBriefStub) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .scaledFont(14).foregroundStyle(NDS.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Slack daily brief").font(NDS.small.weight(.semibold))
                    .foregroundStyle(NDS.textTertiary)
                Text(s.note).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            Spacer()
            Button { store.removeSource(session.id, sourceID: s.id) } label: {
                Image(systemName: "xmark").scaledFont(10).foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(NDS.fieldBg.opacity(0.5), in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.hairline, lineWidth: 0.5))
    }

    // MARK: - Helpers

    private static func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        return f.localizedString(for: d, relativeTo: Date())
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: - DisclosureCard

@available(macOS 14.0, *)
private struct DisclosureCard<Content: View>: View {
    let kind: String
    let title: String
    let subtitle: String
    let tokens: Int
    let isLoading: Bool
    let error: String?
    let onRemove: () -> Void
    @ViewBuilder let content: Content

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .scaledFont(10).foregroundStyle(NDS.textTertiary)
                Text(kind).font(NDS.tiny.weight(.bold)).foregroundStyle(NDS.brand)
                    .textCase(.uppercase).tracking(0.6)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.mini) // design-lint:allow
                } else {
                    Text("~\(tokens) tok")
                        .font(NDS.tiny.monospacedDigit())
                        .foregroundStyle(NDS.textTertiary)
                }
                Button { onRemove() } label: {
                    Image(systemName: "xmark").scaledFont(10).foregroundStyle(NDS.textTertiary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NDS.small.weight(.semibold))
                    .lineLimit(1).truncationMode(.tail)
                Text(subtitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.top, 6)

            if let error {
                Text(error).font(NDS.tiny).foregroundStyle(NDS.selectColor("red"))
                    .padding(.top, 6)
            }

            if expanded {
                Divider().overlay(NDS.divider).padding(.vertical, 8)
                content
            }
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.hairline, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } }
    }
}
