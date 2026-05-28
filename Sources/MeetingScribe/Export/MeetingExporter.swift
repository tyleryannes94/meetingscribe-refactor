import AppKit
import UniformTypeIdentifiers

/// Phase 4 — export a meeting (or any document) to Markdown or PDF.
///
/// PDF rendering reuses `MarkdownStyle` so the exported document looks like the
/// in-app editor (true heading sizes, indented lists, monospaced code). Both
/// paths prompt the user with an `NSSavePanel`.
@available(macOS 14.0, *)
enum MeetingExporter {

    /// Builds a single combined markdown document from a meeting's parts.
    /// Empty sections are skipped.
    static func combinedMarkdown(title: String,
                                 dateString: String,
                                 attendees: [String],
                                 summary: String,
                                 notes: String,
                                 transcript: String) -> String {
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
        section("Summary", summary)
        section("My Notes", notes)
        section("Transcript", transcript)
        return out
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
