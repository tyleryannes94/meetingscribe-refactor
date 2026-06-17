import SwiftUI

/// The Decision Ledger (4-D): a dedicated, filterable view of every decision
/// across all meetings, so power users stop re-litigating choices they made
/// months ago. Filter by status / person / search; grouped by month. Each card
/// shows the rationale (the WHY, from P0-E), the people involved, and a backlink
/// to the source meeting.
@available(macOS 14.0, *)
struct DecisionLedgerView: View {
    @EnvironmentObject var decisions: DecisionStore
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var router: WorkspaceRouter
    var asSheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var statusFilter: DecisionStatus?
    @State private var groupMode: GroupMode = .byMonth
    @State private var topicGroups: [(key: String, items: [Decision])] = []

    enum GroupMode: String, CaseIterable, Identifiable {
        case byMonth, byTopic
        var id: String { rawValue }
        var label: String { self == .byMonth ? "Month" : "Topic" }
    }

    var body: some View {
        VStack(spacing: 0) {
            if asSheet {
                HStack {
                    Label("Decision Ledger", systemImage: "checkmark.seal")
                        .font(.headline)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .padding(14)
                Divider().overlay(NDS.divider)
            }
            filterBar
            Divider().overlay(NDS.divider)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if filtered.isEmpty {
                        Text("No decisions match.").font(NDS.small)
                            .foregroundStyle(NDS.textTertiary).padding(.top, 24)
                    }
                    ForEach(grouped, id: \.key) { group in
                        Text(group.key).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .padding(.top, 6)
                        ForEach(group.items, id: \.id) { d in card(d) }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: asSheet ? 620 : nil, minHeight: asSheet ? 640 : nil)
        .background(NDS.bg)
        .task(id: "\(groupMode.rawValue)|\(query)|\(statusFilter?.rawValue ?? "")") {
            if groupMode == .byTopic { recomputeTopicGroups() }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(NDS.textTertiary)
            TextField("Search decisions…", text: $query).textFieldStyle(.plain)
            Picker("", selection: $statusFilter) {
                Text("All").tag(DecisionStatus?.none)
                ForEach(DecisionStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(DecisionStatus?.some($0)) }
            }
            .labelsHidden().fixedSize()
            Picker("", selection: $groupMode) {
                ForEach(GroupMode.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().fixedSize()
            .help("Group decisions by month or by topic cluster")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var filtered: [Decision] {
        var out = decisions.decisions
        if let statusFilter { out = out.filter { $0.status == statusFilter } }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            out = out.filter { $0.text.lowercased().contains(q) || ($0.rationale ?? "").lowercased().contains(q) }
        }
        return out
    }

    private var grouped: [(key: String, items: [Decision])] {
        switch groupMode {
        case .byMonth:
            let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"
            let groups = Dictionary(grouping: filtered) { fmt.string(from: $0.date) }
            return groups.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
                .sorted { ($0.items.first?.date ?? .distantPast) > ($1.items.first?.date ?? .distantPast) }
        case .byTopic:
            return topicGroups
        }
    }

    /// 4-D: cluster the filtered decisions by embedding similarity into labeled
    /// topic groups. Cheap + synchronous; recomputed via `.task` when the inputs
    /// change so it never runs on every body evaluation.
    private func recomputeTopicGroups() {
        let embByID = Dictionary(
            VaultIndexService.shared.allEmbeddings()
                .filter { $0.entityKind == "decision" }
                .map { ($0.entityID, $0.vector) },
            uniquingKeysWith: { a, _ in a })
        topicGroups = DecisionClusterer.cluster(filtered, embeddings: embByID)
    }

    @ViewBuilder
    private func card(_ d: Decision) -> some View {
        Button {
            if let m = manager.meeting(forEntityID: d.meetingID) { router.openMeeting(m) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(d.text).font(NDS.body.weight(.medium)).foregroundStyle(NDS.textPrimary)
                    .multilineTextAlignment(.leading)
                if let r = d.rationale, !r.isEmpty {
                    Text(r).font(NDS.small).foregroundStyle(NDS.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    statusBadge(d.status)
                    Text(d.meetingTitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                    Spacer()
                    ForEach(d.personIDs.prefix(3), id: \.self) { pid in
                        if let p = people.person(by: pid) {
                            Text(p.displayName.split(separator: " ").first.map(String.init) ?? p.displayName)
                                .font(NDS.tiny).foregroundStyle(NDS.brand)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ s: DecisionStatus) -> some View {
        Text(s.rawValue.capitalized)
            .font(NDS.tiny).foregroundStyle(s == .open ? NDS.gold : NDS.textTertiary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((s == .open ? NDS.gold : NDS.textTertiary).opacity(0.15), in: Capsule())
    }
}
