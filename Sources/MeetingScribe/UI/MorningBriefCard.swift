import SwiftUI

/// AI morning briefing card on Today (5-C): one Ollama-synthesized paragraph that
/// connects today's meetings, open follow-ups, and relationship nudges — the
/// surface that ties all the tabs together in a sentence. Streams in (1-C) and
/// only renders when there's something to say.
@available(macOS 14.0, *)
struct MorningBriefCard: View {
    /// Pre-computed facts for the prompt; empty ⇒ the card hides itself.
    let contextSummary: String
    @StateObject private var vm = MorningBriefVM()

    var body: some View {
        if !contextSummary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").foregroundStyle(NDS.gold)
                    Text("Morning brief").scaledFont(12, weight: .semibold)
                        .foregroundStyle(NDS.textSecondary)
                    Spacer()
                    if vm.generating {
                        ProgressView().controlSize(.small)
                    }
                }
                if vm.text.isEmpty && vm.generating {
                    Text("Putting your day together…").scaledFont(13)
                        .foregroundStyle(NDS.textTertiary)
                } else if !vm.text.isEmpty {
                    Text(vm.text).scaledFont(14).foregroundStyle(NDS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NDS.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: NDS.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius).strokeBorder(NDS.gold.opacity(0.2), lineWidth: 1))
            .onAppear { vm.generateIfStale(contextSummary) }
        }
    }
}

@available(macOS 14.0, *)
@MainActor
final class MorningBriefVM: ObservableObject {
    @Published var text = ""
    @Published var generating = false
    private var lastContext = ""
    private var task: Task<Void, Never>?

    /// Regenerate only when the day's facts changed, so re-renders don't re-hit
    /// the model. Caches the last brief in-session.
    func generateIfStale(_ context: String) {
        guard context != lastContext else { return }
        lastContext = context
        task?.cancel()
        text = ""; generating = true
        let prompt = """
        Write Tyler a warm, specific morning brief of 2–3 sentences that connects \
        today's meetings, open follow-ups, and any relationship nudges into a single \
        short paragraph. Plain prose, no lists, no preamble.

        Today:
        \(context)
        """
        task = Task { [weak self] in
            do {
                _ = try await OllamaService().streamGenerate(prompt: prompt, temperature: 0.4) { piece in
                    Task { @MainActor in self?.text += piece }
                }
            } catch { /* leave empty on failure — card stays minimal */ }
            await MainActor.run { self?.generating = false }
        }
    }
}
