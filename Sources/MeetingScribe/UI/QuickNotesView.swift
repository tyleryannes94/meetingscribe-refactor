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
    @State private var pendingFocusTasksID: String?

    var body: some View {
        ResponsiveMasterDetail(showingDetail: selection != nil,
                               onBack: { selection = nil }, backLabel: "Voice Notes",
                               sidebarMax: 360,
                               sidebar: { sidebar }, detail: { detail })
        // FloatingOverlay's "Go to Recording" button → select that note here.
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeOpenVoiceNote)) { notif in
            if let id = notif.userInfo?["id"] as? String {
                manager.refreshQuickNotes()
                selection = id
                if (notif.userInfo?["focusTasks"] as? Bool) == true {
                    pendingFocusTasksID = id
                }
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
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Voice Notes").scaledFont(20, weight: .heavy, kind: .display)
                    Text("\(manager.quickNotes.count)")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    Spacer()
                    importButton
                }
                bigRecordButton
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
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
        .onAppear { manager.refreshQuickNotesIfStale() }
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

    /// Comp: full-width record button — coral "New voice note" idle, danger
    /// "Stop recording" while live, disabled progress while transcribing.
    @ViewBuilder
    private var bigRecordButton: some View {
        switch manager.quickRecordState {
        case .idle:
            Button {
                Task { await manager.startQuickNote() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill").scaledFont(15)
                    Text("New voice note").scaledFont(13.5, weight: .bold)
                }
                .frame(maxWidth: .infinity).frame(height: 42)
            }
            .buttonStyle(MSPrimaryButtonStyle())
        case .recording:
            Button {
                Task { await manager.stopQuickNote() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill").scaledFont(15)
                    Text("Stop recording").scaledFont(13.5, weight: .bold)
                }
                .frame(maxWidth: .infinity).frame(height: 42)
            }
            .buttonStyle(MSDangerButtonStyle())
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small) // design-lint:allow
                Text("Transcribing…").scaledFont(13, weight: .semibold)
                    .foregroundStyle(NDS.textSecondary)
            }
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
        case .error(let msg):
            Button { Task { await manager.startQuickNote() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").scaledFont(14)
                    Text("Retry").scaledFont(13.5, weight: .bold)
                }
                .frame(maxWidth: .infinity).frame(height: 42)
            }
            .buttonStyle(MSSecondaryButtonStyle()).help(msg)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let note = manager.quickNotes.first(where: { $0.id == id }) {
            QuickNoteDetail(note: note,
                            focusTasksOnAppear: pendingFocusTasksID == id,
                            onConsumeFocus: { pendingFocusTasksID = nil })
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
        HStack(alignment: .top, spacing: 9) {
            // Comp: 30px surface tile with a waveform glyph.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(NDS.surface2)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "waveform")
                    .scaledFont(13).foregroundStyle(NDS.textSecondary))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(note.title).scaledFont(13.5, weight: .semibold).lineLimit(1)
                    if note.wasDictation {
                        Image(systemName: "keyboard").font(.caption2).foregroundStyle(.secondary)
                    }
                    if manager.isTranscribingQuickNote(note) {
                        ProgressView().controlSize(.mini) // design-lint:allow
                    } else if manager.isPolishingQuickNote(note) {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(NDS.lilac)
                    } else if manager.lastErrorForQuickNote(note) != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(NDS.danger)
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
    var focusTasksOnAppear: Bool = false
    var onConsumeFocus: () -> Void = {}
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var actionItems: ActionItemStore
    @ObservedObject private var drive = GoogleDriveService.shared
    @State private var tasksHighlight = false

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
            recommendedTasksSection
            Divider()
            sideBySide
        }
        .onAppear {
            reload()
            if focusTasksOnAppear {
                withAnimation(.easeOut(duration: 0.4)) { tasksHighlight = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(.easeOut(duration: 0.6)) { tasksHighlight = false }
                }
                onConsumeFocus()
            }
        }
        .onChange(of: manager.quickNotesTranscribing) { _, _ in reloadIfNoUserEdits() }
        .onChange(of: manager.quickNotesPolishing) { _, _ in reloadIfNoUserEdits() }
        .onChange(of: manager.quickNotesStructuringPrompt) { _, _ in reloadIfNoUserEdits() }
        .onDisappear { flushSaves() }
        .id(note.id)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .scaledFont(24, weight: .heavy, relativeTo: .title, kind: .display)
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

    // MARK: - Recommended Tasks

    private var noteTasks: [ActionItem] {
        actionItems.items(for: note.id).filter { !$0.isTrashed }
    }

    @ViewBuilder
    private var recommendedTasksSection: some View {
        let tasks = noteTasks
        if !tasks.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist").foregroundStyle(NDS.brand)
                    Text("Recommended Tasks").font(.callout.weight(.semibold))
                    Text("\(tasks.count)")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    Spacer()
                    Text("Auto-extracted from this voice note")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                ForEach(tasks) { task in
                    RecommendedTaskRow(task: task)
                        .environmentObject(actionItems)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tasksHighlight ? NDS.brand.opacity(0.10) : Color.clear)
            )
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }
}

/// One row in the voice-note Recommended Tasks section: status toggle,
/// editable title, plus inline menus for project, labels, due date, and
/// priority. Each control writes through ActionItemStore on click — no
/// confirmation step — matching the user's "one-click edits" intent.
@available(macOS 14.0, *)
private struct RecommendedTaskRow: View {
    let task: ActionItem
    @EnvironmentObject var actionItems: ActionItemStore
    @State private var titleDraft: String = ""
    @State private var editingTitle = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusButton
            VStack(alignment: .leading, spacing: 6) {
                titleField
                HStack(spacing: 6) {
                    projectMenu
                    labelsMenu
                    dueDateMenu
                    priorityMenu
                    Spacer()
                    Button {
                        actionItems.delete(task.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this suggestion")
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { titleDraft = task.title }
        .onChange(of: task.title) { _, new in
            if !editingTitle { titleDraft = new }
        }
    }

    private var statusButton: some View {
        Button {
            let next: ActionItem.Status = task.status == .completed ? .open : .completed
            actionItems.setStatus(task.id, status: next)
        } label: {
            Image(systemName: task.status.systemImage)
                .font(.title3)
                .foregroundStyle(task.status == .completed ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help(task.status.label)
    }

    private var titleField: some View {
        TextField("Task", text: $titleDraft, onEditingChanged: { began in
            editingTitle = began
            if !began {
                let trimmed = titleDraft.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed != task.title {
                    actionItems.setTitle(task.id, title: trimmed)
                }
            }
        })
        .textFieldStyle(.plain)
        .font(.callout)
        .strikethrough(task.status == .completed, color: .secondary)
        .foregroundStyle(task.status == .completed ? .secondary : .primary)
    }

    private var projectMenu: some View {
        Menu {
            Button("None") { actionItems.setProject(task.id, projectID: nil) }
            if !actionItems.initiatives.isEmpty {
                ForEach(actionItems.initiatives) { initiative in
                    let projects = actionItems.projects.filter {
                        $0.belongs(toInitiative: initiative.id) && $0.status == .active
                    }
                    if !projects.isEmpty {
                        Section(initiative.name) {
                            ForEach(projects) { p in
                                Button(p.name) { actionItems.setProject(task.id, projectID: p.id) }
                            }
                        }
                    }
                }
            }
            let unfiled = actionItems.projects.filter {
                ($0.initiativeID ?? "").isEmpty && $0.status == .active
            }
            if !unfiled.isEmpty {
                Section("Other Projects") {
                    ForEach(unfiled) { p in
                        Button(p.name) { actionItems.setProject(task.id, projectID: p.id) }
                    }
                }
            }
        } label: {
            chipLabel(icon: "folder",
                      text: currentProjectName ?? "Project",
                      muted: task.projectID == nil)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var currentProjectName: String? {
        guard let pid = task.projectID,
              let p = actionItems.projects.first(where: { $0.id == pid }) else { return nil }
        if let iid = p.initiativeID,
           let initiative = actionItems.initiatives.first(where: { $0.id == iid }) {
            return "\(initiative.name) › \(p.name)"
        }
        return p.name
    }

    private var labelsMenu: some View {
        Menu {
            if actionItems.labels.isEmpty {
                Text("No tags yet — create one from the Tasks view")
            } else {
                ForEach(actionItems.labels) { label in
                    Button {
                        actionItems.toggleLabel(task.id, labelID: label.id)
                    } label: {
                        if (task.labelIDs ?? []).contains(label.id) {
                            Label(label.name, systemImage: "checkmark")
                        } else {
                            Text(label.name)
                        }
                    }
                }
            }
        } label: {
            chipLabel(icon: "tag",
                      text: labelChipText,
                      muted: (task.labelIDs ?? []).isEmpty)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var labelChipText: String {
        let ids = task.labelIDs ?? []
        if ids.isEmpty { return "Tag" }
        let names = ids.compactMap { id in
            actionItems.labels.first(where: { $0.id == id })?.name
        }
        if names.count == 1 { return names[0] }
        return "\(names.count) tags"
    }

    private var dueDateMenu: some View {
        Menu {
            Button("Today") {
                actionItems.setDueDate(task.id, dueDate: Calendar.current.startOfDay(for: Date()))
            }
            Button("Tomorrow") {
                let cal = Calendar.current
                let d = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
                actionItems.setDueDate(task.id, dueDate: d)
            }
            Button("Next week") {
                let cal = Calendar.current
                let d = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: Date()))
                actionItems.setDueDate(task.id, dueDate: d)
            }
            Divider()
            Button("Clear due date") { actionItems.setDueDate(task.id, dueDate: nil) }
        } label: {
            chipLabel(icon: "calendar",
                      text: dueChipText,
                      muted: task.dueDate == nil,
                      tint: dueChipTint)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var dueChipText: String {
        guard let due = task.dueDate else { return "Due" }
        let cal = Calendar.current
        if cal.isDateInToday(due) { return "Today" }
        if cal.isDateInTomorrow(due) { return "Tomorrow" }
        if cal.isDateInYesterday(due) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: due)
    }

    private var dueChipTint: Color? {
        guard let due = task.dueDate else { return nil }
        if due < Calendar.current.startOfDay(for: Date()) { return .red }
        if Calendar.current.isDateInToday(due) { return .orange }
        return nil
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(ActionItem.Priority.allCases) { p in
                Button(p.label) { actionItems.setPriority(task.id, priority: p) }
            }
        } label: {
            chipLabel(icon: "flag",
                      text: task.priority.label,
                      muted: task.priority == .medium)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func chipLabel(icon: String, text: String, muted: Bool, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(tint ?? (muted ? .secondary : .primary))
        .background(
            Capsule().fill((tint ?? Color.secondary).opacity(muted ? 0.08 : 0.14))
        )
    }
}
