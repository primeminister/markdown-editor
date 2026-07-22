//
//  FileRow.swift
//  MarkdownEditor
//

import SwiftUI

/// Directories and non-markdown files render identically de-emphasized and inert -- directories
/// are purely navigational (List's native disclosure triangle handles expand/collapse; there's no
/// separate "open this folder" action), and only `.md`/`.markdown` files are real content to load.
struct FileRow: View {
    let node: FileNode
    let isSelected: Bool

    var body: some View {
        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
            .foregroundStyle(node.isMarkdown ? .primary : .tertiary)
            .fontWeight(isSelected ? .semibold : .regular)
            .contentShape(Rectangle())
    }
}
