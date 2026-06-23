import SwiftUI
import AppKit

// MARK: - Note timestamp helpers

struct NoteTimestamp {
    let seconds: TimeInterval
    let label: String
    let context: String
}

func parseNoteTimestamps(_ text: String) -> [NoteTimestamp] {
    var results: [NoteTimestamp] = []
    let pattern = #"\[(\d+):(\d{2})(?::(\d{2}))?\]([^\n]*)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    for match in regex.matches(in: text, range: range) {
        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: text), !r.isEmpty else { return nil }
            return String(text[r])
        }
        let a = Double(group(1) ?? "0") ?? 0
        let b = Double(group(2) ?? "0") ?? 0
        let c = Double(group(3) ?? "")
        let seconds: TimeInterval
        let label: String
        if let c = c {
            seconds = a * 3600 + b * 60 + c
            label = String(format: "%d:%02d:%02d", Int(a), Int(b), Int(c))
        } else {
            seconds = a * 60 + b
            label = String(format: "%d:%02d", Int(a), Int(b))
        }
        let ctx = group(4).map { String($0.trimmingCharacters(in: .whitespaces).prefix(50)) } ?? ""
        results.append(NoteTimestamp(seconds: seconds, label: label, context: ctx))
    }
    return results
}

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    /// Parse the notes editor for action-item-like lines (checkboxes / TODO:)
    /// and push them into Tasks, linked to this meeting (§3C). No-op lines and
    /// already-pushed duplicates are skipped by the store. Called from the
    /// canvas notes section's "Push to-dos → Tasks" inline button.
    func pushNoteTodosToTasks(_ m: Meeting) {
        let markers = ["- [ ]", "- [x]", "- [X]", "* [ ]", "[ ]", "todo:", "- todo"]
        let drafts: [ActionItemStore.TaskDraft] = noteDraft.components(separatedBy: .newlines).compactMap { raw in
            var t = raw.trimmingCharacters(in: .whitespaces)
            let lower = t.lowercased()
            guard markers.contains(where: { lower.hasPrefix($0) }) else { return nil }
            for prefix in ["- [ ]", "- [x]", "- [X]", "* [ ]", "[ ]", "TODO:", "Todo:", "todo:", "- TODO:", "- todo:"]
            where t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)); break
            }
            t = t.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : ActionItemStore.TaskDraft(title: t)
        }
        guard !drafts.isEmpty else {
            ToastCenter.shared.show("No to-do lines found — use “- [ ] …” or “TODO: …”")
            return
        }
        manager.pushToTasks(meeting: m, drafts: drafts)
    }

    /// Cross-entity backlinks ("Linked from") for the canvas's Related & linked
    /// section. Hidden when `backlinks` is empty; the parent section's
    /// visibility guard already handles that, so this view just renders rows.
    @ViewBuilder
    var backlinksPanel: some View {
        if !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("Linked from", systemImage: "link")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(backlinks) { e in
                    Button {
                        NotificationCenter.default.post(name: .meetingScribeOpenEntity,
                                                        object: nil,
                                                        userInfo: ["url": e.linkURL.absoluteString])
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: e.kind.systemImage).font(.caption2)
                            Text(e.title).font(.caption).lineLimit(1)
                            Text(e.subtitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NDS.fieldBg,
                        in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
    }
}
