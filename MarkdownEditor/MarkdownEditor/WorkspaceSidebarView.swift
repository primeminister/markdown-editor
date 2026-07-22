//
//  WorkspaceSidebarView.swift
//  MarkdownEditor
//

import SwiftUI

struct WorkspaceSidebarView: View {
    let folderModel: WorkspaceFolderModel
    let windowController: WorkspaceWindowController

    var body: some View {
        // `.task` sits on this stable outer `Group`, not inside the `if`/`else` below -- attaching
        // it to either branch directly would re-fire (and re-walk the whole tree) every time
        // toggling the sidebar swaps which branch is present, since that changes view identity.
        Group {
            if windowController.isSidebarVisible {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        toggleButton
                    }
                    .padding(6)
                    fileList
                }
                .navigationTitle(folderModel.folderURL.lastPathComponent)
            } else {
                VStack {
                    toggleButton
                        .padding(.top, 6)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            }
        }
        .task { await folderModel.loadTree() }
    }

    @ViewBuilder
    private var fileList: some View {
        if let root = folderModel.root {
            List(root.children ?? [], children: \.children) { node in
                FileRow(
                    node: node,
                    isSelected: node.url == windowController.activeTab?.selectedFileURL,
                    onSingleClick: {
                        guard node.isMarkdown else { return }
                        windowController.openPreview(node.url)
                    },
                    onDoubleClick: {
                        guard node.isMarkdown else { return }
                        windowController.openPermanent(node.url)
                    }
                )
            }
        } else {
            ProgressView()
        }
    }

    private var toggleButton: some View {
        Button {
            windowController.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.leading")
        }
        .buttonStyle(.borderless)
        .help(windowController.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
    }
}
