# M7 — Custom in-window tabs + persistent full-height sidebar

## Context

The first item in `docs/plan.md`'s "Next features to implement" list asks for a different tab/sidebar structure than M6 built: a persistent sidebar spanning the full window height, with a custom tab strip that appears only above the editor/preview pane (tab width sized to the filename), replacing M6's native `NSWindow.addTabbedWindow` tabs entirely. M6 itself flagged this exact trade-off as accepted-for-now under "Out of scope" ("Tab bar... span[s] the full window, including above the sidebar... Getting a shared full-height sidebar with tabs only above the editor/preview... would require dropping native window tabs for a custom-built in-app tab strip — a milestone-sized rework, not pursued here"). This is that rework.

Confirmed with the owner:
1. Native window-tabs are fully replaced — one real `NSWindow` per open folder from now on; "tabs" become an in-app concept (one window, N file-tabs).
2. The existing preview/permanent-tab promotion model from M6 carries over unchanged in behavior: single-click reuses/replaces the current preview tab's content; double-click always opens a brand-new tab.
3. Tabs get a close button only for now — drag-to-reorder, keyboard shortcuts (Cmd+W/Cmd+1-9), right-click menu are explicitly deferred ("rest may come in later").
4. The sidebar gets a show/hide toggle, icon top-right of the sidebar. Since hiding the sidebar can't hide the only control that re-shows it, the icon stays part of the sidebar column at all times: collapsing doesn't remove the sidebar to zero width, it shrinks to a narrow rail that still shows just the icon (click again to re-expand) — not an icon that jumps elsewhere on collapse.

M5 gave every open folder exactly one `NSWindow` with one `WorkspaceModel`/`WorkspaceAutosaveController`. M6 turned that into one-window-per-tab (N windows per folder, one `WorkspaceModel` each, each independently loading its own file tree). M7 goes back to **one window per folder** (like M5) but keeps M6's multi-tab/preview-promotion capability — it just relocates "tab" from "a whole window" to "a slot inside one window's tab strip." This means `WorkspaceModel` needs to split into folder-wide state (the file tree, loaded once, shared) and per-tab state (selected file, text, autosave) — today's M6 `WorkspaceModel` conflates both, which is exactly why M6 re-walks the tree once per tab.

## Approach

### 1. `WorkspaceFolderModel.swift` (rename of `WorkspaceModel.swift`) — folder-wide state only

```swift
@MainActor
@Observable
final class WorkspaceFolderModel {
    let folderURL: URL
    var root: FileNode?
    func loadTree() async { /* unchanged Task.detached walk */ }
}
```
Drops `selectedFileURL`/`text`/`loadedText`/`autosave`/`selectFile` — those move to `WorkspaceTab` below. One instance per window (per folder), shared by the sidebar and by every tab — fixes M6's per-tab tree reload as a side effect.

### 2. `WorkspaceTab.swift` (rewrite) — per-tab file state, not a window wrapper

```swift
@MainActor
@Observable
final class WorkspaceTab {
    let id = UUID()
    let autosave: WorkspaceAutosaveController
    var selectedFileURL: URL?
    var text: String = ""
    var loadedText: String = ""

    func selectFile(_ url: URL) { /* moved from today's WorkspaceModel.selectFile, unchanged body */ }
}
```
No more `window: NSWindow` — M6's `WorkspaceTab` *was* a window handle; M7's is purely the file/text/autosave state a tab bar chip and the detail pane read from. `@Observable` so the tab bar and detail view react to mutations without any manual `rootView` reassignment (same reason `WorkspaceDetailView`'s `@Bindable var model` already works today with no update-cycle plumbing).

### 3. `WorkspaceWindowController.swift` (new, replaces `WorkspaceTabGroup.swift`) — one per open folder

```swift
@MainActor
@Observable
final class WorkspaceWindowController {
    let window: NSWindow
    let folderModel: WorkspaceFolderModel
    private(set) var tabs: [WorkspaceTab] = []
    var activeTab: WorkspaceTab?
    private weak var previewTab: WorkspaceTab?
    var isSidebarVisible = true
    private let splitViewController: WorkspaceSplitViewController
    var onEmpty: (() -> Void)?

    func openInitialTab()             // folder just opened — empty tab, becomes previewTab + activeTab
    func openPreview(_ url: URL)      // single-click: reuse previewTab (selectFile + make active) or mint one
    func openPermanent(_ url: URL)    // double-click: always mint a new tab, made active, never previewTab
    func notifyEdited(_ tab: WorkspaceTab) // clears previewTab if it matches — same M6 promotion rule
    func activate(_ tab: WorkspaceTab)      // tab-bar click: just switches activeTab, doesn't touch previewTab
    func closeTab(_ tab: WorkspaceTab)      // close button: flush + remove; reassigns activeTab if needed
    func toggleSidebar()              // flips isSidebarVisible, animates splitViewController's rail width
    func bringToFront()               // window.makeKeyAndOrderFront(nil) — one window now, trivial
    func flushAllPendingAutosaves()   // iterate tabs
}
```
This carries over M6's `WorkspaceTabGroup` preview/permanent logic almost verbatim (`previewTab` as the single source of truth, no per-tab pinned flag) — the only real change is that `openPreview`/`openPermanent`/`makeTab` no longer create/show/close `NSWindow`s, they create/activate/remove entries in `tabs` within the one already-existing window.

`closeTab`: flush autosave, remove from `tabs`; if it was `previewTab`, clear that; if it was `activeTab`, activate the adjacent tab (previous, else next, else `nil`). `activeTab == nil` falls back to the existing `ContentUnavailableView` empty state — **closing the last tab does not close the window**, unlike M6 where closing the last tab's window naturally ended the group. The window itself closing (real macOS window close) is the only thing that calls `onEmpty`.

`toggleSidebar()` needs an actual AppKit width change (see `WorkspaceSplitViewController` below) since `NSSplitViewItem` isn't part of the SwiftUI-observed tree — `WorkspaceWindowController` holds the `splitViewController` reference it already needs for window construction and calls a method on it directly, rather than trying to bridge `@Observable` state into AppKit.

### 4. `WorkspaceWindowManager.swift` (edit) — same public surface, new value type

```swift
final class WorkspaceWindowManager {
    static let shared = WorkspaceWindowManager()
    private var controllers: [URL: WorkspaceWindowController] = [:]
    // presentOpenPanel(), open(folder:), flushAllPendingAutosaves() — unchanged bodies,
    // just keyed to WorkspaceWindowController instead of WorkspaceTabGroup
}
```
`AppDelegate.swift`/`MarkdownEditorApp.swift` need zero changes — same `open(folder:)`/`presentOpenPanel()`/`flushAllPendingAutosaves()` calls.

### 5. `WorkspaceSplitViewController.swift` (edit) — sidebar rail animation

Still a 2-item `NSSplitViewController` (sidebar | detail); sidebar item's autosave name unchanged. Adds:
```swift
private let sidebarItem: NSSplitViewItem
private static let railWidth: CGFloat = 36
private var expandedWidth: CGFloat = 220 // captured once, first time the sidebar collapses

func setSidebarVisible(_ visible: Bool, animated: Bool) {
    let target = visible ? expandedWidth : Self.railWidth
    if !visible { expandedWidth = splitView.arrangedSubviews[0].frame.width }
    sidebarItem.minimumThickness = visible ? 180 : Self.railWidth
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.allowsImplicitAnimation = animated
        splitView.animator().setPosition(target, ofDividerAt: 0)
    }
}
```
`sidebarItem.canCollapse` stays `false` — the rail must remain visible/clickable, not disappear, so this is a width tween between two fixed thicknesses (mirroring how `MainSplitViewController` already animates the *preview* item's `isCollapsed` via `NSAnimationContext`), not a boolean collapse. `minimumThickness` has to move with it or the split view's own layout would clamp the rail back up to 180pt.

### 6. `WorkspaceSidebarView.swift` (edit) — header toggle + rail mode

```swift
struct WorkspaceSidebarView: View {
    let folderModel: WorkspaceFolderModel
    let windowController: WorkspaceWindowController

    var body: some View {
        if windowController.isSidebarVisible {
            VStack(spacing: 0) {
                HStack { Spacer(); toggleButton }.padding(6)
                fileList // existing List(...), click handlers now call windowController.openPreview/openPermanent
            }
        } else {
            VStack { toggleButton; Spacer() }.frame(maxHeight: .infinity)
        }
    }
}
```
Click handlers move from `tabGroup.openPreview/openPermanent` to `windowController.openPreview/openPermanent` — same call shape, new receiver type. `isSelected` in `FileRow` now compares against `windowController.activeTab?.selectedFileURL`.

### 7. `WorkspaceTabBarView.swift` (new) — the tab strip

```swift
struct WorkspaceTabBarView: View {
    let windowController: WorkspaceWindowController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(windowController.tabs, id: \.id) { tab in
                    TabChip(
                        title: tab.selectedFileURL?.lastPathComponent ?? windowController.folderModel.folderURL.lastPathComponent,
                        isActive: tab === windowController.activeTab,
                        onSelect: { windowController.activate(tab) },
                        onClose: { windowController.closeTab(tab) }
                    )
                }
            }
        }
        .frame(height: 32)
    }
}
```
Each `TabChip` sizes to its own text (`.fixedSize()`, no `maxWidth`) plus a close button — matches "tab width is size of filename." No drag-reorder, no keyboard shortcuts, no context menu, per the owner's scope call above.

### 8. `WorkspaceDetailView.swift` (edit) — tab bar above the active tab's content

```swift
struct WorkspaceDetailView: View {
    let windowController: WorkspaceWindowController
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBarView(windowController: windowController)
            Divider()
            if let tab = windowController.activeTab {
                SplitView(text: bindingTo(tab), isPreviewVisible: $isPreviewVisible, autosaveIdentifier: windowController.folderModel.folderURL.path)
                    .id(tab.id)
                    .onChange(of: tab.text) { _, newValue in
                        guard let url = tab.selectedFileURL, newValue != tab.loadedText else { return }
                        tab.autosave.schedule(text: newValue, to: url)
                        windowController.notifyEdited(tab)
                    }
            } else {
                ContentUnavailableView("Select a Markdown File", systemImage: "doc.text")
            }
        }
    }
}
```
Editor/preview split autosave identifier stays `folderURL.path` (not per-tab) — same reasoning M5 already established: it's a window-level layout preference (divider position), correctly shared across every tab of one window, not per-file. `.id(tab.id)` on the `if let` branch gives SwiftUI a stable identity boundary per active tab so switching tabs is a clean swap.

### 9. `WorkspaceModel.swift`, `FileNode.swift`, `FileRow.swift` — mostly unchanged

`FileNode.swift` untouched. `FileRow.swift` untouched (already just fires closures). `WorkspaceModel.swift` is replaced by the split described in steps 1–2 above (no file left with that name).

## Out of scope for M7 (explicitly deferred)
- Drag-to-reorder tabs, keyboard shortcuts (Cmd+W/Cmd+1-9), right-click tab menu — confirmed deferred by the owner.
- Dragging a tab out into its own OS window — single-window-per-folder only now.
- De-duplicating permanent tabs (double-clicking an already-open file opens a second tab) — carried over unchanged from M6's own out-of-scope call.
- `isPreviewVisible` (editor/preview toggle) — unrelated existing global `@AppStorage`, untouched.

## Files touched
- `MarkdownEditor/MarkdownEditor/WorkspaceModel.swift` → `WorkspaceFolderModel.swift` (rename + split)
- `MarkdownEditor/MarkdownEditor/WorkspaceTab.swift` (rewrite)
- `MarkdownEditor/MarkdownEditor/WorkspaceTabGroup.swift` → `WorkspaceWindowController.swift` (replace)
- `MarkdownEditor/MarkdownEditor/WorkspaceWindowManager.swift` (edit)
- `MarkdownEditor/MarkdownEditor/WorkspaceSplitViewController.swift` (edit)
- `MarkdownEditor/MarkdownEditor/WorkspaceSidebarView.swift` (edit)
- `MarkdownEditor/MarkdownEditor/WorkspaceTabBarView.swift` (new)
- `MarkdownEditor/MarkdownEditor/WorkspaceDetailView.swift` (edit)

No new automated tests planned: like M5's `WorkspaceWindowManager` and M6's `WorkspaceTabGroup`, this milestone is entirely `NSWindow`/`NSSplitViewItem`/tab orchestration with no pure-logic surface worth extracting — covered by the manual checklist only, per the project's testing strategy.

## Verification
- Build: `xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`.
- Automated: `xcodebuild test -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'` — existing suite must still pass unchanged.
- Manual (owner's Mac, per project workflow — hand off the checklist, wait for go-ahead before merge):
  - Open a folder: exactly one native window, sidebar spans the full window height, no OS-level tab bar.
  - Single-click a file, then another: same tab's content replaces in place (no new tab chip appears).
  - Double-click a file: a new tab chip appears, sized to the filename; the previous preview tab is untouched.
  - Edit the current preview tab's content, then single-click a different file elsewhere in the sidebar: the edited tab is pinned (stays put) and a fresh tab is used/created for the new selection.
  - Close a tab via its close button (both a pinned tab and the preview tab); close the very last tab — window and sidebar stay open, showing the "Select a Markdown File" empty state.
  - Toggle the sidebar closed: a narrow rail with just the toggle icon remains, full tree disappears; toggle again to restore the tree at its previous width. Sidebar/window-frame autosave positions still persist across relaunch.
  - Reopen the same folder (menu or Finder) while its window is already open — brings the existing window forward instead of opening a duplicate.
- Follows repo workflow: branch `m7-custom-tabs-sidebar`, run `/code-review` on the diff before opening the PR, then open PR and stop — owner merges manually after the manual checklist is confirmed.
