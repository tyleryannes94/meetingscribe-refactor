import Foundation
import AppKit

/// Foundation/AppKit-only HTML → Markdown extractor for the Brain Dump page.
///
/// We deliberately do NOT pull in SwiftSoup or a full HTML parser — the
/// Package manifest is otherwise dependency-clean. Instead this implements a
/// small Readability-style heuristic:
///
///   1. Strip everything inside `<script>`, `<style>`, `<noscript>`, `<svg>`,
///      and HTML comments.
///   2. Walk the cleaned document and pick the densest container among
///      `<article>`, `<main>`, `<div role="main">`. Density = text length /
///      (1 + link length). Fall back to `<body>` when nothing scores well.
///   3. Replace block tags with newlines, `<h1..6>` with leading `#`s,
///      `<a href="…">x</a>` with `[x](href)`, `<li>` with `- `, paragraphs
///      with blank lines.
///   4. Decode HTML entities.
///   5. If the result is implausibly short (< 40 words), retry with
///      `NSAttributedString(data:options:[.documentType:.html])` as a backstop.
struct ExtractedArticle {
    var title: String
    var byline: String?
    var markdown: String
    var wordCount: Int
}

enum ReadabilityExtractor {

    static func extract(html: String, baseURL: URL) -> ExtractedArticle {
        let cleaned = stripNoiseBlocks(html)
        let title = extractTitle(cleaned)
        let byline = extractByline(cleaned)
        let body = pickMainContent(cleaned) ?? cleaned

        let markdown = htmlToMarkdown(body, baseURL: baseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let wordCount = markdown.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount < 40 {
            // Backstop: NSAttributedString HTML import. Strips formatting but
            // is reliable when our scanner gives up on a heavy SPA shell.
            if let attr = attributedStringFallback(html) {
                let fallback = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
                let fbCount = fallback.split(whereSeparator: { $0.isWhitespace }).count
                if fbCount > wordCount {
                    return ExtractedArticle(
                        title: title ?? (baseURL.host ?? ""),
                        byline: byline,
                        markdown: fallback,
                        wordCount: fbCount
                    )
                }
            }
        }
        return ExtractedArticle(
            title: title ?? (baseURL.host ?? ""),
            byline: byline,
            markdown: markdown,
            wordCount: wordCount
        )
    }

    // MARK: - Noise stripping

    /// Drop the regions that never carry article content. Case-insensitive
    /// open / close tag matching, and HTML comments (`<!-- … -->`).
    private static func stripNoiseBlocks(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg", "iframe", "form", "footer", "nav", "aside"] {
            s = removeBlockTag(s, name: tag)
        }
        s = removeComments(s)
        return s
    }

    private static func removeBlockTag(_ html: String, name: String) -> String {
        var out = html
        let nameLC = name.lowercased()
        var searchStart = out.startIndex
        while let openRange = out.range(
            of: "<\(nameLC)",
            options: [.caseInsensitive],
            range: searchStart..<out.endIndex
        ) {
            // Find the matching close tag; tolerate self-closing forms.
            guard let closeRange = out.range(
                of: "</\(nameLC)>",
                options: [.caseInsensitive],
                range: openRange.upperBound..<out.endIndex
            ) else {
                // No close — drop from the open onward.
                out.removeSubrange(openRange.lowerBound..<out.endIndex)
                break
            }
            out.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            searchStart = openRange.lowerBound
        }
        return out
    }

    private static func removeComments(_ html: String) -> String {
        var out = html
        while let openRange = out.range(of: "<!--") {
            guard let closeRange = out.range(of: "-->",
                                             range: openRange.upperBound..<out.endIndex) else {
                out.removeSubrange(openRange.lowerBound..<out.endIndex)
                break
            }
            out.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }
        return out
    }

    // MARK: - Title / byline

    private static func extractTitle(_ html: String) -> String? {
        // Prefer <h1>; fall back to <title>.
        if let h1 = innerText(of: "h1", in: html), !h1.isEmpty { return h1 }
        if let title = innerText(of: "title", in: html), !title.isEmpty { return title }
        return nil
    }

    private static func extractByline(_ html: String) -> String? {
        // <meta name="author" content="…">
        if let range = html.range(of: #"<meta[^>]+name=["']author["'][^>]+content=["']([^"']+)["']"#,
                                  options: [.regularExpression, .caseInsensitive]) {
            let chunk = String(html[range])
            if let m = chunk.range(of: #"content=["']([^"']+)["']"#,
                                   options: [.regularExpression, .caseInsensitive]) {
                let raw = String(chunk[m])
                // Pull out the captured group manually — Foundation regex
                // ranges don't expose groups without NSRegularExpression.
                if let openQuote = raw.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                    let after = raw.index(after: openQuote)
                    if let closeQuote = raw[after...].firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                        return decodeHTMLEntities(String(raw[after..<closeQuote]))
                    }
                }
            }
        }
        return nil
    }

    private static func innerText(of tag: String, in html: String) -> String? {
        let lower = tag.lowercased()
        guard let openRange = html.range(of: "<\(lower)", options: [.caseInsensitive]) else { return nil }
        guard let openClose = html.range(of: ">", range: openRange.upperBound..<html.endIndex) else { return nil }
        guard let close = html.range(of: "</\(lower)>",
                                     options: [.caseInsensitive],
                                     range: openClose.upperBound..<html.endIndex) else { return nil }
        let inner = html[openClose.upperBound..<close.lowerBound]
        return decodeHTMLEntities(stripTags(String(inner)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Main content selection

    /// Score each candidate container by text density and pick the densest one.
    /// Caller falls back to the full doc when nothing is found.
    private static func pickMainContent(_ html: String) -> String? {
        let candidates: [String] = ["article", "main"]
        var best: (score: Double, body: String)?
        for tag in candidates {
            let bodies = innerHTMLs(of: tag, in: html)
            for body in bodies {
                let score = densityScore(body)
                if score > (best?.score ?? 0) { best = (score, body) }
            }
        }
        // Also try `<div role="main">` and common id/class signals.
        for signal in [#"<div[^>]+role=["']main["']"#,
                       #"<div[^>]+id=["'](content|main|article|story|post)["']"#,
                       #"<div[^>]+class=["'][^"']*(content|article|story|post)[^"']*["']"#] {
            if let range = html.range(of: signal, options: [.regularExpression, .caseInsensitive]) {
                // Find the matching </div> for this div by simple depth tracking.
                let after = range.upperBound
                if let endIdx = matchingCloseTag("div", in: html, from: after) {
                    let body = String(html[after..<endIdx])
                    let score = densityScore(body)
                    if score > (best?.score ?? 0) { best = (score, body) }
                }
            }
        }
        return best?.body
    }

    private static func densityScore(_ html: String) -> Double {
        let text = stripTags(html)
        let textLen = Double(text.count)
        // Count rough link character mass — we'd rather not pick a nav blob.
        var linkLen = 0
        var idx = html.startIndex
        while let openRange = html.range(of: "<a", options: [.caseInsensitive], range: idx..<html.endIndex) {
            guard let close = html.range(of: "</a>",
                                         options: [.caseInsensitive],
                                         range: openRange.upperBound..<html.endIndex) else { break }
            linkLen += stripTags(String(html[openRange.upperBound..<close.lowerBound])).count
            idx = close.upperBound
        }
        return textLen / (1.0 + Double(linkLen))
    }

    /// Find the index right after the matching `</tag>` starting from `start`,
    /// counting nested opens. Returns nil if unbalanced.
    private static func matchingCloseTag(_ tag: String, in html: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var i = start
        let openPattern = "<\(tag.lowercased())"
        let closePattern = "</\(tag.lowercased())>"
        while i < html.endIndex {
            let opn = html.range(of: openPattern, options: [.caseInsensitive], range: i..<html.endIndex)
            let cls = html.range(of: closePattern, options: [.caseInsensitive], range: i..<html.endIndex)
            switch (opn, cls) {
            case (nil, nil):
                return nil
            case (nil, let cls?):
                depth -= 1
                if depth == 0 { return cls.lowerBound }
                i = cls.upperBound
            case (let opn?, nil):
                depth += 1
                i = opn.upperBound
            case (let opn?, let cls?):
                if opn.lowerBound < cls.lowerBound {
                    depth += 1
                    i = opn.upperBound
                } else {
                    depth -= 1
                    if depth == 0 { return cls.lowerBound }
                    i = cls.upperBound
                }
            }
        }
        return nil
    }

    /// All inner-HTML segments for a tag (e.g. multiple `<article>`s on one
    /// page). Skips empty bodies.
    private static func innerHTMLs(of tag: String, in html: String) -> [String] {
        let lower = tag.lowercased()
        var results: [String] = []
        var idx = html.startIndex
        while let openRange = html.range(of: "<\(lower)",
                                         options: [.caseInsensitive],
                                         range: idx..<html.endIndex) {
            guard let openClose = html.range(of: ">",
                                             range: openRange.upperBound..<html.endIndex) else { break }
            guard let endIdx = matchingCloseTag(lower, in: html, from: openClose.upperBound) else {
                break
            }
            let body = String(html[openClose.upperBound..<endIdx])
            if !body.isEmpty { results.append(body) }
            // Move past `</tag>`.
            if let advance = html.range(of: "</\(lower)>",
                                        options: [.caseInsensitive],
                                        range: endIdx..<html.endIndex) {
                idx = advance.upperBound
            } else {
                idx = endIdx
            }
        }
        return results
    }

    // MARK: - HTML → Markdown

    /// Replace structural tags with whitespace and inline tags with markdown
    /// equivalents. Order matters: handle anchors before stripping all tags,
    /// so we keep the URLs.
    private static func htmlToMarkdown(_ html: String, baseURL: URL) -> String {
        var s = html

        // <br> → newline
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n",
                                   options: [.regularExpression, .caseInsensitive])

        // Headings: <h1>x</h1> → \n# x\n
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            s = s.replacingOccurrences(of: "<h\(level)[^>]*>", with: "\n\(hashes) ",
                                       options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: "</h\(level)>", with: "\n",
                                       options: [.regularExpression, .caseInsensitive])
        }

        // Paragraphs and blocks → blank line
        for tag in ["p", "div", "section", "header", "footer", "li", "tr", "blockquote", "pre"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>", with: "\n",
                                       options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: "</\(tag)>", with: "\n",
                                       options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "\n- ",
                                   options: [.regularExpression, .caseInsensitive])

        // Bold / italic
        s = s.replacingOccurrences(of: "<(strong|b)[^>]*>", with: "**",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(strong|b)>", with: "**",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<(em|i)[^>]*>", with: "_",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(em|i)>", with: "_",
                                   options: [.regularExpression, .caseInsensitive])

        // Anchors: <a href="…">text</a> → [text](url). Resolve relative URLs.
        s = rewriteAnchors(s, baseURL: baseURL)

        // Strip remaining tags
        s = stripTags(s)
        s = decodeHTMLEntities(s)

        // Collapse runaway blank lines into at most two newlines.
        s = s.replacingOccurrences(of: "[\\t ]+", with: " ",
                                   options: [.regularExpression])
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n",
                                   options: [.regularExpression])

        return s
    }

    private static func rewriteAnchors(_ html: String, baseURL: URL) -> String {
        // Pattern: <a … href="…" … >…</a>. We find each anchor open + close
        // and rewrite by hand because Foundation regex can't capture groups
        // without NSRegularExpression bookkeeping.
        var out = html
        var idx = out.startIndex
        while let openRange = out.range(of: "<a", options: [.caseInsensitive], range: idx..<out.endIndex) {
            guard let openClose = out.range(of: ">", range: openRange.upperBound..<out.endIndex) else { break }
            let openTag = out[openRange.lowerBound..<openClose.upperBound]
            guard let close = out.range(of: "</a>",
                                        options: [.caseInsensitive],
                                        range: openClose.upperBound..<out.endIndex) else { break }
            let inner = stripTags(String(out[openClose.upperBound..<close.lowerBound]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let href = extractAttribute("href", from: String(openTag)) ?? ""
            let resolved = href.isEmpty ? "" : (URL(string: href, relativeTo: baseURL)?.absoluteString ?? href)
            let replacement: String
            if inner.isEmpty {
                replacement = resolved
            } else if resolved.isEmpty {
                replacement = inner
            } else {
                replacement = "[\(inner)](\(resolved))"
            }
            out.replaceSubrange(openRange.lowerBound..<close.upperBound, with: replacement)
            // Advance past the inserted markdown so we don't re-match it.
            idx = out.index(openRange.lowerBound, offsetBy: replacement.count, limitedBy: out.endIndex) ?? out.endIndex
        }
        return out
    }

    private static func extractAttribute(_ name: String, from tag: String) -> String? {
        // Match either single or double quotes; tolerate `name = "val"` spacing.
        let pattern = "\(name)\\s*=\\s*\"([^\"]*)\""
        if let r = tag.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let chunk = String(tag[r])
            if let open = chunk.firstIndex(of: "\""),
               let close = chunk[chunk.index(after: open)...].firstIndex(of: "\"") {
                return String(chunk[chunk.index(after: open)..<close])
            }
        }
        let altPattern = "\(name)\\s*=\\s*'([^']*)'"
        if let r = tag.range(of: altPattern, options: [.regularExpression, .caseInsensitive]) {
            let chunk = String(tag[r])
            if let open = chunk.firstIndex(of: "'"),
               let close = chunk[chunk.index(after: open)...].firstIndex(of: "'") {
                return String(chunk[chunk.index(after: open)..<close])
            }
        }
        return nil
    }

    /// Cheap tag stripper: drops every `<…>` substring. Used both during the
    /// markdown pass and inside link-text extraction.
    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: " ",
                               options: [.regularExpression])
    }

    /// Minimal HTML entity decoder. Covers the named entities and the numeric
    /// `&#1234;` / `&#x1A2B;` shapes — enough for article text.
    private static func decodeHTMLEntities(_ s: String) -> String {
        var out = s
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}")
        ]
        for (entity, replacement) in named {
            out = out.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        // Numeric entities. Walk and replace.
        var idx = out.startIndex
        while let openRange = out.range(of: "&#", range: idx..<out.endIndex) {
            guard let semi = out.range(of: ";", range: openRange.upperBound..<out.endIndex) else { break }
            let raw = String(out[openRange.upperBound..<semi.lowerBound])
            var code: UInt32?
            if raw.lowercased().hasPrefix("x") {
                code = UInt32(raw.dropFirst(), radix: 16)
            } else {
                code = UInt32(raw, radix: 10)
            }
            if let c = code, let scalar = Unicode.Scalar(c) {
                out.replaceSubrange(openRange.lowerBound..<semi.upperBound, with: String(scalar))
                idx = out.index(openRange.lowerBound, offsetBy: 1, limitedBy: out.endIndex) ?? out.endIndex
            } else {
                idx = semi.upperBound
            }
        }
        return out
    }

    // MARK: - NSAttributedString backstop

    private static func attributedStringFallback(_ html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return try? NSAttributedString(data: data, options: options,
                                       documentAttributes: nil)
    }
}
