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
    /// D3-6: when false (the default), tapping a Kind chip logs the check-in
    /// optimistically and dismisses with an Undo toast — the true 1-tap path.
    /// Flip on to reveal mood/note/date and commit with Save.
    @State private var detailed = false
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
                // Opt into mood / note / date capture. Off by default so the
                // common case stays one tap (D3-6).
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { detailed.toggle() }
                } label: {
                    Label(detailed ? "Quick" : "Add details",
                          systemImage: detailed ? "bolt.fill" : "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(detailed ? "Back to one-tap logging" : "Add mood, a note, or a different date")

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
                            if detailed {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedKind = (selectedKind == kind) ? nil : kind
                                }
                            } else {
                                instantLog(kind)
                            }
                        }
                    }
                }
            }

            // Mood chips (optional) — only in detailed mode; in the 1-tap
            // default the chip tap has already saved and dismissed.
            if detailed, selectedKind != nil {
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

            // Save button (detailed mode only; the 1-tap path saves on chip tap)
            if detailed {
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
            } else {
                Text("Tap how you connected — it logs instantly. Need mood or a note? Add details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 480)
    }

    /// The 1-tap path (D3-6): save the check-in immediately on chip tap, dismiss,
    /// and offer Undo via a toast — no mood/note required for the common case.
    private func instantLog(_ kind: Encounter.Kind) {
        // C2-7: persist the plain kind (e.g. "Call") — no emoji in stored data.
        // The emoji/symbol is rendered at view time. Old rows still carry a
        // leading emoji and are tolerated by readers.
        let enc = people.addEncounter(
            to: person.id,
            eventName: kind.rawValue,
            date: date,
            notes: ""
        )
        onSave?(enc)
        Task { @MainActor in
            await RelationshipNotificationManager.shared.syncPersonReminders(people: people.people)
        }
        let first = person.displayName.split(separator: " ").first.map(String.init) ?? person.displayName
        ToastCenter.shared.show("Logged \(kind.shortLabel) with \(first)",
                                undoTitle: "Undo") { [people] in
            people.deleteEncounter(enc)
        }
        dismiss()
    }

    private func saveIfValid() {
        guard let kind = selectedKind else { return }
        let moodTag = selectedMood.map { " [mood:\($0.rawValue)]" } ?? ""
        let noteFull = note.trimmingCharacters(in: .whitespacesAndNewlines) + moodTag
        // C2-7: persist the plain kind — no emoji in stored data.
        let enc = people.addEncounter(
            to: person.id,
            eventName: kind.rawValue,
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
