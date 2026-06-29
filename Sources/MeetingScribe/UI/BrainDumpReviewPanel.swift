import SwiftUI
import AppKit
import EventKit

/// Right column of the Brain Dump page. Renders the planner's drafts grouped
/// into Tasks / Calendar / Parked sections. Each card has Accept / Edit /
/// Reject actions that commit through to the live `ActionItemStore` or
/// `CalendarStoreActor`.
@available(macOS 14.0, *)
struct BrainDumpReviewPanel: View {
    @EnvironmentObject var store: BrainDumpStore
    @EnvironmentObject var actionItems: ActionItemStore
    let session: BrainDumpSession

    @State private var calendarError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NDS.divider)
            if session.drafts.isEmpty {
                empty
            } else {
                body(grouped: session.drafts)
            }
        }
        .background(NDS.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist").scaledFont(13).foregroundStyle(NDS.brand)
            Text("Review").scaledFont(13, weight: .semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            if !session.drafts.isEmpty {
                let pending = session.pendingDrafts.count
                Text("\(pending) pending")
                    .font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles").scaledFont(20).foregroundStyle(NDS.textTertiary)
            Text("Run \"Plan with AI\" — proposed tasks and focus blocks will land here.")
                .font(NDS.small).foregroundStyle(NDS.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func body(grouped drafts: [BrainDumpDraft]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let taskDrafts = drafts.compactMap { d -> TaskDraft? in
                    if case let .task(t) = d { return t } else { return nil }
                }
                let calendarDrafts = drafts.compactMap { d -> CalendarBlockDraft? in
                    if case let .calendarBlock(b) = d { return b } else { return nil }
                }

                section(title: "Tasks", count: taskDrafts.count) {
                    ForEach(taskDrafts) { draft in
                        TaskDraftCard(
                            draft: draft,
                            store: store,
                            actionItems: actionItems,
                            sessionID: session.id
                        )
                    }
                    if taskDrafts.isEmpty {
                        emptySectionRow("No task suggestions yet.")
                    }
                }

                section(title: "Calendar blocks", count: calendarDrafts.count) {
                    ForEach(calendarDrafts) { draft in
                        CalendarBlockDraftCard(
                            draft: draft,
                            store: store,
                            sessionID: session.id,
                            onError: { calendarError = $0 }
                        )
                    }
                    if calendarDrafts.isEmpty {
                        emptySectionRow("No focus blocks suggested yet.")
                    }
                }

                if let err = calendarError {
                    Text(err).font(NDS.small).foregroundStyle(NDS.selectColor("red"))
                }
            }
            .padding(12)
        }
    }

    private func emptySectionRow(_ text: String) -> some View {
        Text(text).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
    }

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        count: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(NDS.small.weight(.semibold))
                    .foregroundStyle(NDS.textPrimary)
                Text("\(count)").font(NDS.tiny.monospacedDigit())
                    .foregroundStyle(NDS.textTertiary)
                Spacer()
            }
            content()
        }
    }
}

// MARK: - Task draft card

@available(macOS 14.0, *)
private struct TaskDraftCard: View {
    let draft: TaskDraft
    let store: BrainDumpStore
    let actionItems: ActionItemStore
    let sessionID: String

    @State private var editing = false
    @State private var editedTitle = ""
    @State private var editedPriority: ActionItem.Priority = .medium
    @State private var editedDueDate = Date()
    @State private var editedHasDueDate = false
    @State private var editedNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: stateGlyph)
                    .scaledFont(14).foregroundStyle(stateColor)
                if editing {
                    TextField("Title", text: $editedTitle).textFieldStyle(.plain)
                        .font(NDS.small.weight(.semibold))
                } else {
                    Text(draft.title).font(NDS.small.weight(.semibold))
                        .foregroundStyle(stateColor == NDS.textTertiary ? NDS.textTertiary : NDS.textPrimary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                NotionChip(draft.priority.label,
                           color: NDS.priority(draft.priority),
                           systemImage: NDS.priorityGlyph(draft.priority))
                if let projectName = draft.suggestedProjectName ?? actionItems.project(id: draft.suggestedProjectID ?? "")?.name {
                    NotionChip(projectName, color: NDS.selectColor(projectName), systemImage: "folder")
                }
                if let due = draft.dueDate {
                    Text(Self.dueLabel(due)).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
            }
            if !draft.sourceURLs.isEmpty {
                FlowText(urls: draft.sourceURLs)
            }
            if let notes = draft.notes, !notes.isEmpty {
                Text(notes).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                    .lineLimit(3)
            }
            actionsRow
        }
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.hairline, lineWidth: 0.5))
        .opacity(stateOpacity)
    }

    private var cardBackground: Color {
        switch draft.state {
        case .accepted: return NDS.brand.opacity(0.05)
        case .rejected: return NDS.fieldBg.opacity(0.4)
        default:        return NDS.fieldBg
        }
    }

    private var stateOpacity: Double {
        if case .rejected = draft.state { return 0.55 }
        return 1.0
    }

    private var stateGlyph: String {
        switch draft.state {
        case .pending:  return "circle"
        case .accepted: return "checkmark.circle.fill"
        case .edited:   return "pencil.circle.fill"
        case .rejected: return "xmark.circle"
        }
    }

    private var stateColor: Color {
        switch draft.state {
        case .pending:  return NDS.brand
        case .accepted: return NDS.brand
        case .edited:   return NDS.brand
        case .rejected: return NDS.textTertiary
        }
    }

    @ViewBuilder
    private var actionsRow: some View {
        if editing {
            HStack(spacing: 6) {
                Picker("Priority", selection: $editedPriority) {
                    ForEach(ActionItem.Priority.allCases) { p in Text(p.label).tag(p) }
                }.pickerStyle(.menu).labelsHidden().frame(width: 110)
                Toggle("Due", isOn: $editedHasDueDate).toggleStyle(.checkbox)
                if editedHasDueDate {
                    DatePicker("", selection: $editedDueDate, displayedComponents: .date).labelsHidden()
                }
                Spacer()
                Button("Cancel") { editing = false }
                Button("Save") { commitEdit() }.keyboardShortcut(.defaultAction)
            }
            TextField("Notes", text: $editedNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        } else if case .pending = draft.state {
            HStack(spacing: 6) {
                Button { accept() } label: { Label("Accept", systemImage: "checkmark") }
                    .buttonStyle(MSPrimaryButtonStyle()).controlSize(.small)
                Button { beginEdit() } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(MSSecondaryButtonStyle()).controlSize(.small)
                Button { store.setDraftState(sessionID, draft.id, .rejected) } label: {
                    Label("Reject", systemImage: "xmark").font(NDS.tiny)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
                Spacer()
            }
        } else if case .accepted(let id) = draft.state, !id.isEmpty {
            HStack(spacing: 6) {
                Text("Added to Tasks").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Spacer()
                Button { store.setDraftState(sessionID, draft.id, .pending) } label: {
                    Text("Re-open").font(NDS.tiny)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
            }
        } else if case .rejected = draft.state {
            HStack(spacing: 6) {
                Spacer()
                Button { store.setDraftState(sessionID, draft.id, .pending) } label: {
                    Text("Undo").font(NDS.tiny)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
            }
        }
    }

    private func beginEdit() {
        editedTitle = draft.title
        editedPriority = draft.priority
        editedHasDueDate = draft.dueDate != nil
        editedDueDate = draft.dueDate ?? Date()
        editedNotes = draft.notes ?? ""
        editing = true
    }

    private func commitEdit() {
        store.updateDraft(sessionID, draft.id) { existing in
            guard case .task(var t) = existing else { return }
            t.title = editedTitle
            t.priorityRaw = editedPriority.rawValue
            t.dueDate = editedHasDueDate ? editedDueDate : nil
            t.notes = editedNotes.isEmpty ? nil : editedNotes
            t.state = .edited
            existing = .task(t)
        }
        editing = false
    }

    private func accept() {
        let newTask = actionItems.createTask(
            title: draft.title,
            projectID: draft.suggestedProjectID,
            priority: draft.priority
        )
        if let due = draft.dueDate { actionItems.setDueDate(newTask.id, dueDate: due) }
        if let notes = draft.notes, !notes.isEmpty {
            actionItems.setNotes(newTask.id, notes: notes)
        }
        store.setDraftState(sessionID, draft.id, .accepted(externalID: newTask.id))
    }

    private static func dueLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "Due \(f.string(from: d))"
    }
}

// MARK: - Calendar block draft card

@available(macOS 14.0, *)
private struct CalendarBlockDraftCard: View {
    let draft: CalendarBlockDraft
    let store: BrainDumpStore
    let sessionID: String
    let onError: (String) -> Void

    @State private var editing = false
    @State private var editedTitle = ""
    @State private var editedStart = Date()
    @State private var editedDuration: Int = 25

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: stateGlyph)
                    .scaledFont(14).foregroundStyle(NDS.brand)
                if editing {
                    TextField("Title", text: $editedTitle).textFieldStyle(.plain)
                        .font(NDS.small.weight(.semibold))
                } else {
                    Text(draft.title).font(NDS.small.weight(.semibold))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                Image(systemName: "clock").scaledFont(11).foregroundStyle(NDS.textTertiary)
                Text(Self.timeRange(draft.start, minutes: draft.durationMinutes))
                    .font(NDS.tiny.monospaced()).foregroundStyle(NDS.textPrimary)
                Text("·").foregroundStyle(NDS.textTertiary)
                Text("\(draft.durationMinutes) min").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            if let linked = draft.linkedTaskTitle, !linked.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link").scaledFont(10).foregroundStyle(NDS.textTertiary)
                    Text(linked).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                        .lineLimit(1)
                }
            }
            if let notes = draft.notes, !notes.isEmpty {
                Text(notes).font(NDS.tiny).foregroundStyle(NDS.textSecondary).lineLimit(2)
            }
            actionsRow
        }
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(NDS.hairline, lineWidth: 0.5))
        .opacity(stateOpacity)
    }

    private var cardBackground: Color {
        switch draft.state {
        case .accepted: return NDS.brand.opacity(0.05)
        case .rejected: return NDS.fieldBg.opacity(0.4)
        default:        return NDS.fieldBg
        }
    }

    private var stateOpacity: Double {
        if case .rejected = draft.state { return 0.55 }
        return 1.0
    }

    private var stateGlyph: String {
        switch draft.state {
        case .pending:  return "calendar.badge.plus"
        case .accepted: return "calendar.badge.checkmark"
        case .edited:   return "calendar.badge.exclamationmark"
        case .rejected: return "calendar"
        }
    }

    @ViewBuilder
    private var actionsRow: some View {
        if editing {
            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Starts", selection: $editedStart)
                Stepper("Duration: \(editedDuration) min", value: $editedDuration, in: 5...240, step: 5)
                HStack {
                    Spacer()
                    Button("Cancel") { editing = false }
                    Button("Save") { commitEdit() }.keyboardShortcut(.defaultAction)
                }
            }
        } else if case .pending = draft.state {
            HStack(spacing: 6) {
                Button { Task { await accept() } } label: { Label("Accept", systemImage: "checkmark") }
                    .buttonStyle(MSPrimaryButtonStyle()).controlSize(.small)
                Button { beginEdit() } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(MSSecondaryButtonStyle()).controlSize(.small)
                Button { store.setDraftState(sessionID, draft.id, .rejected) } label: {
                    Label("Reject", systemImage: "xmark").font(NDS.tiny)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
                Spacer()
            }
        } else if case .accepted(let id) = draft.state {
            HStack(spacing: 6) {
                Text(id.isEmpty ? "Copied to clipboard as ICS" : "Added to Calendar")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Spacer()
                Button { store.setDraftState(sessionID, draft.id, .pending) } label: {
                    Text("Re-open").font(NDS.tiny)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
            }
        } else if case .rejected = draft.state {
            HStack {
                Spacer()
                Button { store.setDraftState(sessionID, draft.id, .pending) } label: {
                    Text("Undo").font(NDS.tiny)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
            }
        }
    }

    private func beginEdit() {
        editedTitle = draft.title
        editedStart = draft.start
        editedDuration = draft.durationMinutes
        editing = true
    }

    private func commitEdit() {
        store.updateDraft(sessionID, draft.id) { existing in
            guard case .calendarBlock(var b) = existing else { return }
            b.title = editedTitle
            b.start = editedStart
            b.durationMinutes = editedDuration
            b.state = .edited
            existing = .calendarBlock(b)
        }
        editing = false
    }

    private func accept() async {
        // EventKit permission. If we don't have full access, fall back to
        // building an ICS payload and copying it to the clipboard.
        let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
            || (await CalendarStoreActor.shared.requestAccess())
        if granted, let id = await CalendarStoreActor.shared.scheduleFollowUp(
            title: draft.title,
            start: draft.start,
            durationMinutes: draft.durationMinutes,
            notes: draft.notes
        ) {
            store.setDraftState(sessionID, draft.id, .accepted(externalID: id))
            return
        }

        // Clipboard fallback. Mark the draft accepted with an empty id so the
        // card surfaces the "Copied to clipboard as ICS" message.
        let ics = Self.buildICS(draft)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ics, forType: .string)
        store.setDraftState(sessionID, draft.id, .accepted(externalID: ""))
        onError("Couldn't add to Calendar (no permission). The .ics is on your clipboard — paste into Calendar to add it.")
    }

    private static func buildICS(_ d: CalendarBlockDraft) -> String {
        let dtf = DateFormatter()
        dtf.locale = Locale(identifier: "en_US_POSIX")
        dtf.timeZone = TimeZone(identifier: "UTC")
        dtf.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let start = dtf.string(from: d.start)
        let end = dtf.string(from: d.end)
        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//MeetingScribe//BrainDump//EN
        BEGIN:VEVENT
        UID:\(d.id.uuidString)@meetingscribe
        DTSTAMP:\(dtf.string(from: Date()))
        DTSTART:\(start)
        DTEND:\(end)
        SUMMARY:\(d.title)
        DESCRIPTION:\(d.notes ?? "")
        END:VEVENT
        END:VCALENDAR
        """
    }

    private static func timeRange(_ start: Date, minutes: Int) -> String {
        let end = Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        let g = DateFormatter()
        g.dateFormat = "h:mm a"
        return "\(f.string(from: start)) – \(g.string(from: end))"
    }
}

// MARK: - Flow text for source URLs

@available(macOS 14.0, *)
private struct FlowText: View {
    let urls: [URL]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(urls, id: \.absoluteString) { url in
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "link").scaledFont(9).foregroundStyle(NDS.textTertiary)
                        Text(url.host ?? url.absoluteString)
                            .font(NDS.tiny).foregroundStyle(NDS.brand)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
    }
}
