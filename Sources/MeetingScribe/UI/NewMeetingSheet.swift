import SwiftUI

/// Quick "New meeting" sheet (redesign §1): name an ad-hoc meeting, or pick an
/// upcoming calendar meeting to record, then start. `onStart` receives the
/// meeting to begin recording.
@available(macOS 14.0, *)
struct NewMeetingSheet: View {
    @EnvironmentObject var calendar: CalendarService
    @ObservedObject private var people = PeopleStore.shared
    let onStart: (Meeting) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    /// P1-4: who this ad-hoc meeting is with — written as attendees at creation
    /// so the meeting is people-linked from the start.
    @State private var selectedPeople: [Person] = []
    @State private var showPeoplePicker = false
    @State private var peopleQuery = ""

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

            whoWithSection   // P1-4

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

    // MARK: - Who's this with? (P1-4)

    @ViewBuilder
    private var whoWithSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotionEyebrow(text: "Who's this with?")
            HStack(spacing: 6) {
                ForEach(selectedPeople) { p in
                    HStack(spacing: 4) {
                        MSAvatar(name: p.displayName, size: 16)
                        Text(p.displayName.split(separator: " ").first.map(String.init) ?? p.displayName)
                            .scaledFont(11)
                        Button { selectedPeople.removeAll { $0.id == p.id } } label: {
                            Image(systemName: "xmark.circle.fill").scaledFont(10)
                        }.buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(NDS.fieldBg, in: Capsule())
                }
                Button { showPeoplePicker = true } label: {
                    Label("Add", systemImage: "person.crop.circle.badge.plus").scaledFont(11)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.brand)
                .popover(isPresented: $showPeoplePicker, arrowEdge: .bottom) { peoplePicker }
                Spacer()
            }
            // Relationship context for the picked people (P1-4).
            if let p = selectedPeople.first, let last = p.lastInteractionAt {
                let days = Int(Date().timeIntervalSince(last) / 86400)
                Text("\(p.displayName.split(separator: " ").first.map(String.init) ?? p.displayName) · last met \(days)d ago")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
    }

    private var peoplePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search people…", text: $peopleQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(filteredPickerPeople) { p in
                        Button { addPerson(p) } label: {
                            HStack(spacing: 8) {
                                MSAvatar(name: p.displayName, size: 20)
                                Text(p.displayName).scaledFont(12).foregroundStyle(NDS.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 220)
        }
        .padding(12).frame(width: 260)
    }

    private var filteredPickerPeople: [Person] {
        let q = peopleQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = people.people.filter { p in !selectedPeople.contains { $0.id == p.id } }
        let base = q.isEmpty ? pool : pool.filter { $0.displayName.lowercased().contains(q) }
        return Array(base.prefix(40))
    }

    private func addPerson(_ p: Person) {
        if !selectedPeople.contains(where: { $0.id == p.id }) { selectedPeople.append(p) }
        peopleQuery = ""
        showPeoplePicker = false
    }

    private func startAdhoc() {
        var m = MeetingManager.adhocMeeting()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { m.title = t; m.userTitle = t }
        // P1-4: write the picked people as attendees so the meeting is
        // person-linked from creation (PersonResolver links them at finalize).
        if !selectedPeople.isEmpty {
            m.attendees = selectedPeople.map { p in
                p.primaryEmail.isEmpty ? p.displayName : "\(p.displayName) <\(p.primaryEmail)>"
            }
        }
        onStart(m)
        dismiss()
    }

    private func start(_ m: Meeting) {
        onStart(m)
        dismiss()
    }
}
