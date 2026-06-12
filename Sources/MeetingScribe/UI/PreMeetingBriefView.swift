import SwiftUI
import AppKit

/// Pre-meeting brief shown when a user taps into an upcoming calendar event.
/// Replaces the "No transcript yet" placeholder with genuinely useful context:
///   • Prior meetings with any of the same attendees (email-matched)
///   • Open action items from those prior meetings
///   • Attendee People-record links (if they exist in PeopleStore)
///
/// Data is all in-memory — no async work needed beyond an initial filter pass.
@available(macOS 14.0, *)
struct PreMeetingBriefView: View {
    let meeting: Meeting

    @EnvironmentObject var manager: MeetingManager

    // Computed once on appear; stored in state so the view doesn't
    // recompute on every re-render triggered by unrelated manager changes.
    @State private var priorMeetings: [Meeting] = []
    @State private var openItems: [ActionItem] = []
    /// LLM-synthesized brief (P1-3). nil until generated; the static lists below
    /// are always shown as backup detail.
    @State private var brief: String?
    @State private var generating = false
    @State private var briefMeetingID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                synthesizedSection
                talkingPointsSection   // U1-5: "discuss next time" per attendee
                if !openItems.isEmpty   { openItemsSection }
                if !priorMeetings.isEmpty { priorMeetingsSection }
                if priorMeetings.isEmpty && openItems.isEmpty { emptyState }
            }
            .padding()
        }
        .onAppear { computeBrief() }
        .onChange(of: meeting.id) { _, _ in computeBrief() }
    }

    /// U1-5: surface "discuss next time" talking points for the meeting's
    /// resolved attendees — the notes you jotted are waiting where you need them.
    @ViewBuilder
    private var talkingPointsSection: some View {
        let people = PeopleStore.shared.people
        let entries: [(name: String, points: [String])] = meeting.attendees.compactMap { raw in
            guard let id = PersonResolver.resolve(raw, in: people),
                  let p = people.first(where: { $0.id == id }), !p.talkingPoints.isEmpty
            else { return nil }
            return (p.displayName, p.talkingPoints)
        }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Discuss next time", systemImage: "bubble.left.fill")
                    .font(.headline).foregroundStyle(NDS.gold)
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.subheadline.weight(.semibold))
                        ForEach(Array(entry.points.enumerated()), id: \.offset) { _, pt in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(NDS.gold)
                                Text(pt).font(.callout).foregroundStyle(NDS.textSecondary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NDS.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                }
            }
        }
    }

    @ViewBuilder
    private var synthesizedSection: some View {
        if generating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Synthesizing brief…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let brief, !brief.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Summary", systemImage: "sparkles")
                    .font(.callout.weight(.semibold)).foregroundStyle(NDS.brand)
                MarkdownText(brief)
            }
            .padding(12)
            .background(NDS.brand.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Pre-meeting brief", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .foregroundStyle(NDS.brand)
            Text("Context from previous meetings with these attendees.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var openItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Open action items from prior meetings",
                  systemImage: "checklist")
                .font(.callout.weight(.semibold))

            ForEach(openItems.prefix(10)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle")
                        .scaledFont(14)
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.callout)
                        if let mtg = manager.pastMeetings.first(where: { $0.id == item.meetingID }) {
                            Text(mtg.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            if openItems.count > 10 {
                Text("+ \(openItems.count - 10) more in Tasks tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(NDS.brand.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var priorMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent meetings with these attendees",
                  systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.callout.weight(.semibold))

            ForEach(priorMeetings.prefix(5)) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.displayTitle)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(m.startDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let items = manager.actionItems.items(for: m.id)
                        .filter { $0.status != .completed }
                    if !items.isEmpty {
                        Text("\(items.count) open action item\(items.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .scaledFont(32)
                .foregroundStyle(.secondary)
            Text("No prior meetings found")
                .font(.callout.weight(.medium))
            Text("This appears to be a first meeting with these attendees, or Calendar access hasn't been granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    // MARK: - Data computation

    private func computeBrief() {
        let emails = attendeeEmails(from: meeting.attendees)
        guard !emails.isEmpty else {
            priorMeetings = []
            openItems = []
            return
        }

        // All past meetings that share at least one attendee email.
        let related = manager.pastMeetings.filter { past in
            let pastEmails = attendeeEmails(from: past.attendees)
            return !pastEmails.isDisjoint(with: emails)
        }
        .sorted { $0.startDate > $1.startDate }

        priorMeetings = Array(related.prefix(10))

        // Collect open action items from those meetings.
        openItems = related.flatMap { m in
            manager.actionItems.items(for: m.id).filter { $0.status != .completed }
        }
        .sorted { $0.createdAt > $1.createdAt }

        // Synthesize a brief (once per meeting) when there's something to say.
        if briefMeetingID != meeting.id, !(priorMeetings.isEmpty && openItems.isEmpty) {
            briefMeetingID = meeting.id
            brief = nil
            generating = true
            let prior = priorMeetings, items = openItems
            Task { await generateSynthesis(prior: prior, items: items) }
        }
    }

    /// Series-aware LLM synthesis (P1-3/P1-2): carries forward last-time context
    /// from the most recent occurrence of the same recurring series (seriesID,
    /// which previously did nothing) plus open commitments, and asks the local
    /// model for a tight brief. Degrades to the static lists if Ollama is down.
    private func generateSynthesis(prior: [Meeting], items: [ActionItem]) async {
        let df = DateFormatter(); df.dateStyle = .medium
        // Most recent prior occurrence of the SAME recurring series.
        let seriesPrior: Meeting? = meeting.seriesID.flatMap { sid in
            sid.isEmpty ? nil : prior.first { $0.seriesID == sid }
        }
        var ctx = "Upcoming meeting: \(meeting.displayTitle)\n"
        ctx += "Attendees: \(meeting.attendees.joined(separator: ", "))\n\n"
        if let sp = seriesPrior {
            let summary = manager.summaryMarkdown(for: sp)
            ctx += "This is a recurring meeting. Last occurrence (\(df.string(from: sp.startDate))):\n"
            ctx += String(summary.prefix(2000)) + "\n\n"
        }
        if !items.isEmpty {
            ctx += "Open commitments from prior meetings:\n"
            ctx += items.prefix(15).map { "- \($0.title)" }.joined(separator: "\n") + "\n\n"
        }
        if !prior.isEmpty {
            ctx += "Recent meetings with these attendees:\n"
            ctx += prior.prefix(5).map { "- \($0.displayTitle) (\(df.string(from: $0.startDate)))" }
                .joined(separator: "\n")
        }
        let prompt = """
        You are preparing the user for an upcoming meeting. Using ONLY the context below, write a tight pre-meeting brief in Markdown with these sections (omit any with no content):
        - **Where you left off** — 1–2 sentences on last time (only if recurring context is given).
        - **Open commitments to follow up** — bullets: who owes what.
        - **Suggested talking points** — 2–4 bullets.
        Under 150 words. No preamble, no closing remarks.

        CONTEXT:
        \(ctx)
        """
        do {
            let result = try await OllamaService().generate(prompt: prompt, temperature: 0.3)
            await MainActor.run {
                guard self.meeting.id == self.briefMeetingID else { return }
                self.brief = result
                self.generating = false
            }
        } catch {
            await MainActor.run { self.generating = false }  // fall back to static lists
        }
    }

    /// Normalized emails for a meeting's attendees, via the one identity layer.
    private func attendeeEmails(from attendees: [String]) -> Set<String> {
        Set(attendees.compactMap { str -> String? in
            let id = PersonResolver.parse(str)
            return id.hasEmail ? id.email : nil
        })
    }
}
