//
//  MarkdownFormatterTests.swift
//  MarkdownEditorTests
//
//  Created by Charlie van de Kerkhof on 23/08/2026.
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

struct MarkdownFormatterTests {

    // MARK: - Heading

    @Test func heading1AppliesToUnformattedLineWithSelection() {
        let text = "Some text"
        let selection = nsRange(of: "Some", in: text)

        let edit = MarkdownFormatter.apply(.heading1, to: text, selection: selection)

        #expect(edit.replacementRange == NSRange(location: 0, length: (text as NSString).length))
        #expect(edit.replacementText == "# Some text")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 4))
    }

    @Test func heading1AppliesToCurrentLineWithEmptySelection() {
        let text = "Line one"
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.heading1, to: text, selection: selection)

        #expect(edit.replacementText == "# Line one")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 0))
    }

    @Test func headingToggleOffSameLevelStripsPrefix() {
        let text = "# Title"
        let selection = NSRange(location: 2, length: 0)

        let edit = MarkdownFormatter.apply(.heading1, to: text, selection: selection)

        #expect(edit.replacementRange == NSRange(location: 0, length: (text as NSString).length))
        #expect(edit.replacementText == "Title")
    }

    @Test func headingLevelSwitchReplacesPrefixRatherThanStacking() {
        let text = "# Title"
        let selection = NSRange(location: 2, length: 0)

        let edit = MarkdownFormatter.apply(.heading2, to: text, selection: selection)

        #expect(edit.replacementText == "## Title")
    }

    @Test func heading3TogglesOnIndependentlyOfOtherLevels() {
        let text = "Title"
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.heading3, to: text, selection: selection)

        #expect(edit.replacementText == "### Title")
    }

    // MARK: - Bold

    @Test func boldAppliesToUnformattedSelection() {
        let text = "Some bold text"
        let selection = nsRange(of: "bold", in: text)

        let edit = MarkdownFormatter.apply(.bold, to: text, selection: selection)

        #expect(edit.replacementRange == selection)
        #expect(edit.replacementText == "**bold**")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 4))
    }

    @Test func boldInsertsEmptyMarkersWithCursorBetweenOnEmptySelection() {
        let text = ""
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.bold, to: text, selection: selection)

        #expect(edit.replacementText == "****")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 0))
    }

    @Test func boldDoesNotToggleOffWhenCaretIsAdjacentButOutsideExistingBold() {
        let text = "Hi **bold**!"
        let boldToken = nsRange(of: "**bold**", in: text)
        let caretAfter = NSRange(location: NSMaxRange(boldToken), length: 0)

        let edit = MarkdownFormatter.apply(.bold, to: text, selection: caretAfter)

        // The caret sits right after the closing markers, not inside the bold span -- toggling
        // here should insert a fresh empty marker pair at the caret, not strip the adjacent bold.
        #expect(edit.replacementRange == caretAfter)
        #expect(edit.replacementText == "****")
    }

    @Test func boldTogglesOffWhenAlreadyFormatted() {
        let text = "**bold**"
        let selection = nsRange(of: "bold", in: text)

        let edit = MarkdownFormatter.apply(.bold, to: text, selection: selection)

        #expect(edit.replacementRange == NSRange(location: 0, length: (text as NSString).length))
        #expect(edit.replacementText == "bold")
        #expect(edit.selectionInReplacement == NSRange(location: 0, length: 4))
    }

    // MARK: - Italic

    @Test func italicAppliesToUnformattedSelection() {
        let text = "Some italic text"
        let selection = nsRange(of: "italic", in: text)

        let edit = MarkdownFormatter.apply(.italic, to: text, selection: selection)

        #expect(edit.replacementText == "*italic*")
        #expect(edit.selectionInReplacement == NSRange(location: 1, length: 6))
    }

    @Test func italicInsertsEmptyMarkersWithCursorBetweenOnEmptySelection() {
        let text = ""
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.italic, to: text, selection: selection)

        #expect(edit.replacementText == "**")
        #expect(edit.selectionInReplacement == NSRange(location: 1, length: 0))
    }

    @Test func italicTogglesOffWhenAlreadyFormatted() {
        let text = "*italic*"
        let selection = nsRange(of: "italic", in: text)

        let edit = MarkdownFormatter.apply(.italic, to: text, selection: selection)

        #expect(edit.replacementText == "italic")
        #expect(edit.selectionInReplacement == NSRange(location: 0, length: 6))
    }

    @Test func italicDoesNotFalsePositiveInsideBoldSpan() {
        let text = "**bold**"
        // Cursor between "bo" and "ld" -- no single-asterisk (italic) token exists here, since
        // both asterisk pairs belong to the bold markers. Must insert new italic markers rather
        // than mistaking this for "already italic" and stripping the surrounding bold.
        let selection = NSRange(location: 4, length: 0)

        let edit = MarkdownFormatter.apply(.italic, to: text, selection: selection)

        #expect(edit.replacementRange == selection)
        #expect(edit.replacementText == "**")
        #expect(edit.selectionInReplacement == NSRange(location: 1, length: 0))
    }

    // MARK: - Strikethrough

    @Test func strikethroughAppliesToUnformattedSelection() {
        let text = "Some struck text"
        let selection = nsRange(of: "struck", in: text)

        let edit = MarkdownFormatter.apply(.strikethrough, to: text, selection: selection)

        #expect(edit.replacementText == "~~struck~~")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 6))
    }

    @Test func strikethroughInsertsEmptyMarkersWithCursorBetweenOnEmptySelection() {
        let text = ""
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.strikethrough, to: text, selection: selection)

        #expect(edit.replacementText == "~~~~")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 0))
    }

    @Test func strikethroughTogglesOffWhenAlreadyFormatted() {
        let text = "~~struck~~"
        let selection = nsRange(of: "struck", in: text)

        let edit = MarkdownFormatter.apply(.strikethrough, to: text, selection: selection)

        #expect(edit.replacementText == "struck")
        #expect(edit.selectionInReplacement == NSRange(location: 0, length: 6))
    }

    // MARK: - Inline code

    @Test func inlineCodeAppliesToUnformattedSelection() {
        let text = "Use code here"
        let selection = nsRange(of: "code", in: text)

        let edit = MarkdownFormatter.apply(.inlineCode, to: text, selection: selection)

        #expect(edit.replacementText == "`code`")
        #expect(edit.selectionInReplacement == NSRange(location: 1, length: 4))
    }

    @Test func inlineCodeInsertsEmptyMarkersWithCursorBetweenOnEmptySelection() {
        let text = ""
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.inlineCode, to: text, selection: selection)

        #expect(edit.replacementText == "``")
        #expect(edit.selectionInReplacement == NSRange(location: 1, length: 0))
    }

    @Test func inlineCodeTogglesOffWhenAlreadyFormatted() {
        let text = "`code`"
        let selection = nsRange(of: "code", in: text)

        let edit = MarkdownFormatter.apply(.inlineCode, to: text, selection: selection)

        #expect(edit.replacementText == "code")
        #expect(edit.selectionInReplacement == NSRange(location: 0, length: 4))
    }

    // MARK: - Fenced code

    @Test func fencedCodeAppliesExpandingPartialLineSelectionToFullLine() {
        let text = "before\ncode line\nafter"
        let selection = nsRange(of: "code", in: text)

        let edit = MarkdownFormatter.apply(.fencedCode, to: text, selection: selection)

        #expect(edit.replacementRange == nsRange(of: "code line\n", in: text))
        #expect(edit.replacementText == "```\ncode line\n```\n")
        #expect(edit.selectionInReplacement == NSRange(location: 4, length: 4))
    }

    @Test func fencedCodeInsertsEmptyFenceWithCursorBetweenOnEmptySelection() {
        let text = ""
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.fencedCode, to: text, selection: selection)

        #expect(edit.replacementText == "```\n\n```")
        #expect(edit.selectionInReplacement == NSRange(location: 4, length: 0))
    }

    @Test func fencedCodeTogglesOffStrippingFenceMarkers() {
        let text = "```\ncode\n```"
        let selection = nsRange(of: "code", in: text)

        let edit = MarkdownFormatter.apply(.fencedCode, to: text, selection: selection)

        #expect(edit.replacementRange == NSRange(location: 0, length: (text as NSString).length))
        #expect(edit.replacementText == "code")
        #expect(edit.selectionInReplacement == NSRange(location: 0, length: 4))
    }

    @Test func fencedCodeTogglesOffSingleLineFenceWithoutNewlines() {
        // Degenerate case: opening and closing markers on the same line, no newlines at all.
        let text = "```code```"
        let selection = nsRange(of: "code", in: text)

        let edit = MarkdownFormatter.apply(.fencedCode, to: text, selection: selection)

        #expect(edit.replacementText == "code")
    }

    // MARK: - Blockquote

    @Test func blockquoteAppliesToUnformattedLineWithSelection() {
        let text = "Some text"
        let selection = nsRange(of: "Some", in: text)

        let edit = MarkdownFormatter.apply(.blockquote, to: text, selection: selection)

        #expect(edit.replacementText == "> Some text")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 4))
    }

    @Test func blockquoteAppliesToCurrentLineWithEmptySelection() {
        let text = "Line one"
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.blockquote, to: text, selection: selection)

        #expect(edit.replacementText == "> Line one")
        #expect(edit.selectionInReplacement == NSRange(location: 2, length: 0))
    }

    @Test func blockquoteTogglesOffWhenAlreadyFormatted() {
        let text = "> Quoted"
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.blockquote, to: text, selection: selection)

        #expect(edit.replacementText == "Quoted")
    }

    @Test func blockquoteMultiLineToggleCoversEveryTouchedLine() {
        let text = "Line one\nLine two"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let edit = MarkdownFormatter.apply(.blockquote, to: text, selection: selection)

        #expect(edit.replacementText == "> Line one\n> Line two")
    }

    @Test func blockquoteMultiLineToggleOffCoversEveryTouchedLine() {
        let text = "> Line one\n> Line two"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let edit = MarkdownFormatter.apply(.blockquote, to: text, selection: selection)

        #expect(edit.replacementText == "Line one\nLine two")
    }

    // MARK: - Link

    @Test func linkAppliesToUnformattedSelection() {
        let text = "See docs here"
        let selection = nsRange(of: "docs", in: text)

        let edit = MarkdownFormatter.apply(.link, to: text, selection: selection)

        #expect(edit.replacementText == "[docs]()")
        #expect(edit.selectionInReplacement == NSRange(location: 7, length: 0))
    }

    @Test func linkInsertsEmptyMarkersWithCursorBetweenParensWhenNoClipboardURL() {
        let text = ""
        let selection = NSRange(location: 0, length: 0)

        let edit = MarkdownFormatter.apply(.link, to: text, selection: selection, clipboardURL: nil)

        #expect(edit.replacementText == "[]()")
        #expect(edit.selectionInReplacement == NSRange(location: 3, length: 0))
    }

    @Test func linkPreSelectsClipboardURLWhenPresent() {
        let text = ""
        let selection = NSRange(location: 0, length: 0)
        let clipboardURL = "https://example.com"

        let edit = MarkdownFormatter.apply(.link, to: text, selection: selection, clipboardURL: clipboardURL)

        #expect(edit.replacementText == "[](https://example.com)")
        #expect(edit.selectionInReplacement == NSRange(location: 3, length: (clipboardURL as NSString).length))
    }

    @Test func linkTogglesOffToJustTheLabelWhenAlreadyFormatted() {
        let text = "[docs](https://example.com)"
        let selection = nsRange(of: "docs", in: text)

        let edit = MarkdownFormatter.apply(.link, to: text, selection: selection)

        #expect(edit.replacementRange == NSRange(location: 0, length: (text as NSString).length))
        #expect(edit.replacementText == "[docs]")
        #expect(edit.selectionInReplacement == NSRange(location: 1, length: 4))
    }
}
