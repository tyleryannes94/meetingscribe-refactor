import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Today scratchpad (1-3)
    //
    // Today is the home view you land on when opening Tasks. It's a daily
    // scratchpad built for momentum: a left "quick capture" column for ripping
    // off tasks in rapid succession (anything you add is pinned to today so it
    // doesn't vanish), and a right "brain dump" column where the local AI turns
    // free-text into tasks — suggesting a project, priority, and due date — or
    // sketches a focus plan for the day.

    /// Narrows a task list to the active workspace context (1-2). nil context
    /// ("All") passes everything through.
    func contextFiltered(_ list: [ActionItem]) -> [ActionItem] {
        guard let cid = env.activeContextID else { return list }
        return list.filter { store.effectiveContextID(for: $0) == cid }
    }

    /// Count that drives the sidebar "Today" badge: overdue + due-today.
    var todayCount: Int {
        contextFiltered(store.overdueTasks).count + contextFiltered(store.myDayTasks).count
    }

    @ViewBuilder
    var todayPane: some View {
        VStack(spacing: 0) {
            todayScratchHeader
            Divider().overlay(NDS.divider)
            HStack(spacing: 0) {
                todayCaptureColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(NDS.divider)
                todayBrainDumpColumn
                    .frame(width: 420)
            }
        }
    }

    // MARK: Header

    private var todayScratchHeader: some View {
        let overdue = contextFiltered(store.overdueTasks).count
        let dueToday = contextFiltered(store.myDayTasks).count
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill").scaledFont(16).foregroundStyle(NDS.selectColor("orange"))
                    Text("Today").scaledFont(22, weight: .bold, kind: .display)
                    Text(Self.todayDateString())
                        .font(NDS.small).foregroundStyle(NDS.textTertiary)
                }
                Text("What are your top priorities today?")
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if overdue > 0 { stat(label: "Overdue", value: overdue, color: NDS.selectColor("red")) }
                stat(label: "Due today", value: dueToday, color: NDS.brand)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    // MARK: Left — quick capture

    private var todayCaptureColumn: some View {
        let overdue = contextFiltered(store.overdueTasks)
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        let dueToday = contextFiltered(store.myDayTasks).sorted { sort($0, $1) }
        let seen = Set(overdue.map(\.id)).union(dueToday.map(\.id))
        let pinnedExtra = pinnedTodayTasks.filter { !seen.contains($0.id) }
        let todayItems = (dueToday + pinnedExtra)

        return VStack(spacing: 0) {
            todayQuickAddRow
            if overdue.isEmpty && todayItems.isEmpty {
                todayCaptureEmpty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !overdue.isEmpty {
                            todaySection("Overdue", items: overdue, tint: NDS.selectColor("red"))
                        }
                        if !todayItems.isEmpty {
                            todaySection("Today", items: todayItems, tint: NDS.brand)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    /// Tasks the user explicitly pinned into today (5-2), still open.
    private var pinnedTodayTasks: [ActionItem] {
        let pinned = PinnedToday.ids(pinnedTodayCSV)
        return contextFiltered(store.items.filter {
            pinned.contains($0.id) && $0.status != .completed && !$0.needsTriage
        })
    }

    private var todayQuickAddRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").scaledFont(15).foregroundStyle(NDS.brand)
            TextField("Add a task — try “Email Sarah friday !high +Marketing”", text: $todayQuickAddText)
                .textFieldStyle(.plain).font(NDS.body)
                .focused($todayQuickAddFocused)
                .onSubmit { commitTodayQuickAdd() }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        .overlay(RoundedRectangle(cornerRadius: NDS.radius).strokeBorder(NDS.hairline, lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var todayCaptureEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").scaledFont(34).foregroundStyle(NDS.selectColor("green"))
            Text("Nothing on deck yet").scaledFont(15, weight: .semibold)
            Text("Jot tasks above as they come to mind, or brain-dump on the right and let AI sort them.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func todaySection(_ title: String, items: [ActionItem], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title)
                    .scaledFont(13, weight: .semibold).foregroundStyle(tint)
                    .textCase(.uppercase).tracking(0.6)
                Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
            }
            ForEach(items) { row(for: $0) }
        }
    }

    // MARK: Right — AI brain dump

    private var todayBrainDumpColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles").scaledFont(14).foregroundStyle(NDS.brand)
                        Text("Brain dump").scaledFont(15, weight: .bold)
                    }
                    Text("Type or paste everything on your mind. AI turns it into tasks and suggests a project for each.")
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                }

                brainDumpEditor
                brainDumpActions

                if todayAnalyzing || todayPlanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small) // design-lint:allow
                        Text(todayAnalyzing ? "Reading your notes…" : "Planning your day…")
                            .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    }
                }
                if let err = todayScratchError {
                    Text(err).font(NDS.small).foregroundStyle(NDS.selectColor("red"))
                }
                if !todayDrafts.isEmpty { draftsReview }
                if let plan = todayPlan, !plan.isEmpty { planPanel(plan) }
            }
            .padding(16)
        }
    }

    private var brainDumpEditor: some View {
        TextEditor(text: $todayBrainDump)
            .font(NDS.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 150, maxHeight: 240)
            .padding(8)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            .overlay(RoundedRectangle(cornerRadius: NDS.radius).strokeBorder(NDS.hairline, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if todayBrainDump.isEmpty {
                    Text("e.g. Need to finish the Q3 deck by Friday, call the vendor back, follow up with Sam about the contract, book flights for the offsite…")
                        .font(NDS.body).foregroundStyle(NDS.textTertiary)
                        .padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    private var brainDumpActions: some View {
        let disabled = todayBrainDump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || todayAnalyzing || todayPlanning
        return HStack(spacing: 8) {
            Button { analyzeTodayBrainDump() } label: {
                Label("Extract tasks", systemImage: "wand.and.stars")
            }
            .buttonStyle(MSPrimaryButtonStyle())
            .disabled(disabled)

            Button { planTodayDay() } label: {
                Label("Top priorities", systemImage: "list.number")
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .disabled(todayAnalyzing || todayPlanning)

            Spacer()
            if !todayBrainDump.isEmpty {
                Button { todayBrainDump = ""; todayDrafts = []; todayPlan = nil; todayScratchError = nil } label: {
                    Text("Clear").font(NDS.small)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
            }
        }
    }

    private var draftsReview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Suggested tasks").scaledFont(13, weight: .semibold)
                    .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                Text("\(todayDrafts.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
                Button { addAllTodayDrafts() } label: {
                    Label("Add all", systemImage: "tray.and.arrow.down").font(NDS.small)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.brand)
            }
            ForEach(todayDrafts) { draft in draftRow(draft) }
        }
        .padding(.top, 4)
    }

    private func draftRow(_ d: ExtractedTaskDraft) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { addTodayDraft(d) } label: {
                Image(systemName: "plus.circle.fill").scaledFont(16).foregroundStyle(NDS.brand)
            }
            .buttonStyle(.plain).help("Add this task")
            VStack(alignment: .leading, spacing: 4) {
                Text(d.title).font(NDS.body).foregroundStyle(NDS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    NotionChip(d.priority.label, color: NDS.priority(d.priority), systemImage: NDS.priorityGlyph(d.priority))
                    if let pid = d.suggestedProjectID, let p = store.project(id: pid) {
                        NotionChip(p.name, color: NDS.selectColor(p.name), systemImage: p.icon ?? "doc.text")
                    } else if let name = d.suggestedProjectName {
                        NotionChip("\(name)?", color: NDS.textTertiary, systemImage: "questionmark.folder")
                    }
                    if let due = d.dueDate {
                        Text(Self.draftDueString(due)).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { todayDrafts.removeAll { $0.id == d.id } } label: {
                Image(systemName: "xmark").scaledFont(11).foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.plain).help("Dismiss")
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.hairline, lineWidth: 0.5))
    }

    private func planPanel(_ plan: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "target").scaledFont(12).foregroundStyle(NDS.brand)
                Text("Focus plan").scaledFont(13, weight: .semibold)
                    .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                Spacer()
                Button { todayPlan = nil } label: {
                    Image(systemName: "xmark").scaledFont(11).foregroundStyle(NDS.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Text(LocalizedStringKey(plan)).font(NDS.body).foregroundStyle(NDS.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(NDS.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.brand.opacity(0.25), lineWidth: 1))
    }

    // MARK: Actions

    func commitTodayQuickAdd() {
        let raw = todayQuickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let t = store.createTask(parsing: raw, projectID: nil)
        // Anything captured here belongs to today until it's done.
        PinnedToday.toggle(t.id, in: &pinnedTodayCSV)
        todayQuickAddText = ""
        Task { @MainActor in todayQuickAddFocused = true }
    }

    func addTodayDraft(_ d: ExtractedTaskDraft) {
        let pid = d.suggestedProjectID
        if let pid, let p = store.project(id: pid), !store.pageHasDatabase(p) {
            store.setProjectDatabaseEnabled(pid, true)
        }
        let t = store.createTask(title: d.title, projectID: pid, priority: d.priority)
        if let due = d.dueDate { store.setDueDate(t.id, dueDate: due) }
        PinnedToday.toggle(t.id, in: &pinnedTodayCSV)
        todayDrafts.removeAll { $0.id == d.id }
    }

    func addAllTodayDrafts() {
        for d in todayDrafts { addTodayDraft(d) }
    }

    func analyzeTodayBrainDump() {
        let text = todayBrainDump
        todayScratchError = nil
        todayPlan = nil
        todayAnalyzing = true
        let projects = store.projects
            .filter { $0.status != .archived }
            .map { (id: $0.id, name: $0.name) }
        Task {
            do {
                let drafts = try await OllamaService().extractTaskDrafts(from: text, projects: projects)
                todayDrafts = drafts
                todayAnalyzing = false
                if drafts.isEmpty { todayScratchError = "Couldn't find any tasks in that text." }
            } catch {
                todayAnalyzing = false
                todayScratchError = Self.aiErrorMessage(error)
            }
        }
    }

    func planTodayDay() {
        todayScratchError = nil
        todayPlanning = true
        let dump = todayBrainDump
        let current = (contextFiltered(store.overdueTasks) + contextFiltered(store.myDayTasks)
                       + pinnedTodayTasks).map(\.title)
        Task {
            do {
                let plan = try await OllamaService().planTodayPriorities(brainDump: dump, currentTasks: current)
                todayPlan = plan
                todayPlanning = false
            } catch {
                todayPlanning = false
                todayScratchError = Self.aiErrorMessage(error)
            }
        }
    }

    static func aiErrorMessage(_ error: Error) -> String {
        "The on-device AI engine isn't reachable right now. Make sure it's running, then try again."
    }

    static func draftDueString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return "Due \(f.string(from: d))"
    }

    static func todayDateString() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}
