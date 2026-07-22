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
  system light/dark mode.
- **Preview toggle** to hide the preview pane and edit distraction-free.
- **Native open/save** — standard macOS document handling, `.md` file
  association (Finder "Open With"), multiple documents open at once.
- **Persistent layout** — window size/position and the editor/preview split
  position are remembered per document across relaunches.

## Requirements

- macOS 14.0 or later
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
