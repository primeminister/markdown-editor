//
//  MarkdownEditorTests.swift
//  MarkdownEditorTests
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import MarkdownEditor

struct MarkdownDocumentTests {

    @Test func defaultTextIsEmpty() {
        #expect(MarkdownDocument().text == "")
    }

    @Test func encodeDecodeRoundTripsText() throws {
        let original = "# Title\n\nSome *markdown* text.\n"
        let data = MarkdownDocument.encodeText(original)
        let decoded = try MarkdownDocument.decodeText(from: data)

        #expect(decoded == original)
    }

    @Test func decodingInvalidUTF8Throws() {
        let invalidData = Data([0xFF, 0xFE, 0xFD])

        #expect(throws: CocoaError.self) {
            try MarkdownDocument.decodeText(from: invalidData)
        }
    }

    @Test func readableContentTypesIncludesMarkdown() {
        #expect(MarkdownDocument.readableContentTypes.contains(.markdownText))
    }
}
