import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            seriesSpine   // recurring-series prev/next thread
            // Main title row — tightened: 12 top / 8 bottom (was 18 / 12).
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    titleAndDescription
                    metaLine
                    chipRow
                }
                Spacer(minLength: 12)
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Attendees + shared-history + conference URL packed onto ONE
            // horizontal scroll row so the header doesn't stack 4–5 rows of
            // chrome on top of the canvas. Each is a chip; the row wraps
            // gracefully on narrow widths.
            if hasContextChips {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let m = meeting {
                            let shown = showAllAttendees ? m.attendees.count : 6
                            ForEach(m.attendees.prefix(shown), id: \.self) { a in
                                AttendeeChip(attendee: a) { connectingAttendee = $0 }
                            }
                            if m.attendees.count > 6 {
                                MSInlineButton(showAllAttendees
                                               ? "Fewer"
                                               : "+\(m.attendees.count - 6)") {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        showAllAttendees.toggle()
                                    }
                                }
                            }
                            if unaddedAttendeeCount(m) > 0 {
                                MSInlineButton("Add \(unaddedAttendeeCount(m)) to People",
                                               systemImage: "person.crop.circle.badge.plus") {
                                    addAllAttendeesToPeople(m)
                                }
                            }
                        }
                        if let url = meeting?.conferenceURL, let u = URL(string: url) {
                            Link(destination: u) {
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .scaledFont(10).foregroundStyle(NDS.brand)
                                    Text("Join call").scaledFont(11).foregroundStyle(NDS.brand)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(NDS.brand.opacity(0.08), in: Capsule())
                            }
                        }
                        if let strip = sharedHistoryLine(for: meeting) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .scaledFont(9).foregroundStyle(NDS.textTertiary)
                                Text(strip).scaledFont(11)
                                    .foregroundStyle(NDS.textSecondary).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(NDS.fieldBg, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 6)
            }

            // Tags
            if let m = meeting {
                TagPicker(meeting: m, propagateToSeries: m.seriesID != nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            // Upcoming action bar — only meaningful for upcoming meetings.
            if case .upcoming = mode, let m = meeting {
                upcomingActionRow(m)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            // Status / warning banner
            if showStatusBanner {
                statusBanner
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider().overlay(NDS.divider)
        }
    }

    /// True when at least one of the trailing context chips would render — so
    /// we can omit the whole row (and its bottom padding) when there's nothing
    /// to show. Keeps the header from reserving a dead 32pt strip.
    private var hasContextChips: Bool {
        if let m = meeting, !m.attendees.isEmpty { return true }
        if let url = meeting?.conferenceURL, URL(string: url) != nil { return true }
        if sharedHistoryLine(for: meeting) != nil { return true }
        return false
    }

    // MARK: - Title + description

    @ViewBuilder
    var titleAndDescription: some View {
        if editingHeader {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $titleDraft)
                    .scaledFont(22, weight: .bold, kind: .display)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 6))
                TextField("Quick description (optional)", text: $descriptionDraft, axis: .vertical)
                    .scaledFont(13)
                    .foregroundStyle(NDS.textSecondary)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 6))
                    .lineLimit(2...4)
                HStack(spacing: 8) {
                    Button("Save") { saveHeader() }
                        .buttonStyle(MSPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { editingHeader = false; resetDrafts() }
                        .buttonStyle(MSSecondaryButtonStyle())
                }
            }
        } else {
            // Title — large, prominent
            Text(meeting?.displayTitle ?? "Untitled")
                .scaledFont(22, weight: .bold, kind: .display)
                .foregroundStyle(NDS.textPrimary)
                .textSelection(.enabled)
            if let d = meeting?.userDescription, !d.isEmpty {
                Text(d)
                    .scaledFont(13)
                    .foregroundStyle(NDS.textSecondary)
            }
        }
    }

    // MARK: - Meta line (date/time + health)

    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(timeRange())
                .scaledFont(12)
                .foregroundStyle(NDS.textSecondary)
            if case .past = mode {
                MeetingHealthBadge(health: meeting?.health)
            }
            if let m = meeting, manager.isTranscribingMeeting(m) {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Processing…")
                        .scaledFont(11)
                        .foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }

    // MARK: - Chip row (recurring, calendar)

    @ViewBuilder
    private var chipRow: some View {
        HStack(spacing: 6) {
            if isRecurring, let m = meeting {
                // The "Recurring" chip opens the Series Hub (C1-4) — the page for
                // the standing meeting itself (timeline, rolling open follow-ups,
                // decisions, roster), not just a caption.
                RecurringChip(meeting: m, priorCount: priorOccurrences.count)
            }
            if let cal = meeting?.calendarName {
                NotionChip(cal, color: NDS.selectColor("blue"), systemImage: "calendar")
            }
        }
    }

    // MARK: - Action buttons (primary CTA + overflow menu)

    @ViewBuilder
    var actionButtons: some View {
        if editingHeader { EmptyView() }
        else {
            HStack(spacing: 8) {
                primaryCTA
                overflowMenu
            }
        }
    }

    /// One context-aware primary button. Only the most likely next action.
    @ViewBuilder
    private var primaryCTA: some View {
        switch mode {
        case .live:
            if case .recording = manager.state {
                Button(role: .destructive) {
                    Task { await manager.stopRecording() }
                } label: {
                    Label("Stop Recording", systemImage: "stop.fill")
                }
                .buttonStyle(MSDangerButtonStyle())
            }

        case .past(let m):
            if manager.isTranscribingMeeting(m) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Processing…").scaledFont(12).foregroundStyle(NDS.textSecondary)
                }
            } else if manager.hasAudio(for: m) && transcript.isEmpty {
                Button { manager.transcribeNow(meeting: m) } label: {
                    Label("Transcribe Now", systemImage: "text.bubble")
                }
                .buttonStyle(MSPrimaryButtonStyle())
            } else if manager.hasAudio(for: m) {
                // A transcript exists but the audio is still here — always offer
                // a visible retry (re-runs transcription + summary on the
                // recorded audio). Previously this was only reachable, mislabeled,
                // from the overflow menu.
                Button { manager.transcribeNow(meeting: m) } label: {
                    Label("Re-transcribe", systemImage: "arrow.clockwise")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                .help("Re-run transcription and summary on this meeting's audio.")
            } else if m.conferenceURL != nil {
                Button {
                    Task { await manager.switchToRecording(m) }
                } label: {
                    Label("Record Again", systemImage: "video.fill")
                }
                .buttonStyle(MSSecondaryButtonStyle())
            }

        case .upcoming(let m):
            if m.conferenceURL != nil {
                Button {
                    Task { await manager.switchToRecording(m) }
                } label: {
                    Label("Join & Record", systemImage: "video.fill")
                }
                .buttonStyle(MSPrimaryButtonStyle())
            } else {
                Button {
                    Task { await manager.startRecording(for: m) }
                } label: {
                    Label("Record", systemImage: "record.circle.fill")
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }
        }
    }

    /// All secondary actions in a single ··· overflow menu.
    private var overflowMenu: some View {
        Menu {
            // Edit title/description
            Button { editingHeader = true } label: {
                Label("Edit title…", systemImage: "pencil")
            }

            // P1-6: meeting source — moved out of the header into Options.
            if let m = meeting {
                Menu {
                    sourceMenuContent(for: m)
                } label: {
                    Label("Meeting source", systemImage: m.effectiveSource?.systemImage ?? "questionmark.circle")
                }
            }

            if case .past(let m) = mode {
                Divider()

                // Transcription — re-run on the recorded audio. Always available
                // when audio exists (even mid-"Processing", so a stuck or bad
                // job can be retried). Label adapts to a clear retry.
                Button {
                    manager.transcribeNow(meeting: m)
                } label: {
                    Label(transcript.isEmpty ? "Transcribe Now" : "Re-transcribe & summarize",
                          systemImage: transcript.isEmpty ? "text.bubble" : "arrow.clockwise")
                }
                .disabled(!manager.hasAudio(for: m))

                // Join actions (if URL exists)
                if m.conferenceURL != nil {
                    Button {
                        if let url = m.conferenceURL.flatMap(URL.init(string:)) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Join Call (no recording)", systemImage: "video")
                    }
                }

                // Add new recording
                Button {
                    Task {
                        if case .recording = manager.state {
                            await manager.stopRecording()
                            try? await Task.sleep(nanoseconds: 300_000_000)
                        }
                        await manager.continueRecording(for: m)
                    }
                } label: {
                    Label("Add New Recording", systemImage: "plus.circle")
                }
                .help("Appends a new audio segment to this meeting.")

                Divider()

                // File operations
                Button {
                    let link = WorkspaceLink.url(kind: .meeting, id: m.id).absoluteString
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                } label: {
                    Label("Copy link to meeting", systemImage: "link")
                }
                Button {
                    manager.revealInFinder(m)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                // Recover submenu
                Menu("Recover…") {
                    Button {
                        manager.recoverAudio(for: m)
                    } label: { Label("Recover audio from folder", systemImage: "arrow.clockwise.icloud") }
                    Divider()
                    Button { showAudioImporter = true } label: {
                        Label("Upload audio file…", systemImage: "waveform.badge.plus")
                    }
                    Button { showTranscriptImporter = true } label: {
                        Label("Upload transcript…", systemImage: "doc.badge.plus")
                    }
                }

                // Export submenu
                Menu("Export…") {
                    Button {
                        if let doc = confirmedExportDocument(for: m) {
                            MeetingExporter.exportMarkdown(doc, suggestedName: m.slug)
                        }
                    } label: { Label("Markdown (.md)", systemImage: "doc.plaintext") }
                    Button {
                        if let doc = confirmedExportDocument(for: m) {
                            MeetingExporter.exportPDF(doc, suggestedName: m.slug)
                        }
                    } label: { Label("PDF (.pdf)", systemImage: "doc.richtext") }
                    Divider()
                    Button { exportToDrive(m) } label: {
                        Label(drive.isConnected
                              ? "Google Drive"
                              : "Google Drive (connect in Settings)",
                              systemImage: "arrow.up.doc")
                    }
                    Button { exportToObsidian(m) } label: {
                        Label("Obsidian vault", systemImage: "doc.text.below.ecg")
                    }
                    Button { openInObsidian(m) } label: {
                        Label("Open in Obsidian", systemImage: "arrow.up.forward.app")
                    }
                }

                // Calendar write-back (P4-1)
                Menu("Calendar…") {
                    if isCalendarLinked(m) {
                        Button { addRecapToCalendar(m) } label: {
                            Label("Add recap to event", systemImage: "calendar.badge.plus")
                        }
                        Divider()
                    }
                    Button { scheduleFollowUp(m, days: 1) } label: {
                        Label("Schedule follow-up tomorrow", systemImage: "calendar.badge.clock")
                    }
                    Button { scheduleFollowUp(m, days: 3) } label: {
                        Label("Schedule follow-up in 3 days", systemImage: "calendar.badge.clock")
                    }
                    Button { scheduleFollowUp(m, days: 7) } label: {
                        Label("Schedule follow-up next week", systemImage: "calendar.badge.clock")
                    }
                }
            }

        } label: {
            // Labeled so it reads as a real "options / settings" affordance
            // instead of a bare ⋯ icon people miss. (Edit, Re-transcribe,
            // Recover, Export, Reveal all live in here.)
            // B1: shared menu chrome so the radius/height match the adjacent
            // primary CTA (was a hand-built radius-8 frame).
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3").scaledFont(12, weight: .medium)
                Text("Options").scaledFont(12, weight: .medium)
            }
            .msMenuButtonChrome()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Meeting options — edit, re-transcribe, recover, export")
    }

    // MARK: - Source picker

    /// P1-6: source options, rendered inside the Options menu's "Meeting source"
    /// submenu (previously a standalone header row). A checkmark marks the
    /// active source; "Clear" returns to auto-detect.
    @ViewBuilder
    func sourceMenuContent(for m: Meeting) -> some View {
        let current = m.effectiveSource
        ForEach(MeetingSource.allCases, id: \.self) { src in
            Button {
                manager.updateMeeting(m, source: .some(src))
            } label: {
                if src == current {
                    Label(src.displayName, systemImage: "checkmark")
                } else {
                    Text(src.displayName)
                }
            }
        }
        if m.userSource != nil {
            Divider()
            Button("Clear (auto-detect)") {
                manager.updateMeeting(m, source: .some(nil))
            }
        }
    }

    // MARK: - Upcoming action row

    func upcomingActionRow(_ m: Meeting) -> some View {
        HStack(spacing: 8) {
            if m.conferenceURL != nil {
                // Join only (no recording)
                Button {
                    if let url = m.conferenceURL.flatMap(URL.init(string:)) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Join Call", systemImage: "video")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                .help("Open the meeting link without recording.")
            }
            Button {
                Task {
                    if case .recording = manager.state {
                        await manager.stopRecording()
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                    await manager.startRecording(for: m)
                }
            } label: {
                Label("Record Only", systemImage: "record.circle")
            }
            .buttonStyle(MSSecondaryButtonStyle())
        }
    }

    // MARK: - Status banner

    private var showStatusBanner: Bool {
        if case .live = mode, case .recording = manager.state { return true }
        if let m = meeting, manager.wasInterrupted(m) { return true }
        return false
    }

    @ViewBuilder
    var statusBanner: some View {
        if case .live = mode, case .recording = manager.state {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                        .pulsingSymbol(active: !reduceMotion)
                    Text("Recording")
                        .font(.callout.bold())
                }
                AudioLevelMeter(micLevel: recordingMonitor.recordingHealth.micLevel,
                                systemLevel: recordingMonitor.recordingHealth.systemLevel,
                                bars: 14, height: 20)
                    .frame(maxWidth: 160)
                Spacer()
                recordingHealthRow
            }
            .padding(10)
            .background(Color.red.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: NDS.radius))
        } else if let m = meeting, manager.wasInterrupted(m) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recording may be incomplete").font(.callout.bold())
                    Text("The app may have quit mid-recording. Recover the audio to transcribe.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    manager.recoverAudio(for: m)
                } label: { Label("Recover", systemImage: "arrow.clockwise.icloud") }
                .buttonStyle(MSPrimaryButtonStyle())
            }
            .padding(10)
            .background(Color.orange.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: NDS.radius))
        }
    }

    // MARK: - Helpers (unchanged from original)

    func resetDrafts() {
        guard let m = meeting else { return }
        titleDraft = m.userTitle ?? m.title
        descriptionDraft = m.userDescription ?? ""
    }

    func saveHeader() {
        guard let m = meeting else { return }
        let t = titleDraft.trimmingCharacters(in: .whitespaces)
        let d = descriptionDraft.trimmingCharacters(in: .whitespaces)
        manager.updateMeeting(m,
                              title: t.isEmpty ? nil : t,
                              description: d.isEmpty ? nil : d)
        editingHeader = false
    }

    func timeRange() -> String {
        guard let m = meeting else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d  ·  h:mm a"
        let start = f.string(from: m.startDate)
        let endF = DateFormatter(); endF.dateFormat = "h:mm a"
        let end = endF.string(from: m.endDate)
        let mins = Int(m.endDate.timeIntervalSince(m.startDate) / 60)
        return "\(start) – \(end)  (\(mins) min)"
    }

    var isAppIdle: Bool {
        if case .idle = manager.state { return true }
        if case .error = manager.state { return true }
        return false
    }

    func exportToDrive(_ m: Meeting) {
        guard drive.isConnected else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            return
        }
        guard let doc = confirmedExportDocument(for: m) else { return }
        Task { try? await drive.exportMarkdown(filename: m.slug, content: doc) }
    }

    func exportToObsidian(_ m: Meeting) {
        let tagNames = tagStore.tagIDs(for: m).compactMap { tagStore.tag(by: $0)?.name }
        let md = ObsidianExporter.markdown(
            for: m,
            summary: manager.summaryMarkdown(for: m),
            notes: noteDraft.isEmpty ? manager.userNotes(for: m) : noteDraft,
            transcript: manager.transcriptMarkdown(for: m),
            tags: tagNames)
        ObsidianExporter.export(md, filename: m.slug)
    }

    // MARK: - Series spine (D1-6)

    /// Prev/next navigation across a recurring series — "the 1:1 home, both
    /// directions". Only shown when there are 2+ recorded occurrences.
    @ViewBuilder
    var seriesSpine: some View {
        if isRecurring, allOccurrences.count > 1, let idx = occurrenceIndex {
            HStack(spacing: 8) {
                Image(systemName: "repeat").scaledFont(10).foregroundStyle(NDS.lilac)
                Button { if let p = previousOccurrence { router.openMeeting(p) } } label: {
                    Image(systemName: "chevron.left").scaledFont(11)
                }
                .buttonStyle(.plain).disabled(previousOccurrence == nil)
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .help("Previous in series (⌥⌘←)")

                Menu {
                    ForEach(allOccurrences.reversed()) { occ in
                        Button { router.openMeeting(occ) } label: {
                            Text(MeetingManager.entityDateString(occ.startDate)
                                 + (occ.id == meeting?.id ? "  ✓" : ""))
                        }
                    }
                } label: {
                    Text("Occurrence \(idx) of \(allOccurrences.count)")
                        .scaledFont(12, weight: .medium).foregroundStyle(NDS.textSecondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

                Button { if let n = nextOccurrence { router.openMeeting(n) } } label: {
                    Image(systemName: "chevron.right").scaledFont(11)
                }
                .buttonStyle(.plain).disabled(nextOccurrence == nil)
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .help("Next in series (⌥⌘→)")
                Spacer()
            }
            .foregroundStyle(NDS.textSecondary)
            .padding(.horizontal, 20).padding(.top, 10)
        }
    }

    // MARK: - Shared history (P1-5)

    /// "You've met Jane 12× · last: pricing follow-up" for the meeting's
    /// most-significant resolved attendee (by shared past-meeting count).
    func sharedHistoryLine(for meeting: Meeting?) -> String? {
        guard let m = meeting else { return nil }
        let people = PeopleStore.shared.people
        var best: (name: String, count: Int, last: Meeting?)?
        for raw in m.attendees {
            guard let pid = PersonResolver.resolve(raw, in: people),
                  let person = people.first(where: { $0.id == pid }) else { continue }
            let shared = manager.pastMeetings.filter {
                $0.id != m.id && person.meetingMentions.contains($0.id)
            }
            if shared.count > (best?.count ?? 0) {
                best = (person.displayName, shared.count,
                        shared.max(by: { $0.startDate < $1.startDate }))
            }
        }
        guard let b = best, b.count > 0 else { return nil }
        let first = b.name.split(separator: " ").first.map(String.init) ?? b.name
        let times = b.count == 1 ? "once before" : "\(b.count)× before"
        if let last = b.last {
            return "You've met \(first) \(times) · last: \(last.displayTitle)"
        }
        return "You've met \(first) \(times)"
    }

    // MARK: - Add all attendees to People (TM-9)

    private func attendeeExists(_ a: String) -> Bool {
        PersonResolver.resolve(a, in: PeopleStore.shared.people) != nil
    }

    func unaddedAttendeeCount(_ m: Meeting) -> Int {
        m.attendees.filter { !attendeeExists($0) }.count
    }

    func addAllAttendeesToPeople(_ m: Meeting) {
        var created: [Person] = []
        for a in m.attendees where !attendeeExists(a) {
            let id = PersonResolver.parse(a)
            let name = id.hasName ? id.name : PersonResolver.localPart(of: id.email)
            let person = PeopleStore.shared.createPerson(displayName: name, email: id.email)
            // P1-6: don't leave a hollow Person divorced from the meeting that
            // created them. Link this meeting and count it as an interaction so
            // the new record shows up in their history and ages correctly.
            PeopleStore.shared.addMeetingMention(m.id, toPersonID: person.id)
            PeopleStore.shared.bumpLastInteraction(personID: person.id, date: m.startDate)
            created.append(person)
        }
        guard !created.isEmpty else { return }
        let label = created.count == 1 ? created[0].displayName : "\(created.count) people"
        ToastCenter.shared.show("Added \(label) to People", undoTitle: "Undo") {
            for person in created { PeopleStore.shared.deletePerson(person) }
        }
    }

    // MARK: - Calendar write-back (P4-1)

    /// Only calendar-sourced meetings have a real EKEvent to write back to.
    func isCalendarLinked(_ m: Meeting) -> Bool {
        !m.isImpromptu && !m.isImported && (m.calendarName?.isEmpty == false)
    }

    /// Write the meeting recap (summary + deep link) into the calendar event's
    /// notes, in place. Full calendar access is requested at onboarding.
    func addRecapToCalendar(_ m: Meeting) {
        let summary = manager.summaryMarkdown(for: m)
        let recap = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Recorded with MeetingScribe — recap pending."
            : summary
        let link = WorkspaceLink.url(kind: .meeting, id: m.id).absoluteString
        Task {
            let ok = await CalendarStoreActor.shared.attachRecap(
                toEventID: m.id, markdown: recap, deepLink: link)
            await MainActor.run {
                infoAlert(ok
                    ? "Recap added to the calendar event."
                    : "Couldn't update the event — it may have been deleted or you don't have write access to that calendar.")
            }
        }
    }

    /// Create a follow-up event `days` after the meeting, same time of day.
    func scheduleFollowUp(_ m: Meeting, days: Int) {
        guard let start = Calendar.current.date(byAdding: .day, value: days, to: m.startDate) else { return }
        let link = WorkspaceLink.url(kind: .meeting, id: m.id).absoluteString
        Task {
            let id = await CalendarStoreActor.shared.scheduleFollowUp(
                title: "Follow-up: \(m.displayTitle)",
                start: start, durationMinutes: 30,
                notes: "Follow-up to the meeting on \(timeRange()).\n\(link)")
            await MainActor.run {
                let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
                infoAlert(id != nil
                    ? "Follow-up scheduled for \(f.string(from: start))."
                    : "Couldn't create the event. Check calendar access in Settings.")
            }
        }
    }

    private func infoAlert(_ message: String) {
        // U3-11: an in-app toast instead of a blocking NSAlert modal — modal
        // jank reads cheap, and these are informational confirmations.
        ToastCenter.shared.show(message)
    }

    // MARK: - Open in Obsidian (C3-x)

    /// Deep-link the meeting's canonical markdown open in Obsidian. Best-effort:
    /// requires Obsidian installed with this vault added.
    func openInObsidian(_ m: Meeting) {
        guard let url = manager.canonicalMarkdownURL(for: m) else {
            infoAlert("No exported markdown yet — finalize the meeting first.")
            return
        }
        var comps = URLComponents()
        comps.scheme = "obsidian"
        comps.host = "open"
        comps.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let obsURL = comps.url {
            NSWorkspace.shared.open(obsURL)
        }
    }

    func exportDocument(for m: Meeting,
                        selection: MeetingExporter.ShareSelection = .init()) -> String {
        MeetingExporter.combinedMarkdown(
            title: m.displayTitle,
            dateString: timeRange(),
            attendees: m.attendees,
            summary: manager.summaryMarkdown(for: m),
            notes: noteDraft.isEmpty ? manager.userNotes(for: m) : noteDraft,
            transcript: manager.transcriptMarkdown(for: m),
            selection: selection)
    }

    /// Shows the "what's included" confirm (private notes off by default), then
    /// builds the export document for the chosen sections. Returns nil if the
    /// user cancels. (U4-3)
    func confirmedExportDocument(for m: Meeting) -> String? {
        let summary = manager.summaryMarkdown(for: m)
        let notes = noteDraft.isEmpty ? manager.userNotes(for: m) : noteDraft
        let transcript = manager.transcriptMarkdown(for: m)
        func hasText(_ s: String) -> Bool {
            !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let selection = MeetingExporter.confirmShareSelection(
            hasSummary: hasText(summary),
            hasNotes: hasText(notes),
            hasTranscript: hasText(transcript)
        ) else { return nil }
        return exportDocument(for: m, selection: selection)
    }

    @ViewBuilder
    var recordingHealthRow: some View {
        let h = recordingMonitor.recordingHealth
        HStack(spacing: 10) {
            healthDot(label: "Mic", ageSeconds: Int(h.micSecondsSinceLastSample),
                      hasData: h.micSamples > 0, restartCount: h.micRestarts)
            healthDot(label: "Sys", ageSeconds: Int(h.systemSecondsSinceLastSample),
                      hasData: h.systemSamples > 0, restartCount: h.systemRestarts)
            if let err = h.lastError {
                Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(1).help(err)
            }
        }
    }

    func healthDot(label: String, ageSeconds: Int, hasData: Bool, restartCount: Int) -> some View {
        let color: Color = !hasData ? .secondary : ageSeconds > 8 ? .red : ageSeconds > 3 ? .yellow : .green
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label): \(hasData ? "\(ageSeconds)s" : "—")")
                .font(.caption2).foregroundStyle(.secondary)
            if restartCount > 0 {
                Text("·\(restartCount)↺").font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Attendee chip

private struct AttendeeChip: View {
    let attendee: String
    /// Called on tap to open the inline connect panel inside the meeting detail
    /// (instead of jumping to the People tab). The host passes the attendee
    /// string back so the panel can parse name/email and offer connect/create.
    var onConnect: ((String) -> Void)? = nil
    @EnvironmentObject var router: WorkspaceRouter
    // Observe the store so the "already in People" dot updates live after you
    // create/tag a person — it read PeopleStore.shared statically before. (SP-3)
    @EnvironmentObject var people: PeopleStore

    // Parsed once through the one identity layer (P1-1) — no more bespoke
    // substring parsing here.
    private var identity: AttendeeIdentity { PersonResolver.parse(attendee) }

    /// Full name (or email localpart), for creating a Person.
    private var fullName: String {
        identity.hasName ? identity.name : PersonResolver.localPart(of: identity.email)
    }

    private var displayName: String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    private var email: String { identity.email }

    private var existingPerson: Person? {
        guard let id = PersonResolver.resolve(identity: identity, in: people.people) else { return nil }
        return people.person(by: id)
    }

    var body: some View {
        // Left-click opens an inline connect panel inside the meeting (D1-5,
        // refined): instead of jumping to the People tab, the user can link this
        // attendee to a saved person or add them as a new one without losing the
        // meeting context. A filled dot marks attendees already in People.
        Button(action: openConnectPanel) {
            let linked = existingPerson != nil
            HStack(spacing: 5) {
                // Shared avatar so attendees read identically to People rows.
                MSAvatar(name: fullName, size: 20)
                Text(displayName)
                    .scaledFont(12)
                    .foregroundStyle(linked ? NDS.textPrimary : NDS.textSecondary)
                    .lineLimit(1)
                // D5-10: a legible linked state — a clear checkmark badge when in
                // People, a subtle "+" hint when not, instead of a 5pt dot.
                Image(systemName: linked ? "checkmark.circle.fill" : "plus.circle")
                    .scaledFont(11)
                    .foregroundStyle(linked ? NDS.mint : NDS.textTertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(linked ? NDS.mint.opacity(0.12) : NDS.fieldBg, in: Capsule())
            .overlay(Capsule().strokeBorder(linked ? NDS.mint.opacity(0.3) : NDS.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(existingPerson == nil ? "Connect \(fullName) to a person" : "Manage \(fullName)")
        .contextMenu {
            Button(action: openConnectPanel) {
                Label(existingPerson == nil ? "Connect to a person…" : "Manage link…",
                      systemImage: "person.crop.circle.badge.plus")
            }
            if let p = existingPerson {
                Button { router.openPerson(p.id) } label: {
                    Label("Open in People", systemImage: "arrow.up.forward.app")
                }
            }
        }
    }

    /// Open the inline connect panel within the meeting detail. Falls back to
    /// the canonical People-tab route only if no host handler is wired.
    private func openConnectPanel() {
        if let onConnect {
            onConnect(attendee)
        } else if let p = existingPerson {
            router.openPerson(p.id)
        } else {
            let p = people.createPerson(displayName: fullName, email: email)
            router.openPerson(p.id)
        }
    }
}

// MARK: - Recurring chip → Series Hub (C1-4)

/// The "Recurring" header chip, made tappable. It owns the Series Hub sheet's
/// presentation state itself (a self-contained subview) so the host detail view
/// needs no new `@State` — and no router section is added. The hub inherits the
/// detail view's `MeetingManager` / `WorkspaceRouter` environment objects.
@available(macOS 14.0, *)
private struct RecurringChip: View {
    let meeting: Meeting
    let priorCount: Int
    @State private var showHub = false

    var body: some View {
        Button { showHub = true } label: {
            HStack(spacing: 6) {
                NotionChip("Recurring", color: NDS.selectColor("purple"), systemImage: "repeat")
                if priorCount > 0 {
                    Text("\(priorCount) previous")
                        .scaledFont(11, relativeTo: .caption2)
                        .foregroundStyle(NDS.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the series hub — timeline, open follow-ups, and decisions across every occurrence.")
        .sheet(isPresented: $showHub) {
            SeriesHubView(meeting: meeting)
        }
    }
}
