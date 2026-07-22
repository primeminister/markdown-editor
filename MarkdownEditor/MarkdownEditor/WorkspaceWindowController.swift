//
//  WorkspaceWindowController.swift
//  MarkdownEditor
//

import AppKit
import Observation

/// Manages the single `NSWindow` for one open folder, plus every tab within it: the single-click-
/// reuse / double-click-or-edit-pins "preview tab" model. `previewTab` is the only piece of state
/// needed -- a tab is "permanent" purely by virtue of *not* being `previewTab`, so there's no
/// separate per-tab pinned flag to keep in sync.
@MainActor
@Observable
final class WorkspaceWindowController {
    let folderModel: WorkspaceFolderModel
    private let sidebarVisibilityKey: String
    private(set) var window: NSWindow!
    private(set) var tabs: [WorkspaceTab] = []
    var activeTab: WorkspaceTab?
    var isSidebarVisible: Bool
    private weak var previewTab: WorkspaceTab?
    private var splitViewController: WorkspaceSplitViewController!
    private var closeObserver: NSObjectProtocol?

    /// Called once the window closes, so `WorkspaceWindowManager` can drop this controller.
    var onEmpty: (() -> Void)?

    init(folderURL: URL) {
        self.folderModel = WorkspaceFolderModel(folderURL: folderURL)
        sidebarVisibilityKey = "WorkspaceSidebarVisible-\(folderURL.path)"
        isSidebarVisible = UserDefaults.standard.object(forKey: sidebarVisibilityKey) as? Bool ?? true
        setUpWindow(folderURL: folderURL)
        if !isSidebarVisible {
            splitViewController.setSidebarVisible(false, animated: false)
        }
    }

    private func setUpWindow(folderURL: URL) {
        let splitViewController = WorkspaceSplitViewController(folderModel: folderModel, windowController: self)
        self.splitViewController = splitViewController

        let window = NSWindow(contentViewController: splitViewController)
        window.title = folderURL.lastPathComponent
        window.setContentSize(NSSize(width: 900, height: 600))
        window.setFrameAutosaveName(SplitViewAutosaveNaming.windowName(for: folderURL.path))
        self.window = window

        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.flushAllPendingAutosaves()
                if let token = self.closeObserver {
                    NotificationCenter.default.removeObserver(token)
                }
                self.onEmpty?()
            }
        }
        closeObserver = token
    }

    /// The very first tab of a newly-opened folder (menu command or Finder open) -- nothing is
    /// selected yet, and since nothing else exists to pin, this tab becomes the initial preview tab.
    func openInitialTab() {
        let tab = makeTab()
        previewTab = tab
        activeTab = tab
        window.makeKeyAndOrderFront(nil)
        syncWindowTitle()
    }

    /// Single-click: reuse the current preview tab if there is one, otherwise mint a fresh one.
    /// Activates the target tab and brings the window forward *before* calling `selectFile` --
    /// `selectFile` can show a blocking `NSAlert` on a failed read, so the tab it's about to affect
    /// (and the window it's in) needs to already be the one on screen when that alert appears.
    func openPreview(_ url: URL) {
        let tab: WorkspaceTab
        if let previewTab {
            tab = previewTab
        } else {
            tab = makeTab()
            previewTab = tab
        }
        activeTab = tab
        window.makeKeyAndOrderFront(nil)
        tab.selectFile(url)
        syncWindowTitle()
    }

    /// Double-click: always a brand-new tab, permanent from birth since it's never made `previewTab`.
    func openPermanent(_ url: URL) {
        let tab = makeTab()
        activeTab = tab
        window.makeKeyAndOrderFront(nil)
        tab.selectFile(url)
        syncWindowTitle()
    }

    /// Tab-bar click: just switches which tab is shown, doesn't affect the preview/permanent state.
    func activate(_ tab: WorkspaceTab) {
        activeTab = tab
        syncWindowTitle()
    }

    /// Editing the preview tab's content promotes it to permanent -- the tab itself doesn't change,
    /// it just stops being reusable, so the next `openPreview` call has nothing to reuse and mints one.
    func notifyEdited(_ tab: WorkspaceTab) {
        guard previewTab === tab else { return }
        previewTab = nil
    }

    /// Tab close button: flush its autosave, remove it, and reassign `activeTab`/`previewTab` if
    /// this was either. Closing the last tab does not close the window -- it falls back to the
    /// same empty state shown before any file has ever been selected.
    func closeTab(_ tab: WorkspaceTab) {
        tab.autosave.flush()
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: index)

        if previewTab === tab {
            previewTab = nil
        }
        if activeTab === tab {
            activeTab = tabs[safe: index - 1] ?? tabs[safe: index]
            syncWindowTitle()
        }
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
        UserDefaults.standard.set(isSidebarVisible, forKey: sidebarVisibilityKey)
        splitViewController.setSidebarVisible(isSidebarVisible, animated: true)
    }

    /// Folder reopened (menu/Finder) while its window is already open -- just bring it forward.
    func bringToFront() {
        window.makeKeyAndOrderFront(nil)
    }

    /// Session restore on launch: one permanent tab per surviving file path (none becomes
    /// `previewTab`, matching the "freshly opened folder" behavior -- the first sidebar single-click
    /// after relaunch mints its own preview tab rather than reusing a restored one). Files that no
    /// longer exist (or were replaced by a directory of the same name) are silently skipped; if none
    /// survive, the window still opens in the existing empty state rather than erroring. Window is
    /// brought forward before `selectFile` runs, matching `openPreview`/`openPermanent`'s ordering --
    /// `selectFile` can show a blocking alert on a failed read, so the window needs to already be on
    /// screen when that happens.
    func restoreTabs(filePaths: [String], activeFilePath: String?) {
        window.makeKeyAndOrderFront(nil)
        for path in filePaths {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let tab = makeTab()
            tab.selectFile(URL(fileURLWithPath: path))
        }
        activeTab = tabs.first { $0.selectedFileURL?.path == activeFilePath } ?? tabs.first
        syncWindowTitle()
    }

    func flushAllPendingAutosaves() {
        for tab in tabs {
            tab.autosave.flush()
        }
    }

    @discardableResult
    private func makeTab() -> WorkspaceTab {
        let tab = WorkspaceTab(autosave: WorkspaceAutosaveController())
        tabs.append(tab)
        return tab
    }

    /// Keeps the real NSWindow's title (title bar, Window menu, Mission Control) in sync with
    /// whichever tab is active -- falls back to the folder name for a tab with nothing selected
    /// yet (or whose selection failed to load).
    private func syncWindowTitle() {
        window.title = activeTab?.selectedFileURL?.lastPathComponent ?? folderModel.folderURL.lastPathComponent
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
