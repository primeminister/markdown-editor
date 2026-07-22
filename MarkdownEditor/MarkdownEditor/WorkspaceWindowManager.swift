//
//  WorkspaceWindowManager.swift
//  MarkdownEditor
//

import AppKit
import SwiftUI

@MainActor
final class WorkspaceWindowManager {
    static let shared = WorkspaceWindowManager()
    private var controllers: [URL: WorkspaceWindowController] = [:]

    private init() {}

    /// Called from `AppDelegate.applicationWillTerminate` so a pending debounced edit isn't
    /// dropped when the app quits within the debounce window, since these plain `NSWindow`s
    /// aren't guaranteed to receive `willCloseNotification` as part of app termination.
    func flushAllPendingAutosaves() {
        for controller in controllers.values {
            controller.flushAllPendingAutosaves()
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(folder: url)
    }

    func open(folder url: URL) {
        let key = url.standardizedFileURL
        if let existing = controllers[key] {
            existing.bringToFront()
            return
        }

        let controller = WorkspaceWindowController(folderURL: key)
        controller.onEmpty = { [weak self] in self?.controllers[key] = nil }
        controllers[key] = controller
        controller.openInitialTab()
    }
}
