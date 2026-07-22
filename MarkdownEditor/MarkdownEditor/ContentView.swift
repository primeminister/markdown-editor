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
        EditorView(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(MarkdownDocument()))
}
