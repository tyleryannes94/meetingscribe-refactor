import SwiftUI
import VaultKit

/// Keep-in-touch board (C2-2): a Dex-style kanban that groups typed-relationship
/// people into four columns by relationship-health band — Overdue · Drifting ·
/// Steady · Thriving — so "who needs attention" is whole-network triage in one
/// screen. Each column is a vertical list of person cards (ringed avatar, name,
/// last-met); tapping a card opens that person via the caller's `onOpen`.
@available(macOS 14.0, *)
@MainActor
struct KeepInTouchBoard: View {
    @EnvironmentObject var store: PeopleStore
    /// Typed-relationship people to triage (already filtered by the caller).
    let people: [Person]
    /// Open a person by id (router-backed).
    let onOpen: (String) -> Void

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()

    /// Shared 0–100 health (same formula as `StayConnectedSection.health(for:)`,
    /// the health ring, and the MCP coach — so the bands agree everywhere).
    private func health(for p: Person) -> RelationshipHealth {
        let encs = store.encounters(for: p.id)
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

    /// People bucketed by band, columns in triage order (worst first), each
    /// column sorted lowest-health-first so the most urgent card is on top.
    private var columns: [(band: RelationshipHealth.Band, people: [Person])] {
        var buckets: [RelationshipHealth.Band: [(person: Person, score: Int)]] = [:]
        for p in people {
            let h = health(for: p)
            buckets[h.band, default: []].append((p, h.score))
        }
        let order: [RelationshipHealth.Band] = [.overdue, .drifting, .steady, .thriving]
        return order.map { band in
            let sorted = (buckets[band] ?? [])
                .sorted { $0.score < $1.score }
                .map { $0.person }
            return (band, sorted)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns, id: \.band) { col in
                    column(col.band, col.people)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Column

    @ViewBuilder
    private func column(_ band: RelationshipHealth.Band, _ items: [Person]) -> some View {
        let color = bandColor(band)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: bandIcon(band)).foregroundStyle(color)
                Text(bandTitle(band)).scaledFont(14, weight: .bold)
                Text("\(items.count)")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(NDS.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(color.opacity(0.18), in: Capsule())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            if items.isEmpty {
                Text("No one here")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12).padding(.horizontal, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(items) { person in
                            card(person, color)
                        }
                    }
                }
            }
        }
        .frame(width: 240)
        .padding(10)
        .background(NDS.columnBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius).strokeBorder(NDS.hairline, lineWidth: 1))
    }

    // MARK: - Card

    @ViewBuilder
    private func card(_ person: Person, _ color: Color) -> some View {
        Button {
            onOpen(person.id)
        } label: {
            HStack(spacing: 10) {
                MSAvatar(name: person.displayName, size: 32,
                         ringColor: healthRingColor(for: person, in: store))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(person.displayName).scaledFont(13, weight: .semibold).lineLimit(1)
                        if person.relationshipType != .unset {
                            Text(person.relationshipType.emoji)
                                .scaledFont(10)
                                .help(person.relationshipType.displayName)
                        }
                    }
                    Text(lastMet(person)).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
            .overlay(RoundedRectangle(cornerRadius: NDS.radius).strokeBorder(color.opacity(0.25), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: NDS.radius))
        }
        .buttonStyle(.plain)
        .help("Open \(person.displayName)")
        .accessibilityLabel("Open \(person.displayName)")
    }

    private func lastMet(_ p: Person) -> String {
        guard let last = p.lastInteractionAt else { return "No interactions yet" }
        return "Last met " + Self.relative.localizedString(for: last, relativeTo: Date())
    }

    // MARK: - Band styling (mirrors the shared health-ring colors)

    private func bandColor(_ band: RelationshipHealth.Band) -> Color {
        switch band {
        case .thriving: return NDS.mint
        case .steady:   return NDS.sky
        case .drifting: return NDS.gold
        case .overdue:  return NDS.danger
        }
    }

    private func bandTitle(_ band: RelationshipHealth.Band) -> String {
        switch band {
        case .thriving: return "Thriving"
        case .steady:   return "Steady"
        case .drifting: return "Drifting"
        case .overdue:  return "Overdue"
        }
    }

    private func bandIcon(_ band: RelationshipHealth.Band) -> String {
        switch band {
        case .thriving: return "flame.fill"
        case .steady:   return "checkmark.circle.fill"
        case .drifting: return "exclamationmark.triangle.fill"
        case .overdue:  return "clock.badge.exclamationmark.fill"
        }
    }
}
