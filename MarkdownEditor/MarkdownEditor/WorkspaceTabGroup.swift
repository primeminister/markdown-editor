//
//  WorkspaceTabGroup.swift
//  MarkdownEditor
//

import AppKit

/// Manages every open tab (native `NSWindow`) for one folder, plus the single-click-reuse /
/// double-click-or-edit-pins "preview tab" model: `previewTab` is the only piece of state needed --
/// a tab is "permanent" purely by virtue of *not* being `previewTab`, so there's no separate
/// per-tab pinned flag to keep in sync.
@MainActor
final class WorkspaceTabGroup {
    let folderURL: URL
    private(set) var tabs: [WorkspaceTab] = []
    private weak var previewTab: WorkspaceTab?

    /// Called once every tab in the group has closed, so `WorkspaceWindowManager` can drop this group.
    var onEmpty: (() -> Void)?

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    /// The very first tab of a newly-opened folder (menu command or Finder open) -- nothing is
    /// selected yet, and since nothing else exists to pin, this tab becomes the initial preview tab.
    func openInitialTab() {
        let tab = makeTab(selecting: nil)
        previewTab = tab
    }

    /// Single-click: reuse the current preview tab if there is one, otherwise mint a fresh one.
    func openPreview(_ url: URL) {
        if let previewTab {
            // Bring the target tab forward before loading -- otherwise a failed read pops
            // `selectFile`'s blocking NSAlert while the *previously* frontmost tab is still key,
            // and the actually-affected tab only appears after the alert is dismissed.
            previewTab.window.makeKeyAndOrderFront(nil)
            previewTab.model.selectFile(url)
            syncTitle(previewTab)
        } else {
            previewTab = makeTab(selecting: url)
        }
    }

    /// Double-click: always a brand-new tab, permanent from birth since it's never made `previewTab`.
    func openPermanent(_ url: URL) {
        makeTab(selecting: url)
    }

    /// Editing the preview tab's content promotes it to permanent -- the tab itself doesn't change,
    /// it just stops being reusable, so the next `openPreview` call has nothing to reuse and mints one.
    func notifyEdited(_ model: WorkspaceModel) {
        guard previewTab?.model === model else { return }
        previewTab = nil
    }

    /// Folder reopened (menu/Finder) while its tab group is already open -- surface the preview tab,
    /// or just the first tab if every tab in the group has been pinned.
    func bringToFront() {
        (previewTab ?? tabs.first)?.window.makeKeyAndOrderFront(nil)
    }

    func flushAllPendingAutosaves() {
        for tab in tabs {
            tab.autosave.flush()
        }
    }

    @discardableResult
    private func makeTab(selecting url: URL?) -> WorkspaceTab {
        let autosave = WorkspaceAutosaveController()
        let model = WorkspaceModel(folderURL: folderURL, autosave: autosave)

        let splitViewController = WorkspaceSplitViewController(model: model, tabGroup: self)
        let window = NSWindow(contentViewController: splitViewController)
        window.title = folderURL.lastPathComponent
        window.setContentSize(NSSize(width: 900, height: 600))
        // Explicit identifier so macOS's *automatic* tabbing heuristics never merge a different
        // folder's workspace window (or a DocumentGroup single-file window) into this tab group by
        // coincidence -- the actual grouping below is done explicitly via `addTabbedWindow`.
        window.tabbingIdentifier = folderURL.path
        window.setFrameAutosaveName(SplitViewAutosaveNaming.windowName(for: folderURL.path))

        let tab = WorkspaceTab(window: window, model: model, autosave: autosave)

        if let firstTab = tabs.first {
            firstTab.window.addTabbedWindow(window, ordered: .above)
        }
        tabs.append(tab)

        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak tab] _ in
            MainActor.assumeIsolated {
                guard let self, let tab else { return }
                self.closeTab(tab)
            }
        }
        tab.closeObserver = token

        // Bring the tab forward before loading -- see the matching comment in `openPreview`.
        window.makeKeyAndOrderFront(nil)
        if let url {
            model.selectFile(url)
        }
        syncTitle(tab)
        return tab
    }

    /// Keeps the native tab bar's label in sync with the file actually shown -- falls back to the
    /// folder name for a tab with nothing selected yet (or whose selection failed to load).
    private func syncTitle(_ tab: WorkspaceTab) {
        tab.window.title = tab.model.selectedFileURL?.lastPathComponent ?? folderURL.lastPathComponent
    }

    private func closeTab(_ tab: WorkspaceTab) {
        tab.autosave.flush()
        tabs.removeAll { $0 === tab }
        if previewTab === tab {
            previewTab = nil
        }
        if let token = tab.closeObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if tabs.isEmpty {
            onEmpty?()
        }
    }
}
