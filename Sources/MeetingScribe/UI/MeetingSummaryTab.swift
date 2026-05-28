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
            placeholder(systemImage: "sparkles",
                        title: "No summary yet",
                        message: "Start a recording and stop it. Ollama will draft a summary from the transcript.")
        case .past:
            if summary.isEmpty {
                placeholder(systemImage: "sparkles",
                            title: "No summary",
                            message: "Summary not generated — likely Ollama wasn't running. Restart Ollama and re-record, or generate manually.")
            } else {
                // Read-only markdown renderer with the same styling as the
                // editor — true heading sizes, indented lists, monospaced code.
                MarkdownEditor(text: .constant(summary), isEditable: false)
            }
        }
    }
}
