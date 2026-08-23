# M10 — Formatting toolbar with keyboard shortcuts

## Context

`docs/plan.md`'s "Next features to implement" note asked for a formatting toolbar (H1-3, bold, italic, code, etc.) so markdown files can be edited faster without hand-typing syntax. This became milestone M10, scoped through discussion with the owner into a concrete spec (below), then a technical design was worked out against the current codebase and verified against the actual source of `EditorView.swift`, `SplitView.swift`, `MarkdownEditorApp.swift`, and `MarkdownHighlighter.swift`.

Two things shape the design:

1. **No existing "reach the focused editor" registry covers both window types.** `WorkspaceWindowManager.toggleSidebarForKeyWindow()` only enumerates folder/workspace `NSWindow`s (single-file `DocumentGroup` windows have no equivalent). Building a new registry would duplicate what AppKit's responder chain already gives for free.
2. **Exactly one `NSTextView` per window**, reused across tabs in folder windows — so there's never ambiguity about *which* text view within a window, only whether one is focused at all.

## Product spec (finalized with the owner)

**10 toolbar buttons**, in a thin bar directly above the editor pane only (not over preview, not in the window's top `.toolbar`): Heading 1/2/3 (separate buttons), Bold, Italic, Strikethrough, Inline code, Fenced code block, Blockquote, Link. SF Symbols only, no custom asset files.

**Toggle behavior**: every action is a smart toggle. Re-invoking it on already-formatted text/line removes the formatting instead of double-wrapping. No separate "clear formatting" control.

**No-selection behavior**: wrapping actions (bold/italic/strikethrough/inline-code/fenced-code/link) with a bare cursor insert empty markers with the cursor landing between them. Line-prefix actions (heading, blockquote) apply to the current line.

**Heading level switching**: pressing e.g. ⌘2 on a line that's already H1 sets it to H2 (replaces the prefix) — a line has one heading level. Only pressing the same level again toggles it off.

**Blockquote multi-line scope**: toggling with a multi-line selection applies to every line the selection touches (like Xcode's ⌘/ comment-toggle), not just the current line.

**Keyboard shortcuts** — all 10 new, plus 2 reassignments freeing up ⌘B for Bold:

| Action | Shortcut |
|---|---|
| Heading 1 / 2 / 3 | ⌘1 / ⌘2 / ⌘3 |
| Bold | ⌘B |
| Italic | ⌘I |
| Strikethrough | ⌘⇧X |
| Inline code | ⌘E |
| Fenced code block | ⌘⇧C |
| Blockquote | ⌘⇧> |
| Link | ⌘K |
| Toggle sidebar | ⌘/ (was ⌘B) |
| Toggle preview | ⌘⇧P (was ⌘/) |

⌘0 stays "Reset font size" (M8, unchanged) — heading removal is just the ⌘1/⌘2/⌘3 toggle-off, no dedicated shortcut needed.

**Syntax emitted** (matches what `MarkdownHighlighter` already recognizes): Bold `**text**`, Italic `*text*`, Inline code `` `text` ``, Fenced code `` ```\ntext\n``` ``, Blockquote `> ` per line, Link `[text](url)`, Heading `#`/`##`/`###` + space. **Strikethrough `~~text~~` is new** — not currently a highlighter token type, so this milestone also extends `MarkdownHighlighter.swift` with an 8th token type (regex, attributes, tests) to keep it visually consistent with the other 7.

## Design

### 1. Toggle-detection reuses `MarkdownHighlighter.matches`

`MarkdownFormatter` (new, pure) calls `MarkdownHighlighter.matches(in: text)` and checks whether an existing token of the action's type fully contains the current selection — this can never disagree with what's already colored in the editor, since it's the same regexes. A partially-overlapping selection (e.g. selecting just `bol` inside `**bold**`) is treated as *not* formatted — out of scope.

- Toggle off: replace the matched token's full range with its inner (marker-stripped) text.
- Toggle on: wrap the selection, or insert an empty marker pair with the cursor between them if the selection is empty.

### 2. `MarkdownFormatter.swift` (new) — pure logic, unit-testable

```swift
enum MarkdownFormattingAction: CaseIterable {
    case heading1, heading2, heading3
    case bold, italic, strikethrough
    case inlineCode, fencedCode
    case blockquote, link
}

struct MarkdownFormattingEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
    let selectionInReplacement: NSRange  // relative to replacementText
}

enum MarkdownFormatter {
    static func apply(
        _ action: MarkdownFormattingAction,
        to text: String,
        selection: NSRange,
        clipboardURL: String? = nil
    ) -> MarkdownFormattingEdit
}
```

One private helper per shape, mirroring `MarkdownHighlighter`'s "one rule per type" structure, all using `NSString`/`NSRange` (not `String.Index`) consistent with the rest of the codebase:

- **`wrapToggle`** (bold `**`, italic `*`, strikethrough `~~`, inline code `` ` ``): strips/adds `marker` at both ends of the containing token or selection.
- **`fencedCodeToggle`**: block-level — expands the target to the full paragraph range first via `paragraphRange(for:)`, then wraps/unwraps the `` ``` `` fence lines.
- **`linkToggle`**: toggle-off replaces the containing `.link` token with just its `[text]` label. Toggle-on produces `[selected-or-empty](clipboardURL-or-empty)`, with the selection always landing inside `()` — pre-selecting a clipboard URL if one's present (looks like a URL — has a scheme) so typing/pasting overwrites it in one motion, otherwise a zero-length cursor there.
- **`linePrefixToggle`** (blockquote): operates over every line in `paragraphRange(for: selection)`; strips `> ` from all lines in range if every non-empty line already has it, otherwise adds it to every line lacking it.
- **`headingToggle`**: always targets exactly one line (`lineRange(for:)` at the selection's start, ignoring any wider selection). Detects the line's current heading level via `.header` tokens: same level → strip; different level → replace; none → add. Shifts `selectionInReplacement` by the prefix-length delta so the caret stays anchored to the same text content.

### 3. `MarkdownTextView.swift` (new) — `NSTextView` subclass owning dispatch

```swift
final class MarkdownTextView: NSTextView {
    @objc func mdToggleHeading1(_ sender: Any?) { perform(.heading1) }
    // ...one @objc method per action...

    private func perform(_ action: MarkdownFormattingAction) {
        let clipboardURL = action == .link ? Self.pasteboardURLIfAny() : nil
        let edit = MarkdownFormatter.apply(action, to: string, selection: selectedRange(), clipboardURL: clipboardURL)
        guard shouldChangeText(in: edit.replacementRange, replacementString: edit.replacementText) else { return }
        textStorage?.replaceCharacters(in: edit.replacementRange, with: edit.replacementText)
        didChangeText()
        let newSelection = NSRange(
            location: edit.replacementRange.location + edit.selectionInReplacement.location,
            length: edit.selectionInReplacement.length
        )
        setSelectedRange(newSelection)
        scrollRangeToVisible(newSelection)
    }
}
```

The `shouldChangeText(in:replacementString:) → mutate textStorage → didChangeText()` triple is the documented AppKit pattern for programmatic edits that behave exactly like typed input:
- `shouldChangeText` invokes `Coordinator.textView(_:shouldChangeTextIn:replacementString:)` (`EditorView.swift:138`), which is what sets `needsFullRescan` when a fence marker is touched — so toggling a fenced code block correctly forces `MarkdownHighlighter`'s full rescan.
- `didChangeText()` triggers `textDidChange` (pushes the new `text` binding) and `NSTextStorageDelegate.textStorage(_:didProcessEditingFor:...)` (re-highlight).
- Registers one coalesced undo step via the text view's existing `allowsUndo = true` — **verify early**: confirm one ⌘Z fully reverts a formatting action.

**Verify early**: `NSTextView.scrollableTextView()` (used today in `EditorView.makeNSView`) is a class factory method — calling `MarkdownTextView.scrollableTextView()` should return a scroll view whose `documentView` is a `MarkdownTextView` per Apple's documented behavior ("creates a scroll view configured to correctly display an instance of the class on which this method is invoked"), but confirm this in practice since it's not something this codebase has relied on before.

### 4. `MarkdownFormattingAction.swift` (new) — shortcut/icon/selector metadata + shared dispatch

```swift
extension MarkdownFormattingAction {
    var title: String { ... }
    var systemImage: String { ... }
    var keyEquivalent: KeyEquivalent { ... }
    var modifiers: EventModifiers { ... }
    var selector: Selector { ... }  // #selector(MarkdownTextView.mdToggleBold(_:)) etc.
}

enum MarkdownFormattingDispatch {
    /// Routes to whatever responder in the key window's chain implements the action's selector —
    /// a harmless no-op when no MarkdownTextView is first responder, mirroring
    /// WorkspaceWindowManager.toggleSidebarForKeyWindow()'s precedent.
    static func perform(_ action: MarkdownFormattingAction) {
        NSApp.sendAction(action.selector, to: nil, from: nil)
    }
}
```

Both toolbar buttons and app-menu shortcuts call `MarkdownFormattingDispatch.perform(_:)` — the only place click-path and shortcut-path logic lives.

| Action | SF Symbol (verify legibility in Xcode; fall back to text labels "H1"/"H2"/"H3" if the number-square glyphs read poorly) |
|---|---|
| Heading 1/2/3 | `1.square` / `2.square` / `3.square` |
| Bold | `bold` |
| Italic | `italic` |
| Strikethrough | `strikethrough` |
| Inline code | `chevron.left.forwardslash.chevron.right` |
| Fenced code block | `curlybraces` |
| Blockquote | `text.quote` |
| Link | `link` |

### 5. `FormattingToolbar.swift` (new) — SwiftUI view

Parameterless — no `text`/`cursorLine` bindings needed, since all mutation happens through the responder chain. `HStack` of borderless buttons grouped with `Divider()`s, each `Button(systemImage: action.systemImage) { MarkdownFormattingDispatch.perform(action) }.help(action.title)` (same `.help(...)` tooltip pattern as the existing preview-toggle button in `ContentView.swift`). No `.keyboardShortcut` on these buttons — the app-level `.commands` group owns the actual key bindings, to avoid double-registering.

### 6. Toolbar placement (`SplitView.swift`) — no new split item

Mount inside the *existing* editor split item, not as a third `NSSplitViewItem`. In `MainSplitViewController`'s `init` and `update`, change the editor hosting controller's `rootView` from `AnyView(EditorView(...))` to:

```swift
AnyView(
    VStack(spacing: 0) {
        if isEditorEditable {
            FormattingToolbar()
            Divider()
        }
        EditorView(text: text, cursorLine: cursorLine, isEditable: isEditorEditable)
    }
)
```

Smallest possible change: same two `NSSplitViewItem`s, same `splitView.autosaveName`/window-frame-autosave logic untouched (no risk to persisted divider positions). Gating on the existing `isEditorEditable` flag automatically hides the toolbar in the read-only Cheatsheet window (`CheatsheetView.swift` already passes `isEditorEditable: false`) — no new flag needed. `ContentView.swift`, `WorkspaceDetailView.swift`, `WorkspaceTab.swift`, `WorkspaceWindowController.swift`, `WorkspaceWindowManager.swift` need **no changes**.

### 7. `MarkdownEditorApp.swift` — shortcuts

- Change the existing preview button's `.keyboardShortcut("/", modifiers: .command)` → `.keyboardShortcut("p", modifiers: [.command, .shift])`.
- Change the existing sidebar button's `.keyboardShortcut("b", modifiers: .command)` → `.keyboardShortcut("/", modifiers: .command)`.
- New command group with 10 `Button`s, each `Button(action.title) { MarkdownFormattingDispatch.perform(action) }.keyboardShortcut(action.keyEquivalent, modifiers: action.modifiers)`. Try `CommandGroup(after: .textFormatting)` (SwiftUI's built-in anchor, surfaces under a "Format" menu) first — **verify early** it renders cleanly with no unexpected default items, since this app hasn't used that anchor before; fall back to `CommandGroup(after: .toolbar)` (where the existing fixed shortcuts already live) if not.

### 8. `MarkdownHighlighter.swift` — new strikethrough token

- `MarkdownTokenType` gains `.strikethrough`.
- New rule (after bold/italic, same inline-style ordering): `(.strikethrough, regex("(?<!~)~~(?=\\S)(.+?)(?<=\\S)~~(?!~)"))`.
- `attributes(for:)` gains `.strikethrough` → `[.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor]` — an actual strikethrough render (unlike bold/italic's font tricks), so the toggle is visibly confirmable.

## Files touched

New:
- `MarkdownEditor/MarkdownEditor/MarkdownFormatter.swift`
- `MarkdownEditor/MarkdownEditor/MarkdownFormattingAction.swift`
- `MarkdownEditor/MarkdownEditor/MarkdownTextView.swift`
- `MarkdownEditor/MarkdownEditor/FormattingToolbar.swift`

Edited:
- `MarkdownEditor/MarkdownEditor/MarkdownHighlighter.swift` — strikethrough token
- `MarkdownEditor/MarkdownEditor/EditorView.swift` — swap `NSTextView.scrollableTextView()` for `MarkdownTextView.scrollableTextView()`
- `MarkdownEditor/MarkdownEditor/SplitView.swift` — wrap editor in `VStack` with `FormattingToolbar`
- `MarkdownEditor/MarkdownEditor/MarkdownEditorApp.swift` — new Format shortcuts, 2 reassignments

## Automated tests

- `MarkdownHighlighterTests.swift`: new strikethrough match test; extend the existing all-token-types integration test to include `~~strikethrough~~`.
- New `MarkdownFormatterTests.swift`: for each of the 10 actions — apply when unformatted (with selection), apply with empty selection (markers inserted, cursor between), toggle off when already formatted. Plus: heading level-switch (H1 → request H2 → becomes H2), multi-line blockquote toggle, link with/without a clipboard URL, fenced-code toggle expanding a partial-line selection to full lines, and bold/italic disambiguation (toggling italic inside an existing bold span must not false-positive as "already italic").
- Everything else (responder-chain dispatch, undo grouping, live `NSTextView` selection/scroll, toolbar visibility) is manual-only — no pure-logic seam, consistent with the M1–M9 testing split.

## Verification

- Build: `xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`
- Automated: `xcodebuild test -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'`
- Manual (owner's Mac):
  - All 10 toolbar buttons and all 10 shortcuts apply correct syntax with immediate highlighting, in both single-file and folder/workspace windows.
  - Toggle-off works for all 10; bold/italic don't cross-trigger; ⌘2 on an H1 line sets H2; multi-line blockquote toggle covers every touched line.
  - No-selection behavior: wrapping actions center the cursor between empty markers; heading/blockquote apply to the current line (or lines, for blockquote with a real selection).
  - Link: selected text becomes `[text]`, cursor/selection lands in `()`; a URL-like clipboard string is prefilled and selected; otherwise empty with cursor between.
  - Single ⌘Z fully reverts one formatting action; redo works.
  - Toggling a fenced code block near another existing one doesn't leave stale coloring past the fence boundary (confirms full-rescan still fires for programmatic edits).
  - ⌘/ toggles sidebar (no-op in single-file windows); ⌘⇧P toggles preview in both window types; ⌘B performs Bold.
  - Toolbar sits above the editor pane only — absent above preview, absent from the window's native toolbar, absent in the read-only Cheatsheet window.
  - Clicking a button/pressing a shortcut while the editor isn't focused (e.g. focus in sidebar/tab bar) is a harmless no-op.
  - Divider-position and window-frame autosave still persist correctly across relaunch (regression check on the `SplitView.swift` change).

## Workflow

Branch `m10-formatting-toolbar`. Run `/code-review` on the diff before opening the PR. Open the PR (title referencing M10) and stop — per project convention, the owner merges manually after confirming the manual checklist.
