//
//  AppDelegate.swift
//  MarkdownEditor
//

import AppKit

/// Routes opens by URL kind: directories go to the new imperatively-managed workspace window;
/// regular files are forwarded to `NSDocumentController` so the existing `DocumentGroup`
/// single-file window keeps working exactly as before. Used both for Finder-initiated opens
/// (`application(_:open:)`) and for the launch-time picker below. Supplying this delegate means
/// `DocumentGroup`'s automatic open-URL handling no longer fires on its own for
/// `application(_:open:)`, so the plain-file case must be explicitly forwarded here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didRestoreSession = false
    /// Set whenever `application(_:open:)` fires with a nonempty URL list, including well after
    /// launch -- only the value at the one point `applicationDidFinishLaunching` reads it actually
    /// matters, to know whether Finder already told us what to open during launch (double-click /
    /// drag onto the app icon while not already running) so it doesn't also show its own launch
    /// picker on top of that.
    private var didOpenURLDuringLaunch = false
    /// Flips true once `applicationDidFinishLaunching` has made its one launch-time decision.
    /// `applicationShouldOpenUntitledFile` stays a hard `false` until then, regardless of call
    /// order, so AppKit's own built-in blank-document handling can never fire concurrently with
    /// (and duplicate) what `applicationDidFinishLaunching` already decided to do.
    private var hasHandledInitialLaunch = false

    /// Runs before AppKit decides whether to open a blank "Untitled" document window, so a
    /// restored session can suppress that via `applicationShouldOpenUntitledFile(_:)` below.
    func applicationWillFinishLaunching(_ notification: Notification) {
        didRestoreSession = WorkspaceWindowManager.shared.restorePreviousSession()
    }

    /// `DocumentGroup` has `.defaultLaunchBehavior(.suppressed)` (see `MarkdownEditorApp`) so it
    /// never auto-presents its own launch-time Open panel -- that panel is hard-restricted to
    /// `MarkdownDocument.readableContentTypes` with no supported way to also allow folders (a
    /// SwiftUI `DocumentGroup` limitation), which is what made picking a folder there leave "Open"
    /// permanently disabled. This drives launch presentation ourselves instead: nothing to do if a
    /// previous session was restored or Finder already opened something (see
    /// `didOpenURLDuringLaunch`), otherwise show the same combined file-or-folder picker used by
    /// the "Open…" menu command, falling back to a blank untitled document on cancel (what
    /// `DocumentGroup`'s suppressed automatic launch behavior would otherwise have done).
    func applicationDidFinishLaunching(_ notification: Notification) {
        defer { hasHandledInitialLaunch = true }
        guard !didRestoreSession, !didOpenURLDuringLaunch else { return }
        if let url = runOpenPanel() {
            openURL(url)
        } else {
            do {
                _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    // AppKit also calls this later in the app's life (e.g. a Dock-icon click while no windows are
    // open), not just at launch. Before `applicationDidFinishLaunching` has run its course this
    // always returns false -- see `hasHandledInitialLaunch` above -- and afterward it just falls
    // back to a blank document, same as clicking "New".
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        hasHandledInitialLaunch
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        didOpenURLDuringLaunch = true
        for url in urls {
            openURL(url)
        }
    }

    /// The "Open…" menu command (Cmd+O) -- the one place both files and folders can be picked,
    /// replacing `DocumentGroup`'s built-in file-only Open panel/shortcut (see the `.newItem`
    /// `CommandGroup` in `MarkdownEditorApp`). A cancel just does nothing, same as any other Open
    /// panel dismissal; `applicationDidFinishLaunching` above has its own cancel handling since it
    /// additionally needs a blank-document fallback.
    func presentOpenPanel() {
        guard let url = runOpenPanel() else { return }
        openURL(url)
    }

    private func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MarkdownDocument.readableContentTypes
        panel.prompt = "Open"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Routes a file-or-folder URL to the right place. Deliberately doesn't call
    /// `noteNewRecentDocumentURL` for folders: that would add them to the same list AppKit's
    /// native "Open Recent" menu reads (see `MarkdownEditorApp`), but that menu's default click
    /// handling only knows how to open `NSDocument`-backed files, so a folder entry there would
    /// just error instead of opening a workspace.
    func openURL(_ url: URL) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            WorkspaceWindowManager.shared.open(folder: url)
        } else {
            // Not documented as main-thread-only, so hop back explicitly rather than assume.
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    NSAlert(error: error).runModal()
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
