//
//  ContentView.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true
    // Falls back to a per-window identifier for untitled documents (no fileURL yet) so multiple
    // simultaneously open untitled windows don't share/clobber each other's saved layout.
    @State private var untitledIdentifier = UUID().uuidString

    private var autosaveIdentifier: String {
        fileURL?.path ?? untitledIdentifier
    }

    var body: some View {
        SplitView(text: $document.text, isPreviewVisible: $isPreviewVisible, autosaveIdentifier: autosaveIdentifier)
            .frame(minWidth: 620, minHeight: 400)
            .toolbar {
                ToolbarItem {
                    Button {
                        isPreviewVisible.toggle()
                    } label: {
                        Image(systemName: isPreviewVisible ? "eye.slash" : "eye")
                    }
                    .help(isPreviewVisible ? "Hide Preview" : "Show Preview")
                }
            }
    }
}

#Preview {
    ContentView(document: .constant(MarkdownDocument()), fileURL: nil)
}
