//
//  MarkdownRendererTests.swift
//  MarkdownEditorTests
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import Foundation
import Testing
@testable import MarkdownEditor

struct MarkdownRendererTests {

    @Test func headingProducesLevelTag() {
        let html = MarkdownRenderer.htmlFragment(from: "## Subtitle")
        #expect(html.contains("<h2>Subtitle</h2>"))
    }

    @Test func tableProducesHeadAndBodyWithAlignment() {
        let text = """
        | Left | Center | Right |
        | :--- | :----: | ----: |
        | a    | b      | c     |
        """
        let html = MarkdownRenderer.htmlFragment(from: text)

        #expect(html.contains("<table>"))
        #expect(html.contains("<thead>"))
        #expect(html.contains("<th style=\"text-align:left\">Left</th>"))
        #expect(html.contains("<th style=\"text-align:center\">Center</th>"))
        #expect(html.contains("<th style=\"text-align:right\">Right</th>"))
        #expect(html.contains("<tbody>"))
        #expect(html.contains("<td style=\"text-align:left\">a</td>"))
    }

    @Test func nestedListsProduceNestedULTags() {
        let text = """
        - Outer
          - Inner
        """
        let html = MarkdownRenderer.htmlFragment(from: text)

        let outerUL = html.range(of: "<ul>")
        let innerUL = html.range(of: "<ul>", range: outerUL.map { $0.upperBound..<html.endIndex })
        #expect(outerUL != nil)
        #expect(innerUL != nil)
        #expect(html.contains("<li>Outer"))
        #expect(html.contains("<li>Inner</li>"))
    }

    @Test func fencedCodeBlockProducesPreCodeWithLanguageClass() {
        let text = """
        ```swift
        let x = 1
        ```
        """
        let html = MarkdownRenderer.htmlFragment(from: text)

        #expect(html.contains("<pre><code class=\"language-swift\">let x = 1"))
        #expect(html.contains("</code></pre>"))
    }

    @Test func rawInlineHTMLInSourceIsEscapedNotPassedThrough() {
        let html = MarkdownRenderer.htmlFragment(from: "Click <script>alert(1)</script> here")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test func rawHTMLBlockInSourceIsEscapedNotPassedThrough() {
        let text = """
        <div class="evil">
        injected
        </div>
        """
        let html = MarkdownRenderer.htmlFragment(from: text)
        #expect(!html.contains("<div class=\"evil\">"))
        #expect(html.contains("&lt;div class=\"evil\"&gt;"))
    }

    @Test func textContentIsHTMLEscaped() {
        let html = MarkdownRenderer.htmlFragment(from: "1 < 2 & 3 > 1")
        #expect(html.contains("1 &lt; 2 &amp; 3 &gt; 1"))
    }

    @Test func linkProducesAnchorTag() {
        let html = MarkdownRenderer.htmlFragment(from: "[docs](https://example.com)")
        #expect(html.contains("<a href=\"https://example.com\">docs</a>"))
    }

    @Test func htmlDocumentInlinesStylesheet() {
        let html = MarkdownRenderer.htmlDocument(from: "# Title", stylesheet: "body { color: red; }")
        #expect(html.contains("<style>"))
        #expect(html.contains("body { color: red; }"))
        #expect(html.contains("<h1>Title</h1>"))
    }

    @Test func tightListItemDoesNotWrapContentInParagraphTag() {
        let text = """
        - Outer
          - Inner
        """
        let html = MarkdownRenderer.htmlFragment(from: text)
        #expect(!html.contains("<p>"))
    }

    @Test func looseListItemWithMultipleParagraphsKeepsThemSeparated() {
        let text = """
        - First para.

          Second para.
        """
        let html = MarkdownRenderer.htmlFragment(from: text)
        #expect(html.contains("<li><p>First para.</p>\n<p>Second para.</p>\n</li>"))
    }
}
