import XCTest
@testable import MeetingScribe

/// Sanity checks for the hand-rolled HTML → Markdown extractor. We feed it a
/// small handful of representative shapes (article tag, doc-style page, SPA
/// shell) and assert the basic guarantees: title picked, script content
/// stripped, word count plausible.
final class ReadabilityExtractorTests: XCTestCase {

    private let baseURL = URL(string: "https://example.com/")!

    func testExtractsArticleAndStripsScripts() {
        let html = """
        <html><head><title>Top of doc</title></head>
        <body>
          <header><nav><a href="/x">Home</a></nav></header>
          <article>
            <h1>The Real Article</h1>
            <p>This article talks about the planner. The planner reads the brain dump.</p>
            <p>It also writes <strong>tasks</strong>.</p>
            <script>window.__nasty = 1; alert('boom');</script>
          </article>
          <footer>© example</footer>
        </body></html>
        """
        let extracted = ReadabilityExtractor.extract(html: html, baseURL: baseURL)
        XCTAssertEqual(extracted.title, "The Real Article")
        XCTAssertTrue(extracted.markdown.contains("The planner"),
                      "article body should survive")
        XCTAssertFalse(extracted.markdown.contains("window.__nasty"),
                       "<script> contents must never leak into the markdown")
        XCTAssertFalse(extracted.markdown.contains("alert("),
                       "<script> contents must never leak into the markdown")
        XCTAssertGreaterThan(extracted.wordCount, 8)
    }

    func testHeadingsAndLinks() {
        let html = """
        <html><body><main>
          <h2>Section</h2>
          <p>See the <a href="/docs/page">docs</a> for more.</p>
        </main></body></html>
        """
        let out = ReadabilityExtractor.extract(html: html, baseURL: baseURL)
        XCTAssertTrue(out.markdown.contains("## Section"))
        XCTAssertTrue(out.markdown.contains("[docs](https://example.com/docs/page)"),
                      "links should be markdown-rendered with absolute URLs")
    }

    func testEntityDecode() {
        let html = """
        <html><body><article>
          <p>Caf&eacute; &amp; tea &mdash; today&#39;s special is &#x2603;.</p>
        </article></body></html>
        """
        let out = ReadabilityExtractor.extract(html: html, baseURL: baseURL)
        // Be tolerant of the named-entity decoder skipping ones we don't list;
        // just check the ones we DO list.
        XCTAssertTrue(out.markdown.contains("&"))
        XCTAssertTrue(out.markdown.contains("—"))
        XCTAssertTrue(out.markdown.contains("'"))
        XCTAssertTrue(out.markdown.contains("☃"))
    }

    func testFallsBackToNSAttributedStringOnSparseScannerOutput() {
        // No <article>/<main>, no h1, content buried in deep divs that the
        // scanner's density heuristic may not pick. We just want SOME output.
        let html = """
        <html><body>
          <div><div><div><div>
            <p>Real content lives down here in a deeply nested div tree.</p>
            <p>The planner should still see at least these sentences after the fallback runs.</p>
            <p>Another paragraph to push us over the 40-word threshold so the body is non-trivial.</p>
            <p>Yet another paragraph with concrete words like Linear Notion calendar focus block etcetera.</p>
          </div></div></div></div>
        </body></html>
        """
        let out = ReadabilityExtractor.extract(html: html, baseURL: baseURL)
        XCTAssertGreaterThan(out.wordCount, 10,
                             "the NSAttributedString backstop should still surface body text")
    }
}
