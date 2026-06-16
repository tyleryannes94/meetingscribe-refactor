import SwiftUI

/// A keyboard-first due-date editor (2-5): type "tod", "fri", "6/12", "+3d",
/// "next week" and see the parsed date confirmed below as a green chip; a
/// calendar button falls back to the graphical picker. Replaces the
/// click-only `DatePicker(.graphical)` popovers in task rows and the task page.
@available(macOS 14.0, *)
struct DateTypeAheadField: View {
    @Binding var date: Date?
    var onCommit: () -> Void = {}

    @State private var text = ""
    @State private var parsed: Date?
    @State private var showPicker = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock").font(.caption2).foregroundStyle(NDS.textTertiary)
                TextField("tod, fri, 6/12, +3d…", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onChange(of: text) { _, v in parsed = Self.parse(v) }
                    .onSubmit(commit)
                Button { showPicker = true } label: { Image(systemName: "calendar") }
                    .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
                    .popover(isPresented: $showPicker) {
                        DatePicker("", selection: Binding(get: { date ?? Date() },
                                                          set: { date = $0; onCommit() }),
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden().padding(10)
                    }
            }
            if let p = parsed {
                Button(action: commit) {
                    HStack(spacing: 4) {
                        Image(systemName: "return").font(.system(size: 9, weight: .bold)) // design-lint:allow
                        Text(Self.format(p))
                    }
                    .font(.caption2).foregroundStyle(NDS.selectColor("green"))
                }
                .buttonStyle(.plain)
            } else if let d = date {
                HStack(spacing: 6) {
                    Text(Self.format(d)).font(.caption2).foregroundStyle(NDS.textSecondary)
                    Button("Clear") { date = nil; onCommit() }
                        .font(.caption2).buttonStyle(.plain).foregroundStyle(NDS.selectColor("red"))
                }
            }
        }
        .frame(width: 210)
        .padding(10)
        .onAppear { focused = true }
    }

    private func commit() {
        if let p = parsed { date = p; onCommit() }
    }

    /// Parses a typed fragment into a date: the quick-add `due:` shorthands
    /// first ("tod"/"fri"/"+3d"/"next-week"), then NSDataDetector for the rest.
    static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        // Map a couple of common abbreviations the shorthand expects.
        let token = t.lowercased() == "tod" ? "today" : t
        if let d = TaskQuickAddParser.dueShorthand(token.replacingOccurrences(of: " ", with: "-"), now: Date()) {
            return d
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let ns = t as NSString
            if let m = detector.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
               let d = m.date { return d }
        }
        return nil
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: d)
    }
}
