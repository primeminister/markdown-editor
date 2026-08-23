//
//  MarkdownFormattingAction.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 23/08/2026.
//

import AppKit
import SwiftUI

extension MarkdownFormattingAction {
    var title: String {
        switch self {
            case .heading1: return "Heading 1"
            case .heading2: return "Heading 2"
            case .heading3: return "Heading 3"
            case .bold: return "Bold"
            case .italic: return "Italic"
            case .strikethrough: return "Strikethrough"
            case .inlineCode: return "Inline Code"
            case .fencedCode: return "Code Block"
            case .blockquote: return "Blockquote"
            case .link: return "Link"
        }
    }

    var systemImage: String {
        switch self {
            case .heading1: return "1.square"
            case .heading2: return "2.square"
            case .heading3: return "3.square"
            case .bold: return "bold"
            case .italic: return "italic"
            case .strikethrough: return "strikethrough"
            case .inlineCode: return "chevron.left.forwardslash.chevron.right"
            case .fencedCode: return "curlybraces"
            case .blockquote: return "text.quote"
            case .link: return "link"
        }
    }

    var keyEquivalent: KeyEquivalent {
        switch self {
            case .heading1: return "1"
            case .heading2: return "2"
            case .heading3: return "3"
            case .bold: return "b"
            case .italic: return "i"
            case .strikethrough: return "x"
            case .inlineCode: return "e"
            case .fencedCode: return "c"
            case .blockquote: return ">"
            case .link: return "k"
        }
    }

    var modifiers: EventModifiers {
        switch self {
            // Blockquote's key equivalent (">") is already only producible by holding Shift, so an
            // explicit `.shift` here is redundant and can keep the shortcut from matching -- macOS
            // still displays the ⇧ glyph in the menu automatically since the character itself needs it.
            case .heading1, .heading2, .heading3, .bold, .italic, .inlineCode, .link, .blockquote:
                return .command
            case .strikethrough, .fencedCode:
                return [.command, .shift]
        }
    }

    var selector: Selector {
        switch self {
            case .heading1: return #selector(MarkdownTextView.mdToggleHeading1(_:))
            case .heading2: return #selector(MarkdownTextView.mdToggleHeading2(_:))
            case .heading3: return #selector(MarkdownTextView.mdToggleHeading3(_:))
            case .bold: return #selector(MarkdownTextView.mdToggleBold(_:))
            case .italic: return #selector(MarkdownTextView.mdToggleItalic(_:))
            case .strikethrough: return #selector(MarkdownTextView.mdToggleStrikethrough(_:))
            case .inlineCode: return #selector(MarkdownTextView.mdToggleInlineCode(_:))
            case .fencedCode: return #selector(MarkdownTextView.mdToggleFencedCode(_:))
            case .blockquote: return #selector(MarkdownTextView.mdToggleBlockquote(_:))
            case .link: return #selector(MarkdownTextView.mdToggleLink(_:))
        }
    }
}

enum MarkdownFormattingDispatch {
    /// Routes to whatever responder in the key window's chain implements the action's selector --
    /// a harmless no-op when no MarkdownTextView is first responder, mirroring
    /// WorkspaceWindowManager.toggleSidebarForKeyWindow()'s precedent.
    static func perform(_ action: MarkdownFormattingAction) {
        NSApp.sendAction(action.selector, to: nil, from: nil)
    }
}
