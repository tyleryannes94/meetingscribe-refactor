import SwiftUI

/// The People tab's overview, shown in the detail pane when no one is selected.
/// Surfaces who to reconnect with, upcoming birthdays, and your most-active
/// contacts — turning dead space into a relationship dashboard.
@available(macOS 14.0, *)
struct PeopleInsightsView: View {
    @EnvironmentObject var people: PeopleStore
    /// Select a person in the list.
    var onOpen: (String) -> Void

    private static let goneColdDays = 45
    private static let birthdayWindowDays = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("People").font(NDS.pageTitle)
                Text("\(people.people.count) contacts").font(NDS.body).foregroundStyle(NDS.textSecondary)

                if let cold = goneCold, !cold.isEmpty {
                    card(title: "Reconnect", icon: "person.crop.circle.badge.exclamationmark",
                         subtitle: "Haven't talked in a while") {
                        ForEach(cold, id: \.0.id) { person, last in
                            HStack(spacing: 6) {
                                row(person, trailing: Self.relative.localizedString(for: last, relativeTo: Date()))
                                // Inline reconnect: logs an interaction now so they
                                // drop off the gone-cold list. (TP-8)
                                Button {
                                    people.bumpLastInteraction(personID: person.id, date: Date())
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                }
                                .buttonStyle(.borderless).foregroundStyle(NDS.brand)
                                .help("Mark reached out")
                            }
                        }
                    }
                }

                if let bdays = upcomingBirthdays, !bdays.isEmpty {
                    card(title: "Upcoming birthdays", icon: "gift", subtitle: "Next \(Self.birthdayWindowDays) days") {
                        ForEach(bdays, id: \.0.id) { person, date in
                            row(person, trailing: Self.birthdayFormatter.string(from: date))
                        }
                    }
                }

                if let active = mostActive, !active.isEmpty {
                    card(title: "Most active", icon: "flame", subtitle: "By meetings & encounters") {
                        ForEach(active, id: \.0.id) { person, count in
                            row(person, trailing: "\(count)")
                        }
                    }
                }

                if (goneCold?.isEmpty ?? true) && (upcomingBirthdays?.isEmpty ?? true) && (mostActive?.isEmpty ?? true) {
                    MSEmptyState(systemImage: "person.crop.circle",
                                 title: "No insights yet",
                                 message: "Select a person, or add interactions to see who to reconnect with here.")
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, NDS.splitPaneTopInset)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NDS.bg)
    }

    // MARK: - Computed insight lists

    /// People you've interacted with before but not in a while (excludes
    /// never-contacted imports, which have no lastInteractionAt).
    private var goneCold: [(Person, Date)]? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.goneColdDays, to: Date()) ?? Date()
        return people.people
            .compactMap { p -> (Person, Date)? in
                guard let last = p.lastInteractionAt, last < cutoff else { return nil }
                return (p, last)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(8).map { $0 }
    }

    private var upcomingBirthdays: [(Person, Date)]? {
        let cal = Calendar.current
        let now = Date()
        return people.people
            .compactMap { p -> (Person, Date)? in
                guard let bday = p.birthday, let next = nextOccurrence(of: bday, after: now, cal: cal) else { return nil }
                let days = cal.dateComponents([.day], from: now, to: next).day ?? 999
                return days <= Self.birthdayWindowDays ? (p, next) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(8).map { $0 }
    }

    private var mostActive: [(Person, Int)]? {
        people.people
            .map { p in (p, people.encounterCount(for: p.id) + p.meetingMentions.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(8).map { $0 }
    }

    /// Next time this month/day lands on or after `after`.
    private func nextOccurrence(of birthday: Date, after: Date, cal: Calendar) -> Date? {
        let comps = cal.dateComponents([.month, .day], from: birthday)
        guard let month = comps.month, let day = comps.day else { return nil }
        let year = cal.component(.year, from: after)
        for y in [year, year + 1] {
            if let d = cal.date(from: DateComponents(year: y, month: month, day: day)),
               cal.startOfDay(for: d) >= cal.startOfDay(for: after) {
                return d
            }
        }
        return nil
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func card<Content: View>(title: String, icon: String, subtitle: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(NDS.brand)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(subtitle).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            VStack(spacing: 2) { content() }
        }
        .msCard()
    }

    private func row(_ person: Person, trailing: String) -> some View {
        Button { onOpen(person.id) } label: {
            HStack(spacing: 10) {
                Circle().fill(NDS.selectColor(person.displayName)).frame(width: 26, height: 26)
                    .overlay(Text(initials(person.displayName)).font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.displayName).font(.system(size: 13.5, weight: .medium)).foregroundStyle(NDS.textPrimary)
                    let sub = [person.role, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(trailing).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            .padding(.vertical, 5).padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func initials(_ name: String) -> String {
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        let chars = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    private static let birthdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}
