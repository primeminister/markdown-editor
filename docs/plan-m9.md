# M9 — Preview scrolls to follow the editor cursor

## Context

`docs/plan.md`'s "Next features to implement" list asked for the preview pane to scroll to
whichever part of the document the editor cursor is in — e.g. click halfway into the file and
start editing, and the preview should already be showing that section, not sitting wherever it
last was (often the top). Confirmed with the owner:

1. Scroll target: the block matching the cursor's line is scrolled to the **vertical center** of
   the preview pane (not pinned to the top), so surrounding context stays visible above and below.
2. Scroll motion: **smooth/animated** when the cursor simply moves (click, arrow keys) — the DOM
   already matches the current text, so there's something continuous to animate between. After a
   text edit, the preview's debounced re-render (`PreviewView.swift`'s existing ~275ms debounce)
   does a full `loadHTMLString` reload, which resets `WKWebView` scroll to the top; the resync that
   follows a reload snaps **instantly** instead, since animating from a freshly reloaded blank page
   would just look like a jump-cut. This also incidentally fixes an existing quirk where every
   re-render currently leaves the preview scrolled to the top regardless of where the reader was.

**Explicitly out of scope for v1** (flagged as possible follow-ups if they turn out to matter in
practice, not designed now):
- **One-way only.** The editor cursor drives the preview scroll; scrolling the preview by hand
  never moves the editor cursor or selection.
- **No "pause while the user is manually scrolling the preview" heuristic.** If the owner scrolls
  the preview away from the cursor's block to read ahead, the next cursor move or edit will snap it
  back. This is a personal single-user two-pane editor, not a collaborative doc — the ask was
  specifically "preview follows my cursor," and idle/direction-detection heuristics are speculative
  complexity for a wishlist item.
- **No visual highlight** of the matched block in the preview — scroll position only.

## Approach

### 1. Tag rendered HTML with source line numbers (`MarkdownRenderer.swift`)

`swift-markdown`'s `Markup` nodes carry a `range: SourceRange?` (a `Range<SourceLocation>`, each
`SourceLocation` having a 1-based `.line`) when parsed via `Document(parsing: markdownText)`.
**To verify early in implementation:** that this range is populated by default with no extra parse
options — if it turns out to need an explicit option, that's a one-line change to
`Document(parsing:)`'s call site, not a design change.

Every block-level `visit*` method in `HTMLVisitor` (`visitParagraph`, `visitHeading`,
`visitCodeBlock`, `visitBlockQuote`, `visitListItem`, `visitTableRow`, `visitThematicBreak`,
`visitHTMLBlock`, `visitUnorderedList`/`visitOrderedList` for the empty-list edge case) adds
`data-source-line="\(line)"` to its opening tag, reading `markup.range?.lowerBound.line`. Tag
every block, not just top-level ones, so nested list items/blockquotes resolve to their own line
rather than their container's. Inline nodes (emphasis, links, inline code, etc.) are not tagged —
scrolling resolves at block granularity. If `range` is ever `nil`, the attribute is simply omitted
and that node isn't a scroll target (the JS lookup below skips over it).

### 2. Track the editor's cursor line (`EditorView.swift`)

Add a pure, testable helper (mirrors the project's existing "pure logic gets a unit test" split):
```swift
enum EditorCursorLocation {
    /// 1-based line number containing `characterIndex` in `text`.
    static func lineNumber(in text: String, at characterIndex: Int) -> Int
}
```
`EditorView.Coordinator` implements `NSTextViewDelegate.textViewDidChangeSelection(_:)`, computes
the line number for `textView.selectedRange().location` via the helper above, and pushes it into a
new `@Binding var cursorLine: Int` (added to `EditorView`, alongside the existing `text` binding).

### 3. Thread `cursorLine` down to the preview

Same shape as the existing `text` binding's plumbing:
- `SplitView` gains `@Binding var cursorLine: Int`, passed into `MainSplitViewController`'s
  `init`/`update(text:isPreviewVisible:cursorLine:)`, which in turn constructs
  `EditorView(text:cursorLine:...)` (read-write) and `PreviewView(text:cursorLine:...)` (read-only).
- `ContentView` adds `@State private var cursorLine: Int = 1`.
- `WorkspaceTab` (the per-tab model) adds `var cursorLine: Int = 1` as a plain stored property, same
  as `text` — this is what makes cursor-follow position survive tab switches within one workspace
  window, consistent with `MainSplitViewController`'s existing "stable instance across tab
  switches" identity (see `WorkspaceDetailView.swift`'s comment on `WorkspaceTabContentView`).
  `WorkspaceTabContentView` passes `$tab.cursorLine`.

### 4. Scroll the preview to the matching block (`PreviewView.swift`)

`Coordinator` adds `scrollToLine(_ line: Int, in webView: WKWebView, animated: Bool)`, evaluating:
```js
(function() {
  var nodes = document.querySelectorAll('[data-source-line]');
  var target = null;
  for (var i = 0; i < nodes.length; i++) {
    if (parseInt(nodes[i].getAttribute('data-source-line'), 10) <= LINE) {
      target = nodes[i];
    } else {
      break;
    }
  }
  if (target) {
    target.scrollIntoView({ block: 'center', behavior: 'ANIMATED' });
  }
})();
```
(`LINE`/`ANIMATED` substituted per call.) `querySelectorAll` returns nodes in document order and
source line numbers are monotonically non-decreasing in document order, so a linear scan for the
last node at or before the cursor's line is correct — no need for a smarter search at the file
sizes this app targets (personal notes, same reasoning `MarkdownHighlighter`'s full-rescan-per-edit
already relies on).

Two call sites:
- **`webView(_:didFinish:)`** (`WKNavigationDelegate`, already present for the external-link-open
  behavior) — after every reload, resync to the coordinator's last-known cursor line with
  `animated: false`. This is what keeps a re-render from leaving the preview stuck at the top.
- **`updateNSView`**, when `cursorLine` changed but `text` did not (pure cursor movement — click,
  arrow keys — with no pending re-render) — call with `animated: true`. Lightly debounced (~60ms,
  same `DispatchWorkItem` pattern the existing render-debounce uses) so holding an arrow key or
  drag-selecting doesn't spam `evaluateJavaScript`. When `text` *did* change, skip this path
  entirely and let the render debounce's own `didFinish` resync handle it instead, so a cursor
  update never races a content update against a stale DOM.

## Files touched
- `MarkdownEditor/MarkdownEditor/MarkdownRenderer.swift` — `data-source-line` attributes on block-level HTML output.
- `MarkdownEditor/MarkdownEditor/EditorView.swift` — `EditorCursorLocation.lineNumber(in:at:)`, `cursorLine` binding, `textViewDidChangeSelection`.
- `MarkdownEditor/MarkdownEditor/PreviewView.swift` — `cursorLine` param, `scrollToLine`, debounced cursor-driven scroll, post-reload resync.
- `MarkdownEditor/MarkdownEditor/SplitView.swift` — `cursorLine` binding threaded through `SplitView`/`MainSplitViewController`.
- `MarkdownEditor/MarkdownEditor/ContentView.swift` — `@State private var cursorLine`.
- `MarkdownEditor/MarkdownEditor/WorkspaceDetailView.swift` — passes `$tab.cursorLine`.
- `MarkdownEditor/MarkdownEditor/WorkspaceTab.swift` — new `cursorLine` stored property, reset on file switch.
- `MarkdownEditor/MarkdownEditor/CheatsheetView.swift` — new `cursorLine` state for its `SplitView` call site.

## Automated tests (`MarkdownEditorTests`)
- `EditorCursorLocation.lineNumber(in:at:)` — start of file, mid-line, exact line boundaries (right after a `\n`), last line with/without a trailing newline, empty string.
- `MarkdownRenderer`: `data-source-line` values are present and correct on paragraphs, headings, list items (including nested), code blocks, blockquotes, and table rows for a small multi-block fixture.
- Everything else (`WKWebView` JS execution, live `NSTextView` selection/scroll behavior) is AppKit/WebKit runtime behavior with no pure-logic seam — manual-only, consistent with the project's existing testing split (same reasoning as M5–M8).

## Verification
- Build: `xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`.
- Automated: `xcodebuild test -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'` — existing suite must still pass, plus the new cases above.
- Manual (owner's Mac, per project workflow — hand off the checklist, wait for go-ahead before merge):
  - Open a long `.md` file, click roughly halfway down the editor — preview smoothly scrolls to center the corresponding section.
  - Move the cursor with arrow keys / click around without editing — preview keeps following, no stutter or runaway `evaluateJavaScript` calls when holding an arrow key.
  - Type at the cursor — preview re-renders (existing debounce) and lands centered on the same section instead of resetting to the top.
  - Scroll the preview away by hand, then move the cursor or keep typing — preview snaps back to the cursor's section (confirms the deliberate one-way, no-pause-heuristic behavior).
  - In a folder/workspace window, switch between two tabs with cursors left in different parts of their files — each tab's preview resumes following its own remembered cursor line, not the other tab's.
  - Toggle preview visibility off then back on mid-edit — no crash, scroll-follow resumes correctly once visible again.
  - Works the same in both a single-file `DocumentGroup` window and a folder/workspace window.
- Follows repo workflow: branch `m9-cursor-synced-preview-scroll`, run `/code-review` on the diff before opening the PR, then open the PR and stop — owner merges manually after the manual checklist is confirmed.
