//
//  MarkdownTextView.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 23/08/2026.
//

import AppKit

/// `NSTextView` subclass that owns dispatch for the formatting toolbar/shortcuts. Toolbar buttons
/// and app-menu shortcuts both route here via `NSApp.sendAction(_:to:nil:)` through the responder
/// chain (see `MarkdownFormattingDispatch`), so there's exactly one place formatting edits happen.
final class MarkdownTextView: NSTextView {
    @objc func mdToggleHeading1(_ sender: Any?) { applyFormatting(.heading1) }
    @objc func mdToggleHeading2(_ sender: Any?) { applyFormatting(.heading2) }
    @objc func mdToggleHeading3(_ sender: Any?) { applyFormatting(.heading3) }
    @objc func mdToggleBold(_ sender: Any?) { applyFormatting(.bold) }
    @objc func mdToggleItalic(_ sender: Any?) { applyFormatting(.italic) }
    @objc func mdToggleStrikethrough(_ sender: Any?) { applyFormatting(.strikethrough) }
    @objc func mdToggleInlineCode(_ sender: Any?) { applyFormatting(.inlineCode) }
    @objc func mdToggleFencedCode(_ sender: Any?) { applyFormatting(.fencedCode) }
    @objc func mdToggleBlockquote(_ sender: Any?) { applyFormatting(.blockquote) }
    @objc func mdToggleLink(_ sender: Any?) { applyFormatting(.link) }

    private func applyFormatting(_ action: MarkdownFormattingAction) {
        let clipboardURL = action == .link ? Self.pasteboardURLIfAny() : nil
        let edit = MarkdownFormatter.apply(action, to: string, selection: selectedRange(), clipboardURL: clipboardURL)
        // The shouldChangeText -> mutate textStorage -> didChangeText triple is the documented
        // AppKit pattern for programmatic edits that behave exactly like typed input: it drives the
        // same delegate callbacks (fence-aware rescan, text binding push, undo registration) that
        // typing does, rather than bypassing them.
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

    /// A clipboard string is only used to prefill the Link action's URL field when it actually
    /// looks like a URL (has a scheme) -- otherwise arbitrary copied text would get misinterpreted.
    private static func pasteboardURLIfAny() -> String? {
        guard let string = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return trimmed
    }
}
