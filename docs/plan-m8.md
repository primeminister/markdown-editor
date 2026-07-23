# M8 — App preferences: keyboard shortcuts, editor font size, session restore

## Context

`docs/plan.md`'s "Next features to implement" list asked for app preferences, starting with
keyboard shortcuts to hide/show preview and hide/show sidebar. Discussed with the owner and
expanded into this milestone. Confirmed with the owner:

1. Style: plain `CommandGroup`/`.keyboardShortcut` menu items, matching the existing "Open Folder…"
   pattern (`MarkdownEditorApp.swift`) — no new Settings/Preferences window, no remappable shortcuts.
2. Preview toggle: **⌘/**. Sidebar toggle: **⌘B** (owner accepted the eventual collision risk with a
   possible future Bold-insertion shortcut).
3. Editor font size gets **Increase/Decrease/Reset** menu items (⌘+ / ⌘− / ⌘0) rather than a
   settings UI, consistent with "fixed shortcuts, no new UI."
4. Folder windows open at quit are restored on next launch — **all** of them, each with its own
   tabs/active tab/sidebar state as left (not just the most recent one).

Two independent window types exist in this app, which is the main thing shaping the design below:
SwiftUI `DocumentGroup` single-file windows (`ContentView.swift`) and plain-AppKit folder/workspace
windows (`WorkspaceWindowController`, managed by `WorkspaceWindowManager.shared`, introduced in M5,
reworked in M7). Preview visibility is already a single shared `@AppStorage("isPreviewVisible")` key
read by both `ContentView` and `WorkspaceDetailView`, so one keyboard shortcut for it just works
everywhere for free. Sidebar visibility only exists on workspace windows
(`WorkspaceWindowController.isSidebarVisible`/`toggleSidebar()`), so its shortcut has to reach into
`WorkspaceWindowManager` and be a harmless no-op when the key window is a single-file window.

**Correction, found during manual verification of this milestone:** the paragraph above was wrong —
the app *is* App-Sandboxed (`ENABLE_APP_SANDBOX = YES` in `project.pbxproj`'s build settings, present
since the M1 commit, with only `com.apple.security.files.user-selected.read-write`). That entitlement
only grants read access to a folder for the lifetime of the process that had it selected via
`NSOpenPanel` — it does **not** survive a relaunch. Persisting plain path strings and reading them
back in a new process after relaunch fails silently with `NSCocoaErrorDomain 257` /
`POSIXErrorDomain 1` ("Operation not permitted"), because `WorkspaceTab.selectFile`'s catch block
builds an `NSAlert` but never calls `.runModal()` on it. The actual implementation stores a
security-scoped bookmark (`URL.bookmarkData(options: .withSecurityScope)`) for each restored
folder in `RestorableWorkspace.folderBookmark`, resolves it and calls
`startAccessingSecurityScopedResource()` on launch before reading any files, and holds that access
open for the window's lifetime via `WorkspaceWindowController.retainSecurityScopedAccess(for:)`
(released on window close). One bookmark per folder is sufficient — the granted access covers the
whole folder subtree, so individual tab file paths don't need their own bookmarks.

## Approach

### 1. Preview toggle (⌘/)

`MarkdownEditorApp.swift` adds `@AppStorage("isPreviewVisible") private var isPreviewVisible = true`
and extends `.commands` with a new `CommandGroup(after: .toolbar)` (this is where macOS conventionally
puts view-visibility toggles) containing a `Button` that flips it, with a label that switches between
"Show Preview"/"Hide Preview", and `.keyboardShortcut("/", modifiers: .command)`.

### 2. Sidebar toggle (⌘B)

`WorkspaceWindowManager.swift` adds:
```swift
func toggleSidebarForKeyWindow() {
    guard let controller = controllers.values.first(where: { $0.window === NSApp.keyWindow }) else { return }
    controller.toggleSidebar()
}
```
Same `CommandGroup`: `Button("Toggle Sidebar") { WorkspaceWindowManager.shared.toggleSidebarForKeyWindow() }.keyboardShortcut("b", modifiers: .command)`. Label stays static (no per-window
Show/Hide text) since sidebar state isn't observed at the App-scene level and a single global menu
item can't reflect N independent per-window states anyway.

### 3. Editor font size (⌘+ / ⌘− / ⌘0)

`EditorView.swift` adds:
```swift
enum EditorFontSize {
    static let min = 9.0
    static let max = 28.0
    static let step = 1.0
    static let `default` = Double(NSFont.systemFontSize)
    static func clamped(_ value: Double) -> Double { Swift.min(max, Swift.max(min, value)) }
}
```
`MarkdownEditorApp.swift` adds `@AppStorage("editorFontSize") private var editorFontSize = EditorFontSize.default` plus three more buttons in the same `CommandGroup`: Increase (⌘+, `editorFontSize = EditorFontSize.clamped(editorFontSize + EditorFontSize.step)`), Decrease (⌘−), Reset (⌘0, back to `.default`).

`EditorView` (the `NSViewRepresentable`) also reads `@AppStorage("editorFontSize")` as a property, so
SwiftUI re-invokes `updateNSView` whenever it changes anywhere in the app (both properties share the
same `UserDefaults` suite). In `makeNSView`/`updateNSView`, compare `textView.font?.pointSize` against
`CGFloat(editorFontSize)` and only reassign `NSFont.monospacedSystemFont(ofSize:weight:)` when they
differ, so unrelated `updateNSView` calls don't disturb the font unnecessarily.

### 4. Reopen all folder windows on launch

New `Codable` type in `WorkspaceWindowManager.swift`:
```swift
struct RestorableWorkspace: Codable {
    let folderPath: String
    let tabFilePaths: [String]
    let activeTabIndex: Int?
}
```
Sidebar visibility deliberately isn't part of this blob — it's already persisted separately per
folder path (`WorkspaceSidebarVisible-<path>` key, read in `WorkspaceWindowController.init`), so
recreating the controller for that path picks the right value up automatically.

**Capture, on quit:**
- `WorkspaceWindowManager` adds `func snapshotForRestoration() -> [RestorableWorkspace]`, mapping
  each controller's `tabs`/`activeTab` into the struct above.
- `AppDelegate.applicationWillTerminate` JSON-encodes the snapshot into `UserDefaults.standard`
  under a new `"WorkspaceRestorationState"` key, alongside the existing `flushAllPendingAutosaves()`
  call.

**Restore, on launch — one deliberate simplification:** restored tabs are all created as permanent
(none is marked as the window's `previewTab`), so the first single-click in the sidebar after
relaunch mints a fresh preview tab rather than reusing a restored one. This matches the existing
"freshly opened folder" behavior and avoids persisting extra preview/permanent state for little
practical benefit.
- `WorkspaceWindowController` adds `func restoreTabs(filePaths: [String], activeIndex: Int?)` — one
  tab per surviving file path via the existing `makeTab()` + `tab.selectFile(url)`, `activeTab` set
  from `activeIndex` (clamped to bounds), window shown. Files that no longer exist are silently
  skipped; if none survive, the window still opens in the existing empty state (no tabs) rather than
  erroring.
- `WorkspaceWindowManager` adds `func restorePreviousSession()` — decode the persisted array, skip
  any folder that no longer exists on disk, otherwise construct a `WorkspaceWindowController` and
  call `restoreTabs(...)` instead of `openInitialTab()`. Returns/tracks whether at least one window
  was actually restored.

**Launch-timing detail — the one real risk here.** SwiftUI's `DocumentGroup(newDocument:)` still
wants to open a blank "Untitled" window on a launch with nothing else to open. To suppress that only
when we restore at least one folder window:
- Call `restorePreviousSession()` from `AppDelegate.applicationWillFinishLaunching` — not
  `applicationDidFinishLaunching` — since it must run before AppKit decides whether to open an
  untitled file. Store the "did we restore anything" result on the delegate.
- Implement `applicationShouldOpenUntitledFile(_:) -> Bool`, returning `false` when something was
  restored, `true` otherwise (so the normal blank-document launch is preserved when there's no saved
  session, or the saved folders are all gone).
- This exact ordering is worth confirming by hand rather than trusting from documentation alone —
  called out explicitly in the manual verify list below.

## Files touched
- `MarkdownEditor/MarkdownEditor/MarkdownEditorApp.swift` — new `@AppStorage` properties, expanded `.commands`.
- `MarkdownEditor/MarkdownEditor/WorkspaceWindowManager.swift` — `toggleSidebarForKeyWindow()`, `snapshotForRestoration()`, `restorePreviousSession()`, `RestorableWorkspace`.
- `MarkdownEditor/MarkdownEditor/WorkspaceWindowController.swift` — `restoreTabs(filePaths:activeIndex:)`.
- `MarkdownEditor/MarkdownEditor/AppDelegate.swift` — `applicationWillFinishLaunching`, `applicationShouldOpenUntitledFile`, persist snapshot in `applicationWillTerminate`.
- `MarkdownEditor/MarkdownEditor/EditorView.swift` — `EditorFontSize` constants + clamp helper, live font-size application.

## Automated tests (`MarkdownEditorTests`)
- `RestorableWorkspace` JSON round-trip (encode/decode).
- `EditorFontSize.clamped(_:)` — below min, above max, in-range pass-through.
- Everything else in this milestone is AppKit menu/window/launch-lifecycle behavior with no pure-logic
  seam — manual-only, consistent with the project's existing testing split (same reasoning as M5/M6/M7).

## Verification
- Build: `xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`.
- Automated: `xcodebuild test -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'` — existing suite must still pass, plus the two new test cases above.
- Manual (owner's Mac, per project workflow — hand off the checklist, wait for go-ahead before merge):
  - ⌘/ toggles preview in both a single-file window and a folder window; View-menu label flips Show/Hide Preview.
  - ⌘B toggles the sidebar in a folder window; does nothing (no crash) with a single-file window key.
  - ⌘+ / ⌘− / ⌘0 change editor font size live, persist across relaunch, clamp at the configured min/max.
  - Quit with 2+ folder windows open (varying tabs, a non-default active tab, one sidebar collapsed) → relaunch → every window restores with correct tabs/active tab/sidebar state, no extra blank Untitled window appears.
  - Quit with a restored folder, or one of its open files, deleted/renamed before relaunch → that folder/file is skipped gracefully, no crash or alert spam.
  - Quit with zero folder windows open → relaunch → normal blank Untitled document window appears (fallback path still works).
- Follows repo workflow: branch `m8-app-preferences`, run `/code-review` on the diff before opening the PR, then open the PR and stop — owner merges manually after the manual checklist is confirmed.
