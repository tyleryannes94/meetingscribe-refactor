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
            Image(systemName: "person.circle").font(.system(size: 22)).foregroundStyle(NDS.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .semibold))
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
