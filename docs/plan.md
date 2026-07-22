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
   - Interface: SwiftUI, Language: Swift, uncheck "Include Tests"
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
```

Key design decisions:
- **Document model** is a plain `FileDocument` (value type) holding a `String`; `EditorView`'s Coordinator holds its own live text buffer and only pushes to the SwiftUI binding, so AppKit's per-keystroke mutation doesn't force SwiftUI to diff the whole document each keystroke.
- **UTType**: import `net.daringfireball.markdown` (the de facto standard other markdown apps use) and export our own `nl.mowd.markdown-editor.markdown` conforming to it — both conforming to `public.plain-text`. If another markdown app is already the default `.md` handler, a one-time `Get Info > Open With > Change All…` is needed — macOS won't silently reassign it.
- **Editor**: `NSTextView`, not SwiftUI `TextEditor`, for undo grouping and attribute-level control. Disable smart quotes/dashes (they corrupt literal markdown syntax). Monospaced font. Highlighting via precompiled `NSRegularExpression`s applied in `NSTextStorageDelegate.textStorage(_:didProcessEditingFor:range:changeInLength:)`. Start with a simple full-document rescan per edit (personal note files are small — sub-millisecond); don't build incremental/debounced highlighting until it's actually observed to lag.
- **Preview**: parse with `swift-markdown`, walk with a custom `MarkupVisitor` emitting HTML (covers GFM tables, nested lists, code fences "for free" via `<table>`/`<ul>`/`<pre>` instead of hand-rolled SwiftUI layout), render in `WKWebView` with a small bundled CSS file. Escape raw HTML in source rather than passing it through. Debounce re-render (~250-300ms) since a full WKWebView reload per keystroke would stutter — unlike the cheap editor highlighter.

### Milestones (each independently runnable/testable)

1. **M1 — skeleton, open/save round-trip.** Stock `TextEditor(text: $document.text)` temporarily; Info.plist UTI edits. Verify: create/save/reopen a `.md` file, confirm Finder "Open With" lists the app.
2. **M2 — custom editor + highlighting.** Swap in `EditorView`/`MarkdownHighlighter`. Verify: undo/redo works, all 7 token types render distinctly, typing feels instant on a ~500-line file.
3. **M3 — live preview.** Add `swift-markdown`, `MarkdownRenderer`, `PreviewStyle.css`, `PreviewView`, assemble `HSplitView`. Verify: tables/nested lists/code fences render correctly, external links open in browser not in-pane, dark/light mode switches live.
4. **M4 — polish.** Preview toggle, live word count, window/split-position restoration. Verify: toggle doesn't glitch layout, count updates live, state persists across relaunch.

Later, headless build verification is possible via `xcodebuild -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`, but the UX checks above require actually running the app.
