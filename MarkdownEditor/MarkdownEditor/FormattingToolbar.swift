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
        HStack(spacing: 2) {
            ForEach(Self.headingActions, id: \.self) { button(for: $0) }
            Divider().frame(height: 20)
            ForEach(Self.inlineActions, id: \.self) { button(for: $0) }
            Divider().frame(height: 20)
            ForEach(Self.blockActions, id: \.self) { button(for: $0) }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func button(for action: MarkdownFormattingAction) -> some View {
        Button {
            MarkdownFormattingDispatch.perform(action)
        } label: {
            label(for: action)
                .frame(width: 30, height: 24)
        }
        .buttonStyle(.borderless)
        .help(action.title)
        // `.help` only supplies the accessibility *hint*; an icon-only button still needs an
        // explicit label so VoiceOver announces what it does, not just its SF Symbol name.
        .accessibilityLabel(action.title)
    }

    // The number-square SF Symbols (1.square/2.square/3.square) read ambiguously at toolbar size --
    // a plain "H1"/"H2"/"H3" text label is unambiguous where an icon has to be understood, not just seen.
    @ViewBuilder
    private func label(for action: MarkdownFormattingAction) -> some View {
        switch action {
        case .heading1: Text("H1").font(.system(size: 18, weight: .semibold))
        case .heading2: Text("H2").font(.system(size: 18, weight: .semibold))
        case .heading3: Text("H3").font(.system(size: 18, weight: .semibold))
        default: Image(systemName: action.systemImage).font(.system(size: 18, weight: .medium))
        }
    }
}

#Preview {
    FormattingToolbar()
        .frame(width: 500)
}
