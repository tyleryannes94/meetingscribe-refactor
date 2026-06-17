import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VaultKit

/// How wide to throw the net when running a conversation analysis.
/// Recent-by-count beats date-based for sporadic contacts (a friend
/// you haven't texted in 3 months still gets 1000 messages of context).
/// All-time pays the full LLM cost once and persists the result as an
/// AttachedNote (kind "<preset>-all") so subsequent views are instant.
enum AnalysisScope: Hashable {
    case recent1000
    case allTime
}

/// Time range for the Analyze popover (§4C) — combines date windows with the
/// two count-based modes. Maps to a `MessagesAnalyzer.MessageWindow` (date
/// filtering) plus a message-count cap. `.allTime` keeps the cache-and-save
/// behavior; everything else produces an inline result.
enum AnalyzeRange: String, CaseIterable, Identifiable, Hashable {
    case last30, last90, last6mo, thisYear, recent1000, allTime
    var id: String { rawValue }
    var label: String {
        switch self {
        case .last30:     return "Last 30d"
        case .last90:     return "Last 90d"
        case .last6mo:    return "Last 6mo"
        case .thisYear:   return "This year"
        case .recent1000: return "Recent 1000"
        case .allTime:    return "All time"
        }
    }
    var window: MessagesAnalyzer.MessageWindow {
        switch self {
        case .last30:   return .lastDays(30)
        case .last90:   return .lastDays(90)
        case .last6mo:  return .lastDays(180)
        case .thisYear: return .lastDays(365)
        case .recent1000, .allTime: return .allTime
        }
    }
    var recentLimit: Int {
        switch self {
        case .recent1000: return 1000
        case .allTime:    return 100_000
        default:          return 5000     // date window does the limiting
        }
    }
}

/// Conversation analysis preset — choices the user can pick from on the
/// Person detail view to run different kinds of analysis over the recent
/// iMessage snippets. Each preset bundles a label, a SF Symbol, a `kind`
/// tag (which becomes the AttachedNote.kind when saved), and a prompt
/// template (`PROMPT_BODY` placeholder is replaced with the transcript).
///
/// Adding a new preset = add a case + describe it in `template`. No
/// schema migrations needed.
enum ConversationAnalysisPreset: String, CaseIterable, Identifiable, Hashable {
    case relationshipSummary
    case sentimentTrends
    case topicsThemes
    case communicationStyle
    case actionItems
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relationshipSummary: return "Summarize relationship"
        case .sentimentTrends:     return "Sentiment & trends"
        case .topicsThemes:        return "Topics & themes"
        case .communicationStyle:  return "Communication style"
        case .actionItems:         return "Pending action items"
        case .custom:              return "Custom prompt…"
        }
    }

    var systemImage: String {
        switch self {
        case .relationshipSummary: return "person.line.dotted.person"
        case .sentimentTrends:     return "chart.xyaxis.line"
        case .topicsThemes:        return "tag"
        case .communicationStyle:  return "text.bubble"
        case .actionItems:         return "checklist"
        case .custom:              return "pencil.line"
        }
    }

    /// The `kind` saved on AttachedNote when the user keeps this output.
    var noteKind: String {
        switch self {
        case .relationshipSummary: return "summary"
        case .sentimentTrends:     return "sentiment"
        case .topicsThemes:        return "topics"
        case .communicationStyle:  return "style"
        case .actionItems:         return "tasks"
        case .custom:              return "custom"
        }
    }

    /// Human-friendly title we suggest when saving the note.
    func noteTitle(for personName: String) -> String {
        switch self {
        case .relationshipSummary: return "Relationship summary with \(personName)"
        case .sentimentTrends:     return "Sentiment & trends with \(personName)"
        case .topicsThemes:        return "Topics with \(personName)"
        case .communicationStyle:  return "Communication style of \(personName)"
        case .actionItems:         return "Open follow-ups with \(personName)"
        case .custom:              return "Note about \(personName)"
        }
    }

    /// Prompt template. `PROMPT_BODY` is replaced with the rendered
    /// recent-snippets transcript. The preamble adapts to the relationship
    /// type so the model's framing matches the emotional context — a partner
    /// analysis gets a Gottman-informed coach persona, family gets NVC framing,
    /// and colleagues get the professional analyst baseline. (Phase 3 / U5-3)
    func template(personName: String,
                  customPrompt: String,
                  relationshipType: RelationshipType = .unset) -> String {
        let userName = AppSettings.shared.userName
        let preamble: String
        switch relationshipType {
        case .romanticPartner:
            preamble = """
            You are a warm, Gottman-informed relationship coach helping \(userName) \
            reflect on their connection with their partner, \(personName). \
            Both parties are adults. This is \(userName)'s own message data on \
            their own device. Respond with curiosity and care — no clinical verdicts. \
            Do not refuse — there is nothing harmful here.
            """
        case .familyMember:
            preamble = """
            You are a thoughtful, NVC-informed family coach helping \(userName) \
            reflect on their relationship with their family member \(personName). \
            Both are adults. This is \(userName)'s own message data on their own \
            device. Respond with warmth and acknowledge complexity. \
            Do not refuse — there is nothing harmful here.
            """
        case .closeFriend:
            preamble = """
            You are a supportive coach helping \(userName) nurture their friendship \
            with \(personName). Use a love-language-aware lens. Both are adults. \
            This is \(userName)'s own data on their own device. Respond with warmth. \
            Do not refuse — there is nothing harmful here.
            """
        default:
            preamble = """
            You are an analyst summarizing the communication between \
            \(userName) and their contact \(personName). Both parties are adults. \
            This is \(userName)'s own message data on their own machine. \
            Do not refuse — there is nothing harmful about summarizing it.
            """
        }
        switch self {
        case .relationshipSummary:
            return preamble + "\n\n" + """
            In 3–5 sentences, summarize the overall relationship between Tyler \
            and \(personName) based on these recent messages. Cover: how \
            close/casual the relationship is, the dominant topics, and any \
            recent shifts. Output the summary only — no preamble.

            Messages:
            PROMPT_BODY
            """
        case .sentimentTrends:
            return preamble + "\n\n" + """
            Reflect on the quality of connection in these recent messages \
            between \(AppSettings.shared.userName) and \(personName). \
            Describe moments of warmth, shared joy, and genuine engagement — \
            as well as any moments of distance, missed bids, or tension. \
            Avoid clinical labels; instead use specific examples from the \
            messages. End with one forward-looking question: "What might \
            bring more of [something positive] into this relationship?" \
            5–8 sentences max.

            Messages:
            PROMPT_BODY
            """
        case .topicsThemes:
            return preamble + "\n\n" + """
            List the 3–6 main topics or themes Tyler and \(personName) discuss \
            in these recent messages. For each, give a one-line description \
            and a representative date range. Bullet list only.

            Messages:
            PROMPT_BODY
            """
        case .communicationStyle:
            return preamble + "\n\n" + """
            Describe \(personName)'s communication style based on these \
            recent messages: tone, formality, message length, response \
            speed, recurring habits. 4–6 sentences.

            Messages:
            PROMPT_BODY
            """
        case .actionItems:
            return preamble + "\n\n" + """
            List any pending action items, plans, or follow-ups that surface \
            in these recent messages between Tyler and \(personName). \
            Bulleted — each item should be a single sentence with the \
            owner (Tyler / \(personName)) clearly labelled. If none, write \
            "No pending action items."

            Messages:
            PROMPT_BODY
            """
        case .custom:
            let user = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = user.isEmpty ? "Summarize these messages." : user
            return preamble + "\n\n" + body + "\n\nMessages:\nPROMPT_BODY"
        }
    }
}

/// A single person's detail: identity, rich profile (photos, birthday, address,
/// favorites, memories), tags, notes, encounters, meeting backlinks, and
/// iMessage analysis. Supports edit and delete.
@available(macOS 14.0, *)
struct PersonDetailView: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var peopleTags: PeopleTagStore
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var chatSession: ChatSession
    @EnvironmentObject var router: WorkspaceRouter
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var actionItems: ActionItemStore
    @EnvironmentObject var decisions: DecisionStore

    let person: Person
    /// Called after the person is deleted so the list can clear its selection.
    var onDeleted: () -> Void

    @State private var showEdit = false
    @State private var showBrief = false   // 2-B
    // Inline identity editing — change name/role/company in place instead of
    // opening the full AddPersonSheet modal for a one-field fix (req #2: easier
    // CRM editing). The modal stays available (ellipsis) for contact fields/tags.
    @State private var editingIdentity = false
    @State private var draftName = ""
    @State private var draftRole = ""
    @State private var draftCompany = ""
    @State private var draftEmail = ""
    @State private var draftPhone = ""
    @State private var draftAddress = ""
    @State private var draftBio = ""
    @State private var showAddEncounter = false
    /// C2-3: the health "why" popover.
    @State private var showHealthWhy = false
    @State private var showAddRelationship = false
    @State private var confirmDelete = false
    @State private var newMemory = ""
    /// C2-11: keyboard-first verbs — `N` jumps focus to the add-memory field.
    @FocusState private var memoryFieldFocused: Bool
    @State private var newTalkingPoint = ""
    @State private var showEvidence = false
    // C2-4: reconnect-with-context + local AI-drafted opener.
    @State private var showReconnectDraft = false
    @State private var reconnectDraft = ""
    @State private var reconnectDrafting = false
    @State private var reconnectError: String?
    @State private var newTaskTitle = ""
    @State private var newFavorite = ""
    @State private var newTagName = ""
    @State private var aiSuggestions: PersonAISuggestions?
    @State private var aiRunning = false
    @State private var aiError: String?
    @State private var dismissedSuggestions: Set<String> = []
    @State private var deepRunning = false
    /// Unrecorded calendar meetings with this person (last ~180 days), for the
    /// unified timeline (U2-1).
    @State private var calendarMeetings: [Meeting] = []
    @State private var messageStats: MessagesAnalyzer.Stats?
    @State private var messageError: String?
    @State private var analyzingMessages = false
    /// Which slice of the conversation the stats reflect (user-selectable).
    @State private var messageWindow: MessagesAnalyzer.MessageWindow = .allTime
    @State private var analysisOutput: AnalysisOutput?
    @State private var analysisRunning: ConversationAnalysisPreset?
    @State private var customPromptDraft = ""
    @State private var showCustomPrompt = false
    // Two-pane work area (§4B): which tab is showing in the right pane.
    @State private var personTab: PersonTab = .overview
    enum PersonTab: String, CaseIterable, Hashable {
        // P1-1: 6 → 4 tabs — Story folds into Overview, Tasks into Meetings, so
        // the profile is less overwhelming without burying texts or notes.
        case overview, meetings, messages, notes
        var label: String {
            switch self {
            case .overview: return "Overview"
            case .meetings: return "Meetings"
            case .messages: return "Messages"
            case .notes:    return "Notes"
            }
        }
    }
    // Inline add-email (§4A) and add-to-meeting (§4D).
    @State private var showAddEmail = false
    @State private var newEmailDraft = ""
    @State private var showAddToMeeting = false
    // Analyze popover (§4C): pick WHAT to analyze × the TIME RANGE.
    @State private var showAnalyzePopover = false
    @State private var analyzePreset: ConversationAnalysisPreset = .relationshipSummary
    @State private var analyzeRange: AnalyzeRange = .recent1000
    @State private var noteExpansion: [String: Bool] = [:]
    // C2-8: co-attendees from the people graph's edge data. Computed once per
    // profile open (the graph + force layout is too costly to rebuild in body)
    // and cached here; empty for isolated contacts (the section then hides).
    @State private var inCommon: [InCommonPerson] = []

    /// One "In common" row: a co-attendee plus how many meetings they shared.
    private struct InCommonPerson: Identifiable {
        let person: Person
        let count: Int
        var id: String { person.id }
    }

    /// Display container for a finished analysis. Holds the preset (so we
    /// know what kind chip to show) and the rendered text the user can
    /// either read inline or save as an AttachedNote.
    struct AnalysisOutput: Identifiable, Equatable {
        let id = UUID()
        let preset: ConversationAnalysisPreset
        let body: String
        let promptUsed: String
    }

    /// Re-resolve from the store so edits/encounter additions reflect live.
    private var current: Person { people.person(by: person.id) ?? person }
    private var subtitle: String {
        [current.role, current.company].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var tags: [MeetingTag] {
        peopleTags.allTags.filter { current.tagIDs.contains($0.id) }
    }

    /// C2-11: keyboard-first profile verbs (Clay-style). Single keys for the
    /// common actions — N add memory, L log an encounter, T new task — plus
    /// ⌘1–5 to switch tabs. Rendered as a hidden, zero-size shortcut layer; while
    /// a text field is focused the keystroke goes to the field, not these.
    @ViewBuilder
    /// P7 (ux-audit-2026-06b §4.3): tabs are gone, so the keyboard verbs no
    /// longer flip `personTab`. Memories defaults collapsed under the canvas;
    /// the `N` verb expands that section first (writes its `MSSection`
    /// persistence key) then focuses the new-memory field. The `T` verb
    /// nudges focus toward the task quick-add field. ⌘1–5 tab shortcuts are
    /// dropped entirely.
    private var keyboardVerbs: some View {
        Group {
            Button("") {
                UserDefaults.standard.set(true, forKey: "section.person.memories.expanded")
                DispatchQueue.main.async { memoryFieldFocused = true }
            }
            .keyboardShortcut("n", modifiers: [])
            Button("") { showAddEncounter = true }
                .keyboardShortcut("l", modifiers: [])
            Button("") {
                UserDefaults.standard.set(true, forKey: "section.person.tasks.expanded")
            }
            .keyboardShortcut("t", modifiers: [])
        }
        .opacity(0).frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var body: some View {
        // One scrolling canvas. The chat used to live in a dedicated right
        // column (`personChatColumn`) — that's now gone because the global
        // right-side `ChatSidebar` is the one chat surface, scoped to this
        // person via `updateChatContext()`. No more duplicate chat panels.
        detailPane
            .frame(maxWidth: .infinity)
            .background(NDS.bg)
            .background(keyboardVerbs)   // N / L / T
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updateChatContext() }
        .onChange(of: current.id) { _, _ in updateChatContext() }
        .task(id: current.id) { await loadCalendarMeetings() }
        .task(id: current.id) { computeInCommon() }
        // P0-4: pull this person's latest iMessage recency so the overdue badge
        // + insight reflect texts, not just meetings, the moment the profile opens.
        .task(id: current.id) { people.refreshIMessageSignal(forPersonID: current.id) }
        .onDisappear {
            chatSession.setContext("The People tab — the user's second-brain contacts.")
        }
        .sheet(isPresented: $showEdit) {
            AddPersonSheet(editing: current)
                .environmentObject(people)
                .environmentObject(peopleTags)
        }
        .sheet(isPresented: $showAddEncounter) {
            // C2-12: one encounter flow. The profile now opens the same 1-tap
            // QuickEncounterSheet used from Today, not the retired long-form sheet.
            QuickEncounterSheet(person: current)
                .environmentObject(people)
        }
        .sheet(isPresented: $showAddRelationship) {
            AddRelationshipSheet(personID: current.id).environmentObject(people)
        }
        .sheet(isPresented: $showAddToMeeting) { addToMeetingSheet }
        .sheet(isPresented: $showBrief) {
            PersonBriefSheet(personID: current.id,
                             actionItems: actionItems,
                             pastMeetings: manager.pastMeetings,
                             calendarUpcoming: calendar.upcoming)
        }
        .confirmationDialog("Delete \(current.displayName)?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let snapshot = current
                let encs = people.encounters(for: current.id)
                people.deletePerson(current)
                onDeleted()
                ToastCenter.shared.show("Deleted \(snapshot.displayName)", undoTitle: "Undo") {
                    people.restore(person: snapshot, encounters: encs)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the person and their encounters. You can undo right after.")
        }
    }

    private var firstName: String {
        current.displayName.components(separatedBy: " ").first ?? current.displayName
    }

    /// Sheet to add this person as an attendee on an upcoming meeting (§4D).
    private var addToMeetingSheet: some View {
        let upcoming = calendar.upcoming
            .filter { $0.startDate > Date().addingTimeInterval(-3600) }
            .sorted { $0.startDate < $1.startDate }
        return VStack(spacing: 0) {
            HStack {
                Text("Add \(current.displayName) to a meeting").font(.headline)
                Spacer()
                Button("Done") { showAddToMeeting = false }
                    .buttonStyle(MSSecondaryButtonStyle())
            }
            .padding()
            Divider().overlay(NDS.divider)
            if upcoming.isEmpty {
                MSEmptyState(systemImage: "calendar",
                             title: "No upcoming meetings",
                             message: "Meetings from your calendar will appear here.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(upcoming) { m in
                            Button { addToMeeting(m) } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.displayTitle).scaledFont(13, weight: .semibold)
                                            .foregroundStyle(NDS.textPrimary).lineLimit(1)
                                        Text(m.startDate.formatted(date: .abbreviated, time: .shortened))
                                            .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(NDS.accent)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: 460)
        .background(NDS.bg)
    }

    private func addToMeeting(_ m: Meeting) {
        let attendee = current.primaryEmail.isEmpty
            ? current.displayName
            : "\(current.displayName) <\(current.primaryEmail)>"
        if manager.addAttendee(attendee, to: m) != nil {
            ToastCenter.shared.show("Added \(firstName) to \(m.displayTitle)")
        } else {
            ToastCenter.shared.show("\(firstName) is already on that meeting")
        }
        showAddToMeeting = false
    }

    // MARK: - Two-pane detail (§4)

    /// Fixed identity/contact pane on the left + tabbed work area on the right.
    /// Collapsed two-column person canvas — the 300pt identity rail is gone.
    /// Everything that used to live in it (compactHeader + insight + tags +
    /// contact + relationships + encounters + photos) now sits at the top of
    /// the right canvas above the rest of the MSSection stack.
    private var detailPane: some View {
        workArea
    }

    // `identityPane` (the 300pt left column) is gone — its content stacks at
    // the top of the canvas now. Helpers (`tagsEditSection`, `contactRows`,
    // `relationshipsSection`, `encountersSection`, `photosSection`) are still
    // used by `workContent` so they stay.

    /// 5-E / C2-3: a pinned, deterministic relationship insight at the top of the
    /// profile — the "why" behind the health, computed instantly from cadence +
    /// last-contact (no AI round-trip). Self-hides for untyped contacts.
    @ViewBuilder
    private var proactiveInsightCard: some View {
        if let insight = relationshipInsight {
            HStack(alignment: .center, spacing: 10) {
                healthRing
                Text(insight).font(NDS.small).foregroundStyle(NDS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    /// Relationship-health arc (coach): the persisted strength score (0–1) as a
    /// colored ring with the percentage, banded green / gold / red.
    private var healthRing: some View {
        let score = max(0, min(1, current.relationshipStrengthScore))
        let color: Color = score >= 0.66 ? .green : (score >= 0.33 ? NDS.gold : NDS.danger)
        return ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 4)
            Circle().trim(from: 0, to: max(0.02, score))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(score * 100))")
                .scaledFont(11, weight: .bold).foregroundStyle(color)
        }
        .frame(width: 38, height: 38)
        .help("Relationship health")
    }

    private var relationshipInsight: String? {
        let p = current
        guard p.relationshipType != .unset else { return nil }
        let cadence = p.effectiveCheckInDays
        guard let last = p.lastInteractionAt else {
            return "No contact logged yet with \(firstName). Log a check-in to start tracking this relationship."
        }
        let days = Int(Date().timeIntervalSince(last) / 86400)
        if days > cadence {
            return "It's been \(days) days since you connected with \(firstName) — overdue by \(days - cadence) on your \(cadence)-day cadence. A quick hello keeps it warm."
        }
        return "Last connected \(days) day\(days == 1 ? "" : "s") ago — on track for your \(cadence)-day cadence with \(firstName)."
    }

    /// P6 (ux-audit-2026-06b): right pane is now one scrolling canvas — the
    /// `MSPillTabs` are gone, sections from every former tab stack inside one
    /// `ScrollView` (see `workContent`). Each section owns its own
    /// expand/collapse state, so the user controls what's open instead of the
    /// tab bar gating four exclusive views.
    private var workArea: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: NDS.splitPaneTopInset)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    workContent
                }
                .padding(.horizontal, NDS.spaceXL)
                .padding(.vertical, NDS.spaceXL)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(NDS.bg)
    }

    // MARK: - Story (C2-1): one chronological stream of everything with this
    // person — encounters, meetings, notes, and decisions — so the profile
    // reads as a single relationship history instead of siloed tabs.
    private struct StoryItem: Identifiable {
        let id = UUID()
        let date: Date
        let icon: String
        let kind: String
        let title: String
        let detail: String?
    }

    private var storyItems: [StoryItem] {
        var items: [StoryItem] = []
        for e in people.encounters(for: current.id) {
            let emoji = e.mood.flatMap { Encounter.Mood(rawValue: $0)?.emoji }
            let title = emoji.map { "\($0)  \(e.eventName)" } ?? e.eventName
            items.append(.init(date: e.date, icon: "checkmark.circle.fill", kind: "Encounter",
                               title: title, detail: e.notes.isEmpty ? nil : e.notes))
        }
        for m in current.meetingMentionRecords {
            items.append(.init(date: m.date, icon: "bubble.left.and.bubble.right.fill", kind: "Meeting",
                               title: m.meetingTitle, detail: m.excerpt))
        }
        for mem in current.memories {
            items.append(.init(date: mem.occurredOn ?? mem.createdAt, icon: "note.text", kind: "Note",
                               title: mem.text, detail: nil))
        }
        for d in manager.decisions.decisions where d.personIDs.contains(current.id) {
            items.append(.init(date: d.date, icon: "checkmark.seal.fill", kind: "Decision",
                               title: d.text, detail: d.rationale))
        }
        return items.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var storySection: some View {
        let items = storyItems
        if items.isEmpty {
            Text("No history yet. Meetings, encounters, notes, and decisions with \(firstName) collect here as one story.")
                .font(NDS.small).foregroundStyle(NDS.textTertiary).padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.icon).scaledFont(12).foregroundStyle(NDS.brand)
                            .frame(width: 24, height: 24)
                            .background(NDS.brand.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.kind.uppercased())
                                    .scaledFont(10, weight: .bold).foregroundStyle(NDS.textTertiary).tracking(0.5)
                                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                    .scaledFont(10).foregroundStyle(NDS.textTertiary)
                            }
                            Text(item.title).font(NDS.small).foregroundStyle(NDS.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let d = item.detail, !d.isEmpty {
                                Text(d).scaledFont(11).foregroundStyle(NDS.textSecondary)
                                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    if item.id != items.last?.id {
                        Divider().overlay(NDS.divider.opacity(0.5))
                    }
                }
            }
        }
    }

    /// P5 (ux-audit-2026-06b §4.2) — the de-tabbed canvas. Every former tab's
    /// content is now wrapped in an `MSSection` and stacked one after another
    /// in a single scrolling column. Each section persists its own
    /// expand/collapse state via `section.person.<key>.expanded`. Tasks is
    /// promoted to top-level + expanded; the previously buried "Add to a
    /// meeting" action becomes the Meetings section's trailing accessory.
    @ViewBuilder
    private var workContent: some View {
        // The compact header and the always-on glance cards now live AT THE TOP
        // OF THE CANVAS (no more 300pt identity rail). The cramped column
        // showed e.g. "H..." for "Horst Carreño-Bauer" — gone.
        identityPanel    // compactHeader + inline edit form when editing
        proactiveInsightCard
        reconnectSection
        inCommonSection

        // Identity-rail content — kept available, but collapsed by default
        // so the canvas leads with the actionable stuff (Tasks / Meetings).
        // Tap a header to expand.
        MSSection("Contact", systemImage: "person.crop.circle",
                  persistenceKey: "person.contact.v2",
                  defaultExpanded: false) {
            contactRows
        }
        MSSection("Tags", systemImage: "tag",
                  count: tags.count,
                  persistenceKey: "person.tags.v2",
                  defaultExpanded: false) {
            tagsEditSection
        }
        MSSection("Relationships", systemImage: "person.2",
                  count: current.relationships.count,
                  persistenceKey: "person.relationships.v2",
                  defaultExpanded: false,
                  trailing: {
                      MSInlineButton("Add", systemImage: "plus") {
                          showAddRelationship = true
                      }
                      .disabled(people.people.count < 2)
                  }) {
            relationshipsSection
        }
        MSSection("Encounters", systemImage: "mappin.and.ellipse",
                  persistenceKey: "person.encounters.v2",
                  defaultExpanded: false,
                  trailing: {
                      MSInlineButton("Log encounter", systemImage: "calendar.badge.plus") {
                          showAddEncounter = true
                      }
                  }) {
            encountersSection
        }
        if !current.photoRelativePaths.isEmpty {
            MSSection("Photos", systemImage: "photo",
                      count: current.photoRelativePaths.count,
                      persistenceKey: "person.photos.v2",
                      defaultExpanded: false) {
                photosSection
            }
        }

        MSSection("Tasks", systemImage: "checklist",
                  count: personTasks.filter { $0.status != .completed }.count,
                  persistenceKey: "person.tasks.v2",
                  defaultExpanded: true) {
            tasksSection
        }
        MSSection("Meetings", systemImage: "calendar",
                  count: current.meetingMentions.count,
                  persistenceKey: "person.meetings.v2",
                  defaultExpanded: true,
                  trailing: {
                      MSInlineButton("Add to a meeting", systemImage: "calendar.badge.plus") {
                          showAddToMeeting = true
                      }
                  }) {
            VStack(alignment: .leading, spacing: NDS.spaceMD) {
                meetingHistorySection
                if !current.meetingMentions.isEmpty { mentionedInSection }
                decisionsSection
            }
        }
        MSSection("Messages", systemImage: "message",
                  persistenceKey: "person.messages.v2",
                  defaultExpanded: false) {
            messagesSection
        }
        MSSection("Discuss next time", systemImage: "bubble.left",
                  count: current.talkingPoints.count,
                  persistenceKey: "person.talkingpoints.v2",
                  defaultExpanded: false) {
            talkingPointsSection
        }
        MSSection("Memories", systemImage: "sparkles",
                  count: current.memories.count,
                  persistenceKey: "person.memories.v2",
                  defaultExpanded: false) {
            memoriesSection
        }
        MSSection("About", systemImage: "text.alignleft",
                  persistenceKey: "person.bio.v2",
                  defaultExpanded: false) {
            notes
        }
        MSSection("Saved analyses", systemImage: "doc.text",
                  count: current.attachedNotes.count,
                  persistenceKey: "person.attachednotes.v2",
                  defaultExpanded: false) {
            attachedNotesSection
        }
        MSSection("AI suggestions", systemImage: "wand.and.stars",
                  persistenceKey: "person.aisuggestions.v2",
                  defaultExpanded: false) {
            aiSuggestionsSection
        }
        MSSection("Favorites", systemImage: "heart",
                  count: current.favorites.count,
                  persistenceKey: "person.favorites.v2",
                  defaultExpanded: false) {
            favoritesEditSection
        }
        MSSection("Perf-review evidence", systemImage: "doc.text.magnifyingglass",
                  persistenceKey: "person.evidence.v2",
                  defaultExpanded: false) {
            evidenceSection
        }
        provenanceFooter
    }

    // MARK: - Inline identity editing
    // (req #2 — edit core fields in place; full sheet stays behind the ellipsis)

    private func beginIdentityEdit() {
        draftName = current.displayName
        draftRole = current.role
        draftCompany = current.company
        draftEmail = current.emails.first ?? ""
        draftPhone = current.phones.first ?? ""
        draftAddress = current.addresses.first ?? ""
        draftBio = current.bio
        editingIdentity = true
    }

    private func saveIdentityEdit() {
        var u = current
        u.displayName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        u.role = draftRole.trimmingCharacters(in: .whitespacesAndNewlines)
        u.company = draftCompany.trimmingCharacters(in: .whitespacesAndNewlines)
        u.bio = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
        // Edit the PRIMARY contact value in place but preserve any additional
        // values the modal added (don't clobber emails[1...]). (PPL-1 / PPL-2)
        u.emails = setPrimary(draftEmail, in: current.emails)
        u.phones = setPrimary(draftPhone, in: current.phones)
        u.addresses = setPrimary(draftAddress, in: current.addresses)
        people.updatePerson(u)
        editingIdentity = false
    }

    /// Replace the first value with `value` while keeping the rest; drop blanks.
    private func setPrimary(_ value: String, in arr: [String]) -> [String] {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = arr.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return (v.isEmpty ? [] : [v]) + Array(rest)
    }

    // MARK: - Compact header (P1, additive)

    /// P1 / 02 §4.1: full-width identity header for the de-tabbed canvas. One
    /// Primary CTA + one `⋯` overflow + a FlowLayout metadata row that wraps
    /// (R2 fit guardrail) instead of clipping. Not yet wired into `body` —
    /// P2 swaps `identityPanel`'s button rows for this; the canvas migration
    /// (P3-P6) puts it at the top of the scrolling column.
    @ViewBuilder
    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                MSAvatar(name: current.displayName, size: 56,
                         ringColor: healthRingColor(for: current, in: people))
                VStack(alignment: .leading, spacing: 3) {
                    // R1 fit guardrail: name truncates so Primary + overflow
                    // stay right-anchored on narrow canvases.
                    Text(current.displayName)
                        .scaledFont(24, weight: .heavy, relativeTo: .title, kind: .display)
                        .foregroundStyle(NDS.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                        .onTapGesture { beginIdentityEdit() }
                        .help("Click to edit name, role, and company")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .scaledFont(12.5)
                            .foregroundStyle(NDS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button { showBrief = true } label: {
                    Label("Brief Me", systemImage: "sparkles")
                }
                .buttonStyle(MSPrimaryButtonStyle())
                Menu {
                    Button { beginIdentityEdit() } label: {
                        Label("Edit name & role", systemImage: "pencil")
                    }
                    Button { showEdit = true } label: {
                        Label("Edit all fields…", systemImage: "square.and.pencil")
                    }
                    Button { showAddEncounter = true } label: {
                        Label("Log encounter", systemImage: "calendar.badge.plus")
                    }
                    Button { showAddRelationship = true } label: {
                        Label("Add relationship", systemImage: "person.2.badge.plus")
                    }
                    Button { showAddToMeeting = true } label: {
                        Label("Add to a meeting", systemImage: "calendar.badge.plus")
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete \(firstName)", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .scaledFont(13).foregroundStyle(NDS.textSecondary)
                        .frame(width: NDS.buttonIconSide, height: NDS.buttonIconSide)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .minTap()
                .help("More actions")
                .accessibilityLabel("More actions")
            }
            // R2 fit guardrail: multi-control metadata row uses FlowLayout so
            // it wraps to a second line instead of clipping.
            FlowLayout(spacing: 8) {
                relationshipTypePicker
                if let health = relationshipHealth { healthBadge(health) }
                if let since = knownSinceLine {
                    Text(since).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }

    // MARK: - Identity panel (left column)
    //
    // P2 (ux-audit-2026-06b): the action button rows + standalone
    // relationshipType/health block previously stacked inside this 300pt
    // column have been folded into `compactHeader` — one Primary + one ⋯
    // overflow + a FlowLayout metadata row. The identity column now leads
    // with the compact header, then the inline edit form (when editing),
    // then the rest of the panel sections stay unchanged.

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            compactHeader

            // Inline contact + bio editing (PPL-1) — quick edit of the primary
            // email/phone/address and the bio without opening the full sheet.
            if editingIdentity {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .scaledFont(15, weight: .semibold)
                        .onSubmit { saveIdentityEdit() }
                    TextField("Role", text: $draftRole)
                        .textFieldStyle(.roundedBorder).scaledFont(12)
                        .onSubmit { saveIdentityEdit() }
                    TextField("Company", text: $draftCompany)
                        .textFieldStyle(.roundedBorder).scaledFont(12)
                        .onSubmit { saveIdentityEdit() }
                    TextField("Email", text: $draftEmail)
                        .textFieldStyle(.roundedBorder).scaledFont(12)
                        .onSubmit { saveIdentityEdit() }
                    TextField("Phone", text: $draftPhone)
                        .textFieldStyle(.roundedBorder).scaledFont(12)
                        .onSubmit { saveIdentityEdit() }
                    TextField("Address", text: $draftAddress)
                        .textFieldStyle(.roundedBorder).scaledFont(12)
                        .onSubmit { saveIdentityEdit() }
                    TextField("About", text: $draftBio, axis: .vertical)
                        .textFieldStyle(.roundedBorder).scaledFont(12)
                        .lineLimit(2...5)
                    if current.emails.count > 1 || current.phones.count > 1 || current.addresses.count > 1 {
                        Text("Editing the first value — use ⋯ for all.")
                            .font(.caption2).foregroundStyle(NDS.textTertiary)
                    }
                    HStack(spacing: 6) {
                        Button { saveIdentityEdit() } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        .buttonStyle(MSPrimaryButtonStyle())
                        Button { editingIdentity = false } label: { Text("Cancel") }
                            .buttonStyle(MSSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    /// Phase 2 (2B) — normalized 0–100 connection health for typed
    /// relationships, computed from existing encounter/cadence data via the
    /// shared `VaultKit.RelationshipHealth` (same formula the MCP coach uses).
    private var relationshipHealth: RelationshipHealth? {
        guard current.relationshipType != .unset else { return nil }
        let encs = people.encounters(for: current.id)
        let dates = encs.map(\.date).sorted(by: >)
        let medianGap: Int = {
            guard dates.count >= 2 else { return 0 }
            var gaps = (0..<(dates.count - 1)).map { Int(dates[$0].timeIntervalSince(dates[$0 + 1]) / 86400) }
            gaps.sort()
            return gaps[gaps.count / 2]
        }()
        let last = dates.first ?? current.lastInteractionAt
        let daysSince = last.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 9_999
        let cadence = current.checkInCadenceDays ?? current.relationshipType.defaultCheckInDays
        return RelationshipHealth(daysSinceLast: daysSince, cadenceDays: cadence,
                                  encounterCount: encs.count, medianGapDays: medianGap)
    }

    private func healthColor(_ band: RelationshipHealth.Band) -> Color {
        switch band {
        case .thriving: return NDS.mint
        case .steady:   return NDS.sky
        case .drifting: return NDS.gold
        case .overdue:  return NDS.danger
        }
    }

    @ViewBuilder
    private func healthBadge(_ health: RelationshipHealth) -> some View {
        let color = healthColor(health.band)
        VStack(alignment: .leading, spacing: 4) {
            // C2-3: the badge is now a button that explains WHY + a next-best action.
            Button { showHealthWhy.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(NDS.small).imageScale(.small).foregroundStyle(color)
                    Text("Health \(health.score) · \(health.band.rawValue.capitalized)")
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    Image(systemName: "chevron.down").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHealthWhy, arrowEdge: .bottom) { healthWhyPopover(health) }
            .accessibilityLabel("Connection health \(health.score) out of 100, \(health.band.rawValue). Tap for details.")
            // C2-9: "Known since" line.
            if let since = knownSinceLine { Text(since).font(NDS.tiny).foregroundStyle(NDS.textTertiary) }
        }
    }

    /// First-met date = earliest encounter, else the record's creation date.
    private var firstMet: Date {
        people.encounters(for: current.id).map(\.date).min() ?? current.createdAt
    }

    /// "Known for 3 years · first met Mar 2022" (C2-9).
    private var knownSinceLine: String? {
        let days = Int(Date().timeIntervalSince(firstMet) / 86400)
        guard days >= 1 else { return nil }
        let dur: String
        if days >= 730 { dur = "Known for \(days / 365) years" }
        else if days >= 365 { dur = "Known for 1 year" }
        else if days >= 60 { dur = "Known for \(days / 30) months" }
        else { dur = "Known for \(days) days" }
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return "\(dur) · first met \(f.string(from: firstMet))"
    }

    /// C2-3: a plain-language breakdown of the health score + next-best action.
    @ViewBuilder
    private func healthWhyPopover(_ health: RelationshipHealth) -> some View {
        let encs = people.encounters(for: current.id)
        let last = encs.map(\.date).max() ?? current.lastInteractionAt
        let daysSince = last.map { Int(Date().timeIntervalSince($0) / 86400) }
        let cadence = current.checkInCadenceDays ?? current.relationshipType.defaultCheckInDays
        VStack(alignment: .leading, spacing: 8) {
            Text("Why \(health.score) · \(health.band.rawValue.capitalized)")
                .font(NDS.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                whyRow("clock", daysSince.map { "Last contact \($0)d ago (aim: every \(cadence)d)" } ?? "No contact logged yet")
                whyRow("repeat", "\(encs.count) encounter\(encs.count == 1 ? "" : "s") on record")
            }
            Divider()
            // Next-best action.
            let overdue = (daysSince ?? 9999) - cadence
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(NDS.brand)
                Text(overdue > 0 ? "Reach out — \(overdue)d overdue" : "On track — next check-in in \(-overdue)d")
                    .font(NDS.small)
            }
            Button { showHealthWhy = false; showAddEncounter = true } label: {
                Label("Log a check-in", systemImage: "plus.circle")
            }
            .buttonStyle(MSPrimaryButtonStyle())
        }
        .padding(14).frame(width: 260)
    }

    private func whyRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(NDS.tiny).foregroundStyle(NDS.textTertiary).frame(width: 14)
            Text(text).font(NDS.small).foregroundStyle(NDS.textSecondary)
        }
    }

    /// Compact relationship-type selector displayed in the identity panel.
    @ViewBuilder
    private var relationshipTypePicker: some View {
        HStack(spacing: 6) {
            Text("Relationship:")
                .font(NDS.small)
                .foregroundStyle(NDS.textSecondary)
            Menu {
                ForEach(RelationshipType.allCases, id: \.self) { rtype in
                    Button {
                        var updated = current
                        updated.relationshipType = rtype
                        people.updatePerson(updated)
                    } label: {
                        HStack {
                            Label(rtype.displayName, systemImage: rtype.symbol)
                            if current.relationshipType == rtype {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    RelationshipTypeChip(type: current.relationshipType)
                    Image(systemName: "chevron.down").scaledFont(9)
                        .foregroundStyle(NDS.textTertiary)
                }
                .msMenuButtonChrome()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Set relationship type — controls check-in cadence and coaching content")
            Spacer()
        }
    }

    // MARK: - Tags (inline add) + Favorites (inline add)

    /// Tags with an inline add field (P0-5) so tagging is one keystroke, not a
    /// menu → popover. Matches an existing people-tag by name, else creates one.
    private var tagsEditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            if !tags.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(tags) { t in
                        TagChip(tag: t, removable: true) { removeTag(t.id) }
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "tag").foregroundStyle(NDS.textTertiary)
                TextField("Add a tag — clients, family, an event…", text: $newTagName)
                    .textFieldStyle(.plain)
                    .onSubmit { commitTagEntry() }
                if !newTagName.isEmpty { MSInlineButton("Add") { commitTagEntry() } }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        }
    }

    private func addTag(_ tagID: String) {
        var u = current
        u.tagIDs.insert(tagID)
        people.updatePerson(u)
    }

    private func removeTag(_ tagID: String) {
        var u = current
        u.tagIDs.remove(tagID)
        people.updatePerson(u)
    }

    /// Inline tag add: reuse an existing people-tag whose name matches
    /// (case-insensitive), else create a new one, then attach — no menu/sheet.
    private func commitTagEntry() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !name.isEmpty else { return }
        if let existing = peopleTags.allTags.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            addTag(existing.id)
        } else {
            let tag = peopleTags.createTag(name: name)
            addTag(tag.id)
        }
    }

    /// Favorites with an inline add field so favorite things can be captured
    /// without the edit sheet.
    private var favoritesEditSection: some View {
        // P8: outer MSSection owns the eyebrow.
        VStack(alignment: .leading, spacing: 8) {
            if !current.favorites.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(current.favorites, id: \.self) { fav in
                        HStack(spacing: 4) {
                            Text(fav).font(NDS.small)
                            NotionIconButton(systemName: "xmark.circle.fill", help: "Remove favorite") {
                                removeFavorite(fav)
                            }
                            .minTap()
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(NDS.fieldBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 1))
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "heart").foregroundStyle(NDS.textTertiary)
                TextField("Add a favorite — coffee order, hobby, team…", text: $newFavorite)
                    .textFieldStyle(.plain)
                    .onSubmit { addFavorite() }
                if !newFavorite.isEmpty { MSInlineButton("Add") { addFavorite() } }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        }
    }

    private func addFavorite() {
        let v = newFavorite.trimmingCharacters(in: .whitespacesAndNewlines)
        newFavorite = ""
        guard !v.isEmpty else { return }
        var u = current
        if !u.favorites.contains(v) { u.favorites.append(v) }
        people.updatePerson(u)
    }

    private func removeFavorite(_ fav: String) {
        var u = current
        u.favorites.removeAll { $0 == fav }
        people.updatePerson(u)
    }

    // MARK: - AI suggestions (tags / relationships / encounters)

    private var aiSuggestionsSection: some View {
        // P8: outer MSSection owns the eyebrow.
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                if aiRunning {
                    ProgressView().controlSize(.small)
                } else {
                    MSInlineButton(aiSuggestions == nil ? "Suggest" : "Refresh", systemImage: "sparkles") {
                        Task { await generateAISuggestions() }
                    }
                }
            }

            if let err = aiError {
                Text(err).font(NDS.small).foregroundStyle(.red)
            }

            if let s = visibleSuggestions {
                if s.isEmpty {
                    Text("No new suggestions — this profile already looks well-organized.")
                        .font(NDS.small).foregroundStyle(NDS.textTertiary)
                } else {
                    // Tags
                    if !s.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tags").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            FlowLayout(spacing: 6) {
                                ForEach(s.tags, id: \.self) { name in
                                    suggestionChip(label: name, icon: "tag") { acceptTagSuggestion(name) }
                                }
                            }
                        }
                    }
                    // Relationships
                    if !s.relationships.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Relationships").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            ForEach(s.relationships, id: \.self) { rel in
                                suggestionRow(
                                    title: rel.name,
                                    detail: rel.label,
                                    actionLabel: matchedPerson(rel.name) == nil ? nil : "Link",
                                    disabledNote: matchedPerson(rel.name) == nil ? "not in People" : nil
                                ) { acceptRelationshipSuggestion(rel) }
                            }
                        }
                    }
                    // Encounters
                    if !s.encounters.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Encounters").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            ForEach(s.encounters, id: \.self) { enc in
                                suggestionRow(title: enc.title, detail: enc.note, actionLabel: "Log", disabledNote: nil) {
                                    acceptEncounterSuggestion(enc)
                                }
                            }
                        }
                    }
                }
            } else if !aiRunning {
                Text("Let AI propose tags, relationships, and encounters from this person's meetings and profile.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            }
        }
        .msCard(padding: 12)
    }

    /// Suggestions minus anything the user already accepted or dismissed.
    private var visibleSuggestions: PersonAISuggestions? {
        guard var s = aiSuggestions else { return nil }
        s.tags = s.tags.filter { name in
            !dismissedSuggestions.contains("tag:\(name)")
                && !current.tagIDs.contains(where: { peopleTags.tag(by: $0)?.name.caseInsensitiveCompare(name) == .orderedSame })
        }
        s.relationships = s.relationships.filter { !dismissedSuggestions.contains("rel:\($0.name)|\($0.label)") }
        s.encounters = s.encounters.filter { !dismissedSuggestions.contains("enc:\($0.title)") }
        return s
    }

    private func suggestionChip(label: String, icon: String, accept: @escaping () -> Void) -> some View {
        Button(action: accept) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill").scaledFont(11)
                Text(label).font(NDS.small)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(NDS.brand.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(NDS.brand.opacity(0.4), lineWidth: 1))
            .foregroundStyle(NDS.brand)
        }
        .buttonStyle(.plain)
        .help("Add “\(label)”")
    }

    @ViewBuilder
    private func suggestionRow(title: String, detail: String, actionLabel: String?,
                               disabledNote: String?, accept: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).scaledFont(13, weight: .medium)
                if !detail.isEmpty {
                    Text(detail).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let actionLabel {
                MSInlineButton(actionLabel) { accept() }
            } else if let disabledNote {
                Text(disabledNote).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(8)
        .background(NDS.bg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func matchedPerson(_ name: String) -> Person? {
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != current.displayName.lowercased() else { return nil }
        return people.people.first { $0.displayName.lowercased() == n }
            ?? people.people.first { $0.id != current.id && $0.displayName.lowercased().contains(n) }
    }

    private func acceptTagSuggestion(_ name: String) {
        let existing = peopleTags.allTags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let tag = existing ?? peopleTags.createTag(name: name)
        addTag(tag.id)
        dismissedSuggestions.insert("tag:\(name)")
    }

    private func acceptRelationshipSuggestion(_ rel: PersonAISuggestions.RelSuggestion) {
        if let other = matchedPerson(rel.name) {
            people.addRelationship(from: current.id, to: other.id, label: rel.label)
        }
        dismissedSuggestions.insert("rel:\(rel.name)|\(rel.label)")
    }

    private func acceptEncounterSuggestion(_ enc: PersonAISuggestions.EncSuggestion) {
        _ = people.addEncounter(to: current.id, eventName: enc.title, notes: enc.note)
        dismissedSuggestions.insert("enc:\(enc.title)")
    }

    /// Assemble the on-device context blob the model reasons over.
    private func personContextForAI() -> String {
        let p = current
        var lines: [String] = []
        lines.append("Name: \(p.displayName)")
        if !p.role.isEmpty { lines.append("Role: \(p.role)") }
        if !p.company.isEmpty { lines.append("Company: \(p.company)") }
        if !p.bio.isEmpty { lines.append("Notes: \(p.bio)") }
        let tagNames = tags.map { $0.name }
        if !tagNames.isEmpty { lines.append("Existing tags: \(tagNames.joined(separator: ", "))") }
        if !p.favorites.isEmpty { lines.append("Favorites: \(p.favorites.joined(separator: ", "))") }
        let rels = p.relationships.compactMap { r -> String? in
            guard let other = people.person(by: r.toPersonID) else { return nil }
            return "\(r.label): \(other.displayName)"
        }
        if !rels.isEmpty { lines.append("Existing relationships: \(rels.joined(separator: "; "))") }
        let encs = people.encounters(for: p.id).prefix(8).map { e in
            "\(Self.dateFormatter.string(from: e.date)) — \(e.eventName)\(e.notes.isEmpty ? "" : ": \(e.notes)")"
        }
        if !encs.isEmpty { lines.append("Encounters:\n- " + encs.joined(separator: "\n- ")) }
        // Recorded + calendar meetings this person was part of.
        let recorded = manager.pastMeetings.filter(attendeeMatches(_:)).prefix(10)
            .map { "\(Self.dateFormatter.string(from: $0.startDate)) — \($0.displayTitle)" }
        let cal = calendarMeetings.prefix(10)
            .map { "\(Self.dateFormatter.string(from: $0.startDate)) — \($0.displayTitle)" }
        let meetings = (recorded + cal)
        if !meetings.isEmpty { lines.append("Meetings together:\n- " + meetings.joined(separator: "\n- ")) }
        // Other people who appear in those meetings — candidates for relationships.
        let others = Set(manager.pastMeetings.filter(attendeeMatches(_:)).flatMap { $0.attendees })
            .prefix(20)
        if !others.isEmpty { lines.append("Other attendees seen with them: \(others.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    private func generateAISuggestions() async {
        aiError = nil
        aiRunning = true
        defer { aiRunning = false }
        let context = personContextForAI()
        let result = await PersonSuggestionEngine.generate(
            personName: current.displayName, context: context, using: OllamaService())
        if let result {
            aiSuggestions = result
            if result.isEmpty { aiError = nil }
        } else {
            aiError = "Couldn't generate suggestions. Make sure Ollama is running."
        }
    }

    // `personChatColumn` is gone — the global right-side ChatSidebar is the
    // single chat surface, scoped to this person via `updateChatContext()`.

    // MARK: - Meeting history

    /// True when `m` lists this person as an attendee. Resolved through the one
    /// identity layer (email-first, exact-name-second) — the old substring test
    /// matched "Dan" against every "Daniel" (P1-1).
    private func attendeeMatches(_ m: Meeting) -> Bool {
        m.attendees.contains { PersonResolver.resolve($0, in: [current]) == current.id }
    }

    /// Load unrecorded calendar meetings with this person over the last ~180
    /// days for the unified timeline (U2-1). Runs off the main actor.
    private func loadCalendarMeetings() async {
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -180, to: now) ?? now
        let all = await calendar.meetings(from: from, to: now, filterConferenceURLs: false)
        let mine = all.filter(attendeeMatches)
        await MainActor.run { self.calendarMeetings = mine }
    }

    /// Unified person timeline: recorded meetings (clickable) UNIONED with
    /// unrecorded calendar meetings, deduped, each badged. Previously this only
    /// showed recordings, so a manager's unrecorded 1:1s read empty. (U2-1, D1-5)
    /// Decisions from meetings this person is linked to — a cross-tab surface so
    /// commitments don't stay buried in one meeting's markdown. (V5, derived from
    /// meetingMentions — no model change.)
    @ViewBuilder
    private var decisionsSection: some View {
        let mine = decisions.decisions
            .filter { current.meetingMentions.contains($0.meetingID) }
            .sorted { $0.date > $1.date }
            .prefix(8)
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Decisions").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                ForEach(Array(mine)) { d in
                    Button {
                        NotificationCenter.default.post(
                            name: .meetingScribeOpenEntity, object: nil,
                            userInfo: ["url": WorkspaceLink.url(kind: .meeting, id: d.meetingID).absoluteString])
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal").scaledFont(13)
                                .foregroundStyle(NDS.brand.opacity(0.7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.text).scaledFont(13.5).foregroundStyle(NDS.textPrimary)
                                    .lineLimit(2)
                                Text("\(d.meetingTitle) · \(Self.dateFormatter.string(from: d.date))")
                                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var meetingHistorySection: some View {
        let recorded = manager.pastMeetings.filter(attendeeMatches)
        // Drop calendar meetings that line up with a recording (same ~minute).
        let recordedMinutes = Set(recorded.map { Int($0.startDate.timeIntervalSince1970 / 60) })
        let calOnly = calendarMeetings.filter {
            !recordedMinutes.contains(Int($0.startDate.timeIntervalSince1970 / 60))
        }
        let rows = (recorded.map { (meeting: $0, recorded: true) }
                    + calOnly.map { (meeting: $0, recorded: false) })
            .sorted { $0.meeting.startDate > $1.meeting.startDate }

        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    NotionEyebrow(text: "Meeting history", count: rows.count)
                    ForEach(Array(rows.prefix(30).enumerated()), id: \.offset) { _, row in
                        timelineRow(row.meeting, recorded: row.recorded)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ m: Meeting, recorded: Bool) -> some View {
        if recorded {
            // Clickable backlink → canonical Meetings-tab detail (D1-5).
            Button { router.openMeeting(m) } label: { timelineRowContent(m, recorded: true) }
                .buttonStyle(.plain)
        } else {
            // Calendar-only — no recording to open, so just informational.
            timelineRowContent(m, recorded: false)
        }
    }

    private func timelineRowContent(_ m: Meeting, recorded: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.displayTitle)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(NDS.textPrimary)
                Text(m.startDate, style: .date)
                    .scaledFont(11)
                    .foregroundStyle(NDS.textTertiary)
            }
            Spacer()
            Text(recorded ? "Recorded" : "Calendar")
                .scaledFont(9, weight: .semibold)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((recorded ? Color.green : NDS.textTertiary).opacity(0.15), in: Capsule())
                .foregroundStyle(recorded ? Color.green : NDS.textSecondary)
            if recorded {
                Image(systemName: "chevron.right")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contactRows: some View {
        let emails = current.emails.filter { !$0.isEmpty }
        let phones = current.phones.filter { !$0.isEmpty }
        let addresses = current.addresses.filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            NotionEyebrow(text: "Contact")
            ForEach(emails, id: \.self) { contactRow(icon: "envelope", text: $0) }
            ForEach(phones, id: \.self) { contactRow(icon: "phone", text: $0) }
            ForEach(addresses, id: \.self) { contactRow(icon: "mappin.and.ellipse", text: $0) }
            if let bday = current.birthday {
                contactRow(icon: "gift", text: Self.birthdayFormatter.string(from: bday))
            }
            addEmailControl
        }
    }

    /// Inline "+ Add email" (§4A) — appends a deduped email via the store service.
    private var addEmailControl: some View {
        MSInlineButton("Add email", systemImage: "plus") { showAddEmail = true }
        .popover(isPresented: $showAddEmail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add email").scaledFont(13, weight: .bold, relativeTo: .headline)
                TextField("name@company.com", text: $newEmailDraft)
                    .textFieldStyle(.roundedBorder).frame(width: 230)
                    .onSubmit(commitAddEmail)
                HStack {
                    Spacer()
                    Button("Cancel") { showAddEmail = false; newEmailDraft = "" }
                        .buttonStyle(MSSecondaryButtonStyle())
                    Button("Add") { commitAddEmail() }
                        .buttonStyle(MSPrimaryButtonStyle())
                        .disabled(newEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
        }
    }

    private func commitAddEmail() {
        let e = newEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return }
        if people.addEmail(e, to: current.id) == nil {
            ToastCenter.shared.show("That email is already on \(current.displayName)")
        }
        newEmailDraft = ""
        showAddEmail = false
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Photos").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                Spacer()
                MSInlineButton("Add", systemImage: "photo.badge.plus") { attachPhotos() }
            }
            if current.photoRelativePaths.isEmpty {
                Text("No photos yet. Add pictures exported from Apple Photos, Google Photos, or any file.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(current.photoRelativePaths, id: \.self) { rel in
                            photoThumb(rel)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func photoThumb(_ rel: String) -> some View {
        let url = people.photoURL(for: current, relativePath: rel)
        // Off-main decode + cache (E2-5 / V5 DI-2) — no synchronous decode on scroll.
        CachedThumbnail(url: url, side: 72)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(NDS.hairline, lineWidth: 1))
            .contextMenu {
                Button("Remove photo", role: .destructive) { people.removePhoto(rel, from: current.id) }
            }
    }

    @ViewBuilder
    private func contactRow(icon: String, text: String) -> some View {
        // Email/phone rows are now actionable — mailto: / tel: — instead of dead
        // text the user had to copy and switch apps to use. (A2/UX3-1)
        let url: URL? = {
            switch icon {
            case "envelope": return URL(string: "mailto:\(text)")
            case "phone":    return URL(string: "tel:\(text.filter { $0.isNumber || $0 == "+" })")
            default:         return nil
            }
        }()
        HStack(spacing: 8) {
            Image(systemName: icon).scaledFont(12).foregroundStyle(NDS.textTertiary).frame(width: 16)
            if let url {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text(text).font(NDS.body).foregroundStyle(NDS.brand)
                }
                .buttonStyle(.plain)
                .help(icon == "envelope" ? "Email \(text)" : "Call \(text)")
            } else {
                Text(text).font(NDS.body).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private var notes: some View {
        // P8: outer MSSection ("About") owns the eyebrow.
        VStack(alignment: .leading, spacing: 6) {
            Text(current.bio.isEmpty ? "No bio yet." : current.bio)
                .font(NDS.body)
                .foregroundStyle(current.bio.isEmpty ? NDS.textTertiary : NDS.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var encountersSection: some View {
        let mine = people.encounters(for: current.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Encounters").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                Spacer()
                checkInGoalMenu
            }
            if mine.isEmpty {
                Text("No encounters yet. Add where you met or last saw them.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                // D4-6 — 13-week consistency heat map + streak.
                EncounterHeatMap(dates: mine.map(\.date), goalDays: current.checkInGoalDays)
                ForEach(mine) { e in EncounterRow(encounter: e) { people.deleteEncounter(e) } }
            }
        }
    }

    /// P2-8 — per-person aspirational check-in goal. Distinct from the inferred
    /// cadence; shown as an annotation on the heat map.
    @ViewBuilder
    private var checkInGoalMenu: some View {
        let options: [Int?] = [nil, 3, 7, 14, 30, 60]
        Menu {
            ForEach(options.indices, id: \.self) { idx in
                let opt = options[idx]
                Button {
                    var updated = current
                    updated.checkInGoalDays = opt
                    people.updatePerson(updated)
                } label: {
                    HStack {
                        Text(opt.map { "Every \($0) days" } ?? "No goal")
                        if current.checkInGoalDays == opt {
                            Spacer(); Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(current.checkInGoalDays.map { "Goal: \($0)d" } ?? "Set goal",
                  systemImage: "target")
                .msMenuButtonChrome()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Set an aspirational check-in goal for this person")
    }

    // MARK: - Tasks (cross-tab: ActionItems owned by this person)

    /// T10 / 04 §4.5: one matcher across the whole app — `PersonResolver.taskBelongs`.
    /// Tightens the profile to exact resolution; legacy substring hits drop off
    /// (re-resolution on People mutation in T11 backfills the real link).
    private var personTasks: [ActionItem] {
        actionItems.items
            .filter { PersonResolver.taskBelongs($0, to: current) }
            .sorted { lhs, rhs in
                let lDone = lhs.status == .completed, rDone = rhs.status == .completed
                if lDone != rDone { return !lDone }   // open first
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
    }

    private func addTaskForPerson() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let item = actionItems.createTask(title: title)
        actionItems.setOwnerPerson(item.id, personID: current.id, ownerName: current.displayName)
        newTaskTitle = ""
    }

    private var tasksSection: some View {
        let mine = personTasks
        // P8 (ux-audit-2026-06b §D1): outer MSSection owns the eyebrow + count.
        return VStack(alignment: .leading, spacing: 8) {
            // Quick add — assigns this person as owner so it shows up here and in
            // the Actions tab.
            HStack(spacing: 8) {
                Image(systemName: "plus.circle").foregroundStyle(NDS.textTertiary)
                TextField("Add a task for \(current.displayName.split(separator: " ").first.map(String.init) ?? current.displayName)…",
                          text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit { addTaskForPerson() }
                if !newTaskTitle.isEmpty {
                    MSInlineButton("Add") { addTaskForPerson() }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))

            if mine.isEmpty {
                Text("No tasks assigned to \(current.displayName) yet. Assign them as a task owner here or in the Actions tab.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                commitmentLedger(mine)
            }
        }
    }

    /// 2-C: per-person commitment ledger. Splits this person's tasks into what
    /// you're waiting on them for (delegated + open) and their other open work,
    /// so the owe/owed picture is visible without leaving the profile.
    @ViewBuilder
    private func commitmentLedger(_ tasks: [ActionItem]) -> some View {
        let firstName = current.displayName.split(separator: " ").first.map(String.init) ?? current.displayName
        let waitingOn = tasks.filter { $0.delegated == true && $0.status != .completed }
        let theirOpen = tasks.filter { $0.delegated != true && $0.status != .completed }
        let done = tasks.filter { $0.status == .completed }
        VStack(alignment: .leading, spacing: 10) {
            if !waitingOn.isEmpty {
                ledgerGroup("Waiting on \(firstName)", icon: "hourglass", tint: NDS.gold, items: waitingOn)
            }
            if !theirOpen.isEmpty {
                ledgerGroup("\(firstName)'s open items", icon: "circle", tint: NDS.textTertiary, items: theirOpen)
            }
            if !done.isEmpty {
                ledgerGroup("Completed", icon: "checkmark.circle.fill", tint: NDS.brand, items: done)
            }
        }
    }

    @ViewBuilder
    private func ledgerGroup(_ title: String, icon: String, tint: Color, items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).scaledFont(11).foregroundStyle(tint)
                Text(title).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Text("\(items.count)").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            ForEach(items) { item in taskRow(item) }
        }
    }

    @ViewBuilder
    private func taskRow(_ item: ActionItem) -> some View {
        let done = item.status == .completed
        HStack(spacing: 10) {
            Button {
                actionItems.setStatus(item.id, status: done ? .open : .completed)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .scaledFont(15)
                    .foregroundStyle(done ? NDS.brand : NDS.textTertiary)
            }
            .buttonStyle(.plain)
            .minTap()

            Button {
                router.route(kind: .actionItem, id: item.id, manager: manager)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .scaledFont(13.5, weight: .medium)
                        .strikethrough(done, color: NDS.textTertiary)
                        .foregroundStyle(done ? NDS.textTertiary : NDS.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let due = item.dueDate {
                            Label(Self.dateFormatter.string(from: due), systemImage: "calendar")
                                .font(NDS.tiny)
                                .foregroundStyle(due < Date() && !done ? .red : NDS.textTertiary)
                        }
                        if !item.meetingTitle.isEmpty {
                            // T3: jump to the source meeting (nested plain button is
                            // hit-tested before the row's task-open button).
                            if !item.meetingID.isEmpty, let m = manager.meeting(id: item.meetingID) {
                                Button { router.openMeeting(m) } label: {
                                    Label(item.meetingTitle, systemImage: "mic")
                                        .font(NDS.tiny).foregroundStyle(NDS.brand).lineLimit(1)
                                }
                                .buttonStyle(.plain).help("Open \(item.meetingTitle)")
                            } else {
                                Label(item.meetingTitle, systemImage: "mic")
                                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Image(systemName: "chevron.right").scaledFont(10).foregroundStyle(NDS.textTertiary)
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
    }

    private var relationshipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Relationships").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                Spacer()
                MSInlineButton("Add", systemImage: "plus") { showAddRelationship = true }
                    .disabled(people.people.count < 2)
            }
            if current.relationships.isEmpty {
                Text("No relationships yet. Link family, colleagues, or friends.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                ForEach(current.relationships) { rel in
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill").scaledFont(12)
                            .foregroundStyle(NDS.brand.opacity(0.7))
                        Text(rel.label).font(NDS.small).foregroundStyle(NDS.textSecondary)
                        Text(people.person(by: rel.toPersonID)?.displayName ?? "Unknown")
                            .scaledFont(13.5, weight: .semibold)
                        Spacer(minLength: 0)
                        NotionIconButton(systemName: "xmark.circle.fill", help: "Remove relationship") {
                            people.removeRelationship(rel, from: current.id)
                        }
                        .minTap()
                    }
                    .padding(10)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                }
            }
            weeklyRelationshipPrompt
        }
    }

    /// Phase 3 (relationship-coach): a rotating, type-aware connection prompt
    /// drawn from `RelationshipPromptLibrary`. Only shows for the close personal
    /// relationship types that have curated prompts.
    @ViewBuilder
    private var weeklyRelationshipPrompt: some View {
        if let prompt = RelationshipPromptLibrary.weeklyPrompt(for: current.relationshipType) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .scaledFont(11, weight: .semibold).foregroundStyle(NDS.brand)
                    Text("This week's prompt")
                        .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                }
                Text(prompt).font(NDS.small).foregroundStyle(NDS.textPrimary)
            }
            .padding(10)
            .background(NDS.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: NDS.radius))
        }
    }

    // MARK: - In common (C2-8)

    /// Co-attendees pulled from the people graph's edge data: who else sat in
    /// meetings with this person, ranked by how many they shared. Answers "who
    /// else knows them?" / "who should join this meeting?" on the profile. Hidden
    /// entirely for isolated contacts (no rows → no empty box).
    @ViewBuilder
    private var inCommonSection: some View {
        if !inCommon.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill").scaledFont(11)
                        .foregroundStyle(NDS.brand.opacity(0.7))
                    Text("In common").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                }
                ForEach(inCommon) { entry in
                    Button { router.openPerson(entry.person.id) } label: {
                        HStack(spacing: 10) {
                            MSAvatar(name: entry.person.displayName, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.person.displayName)
                                    .scaledFont(13.5, weight: .semibold)
                                    .foregroundStyle(NDS.textPrimary)
                                Text("\(entry.count) meeting\(entry.count == 1 ? "" : "s") together")
                                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").scaledFont(10)
                                .foregroundStyle(NDS.textTertiary)
                        }
                        .padding(10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .ndsHover()
                }
            }
        }
    }

    /// Builds the people graph once and resolves this person's meeting-sharing
    /// edges into ranked rows. Runs in a `.task` (off the render path) because
    /// the graph build + force layout is too heavy to repeat in `body`.
    @MainActor
    private func computeInCommon() {
        let vm = PeopleGraphViewModel()
        vm.buildGraph(from: people.people)
        let rows: [InCommonPerson] = vm.edges(for: current.id).compactMap { edge in
            guard edge.sharedMeetingCount > 0,
                  let otherID = edge.other(than: current.id),
                  let p = people.person(by: otherID) else { return nil }
            return InCommonPerson(person: p, count: edge.sharedMeetingCount)
        }
        .sorted { $0.count > $1.count }
        inCommon = Array(rows.prefix(8))
    }

    /// Backlinks (Phase B): meetings whose transcript mentions this person.
    private var mentionedInSection: some View {
        let meetings = current.meetingMentions
            .compactMap { manager.meeting(forEntityID: $0) }
            .sorted { $0.startDate > $1.startDate }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Mentioned in").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            if meetings.isEmpty {
                Text("\(current.meetingMentions.count) meeting(s) — open the Meetings tab to view.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                ForEach(meetings) { m in
                    HStack(spacing: 8) {
                        Button {
                            NotificationCenter.default.post(
                                name: .meetingScribeOpenEntity, object: nil,
                                userInfo: ["url": WorkspaceLink.url(kind: .meeting, id: m.id).absoluteString])
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar").scaledFont(13)
                                    .foregroundStyle(NDS.brand.opacity(0.7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.displayTitle).scaledFont(13.5, weight: .semibold).lineLimit(1)
                                    Text(Self.dateFormatter.string(from: m.startDate))
                                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // §8.2 — one-tap "log this meeting as an encounter".
                        if !hasEncounter(forMeeting: m.id) {
                            NotionIconButton(systemName: "plus.circle", help: "Log this meeting as an encounter") {
                                people.addEncounter(to: current.id, eventName: m.displayTitle,
                                                    date: m.startDate, meetingID: m.id)
                            }
                            .minTap()
                        }
                    }
                }
            }
        }
    }

    private func hasEncounter(forMeeting id: String) -> Bool {
        people.encounters(for: current.id).contains { $0.meetingID == id }
    }

    // MARK: - Evidence compiler (U1-4)

    // MARK: - Reconnect with context (C2-4)

    /// The newest encounter's topic — its freeform note, falling back to the
    /// denormalized event name. Nil when there's no usable text.
    private var lastEncounterTopic: String? {
        guard let enc = people.encounters(for: current.id).max(by: { $0.date < $1.date })
        else { return nil }
        let note = enc.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        let name = enc.eventName.strippingLeadingEmoji().trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The title of the most recent recorded meeting this person attended.
    private var lastMeetingTitle: String? {
        guard let mtg = manager.pastMeetings.filter(attendeeMatches).max(by: { $0.startDate < $1.startDate })
        else { return nil }
        let t = mtg.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Days since the last contact (newest encounter, else `lastInteractionAt`).
    private var daysSinceLastContact: Int? {
        let last = people.encounters(for: current.id).map(\.date).max() ?? current.lastInteractionAt
        return last.map { max(0, Int(Date().timeIntervalSince($0) / 86400)) }
    }

    /// C2-4 — Reconnect with context. For an overdue/drifting relationship, show
    /// what you last talked about and offer a one-tap, locally-drafted opener so
    /// the real blocker ("what do I even say?") disappears. 100% on-device.
    @ViewBuilder
    private var reconnectSection: some View {
        if let health = relationshipHealth, health.band == .overdue || health.band == .drifting {
            let color = healthColor(health.band)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.wave.fill").imageScale(.small).foregroundStyle(color)
                    Text("Reconnect").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    Spacer()
                    if let days = daysSinceLastContact {
                        Text("\(days)d since last contact")
                            .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    }
                    Text(health.band.rawValue.capitalized)
                        .font(NDS.tiny).foregroundStyle(color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.14)))
                }
                // Last-topic context.
                if lastEncounterTopic != nil || lastMeetingTitle != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        if let topic = lastEncounterTopic {
                            reconnectContextRow("text.bubble", "Last note", topic)
                        }
                        if let mtg = lastMeetingTitle {
                            reconnectContextRow("calendar", "Last meeting", mtg)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                } else {
                    Text("No recent topic on record — a simple \"thinking of you\" still lands.")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
                // One-tap, on-device draft.
                HStack(spacing: 8) {
                    Button { draftReconnectOpener() } label: {
                        Label(reconnectDrafting ? "Drafting…" : "Draft an opener", systemImage: "sparkles")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                    .disabled(reconnectDrafting || !manager.ollamaReachable)
                    if reconnectDrafting { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if !manager.ollamaReachable {
                    Text("Local AI is offline — start it to draft a warm opener on-device.")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
                if let err = reconnectError {
                    Text(err).font(NDS.tiny).foregroundStyle(NDS.danger)
                }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .leading) {
                // Subtle left accent stripe instead of a full bordered card.
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
            .padding(.leading, 10)
            .sheet(isPresented: $showReconnectDraft) { reconnectDraftSheet }
        }
    }

    @ViewBuilder
    private func reconnectContextRow(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).scaledFont(11).foregroundStyle(NDS.textTertiary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Text(value).font(NDS.body).foregroundStyle(NDS.textPrimary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
    }

    /// The sheet that shows the drafted opener with a Copy button.
    private var reconnectDraftSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Opener for \(firstName)").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reconnectDraft, forType: .string)
                    ToastCenter.shared.show("Copied")
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(MSSecondaryButtonStyle())
                    .disabled(reconnectDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Done") { showReconnectDraft = false }
                    .buttonStyle(MSSecondaryButtonStyle())
            }
            .padding(12)
            Divider().overlay(NDS.divider)
            ScrollView {
                Text(reconnectDraft.isEmpty ? "…" : reconnectDraft)
                    .font(NDS.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            Text("Drafted on-device · grounded in your last topic. Edit before sending.")
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                .padding(.horizontal, 14).padding(.bottom, 12)
        }
        .frame(minWidth: 460, maxWidth: 460, minHeight: 360)
        .background(NDS.bg)
    }

    /// Build a context-grounded prompt and ask the local model for a short, warm
    /// reconnect opener. Gracefully surfaces an error line if the model is down.
    private func draftReconnectOpener() {
        guard !reconnectDrafting else { return }
        reconnectError = nil
        reconnectDrafting = true
        let name = firstName
        let relation = current.relationshipType.displayName.lowercased()
        let days = daysSinceLastContact
        let topicEnc = lastEncounterTopic
        let topicMtg = lastMeetingTitle
        Task {
            var ctx = ""
            if let days { ctx += "It's been about \(days) days since we last connected.\n" }
            if let topicEnc { ctx += "Last note from our last encounter: \(topicEnc)\n" }
            if let topicMtg { ctx += "Most recent meeting we shared: \(topicMtg)\n" }
            if ctx.isEmpty { ctx = "We haven't talked in a while and I don't have notes on our last topic.\n" }
            let prompt = """
            Write a short, warm message to reconnect with \(name), who is my \(relation). \
            Use ONLY the context below — do not invent specifics. Reference what we last \
            talked about if it's given. Keep it to 2–3 friendly sentences, casual and \
            genuine, no subject line, no sign-off, no preamble — just the message text.

            CONTEXT:
            \(ctx)
            """
            do {
                let result = try await OllamaService().generate(prompt: prompt, temperature: 0.6)
                let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    reconnectDrafting = false
                    guard !cleaned.isEmpty else {
                        reconnectError = "The local model returned an empty draft — try again."
                        return
                    }
                    reconnectDraft = cleaned
                    showReconnectDraft = true
                }
            } catch {
                await MainActor.run {
                    reconnectDrafting = false
                    reconnectError = "Couldn't reach the local model. Make sure it's running and try again."
                }
            }
        }
    }

    private var evidenceSection: some View {
        // P8: outer MSSection owns the eyebrow.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { showEvidence = true } label: {
                    Label("Compile last 6 months", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                Spacer()
            }
            Text("A deterministic summary of meetings, decisions, completed work, and check-ins — no AI, instant.")
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
        }
        .sheet(isPresented: $showEvidence) { evidenceSheet }
    }

    private var evidenceSheet: some View {
        let text = personEvidenceText()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Evidence — \(current.displayName)").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    ToastCenter.shared.show("Evidence copied")
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(MSSecondaryButtonStyle())
                Button("Done") { showEvidence = false }
                    .buttonStyle(MSSecondaryButtonStyle())
            }
            .padding(12)
            Divider()
            ScrollView { Text(text).font(NDS.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14) }
        }
        .frame(minWidth: 520, maxWidth: 520, minHeight: 560)
    }

    /// Deterministic 6-month evidence pack (U1-4) — meetings, decisions,
    /// completed work, and check-ins. No LLM, no wait.
    private func personEvidenceText() -> String {
        let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? .distantPast
        let f = DateFormatter(); f.dateStyle = .medium
        let meetings = manager.pastMeetings
            .filter { attendeeMatches($0) && $0.startDate >= cutoff }
            .sorted { $0.startDate > $1.startDate }
        let meetingIDs = Set(meetings.map(\.id))
        let decisionLines = decisions.decisions
            .filter { meetingIDs.contains($0.meetingID) }
            .map { "- \($0.text)" }
        let doneTasks = actionItems.items
            .filter { $0.ownerPersonID == current.id && $0.status == .completed && (($0.completedAt ?? $0.updatedAt) >= cutoff) }
            .map { "- \($0.title)" }
        let encs = people.encounters(for: current.id)
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }

        var out = "# Evidence — \(current.displayName) (last 6 months)\n"
        if !current.role.isEmpty || !current.company.isEmpty {
            out += [current.role, current.company].filter { !$0.isEmpty }.joined(separator: " · ") + "\n"
        }
        out += "\n## Meetings (\(meetings.count))\n"
        out += meetings.prefix(30).map { "- \(f.string(from: $0.startDate)) — \($0.displayTitle)" }.joined(separator: "\n")
        out += "\n\n## Decisions (\(decisionLines.count))\n" + (decisionLines.isEmpty ? "- (none recorded)" : decisionLines.joined(separator: "\n"))
        out += "\n\n## Completed work (\(doneTasks.count))\n" + (doneTasks.isEmpty ? "- (none recorded)" : doneTasks.joined(separator: "\n"))
        out += "\n\n## Check-ins (\(encs.count))\n"
        out += encs.prefix(30).map { "- \(f.string(from: $0.date)) — \($0.eventName)" }.joined(separator: "\n")
        return out
    }

    // MARK: - Discuss next time (U1-5)

    private var talkingPointsSection: some View {
        // P8: outer MSSection owns the eyebrow.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Add a talking point to raise next time…", text: $newTalkingPoint)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTalkingPoint)
                MSInlineButton("Add") { addTalkingPoint() }
                    .disabled(newTalkingPoint.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(Array(current.talkingPoints.enumerated()), id: \.offset) { idx, point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bubble.left.fill").scaledFont(11)
                        .foregroundStyle(NDS.gold.opacity(0.8)).padding(.top, 2)
                    Text(point).font(NDS.body).frame(maxWidth: .infinity, alignment: .leading)
                    Button { removeTalkingPoint(at: idx) } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(NDS.mint)
                    }
                    .buttonStyle(.plain)
                    .minTap()
                    .help("Done — remove this point")
                }
                .padding(10)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            }
        }
    }

    private func addTalkingPoint() {
        let text = newTalkingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var updated = current
        updated.talkingPoints.append(text)
        people.updatePerson(updated)
        newTalkingPoint = ""
    }

    private func removeTalkingPoint(at idx: Int) {
        var updated = current
        guard idx < updated.talkingPoints.count else { return }
        updated.talkingPoints.remove(at: idx)
        people.updatePerson(updated)
    }

    // MARK: - Memories

    private var memoriesSection: some View {
        // P8: outer MSSection owns the eyebrow.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Add a memory — \"loves single-origin coffee\"", text: $newMemory)
                    .textFieldStyle(.roundedBorder)
                    .focused($memoryFieldFocused)
                    .onSubmit(addMemory)
                MSInlineButton("Add") { addMemory() }
                    .disabled(newMemory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(current.memories) { m in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").scaledFont(12)
                        .foregroundStyle(NDS.brand.opacity(0.7)).padding(.top, 2)
                    Text(m.text).font(NDS.body).frame(maxWidth: .infinity, alignment: .leading)
                    NotionIconButton(systemName: "xmark.circle.fill", help: "Delete memory") {
                        people.deleteMemory(m, from: current.id)
                    }
                    .minTap()
                }
                .padding(10)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            }
        }
    }

    // MARK: - iMessage analysis

    private var messagesSection: some View {
        // P8: outer MSSection owns the eyebrow.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if analyzingMessages {
                    ProgressView().controlSize(.small)
                } else {
                    // Pick WHAT to analyze instead of forcing all-time history.
                    // P2: "Scan" loads the message stats for a window; the LLM
                    // "Analyze…" inside the card is a separate step — distinct
                    // labels so the two aren't confused.
                    Menu {
                        ForEach(MessagesAnalyzer.MessageWindow.presets, id: \.self) { window in
                            Button(window.label) { analyzeMessages(scope: window) }
                        }
                    } label: {
                        Label("Scan", systemImage: "message")
                            .msMenuButtonChrome()
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            if let err = messageError {
                Text(err).font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else if let s = messageStats {
                VStack(alignment: .leading, spacing: 6) {
                    statRow("Window", messageWindow.label)
                    statRow("Total", "\(s.total)  ·  \(s.sent) sent / \(s.received) received")
                    if let last = s.lastDate { statRow("Last message", Self.dateFormatter.string(from: last)) }
                    statRow("Recent", "\(s.last30) in 30d  ·  \(s.last90) in 90d")
                    if s.total >= 4 { analysisPresetMenu }
                    analysisResultView
                    if s.total >= 1 { deepAnalysisControl }
                }
                .padding(10)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            } else {
                Text("Match this person's email/phone to your iMessage history (needs Full Disk Access).")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            }
        }
        .sheet(isPresented: $showCustomPrompt) { customPromptSheet }
    }

    /// Menu of analysis presets — one click runs the prompt, output
    /// renders below with a "Save to notes" action. Each preset has a
    /// "Recent 1000 messages" submenu item (the default) and an "All
    /// time (cache and save)" item that persists the result so we don't
    /// pay the LLM cost again. When a cached all-time note already
    /// exists, the menu item changes to "Refresh all-time" so the user
    /// can rerun deliberately.
    private var analysisPresetMenu: some View {
        HStack(spacing: 6) {
            MSInlineButton("Analyze…", systemImage: "sparkles") { showAnalyzePopover = true }
                .popover(isPresented: $showAnalyzePopover, arrowEdge: .bottom) { analyzePopover }
            if let running = analysisRunning {
                ProgressView().controlSize(.small)
                Text("Running: \(running.label)…")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.top, 2)
    }

    /// Structured Analyze popover (§4C): choose the analysis kind and the time
    /// range, then run. Replaces the old nested preset→scope menu.
    private var analyzePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analyze messages").scaledFont(15, weight: .bold, relativeTo: .headline)

            NotionEyebrow(text: "What to analyze")
            VStack(alignment: .leading, spacing: 1) {
                ForEach(ConversationAnalysisPreset.allCases) { preset in
                    Button { analyzePreset = preset } label: {
                        HStack(spacing: 9) {
                            Image(systemName: analyzePreset == preset ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(analyzePreset == preset ? NDS.accent : NDS.textTertiary)
                            Image(systemName: preset.systemImage).frame(width: 16)
                                .foregroundStyle(NDS.textSecondary)
                            Text(preset.label).foregroundStyle(NDS.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .scaledFont(13)
                        .padding(.vertical, 5).padding(.horizontal, 6)
                        .background(analyzePreset == preset ? NDS.accentSoft : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if analyzePreset == .custom {
                TextField("Custom instruction…", text: $customPromptDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4).font(NDS.small)
            }

            Divider().overlay(NDS.divider)

            NotionEyebrow(text: "Time range")
            FlowLayout(spacing: 6) {
                ForEach(AnalyzeRange.allCases) { range in
                    let active = analyzeRange == range
                    Button { analyzeRange = range } label: {
                        Text(range.label)
                            .scaledFont(11.5, weight: .bold, relativeTo: .caption)
                            .foregroundStyle(active ? NDS.onAccent : NDS.textSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(active ? AnyShapeStyle(NDS.accentGradient)
                                              : AnyShapeStyle(NDS.surface2), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                showAnalyzePopover = false
                if analyzePreset == .custom,
                   customPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showCustomPrompt = true
                } else {
                    runAnalysis(analyzePreset, range: analyzeRange)
                }
            } label: {
                Label("Run analysis", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(MSPrimaryButtonStyle())
        }
        .padding(16)
        .frame(width: 320)
    }

    /// The most recent analysis output (if any), with a save-to-notes
    /// affordance. Shown inline so the user can read it without context-
    /// switching.
    @ViewBuilder
    private var analysisResultView: some View {
        if let output = analysisOutput {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: output.preset.systemImage).font(NDS.tiny)
                    Text(output.preset.label.uppercased())
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    Spacer()
                    MSInlineButton("Save to notes", systemImage: "square.and.arrow.down") {
                        saveAnalysisToNotes(output)
                    }
                    NotionIconButton(systemName: "xmark", help: "Dismiss analysis output") {
                        analysisOutput = nil
                    }
                    .minTap()
                }
                Text(output.body)
                    .font(NDS.small)
                    .foregroundStyle(NDS.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(NDS.brand.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: NDS.radius))
            .padding(.top, 4)
        }
    }

    /// Sheet for the "Custom prompt…" preset. Lets the user type any
    /// instruction — we substitute the transcript and run it.
    private var customPromptSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom analysis prompt").font(.headline)
            Text("Ask anything about the recent conversation. The messages will be appended as context automatically.")
                .font(NDS.small).foregroundStyle(.secondary)
            TextEditor(text: $customPromptDraft)
                .font(.body)
                .frame(minHeight: 120)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: NDS.radius).stroke(.separator))
            HStack {
                Spacer()
                Button("Cancel") { showCustomPrompt = false }
                    .buttonStyle(MSSecondaryButtonStyle())
                Button("Run") {
                    showCustomPrompt = false
                    runAnalysis(.custom)
                }
                .buttonStyle(MSPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(customPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    /// Renders the per-person AttachedNote list — saved chat analyses,
    /// each with a kind chip, timestamp, body, and inline delete.
    private var attachedNotesSection: some View {
        // P8: outer MSSection owns the eyebrow + count.
        VStack(alignment: .leading, spacing: 8) {
            if current.attachedNotes.isEmpty {
                Text("Saved analyses — relationship summaries, sentiment trends, etc. Run an analysis below and click \"Save to notes\".")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                ForEach(current.attachedNotes) { note in
                    attachedNoteRow(note)
                }
            }
        }
    }

    private func attachedNoteRow(_ note: AttachedNote) -> some View {
        let expanded = noteExpansion[note.id] ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(note.title).font(NDS.body).fontWeight(.medium)
                Text(note.kind.uppercased())
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(NDS.fieldBg, in: Capsule())
                Spacer()
                Text(Self.dateFormatter.string(from: note.createdAt))
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                NotionIconButton(systemName: expanded ? "chevron.up" : "chevron.down",
                                 help: expanded ? "Collapse" : "Expand") {
                    noteExpansion[note.id] = !expanded
                }
                .minTap()
                NotionIconButton(systemName: "trash", help: "Delete saved analysis") {
                    people.deleteAttachedNote(note, from: current.id)
                    noteExpansion.removeValue(forKey: note.id)
                }
                .minTap()
            }
            if expanded {
                Text(note.body)
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(note.body)
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(NDS.tiny).foregroundStyle(NDS.textTertiary).frame(width: 100, alignment: .leading)
            Text(value).font(NDS.small)
        }
    }

    @ViewBuilder
    private var provenanceFooter: some View {
        if !current.importSources.isEmpty {
            Text("Sources: " + current.importSources.sorted().joined(separator: ", "))
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
        }
    }

    // MARK: - Actions

    private func addMemory() {
        let text = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        people.addMemory(to: current.id, text: text)
        newMemory = ""
    }

    private func attachPhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose photos of \(current.displayName)"
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            people.attachPhoto(to: current.id, data: data, ext: url.pathExtension)
        }
    }

    private func analyzeMessages(scope: MessagesAnalyzer.MessageWindow = .allTime) {
        analyzingMessages = true
        messageError = nil
        messageWindow = scope
        // Reset any prior preset output so the user knows the stats
        // refresh isn't carrying stale analysis text.
        analysisOutput = nil
        let target = current
        Task.detached(priority: .userInitiated) {
            do {
                let (stats, _) = try MessagesAnalyzer.analyze(person: target, scope: scope)
                await MainActor.run { self.messageStats = stats; self.analyzingMessages = false }
            } catch {
                await MainActor.run {
                    self.messageError = error.localizedDescription
                    self.analyzingMessages = false
                }
            }
        }
    }

    /// Push the current person's identity into the chat's pageContext.
    /// The chat sidebar's system prompt already templates pageContext
    /// into the "where the user is right now" block, so this gives the
    /// model everything it needs to default to this person when the user
    /// asks ambiguous follow-ups ("what about next week's trip?").
    private func updateChatContext() {
        let p = current
        let bits: [String] = [
            "Person tab — viewing \(p.displayName) (id: \(p.id)).",
            p.role.isEmpty ? "" : "Role: \(p.role).",
            p.company.isEmpty ? "" : "Company: \(p.company).",
            p.primaryEmail.isEmpty ? "" : "Email: \(p.primaryEmail).",
            p.primaryPhone.isEmpty ? "" : "Phone: \(p.primaryPhone).",
            "When the user asks anything ambiguous, default to this person — use the id above as the `id` argument to get_person / get_person_messages / list_person_meetings / attach_note_to_person."
        ]
        chatSession.setContext(bits.filter { !$0.isEmpty }.joined(separator: " "),
                               label: p.displayName)
    }

    /// Run a briefing prompt in the embedded chat column, grounded on this person.
    private func askAIAboutPerson() {
        updateChatContext()
        let q = "Give me a briefing on \(current.displayName): recent meetings and "
            + "interactions, any open tasks, and what I should follow up on."
        Task { await chatSession.sendUserMessage(q) }
    }

    /// Run one of the conversation analysis presets. For `.custom`,
    /// prompts the user for a free-text instruction first; everything
    /// else runs immediately. `scope` defaults to "recent 1000" — the
    /// last 1000 messages regardless of date, so it works even for
    /// contacts you haven't texted in a while. The "All time" scope
    /// runs over the FULL conversation and persists the result as an
    /// AttachedNote (kind "summary-all" etc.) so the user doesn't pay
    /// the LLM cost again unless they explicitly refresh.
    private func runAnalysis(_ preset: ConversationAnalysisPreset,
                             range: AnalyzeRange = .recent1000) {
        if preset == .custom,
           customPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showCustomPrompt = true
            return
        }
        analysisRunning = preset
        analysisOutput = nil
        let target = current
        let customDraft = customPromptDraft
        let isAllTime = (range == .allTime)
        Task.detached(priority: .utility) {
            // Pull messages within the chosen window, capped by count. Date
            // windows scope by time; recent-1000 / all-time are count-based so a
            // sporadic contact still gives the model context.
            guard let (_, recent) = try? MessagesAnalyzer.analyze(
                    person: target, recentLimit: range.recentLimit, scope: range.window) else {
                await MainActor.run { self.analysisRunning = nil }
                return
            }
            // Truncate the rendered transcript to a model-friendly size.
            // All-time uses a bigger budget because the user opted into the
            // slower run.
            let transcriptBudget = isAllTime ? 32_000 : 8_000
            let transcript = recent.map { "\($0.fromMe ? "Me" : target.displayName): \($0.text)" }
                .joined(separator: "\n")
                .prefix(transcriptBudget)
            // C2-4 — distress pre-flight guard. For intimate relationships,
            // never hand crisis/harm content to the model for clinical-style
            // analysis; surface supportive resources instead and stop here.
            if target.relationshipType.supportsDepthContent,
               let category = DistressFilter.scan(String(transcript)) {
                await MainActor.run {
                    self.analysisRunning = nil
                    self.analysisOutput = AnalysisOutput(
                        preset: preset,
                        body: DistressFilter.supportiveMessage(for: category),
                        promptUsed: "")
                }
                return
            }
            let prompt = preset.template(personName: target.displayName,
                                         customPrompt: customDraft,
                                         relationshipType: target.relationshipType)
                .replacingOccurrences(of: "PROMPT_BODY", with: String(transcript))
            // Larger num_ctx for the all-time run so qwen2.5:7b can
            // actually read everything we hand it; smaller for recent.
            let numCtx = isAllTime ? 16_384 : 8_192
            let result = (try? await OllamaService().generate(prompt: prompt,
                                                              temperature: 0.2,
                                                              numCtx: numCtx)) ?? ""
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.analysisRunning = nil
                guard !cleaned.isEmpty else { return }
                if isAllTime {
                    // All-time analyses persist directly — that's the whole
                    // point: pay the cost once, cache the result.
                    let title = preset.noteTitle(for: target.displayName) + " (all-time)"
                    self.people.deleteCachedAllTimeNote(personID: target.id,
                                                        kind: preset.noteKind + "-all")
                    self.people.addAttachedNote(to: target.id,
                                                title: title,
                                                body: cleaned,
                                                kind: preset.noteKind + "-all")
                } else {
                    self.analysisOutput = AnalysisOutput(preset: preset,
                                                         body: cleaned,
                                                         promptUsed: prompt)
                }
            }
        }
    }

    /// The one cached "deep analysis" report (kind "deep-all"), if it exists.
    private var deepNote: AttachedNote? { current.attachedNotes.first { $0.kind == "deep-all" } }

    /// A thorough one-time pass over the WHOLE message history: writes a full
    /// report to Notes (cached, run-once) and mines tags/encounters from the
    /// actual message content into the AI suggestions card.
    @ViewBuilder
    private var deepAnalysisControl: some View {
        Divider().overlay(NDS.divider)
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(NDS.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text("Deep analysis").font(NDS.small).foregroundStyle(NDS.textPrimary)
                Text(deepNote == nil
                     ? "One thorough pass over the entire history — cached, runs once."
                     : "Saved to Notes · \(Self.dateFormatter.string(from: deepNote!.createdAt))")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            Spacer(minLength: 0)
            if deepRunning {
                ProgressView().controlSize(.small)
            } else {
                MSInlineButton(deepNote == nil ? "Run" : "Refresh") { runDeepMessageAnalysis() }
            }
        }
    }

    private func runDeepMessageAnalysis() {
        deepRunning = true
        messageError = nil
        let target = current
        Task.detached(priority: .utility) {
            guard let (_, recent) = try? MessagesAnalyzer.analyze(person: target, recentLimit: 100_000),
                  !recent.isEmpty else {
                await MainActor.run {
                    self.deepRunning = false
                    self.messageError = "No matched messages to analyze."
                }
                return
            }
            let transcript = String(recent
                .map { "\($0.fromMe ? "Me" : target.displayName): \($0.text)" }
                .joined(separator: "\n").prefix(48_000))
            let ollama = OllamaService()
            let reportPrompt = """
            You are analyzing the COMPLETE text-message history between me and \
            \(target.displayName). Write a thorough but concise Markdown report with \
            these sections: ## Relationship overview, ## Communication style & cadence, \
            ## Recurring topics, ## Notable moments & commitments, ## Suggested follow-ups. \
            Base everything strictly on the messages — do not invent facts.

            MESSAGES:
            \(transcript)
            """
            let report = (try? await ollama.generate(prompt: reportPrompt,
                                                     temperature: 0.2, numCtx: 16_384)) ?? ""
            let cleaned = report.trimmingCharacters(in: .whitespacesAndNewlines)
            // Mine structured tags/encounters from the real message content.
            let mined = await PersonSuggestionEngine.generate(
                personName: target.displayName,
                context: "These are real text messages between me and \(target.displayName):\n"
                    + String(transcript.prefix(16_000)),
                using: ollama)
            await MainActor.run {
                self.deepRunning = false
                if !cleaned.isEmpty {
                    self.people.deleteCachedAllTimeNote(personID: target.id, kind: "deep-all")
                    self.people.addAttachedNote(
                        to: target.id,
                        title: "Deep message analysis — \(target.displayName)",
                        body: cleaned, kind: "deep-all")
                }
                if let mined { self.mergeSuggestions(mined) }
            }
        }
    }

    private func mergeSuggestions(_ s: PersonAISuggestions) {
        var base = aiSuggestions ?? PersonAISuggestions()
        for t in s.tags where !base.tags.contains(t) { base.tags.append(t) }
        let relKeys = Set(base.relationships.map { "\($0.name)|\($0.label)" })
        base.relationships += s.relationships.filter { !relKeys.contains("\($0.name)|\($0.label)") }
        let encKeys = Set(base.encounters.map { $0.title })
        base.encounters += s.encounters.filter { !encKeys.contains($0.title) }
        aiSuggestions = base
    }

    /// Whether an all-time analysis exists for this person + preset.
    /// Lets the UI swap the menu item between "Run" and "Refresh" so
    /// the user knows when they're paying the cost again.
    private func cachedAllTimeNote(for preset: ConversationAnalysisPreset) -> AttachedNote? {
        let kind = preset.noteKind + "-all"
        return current.attachedNotes.first { $0.kind == kind }
    }

    /// Persist the in-view analysis output as an AttachedNote on this
    /// person. Title is derived from the preset + person name so the
    /// notes section reads naturally without a save dialog.
    private func saveAnalysisToNotes(_ output: AnalysisOutput) {
        let title = output.preset.noteTitle(for: current.displayName)
        people.addAttachedNote(to: current.id,
                               title: title,
                               body: output.body,
                               kind: output.preset.noteKind)
        // Clear the inline result so the new note in the Notes section
        // is the canonical version the user works with from here.
        analysisOutput = nil
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    private static let birthdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM d"; return f
    }()
}

@available(macOS 14.0, *)
private struct EncounterRow: View {
    let encounter: Encounter
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    /// Mood parsed out of the legacy "[mood:x]" note serialization (C2-6).
    private var parsedMood: Encounter.Mood? {
        guard let r = encounter.notes.range(of: #"\[mood:([a-z]+)\]"#, options: .regularExpression) else { return nil }
        let token = encounter.notes[r].dropFirst(6).dropLast(1)
        return Encounter.Mood(rawValue: String(token))
    }
    /// The note with the "[mood:x]" marker stripped, so it never shows raw.
    private var cleanNotes: String {
        encounter.notes
            .replacingOccurrences(of: #"\s*\[mood:[a-z]+\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Event name with any leading emoji stripped (C2-7). New encounters persist
    /// the plain kind ("Call"); older rows stored "📞 Call", "📅 Meeting", etc. —
    /// strip a leading emoji glyph so both render as clean typed text.
    private var displayEventName: String {
        encounter.eventName.strippingLeadingEmoji()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.and.ellipse").scaledFont(13)
                .foregroundStyle(NDS.brand.opacity(0.7)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayEventName).scaledFont(13.5, weight: .semibold)
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: encounter.date))
                    if let loc = encounter.location, !loc.isEmpty { Text("· \(loc)") }
                    // C2-6: mood as a first-class chip, parsed out of the note
                    // instead of the raw "[mood:x]" string leaking into the UI.
                    if let mood = parsedMood {
                        Text("\(mood.emoji) \(mood.label)")
                            .scaledFont(10, weight: .medium)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(NDS.surface2, in: Capsule())
                    }
                }
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                if !cleanNotes.isEmpty {
                    Text(cleanNotes).font(NDS.small).foregroundStyle(NDS.textSecondary)
                }
            }
            Spacer(minLength: 0)
            NotionIconButton(systemName: "xmark.circle.fill", help: "Delete encounter") {
                onDelete()
            }
            .minTap()
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
    }
}

/// Pick another person + label to create a (bidirectional) relationship.
@available(macOS 14.0, *)
private struct AddRelationshipSheet: View {
    @EnvironmentObject var people: PeopleStore
    @Environment(\.dismiss) private var dismiss

    let personID: String
    @State private var label = ""
    @State private var query = ""
    @State private var selectedID: String?

    private var candidates: [Person] {
        people.filteredPeople(query: query, tagID: nil, includeGhosts: true)
            .filter { $0.id != personID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Relationship").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(MSSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(MSPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID == nil || label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                TextField("Relationship (spouse, manager, friend…)", text: $label)
                    .textFieldStyle(.roundedBorder)
                TextField("Search people…", text: $query)
                    .textFieldStyle(.roundedBorder)
                List(candidates, selection: $selectedID) { p in
                    Text(p.displayName).tag(p.id)
                }
                .frame(minHeight: 220)
            }
            .padding(12)
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: 420)
    }

    private func save() {
        guard let selectedID else { return }
        people.addRelationship(from: personID, to: selectedID,
                               label: label.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

// MARK: - C2-7 emoji tolerance

extension String {
    /// Drops a single leading emoji glyph (and any following whitespace) from a
    /// stored string. Older encounters persisted their kind as "📞 Call",
    /// "📅 Meeting", "✉️ Follow-up"; new writes store the plain text. This lets
    /// both render as clean typed text without a destructive migration (C2-7).
    func strippingLeadingEmoji() -> String {
        guard let scalar = unicodeScalars.first,
              scalar.properties.isEmoji,
              scalar.value > 0x238C   // skip ASCII digits / # / * that are emoji-capable
        else { return self }
        return String(dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}
