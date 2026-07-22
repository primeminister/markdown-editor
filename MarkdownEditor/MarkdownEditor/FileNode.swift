//
//  FileNode.swift
//  MarkdownEditor
//

import Foundation

nonisolated struct FileNode: Identifiable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let isMarkdown: Bool
    var children: [FileNode]?

    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    init(url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.isMarkdown = !isDirectory && Self.markdownExtensions.contains(url.pathExtension.lowercased())
        self.children = children
    }

    static func build(from url: URL) -> FileNode {
        FileNode(url: url, isDirectory: true, children: childNodes(of: url))
    }

    private static func childNodes(of directoryURL: URL) -> [FileNode] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let nodes = contents.map { childURL -> FileNode in
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isDir
                ? FileNode(url: childURL, isDirectory: true, children: childNodes(of: childURL))
                : FileNode(url: childURL, isDirectory: false)
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
