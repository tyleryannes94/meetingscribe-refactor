import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main title row
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    titleAndDescription
                    metaLine
                    chipRow
                }
                Spacer(minLength: 12)
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            // Attendees line — full width, below title
            if let m = meeting, !m.attendees.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(m.attendees.prefix(12), id: \.self) { a in
                            AttendeeChip(attendee: a) { connectingAttendee = $0 }
                        }
                        if m.attendees.count > 12 {
                            Text("+\(m.attendees.count - 12)")
                                .scaledFont(11)
                                .foregroundStyle(NDS.textTertiary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(NDS.fieldBg, in: Capsule())
                        }
                        // One-click add every attendee not yet in People. (TM-9)
                        if unaddedAttendeeCount(m) > 0 {
                            Button { addAllAttendeesToPeople(m) } label: {
                                Label("Add \(unaddedAttendeeCount(m)) to People",
                                      systemImage: "person.crop.circle.badge.plus")
                                    .scaledFont(11)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)
            }

            // Conference URL — prominent, tappable
            if let url = meeting?.conferenceURL, let u = URL(string: url) {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .scaledFont(11)
                        .foregroundStyle(NDS.brand)
                    Link(url, destination: u)
                        .scaledFont(12)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Source picker — user-editable. Lets the user correctly tag an
            // impromptu recording, or override the URL guess on a calendar
            // event whose link is hidden in the body.
            if let m = meeting {
                sourcePickerRow(for: m)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            // Tags
            if let m = meeting {
                TagPicker(meeting: m, propagateToSeries: m.seriesID != nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            // Upcoming action bar
            if case .upcoming = mode, let m = meeting {
                upcomingActionRow(m)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            // Status/warning banner
            if showStatusBanner {
                statusBanner
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            Divider().overlay(NDS.divider)
        }
    }

    // MARK: - Title + description

    @ViewBuilder
    var titleAndDescription: some View {
        if editingHeader {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $titleDraft)
                    .scaledFont(22, weight: .bold)
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
                .scaledFont(24, weight: .bold)
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
            if isRecurring {
                NotionChip("Recurring", color: NDS.selectColor("purple"), systemImage: "repeat")
                if !priorOccurrences.isEmpty {
                    Text("\(priorOccurrences.count) previous")
                        .font(.caption2)
                        .foregroundStyle(NDS.textTertiary)
                }
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
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3").scaledFont(12, weight: .medium)
                Text("Options").scaledFont(12, weight: .medium)
            }
            .padding(.horizontal, 11)
            .frame(height: NDS.buttonSecondaryH)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NDS.hairline, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Meeting options — edit, re-transcribe, recover, export")
    }

    // MARK: - Source picker

    @ViewBuilder
    func sourcePickerRow(for m: Meeting) -> some View {
        let current = m.effectiveSource
        let isAutoDetected = m.userSource == nil && current != nil
        HStack(spacing: 6) {
            Image(systemName: current?.systemImage ?? "questionmark.circle")
                .scaledFont(11)
                .foregroundStyle(NDS.textSecondary)
            Menu {
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
            } label: {
                HStack(spacing: 4) {
                    Text(current?.displayName ?? "Set source")
                        .scaledFont(12)
                        .foregroundStyle(current == nil ? NDS.textTertiary : NDS.textSecondary)
                    if isAutoDetected {
                        Text("· auto")
                            .scaledFont(11)
                            .foregroundStyle(NDS.textTertiary)
                    }
                    Image(systemName: "chevron.down")
                        .scaledFont(9)
                        .foregroundStyle(NDS.textTertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Where this meeting is happening — used to match auto-record against the call you've actually joined.")
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

    // MARK: - Add all attendees to People (TM-9)

    /// (fullName, email) for an attendee string "Name <email>".
    private func parseAttendee(_ a: String) -> (name: String, email: String) {
        let name = a.components(separatedBy: "<").first?
            .trimmingCharacters(in: .whitespaces) ?? a
        var email = ""
        if let lt = a.firstIndex(of: "<"), let gt = a.firstIndex(of: ">"), lt < gt {
            email = String(a[a.index(after: lt)..<gt]).trimmingCharacters(in: .whitespaces)
        }
        return (name.isEmpty ? a : name, email)
    }

    private func attendeeExists(_ a: String) -> Bool {
        let p = parseAttendee(a)
        return PeopleStore.shared.people.contains { person in
            person.displayName.caseInsensitiveCompare(p.name) == .orderedSame
            || (!p.email.isEmpty && person.emails.contains { $0.caseInsensitiveCompare(p.email) == .orderedSame })
        }
    }

    func unaddedAttendeeCount(_ m: Meeting) -> Int {
        m.attendees.filter { !attendeeExists($0) }.count
    }

    func addAllAttendeesToPeople(_ m: Meeting) {
        var created: [Person] = []
        for a in m.attendees where !attendeeExists(a) {
            let p = parseAttendee(a)
            let person = PeopleStore.shared.createPerson(displayName: p.name, email: p.email)
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
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    private var initials: String {
        // Extract display name (before <email>)
        let name = attendee.components(separatedBy: "<").first?
            .trimmingCharacters(in: .whitespaces) ?? attendee
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "?" }
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(parts[0].prefix(2))
    }

    private var displayName: String {
        attendee.components(separatedBy: "<").first?
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? attendee
    }

    /// Full name (everything before an "<email>"), for creating a Person.
    private var fullName: String {
        let n = attendee.components(separatedBy: "<").first?
            .trimmingCharacters(in: .whitespaces) ?? attendee
        return n.isEmpty ? attendee : n
    }

    /// Email inside "Name <email>", if present.
    private var email: String {
        guard let lt = attendee.firstIndex(of: "<"),
              let gt = attendee.firstIndex(of: ">"), lt < gt else { return "" }
        return String(attendee[attendee.index(after: lt)..<gt]).trimmingCharacters(in: .whitespaces)
    }

    private var existingPerson: Person? {
        people.people.first {
            $0.displayName.caseInsensitiveCompare(fullName) == .orderedSame
            || (!email.isEmpty && $0.emails.contains { $0.caseInsensitiveCompare(email) == .orderedSame })
        }
    }

    var body: some View {
        // Left-click opens an inline connect panel inside the meeting (D1-5,
        // refined): instead of jumping to the People tab, the user can link this
        // attendee to a saved person or add them as a new one without losing the
        // meeting context. A filled dot marks attendees already in People.
        Button(action: openConnectPanel) {
            HStack(spacing: 5) {
                Circle()
                    .fill(NDS.selectColor(displayName))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(initials.uppercased())
                            .scaledFont(8, weight: .bold)
                            .foregroundStyle(.white)
                    )
                Text(displayName)
                    .scaledFont(12)
                    .foregroundStyle(NDS.textSecondary)
                    .lineLimit(1)
                if existingPerson != nil {
                    Circle().fill(Color.green.opacity(0.7)).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(NDS.fieldBg, in: Capsule())
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
