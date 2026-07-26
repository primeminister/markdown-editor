//
//  WorkspaceDetailView.swift
//  MarkdownEditor
//

import SwiftUI

struct WorkspaceDetailView: View {
    let windowController: WorkspaceWindowController

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBarView(windowController: windowController)
            Divider()
            if let tab = windowController.activeTab {
                WorkspaceTabContentView(tab: tab, windowController: windowController)
            } else {
                ContentUnavailableView("Select a Markdown File", systemImage: "doc.text")
            }
        }
    }
}

/// Split out so `@Bindable` binds to whichever tab is currently active. Deliberately has no
/// `.id(tab.id)` at the call site -- this view's identity (and the `SplitView`/
/// `MainSplitViewController` it hosts) must stay stable across tab switches, the same way it
/// already stays stable across file switches within one tab: giving it a fresh id per tab would
/// tear down and rebuild the NSTextView/WKWebView on every click, losing undo/selection/scroll
/// state and re-triggering the window-frame-autosave reapplication in `SplitView.swift`.
private struct WorkspaceTabContentView: View {
    @Bindable var tab: WorkspaceTab
    let windowController: WorkspaceWindowController
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true

    var body: some View {
        // Stable per-workspace-window identifier (the folder, not the selected file) --
        // MainSplitViewController bakes this in at first appearance and never re-reads it,
        // so this must not vary per file or per tab. See docs/plan-m7.md.
        SplitView(text: $tab.text, isPreviewVisible: $isPreviewVisible, cursorLine: $tab.cursorLine, autosaveIdentifier: windowController.folderModel.folderURL.path)
            .onChange(of: tab.text) { _, newValue in
                guard let url = tab.selectedFileURL, newValue != tab.loadedText else { return }
                tab.autosave.schedule(text: newValue, to: url)
                windowController.notifyEdited(tab)
            }
    }
}
