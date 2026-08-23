//
//  FormattingToolbar.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 23/08/2026.
//

import SwiftUI

/// Thin bar above the editor pane only. Parameterless -- no text/cursor bindings needed, since all
/// mutation happens through the responder chain via `MarkdownFormattingDispatch`, the same path
/// the app-menu keyboard shortcuts use.
struct FormattingToolbar: View {
    private static let headingActions: [MarkdownFormattingAction] = [.heading1, .heading2, .heading3]
    private static let inlineActions: [MarkdownFormattingAction] = [.bold, .italic, .strikethrough, .inlineCode]
    private static let blockActions: [MarkdownFormattingAction] = [.fencedCode, .blockquote, .link]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.headingActions, id: \.self) { button(for: $0) }
            Divider()
            ForEach(Self.inlineActions, id: \.self) { button(for: $0) }
            Divider()
            ForEach(Self.blockActions, id: \.self) { button(for: $0) }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func button(for action: MarkdownFormattingAction) -> some View {
        Button {
            MarkdownFormattingDispatch.perform(action)
        } label: {
            Image(systemName: action.systemImage)
        }
        .buttonStyle(.borderless)
        .help(action.title)
    }
}

#Preview {
    FormattingToolbar()
        .frame(width: 500)
}
