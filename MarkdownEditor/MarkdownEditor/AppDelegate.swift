//
//  AppDelegate.swift
//  MarkdownEditor
//

import AppKit

/// Routes Finder-initiated opens by URL kind: directories go to the new imperatively-managed
/// workspace window; regular files are forwarded to `NSDocumentController` so the existing
/// `DocumentGroup` single-file window keeps working exactly as before. Supplying this delegate
/// means `DocumentGroup`'s automatic open-URL handling no longer fires on its own for
/// `application(_:open:)`, so the plain-file case must be explicitly forwarded here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didRestoreSession = false

    /// Runs before AppKit decides whether to open a blank "Untitled" document window, so a
    /// restored session can suppress that via `applicationShouldOpenUntitledFile(_:)` below.
    func applicationWillFinishLaunching(_ notification: Notification) {
        didRestoreSession = WorkspaceWindowManager.shared.restorePreviousSession()
    }

    // AppKit also calls this later in the app's life (e.g. a Dock-icon click while no windows are
    // open), not just at launch -- consume the flag on first read so a launch-time restore doesn't
    // permanently suppress the blank-document fallback for the rest of the session.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        defer { didRestoreSession = false }
        return !didRestoreSession
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue {
                WorkspaceWindowManager.shared.open(folder: url)
            } else {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    guard let error else { return }
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }

    // Workspace windows are plain `NSWindow`s, not `NSDocument`-backed ones `NSDocumentController`
    // walks and saves during quit -- without this, a debounced autosave still pending when the
    // user quits within the debounce window would be silently dropped.
    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceWindowManager.shared.flushAllPendingAutosaves()
        WorkspaceWindowManager.shared.snapshotForRestoration()
    }
}
