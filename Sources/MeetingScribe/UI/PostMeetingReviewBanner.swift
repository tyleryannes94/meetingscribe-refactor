import SwiftUI

/// Post-meeting review mode (3-E): a time-sensitive checklist that appears atop a
/// meeting for 24h after it ends — the human-in-the-loop complement to the
/// automated post-meeting pipeline (3-A). Auto-collapses once every item is
/// checked or the 24h window passes. State persists per meeting in UserDefaults.
@available(macOS 14.0, *)
struct PostMeetingReviewBanner: View {
    let meeting: Meeting
    let actionItemCount: Int
    let decisionCount: Int
    var onReviewTasks: () -> Void = {}

    @State private var checks: Set<String> = []
    @State private var expanded = true

    private var inWindow: Bool { Date().timeIntervalSince(meeting.endDate) < 86_400 }

    private var items: [(key: String, label: String, action: (() -> Void)?)] {
        [("tasks", "Review action items (\(actionItemCount))", onReviewTasks),
         ("decisions", "Link decisions to people (\(decisionCount))", nil),
         ("followup", "Schedule a follow-up", nil),
         ("export", "Export to Notion", nil)]
    }
    private var allDone: Bool { items.allSatisfy { checks.contains($0.key) } }

    var body: some View {
        if inWindow && !allDone {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist").foregroundStyle(NDS.gold)
                        Text("Review this meeting").scaledFont(13, weight: .semibold)
                            .foregroundStyle(NDS.textPrimary)
                        Text("\(checks.count)/\(items.count)")
                            .scaledFont(11).foregroundStyle(NDS.textTertiary)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .scaledFont(11).foregroundStyle(NDS.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(items, id: \.key) { item in
                        Button {
                            toggle(item.key); item.action?()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: checks.contains(item.key) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checks.contains(item.key) ? NDS.brand : NDS.textTertiary)
                                Text(item.label).scaledFont(12)
                                    .foregroundStyle(NDS.textSecondary)
                                    .strikethrough(checks.contains(item.key))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(NDS.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: NDS.rowRadius))
            .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.gold.opacity(0.25), lineWidth: 1))
            .padding(.horizontal, 12).padding(.top, 8)
            .onAppear(perform: load)
        }
    }

    private var key: String { "review.checklist.\(meeting.id)" }
    private func load() { checks = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    private func toggle(_ k: String) {
        if checks.contains(k) { checks.remove(k) } else { checks.insert(k) }
        UserDefaults.standard.set(Array(checks), forKey: key)
    }
}
