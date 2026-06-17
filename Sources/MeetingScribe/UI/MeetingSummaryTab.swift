import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    // MARK: - Summary helpers (used by the canvas summary section)

    /// A genuine finished recap — non-empty and not the "_Summary unavailable_"
    /// failure placeholder. Gates the summary/notes split so a failed run shows
    /// the retry banner, not a dead pane rendering the placeholder text.
    var hasRealSummary: Bool {
        let s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.isEmpty && !s.contains("_Summary unavailable")
    }

    /// True while the post-meeting summary is actively generating (or streaming).
    var isSummaryGenerating: Bool {
        guard let id = meeting?.id else { return false }
        return pipeline.summaryGeneratingIDs.contains(id)
            || !(pipeline.liveSummaryByID[id] ?? "").isEmpty
    }

    @ViewBuilder
    var summaryGeneratingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Generating summary…")
                    .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
            }
            if let id = meeting?.id, let live = pipeline.liveSummaryByID[id], !live.isEmpty {
                ScrollView {
                    MarkdownEditor(text: .constant(live), isEditable: false)
                        .padding(.horizontal, 8)
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NDS.sidebarBg)
    }

    @ViewBuilder
    var summaryFailedBanner: some View {
        if let m = meeting {
            let isRetrying = manager.transcribingMeetingIDs.contains(m.id)
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NDS.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No summary yet")
                        .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    Text("The summary engine wasn't reachable when this finished. Your transcript is safe.")
                        .font(NDS.small).foregroundStyle(NDS.textTertiary)
                }
                Spacer(minLength: 8)
                if isRetrying {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Generate summary") {
                        manager.pipelineController.transcribeNow(meeting: m, regenerateSummary: true)
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NDS.sidebarBg)
        }
    }

    /// 4-F / 5-A: meetings the embedding index found similar to this one, loaded
    /// in `reload()` into `relatedMeetings` but previously never rendered. Tapping
    /// one opens it.
    @ViewBuilder
    var relatedMeetingsStrip: some View {
        if !relatedMeetings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Related meetings")
                    .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                ForEach(relatedMeetings) { m in
                    Button { router.openMeeting(m) } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.displayTitle).font(NDS.small).foregroundStyle(NDS.textPrimary)
                                Text(m.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .scaledFont(11).foregroundStyle(NDS.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .scaledFont(10).foregroundStyle(NDS.textTertiary)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    @ViewBuilder
    /// C1-6: copy the recap for the channel you're pasting into.
    var copyMenu: some View {
        Menu {
            Button("Copy as plain text") { copyToClipboard(summary) }
            Button("Copy for Slack") { copyToClipboard(slackFormatted(summary)) }
            Button("Copy as email") { copyToClipboard(emailFormatted(summary)) }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.show("Copied")
    }

    /// Lightly de-markdown for Slack: `## H` → `*H*`, `**b**` → `*b*`.
    private func slackFormatted(_ md: String) -> String {
        var s = md
        s = s.replacingOccurrences(of: #"(?m)^#{1,6}\s*(.+)$"#, with: "*$1*", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "*$1*", options: .regularExpression)
        let title = meeting?.displayTitle ?? "Meeting"
        return "*\(title) — recap*\n\n" + s
    }

    private func emailFormatted(_ md: String) -> String {
        let title = meeting?.displayTitle ?? "Meeting"
        let plain = md.replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        return "Hi all,\n\nHere's a quick recap of \(title):\n\n\(plain)\n\nBest,"
    }

    var followUpButton: some View {
        Button {
            showFollowUp = true
        } label: {
            Label("Draft follow-up…", systemImage: "paperplane")
        }
        .buttonStyle(MSPrimaryButtonStyle())
        .sheet(isPresented: $showFollowUp) {
            if let m = meeting {
                NavigationStack {
                    FollowUpView(
                        meetingTitle: m.displayTitle,
                        summary: summary,
                        actionItems: (manager.actionItems.items(for: m.id))
                            .map(\.title),
                        recipients: attendeeEmails(for: m),
                        meetingID: m.id
                    )
                    .navigationTitle("Draft follow-up")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showFollowUp = false }
                        }
                    }
                }
                .frame(minWidth: 640, minHeight: 480)
            }
        }
    }

    /// Resolve attendees to emails for prefilling Mail. The old version compared
    /// the *raw* "Jane <jane@acme.com>" string against displayName and never
    /// parsed the email sitting right there — so invite-sourced meetings opened
    /// the follow-up with empty recipients. Now: linked person's email first,
    /// then the email parsed straight out of the attendee string (P1-1).
    private func attendeeEmails(for m: Meeting) -> [String] {
        m.attendees.compactMap { raw in
            if let p = PeopleStore.shared.resolvedPerson(forAttendee: raw),
               !p.primaryEmail.isEmpty {
                return p.primaryEmail
            }
            let id = PersonResolver.parse(raw)
            return id.hasEmail ? id.email : nil
        }
    }
}

/// 👍/👎 + "why" feedback on a summary; a thumbs-down reason steers the next
/// regeneration (P5-3).
@available(macOS 14.0, *)
struct SummaryFeedbackRow: View {
    let meetingID: String
    var onRegenerate: () -> Void

    @State private var up: Bool?
    @State private var showWhy = false
    @State private var why = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Was this summary useful?").font(.caption).foregroundStyle(.secondary)
                Button { rate(true) } label: {
                    Image(systemName: up == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .buttonStyle(.plain).foregroundStyle(up == true ? Color.green : .secondary)
                Button { rate(false) } label: {
                    Image(systemName: up == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .buttonStyle(.plain).foregroundStyle(up == false ? Color.orange : .secondary)
                Spacer()
            }
            if showWhy {
                TextField("What was wrong? (e.g. missed action items, too long)", text: $why)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Save & regenerate") {
                        SummaryFeedback.set(up: false, why: why, for: meetingID)
                        showWhy = false
                        onRegenerate()
                    }
                    .buttonStyle(MSPrimaryButtonStyle())
                    .disabled(why.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Just save") {
                        SummaryFeedback.set(up: false, why: why, for: meetingID)
                        showWhy = false
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                }
            }
        }
        .onAppear {
            let r = SummaryFeedback.rating(for: meetingID)
            if r.has { up = r.up; why = r.why ?? "" }
        }
    }

    private func rate(_ u: Bool) {
        up = u
        SummaryFeedback.set(up: u, why: u ? nil : (why.isEmpty ? nil : why), for: meetingID)
        showWhy = !u
    }
}

/// C1-12: "edit the summary by asking." Quick chips + a free-text instruction run
/// a targeted local-model rewrite of the recap, with one-step undo. Faithful by
/// prompt (no invented facts); gated by the caller on engine availability.
@available(macOS 14.0, *)
struct SummaryEditByAsking: View {
    let meeting: Meeting
    let current: String
    /// Push the rewritten (or restored) text up to the detail's `summary` state.
    var onChanged: (String) -> Void

    @EnvironmentObject var manager: MeetingManager
    @State private var instruction = ""
    @State private var isRunning = false
    @State private var beforeUndo: String?
    @State private var errorText: String?

    private static let presets: [(label: String, instruction: String)] = [
        ("Shorter", "Make it noticeably shorter — keep only the most important points."),
        ("More on decisions", "Expand the decisions: what was decided and why, in more detail."),
        ("Turn into an email", "Rewrite as a short email recap: a greeting, the recap, then next steps."),
        ("Plain language", "Rewrite in plainer language, fewer headings, no jargon.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .scaledFont(11, weight: .semibold).foregroundStyle(NDS.brand)
                Text("Edit by asking")
                    .scaledFont(11, weight: .bold, relativeTo: .caption2).tracking(0.6)
                    .foregroundStyle(NDS.textSecondary)
                if isRunning {
                    ProgressView().controlSize(.small).padding(.leading, 2)
                }
                Spacer()
                if beforeUndo != nil {
                    Button { undo() } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .scaledFont(11, weight: .medium)
                    }
                    .buttonStyle(.plain).foregroundStyle(NDS.brand)
                }
            }

            FlowLayout(spacing: 6) {
                ForEach(Self.presets, id: \.label) { preset in
                    Button { run(preset.instruction) } label: {
                        Text(preset.label)
                            .scaledFont(11, weight: .medium).foregroundStyle(NDS.textPrimary)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(NDS.fieldBg)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
            }

            HStack(spacing: 6) {
                TextField("Ask for a change…", text: $instruction)
                    .textFieldStyle(.plain).scaledFont(12)
                    .foregroundStyle(NDS.textPrimary)
                    .onSubmit { if !trimmed.isEmpty { run(trimmed) } }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(NDS.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: NDS.rowRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius, style: .continuous)
                        .strokeBorder(NDS.hairline, lineWidth: 1))
                Button { run(trimmed) } label: {
                    Image(systemName: "arrow.up.circle.fill").scaledFont(18)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.brand)
                .disabled(isRunning || trimmed.isEmpty)
            }

            if let err = errorText {
                Text(err).font(NDS.tiny).foregroundStyle(NDS.danger)
            }
        }
    }

    private var trimmed: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func run(_ ask: String) {
        guard !ask.isEmpty, !isRunning else { return }
        let snapshot = current
        isRunning = true
        errorText = nil
        Task {
            do {
                let rewritten = try await manager.rewriteSummary(
                    instruction: ask, current: snapshot, for: meeting)
                await MainActor.run {
                    beforeUndo = snapshot
                    instruction = ""
                    isRunning = false
                    onChanged(rewritten)
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    errorText = "Couldn't rewrite the summary. Is the summary engine running?"
                }
            }
        }
    }

    private func undo() {
        guard let original = beforeUndo else { return }
        manager.applyEditedSummary(original, for: meeting)
        onChanged(original)
        beforeUndo = nil
    }
}
