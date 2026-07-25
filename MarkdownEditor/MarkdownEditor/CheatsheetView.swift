//
//  CheatsheetView.swift
//  MarkdownEditor
//

import SwiftUI

/// Read-only Help > Markdown Syntax window: the bundled `Cheatsheet.md` shown in the same
/// editor/preview split used for real documents, so its raw syntax and rendered output are
/// visible side by side. The editor side is non-editable since this isn't a real document --
/// there's nowhere for edits to be saved.
struct CheatsheetView: View {
    @State private var text = Self.loadCheatsheet()
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true

    var body: some View {
        SplitView(text: $text, isPreviewVisible: $isPreviewVisible, autosaveIdentifier: "cheatsheet", isEditorEditable: false)
            .frame(minWidth: 620, minHeight: 400)
    }

    private static func loadCheatsheet() -> String {
        guard let url = Bundle.main.url(forResource: "Cheatsheet", withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "# Markdown Syntax\n\nCheatsheet resource not found."
        }
        return contents
    }
}

#Preview {
    CheatsheetView()
}
