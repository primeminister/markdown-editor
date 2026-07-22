//
//  WorkspaceTabBarView.swift
//  MarkdownEditor
//

import SwiftUI

/// Custom tab strip shown only above the editor/preview pane -- each chip is sized to its own
/// filename (no stretching to fill the bar), with a close button only for now.
struct WorkspaceTabBarView: View {
    let windowController: WorkspaceWindowController
    @AppStorage("isPreviewVisible") private var isPreviewVisible: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(windowController.tabs, id: \.id) { tab in
                        TabChip(
                            title: tab.selectedFileURL?.lastPathComponent ?? windowController.folderModel.folderURL.lastPathComponent,
                            isActive: tab === windowController.activeTab,
                            onSelect: { windowController.activate(tab) },
                            onClose: { windowController.closeTab(tab) }
                        )
                    }
                }
                .padding(.horizontal, 6)
            }
            Spacer(minLength: 8)
            Button {
                isPreviewVisible.toggle()
            } label: {
                Image(systemName: isPreviewVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isPreviewVisible ? "Hide Preview" : "Show Preview")
            .padding(.trailing, 8)
        }
        .frame(height: 38)
        .background(.thinMaterial)
    }
}

private struct TabChip: View {
    let title: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Tap gesture is scoped to just the label, as a sibling of the close button below --
            // not wrapping the whole chip, which would nest the close `Button`'s hit region inside
            // this gesture's and risk both firing for one click on the close button (this codebase
            // already hit exactly that failure mode once, see FileRow's tap-gesture-exclusivity fix).
            Text(title)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .fixedSize()
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1)
        )
    }
}
