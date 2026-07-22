//
//  WorkspaceSplitViewController.swift
//  MarkdownEditor
//

import AppKit
import SwiftUI

/// Hosts the folder sidebar + editor/preview detail as a real `NSSplitView` (rather than SwiftUI's
/// `NavigationSplitView`) so the sidebar width persists via `autosaveName` -- SwiftUI's
/// `NavigationSplitView` has no built-in mechanism for that, and these workspace windows are plain
/// `NSWindow`s outside SwiftUI's own Scene-based state restoration.
final class WorkspaceSplitViewController: NSSplitViewController {
    init(model: WorkspaceModel) {
        let sidebarHostingController = NSHostingController(rootView: WorkspaceSidebarView(model: model))
        // Without this, NSHostingController derives the window's size (and resize limits) from the
        // hosted SwiftUI content's ideal/max size -- for the sidebar that's the List's intrinsic
        // size based on row count, capping the whole window to a size tied to the number of files.
        sidebarHostingController.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHostingController)
        sidebarItem.minimumThickness = 180
        sidebarItem.canCollapse = false

        let detailHostingController = NSHostingController(rootView: WorkspaceDetailView(model: model))
        detailHostingController.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detailHostingController)
        detailItem.minimumThickness = 400

        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        let autosaveName = SplitViewAutosaveNaming.workspaceSidebarName(for: model.folderURL.path)
        splitView.identifier = NSUserInterfaceItemIdentifier(autosaveName)
        splitView.autosaveName = autosaveName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
