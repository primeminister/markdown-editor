//
//  MarkdownRenderer.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import Foundation
import Markdown

enum MarkdownRenderer {
    /// Parses `markdownText` and returns a full HTML document with `stylesheet` inlined in a
    /// `<style>` tag — inlined rather than linked so rendering doesn't depend on WKWebView's
    /// sandboxed content process being able to resolve a relative subresource URL.
    static func htmlDocument(from markdownText: String, stylesheet: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        \(htmlFragment(from: markdownText))</body>
        </html>
        """
    }

    /// Pure body-only HTML fragment (no document shell), used by tests to assert on structure
    /// without coupling them to the surrounding boilerplate.
    static func htmlFragment(from markdownText: String) -> String {
        let document = Document(parsing: markdownText)
        var visitor = HTMLVisitor()
        return visitor.visit(document)
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Walks the swift-markdown tree and emits HTML. Raw HTML found in the source (`InlineHTML`,
    /// `HTMLBlock`) is escaped rather than passed through, so it renders as visible text, not markup.
    private struct HTMLVisitor: MarkupVisitor {
        private var columnAlignments: [Table.ColumnAlignment?] = []

        mutating func defaultVisit(_ markup: Markup) -> String {
            childrenHTML(of: markup)
        }

        private mutating func childrenHTML(of markup: Markup) -> String {
            markup.children.reduce(into: "") { html, child in
                html += visit(child)
            }
        }

        /// `data-source-line` lets the preview locate the rendered block matching a given editor
        /// cursor line (see `PreviewView.scrollToLine`). Block-level elements only — inline nodes
        /// (emphasis, links, ...) resolve at their enclosing block's granularity.
        private func sourceLineAttribute(for markup: Markup) -> String {
            guard let line = markup.range?.lowerBound.line else { return "" }
            return " data-source-line=\"\(line)\""
        }

        mutating func visitDocument(_ document: Document) -> String {
            childrenHTML(of: document)
        }

        mutating func visitText(_ text: Text) -> String {
            escapeHTML(text.string)
        }

        mutating func visitParagraph(_ paragraph: Paragraph) -> String {
            "<p\(sourceLineAttribute(for: paragraph))>\(childrenHTML(of: paragraph))</p>\n"
        }

        mutating func visitHeading(_ heading: Heading) -> String {
            "<h\(heading.level)\(sourceLineAttribute(for: heading))>\(childrenHTML(of: heading))</h\(heading.level)>\n"
        }

        mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
            "<em>\(childrenHTML(of: emphasis))</em>"
        }

        mutating func visitStrong(_ strong: Strong) -> String {
            "<strong>\(childrenHTML(of: strong))</strong>"
        }

        mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
            "<del>\(childrenHTML(of: strikethrough))</del>"
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
            "<code>\(escapeHTML(inlineCode.code))</code>"
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
            let languageClass = codeBlock.language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
            // CommonMark code block content always ends in a newline before the closing fence;
            // trim it so <pre> doesn't render a trailing blank line.
            let code = codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
            return "<pre\(sourceLineAttribute(for: codeBlock))><code\(languageClass)>\(escapeHTML(code))</code></pre>\n"
        }

        mutating func visitLink(_ link: Link) -> String {
            let destination = escapeAttribute(link.destination ?? "")
            return "<a href=\"\(destination)\">\(childrenHTML(of: link))</a>"
        }

        mutating func visitImage(_ image: Image) -> String {
            let source = escapeAttribute(image.source ?? "")
            let alt = escapeAttribute(childrenPlainText(of: image))
            return "<img src=\"\(source)\" alt=\"\(alt)\">"
        }

        private func childrenPlainText(of markup: Markup) -> String {
            markup.children.reduce(into: "") { text, child in
                if let textNode = child as? Text {
                    text += textNode.string
                } else {
                    text += childrenPlainText(of: child)
                }
            }
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
            "<blockquote\(sourceLineAttribute(for: blockQuote))>\n\(childrenHTML(of: blockQuote))</blockquote>\n"
        }

        mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
            "<ul\(sourceLineAttribute(for: unorderedList))>\n\(childrenHTML(of: unorderedList))</ul>\n"
        }

        mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
            let startAttribute = orderedList.startIndex != 1 ? " start=\"\(orderedList.startIndex)\"" : ""
            return "<ol\(startAttribute)\(sourceLineAttribute(for: orderedList))>\n\(childrenHTML(of: orderedList))</ol>\n"
        }

        mutating func visitListItem(_ listItem: ListItem) -> String {
            let checkbox: String
            switch listItem.checkbox {
            case .checked:
                checkbox = "<input type=\"checkbox\" checked disabled> "
            case .unchecked:
                checkbox = "<input type=\"checkbox\" disabled> "
            case nil:
                checkbox = ""
            }
            // swift-markdown doesn't expose CommonMark's tight/loose distinction, so a tight item's
            // own paragraph arrives wrapped in a Paragraph node just like a loose one's. Unwrap it
            // when it's the item's only paragraph (the common tight-list case) so items don't get
            // unwanted <p> margin; a genuinely multi-paragraph (loose) item keeps <p> wrapping on
            // every paragraph so the paragraphs stay visually separated instead of running together.
            // Other block children (nested lists, code blocks, ...) always render through `visit`.
            let paragraphCount = listItem.children.filter { $0 is Paragraph }.count
            let content = listItem.children.reduce(into: "") { html, child in
                if let paragraph = child as? Paragraph, paragraphCount == 1 {
                    html += childrenHTML(of: paragraph)
                } else {
                    html += visit(child)
                }
            }
            return "<li\(sourceLineAttribute(for: listItem))>\(checkbox)\(content)</li>\n"
        }

        mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
            "<hr\(sourceLineAttribute(for: thematicBreak))>\n"
        }

        mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
            "<br>\n"
        }

        mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
            "\n"
        }

        mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
            escapeHTML(inlineHTML.rawHTML)
        }

        mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
            "<p\(sourceLineAttribute(for: html))>\(escapeHTML(html.rawHTML))</p>\n"
        }

        mutating func visitTable(_ table: Table) -> String {
            columnAlignments = table.columnAlignments
            let head = visit(table.head)
            let body = visit(table.body)
            columnAlignments = []
            return "<table>\n\(head)\(body)</table>\n"
        }

        mutating func visitTableHead(_ tableHead: Table.Head) -> String {
            let cells = tableHead.cells.enumerated().map { index, cell in
                "<th\(alignmentAttribute(index))>\(childrenHTML(of: cell))</th>"
            }.joined()
            return "<thead>\n<tr\(sourceLineAttribute(for: tableHead))>\(cells)</tr>\n</thead>\n"
        }

        mutating func visitTableBody(_ tableBody: Table.Body) -> String {
            let rows = tableBody.rows.reduce(into: "") { html, row in
                html += visit(row)
            }
            return "<tbody>\n\(rows)</tbody>\n"
        }

        mutating func visitTableRow(_ tableRow: Table.Row) -> String {
            let cells = tableRow.cells.enumerated().map { index, cell in
                "<td\(alignmentAttribute(index))>\(childrenHTML(of: cell))</td>"
            }.joined()
            return "<tr\(sourceLineAttribute(for: tableRow))>\(cells)</tr>\n"
        }

        private func alignmentAttribute(_ columnIndex: Int) -> String {
            guard columnIndex < columnAlignments.count, let alignment = columnAlignments[columnIndex] else {
                return ""
            }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }
    }
}
