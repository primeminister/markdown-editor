//
//  WorkspaceAutosaveController.swift
//  MarkdownEditor
//

import Foundation
import OSLog

private extension Logger {
    static let workspaceAutosave = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MarkdownEditor", category: "WorkspaceAutosave")
}

@MainActor
final class WorkspaceAutosaveController {
    private static let debounceInterval: TimeInterval = 0.5
    private var pendingWorkItem: DispatchWorkItem?
    private var pendingURL: URL?
    private var pendingText: String?

    func schedule(text: String, to url: URL) {
        pendingWorkItem?.cancel()
        pendingURL = url
        pendingText = text

        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem { [weak self] in
            guard let self, self.pendingWorkItem === workItem, !workItem.isCancelled else { return }
            self.write(text: text, to: url)
            self.pendingWorkItem = nil
            self.pendingURL = nil
            self.pendingText = nil
        }

        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }

    /// Synchronous -- called on file switch and on window close so no pending edit is lost.
    func flush() {
        guard let workItem = pendingWorkItem, let url = pendingURL, let text = pendingText else { return }
        workItem.cancel()
        write(text: text, to: url)
        pendingWorkItem = nil
        pendingURL = nil
        pendingText = nil
    }

    private func write(text: String, to url: URL) {
        do {
            try MarkdownDocument.encodeText(text).write(to: url, options: .atomic)
        } catch {
            Logger.workspaceAutosave.error("Failed to autosave \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }
}
