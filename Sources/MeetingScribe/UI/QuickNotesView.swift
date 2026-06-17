import SwiftUI
import AppKit
import UniformTypeIdentifiers

@available(macOS 14.0, *)
struct QuickNotesView: View {
    @EnvironmentObject var manager: MeetingManager
    /// Scoped observation: quick-notes UI invalidates ONLY when the
    /// QuickNotesController publishes — not when unrelated MeetingManager
    /// state changes (audit 6.3). The `manager` reference above is kept
    /// for the legacy forwarding-shim API; new code paths should route
    /// through `quickNotes` directly.
    @EnvironmentObject var quickNotes: QuickNotesController
    @EnvironmentObject var router: WorkspaceRouter
    @State private var selection: String?
    @State private var importing = false

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 240, idealWidth: 320, maxWidth: 360)
            detail.frame(minWidth: 380)
        }
        // FloatingOverlay's "Go to Recording" button → select that note here.
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeOpenVoiceNote)) { notif in
            if let id = notif.userInfo?["id"] as? String {
                manager.refreshQuickNotes()
                selection = id
            }
        }
        // Deep-link routing via the router mailbox (D1-3): consumed on appear so
        // it lands even when the Notes tab is built for the first time.
        .onAppear { consumeRouterVoiceNote() }
        .onChange(of: router.pendingRoute) { _, _ in consumeRouterVoiceNote() }
    }

    private func consumeRouterVoiceNote() {
        if case .voiceNote(let id)? = router.pendingRoute {
            manager.refreshQuickNotes()
            selection = id
            router.consume(.voiceNote(id))
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Notes").scaledFont(22, weight: .bold, kind: .display)
                Text("\(manager.quickNotes.count)")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Spacer()
                importButton
                recordButton
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            Divider().overlay(NDS.divider)
            if manager.quickNotes.isEmpty {
                MSEmptyState(systemImage: "waveform.badge.plus",
                             title: "No notes yet",
                             message: "Record a note, or import an audio file — it'll be transcribed locally.") {
                    Button { importNote() } label: {
                        Label("Import audio file", systemImage: "square.and.arrow.down")
                    }
                }
            } else {
                List(selection: $selection) {
                    ForEach(manager.quickNotes) { note in
                        QuickNoteRow(note: note)
                            .tag(note.id)
                    }
                    .onDelete { idxs in
                        for i in idxs {
                            let n = manager.quickNotes[i]
                            manager.deleteQuickNote(n)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { manager.refreshQuickNotes() }
    }

    @ViewBuilder
    private var importButton: some View {
        if importing {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small) // design-lint:allow
                Text("Importing…").font(.caption)
            }
        } else {
            Button {
                importNote()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import an audio file (m4a, mp3, wav…) — it'll be transcribed automatically.")
        }
    }

    private func importNote() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose audio file(s) to import and transcribe"
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }
        importing = true
        Task {
            var firstID: String?
            for url in urls {
                let id = await manager.importVoiceNote(from: url)
                if firstID == nil { firstID = id }
            }
            importing = false
            if let firstID { selection = firstID }
        }
    }

    @ViewBuilder
    private var recordButton: some View {
        switch manager.quickRecordState {
        case .idle:
            Button {
                Task { await manager.startQuickNote() }
            } label: {
                Label("New Note", systemImage: "mic.circle.fill")
            }
        case .recording:
            Button(role: .destructive) {
                Task { await manager.stopQuickNote() }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
            }
        case .transcribing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small) // design-lint:allow
                Text("Transcribing…").font(.caption)
            }
        case .error(let msg):
            Button("Retry") { Task { await manager.startQuickNote() } }.help(msg)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let note = manager.quickNotes.first(where: { $0.id == id }) {
            QuickNoteDetail(note: note)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .scaledFont(40).foregroundStyle(.secondary)
                Text("Pick a note from the sidebar.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 14.0, *)
struct QuickNoteRow: View {
    @EnvironmentObject var manager: MeetingManager
    let note: QuickNote

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(note.title).font(.callout).lineLimit(1)
                    if note.wasDictation {
                        Image(systemName: "keyboard").font(.caption2).foregroundStyle(.secondary)
                    }
                    if manager.isTranscribingQuickNote(note) {
                        ProgressView().controlSize(.mini) // design-lint:allow
                    } else if manager.isPolishingQuickNote(note) {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(.purple)
                    } else if manager.lastErrorForQuickNote(note) != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                Text(note.snippet.isEmpty
                     ? (manager.isTranscribingQuickNote(note) ? "Transcribing…" : "—")
                     : note.snippet)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    Text(relativeDate(note.createdAt))
                    Text("·")
                    Text(durationString(note.durationSeconds))
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
    private func durationString(_ s: Double) -> String {
        let total = Int(s.rounded())
        let m = total / 60; let r = total % 60
        return m > 0 ? "\(m)m \(r)s" : "\(r)s"
    }
}

/// Voice-note detail. Header on top, audio bar, then two editable panes
/// side by side — Polished (left) and Raw (right). Each pane has its
/// own Copy + Re-run button. Edits to either pane are debounced and
/// persisted to disk.
///
/// Auto-polish runs the moment whisper finishes — the user never needs
/// to click anything to see a polished version.
@available(macOS 14.0, *)
struct QuickNoteDetail: View {
    let note: QuickNote
    @EnvironmentObject var manager: MeetingManager
    @ObservedObject private var drive = GoogleDriveService.shared

    @State private var rawDraft: String = ""
    @State private var polishedDraft: String = ""
    @State private var promptDraft: String = ""
    @State private var lastSavedRaw: String = ""
    @State private var lastSavedPolished: String = ""
    @State private var lastSavedPrompt: String = ""
    @State private var rawSaveTimer: Timer?
    @State private var polishedSaveTimer: Timer?
    @State private var promptSaveTimer: Timer?
    @State private var rawCopied = false
    @State private var polishedCopied = false
    @State private var promptCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            audio
            if let err = manager.lastErrorForQuickNote(note) {
                Divider()
                errorBanner(err)
            }
            Divider()
            sideBySide
        }
        .onAppear { reload() }
        .onChange(of: manager.quickNotesTranscribing) { _, _ in reloadIfNoUserEdits() }
        .onChange(of: manager.quickNotesPolishing) { _, _ in reloadIfNoUserEdits() }
        .onChange(of: manager.quickNotesStructuringPrompt) { _, _ in reloadIfNoUserEdits() }
        .onDisappear { flushSaves() }
        .id(note.id)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.title2).bold()
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                statusPill
                exportMenu
                Button {
                    manager.reTranscribeQuickNote(note)
                } label: {
                    Label(rawDraft.isEmpty ? "Transcribe" : "Re-transcribe",
                          systemImage: "text.bubble")
                }
                .help("Re-run whisper on the recorded audio. Polishing runs automatically after.")
                .disabled(manager.isTranscribingQuickNote(note))
            }
        }
        .padding()
    }

    private var exportMenu: some View {
        Menu {
            Button {
                MeetingExporter.exportMarkdown(exportContent(), suggestedName: note.title)
            } label: { Label("Markdown (.md)", systemImage: "doc.plaintext") }
            Divider()
            Button {
                exportToDrive()
            } label: { Label(drive.isConnected ? "Google Drive" : "Google Drive (connect in Settings)",
                             systemImage: "arrow.up.doc") }
        } label: {
            if drive.isWorking { ProgressView().controlSize(.small) } // design-lint:allow
            else { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(rawDraft.isEmpty && polishedDraft.isEmpty)
        .help("Export this note's transcript.")
    }

    private func exportContent() -> String {
        let body = polishedDraft.isEmpty ? rawDraft : polishedDraft
        let date = note.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "# \(note.title)\n\n_\(date)_\n\n\(body)\n"
    }

    private func exportToDrive() {
        guard drive.isConnected else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            return
        }
        let content = exportContent()
        let name = note.title
        Task { try? await drive.exportMarkdown(filename: name, content: content) }
    }

    @ViewBuilder
    private var statusPill: some View {
        if manager.isTranscribingQuickNote(note) {
            inlineStatus("Transcribing…", icon: "ear", color: .blue, spinner: true)
        } else if manager.isPolishingQuickNote(note) {
            inlineStatus("Polishing…", icon: "sparkles", color: .purple, spinner: true)
        }
    }

    private func inlineStatus(_ text: String, icon: String, color: Color, spinner: Bool) -> some View {
        HStack(spacing: 5) {
            if spinner { ProgressView().controlSize(.small) } // design-lint:allow
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(err).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    @ViewBuilder
    private var audio: some View {
        let url = manager.quickNoteAudioURL(note)
        if FileManager.default.fileExists(atPath: url.path) {
            AudioPlayerView(url: url)
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Side-by-side editors

    private var sideBySide: some View {
        HSplitView {
            pane(
                title: "Polished",
                subtitle: "Cleaned-up version (auto-generated)",
                icon: "sparkles",
                accent: .purple,
                text: $polishedDraft,
                isInFlight: manager.isPolishingQuickNote(note),
                inFlightText: "Polishing transcript…",
                emptyPlaceholder: emptyPolishedPlaceholder,
                copied: $polishedCopied,
                onCopy: { copy(polishedDraft, into: $polishedCopied) },
                onRerun: { manager.repolishQuickNote(note) },
                rerunLabel: "Re-polish",
                rerunDisabled: rawDraft.isEmpty || manager.isPolishingQuickNote(note),
                onChange: { schedulePolishedSave() }
            )
            pane(
                title: "Raw",
                subtitle: "Original whisper output",
                icon: "text.alignleft",
                accent: .blue,
                text: $rawDraft,
                isInFlight: manager.isTranscribingQuickNote(note),
                inFlightText: "Transcribing…",
                emptyPlaceholder: emptyRawPlaceholder,
                copied: $rawCopied,
                onCopy: { copy(rawDraft, into: $rawCopied) },
                onRerun: { manager.reTranscribeQuickNote(note) },
                rerunLabel: "Re-transcribe",
                rerunDisabled: manager.isTranscribingQuickNote(note),
                onChange: { scheduleRawSave() }
            )
            pane(
                title: "AI Prompt",
                subtitle: "TCREI-structured prompt (optional)",
                icon: "wand.and.stars",
                accent: .green,
                text: $promptDraft,
                isInFlight: manager.isStructuringQuickNotePrompt(note),
                inFlightText: "Structuring prompt…",
                emptyPlaceholder: emptyPromptPlaceholder,
                copied: $promptCopied,
                onCopy: { copy(promptDraft, into: $promptCopied) },
                onRerun: { manager.regenerateQuickNotePrompt(note) },
                rerunLabel: promptDraft.isEmpty ? "Generate" : "Regenerate",
                rerunDisabled: rawDraft.isEmpty || manager.isStructuringQuickNotePrompt(note),
                onChange: { schedulePromptSave() }
            )
        }
    }

    private var emptyPolishedPlaceholder: String {
        if manager.isTranscribingQuickNote(note) { return "Waiting for transcript…" }
        if rawDraft.isEmpty { return "No transcript yet." }
        return "Polished version not generated yet. The polish pass runs automatically — if you're seeing this, Ollama may have been unreachable. Click Re-polish to retry."
    }

    private var emptyRawPlaceholder: String {
        if manager.isTranscribingQuickNote(note) { return "Whisper is running…" }
        return "No transcript yet. Click Re-transcribe to run whisper against the recorded audio."
    }

    private var emptyPromptPlaceholder: String {
        if manager.isTranscribingQuickNote(note) { return "Waiting for transcript…" }
        if rawDraft.isEmpty { return "No transcript yet." }
        return "Optional. Click Generate to rewrite the transcript into a structured AI prompt (Task, Context, References, Evaluate, Iterate). Or use the prompt hotkey right after dictating."
    }

    @ViewBuilder
    private func pane(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        text: Binding<String>,
        isInFlight: Bool,
        inFlightText: String,
        emptyPlaceholder: String,
        copied: Binding<Bool>,
        onCopy: @escaping () -> Void,
        onRerun: @escaping () -> Void,
        rerunLabel: String,
        rerunDisabled: Bool,
        onChange: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader(title: title, subtitle: subtitle, icon: icon, accent: accent,
                       isInFlight: isInFlight, inFlightText: inFlightText,
                       copied: copied.wrappedValue, onCopy: onCopy,
                       onRerun: onRerun, rerunLabel: rerunLabel, rerunDisabled: rerunDisabled,
                       textIsEmpty: text.wrappedValue.isEmpty)
            Divider().opacity(0.5)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .onChange(of: text.wrappedValue) { _, _ in onChange() }
                if text.wrappedValue.isEmpty && !isInFlight {
                    Text(emptyPlaceholder)
                        .font(.callout).foregroundStyle(.tertiary)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 280)
        .background(NDS.bg)
    }

    private func paneHeader(
        title: String, subtitle: String, icon: String, accent: Color,
        isInFlight: Bool, inFlightText: String,
        copied: Bool, onCopy: @escaping () -> Void,
        onRerun: @escaping () -> Void, rerunLabel: String, rerunDisabled: Bool,
        textIsEmpty: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isInFlight {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small) // design-lint:allow
                    Text(inFlightText).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button {
                onCopy()
            } label: {
                Label(copied ? "Copied!" : "Copy",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .controlSize(.small) // design-lint:allow
            .disabled(textIsEmpty)
            Button {
                onRerun()
            } label: {
                Label(rerunLabel, systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .font(.caption)
            }
            .buttonStyle(MSSecondaryButtonStyle())
            .controlSize(.small) // design-lint:allow
            .disabled(rerunDisabled)
            .help(rerunLabel)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(NDS.fieldBg)
    }

    // MARK: - Save / load

    private func reload() {
        let raw = manager.readQuickNoteTranscript(note)
        let polished = manager.readQuickNotePolished(note)
        let prompt = manager.readQuickNotePrompt(note)
        rawDraft = raw
        polishedDraft = polished
        promptDraft = prompt
        lastSavedRaw = raw
        lastSavedPolished = polished
        lastSavedPrompt = prompt
    }

    /// Re-read disk-side state when a background job (transcribe / polish)
    /// finishes — but ONLY if the user hasn't typed something we'd clobber.
    private func reloadIfNoUserEdits() {
        if rawDraft == lastSavedRaw {
            let fresh = manager.readQuickNoteTranscript(note)
            if fresh != rawDraft {
                rawDraft = fresh
                lastSavedRaw = fresh
            }
        }
        if polishedDraft == lastSavedPolished {
            let fresh = manager.readQuickNotePolished(note)
            if fresh != polishedDraft {
                polishedDraft = fresh
                lastSavedPolished = fresh
            }
        }
        if promptDraft == lastSavedPrompt {
            let fresh = manager.readQuickNotePrompt(note)
            if fresh != promptDraft {
                promptDraft = fresh
                lastSavedPrompt = fresh
            }
        }
    }

    private func scheduleRawSave() {
        rawSaveTimer?.invalidate()
        rawSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flushRawSave() }
        }
    }
    private func schedulePolishedSave() {
        polishedSaveTimer?.invalidate()
        polishedSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flushPolishedSave() }
        }
    }
    private func flushRawSave() {
        rawSaveTimer?.invalidate(); rawSaveTimer = nil
        guard rawDraft != lastSavedRaw else { return }
        manager.saveQuickNoteTranscript(rawDraft, for: note)
        lastSavedRaw = rawDraft
    }
    private func flushPolishedSave() {
        polishedSaveTimer?.invalidate(); polishedSaveTimer = nil
        guard polishedDraft != lastSavedPolished else { return }
        manager.saveQuickNotePolished(polishedDraft, for: note)
        lastSavedPolished = polishedDraft
    }
    private func schedulePromptSave() {
        promptSaveTimer?.invalidate()
        promptSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flushPromptSave() }
        }
    }
    private func flushPromptSave() {
        promptSaveTimer?.invalidate(); promptSaveTimer = nil
        guard promptDraft != lastSavedPrompt else { return }
        manager.saveQuickNotePrompt(promptDraft, for: note)
        lastSavedPrompt = promptDraft
    }
    private func flushSaves() {
        flushRawSave()
        flushPolishedSave()
        flushPromptSave()
    }

    private func copy(_ text: String, into flag: Binding<Bool>) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { flag.wrappedValue = false }
    }
}
