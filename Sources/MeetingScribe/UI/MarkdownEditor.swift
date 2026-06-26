import SwiftUI
import AppKit

/// Notion-style "live preview" markdown editor.
///
/// The underlying text is plain markdown (so notes.md / summary.md stay
/// portable), but it's RENDERED in-place with real heading sizes, indented
/// lists, monospaced inline code, etc. Type `# `, `## `, `- `, `1. ` and the
/// line restyles instantly. Markdown sigils (#, *, -, `) are dimmed rather
/// than hidden so the file content is always visible.
@available(macOS 14.0, *)
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var placeholder: String? = nil
    /// Optional controller that a formatting toolbar can use to apply
    /// markdown to the current selection (see RichMarkdownEditor).
    var controller: MarkdownEditorController? = nil
    /// When true, typing "/" at the start of a line pops the block menu.
    var enableSlashMenu: Bool = false
    /// When true, typing "@" pops the workspace @-mention picker.
    var enableMentions: Bool = false
    /// Supplies the list of @-mentionable entities (set by the host view).
    var mentionProvider: (() -> [WorkspaceEntity])? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = MarkdownNSTextView()
        // Proper sizing inside NSScrollView — without these the text view
        // ends up with a zero/fixed frame and clicks/typing fail mysteriously.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
        }

        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.font = MarkdownStyle.bodyFont
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = MarkdownStyle.caretColor
        textView.string = text
        textView.delegate = context.coordinator
        textView.placeholderString = placeholder ?? ""
        textView.isEditable = isEditable
        textView.isSelectable = true

        scroll.documentView = textView
        scroll.contentInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        controller?.textView = textView
        controller?.mentionProvider = mentionProvider
        MarkdownStyle.applyStyling(to: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? MarkdownNSTextView else { return }
        controller?.textView = textView
        controller?.mentionProvider = mentionProvider
        context.coordinator.controller = controller
        context.coordinator.enableSlashMenu = enableSlashMenu
        context.coordinator.enableMentions = enableMentions
        // Reentry guard: if we just pushed the user's typing into the binding,
        // SwiftUI re-renders and lands here with text == textView.string. We
        // must not overwrite the textView (would lose cursor position and
        // any new keystrokes that happened in the meantime).
        if !context.coordinator.isApplyingFromBinding && textView.string != text {
            context.coordinator.isApplyingFromBinding = true
            let selected = textView.selectedRanges
            textView.string = text
            MarkdownStyle.applyStyling(to: textView)
            textView.selectedRanges = selected
            context.coordinator.isApplyingFromBinding = false
        }
        textView.isEditable = isEditable
        textView.placeholderString = placeholder ?? ""
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(text: $text)
        c.controller = controller
        c.enableSlashMenu = enableSlashMenu
        c.enableMentions = enableMentions
        return c
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isApplyingFromBinding: Bool = false
        weak var controller: MarkdownEditorController?
        var enableSlashMenu: Bool = false
        var enableMentions: Bool = false
        /// Set while a "/" or "@" menu is being presented so the programmatic
        /// insertion that follows doesn't re-trigger the detector.
        private var suppressTriggerDetection = false
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingFromBinding else { return }
            guard let tv = notification.object as? NSTextView else { return }
            // Push the new text into the binding FIRST so SwiftUI's next
            // updateNSView sees them equal and doesn't overwrite.
            text.wrappedValue = tv.string
            MarkdownStyle.applyStyling(to: tv)
            detectTrigger(in: tv)
            controller?.removeSelectionBar()
        }

        /// Show/hide the floating selection toolbar as the selection changes (§3C).
        func textViewDidChangeSelection(_ notification: Notification) {
            controller?.updateSelectionBar()
        }

        /// Notion-style triggers: "/" at the start of a line (or after
        /// whitespace) opens the block menu; "@" anywhere word-initial opens
        /// the @-mention picker. The menu is deferred to the next runloop tick
        /// so it doesn't reenter the text system mid-edit.
        private func detectTrigger(in tv: NSTextView) {
            guard !suppressTriggerDetection else { return }
            guard enableSlashMenu || enableMentions else { return }
            let sel = tv.selectedRange()
            guard sel.length == 0, sel.location > 0 else { return }
            let ns = tv.string as NSString
            guard sel.location <= ns.length else { return }
            let lastChar = ns.substring(with: NSRange(location: sel.location - 1, length: 1))
            let atLineStartOrSpace: Bool = {
                if sel.location - 1 == 0 { return true }
                let prev = ns.substring(with: NSRange(location: sel.location - 2, length: 1))
                return prev == "\n" || prev == " " || prev == "\t"
            }()
            guard atLineStartOrSpace else { return }

            if lastChar == "/", enableSlashMenu {
                suppressTriggerDetection = true
                DispatchQueue.main.async { [weak self] in
                    self?.controller?.presentSlashMenu()
                    self?.suppressTriggerDetection = false
                }
            } else if lastChar == "@", enableMentions {
                suppressTriggerDetection = true
                DispatchQueue.main.async { [weak self] in
                    self?.controller?.presentMentionMenu()
                    self?.suppressTriggerDetection = false
                }
            }
        }

        /// Intercept clicks on `meetingscribe://` links and route them through
        /// the in-app navigator instead of NSWorkspace.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL? = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
            guard let url, url.scheme == WorkspaceLink.scheme else { return false }
            NotificationCenter.default.post(name: .meetingScribeOpenEntity,
                                            object: nil,
                                            userInfo: ["url": url.absoluteString])
            return true
        }
    }
}

// MARK: - NSTextView subclass that draws a placeholder when empty

@available(macOS 14.0, *)
final class MarkdownNSTextView: NSTextView {
    var placeholderString: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: MarkdownStyle.bodyFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let origin = NSPoint(x: textContainerInset.width + 5,
                             y: textContainerInset.height + 1)
        (placeholderString as NSString).draw(at: origin, withAttributes: attrs)
    }
}

// MARK: - Styling engine

@available(macOS 14.0, *)
enum MarkdownStyle {
    static let bodyFont = NSFont(name: "Plus Jakarta Sans", size: 14) ?? NSFont.systemFont(ofSize: 14)
    static let h1Font   = NSFont.systemFont(ofSize: 26, weight: .bold)
    static let h2Font   = NSFont.systemFont(ofSize: 22, weight: .bold)
    static let h3Font   = NSFont.systemFont(ofSize: 18, weight: .semibold)
    static let h4Font   = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let h5Font   = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    // Compile the inline/link regexes ONCE. `applyStyling` runs on every keystroke
    // in every markdown editor; building six `NSRegularExpression`s from source
    // each time was a measurable per-keystroke cost (regex compilation is
    // expensive). These patterns are constant, so cache the compiled objects.
    private static func compile(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }
    private static let boldRE   = compile(#"\*\*([^*\n]+)\*\*"#)
    private static let emStarRE = compile(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private static let emUndRE  = compile(#"_([^_\n]+)_"#)
    private static let codeRE   = compile(#"`([^`\n]+)`"#)
    private static let strikeRE = compile(#"~~([^~\n]+)~~"#)
    private static let linkRE   = compile(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#)

    static func applyStyling(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultParagraph()
        ], range: fullRange)

        var inCodeBlock = false
        ns.enumerateSubstrings(in: fullRange, options: .byLines) { line, lineRange, _, _ in
            guard let line = line else { return }
            if line.hasPrefix("```") {
                inCodeBlock.toggle()
                storage.addAttributes([
                    .font: codeFont,
                    .foregroundColor: NSColor.secondaryLabelColor
                ], range: lineRange)
                return
            }
            if inCodeBlock {
                storage.addAttribute(.font, value: codeFont, range: lineRange)
                storage.addAttribute(.foregroundColor,
                                     value: NSColor.secondaryLabelColor,
                                     range: lineRange)
                return
            }
            applyBlockStyle(line: line, range: lineRange, storage: storage)
        }

        applyInline(regex: boldRE, font: NSFont.boldSystemFont(ofSize: 14),
                    dimMarkers: true, markerLen: 2, in: storage, range: fullRange)
        applyInline(regex: emStarRE, font: italicFont(),
                    dimMarkers: true, markerLen: 1, in: storage, range: fullRange)
        applyInline(regex: emUndRE, font: italicFont(),
                    dimMarkers: true, markerLen: 1, in: storage, range: fullRange)
        applyInline(regex: codeRE, font: codeFont,
                    dimMarkers: true, markerLen: 1, in: storage, range: fullRange,
                    bgColor: NSColor.secondaryLabelColor.withAlphaComponent(0.1))
        applyInline(regex: strikeRE, font: bodyFont,
                    dimMarkers: true, markerLen: 2, in: storage, range: fullRange,
                    strikethrough: true)
        applyLinks(in: storage, range: fullRange)
    }

    private static func applyBlockStyle(line: String, range: NSRange, storage: NSTextStorage) {
        let headingPrefixes: [(prefix: String, font: NSFont)] = [
            ("###### ", h5Font), ("##### ", h5Font),
            ("#### ", h4Font), ("### ", h3Font),
            ("## ", h2Font), ("# ", h1Font)
        ]
        for (prefix, font) in headingPrefixes where line.hasPrefix(prefix) {
            storage.addAttribute(.font, value: font, range: range)
            let markerRange = NSRange(location: range.location, length: prefix.count)
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.tertiaryLabelColor,
                                 range: markerRange)
            return
        }

        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            let bulletStyle = NSMutableParagraphStyle()
            bulletStyle.headIndent = 20; bulletStyle.firstLineHeadIndent = 0
            storage.addAttribute(.paragraphStyle, value: bulletStyle, range: range)
            let markerRange = NSRange(location: range.location, length: 2)
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.controlAccentColor,
                                 range: markerRange)
            return
        }

        if let m = line.range(of: #"^- \[[ xX]\] "#, options: .regularExpression) {
            let count = line.distance(from: line.startIndex, to: m.upperBound)
            let style = NSMutableParagraphStyle()
            style.headIndent = 26; style.firstLineHeadIndent = 0
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            let markerRange = NSRange(location: range.location, length: count)
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.controlAccentColor,
                                 range: markerRange)
            return
        }

        if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil,
           let dot = line.firstIndex(of: ".") {
            let prefixLen = line.distance(from: line.startIndex, to: line.index(after: dot)) + 1
            let style = NSMutableParagraphStyle()
            style.headIndent = 24; style.firstLineHeadIndent = 0
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            let markerRange = NSRange(location: range.location, length: min(prefixLen, range.length))
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.controlAccentColor,
                                 range: markerRange)
            return
        }

        if line.hasPrefix("> ") {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 14; style.headIndent = 14
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.secondaryLabelColor, range: range)
            storage.addAttribute(.font, value: italicFont(), range: range)
            let markerRange = NSRange(location: range.location, length: 2)
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.tertiaryLabelColor,
                                 range: markerRange)
            return
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "***" {
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.tertiaryLabelColor, range: range)
        }
    }

    private static func applyInline(regex: NSRegularExpression?,
                                    font: NSFont,
                                    dimMarkers: Bool,
                                    markerLen: Int,
                                    in storage: NSTextStorage,
                                    range: NSRange,
                                    bgColor: NSColor? = nil,
                                    strikethrough: Bool = false) {
        guard let regex else { return }
        regex.enumerateMatches(in: storage.string, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.font, value: font, range: r)
            if let bg = bgColor {
                storage.addAttribute(.backgroundColor, value: bg, range: r)
            }
            if strikethrough {
                storage.addAttribute(.strikethroughStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: r)
            }
            if dimMarkers, r.length > markerLen * 2 {
                let leading = NSRange(location: r.location, length: markerLen)
                let trailing = NSRange(location: r.location + r.length - markerLen, length: markerLen)
                storage.addAttribute(.foregroundColor,
                                     value: NSColor.tertiaryLabelColor, range: leading)
                storage.addAttribute(.foregroundColor,
                                     value: NSColor.tertiaryLabelColor, range: trailing)
            }
        }
    }

    private static func applyLinks(in storage: NSTextStorage, range: NSRange) {
        guard let regex = linkRE else { return }
        let text = storage.string
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range,
                  let textRange = match?.range(at: 1),
                  let urlRange = match?.range(at: 2) else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            storage.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: textRange)
            if let url = URL(string: (text as NSString).substring(with: urlRange)) {
                storage.addAttribute(.link, value: url, range: textRange)
            }
            let dim = NSColor.tertiaryLabelColor
            storage.addAttribute(.foregroundColor, value: dim,
                                 range: NSRange(location: r.location, length: 1))
            storage.addAttribute(.foregroundColor, value: dim,
                                 range: NSRange(location: textRange.location + textRange.length, length: 2))
            storage.addAttribute(.foregroundColor, value: dim,
                                 range: NSRange(location: urlRange.location, length: urlRange.length))
            storage.addAttribute(.foregroundColor, value: dim,
                                 range: NSRange(location: r.location + r.length - 1, length: 1))
        }
    }

    private static func defaultParagraph() -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        // Notion-parity airy line height (§3C) instead of a flat 2pt spacing.
        p.lineHeightMultiple = 1.5
        p.lineSpacing = 2; p.paragraphSpacing = 6
        return p
    }

    /// Coral editor caret (§3C). #ff9173.
    static let caretColor = NSColor(srgbRed: 1.0, green: 0x91/255.0, blue: 0x73/255.0, alpha: 1)

    private static func italicFont() -> NSFont {
        let descriptor = NSFont.systemFont(ofSize: 14).fontDescriptor
            .withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: 14) ?? NSFont.systemFont(ofSize: 14)
    }
}

// MARK: - Editor controller (toolbar → NSTextView bridge)

/// Lets a SwiftUI formatting toolbar drive the underlying NSTextView of a
/// MarkdownEditor: toggle line prefixes (headings, bullets, checkboxes,
/// numbered, quote) and wrap the selection (bold, italic, code). Edits go
/// through the responder chain so undo + the binding stay in sync.
@available(macOS 14.0, *)
@MainActor
final class MarkdownEditorController: ObservableObject {
    weak var textView: NSTextView?
    /// Supplies @-mention candidates; set by the MarkdownEditor that owns us.
    var mentionProvider: (() -> [WorkspaceEntity])?
    /// Keeps menu action targets alive for the lifetime of a popUp.
    private var menuTargets: [MenuActionTarget] = []

    /// Toggle a block prefix on the line(s) the selection touches. If the
    /// first line already has the prefix, it's removed (and stripped from the
    /// others); otherwise it's added — replacing any other known block prefix.
    func toggleLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let lineRange = ns.lineRange(for: sel)
        var block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        if hadTrailingNewline { block.removeLast() }

        let lines = block.components(separatedBy: "\n")
        let firstHasPrefix = lines.first?.hasPrefix(prefix) ?? false
        let newLines: [String] = lines.map { line in
            if firstHasPrefix {
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
            } else {
                return prefix + Self.stripKnownPrefix(line)
            }
        }
        var replacement = newLines.joined(separator: "\n")
        if hadTrailingNewline { replacement += "\n" }
        apply(replacement, over: lineRange, in: tv)
    }

    /// Wrap the current selection with `marker` on both sides (bold/italic/
    /// code). With no selection, inserts the markers and parks the cursor
    /// between them.
    func wrapSelection(_ marker: String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = ns.substring(with: sel)
        let replacement = marker + selected + marker
        if tv.shouldChangeText(in: sel, replacementString: replacement) {
            tv.textStorage?.replaceCharacters(in: sel, with: replacement)
            if selected.isEmpty {
                tv.setSelectedRange(NSRange(location: sel.location + (marker as NSString).length, length: 0))
            }
            tv.didChangeText()
        }
        MarkdownStyle.applyStyling(to: tv)
        tv.window?.makeFirstResponder(tv)
    }

    /// Wrap the selection as a markdown link `[text](url)`, parking the caret in
    /// the `url` slot when nothing was selected.
    func wrapLink() {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = ns.substring(with: sel)
        let label = selected.isEmpty ? "text" : selected
        let replacement = "[\(label)](url)"
        guard tv.shouldChangeText(in: sel, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: sel, with: replacement)
        tv.didChangeText()
        // Select the "url" placeholder so the user can type the address.
        let urlStart = sel.location + (("[\(label)](") as NSString).length
        tv.setSelectedRange(NSRange(location: urlStart, length: 3))
        MarkdownStyle.applyStyling(to: tv)
        tv.window?.makeFirstResponder(tv)
    }

    private func apply(_ replacement: String, over range: NSRange, in tv: NSTextView) {
        guard tv.shouldChangeText(in: range, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        MarkdownStyle.applyStyling(to: tv)
        tv.window?.makeFirstResponder(tv)
    }

    // MARK: - Floating selection toolbar (§3C)

    private var selectionBar: NSHostingView<SelectionFormatBar>?

    /// Show/hide the floating B/I/Link bar above the current selection. Added as
    /// a subview of the text view so it tracks scrolling in text-view coords.
    func updateSelectionBar() {
        guard let tv = textView, tv.isEditable,
              let lm = tv.layoutManager, let tc = tv.textContainer else {
            removeSelectionBar(); return
        }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { removeSelectionBar(); return }

        let glyphRange = lm.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let origin = tv.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y

        let bar = selectionBar ?? {
            let host = NSHostingView(rootView: SelectionFormatBar(controller: self))
            host.translatesAutoresizingMaskIntoConstraints = true
            selectionBar = host
            return host
        }()
        let size = bar.fittingSize
        let x = max(2, rect.midX - size.width / 2)
        let y = max(0, rect.minY - size.height - 6)   // above the selection (flipped coords)
        bar.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        if bar.superview == nil { tv.addSubview(bar) }
    }

    func removeSelectionBar() {
        selectionBar?.removeFromSuperview()
        selectionBar = nil
    }

    // MARK: - Slash & @-mention menus (Phase 4)

    /// Inserts a block snippet, first removing the "/" trigger char that sits
    /// immediately before the caret. `caretOffsetFromEnd` parks the cursor
    /// inside the snippet (e.g. between code fences).
    func insertBlockSnippet(_ snippet: String, caretOffsetFromEnd: Int = 0) {
        replaceTrigger("/", with: snippet, caretOffsetFromEnd: caretOffsetFromEnd)
    }

    /// Inserts a markdown link for an @-mention, removing the "@" trigger.
    func insertMention(_ entity: WorkspaceEntity) {
        replaceTrigger("@", with: entity.markdownLink + " ")
    }

    /// Inserts a template/snippet at the caret (no trigger char to remove).
    /// Used by the Templates toolbar button.
    func insertTemplate(_ snippet: String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        guard tv.shouldChangeText(in: sel, replacementString: snippet) else { return }
        tv.textStorage?.replaceCharacters(in: sel, with: snippet)
        tv.didChangeText()
        let caret = sel.location + (snippet as NSString).length
        tv.setSelectedRange(NSRange(location: max(0, caret), length: 0))
        MarkdownStyle.applyStyling(to: tv)
        tv.window?.makeFirstResponder(tv)
    }

    private func replaceTrigger(_ trigger: Character, with snippet: String, caretOffsetFromEnd: Int = 0) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        var range = sel
        if sel.location > 0 {
            let ns = tv.string as NSString
            let prev = ns.substring(with: NSRange(location: sel.location - 1, length: 1))
            if prev == String(trigger) {
                range = NSRange(location: sel.location - 1, length: 1 + sel.length)
            }
        }
        guard tv.shouldChangeText(in: range, replacementString: snippet) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: snippet)
        tv.didChangeText()
        let caret = range.location + (snippet as NSString).length - caretOffsetFromEnd
        tv.setSelectedRange(NSRange(location: max(0, caret), length: 0))
        MarkdownStyle.applyStyling(to: tv)
        tv.window?.makeFirstResponder(tv)
    }

    /// Caret position in the text view's own coordinate space, nudged just
    /// below the insertion point so a popUp menu doesn't cover the line.
    private func caretPoint(in tv: NSTextView) -> NSPoint {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else {
            return NSPoint(x: 8, y: 8)
        }
        let loc = min(max(0, tv.selectedRange().location), (tv.string as NSString).length)
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: loc, length: 0),
                                       actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let origin = tv.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return NSPoint(x: rect.minX, y: rect.maxY + 5)
    }

    func presentSlashMenu() {
        guard let tv = textView else { return }
        menuTargets.removeAll()
        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ image: String, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.fire), keyEquivalent: "")
            let target = MenuActionTarget(handler: action)
            item.target = target
            item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
            menuTargets.append(target)
            menu.addItem(item)
        }

        add("Text", "textformat") { [weak self] in self?.insertBlockSnippet("") }
        add("Heading 1", "1.square") { [weak self] in self?.insertBlockSnippet("# ") }
        add("Heading 2", "2.square") { [weak self] in self?.insertBlockSnippet("## ") }
        add("Heading 3", "3.square") { [weak self] in self?.insertBlockSnippet("### ") }
        menu.addItem(.separator())
        add("Bulleted list", "list.bullet") { [weak self] in self?.insertBlockSnippet("- ") }
        add("Numbered list", "list.number") { [weak self] in self?.insertBlockSnippet("1. ") }
        add("To-do checkbox", "checklist") { [weak self] in self?.insertBlockSnippet("- [ ] ") }
        add("Quote", "text.quote") { [weak self] in self?.insertBlockSnippet("> ") }
        add("Divider", "minus") { [weak self] in self?.insertBlockSnippet("---\n") }
        add("Code block", "chevron.left.forwardslash.chevron.right") { [weak self] in
            self?.insertBlockSnippet("```\n\n```\n", caretOffsetFromEnd: 5)
        }
        menu.addItem(.separator())

        let templatesItem = NSMenuItem(title: "Template", action: nil, keyEquivalent: "")
        templatesItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        let sub = NSMenu()
        for t in NoteTemplate.all {
            let item = NSMenuItem(title: t.name, action: #selector(MenuActionTarget.fire), keyEquivalent: "")
            let target = MenuActionTarget(handler: { [weak self] in self?.insertBlockSnippet(t.body) })
            item.target = target
            item.image = NSImage(systemSymbolName: t.systemImage, accessibilityDescription: nil)
            menuTargets.append(target)
            sub.addItem(item)
        }
        templatesItem.submenu = sub
        menu.addItem(templatesItem)

        menu.popUp(positioning: nil, at: caretPoint(in: tv), in: tv)
        menuTargets.removeAll()
    }

    func presentMentionMenu() {
        guard let tv = textView else { return }
        let entities = mentionProvider?() ?? []
        menuTargets.removeAll()
        let menu = NSMenu()
        menu.autoenablesItems = false

        if entities.isEmpty {
            let empty = NSMenuItem(title: "No meetings, notes, or projects to link yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            // Group by kind for readability; cap each group so the menu stays
            // navigable (type-to-select still works across the whole menu).
            for kind in WorkspaceEntityKind.allCases {
                let group = entities.filter { $0.kind == kind }.prefix(25)
                guard !group.isEmpty else { continue }
                let headerItem = NSMenuItem(title: kind.label, action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                for e in group {
                    let item = NSMenuItem(title: "   " + e.title, action: #selector(MenuActionTarget.fire), keyEquivalent: "")
                    let target = MenuActionTarget(handler: { [weak self] in self?.insertMention(e) })
                    item.target = target
                    item.image = NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil)
                    menuTargets.append(target)
                    menu.addItem(item)
                }
            }
        }

        menu.popUp(positioning: nil, at: caretPoint(in: tv), in: tv)
        menuTargets.removeAll()
    }

    private static func stripKnownPrefix(_ line: String) -> String {
        let prefixes = ["###### ", "##### ", "#### ", "### ", "## ", "# ",
                        "- [ ] ", "- [x] ", "- ", "* ", "1. ", "> "]
        for p in prefixes where line.hasPrefix(p) {
            return String(line.dropFirst(p.count))
        }
        return line
    }
}

/// Trivial @objc target so NSMenuItem can call a Swift closure. Retained by
/// the controller for the duration of a popUp.
final class MenuActionTarget: NSObject {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler; super.init() }
    @objc func fire() { handler() }
}

// MARK: - Rich markdown editor (toolbar + live-preview editor)

/// MarkdownEditor with a Notion-like formatting toolbar. The text stays plain
/// markdown; the toolbar just inserts the right sigils for the selection.
@available(macOS 14.0, *)
struct RichMarkdownEditor: View {
    @Binding var text: String
    var placeholder: String? = nil
    /// Enables the "/" block menu and "@" mention picker (notes editing).
    var enableSlashMenu: Bool = true
    var enableMentions: Bool = true
    /// Supplies @-mention candidates (meetings, notes, projects, action items).
    var mentionProvider: (() -> [WorkspaceEntity])? = nil
    @StateObject private var controller = MarkdownEditorController()

    /// Mentions only make sense when a candidate provider is supplied.
    private var mentionsOn: Bool { enableMentions && mentionProvider != nil }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            MarkdownEditor(text: $text, isEditable: true,
                           placeholder: placeholder, controller: controller,
                           enableSlashMenu: enableSlashMenu,
                           enableMentions: mentionsOn,
                           mentionProvider: mentionProvider)
        }
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5))
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            tbButton("H1", help: "Heading 1") { controller.toggleLinePrefix("# ") }
            tbButton("H2", help: "Heading 2") { controller.toggleLinePrefix("## ") }
            tbButton("H3", help: "Heading 3") { controller.toggleLinePrefix("### ") }
            divider
            tbIcon("list.bullet", help: "Bullet list") { controller.toggleLinePrefix("- ") }
            tbIcon("list.number", help: "Numbered list") { controller.toggleLinePrefix("1. ") }
            tbIcon("checklist", help: "Checkbox") { controller.toggleLinePrefix("- [ ] ") }
            tbIcon("text.quote", help: "Quote") { controller.toggleLinePrefix("> ") }
            divider
            tbIcon("bold", help: "Bold") { controller.wrapSelection("**") }
            tbIcon("italic", help: "Italic") { controller.wrapSelection("*") }
            tbIcon("chevron.left.forwardslash.chevron.right", help: "Inline code") { controller.wrapSelection("`") }
            if mentionsOn {
                divider
                tbIcon("at", help: "Link a meeting, note, or project (@)") { controller.presentMentionMenu() }
            }
            if enableSlashMenu {
                templatesMenu
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(NDS.fieldBg)
    }

    private var templatesMenu: some View {
        Menu {
            ForEach(NoteTemplate.all) { t in
                Button {
                    controller.insertTemplate(t.body)
                } label: {
                    Label(t.name, systemImage: t.systemImage)
                }
            }
        } label: {
            Image(systemName: "doc.on.doc").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(width: 34)
        .help("Insert a template")
    }

    private var divider: some View {
        Rectangle().fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 16).padding(.horizontal, 4)
    }

    private func tbButton(_ label: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).scaledFont(12, weight: .heavy, relativeTo: .caption)
                .foregroundStyle(NDS.textSecondary)
                .frame(minWidth: 24)
                .padding(.vertical, 3).padding(.horizontal, 4)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func tbIcon(_ system: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).scaledFont(12, weight: .semibold)
                .foregroundStyle(NDS.textSecondary)
                .frame(minWidth: 24)
                .padding(.vertical, 3).padding(.horizontal, 4)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Floating selection toolbar (§3C)

/// Compact B / I / Link bar that floats above the current text selection.
@available(macOS 14.0, *)
private struct SelectionFormatBar: View {
    let controller: MarkdownEditorController

    var body: some View {
        HStack(spacing: 1) {
            btn("bold", help: "Bold") { controller.wrapSelection("**") }
            btn("italic", help: "Italic") { controller.wrapSelection("*") }
            btn("link", help: "Link") { controller.wrapLink() }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(NDS.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }

    private func btn(_ system: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).scaledFont(11, weight: .semibold)
                .foregroundStyle(NDS.textPrimary)
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
