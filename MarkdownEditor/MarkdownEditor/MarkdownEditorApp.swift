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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        // Suppresses DocumentGroup's own launch-time Open panel, which can't be configured to
        // allow folders. `AppDelegate.applicationDidFinishLaunching` drives launch presentation
        // instead, with a combined file-or-folder picker.
        .defaultLaunchBehavior(.suppressed)
        .commands {
            // Replaces DocumentGroup's built-in New/Open (SwiftUI only lets you swap out this
            // whole group, not individual items within it -- see AppDelegate.swift) so "Open…" can
            // offer files and folders together instead of files only, with "Open Folder…" folded
            // in rather than kept as a separate command. Deliberately doesn't also rebuild "Open
            // Recent": AppKit still shows its own native one for document-based apps regardless of
            // what's supplied here (a `CommandGroup(replacing: .newItem)` quirk), so a hand-built
            // one here just duplicates it rather than replacing it -- see AppDelegate.swift.
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    NSDocumentController.shared.newDocument(nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open…") {
                    appDelegate.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
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
            CommandGroup(after: .help) {
                Button("Markdown Syntax") {
                    openWindow(id: "cheatsheet")
                }
            }
        }

        // `.defaultLaunchBehavior(.suppressed)` keeps this from auto-opening on every launch --
        // SwiftUI otherwise presents every Scene in `body` at launch by default, alongside the
        // primary DocumentGroup.
        Window("Markdown Syntax", id: "cheatsheet") {
            CheatsheetView()
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 720, height: 560)
    }
}
