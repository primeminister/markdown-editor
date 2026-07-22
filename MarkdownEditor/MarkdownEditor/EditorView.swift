//
//  EditorView.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import AppKit
import SwiftUI

struct EditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.string = text
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
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
        // Only external changes (new document loaded, undo from outside the view) reach here —
        // the Coordinator already pushed our own keystrokes into `text`, so skip re-setting
        // identical content to avoid clobbering the live cursor/selection on every keystroke.
        guard textView.string != text else { return }
        let selectedRanges = textView.selectedRanges
        textView.string = text
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
        MarkdownHighlighter.applyHighlighting(to: textStorage)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var text: Binding<String>
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
            MarkdownHighlighter.applyHighlighting(to: textStorage, editedRange: range)
        }
    }
}

#Preview {
    EditorView(text: .constant("# Heading\n\nSome **bold** and *italic* text with `code` and a [link](https://example.com).\n\n> A quote\n\n```\nlet x = 1\n```\n"))
        .frame(width: 500, height: 400)
}
