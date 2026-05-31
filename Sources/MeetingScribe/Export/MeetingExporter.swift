import AppKit
import UniformTypeIdentifiers

/// Phase 4 — export a meeting (or any document) to Markdown or PDF.
///
/// PDF rendering reuses `MarkdownStyle` so the exported document looks like the
/// in-app editor (true heading sizes, indented lists, monospaced code). Both
/// paths prompt the user with an `NSSavePanel`.
@available(macOS 14.0, *)
enum MeetingExporter {

    /// What a share/export is allowed to include. Private notes default OFF so
    /// they can't leak to a recipient unless explicitly chosen. (U4-3)
    struct ShareSelection {
        var includeSummary = true
        var includeNotes = false
        var includeTranscript = true

        /// Safe default for non-interactive (agent-driven) exports: never the
        /// user's private notes.
        static let safeDefault = ShareSelection(includeSummary: true,
                                                includeNotes: false,
                                                includeTranscript: true)
    }

    /// Builds a single combined markdown document from a meeting's parts.
    /// Empty sections are skipped. The `include*` flags gate which sections
    /// are emitted so a share can omit private notes / the full transcript.
    static func combinedMarkdown(title: String,
                                 dateString: String,
                                 attendees: [String],
                                 summary: String,
                                 notes: String,
                                 transcript: String,
                                 includeSummary: Bool = true,
                                 includeNotes: Bool = true,
                                 includeTranscript: Bool = true) -> String {
        var out = "# \(title)\n\n_\(dateString)_\n"
        if !attendees.isEmpty {
            out += "\n**Attendees:** \(attendees.joined(separator: ", "))\n"
        }
        func section(_ heading: String, _ body: String) {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // Strip a leading duplicate H1 the source files sometimes carry.
            var b = trimmed
            for prefix in ["# Summary", "# Transcript"] where b.hasPrefix(prefix) {
                b = String(b.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            out += "\n---\n\n## \(heading)\n\n\(b)\n"
        }
        if includeSummary { section("Summary", summary) }
        if includeNotes { section("My Notes", notes) }
        if includeTranscript { section("Transcript", transcript) }
        return out
    }

    /// Convenience overload taking a `ShareSelection`.
    static func combinedMarkdown(title: String,
                                 dateString: String,
                                 attendees: [String],
                                 summary: String,
                                 notes: String,
                                 transcript: String,
                                 selection: ShareSelection) -> String {
        combinedMarkdown(title: title, dateString: dateString, attendees: attendees,
                         summary: summary, notes: notes, transcript: transcript,
                         includeSummary: selection.includeSummary,
                         includeNotes: selection.includeNotes,
                         includeTranscript: selection.includeTranscript)
    }

    /// Presents a "what's included" confirmation before any share/export so the
    /// user can't accidentally send private notes or the full transcript to a
    /// recipient. Private notes default OFF. Returns nil if cancelled. (U4-3)
    @MainActor
    static func confirmShareSelection(hasSummary: Bool,
                                      hasNotes: Bool,
                                      hasTranscript: Bool) -> ShareSelection? {
        let alert = NSAlert()
        alert.messageText = "What should this export include?"
        alert.informativeText = "Choose what leaves MeetingScribe. Your private notes are excluded by default."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Cancel")

        func checkbox(_ title: String, on: Bool, enabled: Bool) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            b.state = on ? .on : .off
            b.isEnabled = enabled
            return b
        }
        let summaryBox = checkbox("Summary", on: hasSummary, enabled: hasSummary)
        let notesBox = checkbox("My private notes", on: false, enabled: hasNotes)
        let transcriptBox = checkbox("Full transcript", on: hasTranscript, enabled: hasTranscript)

        let stack = NSStackView(views: [summaryBox, notesBox, transcriptBox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 78)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return ShareSelection(includeSummary: summaryBox.state == .on,
                              includeNotes: notesBox.state == .on,
                              includeTranscript: transcriptBox.state == .on)
    }

    /// Prompts for a destination and writes the markdown. Returns the URL on
    /// success.
    @discardableResult
    static func exportMarkdown(_ markdown: String, suggestedName: String) -> URL? {
        guard let url = savePanel(suggestedName: suggestedName, ext: "md") else { return nil }
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            presentError(error)
            return nil
        }
    }

    /// Prompts for a destination and renders the markdown to a paginated PDF.
    @discardableResult
    static func exportPDF(_ markdown: String, suggestedName: String) -> URL? {
        guard let url = savePanel(suggestedName: suggestedName, ext: "pdf") else { return nil }

        let pageWidth: CGFloat = 612   // US Letter @ 72dpi
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: pageHeight))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isRichText = true
        textView.backgroundColor = .white
        textView.string = markdown
        MarkdownStyle.applyStyling(to: textView)
        textView.sizeToFit()

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: pageWidth, height: pageHeight)
        printInfo.topMargin = margin; printInfo.bottomMargin = margin
        printInfo.leftMargin = margin; printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false
        let dict = printInfo.dictionary()
        dict[NSPrintInfo.AttributeKey.jobDisposition] = NSPrintInfo.JobDisposition.save
        dict[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { return nil }
        return url
    }

    // MARK: - Helpers

    private static func savePanel(suggestedName: String, ext: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitizeFilename(suggestedName) + "." + ext
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "MeetingScribe Export" : cleaned
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Export failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
