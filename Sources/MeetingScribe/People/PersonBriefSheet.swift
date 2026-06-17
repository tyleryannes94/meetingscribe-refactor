import SwiftUI

/// Streams a one-shot, Ollama-synthesized relationship brief (2-B) — the single
/// most visible proof that MeetingScribe is a second brain. Built on the canonical
/// `PersonContextBuilder` (1-D) and the streaming summary path (1-C).
@available(macOS 14.0, *)
@MainActor
final class PersonBriefVM: ObservableObject {
    @Published var brief = ""
    @Published var generating = false
    @Published var error: String?
    private var task: Task<Void, Never>?

    func generate(name: String, contextBlock: String) {
        task?.cancel()
        brief = ""; error = nil; generating = true
        let prompt = """
        You are preparing Tyler for time with \(name). Using ONLY the facts below, \
        write a warm, concise brief of about 150 words covering: the current state of \
        the relationship, the key open items, and two specific talking points to \
        raise. Write in plain prose — no headings, no bullet lists, no preamble.

        Facts:
        \(contextBlock)
        """
        task = Task { [weak self] in
            do {
                _ = try await OllamaService().streamGenerate(prompt: prompt, temperature: 0.3) { piece in
                    Task { @MainActor in self?.brief += piece }
                }
            } catch {
                await MainActor.run { self?.error = "Couldn't generate a brief. Make sure the summary engine (Ollama) is running." }
            }
            await MainActor.run { self?.generating = false }
        }
    }

    func cancel() { task?.cancel() }
}

@available(macOS 14.0, *)
struct PersonBriefSheet: View {
    let personID: String
    let actionItems: ActionItemStore
    let pastMeetings: [Meeting]
    var calendarUpcoming: [Meeting] = []

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PersonBriefVM()

    private var context: PersonContext? {
        PersonContextBuilder.build(personID: personID, actionItems: actionItems,
                                   pastMeetings: pastMeetings, calendarUpcoming: calendarUpcoming)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NDS.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    synthesis
                    if let ctx = context { contextCards(ctx) }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 640)
        .onAppear { regenerate() }
        .onDisappear { vm.cancel() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(NDS.brand)
            Text(context.map { "Brief: \($0.person.displayName)" } ?? "Brief")
                .font(.headline)
            Spacer()
            Button { regenerate() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(vm.generating)
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var synthesis: some View {
        if let error = vm.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(NDS.small).foregroundStyle(NDS.textSecondary)
        } else if vm.brief.isEmpty && vm.generating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Thinking…").font(NDS.small).foregroundStyle(NDS.textSecondary)
            }
        } else {
            Text(vm.brief)
                .font(NDS.body)
                .foregroundStyle(NDS.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func contextCards(_ ctx: PersonContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NotionEyebrow(text: "Context")
            if let s = ctx.strengthScore {
                briefRow("heart.fill", "Relationship strength", "\(Int(s * 100))/100")
            }
            if let m = ctx.lastMeeting {
                briefRow("calendar", "Last meeting", m.displayTitle)
            }
            briefRow("number", "Meetings together", "\(ctx.meetingCount)")
            if !ctx.openTasksForPerson.isEmpty {
                briefRow("checklist", "Open items they own", "\(ctx.openTasksForPerson.count)")
            }
            if !ctx.talkingPoints.isEmpty {
                briefRow("text.bubble", "Talking points", ctx.talkingPoints.joined(separator: " · "))
            }
            if let e = ctx.nextSharedEvent {
                briefRow("calendar.badge.clock", "Next meeting", e.displayTitle)
            }
        }
    }

    private func briefRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).scaledFont(12).foregroundStyle(NDS.textTertiary).frame(width: 18)
            Text(label).font(NDS.small).foregroundStyle(NDS.textSecondary).frame(width: 150, alignment: .leading)
            Text(value).font(NDS.small).foregroundStyle(NDS.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func regenerate() {
        guard let ctx = context else {
            vm.error = "No context available for this person yet."
            return
        }
        vm.generate(name: ctx.person.displayName, contextBlock: ctx.aiContextBlock())
    }
}
