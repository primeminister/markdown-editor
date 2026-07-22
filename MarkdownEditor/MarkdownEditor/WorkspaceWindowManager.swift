//
//  WorkspaceWindowManager.swift
//  MarkdownEditor
//

import AppKit
import SwiftUI

final class WorkspaceWindowManager {
    static let shared = WorkspaceWindowManager()
    private var tabGroups: [URL: WorkspaceTabGroup] = [:]

    private init() {}

    /// Called from `AppDelegate.applicationWillTerminate` so a pending debounced edit isn't
    /// dropped when the app quits within the debounce window, since these plain `NSWindow`s
    /// aren't guaranteed to receive `willCloseNotification` as part of app termination.
    func flushAllPendingAutosaves() {
        for group in tabGroups.values {
            group.flushAllPendingAutosaves()
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
        if let existing = tabGroups[key] {
            existing.bringToFront()
            return
        }

        let group = WorkspaceTabGroup(folderURL: key)
        group.onEmpty = { [weak self] in self?.tabGroups[key] = nil }
        tabGroups[key] = group
        group.openInitialTab()
    }
}
