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

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @AppStorage("editorFontSize") private var editorFontSize = EditorFontSize.default

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        // Set right after creation in `makeNSView` -- lets `didProcessEditing` below read the
        // textView's current font size (kept in sync with `editorFontSize` by `updateNSView`)
        // without the Coordinator needing its own `@AppStorage` observer.
        weak var textView: NSTextView?
        // Set in shouldChangeTextIn (pre-edit) when the affected line contains a fence marker so
        // that the subsequent didProcessEditing forces a full rescan rather than a paragraph-only
        // update. This prevents stale fenced-code attributes from lingering outside the edited
        // range when a fence boundary is broken or created.
        private var needsFullRescan = false

        init(text: Binding<String>) {
            self.text = text
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
    EditorView(text: .constant("# Heading\n\nSome **bold** and *italic* text with `code` and a [link](https://example.com).\n\n> A quote\n\n```\nlet x = 1\n```\n"))
        .frame(width: 500, height: 400)
}
