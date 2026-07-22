//
//  SplitView.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import AppKit
import SwiftUI

struct SplitView: NSViewControllerRepresentable {
    @Binding var text: String
    @Binding var isPreviewVisible: Bool
    let autosaveIdentifier: String

    func makeNSViewController(context: Context) -> MainSplitViewController {
        MainSplitViewController(text: $text, isPreviewVisible: isPreviewVisible, autosaveIdentifier: autosaveIdentifier)
    }

    func updateNSViewController(_ controller: MainSplitViewController, context: Context) {
        controller.update(text: $text, isPreviewVisible: isPreviewVisible)
    }
}

final class MainSplitViewController: NSSplitViewController {
    private let previewItem: NSSplitViewItem
    private let editorHostingController: NSHostingController<AnyView>
    private let previewHostingController: NSHostingController<AnyView>
    private let autosaveIdentifier: String
    private var hasSetWindowAutosaveName = false

    init(text: Binding<String>, isPreviewVisible: Bool, autosaveIdentifier: String) {
        self.autosaveIdentifier = autosaveIdentifier

        let editorHostingController = NSHostingController(rootView: AnyView(EditorView(text: text)))
        self.editorHostingController = editorHostingController
        let editorItem = NSSplitViewItem(viewController: editorHostingController)
        editorItem.minimumThickness = 300

        let previewHostingController = NSHostingController(rootView: AnyView(PreviewView(text: text)))
        self.previewHostingController = previewHostingController
        let previewSplitItem = NSSplitViewItem(viewController: previewHostingController)
        previewSplitItem.minimumThickness = 300
        previewSplitItem.canCollapse = true
        // Set directly (not through the animated `setPreviewVisible`) so a previously-hidden
        // preview opens already collapsed instead of visibly collapsing on first appearance.
        previewSplitItem.isCollapsed = !isPreviewVisible
        self.previewItem = previewSplitItem

        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        addSplitViewItem(editorItem)
        addSplitViewItem(previewSplitItem)

        // Both an identifier and an autosaveName are required for AppKit to persist/restore the
        // divider position across launches — no manual Codable/UserDefaults plumbing needed.
        // Scoped per document via `autosaveIdentifier` so multiple open document windows don't
        // clobber each other's saved divider position.
        splitView.identifier = NSUserInterfaceItemIdentifier("MainSplit-\(autosaveIdentifier)")
        splitView.autosaveName = "MainSplit-\(autosaveIdentifier)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // setFrameAutosaveName re-applies the last saved frame every time it's called, so guard
        // against reapplying it on later appearances (e.g. un-minimizing) and discarding an
        // unsaved move/resize. Scoped per document, like the split autosave name above.
        guard !hasSetWindowAutosaveName else { return }
        hasSetWindowAutosaveName = true
        view.window?.setFrameAutosaveName("MainWindow-\(autosaveIdentifier)")
    }

    func update(text: Binding<String>, isPreviewVisible: Bool) {
        // SwiftUI never re-diffs a NSHostingController's rootView on its own once handed to
        // AppKit — without reassigning it here on every update, EditorView/PreviewView would
        // freeze after the first render and never see subsequent text or state changes.
        editorHostingController.rootView = AnyView(EditorView(text: text))
        previewHostingController.rootView = AnyView(PreviewView(text: text))
        setPreviewVisible(isPreviewVisible)
    }

    private func setPreviewVisible(_ visible: Bool) {
        let shouldCollapse = !visible
        guard previewItem.isCollapsed != shouldCollapse else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            previewItem.animator().isCollapsed = shouldCollapse
        }
    }
}
