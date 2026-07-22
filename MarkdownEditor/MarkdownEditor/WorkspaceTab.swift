//
//  WorkspaceTab.swift
//  MarkdownEditor
//

import AppKit
import Observation

/// One tab's worth of state within a `WorkspaceWindowController`: its own selected file, text
/// buffer, and debounced autosave -- several of these can exist per window, each potentially
/// showing (and editing) a different file, sharing the window's one `WorkspaceFolderModel` tree.
@MainActor
@Observable
final class WorkspaceTab {
    let id = UUID()
    let autosave: WorkspaceAutosaveController
    var selectedFileURL: URL?
    var text: String = ""
    var loadedText: String = ""

    init(autosave: WorkspaceAutosaveController) {
        self.autosave = autosave
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
            alert.messageText = "Couldn't open \"\(url.lastPathComponent)\""
        }
    }
}
