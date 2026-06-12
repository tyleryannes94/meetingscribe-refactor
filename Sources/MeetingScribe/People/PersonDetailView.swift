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
    @State private var showAddRelationship = false
    @State private var confirmDelete = false
    @State private var newMemory = ""
    @State private var newTaskTitle = ""
    @State private var newFavorite = ""
    @State private var showNewTag = false
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
        case overview, meetings, tasks, messages, notes
        var label: String {
            switch self {
            case .overview: return "Overview"
            case .meetings: return "Meetings"
            case .tasks:    return "Tasks"
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

    var body: some View {
        // One scrollable page of sections (no tabs) on the left so everything is
        // visible at once, with the AI chat embedded as a persistent right column
        // instead of a toggled rail.
        HSplitView {
            // Two-pane detail (§4): fixed identity/contact pane + tabbed work area.
            detailPane
                .frame(minWidth: 560, idealWidth: 760)
                .background(NDS.bg)

            personChatColumn
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updateChatContext() }
        .onChange(of: current.id) { _, _ in updateChatContext() }
        .task(id: current.id) { await loadCalendarMeetings() }
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
        .frame(width: 420, height: 460)
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
    private var detailPane: some View {
        HStack(spacing: 0) {
            identityPane
                .frame(width: 300)
                .background(NDS.sidebarBg)
            Divider().overlay(NDS.divider)
            workArea
                .frame(maxWidth: .infinity)
        }
    }

    /// Always-present summary of the person (§4A): identity, tags, contact,
    /// relationships, cadence/encounters, photos. Scrolls on its own.
    private var identityPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identityPanel
                tagsEditSection
                contactRows
                relationshipsSection
                encountersSection
                if !current.photoRelativePaths.isEmpty { photosSection }
            }
            .padding(.horizontal, 16)
            .padding(.top, NDS.splitPaneTopInset)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Right pane: pill tab bar (§4B) + the selected tab's content.
    private var workArea: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: NDS.splitPaneTopInset)
            HStack {
                MSPillTabs(tabs: PersonTab.allCases.map { ($0, $0.label) }, selection: $personTab)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
            Divider().overlay(NDS.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    workContent
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.18), value: personTab)
            }
        }
        .background(NDS.bg)
    }

    @ViewBuilder
    private var workContent: some View {
        switch personTab {
        case .overview:
            if !current.bio.isEmpty || editingIdentity { notes }
            favoritesEditSection
            aiSuggestionsSection
            provenanceFooter
        case .meetings:
            Button { showAddToMeeting = true } label: {
                Label("Add \(firstName) to a meeting", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(MSSecondaryButtonStyle())
            meetingHistorySection
            if !current.meetingMentions.isEmpty { mentionedInSection }
            decisionsSection
        case .tasks:
            tasksSection
        case .messages:
            messagesSection
        case .notes:
            memoriesSection
            attachedNotesSection
        }
    }

    // MARK: - Section jump-rail (U3, legacy — superseded by the work-area tabs)

    /// Chips for the present sections; tapping scrolls the profile to that anchor.
    @ViewBuilder
    private func sectionNav(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sectionNavItems, id: \.id) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(item.id, anchor: .top)
                        }
                    } label: {
                        Text(item.label)
                            .font(NDS.tiny)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(NDS.fieldBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 1))
                            .foregroundStyle(NDS.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sectionNavItems: [(id: String, label: String)] {
        var items: [(id: String, label: String)] = [(id: "nav-tags", label: "Tags")]
        let hasContact = !current.emails.filter { !$0.isEmpty }.isEmpty
            || !current.phones.filter { !$0.isEmpty }.isEmpty
            || !current.addresses.filter { !$0.isEmpty }.isEmpty
            || current.birthday != nil
        if hasContact { items.append((id: "nav-contact", label: "Contact")) }
        items.append(contentsOf: [
            (id: "nav-ai", label: "Suggestions"),
            (id: "nav-relationships", label: "Relationships"),
            (id: "nav-encounters", label: "Encounters"),
            (id: "nav-meetings", label: "Meetings"),
            (id: "nav-tasks", label: "Tasks"),
            (id: "nav-notes", label: "Notes"),
            (id: "nav-messages", label: "Messages"),
        ])
        return items
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

    // MARK: - Identity panel (left column)

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Avatar + name
            HStack(alignment: .center, spacing: 12) {
                MSAvatar(name: current.displayName, size: 56)
                if editingIdentity {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .scaledFont(15, weight: .semibold)
                            .onSubmit { saveIdentityEdit() }
                        TextField("Role", text: $draftRole)
                            .textFieldStyle(.roundedBorder)
                            .scaledFont(12)
                            .onSubmit { saveIdentityEdit() }
                        TextField("Company", text: $draftCompany)
                            .textFieldStyle(.roundedBorder)
                            .scaledFont(12)
                            .onSubmit { saveIdentityEdit() }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.displayName)
                            .scaledFont(22, weight: .heavy, relativeTo: .title, kind: .display)
                            .foregroundStyle(NDS.textPrimary)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .scaledFont(12)
                                .foregroundStyle(NDS.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { beginIdentityEdit() }
                    .help("Click to edit name, role, and company")
                }
            }

            // Inline contact + bio editing (PPL-1) — quick edit of the primary
            // email/phone/address and the bio without opening the full sheet.
            if editingIdentity {
                VStack(alignment: .leading, spacing: 6) {
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
                }
            }

            // Action buttons
            if editingIdentity {
                HStack(spacing: 6) {
                    Button { saveIdentityEdit() } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(MSPrimaryButtonStyle())
                    Button { editingIdentity = false } label: { Text("Cancel") }
                        .buttonStyle(MSSecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 6) {
                    Button { beginIdentityEdit() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                    Button { showEdit = true } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                    .help("Edit all fields — email, phone, address, tags…")
                    .accessibilityLabel("Edit all fields")
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                    .accessibilityLabel("Delete person")
                }
                // Always-visible add affordances so logging an encounter or
                // adding the FIRST relationship doesn't require navigating away
                // or waiting for a section to appear. (UX3-4/A8)
                HStack(spacing: 6) {
                    Button { showAddEncounter = true } label: {
                        Label("Encounter", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.borderless).font(NDS.small)
                    Button { showAddRelationship = true } label: {
                        Label("Relationship", systemImage: "person.2.badge.plus")
                    }
                    .buttonStyle(.borderless).font(NDS.small)
                    // Open the chat rail grounded on this person — the page context
                    // is already set via updateChatContext(). (cross-tab)
                    Button { askAIAboutPerson() } label: {
                        Label("Ask AI", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless).font(NDS.small)
                    Spacer()
                }
                .padding(.top, 2)
            }
        // Relationship type row — always visible; tapping cycles through types
        // or opens a compact picker. Hidden during active identity editing to
        // keep the form focused.
        if !editingIdentity {
            relationshipTypePicker
            if let health = relationshipHealth {
                healthBadge(health)
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
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(NDS.small)
                .imageScale(.small)
                .foregroundStyle(color)
            Text("Health \(health.score) · \(health.band.rawValue.capitalized)")
                .font(NDS.small)
                .foregroundStyle(NDS.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .help("Connection health blends recency vs. cadence, how often you log encounters, and consistency.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection health \(health.score) out of 100, \(health.band.rawValue)")
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
                            Text("\(rtype.emoji) \(rtype.displayName)")
                            if current.relationshipType == rtype {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current.relationshipType.emoji)
                    Text(current.relationshipType.displayName)
                        .font(NDS.small)
                        .foregroundStyle(current.relationshipType == .unset ? NDS.textTertiary : NDS.textPrimary)
                    Image(systemName: "chevron.down").scaledFont(9)
                        .foregroundStyle(NDS.textTertiary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .help("Set relationship type — controls check-in cadence and coaching content")
            Spacer()
        }
    }

    // MARK: - Tags (inline add) + Favorites (inline add)

    /// Tags with an always-present "Add tag" menu so tagging doesn't require the
    /// full edit sheet. Lists existing people-tags and offers to create a new one.
    private var tagsEditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                Spacer()
                Menu {
                    let unused = peopleTags.allTags.filter { !current.tagIDs.contains($0.id) }
                    if !unused.isEmpty {
                        ForEach(unused) { t in
                            Button(t.name) { addTag(t.id) }
                        }
                        Divider()
                    }
                    Button("New tag…") { showNewTag = true }
                } label: {
                    Label("Add tag", systemImage: "plus")
                }
                .menuStyle(.borderlessButton).fixedSize().font(NDS.small)
            }
            if tags.isEmpty {
                Text("No tags yet. Use Add tag to group this person (clients, family, an event…).")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(tags) { t in
                        TagChip(tag: t, removable: true) { removeTag(t.id) }
                    }
                }
            }
        }
        .alert("New tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagName = "" }
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

    private func commitNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !name.isEmpty else { return }
        let tag = peopleTags.createTag(name: name)
        addTag(tag.id)
    }

    /// Favorites with an inline add field so favorite things can be captured
    /// without the edit sheet.
    private var favoritesEditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorite things").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            if !current.favorites.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(current.favorites, id: \.self) { fav in
                        HStack(spacing: 4) {
                            Text(fav).font(NDS.small)
                            Button { removeFavorite(fav) } label: {
                                Image(systemName: "xmark.circle.fill").scaledFont(11)
                            }
                            .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
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
                if !newFavorite.isEmpty { Button("Add") { addFavorite() }.font(NDS.small) }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI suggestions", systemImage: "wand.and.stars")
                    .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                Spacer()
                if aiRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await generateAISuggestions() }
                    } label: {
                        Label(aiSuggestions == nil ? "Suggest" : "Refresh", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless).font(NDS.small)
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
                Button(actionLabel, action: accept).font(NDS.small)
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

    // MARK: - Embedded chat (replaces the toggled sidebar rail)

    private var personChatColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(NDS.brand)
                Text("Ask AI about \(current.displayName.split(separator: " ").first.map(String.init) ?? current.displayName)")
                    .scaledFont(13, weight: .semibold)
                Spacer()
                if !chatSession.messages.isEmpty {
                    Button { chatSession.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                        .help("Clear conversation")
                }
            }
            .padding(.horizontal, 14).padding(.top, NDS.splitPaneTopInset).padding(.bottom, 10)
            .background(NDS.sidebarBg)
            Divider().overlay(NDS.divider)
            ChatPanel(
                session: chatSession,
                density: .compact,
                examplePrompts: [
                    "Give me a briefing on \(current.displayName).",
                    "What are my open tasks with them?",
                    "Suggest tags and a relationship for this person.",
                    "When did we last meet and what about?"
                ]
            )
        }
        .background(NDS.sidebarBg)
    }

    // MARK: - Meeting history (right column, Meetings tab)

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

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.circle.fill")
                .scaledFont(48).foregroundStyle(NDS.brand.opacity(0.7))
            VStack(alignment: .leading, spacing: 3) {
                Text(current.displayName).font(NDS.pageTitle)
                if !subtitle.isEmpty {
                    Text(subtitle).font(NDS.body).foregroundStyle(NDS.textSecondary)
                }
            }
            Spacer()
            Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var tagRow: some View {
        HStack(spacing: 6) {
            ForEach(tags) { t in TagChip(tag: t, removable: false, onRemove: nil) }
        }
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
        Button { showAddEmail = true } label: {
            Label("Add email", systemImage: "plus").font(NDS.tiny)
        }
        .buttonStyle(.borderless).foregroundStyle(NDS.accent)
        .popover(isPresented: $showAddEmail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add email").scaledFont(13, weight: .bold, relativeTo: .headline)
                TextField("name@company.com", text: $newEmailDraft)
                    .textFieldStyle(.roundedBorder).frame(width: 230)
                    .onSubmit(commitAddEmail)
                HStack {
                    Spacer()
                    Button("Cancel") { showAddEmail = false; newEmailDraft = "" }
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
                Button { attachPhotos() } label: { Label("Add", systemImage: "photo.badge.plus") }
                    .buttonStyle(.borderless).font(NDS.small)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            Text(current.bio).font(NDS.body).foregroundStyle(NDS.textPrimary)
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
                Button { showAddEncounter = true } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(.borderless).font(NDS.small)
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
        }
        .menuStyle(.borderlessButton)
        .font(NDS.small)
        .help("Set an aspirational check-in goal for this person")
    }

    // MARK: - Tasks (cross-tab: ActionItems owned by this person)

    /// Lowercased tokens that an ActionItem.owner string can match this person by:
    /// full name, first name, and any email.
    private func ownerTokens(_ p: Person) -> Set<String> {
        var t = Set<String>()
        let name = p.displayName.lowercased().trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            t.insert(name)
            if let first = name.split(separator: " ").first { t.insert(String(first)) }
        }
        for e in p.emails {
            let el = e.lowercased().trimmingCharacters(in: .whitespaces)
            if !el.isEmpty { t.insert(el) }
        }
        return t
    }

    private func ownerMatchesPerson(_ item: ActionItem) -> Bool {
        // Exact hard link wins; otherwise fall back to owner-string matching for
        // legacy tasks that predate the Person link.
        if let pid = item.ownerPersonID { return pid == current.id }
        guard let owner = item.owner?.lowercased().trimmingCharacters(in: .whitespaces),
              !owner.isEmpty else { return false }
        let tokens = ownerTokens(current)
        // Exact token match, or the owner string contains the full name.
        if tokens.contains(owner) { return true }
        let full = current.displayName.lowercased().trimmingCharacters(in: .whitespaces)
        return full.split(separator: " ").count > 1 && owner.contains(full)
    }

    private var personTasks: [ActionItem] {
        actionItems.items
            .filter { ownerMatchesPerson($0) }
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                if !mine.isEmpty {
                    Text("\(mine.filter { $0.status != .completed }.count) open")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
                Spacer()
            }
            // Quick add — assigns this person as owner so it shows up here and in
            // the Actions tab.
            HStack(spacing: 8) {
                Image(systemName: "plus.circle").foregroundStyle(NDS.textTertiary)
                TextField("Add a task for \(current.displayName.split(separator: " ").first.map(String.init) ?? current.displayName)…",
                          text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit { addTaskForPerson() }
                if !newTaskTitle.isEmpty {
                    Button("Add") { addTaskForPerson() }.font(NDS.small)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))

            if mine.isEmpty {
                Text("No tasks assigned to \(current.displayName) yet. Assign them as a task owner here or in the Actions tab.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                ForEach(mine) { item in taskRow(item) }
            }
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
            .buttonStyle(.borderless)

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
                            Label(item.meetingTitle, systemImage: "mic")
                                .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
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
                Button { showAddRelationship = true } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(.borderless).font(NDS.small)
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
                        Button { people.removeRelationship(rel, from: current.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                    }
                    .padding(10)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                }
            }
        }
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
                            Button {
                                people.addEncounter(to: current.id, eventName: m.displayTitle,
                                                    date: m.startDate, meetingID: m.id)
                            } label: { Image(systemName: "plus.circle") }
                                .buttonStyle(.borderless)
                                .help("Log this meeting as an encounter")
                                .accessibilityLabel("Log this meeting as an encounter")
                        }
                    }
                }
            }
        }
    }

    private func hasEncounter(forMeeting id: String) -> Bool {
        people.encounters(for: current.id).contains { $0.meetingID == id }
    }

    // MARK: - Memories

    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memories").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            HStack(spacing: 6) {
                TextField("Add a memory — \"loves single-origin coffee\"", text: $newMemory)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addMemory)
                Button("Add", action: addMemory)
                    .disabled(newMemory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(current.memories) { m in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").scaledFont(12)
                        .foregroundStyle(NDS.brand.opacity(0.7)).padding(.top, 2)
                    Text(m.text).font(NDS.body).frame(maxWidth: .infinity, alignment: .leading)
                    Button { people.deleteMemory(m, from: current.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                }
                .padding(10)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            }
        }
    }

    // MARK: - iMessage analysis

    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Messages").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                Spacer()
                if analyzingMessages {
                    ProgressView().controlSize(.small)
                } else {
                    // Pick WHAT to analyze instead of forcing all-time history.
                    Menu {
                        ForEach(MessagesAnalyzer.MessageWindow.presets, id: \.self) { window in
                            Button(window.label) { analyzeMessages(scope: window) }
                        }
                    } label: {
                        Label("Analyze", systemImage: "message")
                    }
                    .menuStyle(.borderlessButton).fixedSize().font(NDS.small)
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
            Button { showAnalyzePopover = true } label: {
                Label("Analyze…", systemImage: "sparkles")
            }
            .buttonStyle(.borderless).font(NDS.small)
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
                    Button {
                        saveAnalysisToNotes(output)
                    } label: { Label("Save to notes", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.borderless).font(NDS.tiny)
                    Button {
                        analysisOutput = nil
                    } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).font(NDS.tiny)
                        .help("Dismiss")
                        .accessibilityLabel("Dismiss analysis output")
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
                Button("Run") {
                    showCustomPrompt = false
                    runAnalysis(.custom)
                }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                Spacer()
                if !current.attachedNotes.isEmpty {
                    Text("\(current.attachedNotes.count)")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
            }
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
                Button {
                    noteExpansion[note.id] = !expanded
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless).font(NDS.tiny)
                Button(role: .destructive) {
                    people.deleteAttachedNote(note, from: current.id)
                    noteExpansion.removeValue(forKey: note.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).font(NDS.tiny)
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
        chatSession.setContext(bits.filter { !$0.isEmpty }.joined(separator: " "))
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
                Button(deepNote == nil ? "Run" : "Refresh") { runDeepMessageAnalysis() }
                    .font(NDS.small)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.and.ellipse").scaledFont(13)
                .foregroundStyle(NDS.brand.opacity(0.7)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(encounter.eventName).scaledFont(13.5, weight: .semibold)
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: encounter.date))
                    if let loc = encounter.location, !loc.isEmpty { Text("· \(loc)") }
                }
                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                if !encounter.notes.isEmpty {
                    Text(encounter.notes).font(NDS.small).foregroundStyle(NDS.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Button { onDelete() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(NDS.textTertiary)
                .accessibilityLabel("Delete encounter")
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
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
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
        .frame(width: 420, height: 420)
    }

    private func save() {
        guard let selectedID else { return }
        people.addRelationship(from: personID, to: selectedID,
                               label: label.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
