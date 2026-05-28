import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Calendar tab — every past + upcoming meeting in one place. Two view
/// modes:
///   • List: chronological list grouped by day (default).
///   • Month: a classic monthly grid with meeting dots; clicking a day
///     shows that day's meetings on the right.
///
/// Both modes hand off to the same inline-expand row used on Today, so
/// clicking a call opens the full detail in place.
@available(macOS 14.0, *)
struct CalendarTabView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var tagStore: TagStore

    @State private var mode: ViewMode = .month
    @State private var expandedID: String?
    @State private var monthCursor: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var search: String = ""
    @State private var sheetMeeting: Meeting?

    enum ViewMode: String, CaseIterable, Identifiable {
        case list, month
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String { self == .list ? "list.bullet" : "calendar" }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                switch mode {
                case .list:  listMode
                case .month: monthMode
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $sheetMeeting) { m in meetingSheet(m) }
        .onAppear {
            calendar.refreshUpcoming()
            manager.refreshPastMeetings()
        }
    }

    @ViewBuilder
    private func meetingSheet(_ m: Meeting) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(m.displayTitle).font(.headline).lineLimit(1)
                Spacer()
                Button("Done") { sheetMeeting = nil }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            UnifiedMeetingDetail(mode: cardVariant(for: m) == .upcoming ? .upcoming(m) : .past(m))
                .environmentObject(manager)
                .environmentObject(tagStore)
                .environmentObject(calendar)
        }
        .frame(width: 860, height: 680)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar").font(.system(size: 28, weight: .bold)).lineLimit(1)
                Text("\(allMeetings.count) meetings — past + upcoming")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .layoutPriority(0)
            Spacer(minLength: 12)
            Picker("", selection: $mode) {
                ForEach(ViewMode.allCases) { m in
                    Label(m.label, systemImage: m.systemImage).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, maxWidth: 200)
            Button {
                importMeeting()
            } label: { Label("Import", systemImage: "square.and.arrow.down") }
            .help("Import an audio file as a meeting — transcribed and summarized.")
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
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

    // MARK: - All meetings (past + upcoming, deduped by id)

    private var allMeetings: [Meeting] {
        var seen = Set<String>()
        var out: [Meeting] = []
        for m in calendar.upcoming + manager.pastMeetings {
            if seen.insert(m.id).inserted {
                out.append(m)
            }
        }
        out.sort { $0.startDate > $1.startDate }
        if !search.isEmpty {
            let q = search.lowercased()
            out = out.filter { m in
                m.displayTitle.lowercased().contains(q)
                    || m.attendees.contains(where: { $0.lowercased().contains(q) })
            }
        }
        return out
    }

    // MARK: - List mode

    private var listMode: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(groupedByDay, id: \.0) { day, items in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(dayHeader(day))
                                .font(.subheadline.weight(.semibold))
                            Text("\(items.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        ForEach(items) { m in
                            cardWithDetail(m)
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var groupedByDay: [(Date, [Meeting])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: allMeetings) { m in
            cal.startOfDay(for: m.startDate)
        }
        return grouped.keys.sorted(by: >).map { key in
            let sorted = (grouped[key] ?? []).sorted { $0.startDate < $1.startDate }
            return (key, sorted)
        }
    }

    // MARK: - Month mode

    private var monthMode: some View {
        VStack(spacing: 0) {
            weekStrip
            Divider().overlay(NDS.divider)
            ScrollView { monthGrid }
        }
    }

    // MARK: - Week kanban strip (calls per day for the selected week)

    private var weekStrip: some View {
        let days = weekDays(containing: selectedDay)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(weekTitle(days)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NDS.textSecondary)
                Spacer()
                Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(NDS.textSecondary)
                Button { selectedDay = Calendar.current.startOfDay(for: Date()); monthCursor = selectedDay } label: {
                    Text("This week").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.brand)
                Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).foregroundStyle(NDS.textSecondary)
            }
            .padding(.horizontal, 16).padding(.top, 12)

            HStack(alignment: .top, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    weekColumn(day)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
            .frame(height: 240)
        }
    }

    private func weekColumn(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let items = allMeetings
            .filter { cal.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
        let wf = DateFormatter(); wf.dateFormat = "EEE"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(wf.string(from: day).uppercased())
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(NDS.textTertiary)
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isToday ? .white : NDS.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(isToday ? NDS.brand : .clear, in: Circle())
                Spacer()
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(items) { m in weekChip(m) }
                    if items.isEmpty {
                        Text("—").font(.caption2).foregroundStyle(NDS.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isToday ? NDS.brand.opacity(0.06) : NDS.fieldBg,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(NDS.hairline, lineWidth: 1))
        .onTapGesture { selectedDay = cal.startOfDay(for: day) }
    }

    private func weekChip(_ m: Meeting) -> some View {
        let past = m.startDate < Date()
        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        let accent = m.conferenceURL != nil ? NDS.selectColor("blue") : NDS.selectColor("gray")
        return Button { sheetMeeting = m } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tf.string(from: m.startDate))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(accent)
                Text(m.displayTitle).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NDS.textPrimary).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(accent.opacity(0.25), lineWidth: 0.5))
            .opacity(past ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }

    private func weekDays(containing date: Date) -> [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }
    private func weekTitle(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
    private func shiftWeek(_ delta: Int) {
        let cal = Calendar.current
        if let d = cal.date(byAdding: .day, value: delta * 7, to: selectedDay) {
            selectedDay = cal.startOfDay(for: d)
            if !cal.isDate(d, equalTo: monthCursor, toGranularity: .month) { monthCursor = d }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let prev = Calendar.current.date(byAdding: .month, value: -1, to: monthCursor) {
                        monthCursor = prev
                    }
                } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle).font(.title3.weight(.semibold))
                Spacer()
                Button {
                    if let next = Calendar.current.date(byAdding: .month, value: 1, to: monthCursor) {
                        monthCursor = next
                    }
                } label: { Image(systemName: "chevron.right") }
                Button("Today") {
                    monthCursor = Calendar.current.startOfDay(for: Date())
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            weekdayRow
            grid
            Spacer(minLength: 0)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 6)
    }

    private var weekdaySymbols: [String] {
        let df = DateFormatter()
        return df.shortWeekdaySymbols ?? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: monthCursor)
    }

    private var grid: some View {
        let days = daysGrid(for: monthCursor)
        let cal = Calendar.current
        return VStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        if idx < days.count {
                            let day = days[idx]
                            dayCell(day, inMonth: cal.isDate(day, equalTo: monthCursor, toGranularity: .month))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private func daysGrid(for month: Date) -> [Date] {
        let cal = Calendar.current
        guard let monthRange = cal.range(of: .day, in: .month, for: month),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month)) else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leadDays = firstWeekday - 1
        guard let gridStart = cal.date(byAdding: .day, value: -leadDays, to: firstOfMonth) else {
            return []
        }
        // 6 rows × 7 cols = 42 cells.
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func dayCell(_ day: Date, inMonth: Bool) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let meetingsOnDay = allMeetings.filter { cal.isDate($0.startDate, inSameDayAs: day) }
        return Button {
            selectedDay = cal.startOfDay(for: day)
            if !cal.isDate(day, equalTo: monthCursor, toGranularity: .month) {
                monthCursor = day
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(inMonth ? (isToday ? Color.accentColor : .primary)
                                             : Color.secondary.opacity(0.5))
                if !meetingsOnDay.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(0..<min(meetingsOnDay.count, 3), id: \.self) { _ in
                            Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                        }
                        if meetingsOnDay.count > 3 {
                            Text("+").font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18)
                                     : (isToday ? Color.accentColor.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var dayDetail: some View {
        let cal = Calendar.current
        let meetingsOnDay = allMeetings
            .filter { cal.isDate($0.startDate, inSameDayAs: selectedDay) }
            .sorted { $0.startDate < $1.startDate }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(dayTitle).font(.headline)
                if meetingsOnDay.isEmpty {
                    Text("No meetings on this day.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else {
                    ForEach(meetingsOnDay) { m in
                        cardWithDetail(m)
                    }
                }
            }
            .padding(16)
        }
        .background(NDS.fieldBg)
    }

    private var dayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return "Today" }
        if cal.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        if cal.isDateInYesterday(selectedDay) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: selectedDay)
    }

    // MARK: - Row helpers (shared with Today view)

    @ViewBuilder
    private func cardWithDetail(_ meeting: Meeting) -> some View {
        let variant = cardVariant(for: meeting)
        let expanded = expandedID == meeting.id
        VStack(spacing: 0) {
            MeetingCard(meeting: meeting,
                        variant: variant,
                        isExpanded: expanded,
                        onOpen: { toggle(meeting) })
                .environmentObject(manager)
                .environmentObject(tagStore)
            if expanded {
                inlineDetail(meeting, variant: variant)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: expanded)
    }

    private func cardVariant(for m: Meeting) -> MeetingCard.Variant {
        if manager.activeMeeting?.id == m.id { return .live }
        return m.startDate < Date() ? .past : .upcoming
    }

    private func inlineDetail(_ meeting: Meeting, variant: MeetingCard.Variant) -> some View {
        let isLive = (variant == .live)
        let mode: UnifiedMeetingDetail.Mode = isLive
            ? .live
            : (variant == .upcoming ? .upcoming(meeting) : .past(meeting))
        return VStack(spacing: 0) {
            UnifiedMeetingDetail(mode: mode)
                .environmentObject(manager)
                .environmentObject(tagStore)
                .environmentObject(calendar)
            HStack {
                Spacer()
                Button {
                    toggle(meeting)
                } label: {
                    Label("Collapse", systemImage: "chevron.up").font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.vertical, 6).padding(.trailing, 10)
            }
        }
        .frame(minHeight: 520)
        .padding(.top, 8).padding(.horizontal, 4)
    }

    private func toggle(_ m: Meeting) {
        expandedID = (expandedID == m.id) ? nil : m.id
    }

    private func dayHeader(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: d)
    }
}
