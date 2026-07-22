//
//  MarkdownEditorApp.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import SwiftUI

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
