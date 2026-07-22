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
    private let sidebarItem: NSSplitViewItem
    private static let railWidth: CGFloat = 36
    private static let defaultExpandedWidth: CGFloat = 220
    private static let expandedMinimumThickness: CGFloat = 180
    private var expandedWidth: CGFloat = defaultExpandedWidth

    init(folderModel: WorkspaceFolderModel, windowController: WorkspaceWindowController) {
        let sidebarHostingController = NSHostingController(
            rootView: WorkspaceSidebarView(folderModel: folderModel, windowController: windowController)
        )
        // Without this, NSHostingController derives the window's size (and resize limits) from the
        // hosted SwiftUI content's ideal/max size -- for the sidebar that's the List's intrinsic
        // size based on row count, capping the whole window to a size tied to the number of files.
        sidebarHostingController.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHostingController)
        sidebarItem.minimumThickness = Self.expandedMinimumThickness
        // Never truly collapses -- a collapsed NSSplitViewItem removes its content entirely, but
        // the sidebar must keep showing its toggle icon as a narrow rail so it can be re-expanded.
        sidebarItem.canCollapse = false
        self.sidebarItem = sidebarItem

        let detailHostingController = NSHostingController(rootView: WorkspaceDetailView(windowController: windowController))
        detailHostingController.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detailHostingController)
        detailItem.minimumThickness = 400

        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        let autosaveName = SplitViewAutosaveNaming.workspaceSidebarName(for: folderModel.folderURL.path)
        splitView.identifier = NSUserInterfaceItemIdentifier(autosaveName)
        splitView.autosaveName = autosaveName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Widths a boolean `isCollapsed` can't express here, since the rail must stay visible/clickable
    /// rather than disappear -- a tween between the sidebar's normal width and a fixed rail width,
    /// mirroring how `MainSplitViewController` animates the preview item's `isCollapsed`.
    func setSidebarVisible(_ visible: Bool, animated: Bool) {
        if !visible {
            expandedWidth = splitView.arrangedSubviews[0].frame.width
        }
        // minimumThickness must move with the target width, or the split view's own layout
        // enforcement would clamp the animated position straight back up past the rail width.
        sidebarItem.minimumThickness = visible ? Self.expandedMinimumThickness : Self.railWidth
        let target = visible ? expandedWidth : Self.railWidth
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = animated
            splitView.animator().setPosition(target, ofDividerAt: 0)
        }
    }
}
