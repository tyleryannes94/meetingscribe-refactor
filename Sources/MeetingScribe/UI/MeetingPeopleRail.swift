import SwiftUI
import VaultKit

/// "Who's here" — a persistent people rail in meeting detail (P1-2). Promotes the
/// app's "relationship second brain" onto its highest-traffic surface: for every
/// attendee, who they are, how the relationship is doing, and when you last met —
/// right there, instead of 4 navigations away. Unlinked attendees get an inline
/// Connect affordance that opens the existing connect panel.
@available(macOS 14.0, *)
struct MeetingPeopleRail: View {
    let meeting: Meeting
    /// Opens the inline connect panel for an unlinked attendee string.
    let onConnect: (String) -> Void
    /// Hides the rail (re-show with ⌥⌘P).
    var onHide: (() -> Void)? = nil

    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: WorkspaceRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").scaledFont(10).foregroundStyle(NDS.textTertiary)
                Text("Who's here").scaledFont(11, weight: .semibold).foregroundStyle(NDS.textSecondary)
                Text("\(meeting.attendees.count)").scaledFont(10).foregroundStyle(NDS.textTertiary)
                Spacer()
                if let onHide {
                    Button(action: onHide) {
                        Image(systemName: "sidebar.right").scaledFont(11).foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Hide people rail (⌥⌘P)")
                }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            Divider().overlay(NDS.divider)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(meeting.attendees, id: \.self) { raw in
                        rowFor(raw)
                    }
                    if meeting.attendees.isEmpty {
                        Text("No attendees on this meeting.")
                            .scaledFont(12).foregroundStyle(NDS.textTertiary)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: 280, maxHeight: .infinity)
        .background(NDS.rightRailBg)
    }

    @ViewBuilder
    private func rowFor(_ raw: String) -> some View {
        let id = PersonResolver.parse(raw)
        let name = id.hasName ? id.name : PersonResolver.localPart(of: id.email)
        if let pid = people.resolvePersonID(identity: id),
           let person = people.person(by: pid) {
            MeetingPersonRow(person: person, meeting: meeting)
        } else {
            unlinkedRow(name: name, raw: raw)
        }
    }

    private func unlinkedRow(name: String, raw: String) -> some View {
        HStack(spacing: 10) {
            MSAvatar(name: name, size: 30).opacity(0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).scaledFont(12.5, weight: .medium).foregroundStyle(NDS.textSecondary).lineLimit(1)
                Text("Not in People").scaledFont(10.5).foregroundStyle(NDS.textTertiary)
            }
            Spacer(minLength: 0)
            Button { onConnect(raw) } label: {
                Image(systemName: "person.crop.circle.badge.plus").scaledFont(13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NDS.brand)
            .help("Connect \(name) to a person")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

}

/// A single linked-person row in the "Who's here" rail. Tapping it opens the
/// person; the trailing "＋" reveals an inline field to jot a note attributed to
/// this person — "Priya promised the migration doc" — without leaving the live
/// meeting. The note is saved as an encounter tagged to the current meeting so it
/// surfaces on the person's profile later. (P1-12)
@available(macOS 14.0, *)
private struct MeetingPersonRow: View {
    let person: Person
    let meeting: Meeting

    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: WorkspaceRouter

    @State private var capturing = false
    @State private var noteText = ""
    @State private var justSaved = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { router.openPerson(person.id) } label: {
                HStack(alignment: .top, spacing: 10) {
                    MSAvatar(name: person.displayName, size: 30,
                             ringColor: healthRingColor(for: person, in: people))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).scaledFont(12.5, weight: .semibold)
                            .foregroundStyle(NDS.textPrimary).lineLimit(1)
                        if let sub = roleLine(person) {
                            Text(sub).scaledFont(11).foregroundStyle(NDS.textTertiary).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            healthCapsule(person)
                            if let last = lastMet(person) {
                                Text(last).scaledFont(10.5).foregroundStyle(NDS.textTertiary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .ndsHover()   // D3-10
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) { noteToggle }

            if capturing { captureField }
        }
    }

    // MARK: - Quick-capture (P1-12)

    private var noteToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { capturing.toggle() }
            if capturing { fieldFocused = true }
        } label: {
            Image(systemName: justSaved ? "checkmark" : (capturing ? "xmark" : "plus"))
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(justSaved ? NDS.mint : NDS.brand)
                .frame(width: 20, height: 20)
                .background(NDS.fieldBg, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 10).padding(.top, 8)
        .help("Note about \(person.displayName)")
    }

    private var captureField: some View {
        HStack(spacing: NDS.spaceSM) {
            TextField("Note about \(person.displayName)…", text: $noteText)
                .textFieldStyle(.plain)
                .scaledFont(12)
                .foregroundStyle(NDS.textPrimary)
                .focused($fieldFocused)
                .onSubmit(save)
            if !noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: save) {
                    Image(systemName: "arrow.up.circle.fill")
                        .scaledFont(15).foregroundStyle(NDS.brand)
                }
                .buttonStyle(.plain)
                .help("Save note")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func save() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Attribute the note to the live meeting so it surfaces on the person's
        // profile with the where/when context intact.
        people.addEncounter(to: person.id,
                            eventName: meeting.displayTitle,
                            notes: trimmed,
                            meetingID: meeting.id)
        noteText = ""
        withAnimation(.easeInOut(duration: 0.15)) {
            capturing = false
            justSaved = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run { withAnimation { justSaved = false } }
        }
    }

    // MARK: - Derived bits

    private func roleLine(_ p: Person) -> String? {
        let parts = [p.role, p.company].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func health(_ p: Person) -> RelationshipHealth {
        let encs = people.encounters(for: p.id)
        let dates = encs.map(\.date).sorted(by: >)
        let medianGap: Int = {
            guard dates.count >= 2 else { return 0 }
            var gaps = (0..<(dates.count - 1)).map { Int(dates[$0].timeIntervalSince(dates[$0 + 1]) / 86400) }
            gaps.sort()
            return gaps[gaps.count / 2]
        }()
        let last = dates.first ?? p.lastInteractionAt
        let daysSince = last.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 9_999
        return RelationshipHealth(daysSinceLast: daysSince, cadenceDays: p.effectiveCheckInDays,
                                  encounterCount: encs.count, medianGapDays: medianGap)
    }

    private func healthCapsule(_ p: Person) -> some View {
        let h = health(p)
        let color: Color = {
            switch h.band {
            case .thriving: return NDS.mint
            case .steady:   return NDS.sky
            case .drifting: return NDS.gold
            case .overdue:  return NDS.danger
            }
        }()
        return Text(h.band.rawValue.capitalized)
            .scaledFont(9.5, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func lastMet(_ p: Person) -> String? {
        guard let last = p.lastInteractionAt else { return nil }
        let days = Int(Date().timeIntervalSince(last) / 86400)
        if days <= 0 { return "today" }
        if days == 1 { return "1d ago" }
        return "\(days)d ago"
    }
}
