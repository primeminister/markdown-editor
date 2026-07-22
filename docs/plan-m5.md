# M5 — Open Folder + sidebar, single-window file switching

## Context

`docs/plan.md` (merged in PR #8) defines M5: a `File > Open Folder…` command that opens a sidebar showing the folder's full file tree (only `.md`/`.markdown` files active/clickable, everything else grayed out and inert), with single-click loading a file into that window's editor/preview in place. Opening `.md` files directly from Finder must keep working exactly as today (existing `DocumentGroup` single-file window, no sidebar). Tabs and the preview/permanent-tab promotion model are explicitly deferred to M6.

The current app is built entirely on SwiftUI's `DocumentGroup` (`MarkdownEditorApp.swift`), which is strictly one-file-per-window. This milestone introduces a second, manually-managed window kind for folders, alongside the existing per-file `DocumentGroup` windows — without disturbing the latter.

## Approach

### 1. `Info.plist` — declare folder handling

Add a second entry to the existing `CFBundleDocumentTypes` array:
```xml
<dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>public.folder</string>
    </array>
</dict>
```
This is what makes Finder offer "Open With > MarkdownEditor" for a folder and route it through `application(_:open:)`. (Manual verify only — Launch Services registration isn't observable from a headless build.)

### 2. `AppDelegate.swift` (new) — route Finder opens by URL kind

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue {
                WorkspaceWindowManager.shared.open(folder: url)
            } else {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
    }
}
```
Wired in via `@NSApplicationDelegateAdaptor(AppDelegate.self)` in `MarkdownEditorApp`. Supplying our own delegate means `DocumentGroup`'s built-in open-URL handling no longer fires automatically for this method, so plain `.md` opens are explicitly forwarded to `NSDocumentController` to preserve today's behavior exactly (same object `DocumentGroup` uses internally). This is the main regression risk for existing behavior and gets its own manual verify step.

### 3. `WorkspaceWindowManager.swift` (new) — imperative window management

A small class (not a SwiftUI `Scene`) that owns folder windows directly, since M6 will need raw `NSWindow` access for `addTabbedWindow` anyway — better to have one window-creation path than to mix a `WindowGroup(for:)` scene now and refactor to manual windows next milestone.

```swift
final class WorkspaceWindowManager {
    static let shared = WorkspaceWindowManager()
    private var windows: [URL: NSWindow] = [:]

    func presentOpenPanel() { /* NSOpenPanel, directories only -> open(folder:) */ }

    func open(folder url: URL) {
        // key = url.standardizedFileURL; dedupe same folder via makeKeyAndOrderFront if already open
        // else construct one WorkspaceAutosaveController for this window, build
        // NSWindow(contentViewController: NSHostingController(rootView: WorkspaceView(folderURL: key, autosave: autosave)))
        // title = url.lastPathComponent
        // setFrameAutosaveName("MainWindow-\(key.path)") -- same name MainSplitViewController applies
        // once a file is first selected; applied here too so the frame is covered before any file is picked
        // observe NSWindow.willCloseNotification -> autosave.flush(), then remove from `windows`
    }
}
```
Keyed by `url.standardizedFileURL` so equivalent-but-differently-formed paths (trailing slash, relative components) dedupe correctly.

### 4. `MarkdownEditorApp.swift` — wire up the delegate + menu command

Add `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Add a `.commands { CommandGroup(after: .newItem) { Button("Open Folder…") { WorkspaceWindowManager.shared.presentOpenPanel() }.keyboardShortcut("o", modifiers: [.command, .shift]) } }`. No new `Scene` needed — `DocumentGroup` is untouched.

### 5. `FileNode.swift` (new) — pure file-tree model

```swift
struct FileNode: Identifiable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let isMarkdown: Bool
    var children: [FileNode]?  // nil for files; populated (possibly empty) for directories
}
```
Static builder `FileNode.build(from url: URL) -> FileNode` recursively walks via `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:.skipsHiddenFiles)`, sorting directories before files, then case-insensitive alphabetically; `isMarkdown` true for `.md`/`.markdown` extensions (matching the extensions already declared in `Info.plist`'s UTI). This is pure enough to unit test with real temp directories (`FileManager` on a `NSTemporaryDirectory()` subpath), same spirit as existing tests — new `FileTreeTests.swift` in `MarkdownEditorTests` covering: folders-before-files ordering, hidden-file exclusion, correct `isMarkdown` flagging, nested-subfolder recursion.

### 6. `WorkspaceAutosaveController.swift` (new) — debounced autosave

`WorkspaceView` is a plain SwiftUI `View`, but the autosave debounce timer needs one identity reachable both from the view (on file switch) and from `WorkspaceWindowManager`'s `NSWindow.willCloseNotification` observer (on window close) — a `@State`-owned timer wouldn't be reachable from the latter. So this is a small `@MainActor` reference-type class, constructed once per workspace window by `WorkspaceWindowManager` and handed to `WorkspaceView` as a `let`:

```swift
@MainActor
final class WorkspaceAutosaveController {
    private static let debounceInterval: TimeInterval = 0.5
    private var pendingWorkItem: DispatchWorkItem?
    private var pendingURL: URL?
    private var pendingText: String?

    func schedule(text: String, to url: URL) {
        pendingWorkItem?.cancel()
        pendingURL = url
        pendingText = text
        let workItem = DispatchWorkItem { [weak self] in
            self?.write(text: text, to: url)
            self?.pendingWorkItem = nil
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }

    /// Synchronous — called on file switch and on window close so no pending edit is lost.
    func flush() {
        guard let workItem = pendingWorkItem, let url = pendingURL, let text = pendingText else { return }
        workItem.cancel()
        write(text: text, to: url)
        pendingWorkItem = nil
        pendingURL = nil
        pendingText = nil
    }

    private func write(text: String, to url: URL) {
        try? MarkdownDocument.encodeText(text).write(to: url)
    }
}
```

This mirrors the codebase's existing debounce idiom used by `PreviewView.Coordinator` for re-render (a cancelable `DispatchWorkItem` + `DispatchQueue.main.asyncAfter`, not `Task`/`sleep`) — applied here to disk writes instead of re-rendering. `flush()` is called synchronously both on file switch (inside `WorkspaceView.selectFile(_:)`, before reassigning `text`) and from `WorkspaceWindowManager`'s `NSWindow.willCloseNotification` observer, so no pending edit is ever lost — more deterministic than relying on `.onDisappear`, which doesn't reliably fire for SwiftUI content hosted as a raw `NSWindow`'s `contentViewController`.

### 7. `WorkspaceView.swift` (new) — sidebar + reused editor/preview

```swift
struct WorkspaceView: View {
    let folderURL: URL
    let autosave: WorkspaceAutosaveController

    @State private var root: FileNode
    @State private var selectedFileURL: URL?
    @State private var text: String = ""
    @State private var loadedText: String = ""
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true

    init(folderURL: URL, autosave: WorkspaceAutosaveController) {
        self.folderURL = folderURL
        self.autosave = autosave
        _root = State(initialValue: FileNode.build(from: folderURL))
    }

    var body: some View {
        NavigationSplitView {
            List(root.children ?? [], children: \.children) { node in
                FileRow(node: node, isSelected: node.url == selectedFileURL)
                    .onTapGesture { if node.isMarkdown { selectFile(node.url) } }
            }
        } detail: {
            if selectedFileURL != nil {
                SplitView(text: $text, isPreviewVisible: $isPreviewVisible, autosaveIdentifier: folderURL.path)
                    .onChange(of: text) { _, newValue in
                        guard let url = selectedFileURL, newValue != loadedText else { return }
                        autosave.schedule(text: newValue, to: url)
                    }
            } else {
                ContentUnavailableView("Select a Markdown File", systemImage: "doc.text")
            }
        }
    }

    private func selectFile(_ url: URL) {
        guard url != selectedFileURL else { return }
        autosave.flush()
        do {
            let data = try Data(contentsOf: url)
            let loaded = try MarkdownDocument.decodeText(from: data)
            loadedText = loaded
            text = loaded
            selectedFileURL = url
        } catch {
            // Read failed (permissions, race with external delete) — leave the previously shown file untouched.
        }
    }
}
```
Key points:
- **Reuses `SplitView` as-is** (`SplitView.swift`) — it already takes a `text`/`isPreviewVisible` binding and an `autosaveIdentifier`; no changes needed there.
- **`autosaveIdentifier: folderURL.path`, not per-file.** `MainSplitViewController` (inside `SplitView.swift`) only ever reads `autosaveIdentifier` once — `splitView.autosaveName` is set in `init`, and `setFrameAutosaveName` in `viewDidAppear` is guarded to fire once per controller instance. `SplitView.updateNSViewController` never re-derives it. Since the `detail:` branch keeps the same `SplitView` identity for the life of the window once any file is first selected, `makeNSViewController` runs exactly once — so a per-file identifier (as originally sketched) would silently freeze to whichever file was selected *first*, not rotate per file. The correct scope for a per-window concern like frame/divider position is the folder, not the file: `WorkspaceView` passes `folderURL.path`, giving stable keys `"MainSplit-\(folderURL.path)"` (divider) and `"MainWindow-\(folderURL.path)"` (frame) across file switches within one window. Trade-off: the divider position is shared across all files in a workspace window, not remembered per-file — an acceptable M5 simplification. `WorkspaceWindowManager` also applies the identical `"MainWindow-\(url.path)"` frame-autosave name immediately at window creation (see below), covering the frame before any file is selected.
- `FileRow` renders directories/non-markdown files with `.foregroundStyle(.tertiary)` and no tap action (disclosure-only via List's native recursive-children expansion); markdown files are full-opacity and tappable.
- `selectFile(_:)` flushes any pending debounced save for the *previous* file synchronously (via `autosave.flush()`) before reassigning `text`/`selectedFileURL`, then reads the new file via `Data(contentsOf:)` + the existing `MarkdownDocument.decodeText(from:)` helper (reuse, don't reimplement UTF-8 decoding).
- The `loadedText` guard in the `onChange(of: text)` handler prevents the load-triggered text assignment in `selectFile` from immediately re-scheduling a pointless (unchanged-content) save.

### Code-review fixes applied after initial implementation

`/code-review` on the implementation diff (10 confirmed findings, run before opening the PR) surfaced several real bugs beyond the two design issues already covered above. Fixed in place:

- **Undo corruption across file switches.** Because the same `NSTextView` persists across file switches (by design, per the autosave-identifier fix above), switching files only replaced the text buffer — it never cleared the text view's undo stack. Cmd-Z after switching files would replay the *previous* file's edit against the *new* file's buffer, corrupting it, and the corruption would then get autosaved to disk. Fixed in `EditorView.updateNSView` by calling `textView.undoManager?.removeAllActions()` immediately after any programmatic full-buffer replacement (the same branch that already detects "content changed for a reason other than local typing").
- **Non-atomic autosave write, and swallowed write errors.** `WorkspaceAutosaveController.write(text:to:)` now writes with `.atomic` (matching how `DocumentGroup`'s own save path is safe against a mid-write crash/power-loss) and logs failures via `OSLog` instead of discarding them with `try?`.
- **Cmd+Q could drop the last debounced edit.** These are plain `NSWindow`s, not `NSDocument`-backed ones tracked by `NSDocumentController`, so they aren't guaranteed a `willCloseNotification` during app termination — a pending debounced write within the 0.5s window could be lost on quit. Fixed by having `AppDelegate` implement `applicationWillTerminate(_:)`, which calls a new `WorkspaceWindowManager.flushAllPendingAutosaves()` that flushes every open workspace window's autosave controller (tracked in a new `autosaveControllers: [URL: WorkspaceAutosaveController]` dict alongside the existing `windows` dict).
- **Full recursive folder walk blocked the main thread on open.** `FileNode.build(from:)` has no size/depth limit, so a large folder (a big docs repo, an Obsidian vault) could hang the UI for the whole scan. `FileNode` is now declared `nonisolated` (matching `MarkdownDocument`'s existing convention) so the walk can run via `Task.detached(priority: .userInitiated)`; `WorkspaceView.root` is now `FileNode?` (nil while loading, populated via `.task` once the detached build completes), with a `ProgressView` shown in the sidebar meanwhile.
- **Silently swallowed file errors gave no feedback.** Both `AppDelegate`'s Finder-open forwarding (`NSDocumentController.openDocument`'s discarded completion error) and `WorkspaceView.selectFile`'s read/decode failure now present an `NSAlert` instead of failing invisibly — matching what `DocumentGroup`'s own error path would have shown for the same failure before this branch existed.
- **`"MainWindow-<path>"` name duplicated across two files.** `WorkspaceWindowManager.open(folder:)` and `MainSplitViewController.viewDidAppear` each independently typed out the same autosave-name format string, risking silent drift if one changed without the other. Extracted into a shared `SplitViewAutosaveNaming` enum (`SplitView.swift`) with `windowName(for:)`/`splitName(for:)`, used by both.

Not fixed, judged an acceptable trade-off (noted in the PR description rather than addressed in code): the new `public.folder` `Info.plist` entry has no narrower UTI to scope it to "markdown workspace folders" specifically — `public.folder` is the only folder UTI, so the app is offered as an Open-With candidate for any folder system-wide, the same trade-off any "open a project folder" app (e.g. VS Code) makes.

### Out of scope for M5 (explicitly deferred)
- Tabs, preview/permanent-tab promotion — M6.
- Creating/renaming/deleting files from the sidebar — not requested.
- Explicit save UI / dirty indicators — autosave per above, confirmed with the owner.

## Files touched
- `MarkdownEditor/MarkdownEditor/Info.plist` (edit)
- `MarkdownEditor/MarkdownEditor/MarkdownEditorApp.swift` (edit)
- `MarkdownEditor/MarkdownEditor/AppDelegate.swift` (new)
- `MarkdownEditor/MarkdownEditor/WorkspaceWindowManager.swift` (new)
- `MarkdownEditor/MarkdownEditor/WorkspaceAutosaveController.swift` (new)
- `MarkdownEditor/MarkdownEditor/FileNode.swift` (new)
- `MarkdownEditor/MarkdownEditor/WorkspaceView.swift` (new)
- `MarkdownEditor/MarkdownEditorTests/FileTreeTests.swift` (new)

## Verification
- Automated: `xcodebuild test -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'` — new `FileTreeTests` plus existing suite must pass.
- Build: `xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`.
- Manual (owner's Mac, per project workflow — hand off the checklist, wait for go-ahead before merge):
  - `File > Open Folder…` opens a window with the sidebar showing the full recursive tree; non-`.md` files/folders are visibly grayed out and clicking them does nothing.
  - Single-clicking a `.md` file loads it into the editor/preview, replacing whatever was shown before.
  - Edit a file, switch to another file, switch back — edit is preserved (autosave-on-switch works, no data loss).
  - Drag a folder onto the app icon (or Finder right-click > Open With) opens the same sidebar window.
  - Double-clicking a `.md` file directly in Finder still opens the existing plain single-file window with **no** sidebar (regression check on the `AppDelegate` rerouting).
  - Workspace window frame position persists across relaunch.
- Follows repo workflow: branch `m5-folder-sidebar`, run `/code-review` on the diff before opening the PR, then open PR and stop — owner merges manually after the manual checklist is confirmed.
