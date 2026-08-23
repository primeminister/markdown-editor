//
//  MarkdownHighlighterTests.swift
//  MarkdownEditorTests
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import Foundation
import Testing
@testable import MarkdownEditor

private func nsRange(of substring: String, in text: String) -> NSRange {
    guard let range = text.range(of: substring) else {
        Issue.record("substring \"\(substring)\" not found in \"\(text)\"")
        return NSRange(location: NSNotFound, length: 0)
    }
    return NSRange(range, in: text)
}

struct MarkdownHighlighterTests {

    @Test func headerMatchesHashPrefixedLine() {
        let text = "### Subtitle\nBody text"
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .header }

        #expect(tokens.map(\.range) == [nsRange(of: "### Subtitle", in: text)])
    }

    @Test func boldMatchesDoubleAsteriskSpan() {
        let text = "This is **bold** text."
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .bold }

        #expect(tokens.map(\.range) == [nsRange(of: "**bold**", in: text)])
    }

    @Test func italicMatchesSingleAsteriskSpanWithoutMatchingBold() {
        let text = "This is *italic*, not **bold**."
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .italic }

        #expect(tokens.map(\.range) == [nsRange(of: "*italic*", in: text)])
    }

    @Test func strikethroughMatchesDoubleTildeSpan() {
        let text = "This is ~~struck~~ text."
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .strikethrough }

        #expect(tokens.map(\.range) == [nsRange(of: "~~struck~~", in: text)])
    }

    @Test func inlineCodeMatchesBacktickSpan() {
        let text = "Use `let x = 1` here."
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .inlineCode }

        #expect(tokens.map(\.range) == [nsRange(of: "`let x = 1`", in: text)])
    }

    @Test func linkMatchesMarkdownLinkSyntax() {
        let text = "See [docs](https://example.com) for more."
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .link }

        #expect(tokens.map(\.range) == [nsRange(of: "[docs](https://example.com)", in: text)])
    }

    @Test func fencedCodeMatchesTripleBacktickBlock() {
        let text = "Before\n```\nlet x = 1\nlet y = 2\n```\nAfter"
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .fencedCode }

        #expect(tokens.map(\.range) == [nsRange(of: "```\nlet x = 1\nlet y = 2\n```", in: text)])
    }

    @Test func blockquoteMatchesAngleBracketPrefixedLine() {
        let text = "> Quoted line\nNormal line"
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .blockquote }

        #expect(tokens.map(\.range) == [nsRange(of: "> Quoted line", in: text)])
    }

    // MARK: - scopedRange

    @Test func scopedRangeReturnsParagraphRangeForEditAwayFromFence() {
        let text = "First paragraph\n\nSecond paragraph\n\nThird paragraph"
        let tokens = MarkdownHighlighter.matches(in: text)
        let editRange = nsRange(of: "Second paragraph", in: text)

        let result = MarkdownHighlighter.scopedRange(for: editRange, in: text, tokens: tokens)

        #expect(result == (text as NSString).paragraphRange(for: editRange))
    }

    @Test func scopedRangeReturnsNilWhenEditIsInsideFencedCode() {
        let text = "Preamble\n```\ncode line\n```\nEpilogue"
        let tokens = MarkdownHighlighter.matches(in: text)
        let editRange = nsRange(of: "code line", in: text)

        let result = MarkdownHighlighter.scopedRange(for: editRange, in: text, tokens: tokens)

        #expect(result == nil)
    }

    @Test func scopedRangeReturnsNilWhenEditParagraphBordersFencedCode() {
        let text = "Preamble\n```\ncode line\n```\nEpilogue"
        let tokens = MarkdownHighlighter.matches(in: text)
        // "Preamble\n" paragraph ends where the opening fence begins
        let editRange = nsRange(of: "Preamble", in: text)

        let result = MarkdownHighlighter.scopedRange(for: editRange, in: text, tokens: tokens)

        #expect(result == nil)
    }

    @Test func scopedRangeCoversAllParagraphsSpannedByMultiParagraphEdit() {
        let text = "Line one\nLine two\nLine three"
        let tokens = MarkdownHighlighter.matches(in: text)
        let editRange = NSUnionRange(nsRange(of: "Line one", in: text), nsRange(of: "Line two", in: text))

        let result = MarkdownHighlighter.scopedRange(for: editRange, in: text, tokens: tokens)

        #expect(result == (text as NSString).paragraphRange(for: editRange))
    }

    @Test func scopedRangeHandlesEditAtEndOfDocument() {
        let text = "First paragraph\nLast paragraph"
        let tokens: [MarkdownToken] = []
        let editRange = NSRange(location: (text as NSString).length, length: 0)

        let result = MarkdownHighlighter.scopedRange(for: editRange, in: text, tokens: tokens)

        // Should return the last paragraph, not nil or paragraph zero
        let lastParaRange = (text as NSString).paragraphRange(
            for: NSRange(location: (text as NSString).length - 1, length: 0)
        )
        #expect(result == lastParaRange)
    }

    @Test func matchesFindsAllEightTokenTypesInOneDocument() {
        let text = """
        # Heading

        Some **bold** and *italic* and ~~struck~~ text with `code` and a [link](https://example.com).

        > A quote

        ```
        let x = 1
        ```
        """

        let foundTypes = Set(MarkdownHighlighter.matches(in: text).map(\.type))
        #expect(foundTypes == Set(MarkdownTokenType.allCases))
    }
}
