//
//  WorkspaceSidebarView.swift
//  MarkdownEditor
//

import SwiftUI

struct WorkspaceSidebarView: View {
    let model: WorkspaceModel

    var body: some View {
        Group {
            if let root = model.root {
                List(root.children ?? [], children: \.children) { node in
                    FileRow(node: node, isSelected: node.url == model.selectedFileURL)
                        .onTapGesture {
                            guard node.isMarkdown else { return }
                            model.selectFile(node.url)
                        }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.folderURL.lastPathComponent)
        .task { await model.loadTree() }
    }
}
