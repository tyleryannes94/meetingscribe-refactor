import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    // MARK: - Enhanced Notes canvas (CN-1)

    /// One canvas: the AI summary (collapsible, up top) + your editable notes
    /// below, so you read the recap and write notes without switching tabs.
    @ViewBuilder
    var combinedNotesBody: some View {
        switch mode {
        case .past:
            VStack(spacing: 0) {
                outcomesStrip        // action items + decisions, always visible (TM-5)
                highlightsStrip      // C1-2 "mark moment" anchors, if any
                summaryDisclosure
                Divider().overlay(NDS.divider)
                notesEditor
            }
        default:
            // Live/upcoming: no finished summary yet — just the notes editor.
            notesEditor
        }
    }

    /// C1-2: highlights the user flagged with "mark moment" during the call,
    /// pinned atop the recap as navigable anchors. Tapping one jumps to the
    /// transcript so the surrounding context is one click away.
    @ViewBuilder
    private var highlightsStrip: some View {
        if let m = meeting {
            let marks = MeetingMarks.load(m.id)
            if !marks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .scaledFont(11, weight: .semibold).foregroundStyle(NDS.gold)
                        Text("Highlights")
                            .scaledFont(11, weight: .bold, relativeTo: .caption2).tracking(0.6)
                            .foregroundStyle(NDS.textSecondary)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(marks) { mark in
                            Button { tab = .transcript } label: {
                                HStack(spacing: 5) {
                                    Text(mark.timestamp)
                                        .scaledFont(11, weight: .semibold).monospacedDigit()
                                        .foregroundStyle(NDS.gold)
                                    if !mark.label.isEmpty {
                                        Text(mark.label)
                                            .scaledFont(11).foregroundStyle(NDS.textPrimary)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(NDS.gold.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Jump to the transcript")
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    /// Outcomes (action items + decisions) lifted OUT of the summary-gated branch
    /// so they're visible even before/without a summary. (TM-5)
    @ViewBuilder
    private var outcomesStrip: some View {
        if let m = meeting {
            let items = manager.actionItems.items(for: m.id)
            let decs = manager.decisions.decisions.filter { $0.meetingID == m.id }
            if !items.isEmpty || !decs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Outcomes").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    ForEach(items.prefix(5)) { item in
                        HStack(spacing: 8) {
                            Button {
                                manager.actionItems.setStatus(
                                    item.id, status: item.status == .completed ? .open : .completed)
                            } label: {
                                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.status == .completed ? NDS.brand : NDS.textTertiary)
                            }
                            .buttonStyle(.borderless)
                            Text(item.title).font(NDS.small).lineLimit(1)
                                .strikethrough(item.status == .completed, color: NDS.textTertiary)
                            if let owner = item.owner, !owner.isEmpty {
                                Text(owner).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    ForEach(decs.prefix(3)) { d in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal").scaledFont(12)
                                .foregroundStyle(NDS.brand.opacity(0.7))
                            Text(d.text).font(NDS.small).foregroundStyle(NDS.textSecondary).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NDS.sidebarBg)
                Divider().overlay(NDS.divider)
            }
        }
    }

    @ViewBuilder
    private var summaryDisclosure: some View {
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { summaryExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: summaryExpanded ? "chevron.down" : "chevron.right")
                            .scaledFont(10, weight: .semibold).foregroundStyle(NDS.textTertiary)
                        Label("Summary", systemImage: "sparkles")
                            .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
                if summaryExpanded {
                    followUpButton.padding(.horizontal).padding(.bottom, 8)
                    ScrollView {
                        MarkdownEditor(text: .constant(summary), isEditable: false)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxHeight: 320)
                }
            }
            .background(NDS.sidebarBg)
        } else if !bodyLoaded {
            MSSkeleton(lines: 4).padding(14)
        }
        // Loaded + empty summary → render nothing; the notes editor takes the
        // full height.
    }

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
            // U4-9: never promise a capability that isn't ready. If the summary
            // engine is off, say so plainly instead of naming a tool that won't run.
            placeholder(systemImage: "sparkles",
                        title: "No summary yet",
                        message: manager.ollamaReachable
                            ? "Start a recording and stop it — a summary is drafted from the transcript."
                            : "Start a recording and stop it. Turn on the summary engine in Settings to get summaries.")
        case .past:
            pastSummaryBody
        }
    }

    @ViewBuilder
    /// C1-6: copy the recap for the channel you're pasting into.
    private var copyMenu: some View {
        Menu {
            Button("Copy as plain text") { copyToClipboard(summary) }
            Button("Copy for Slack") { copyToClipboard(slackFormatted(summary)) }
            Button("Copy as email") { copyToClipboard(emailFormatted(summary)) }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.show("Copied")
    }

    /// Lightly de-markdown for Slack: `## H` → `*H*`, `**b**` → `*b*`.
    private func slackFormatted(_ md: String) -> String {
        var s = md
        s = s.replacingOccurrences(of: #"(?m)^#{1,6}\s*(.+)$"#, with: "*$1*", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "*$1*", options: .regularExpression)
        let title = meeting?.displayTitle ?? "Meeting"
        return "*\(title) — recap*\n\n" + s
    }

    private func emailFormatted(_ md: String) -> String {
        let title = meeting?.displayTitle ?? "Meeting"
        let plain = md.replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        return "Hi all,\n\nHere's a quick recap of \(title):\n\n\(plain)\n\nBest,"
    }

    private var pastSummaryBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if summary.isEmpty {
                    if bodyLoaded { emptySummaryView }
                    else { MSSkeleton(lines: 6).padding(24) }   // loading, not empty (PP-1)
                } else {
                    // Read-only markdown renderer — true heading sizes,
                    // indented lists, monospaced code. MarkdownEditor on
                    // macOS is significantly more performant than
                    // AttributedString for long documents.
                    // Draft follow-up is the #1 post-meeting action — surface it
                    // at the TOP of the summary instead of buried below it (DEF-3).
                    HStack(spacing: 8) {
                        followUpButton
                        copyMenu   // C1-6
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                    MarkdownEditor(text: .constant(summary), isEditable: false)
                        .padding(.bottom, 8)

                    // 👍/👎 feedback that steers regeneration (P5-3).
                    if let m = meeting {
                        SummaryFeedbackRow(meetingID: m.id) {
                            manager.pipelineController.transcribeNow(meeting: m, regenerateSummary: true)
                        }
                        .padding(.horizontal).padding(.bottom, 10)
                    }

                    // Extracted action items from this meeting — inline
                    // so users don't have to navigate to the Tasks tab
                    // to see what was agreed. The same items are shown
                    // in the Tasks tab with full CRUD — these are read-
                    // only cards with a quick "mark done" affordance.
                    let items = meeting.map { manager.actionItems.items(for: $0.id) } ?? []
                    actionItemsSection(items)
                }
            }
        }
    }

    @ViewBuilder
    private var emptySummaryView: some View {
        VStack(spacing: 16) {
            if !transcript.isEmpty, let m = meeting {
                // We have a transcript but no summary → summarization failed.
                // D4-1: a designed failure state with the Generate retry as its
                // one-click fix, not jargon prose ("Ollama wasn't running…").
                let isRunning = manager.transcribingMeetingIDs.contains(m.id)
                MSErrorState(
                    presented: PresentedError(
                        title: "The summary engine wasn't running",
                        diagnosis: "Your on-device summary engine was off when this finished, so there's no summary yet. The recording and transcript are safe.",
                        fixLabel: isRunning ? nil : "Generate summary",
                        kind: .summaryEngine),
                    onFix: isRunning ? nil : {
                        manager.pipelineController.transcribeNow(meeting: m, regenerateSummary: true)
                    })
                if isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Generating…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                // Genuinely empty (upcoming / no transcript yet).
                Image(systemName: "sparkles")
                    .scaledFont(36)
                    .foregroundStyle(.secondary)
                Text("No summary yet")
                    .font(.headline)
                Text("A short recap appears here once this conversation has been recorded and processed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                            .map(\.title),
                        recipients: attendeeEmails(for: m),
                        meetingID: m.id
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
                if !items.isEmpty {
                    Text("\(items.filter { $0.status != .completed }.count) open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Confirm this meeting's unreviewed action items out of the
                // Triage inbox and into the Tasks workspace (redesign §3D).
                let unconfirmed = items.filter { $0.needsTriage }
                if !unconfirmed.isEmpty {
                    Button {
                        manager.actionItems.confirm(ids: unconfirmed.map(\.id))
                    } label: {
                        Label("Add \(unconfirmed.count) → Tasks", systemImage: "arrow.right.circle")
                            .labelStyle(.titleAndIcon).font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Confirm these action items into the Tasks workspace")
                }
                Button { addActionItem() } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon).font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Add an action item linked to this meeting")
                .accessibilityLabel("Add action item")
            }
            .padding(.horizontal)

            if items.isEmpty {
                Text("No action items yet. Add one, or they appear here automatically after summarization.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ForEach(items) { item in
                    InlineActionItemRow(item: item, store: manager.actionItems)
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 16)
    }

    /// Create a new action item already linked to this meeting (Req #7).
    private func addActionItem() {
        guard let m = meeting else { return }
        var t = manager.actionItems.createTask(title: "New action item")
        t.meetingID = m.id
        t.meetingTitle = m.displayTitle
        t.meetingDate = m.startDate
        manager.actionItems.upsert(t)
    }

    /// Resolve attendees to emails for prefilling Mail. The old version compared
    /// the *raw* "Jane <jane@acme.com>" string against displayName and never
    /// parsed the email sitting right there — so invite-sourced meetings opened
    /// the follow-up with empty recipients. Now: linked person's email first,
    /// then the email parsed straight out of the attendee string (P1-1).
    private func attendeeEmails(for m: Meeting) -> [String] {
        m.attendees.compactMap { raw in
            if let p = PeopleStore.shared.resolvedPerson(forAttendee: raw),
               !p.primaryEmail.isEmpty {
                return p.primaryEmail
            }
            let id = PersonResolver.parse(raw)
            return id.hasEmail ? id.email : nil
        }
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
                    .scaledFont(16)
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
            .accessibilityLabel("Set priority")
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

    private var priorityColor: Color { NDS.priority(item.priority) }
}

/// 👍/👎 + "why" feedback on a summary; a thumbs-down reason steers the next
/// regeneration (P5-3).
@available(macOS 14.0, *)
struct SummaryFeedbackRow: View {
    let meetingID: String
    var onRegenerate: () -> Void

    @State private var up: Bool?
    @State private var showWhy = false
    @State private var why = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Was this summary useful?").font(.caption).foregroundStyle(.secondary)
                Button { rate(true) } label: {
                    Image(systemName: up == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .buttonStyle(.plain).foregroundStyle(up == true ? Color.green : .secondary)
                Button { rate(false) } label: {
                    Image(systemName: up == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .buttonStyle(.plain).foregroundStyle(up == false ? Color.orange : .secondary)
                Spacer()
            }
            if showWhy {
                TextField("What was wrong? (e.g. missed action items, too long)", text: $why)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Save & regenerate") {
                        SummaryFeedback.set(up: false, why: why, for: meetingID)
                        showWhy = false
                        onRegenerate()
                    }
                    .controlSize(.small)
                    .disabled(why.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Just save") {
                        SummaryFeedback.set(up: false, why: why, for: meetingID)
                        showWhy = false
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            let r = SummaryFeedback.rating(for: meetingID)
            if r.has { up = r.up; why = r.why ?? "" }
        }
    }

    private func rate(_ u: Bool) {
        up = u
        SummaryFeedback.set(up: u, why: u ? nil : (why.isEmpty ? nil : why), for: meetingID)
        showWhy = !u
    }
}
