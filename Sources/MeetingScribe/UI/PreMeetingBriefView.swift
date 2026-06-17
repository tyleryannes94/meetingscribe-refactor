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
    /// Recurring-only (P-2): the last 2 occurrences of THIS series, each with
    /// the topics covered (bullet points pulled from its summary) and its action
    /// items. Empty for one-off meetings.
    @State private var seriesRecap: [SeriesRecapEntry] = []
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
                if !seriesRecap.isEmpty { seriesRecapSection }   // recurring only
                talkingPointsSection   // U1-5: "discuss next time" per attendee
                relationshipSummarySection   // 2-G: who these people are
                if !openItems.isEmpty   { openItemsSection }
                if !priorMeetings.isEmpty { priorMeetingsSection }
                if priorMeetings.isEmpty && openItems.isEmpty { emptyState }
            }
            .padding()
        }
        .onAppear { computeBrief() }
        .onChange(of: meeting.id) { _, _ in computeBrief() }
    }

    /// 2-G: a short "about this person" line per known attendee — the cached
    /// relationship summary excerpt plus strength — surfaced at the highest-ROC
    /// moment (2 minutes before the call).
    @ViewBuilder
    private var relationshipSummarySection: some View {
        let people = PeopleStore.shared.people
        let entries: [(person: Person, excerpt: String)] = meeting.attendees.compactMap { raw in
            guard let id = PersonResolver.resolve(raw, in: people),
                  let p = people.first(where: { $0.id == id }),
                  let note = p.attachedNotes.first(where: { $0.kind == "summary-all" }),
                  !note.body.isEmpty else { return nil }
            return (p, String(note.body.prefix(220)))
        }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("About these people", systemImage: "person.text.rectangle")
                    .font(.headline).foregroundStyle(NDS.brand)
                ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(e.person.displayName).font(.subheadline.weight(.semibold))
                            if e.person.relationshipStrengthScore > 0 {
                                Text("· \(Int(e.person.relationshipStrengthScore * 100)) strength")
                                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            }
                        }
                        Text(e.excerpt).font(.callout).foregroundStyle(NDS.textSecondary)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(NDS.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                }
            }
        }
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

    /// Recurring-only recap: the last 2 occurrences of this series, each with
    /// the topics covered and that call's action items. (P-2)
    private var seriesRecapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Last 2 meetings in this series", systemImage: "repeat")
                .font(.callout.weight(.semibold)).foregroundStyle(.purple)
            ForEach(seriesRecap) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.meeting.displayTitle).font(.callout.weight(.medium))
                        Spacer()
                        Text(entry.meeting.startDate, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !entry.topics.isEmpty {
                        Text("Topics covered").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(entry.topics.enumerated()), id: \.offset) { _, t in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(.purple)
                                Text(t).font(.callout).foregroundStyle(NDS.textSecondary)
                            }
                        }
                    }
                    if !entry.items.isEmpty {
                        Text("Action items").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(entry.items.prefix(8)) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                                    .scaledFont(12)
                                    .foregroundStyle(item.status == .completed ? .green : .secondary)
                                    .padding(.top, 1)
                                Text(item.title).font(.callout)
                            }
                        }
                    }
                    if entry.topics.isEmpty && entry.items.isEmpty {
                        Text("No summary or action items captured for this occurrence.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: NDS.rowRadius))
            }
        }
    }

    @ViewBuilder
    private var synthesizedSection: some View {
        if generating {
            // D4-9: a shaped skeleton + labeled spinner instead of a bare one,
            // so the loading brief reads as "coming", not broken.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Synthesizing brief…").font(.caption).foregroundStyle(.secondary)
                }
                MSSkeleton(lines: 4)
            }
            .padding(12)
            .background(NDS.brand.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let brief, !brief.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Summary", systemImage: "sparkles")
                        .font(.callout.weight(.semibold)).foregroundStyle(NDS.brand)
                    Spacer()
                    // P1-5: regenerate on demand — re-synthesizes from the latest
                    // prior meetings + open items, bypassing the cached brief.
                    Button { regenerateBrief() } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Re-synthesize this brief from the latest prior meetings and open items")
                }
                MarkdownText(brief)
            }
            .padding(12)
            .background(NDS.brand.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// P1-5: force a fresh synthesis, ignoring the cached brief.
    private func regenerateBrief() {
        guard !generating else { return }
        brief = nil
        generating = true
        let prior = priorMeetings, items = openItems
        Task { await generateSynthesis(prior: prior, items: items) }
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
        // Recurring-only (P-2): the last 2 occurrences of THIS series, with the
        // topics covered (from each summary) and that call's action items.
        // Matched by seriesID, so this works even when attendees lack emails.
        if let sid = meeting.seriesID, !sid.isEmpty {
            let occurrences = manager.pastMeetings
                .filter { $0.seriesID == sid && $0.id != meeting.id }
                .sorted { $0.startDate > $1.startDate }
                .prefix(2)
            seriesRecap = occurrences.map { occ in
                SeriesRecapEntry(
                    meeting: occ,
                    topics: Self.topicBullets(from: manager.summaryMarkdown(for: occ), limit: 6),
                    items: manager.actionItems.items(for: occ.id)
                )
            }
        } else {
            seriesRecap = []
        }

        let emails = attendeeEmails(from: meeting.attendees)
        guard !emails.isEmpty else {
            priorMeetings = []
            openItems = []
            maybeSynthesize()
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

        maybeSynthesize()
    }

    /// Kicks off the LLM synthesis once per meeting when there's something to
    /// say — prior meetings, open items, OR (for recurring calls) the series
    /// recap. Shows the persisted brief instantly, then refreshes in background.
    private func maybeSynthesize() {
        guard briefMeetingID != meeting.id,
              !(priorMeetings.isEmpty && openItems.isEmpty && seriesRecap.isEmpty)
        else { return }
        briefMeetingID = meeting.id
        if let cached = BriefCache.load(meeting.id) {
            brief = cached
            generating = false
        } else {
            brief = nil
            generating = true
        }
        let prior = priorMeetings, items = openItems
        Task { await generateSynthesis(prior: prior, items: items) }
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
        // Recurring (P-2): feed the last 2 occurrences — topics covered + action
        // items — so the brief carries forward this series' running thread.
        if !seriesRecap.isEmpty {
            ctx += "This is a recurring meeting. Recap of the last \(seriesRecap.count) occurrence(s):\n"
            for entry in seriesRecap {
                ctx += "\n• \(entry.meeting.displayTitle) (\(df.string(from: entry.meeting.startDate)))\n"
                if !entry.topics.isEmpty {
                    ctx += "  Topics covered:\n"
                    ctx += entry.topics.map { "    - \($0)" }.joined(separator: "\n") + "\n"
                }
                let open = entry.items.filter { $0.status != .completed }
                if !open.isEmpty {
                    ctx += "  Open action items:\n"
                    ctx += open.prefix(10).map { "    - \($0.title)" }.joined(separator: "\n") + "\n"
                }
            }
            ctx += "\n"
        } else if let sp = seriesPrior {
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
        - **Recap of the last 2 meetings** — bullets covering the key topics discussed and the action items from each (only if recurring context is given).
        - **Open commitments to follow up** — bullets: who owes what.
        - **Suggested talking points** — 2–4 bullets.
        Under 180 words. No preamble, no closing remarks.

        CONTEXT:
        \(ctx)
        """
        do {
            let result = try await OllamaService().generate(prompt: prompt, temperature: 0.3)
            BriefCache.save(result, for: meeting.id)   // U1-10: persist for instant reload
            await MainActor.run {
                guard self.meeting.id == self.briefMeetingID else { return }
                self.brief = result
                self.generating = false
                // F3: if this meeting has already been recorded, drop the brief
                // into its notes so it's visible during/after the call too. For
                // not-yet-recorded calendar events this no-ops (no folder yet);
                // startRecording seeds the brief from BriefCache at record time.
                self.manager.attachBriefToNotes(result, for: self.meeting, onlyIfRecorded: true)
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

    /// Pulls up to `limit` "topics covered" bullets from a meeting's summary
    /// markdown — bullet lines (`- `, `* `, `• `) and headings (`#`), stripped of
    /// their markers. Lets the recap show what a prior occurrence was about
    /// without depending on the LLM.
    static func topicBullets(from summary: String, limit: Int) -> [String] {
        var out: [String] = []
        for rawLine in summary.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var text: String?
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                text = String(line.dropFirst(2))
            } else if line.hasPrefix("#") {
                text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            // Skip markdown checkbox lines (those are action items, shown separately).
            if let t = text?.trimmingCharacters(in: .whitespaces),
               !t.isEmpty, !t.hasPrefix("[ ]"), !t.hasPrefix("[x]"), !t.hasPrefix("[X]") {
                out.append(t)
                if out.count >= limit { break }
            }
        }
        return out
    }
}

/// One prior occurrence of a recurring series, summarized for the brief.
@available(macOS 14.0, *)
struct SeriesRecapEntry: Identifiable {
    let meeting: Meeting
    let topics: [String]
    let items: [ActionItem]
    var id: String { meeting.id }
}

/// Persists pre-meeting briefs to disk so re-opening a meeting shows the brief
/// instantly instead of waiting on a cold Ollama call (U1-10). A derived cache
/// under Application Support — safe to delete; regenerated on demand.
enum BriefCache {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe/briefs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static func url(_ id: String) -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return dir.appendingPathComponent("\(safe).md")
    }
    static func load(_ meetingID: String) -> String? {
        let text = try? String(contentsOf: url(meetingID), encoding: .utf8)
        return (text?.isEmpty == false) ? text : nil
    }
    static func save(_ brief: String, for meetingID: String) {
        try? brief.write(to: url(meetingID), atomically: true, encoding: .utf8)
    }
}
