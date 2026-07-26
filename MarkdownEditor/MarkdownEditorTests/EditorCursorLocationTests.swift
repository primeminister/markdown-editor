//
//  EditorCursorLocationTests.swift
//  MarkdownEditorTests
//

import Foundation
import Testing
@testable import MarkdownEditor

struct EditorCursorLocationTests {
    @Test func startOfFileIsLineOne() {
        #expect(EditorCursorLocation.lineNumber(in: "abc\ndef", at: 0) == 1)
    }

    @Test func midLineStaysOnSameLine() {
        #expect(EditorCursorLocation.lineNumber(in: "abc\ndef", at: 2) == 1)
    }

    @Test func positionRightBeforeNewlineIsStillOnThatLine() {
        #expect(EditorCursorLocation.lineNumber(in: "abc\ndef", at: 3) == 1)
    }

    @Test func positionRightAfterNewlineIsNextLine() {
        #expect(EditorCursorLocation.lineNumber(in: "abc\ndef", at: 4) == 2)
    }

    @Test func lastLineWithoutTrailingNewline() {
        let text = "one\ntwo\nthree"
        #expect(EditorCursorLocation.lineNumber(in: text, at: (text as NSString).length) == 3)
    }

    @Test func trailingNewlineCountsABlankFinalLine() {
        let text = "one\ntwo\n"
        #expect(EditorCursorLocation.lineNumber(in: text, at: (text as NSString).length) == 3)
    }

    @Test func emptyStringIsLineOne() {
        #expect(EditorCursorLocation.lineNumber(in: "", at: 0) == 1)
    }

    @Test func indexBeyondTextLengthClampsToEnd() {
        let text = "one\ntwo"
        #expect(EditorCursorLocation.lineNumber(in: text, at: 999) == 2)
    }

    @Test func negativeIndexClampsToStart() {
        #expect(EditorCursorLocation.lineNumber(in: "one\ntwo", at: -5) == 1)
    }
}
