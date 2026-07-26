# markdown-editor

A native macOS markdown editor: a plain-text editor with markdown syntax
highlighting on one side, and a live rendered preview on the other. Built for
personal use — no App Store, no accounts, no cloud sync of its own. It just
opens and saves `.md` files; syncing them between machines (Dropbox, iCloud
Drive, git, whatever) is up to you.

## Features

- **Two-pane layout** — plain-text editor with syntax highlighting alongside
  a live HTML preview, not inline/WYSIWYG rendering.
- **Syntax highlighting** for headers, bold, italic, inline code, links,
  fenced code blocks, and blockquotes.
- **Live preview** with support for tables, nested lists, and code fences;
  external links open in your default browser instead of in-pane; follows
  system light/dark mode. The preview scrolls to follow the editor cursor,
  smoothly centering the corresponding rendered block as you move around the
  document.
- **Preview toggle** to hide the preview pane and edit distraction-free.
- **Native open/save** — standard macOS document handling, `.md` file
  association (Finder "Open With"), multiple documents open at once.
- **Persistent layout** — window size/position and the editor/preview split
  position are remembered per document across relaunches.
- **Open Folder** (`File > Open Folder…`, or drag a folder onto the app) —
  a workspace window with a full-height sidebar showing the folder's file
  tree; non-markdown files are visible for context but disabled. Single-click
  loads a file into the window's editor/preview; double-clicking a file
  directly in Finder still opens the plain single-file window.
- **In-window tabs** — single-click browsing reuses one "preview" tab;
  double-click, or editing that tab's content, promotes it to a permanent
  tab. The sidebar can be collapsed to an icon-only rail.
- **Keyboard shortcuts** — ⌘/ toggles the preview pane, ⌘B toggles the
  sidebar (folder windows), ⌘+/⌘−/⌘0 adjust/reset the editor's font size.
  Shortcuts are customizable in app preferences.
- **Session restore** — folder windows open at quit (tabs, active tab,
  sidebar state) are restored on next launch.
- **Markdown syntax cheatsheet** (`Help` menu) — a read-only editor/preview
  window showing common Markdown syntax side by side with its rendered
  output.

## Requirements

- macOS 15.6 or later
- Xcode (full install, not just Command Line Tools) to build

## Building and running

Open `MarkdownEditor/MarkdownEditor.xcodeproj` in Xcode and run (⌘R), or from
the command line:

```sh
xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build
```

Xcode resolves the one dependency ([`swift-markdown`](https://github.com/swiftlang/swift-markdown))
automatically via Swift Package Manager.

## Project layout

See `CLAUDE.md` for the full architecture breakdown and test commands, and
`docs/plan.md` for the original design plan and milestones this was built
against.
