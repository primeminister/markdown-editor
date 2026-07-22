//
//  WorkspaceDetailView.swift
//  MarkdownEditor
//

import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var model: WorkspaceModel
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true

    var body: some View {
        if model.selectedFileURL != nil {
            // Stable per-workspace-window identifier (the folder, not the selected file) --
            // MainSplitViewController bakes this in at first appearance and never re-reads it,
            // so this must not vary per file. See docs/plan-m5.md.
            SplitView(text: $model.text, isPreviewVisible: $isPreviewVisible, autosaveIdentifier: model.folderURL.path)
                .onChange(of: model.text) { _, newValue in
                    guard let url = model.selectedFileURL, newValue != model.loadedText else { return }
                    model.autosave.schedule(text: newValue, to: url)
                }
        } else {
            ContentUnavailableView("Select a Markdown File", systemImage: "doc.text")
        }
    }
}
