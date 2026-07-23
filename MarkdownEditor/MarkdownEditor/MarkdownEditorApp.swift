//
//  MarkdownEditorApp.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import SwiftUI

@main
struct MarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("isPreviewVisible") private var isPreviewVisible = true
    @AppStorage("editorFontSize") private var editorFontSize = EditorFontSize.default

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder…") {
                    WorkspaceWindowManager.shared.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button(isPreviewVisible ? "Hide Preview" : "Show Preview") {
                    isPreviewVisible.toggle()
                }
                .keyboardShortcut("/", modifiers: .command)

                Button("Toggle Sidebar") {
                    WorkspaceWindowManager.shared.toggleSidebarForKeyWindow()
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Button("Increase Font Size") {
                    editorFontSize = EditorFontSize.clamped(editorFontSize + EditorFontSize.step)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Font Size") {
                    editorFontSize = EditorFontSize.clamped(editorFontSize - EditorFontSize.step)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    editorFontSize = EditorFontSize.default
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
