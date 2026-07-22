//
//  ContentView.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument

    var body: some View {
        HSplitView {
            EditorView(text: $document.text)
                .frame(minWidth: 300)
            PreviewView(text: $document.text)
                .frame(minWidth: 300)
        }
        .frame(minWidth: 620, minHeight: 400)
    }
}

#Preview {
    ContentView(document: .constant(MarkdownDocument()))
}
