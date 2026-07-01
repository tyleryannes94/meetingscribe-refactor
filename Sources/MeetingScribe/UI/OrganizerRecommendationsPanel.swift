import SwiftUI

/// The "Organize my Tasks" AI recommendations, surfaced INSIDE the Brain Dump
/// page (not just the one-off modal) so they persist and are reviewable in the
/// recommendations hub. Backed by the shared, disk-persisted `TaskOrganizer`, so
/// results survive closing the modal and app restarts.
@available(macOS 14.0, *)
struct OrganizerRecommendationsPanel: View {
    @ObservedObject var organizer: TaskOrganizer
    @ObservedObject var store: ActionItemStore
    /// When embedded as a section inside the Brain Dump review, render just the
    /// cards — no header, background, or empty-state chrome (the host provides a
    /// section title + count, so a second header would just be noise).
    var embedded: Bool = false

    private var pending: [TaskSuggestion] { organizer.suggestions.filter { !$0.applied && !$0.dismissed } }

    var body: some View {
        if embedded {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pending) { s in card(s) }
            }
        } else {
            fullPanel
        }
    }

    private var fullPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if organizer.refining {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)  // design-lint:allow
                    Text("Reviewing your tasks…").font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                }
            }
            if pending.isEmpty && !organizer.refining {
                Text(organizer.didRun
                     ? "No task tune-ups right now."
                     : "Run “Organize” to get due-date, priority, and project suggestions for your existing tasks.")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(pending) { s in card(s) }
            }
        }
        .padding(12)
        .background(NDS.fieldBg.opacity(0.5), in: RoundedRectangle(cornerRadius: NDS.cardRadius))
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "wand.and.stars").foregroundStyle(NDS.brand)
            Text("Task tune-ups").scaledFont(13, weight: .bold)
            if !pending.isEmpty {
                Text("\(pending.count)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
            }
            Spacer()
            Button {
                organizer.run(store: store)
            } label: {
                Label(organizer.isRunning ? "Organizing…" : "Organize",
                      systemImage: organizer.isRunning ? "hourglass" : "sparkles")
                    .font(NDS.tiny)
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .disabled(organizer.isRunning)
            if !pending.isEmpty {
                Button { organizer.applyAll(store: store) } label: {
                    Label("Apply all", systemImage: "checkmark.circle").font(NDS.tiny)
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }
        }
    }

    private func card(_ s: TaskSuggestion) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: glyph(s.kind)).scaledFont(12).foregroundStyle(NDS.brand).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(s)).font(NDS.tiny.weight(.semibold)).foregroundStyle(NDS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !s.reason.isEmpty {
                    Text(s.reason).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Button("Apply") { organizer.apply(s, store: store) }
                .buttonStyle(MSPrimaryButtonStyle()).controlSize(.small)
                .disabled(s.activeTaskIDs.isEmpty)
            Button { organizer.dismiss(s) } label: {
                Image(systemName: "xmark").scaledFont(10).foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(NDS.bg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.hairline, lineWidth: 0.5))
    }

    private func glyph(_ k: TaskSuggestion.Kind) -> String {
        switch k {
        case .reschedule:         return "calendar.badge.clock"
        case .reprioritize:       return "flag.fill"
        case .assignProject:      return "folder.fill"
        case .addTag:             return "tag.fill"
        case .split:              return "scissors"
        case .setProjectDeadline: return "flag.checkered"
        }
    }

    private func title(_ s: TaskSuggestion) -> String {
        switch s.kind {
        case let .reschedule(id, t, d):
            let cur = store.items.first { $0.id == id }?.dueDate
            let from = cur == nil ? "no date" : Self.day(cur!)
            return "“\(t)” — \(from) → \(Self.day(d))"
        case let .reprioritize(id, t, p):
            let cur = store.items.first { $0.id == id }?.priority.label ?? "—"
            return "“\(t)” priority — \(cur) → \(p.label)"
        case let .assignProject(_, titles, name, _):
            return titles.count == 1 ? "Move “\(titles[0])” to “\(name)”"
                                     : "Move \(s.activeTaskIDs.count) tasks to “\(name)”"
        case let .addTag(_, titles, tag):
            return titles.count == 1 ? "Tag “\(titles[0])” #\(tag)" : "Tag \(s.activeTaskIDs.count) tasks #\(tag)"
        case let .split(_, t, parts):
            return "Split “\(t)” into \(parts.count) subtasks"
        case let .setProjectDeadline(_, name, d):
            return "Give “\(name)” a deadline → \(Self.day(d))"
        }
    }

    private static func day(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "today" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: d)
    }
}
