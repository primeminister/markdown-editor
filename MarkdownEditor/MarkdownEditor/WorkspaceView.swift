//
//  WorkspaceView.swift
//  MarkdownEditor
//

import AppKit
import SwiftUI

struct WorkspaceView: View {
    let folderURL: URL
    let autosave: WorkspaceAutosaveController

    @State private var root: FileNode?
    @State private var selectedFileURL: URL?
    @State private var text: String = ""
    @State private var loadedText: String = ""
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true

    init(folderURL: URL, autosave: WorkspaceAutosaveController) {
        self.folderURL = folderURL
        self.autosave = autosave
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if let root {
                    List(root.children ?? [], children: \.children) { node in
                        FileRow(node: node, isSelected: node.url == selectedFileURL)
                            .onTapGesture {
                                guard node.isMarkdown else { return }
                                selectFile(node.url)
                            }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(folderURL.lastPathComponent)
            .task {
                // Recursive directory walk can be slow for large folders -- build it off the main
                // thread so opening a big folder doesn't hang the UI before the window even shows.
                root = await Task.detached(priority: .userInitiated) {
                    FileNode.build(from: folderURL)
                }.value
            }
        } detail: {
            if selectedFileURL != nil {
                // Stable per-workspace-window identifier (the folder, not the selected file) --
                // MainSplitViewController bakes this in at first appearance and never re-reads it,
                // so this must not vary per file. See docs/plan-m5.md.
                SplitView(text: $text, isPreviewVisible: $isPreviewVisible, autosaveIdentifier: folderURL.path)
                    .onChange(of: text) { _, newValue in
                        guard let url = selectedFileURL, newValue != loadedText else { return }
                        autosave.schedule(text: newValue, to: url)
                    }
            } else {
                ContentUnavailableView("Select a Markdown File", systemImage: "doc.text")
            }
        }
    }

    private func selectFile(_ url: URL) {
        guard url != selectedFileURL else { return }
        autosave.flush()
        do {
            let data = try Data(contentsOf: url)
            let loaded = try MarkdownDocument.decodeText(from: data)
            loadedText = loaded
            text = loaded
            selectedFileURL = url
        } catch {
            // Read failed (permissions, race with external delete) -- leave the previously shown file untouched.
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't Open \"\(url.lastPathComponent)\""
            alert.runModal()
        }
    }
}
