//
//  FileTreeTests.swift
//  MarkdownEditorTests
//

import Testing
import Foundation
@testable import MarkdownEditor

struct FileTreeTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func directoriesSortBeforeFiles() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent("b.md").path, contents: nil)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a-folder"), withIntermediateDirectories: true)

        let node = FileNode.build(from: root)

        #expect(node.children?.first?.isDirectory == true)
    }

    @Test func hiddenFilesAreExcluded() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent(".hidden.md").path, contents: nil)
        FileManager.default.createFile(atPath: root.appendingPathComponent("visible.md").path, contents: nil)

        let node = FileNode.build(from: root)

        #expect(node.children?.count == 1)
        #expect(node.children?.first?.name == "visible.md")
    }

    @Test func markdownExtensionsAreFlagged() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent("notes.md").path, contents: nil)
        FileManager.default.createFile(atPath: root.appendingPathComponent("readme.txt").path, contents: nil)

        let node = FileNode.build(from: root)

        #expect(node.children?.first { $0.name == "notes.md" }?.isMarkdown == true)
        #expect(node.children?.first { $0.name == "readme.txt" }?.isMarkdown == false)
    }

    @Test func nestedSubfoldersRecurse() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sub.appendingPathComponent("deep.md").path, contents: nil)

        let node = FileNode.build(from: root)

        #expect(node.children?.first { $0.name == "sub" }?.children?.first?.name == "deep.md")
    }
}
