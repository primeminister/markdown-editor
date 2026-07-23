//
//  AppPreferencesTests.swift
//  MarkdownEditorTests
//

import Testing
import Foundation
@testable import MarkdownEditor

struct EditorFontSizeTests {
    @Test func clampedPassesThroughInRangeValues() {
        #expect(EditorFontSize.clamped(13) == 13)
    }

    @Test func clampedFloorsBelowMin() {
        #expect(EditorFontSize.clamped(1) == EditorFontSize.min)
    }

    @Test func clampedCeilsAboveMax() {
        #expect(EditorFontSize.clamped(100) == EditorFontSize.max)
    }
}

struct RestorableWorkspaceTests {
    private static let fakeBookmark = Data([0x01, 0x02, 0x03])

    @Test func encodeDecodeRoundTrips() throws {
        let original = RestorableWorkspace(
            folderPath: "/Users/test/Documents/notes",
            folderBookmark: Self.fakeBookmark,
            tabFilePaths: ["/Users/test/Documents/notes/a.md", "/Users/test/Documents/notes/b.md"],
            activeTabFilePath: "/Users/test/Documents/notes/b.md"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RestorableWorkspace.self, from: data)

        #expect(decoded.folderPath == original.folderPath)
        #expect(decoded.folderBookmark == original.folderBookmark)
        #expect(decoded.tabFilePaths == original.tabFilePaths)
        #expect(decoded.activeTabFilePath == original.activeTabFilePath)
    }

    @Test func encodeDecodeRoundTripsNilActiveTabFilePath() throws {
        let original = RestorableWorkspace(
            folderPath: "/Users/test/Documents/notes",
            folderBookmark: Self.fakeBookmark,
            tabFilePaths: [],
            activeTabFilePath: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RestorableWorkspace.self, from: data)

        #expect(decoded.activeTabFilePath == nil)
    }

    @Test func arrayOfWorkspacesRoundTrips() throws {
        let original = [
            RestorableWorkspace(folderPath: "/a", folderBookmark: Self.fakeBookmark, tabFilePaths: ["/a/1.md"], activeTabFilePath: "/a/1.md"),
            RestorableWorkspace(folderPath: "/b", folderBookmark: Self.fakeBookmark, tabFilePaths: [], activeTabFilePath: nil),
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([RestorableWorkspace].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].folderPath == "/a")
        #expect(decoded[1].folderPath == "/b")
    }
}
