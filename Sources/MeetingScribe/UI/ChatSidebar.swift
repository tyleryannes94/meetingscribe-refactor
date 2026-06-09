import SwiftUI
import AppKit

/// The right-side sidebar shown in the Today view. A single Chat
/// surface (the app-wide session, so messages persist as the user clicks
/// around). A folder button in the header opens the sandboxed-folders
/// picker.
@available(macOS 14.0, *)
struct ChatSidebar: View {
    @EnvironmentObject var session: ChatSession

    @State private var showingFolders = false
    @State private var folders: [String] = AppSettings.shared.chatFolders

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ChatPanel(
                session: session,
                density: .compact,
                examplePrompts: [
                    "What action items came out of yesterday's meetings?",
                    "Summarize my calls from this week.",
                    "List my voice notes from the past 7 days.",
                    "Find files in my Chat folders that mention 'pricing'."
                ]
            )
        }
        .background(
            LinearGradient(
                colors: [
                    NDS.sidebarBg,
                    NDS.rightRailBg
                ],
                startPoint: .top, endPoint: .bottom)
        )
        .sheet(isPresented: $showingFolders) {
            ChatFoldersSheet(folders: $folders)
        }
        // Natural-language passthrough from the search palette: when a
        // user picks "Ask Chat: …" the typed query gets dropped straight
        // into the session and a send fires. Saves them re-typing.
        .onReceive(NotificationCenter.default.publisher(for: .meetingScribeRunChat)) { note in
            guard let text = note.userInfo?["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { await session.sendUserMessage(text) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(NDS.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text("Chat")
                    .font(.headline)
                Text(captionText)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                folders = AppSettings.shared.chatFolders
                showingFolders = true
            } label: {
                Image(systemName: folders.isEmpty
                      ? "folder.badge.plus"
                      : "folder.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(folders.isEmpty
                  ? "Add folders the AI can read/write"
                  : "Manage \(folders.count) Chat folder\(folders.count == 1 ? "" : "s")")
            Button {
                session.reset()
            } label: {
                Image(systemName: "plus.message")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(session.messages.isEmpty)
            .help("Start a new chat")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var captionText: String {
        let model = AppSettings.shared.ollamaModel
        let n = folders.count
        if n == 0 { return "Local · \(model)" }
        return "Local · \(model) · \(n) folder\(n == 1 ? "" : "s")"
    }
}

// MARK: - Chat folders sheet

@available(macOS 14.0, *)
struct ChatFoldersSheet: View {
    @Binding var folders: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat folders").font(.title3.bold())
                    Text("The local AI has read + write access to files inside these folders.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if folders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("No folders added yet").font(.headline)
                    Text("Add at least one project folder so the AI can read/edit files there.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(folders, id: \.self) { path in
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue.opacity(0.8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.callout.weight(.medium))
                                    Text(path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting(
                                        [URL(fileURLWithPath: path)])
                                } label: {
                                    Image(systemName: "magnifyingglass.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Reveal in Finder")
                                Button(role: .destructive) {
                                    folders.removeAll { $0 == path }
                                    AppSettings.shared.chatFolders = folders
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(10)
                            .background(NDS.fieldBg,
                                        in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                            .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius)
                                .strokeBorder(NDS.hairline, lineWidth: 0.5))
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            HStack(spacing: 8) {
                Button {
                    addFolder()
                } label: {
                    Label("Add folder…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Chat"
        if panel.runModal() == .OK {
            for url in panel.urls where !folders.contains(url.path) {
                folders.append(url.path)
            }
            AppSettings.shared.chatFolders = folders
        }
    }
}
