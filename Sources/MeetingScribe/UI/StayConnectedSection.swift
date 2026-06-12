import SwiftUI
import VaultKit

/// Today-tab "Stay connected" section: shows up to 3 people with typed
/// relationships who are overdue for a check-in, ordered by lowest connection
/// health first, with a one-tap quick-log button. Only appears when there are
/// overdue people. (Phase 2)
@available(macOS 14.0, *)
struct StayConnectedSection: View {
    @EnvironmentObject var people: PeopleStore
    let onOpenPerson: (Person) -> Void

    @State private var quickLogTarget: Person? = nil

    private var overdueRelationships: [Person] {
        people.people
            .filter { $0.relationshipType != .unset }
            .filter { isOverdue($0) }
            // Worst health first — health blends recency, frequency, and
            // consistency, so it's a better triage order than raw overdue days.
            .sorted { health(for: $0).score < health(for: $1).score }
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

    /// Shared 0–100 health (same formula as the person detail badge + MCP tool).
    private func health(for p: Person) -> RelationshipHealth {
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

    private func healthColor(_ band: RelationshipHealth.Band) -> Color {
        switch band {
        case .thriving: return NDS.mint
        case .steady:   return NDS.sky
        case .drifting: return NDS.gold
        case .overdue:  return NDS.danger
        }
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
                    let h = health(for: person)
                    let color = healthColor(h.band)
                    HStack(spacing: 12) {
                        // Squircle avatar + typed-glyph type badge (C2-7)
                        ZStack(alignment: .bottomTrailing) {
                            MSAvatar(name: person.displayName, size: 36)
                            RelationshipTypeChip(type: person.relationshipType, showLabel: false)
                                .offset(x: 6, y: 6)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.displayName)
                                .scaledFont(13, weight: .bold)
                            Text("\(h.band.rawValue.capitalized) · \(overdueDays(person)) day\(overdueDays(person) == 1 ? "" : "s") overdue")
                                .font(.caption)
                                .foregroundStyle(color)
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
                        .accessibilityLabel("Open \(person.displayName)")
                    }
                    .padding(10)
                    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: NDS.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius)
                        .strokeBorder(color.opacity(0.35), lineWidth: 1))
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
