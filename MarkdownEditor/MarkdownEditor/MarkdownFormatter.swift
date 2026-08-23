//
//  MarkdownFormatter.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 23/08/2026.
//

import Foundation

enum MarkdownFormattingAction: CaseIterable, Hashable {
    case heading1, heading2, heading3
    case bold, italic, strikethrough
    case inlineCode, fencedCode
    case blockquote, link
}

/// A single edit to apply to a text view: replace `replacementRange` with `replacementText`,
/// then select `selectionInReplacement` (a range relative to the start of `replacementText`).
struct MarkdownFormattingEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
    let selectionInReplacement: NSRange
}

/// Pure logic for the formatting toolbar/shortcuts: given the document text and current selection,
/// decides whether an action should toggle formatting on or off and produces the resulting edit.
/// Toggle detection reuses `MarkdownHighlighter.matches` so it can never disagree with what's
/// already colored in the editor -- it's the same regexes.
enum MarkdownFormatter {
    static func apply(
        _ action: MarkdownFormattingAction,
        to text: String,
        selection: NSRange,
        clipboardURL: String? = nil
    ) -> MarkdownFormattingEdit {
        switch action {
        case .heading1: return headingToggle(text: text, selection: selection, level: 1)
        case .heading2: return headingToggle(text: text, selection: selection, level: 2)
        case .heading3: return headingToggle(text: text, selection: selection, level: 3)
        case .bold: return wrapToggle(text: text, selection: selection, type: .bold, marker: "**")
        case .italic: return wrapToggle(text: text, selection: selection, type: .italic, marker: "*")
        case .strikethrough: return wrapToggle(text: text, selection: selection, type: .strikethrough, marker: "~~")
        case .inlineCode: return wrapToggle(text: text, selection: selection, type: .inlineCode, marker: "`")
        case .fencedCode: return fencedCodeToggle(text: text, selection: selection)
        case .blockquote: return linePrefixToggle(text: text, selection: selection, prefix: "> ")
        case .link: return linkToggle(text: text, selection: selection, clipboardURL: clipboardURL)
        }
    }

    /// A zero-length caret sitting exactly on `outer`'s edge (right before its first character or
    /// right after its last) is adjacent to it, not inside it -- only a caret strictly between the
    /// edges, or any non-empty `inner` reaching an edge, counts as contained. Without this, placing
    /// the cursor right after typing "**bold**" and pressing the shortcut again would strip the
    /// bold the user just finished, instead of starting fresh at the caret.
    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        guard outer.location <= inner.location, NSMaxRange(inner) <= NSMaxRange(outer) else { return false }
        if inner.length == 0 && (inner.location == outer.location || inner.location == NSMaxRange(outer)) {
            return false
        }
        return true
    }

    private static func clamp(_ value: Int, min lo: Int, max hi: Int) -> Int {
        Swift.max(lo, Swift.min(hi, value))
    }

    // MARK: - wrapToggle (bold, italic, strikethrough, inline code)

    /// Symmetric marker wrapping: `marker` is the same length whether emitted by us (always the
    /// canonical form, e.g. "**") or found in an existing match (bold's regex also accepts "__",
    /// but both are 2 UTF-16 units, so stripping by length works regardless of which was typed).
    private static func wrapToggle(text: String, selection: NSRange, type: MarkdownTokenType, marker: String) -> MarkdownFormattingEdit {
        let nsText = text as NSString
        let markerLen = marker.utf16.count
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == type }

        if let containing = tokens.first(where: { contains($0.range, selection) }) {
            let innerRange = NSRange(location: containing.range.location + markerLen, length: containing.range.length - 2 * markerLen)
            let innerText = nsText.substring(with: innerRange)
            let innerLen = (innerText as NSString).length
            let selOffset = clamp(selection.location - containing.range.location - markerLen, min: 0, max: innerLen)
            let selLen = clamp(selection.length, min: 0, max: innerLen - selOffset)
            return MarkdownFormattingEdit(
                replacementRange: containing.range,
                replacementText: innerText,
                selectionInReplacement: NSRange(location: selOffset, length: selLen)
            )
        }

        let selectedText = nsText.substring(with: selection)
        let replacementText = marker + selectedText + marker
        return MarkdownFormattingEdit(
            replacementRange: selection,
            replacementText: replacementText,
            selectionInReplacement: NSRange(location: markerLen, length: selection.length)
        )
    }

    // MARK: - fencedCodeToggle

    /// Block-level: expands the target to the full paragraph range (all lines touched by the
    /// selection) before wrapping/unwrapping the ``` fence lines.
    private static func fencedCodeToggle(text: String, selection: NSRange) -> MarkdownFormattingEdit {
        let nsText = text as NSString
        let paragraphRange = nsText.paragraphRange(for: selection)
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .fencedCode }

        if let containing = tokens.first(where: { contains($0.range, paragraphRange) }) {
            let full = nsText.substring(with: containing.range) as NSString
            let markerLen = 3
            // The fence marker is always exactly "```" -- only a newline right after it (present
            // for the normal multi-line case, absent for a degenerate single-line match like
            // "```code```") is part of the opening delimiter, not code content.
            let hasOpeningNewline = full.length > markerLen && full.character(at: markerLen) == 0x0A
            let openingLen = markerLen + (hasOpeningNewline ? 1 : 0)
            let closingStart = max(openingLen, full.length - markerLen)
            let innerRange = NSRange(location: openingLen, length: max(0, closingStart - openingLen))
            var innerText = full.substring(with: innerRange)
            // The newline right before the closing fence marker is the fence's own required line
            // break, not code content -- drop it so unwrapping doesn't leave a stray trailing blank line.
            if innerText.hasSuffix("\n") { innerText.removeLast() }
            let innerLen = (innerText as NSString).length
            let selOffset = clamp(selection.location - containing.range.location - openingLen, min: 0, max: innerLen)
            let selLen = clamp(selection.length, min: 0, max: innerLen - selOffset)
            return MarkdownFormattingEdit(
                replacementRange: containing.range,
                replacementText: innerText,
                selectionInReplacement: NSRange(location: selOffset, length: selLen)
            )
        }

        let content = nsText.substring(with: paragraphRange)
        let hasTrailingNewline = content.hasSuffix("\n")
        let body = hasTrailingNewline ? content : content + "\n"
        let replacementText = "```\n" + body + "```" + (hasTrailingNewline ? "\n" : "")
        let selOffsetInParagraph = selection.location - paragraphRange.location
        return MarkdownFormattingEdit(
            replacementRange: paragraphRange,
            replacementText: replacementText,
            selectionInReplacement: NSRange(location: 4 + selOffsetInParagraph, length: selection.length)
        )
    }

    // MARK: - linkToggle

    private static func linkToggle(text: String, selection: NSRange, clipboardURL: String?) -> MarkdownFormattingEdit {
        let nsText = text as NSString
        let tokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .link }

        if let containing = tokens.first(where: { contains($0.range, selection) }) {
            let full = nsText.substring(with: containing.range) as NSString
            let closeBracket = full.range(of: "]")
            let labelLength = closeBracket.location != NSNotFound ? NSMaxRange(closeBracket) : full.length
            let label = full.substring(to: labelLength)
            let labelLen = (label as NSString).length
            let selOffset = clamp(selection.location - containing.range.location, min: 0, max: labelLen)
            let selLen = clamp(selection.length, min: 0, max: labelLen - selOffset)
            return MarkdownFormattingEdit(
                replacementRange: containing.range,
                replacementText: label,
                selectionInReplacement: NSRange(location: selOffset, length: selLen)
            )
        }

        let selectedText = nsText.substring(with: selection)
        let urlText = clipboardURL ?? ""
        let replacementText = "[\(selectedText)](\(urlText))"
        let openParenOffset = (("[" + selectedText + "]") as NSString).length + 1
        let urlLen = (urlText as NSString).length
        return MarkdownFormattingEdit(
            replacementRange: selection,
            replacementText: replacementText,
            selectionInReplacement: NSRange(location: openParenOffset, length: urlLen)
        )
    }

    // MARK: - linePrefixToggle (blockquote)

    /// Toggles over every line in `paragraphRange(for: selection)` (like Xcode's ⌘/): strips the
    /// prefix from all lines in range if every non-empty line already has it, otherwise adds it to
    /// every line lacking it.
    private static func linePrefixToggle(text: String, selection: NSRange, prefix: String) -> MarkdownFormattingEdit {
        let nsText = text as NSString
        let paragraphRange = nsText.paragraphRange(for: selection)
        let content = nsText.substring(with: paragraphRange)
        let lines = content.components(separatedBy: "\n")

        func hasPrefix(_ line: String) -> Bool { line.hasPrefix(">") }
        func stripPrefix(_ line: String) -> String {
            if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
            if line.hasPrefix(">") { return String(line.dropFirst(1)) }
            return line
        }

        let nonEmptyLines = lines.filter { !$0.isEmpty }
        let shouldStrip = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy(hasPrefix)

        let newLines: [String] = shouldStrip
            ? lines.map { hasPrefix($0) ? stripPrefix($0) : $0 }
            : lines.map { $0.isEmpty || hasPrefix($0) ? $0 : prefix + $0 }

        let replacementText = newLines.joined(separator: "\n")

        // Lines can grow/shrink by different amounts (e.g. mixed "> " / bare lines when adding),
        // so the caret's new offset has to be walked line-by-line rather than shifted by one delta.
        func mapOffset(_ oldOffset: Int) -> Int {
            var oldPos = 0
            var newPos = 0
            for (oldLine, newLine) in zip(lines, newLines) {
                let oldLen = (oldLine as NSString).length
                let newLen = (newLine as NSString).length
                let oldLineEnd = oldPos + oldLen
                if oldOffset <= oldLineEnd {
                    let withinLine = oldOffset - oldPos
                    let delta = newLen - oldLen
                    let mappedWithin = max(0, withinLine + delta)
                    return newPos + min(mappedWithin, newLen)
                }
                oldPos = oldLineEnd + 1
                newPos += newLen + 1
            }
            return newPos
        }

        let selStartOffset = selection.location - paragraphRange.location
        let selEndOffset = NSMaxRange(selection) - paragraphRange.location
        let newSelStart = mapOffset(selStartOffset)
        let newSelEnd = mapOffset(selEndOffset)

        return MarkdownFormattingEdit(
            replacementRange: paragraphRange,
            replacementText: replacementText,
            selectionInReplacement: NSRange(location: newSelStart, length: max(0, newSelEnd - newSelStart))
        )
    }

    // MARK: - headingToggle

    /// Always targets exactly one line (the selection's start), ignoring any wider selection --
    /// a line has one heading level. Same level requested again strips it; a different level
    /// replaces the prefix; no existing heading adds one.
    private static func headingToggle(text: String, selection: NSRange, level: Int) -> MarkdownFormattingEdit {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        let lineText = nsText.substring(with: lineRange)
        let headerTokens = MarkdownHighlighter.matches(in: text).filter { $0.type == .header }
        let isHeaderLine = headerTokens.contains { $0.range.location == lineRange.location }

        let requestedPrefix = String(repeating: "#", count: level) + " "
        let hashCount = isHeaderLine ? lineText.prefix(while: { $0 == "#" }).count : 0
        let oldPrefixLen = isHeaderLine ? hashCount + 1 : 0
        let restOfLine = String(lineText.dropFirst(oldPrefixLen))

        let newPrefixLen: Int
        let newLineText: String
        if isHeaderLine && hashCount == level {
            newPrefixLen = 0
            newLineText = restOfLine
        } else {
            newPrefixLen = (requestedPrefix as NSString).length
            newLineText = requestedPrefix + restOfLine
        }

        let delta = newPrefixLen - oldPrefixLen
        let selOffset = selection.location - lineRange.location
        let newLineLen = (newLineText as NSString).length
        let newSelOffset = clamp(selOffset + delta, min: 0, max: newLineLen)
        let newSelLen = clamp(selection.length, min: 0, max: newLineLen - newSelOffset)

        return MarkdownFormattingEdit(
            replacementRange: lineRange,
            replacementText: newLineText,
            selectionInReplacement: NSRange(location: newSelOffset, length: newSelLen)
        )
    }
}
