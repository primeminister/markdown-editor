//
//  MarkdownHighlighter.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import AppKit
import Foundation

enum MarkdownTokenType: CaseIterable {
    case header
    case bold
    case italic
    case inlineCode
    case link
    case fencedCode
    case blockquote
}

struct MarkdownToken: Equatable {
    let type: MarkdownTokenType
    let range: NSRange
}

enum MarkdownHighlighter {
    // Order also doubles as attribute-application order: later entries are applied on top of earlier ones.
    private static let rules: [(type: MarkdownTokenType, regex: NSRegularExpression)] = [
        (.fencedCode, regex("```[\\s\\S]*?```")),
        (.blockquote, regex("^>[ \\t]?.*$", options: [.anchorsMatchLines])),
        (.header, regex("^#{1,6}[ \\t].*$", options: [.anchorsMatchLines])),
        (.link, regex("\\[[^\\]\\n]+\\]\\([^)\\n]+\\)")),
        (.inlineCode, regex("`[^`\\n]+`")),
        (.bold, regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")),
        (.italic, regex("(?<!\\*)\\*(?!\\*)(?=\\S)(.+?)(?<=\\S)\\*(?!\\*)|(?<!_)_(?!_)(?=\\S)(.+?)(?<=\\S)_(?!_)")),
    ]

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are fixed string literals; a bad pattern here is a coding error, not a runtime condition.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Pure token matching: given source text, returns every match for every token type.
    static func matches(in text: String) -> [MarkdownToken] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var tokens: [MarkdownToken] = []
        for rule in rules {
            rule.regex.enumerateMatches(in: text, range: fullRange) { result, _, _ in
                guard let match = result else { return }
                tokens.append(MarkdownToken(type: rule.type, range: match.range))
            }
        }
        return tokens
    }

    private static let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
    private static let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)

    /// Applies syntax-highlighting attributes to a live text storage.
    ///
    /// - Parameter editedRange: the range that just changed, if this is an incremental edit (as
    ///   opposed to the initial highlight of a freshly-loaded document). Token *matching* still
    ///   scans the full text either way — regex matching alone is cheap and has no layout impact.
    ///   What's expensive is *writing* attributes: resetting them across the whole document forces
    ///   `NSLayoutManager` to redo glyph/line-fragment layout for the whole document on every
    ///   keystroke, which on a realistically-sized file (some thousands of characters, e.g.
    ///   `docs/plan.md`) is slow enough to race visibly with NSTextView's scroll-to-cursor logic —
    ///   the scroll position briefly lands in the wrong place before snapping back, seen as a quick
    ///   up/down jump. So attribute writes are scoped to just the edited paragraph(s), unless the
    ///   edit touches a fenced code block — a fence boundary can change how much of the *rest* of
    ///   the document reads as code, so that case still needs a full rescan to stay correct.
    static func applyHighlighting(to textStorage: NSTextStorage, editedRange: NSRange? = nil) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let tokens = matches(in: textStorage.string)

        let updateRange = editedRange.flatMap { scopedRange(for: $0, in: textStorage.string, tokens: tokens) } ?? fullRange

        textStorage.beginEditing()
        textStorage.setAttributes(
            [.font: baseFont, .foregroundColor: NSColor.textColor],
            range: updateRange
        )
        for token in tokens where NSIntersectionRange(token.range, updateRange).length == token.range.length {
            textStorage.addAttributes(attributes(for: token.type), range: token.range)
        }
        textStorage.endEditing()
    }

    /// Narrows a full-document rescan down to just the edited paragraph(s), as long as doing so
    /// can't produce a different result than a full rescan would. That holds for every token type
    /// except `.fencedCode`, since fenced code is the only multi-line construct (its regex spans
    /// newlines) — every other rule matches within a single line, so it can't be affected by, or
    /// affect, anything outside the edited paragraph. Returns `nil` (meaning "fall back to a full
    /// rescan") whenever the edit's paragraph range overlaps or borders an existing fenced-code
    /// range, since adding/removing a fence marker can change how much of the document after it
    /// reads as code.
    static func scopedRange(for editedRange: NSRange, in text: String, tokens: [MarkdownToken]) -> NSRange? {
        let nsText = text as NSString
        // NSIntersectionRange, not clamping: a zero-length editedRange sitting exactly at the end
        // of the document (e.g. deleting the last character) doesn't "intersect" fullRange by that
        // function's definition and collapses to {0, 0} — silently redirecting to paragraph zero
        // instead of the paragraph actually being edited. Clamp location/length individually instead.
        let clampedLocation = min(editedRange.location, nsText.length)
        let clampedLength = min(editedRange.length, nsText.length - clampedLocation)
        let clampedEditedRange = NSRange(location: clampedLocation, length: clampedLength)
        let paragraphRange = nsText.paragraphRange(for: clampedEditedRange)

        let touchesFence = tokens.contains { token in
            guard token.type == .fencedCode else { return false }
            return NSMaxRange(token.range) >= paragraphRange.location && token.range.location <= NSMaxRange(paragraphRange)
        }
        guard !touchesFence else { return nil }

        return paragraphRange
    }

    private static func attributes(for type: MarkdownTokenType) -> [NSAttributedString.Key: Any] {
        switch type {
        case .header:
            return [.foregroundColor: NSColor.systemBlue, .font: boldFont]
        case .bold:
            return [.font: boldFont]
        case .italic:
            return [.font: italicFont]
        case .inlineCode:
            return [
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.5),
            ]
        case .link:
            return [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        case .fencedCode:
            return [
                .foregroundColor: NSColor.systemGreen,
                .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.3),
            ]
        case .blockquote:
            return [.foregroundColor: NSColor.systemGray]
        }
    }
}
