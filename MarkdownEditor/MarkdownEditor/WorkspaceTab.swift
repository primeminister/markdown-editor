//
//  WorkspaceTab.swift
//  MarkdownEditor
//

import AppKit

/// One tab's worth of state within a `WorkspaceTabGroup`: its own window, its own file/text model,
/// and its own debounced autosave -- unlike M5, a folder can now have several of these open at once,
/// each potentially showing (and editing) a different file.
@MainActor
final class WorkspaceTab {
    let window: NSWindow
    let model: WorkspaceModel
    let autosave: WorkspaceAutosaveController
    var closeObserver: NSObjectProtocol?

    init(window: NSWindow, model: WorkspaceModel, autosave: WorkspaceAutosaveController) {
        self.window = window
        self.model = model
        self.autosave = autosave
    }
}
