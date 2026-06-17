import SwiftUI

/// The scheduled weekly-review ritual (3-F): a native closure surface that
/// replaces the old markdown export. Shows this week vs. last week at a glance,
/// the decisions made, and an Ollama-narrated reflection — turning the weekly
/// review from a passive export into a Friday-afternoon habit.
@available(macOS 14.0, *)
struct WeeklyReviewView: View {
    @EnvironmentObject var manager: MeetingManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = WeeklyReviewVM()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Your week in review", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider().overlay(NDS.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let m = metrics
                    statRow("Meetings", this: m.meetingsThis, prior: m.meetingsPrior)
                    statRow("Tasks created", this: m.tasksCreated, prior: m.tasksCreatedPrior)
                    statRow("Tasks completed", this: m.tasksCompleted, prior: m.tasksCompletedPrior)
                    statRow("Decisions made", this: m.decisions, prior: m.decisionsPrior)

                    if !m.recentDecisions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            NotionEyebrow(text: "Key decisions")
                            ForEach(m.recentDecisions.prefix(6), id: \.id) { d in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "circle.fill").scaledFont(5)
                                        .foregroundStyle(NDS.brand).padding(.top, 6)
                                    Text(d.text).scaledFont(12).foregroundStyle(NDS.textPrimary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        NotionEyebrow(text: "Reflection")
                        if vm.reflection.isEmpty && vm.generating {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Synthesizing…").font(NDS.small) }
                        } else {
                            Text(vm.reflection.isEmpty ? "—" : vm.reflection)
                                .font(NDS.body).foregroundStyle(NDS.textPrimary).textSelection(.enabled)
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 540, minHeight: 640)
        .onAppear { vm.generate(summary: metrics.promptSummary) }
    }

    private func statRow(_ label: String, this: Int, prior: Int) -> some View {
        let delta = this - prior
        return HStack {
            Text(label).font(NDS.body).foregroundStyle(NDS.textSecondary)
            Spacer()
            Text("\(this)").font(NDS.body.weight(.semibold)).foregroundStyle(NDS.textPrimary)
            if delta != 0 {
                Text(delta > 0 ? "▲\(delta)" : "▼\(-delta)")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(delta > 0 ? NDS.brand : NDS.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var metrics: WeeklyMetrics { WeeklyMetrics(manager: manager) }
}

/// Pure metric computation for the weekly review.
@available(macOS 14.0, *)
struct WeeklyMetrics {
    let meetingsThis: Int, meetingsPrior: Int
    let tasksCreated: Int, tasksCreatedPrior: Int
    let tasksCompleted: Int, tasksCompletedPrior: Int
    let decisions: Int, decisionsPrior: Int
    let recentDecisions: [Decision]

    @MainActor init(manager: MeetingManager) {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        func inThis(_ d: Date) -> Bool { d >= weekAgo && d <= now }
        func inPrior(_ d: Date) -> Bool { d >= twoWeeksAgo && d < weekAgo }

        let meetings = manager.pastMeetings
        meetingsThis = meetings.filter { inThis($0.startDate) }.count
        meetingsPrior = meetings.filter { inPrior($0.startDate) }.count

        let items = manager.actionItems.items + manager.actionItems.trashedItems
        tasksCreated = items.filter { inThis($0.createdAt) }.count
        tasksCreatedPrior = items.filter { inPrior($0.createdAt) }.count
        tasksCompleted = items.filter { ($0.completedAt).map(inThis) ?? false }.count
        tasksCompletedPrior = items.filter { ($0.completedAt).map(inPrior) ?? false }.count

        let decs = manager.decisions.decisions
        decisions = decs.filter { inThis($0.date) }.count
        decisionsPrior = decs.filter { inPrior($0.date) }.count
        recentDecisions = decs.filter { inThis($0.date) }
    }

    var promptSummary: String {
        """
        Meetings this week: \(meetingsThis) (last week \(meetingsPrior)).
        Tasks created: \(tasksCreated), completed: \(tasksCompleted).
        Decisions made: \(decisions).
        Key decisions: \(recentDecisions.prefix(5).map(\.text).joined(separator: "; "))
        """
    }
}

@available(macOS 14.0, *)
@MainActor
final class WeeklyReviewVM: ObservableObject {
    @Published var reflection = ""
    @Published var generating = false
    private var task: Task<Void, Never>?

    func generate(summary: String) {
        task?.cancel()
        reflection = ""; generating = true
        let prompt = """
        Here is a summary of someone's work week. Synthesize the highlights in \
        three encouraging, specific sentences — what got done, what moved, and one \
        thing to carry into next week. Plain prose, no headings.

        \(summary)
        """
        task = Task { [weak self] in
            do {
                _ = try await OllamaService().streamGenerate(prompt: prompt, temperature: 0.4) { piece in
                    Task { @MainActor in self?.reflection += piece }
                }
            } catch { /* leave reflection empty on failure */ }
            await MainActor.run { self?.generating = false }
        }
    }
}
