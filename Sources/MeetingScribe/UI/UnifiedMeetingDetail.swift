import SwiftUI
import AppKit
import UniformTypeIdentifiers
/// One detail view that handles every kind of call — upcoming, currently
/// recording, or past. The header (title, time, attendees, link, tags) and
/// the tabs (Transcript / My Notes / Summary) are always present. The audio
/// player appears whenever audio files exist.
@available(macOS 14.0, *)
struct UnifiedMeetingDetail: View {
    enum Mode: Equatable {
        case live
        case upcoming(Meeting)
        case past(Meeting)
    }

    let mode: Mode

    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var recordingMonitor: RecordingMonitor
    @EnvironmentObject var router: WorkspaceRouter
    /// Observed so the summary tab re-renders as tokens stream in (1-C).
    @EnvironmentObject var pipeline: MeetingPipelineController
    @ObservedObject var drive = GoogleDriveService.shared
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// P0-2: the single app-wide assistant (same instance the Today sidebar +
    /// person view use), so messages persist when you navigate between a
    /// meeting and elsewhere instead of being wiped by a per-view session.
    @EnvironmentObject var chatSession: ChatSession

    @State var tab: DetailTab = .notes
    /// Summary disclosure state within the combined Notes canvas (CN-1).
    @State var summaryExpanded = true
    /// Whether we've applied the smart tab default for this meeting yet.
    /// Prevents tab from jumping when the user has already made a selection.
    @State private var hasAppliedTabDefault = false
    @State var chatAttached = false
    /// P1-6: when a meeting has many attendees, collapse past 8 behind a
    /// "View all" expander so the header doesn't sprawl into a long chip rail.
    @State var showAllAttendees = false
    /// In the My Notes tab for a recurring series: which occurrence's notes are
    /// shown. nil = the current call (editable); otherwise a prior meeting id
    /// (read-only).
    @State var selectedOccurrenceID: String?
    @State var noteDraft: String = ""
    @State var lastSavedDraft: String = ""
    @State var saveTimer: Timer?
    @State var transcript: String = ""
    @State var summary: String = ""
    /// Tri-state loading flag (V5 PP-1): false while a cold body load is in
    /// flight so empty content reads as "loading" (skeleton), not the
    /// error-looking "No transcript / No summary".
    @State var bodyLoaded: Bool = false
    @State var titleDraft: String = ""
    @State var descriptionDraft: String = ""
    @State var editingHeader: Bool = false
    @State var previousPrimaryTagID: String?
    @State var audioURLs: [URL] = []
    /// One audio player shared by the transport bar and the synced transcript
    /// so tapping a transcript timestamp seeks the same player you can hear
    /// (C1-3). Reloaded whenever `audioURLs` changes on a meeting switch.
    @StateObject var audioController = AudioPlayerController(urls: [])
    /// In-flight body refresh — cancelled when the user switches meetings
    /// so a slow disk read on meeting A doesn't overwrite meeting B's
    /// freshly-painted state.
    @State var bodyLoadTask: Task<Void, Never>?
    @State var backlinks: [WorkspaceEntity] = []
    /// Auto-discovered related meetings (semantic similarity). (C2-3)
    @State var relatedMeetings: [Meeting] = []
    /// Failsafe upload flows (manual audio / transcript into this meeting).
    @State var showAudioImporter = false
    @State var showTranscriptImporter = false
    @State var showFollowUp = false
    /// When set, the inline "connect attendee → person" panel is shown as a
    /// trailing inspector. Holds the raw attendee string ("Name <email>") so the
    /// panel can parse name/email and offer link-to-existing or add-as-new —
    /// without leaving the meeting (replaces the old jump-to-People behavior).
    @State var connectingAttendee: String?
    /// The persistent "Who's here" people rail (P1-2). On by default; toggle ⌥⌘P.
    @AppStorage("meetingPeopleRailVisible") var peopleRailVisible = true

    /// M9 cutover: the de-tabbed canvas is now the default. Flip back via
    /// `defaults write com.tyleryannes.MeetingScribe meetingCanvasV2 -bool false`
    /// if a regression appears; the legacy `tabbedBody` path remains compiled
    /// until M10's cleanup deletes it.
    @AppStorage("meetingCanvasV2") var canvasV2 = true
    /// Query carried from a search hit into the transcript find bar (U2-2).
    @State var transcriptSearchSeed: String?

    var meeting: Meeting? {
        switch mode {
        case .live: return manager.activeMeeting
        case .upcoming(let m): return m
        case .past(let m): return m
        }
    }

    /// A recurring series (set from the calendar event's recurrence rules).
    var isRecurring: Bool { (meeting?.seriesID?.isEmpty == false) }

    /// Past recorded occurrences of the same recurring series, newest first.
    /// Each keeps its own notes — they are never merged.
    var priorOccurrences: [Meeting] {
        guard let m = meeting, let sid = m.seriesID, !sid.isEmpty else { return [] }
        return manager.pastMeetings
            .filter { $0.seriesID == sid && $0.id != m.id && $0.startDate < m.startDate }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Series spine (D1-6): every recorded occurrence of this series, oldest →
    /// newest, including the current one. The thread the 1:1 lives on.
    var allOccurrences: [Meeting] {
        guard let m = meeting, let sid = m.seriesID, !sid.isEmpty else { return [] }
        var all = manager.pastMeetings.filter { $0.seriesID == sid }
        if !all.contains(where: { $0.id == m.id }) { all.append(m) }
        return all.sorted { $0.startDate < $1.startDate }
    }

    /// The current occurrence's 1-based index in the series, or nil.
    var occurrenceIndex: Int? {
        guard let m = meeting else { return nil }
        return allOccurrences.firstIndex(where: { $0.id == m.id }).map { $0 + 1 }
    }

    /// The previous / next occurrence in the series, if any.
    var previousOccurrence: Meeting? {
        guard let idx = occurrenceIndex, idx > 1 else { return nil }
        return allOccurrences[idx - 2]
    }
    var nextOccurrence: Meeting? {
        guard let idx = occurrenceIndex, idx < allOccurrences.count else { return nil }
        return allOccurrences[idx]
    }

    /// 3-E: post-meeting review checklist (extracted to keep the main body within
    /// the Swift type-checker's budget).
    @ViewBuilder
    private var reviewBanner: some View {
        if case .past(let m) = mode {
            let aiCount = manager.actionItems.items.filter { $0.meetingID == m.id }.count
            let decCount = manager.decisions.decisions.filter { $0.meetingID == m.id }.count
            PostMeetingReviewBanner(meeting: m, actionItemCount: aiCount,
                                    decisionCount: decCount,
                                    onReviewTasks: { tab = .actions })
        }
    }

    var body: some View {
        HStack(spacing: 0) {
        VStack(spacing: 0) {
            // Clear the translucent window toolbar (Tahoe) in the Meetings-tab
            // split view — without this the title + action buttons (Transcribe,
            // Options) slid under the toolbar and were cut off. Matches the
            // People tab's identity-panel inset.
            Color.clear.frame(height: NDS.splitPaneTopInset)
            header
            reviewBanner   // 3-E: 24h post-meeting review checklist
            Divider()
            audioBar
            Divider().opacity(audioURLs.isEmpty ? 0 : 1)
            if canvasV2 {
                canvasBody
            } else {
                tabbedBody
            }
        }
        .onAppear {
            reload()
            attachChatIfNeeded()
            applySmartTabDefault()
        }
        .onChange(of: meeting?.id) { _, _ in
            hasAppliedTabDefault = false
            reload()
        }
        .onChange(of: audioURLs) { _, urls in audioController.reload(urls: urls) }
        .onAppear { consumeTranscriptQuery() }
        .onChange(of: router.pendingTranscriptQuery) { _, _ in consumeTranscriptQuery() }
        .onChange(of: noteDraft) { _, _ in scheduleNoteSave() }
        .onChange(of: meeting.flatMap { tagStore.tagIDs(for: $0) }) { _, _ in handleTagChange() }
        .onChange(of: manager.state) { _, _ in reloadIfLiveFinished() }
        .onChange(of: manager.transcribingMeetingIDs) { _, ids in
            // Re-read transcript + summary the moment the Transcribe Now job
            // for THIS meeting drops out of the in-flight set.
            if let m = meeting, !ids.contains(m.id) {
                reload()
            }
        }
        .onDisappear {
            flushNoteSave()
            bodyLoadTask?.cancel()
            bodyLoadTask = nil
            audioController.release()
        }
        .fileImporter(isPresented: $showAudioImporter,
                      allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3, .movie],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let src = urls.first, let m = meeting else { return }
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            manager.importAudioFile(src, into: m)
        }
        .fileImporter(isPresented: $showTranscriptImporter,
                      allowedContentTypes: [.plainText, .text, .utf8PlainText],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let src = urls.first, let m = meeting else { return }
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            manager.importTranscriptFile(src, into: m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Trailing inspector: the connect panel (transient) takes priority;
            // otherwise the persistent "Who's here" people rail (P1-2).
            if let attendee = connectingAttendee, let m = meeting {
                Divider().overlay(NDS.divider)
                MeetingPersonConnectPanel(
                    attendee: attendee,
                    meeting: m,
                    onClose: { connectingAttendee = nil }
                )
                .frame(width: 320)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if peopleRailVisible, let m = meeting, !m.attendees.isEmpty {
                Divider().overlay(NDS.divider)
                MeetingPeopleRail(meeting: m,
                                  onConnect: { connectingAttendee = $0 },
                                  onHide: { peopleRailVisible = false })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(
            Button("") { peopleRailVisible.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .opacity(0)
                .accessibilityHidden(true)
        )
        .animation(NDS.motion(NDS.springStandard, reduce: reduceMotion),
                   value: connectingAttendee)
        .animation(NDS.motion(NDS.springStandard, reduce: reduceMotion),
                   value: peopleRailVisible)
        // Switching meetings closes any open connect panel.
        .onChange(of: meeting?.id) { _, _ in connectingAttendee = nil }
    }
    // MARK: - Body branches (M1 flag-gated)

    /// Today's path: pill tab picker + one mode-multiplexed body. Stays byte-
    /// for-byte unchanged while `canvasV2` is off.
    @ViewBuilder var tabbedBody: some View {
        tabPicker
        Group {
            switch tab {
            case .notes:      combinedNotesBody
            case .actions:    actionsBody
            case .transcript: transcriptBody
            case .chat:       chatBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// M2 / 01 §4.1 — section anchors for the upper `ScrollView`'s
    /// `ScrollViewReader`. The highlights chip / transcript deep-link rewire
    /// in M8 will `scrollTo(.outcomes / .summary / .transcript)` instead of
    /// `tab = …`, closing P4 (lost-scroll teleports).
    enum SectionAnchor: Hashable { case outcomes, summary, transcript }

    /// Detail reading measure for the canvas column (01 §5.1). Matches the
    /// existing `actionsBody` 760pt clamp.
    static let canvasContentMaxWidth: CGFloat = 760

    /// M2 scaffold: chrome split between the short, intrinsically-sized
    /// sections (Outcomes / Highlights / Summary / Related) which scroll
    /// together up top, and the bounded-height long sections (Notes /
    /// Transcript / Ask AI) which sit below outside any outer ScrollView so
    /// they can clip-and-scroll internally without violating C-A.
    /// M3-M9 fill in the actual sections; today the top group hosts
    /// `combinedNotesBody` so the editor proves the bounded-height shape.
    @ViewBuilder var canvasBody: some View {
        // One scroll column, mode-aware section ordering — Notes and Brief
        // come FIRST for upcoming/live (the prep/recording job), Outcomes
        // and Summary first for past. Each section self-hides when it has
        // nothing to show. Persistence keys are mode-suffixed so toggling
        // collapse on a past meeting doesn't bury Brief on an upcoming one.
        ScrollViewReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: NDS.spaceXL) {
                    // The Ask-AI section that used to live inside the canvas
                    // is gone — the global right-side `ChatSidebar` is the one
                    // chat surface, and it's already scoped to this meeting via
                    // `chatSession.setContext`. No duplicate.
                    switch mode {
                    case .past:
                        outcomesSection.id(SectionAnchor.outcomes)
                        highlightsSection
                        summarySection.id(SectionAnchor.summary)
                        notesSection
                        transcriptSection.id(SectionAnchor.transcript)
                        relatedSection
                    case .live:
                        notesSection
                        transcriptSection.id(SectionAnchor.transcript)
                        outcomesSection.id(SectionAnchor.outcomes)
                        highlightsSection
                    case .upcoming:
                        transcriptSection.id(SectionAnchor.transcript)   // = Pre-meeting brief
                        notesSection
                    }
                }
                .padding(.horizontal, NDS.spaceXL)
                .padding(.vertical, NDS.spaceXL)
                .frame(maxWidth: Self.canvasContentMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    /// Mode-suffixed persistence key so toggling Notes collapsed on a past
    /// meeting doesn't carry over to upcoming/live.
    private var modeKey: String {
        switch mode {
        case .past: return "past"
        case .live: return "live"
        case .upcoming: return "upcoming"
        }
    }

    /// M8 / 01 §6 Step 8 — Ask AI section. Lazy-mounted via MSSection
    /// collapse state — defaults collapsed so opening a meeting doesn't
    /// spin up the chat panel. Bounded height keeps the chat view from
    /// fighting the outer scroll.
    @ViewBuilder var chatSection: some View {
        if meeting != nil {
            MSSection("Ask AI", systemImage: "bubble.left.and.sparkles",
                      persistenceKey: "meeting.chat.\(modeKey)",
                      defaultExpanded: false) {
                GeometryReader { geo in
                    chatBody
                        .frame(height: max(360, geo.size.height * 0.55))
                }
                .frame(minHeight: 400)
            }
        }
    }

    /// M7 / 01 §6 Step 7 — Transcript section. Lazy-mounted via the
    /// `MSSection`'s collapse state (C-B): the heavy `TranscriptSyncView`
    /// parse only happens on first expand. Mode-multiplexed title (C-C):
    /// "Live transcript" / "Pre-meeting brief" / "Transcript". Bounded
    /// height so the inner self-scrolling AppKit text view doesn't fight
    /// the outer ScrollView (C-A). The shared `audioController` (C-D) is
    /// passed unchanged so a timestamp tap seeks the same audio the
    /// transport bar plays.
    @ViewBuilder var transcriptSection: some View {
        let defaultExpanded: Bool = {
            switch mode {
            case .past: return false
            case .live, .upcoming: return true
            }
        }()
        // Past with no transcript and not loading → omit (no empty husk).
        let omit: Bool = {
            if case .past = mode { return bodyLoaded && transcript.isEmpty }
            return false
        }()
        if !omit {
            MSSection(transcriptSectionTitle,
                      systemImage: "text.alignleft",
                      persistenceKey: "meeting.transcript.\(modeKey)",
                      defaultExpanded: defaultExpanded) {
                transcriptSectionBody
            }
        }
    }

    private var transcriptSectionTitle: String {
        switch mode {
        case .live:     return "Live transcript"
        case .upcoming: return "Pre-meeting brief"
        case .past:     return "Transcript"
        }
    }

    @ViewBuilder
    private var transcriptSectionBody: some View {
        GeometryReader { geo in
            let h = max(320, geo.size.height * 0.55)
            switch mode {
            case .live:
                LiveTranscriptScroll(transcriber: manager.liveTranscriber,
                                     recordingStartedAt: liveStartedAt)
                    .frame(height: h)
            case .upcoming(let m):
                PreMeetingBriefView(meeting: m)
                    .environmentObject(manager)
                    .frame(height: h)
            case .past:
                if !bodyLoaded {
                    MSSkeleton(lines: 8).padding(.vertical, NDS.spaceSM)
                } else if !transcript.isEmpty {
                    TranscriptSyncView(rawTranscript: transcript,
                                       audioController: audioURLs.isEmpty ? nil : audioController,
                                       initialSearch: transcriptSearchSeed,
                                       meetingID: meeting?.id,
                                       attendees: meeting?.attendees ?? [])
                        .frame(height: h)
                }
            }
        }
        .frame(minHeight: 360)
    }

    /// M5 / 01 §6 Step 5 — Notes section. The C-A constraint test: the
    /// `RichMarkdownEditor` is `NSScrollView`-backed and cannot nest in an
    /// outer SwiftUI `ScrollView` with unbounded height, so the editor gets a
    /// fixed `frame(height:)` and self-scrolls. The MSSection lazy-mounts
    /// content when expanded, so a collapsed Notes section never violates
    /// C-A in the first place.
    @ViewBuilder var notesSection: some View {
        if meeting != nil {
            MSSection("Your notes", systemImage: "doc.text",
                      persistenceKey: "meeting.notes.\(modeKey)",
                      defaultExpanded: true) {
                notesSectionBody
            }
        }
    }

    @AppStorage("meeting.notes.height") private var notesPaneHeight: Double = 320

    @ViewBuilder
    private var notesSectionBody: some View {
        VStack(alignment: .leading, spacing: NDS.spaceSM) {
            Text("Markdown notes — type `/` for blocks, `@` to link. Saved to notes.md.")
                .font(.caption).foregroundStyle(.secondary)
            RichMarkdownEditor(text: $noteDraft,
                               placeholder: "Type / for blocks, @ to link a meeting…",
                               mentionProvider: { manager.workspaceEntities() })
                .frame(height: max(160, notesPaneHeight))
                .overlay(RoundedRectangle(cornerRadius: NDS.radiusSmall)
                    .strokeBorder(NDS.hairline, lineWidth: 1))
            // C-A drag-resize grabber (01 §4.5).
            Rectangle().fill(Color.clear)
                .frame(height: 6)
                .contentShape(Rectangle())
                .overlay(Capsule().fill(NDS.textTertiary.opacity(0.35))
                    .frame(width: 36, height: 3))
                .gesture(DragGesture().onChanged { v in
                    let next = notesPaneHeight + Double(v.translation.height)
                    notesPaneHeight = min(max(160, next), 900)
                })
                .help("Drag to resize notes")
            if let m = meeting,
               !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MSInlineButton("Push to-dos → Tasks", systemImage: "arrow.right.circle") {
                    pushNoteTodosToTasks(m)
                }
            }
        }
    }

    /// M9 / 01 §6 Step 9 — Related & linked section. Combines the
    /// embedding-similar list (`relatedMeetingsStrip`) with the cross-entity
    /// backlinks (`backlinksPanel`). Hidden when both empty.
    @ViewBuilder var relatedSection: some View {
        let count = relatedMeetings.count + backlinks.count
        if count > 0 {
            MSSection("Related & linked", systemImage: "link",
                      count: count,
                      persistenceKey: "meeting.related",
                      defaultExpanded: false) {
                VStack(alignment: .leading, spacing: NDS.spaceMD) {
                    if !relatedMeetings.isEmpty {
                        relatedMeetingsStrip
                    }
                    if !backlinks.isEmpty {
                        backlinksPanel
                    }
                }
            }
        }
    }

    /// M6 / 01 §6 Step 6 — Summary section. Past-only. Branch order matches
    /// the spec: real summary → editor + edit-by-asking + feedback; else
    /// generating → banner; else loaded-with-transcript → engine-off retry;
    /// else cold → skeleton; else omitted. Replaces `summaryDisclosure` /
    /// `pastSummaryBody` / `emptySummaryView` (M10 will delete them).
    @ViewBuilder var summarySection: some View {
        if case .past = mode, let m = meeting {
            let showSection = hasRealSummary || isSummaryGenerating
                || (bodyLoaded && !transcript.isEmpty) || !bodyLoaded
            if showSection {
                MSSection("Summary", systemImage: "doc.text",
                          persistenceKey: "meeting.summary",
                          defaultExpanded: true,
                          trailing: { copyMenu }) {
                    summarySectionBody(meetingID: m.id)
                }
            }
        }
    }

    @ViewBuilder
    private func summarySectionBody(meetingID: String) -> some View {
        if hasRealSummary {
            GeometryReader { geo in
                let h = min(420, max(180, geo.size.height * 0.45))
                VStack(alignment: .leading, spacing: NDS.spaceMD) {
                    ScrollView {
                        MarkdownEditor(text: .constant(summary), isEditable: false)
                            .padding(.horizontal, 4)
                    }
                    .frame(height: h)
                    .overlay(RoundedRectangle(cornerRadius: NDS.radiusSmall)
                        .strokeBorder(NDS.hairline, lineWidth: 1))
                    if let m = meeting {
                        if manager.ollamaReachable, !summary.isEmpty {
                            SummaryEditByAsking(meeting: m, current: summary,
                                                onChanged: { summary = $0 })
                        }
                        SummaryFeedbackRow(meetingID: m.id) {
                            manager.pipelineController.transcribeNow(meeting: m,
                                                                     regenerateSummary: true)
                        }
                        followUpButton
                    }
                }
            }
            .frame(minHeight: 260)
        } else if isSummaryGenerating {
            summaryGeneratingBanner
        } else if bodyLoaded && !transcript.isEmpty {
            summaryFailedBanner
        } else if !bodyLoaded {
            MSSkeleton(lines: 4).padding(.vertical, NDS.spaceSM)
        }
    }

    /// M4 / 01 §6 Step 4 — Highlights section. Each `MeetingMark` is a
    /// timestamped chip; M8 will rewire the tap target to scroll-to-transcript
    /// + seed the search instead of teleporting `tab = .transcript`.
    @ViewBuilder var highlightsSection: some View {
        if let m = meeting {
            let marks = MeetingMarks.load(m.id)
            if !marks.isEmpty {
                MSSection("Highlights", systemImage: "flag.fill",
                          count: marks.count,
                          persistenceKey: "meeting.highlights") {
                    FlowLayout(spacing: NDS.spaceSM) {
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
            }
        }
    }

    /// M3 / 01 §6 Step 3 — Outcomes section. The §P2 merge: full-CRUD
    /// `MeetingActionRow`s + decisions + add. Replaces `outcomesStrip`'s
    /// read-only preview, `actionsBody`'s standalone tab, and the legacy
    /// `actionItemsSection`'s third render.
    @ViewBuilder var outcomesSection: some View {
        if let m = meeting {
            let items = manager.actionItems.items(for: m.id)
            let unconfirmed = items.filter { $0.needsTriage }
            let decs = manager.decisions.decisions.filter { $0.meetingID == m.id }
            let isUpcoming: Bool = { if case .upcoming = mode { return true } else { return false } }()
            if !isUpcoming {
                MSSection("Outcomes", systemImage: "checklist",
                          count: items.count,
                          persistenceKey: "meeting.outcomes",
                          defaultExpanded: !items.isEmpty || !decs.isEmpty,
                          trailing: {
                              if !unconfirmed.isEmpty {
                                  MSInlineButton("Add all \(unconfirmed.count) → Tasks",
                                                 systemImage: "checkmark.circle.fill") {
                                      manager.actionItems.confirm(ids: unconfirmed.map(\.id))
                                  }
                              }
                          }) {
                    VStack(alignment: .leading, spacing: NDS.spaceMD) {
                        if items.isEmpty && decs.isEmpty {
                            MSEmptyState(systemImage: "checklist",
                                         title: "No action items",
                                         message: "Items appear here after summarization, or add one below.")
                                .frame(minHeight: 140)
                        } else {
                            ForEach(items) { item in
                                MeetingActionRow(item: item, store: manager.actionItems, meeting: m)
                            }
                            ForEach(decs.prefix(5)) { d in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal").scaledFont(12)
                                        .foregroundStyle(NDS.brand.opacity(0.7))
                                    Text(d.text).font(NDS.small)
                                        .foregroundStyle(NDS.textSecondary).lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        MSInlineButton("Add action item", systemImage: "plus") {
                            var t = manager.actionItems.createTask(title: "New action item")
                            t.meetingID = m.id
                            t.meetingTitle = m.displayTitle
                            t.meetingDate = m.startDate
                            manager.actionItems.upsert(t)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tabs

    /// Count of this meeting's action items still awaiting review (Triage) —
    /// shown as a badge on the Actions tab (§3B).
    var unconfirmedActionCount: Int {
        guard let m = meeting else { return 0 }
        return manager.actionItems.items(for: m.id).filter { $0.needsTriage }.count
    }

    var tabPicker: some View {
        HStack {
            MSPillTabs(tabs: DetailTab.allCases.map { t in
                // C1-1: for an upcoming meeting the "Transcript" tab IS the
                // pre-meeting brief — label it so prep greets you, not a misnomer.
                let label: String
                if t == .actions && unconfirmedActionCount > 0 {
                    label = "Actions \(unconfirmedActionCount)"
                } else if t == .transcript, case .upcoming = mode {
                    label = "Brief"
                } else {
                    label = t.label
                }
                return (t, label)
            }, selection: $tab)
            Spacer(minLength: 0)
        }
        .padding([.horizontal, .top], 10)
        .padding(.bottom, 4)
    }

    /// Dedicated Actions tab (§3D): this meeting's action items with confirm /
    /// push-to-Tasks controls and inline add.
    @ViewBuilder
    var actionsBody: some View {
        if let m = meeting {
            let items = manager.actionItems.items(for: m.id)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        NotionEyebrow(text: "Actions from this meeting", count: items.count)
                        Spacer()
                        let unconfirmed = items.filter { $0.needsTriage }
                        if !unconfirmed.isEmpty {
                            Button {
                                manager.actionItems.confirm(ids: unconfirmed.map(\.id))
                            } label: {
                                Label("Add all \(unconfirmed.count) → Tasks", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(MSPrimaryButtonStyle())
                        }
                    }
                    if items.isEmpty {
                        MSEmptyState(systemImage: "checklist",
                                     title: "No action items",
                                     message: "Items appear here after summarization, or add one below.")
                            .frame(minHeight: 200)
                    } else {
                        ForEach(items) { item in
                            MeetingActionRow(item: item, store: manager.actionItems, meeting: m)
                        }
                    }
                    Button {
                        var t = manager.actionItems.createTask(title: "New action item")
                        t.meetingID = m.id; t.meetingTitle = m.displayTitle; t.meetingDate = m.startDate
                        manager.actionItems.upsert(t)
                    } label: {
                        Label("Add action item", systemImage: "plus")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    func placeholder(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).scaledFont(36).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    // MARK: - State sync

    /// Sync paint (from in-memory cache) + async refresh (from disk).
    /// Replaces the previous three-synchronous-disk-reads-on-main pattern
    /// that made clicking into a meeting hitch perceptibly. The cache
    /// returns whatever it has instantly; the in-flight refresh task
    /// fills in the freshest copy a frame or two later.
    func reload() {
        // Cancel any in-flight reload from a prior meeting click.
        bodyLoadTask?.cancel()

        guard let m = meeting else {
            transcript = ""; summary = ""; noteDraft = ""; lastSavedDraft = ""
            audioURLs = []; backlinks = []; bodyLoaded = true; return
        }

        // 1. Synchronous cache snapshot — instant first paint.
        let cached = manager.bodyCache.cached(m.id)
        transcript = cached.transcript
        summary = cached.summary
        // A warm cache hit is "loaded"; a cold miss stays "loading" until the
        // async refresh commits, so we show a skeleton instead of a false empty.
        bodyLoaded = !(cached.transcript.isEmpty && cached.summary.isEmpty)
        noteDraft = Self.stripBriefBlock(from: cached.notes)
        lastSavedDraft = noteDraft
        titleDraft = m.userTitle ?? m.title
        descriptionDraft = m.userDescription ?? ""
        previousPrimaryTagID = manager.tagStore.primaryTag(for: m)?.id
        selectedOccurrenceID = nil

        // Audio URLs are cheap (fileExists on a known set) but still off-main.
        // Stale audioURLs from a prior meeting will be replaced when the
        // task finishes; until then we show the previous list — usually
        // close enough to suppress a flash.
        let bodyCache = manager.bodyCache
        let storeRef = manager.store
        let primary = manager.tagStore.primaryTag(for: m)
        let viewedID = m.id

        bodyLoadTask = Task { [weak manager] in
            // 2. Async body refresh (cancellable; only commits if we're
            //    still showing the same meeting).
            let fresh = await bodyCache.load(m)
            guard !Task.isCancelled, meeting?.id == viewedID else { return }
            transcript = fresh.transcript
            summary = fresh.summary
            bodyLoaded = true   // refresh landed — empty now means truly empty (PP-1)
            if noteDraft == lastSavedDraft {
                // Don't clobber in-progress edits.
                noteDraft = Self.stripBriefBlock(from: fresh.notes)
                lastSavedDraft = noteDraft
            }
            // 3. Audio URL discovery off-main.
            let dir = storeRef.directory(for: m, primaryTag: primary)
            let urls = await Task.detached(priority: .userInitiated) {
                Self.discoverAudioURLs(in: dir)
            }.value
            guard !Task.isCancelled, meeting?.id == viewedID else { return }
            audioURLs = urls
            // 4. Backlinks last — most expensive, least time-critical.
            if let mgr = manager {
                let found = await mgr.backlinks(toMeetingID: viewedID)
                guard !Task.isCancelled, meeting?.id == viewedID else { return }
                backlinks = found
                // Auto-discovered related meetings via embedding similarity (C2-3).
                let related = PeopleStore.shared.relatedMeetingIDs(toID: viewedID)
                    .compactMap { mgr.meeting(forEntityID: $0) }
                guard !Task.isCancelled, meeting?.id == viewedID else { return }
                relatedMeetings = related
            }
        }
    }

    nonisolated private static func discoverAudioURLs(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let mic = dir.appendingPathComponent("mic.m4a")
        let sys = dir.appendingPathComponent("system.m4a")
        var urls: [URL] = []
        if fm.fileExists(atPath: mic.path) { urls.append(mic) }
        if fm.fileExists(atPath: sys.path) { urls.append(sys) }
        if !urls.isEmpty { return urls }
        let audioDir = dir.appendingPathComponent("audio", isDirectory: true)
        if fm.fileExists(atPath: audioDir.path),
           let contents = try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
            return contents.filter { $0.pathExtension.lowercased() == "m4a" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return []
    }

    // (Backlinks are now loaded inside `reload()`'s body refresh task so
    // they cancel along with the rest when the user switches meetings.)

    /// For past meetings that already have a summary, default to the Summary
    /// tab instead of My Notes — that's what users want to see first.
    /// Runs once per meeting switch; tab jumps back to Notes for live meetings
    /// so users can type while recording.
    func applySmartTabDefault() {
        guard !hasAppliedTabDefault else { return }
        hasAppliedTabDefault = true
        switch mode {
        case .past:
            // The Notes canvas already shows the summary up top, so it's the
            // right default; expand the summary when one exists.
            tab = .notes
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                summaryExpanded = !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .live:
            tab = .notes  // Notes while recording so you can type alongside the transcript.
        case .upcoming:
            tab = .transcript  // Transcript placeholder for upcoming — no notes to show yet.
        }
    }

    func reloadIfLiveFinished() {
        if case .idle = manager.state, case .live = mode { reload() }
        // After summary finishes for any mode, refresh files.
        if case .idle = manager.state, case .past = mode {
            reload()
        }
    }
    func handleTagChange() {
        guard let m = meeting else { return }
        let newPrimaryID = manager.tagStore.primaryTag(for: m)?.id
        if newPrimaryID != previousPrimaryTagID {
            let prev = previousPrimaryTagID.flatMap { manager.tagStore.tag(by: $0) }
            manager.handleTagChange(for: m, previousPrimary: prev)
            previousPrimaryTagID = newPrimaryID
            audioURLs = manager.audioURLs(for: m)
        }
    }

    func scheduleNoteSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flushNoteSave() }
        }
    }

    func flushNoteSave() {
        saveTimer?.invalidate(); saveTimer = nil
        guard let m = meeting, noteDraft != lastSavedDraft else { return }
        manager.saveUserNotes(noteDraft, for: m)
        lastSavedDraft = noteDraft
    }

    /// The pre-meeting brief used to be injected into `notes.md` as an
    /// auto-managed block so it'd live in the always-present Notes tab.
    /// In the de-tabbed canvas the brief is its OWN section, so showing it a
    /// second time inside the Notes editor was duplicate + confusing. Strip
    /// the block here so the editor shows only the user's own notes; the
    /// block on disk stays untouched in case other code paths need it, and
    /// `attachBriefToNotes` is now a no-op (see `MeetingManager`).
    static func stripBriefBlock(from raw: String) -> String {
        let begin = MeetingManager.briefNoteBegin
        let end = MeetingManager.briefNoteEnd
        guard let r1 = raw.range(of: begin),
              let r2 = raw.range(of: end),
              r1.lowerBound < r2.upperBound else { return raw }
        var cleaned = raw
        cleaned.replaceSubrange(r1.lowerBound..<r2.upperBound, with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
