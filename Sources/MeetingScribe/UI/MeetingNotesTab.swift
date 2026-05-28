import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    @ViewBuilder
var notesEditor: some View {
        if isRecurring && !priorOccurrences.isEmpty {
            HStack(spacing: 0) {
                previousCallsSidebar
                Divider().overlay(NDS.divider)
                notesMainArea
            }
        } else {
            currentNotesEditor
        }
    }

    /// The editable notes for the call currently being viewed.
var currentNotesEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Markdown notes — type `/` for blocks, `@` to link. Saved to notes.md.")
                .font(.caption).foregroundStyle(.secondary)
                .padding([.horizontal, .top])
            RichMarkdownEditor(text: $noteDraft,
                               placeholder: "Type / for blocks, @ to link a meeting…",
                               mentionProvider: { manager.workspaceEntities() })
                .padding(.horizontal, 8).padding(.bottom, 8)
            backlinksPanel
        }
    }

    /// Right pane of the recurring layout: either the current call's editor or
    /// a selected prior occurrence's notes (read-only). Each call's notes stay
    /// completely separate.
    @ViewBuilder
var notesMainArea: some View {
        if let pid = selectedOccurrenceID,
           let prior = priorOccurrences.first(where: { $0.id == pid }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(occurrenceLabel(prior)).font(.headline)
                    NotionChip("Read-only", color: NDS.selectColor("gray"))
                    Spacer()
                    Button {
                        selectedOccurrenceID = nil
                    } label: { Label("Back to this call", systemImage: "arrow.uturn.left").font(.caption) }
                    .buttonStyle(.borderless).controlSize(.small)
                }
                .padding([.horizontal, .top])
                let priorNotes = manager.userNotes(for: prior)
                if priorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    placeholder(systemImage: "note.text",
                                title: "No notes for this call",
                                message: "Nothing was written for \(occurrenceLabel(prior)).")
                } else {
                    MarkdownEditor(text: .constant(priorNotes), isEditable: false)
                        .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        } else {
            currentNotesEditor
        }
    }

    /// Quick-access list of this call + every prior occurrence in the series.
var previousCallsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CALLS IN THIS SERIES")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
            occurrenceRow(title: "This call",
                          subtitle: meeting.map { occurrenceLabel($0) } ?? "",
                          selected: selectedOccurrenceID == nil,
                          isCurrent: true) { selectedOccurrenceID = nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(priorOccurrences) { prior in
                        occurrenceRow(title: occurrenceLabel(prior),
                                      subtitle: hasNotes(prior) ? "Has notes" : "No notes",
                                      selected: selectedOccurrenceID == prior.id,
                                      isCurrent: false) { selectedOccurrenceID = prior.id }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 200)
        .background(NDS.sidebarBg)
    }

func occurrenceRow(title: String, subtitle: String, selected: Bool,
                               isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "pencil.circle.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

func hasNotes(_ m: Meeting) -> Bool {
        !manager.userNotes(for: m).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

func occurrenceLabel(_ m: Meeting) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: m.startDate)
    }

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
