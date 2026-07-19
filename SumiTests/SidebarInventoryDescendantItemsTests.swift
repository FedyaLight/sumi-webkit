@testable import Sumi
import XCTest

@MainActor
final class SidebarInventoryDescendantItemsTests: XCTestCase {
    private let rootFolder = UUID()
    private let nestedFolder = UUID()
    private let deepFolder = UUID()
    private let pinA = UUID()
    private let pinB = UUID()
    private let nestedPin = UUID()
    private let deepPin = UUID()
    private let splitGroup = UUID()

    private func makeSnapshot(
        folderItemsByFolderID: [UUID: [SidebarPinnedInventoryItem]]
    ) -> SidebarSpaceInventorySnapshot {
        SidebarSpaceInventorySnapshot(
            spaceID: UUID(),
            regularTabs: [],
            topLevelItems: [],
            topLevelFolders: [],
            topLevelPins: [],
            childFoldersByParentID: [:],
            folderPinsByFolderID: [:],
            folderItemsByFolderID: folderItemsByFolderID,
            foldersByID: [:],
            pinsByID: [:],
            tabsByID: [:],
            splitGroupsByID: [:]
        )
    }

    func testDescendantsFollowDepthFirstPositionalOrderAndIncludeSplitGroups() {
        let snapshot = makeSnapshot(folderItemsByFolderID: [
            rootFolder: [.shortcut(pinA), .folder(nestedFolder), .splitGroup(splitGroup), .shortcut(pinB)],
            nestedFolder: [.shortcut(nestedPin), .folder(deepFolder)],
            deepFolder: [.shortcut(deepPin)],
        ])

        XCTAssertEqual(
            snapshot.descendantItems(for: rootFolder),
            [.shortcut(pinA), .shortcut(nestedPin), .shortcut(deepPin), .splitGroup(splitGroup), .shortcut(pinB)]
        )
        XCTAssertEqual(
            snapshot.orderedDescendantItemIDs(for: rootFolder),
            [pinA, nestedPin, deepPin, splitGroup, pinB]
        )
        XCTAssertEqual(
            snapshot.orderedDescendantItemIDs(for: nestedFolder),
            [nestedPin, deepPin]
        )
    }

    func testDescendantWalkSurvivesFolderCycles() {
        let snapshot = makeSnapshot(folderItemsByFolderID: [
            rootFolder: [.shortcut(pinA), .folder(nestedFolder)],
            nestedFolder: [.shortcut(nestedPin), .folder(rootFolder)],
        ])

        XCTAssertEqual(
            snapshot.orderedDescendantItemIDs(for: rootFolder),
            [pinA, nestedPin]
        )
    }
}
