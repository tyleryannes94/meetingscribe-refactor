import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    // MARK: - Header

var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    titleAndDescription
                    HStack(spacing: 8) {
                        Text(timeRange()).font(.caption).foregroundStyle(.secondary)
                        // Full-width health badge for the detail view —
                        // hover popover lists the recorder's specific
                        // warnings (audit 8.1).
                        if case .past = mode {
                            MeetingHealthBadge(health: meeting?.health)
                        }
                    }
                    if let cal = meeting?.calendarName {
                        Text("Calendar: \(cal)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if isRecurring {
                        HStack(spacing: 6) {
                            NotionChip("Recurring", color: NDS.selectColor("purple"), systemImage: "repeat")
                            if !priorOccurrences.isEmpty {
                                Text("\(priorOccurrences.count) previous call\(priorOccurrences.count == 1 ? "" : "s")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer()
                headerButtons
            }
            if let m = meeting, !m.attendees.isEmpty {
                Text(m.attendees.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let url = meeting?.conferenceURL, let u = URL(string: url) {
                Link(destination: u) {
                    Label(url, systemImage: "link").font(.caption)
                }
            }
            if let m = meeting {
                TagPicker(meeting: m, propagateToSeries: m.seriesID != nil)
            }
            if case .upcoming = mode, let m = meeting {
                upcomingActionRow(m)
            }
            statusBanner
        }
        .padding()
    }

    @ViewBuilder
var titleAndDescription: some View {
        if editingHeader, let _ = meeting {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            TextField("Quick description (optional)", text: $descriptionDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .lineLimit(2...4)
        } else {
            Text(meeting?.displayTitle ?? "Untitled").font(.title2).bold()
            if let d = meeting?.userDescription, !d.isEmpty {
                Text(d).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
var headerButtons: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if editingHeader {
                HStack {
                    Button("Cancel") { editingHeader = false; resetDrafts() }.controlSize(.small)
                    Button("Save") { saveHeader() }.controlSize(.small).keyboardShortcut(.defaultAction)
                }
            } else if meeting != nil {
                Button {
                    editingHeader = true
                } label: { Label("Edit", systemImage: "pencil") }
                .controlSize(.small)
            }
            switch mode {
            case .live:
                if case .recording = manager.state {
                    Button(role: .destructive) {
                        Task { await manager.stopRecording() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.small)
                }
            case .past(let m):
                if manager.isTranscribingMeeting(m) {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        manager.transcribeNow(meeting: m)
                    } label: {
                        Label("Transcribe Now", systemImage: "text.bubble")
                    }
                    .controlSize(.small)
                    .disabled(!manager.hasAudio(for: m))
                    .help(manager.hasAudio(for: m)
                          ? "Re-merges all audio segments and re-runs whisper + summary."
                          : "No audio recorded for this meeting yet.")
                }
                // Past detail's join + re-record actions — never disabled even
                // if a different recording is active; that's intentional, the
                // join flow auto-switches recordings.
                if m.conferenceURL != nil {
                    Button {
                        if let url = m.conferenceURL.flatMap(URL.init(string:)) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: { Label("Join Call", systemImage: "video") }
                    .controlSize(.small)
                    .help("Re-open the meeting link without starting a recording.")
                    Button {
                        Task { await manager.switchToRecording(m) }
                    } label: { Label("Join & Record Again", systemImage: "video.fill") }
                    .controlSize(.small)
                    .help("Open the link AND start a new recording for this meeting (stops any current recording).")
                }
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
                .controlSize(.small)
                .help("Appends a new audio segment. Stops any currently-running recording first. The transcript merges all segments.")
                Button {
                    manager.revealInFinder(m)
                } label: { Label("Reveal", systemImage: "folder") }
                .controlSize(.small)
                recoverMenu(for: m)
                exportMenu(for: m)
            case .upcoming:
                EmptyView()
            }
        }
    }

    /// Failsafe actions: recover audio from the meeting folder (e.g. after a
    /// crash or iCloud eviction), or manually upload an audio/transcript file.
func recoverMenu(for m: Meeting) -> some View {
        Menu {
            Button {
                manager.recoverAudio(for: m)
            } label: { Label("Recover Audio from Folder", systemImage: "arrow.clockwise.icloud") }
                .help("Re-download (from iCloud if needed), re-scan this meeting's folder, and transcribe any audio found.")
            Divider()
            Button {
                showAudioImporter = true
            } label: { Label("Upload Audio…", systemImage: "waveform.badge.plus") }
            Button {
                showTranscriptImporter = true
            } label: { Label("Upload Transcript…", systemImage: "doc.badge.plus") }
        } label: {
            Label("Recover", systemImage: "stethoscope")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .help("Recover or manually add audio/transcript for this meeting.")
    }

func exportMenu(for m: Meeting) -> some View {
        Menu {
            Button {
                MeetingExporter.exportMarkdown(exportDocument(for: m), suggestedName: m.slug)
            } label: { Label("Markdown (.md)", systemImage: "doc.plaintext") }
            Button {
                MeetingExporter.exportPDF(exportDocument(for: m), suggestedName: m.slug)
            } label: { Label("PDF (.pdf)", systemImage: "doc.richtext") }
            Divider()
            Button {
                exportToDrive(m)
            } label: { Label(drive.isConnected ? "Google Drive" : "Google Drive (connect in Settings)",
                             systemImage: "arrow.up.doc") }
            Button {
                exportToObsidian(m)
            } label: { Label("Obsidian (vault)", systemImage: "doc.text.below.ecg") }
        } label: {
            if drive.isWorking {
                ProgressView().controlSize(.small)
            } else {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .help("Export this meeting's summary, notes, and transcript.")
    }

func exportToDrive(_ m: Meeting) {
        guard drive.isConnected else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            return
        }
        let doc = exportDocument(for: m)
        Task { try? await drive.exportMarkdown(filename: m.slug, content: doc) }
    }

func exportToObsidian(_ m: Meeting) {
        // Meeting tags make the most useful Obsidian #tags; falls back to just
        // the default "meeting" tag when none are set.
        let tagNames = tagStore.tagIDs(for: m).compactMap { tagStore.tag(by: $0)?.name }
        let md = ObsidianExporter.markdown(
            for: m,
            summary: manager.summaryMarkdown(for: m),
            notes: noteDraft.isEmpty ? manager.userNotes(for: m) : noteDraft,
            transcript: manager.transcriptMarkdown(for: m),
            tags: tagNames)
        ObsidianExporter.export(md, filename: m.slug)
    }

func exportDocument(for m: Meeting) -> String {
        MeetingExporter.combinedMarkdown(
            title: m.displayTitle,
            dateString: timeRange(),
            attendees: m.attendees,
            summary: manager.summaryMarkdown(for: m),
            notes: noteDraft.isEmpty ? manager.userNotes(for: m) : noteDraft,
            transcript: manager.transcriptMarkdown(for: m))
    }

func upcomingActionRow(_ m: Meeting) -> some View {
        // Buttons are intentionally NEVER disabled. If a recording is already
        // in progress, joining a new meeting auto-stops the old one and
        // starts the new one (via MeetingManager.switchToRecording).
        HStack(spacing: 8) {
            if m.conferenceURL != nil {
                Button {
                    if let url = m.conferenceURL.flatMap(URL.init(string:)) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Join Call", systemImage: "video")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .help("Open the meeting link without starting a recording.")

                Button {
                    Task { await manager.switchToRecording(m) }
                } label: {
                    Label("Join Call & Start Recording", systemImage: "video.fill")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .help(isAppIdle ? "Join the call and start recording."
                                : "Join the call — current recording will stop and a new one will start.")
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
                Label("Record Only", systemImage: "record.circle").padding(.horizontal, 6)
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
var statusBanner: some View {
        if case .live = mode, case .recording = manager.state {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                    Text("Recording")
                        .font(.callout).bold()
                    AudioLevelMeter(micLevel: recordingMonitor.recordingHealth.micLevel,
                                    systemLevel: recordingMonitor.recordingHealth.systemLevel,
                                    bars: 14, height: 22)
                        .frame(maxWidth: 200)
                    Spacer()
                    if manager.liveTranscriber.pendingCount > 0 {
                        Label("\(manager.liveTranscriber.pendingCount) chunk\(manager.liveTranscriber.pendingCount == 1 ? "" : "s") processing",
                              systemImage: "hourglass")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                recordingHealthRow
            }
        } else if let m = meeting, manager.isTranscribingMeeting(m) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Finalizing transcript + summary…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if let m = meeting, manager.wasInterrupted(m) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recording may be incomplete").font(.callout).bold()
                    Text("This recording didn't finish cleanly (the app may have quit). Its audio is on disk — recover it to transcribe.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    manager.recoverAudio(for: m)
                } label: { Label("Recover Audio", systemImage: "arrow.clockwise.icloud") }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: NDS.radius))
        }
    }

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

    /// Inline indicator: green dot when both sources are flowing, yellow/red
    /// when a source has stalled. Surfaces the underlying error if any source
    /// restarted because of a problem (mic disconnect, SCStream stop, etc).
    @ViewBuilder
var recordingHealthRow: some View {
        let h = recordingMonitor.recordingHealth
        let micAge = Int(h.micSecondsSinceLastSample)
        let sysAge = Int(h.systemSecondsSinceLastSample)
        HStack(spacing: 12) {
            healthDot(label: "Mic",
                      ageSeconds: micAge,
                      hasData: h.micSamples > 0,
                      restartCount: h.micRestarts)
            healthDot(label: "System",
                      ageSeconds: sysAge,
                      hasData: h.systemSamples > 0,
                      restartCount: h.systemRestarts)
            if let err = h.lastError {
                Text(err)
                    .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    .help(err)
            }
            Spacer()
        }
    }

func healthDot(label: String, ageSeconds: Int, hasData: Bool, restartCount: Int) -> some View {
        let color: Color = !hasData ? .secondary
                           : ageSeconds > 8 ? .red
                           : ageSeconds > 3 ? .yellow
                           : .green
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) — \(hasData ? "\(ageSeconds)s ago" : "no samples yet")")
                .font(.caption2).foregroundStyle(.secondary)
            if restartCount > 0 {
                Text("· \(restartCount) restart\(restartCount == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}
