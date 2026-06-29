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
                    if let reasoning = organizer.reasoning, !reasoning.isEmpty {
                        Text(reasoning).font(NDS.small).foregroundStyle(NDS.textSecondary)
                            .padding(.bottom, 2)
                    }
                    ForEach(organizer.suggestions) { s in suggestionCard(s) }
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: glyph(s.kind)).scaledFont(14).foregroundStyle(NDS.brand)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(s.kind)).font(NDS.small.weight(.semibold))
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
                    Button { organizer.dismiss(s) } label: { Text("Dismiss").font(NDS.tiny) }
                        .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
                }
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

    private func glyph(_ kind: TaskSuggestion.Kind) -> String {
        switch kind {
        case .reschedule:    return "calendar.badge.clock"
        case .reprioritize:  return "flag.fill"
        case .assignProject: return "folder.fill"
        case .addTag:        return "tag.fill"
        case .split:         return "scissors"
        }
    }

    private func title(_ kind: TaskSuggestion.Kind) -> String {
        switch kind {
        case let .reschedule(id, t, d):
            // A task that has no due date yet gets "Set due"; one that already
            // has a (likely overdue) date gets "Reschedule".
            let hadDue = store.items.first { $0.id == id }?.dueDate != nil
            let verb = hadDue ? "Reschedule" : "Set due date for"
            return "\(verb) “\(t)” → \(Self.dateLabel(d))"
        case let .reprioritize(_, t, p):
            return "Set “\(t)” to \(p.label) priority"
        case let .assignProject(ids, _, name, existing):
            let verb = existing == nil ? "Create project “\(name)” and move" : "Move to “\(name)”"
            return "\(verb) \(ids.count) task\(ids.count == 1 ? "" : "s")"
        case let .addTag(ids, _, tag):
            return "Tag \(ids.count) task\(ids.count == 1 ? "" : "s") with #\(tag)"
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
