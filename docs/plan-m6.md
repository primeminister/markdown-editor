# M6 — Native tabs + preview/permanent tab promotion

## Context

`docs/plan.md` defines M6: double-clicking an active sidebar file opens it in a new native macOS window tab (`NSWindow.addTabbedWindow`) within the same folder's tab group, and the group tracks one "preview" tab — single-click always reuses/replaces that tab's content (bringing it to front); double-click, or editing the preview tab's content, promotes it to a permanent tab, so the next single-click gets a fresh preview tab. This is the same single-click-reuse/double-click-or-edit-pins model used by VS Code and Xcode's own Navigator.

M5 (merged in PR #9) gave every open folder exactly one `NSWindow`, owned by `WorkspaceWindowManager` keyed by folder URL, with one `WorkspaceModel` (`selectedFileURL`/`text`/`loadedText`) and one `WorkspaceAutosaveController` per window. M6 needs *multiple* windows (tabs) per folder, each potentially showing a different file and each independently editable — so the per-folder 1:1 assumptions baked into `WorkspaceWindowManager` (one window, one model, one autosave controller per key) have to become 1:many, and the sidebar's click handling has to be rerouted through shared tab-group logic instead of calling `model.selectFile` directly on whichever window happened to be clicked in.

## Approach

### 1. `WorkspaceTab.swift` (new) — one tab's state

```swift
@MainActor
final class WorkspaceTab {
    let window: NSWindow
    let model: WorkspaceModel
    let autosave: WorkspaceAutosaveController
    var closeObserver: NSObjectProtocol?
}
```
Replaces the flat `windows`/`autosaveControllers`/`observerTokens` dictionaries M5 kept in `WorkspaceWindowManager` (which assumed one of each per folder) with one bundle per tab, since M6 needs N of these per folder.

### 2. `WorkspaceTabGroup.swift` (new) — per-folder tab management + preview/permanent state machine

```swift
@MainActor
final class WorkspaceTabGroup {
    let folderURL: URL
    private(set) var tabs: [WorkspaceTab] = []
    private weak var previewTab: WorkspaceTab?
    var onEmpty: (() -> Void)?

    func openInitialTab()            // folder just opened via menu/Finder — no file selected yet, becomes the preview tab
    func openPreview(_ url: URL)     // single-click: reuse previewTab if one exists, else create+mark one
    func openPermanent(_ url: URL)   // double-click: always create a brand-new, never-preview tab
    func notifyEdited(_ model: WorkspaceModel) // called on every text edit; clears previewTab if it matches
    func bringToFront()              // folder reopened while already open — surface previewTab (or first tab)
    func flushAllPendingAutosaves()
}
```

The whole preview/permanent model collapses to a single `weak var previewTab: WorkspaceTab?` reference — no per-tab `isPinned` flag needed. A tab is "permanent" purely by *not* being `previewTab`:
- `openPreview`: if `previewTab` exists, call `previewTab.model.selectFile(url)` and bring its window front (matches M5's existing in-place-swap behavior, just always targeting the group's designated preview tab rather than whichever window was clicked in). If `previewTab` is `nil` (nothing to reuse — either no tab has been the preview yet, or it was just promoted), create a new tab via `makeTab(selecting:)` and set it as `previewTab`.
- `openPermanent`: unconditionally `makeTab(selecting: url)` and leave `previewTab` untouched — the new tab is permanent from birth simply because it's never assigned to `previewTab`.
- `notifyEdited`: if `previewTab?.model === model`, set `previewTab = nil`. This is the "editing the preview tab's content promotes it to a permanent tab" rule — the tab itself doesn't change, it just stops being reusable, so the *next* `openPreview` call has no `previewTab` to reuse and mints a fresh one.
- Closing a tab (`willCloseNotification`) flushes its autosave, removes it from `tabs`, clears `previewTab` if it was the one closed, and calls `onEmpty` once `tabs` is empty (so `WorkspaceWindowManager` can drop the group).

`makeTab(selecting:)` (private) builds a `WorkspaceModel` + `WorkspaceAutosaveController` + `WorkspaceSplitViewController` exactly as `WorkspaceWindowManager.open(folder:)` does today, then:
- Sets `window.tabbingIdentifier = folderURL.path` (defensive — explicit `addTabbedWindow` below doesn't strictly need matching identifiers to group correctly, but this keeps macOS's own *automatic* tabbing heuristics from ever merging two different folders' workspace windows, or a `DocumentGroup` single-file window, into one tab bar by coincidence).
- Calls `tabs.first?.window.addTabbedWindow(window, ordered: .above)` when another tab already exists in the group (the very first tab of a group is just a plain new window — nothing to add it *to* yet).
- Registers the same `willCloseNotification` → flush/remove/clear-preview/onEmpty handling described above.

Each tab gets its **own** `WorkspaceModel`, including its own `loadTree()` call — i.e. each tab independently re-walks the folder's file tree rather than sharing one loaded `FileNode` tree across the group. This repeats M5's off-main-thread walk once per open tab instead of once per folder; judged an acceptable simplification given personal-use folder sizes (see "Out of scope"), and it sidesteps needing any cross-tab shared/observable tree state.

### 3. `WorkspaceWindowManager.swift` (edit) — now manages tab groups, not raw windows

```swift
final class WorkspaceWindowManager {
    static let shared = WorkspaceWindowManager()
    private var tabGroups: [URL: WorkspaceTabGroup] = [:]

    func flushAllPendingAutosaves() { tabGroups.values.forEach { $0.flushAllPendingAutosaves() } }
    func presentOpenPanel() { /* unchanged */ }

    func open(folder url: URL) {
        let key = url.standardizedFileURL
        if let existing = tabGroups[key] { existing.bringToFront(); return }
        let group = WorkspaceTabGroup(folderURL: key)
        group.onEmpty = { [weak self] in self?.tabGroups[key] = nil }
        tabGroups[key] = group
        group.openInitialTab()
    }
}
```
`flushAllPendingAutosaves()` (still called from `AppDelegate.applicationWillTerminate`) now fans out across every tab of every group, not one controller per folder — the actual bug M6 fixes here: M5's model could only ever have one file mid-edit per folder at quit time, M6 can have N.

### 4. `WorkspaceSplitViewController.swift` (edit) — thread the tab group through

Constructor gains a `tabGroup: WorkspaceTabGroup` parameter, passed to both `WorkspaceSidebarView` and (via it, see below) `WorkspaceDetailView`. No other change — the sidebar-width autosave name stays keyed by `model.folderURL.path`, which is already shared correctly across every tab of a group (all tabs of one folder showing the same sidebar width is the right behavior, not a bug to fix).

### 5. `WorkspaceSidebarView.swift` (edit) — route clicks through the tab group, not the local model

```swift
FileRow(node: node, isSelected: node.url == model.selectedFileURL)
    .onTapGesture(count: 2) {
        guard node.isMarkdown else { return }
        tabGroup.openPermanent(node.url)
    }
    .onTapGesture(count: 1) {
        guard node.isMarkdown else { return }
        tabGroup.openPreview(node.url)
    }
```
SwiftUI's standard idiom for coexisting tap counts on one view: the count-2 recognizer must fail before count-1 fires, so a double-click never *also* fires the single-click handler. This is the key behavioral change from M5: a click no longer calls `model.selectFile` on *this* window's own model — it goes through `tabGroup`, which may end up targeting a *different* tab's model (whichever one is currently the preview tab) or spin up a brand new one. `isSelected` (the bold sidebar row) stays per-tab/per-model as today — each tab's sidebar bolds whichever file *that tab* is showing, not a cross-tab "open somewhere" indicator.

### 6. `WorkspaceDetailView.swift` (edit) — report edits to the tab group

```swift
let tabGroup: WorkspaceTabGroup
...
.onChange(of: model.text) { _, newValue in
    guard let url = model.selectedFileURL, newValue != model.loadedText else { return }
    model.autosave.schedule(text: newValue, to: url)
    tabGroup.notifyEdited(model)
}
```
One extra call alongside the existing autosave scheduling — this is the "editing the preview tab's content promotes it to permanent" trigger.

### 7. `WorkspaceModel.swift`, `FileNode.swift` — unchanged

No structural changes needed; `WorkspaceModel.selectFile`/`loadTree` are already per-instance and work as-is when there are multiple instances per folder instead of one.

### Code-review fixes applied after initial implementation

`/code-review` on the implementation diff (high effort, 4 confirmed/plausible findings) surfaced two real bugs, fixed in place in `WorkspaceTabGroup.swift`:

- **Every tab's window title was the folder name, never the file.** `makeTab` set `window.title` once at creation and nothing ever updated it, so every tab in a group's native tab bar showed an identical label — defeating the point of having a tab bar at all. Fixed by adding `syncTitle(_:)`, called after every `selectFile` call (in `makeTab` and in `openPreview`'s reuse branch), deriving the title from `model.selectedFileURL` (not the raw requested URL) so a failed load correctly leaves the previous title in place, matching `selectFile`'s existing "leave the previously shown file untouched" behavior on error.
- **A failed file load could show its error alert on the wrong window.** `openPreview`'s reuse branch called `previewTab.model.selectFile(url)` before `previewTab.window.makeKeyAndOrderFront(nil)` — since `selectFile` shows a blocking `NSAlert` synchronously on read/decode failure, a single-click routed to a *different* tab than the one clicked in could pop the alert while the wrong tab was still frontmost. Fixed by reordering both call sites (`openPreview` and `makeTab`) to bring the tab's window forward first, then call `selectFile`.

Not fixed, noted here instead per the project's "note uncertain findings in the PR description" policy:
- **`bringToFront()`'s `tabs.first` fallback is oldest-created, not most-recently-active.** Only matters once every tab in a group has been pinned (no `previewTab` left) and the folder is reopened via the menu/Finder rather than by clicking its already-visible window/Dock icon — judged too narrow an edge case to justify adding window-activation tracking for.

### Manual-testing fix: tap-gesture exclusivity was a real bug, not just a theoretical one

Code review flagged (as `PLAUSIBLE`, unable to confirm from static reading) that chaining `.onTapGesture(count: 2)` + `.onTapGesture(count: 1)` on the same sidebar row might not be mutually exclusive in this specific context (a `List` row on macOS, hosted via `NSHostingController`). Manual testing on the owner's Mac confirmed it: double-clicking a file both loaded it into the preview tab (the count-1 handler firing) *and* opened it in a new permanent tab (the count-2 handler firing) — i.e. exactly the failure mode review couldn't rule out.

Fixed in `FileRow.swift` by dropping the two independent `.onTapGesture` modifiers in favor of manual disambiguation: a single click schedules its action (`onSingleClick`) via a cancelable `DispatchWorkItem` delayed by `NSEvent.doubleClickInterval` (the system's actual configured double-click window); a second click within that window cancels the pending single-click action before it runs and fires `onDoubleClick` instead. This doesn't depend on SwiftUI's gesture-priority resolution at all, so it can't regress the same way. `FileRow` now owns this state and takes `onSingleClick`/`onDoubleClick` closures instead of exposing raw tap gestures to `WorkspaceSidebarView`.

## Out of scope for M6 (explicitly deferred / accepted trade-offs)
- **Tab bar (and tab width) span the full window, including above the sidebar.** Confirmed with the owner as an accepted trade-off of using native `NSWindow.addTabbedWindow` tabs, not a bug: each tab is technically a separate window (with its own sidebar), so the OS-drawn tab bar/tab-item sizing is window-wide system chrome, not something scopable to just the detail pane. Getting a shared full-height sidebar with tabs only above the editor/preview (like Mail/Notes/Safari's own bookmarks sidebar) would require dropping native window tabs for a custom-built in-app tab strip — a milestone-sized rework, not pursued here. Owner chose to keep native tabs as-is for the OS-level integration (Window menu, drag-tab-out, System Settings tab prefs, Cmd+Shift+]/[ cycling).
- **Per-tab file-tree sharing.** Each tab re-walks the folder independently on open rather than sharing one cached tree across a group; fine at personal-use folder sizes, and there's no filesystem watcher in this app at all yet (M5 didn't have one either) so trees can already go stale within a single window if files change externally — not a regression introduced here.
- **De-duplicating permanent tabs.** Double-clicking a file that's already open in another permanent tab of the same group opens a *second* tab showing it, rather than bringing the existing one forward. Not specified by the plan; kept simple to match the literal milestone wording ("opens it in a new... tab").
- **Cross-tab "this file is open elsewhere" indicator in the sidebar.** Each tab's sidebar only bolds its own currently-shown file.
- Creating/renaming/deleting files from the sidebar, explicit save UI/dirty indicators — still not requested (carried over from M5's own out-of-scope list).

## Files touched
- `MarkdownEditor/MarkdownEditor/WorkspaceTab.swift` (new)
- `MarkdownEditor/MarkdownEditor/WorkspaceTabGroup.swift` (new)
- `MarkdownEditor/MarkdownEditor/WorkspaceWindowManager.swift` (edit)
- `MarkdownEditor/MarkdownEditor/WorkspaceSplitViewController.swift` (edit)
- `MarkdownEditor/MarkdownEditor/WorkspaceSidebarView.swift` (edit)
- `MarkdownEditor/MarkdownEditor/WorkspaceDetailView.swift` (edit)
- `MarkdownEditor/MarkdownEditor/FileRow.swift` (edit — manual-testing fix, see above)

No new automated tests planned: like M5's own `WorkspaceWindowManager`, this milestone is entirely `NSWindow`/tab-group orchestration with no pure-logic surface worth extracting — covered by the manual checklist below only, per the project's testing strategy.

## Verification
- Build: `xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`.
- Automated: `xcodebuild test -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'` — existing suite must still pass unchanged.
- Manual (owner's Mac, per project workflow — hand off the checklist, wait for go-ahead before merge):
  - Open a folder; single-click through several `.md` files in the sidebar — content swaps in place in the same tab/window, no new tabs appear.
  - Double-click a `.md` file — opens as a new native tab (visible tab bar) in the same window's tab group; the sidebar in the new tab matches the original. Confirm it's exactly **one** new tab, not two, and the previously-active tab's content is untouched (regression check for the manual-testing fix above).
  - Double-click a file, then check the tab bar: each tab's label shows the *file name* it's displaying, not the folder name repeated on every tab.
  - After double-clicking (creating a permanent tab), single-click other files in the sidebar from either tab — browsing continues to reuse a preview tab and never disturbs the pinned/permanent tab.
  - Type into the current preview tab's content, then single-click a different file elsewhere in the sidebar — the edited tab is now pinned (its content stays put) and a fresh preview tab is used for the new selection.
  - Close a pinned tab and a preview tab independently — window/tab bar updates correctly, no crash, no orphaned autosave.
  - Quit the app with unsaved edits pending in more than one tab of the same folder (within the 0.5s autosave debounce window) — confirm both files' edits are flushed to disk, not just one.
  - Reopen the same folder (menu or Finder) while its window/tabs are already open — brings the existing tab group forward instead of opening a duplicate window.
- Follows repo workflow: branch `m6-native-tabs`, run `/code-review` on the diff before opening the PR, then open PR and stop — owner merges manually after the manual checklist is confirmed.
