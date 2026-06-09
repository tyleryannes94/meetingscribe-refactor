import SwiftUI

/// Today-tab "Stay connected" section: shows up to 3 people with typed
/// relationships who are overdue for a check-in, with a one-tap quick-log
/// button. Only appears when there are overdue people. (Phase 2)
@available(macOS 14.0, *)
struct StayConnectedSection: View {
    @EnvironmentObject var people: PeopleStore
    let onOpenPerson: (Person) -> Void

    @State private var quickLogTarget: Person? = nil

    private var overdueRelationships: [Person] {
        people.people
            .filter { $0.relationshipType != .unset }
            .filter { isOverdue($0) }
            .sorted { overdueDays($0) > overdueDays($1) }
            .prefix(3)
            .map { $0 }
    }

    private func isOverdue(_ p: Person) -> Bool {
        overdueDays(p) > 0
    }

    private func overdueDays(_ p: Person) -> Int {
        let last = p.lastInteractionAt ?? p.createdAt
        let cadence = p.effectiveCheckInDays
        let daysSince = Int(Date().timeIntervalSince(last) / 86400)
        return max(0, daysSince - cadence)
    }

    var body: some View {
        let items = overdueRelationships
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.circle")
                        .foregroundStyle(NDS.gold)
                    Text("Stay connected")
                        .scaledFont(15, weight: .bold)
                    Spacer()
                }

                ForEach(items) { person in
                    HStack(spacing: 12) {
                        // Squircle avatar + emoji type badge
                        ZStack(alignment: .bottomTrailing) {
                            MSAvatar(name: person.displayName, size: 36)
                            Text(person.relationshipType.emoji)
                                .scaledFont(10)
                                .offset(x: 4, y: 4)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.displayName)
                                .scaledFont(13, weight: .bold)
                            Text("\(overdueDays(person)) day\(overdueDays(person) == 1 ? "" : "s") overdue")
                                .font(.caption)
                                .foregroundStyle(NDS.gold)
                        }

                        Spacer()

                        // Quick-log button
                        Button {
                            quickLogTarget = person
                        } label: {
                            Label("Log", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(MSPrimaryButtonStyle())

                        // Open profile
                        Button {
                            onOpenPerson(person)
                        } label: {
                            Image(systemName: "arrow.forward")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(NDS.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: NDS.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius)
                        .strokeBorder(NDS.gold.opacity(0.35), lineWidth: 1))
                }
            }
            .sheet(item: $quickLogTarget) { person in
                QuickEncounterSheet(person: person) { _ in
                    // Dismiss handled inside the sheet; list refreshes via @Published.
                }
                .environmentObject(people)
            }
        }
    }
}
