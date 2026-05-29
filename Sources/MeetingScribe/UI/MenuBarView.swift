import SwiftUI
import AppKit

@available(macOS 14.0, *)
struct MenuBarView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow

            Divider()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open MeetingScribe Window", systemImage: "macwindow")
            }
            .keyboardShortcut("o")

            Divider()

            quickActions

            Divider()

            Text("Upcoming").font(.caption).foregroundStyle(.secondary)
            let grouped = calendar.groupedUpcoming()
            if grouped.allSatisfy({ $0.1.isEmpty }) {
                Text(calendar.authorized ? "Nothing in the next 7 days." : "Calendar access not granted.")
                    .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 4)
            } else {
                ForEach(grouped, id: \.0.id) { group, meetings in
                    if !meetings.isEmpty {
                        Text(group.title).font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
                        ForEach(meetings.prefix(6)) { meeting in
                            meetingRow(meeting)
                        }
                    }
                }
            }

            Divider()

            Button("Refresh Calendar") { calendar.refreshUpcoming(force: true) }
            Button("Open Notes Folder") {
                NSWorkspace.shared.open(AppSettings.shared.storageDir)
            }
            SettingsLink { Text("Settings…") }

            Divider()

            Button("Quit MeetingScribe") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(10)
        .frame(width: 340)
        .task {
            if !calendar.authorized { await calendar.requestAccess() }
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
            manager.refreshQuickNotes()
        }
    }

    @ViewBuilder
    private var quickActions: some View {
        Button {
            Task { await manager.startRecording(for: nil) }
        } label: {
            Label("Record Ad-hoc Meeting", systemImage: "record.circle")
        }
        .disabled(!isIdle)

        Button {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            Task { await manager.startQuickNote() }
        } label: {
            Label("New Voice Note", systemImage: "waveform.badge.plus")
        }

        if let live = calendar.upcoming.first(where: { $0.isLive && $0.conferenceURL != nil }) {
            Button {
                Task { await manager.switchToRecording(live) }
            } label: {
                Label("Join & Record: \(live.displayTitle)", systemImage: "video.fill")
            }
        }
    }

    private var isIdle: Bool {
        if case .idle = manager.state { return true }
        return false
    }

    @ViewBuilder
    private var statusRow: some View {
        switch manager.state {
        case .idle, .starting:
            if manager.transcribingMeetingIDs.isEmpty {
                Label("Idle", systemImage: "circle").font(.headline)
            } else {
                Label("Finalizing \(manager.transcribingMeetingIDs.count) meeting(s)…",
                      systemImage: "waveform.badge.magnifyingglass")
                    .font(.headline)
            }
        case .recording(let meeting, let startedAt):
            VStack(alignment: .leading, spacing: 2) {
                Label("Recording", systemImage: "record.circle.fill")
                    .foregroundStyle(.red).font(.headline)
                Text(meeting?.displayTitle ?? "Ad-hoc").font(.subheadline)
                Text("Started \(startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Stop & Transcribe") {
                    Task { await manager.stopRecording() }
                }
                .keyboardShortcut(.return)
                .padding(.top, 4)
            }
        case .stopping:
            // Teardown in progress — show recording UI until idle.
            VStack(alignment: .leading, spacing: 2) {
                Label("Stopping…", systemImage: "stop.circle")
                    .foregroundStyle(.red).font(.headline)
            }
        case .error(let msg):
            VStack(alignment: .leading, spacing: 2) {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.headline)
                Text(msg).font(.caption).foregroundStyle(.secondary)
                Button("Dismiss") {
                    Task { await manager.cancelRecording() }
                }
            }
        }
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.displayTitle).font(.callout).lineLimit(1)
                Text(timeRange(meeting)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Always clickable. switchToRecording auto-stops any current
            // recording before joining the new one.
            if meeting.conferenceURL != nil {
                Button {
                    Task { await manager.switchToRecording(meeting) }
                } label: {
                    Image(systemName: "video.fill")
                }
                .buttonStyle(.borderless)
                .help(isIdle ? "Join & Record"
                             : "Join & Record (stops current recording first)")
                .accessibilityLabel("Join and record meeting")
            } else {
                Button {
                    Task {
                        if case .recording = manager.state {
                            await manager.stopRecording()
                            try? await Task.sleep(nanoseconds: 300_000_000)
                        }
                        await manager.startRecording(for: meeting)
                    }
                } label: {
                    Image(systemName: "record.circle")
                }
                .buttonStyle(.borderless)
                .help(isIdle ? "Start recording"
                             : "Start recording (stops current recording first)")
                .accessibilityLabel("Start recording")
            }
        }
        .padding(.vertical, 2)
    }

    private func timeRange(_ m: Meeting) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: m.startDate)) – \(f.string(from: m.endDate))"
    }
}
