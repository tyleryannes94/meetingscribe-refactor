import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

/// The home view. Single column on the left:
///   1. Header (date + quick actions).
///   2. Action items from today + yesterday (compact widget).
///   3. NOW — the active recording, if any.
///   4. TODAY — today's calls only (past + upcoming).
///   5. Quick link to the Calendar tab for past/future calls.
///
/// A narrow Chat sidebar lives on the right. Sidebar is intentionally
/// secondary — action items and meeting cards are the primary focus.
@available(macOS 14.0, *)
struct TodayView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var decisions: DecisionStore
    @EnvironmentObject var actionItems: ActionItemStore
    @State private var showStandup = false
    @State private var showDecisionLedger = false   // 4-D
    @ObservedObject private var streaks = StreakTracker.shared   // 5-D

    /// D5-1 "Today, calm by default": the long-tail sections collapse under one
    /// "More" disclosure so Today opens calm. Default-collapsed; remembered.
    @AppStorage("today.moreExpanded") private var moreExpanded = false
    /// 5-H: once dismissed, the new-user first-steps card stays gone.
    @AppStorage("today.firstStepsDismissed") private var firstStepsDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Navigation is owned by `WorkspaceRouter` (D1-1): meeting cards route to
    /// the canonical Meetings-tab detail, and the widgets flip sections through
    /// it. Today no longer keeps its own pushed meeting detail.
    @EnvironmentObject var router: WorkspaceRouter

    var body: some View {
        feed
            .background(NDS.bg)
            .onAppear {
                calendar.refreshUpcoming()
                manager.refreshPastMeetings()
                StreakTracker.shared.record(.dailyOpen)   // 5-D
            }
            .task {
                // Defer the one-shot backfills (action items, people, search index,
                // embeddings, decisions) off the first-paint frame so Today renders
                // immediately. They're single-shot-per-session + off-main internally,
                // so a short delay is harmless. (V5 TT-2)
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                manager.backfillActionItemsIfNeeded()
                manager.backfillPeopleIfNeeded()
                manager.backfillSearchIndexIfNeeded()
                manager.backfillEmbeddingsIfNeeded()
                manager.backfillDecisionsIfNeeded()
                PeopleStore.shared.refreshStaleStrengthScores()   // 1-F (ResourceGovernor-gated)
            }
    }

    // MARK: - Feed (left column)

    /// 5-H: dismissible onboarding card on the new-user blank state — three
    /// concrete first actions. Self-hides once the user has any meetings or
    /// once dismissed.
    @ViewBuilder
    private var firstStepsCard: some View {
        if !firstStepsDismissed && manager.pastMeetings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("First steps")
                        .scaledFont(15, weight: .semibold).foregroundStyle(NDS.textPrimary)
                    Spacer()
                    Button { firstStepsDismissed = true } label: {
                        Image(systemName: "xmark").scaledFont(11).foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain).help("Dismiss")
                }
                firstStepRow("Record your first meeting", "record.circle") { router.section = .meetings }
                firstStepRow("Add a person", "person.badge.plus") { router.section = .people }
                firstStepRow("Set a check-in cadence", "bell.badge") { router.section = .people }
            }
            .msCard(accentBorder: true)
        }
    }

    private func firstStepRow(_ title: String, _ icon: String,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).scaledFont(13).foregroundStyle(NDS.brand).frame(width: 18)
                Text(title).scaledFont(13).foregroundStyle(NDS.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").scaledFont(10).foregroundStyle(NDS.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 5-I: after 5pm, a wrap-up card closing the daily loop — how many of
    /// today's tasks are still open. Self-hides before 5pm.
    @ViewBuilder
    private var endOfDayCard: some View {
        if Calendar.current.component(.hour, from: Date()) >= 17 {
            let openToday = actionItems.items.filter {
                $0.status != .completed
                    && ($0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill").scaledFont(13).foregroundStyle(NDS.brand)
                    Text("End of day")
                        .scaledFont(15, weight: .semibold).foregroundStyle(NDS.textPrimary)
                }
                if openToday.isEmpty {
                    Text("Today's tasks are all wrapped up. Nice work.")
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                } else {
                    Text("\(openToday.count) task\(openToday.count == 1 ? "" : "s") still open for today.")
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    Button("Review tasks") { router.section = .actions }
                        .buttonStyle(.borderless).font(NDS.small)
                }
            }
            .msCard()
        }
    }

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                firstStepsCard   // 5-H: dismissible new-user onboarding
                MorningBriefCard(contextSummary: morningContextSummary)   // 5-C
                turnaroundCard  // U3-2: the back-to-back bridge (imminent only)
                dayShapeStrip   // U3-3: the 7am coffee scan, answered in 10s
                quickActions
                upNextCard

                // 1-G: time-sensitive follow-ups + decisions are surfaced here,
                // not buried under "More". Each self-hides when it has no items.
                followUpsSection
                decisionsSection

                oneOnOneDaySection   // U1-1: your 1:1s today, person-first

                if isRecording { liveSection }

                // Overdue + due-today work, surfaced above meetings (TDY-2).
                NeedsAttentionWidget(store: manager.actionItems) {
                    router.section = .actions
                }

                if !todayUpcoming.isEmpty || !todayPast.isEmpty {
                    todaySection
                } else if !isRecording {
                    emptyState
                }

                ActionItemsWidget(store: manager.actionItems) {
                    router.section = .actions
                }

                // Kanban board of all open tasks, with one-tap add (Notion/Trello
                // style) right on the home page.
                HomeTasksBoard(store: manager.actionItems)

                endOfDayCard   // 5-I: after-5pm wrap-up

                // D5-1: everything below the fold collapses under one "More"
                // disclosure so the home screen opens calm.
                moreSection
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            // Full window width (req #5) — the feed is cards/lists, not prose,
            // so no reading-measure cap. (Prose panes keep their own measure.)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - "More" shelf (D5-1)

    /// D5-1 "Today, calm by default": the long-tail sections (weekly ledger,
    /// follow-ups, commitments, decisions, on-this-day, recent notes, and people
    /// context) collapse under one disclosure so the home screen opens calm.
    /// Default-collapsed; remembers its open/closed state across launches.
    @ViewBuilder
    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button {
                withAnimation(NDS.motion(.easeInOut(duration: 0.2), reduce: reduceMotion)) {
                    moreExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(NDS.textSecondary)
                        .rotationEffect(.degrees(moreExpanded ? 90 : 0))
                    Text("More").scaledFont(13, weight: .semibold)
                        .foregroundStyle(NDS.textSecondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(moreExpanded ? "Hide the rest of your day" : "Show the rest of your day")
            .accessibilityLabel(moreExpanded ? "More, expanded" : "More, collapsed")
            .accessibilityHint("Weekly ledger, commitments, on this day, recent notes, and people")

            if moreExpanded {
                weeklyLedgerSection   // U3-6: "what did I commit to this week"

                // Owe / Owed commitments split by direction. (U3-2/P2-7)
                commitmentsSection

                // 5-J: delegation board — what you're waiting on others for.
                waitingOnSection

                // "On this day" — resurface meetings from prior weeks/months/
                // years on today's date. (C2-9/C2-6)
                onThisDaySection

                // Recent voice notes — the one surface Today never referenced. (TT-6)
                recentNotesSection

                // People suggestions below meetings — they're context, not actions
                SuggestedPeopleView()

                // D4-4: StayConnectedSection (health-scored) is the single
                // people-nudge module we keep; the near-duplicate ReconnectView
                // call was dropped from the layout to remove the redundancy.
                StayConnectedSection { p in openPerson(p) }
            }
        }
    }

    // MARK: - Turnaround card (U3-2)

    /// The back-to-back bridge: shown only when the next meeting is ≤15 min away,
    /// so the 30 seconds between calls answer "what's next, who, one number".
    @ViewBuilder
    private var turnaroundCard: some View {
        if let m = nextMeeting {
            let mins = Int(m.startDate.timeIntervalSince(Date()) / 60)
            if mins >= 0 && mins <= 15 {
                let people = PeopleStore.shared.people
                let person = m.attendees.compactMap { PersonResolver.resolve($0, in: people) }
                    .first.flatMap { id in people.first { $0.id == id } }
                let loops = person.map { p in
                    manager.actionItems.items.filter { $0.ownerPersonID == p.id && $0.status != .completed }.count
                } ?? 0
                Button { router.openMeeting(m) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mins == 0 ? "Starting now" : "Up next in \(mins) min")
                                .scaledFont(12, weight: .bold).foregroundStyle(NDS.gold)
                            Text(m.displayTitle).scaledFont(15, weight: .semibold)
                                .foregroundStyle(NDS.textPrimary).lineLimit(1).help(m.displayTitle)
                            Text(turnaroundSubtitle(meeting: m, person: person, loops: loops))
                                .scaledFont(11.5).foregroundStyle(NDS.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        if m.conferenceURL != nil {
                            Label("Join", systemImage: "video.fill").scaledFont(12, weight: .semibold)
                                .foregroundStyle(NDS.brand)
                        }
                    }
                    .padding(14)
                    .background(NDS.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: NDS.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius).strokeBorder(NDS.gold.opacity(0.3), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func turnaroundSubtitle(meeting m: Meeting, person: Person?, loops: Int) -> String {
        var parts: [String] = []
        if let p = person { parts.append("with \(p.displayName.split(separator: " ").first.map(String.init) ?? p.displayName)") }
        else if !m.attendees.isEmpty { parts.append("\(m.attendees.count) attendee\(m.attendees.count == 1 ? "" : "s")") }
        if loops > 0 { parts.append("\(loops) open loop\(loops == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Your 1:1 Day (U1-1)

    /// Today's 1:1s — calendar meetings today that resolve to exactly one known
    /// person. Manager morning prep, person-first.
    private var todaysOneOnOnes: [(meeting: Meeting, person: Person)] {
        let cal = Calendar.current
        let now = Date()
        let people = PeopleStore.shared.people
        return calendar.upcoming
            .filter { cal.isDate($0.startDate, inSameDayAs: now) && $0.endDate > now.addingTimeInterval(-300) }
            .sorted { $0.startDate < $1.startDate }
            .compactMap { m in
                let ids = m.attendees.compactMap { PersonResolver.resolve($0, in: people) }
                guard Set(ids).count == 1, let p = people.first(where: { $0.id == ids[0] }) else { return nil }
                return (m, p)
            }
    }

    @ViewBuilder
    private var oneOnOneDaySection: some View {
        let items = todaysOneOnOnes
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Your 1:1s today")
                ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                    Button { router.openMeeting(pair.meeting) } label: {
                        HStack(spacing: 10) {
                            MSAvatar(name: pair.person.displayName, size: 30,
                                     ringColor: healthRingColor(for: pair.person, in: PeopleStore.shared))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.person.displayName)
                                    .scaledFont(13.5, weight: .semibold).foregroundStyle(NDS.textPrimary)
                                Text(oneOnOneSubtitle(pair))
                                    .scaledFont(11.5).foregroundStyle(NDS.textSecondary)
                            }
                            Spacer()
                            Text(pair.meeting.startDate.formatted(date: .omitted, time: .shortened))
                                .scaledFont(12, weight: .medium).foregroundStyle(NDS.textSecondary)
                            Image(systemName: "chevron.right").scaledFont(11).foregroundStyle(NDS.textTertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func oneOnOneSubtitle(_ pair: (meeting: Meeting, person: Person)) -> String {
        var parts: [String] = []
        if let last = pair.person.lastInteractionAt {
            let d = Int(Date().timeIntervalSince(last) / 86400)
            parts.append(d <= 0 ? "last met today" : "last met \(d)d ago")
        }
        let loops = manager.actionItems.items.filter {
            $0.ownerPersonID == pair.person.id && $0.status != .completed
        }.count
        if loops > 0 { parts.append("\(loops) open loop\(loops == 1 ? "" : "s")") }
        return parts.isEmpty ? "First recorded meeting" : parts.joined(separator: " · ")
    }

    // MARK: - Weekly ledger (U3-6)

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }
    private var weekCompleted: [ActionItem] {
        manager.actionItems.items.filter {
            $0.status == .completed && ($0.completedAt.map { $0 >= weekStart } ?? false)
        }
    }
    private var weekOpenCommitments: [ActionItem] {
        manager.actionItems.items.filter { $0.status != .completed && $0.delegated != true }
    }

    @ViewBuilder
    private var weeklyLedgerSection: some View {
        let done = weekCompleted
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionLabel("This week")
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(weeklyUpdateText(), forType: .string)
                        ToastCenter.shared.show("Weekly update copied")
                    } label: { Label("Copy as update", systemImage: "doc.on.doc").font(NDS.small) }
                    .buttonStyle(.borderless)
                }
                Text("\(done.count) completed").font(NDS.small).foregroundStyle(NDS.textSecondary)
                ForEach(done.prefix(8)) { t in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").scaledFont(12).foregroundStyle(NDS.mint)
                        Text(t.title).font(NDS.body).foregroundStyle(NDS.textSecondary).lineLimit(1)
                        Spacer()
                    }
                }
                if done.count > 8 {
                    Text("+ \(done.count - 8) more").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
            }
            .padding(14)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
        }
    }

    private func weeklyUpdateText() -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        var out = "Weekly update — week of \(f.string(from: weekStart))\n\nDone this week:\n"
        out += weekCompleted.map { "✓ \($0.title)" }.joined(separator: "\n")
        let open = weekOpenCommitments.prefix(10)
        if !open.isEmpty {
            out += "\n\nOpen:\n" + open.map { "• \($0.title)" }.joined(separator: "\n")
        }
        return out
    }

    // MARK: - Follow-ups to send (P2-6/U3-3)

    @State private var followUpRefresh = 0   // bump to re-evaluate after marking sent

    private var pendingFollowUps: [Meeting] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        _ = followUpRefresh   // dependency so marking sent refreshes the list
        return manager.pastMeetings
            .filter { $0.startDate >= cutoff && !cal.isDateInToday($0.startDate) }
            .filter { !FollowUpStatus.isSent($0.id) }
            .sorted { $0.startDate > $1.startDate }
    }

    @ViewBuilder
    private var followUpsSection: some View {
        let items = pendingFollowUps
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane").foregroundStyle(NDS.brand)
                    Text("Follow-ups to send").scaledFont(15, weight: .semibold)
                }
                ForEach(items.prefix(4)) { m in
                    HStack(spacing: 8) {
                        Button { router.openMeeting(m) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayTitle).scaledFont(13, weight: .medium)
                                    .foregroundStyle(NDS.textPrimary).lineLimit(1)
                                Text(m.startDate, style: .date).scaledFont(11)
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("Mark sent") {
                            FollowUpStatus.setSent(m.id, true)
                            followUpRefresh += 1
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Commitments / Owe-Owed (U3-2/P2-7)

    private func isMine(_ owner: String) -> Bool {
        let o = owner.lowercased().trimmingCharacters(in: .whitespaces)
        if o == "me" || o == "i" { return true }
        let name = AppSettings.shared.userName.lowercased()
        if !name.isEmpty && o.contains(name) { return true }
        return AppSettings.shared.userNameAliases.contains { !$0.isEmpty && o.contains($0.lowercased()) }
    }

    @ViewBuilder
    private var commitmentsSection: some View {
        let open = actionItems.items.filter { $0.status != .completed && !($0.owner ?? "").isEmpty }
        let iOwe = open.filter { isMine($0.owner ?? "") }
        let owed = open.filter { !isMine($0.owner ?? "") }
        if !iOwe.isEmpty || !owed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(NDS.brand)
                    Text("Commitments").scaledFont(15, weight: .semibold)
                }
                commitmentColumn("You owe", items: iOwe)
                commitmentColumn("Owed to you", items: owed)
            }
        }
    }

    @ViewBuilder
    private func commitmentColumn(_ title: String, items: [ActionItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) (\(items.count))")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(items.prefix(3)) { item in
                    Button {
                        if let m = manager.meeting(forEntityID: item.meetingID) { router.openMeeting(m) }
                        else { router.section = .actions }
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.title).scaledFont(12)
                                .foregroundStyle(NDS.textPrimary).lineLimit(1)
                            Spacer()
                            if let owner = item.owner, !owner.isEmpty {
                                Text(owner).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Decision ledger (P1-1)

    @ViewBuilder
    private var decisionsSection: some View {
        let items = decisions.decisions
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal").foregroundStyle(NDS.brand)
                    Text("Recent decisions").scaledFont(15, weight: .semibold)
                    Spacer()
                    Button("View all") { showDecisionLedger = true }   // 4-D
                        .scaledFont(12).buttonStyle(.plain).foregroundStyle(NDS.brand)
                }
                ForEach(items.prefix(5)) { d in
                    Button {
                        if let m = manager.meeting(forEntityID: d.meetingID) { router.openMeeting(m) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill").scaledFont(5)
                                .foregroundStyle(NDS.brand).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.text)
                                    .scaledFont(13)
                                    .foregroundStyle(NDS.textPrimary)
                                    .multilineTextAlignment(.leading)
                                // 4-A: surface the rationale (the WHY) inline.
                                if let r = d.rationale, !r.isEmpty {
                                    Text(r).scaledFont(11)
                                        .foregroundStyle(NDS.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Text("\(d.meetingTitle) · \(d.date.formatted(date: .abbreviated, time: .omitted))")
                                    .scaledFont(11)
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - On this day (C2-9/C2-6)

    /// Past meetings that fall on today's calendar date in a prior year (true
    /// anniversaries), or on a round "ago" milestone (~1 week / 1 month /
    /// 1 quarter / 1 year ago, ±1 day). Newest first.
    private var onThisDay: [Meeting] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.dateComponents([.month, .day], from: now)
        let startToday = cal.startOfDay(for: now)
        return manager.pastMeetings.filter { m in
            guard !cal.isDateInToday(m.startDate) else { return false }
            let c = cal.dateComponents([.month, .day], from: m.startDate)
            if c.month == today.month && c.day == today.day { return true }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: m.startDate),
                                          to: startToday).day ?? 0
            return [7, 30, 90, 365].contains { abs(days - $0) <= 1 }
        }
        .sorted { $0.startDate > $1.startDate }
    }

    @ViewBuilder
    private var onThisDaySection: some View {
        let items = onThisDay
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(NDS.brand)
                    Text("On this day").scaledFont(15, weight: .semibold)
                }
                ForEach(items.prefix(4)) { m in
                    Button { router.openMeeting(m) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayTitle)
                                    .scaledFont(13, weight: .medium)
                                    .foregroundStyle(NDS.textPrimary)
                                Text(agoString(m.startDate))
                                    .scaledFont(11)
                                    .foregroundStyle(NDS.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(10, weight: .semibold)
                                .foregroundStyle(NDS.textTertiary)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Human "N days/weeks/months/years ago" label.
    private func agoString(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        switch days {
        case 365...:  return "\(days / 365) year\(days / 365 == 1 ? "" : "s") ago"
        case 28...:   return "\(days / 30) month\(days / 30 == 1 ? "" : "s") ago"
        case 7...:    return "\(days / 7) week\(days / 7 == 1 ? "" : "s") ago"
        default:      return "\(days) days ago"
        }
    }

    // MARK: - Recent notes (TT-6)

    private var recentNotes: [QuickNote] {
        manager.quickNotes.sorted { $0.createdAt > $1.createdAt }.prefix(3).map { $0 }
    }

    @ViewBuilder
    private var recentNotesSection: some View {
        let notes = recentNotes
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Recent notes", systemImage: "waveform")
                        .font(NDS.sectionLabel).foregroundStyle(NDS.textSecondary)
                    Spacer()
                    Button("All") { router.select(.notes) }
                        .font(NDS.small).buttonStyle(.borderless)
                }
                ForEach(notes) { n in
                    Button { router.select(.notes) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform").foregroundStyle(NDS.brand.opacity(0.7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.title).scaledFont(13.5, weight: .medium).lineLimit(1)
                                if !n.snippet.isEmpty {
                                    Text(n.snippet).font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Sections

    /// 5-C: compact facts the morning brief synthesizes. Empty ⇒ card hides.
    private var morningContextSummary: String {
        let cal = Calendar.current
        let todays = manager.pastMeetings.filter { cal.isDateInToday($0.startDate) }
            + calendar.upcoming.filter { cal.isDateInToday($0.startDate) }
        let overdueFollowUps = actionItems.items.filter {
            $0.status != .completed && ($0.dueDate.map { $0 < Date() } ?? false)
        }.count
        let checkIns = PeopleStore.shared.overdueCheckInCount
        guard !todays.isEmpty || overdueFollowUps > 0 || checkIns > 0 else { return "" }
        var parts: [String] = []
        if !todays.isEmpty {
            let names = todays.prefix(4).map(\.displayTitle).joined(separator: ", ")
            parts.append("Meetings today (\(todays.count)): \(names).")
        }
        if overdueFollowUps > 0 { parts.append("\(overdueFollowUps) follow-up(s) overdue.") }
        if checkIns > 0 { parts.append("\(checkIns) relationship check-in(s) overdue.") }
        return parts.joined(separator: " ")
    }

    /// 5-J: first-class delegation board — tasks you're waiting on others for.
    @ViewBuilder
    private var waitingOnSection: some View {
        let waiting = actionItems.items.filter { $0.delegated == true && $0.status != .completed }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass").foregroundStyle(NDS.gold)
                    Text("Waiting on").scaledFont(15, weight: .semibold)
                }
                ForEach(waiting.prefix(8)) { t in
                    let who = t.ownerPersonID.flatMap { PeopleStore.shared.person(by: $0)?.displayName } ?? t.owner
                    let days = Int(Date().timeIntervalSince(t.createdAt) / 86400)
                    HStack(spacing: 8) {
                        Button {
                            router.route(kind: .actionItem, id: t.id, manager: manager)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).scaledFont(13, weight: .medium)
                                    .foregroundStyle(NDS.textPrimary).lineLimit(1)
                                HStack(spacing: 6) {
                                    if let who, !who.isEmpty {
                                        Text(who).scaledFont(11).foregroundStyle(NDS.brand)
                                    }
                                    Text("\(days)d").scaledFont(11).foregroundStyle(NDS.textTertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("Nudge") {
                            let content = UNMutableNotificationContent()
                            content.title = "Follow up" + (who.map { ": \($0)" } ?? "")
                            content.body = t.title
                            content.sound = .default
                            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 86_400, repeats: false)
                            UNUserNotificationCenter.current().add(
                                UNNotificationRequest(identifier: "nudge-\(t.id)", content: content, trigger: trigger))
                            ToastCenter.shared.show("Nudge set — reminder in 2 days")
                        }
                        .controlSize(.small)
                        .help("Remind me to follow up in 2 days")
                        Button("Resolve") { actionItems.setStatus(t.id, status: .completed) }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayLong())
                    .scaledFont(30, weight: .heavy, relativeTo: .largeTitle, kind: .display)
                    .tracking(-0.8)
                    .foregroundStyle(.primary)
                HStack(spacing: 10) {
                    Text(subtitleString())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    // 5-K: privacy positioning — everything stays on-device.
                    Label("100% Local", systemImage: "lock.fill")
                        .scaledFont(10, weight: .semibold)
                        .foregroundStyle(NDS.textTertiary)
                        .help("Recordings, transcripts, and AI all run on your Mac — nothing is uploaded.")
                    // 5-D: compounding-value streak.
                    if streaks.currentStreak > 0 {
                        Label("\(streaks.currentStreak) day streak", systemImage: "flame.fill")
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(NDS.gold)
                            .help("Consecutive days you opened MeetingScribe and captured something.")
                    }
                }
            }
            Spacer()
            Button { showStandup = true } label: {
                Label("Standup", systemImage: "list.bullet.rectangle")
            }
            .help("Generate a daily standup: yesterday, today, open commitments")
        }
        .sheet(isPresented: $showStandup) {
            StandupDigestSheet(
                markdown: StandupDigest.markdown(manager: manager, calendar: calendar),
                isPresented: $showStandup)
        }
        .sheet(isPresented: $showDecisionLedger) {
            DecisionLedgerView(asSheet: true)   // 4-D
                .environmentObject(decisions)
                .environmentObject(PeopleStore.shared)
                .environmentObject(manager)
                .environmentObject(router)
        }
    }

    // MARK: - Quick actions

    /// Direction A — a tight, wrapping pill row instead of the old adaptive
    /// 5-card grid (which collapsed to a single-column wall at narrow widths).
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Primary action — full-width filled button (most common intent)
            if isRecording {
                Button {
                    Task { await manager.stopRecording() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill").scaledFont(16)
                        Text("Stop recording")
                            .scaledFont(14, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(MSDangerButtonStyle())
            } else {
                Button {
                    Task { await manager.startRecording(for: nil) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill").scaledFont(16)
                        Text("Record Meeting")
                            .scaledFont(14, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }

            // Secondary actions — compact pills
            FlowLayout(spacing: 8) {
                QuickPill(title: "Voice note", systemImage: "mic.fill",
                          tint: NDS.gold) {
                    Task { await manager.startQuickNote() }
                }
                QuickPill(title: "New task", systemImage: "checklist",
                          tint: NDS.mint) {
                    manager.actionItems.createTask(title: "New task")
                    router.section = .actions
                }
                QuickPill(title: "New page", systemImage: "doc.badge.plus",
                          tint: NDS.lilac) {
                    _ = manager.actionItems.createProject(name: "Untitled")
                    router.section = .actions
                }
            }
        }
    }

    /// "Up next" hero — the soonest upcoming meeting as a prominent glance with
    /// a one-tap Join & Record (req #3: make Today a better central hub).
    @ViewBuilder
    private var upNextCard: some View {
        if !isRecording, let m = nextMeeting {
            MSTintedHeaderCard(label: m.isJoinableWindow ? "Happening now" : "Up next") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.displayTitle)
                            .scaledFont(16, weight: .bold, relativeTo: .headline, kind: .display)
                            .foregroundStyle(NDS.textPrimary).lineLimit(1)
                        Text(relativeStart(m))
                            .scaledFont(12).foregroundStyle(NDS.textSecondary)
                    }
                    Spacer()
                    if m.conferenceURL != nil {
                        Button { Task { await manager.switchToRecording(m) } } label: {
                            Label("Join & record", systemImage: "video.fill")
                        }
                        .buttonStyle(MSPrimaryButtonStyle())
                    }
                    Button { router.openMeeting(m) } label: {
                        Label("Open", systemImage: "chevron.right")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                }
            }
        }
    }

    /// The meeting to surface in the "Up next" hero. A call you can still join
    /// and record right now — currently live, or ended within the last 45 min —
    /// takes priority over the next future event, so the one-tap Join & Record
    /// never disappears the moment a call starts (or runs long). Falls back to
    /// the soonest future meeting otherwise.
    private var nextMeeting: Meeting? {
        let joinable = calendar.upcoming
            .filter { $0.isJoinableWindow }
            .sorted { $0.startDate < $1.startDate }
        if let live = joinable.first(where: { $0.conferenceURL != nil }) ?? joinable.first {
            return live
        }
        let future = calendar.upcoming
            .filter { $0.startDate > Date() }
            .sorted { $0.startDate < $1.startDate }
        return future.first { $0.conferenceURL != nil } ?? future.first
    }

    /// "Day shape" strip (U3-3): the whole day in one glanceable line —
    /// meetings remaining, overdue tasks, and when the next call is.
    @ViewBuilder
    private var dayShapeStrip: some View {
        let meetingsLeft = todayUpcoming.count
        let overdue = manager.actionItems.overdueTasks.count
        HStack(spacing: 14) {
            dayShapeItem(icon: "calendar",
                         value: "\(meetingsLeft)",
                         label: meetingsLeft == 1 ? "meeting left" : "meetings left",
                         color: NDS.brand)
            if overdue > 0 {
                dayShapeItem(icon: "exclamationmark.circle.fill",
                             value: "\(overdue)", label: "overdue", color: NDS.danger)
            }
            if let m = nextMeeting {
                let f = DateFormatter(); let _ = (f.dateFormat = "h:mm a")
                dayShapeItem(icon: "clock", value: f.string(from: m.startDate),
                             label: "next", color: NDS.gold)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
    }

    private func dayShapeItem(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).scaledFont(13).foregroundStyle(color)
            Text(value).scaledFont(15, weight: .bold).foregroundStyle(NDS.textPrimary)
            Text(label).scaledFont(12).foregroundStyle(NDS.textSecondary)
        }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Recording now")
            if let m = manager.activeMeeting {
                meetingCard(m, variant: .live)
            } else {
                MeetingCard(meeting: adhocPlaceholder(), variant: .live, onOpen: {})
                    .environmentObject(manager)
                    .environmentObject(tagStore)
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Today")
            ForEach(todayUpcoming) { m in
                meetingCard(m, variant: .upcoming)
            }
            ForEach(todayPast) { m in
                meetingCard(m, variant: .past)
            }
        }
    }

    private var calendarLink: some View {
        Button {
            router.section = .meetings  // Calendar absorbed into Meetings tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(NDS.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All past + upcoming calls")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NDS.textPrimary)
                    Text("Open the Calendar tab for the full list + month view")
                        .font(.caption).foregroundStyle(NDS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NDS.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NDS.fieldBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NDS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// A tappable meeting card. Clicking it pushes the full meeting detail onto
    /// the navigation stack (with a back arrow) instead of expanding inline.
    private func meetingCard(_ meeting: Meeting, variant: MeetingCard.Variant) -> some View {
        MeetingCard(meeting: meeting,
                    variant: variant,
                    onOpen: { router.openMeeting(meeting) })
            .environmentObject(manager)
            .environmentObject(tagStore)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .scaledFont(36).foregroundStyle(.secondary)
            Text("Nothing on today's calendar").font(.headline)
            Text("Use a quick action above, or import an existing recording.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                importMeeting()
            } label: { Label("Import meeting recording", systemImage: "square.and.arrow.down") }
            .buttonStyle(UntitledSecondaryButtonStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private func importMeeting() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a meeting audio file to import, transcribe, and summarize"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await manager.importMeeting(from: url) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    // MARK: - Data

    private var isRecording: Bool {
        if case .recording = manager.state { return true }
        return false
    }

    private var todayUpcoming: [Meeting] {
        let cal = Calendar.current
        return calendar.upcoming
            .filter { cal.isDateInToday($0.startDate) && $0.startDate > Date().addingTimeInterval(-60) }
            .sorted { $0.startDate < $1.startDate }
    }

    private var todayPast: [Meeting] {
        let cal = Calendar.current
        return manager.pastMeetings
            .filter { cal.isDateInToday($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    private func relativeStart(_ m: Meeting) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Starts " + f.localizedString(for: m.startDate, relativeTo: Date())
    }

    private func todayLong() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private func subtitleString() -> String {
        let parts = [
            todayUpcoming.count > 0 ? "\(todayUpcoming.count) upcoming today" : nil,
            todayPast.count > 0 ? "\(todayPast.count) earlier today" : nil
        ].compactMap { $0 }
        if parts.isEmpty {
            return "Nothing on the calendar today"
        }
        return parts.joined(separator: " · ")
    }

    /// Jump to the People tab and open a specific person (used by the "Stay in
    /// touch" nudges). Deterministic via the router (D1-3) — no asyncAfter race
    /// against the People tab mounting.
    private func openPerson(_ p: Person) {
        router.openPerson(p.id)
    }

    private func adhocPlaceholder() -> Meeting {
        Meeting(id: UUID().uuidString,
                title: "Quick recording",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                attendees: [], notes: nil, location: nil,
                conferenceURL: nil, calendarName: nil, seriesID: nil,
                userDescription: nil, userTitle: nil,
                isImpromptu: true, segmentCount: 0)
    }
}

// MARK: - Pill button used in the header

@available(macOS 14.0, *)
struct ToolbarPillButton: View {
    enum Prominence { case primary, secondary }
    let label: String
    let systemImage: String
    let prominence: Prominence
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.callout.weight(.semibold))
                Text(label).font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 0.5))
            .foregroundStyle(foreground)
            .shadow(color: shadow, radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.15, dampingFraction: 0.85), value: hovering)
        .onHover { hovering = $0 }
    }

    private var background: AnyShapeStyle {
        switch prominence {
        case .primary:   return AnyShapeStyle(NDS.accentGradient)
        case .secondary: return AnyShapeStyle(NDS.fieldBg)
        }
    }
    private var foreground: Color {
        prominence == .primary ? NDS.onAccent : .primary
    }
    private var borderColor: Color {
        prominence == .primary ? .clear : NDS.hairline
    }
    private var shadow: Color {
        prominence == .primary ? NDS.accent.opacity(0.32) : .clear
    }
}
