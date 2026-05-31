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
                            AttendeeChip(attendee: a)
                        }
                        if m.attendees.count > 12 {
                            Text("+\(m.attendees.count - 12)")
                                .font(.system(size: 11))
                                .foregroundStyle(NDS.textTertiary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(NDS.fieldBg, in: Capsule())
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
                        .font(.system(size: 11))
                        .foregroundStyle(NDS.brand)
                    Link(url, destination: u)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
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
                    .font(.system(size: 22, weight: .bold))
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 6))
                TextField("Quick description (optional)", text: $descriptionDraft, axis: .vertical)
                    .font(.system(size: 13))
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
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(NDS.textPrimary)
                .textSelection(.enabled)
            if let d = meeting?.userDescription, !d.isEmpty {
                Text(d)
                    .font(.system(size: 13))
                    .foregroundStyle(NDS.textSecondary)
            }
        }
    }

    // MARK: - Meta line (date/time + health)

    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(timeRange())
                .font(.system(size: 12))
                .foregroundStyle(NDS.textSecondary)
            if case .past = mode {
                MeetingHealthBadge(health: meeting?.health)
            }
            if let m = meeting, manager.isTranscribingMeeting(m) {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Processing…")
                        .font(.system(size: 11))
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
                    Text("Processing…").font(.system(size: 12)).foregroundStyle(NDS.textSecondary)
                }
            } else if manager.hasAudio(for: m) && (transcript.isEmpty) {
                Button { manager.transcribeNow(meeting: m) } label: {
                    Label("Transcribe Now", systemImage: "text.bubble")
                }
                .buttonStyle(MSPrimaryButtonStyle())
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

                // Transcription
                if !manager.isTranscribingMeeting(m) {
                    Button {
                        manager.transcribeNow(meeting: m)
                    } label: {
                        Label("Transcribe Now", systemImage: "text.bubble")
                    }
                    .disabled(!manager.hasAudio(for: m))
                }

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
                }
            }

        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .frame(width: NDS.buttonIconSide, height: NDS.buttonSecondaryH)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NDS.hairline, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More actions")
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
        PeopleStore.shared.people.first {
            $0.displayName.caseInsensitiveCompare(fullName) == .orderedSame
            || (!email.isEmpty && $0.emails.contains { $0.caseInsensitiveCompare(email) == .orderedSame })
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(NDS.selectColor(displayName))
                .frame(width: 20, height: 20)
                .overlay(
                    Text(initials.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text(displayName)
                .font(.system(size: 12))
                .foregroundStyle(NDS.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(NDS.fieldBg, in: Capsule())
        .help(attendee)
        .contextMenu {
            if existingPerson == nil {
                Button {
                    _ = PeopleStore.shared.createPerson(displayName: fullName, email: email)
                } label: { Label("Add to People", systemImage: "person.crop.circle.badge.plus") }
            } else {
                Label("Already in People", systemImage: "checkmark")
            }
        }
    }
}
