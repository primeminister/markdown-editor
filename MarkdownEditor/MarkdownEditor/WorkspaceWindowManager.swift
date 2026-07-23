//
//  WorkspaceWindowManager.swift
//  MarkdownEditor
//

import AppKit
import SwiftUI

/// One folder window's worth of state needed to reopen it on next launch: which tabs were open,
/// on which file, and which was active. Sidebar visibility deliberately isn't included here -- it's
/// already persisted separately per folder path, so recreating the controller for that path picks
/// the right value up on its own.
///
/// `folderBookmark` is a security-scoped bookmark for the folder -- this app is App-Sandboxed
/// (`ENABLE_APP_SANDBOX` in the project settings, contrary to what `docs/plan-m8.md` originally
/// assumed) with only `com.apple.security.files.user-selected.read-write`, so the read access
/// granted by the `NSOpenPanel` selection that opened this folder does not survive a relaunch --
/// a plain path string is not enough to read the file again in a new process. Resolving this
/// bookmark and calling `startAccessingSecurityScopedResource()` re-grants access to the whole
/// folder subtree, which is what actually lets `tabFilePaths` be read back. A workspace whose
/// bookmark couldn't be created (or fails to resolve later) is simply skipped on restore, same as
/// a folder that no longer exists.
struct RestorableWorkspace: Codable {
    let folderPath: String
    let folderBookmark: Data
    let tabFilePaths: [String]
    let activeTabFilePath: String?
}

private let workspaceRestorationStateKey = "WorkspaceRestorationState"

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
        registerController(folderURL: key).openInitialTab()
    }

    @discardableResult
    private func registerController(folderURL: URL) -> WorkspaceWindowController {
        let controller = WorkspaceWindowController(folderURL: folderURL)
        controller.onEmpty = { [weak self] in self?.controllers[folderURL] = nil }
        controllers[folderURL] = controller
        return controller
    }

    /// Toggles the sidebar of whichever workspace window is currently key, if any -- a harmless
    /// no-op when the key window belongs to a single-file `DocumentGroup` window instead.
    func toggleSidebarForKeyWindow() {
        guard let controller = controllers.values.first(where: { $0.window === NSApp.keyWindow }) else { return }
        controller.toggleSidebar()
    }

    /// Called from `AppDelegate.applicationWillTerminate`, alongside `flushAllPendingAutosaves()`.
    /// Each window's own currently-open folder is still within this process's sandbox access, so a
    /// fresh security-scoped bookmark can be created for it here regardless of whether the window
    /// itself was originally opened via `NSOpenPanel` or restored from a bookmark last launch.
    func snapshotForRestoration() {
        let snapshot = controllers.values.compactMap { controller -> RestorableWorkspace? in
            let folderURL = controller.folderModel.folderURL
            guard let bookmark = try? folderURL.bookmarkData(options: .withSecurityScope) else { return nil }
            return RestorableWorkspace(
                folderPath: folderURL.path,
                folderBookmark: bookmark,
                tabFilePaths: controller.tabs.compactMap { $0.selectedFileURL?.path },
                activeTabFilePath: controller.activeTab?.selectedFileURL?.path
            )
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: workspaceRestorationStateKey)
    }

    /// Called from `AppDelegate.applicationWillFinishLaunching`, before AppKit decides whether to
    /// open a blank "Untitled" document window. Returns whether at least one window was restored,
    /// so the caller can suppress that fallback.
    @discardableResult
    func restorePreviousSession() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: workspaceRestorationStateKey),
              let workspaces = try? JSONDecoder().decode([RestorableWorkspace].self, from: data) else {
            return false
        }

        var restoredAny = false
        for workspace in workspaces {
            var isStale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: workspace.folderBookmark,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            guard resolvedURL.startAccessingSecurityScopedResource() else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                resolvedURL.stopAccessingSecurityScopedResource()
                continue
            }

            let controller = registerController(folderURL: resolvedURL.standardizedFileURL)
            controller.retainSecurityScopedAccess(for: resolvedURL)
            controller.restoreTabs(filePaths: workspace.tabFilePaths, activeFilePath: workspace.activeTabFilePath)
            restoredAny = true
        }
        return restoredAny
    }
}
