//
//  WorkspaceWindowManager.swift
//  MarkdownEditor
//

import AppKit
import SwiftUI

final class WorkspaceWindowManager {
    static let shared = WorkspaceWindowManager()
    private var windows: [URL: NSWindow] = [:]
    private var autosaveControllers: [URL: WorkspaceAutosaveController] = [:]
    private var observerTokens: [URL: NSObjectProtocol] = [:]

    private init() {}

    /// Called from `AppDelegate.applicationWillTerminate` so a pending debounced edit isn't
    /// dropped when the app quits within the debounce window, since these plain `NSWindow`s
    /// aren't guaranteed to receive `willCloseNotification` as part of app termination.
    func flushAllPendingAutosaves() {
        for autosave in autosaveControllers.values {
            autosave.flush()
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
        if let existing = windows[key] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let autosave = WorkspaceAutosaveController()
        let hostingController = NSHostingController(rootView: WorkspaceView(folderURL: key, autosave: autosave))
        let window = NSWindow(contentViewController: hostingController)
        window.title = key.lastPathComponent
        window.setContentSize(NSSize(width: 900, height: 600))
        // Applied here (covers the window before any file is selected) and again, harmlessly,
        // by MainSplitViewController once a file's SplitView first appears -- both derive the
        // identical name from the shared SplitViewAutosaveNaming helper. See docs/plan-m5.md.
        window.setFrameAutosaveName(SplitViewAutosaveNaming.windowName(for: key.path))
        windows[key] = window
        autosaveControllers[key] = autosave

        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                autosave.flush()
                self?.windows[key] = nil
                self?.autosaveControllers[key] = nil
                if let token = self?.observerTokens[key] {
                    NotificationCenter.default.removeObserver(token)
                }
                self?.observerTokens[key] = nil
            }
        }
        observerTokens[key] = token

        window.makeKeyAndOrderFront(nil)
    }
}
