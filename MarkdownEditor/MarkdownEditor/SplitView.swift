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
    @Binding var cursorLine: Int
    let autosaveIdentifier: String
    var isEditorEditable: Bool = true

    func makeNSViewController(context: Context) -> MainSplitViewController {
        MainSplitViewController(text: $text, isPreviewVisible: isPreviewVisible, cursorLine: $cursorLine, autosaveIdentifier: autosaveIdentifier, isEditorEditable: isEditorEditable)
    }

    func updateNSViewController(_ controller: MainSplitViewController, context: Context) {
        // SwiftUI invokes this synchronously as part of laying out *this* representable's own
        // containing hosting view. `controller.update` reassigns rootView on two separately-owned
        // NSHostingControllers (editor/preview), which forces their internal SwiftUI layout to run
        // immediately -- i.e. a nested hosting-view layout inside an in-progress outer one. AppKit
        // detects that as reentrant layout and silently skips a pass, which shows up as a quick
        // up/down flash. Deferring one run-loop tick lets the outer layout pass finish first.
        DispatchQueue.main.async {
            controller.update(text: $text, isPreviewVisible: isPreviewVisible, cursorLine: $cursorLine)
        }
    }
}

/// Single source of truth for the AppKit autosave-name format so `MainSplitViewController` and any
/// external code that needs to apply the same window-frame autosave name before this controller
/// exists (e.g. `WorkspaceWindowManager`) can't drift out of sync with two independently-typed strings.
enum SplitViewAutosaveNaming {
    static func windowName(for identifier: String) -> String { "MainWindow-\(identifier)" }
    static func splitName(for identifier: String) -> String { "MainSplit-\(identifier)" }
    static func workspaceSidebarName(for identifier: String) -> String { "WorkspaceSidebar-\(identifier)" }
}

final class MainSplitViewController: NSSplitViewController {
    private let previewItem: NSSplitViewItem
    private let editorHostingController: NSHostingController<AnyView>
    private let previewHostingController: NSHostingController<AnyView>
    private let autosaveIdentifier: String
    private let isEditorEditable: Bool
    private var hasSetWindowAutosaveName = false

    init(text: Binding<String>, isPreviewVisible: Bool, cursorLine: Binding<Int>, autosaveIdentifier: String, isEditorEditable: Bool = true) {
        self.autosaveIdentifier = autosaveIdentifier
        self.isEditorEditable = isEditorEditable

        let editorHostingController = NSHostingController(rootView: Self.editorRootView(text: text, cursorLine: cursorLine, isEditorEditable: isEditorEditable))
        self.editorHostingController = editorHostingController
        let editorItem = NSSplitViewItem(viewController: editorHostingController)
        editorItem.minimumThickness = 300

        let previewHostingController = NSHostingController(rootView: AnyView(PreviewView(text: text, cursorLine: cursorLine.wrappedValue)))
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
        let splitAutosaveName = SplitViewAutosaveNaming.splitName(for: autosaveIdentifier)
        splitView.identifier = NSUserInterfaceItemIdentifier(splitAutosaveName)
        splitView.autosaveName = splitAutosaveName
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
        view.window?.setFrameAutosaveName(SplitViewAutosaveNaming.windowName(for: autosaveIdentifier))
    }

    func update(text: Binding<String>, isPreviewVisible: Bool, cursorLine: Binding<Int>) {
        // SwiftUI never re-diffs a NSHostingController's rootView on its own once handed to
        // AppKit — without reassigning it here on every update, EditorView/PreviewView would
        // freeze after the first render and never see subsequent text or state changes.
        editorHostingController.rootView = Self.editorRootView(text: text, cursorLine: cursorLine, isEditorEditable: isEditorEditable)
        previewHostingController.rootView = AnyView(PreviewView(text: text, cursorLine: cursorLine.wrappedValue))
        setPreviewVisible(isPreviewVisible)
    }

    /// Mounts the formatting toolbar inside the *existing* editor split item rather than adding a
    /// third `NSSplitViewItem`, so divider-position/window-frame autosave (scoped to two items) is
    /// untouched. Gated on `isEditorEditable` so it's automatically absent in the read-only
    /// Cheatsheet window, which already passes `isEditorEditable: false`.
    private static func editorRootView(text: Binding<String>, cursorLine: Binding<Int>, isEditorEditable: Bool) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                if isEditorEditable {
                    FormattingToolbar()
                    Divider()
                }
                // Without an explicit maxHeight, EditorView (a plain NSViewRepresentable) reports
                // only its ideal/fitting height to the VStack, so the whole stack renders smaller
                // than the split item and gets centered in the leftover space -- forcing it to fill
                // is what makes the toolbar hug the top instead of floating mid-pane.
                EditorView(text: text, cursorLine: cursorLine, isEditable: isEditorEditable)
                    .frame(maxHeight: .infinity)
            }
        )
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
