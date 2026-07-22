# Plan: personal macOS markdown editor

## Context

Existing markdown editors are too bloated, paid, or built on stale (2017-era) code. This app is for personal use only, on 2 of the owner's own Macs — no App Store, no distribution pipeline, no need for iCloud-specific sync code.

Decisions:
- **Editing style:** classic two-pane layout — plain text editor with markdown syntax highlighting on one side, rendered preview on the other (not WYSIWYG/inline rendering).
- **Sync:** plain `.md` files on disk; syncing between devices (Dropbox/iCloud Drive/git) is the user's own responsibility. The app just opens/saves `.md` files anywhere.
- **Distribution:** build & run from Xcode on each Mac.

**Environment note:** only Xcode Command Line Tools are installed on this machine, not full Xcode. Full Xcode must be installed from the App Store before the project can be created or built.

## Approach

A standard SwiftUI document-based app (`DocumentGroup`/`FileDocument`), using Apple's `swift-markdown` package for parsing, `NSTextView` for the editor pane (real undo/selection/attribute control), and `WKWebView` for the preview pane (markdown → HTML → styled with a small bundled CSS file). Fully native, no heavy third-party dependencies.

### Step 0 — one-time manual setup (in Xcode GUI)

1. Install full Xcode from the App Store; launch once to accept license/install components.
2. `File > New > Project…` → macOS → **Application > Document App** template (not plain "App" — this scaffolds `DocumentGroup`/`FileDocument`/UTType plumbing for free).
   - Product Name: `MarkdownEditor`
   - Organization Identifier: `nl.mowd` → bundle id `nl.mowd.MarkdownEditor`
   - Interface: SwiftUI, Language: Swift, **check "Include Tests"** (Testing System: Swift Testing) — scaffolds a `MarkdownEditorTests` target
   - Location: this repo folder; uncheck "Create Git repository" (one already exists)
   - Deployment target: macOS 14.0 (bump higher if both Macs are confirmed newer)
3. `File > Add Package Dependencies…` → `https://github.com/swiftlang/swift-markdown.git` → Up to Next Major Version from `0.8.0` → add `Markdown` library to the target.

Once the project exists, verify the source folder shows as a plain (non-yellow) group in the Project Navigator — modern Xcode uses file-system-synchronized groups, so `.swift` files dropped on disk are auto-added to the target with no further GUI steps.

### Files to create (after Step 0)

```
MarkdownEditor/
  MarkdownEditorApp.swift   – @main App, DocumentGroup scene
  MarkdownDocument.swift    – FileDocument struct + UTType.markdownText
  ContentView.swift         – HSplitView(EditorView | PreviewView), toolbar, word count, preview toggle
  EditorView.swift          – NSViewRepresentable/NSTextView wrapper + Coordinator (NSTextStorageDelegate)
  MarkdownHighlighter.swift – NSRegularExpression rules + attribute application (headers, bold, italic, inline code, links, fenced code, blockquotes)
  PreviewView.swift         – NSViewRepresentable/WKWebView wrapper + WKNavigationDelegate (opens external links in default browser, not in-pane)
  MarkdownRenderer.swift    – swift-markdown MarkupVisitor → HTML string + HTML document shell
  PreviewStyle.css          – bundled resource: typography, code/table/blockquote styling, dark-mode via prefers-color-scheme
  Info.plist                – edit in place: UTImportedTypeDeclarations (net.daringfireball.markdown), UTExportedTypeDeclarations (nl.mowd.markdown-editor.markdown), CFBundleDocumentTypes
and other bundles
```

Key design decisions:
- **Document model** is a plain `FileDocument` (value type) holding a `String`; `EditorView`'s Coordinator holds its own live text buffer and only pushes to the SwiftUI binding, so AppKit's per-keystroke mutation doesn't force SwiftUI to diff the whole document each keystroke.
- **UTType**: import `net.daringfireball.markdown` (the de facto standard other markdown apps use) and export our own `nl.mowd.markdown-editor.markdown` conforming to it — both conforming to `public.plain-text`. If another markdown app is already the default `.md` handler, a one-time `Get Info > Open With > Change All…` is needed — macOS won't silently reassign it.
- **Editor**: `NSTextView`, not SwiftUI `TextEditor`, for undo grouping and attribute-level control. Disable smart quotes/dashes (they corrupt literal markdown syntax). Monospaced font. Highlighting via precompiled `NSRegularExpression`s applied in `NSTextStorageDelegate.textStorage(_:didProcessEditingFor:range:changeInLength:)`. Start with a simple full-document rescan per edit (personal note files are small — sub-millisecond); don't build incremental/debounced highlighting until it's actually observed to lag.
- **Preview**: parse with `swift-markdown`, walk with a custom `MarkupVisitor` emitting HTML (covers GFM tables, nested lists, code fences "for free" via `<table>`/`<ul>`/`<pre>` instead of hand-rolled SwiftUI layout), render in `WKWebView` with a small bundled CSS file. Escape raw HTML in source rather than passing it through. Debounce re-render (~250-300ms) since a full WKWebView reload per keystroke would stutter — unlike the cheap editor highlighter.

### Testing strategy

Two layers, kept deliberately separate:

- **Automated (Swift Testing, `MarkdownEditorTests` target).** Only pure logic gets unit tests — anything that's a plain function/struct taking input and returning output, no `NSTextView`/`WKWebView`/`DocumentGroup` involved:
  - `MarkdownDocument`: string round-trips through `init(configuration:)`/`fileWrapper(configuration:)`.
  - `MarkdownHighlighter`: given source text, each of the 7 token types (headers, bold, italic, inline code, links, fenced code, blockquotes) produces the expected match ranges.
  - `MarkdownRenderer`: given markdown input, the emitted HTML contains the expected structure (tables, nested lists, code fences) and raw HTML in source is escaped, not passed through.
  - ~~Word count / other small pure helpers introduced in M4.~~
  - Runs via `xcodebuild test -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'`, both locally and in CI (see below).
- **Manual (per milestone, on the owner's own Mac).** Anything involving actual AppKit views, window chrome, or feel-under-typing — the "Verify:" bullets below. Claude builds and launches the app (`xcodebuild build` then `open`) after each milestone's PR is ready; the owner clicks through the checklist and gives go-ahead before merge. These are not automated and not worth trying to automate for a 2-machine personal app.

**CI:** `.github/workflows/ci.yml`, added as part of the M1 PR (needs the `.xcodeproj` to exist first) — runs `xcodebuild test` on `macos-latest` for every push/PR. Gates merges on the automated layer; the manual layer is a separate, human-in-the-loop gate per milestone.

### Milestones (each independently runnable/testable)

1. [x] **M1 — skeleton, open/save round-trip.** Stock `TextEditor(text: $document.text)` temporarily; Info.plist UTI edits; add `MarkdownDocument` round-trip tests; add `.github/workflows/ci.yml`. Verify: create/save/reopen a `.md` file, confirm Finder "Open With" lists the app.
2. [x] **M2 — custom editor + highlighting.** Swap in `EditorView`/`MarkdownHighlighter`; add `MarkdownHighlighter` unit tests covering all 7 token types. Verify: undo/redo works, all 7 token types render distinctly, typing feels instant on a ~500-line file.
3. [x] **M3 — live preview.** Add `swift-markdown`, `MarkdownRenderer`, `PreviewStyle.css`, `PreviewView`, assemble `HSplitView`; add `MarkdownRenderer` unit tests (tables, nested lists, code fences, HTML-escaping). Verify: tables/nested lists/code fences render correctly, external links open in browser not in-pane, dark/light mode switches live.
4. [x] **M4 — polish.** Preview toggle, ~~live word count~~, window/split-position restoration; ~~unit-test the word count helper.~~ Verify: toggle doesn't glitch layout, ~~count updates live~~, state persists across relaunch.
5. [x] **M5 — Open Folder + sidebar, single-window file switching (no tabs yet).**
   - `File > Open Folder…` menu command (`NSOpenPanel`, directory mode). Also route Finder-side opening (drag a folder onto the app / right-click "Open With") through `application(_:open:)` on an `NSApplicationDelegateAdaptor` — this requires declaring `public.folder` handling in `Info.plist` separately from the existing `.md` UTI declarations, since Finder won't offer "Open With" for a folder otherwise.
   - New workspace window type (a second scene alongside the existing `DocumentGroup`, e.g. `WindowGroup`) with a sidebar showing the full recursive file tree of the opened folder, plus the existing `SplitView` editor/preview for whichever file is active. Sidebar is shown by default when a folder is opened.
   - Sidebar shows every file in the tree, but only `.md` files are active/clickable — all other files render grayed out/disabled and do nothing on click. This gives full folder context without implying non-markdown files are editable here.
   - Single-click on an active (`.md`) sidebar file loads it into that window's editor/preview, replacing whatever was previously shown (no tabs yet — every click just swaps content in place).
   - Opening a `.md` file directly from Finder is unchanged: existing `DocumentGroup` single-file window, no sidebar.
   - Verify: open a folder, sidebar appears by default with the full tree, non-`.md` files are visibly disabled and inert, single-click swaps `.md` files in place; double-clicking a `.md` file directly in Finder still opens the old plain editor window with no sidebar.
6. [x] **M6 — Native tabs + preview/permanent tab promotion.**
   - Double-click an active sidebar file opens it in a new native macOS window tab (`NSWindow.addTabbedWindow`) within the same folder's tab group; every tab in the group shows the same sidebar.
   - Track one "preview" tab per tab group: single-click always reuses/replaces that tab's content (bringing it to front); double-click, or editing the preview tab's content, promotes it to a permanent tab, and the next single-click gets a fresh preview tab.
   - Verify: single-click browsing never spawns tabs; double-click or typing pins the file as a permanent tab; pinned tabs survive further single-click browsing elsewhere in the sidebar.
7. [ ] **M7 — Custom in-window tabs + persistent full-height sidebar.** Full design in `docs/plan-m7.md`.
   - Replace M6's native window-tabs with a custom in-app tab strip: one real window per folder, sidebar spans the full window height (untouched by tab switching), tabs appear only above the editor/preview pane, sized to the filename.
   - Same preview/permanent-tab promotion behavior as M6, re-scoped from "tab = window" to "tab = a slot in one window's tab strip." Tabs get a close button only (drag-reorder, keyboard shortcuts, context menu deferred).
   - Sidebar gets a show/hide toggle (icon top-right of the sidebar); collapsing shrinks it to a narrow rail that still shows the icon, rather than hiding it entirely.
   - Verify: one window per folder with no OS-level tab bar; single-click/double-click/edit-promotion behavior matches M6; closing the last tab leaves the window/sidebar open in the empty state; sidebar toggle animates between full width and icon-only rail and persists across relaunch.

Headless build/test verification: `xcodebuild -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build` and `... test ...` (see Testing strategy). The "Verify:" bullets above require actually running the app on the owner's Mac.


## Next features to implement:
1. App preferences:
	- keyboard shortcut to turn on/off preview
	- Other suggestions?
2. When clicking help we have an extra menu that displays the contents of https://www.markdownguide.org/cheat-sheet/ for Markdown cheatsheet
3. Scrolling preview where the cursor is in the editor.
