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

    /// Applies syntax-highlighting attributes to a live text storage. Full-document rescan per edit;
    /// personal note files are small enough that this is sub-millisecond.
    static func applyHighlighting(to textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()
        textStorage.setAttributes(
            [.font: baseFont, .foregroundColor: NSColor.textColor],
            range: fullRange
        )
        for token in matches(in: textStorage.string) {
            textStorage.addAttributes(attributes(for: token.type), range: token.range)
        }
        textStorage.endEditing()
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
