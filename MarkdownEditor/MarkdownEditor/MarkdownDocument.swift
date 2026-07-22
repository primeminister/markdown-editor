//
//  MarkdownDocument.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static var markdownText: UTType {
        UTType(importedAs: "net.daringfireball.markdown")
    }
}

nonisolated struct MarkdownDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    static let readableContentTypes: [UTType] = [.markdownText]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decodeText(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: Self.encodeText(text))
    }

    static func decodeText(from data: Data) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return string
    }

    static func encodeText(_ text: String) -> Data {
        Data(text.utf8)
    }
}
