//
//  FileRow.swift
//  MarkdownEditor
//

import AppKit
import SwiftUI

/// Directories and non-markdown files render identically de-emphasized and inert -- directories
/// are purely navigational (List's native disclosure triangle handles expand/collapse; there's no
/// separate "open this folder" action), and only `.md`/`.markdown` files are real content to load.
struct FileRow: View {
    let node: FileNode
    let isSelected: Bool
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    // Chaining `.onTapGesture(count: 2)` + `.onTapGesture(count: 1)` on the same view relies on
    // SwiftUI making the lower count wait for the higher one to fail -- that isn't a documented
    // guarantee, and in practice both fired for one double-click on this macOS List row (hosted via
    // NSHostingController), so a double-click briefly loaded the file into the preview tab *and*
    // opened a permanent tab for it. Disambiguating manually instead: a single click schedules its
    // action after the system's actual double-click window; a second click within that window
    // cancels the pending single-click action before it runs.
    @State private var pendingSingleClick: DispatchWorkItem?

    var body: some View {
        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
            .foregroundStyle(node.isMarkdown ? .primary : .tertiary)
            .fontWeight(isSelected ? .semibold : .regular)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
                onDoubleClick()
            }
            .onTapGesture(count: 1) {
                let workItem = DispatchWorkItem { onSingleClick() }
                pendingSingleClick = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
            }
    }
}
