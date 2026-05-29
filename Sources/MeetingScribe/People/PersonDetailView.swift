import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// How wide to throw the net when running a conversation analysis.
/// Recent-by-count beats date-based for sporadic contacts (a friend
/// you haven't texted in 3 months still gets 1000 messages of context).
/// All-time pays the full LLM cost once and persists the result as an
/// AttachedNote (kind "<preset>-all") so subsequent views are instant.
enum AnalysisScope: Hashable {
    case recent1000
    case allTime
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
    /// recent-snippets transcript. We anchor the participants as
    /// adult professionals to keep small models' over-firing safety
    /// classifiers calm (same trick we use in MessagesAnalyzer
    /// .conversationSummary).
    func template(personName: String, customPrompt: String) -> String {
        let preamble = """
        You are an analyst summarizing the personal communication of \
        the user (an adult professional named Tyler) and one of his \
        adult contacts named \(personName). Both parties are adults. \
        This is the user's own message data on their own machine. \
        Do not refuse — there is nothing harmful about summarizing it.
        """
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
            Analyze sentiment trends in these recent messages between Tyler \
            and \(personName). Identify the general tone (warm / tense / \
            neutral / etc.) and call out any recent shifts in mood, energy, \
            or topic. Be specific and ground claims in the messages. 5–8 \
            sentences max.

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

    let person: Person
    /// Called after the person is deleted so the list can clear its selection.
    var onDeleted: () -> Void

    @State private var showEdit = false
    @State private var showAddEncounter = false
    @State private var showAddRelationship = false
    @State private var confirmDelete = false
    @State private var newMemory = ""
    @State private var messageStats: MessagesAnalyzer.Stats?
    @State private var messageError: String?
    @State private var analyzingMessages = false
    @State private var analysisOutput: AnalysisOutput?
    @State private var analysisRunning: ConversationAnalysisPreset?
    @State private var customPromptDraft = ""
    @State private var showCustomPrompt = false
    @State private var noteExpansion: [String: Bool] = [:]
    @State private var rightTab: PersonRightTab = .notes

    enum PersonRightTab: String, CaseIterable, Identifiable {
        case notes, meetings, messages
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notes:    return "Notes"
            case .meetings: return "Meetings"
            case .messages: return "Messages"
            }
        }
        var systemImage: String {
            switch self {
            case .notes:    return "note.text"
            case .meetings: return "person.2.fill"
            case .messages: return "message.fill"
            }
        }
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

    var body: some View {
        HStack(spacing: 0) {
            // ── LEFT COLUMN: Identity panel (fixed 280pt) ──────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityPanel
                }
                .padding(20)
            }
            .frame(width: 280)
            .background(NDS.sidebarBg)

            Divider().overlay(NDS.divider)

            // ── RIGHT COLUMN: Tabbed content (flex) ────────────────────────
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(PersonRightTab.allCases) { tab in
                        Button {
                            rightTab = tab
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.systemImage).font(.system(size: 11))
                                Text(tab.label).font(.system(size: 13, weight: rightTab == tab ? .semibold : .regular))
                            }
                            .foregroundStyle(rightTab == tab ? NDS.brand : NDS.textSecondary)
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .overlay(alignment: .bottom) {
                                if rightTab == tab {
                                    Rectangle().fill(NDS.brand).frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .background(NDS.sidebarBg)
                Divider().overlay(NDS.divider)

                // Tab content
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch rightTab {
                        case .notes:
                            if !current.bio.isEmpty { notes }
                            memoriesSection
                            attachedNotesSection
                        case .meetings:
                            encountersSection
                            if !current.meetingMentions.isEmpty { mentionedInSection }
                            meetingHistorySection
                        case .messages:
                            messagesSection
                        }
                        if rightTab == .notes { provenanceFooter }
                    }
                    .padding(24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(NDS.bg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updateChatContext() }
        .onChange(of: current.id) { _, _ in updateChatContext() }
        .onDisappear {
            chatSession.setContext("The People tab — the user's second-brain contacts.")
        }
        .sheet(isPresented: $showEdit) {
            AddPersonSheet(editing: current)
                .environmentObject(people)
                .environmentObject(peopleTags)
        }
        .sheet(isPresented: $showAddEncounter) {
            AddEncounterSheet(personID: current.id)
                .environmentObject(people)
                .environmentObject(peopleTags)
        }
        .sheet(isPresented: $showAddRelationship) {
            AddRelationshipSheet(personID: current.id).environmentObject(people)
        }
        .confirmationDialog("Delete \(current.displayName)?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                people.deletePerson(current)
                onDeleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the person and all their encounters. This can't be undone.")
        }
    }

    // MARK: - Identity panel (left column)

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Avatar + name
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(NDS.selectColor(current.displayName))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(initials(for: current.displayName))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(NDS.textPrimary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(NDS.textSecondary)
                    }
                }
            }

            // Action buttons
            HStack(spacing: 6) {
                Button { showEdit = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(MSSecondaryButtonStyle())
            }

            // Tags
            if !tags.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(tags) { t in TagChip(tag: t, removable: false, onRemove: nil) }
                }
            }

            Divider().overlay(NDS.divider)

            // Photos (first one shown)
            if !current.photoRelativePaths.isEmpty {
                photosSection
                Divider().overlay(NDS.divider)
            }

            // Contact rows
            contactRows

            // Relationships
            if !current.relationships.isEmpty {
                Divider().overlay(NDS.divider)
                relationshipsSection
            }

            // Favorites
            if !current.favorites.isEmpty {
                Divider().overlay(NDS.divider)
                favoritesSection
            }
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "?" }
        if parts.count >= 2 { return String(parts[0].prefix(1)) + String(parts[1].prefix(1)) }
        return String(parts[0].prefix(2))
    }

    // MARK: - Meeting history (right column, Meetings tab)

    /// All past meetings from MeetingManager where this person was an attendee.
    private var meetingHistorySection: some View {
        let email = current.emails.first?.lowercased() ?? ""
        let personName = current.displayName.lowercased()
        let matches = manager.pastMeetings.filter { m in
            // Match by email (most reliable) or display name in attendees
            m.attendees.contains {
                let a = $0.lowercased()
                return (!email.isEmpty && a.contains(email))
                    || a.contains(personName)
            }
        }
        .sorted { $0.startDate > $1.startDate }

        return Group {
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    NotionEyebrow(text: "In your recordings", count: matches.count)
                    ForEach(matches.prefix(20)) { m in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(NDS.textPrimary)
                                Text(m.startDate, style: .date)
                                    .font(.system(size: 11))
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            Spacer()
                            if m.health?.status == .ok {
                                Circle().fill(Color.green.opacity(0.6)).frame(width: 6, height: 6)
                            }
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 48)).foregroundStyle(NDS.brand.opacity(0.7))
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
        let hasAny = !emails.isEmpty || !phones.isEmpty || !addresses.isEmpty || current.birthday != nil
        if hasAny {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(emails, id: \.self) { contactRow(icon: "envelope", text: $0) }
                ForEach(phones, id: \.self) { contactRow(icon: "phone", text: $0) }
                ForEach(addresses, id: \.self) { contactRow(icon: "mappin.and.ellipse", text: $0) }
                if let bday = current.birthday {
                    contactRow(icon: "gift", text: Self.birthdayFormatter.string(from: bday))
                }
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favorite things").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            FlowLayout(spacing: 6) {
                ForEach(current.favorites, id: \.self) { fav in
                    Text(fav).font(NDS.small)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(NDS.fieldBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 1))
                }
            }
        }
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
        if let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable().scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(NDS.hairline, lineWidth: 1))
                .contextMenu {
                    Button("Remove photo", role: .destructive) { people.removePhoto(rel, from: current.id) }
                }
        }
    }

    private func contactRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(NDS.textTertiary).frame(width: 16)
            Text(text).font(NDS.body).textSelection(.enabled)
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
                Button { showAddEncounter = true } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(.borderless).font(NDS.small)
            }
            if mine.isEmpty {
                Text("No encounters yet. Add where you met or last saw them.")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                ForEach(mine) { e in EncounterRow(encounter: e) { people.deleteEncounter(e) } }
            }
        }
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
                        Image(systemName: "person.2.fill").font(.system(size: 12))
                            .foregroundStyle(NDS.brand.opacity(0.7))
                        Text(rel.label).font(NDS.small).foregroundStyle(NDS.textSecondary)
                        Text(people.person(by: rel.toPersonID)?.displayName ?? "Unknown")
                            .font(.system(size: 13.5, weight: .semibold))
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
                                Image(systemName: "calendar").font(.system(size: 13))
                                    .foregroundStyle(NDS.brand.opacity(0.7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.displayTitle).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
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
                    Image(systemName: "sparkles").font(.system(size: 12))
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
                    Button { analyzeMessages() } label: { Label("Analyze", systemImage: "message") }
                        .buttonStyle(.borderless).font(NDS.small)
                }
            }
            if let err = messageError {
                Text(err).font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else if let s = messageStats {
                VStack(alignment: .leading, spacing: 6) {
                    statRow("Total", "\(s.total)  ·  \(s.sent) sent / \(s.received) received")
                    if let last = s.lastDate { statRow("Last message", Self.dateFormatter.string(from: last)) }
                    statRow("Recent", "\(s.last30) in 30d  ·  \(s.last90) in 90d")
                    if s.total >= 4 { analysisPresetMenu }
                    analysisResultView
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
            Menu {
                ForEach(ConversationAnalysisPreset.allCases) { preset in
                    Menu {
                        Button {
                            runAnalysis(preset, scope: .recent1000)
                        } label: {
                            Label("Recent 1000 messages", systemImage: "clock")
                        }
                        Button {
                            runAnalysis(preset, scope: .allTime)
                        } label: {
                            let exists = cachedAllTimeNote(for: preset) != nil
                            Label(exists ? "Refresh all-time analysis" : "All time (cache + save)",
                                  systemImage: exists ? "arrow.clockwise" : "archivebox")
                        }
                    } label: {
                        Label(preset.label, systemImage: preset.systemImage)
                    }
                }
            } label: {
                Label("Analyze conversation", systemImage: "sparkles")
            }
            .menuStyle(.borderlessButton)
            .font(NDS.small)
            if let running = analysisRunning {
                ProgressView().controlSize(.small)
                Text("Running: \(running.label)…")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.top, 2)
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

    private func analyzeMessages() {
        analyzingMessages = true
        messageError = nil
        // Reset any prior preset output so the user knows the stats
        // refresh isn't carrying stale analysis text.
        analysisOutput = nil
        let target = current
        Task.detached(priority: .userInitiated) {
            do {
                let (stats, _) = try MessagesAnalyzer.analyze(person: target)
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

    /// Run one of the conversation analysis presets. For `.custom`,
    /// prompts the user for a free-text instruction first; everything
    /// else runs immediately. `scope` defaults to "recent 1000" — the
    /// last 1000 messages regardless of date, so it works even for
    /// contacts you haven't texted in a while. The "All time" scope
    /// runs over the FULL conversation and persists the result as an
    /// AttachedNote (kind "summary-all" etc.) so the user doesn't pay
    /// the LLM cost again unless they explicitly refresh.
    private func runAnalysis(_ preset: ConversationAnalysisPreset,
                             scope: AnalysisScope = .recent1000) {
        if preset == .custom,
           customPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showCustomPrompt = true
            return
        }
        analysisRunning = preset
        analysisOutput = nil
        let target = current
        let customDraft = customPromptDraft
        Task.detached(priority: .utility) {
            // Pull either the last N messages or every message ever,
            // depending on scope. Recent-by-count beats date-based for
            // sporadic contacts (don't penalize a friend you haven't
            // texted in 3 months by giving the model 0 context).
            let limit: Int
            switch scope {
            case .recent1000: limit = 1000
            case .allTime:    limit = 100_000   // effectively uncapped
            }
            guard let (_, recent) = try? MessagesAnalyzer.analyze(person: target, recentLimit: limit) else {
                await MainActor.run { self.analysisRunning = nil }
                return
            }
            // Truncate the rendered transcript to a model-friendly size.
            // All-time scope uses a bigger budget because the user opted
            // into the slower run.
            let transcriptBudget = scope == .allTime ? 32_000 : 8_000
            let transcript = recent.map { "\($0.fromMe ? "Me" : target.displayName): \($0.text)" }
                .joined(separator: "\n")
                .prefix(transcriptBudget)
            let prompt = preset.template(personName: target.displayName,
                                         customPrompt: customDraft)
                .replacingOccurrences(of: "PROMPT_BODY", with: String(transcript))
            // Larger num_ctx for the all-time run so qwen2.5:7b can
            // actually read everything we hand it; smaller for recent.
            let numCtx = scope == .allTime ? 16_384 : 8_192
            let result = (try? await OllamaService().generate(prompt: prompt,
                                                              temperature: 0.2,
                                                              numCtx: numCtx)) ?? ""
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.analysisRunning = nil
                guard !cleaned.isEmpty else { return }
                if scope == .allTime {
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
            Image(systemName: "mappin.and.ellipse").font(.system(size: 13))
                .foregroundStyle(NDS.brand.opacity(0.7)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(encounter.eventName).font(.system(size: 13.5, weight: .semibold))
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
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
    }
}

/// Lightweight encounter capture from a person's detail view.
@available(macOS 14.0, *)
private struct AddEncounterSheet: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var peopleTags: PeopleTagStore
    @Environment(\.dismiss) private var dismiss

    let personID: String

    @State private var eventName = ""
    @State private var date = Date()
    @State private var location = ""
    @State private var notes = ""
    @State private var eventTagID: String?

    private var trimmedName: String { eventName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Encounter").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Event").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    TextField("Purple Party 2026", text: $eventName).textFieldStyle(.roundedBorder)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Location").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    TextField("Optional", text: $location).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    TextEditor(text: $notes).font(NDS.body).frame(minHeight: 80)
                        .padding(6)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                        .overlay(RoundedRectangle(cornerRadius: NDS.radius).strokeBorder(NDS.hairline, lineWidth: 1))
                }
            }
            .padding(16)
            Spacer()
        }
        .frame(width: 420, height: 460)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        // Reuse/create an event-kind tag dated to this encounter, so it shows
        // under that tag's filter chip and carries a real date range (§4.3).
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = peopleTags.createTag(name: trimmedName, kind: .event, startDate: date,
                                       locationHint: loc.isEmpty ? nil : loc)
        people.addEncounter(to: personID,
                            eventName: trimmedName,
                            eventTagID: tag.id,
                            date: date,
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
                            notes: notes)
        dismiss()
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
