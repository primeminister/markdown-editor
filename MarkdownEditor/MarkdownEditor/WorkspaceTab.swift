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
    /// Preserves this tab's preview scroll-follow position across tab switches (`MainSplitViewController`
    /// stays alive across switches within one window, see `WorkspaceDetailView`). Reset to 1 whenever a
    /// new file is loaded into this tab, since a stale line number from the previous file is meaningless.
    var cursorLine: Int = 1

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
            cursorLine = 1
        } catch {
            // Read failed (permissions, race with external delete) -- leave the previously shown file untouched.
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't open \"\(url.lastPathComponent)\""
        }
    }
}
