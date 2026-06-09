import SwiftUI

/// Today-tab surface for Phase B: people the auto-extraction pipeline found in
/// recent transcripts but wasn't sure about. One tap to confirm (link or
/// create) or dismiss. Renders nothing when there are no pending suggestions.
@available(macOS 14.0, *)
struct SuggestedPeopleView: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var extraction: PersonExtractionController

    var body: some View {
        if !people.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(NDS.brand)
                    Text("Suggested people").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    Text("\(people.suggestions.count)")
                        .font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
                    Spacer()
                    if extraction.isRunning {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Scanning \(extraction.processed)/\(extraction.total)")
                                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                        }
                    }
                }
                ForEach(people.suggestions) { s in
                    SuggestionRow(suggestion: s,
                                  onConfirm: { people.confirmSuggestion(s) },
                                  onDismiss: { people.dismissSuggestion(s) })
                }
            }
            .padding(14)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
        }
    }
}

@available(macOS 14.0, *)
private struct SuggestionRow: View {
    let suggestion: PersonSuggestion
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    private var headline: String {
        if let name = suggestion.matchedPersonName {
            return "Is “\(suggestion.extractedName)” the same as \(name)?"
        }
        return "Add \(suggestion.extractedName)?"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.circle").scaledFont(22).foregroundStyle(NDS.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).scaledFont(13, weight: .semibold)
                if !suggestion.summary.isEmpty {
                    Text(suggestion.summary).font(NDS.small).foregroundStyle(NDS.textSecondary).lineLimit(2)
                }
                Text("from \(suggestion.meetingTitle)")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Button(suggestion.isPossibleMatch ? "Link" : "Add", action: onConfirm)
                    .controlSize(.small)
                Button("Dismiss", action: onDismiss)
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Today-tab "stay in touch" nudges — people you haven't interacted with in a
/// while (by `lastInteractionAt`). Renders nothing when nobody is overdue.
@available(macOS 14.0, *)
struct ReconnectView: View {
    @EnvironmentObject var people: PeopleStore
    var onOpen: (Person) -> Void

    /// "Not yet" hides a suggestion for the rest of the session without
    /// logging a fake interaction (C3-7).
    @State private var snoozed: Set<String> = []

    /// Fallback cadence when there isn't enough history to infer one.
    private static let defaultCadenceDays: Double = 30

    /// Per-person reconnect cadence (P2-1): infer "how often you usually talk"
    /// from the median gap between encounters, and flag someone overdue at ~1.5×
    /// that. Falls back to 30 days for people without enough history. Clamped to
    /// a sane 7–120 day window.
    private func cadenceSeconds(for p: Person) -> TimeInterval {
        let dates = people.encounters(for: p.id).map(\.date).sorted()
        guard dates.count >= 3 else { return Self.defaultCadenceDays * 86400 }
        var gaps: [Double] = []
        for i in 1..<dates.count { gaps.append(dates[i].timeIntervalSince(dates[i - 1]) / 86400) }
        let median = gaps.sorted()[gaps.count / 2]
        return min(120, max(7, median * 1.5)) * 86400
    }

    private var candidates: [(person: Person, last: Date)] {
        let now = Date()
        return people.people
            .compactMap { p -> (Person, Date)? in
                guard !snoozed.contains(p.id),
                      let last = p.lastInteractionAt,
                      now.timeIntervalSince(last) > cadenceSeconds(for: p) else { return nil }
                return (p, last)
            }
            .sorted { $0.1 < $1.1 }   // most overdue first
            .prefix(4)
            .map { (person: $0.0, last: $0.1) }
    }

    var body: some View {
        let items = candidates
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.wave.2").foregroundStyle(NDS.brand)
                    Text("Stay in touch").font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    Spacer()
                }
                ForEach(items, id: \.person.id) { item in
                    HStack(spacing: 10) {
                        Button { onOpen(item.person) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.circle")
                                    .scaledFont(22).foregroundStyle(NDS.textTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.person.displayName)
                                        .scaledFont(13, weight: .semibold)
                                        .foregroundStyle(NDS.textPrimary)
                                    Text(Self.lastText(item.last))
                                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 4)
                        // C3-7 — turn the passive card into an active habit
                        // trigger. "Yes" logs the interaction (drops them off
                        // the list); "Not yet" snoozes for this session.
                        HStack(spacing: 4) {
                            Text("Did you connect?")
                                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            Button("Yes") {
                                people.bumpLastInteraction(personID: item.person.id, date: Date())
                            }
                            .buttonStyle(.borderless).font(NDS.tiny).foregroundStyle(NDS.brand)
                            Button("Not yet") {
                                snoozed.insert(item.person.id)
                            }
                            .buttonStyle(.borderless).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(14)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))
        }
    }

    private static func lastText(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days >= 365 { return "Last talked over a year ago" }
        if days >= 60  { return "Last talked \(days / 30) months ago" }
        return "Last talked \(days) days ago"
    }
}
