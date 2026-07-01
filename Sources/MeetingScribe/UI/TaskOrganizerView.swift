import SwiftUI

/// Review sheet for "Organize my Tasks". Runs the AI pass, then lists each
/// proposed fix with one-click Apply / Dismiss — nothing is changed until the
/// user signs off. "Apply all" applies every still-pending suggestion.
@available(macOS 14.0, *)
struct TaskOrganizerView: View {
    @ObservedObject var organizer: TaskOrganizer
    @ObservedObject var store: ActionItemStore
    let onClose: () -> Void

    private var pending: [TaskSuggestion] { organizer.suggestions.filter { !$0.applied && !$0.dismissed } }

    /// "8 suggestions: 3 dates · 2 priorities · 2 projects · 1 split" — a
    /// scannable summary header (research: users trust a typed breakdown far more
    /// than "we changed 8 things").
    private var summaryLine: String {
        let p = pending
        guard !p.isEmpty else { return "" }
        func count(_ pred: (TaskSuggestion.Kind) -> Bool) -> Int { p.filter { pred($0.kind) }.count }
        let dates = count { if case .reschedule = $0 { return true }; return false }
        let pris  = count { if case .reprioritize = $0 { return true }; return false }
        let projs = count { if case .assignProject = $0 { return true }; if case .setProjectDeadline = $0 { return true }; return false }
        let tags  = count { if case .addTag = $0 { return true }; return false }
        let splits = count { if case .split = $0 { return true }; return false }
        var parts: [String] = []
        if dates > 0 { parts.append("\(dates) date\(dates == 1 ? "" : "s")") }
        if pris > 0 { parts.append("\(pris) priorit\(pris == 1 ? "y" : "ies")") }
        if projs > 0 { parts.append("\(projs) project\(projs == 1 ? "" : "s")") }
        if tags > 0 { parts.append("\(tags) tag\(tags == 1 ? "" : "s")") }
        if splits > 0 { parts.append("\(splits) split\(splits == 1 ? "" : "s")") }
        return "\(p.count) suggestion\(p.count == 1 ? "" : "s"): " + parts.joined(separator: " · ")
    }

    /// Suggestions grouped into ordered, titled categories for the review list.
    private var groupedSuggestions: [(String, [TaskSuggestion])] {
        func cat(_ k: TaskSuggestion.Kind) -> String {
            switch k {
            case .reschedule:         return "Due dates"
            case .reprioritize:       return "Priorities"
            case .assignProject, .setProjectDeadline: return "Projects"
            case .addTag:             return "Tags"
            case .split:              return "Split up"
            }
        }
        let order = ["Due dates", "Priorities", "Projects", "Tags", "Split up"]
        var buckets: [String: [TaskSuggestion]] = [:]
        for s in organizer.suggestions { buckets[cat(s.kind), default: []].append(s) }
        return order.compactMap { key in
            guard let items = buckets[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NDS.divider)
            content
            if !organizer.suggestions.isEmpty { footer }
        }
        .frame(width: 560, height: 620)
        .background(NDS.bg)
        .onAppear { if !organizer.didRun && !organizer.isRunning { organizer.run(store: store) } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars").foregroundStyle(NDS.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text("Organize my Tasks").scaledFont(16, weight: .bold)
                Text("AI suggestions — review and apply each. Nothing changes until you do.")
                    .font(NDS.tiny).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            Button { onClose() } label: { Image(systemName: "xmark").foregroundStyle(NDS.textSecondary) }
                .buttonStyle(.plain)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        // Show results the moment the instant pass produces them — never block
        // the whole sheet on the (optional, background) model phase.
        if !organizer.suggestions.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if organizer.refining { refiningBanner }
                    if !summaryLine.isEmpty {
                        Text(summaryLine).font(NDS.small.weight(.semibold)).foregroundStyle(NDS.textSecondary)
                    }
                    if let reasoning = organizer.reasoning, !reasoning.isEmpty {
                        Text(reasoning).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .padding(.bottom, 2)
                    }
                    // Grouped by category so the review reads as "3 dates, 2
                    // priorities, …" rather than one undifferentiated blob.
                    ForEach(groupedSuggestions, id: \.0) { group in
                        Text(group.0.uppercased())
                            .font(NDS.tiny.weight(.bold)).foregroundStyle(NDS.textTertiary)
                            .padding(.top, 4)
                        ForEach(group.1) { s in suggestionCard(s) }
                    }
                }
                .padding(14)
            }
        } else if organizer.isRunning {
            // Only reached when the instant pass found nothing and the model is
            // still looking — brief, and rare.
            VStack(spacing: 10) {
                ProgressView().controlSize(.small) // design-lint:allow
                Text("Looking for things to tidy up…").font(NDS.small).foregroundStyle(NDS.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = organizer.error {
            errorState(err)
        } else {
            emptyState
        }
    }

    /// Slim inline hint shown above the instant results while the model is still
    /// looking for groups/tags in the background.
    private var refiningBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small) // design-lint:allow
            Text("Looking for projects & tags to group loose tasks…")
                .font(NDS.tiny).foregroundStyle(NDS.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
    }

    private func suggestionCard(_ s: TaskSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: glyph(s.kind)).scaledFont(14).foregroundStyle(NDS.brand)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(s)).font(NDS.small.weight(.semibold))
                        .foregroundStyle(s.applied ? NDS.textTertiary : NDS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !s.reason.isEmpty {
                        Text(s.reason).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if s.applied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(NDS.tiny).foregroundStyle(NDS.selectColor("green")).labelStyle(.titleAndIcon)
                } else if s.dismissed {
                    Text("Dismissed").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                } else {
                    HStack(spacing: 6) {
                        Button { organizer.apply(s, store: store) } label: { Text("Apply") }
                            .buttonStyle(MSPrimaryButtonStyle())
                            .disabled(s.activeTaskIDs.isEmpty)
                        Button { organizer.dismiss(s) } label: { Text("Dismiss").font(NDS.tiny) }
                            .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
                    }
                }
            }
            // Multi-task recommendations: list each affected task with a checkbox
            // so the user can uncheck the ones that don't fit before applying.
            if !s.applied && !s.dismissed && s.taskList.count > 1 {
                taskChecklist(s)
            }
        }
        .padding(10)
        .background(s.applied ? NDS.brand.opacity(0.05) : NDS.fieldBg,
                    in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.hairline, lineWidth: 0.5))
        .opacity(s.dismissed ? 0.5 : 1)
    }

    private var footer: some View {
        HStack {
            Text("\(pending.count) pending · \(organizer.suggestions.filter { $0.applied }.count) applied")
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            Spacer()
            Button("Done") { onClose() }.buttonStyle(MSSecondaryButtonStyle())
            Button { organizer.applyAll(store: store) } label: {
                Label("Apply all", systemImage: "checkmark.circle")
            }
            .buttonStyle(MSPrimaryButtonStyle())
            .disabled(pending.isEmpty)
        }
        .padding(14)
        .background(NDS.fieldBg.opacity(0.4))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").scaledFont(34).foregroundStyle(NDS.selectColor("green"))
            Text("Your tasks look well-organized").scaledFont(15, weight: .semibold)
            Text("Nothing to fix right now — no overdue, mis-prioritized, or loose tasks stood out.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary).multilineTextAlignment(.center)
            Button("Re-analyze") { organizer.run(store: store) }.buttonStyle(MSSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }

    private func errorState(_ err: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").scaledFont(28).foregroundStyle(NDS.selectColor("red"))
            Text("Couldn't analyze tasks").scaledFont(15, weight: .semibold)
            Text(err).font(NDS.tiny).foregroundStyle(NDS.textSecondary).multilineTextAlignment(.center)
            Button("Retry") { organizer.run(store: store) }.buttonStyle(MSSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }

    // MARK: - Suggestion presentation

    /// The checkable list of tasks a multi-task recommendation will touch.
    private func taskChecklist(_ s: TaskSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(s.taskList, id: \.id) { t in
                let checked = !s.deselectedTaskIDs.contains(t.id)
                Button { organizer.toggleTask(t.id, in: s) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .scaledFont(13)
                            .foregroundStyle(checked ? NDS.brand : NDS.textTertiary)
                        Text(t.title)
                            .font(NDS.tiny)
                            .foregroundStyle(checked ? NDS.textSecondary : NDS.textTertiary)
                            .strikethrough(!checked)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.leading, 28)
    }

    private func glyph(_ kind: TaskSuggestion.Kind) -> String {
        switch kind {
        case .reschedule:    return "calendar.badge.clock"
        case .reprioritize:  return "flag.fill"
        case .assignProject: return "folder.fill"
        case .addTag:        return "tag.fill"
        case .split:         return "scissors"
        case .setProjectDeadline: return "flag.checkered"
        }
    }

    private func title(_ s: TaskSuggestion) -> String {
        // Multi-task kinds reflect the live checked count so the header tracks
        // the user's selections in the checklist below.
        let n = s.activeTaskIDs.count
        switch s.kind {
        case let .reschedule(id, t, d):
            // Show a before→after diff so the change is scannable: a dateless
            // task reads "no date → Fri", an overdue one "overdue Mon → Fri".
            let cur = store.items.first { $0.id == id }?.dueDate
            let from: String = {
                guard let cur else { return "no date" }
                let overdue = Calendar.current.startOfDay(for: cur) < Calendar.current.startOfDay(for: Date())
                return (overdue ? "overdue " : "") + Self.dateLabel(cur)
            }()
            return "“\(t)” — \(from) → \(Self.dateLabel(d))"
        case let .reprioritize(id, t, p):
            let cur = store.items.first { $0.id == id }?.priority
            let from = cur?.label ?? "—"
            return "“\(t)” priority — \(from) → \(p.label)"
        case let .setProjectDeadline(_, name, d):
            return "Give “\(name)” a deadline → \(Self.dateLabel(d))"
        case let .assignProject(_, titles, name, existing):
            if titles.count == 1, let only = titles.first {
                let verb = existing == nil ? "Create project “\(name)” and move" : "Move to “\(name)”"
                return "\(verb) “\(only)”"
            }
            let verb = existing == nil ? "Create project “\(name)” and move" : "Move to “\(name)”"
            return "\(verb) \(n) task\(n == 1 ? "" : "s")"
        case let .addTag(_, titles, tag):
            if titles.count == 1, let only = titles.first {
                return "Tag “\(only)” with #\(tag)"
            }
            return "Tag \(n) task\(n == 1 ? "" : "s") with #\(tag)"
        case let .split(_, t, parts):
            return "Split “\(t)” into \(parts.count) subtasks"
        }
    }

    private static func dateLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "today" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }
}
