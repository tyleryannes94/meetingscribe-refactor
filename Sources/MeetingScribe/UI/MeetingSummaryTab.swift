import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension UnifiedMeetingDetail {
    @ViewBuilder
    var summaryBody: some View {
        switch mode {
        case .live:
            placeholder(systemImage: "sparkles",
                        title: "Summary not generated yet",
                        message: "Stop the recording — the summary runs on the final transcript.")
        case .upcoming:
            // Pre-meeting brief is rendered in a separate view for .upcoming
            // (see upcomingBriefBody). The Summary tab shows a helpful
            // placeholder directing the user to start recording.
            placeholder(systemImage: "sparkles",
                        title: "No summary yet",
                        message: "Start a recording and stop it. Ollama will draft a summary from the transcript.")
        case .past:
            pastSummaryBody
        }
    }

    @ViewBuilder
    private var pastSummaryBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if summary.isEmpty {
                    emptySummaryView
                } else {
                    // Read-only markdown renderer — true heading sizes,
                    // indented lists, monospaced code. MarkdownEditor on
                    // macOS is significantly more performant than
                    // AttributedString for long documents.
                    MarkdownEditor(text: .constant(summary), isEditable: false)
                        .padding(.bottom, 8)

                    // Follow-up draft button — surfaces FollowUpView which
                    // was previously dead code. Lives at the bottom of the
                    // summary so it's the natural next action after reading.
                    if !summary.isEmpty {
                        followUpButton
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }

                    // Extracted action items from this meeting — inline
                    // so users don't have to navigate to the Tasks tab
                    // to see what was agreed. The same items are shown
                    // in the Tasks tab with full CRUD — these are read-
                    // only cards with a quick "mark done" affordance.
                    let items = meeting.map { manager.actionItems.items(for: $0.id) } ?? []
                    if !items.isEmpty {
                        actionItemsSection(items)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptySummaryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No summary")
                .font(.headline)
            Text("Ollama wasn't running when this meeting finished, or summarization failed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Regenerate button — visible when transcript exists but summary is empty.
            if !transcript.isEmpty {
                if let m = meeting {
                    let isRunning = manager.transcribingMeetingIDs.contains(m.id)
                    Button {
                        manager.pipelineController.transcribeNow(meeting: m,
                                                                  regenerateSummary: true)
                    } label: {
                        if isRunning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Generating…")
                            }
                        } else {
                            Label("Generate Summary", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var followUpButton: some View {
        Button {
            showFollowUp = true
        } label: {
            Label("Draft follow-up…", systemImage: "paperplane")
                .font(.callout)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .sheet(isPresented: $showFollowUp) {
            if let m = meeting {
                NavigationStack {
                    FollowUpView(
                        meetingTitle: m.displayTitle,
                        summary: summary,
                        actionItems: (manager.actionItems.items(for: m.id))
                            .map(\.title)
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

    @ViewBuilder
    private func actionItemsSection(_ items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.horizontal).padding(.vertical, 4)
            HStack {
                Image(systemName: "checklist")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NDS.brand)
                Text("Action Items")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(items.filter { $0.status != .completed }.count) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ForEach(items) { item in
                InlineActionItemRow(item: item, store: manager.actionItems)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Inline action item row

@available(macOS 14.0, *)
private struct InlineActionItemRow: View {
    let item: ActionItem
    @ObservedObject var store: ActionItemStore

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                store.setStatus(item.id,
                                status: item.status == .completed ? .open : .completed)
            } label: {
                Image(systemName: item.status == .completed
                    ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                    .lineLimit(2)
                if let owner = item.owner, !owner.isEmpty {
                    Text(owner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Priority dot
            Circle()
                .fill(priorityColor)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .high:   return .orange
        case .medium: return .yellow
        case .low:    return .secondary.opacity(0.4)
        }
    }
}
