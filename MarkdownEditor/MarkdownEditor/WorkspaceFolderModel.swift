//
//  WorkspaceFolderModel.swift
//  MarkdownEditor
//

import Foundation
import Observation

/// Folder-wide state shared by every tab in a workspace window -- the file tree is loaded once
/// per window, not once per tab, since it's the same tree regardless of which file any given tab
/// is showing.
@MainActor
@Observable
final class WorkspaceFolderModel {
    let folderURL: URL
    var root: FileNode?

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    func loadTree() async {
        let url = folderURL
        // Recursive directory walk can be slow for large folders -- build it off the main thread
        // so opening a big folder doesn't hang the UI before the window even shows.
        root = await Task.detached(priority: .userInitiated) {
            FileNode.build(from: url)
        }.value
    }
}
