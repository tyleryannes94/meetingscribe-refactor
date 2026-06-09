import SwiftUI

/// Quick "New meeting" sheet (redesign §1): name an ad-hoc meeting, or pick an
/// upcoming calendar meeting to record, then start. `onStart` receives the
/// meeting to begin recording.
@available(macOS 14.0, *)
struct NewMeetingSheet: View {
    @EnvironmentObject var calendar: CalendarService
    let onStart: (Meeting) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    private var upcoming: [Meeting] {
        calendar.upcoming
            .filter { $0.startDate > Date().addingTimeInterval(-15 * 60) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New meeting")
                .scaledFont(20, weight: .heavy, relativeTo: .title, kind: .display)

            VStack(alignment: .leading, spacing: 6) {
                NotionEyebrow(text: "Title")
                TextField("e.g. Product Sync — Skio", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startAdhoc)
            }

            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    NotionEyebrow(text: "Or record an upcoming meeting")
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(upcoming) { m in
                                Button { start(m) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: m.conferenceURL != nil ? "video.fill" : "calendar")
                                            .foregroundStyle(NDS.lilac).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(m.displayTitle).scaledFont(13, weight: .semibold)
                                                .foregroundStyle(NDS.textPrimary).lineLimit(1)
                                            Text(m.startDate.formatted(date: .omitted, time: .shortened))
                                                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                        }
                                        Spacer()
                                        Image(systemName: "record.circle").foregroundStyle(NDS.danger)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button { startAdhoc() } label: {
                    Label("Start recording", systemImage: "record.circle.fill")
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(NDS.bg)
    }

    private func startAdhoc() {
        var m = MeetingManager.adhocMeeting()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { m.title = t; m.userTitle = t }
        onStart(m)
        dismiss()
    }

    private func start(_ m: Meeting) {
        onStart(m)
        dismiss()
    }
}
