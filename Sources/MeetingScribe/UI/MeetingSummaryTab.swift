import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    @ViewBuilder
    var summaryBody: some View {
        switch mode {
        case .live:
            placeholder(systemImage: "sparkles",
                        title: "Summary not generated yet",
                        message: "Stop the recording — the summary runs on the final transcript.")
        case .upcoming:
            // Pre-meeting brief is rendered in a separate view for .upcoming
            // (see upcomingBriefBody). The Summary tab shows a helpful
            // placeholder directing the user to start recording.
            placeholder(systemImage: "sparkles",
                        title: "No summary yet",
                        message: "Start a recording and stop it. Ollama will draft a summary from the transcript.")
        case .past:
            pastSummaryBody
        }
    }

    @ViewBuilder
    private var pastSummaryBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if summary.isEmpty {
                    emptySummaryView
                } else {
                    // Read-only markdown renderer — true heading sizes,
                    // indented lists, monospaced code. MarkdownEditor on
                    // macOS is significantly more performant than
                    // AttributedString for long documents.
                    // Draft follow-up is the #1 post-meeting action — surface it
                    // at the TOP of the summary instead of buried below it (DEF-3).
                    followUpButton
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 10)

                    MarkdownEditor(text: .constant(summary), isEditable: false)
                        .padding(.bottom, 8)

                    // Extracted action items from this meeting — inline
                    // so users don't have to navigate to the Tasks tab
                    // to see what was agreed. The same items are shown
                    // in the Tasks tab with full CRUD — these are read-
                    // only cards with a quick "mark done" affordance.
                    let items = meeting.map { manager.actionItems.items(for: $0.id) } ?? []
                    if !items.isEmpty {
                        actionItemsSection(items)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptySummaryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No summary")
                .font(.headline)
            Text("Ollama wasn't running when this meeting finished, or summarization failed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Regenerate button — visible when transcript exists but summary is empty.
            if !transcript.isEmpty {
                if let m = meeting {
                    let isRunning = manager.transcribingMeetingIDs.contains(m.id)
                    Button {
                        manager.pipelineController.transcribeNow(meeting: m,
                                                                  regenerateSummary: true)
                    } label: {
                        if isRunning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Generating…")
                            }
                        } else {
                            Label("Generate Summary", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var followUpButton: some View {
        Button {
            showFollowUp = true
        } label: {
            Label("Draft follow-up…", systemImage: "paperplane")
                .font(.callout)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .sheet(isPresented: $showFollowUp) {
            if let m = meeting {
                NavigationStack {
                    FollowUpView(
                        meetingTitle: m.displayTitle,
                        summary: summary,
                        actionItems: (manager.actionItems.items(for: m.id))
                            .map(\.title)
                    )
                    .navigationTitle("Draft follow-up")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showFollowUp = false }
                        }
                    }
                }
                .frame(minWidth: 640, minHeight: 480)
            }
        }
    }

    @ViewBuilder
    private func actionItemsSection(_ items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.horizontal).padding(.vertical, 4)
            HStack {
                Image(systemName: "checklist")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NDS.brand)
                Text("Action Items")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(items.filter { $0.status != .completed }.count) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ForEach(items) { item in
                InlineActionItemRow(item: item, store: manager.actionItems)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Inline action item row

@available(macOS 14.0, *)
private struct InlineActionItemRow: View {
    let item: ActionItem
    @ObservedObject var store: ActionItemStore

    @State private var titleDraft: String
    @FocusState private var titleFocused: Bool

    init(item: ActionItem, store: ActionItemStore) {
        self.item = item
        self.store = store
        _titleDraft = State(initialValue: item.title)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                store.setStatus(item.id,
                                status: item.status == .completed ? .open : .completed)
            } label: {
                Image(systemName: item.status == .completed
                    ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel(item.status == .completed ? "Mark as open" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                // Editable title — type to rename; commits on Enter or blur (no
                // need to jump to the Tasks tab for a quick fix).
                TextField("Task", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                    .focused($titleFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }

                HStack(spacing: 10) {
                    if let owner = item.owner, !owner.isEmpty {
                        Text(owner).font(.caption).foregroundStyle(.secondary)
                    }
                    // Due-date quick-set menu.
                    Menu {
                        Button("Today")     { store.setDueDate(item.id, dueDate: startOfToday) }
                        Button("Tomorrow")  { store.setDueDate(item.id, dueDate: day(after: 1)) }
                        Button("Next week") { store.setDueDate(item.id, dueDate: day(after: 7)) }
                        if item.dueDate != nil {
                            Divider()
                            Button("Clear due date") { store.setDueDate(item.id, dueDate: nil) }
                        }
                    } label: {
                        Label(dueLabel, systemImage: "calendar").font(.caption)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Priority dot — click to set.
            Menu {
                Button("Urgent") { store.setPriority(item.id, priority: .urgent) }
                Button("High")   { store.setPriority(item.id, priority: .high) }
                Button("Medium") { store.setPriority(item.id, priority: .medium) }
                Button("Low")    { store.setPriority(item.id, priority: .low) }
            } label: {
                Circle().fill(priorityColor).frame(width: 9, height: 9)
            }
            .menuStyle(.borderlessButton).fixedSize().padding(.top, 4)
            .help("Set priority")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func commitTitle() {
        let t = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != item.title { store.setTitle(item.id, title: t) }
    }

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    private func day(after days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: startOfToday)
    }
    private var dueLabel: String {
        guard let d = item.dueDate else { return "Due" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .high:   return .orange
        case .medium: return .yellow
        case .low:    return .secondary.opacity(0.4)
        }
    }
}
