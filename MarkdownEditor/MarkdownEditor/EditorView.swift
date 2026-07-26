//
//  EditorView.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import AppKit
import SwiftUI

enum EditorFontSize {
    static let min = 9.0
    static let max = 28.0
    static let step = 1.0
    static let `default` = Double(NSFont.systemFontSize)
    static func clamped(_ value: Double) -> Double { Swift.min(max, Swift.max(min, value)) }
}

enum EditorCursorLocation {
    /// 1-based line number containing `characterIndex` in `text`, matching the 1-based lines
    /// `swift-markdown` reports in `Markup.range` (see `MarkdownRenderer`'s `data-source-line`).
    static func lineNumber(in text: String, at characterIndex: Int) -> Int {
        let nsText = text as NSString
        let clampedIndex = max(0, min(characterIndex, nsText.length))
        let prefix = nsText.substring(to: clampedIndex)
        return prefix.reduce(1) { count, character in character == "\n" ? count + 1 : count }
    }
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorLine: Int
    var isEditable: Bool = true
    @AppStorage("editorFontSize") private var editorFontSize = EditorFontSize.default

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, cursorLine: $cursorLine)
    }

    private var fontSize: CGFloat { CGFloat(EditorFontSize.clamped(editorFontSize)) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.string = text
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Delegate isn't attached until after `string` is set above, so it didn't see this
        // initial content — highlight it explicitly here. Later updates go through the delegate.
        highlight(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.cursorLine = $cursorLine
        textView.isEditable = isEditable
        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            // A size change alone doesn't retroactively resize already-highlighted text, since each
            // run's font is a per-character attribute set by MarkdownHighlighter, not derived from
            // `textView.font` -- re-highlight now so the size change is visible immediately rather
            // than only on the next edit.
            highlight(textView)
        }
        // Only external changes (new document loaded, undo from outside the view) reach here —
        // the Coordinator already pushed our own keystrokes into `text`, so skip re-setting
        // identical content to avoid clobbering the live cursor/selection on every keystroke.
        guard textView.string != text else { return }
        let selectedRanges = textView.selectedRanges
        // Both the content swap below and the clamped-selection restore each post their own
        // selection-changed notification, which would otherwise overwrite whatever `cursorLine`
        // the caller just set for this external change (e.g. `WorkspaceTab.selectFile` resetting
        // it to 1 for a freshly loaded file) with a value derived from the OLD file's raw offset
        // clamped into the new content -- suppress those writes for the duration of this swap.
        context.coordinator.isApplyingExternalTextChange = true
        defer { context.coordinator.isApplyingExternalTextChange = false }
        textView.string = text
        // A different document's content just replaced this text view's buffer wholesale (e.g. the
        // sidebar switched files onto this same NSTextView instance) -- any undo actions still on the
        // stack were recorded against the PREVIOUS content and would corrupt this one if replayed.
        textView.undoManager?.removeAllActions()
        // `.string` mutates the text storage, which re-triggers the delegate's
        // `didProcessEditing` (already re-highlights) — no explicit call needed here.
        let maxLocation = (text as NSString).length
        textView.selectedRanges = selectedRanges.map { rangeValue in
            let range = rangeValue.rangeValue
            let clampedLocation = min(range.location, maxLocation)
            let clampedLength = min(range.length, maxLocation - clampedLocation)
            return NSValue(range: NSRange(location: clampedLocation, length: clampedLength))
        }
    }

    private func highlight(_ textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        MarkdownHighlighter.applyHighlighting(to: textStorage, fontSize: fontSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var text: Binding<String>
        var cursorLine: Binding<Int>
        // Set right after creation in `makeNSView` -- lets `didProcessEditing` below read the
        // textView's current font size (kept in sync with `editorFontSize` by `updateNSView`)
        // without the Coordinator needing its own `@AppStorage` observer.
        weak var textView: NSTextView?
        // Set by `EditorView.updateNSView` while it's programmatically replacing content and
        // restoring a clamped selection, so the selection-changed notifications that triggers
        // don't overwrite `cursorLine` -- see the comment at that call site.
        var isApplyingExternalTextChange = false
        // Set in shouldChangeTextIn (pre-edit) when the affected line contains a fence marker so
        // that the subsequent didProcessEditing forces a full rescan rather than a paragraph-only
        // update. This prevents stale fenced-code attributes from lingering outside the edited
        // range when a fence boundary is broken or created.
        private var needsFullRescan = false

        init(text: Binding<String>, cursorLine: Binding<Int>) {
            self.text = text
            self.cursorLine = cursorLine
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let nsString = textView.string as NSString
            let clampedLocation = min(affectedCharRange.location, nsString.length)
            let lineRange = nsString.lineRange(for: NSRange(location: clampedLocation, length: 0))
            if nsString.range(of: "```", options: [], range: lineRange).location != NSNotFound {
                needsFullRescan = true
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalTextChange, let textView = notification.object as? NSTextView else { return }
            cursorLine.wrappedValue = EditorCursorLocation.lineNumber(in: textView.string, at: textView.selectedRange().location)
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            let range: NSRange? = needsFullRescan ? nil : editedRange
            needsFullRescan = false
            let fontSize = textView?.font?.pointSize ?? CGFloat(EditorFontSize.default)
            MarkdownHighlighter.applyHighlighting(to: textStorage, editedRange: range, fontSize: fontSize)
        }
    }
}

#Preview {
    EditorView(text: .constant("# Heading\n\nSome **bold** and *italic* text with `code` and a [link](https://example.com).\n\n> A quote\n\n```\nlet x = 1\n```\n"), cursorLine: .constant(1))
        .frame(width: 500, height: 400)
}
