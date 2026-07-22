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

    @Test func matchesFindsAllSevenTokenTypesInOneDocument() {
        let text = """
        # Heading

        Some **bold** and *italic* text with `code` and a [link](https://example.com).

        > A quote

        ```
        let x = 1
        ```
        """

        let foundTypes = Set(MarkdownHighlighter.matches(in: text).map(\.type))
        #expect(foundTypes == Set(MarkdownTokenType.allCases))
    }
}
