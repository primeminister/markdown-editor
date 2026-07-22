//
//  WorkspaceSidebarView.swift
//  MarkdownEditor
//

import SwiftUI

struct WorkspaceSidebarView: View {
    let model: WorkspaceModel
    let tabGroup: WorkspaceTabGroup

    var body: some View {
        Group {
            if let root = model.root {
                List(root.children ?? [], children: \.children) { node in
                    FileRow(
                        node: node,
                        isSelected: node.url == model.selectedFileURL,
                        onSingleClick: {
                            guard node.isMarkdown else { return }
                            tabGroup.openPreview(node.url)
                        },
                        onDoubleClick: {
                            guard node.isMarkdown else { return }
                            tabGroup.openPermanent(node.url)
                        }
                    )
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.folderURL.lastPathComponent)
        .task { await model.loadTree() }
    }
}
