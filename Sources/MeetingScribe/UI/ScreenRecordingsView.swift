import SwiftUI
import AVKit
import ScreenCaptureKit

extension Notification.Name {
    static let meetingScribeNewScreenRecording = Notification.Name("MeetingScribeNewScreenRecording")
    static let meetingScribeNewScreenshot = Notification.Name("MeetingScribeNewScreenshot")
}

/// Top-level "Recordings" page: screen recordings (capture / play back / transcript)
/// plus quick screenshots. Mirrors the Voice Notes page shell.
@available(macOS 14.0, *)
struct ScreenRecordingsView: View {
    @EnvironmentObject var recordings: ScreenRecordingsController
    @AppStorage("screenrec.includeMic") private var includeMic = true

    @State private var selection: String?
    @State private var showWindowPicker = false
    @State private var windows: [SCWindow] = []
    @State private var screenshotImage: ScreenshotPreview?

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            detail
                .frame(minWidth: 420)
        }
        .background(NDS.bg)
        .onAppear { recordings.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeNewScreenRecording)) { _ in
            Task { await start(.fullScreen) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeNewScreenshot)) { _ in
            Task { await captureScreenshot(.fullScreen) }
        }
        .sheet(isPresented: $showWindowPicker) {
            WindowPickerSheet(windows: windows) { window in
                showWindowPicker = false
                if let window { Task { await start(.window(window)) } }
            }
        }
        .sheet(item: $screenshotImage) { shot in
            ScreenshotEditorView(image: shot.image) { recordings.refresh() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recordings").scaledFont(17, weight: .heavy, kind: .display)
                Text("\(recordings.recordings.count)")
                    .scaledFont(12, weight: .bold).foregroundStyle(NDS.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            controls.padding(.horizontal, 12).padding(.bottom, 8)
            Divider().overlay(NDS.divider)

            if recordings.recordings.isEmpty {
                MSEmptyState(systemImage: "record.circle",
                             title: "No recordings yet",
                             message: "Capture your screen or take a screenshot to get started.")
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(recordings.recordings) { rec in
                        ScreenRecordingRow(rec: rec,
                                           thumbnail: recordings.thumbnailURL(rec),
                                           transcribing: recordings.isTranscribing(rec))
                            .tag(rec.id)
                    }
                    .onDelete(perform: deleteRows)
                }
                .listStyle(.sidebar)
            }
        }
        .background(NDS.sidebarBg)
    }

    @ViewBuilder
    private var controls: some View {
        switch recordings.state {
        case .recording:
            Button { Task { await recordings.stopRecording() } } label: {
                Label("Stop recording", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(MSDangerButtonStyle())
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small) // design-lint:allow
                Text("Transcribing…").scaledFont(12).foregroundStyle(NDS.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
        default:
            VStack(spacing: 8) {
                Menu {
                    Button { Task { await start(.fullScreen) } } label: { Label("Full screen", systemImage: "display") }
                    Button { Task { await pickWindow() } } label: { Label("Window…", systemImage: "macwindow") }
                    Button { Task { await start(.regionPrompt) } } label: { Label("Region…", systemImage: "rectangle.dashed") }
                } label: {
                    Label("New recording", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(MSPrimaryButtonStyle())

                HStack(spacing: 8) {
                    Menu {
                        Button { Task { await captureScreenshot(.fullScreen) } } label: { Label("Full screen", systemImage: "display") }
                        Button { Task { await captureScreenshot(.regionPrompt) } } label: { Label("Region…", systemImage: "rectangle.dashed") }
                    } label: {
                        Label("Screenshot", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(MSSecondaryButtonStyle())

                    Toggle(isOn: $includeMic) {
                        Image(systemName: includeMic ? "mic.fill" : "mic.slash")
                    }
                    .toggleStyle(.button)
                    .help("Record microphone voice-over")
                }
                if case .error(let msg) = recordings.state {
                    Text(msg).scaledFont(11).foregroundStyle(NDS.danger).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let rec = recordings.recordings.first(where: { $0.id == id }) {
            ScreenRecordingDetail(rec: rec)
                .id(rec.id)
        } else {
            MSEmptyState(systemImage: "play.rectangle",
                         title: "Select a recording",
                         message: "Pick a recording on the left to play it back and read its transcript.")
        }
    }

    // MARK: - Actions

    /// A capture intent that may need an async region prompt before starting.
    private enum Intent { case fullScreen, window(SCWindow), regionPrompt }

    private func start(_ intent: Intent) async {
        let target: ScreenRecorder.Target
        switch intent {
        case .fullScreen: target = .fullScreen
        case .window(let w): target = .window(w)
        case .regionPrompt:
            guard let rect = await RegionSelectOverlay.selectRegion() else { return }
            target = .region(rect)
        }
        await recordings.startRecording(target: target, includeMic: includeMic)
    }

    private func pickWindow() async {
        windows = await recordings.shareableWindows()
        showWindowPicker = true
    }

    private func captureScreenshot(_ intent: Intent) async {
        let target: ScreenshotCapturer.Target
        switch intent {
        case .fullScreen: target = .fullScreen
        case .window(let w): target = .window(w)
        case .regionPrompt:
            guard let rect = await RegionSelectOverlay.selectRegion() else { return }
            target = .region(rect)
        }
        if let cg = try? await ScreenshotCapturer.capture(target) {
            screenshotImage = ScreenshotPreview(image: cg)
        }
    }

    private func deleteRows(_ offsets: IndexSet) {
        for i in offsets { recordings.delete(recordings.recordings[i]) }
    }
}

/// Wrapper so a captured CGImage can drive `.sheet(item:)`.
private struct ScreenshotPreview: Identifiable {
    let id = UUID()
    let image: CGImage
}

// MARK: - Row

@available(macOS 14.0, *)
private struct ScreenRecordingRow: View {
    let rec: ScreenRecording
    let thumbnail: URL
    let transcribing: Bool

    var body: some View {
        HStack(spacing: 10) {
            thumbView
                .frame(width: 56, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(NDS.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title).scaledFont(13, weight: .semibold).lineLimit(1)
                HStack(spacing: 6) {
                    Text(rec.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(Self.duration(rec.durationSeconds))
                    if transcribing {
                        Text("· transcribing…").foregroundStyle(NDS.accent)
                    }
                }
                .scaledFont(11).foregroundStyle(NDS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var thumbView: some View {
        if let img = NSImage(contentsOf: thumbnail) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack { NDS.surface2; Image(systemName: "record.circle").foregroundStyle(NDS.textTertiary) }
        }
    }

    private static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Detail pane

@available(macOS 14.0, *)
private struct ScreenRecordingDetail: View {
    @EnvironmentObject var recordings: ScreenRecordingsController
    let rec: ScreenRecording

    @State private var transcriptDraft = ""
    @State private var saveTimer: Timer?
    @State private var player: AVPlayer?
    @State private var summary = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                VideoPlayer(player: player)
                    .frame(minHeight: 280, idealHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: NDS.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius).stroke(NDS.hairline, lineWidth: 1))
                analysisCard
                transcriptCard
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(NDS.bg)
        .onAppear {
            transcriptDraft = recordings.readTranscript(rec)
            summary = recordings.readSummary(rec)
            if player == nil { player = AVPlayer(url: recordings.videoURL(rec)) }
        }
        .onChange(of: recordings.analyzing) { _, _ in
            // Refresh the summary text once an analysis run completes.
            if !recordings.isAnalyzing(rec) { summary = recordings.readSummary(rec) }
        }
        .onChange(of: transcriptDraft) { _, _ in scheduleSave() }
        .onDisappear { flush() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.title).scaledFont(22, weight: .heavy, kind: .display)
                HStack(spacing: 6) {
                    Text(rec.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·"); Text("\(rec.width)×\(rec.height)")
                    Text("·"); Text(rec.mode.label)
                    if rec.hasMic { Text("· mic") }
                }
                .scaledFont(12).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            Menu {
                Button { recordings.reTranscribe(rec) } label: { Label("Re-transcribe", systemImage: "arrow.clockwise") }
                Button { revealInFinder() } label: { Label("Show in Finder", systemImage: "folder") }
                Divider()
                Button(role: .destructive) { recordings.delete(rec) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").scaledFont(16).foregroundStyle(NDS.textSecondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    @ViewBuilder
    private var analysisCard: some View {
        let analyzing = recordings.isAnalyzing(rec)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI Summary", systemImage: "sparkles")
                    .scaledFont(12, weight: .bold).foregroundStyle(NDS.textSecondary)
                Spacer()
                if summary.isEmpty {
                    Button { runAnalysis() } label: {
                        Label("Analyze recording", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(MSPrimaryButtonStyle()).disabled(analyzing)
                } else {
                    Button { runAnalysis() } label: {
                        Label("Re-analyze", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(MSSecondaryButtonStyle()).disabled(analyzing)
                }
            }
            if analyzing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small) // design-lint:allow
                    Text("Reading the screen and summarizing… (on-device)")
                        .scaledFont(11).foregroundStyle(NDS.textSecondary)
                }
            } else if summary.isEmpty {
                Text("Summarize what happened on screen and pull out action items — runs locally, nothing leaves your Mac.")
                    .scaledFont(12).foregroundStyle(NDS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(.init(summary))
                    .scaledFont(13).foregroundStyle(NDS.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if recordings.recordingsWithTasks.contains(rec.id) {
                    Label("Action items were added to Tasks", systemImage: "checklist")
                        .scaledFont(11).foregroundStyle(NDS.mint)
                }
            }
        }
        .padding(14)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius).stroke(NDS.hairline, lineWidth: 1))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .scaledFont(12, weight: .bold).foregroundStyle(NDS.textSecondary)
                Spacer()
                if recordings.isTranscribing(rec) {
                    Text("Transcribing…").scaledFont(11).foregroundStyle(NDS.accent)
                }
            }
            if let err = recordings.error(for: rec) {
                Text(err).scaledFont(11).foregroundStyle(NDS.danger).fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: $transcriptDraft)
                .scaledFont(13)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                .overlay(alignment: .topLeading) {
                    if transcriptDraft.isEmpty && !recordings.isTranscribing(rec) {
                        Text("No transcript yet — this recording may have had no spoken audio.")
                            .scaledFont(13).foregroundStyle(NDS.textTertiary).padding(14)
                    }
                }
        }
        .padding(14)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius).stroke(NDS.hairline, lineWidth: 1))
    }

    private func runAnalysis() {
        summary = ""
        Task { await recordings.analyze(rec) }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flush() }
        }
    }
    private func flush() {
        saveTimer?.invalidate(); saveTimer = nil
        recordings.saveTranscript(transcriptDraft, for: rec)
    }
    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([recordings.videoURL(rec)])
    }
}

// MARK: - Window picker

@available(macOS 14.0, *)
private struct WindowPickerSheet: View {
    let windows: [SCWindow]
    let onPick: (SCWindow?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a window").scaledFont(15, weight: .bold).padding(16)
            Divider().overlay(NDS.divider)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(windows, id: \.windowID) { w in
                        Button { onPick(w) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "macwindow").foregroundStyle(NDS.textSecondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(w.title ?? "Untitled").scaledFont(13).lineLimit(1)
                                    Text(w.owningApplication?.applicationName ?? "")
                                        .scaledFont(11).foregroundStyle(NDS.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).ndsHover()
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 360)
            Divider().overlay(NDS.divider)
            HStack {
                Spacer()
                Button("Cancel") { onPick(nil) }.buttonStyle(MSSecondaryButtonStyle())
            }
            .padding(12)
        }
        .frame(width: 380)
        .background(NDS.bg)
    }
}
