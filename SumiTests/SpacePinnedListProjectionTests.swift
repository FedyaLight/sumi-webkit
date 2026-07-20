//
//  SpacePinnedListProjectionTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

@MainActor
final class SpacePinnedListProjectionTests: XCTestCase {
    // The pinned list is never mutated during drag (the drop indicator line
    // marks the insertion point), so the projection is a plain enumeration
    // with stable identities and model drop indices.

    func testDisplayEntriesEnumerateItemsWithModelIndices() {
        let folderIdA = UUID()
        let shortcutId = UUID()
        let groupId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: UUID(),
            items: [.folder(folderIdA), .shortcut(shortcutId), .splitGroup(groupId)]
        )

        let entries = model.displayEntries
        XCTAssertEqual(
            entries.map(\.item),
            [.folder(folderIdA), .shortcut(shortcutId), .splitGroup(groupId)]
        )
        XCTAssertEqual(entries.map(\.dropIndex), [0, 1, 2])
    }

    func testDisplayEntriesUseStableItemIdentity() {
        let shortcutId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: UUID(),
            items: [.shortcut(shortcutId)]
        )

        XCTAssertEqual(
            model.displayEntries.map(\.id),
            ["item-\(shortcutId.uuidString)"]
        )
    }

    func testDisplayEntriesEmptyForEmptySection() {
        let model = SpacePinnedListProjection(spaceId: UUID(), items: [])
        XCTAssertTrue(model.displayEntries.isEmpty)
    }
}
