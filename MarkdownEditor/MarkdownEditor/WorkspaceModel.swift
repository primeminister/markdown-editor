//
//  WorkspaceModel.swift
//  MarkdownEditor
//

import AppKit
import Observation

@MainActor
@Observable
final class WorkspaceModel {
    let folderURL: URL
    let autosave: WorkspaceAutosaveController
    var root: FileNode?
    var selectedFileURL: URL?
    var text: String = ""
    var loadedText: String = ""

    init(folderURL: URL, autosave: WorkspaceAutosaveController) {
        self.folderURL = folderURL
        self.autosave = autosave
    }

    func loadTree() async {
        let url = folderURL
        // Recursive directory walk can be slow for large folders -- build it off the main thread
        // so opening a big folder doesn't hang the UI before the window even shows.
        root = await Task.detached(priority: .userInitiated) {
            FileNode.build(from: url)
        }.value
    }

    func selectFile(_ url: URL) {
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
