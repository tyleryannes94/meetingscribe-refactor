import SwiftUI

// MARK: - Encounter Kind & Mood (Phase 2)

extension Encounter {
    /// The nature of the interaction. Stored in `eventName` when not otherwise
    /// specified — this lets the existing Encounter model carry kind data without
    /// a migration. When `kind` is set, `eventName` is set to `kind.rawValue`.
    enum Kind: String, CaseIterable, Identifiable {
        case call        = "Call"
        case coffee      = "Coffee / Meal"
        case videoCall   = "Video Call"
        case message     = "Message"
        case metUp       = "Met Up"
        case milestone   = "Milestone"

        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .call:      return "📞"
            case .coffee:    return "☕️"
            case .videoCall: return "📹"
            case .message:   return "💬"
            case .metUp:     return "🤝"
            case .milestone: return "✨"
            }
        }

        var shortLabel: String {
            switch self {
            case .call:      return "Call"
            case .coffee:    return "Meal"
            case .videoCall: return "Video"
            case .message:   return "Message"
            case .metUp:     return "Met Up"
            case .milestone: return "Milestone"
            }
        }
    }

    /// Emotional quality of the encounter. Appended to notes as a tag when set.
    enum Mood: String, CaseIterable, Identifiable {
        case great   = "great"
        case good    = "good"
        case neutral = "neutral"
        case tense   = "tense"
        case hard    = "hard"

        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .great:   return "😄"
            case .good:    return "🙂"
            case .neutral: return "😐"
            case .tense:   return "😬"
            case .hard:    return "😔"
            }
        }

        var label: String { rawValue.capitalized }
    }
}

// MARK: - Quick Encounter Sheet

/// A lightweight chip-first encounter logging sheet.
/// Design goal: under 10 seconds from open to saved encounter.
///
///   1. Tap a Kind chip (required)  ← auto-saves on tap
///   2. Optionally tap a Mood chip
///   3. Optionally add a one-line note
///   4. Done button (or ⏎) saves; sheet dismisses automatically after step 1
///
/// The existing `PeopleStore.addEncounter` is used as the persistence layer.
@available(macOS 14.0, *)
struct QuickEncounterSheet: View {
    @EnvironmentObject var people: PeopleStore
    let person: Person
    var onSave: ((Encounter) -> Void)?

    @State private var selectedKind: Encounter.Kind? = nil
    @State private var selectedMood: Encounter.Mood? = nil
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var showDatePicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log check-in")
                        .font(.headline)
                    Text(person.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            // Kind chips (tap any to instantly save a quick encounter)
            VStack(alignment: .leading, spacing: 8) {
                Text("How did you connect?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(Encounter.Kind.allCases) { kind in
                        KindChip(
                            kind: kind,
                            selected: selectedKind == kind
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedKind = (selectedKind == kind) ? nil : kind
                            }
                        }
                    }
                }
            }

            // Mood chips (optional)
            if selectedKind != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How did it feel?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 8) {
                        ForEach(Encounter.Mood.allCases) { mood in
                            MoodChip(
                                mood: mood,
                                selected: selectedMood == mood
                            ) {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    selectedMood = (selectedMood == mood) ? nil : mood
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Optional note
                TextField("One-line note (optional)", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { saveIfValid() }
                    .transition(.opacity)

                // Date override
                HStack {
                    Button {
                        withAnimation { showDatePicker.toggle() }
                    } label: {
                        Label(showDatePicker ? "Hide date" : "Change date",
                              systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                if showDatePicker {
                    DatePicker("Date", selection: $date,
                               in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .transition(.opacity)
                }
            }

            // Save button
            HStack {
                Spacer()
                Button {
                    saveIfValid()
                } label: {
                    Label(selectedKind == nil ? "Select a type above" : "Save check-in",
                          systemImage: selectedKind == nil ? "hand.tap" : "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedKind == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 480)
    }

    private func saveIfValid() {
        guard let kind = selectedKind else { return }
        let moodTag = selectedMood.map { " [mood:\($0.rawValue)]" } ?? ""
        let noteFull = note.trimmingCharacters(in: .whitespacesAndNewlines) + moodTag
        let enc = people.addEncounter(
            to: person.id,
            eventName: "\(kind.emoji) \(kind.rawValue)",
            date: date,
            notes: noteFull.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave?(enc)
        // Schedule updated reminders now that there's a new encounter.
        Task { @MainActor in
            // Person.lastInteractionAt is already updated by addEncounter, so
            // passing just the people list is sufficient for cadence calculations.
            await RelationshipNotificationManager.shared.syncPersonReminders(people: people.people)
        }
        dismiss()
    }
}

// MARK: - Chip sub-views

@available(macOS 14.0, *)
private struct KindChip: View {
    let kind: Encounter.Kind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(kind.emoji).font(.title2)
                Text(kind.shortLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? NDS.brand : Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? NDS.brand : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: selected)
    }
}

@available(macOS 14.0, *)
private struct MoodChip: View {
    let mood: Encounter.Mood
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(mood.emoji).font(.title3)
                Text(mood.label).font(.caption2)
                    .foregroundStyle(selected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? NDS.brand.opacity(0.85) : Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}
